#include "CocoaScheduler.h"
#include <memory>
#include <vector>

// Global render callback — installed ONCE on the mixer AudioUnit.
// Fires every audio buffer cycle and processes events for ALL tracks.
static OSStatus globalRenderCallback(
    void* _Nonnull inRefCon,
    AudioUnitRenderActionFlags* _Nonnull ioActionFlags,
    const AudioTimeStamp* _Nonnull inTimeStamp,
    UInt32 inBusNumber,
    UInt32 inNumberFrames,
    AudioBufferList* _Nullable ioData
) {
    if (!(*ioActionFlags & kAudioUnitRenderAction_PreRender)) return noErr;

    auto scheduler = (CocoaScheduler*)inRefCon;
    scheduler->handleAllTracks(inNumberFrames);

    return noErr;
}

CocoaScheduler::CocoaScheduler(AudioUnit _Nonnull mixerAudioUnit, double sampleRate) {
    mMixerAudioUnit = mixerAudioUnit;
    mSampleRate = sampleRate;
}

CocoaScheduler::~CocoaScheduler() {
    if (mGlobalCallbackActive) {
        AudioUnitRemoveRenderNotify(mMixerAudioUnit, globalRenderCallback, this);
    }
}

void CocoaScheduler::startGlobalCallback() {
    if (mGlobalCallbackActive) return;
    AudioUnitAddRenderNotify(mMixerAudioUnit, globalRenderCallback, this);
    mGlobalCallbackActive = true;
}

void CocoaScheduler::handleAllTracks(uint32_t numFrames) {
    // Collect track indices under lock, then process without lock
    std::vector<track_index_t> tracks;
    {
        std::lock_guard<std::mutex> lock(mBufferMutex);
        tracks.reserve(mBufferMap.size());
        for (auto& pair : mBufferMap) {
            if (pair.second != nullptr) {
                tracks.push_back(pair.first);
            }
        }
    }

    for (auto trackIndex : tracks) {
        auto it = mSampleRateMap.find(trackIndex);
        uint32_t scaledFrames = numFrames;
        if (it != mSampleRateMap.end() && it->second != mSampleRate) {
            scaledFrames = numFrames * (mSampleRate / it->second);
        }
        handleFrames(trackIndex, scaledFrames);
    }
}

void CocoaScheduler::setTrackAudioUnit(track_index_t trackIndex, AudioUnit _Nonnull audioUnit) {
    mSampleRateMap[trackIndex] = getSampleRate(audioUnit);
    mAudioUnitMap[trackIndex] = audioUnit;

    // Create event buffer for this track (required for scheduleEvents to work)
    {
        std::lock_guard<std::mutex> lock(mBufferMutex);
        if (mBufferMap[trackIndex] == nullptr) {
            mBufferMap[trackIndex] = std::make_shared<Buffer<>>();
        }
    }
}

void CocoaScheduler::onRemoveTrack(track_index_t trackIndex) {
    mAudioUnitMap.erase(trackIndex);
    mSampleRateMap.erase(trackIndex);
    mTrackVolumeMap.erase(trackIndex);
}

void CocoaScheduler::onResetTrack(track_index_t trackIndex) {
    AudioUnitReset(mAudioUnitMap[trackIndex], kAudioUnitScope_Global, 0);
}

void CocoaScheduler::handleRenderAudioRange(track_index_t trackIndex, uint32_t offsetFrame, uint32_t numFramesToRender) {
    // Don't need to manually render frames, AVAudioEngine takes care of that
};

void CocoaScheduler::handleEvent(track_index_t trackIndex, SchedulerEvent event, UInt32 offsetFrame) {
    // PERFORMANCE: Early exit for invalid tracks
    AudioUnit trackAU = mAudioUnitMap[trackIndex];
    if (trackAU == nullptr) return;
    
    // OPTIMIZED: Pre-calculate scaled frame once
    auto scaledOffsetFrame = scaleFrames(trackIndex, offsetFrame, false);

    if (event.type == VOLUME_EVENT) {
        auto volumeEvent = VolumeEventData(event.data);

        // Volume via MIDI CC7 (channel volume) on the track's sampler AudioUnit.
        // Cannot use kMultiChannelMixerParam_Volume because mMixerAudioUnit is
        // the output node (RemoteIO), not a MultiChannelMixer.
        UInt32 volumeCC = (UInt32)(volumeEvent.volume * 127.0f);
        if (volumeCC > 127) volumeCC = 127;
        MusicDeviceMIDIEvent(trackAU, 0xB0, 7, volumeCC, scaledOffsetFrame);

        // Store volume for getTrackVolume() queries
        mTrackVolumeMap[trackIndex] = volumeEvent.volume;
    } else if (event.type == MIDI_EVENT) {
        auto midiEvent = MidiEventData(event.data);

        // CRITICAL: Sample-accurate MIDI event timing
        OSStatus result = MusicDeviceMIDIEvent(trackAU, 
                                              midiEvent.midiStatus, 
                                              midiEvent.midiData1, 
                                              midiEvent.midiData2, 
                                              scaledOffsetFrame);
        
        // PERFORMANCE: Only log errors, not every event
        if (result != noErr && midiEvent.midiStatus == 0x90) {
            printf("MIDI event failed: track=%d, status=0x%02X, error=%d\n", 
                   trackIndex, midiEvent.midiStatus, (int)result);
        }
    }
}

float CocoaScheduler::getTrackVolume(track_index_t trackIndex) {
    auto it = mTrackVolumeMap.find(trackIndex);
    if (it != mTrackVolumeMap.end()) {
        return it->second;
    }
    return 1.0f; // default full volume
}

int CocoaScheduler::scaleFrames(track_index_t trackIndex, UInt32 inNumberFrames, bool isToDeviceFrames) {
    auto trackSampleRate = mSampleRateMap[trackIndex];
    int scaledFrames;

    if (trackSampleRate == mSampleRate) {
        scaledFrames = inNumberFrames;
    } else {
        if (isToDeviceFrames) {
            scaledFrames = inNumberFrames * (mSampleRate / trackSampleRate);
        } else {
            scaledFrames = inNumberFrames * (trackSampleRate / mSampleRate);
        }
    }
    
    return scaledFrames;
}

double CocoaScheduler::getSampleRate(AudioUnit  _Nonnull audioUnit) {
    double sampleRate;
    auto size = (UInt32)sizeof(sampleRate);

    AudioUnitGetProperty(audioUnit,
                         kAudioUnitProperty_SampleRate,
                         kAudioUnitScope_Output,
                         0,
                         &sampleRate,
                         &size);

    return sampleRate;
}

// C Bridge
void* InitScheduler(AudioUnit mixerAudioUnit, double sampleRate) {
    CocoaScheduler* scheduler = new CocoaScheduler(mixerAudioUnit, sampleRate);
    return (void*)scheduler;
}

void DestroyScheduler(void* scheduler) {
    delete ((CocoaScheduler*)scheduler);
}

track_index_t SchedulerAddTrack(void* scheduler) {
    return ((CocoaScheduler*)scheduler)->addTrack();
}

void SchedulerSetTrackAudioUnit(void* scheduler, track_index_t trackIndex, AudioUnit audioUnit) {
    ((CocoaScheduler*)scheduler)->setTrackAudioUnit(trackIndex, audioUnit);
}

void SchedulerRemoveTrack(void* scheduler, track_index_t trackIndex) {
    ((CocoaScheduler*)scheduler)->removeTrack(trackIndex);
}

UInt32 SchedulerGetBufferAvailableCount(void* scheduler, track_index_t trackIndex) {
    return ((CocoaScheduler*)scheduler)->getBufferAvailableCount(trackIndex);
}

void SchedulerHandleEventsNow(void* scheduler, track_index_t trackIndex, const SchedulerEvent* events, UInt32 toAddCount) {
    ((CocoaScheduler*)scheduler)->handleEventsNow(trackIndex, &events[0], toAddCount);
}

UInt32 SchedulerAddEvents(void* scheduler, track_index_t trackIndex, const SchedulerEvent* events, UInt32 toAddCount) {
    return ((CocoaScheduler*)scheduler)->scheduleEvents(trackIndex, &events[0], toAddCount);
}

void SchedulerClearEvents(void* scheduler, track_index_t trackIndex, position_frame_t fromFrame) {
    ((CocoaScheduler*)scheduler)->clearEvents(trackIndex, fromFrame);
}

void SchedulerPlay(void* scheduler) {
    ((CocoaScheduler*)scheduler)->play();
}

void SchedulerPause(void* scheduler) {
    ((CocoaScheduler*)scheduler)->pause();
}

void SchedulerResetTrack(void* scheduler, track_index_t trackIndex) {
    ((CocoaScheduler*)scheduler)->resetTrack(trackIndex);
}

UInt32 SchedulerGetPosition(void* scheduler) {
    return ((CocoaScheduler*)scheduler)->getPosition();
}

UInt64 SchedulerGetLastRenderTimeUs(void* scheduler) {
    return ((CocoaScheduler*)scheduler)->getLastRenderTimeUs();
}

Float32 SchedulerGetTrackVolume(void* scheduler, track_index_t trackIndex) {
    return ((CocoaScheduler*)scheduler)->getTrackVolume(trackIndex);
}

void SchedulerStartGlobalCallback(void* scheduler) {
    ((CocoaScheduler*)scheduler)->startGlobalCallback();
}
