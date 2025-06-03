#ifndef ANDROID_ENGINE_STUB_H
#define ANDROID_ENGINE_STUB_H

#include "CallbackManager.h"
#include "IInstrument.h"

// Stub implementation for compilation without full audio dependencies
class AndroidEngine {
public:
    AndroidEngine() {}
    ~AndroidEngine() {}
    
    void start() {}
    void stop() {}
    void pause() {}
    void resume() {}
    
    // Minimal interface for compilation
    bool isRunning() const { return false; }
    void setVolume(float volume) { (void)volume; }
    float getVolume() const { return 1.0f; }
};

#endif // ANDROID_ENGINE_STUB_H