// Minimal sfizz stub implementation for Android
// This allows compilation when real sfizz libraries are not available
// Optimized for minimal performance overhead

#include "sfizz.hpp"
#include <cstring>
#include <atomic>
#include <string>

namespace sfz {

// Forward declaration
class SfizzImpl {
public:
    std::atomic<float> sampleRate{44100.0f};
    std::atomic<int> samplesPerBlock{512};
    std::atomic<bool> isLoaded{false};
    std::atomic<int> numRegions{0};
    
    // Pre-allocated zero buffer to avoid repeated memset calls
    static constexpr size_t MAX_BUFFER_SIZE = 8192; // 8K samples should cover most cases
    static float zeroBuffer[MAX_BUFFER_SIZE];
};

// Define the static zero buffer (initialized to zeros by default)
float SfizzImpl::zeroBuffer[SfizzImpl::MAX_BUFFER_SIZE] = {};

// Implementation class definition for PIMPL pattern
class Sfizz::Impl : public SfizzImpl {};

Sfizz::Sfizz() : pImpl(new Impl()) {}
Sfizz::~Sfizz() { delete pImpl; }

bool Sfizz::loadSfzFile(const std::string& path) {
    pImpl->isLoaded.store(false, std::memory_order_relaxed);
    return false;
}

bool Sfizz::loadSfzString(const std::string& path, const std::string& text) {
    pImpl->isLoaded.store(false, std::memory_order_relaxed);
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
    pImpl->sampleRate.store(sampleRate, std::memory_order_relaxed);
}

void Sfizz::setSamplesPerBlock(int samplesPerBlock) {
    pImpl->samplesPerBlock.store(samplesPerBlock, std::memory_order_relaxed);
}

void Sfizz::noteOn(int delay, int noteNumber, int velocity) {
    // Stub implementation - no-op for performance
}

void Sfizz::noteOff(int delay, int noteNumber, int velocity) {
    // Stub implementation - no-op for performance
}

void Sfizz::cc(int delay, int ccNumber, int ccValue) {
    // Stub implementation - no-op for performance
}

void Sfizz::pitchWheel(int delay, int pitch) {
    // Stub implementation - no-op for performance
}

void Sfizz::renderBlock(float** buffers, size_t numFrames, int numOutputs) {
    // High-performance stub: no locks, minimal operations
    // Fast path for silence generation
    
    if (numFrames <= SfizzImpl::MAX_BUFFER_SIZE) {
        // Use pre-zeroed buffer for small blocks (most common case)
        for (int i = 0; i < numOutputs; ++i) {
            if (buffers[i]) {
                std::memcpy(buffers[i], pImpl->zeroBuffer, numFrames * sizeof(float));
            }
        }
    } else {
        // Fallback for large blocks
        for (int i = 0; i < numOutputs; ++i) {
            if (buffers[i]) {
                std::memset(buffers[i], 0, numFrames * sizeof(float));
            }
        }
    }
}

int Sfizz::getNumRegions() const {
    return pImpl->numRegions.load(std::memory_order_relaxed);
}

} // namespace sfz