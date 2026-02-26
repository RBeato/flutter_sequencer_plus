#ifndef CocoaScheduler_h
#define CocoaScheduler_h

#include <AudioToolbox/AudioUnit.h>
#include "BaseScheduler.h"
#include "CallbackManager.h"
#include "SchedulerEvent.h"

const int MAX_TRACKS = 128;

#ifdef __cplusplus
#include <thread>

class CocoaScheduler : public BaseScheduler {
public:
    CocoaScheduler(AudioUnit _Nonnull mixerAudioUnit, double sampleRate);
    ~CocoaScheduler();

    void setTrackAudioUnit(track_index_t trackIndex, AudioUnit _Nonnull audioUnit);
    void startGlobalCallback();
    void handleAllTracks(uint32_t numFrames);
    void onRemoveTrack(track_index_t trackIndex);
    void rebuildTrackCache();

    void onResetTrack(track_index_t trackIndex);
    void handleRenderAudioRange(track_index_t trackIndex, uint32_t offsetFrame, uint32_t numFramesToRender);
    void handleEvent(track_index_t trackIndex, SchedulerEvent event, position_frame_t offsetFrame);
    float getTrackVolume(track_index_t trackIndex);
    int scaleFrames(track_index_t trackIndex, UInt32 inNumberFrames, bool isToDeviceFrames);
private:
    double getSampleRate(AudioUnit _Nonnull audioUnit);
    double mSampleRate;
    std::unordered_map<track_index_t, AudioUnit _Nonnull> mAudioUnitMap = {};
    std::unordered_map<track_index_t, double> mSampleRateMap = {};
    std::unordered_map<track_index_t, float> mTrackVolumeMap = {};
    bool mGlobalCallbackActive = false;

    AudioUnit _Nonnull mMixerAudioUnit;

    // PERFORMANCE: Pre-allocated array for track iteration (eliminates std::vector allocation in audio callback)
    track_index_t mTrackCache[MAX_TRACKS];
    std::atomic<size_t> mTrackCacheCount{0};
};
#endif


# ifdef __cplusplus
extern "C" {
#endif
void* _Nonnull InitScheduler(AudioUnit _Nonnull mixerAudioUnit, double sampleRate);
void DestroyScheduler(void* _Nonnull engine);
SInt32 SchedulerAddTrack(void* _Nonnull engine);
void SchedulerSetTrackAudioUnit(void* _Nonnull engine, track_index_t trackIndex, AudioUnit _Nonnull audioUnit);
void SchedulerRemoveTrack(void* _Nonnull engine, track_index_t trackIndex);
UInt32 SchedulerGetBufferAvailableCount(void* _Nonnull scheduler, track_index_t trackIndex);
void SchedulerHandleEventsNow(void* _Nonnull engine, track_index_t trackIndex, const struct SchedulerEvent* _Nonnull events, UInt32 eventsCount);
UInt32 SchedulerAddEvents(void* _Nonnull engine, track_index_t trackIndex, const struct SchedulerEvent* _Nonnull events, UInt32 eventsCount);
void SchedulerClearEvents(void* _Nonnull engine, track_index_t trackIndex, position_frame_t fromFrame);
void SchedulerPlay(void* _Nonnull engine);
void SchedulerPause(void* _Nonnull engine);
void SchedulerResetTrack(void* _Nonnull engine, track_index_t trackIndex);
UInt32 SchedulerGetPosition(void* _Nonnull engine);
UInt64 SchedulerGetLastRenderTimeUs(void* _Nonnull engine);
Float32 SchedulerGetTrackVolume(void* _Nonnull engine, track_index_t trackIndex);
void SchedulerStartGlobalCallback(void* _Nonnull scheduler);
#ifdef __cplusplus
}
#endif

#endif /* CocoaScheduler_h */