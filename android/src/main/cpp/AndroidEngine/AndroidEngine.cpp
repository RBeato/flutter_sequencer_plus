#include "AndroidEngine.h"
#include "../Utils/Logging.h"
#include "CallbackManager.h"
#include <chrono>
#include <memory>

AndroidEngine::AndroidEngine(Dart_Port sampleRateCallbackPort) {
    mSchedulerMixer.setChannelCount(kChannelCount);
    
    // Allocate audio buffers
    for (int i = 0; i < kNumBuffers; ++i) {
        mAudioBuffers[i] = new int16_t[kBufferSizeFrames * kChannelCount];
        memset(mAudioBuffers[i], 0, kBufferSizeFrames * kChannelCount * sizeof(int16_t));
    }
    
    // Allocate temporary float buffer for audio rendering
    mTempFloatBuffer = new float[kBufferSizeFrames * kChannelCount];
    memset(mTempFloatBuffer, 0, kBufferSizeFrames * kChannelCount * sizeof(float));
    
    // Initialize OpenSL ES
    if (!initOpenSLES()) {
        LOGE("Failed to initialize OpenSL ES, falling back to simulation mode");
    }
    
    // Notify Dart about sample rate
    callbackToDartInt32(sampleRateCallbackPort, kSampleRate);
    
    LOGI("AndroidEngine initialized: %dHz, %d channels, %d frames buffer", 
         kSampleRate, kChannelCount, kBufferSizeFrames);
}

AndroidEngine::~AndroidEngine() {
    pause();
    cleanupOpenSLES();
    
    // Clean up audio buffers
    for (int i = 0; i < kNumBuffers; ++i) {
        delete[] mAudioBuffers[i];
    }
    delete[] mTempFloatBuffer;
    
    if (mAudioThread.joinable()) {
        mAudioThread.join();
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

void AndroidEngine::playerCallback(SLAndroidSimpleBufferQueueItf bq, void* context) {
    AndroidEngine* engine = static_cast<AndroidEngine*>(context);
    
    // Get current int16 buffer and temp float buffer
    int16_t* int16Buffer = engine->mAudioBuffers[engine->mCurrentBuffer];
    float* floatBuffer = engine->mTempFloatBuffer;
    
    // Clear float buffer first
    memset(floatBuffer, 0, kBufferSizeFrames * kChannelCount * sizeof(float));
    
    // Only render audio if playing, otherwise send silence
    if (engine->mIsPlaying.load()) {
        try {
            // Render audio through the mixer to float buffer
            engine->mSchedulerMixer.renderAudio(floatBuffer, kBufferSizeFrames);
        } catch (const std::exception& e) {
            LOGE("Error rendering audio: %s", e.what());
            // Continue with silence
        }
    }
    
    // Convert float to int16 for OpenSL ES
    const int totalSamples = kBufferSizeFrames * kChannelCount;
    for (int i = 0; i < totalSamples; ++i) {
        float sample = floatBuffer[i];
        // Clamp and convert to int16
        if (sample > 1.0f) sample = 1.0f;
        if (sample < -1.0f) sample = -1.0f;
        int16Buffer[i] = static_cast<int16_t>(sample * 32767.0f);
    }
    
    // Enqueue buffer
    SLresult result = (*bq)->Enqueue(bq, int16Buffer, kBufferSizeFrames * kChannelCount * sizeof(int16_t));
    if (SL_RESULT_SUCCESS != result) {
        LOGE("Failed to enqueue OpenSL ES buffer, result: %d", result);
    }
    
    // Switch to next buffer
    engine->mCurrentBuffer = (engine->mCurrentBuffer + 1) % kNumBuffers;
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