#include "AndroidEngine.h"
#include "../Utils/Logging.h"
#include "CallbackManager.h"
#include <chrono>
#include <memory>
#include <algorithm>
#include <cstdlib>  // For posix_memalign

#ifdef __ARM_NEON__
#include <arm_neon.h>
#endif

AndroidEngine::AndroidEngine(Dart_Port sampleRateCallbackPort) {
    mSchedulerMixer.setChannelCount(kChannelCount);
    
    // Allocate aligned audio buffers for optimal SIMD performance
    const size_t bufferSize = kBufferSizeFrames * kChannelCount;
    for (int i = 0; i < kNumBuffers; ++i) {
        // Use aligned allocation for SIMD optimization
        if (posix_memalign(reinterpret_cast<void**>(&mAudioBuffers[i]), 
                          32, bufferSize * sizeof(int16_t)) != 0) {
            LOGE("Failed to allocate aligned audio buffer %d", i);
            // Fallback to regular allocation
            mAudioBuffers[i] = new int16_t[bufferSize];
        }
        memset(mAudioBuffers[i], 0, bufferSize * sizeof(int16_t));
    }
    
    // Allocate aligned temporary float buffer for audio rendering
    if (posix_memalign(reinterpret_cast<void**>(&mTempFloatBuffer), 
                      32, bufferSize * sizeof(float)) != 0) {
        LOGE("Failed to allocate aligned float buffer");
        // Fallback to regular allocation
        mTempFloatBuffer = new float[bufferSize];
    }
    memset(mTempFloatBuffer, 0, bufferSize * sizeof(float));
    
    // Initialize OpenSL ES with performance settings
    if (!initOpenSLES()) {
        LOGE("Failed to initialize OpenSL ES, falling back to simulation mode");
    }
    
    // Notify Dart about sample rate
    callbackToDartInt32(sampleRateCallbackPort, kSampleRate);
    
    LOGI("AndroidEngine initialized: %dHz, %d channels, %d frames buffer (optimized)", 
         kSampleRate, kChannelCount, kBufferSizeFrames);
}

AndroidEngine::~AndroidEngine() {
    pause();
    cleanupOpenSLES();
    
    // Clean up aligned audio buffers
    for (int i = 0; i < kNumBuffers; ++i) {
        if (mAudioBuffers[i]) {
            free(mAudioBuffers[i]);  // Use free() for posix_memalign allocated memory
            mAudioBuffers[i] = nullptr;
        }
    }
    
    if (mTempFloatBuffer) {
        free(mTempFloatBuffer);  // Use free() for posix_memalign allocated memory
        mTempFloatBuffer = nullptr;
    }
    
    if (mAudioThread.joinable()) {
        mAudioThread.join();
    }
    
    // Log performance statistics
    uint64_t totalFrames = mTotalFrames.load();
    uint64_t droppedFrames = mDroppedFrames.load();
    if (totalFrames > 0) {
        double dropRate = (double)droppedFrames / totalFrames * 100.0;
        LOGI("Audio performance: %.2f%% dropped frames (%llu/%llu)", 
             dropRate, droppedFrames, totalFrames);
    }
}

int32_t AndroidEngine::getSampleRate() {
    return kSampleRate;
}

int32_t AndroidEngine::getChannelCount() {
    return kChannelCount;
}

int32_t AndroidEngine::getBufferSize() {
    return kBufferSizeFrames;
}

void AndroidEngine::play() {
    mSchedulerMixer.play();
    
    if (!mIsPlaying.load()) {
        mIsPlaying.store(true);
        
        if (mPlayerPlay != nullptr) {
            // Start OpenSL ES player
            SLresult result = (*mPlayerPlay)->SetPlayState(mPlayerPlay, SL_PLAYSTATE_PLAYING);
            if (SL_RESULT_SUCCESS != result) {
                LOGE("Failed to start OpenSL ES player");
            }
        } else {
            // Fallback to simulation thread
            mAudioThread = std::thread(&AndroidEngine::audioThreadFunc, this);
        }
        
        LOGI("Audio playback started");
    }
}

void AndroidEngine::pause() {
    mSchedulerMixer.pause();
    mIsPlaying.store(false);
    
    if (mPlayerPlay != nullptr) {
        // Stop OpenSL ES player
        SLresult result = (*mPlayerPlay)->SetPlayState(mPlayerPlay, SL_PLAYSTATE_PAUSED);
        if (SL_RESULT_SUCCESS != result) {
            LOGE("Failed to pause OpenSL ES player");
        }
    }
    
    LOGI("Audio playback paused");
}

bool AndroidEngine::initOpenSLES() {
    SLresult result;
    
    // Create engine
    result = slCreateEngine(&mEngineObject, 0, nullptr, 0, nullptr, nullptr);
    if (SL_RESULT_SUCCESS != result) {
        LOGE("Failed to create OpenSL ES engine");
        return false;
    }
    
    // Realize the engine
    result = (*mEngineObject)->Realize(mEngineObject, SL_BOOLEAN_FALSE);
    if (SL_RESULT_SUCCESS != result) {
        LOGE("Failed to realize OpenSL ES engine");
        return false;
    }
    
    // Get the engine interface
    result = (*mEngineObject)->GetInterface(mEngineObject, SL_IID_ENGINE, &mEngineEngine);
    if (SL_RESULT_SUCCESS != result) {
        LOGE("Failed to get OpenSL ES engine interface");
        return false;
    }
    
    // Create output mix
    result = (*mEngineEngine)->CreateOutputMix(mEngineEngine, &mOutputMixObject, 0, nullptr, nullptr);
    if (SL_RESULT_SUCCESS != result) {
        LOGE("Failed to create OpenSL ES output mix");
        return false;
    }
    
    // Realize the output mix
    result = (*mOutputMixObject)->Realize(mOutputMixObject, SL_BOOLEAN_FALSE);
    if (SL_RESULT_SUCCESS != result) {
        LOGE("Failed to realize OpenSL ES output mix");
        return false;
    }
    
    // Configure audio source
    SLDataLocator_AndroidSimpleBufferQueue loc_bufq = {SL_DATALOCATOR_ANDROIDSIMPLEBUFFERQUEUE, kNumBuffers};
    SLDataFormat_PCM format_pcm = {
        SL_DATAFORMAT_PCM,
        kChannelCount,
        SL_SAMPLINGRATE_44_1,
        SL_PCMSAMPLEFORMAT_FIXED_16,
        SL_PCMSAMPLEFORMAT_FIXED_16,
        SL_SPEAKER_FRONT_LEFT | SL_SPEAKER_FRONT_RIGHT,
        SL_BYTEORDER_LITTLEENDIAN
    };
    SLDataSource audioSrc = {&loc_bufq, &format_pcm};
    
    // Configure audio sink
    SLDataLocator_OutputMix loc_outmix = {SL_DATALOCATOR_OUTPUTMIX, mOutputMixObject};
    SLDataSink audioSnk = {&loc_outmix, nullptr};
    
    // Create audio player
    const SLInterfaceID ids[1] = {SL_IID_BUFFERQUEUE};
    const SLboolean req[1] = {SL_BOOLEAN_TRUE};
    result = (*mEngineEngine)->CreateAudioPlayer(mEngineEngine, &mPlayerObject, &audioSrc, &audioSnk, 1, ids, req);
    if (SL_RESULT_SUCCESS != result) {
        LOGE("Failed to create OpenSL ES audio player");
        return false;
    }
    
    // Realize the player
    result = (*mPlayerObject)->Realize(mPlayerObject, SL_BOOLEAN_FALSE);
    if (SL_RESULT_SUCCESS != result) {
        LOGE("Failed to realize OpenSL ES audio player");
        return false;
    }
    
    // Get the play interface
    result = (*mPlayerObject)->GetInterface(mPlayerObject, SL_IID_PLAY, &mPlayerPlay);
    if (SL_RESULT_SUCCESS != result) {
        LOGE("Failed to get OpenSL ES play interface");
        return false;
    }
    
    // Get the buffer queue interface
    result = (*mPlayerObject)->GetInterface(mPlayerObject, SL_IID_BUFFERQUEUE, &mPlayerBufferQueue);
    if (SL_RESULT_SUCCESS != result) {
        LOGE("Failed to get OpenSL ES buffer queue interface");
        return false;
    }
    
    // Register callback
    result = (*mPlayerBufferQueue)->RegisterCallback(mPlayerBufferQueue, playerCallback, this);
    if (SL_RESULT_SUCCESS != result) {
        LOGE("Failed to register OpenSL ES callback");
        return false;
    }
    
    // Queue initial buffers to start the stream
    for (int i = 0; i < kNumBuffers; ++i) {
        playerCallback(mPlayerBufferQueue, this);
    }
    
    LOGI("OpenSL ES initialized successfully");
    return true;
}

void AndroidEngine::cleanupOpenSLES() {
    // Destroy player object
    if (mPlayerObject != nullptr) {
        (*mPlayerObject)->Destroy(mPlayerObject);
        mPlayerObject = nullptr;
        mPlayerPlay = nullptr;
        mPlayerBufferQueue = nullptr;
    }
    
    // Destroy output mix object
    if (mOutputMixObject != nullptr) {
        (*mOutputMixObject)->Destroy(mOutputMixObject);
        mOutputMixObject = nullptr;
    }
    
    // Destroy engine object
    if (mEngineObject != nullptr) {
        (*mEngineObject)->Destroy(mEngineObject);
        mEngineObject = nullptr;
        mEngineEngine = nullptr;
    }
}

// Optimized float to int16 conversion with SIMD-friendly operations
inline void AndroidEngine::convertFloatToInt16(const float* input, int16_t* output, int numSamples) noexcept {
    // Use restrict keyword for compiler optimization hints
    const float* __restrict__ src = input;
    int16_t* __restrict__ dst = output;
    
    // SIMD-optimized conversion when possible
    #ifdef __ARM_NEON__
    // Process 4 samples at a time with NEON
    const int vectorSamples = numSamples & ~3;  // Round down to multiple of 4
    for (int i = 0; i < vectorSamples; i += 4) {
        float32x4_t samples = vld1q_f32(&src[i]);
        
        // Clamp to [-1.0, 1.0]
        samples = vmaxq_f32(samples, vdupq_n_f32(-1.0f));
        samples = vminq_f32(samples, vdupq_n_f32(1.0f));
        
        // Scale and convert to int16
        samples = vmulq_f32(samples, vdupq_n_f32(32767.0f));
        int32x4_t int32_samples = vcvtq_s32_f32(samples);
        int16x4_t int16_samples = vmovn_s32(int32_samples);
        
        vst1_s16(&dst[i], int16_samples);
    }
    
    // Handle remaining samples
    for (int i = vectorSamples; i < numSamples; ++i) {
        float sample = src[i];
        sample = std::max(-1.0f, std::min(1.0f, sample));
        dst[i] = static_cast<int16_t>(sample * 32767.0f);
    }
    #else
    // Fallback scalar implementation
    for (int i = 0; i < numSamples; ++i) {
        float sample = src[i];
        sample = std::max(-1.0f, std::min(1.0f, sample));
        dst[i] = static_cast<int16_t>(sample * 32767.0f);
    }
    #endif
}

void AndroidEngine::playerCallback(SLAndroidSimpleBufferQueueItf bq, void* context) {
    AndroidEngine* engine = static_cast<AndroidEngine*>(context);
    
    // Performance monitoring
    engine->mTotalFrames.fetch_add(1);
    
    // Get current buffer index atomically
    int currentBufferIndex = engine->mCurrentBuffer.load();
    int16_t* int16Buffer = engine->mAudioBuffers[currentBufferIndex];
    float* floatBuffer = engine->mTempFloatBuffer;
    
    // Zero out float buffer efficiently
    const size_t floatBufferBytes = kBufferSizeFrames * kChannelCount * sizeof(float);
    memset(floatBuffer, 0, floatBufferBytes);
    
    // Only render audio if playing, otherwise send silence
    if (engine->mIsPlaying.load(std::memory_order_relaxed)) {
        try {
            // Render audio through the mixer to float buffer
            engine->mSchedulerMixer.renderAudio(floatBuffer, kBufferSizeFrames);
        } catch (const std::exception& e) {
            LOGE("Error rendering audio: %s", e.what());
            engine->mDroppedFrames.fetch_add(1);
            // Continue with silence
        }
    }
    
    // Convert float to int16 using optimized function
    const int totalSamples = kBufferSizeFrames * kChannelCount;
    engine->convertFloatToInt16(floatBuffer, int16Buffer, totalSamples);
    
    // Enqueue buffer
    SLresult result = (*bq)->Enqueue(bq, int16Buffer, 
                                    kBufferSizeFrames * kChannelCount * sizeof(int16_t));
    if (SL_RESULT_SUCCESS != result) {
        LOGE("Failed to enqueue OpenSL ES buffer, result: %d", result);
        engine->mDroppedFrames.fetch_add(1);
    }
    
    // Switch to next buffer atomically
    int nextBuffer = (currentBufferIndex + 1) % kNumBuffers;
    engine->mCurrentBuffer.store(nextBuffer, std::memory_order_relaxed);
}

void AndroidEngine::audioThreadFunc() {
    // Simple audio rendering loop (fallback when OpenSL ES fails)
    auto buffer = std::make_unique<float[]>(kBufferSizeFrames * kChannelCount);
    
    const auto frameDuration = std::chrono::microseconds(
        (kBufferSizeFrames * 1000000) / kSampleRate
    );
    
    LOGI("Audio simulation thread started");
    
    while (mIsPlaying.load()) {
        auto startTime = std::chrono::steady_clock::now();
        
        // Clear buffer
        std::fill_n(buffer.get(), kBufferSizeFrames * kChannelCount, 0.0f);
        
        // Render audio through the mixer
        mSchedulerMixer.renderAudio(buffer.get(), kBufferSizeFrames);
        
        // Note: In a real implementation, this audio would be sent to the Android audio system
        // For now, this just simulates the timing
        
        // Simple timing to approximate real-time playback
        auto elapsed = std::chrono::steady_clock::now() - startTime;
        auto sleepTime = frameDuration - elapsed;
        
        if (sleepTime > std::chrono::microseconds(0)) {
            std::this_thread::sleep_for(sleepTime);
        }
    }
    
    LOGI("Audio simulation thread stopped");
}