#ifndef BaseScheduler_h
#define BaseScheduler_h
#include <stdint.h>
#include <stdio.h>

typedef int32_t track_index_t;

// Toggle main-thread debug logging: set to 1 to enable, 0 to disable
#define SEQ_DEBUG 0

// Toggle audio-thread debug logging: WARNING - printf is NOT real-time safe!
// Only enable temporarily for debugging. Can cause CoreAudio watchdog kills.
#define SEQ_AUDIO_DEBUG 0

#if SEQ_DEBUG
    #define SEQ_LOG(fmt, ...) printf("[SEQ-C++] " fmt "\n", ##__VA_ARGS__)
#else
    #define SEQ_LOG(fmt, ...) ((void)0)
#endif

#if SEQ_AUDIO_DEBUG
    #define SEQ_AUDIO_LOG(fmt, ...) printf("[SEQ-AUDIO] " fmt "\n", ##__VA_ARGS__)
#else
    #define SEQ_AUDIO_LOG(fmt, ...) ((void)0)
#endif

#ifdef __cplusplus
#include <memory>
#include <unordered_map>
#include <sys/time.h>
#include <mutex>
#include <atomic>
#include <Buffer.h>
#include <CallbackManager.h>
#include <SchedulerEvent.h>

static const int MAX_AUDIO_TRACKS = 128;

class BaseScheduler {
public:
    track_index_t addTrack();
    void removeTrack(track_index_t trackIndex);
    virtual void onRemoveTrack(track_index_t trackIndex) = 0; // Will be called at the end of removeTrack.

    void handleEventsNow(track_index_t trackIndex, const SchedulerEvent* events, uint32_t eventsCount);
    uint32_t scheduleEvents(track_index_t trackIndex, const SchedulerEvent* events, uint32_t eventsCount);
    void clearEvents(track_index_t trackIndex, position_frame_t fromFrame);
    void play();
    void pause();
    void resetTrack(track_index_t trackIndex);
    virtual void onResetTrack(track_index_t trackIndex) = 0;

    void handleFrames(track_index_t trackIndex, uint32_t numFramesToRender);
    virtual void handleRenderAudioRange(track_index_t trackIndex, uint32_t offsetFrame, uint32_t numFramesToRender) = 0;
    virtual void handleEvent(track_index_t trackIndex, SchedulerEvent event, position_frame_t offsetFrame) = 0;

    uint32_t getBufferAvailableCount(track_index_t trackIndex);
    position_frame_t getPosition();
    uint64_t getLastRenderTimeUs();
protected:
    // Lifetime management for buffers (main thread only, mutex-protected)
    std::unordered_map<track_index_t, std::shared_ptr<Buffer<>>> mBufferMap = {};
    mutable std::mutex mBufferMutex;

    // Lock-free audio thread access - raw pointers into mBufferMap's shared_ptrs.
    // Written by main thread (addTrack/removeTrack), read by audio thread (handleFrames).
    // Safe because: pointer writes are atomic on all modern architectures,
    // and we always set the pointer AFTER the buffer is fully constructed.
    Buffer<>* mAudioBuffers[MAX_AUDIO_TRACKS] = {};

    // Lock-free render tracking - replaces mHasRenderedMap
    std::atomic<bool> mHasRendered[MAX_AUDIO_TRACKS] = {};
private:
    std::atomic<bool> mIsPlaying{false};
    std::atomic<position_frame_t> mPositionFrames{0};
};

#endif
#endif /* BaseScheduler_h */
