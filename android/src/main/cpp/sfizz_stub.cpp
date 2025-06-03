// Minimal sfizz stub implementation for Android
// This allows compilation when real sfizz libraries are not available

#include "sfizz.hpp"
#include <cstring>

namespace sfz {

class Sfizz::Impl {
public:
    float sampleRate = 44100.0f;
    int samplesPerBlock = 512;
};

Sfizz::Sfizz() : pImpl(new Impl()) {}
Sfizz::~Sfizz() { delete pImpl; }

bool Sfizz::loadSfzFile(const std::string& path) {
    // Stub implementation
    return false;
}

bool Sfizz::loadSfzString(const std::string& path, const std::string& text) {
    // Stub implementation
    return false;
}

bool Sfizz::loadScalaFile(const std::string& path) {
    // Stub implementation
    return false;
}

bool Sfizz::loadScalaString(const std::string& text) {
    // Stub implementation
    return false;
}

void Sfizz::setSampleRate(float sampleRate) {
    pImpl->sampleRate = sampleRate;
}

void Sfizz::setSamplesPerBlock(int samplesPerBlock) {
    pImpl->samplesPerBlock = samplesPerBlock;
}

void Sfizz::noteOn(int delay, int noteNumber, int velocity) {
    // Stub implementation
}

void Sfizz::noteOff(int delay, int noteNumber, int velocity) {
    // Stub implementation
}

void Sfizz::cc(int delay, int ccNumber, int ccValue) {
    // Stub implementation
}

void Sfizz::pitchWheel(int delay, int pitch) {
    // Stub implementation
}

void Sfizz::renderBlock(float** buffers, size_t numFrames, int numOutputs) {
    // Clear output buffers
    for (int i = 0; i < numOutputs; ++i) {
        if (buffers[i]) {
            std::memset(buffers[i], 0, numFrames * sizeof(float));
        }
    }
}

int Sfizz::getNumRegions() const {
    return 0;
}

} // namespace sfz