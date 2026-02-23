#include "BaseScheduler.h"

#include <limits>
#include "SchedulerEvent.h"

track_index_t BaseScheduler::addTrack() {
    std::lock_guard<std::mutex> lock(mBufferMutex);

    for (track_index_t trackIndex = 0; trackIndex < MAX_AUDIO_TRACKS; trackIndex++) {
        if (mAudioBuffers[trackIndex] == nullptr) {
            auto buffer = std::make_shared<Buffer<>>();
            mBufferMap[trackIndex] = buffer;
            mAudioBuffers[trackIndex] = buffer.get();

            SEQ_LOG("addTrack: created buffer for track %d (ptr=%p)", trackIndex, buffer.get());
            return trackIndex;
        }
    }

    SEQ_LOG("addTrack: FAILED - no available slots");
    return -1;
}

void BaseScheduler::removeTrack(track_index_t trackIndex) {
    if (trackIndex < 0 || trackIndex >= MAX_AUDIO_TRACKS) return;

    SEQ_LOG("removeTrack: track %d - nulling audio buffer", trackIndex);
    mAudioBuffers[trackIndex] = nullptr;
    mHasRendered[trackIndex].store(false, std::memory_order_relaxed);

    onRemoveTrack(trackIndex);

    {
        std::lock_guard<std::mutex> lock(mBufferMutex);
        mBufferMap.erase(trackIndex);
    }
    SEQ_LOG("removeTrack: track %d - done", trackIndex);
}

void BaseScheduler::handleEventsNow(track_index_t trackIndex, const SchedulerEvent* events, uint32_t eventsCount) {
    if (trackIndex < 0 || trackIndex >= MAX_AUDIO_TRACKS) return;

    for (uint32_t i = 0; i < eventsCount; i++) {
        handleEvent(trackIndex, events[i], 0);
    }
}

uint32_t BaseScheduler::scheduleEvents(track_index_t trackIndex, const SchedulerEvent* events, uint32_t eventsCount) {
    if (trackIndex < 0 || trackIndex >= MAX_AUDIO_TRACKS) return 0;

    auto buffer = mAudioBuffers[trackIndex];
    if (buffer == nullptr) {
        SEQ_LOG("scheduleEvents: track %d - buffer is NULL!", trackIndex);
        return 0;
    }

    auto added = buffer->add(events, eventsCount);
    SEQ_LOG("scheduleEvents: track %d, requested=%u, added=%u, bufferCount=%u, available=%u",
            trackIndex, eventsCount, added, buffer->count(), buffer->availableCount());

    // Log first event frame for context
    if (added > 0) {
        SEQ_LOG("  firstEventFrame=%u, lastEventFrame=%u",
                events[0].frame, events[added - 1].frame);
    }
    return added;
}

void BaseScheduler::clearEvents(track_index_t trackIndex, position_frame_t fromFrame) {
    if (trackIndex < 0 || trackIndex >= MAX_AUDIO_TRACKS) return;

    auto buffer = mAudioBuffers[trackIndex];
    if (buffer == nullptr) return;

    auto countBefore = buffer->count();
    buffer->clearAfter(fromFrame);
    SEQ_LOG("clearEvents: track %d, fromFrame=%u, countBefore=%u, countAfter=%u",
            trackIndex, fromFrame, countBefore, buffer->count());
}

void BaseScheduler::play() {
    SEQ_LOG("play() called, position=%u", mPositionFrames.load(std::memory_order_relaxed));

    // Log buffer state for all active tracks
    for (int i = 0; i < MAX_AUDIO_TRACKS; i++) {
        if (mAudioBuffers[i] != nullptr) {
            SEQ_LOG("  track %d: bufferCount=%u, available=%u",
                    i, mAudioBuffers[i]->count(), mAudioBuffers[i]->availableCount());
        }
    }

    mIsPlaying.store(true, std::memory_order_release);
    SEQ_LOG("play() -> mIsPlaying=true");
}

void BaseScheduler::pause() {
    SEQ_LOG("pause() called, position=%u", mPositionFrames.load(std::memory_order_relaxed));
    mIsPlaying.store(false, std::memory_order_release);
}

void BaseScheduler::resetTrack(track_index_t trackIndex) {
    if (trackIndex < 0 || trackIndex >= MAX_AUDIO_TRACKS) return;

    auto buffer = mAudioBuffers[trackIndex];
    if (buffer == nullptr) return;

    SEQ_LOG("resetTrack: track %d, countBefore=%u", trackIndex, buffer->count());
    buffer->clear();
    onResetTrack(trackIndex);
}

uint32_t BaseScheduler::getBufferAvailableCount(track_index_t trackIndex) {
    if (trackIndex < 0 || trackIndex >= MAX_AUDIO_TRACKS) return 0;

    auto buffer = mAudioBuffers[trackIndex];
    if (buffer == nullptr) return 0;

    return buffer->availableCount();
}

position_frame_t BaseScheduler::getPosition() {
    return mPositionFrames.load(std::memory_order_relaxed);
}

uint64_t BaseScheduler::getLastRenderTimeUs() {
    timeval t;
    gettimeofday(&t, NULL);
    return t.tv_sec*uint64_t(1000000) + uint64_t(t.tv_usec);
}

// Audio thread render counter per track (for limited debug output)
#if SEQ_AUDIO_DEBUG
static std::atomic<uint32_t> sRenderCount[MAX_AUDIO_TRACKS] = {};
static const uint32_t LOG_FIRST_N_RENDERS = 5;
static const uint32_t LOG_EVERY_N_RENDERS = 500;
#endif

/// Called on the AUDIO THREAD by the render callback. Must be real-time safe:
/// NO mutex, NO allocations, NO I/O, NO system calls that can block.
void BaseScheduler::handleFrames(track_index_t trackIndex, uint32_t numFramesToRender) {
    if (!mIsPlaying.load(std::memory_order_relaxed)) return;
    if (trackIndex < 0 || trackIndex >= MAX_AUDIO_TRACKS) return;

    auto buffer = mAudioBuffers[trackIndex];
    if (buffer == nullptr) return;

#if SEQ_AUDIO_DEBUG
    auto renderNum = sRenderCount[trackIndex].fetch_add(1, std::memory_order_relaxed);
    bool shouldLog = (renderNum < LOG_FIRST_N_RENDERS) || (renderNum % LOG_EVERY_N_RENDERS == 0);
#endif

    auto originalPositionFrames = mPositionFrames.load(std::memory_order_relaxed);
    auto startFrame = originalPositionFrames;
    auto lastFrameRendered = startFrame;
    uint32_t framesRendered = 0;
    uint32_t eventsProcessed = 0;
    uint32_t eventsSkipped = 0;

    SchedulerEvent nextEvent;

    while (buffer->peek(nextEvent)) {
        auto eventFrame = nextEvent.frame;

        if (eventFrame < startFrame) {
            if (eventFrame + 1024 < startFrame) {
                buffer->removeTop();
                eventsSkipped++;
                continue;
            } else {
                eventFrame = startFrame;
            }
        }

        if ((framesRendered + eventFrame - lastFrameRendered) >= numFramesToRender) {
            break;
        }

        handleRenderAudioRange(trackIndex, framesRendered, eventFrame - lastFrameRendered);
        framesRendered += (eventFrame - lastFrameRendered);
        lastFrameRendered = eventFrame;

        handleEvent(trackIndex, nextEvent, framesRendered);
        buffer->removeTop();
        eventsProcessed++;
    }

    handleRenderAudioRange(trackIndex, framesRendered, numFramesToRender - framesRendered);

#if SEQ_AUDIO_DEBUG
    if (shouldLog) {
        SEQ_AUDIO_LOG("track %d render #%u: frames=%u, pos=%u, events=%u, skipped=%u, bufRemain=%u",
                trackIndex, renderNum, numFramesToRender, startFrame,
                eventsProcessed, eventsSkipped, buffer->count());
    }
#endif

    // Lock-free position tracking
    mHasRendered[trackIndex].store(true, std::memory_order_relaxed);

    bool allTracksHaveRendered = true;
    for (int i = 0; i < MAX_AUDIO_TRACKS; i++) {
        if (mAudioBuffers[i] != nullptr && !mHasRendered[i].load(std::memory_order_relaxed)) {
            allTracksHaveRendered = false;
            break;
        }
    }

    if (allTracksHaveRendered) {
        position_frame_t expected = originalPositionFrames;
        auto newPos = startFrame + numFramesToRender;
        mPositionFrames.compare_exchange_strong(expected, newPos, std::memory_order_relaxed);

        for (int i = 0; i < MAX_AUDIO_TRACKS; i++) {
            if (mAudioBuffers[i] != nullptr) {
                mHasRendered[i].store(false, std::memory_order_relaxed);
            }
        }
    }
}
