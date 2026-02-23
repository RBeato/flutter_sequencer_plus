#include "CocoaScheduler.h"
#include <memory>

/// Audio thread render callback. Fires for each track's AudioUnit pre-render.
/// Must be real-time safe: no locks, no allocations, no I/O, no map lookups.
static OSStatus triggerMidiEvents(
    void* _Nonnull inRefCon,
    AudioUnitRenderActionFlags* _Nonnull ioActionFlags,
    const AudioTimeStamp* _Nonnull inTimeStamp,
    UInt32 inBusNumber,
    UInt32 inNumberFrames,
    AudioBufferList* _Nullable ioData
) {
    if (*ioActionFlags & kAudioUnitRenderAction_PreRender) {
        auto refCon = static_cast<RenderRefCon*>(inRefCon);
        auto scheduler = static_cast<CocoaScheduler*>(refCon->scheduler);
        scheduler->handleFrames(refCon->trackIndex, inNumberFrames);
    }
    return noErr;
}

CocoaScheduler::CocoaScheduler(AudioUnit _Nonnull mixerAudioUnit, double sampleRate) {
    mMixerAudioUnit = mixerAudioUnit;
    mSampleRate = sampleRate;

    // Zero-initialize all arrays for safety
    for (int i = 0; i < MAX_TRACKS; i++) {
        mTrackAudioUnits[i] = nullptr;
        mTrackSampleRates[i] = 0;
        mTrackRefCons[i] = nullptr;
    }

    SEQ_LOG("CocoaScheduler created: sampleRate=%.0f, mixerAU=%p", sampleRate, mixerAudioUnit);
}

CocoaScheduler::~CocoaScheduler() {
    for (int i = 0; i < MAX_TRACKS; i++) {
        if (mTrackAudioUnits[i] != nullptr && mTrackRefCons[i] != nullptr) {
            AudioUnitRemoveRenderNotify(mTrackAudioUnits[i], triggerMidiEvents, mTrackRefCons[i]);
        }
        // Safe to delete in destructor - engine is fully stopped
        delete mTrackRefCons[i];
        mTrackRefCons[i] = nullptr;
        mTrackAudioUnits[i] = nullptr;
    }
}

void CocoaScheduler::setTrackAudioUnit(track_index_t trackIndex, AudioUnit _Nonnull audioUnit) {
    if (trackIndex < 0 || trackIndex >= MAX_TRACKS) {
        return;
    }

    auto trackSR = getSampleRate(audioUnit);
    mTrackSampleRates[trackIndex] = trackSR;
    mTrackAudioUnits[trackIndex] = audioUnit;

    // Step 2: Register render callback (callback is no-op for diagnostic).
    auto refCon = new RenderRefCon{trackIndex, this};
    mTrackRefCons[trackIndex] = refCon;
    AudioUnitAddRenderNotify(audioUnit, triggerMidiEvents, refCon);

    // Step 3: Create buffer.
    {
        std::lock_guard<std::mutex> lock(mBufferMutex);
        if (mAudioBuffers[trackIndex] == nullptr) {
            auto buffer = std::make_shared<Buffer<>>();
            mBufferMap[trackIndex] = buffer;
            mAudioBuffers[trackIndex] = buffer.get();
        }
    }
}

void CocoaScheduler::onRemoveTrack(track_index_t trackIndex) {
    if (trackIndex < 0 || trackIndex >= MAX_TRACKS) return;

    auto audioUnit = mTrackAudioUnits[trackIndex];
    auto refCon = mTrackRefCons[trackIndex];

    // Remove render callback first (reduces chance of callback firing during cleanup)
    if (audioUnit != nullptr && refCon != nullptr) {
        AudioUnitRemoveRenderNotify(audioUnit, triggerMidiEvents, refCon);
    }

    // Null out audio unit (audio thread checks this before use)
    mTrackAudioUnits[trackIndex] = nullptr;
    mTrackSampleRates[trackIndex] = 0;

    // Intentionally do NOT delete refCon here.
    // AudioUnitRemoveRenderNotify does NOT guarantee the callback has finished.
    // The audio thread may still be using this refCon pointer.
    // RefCons are small (16 bytes) and will be freed in the destructor.
    // mTrackRefCons[trackIndex] remains set for destructor cleanup.
}

void CocoaScheduler::onResetTrack(track_index_t trackIndex) {
    if (trackIndex < 0 || trackIndex >= MAX_TRACKS) return;

    auto audioUnit = mTrackAudioUnits[trackIndex];
    if (audioUnit != nullptr) {
        AudioUnitReset(audioUnit, kAudioUnitScope_Global, 0);
    }
}

void CocoaScheduler::handleRenderAudioRange(track_index_t trackIndex, uint32_t offsetFrame, uint32_t numFramesToRender) {
    // AVAudioEngine handles audio rendering; we only handle event dispatch.
};

/// Called on AUDIO THREAD by BaseScheduler::handleFrames.
/// Uses only fixed-size array access - no maps, no allocations, no locks.
void CocoaScheduler::handleEvent(track_index_t trackIndex, SchedulerEvent event, UInt32 offsetFrame) {
    if (trackIndex < 0 || trackIndex >= MAX_TRACKS) return;

    AudioUnit trackAU = mTrackAudioUnits[trackIndex];
    if (trackAU == nullptr) return;

    auto scaledOffsetFrame = scaleFrames(trackIndex, offsetFrame, false);

    if (event.type == VOLUME_EVENT) {
        auto volumeEvent = VolumeEventData(event.data);
        AudioUnitSetParameter(mMixerAudioUnit,
                              kMultiChannelMixerParam_Volume,
                              kAudioUnitScope_Input,
                              trackIndex,
                              volumeEvent.volume,
                              scaledOffsetFrame);
    } else if (event.type == MIDI_EVENT) {
        auto midiEvent = MidiEventData(event.data);
        MusicDeviceMIDIEvent(trackAU,
                             midiEvent.midiStatus,
                             midiEvent.midiData1,
                             midiEvent.midiData2,
                             scaledOffsetFrame);
#if SEQ_AUDIO_DEBUG
        if ((midiEvent.midiStatus & 0xF0) == 0x90 && midiEvent.midiData2 > 0) {
            SEQ_AUDIO_LOG("MIDI NoteOn: track=%d, note=%d, vel=%d, frame=%u, offset=%u",
                    trackIndex, midiEvent.midiData1, midiEvent.midiData2,
                    event.frame, scaledOffsetFrame);
        }
#endif
    }
}

float CocoaScheduler::getTrackVolume(track_index_t trackIndex) {
    if (trackIndex < 0 || trackIndex >= MAX_TRACKS) return 1.0;

    float volume;
    auto osStatus = AudioUnitGetParameter(mMixerAudioUnit,
                                          kMultiChannelMixerParam_Volume,
                                          kAudioUnitScope_Input,
                                          trackIndex,
                                          &volume);

    return (osStatus == noErr) ? volume : 1.0;
}

/// Called on AUDIO THREAD. Uses only fixed-size array access - no maps.
int CocoaScheduler::scaleFrames(track_index_t trackIndex, UInt32 inNumberFrames, bool isToDeviceFrames) {
    if (trackIndex < 0 || trackIndex >= MAX_TRACKS) return inNumberFrames;

    auto trackSampleRate = mTrackSampleRates[trackIndex];
    if (trackSampleRate == 0 || trackSampleRate == mSampleRate) {
        return inNumberFrames;
    }

    if (isToDeviceFrames) {
        return inNumberFrames * (mSampleRate / trackSampleRate);
    } else {
        return inNumberFrames * (trackSampleRate / mSampleRate);
    }
}

double CocoaScheduler::getSampleRate(AudioUnit _Nonnull audioUnit) {
    double sampleRate = 0;
    auto size = (UInt32)sizeof(sampleRate);

    AudioUnitGetProperty(audioUnit,
                         kAudioUnitProperty_SampleRate,
                         kAudioUnitScope_Output,
                         0,
                         &sampleRate,
                         &size);

    return sampleRate > 0 ? sampleRate : mSampleRate;
}

// C Bridge functions
void* InitScheduler(AudioUnit mixerAudioUnit, double sampleRate) {
    SEQ_LOG("InitScheduler: mixerAU=%p, sampleRate=%.0f", mixerAudioUnit, sampleRate);
    return (void*)new CocoaScheduler(mixerAudioUnit, sampleRate);
}

void DestroyScheduler(void* scheduler) {
    delete ((CocoaScheduler*)scheduler);
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

void SchedulerHandleEventsNow(const void* scheduler, track_index_t trackIndex, const SchedulerEvent* events, UInt32 toAddCount) {
    ((CocoaScheduler*)scheduler)->handleEventsNow(trackIndex, &events[0], toAddCount);
}

UInt32 SchedulerAddEvents(const void* scheduler, track_index_t trackIndex, const SchedulerEvent* events, UInt32 toAddCount) {
    return ((CocoaScheduler*)scheduler)->scheduleEvents(trackIndex, &events[0], toAddCount);
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
