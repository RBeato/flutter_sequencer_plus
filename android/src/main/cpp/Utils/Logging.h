#ifndef ANDROID_LOGGING_H
#define ANDROID_LOGGING_H

#include <android/log.h>

#define APP_NAME "FLUTTER_SEQUENCER"

// Info/warn logging is compiled out of release builds: __android_log_print is
// a blocking syscall and several call sites sit on or near the audio path.
// Errors are always logged.
#ifdef NDEBUG
#define LOGI(...) ((void)0)
#define LOGW(...) ((void)0)
#else
#define LOGI(...) ((void)__android_log_print(ANDROID_LOG_INFO, APP_NAME, __VA_ARGS__))
#define LOGW(...) ((void)__android_log_print(ANDROID_LOG_WARN, APP_NAME, __VA_ARGS__))
#endif
#define LOGE(...) ((void)__android_log_print(ANDROID_LOG_ERROR, APP_NAME, __VA_ARGS__))

#endif //ANDROID_LOGGING_H

