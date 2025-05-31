#include "CocoaScheduler.h"
#include <memory>

OSStatus triggerMidiEvents(
    void* _Nonnull inRefCon,
    AudioUnitRenderActionFlags* _Nonnull ioActionFlags,
    const AudioTimeStamp* _Nonnull inTimeStamp,
    UInt32 inBusNumber,
    UInt32 inNumberFrames,
    AudioBufferList* _Nullable ioData
) {
    if (*ioActionFlags != kAudioUnitRenderAction_PreRender) return noErr;
    
    auto pair = (std::pair<track_index_t, CocoaScheduler*>*)inRefCon;
    auto trackIndex = pair->first;
    auto scheduler = pair->second;
    auto scaledFrameCount = scheduler->scaleFrames(trackIndex, inNumberFrames, true);

    scheduler->handleFrames(trackIndex, scaledFrameCount);
    
    return noErr;
}

CocoaScheduler::CocoaScheduler(AudioUnit _Nonnull mixerAudioUnit, double sampleRate) {
    mMixerAudioUnit = mixerAudioUnit;
    mSampleRate = sampleRate;
}

CocoaScheduler::~CocoaScheduler() {
    for (auto pair : mInRefConMap) {
        auto audioUnit = mAudioUnitMap[pair.first];
        
        AudioUnitRemoveRenderNotify(audioUnit, triggerMidiEvents, &pair);
    }
}

void CocoaScheduler::setTrackAudioUnit(track_index_t trackIndex, AudioUnit _Nonnull audioUnit) {
    mSampleRateMap[trackIndex] = getSampleRate(audioUnit);
    mInRefConMap[trackIndex] = this;
    mAudioUnitMap[trackIndex] = audioUnit;
    auto inRefCon = mInRefConMap.find(trackIndex);
    AudioUnitAddRenderNotify(audioUnit, triggerMidiEvents, &*inRefCon);
}

void CocoaScheduler::onRemoveTrack(track_index_t trackIndex) {
    auto inRefCon = mInRefConMap.find(trackIndex);
    AudioUnitRemoveRenderNotify(mAudioUnitMap[trackIndex], triggerMidiEvents, &*inRefCon);
    mInRefConMap.erase(trackIndex);
    mAudioUnitMap.erase(trackIndex);
}

void CocoaScheduler::onResetTrack(track_index_t trackIndex) {
    AudioUnitReset(mAudioUnitMap[trackIndex], kAudioUnitScope_Global, 0);
}

void CocoaScheduler::handleRenderAudioRange(track_index_t trackIndex, uint32_t offsetFrame, uint32_t numFramesToRender) {
    // Don't need to manually render frames, AVAudioEngine takes care of that
};

void CocoaScheduler::handleEvent(track_index_t trackIndex, SchedulerEvent event, UInt32 offsetFrame) {
    AudioUnit trackAU = mAudioUnitMap[trackIndex];
    auto scaledOffsetFrame = scaleFrames(trackIndex, offsetFrame, false);
    
    if (trackAU == nullptr) return;

    if (event.type == VOLUME_EVENT) {
        auto volumeEvent = VolumeEventData(event.data);
        
        AudioUnitSetParameter(mMixerAudioUnit,
                            kMultiChannelMixerParam_Volume,
                            kAudioUnitScope_Input,
                            trackIndex, // bus ID
                            volumeEvent.volume,
                            scaledOffsetFrame);
    } else if (event.type == MIDI_EVENT) {
        auto midiEvent = MidiEventData(event.data);
        MusicDeviceMIDIEvent(trackAU, midiEvent.midiStatus, midiEvent.midiData1, midiEvent.midiData2, scaledOffsetFrame);
    }
}

float CocoaScheduler::getTrackVolume(track_index_t trackIndex) {
    float volume;
    auto osStatus = AudioUnitGetParameter(mMixerAudioUnit,
                                        kMultiChannelMixerParam_Volume,
                                        kAudioUnitScope_Input,
                                        trackIndex, // bus ID
                                        &volume);
    
    if (osStatus == noErr) {
        return volume;
    } else {
        return 0.0;
    }
}

int CocoaScheduler::scaleFrames(track_index_t trackIndex, UInt32 inNumberFrames, bool isToDeviceFrames) {
    auto trackSampleRate = mSampleRateMap[trackIndex];
    int scaledFrames;
    
    if (isToDeviceFrames) {
        // Scale from track's sample rate to device sample rate
        scaledFrames = (inNumberFrames * mSampleRate) / trackSampleRate;
    } else {
        // Scale from device sample rate to track's sample rate
        scaledFrames = (inNumberFrames * trackSampleRate) / mSampleRate;
    }
    
    return scaledFrames;
}

double CocoaScheduler::getSampleRate(AudioUnit _Nonnull audioUnit) {
    AudioStreamBasicDescription asbd;
    UInt32 dataSize = sizeof(AudioStreamBasicDescription);
    OSStatus status;
    
    status = AudioUnitGetProperty(audioUnit,
                                 kAudioUnitProperty_StreamFormat,
                                 kAudioUnitScope_Output,
                                 0,
                                 &asbd,
                                 &dataSize);
    
    if (status != noErr) {
        return 44100.0; // Default sample rate if we can't get it
    }
    
    return asbd.mSampleRate;
}

// C Bridge
void* InitScheduler(AudioUnit mixerAudioUnit, double sampleRate) {
    return new CocoaScheduler(mixerAudioUnit, sampleRate);
}

void DestroyScheduler(void* scheduler) {
    delete (CocoaScheduler*)scheduler;
}

track_index_t SchedulerAddTrack(const void* scheduler) {
    return ((CocoaScheduler*)scheduler)->addTrack();
}

void SchedulerSetTrackAudioUnit(const void* scheduler, track_index_t trackIndex, AudioUnit audioUnit) {
    ((CocoaScheduler*)scheduler)->setTrackAudioUnit(trackIndex, audioUnit);
}

void SchedulerRemoveTrack(const void* scheduler, track_index_t trackIndex) {
    ((CocoaScheduler*)scheduler)->removeTrack(trackIndex);
}

UInt32 SchedulerGetBufferAvailableCount(const void* scheduler, track_index_t trackIndex) {
    return ((CocoaScheduler*)scheduler)->getBufferAvailableCount(trackIndex);
}

void SchedulerHandleEventsNow(const void* scheduler, track_index_t trackIndex, const SchedulerEvent* events, UInt32 eventsCount) {
    ((CocoaScheduler*)scheduler)->handleEventsNow(trackIndex, events, eventsCount);
}

UInt32 SchedulerAddEvents(const void* scheduler, track_index_t trackIndex, const SchedulerEvent* events, UInt32 toAddCount) {
    return ((CocoaScheduler*)scheduler)->addEvents(trackIndex, events, toAddCount);
}

void SchedulerClearEvents(const void* scheduler, track_index_t trackIndex, position_frame_t fromFrame) {
    ((CocoaScheduler*)scheduler)->clearEvents(trackIndex, fromFrame);
}

void SchedulerPlay(const void* scheduler) {
    ((CocoaScheduler*)scheduler)->play();
}

void SchedulerPause(const void* scheduler) {
    ((CocoaScheduler*)scheduler)->pause();
}

void SchedulerResetTrack(const void* scheduler, track_index_t trackIndex) {
    ((CocoaScheduler*)scheduler)->resetTrack(trackIndex);
}

UInt32 SchedulerGetPosition(const void* scheduler) {
    return ((CocoaScheduler*)scheduler)->getPosition();
}

UInt64 SchedulerGetLastRenderTimeUs(const void* scheduler) {
    return ((CocoaScheduler*)scheduler)->getLastRenderTimeUs();
}

Float32 SchedulerGetTrackVolume(const void* scheduler, track_index_t trackIndex) {
    return ((CocoaScheduler*)scheduler)->getTrackVolume(trackIndex);
}
