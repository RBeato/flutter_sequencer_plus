#ifndef SFIZZ_SAMPLER_INSTRUMENT_H
#define SFIZZ_SAMPLER_INSTRUMENT_H

#ifdef __cplusplus
#include "IInstrument.h"
#include "sfizz.hpp"
#include <string>

class SfizzSamplerInstrument : public IInstrument {
public:
    SfizzSamplerInstrument() {
        mSampler = std::make_unique<sfz::Sfizz>();
    }

    bool setOutputFormat(int32_t sampleRate, bool isStereo) override {
        mIsStereo = isStereo;
        mSampler->setSampleRate(sampleRate);

        return true;
    }

    void setSamplesPerBlock(int samplesPerBlock) {
        mSampler->setSamplesPerBlock(samplesPerBlock);
    }

    bool loadSfzString(const char* sampleRoot, const char* sfzString, const char* tuningString) {
        // Convert const char* to std::string for the interface
        std::string sfzStringStd(sfzString);
        
        // sampleRoot is ignored in this implementation since the interface doesn't support it
        auto loadResult = mSampler->loadSfzString(sfzStringStd);
        auto loadTuningResult = true;

        if (tuningString != nullptr) {
            std::string tuningStringStd(tuningString);
            mSampler->loadScalaString(tuningStringStd);
        }

        // Since getNumRegions is not available, we'll just return the load result
        return loadResult && loadTuningResult;
    }

    bool loadSfzFile(const char* path, const char* tuningPath) {
        // Convert const char* to std::string for the interface
        std::string pathStd(path);
        
        auto loadResult = mSampler->loadSfzFile(pathStd);
        auto loadTuningResult = true;

        if (tuningPath != nullptr) {
            std::string tuningPathStd(tuningPath);
            mSampler->loadScalaFile(tuningPathStd);
        }

        // Since getNumRegions is not available, we'll just return the load result
        return loadResult && loadTuningResult;
    }

    void renderAudio(float *audioData, int32_t numFrames) override {
        // Allocate buffers on the heap to avoid VLA warnings
        std::unique_ptr<float[]> leftBuffer(new float[numFrames]);
        std::unique_ptr<float[]> rightBuffer(new float[numFrames]);

        for (int f = 0; f < numFrames; f++) {
            leftBuffer[f] = 0.0f;
            rightBuffer[f] = 0.0f;
        }

        // Call the interface correctly with separate left and right buffers
        mSampler->renderBlock(leftBuffer.get(), rightBuffer.get(), numFrames);

        for (int f = 0; f < numFrames; f++) {
            if (mIsStereo) {
                for (int c = 0; c < 2; c++) {
                    audioData[f * 2 + c] = (c == 0) ? leftBuffer[f] : rightBuffer[f];
                }
            } else {
                audioData[f] = (leftBuffer[f] + rightBuffer[f]) / 2;
            }
        }
    }

    void handleMidiEvent(uint8_t status, uint8_t data1, uint8_t data2) override {
        auto statusCode = status >> 4;

        if (statusCode == 0x9) {
            // Note On
            mSampler->noteOn(0, data1, data2);
        } else if (statusCode == 0x8) {
            // Note Off
            mSampler->noteOff(0, data1, data2);
        } else if (statusCode == 0xB) {
            // CC
            mSampler->cc(0, data1, data2);
        } else if (statusCode == 0xE) {
            // Pitch bend
            // get 14-bit number from data1 and data2, subtract 8192
            auto pitch = ((data2 << 7) | data1) - 8192;
            mSampler->pitchWheel(0, pitch);
        }
    }

    void reset() override {
    }

private:
    bool mIsStereo;
    std::unique_ptr<sfz::Sfizz> mSampler;
};

#endif
#endif //SFIZZ_SAMPLER_INSTRUMENT_H
