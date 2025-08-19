/*
 * This is used on Android only, on iOS we use the built in SoundFont AudioUnit
 */

#ifndef SOUND_FONT_INSTRUMENT_H
#define SOUND_FONT_INSTRUMENT_H

#include "IInstrument.h"
#include "../Utils/AssetManager.h"
#include "../Utils/Logging.h"

#include "tsf.h"

class SoundFontInstrument : public IInstrument {
public:
    int presetIndex;

    SoundFontInstrument() {
    }

    ~SoundFontInstrument() {
        tsf_close(mTsf);
    }

    bool setOutputFormat(int32_t sampleRate, bool isStereo) override {
        mIsStereo = isStereo;
        mSampleRate = sampleRate;

        setTsfOutputFormat();

        return true;
    }

    void setTsfOutputFormat() {
        if (mTsf != nullptr) {
            // TinySoundFont requires 4 parameters: f, outputmode, samplerate, globalgaindb
            // Use 0.0f for global gain (no attenuation) instead of -3.0f
            tsf_set_output(mTsf, mIsStereo ? TSF_STEREO_INTERLEAVED : TSF_MONO, mSampleRate, 0.0f);
            
            // Set reasonable gain to prevent distortion but ensure audible output
            tsf_set_volume(mTsf, 1.0f);  // Use full volume for better audibility
            
            LOGI("TSF: Configured output - %s, %dHz, 0dB gain, volume=1.0", 
                 mIsStereo ? "STEREO" : "MONO", mSampleRate);
        }
    }

    bool loadSf2File(const char* path, bool isAsset, int32_t presetIndex) {
        this->presetIndex = presetIndex;
        LOGI("SF2 Loading: path=%s, isAsset=%d, presetIndex=%d", path, isAsset, presetIndex);

        if (isAsset) {
            auto asset = openAssetBuffer(path);
            if (!asset) {
                LOGE("SF2 Load FAILED: Cannot open asset %s", path);
                return false;
            }
            
            auto assetBuffer = AAsset_getBuffer(asset);
            auto assetLength = AAsset_getLength(asset);
            LOGI("SF2 Asset loaded: size=%ld bytes", assetLength);

            mTsf = tsf_load_memory(assetBuffer, assetLength);
            AAsset_close(asset);
        } else {
            mTsf = tsf_load_filename(path);
        }

        if (mTsf != nullptr) {
            setTsfOutputFormat();
            
            // Get SF2 info for debugging
            int presetCount = tsf_get_presetcount(mTsf);
            LOGI("SF2 Loaded successfully: %d presets available, using preset %d", presetCount, presetIndex);
            
            // Validate preset index
            if (presetIndex >= presetCount) {
                LOGE("SF2 Invalid preset index %d (max: %d), using preset 0", presetIndex, presetCount - 1);
                this->presetIndex = 0;
            }
            
            // CRITICAL: For GM instruments, use bank 0 and the GM program number
            // Look up the correct preset index from the SF2 file using bank/program
            int actualPresetIndex = tsf_get_presetindex(mTsf, 0, presetIndex); // Bank 0, Program = presetIndex
            if (actualPresetIndex == -1) {
                LOGI("SF2 GM program %d not found in bank 0, trying direct preset index", presetIndex);
                actualPresetIndex = (presetIndex < presetCount) ? presetIndex : 0;
            } else {
                LOGI("SF2 GM program %d mapped to preset index %d", presetIndex, actualPresetIndex);
            }
            
            // Set the correct preset for ALL MIDI channels (0-15)
            for (int ch = 0; ch < 16; ch++) {
                tsf_channel_set_presetindex(mTsf, ch, actualPresetIndex);
                tsf_channel_set_bank(mTsf, ch, 0);  // Bank 0 for GM
                tsf_channel_set_presetnumber(mTsf, ch, presetIndex);  // GM program number
            }
            LOGI("SF2 GM preset configured: program=%d -> preset_index=%d", presetIndex, actualPresetIndex);
            
            return true;
        } else {
            LOGE("SF2 Load FAILED: tsf_load_memory returned null for %s", path);
            return false;
        }
    }

    void renderAudio(float *audioData, int32_t numFrames) override {
        if (mTsf == nullptr || numFrames <= 0) {
            // Clear buffer if no sound font loaded
            memset(audioData, 0, numFrames * (mIsStereo ? 2 : 1) * sizeof(float));
            return;
        }
        
        // TinySoundFont requires 4 parameters: f, buffer, samples, flag_mixing
        // Use 0 for replace mode - the Mixer handles combining tracks
        tsf_render_float(mTsf, audioData, numFrames, 0);
        
        // Check for audio activity (very infrequent logging for performance)
        const int32_t totalSamples = numFrames * (mIsStereo ? 2 : 1);
        float maxSample = 0.0f;
        for (int32_t i = 0; i < totalSamples; ++i) {
            maxSample = std::max(maxSample, std::abs(audioData[i]));
        }
        
        // Log audio activity much less frequently (only every 2000 frames with audio)
        static int frameCounter = 0;
        if (++frameCounter % 2000 == 0 && maxSample > 0.001f) {
            LOGI("TSF: Audio rendered - max sample level: %.4f", maxSample);
        }
        
        // Apply soft limiting to prevent clipping distortion
        constexpr float maxLevel = 0.95f;  // Leave headroom
        for (int32_t i = 0; i < totalSamples; ++i) {
            float sample = audioData[i];
            if (sample > maxLevel) {
                audioData[i] = maxLevel;
            } else if (sample < -maxLevel) {
                audioData[i] = -maxLevel;
            }
        }
    }

    void handleMidiEvent(uint8_t status, uint8_t data1, uint8_t data2) override {
        auto channel = status & 0x0F;
        auto statusCode = status >> 4;

        if (statusCode == 0x9) {
            // Note On - CRITICAL PATH
            if (mTsf != nullptr) {
                // Ensure velocity is properly scaled
                float velocity = (data2 > 0) ? (data2 / 127.0f) : 0.0f;
                
                // CRITICAL: If velocity is 0, treat as note off (MIDI standard)
                if (data2 == 0) {
                    tsf_note_off(mTsf, channel, data1);
                    return;
                }
                
                // Minimal logging for performance - only log errors
                tsf_note_on(mTsf, channel, data1, velocity);
                
                // Only log failures to prevent performance issues
                static int errorLogCount = 0;
                if (tsf_active_voice_count(mTsf) == 0 && ++errorLogCount % 10 == 0) {
                    LOGE("SF2 ERROR: Note ON failed - no voices! preset=%d", this->presetIndex);
                }
            }
        } else if (statusCode == 0x8) {
            // Note Off
            if (mTsf != nullptr) {
                tsf_note_off(mTsf, channel, data1);
            }
        } else if (statusCode == 0xB) {
            // CC
            if (mTsf != nullptr) {
                tsf_channel_midi_control(mTsf, channel, data1, data2);
            }
        } else if (statusCode == 0xE) {
            // Pitch bend
            auto pitch = (data2 << 7) | data1;
            if (mTsf != nullptr) {
                tsf_channel_set_pitchwheel(mTsf, channel, pitch);
            }
        }
    }

    void reset() override {
    }

private:
    tsf* mTsf = nullptr;
    bool mIsStereo;
    int32_t mSampleRate;
};

#endif //SOUND_FONT_INSTRUMENT_H
