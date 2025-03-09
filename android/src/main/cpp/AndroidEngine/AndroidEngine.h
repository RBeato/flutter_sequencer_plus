#ifndef ANDROID_ENGINE_H
#define ANDROID_ENGINE_H

#include <oboe/Oboe.h>
#include "CallbackManager.h"
#include "IInstrument.h"
#include "../AndroidInstruments/Mixer.h"

// Fix ambiguous inheritance by inheriting from both interfaces directly
class AndroidEngine : public oboe::AudioStreamDataCallback,
                     public oboe::AudioStreamErrorCallback
{
public:
    explicit AndroidEngine(Dart_Port sampleRateCallbackPort);
    ~AndroidEngine() override;

    // AudioStreamDataCallback interface
    oboe::DataCallbackResult onAudioReady(oboe::AudioStream *oboeStream, void *audioData, int32_t numFrames) override;

    // AudioStreamErrorCallback interface
    void onErrorBeforeClose(oboe::AudioStream *audioStream, oboe::Result error) override;
    void onErrorAfterClose(oboe::AudioStream *audioStream, oboe::Result error) override;

    int32_t getSampleRate();
    int32_t getChannelCount();
    int32_t getBufferSize();
    void play();
    void pause();
    bool isPlaying() const { return mOutStream->getState() == oboe::StreamState::Started; }

    Mixer mSchedulerMixer;

private:
    void recreateStream();
    oboe::ManagedStream mOutStream;
    static int constexpr kSampleRate = 44100;
};

// Global engine instance
extern AndroidEngine *engine;

#endif // ANDROID_ENGINE_H
