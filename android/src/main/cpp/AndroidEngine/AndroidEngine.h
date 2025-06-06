#ifndef ANDROID_ENGINE_H
#define ANDROID_ENGINE_H

#include <android/log.h>
#include <thread>
#include <atomic>
#include <SLES/OpenSLES.h>
#include <SLES/OpenSLES_Android.h>
#include "CallbackManager.h"
#include "IInstrument.h"
#include "../AndroidInstruments/Mixer.h"

class AndroidEngine {
public:
    explicit AndroidEngine(Dart_Port sampleRateCallbackPort);
    ~AndroidEngine();

    int32_t getSampleRate();
    int32_t getChannelCount();
    int32_t getBufferSize();
    void play();
    void pause();

    Mixer mSchedulerMixer;
    
private:
    static constexpr int32_t kSampleRate = 44100;
    static constexpr int32_t kChannelCount = 2;
    static constexpr int32_t kBufferSizeFrames = 128;  // Reduced for lower latency
    
    std::atomic<bool> mIsPlaying{false};
    std::thread mAudioThread;
    
    // OpenSL ES objects
    SLObjectItf mEngineObject = nullptr;
    SLEngineItf mEngineEngine = nullptr;
    SLObjectItf mOutputMixObject = nullptr;
    SLObjectItf mPlayerObject = nullptr;
    SLPlayItf mPlayerPlay = nullptr;
    SLAndroidSimpleBufferQueueItf mPlayerBufferQueue = nullptr;
    
    // Audio buffers - optimized for performance
    static constexpr int kNumBuffers = 3;  // Triple buffering for better stability
    alignas(32) int16_t* mAudioBuffers[kNumBuffers];  // Aligned for SIMD operations
    alignas(32) float* mTempFloatBuffer;  // Aligned temporary buffer
    std::atomic<int> mCurrentBuffer{0};  // Atomic for thread safety
    
    // Performance monitoring
    std::atomic<uint64_t> mDroppedFrames{0};
    std::atomic<uint64_t> mTotalFrames{0};
    
    void audioThreadFunc();
    bool initOpenSLES();
    void cleanupOpenSLES();
    static void playerCallback(SLAndroidSimpleBufferQueueItf bq, void* context);
    
    // Inline performance-critical functions
    inline void convertFloatToInt16(const float* input, int16_t* output, int numSamples) noexcept;
};

#endif //ANDROID_ENGINE_H