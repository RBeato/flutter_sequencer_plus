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

            handleFrames(trackIndex, numFrames);

            // Optimized mixing loop with level scaling
            const float level = trackInfo.level;
            if (level == 1.0f) {
                // Fast path for unity gain
                for (size_t j = 0; j < totalSamples; ++j) {
                    audioData[j] += mixingBuffer[j];
                }
            } else {
                // General case with level scaling
                for (size_t j = 0; j < totalSamples; ++j) {
                    audioData[j] += mixingBuffer[j] * level;
                }
            }
        }
    }

    void handleRenderAudioRange(track_index_t trackIndex, uint32_t offsetFrame, uint32_t numFramesToRender) {
        if (numFramesToRender == 0) return;

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
                // Reduce logging frequency during playback
                uint8_t statusCode = midiEvent.midiStatus >> 4;
                static int noteOnLogCount = 0;
                if (statusCode == 0x9 && ++noteOnLogCount % 8 == 0) { // Only log every 8th note
                    LOGI("→ Mixer routing NOTE ON to track %d: note=%d vel=%d", 
                         trackIndex, midiEvent.midiData1, midiEvent.midiData2);
                }
                track.value()->handleMidiEvent(midiEvent.midiStatus, midiEvent.midiData1, midiEvent.midiData2);
            } else {
                LOGE("❌ MIXER ERROR: Track %d doesn't exist!", trackIndex);
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
        mTrackMap.erase(trackIndex);
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
            
            LOGI("Mixer: Set track %d level to %.3f", trackIndex, level);
        } else {
            LOGE("Mixer: Failed to set level for track %d - track not found", trackIndex);
        }
    }

    float getLevel(track_index_t trackIndex) {
        auto maybeTrackInfo = getTrackInfo(trackIndex);

        if (maybeTrackInfo.has_value()) {
            TrackInfo nextTrackInfo = maybeTrackInfo.value();
            return nextTrackInfo.level;
        } else {
            LOGE("Mixer: getLevel called for non-existent track %d - returning default 1.0", trackIndex);
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

    float mixingBuffer[kBufferSize];
    std::unordered_map<track_index_t, TrackInfo> mTrackMap = {};
    int32_t mChannelCount = 1; // Default to mono
};

#endif //MIXER_H
