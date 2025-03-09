/*
 * This is the Android version of the Sfizz instrument
 */

#ifndef SFIZZ_SAMPLER_INSTRUMENT_H
#define SFIZZ_SAMPLER_INSTRUMENT_H

#include "IInstrument.h"
#include "../Utils/AssetManager.h"
#include <sfizz.hpp>
#include <memory>
#include <string>
#include <vector>

class SfizzSamplerInstrument : public IInstrument {
public:
    SfizzSamplerInstrument() {
        mSfizz = std::make_unique<sfz::Sfizz>();
    }

    ~SfizzSamplerInstrument() = default;

    void setSamplesPerBlock(int samplesPerBlock) {
        if (mSfizz) {
            mSfizz->setSamplesPerBlock(samplesPerBlock);
        }
    }

    bool setOutputFormat(int32_t sampleRate, bool isStereo) override {
        mIsStereo = isStereo;
        mSampleRate = sampleRate;

        if (mSfizz) {
            mSfizz->setSampleRate(mSampleRate);
        }

        return true;
    }

    bool loadSfzFile(const char* path, const char* tuningFile) {
        if (!mSfizz) {
            return false;
        }

        mSfzPath = std::string(path);
        
        bool success = mSfizz->loadSfzFile(mSfzPath);
        
        if (success && tuningFile && strlen(tuningFile) > 0) {
            // Load tuning file if provided
            mSfizz->loadScalaFile(tuningFile);
        }
        
        return success;
    }

    bool loadSfzString(const char* sampleRoot, const char* sfzString, const char* tuningString) {
        if (!mSfizz) {
            return false;
        }

        mSfzPath = std::string(sampleRoot);
        
        bool success = mSfizz->loadSfzString(sfzString);
        
        if (success && tuningString && strlen(tuningString) > 0) {
            // Load tuning data if provided
            mSfizz->loadScalaString(tuningString);
        }
        
        return success;
    }

    void renderAudio(float *audioData, int32_t numFrames) override {
        if (!mSfizz) {
            // Fill with silence if not initialized
            std::fill(audioData, audioData + numFrames * (mIsStereo ? 2 : 1), 0.0f);
            return;
        }

        // Process MIDI events that happened since last render
        processQueuedEvents();

        // Render audio
        if (mIsStereo) {
            mSfizz->renderBlock(audioData, audioData + numFrames, numFrames);
        } else {
            // For mono, we'll use a temporary buffer and mix down
            std::vector<float> stereoBuffer(numFrames * 2);
            mSfizz->renderBlock(stereoBuffer.data(), stereoBuffer.data() + numFrames, numFrames);
            
            // Mix down to mono
            for (int i = 0; i < numFrames; i++) {
                audioData[i] = (stereoBuffer[i * 2] + stereoBuffer[i * 2 + 1]) * 0.5f;
            }
        }
    }

    void handleMidiEvent(uint8_t status, uint8_t data1, uint8_t data2) override {
        if (!mSfizz) {
            return;
        }

        auto channel = status & 0x0F;
        auto statusCode = status >> 4;

        if (statusCode == 0x9 && data2 > 0) {
            // Note On
            mSfizz->noteOn(channel, data1, data2);
        } else if (statusCode == 0x8 || (statusCode == 0x9 && data2 == 0)) {
            // Note Off
            mSfizz->noteOff(channel, data1, data2);
        } else if (statusCode == 0xB) {
            // CC
            mSfizz->cc(channel, data1, data2);
        } else if (statusCode == 0xE) {
            // Pitch bend
            // get 14-bit number from data1 and data2
            uint16_t pitch = (data2 << 7) | data1;
            // Convert from 0-16383 to -8192-8191
            int16_t bipolarPitch = pitch - 8192;
            mSfizz->pitchWheel(channel, bipolarPitch);
        }
    }

    void reset() override {
        if (mSfizz) {
            mSfizz->allSoundOff();
        }
    }

private:
    void processQueuedEvents() {
        // This would process any events that need to be processed at render time
        // For sfizz, we already handle events in real-time, so this is a no-op
    }

    std::unique_ptr<sfz::Sfizz> mSfizz;
    std::string mSfzPath;
    bool mIsStereo = true;
    int32_t mSampleRate = 44100;
};

#endif // SFIZZ_SAMPLER_INSTRUMENT_H 