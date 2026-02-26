#include "BaseScheduler.h"

#include <limits>
#include "SchedulerEvent.h"

track_index_t BaseScheduler::addTrack() {
    std::lock_guard<std::mutex> lock(mBufferMutex);
    constexpr track_index_t maxTracks = 256; // reasonable limit for mobile

    for (track_index_t trackIndex = 0; trackIndex < maxTracks; trackIndex++) {
        if (mBufferMap.find(trackIndex) == mBufferMap.end()) {
            mBufferMap[trackIndex] = std::make_shared<Buffer<>>();
            return trackIndex;
        }
    }

    return -1;
}

void BaseScheduler::removeTrack(track_index_t trackIndex) {
    {
        std::lock_guard<std::mutex> lock(mBufferMutex);
        mBufferMap.erase(trackIndex);
        mHasRenderedMap.erase(trackIndex);
    }

    onRemoveTrack(trackIndex);
}

void BaseScheduler::handleEventsNow(track_index_t trackIndex, const SchedulerEvent* events, uint32_t eventsCount) {
    // Thread-safe check
    {
        std::lock_guard<std::mutex> lock(mBufferMutex);
        if (mBufferMap.find(trackIndex) == mBufferMap.end()) {
            return;
        }
    }

    for (uint32_t i = 0; i < eventsCount; i++) {
        handleEvent(trackIndex, events[i], 0);
    }
}

uint32_t BaseScheduler::scheduleEvents(track_index_t trackIndex, const SchedulerEvent* events, uint32_t eventsCount) {
    std::lock_guard<std::mutex> lock(mBufferMutex);

    // Thread-safe check
    if (mBufferMap.find(trackIndex) == mBufferMap.end()) {
        return 0;
    }

    // Events must come after anything already in the buffer and be sorted by frame, ascending.
    return mBufferMap[trackIndex]->add(events, eventsCount);
};

void BaseScheduler::clearEvents(track_index_t trackIndex, position_frame_t fromFrame) {
    std::lock_guard<std::mutex> lock(mBufferMutex);

    // Thread-safe check - CRITICAL FIX for crash
    if (mBufferMap.find(trackIndex) == mBufferMap.end()) {
        return;
    }

    // Additional safety: check if buffer pointer is valid
    if (mBufferMap[trackIndex] == nullptr) {
        return;
    }

    mBufferMap[trackIndex]->clearAfter(fromFrame);
};

void BaseScheduler::play() {
    if (mIsPlaying) return;

    mIsPlaying = true;
};

void BaseScheduler::pause() {
    if (!mIsPlaying) return;
    
    mIsPlaying = false;
};

void BaseScheduler::resetTrack(track_index_t trackIndex) {
    // Thread-safe operation
    {
        std::lock_guard<std::mutex> lock(mBufferMutex);

        // Safety check: ensure track exists in buffer map
        if (mBufferMap.find(trackIndex) == mBufferMap.end()) {
            return;
        }

        // Additional safety: check if buffer pointer is valid
        if (mBufferMap[trackIndex] == nullptr) {
            return;
        }

        // MINIMAL RESET: Don't send ANY MIDI events during reset to prevent corruption
        // Just call the platform-specific reset and clear the buffer

        // Clear the event buffer for this track
        mBufferMap[trackIndex]->clear();
    }

    // Call the platform-specific reset WITHOUT sending MIDI events (outside lock)
    onResetTrack(trackIndex);
}

uint32_t BaseScheduler::getBufferAvailableCount(track_index_t trackIndex) {
    std::lock_guard<std::mutex> lock(mBufferMutex);

    // Thread-safe check
    if (mBufferMap.find(trackIndex) == mBufferMap.end()) {
        return 0;
    }

    if (mBufferMap[trackIndex] == nullptr) {
        return 0;
    }

    return mBufferMap[trackIndex]->availableCount();
}

position_frame_t BaseScheduler::getPosition() {
    return mPositionFrames;
}

uint64_t BaseScheduler::getLastRenderTimeUs() {
    timeval t;
    gettimeofday(&t, NULL);
    return t.tv_sec*uint64_t(1000000) + uint64_t(t.tv_usec);
}

void BaseScheduler::handleFrames(track_index_t trackIndex, uint32_t numFramesToRender) {
    if (!mIsPlaying) return;

    // Thread-safe buffer access
    std::shared_ptr<Buffer<>> buffer;
    {
        std::lock_guard<std::mutex> lock(mBufferMutex);

        // Safety check: ensure track exists
        if (mBufferMap.find(trackIndex) == mBufferMap.end() || mBufferMap[trackIndex] == nullptr) {
            return;
        }

        buffer = mBufferMap[trackIndex];
    }

    auto originalPositionFrames = mPositionFrames.load(); // so we can check if setPosition was called
    auto startFrame = mPositionFrames.load();
    auto lastFrameRendered = startFrame;
    uint32_t framesRendered = 0;

    SchedulerEvent nextEvent;

    while (buffer->peek(nextEvent)) {
        auto eventFrame = nextEvent.frame;
        
        if (eventFrame < startFrame) {
            // Skip events that are too far in the past (4096 frames ~= 93ms at 44.1kHz)
            // Must exceed position tracking interval (33ms = ~1470 frames) plus scheduling latency
            if (eventFrame + 4096 < startFrame) {
                // printf("Track %i: Skipping event with frame %i, which is less than start frame %i\n", trackIndex, eventFrame, startFrame);
                buffer->removeTop();
                continue;
            } else {
                // printf("Track %i: Accepting late event with frame %i, which is less than start frame %i\n", trackIndex, eventFrame, startFrame);
                eventFrame = startFrame;
            }
        }

        // If the next event is after numFramesToRender, then ignore it for now and just render
        if ((framesRendered + eventFrame - lastFrameRendered) >= numFramesToRender) {
            break;
        }

        // Render frames until event
        handleRenderAudioRange(trackIndex, framesRendered, eventFrame - lastFrameRendered);
        framesRendered += (eventFrame - lastFrameRendered);
        lastFrameRendered = eventFrame;
        
        handleEvent(trackIndex, nextEvent, framesRendered);
        buffer->removeTop();
    }
    
    handleRenderAudioRange(trackIndex, framesRendered, numFramesToRender - framesRendered);

    // PERFORMANCE: Simplified position tracking without heavy mutex contention
    // Just update position atomically after rendering (good enough for most use cases)
    // Don't update if setPosition was called during rendering
    if (mPositionFrames.compare_exchange_weak(originalPositionFrames, startFrame + numFramesToRender,
                                               std::memory_order_release,
                                               std::memory_order_relaxed)) {
        // Position updated successfully
    }
}
