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
    static constexpr int32_t kBufferSizeFrames = 256;
    
    std::atomic<bool> mIsPlaying{false};
    std::thread mAudioThread;
    
    // OpenSL ES objects
    SLObjectItf mEngineObject = nullptr;
    SLEngineItf mEngineEngine = nullptr;
    SLObjectItf mOutputMixObject = nullptr;
    SLObjectItf mPlayerObject = nullptr;
    SLPlayItf mPlayerPlay = nullptr;
    SLAndroidSimpleBufferQueueItf mPlayerBufferQueue = nullptr;
    
    // Audio buffers
    static constexpr int kNumBuffers = 2;
    int16_t* mAudioBuffers[kNumBuffers];
    float* mTempFloatBuffer;  // Temporary buffer for audio rendering
    int mCurrentBuffer = 0;
    
    void audioThreadFunc();
    bool initOpenSLES();
    void cleanupOpenSLES();
    static void playerCallback(SLAndroidSimpleBufferQueueItf bq, void* context);
};

#endif //ANDROID_ENGINE_H