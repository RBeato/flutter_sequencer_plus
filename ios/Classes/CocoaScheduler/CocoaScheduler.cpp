#include "CocoaScheduler.h"
#include <memory>
#include <vector>
#include <mach/mach.h>
#include <mach/mach_time.h>
#include <mach/thread_policy.h>
#include <pthread.h>

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

    // PERFORMANCE: Set real-time thread priority (once)
    static bool rtPrioritySet = false;
    if (!rtPrioritySet) {
        // Set time-constraint policy for real-time audio thread
        thread_time_constraint_policy_data_t policy;
        policy.period = 2902; // ~5ms at bus freq (match audio buffer period)
        policy.computation = 1451; // Allow ~2.5ms of computation
        policy.constraint = 2902; // Must finish within period
        policy.preemptible = TRUE;

        mach_port_t thread = pthread_mach_thread_np(pthread_self());
        kern_return_t result = thread_policy_set(
            thread,
            THREAD_TIME_CONSTRAINT_POLICY,
            (thread_policy_t)&policy,
            THREAD_TIME_CONSTRAINT_POLICY_COUNT
        );

        if (result == KERN_SUCCESS) {
            printf("iOS audio thread promoted to real-time priority\n");
        }
        rtPrioritySet = true;
    }

    auto scheduler = (CocoaScheduler*)inRefCon;

#ifdef DEBUG
    // DIAGNOSTIC: Measure render callback performance (debug builds only)
    // printf can block on I/O and cause glitches in release builds
    static uint64_t callbackCount = 0;
    static uint64_t totalRenderTime = 0;
    static uint64_t maxRenderTime = 0;

    uint64_t startTime = mach_absolute_time();
#endif

    scheduler->handleAllTracks(inNumberFrames);

#ifdef DEBUG
    uint64_t endTime = mach_absolute_time();
    uint64_t renderTime = endTime - startTime;

    callbackCount++;
    totalRenderTime += renderTime;
    if (renderTime > maxRenderTime) {
        maxRenderTime = renderTime;
    }

    if (callbackCount % 200 == 0) {
        mach_timebase_info_data_t timebase;
        mach_timebase_info(&timebase);

        uint64_t avgRenderUs = ((totalRenderTime / callbackCount) * timebase.numer) / (timebase.denom * 1000);
        uint64_t maxRenderUs = (maxRenderTime * timebase.numer) / (timebase.denom * 1000);
        uint64_t bufferTimeUs = (inNumberFrames * 1000000) / (uint64_t)scheduler->getEngineSampleRate();

        float cpuUsage = (avgRenderUs * 100.0f) / bufferTimeUs;
        float maxCpuUsage = (maxRenderUs * 100.0f) / bufferTimeUs;

        printf("[AUDIO-PERF] Avg:%lluµs(%.0f%%) Max:%lluµs(%.0f%%) Buf:%lluµs F:%u%s%s\n",
               avgRenderUs, cpuUsage, maxRenderUs, maxCpuUsage, bufferTimeUs, inNumberFrames,
               (cpuUsage > 80.0f) ? " HIGH!" : "",
               (maxCpuUsage > 100.0f) ? " UNDERRUN!" : "");

        totalRenderTime = 0;
        maxRenderTime = 0;
        callbackCount = 0;
    }
#endif

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
    // PERFORMANCE: Lock-free audio callback - read track count atomically
    // Main thread updates mTrackCacheCount after rebuilding mTrackCache
    size_t trackCount = mTrackCacheCount.load(std::memory_order_acquire);
    if (trackCount == 0) return;

    // CRITICAL FIX: Don't advance position when not playing.
    // The render callback fires every buffer cycle regardless of play state.
    // Without this guard, mPositionFrames drifts thousands of frames per second
    // while idle, causing scheduled events to be skipped when Play is pressed.
    if (!isPlaying()) return;

    // CRITICAL FIX: All tracks must process the SAME frame range.
    // handleFrames() advances mPositionFrames, so without resetting,
    // each track would process a different range — causing N*tempo speedup.
    auto startPosition = mPositionFrames.load(std::memory_order_acquire);

    for (size_t i = 0; i < trackCount; i++) {
        track_index_t trackIndex = mTrackCache[i];

        // Reset position so this track processes the same range as all others
        mPositionFrames.store(startPosition, std::memory_order_relaxed);

        handleFrames(trackIndex, numFrames);
    }

    // Advance position exactly ONCE for the entire buffer cycle
    mPositionFrames.store(startPosition + numFrames, std::memory_order_release);
}

void CocoaScheduler::setTrackAudioUnit(track_index_t trackIndex, AudioUnit _Nonnull audioUnit) {
    // Use engine sample rate for all tracks, not AudioUnit's internal rate.
    // AUs may report 44.1kHz internally even when connected at 48kHz,
    // which would cause scaleFrames() to distort event timing by ~9%.
    mSampleRateMap[trackIndex] = mSampleRate;
    mAudioUnitMap[trackIndex] = audioUnit;

    // Create event buffer for this track (required for scheduleEvents to work)
    {
        std::lock_guard<std::mutex> lock(mBufferMutex);
        if (mBufferMap[trackIndex] == nullptr) {
            mBufferMap[trackIndex] = std::make_shared<Buffer<>>();
        }
    }

    // PERFORMANCE: Rebuild track cache snapshot for lock-free audio callback access
    rebuildTrackCache();
}

void CocoaScheduler::rebuildTrackCache() {
    // Called from main thread when tracks are added/removed
    std::lock_guard<std::mutex> lock(mBufferMutex);

    size_t count = 0;
    for (auto& pair : mBufferMap) {
        if (pair.second != nullptr && count < MAX_TRACKS) {
            mTrackCache[count++] = pair.first;
        }
    }

    // Atomic store with release semantics ensures audio thread sees updated cache
    mTrackCacheCount.store(count, std::memory_order_release);
}

void CocoaScheduler::onRemoveTrack(track_index_t trackIndex) {
    mAudioUnitMap.erase(trackIndex);
    mSampleRateMap.erase(trackIndex);
    mTrackVolumeMap.erase(trackIndex);

    // PERFORMANCE: Rebuild track cache snapshot after removing track
    rebuildTrackCache();
}

void CocoaScheduler::onResetTrack(track_index_t trackIndex) {
    auto it = mAudioUnitMap.find(trackIndex);
    if (it == mAudioUnitMap.end()) return;
    AudioUnitReset(it->second, kAudioUnitScope_Global, 0);
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

        #ifdef DEBUG
        // PERFORMANCE: Only log errors in debug builds (printf can block on I/O)
        if (result != noErr && midiEvent.midiStatus == 0x90) {
            printf("MIDI event failed: track=%d, status=0x%02X, error=%d\n",
                   trackIndex, midiEvent.midiStatus, (int)result);
        }
        #endif
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
