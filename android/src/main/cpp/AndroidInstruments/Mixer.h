/*
 * Adapted from https://github.com/google/oboe/blob/master/samples/shared/Mixer.h
 * This is used on Android only, on iOS we use the built in mixer
 */

#ifndef MIXER_H
#define MIXER_H

#include <array>
#include <optional>
#include "BaseScheduler.h"
#include "IRenderableAudio.h"
#include "../Utils/OptionArray.h"
#include "../Utils/Logging.h"

#ifdef __ARM_NEON__
#include <arm_neon.h>  // SIMD intrinsics for ARM NEON
#endif

constexpr int32_t kBufferSize = 128*2;  // Match AndroidEngine buffer size (128 frames * 2 channels)
constexpr uint8_t kMaxTracks = 64;  // Reasonable limit for mobile performance

/**
 * A Mixer object which sums the output from multiple tracks into a single output. The number of
 * input channels on each track must match the number of output channels (default 1=mono). This can
 * be changed by calling `setChannelCount`.
 * The inputs to the mixer are not owned by the mixer, they should not be deleted while rendering.
 */

struct TrackInfo {
    IInstrument* track;
    float level;
};

class Mixer : public IRenderableAudio, public BaseScheduler {

public:
    Mixer() {
        static_assert(std::is_base_of<IRenderableAudio, IInstrument>::value, "TTrack must be derived from IRenderableAudio");
    }

    void renderAudio(float *audioData, int32_t numFrames) {
        if (numFrames == 0) {
            return;
        }

        // Zero out the incoming container array efficiently
        const size_t totalSamples = numFrames * mChannelCount;
        memset(audioData, 0, sizeof(float) * totalSamples);

        // Early exit if no tracks
        if (mTrackMap.empty()) {
            return;
        }

        // Render each track and mix
        for (const auto& pair : mTrackMap) {
            const auto trackIndex = pair.first;
            const auto& trackInfo = pair.second;

            // Skip silent tracks
            if (trackInfo.level <= 0.0f) {
                continue;
            }

            // Zero mixingBuffer before each track to prevent stale/garbage data
            memset(mixingBuffer, 0, sizeof(float) * totalSamples);

            handleFrames(trackIndex, numFrames);

            // PERFORMANCE: SIMD-optimized mixing loop with NEON intrinsics
            const float level = trackInfo.level;

            #ifdef __ARM_NEON__
            // NEON SIMD path: Process 4 samples at a time (4x speedup)
            const size_t simdSamples = totalSamples & ~3;  // Round down to multiple of 4

            if (level == 1.0f) {
                // Fast path: Unity gain addition (no scaling needed)
                for (size_t j = 0; j < simdSamples; j += 4) {
                    float32x4_t mix = vld1q_f32(&mixingBuffer[j]);
                    float32x4_t out = vld1q_f32(&audioData[j]);
                    out = vaddq_f32(out, mix);
                    vst1q_f32(&audioData[j], out);
                }
            } else {
                // General case: Scaled addition
                float32x4_t levelVec = vdupq_n_f32(level);
                for (size_t j = 0; j < simdSamples; j += 4) {
                    float32x4_t mix = vld1q_f32(&mixingBuffer[j]);
                    float32x4_t out = vld1q_f32(&audioData[j]);
                    mix = vmulq_f32(mix, levelVec);
                    out = vaddq_f32(out, mix);
                    vst1q_f32(&audioData[j], out);
                }
            }

            // Handle remaining samples (scalar fallback)
            for (size_t j = simdSamples; j < totalSamples; ++j) {
                audioData[j] += mixingBuffer[j] * level;
            }
            #else
            // Scalar fallback for non-NEON platforms
            if (level == 1.0f) {
                for (size_t j = 0; j < totalSamples; ++j) {
                    audioData[j] += mixingBuffer[j];
                }
            } else {
                for (size_t j = 0; j < totalSamples; ++j) {
                    audioData[j] += mixingBuffer[j] * level;
                }
            }
            #endif
        }
    }

    void handleRenderAudioRange(track_index_t trackIndex, uint32_t offsetFrame, uint32_t numFramesToRender) {
        if (numFramesToRender == 0) return;
        if ((offsetFrame + numFramesToRender) * mChannelCount > kBufferSize) return;

        auto offsetMixingBuffer = mixingBuffer + offsetFrame * mChannelCount;

        auto maybeTrackInfo = getTrackInfo(trackIndex);
        if (maybeTrackInfo.has_value()) {
            auto trackInfo = maybeTrackInfo.value();
            IInstrument *track = trackInfo.track;
            track->renderAudio(offsetMixingBuffer, numFramesToRender);
        }
    }

    void handleEvent(track_index_t trackIndex, SchedulerEvent event, position_frame_t offsetFrame) {
        if (event.type == VOLUME_EVENT) {
            auto volumeEvent = VolumeEventData(event.data);

            setLevel(trackIndex, volumeEvent.volume);
        } else if (event.type == MIDI_EVENT) {
            auto midiEvent = MidiEventData(event.data);
            auto track = getTrack(trackIndex);

            if (track.has_value()) {
                // MIDI event routed to track
                track.value()->handleMidiEvent(midiEvent.midiStatus, midiEvent.midiData1, midiEvent.midiData2);
            } else {
                // Mixer error: track doesn't exist
            }
        }
    }

    track_index_t addTrack(IInstrument *track) {
        auto trackIndex = BaseScheduler::addTrack();

        TrackInfo trackInfo;
        trackInfo.track = track;
        trackInfo.level = 1.0;

        mTrackMap.insert({ trackIndex, trackInfo });

        return trackIndex;
    }

    void onRemoveTrack(track_index_t trackIndex) {
        auto it = mTrackMap.find(trackIndex);
        if (it != mTrackMap.end()) {
            delete it->second.track;
            mTrackMap.erase(it);
        }
    }

    std::optional<IInstrument*> getTrack(track_index_t trackIndex) {
        auto maybeTrackInfo = getTrackInfo(trackIndex);

        if (maybeTrackInfo.has_value()) {
            return maybeTrackInfo.value().track;
        } else {
            return std::nullopt;
        }
    }

    void onResetTrack(track_index_t trackIndex) {
        auto search = mTrackMap.find(trackIndex);

        if (search != mTrackMap.end()) {
            auto trackInfo = search->second;
            IInstrument *track = trackInfo.track;

            track->reset();
        }
    }

    void setLevel(track_index_t trackIndex, float level) {
        auto maybeTrackInfo = getTrackInfo(trackIndex);

        if (maybeTrackInfo.has_value()) {
            TrackInfo nextTrackInfo = maybeTrackInfo.value();
            nextTrackInfo.level = level;
            mTrackMap.insert_or_assign(trackIndex, nextTrackInfo);
            
            // Track level set
        } else {
            // Failed to set track level - track not found
        }
    }

    float getLevel(track_index_t trackIndex) {
        auto maybeTrackInfo = getTrackInfo(trackIndex);

        if (maybeTrackInfo.has_value()) {
            TrackInfo nextTrackInfo = maybeTrackInfo.value();
            return nextTrackInfo.level;
        } else {
            // getLevel called for non-existent track - returning default
            return 1.0f; // Return sensible default instead of 0.0
        }
    }

    int32_t getChannelCount() { return mChannelCount; }
    void setChannelCount(int32_t channelCount) { mChannelCount = channelCount; }

private:
    std::optional<TrackInfo> getTrackInfo(track_index_t trackIndex) {
        auto search = mTrackMap.find(trackIndex);

        if (search != mTrackMap.end()) {
            return std::optional(search->second);
        } else {
            return std::nullopt;
        }
    }

    float mixingBuffer[kBufferSize] = {};  // Zero-initialize to prevent startup glitch
    std::unordered_map<track_index_t, TrackInfo> mTrackMap = {};
    int32_t mChannelCount = 1; // Default to mono
};

#endif //MIXER_H
