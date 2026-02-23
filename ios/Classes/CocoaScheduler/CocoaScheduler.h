#ifndef CocoaScheduler_h
#define CocoaScheduler_h

#include <AudioToolbox/AudioUnit.h>
#include "BaseScheduler.h"
#include "CallbackManager.h"
#include "SchedulerEvent.h"

const int MAX_TRACKS = 128;

#ifdef __cplusplus
#include <thread>

/// Heap-allocated render callback context.
/// Stable pointer regardless of map rehashing - critical for audio thread safety.
struct RenderRefCon {
    track_index_t trackIndex;
    void* scheduler; // CocoaScheduler*
};

class CocoaScheduler : public BaseScheduler {
public:
    CocoaScheduler(AudioUnit _Nonnull mixerAudioUnit, double sampleRate);
    ~CocoaScheduler();

    void setTrackAudioUnit(track_index_t trackIndex, AudioUnit _Nonnull audioUnit);
    void onRemoveTrack(track_index_t trackIndex);

    void onResetTrack(track_index_t trackIndex);
    void handleRenderAudioRange(track_index_t trackIndex, uint32_t offsetFrame, uint32_t numFramesToRender);
    void handleEvent(track_index_t trackIndex, SchedulerEvent event, position_frame_t offsetFrame);
    float getTrackVolume(track_index_t trackIndex);
    int scaleFrames(track_index_t trackIndex, UInt32 inNumberFrames, bool isToDeviceFrames);
private:
    double getSampleRate(AudioUnit _Nonnull audioUnit);
    double mSampleRate;

    // LOCK-FREE audio thread access: fixed-size arrays indexed by trackIndex.
    // Written by main thread (setTrackAudioUnit/onRemoveTrack),
    // read by audio thread (handleEvent/scaleFrames).
    // Pointer and double writes are atomic on 64-bit architectures (ARM64/x86-64).
    // Using arrays instead of unordered_map eliminates rehash-induced heap corruption.
    AudioUnit mTrackAudioUnits[MAX_TRACKS] = {};
    double mTrackSampleRates[MAX_TRACKS] = {};

    // Render callback contexts - heap allocated for stable pointers.
    // NOT freed during onRemoveTrack to avoid use-after-free in audio callbacks
    // (AudioUnitRemoveRenderNotify does NOT guarantee callback has finished).
    // Freed only in destructor when engine is fully stopped.
    RenderRefCon* mTrackRefCons[MAX_TRACKS] = {};

    AudioUnit _Nonnull mMixerAudioUnit;
};
#endif


# ifdef __cplusplus
extern "C" {
#endif
void* _Nonnull InitScheduler(AudioUnit _Nonnull mixerAudioUnit, double sampleRate);
void DestroyScheduler(void* _Nonnull engine);
SInt32 SchedulerAddTrack(const void* _Nonnull engine);
void SchedulerSetTrackAudioUnit(const void* _Nonnull engine, track_index_t trackIndex, AudioUnit _Nonnull audioUnit);
void SchedulerRemoveTrack(const void* _Nonnull engine, track_index_t trackIndex);
UInt32 SchedulerGetBufferAvailableCount(const void* _Nonnull scheduler, track_index_t trackIndex);
void SchedulerHandleEventsNow(const void* _Nonnull engine, track_index_t trackIndex, const struct SchedulerEvent* _Nonnull events, UInt32 eventsCount);
UInt32 SchedulerAddEvents(const void* _Nonnull engine, track_index_t trackIndex, const struct SchedulerEvent* _Nonnull events, UInt32 eventsCount);
void SchedulerClearEvents(const void* _Nonnull engine, track_index_t trackIndex, position_frame_t fromFrame);
void SchedulerPlay(const void* _Nonnull engine);
void SchedulerPause(const void* _Nonnull engine);
void SchedulerResetTrack(const void* _Nonnull engine, track_index_t trackIndex);
UInt32 SchedulerGetPosition(const void* _Nonnull engine);
UInt64 SchedulerGetLastRenderTimeUs(const void* _Nonnull engine);
Float32 SchedulerGetTrackVolume(const void* _Nonnull engine, track_index_t trackIndex);
#ifdef __cplusplus
}
#endif

#endif /* CocoaScheduler_h */
