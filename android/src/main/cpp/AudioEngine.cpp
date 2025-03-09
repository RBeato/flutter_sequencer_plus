#include <jni.h>
#include "AndroidEngine/AndroidEngine.h"
#include "Utils/Logging.h"

// Global engine instance
AndroidEngine *engine = nullptr;

extern "C"
{

    JNIEXPORT void JNICALL
    Java_com_michaeljperri_flutter_1sequencer_AudioEngine_play(JNIEnv *env, jobject thiz)
    {
        if (engine != nullptr)
        {
            engine->play();
        }
        else
        {
            LOGE("Engine is not initialized");
        }
    }

    JNIEXPORT void JNICALL
    Java_com_michaeljperri_flutter_1sequencer_AudioEngine_pause(JNIEnv *env, jobject thiz)
    {
        if (engine != nullptr)
        {
            engine->pause();
        }
        else
        {
            LOGE("Engine is not initialized");
        }
    }

    JNIEXPORT jboolean JNICALL
    Java_com_michaeljperri_flutter_1sequencer_AudioEngine_isPlaying(JNIEnv *env, jobject thiz)
    {
        if (engine != nullptr)
        {
            return static_cast<jboolean>(engine->isPlaying());
        }
        return JNI_FALSE;
    }
}