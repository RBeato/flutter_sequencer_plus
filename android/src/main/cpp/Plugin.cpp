#include <thread>
#include "AndroidEngine/AndroidEngine.h"
#include "AndroidInstruments/SoundFontInstrument.h"
#include "AndroidInstruments/SfizzSamplerInstrument.h"
#include "Utils/OptionArray.h"
#include <jni.h>
#include "Utils/Logging.h"

// The global engine variable is already defined in AudioEngine.cpp
// and declared as extern in AndroidEngine.h

// Define the function pointer for Dart_PostCObject
typedef bool (*Dart_PostCObjectFn)(Dart_Port port_id, Dart_CObject *message);
Dart_PostCObjectFn Dart_PostCObject_DL;

// Initialize the function pointer
extern "C" __attribute__((visibility("default"))) __attribute__((used))
void register_post_cobject(Dart_PostCObjectFn fn) {
    Dart_PostCObject_DL = fn;
}

void check_engine()
{
    if (engine == nullptr)
    {
        throw std::runtime_error("Engine is not set up. Ensure that setup_engine() is called before calling this method.");
    }
}

void setInstrumentOutputFormat(IInstrument *instrument)
{
    auto sampleRate = engine->getSampleRate();
    auto channelCount = engine->getChannelCount();
    auto isStereo = channelCount > 1;

    instrument->setOutputFormat(sampleRate, isStereo);
}

// JNI implementation for callbacks
extern "C" {

    // JNI method for setupEngine
    JNIEXPORT jint JNICALL Java_com_michaeljperri_flutter_1sequencer_FlutterSequencerPlugin_setupEngine(
        JNIEnv *env, jobject thiz)
    {
        try {
            if (engine == nullptr) {
                // We're using 0 for the callback port since we're not using Dart callbacks here
                engine = new AndroidEngine(0);
            }
            return engine->getSampleRate();
        } catch (const std::exception& e) {
            LOGE("Error setting up engine: %s", e.what());
            return -1;
        }
    }

    // Add JNI method for handling events now
    JNIEXPORT void JNICALL Java_com_michaeljperri_flutter_1sequencer_FlutterSequencerPlugin_handleEventsNow(
        JNIEnv *env, jobject thiz, jint trackId, jbyteArray events, jint eventCount)
    {
        try {
            check_engine();
            
            // Convert Java byte array to C++ array
            jbyte* eventBytes = env->GetByteArrayElements(events, nullptr);
            SchedulerEvent nativeEvents[eventCount];
            
            // Convert raw event bytes to SchedulerEvent objects - Use the already defined function
            rawEventDataToEvents(reinterpret_cast<uint8_t*>(eventBytes), static_cast<uint32_t>(eventCount), nativeEvents);
            
            // Handle the events immediately
            engine->mSchedulerMixer.handleEventsNow(trackId, nativeEvents, eventCount);
            
            // Release the byte array
            env->ReleaseByteArrayElements(events, eventBytes, JNI_ABORT);
        } catch (const std::exception& e) {
            LOGE("Error handling events now: %s", e.what());
        }
    }
    
    // Add JNI method for scheduling events
    JNIEXPORT jint JNICALL Java_com_michaeljperri_flutter_1sequencer_FlutterSequencerPlugin_scheduleEvents(
        JNIEnv *env, jobject thiz, jint trackId, jbyteArray events, jint eventCount)
    {
        try {
            check_engine();
            
            // Convert Java byte array to C++ array
            jbyte* eventBytes = env->GetByteArrayElements(events, nullptr);
            SchedulerEvent nativeEvents[eventCount];
            
            // Convert raw event bytes to SchedulerEvent objects
            rawEventDataToEvents(reinterpret_cast<uint8_t*>(eventBytes), static_cast<uint32_t>(eventCount), nativeEvents);
            
            // Schedule the events
            int result = engine->mSchedulerMixer.scheduleEvents(trackId, nativeEvents, eventCount);
            
            // Release the byte array
            env->ReleaseByteArrayElements(events, eventBytes, JNI_ABORT);
            
            return result;
        } catch (const std::exception& e) {
            LOGE("Error scheduling events: %s", e.what());
            return -1;
        }
    }
    
    // Add JNI method for clearing events
    JNIEXPORT void JNICALL Java_com_michaeljperri_flutter_1sequencer_FlutterSequencerPlugin_clearEvents(
        JNIEnv *env, jobject thiz, jint trackId, jint fromFrame)
    {
        try {
            check_engine();
            
            // Clear the events
            engine->mSchedulerMixer.clearEvents(trackId, fromFrame);
        } catch (const std::exception& e) {
            LOGE("Error clearing events: %s", e.what());
        }
    }
    
    // Add JNI method for adding SF2 track
    JNIEXPORT jint JNICALL Java_com_michaeljperri_flutter_1sequencer_FlutterSequencerPlugin_addTrackSf2(
        JNIEnv *env, jobject thiz, jstring path, jboolean isAsset, jint presetIndex)
    {
        try {
            check_engine();
            
            // Convert Java string to C++ string
            const char* nativePath = env->GetStringUTFChars(path, nullptr);
            
            // Create SF2 instrument
            auto sf2Instrument = new SoundFontInstrument();
            setInstrumentOutputFormat(sf2Instrument);
            
            // Load the SF2 file
            auto didLoad = sf2Instrument->loadSf2File(nativePath, isAsset, presetIndex);
            
            // Release the string
            env->ReleaseStringUTFChars(path, nativePath);
            
            if (didLoad) {
                // Add the track to the mixer
                auto trackIndex = engine->mSchedulerMixer.addTrack(sf2Instrument);
                return trackIndex;
            } else {
                // Clean up and return error
                delete sf2Instrument;
                return -1;
            }
        } catch (const std::exception& e) {
            LOGE("Error adding SF2 track: %s", e.what());
            return -1;
        }
    }

    __attribute__((visibility("default"))) __attribute__((used)) void setup_engine(Dart_Port sampleRateCallbackPort)
    {
        engine = new AndroidEngine(sampleRateCallbackPort);
    }

    __attribute__((visibility("default"))) __attribute__((used)) void destroy_engine()
    {
        delete engine;
        engine = nullptr;
    }

    __attribute__((visibility("default"))) __attribute__((used)) void add_track_sf2(const char *filename, bool isAsset, int32_t presetIndex, Dart_Port callbackPort)
    {
        check_engine();

        std::thread([=]()
                    {
                        auto sf2Instrument = new SoundFontInstrument();
                        setInstrumentOutputFormat(sf2Instrument);

                        auto didLoad = sf2Instrument->loadSf2File(filename, isAsset, presetIndex);

                        if (didLoad)
                        {
                            auto trackIndex = engine->mSchedulerMixer.addTrack(sf2Instrument);

                            callbackToDartInt32(callbackPort, trackIndex);
                        }
                        else
                        {
                            callbackToDartInt32(callbackPort, -1);
                        } })
            .detach();
    }

    __attribute__((visibility("default"))) __attribute__((used)) void add_track_sfz(const char *filename, const char *tuningFilename, Dart_Port callbackPort)
    {
        check_engine();

        std::thread([=]()
                    {
            auto sfzInstrument = new SfizzSamplerInstrument();
            setInstrumentOutputFormat(sfzInstrument);

            auto didLoad = sfzInstrument->loadSfzFile(filename, tuningFilename);

            if (didLoad) {
                auto bufferSize = engine->getBufferSize();
                sfzInstrument->setSamplesPerBlock(bufferSize);
                auto trackIndex = engine->mSchedulerMixer.addTrack(sfzInstrument);

                callbackToDartInt32(callbackPort, trackIndex);
            } else {
                callbackToDartInt32(callbackPort, -1);
            } })
            .detach();
    }

    __attribute__((visibility("default"))) __attribute__((used)) void add_track_sfz_string(const char *sampleRoot, const char *sfzString, const char *tuningString, Dart_Port callbackPort)
    {
        check_engine();

        std::thread([=]()
                    {
            auto sfzInstrument = new SfizzSamplerInstrument();
            setInstrumentOutputFormat(sfzInstrument);

            auto didLoad = sfzInstrument->loadSfzString(sampleRoot, sfzString, tuningString);

            if (didLoad) {
                auto bufferSize = engine->getBufferSize();
                sfzInstrument->setSamplesPerBlock(bufferSize);
                auto trackIndex = engine->mSchedulerMixer.addTrack(sfzInstrument);

                callbackToDartInt32(callbackPort, trackIndex);
            } else {
                callbackToDartInt32(callbackPort, -1);
            } })
            .detach();
    }

    __attribute__((visibility("default"))) __attribute__((used)) void remove_track(track_index_t trackIndex)
    {
        check_engine();

        engine->mSchedulerMixer.removeTrack(trackIndex);
    }

    __attribute__((visibility("default"))) __attribute__((used)) void reset_track(track_index_t trackIndex)
    {
        check_engine();

        engine->mSchedulerMixer.resetTrack(trackIndex);
    }

    __attribute__((visibility("default"))) __attribute__((used)) float get_track_volume(track_index_t trackIndex)
    {
        check_engine();

        return engine->mSchedulerMixer.getLevel(trackIndex);
    }

    __attribute__((visibility("default"))) __attribute__((used))
    int32_t
    get_position()
    {
        check_engine();

        return engine->mSchedulerMixer.getPosition();
    }

    __attribute__((visibility("default"))) __attribute__((used))
    uint64_t
    get_last_render_time_us()
    {
        check_engine();

        return engine->mSchedulerMixer.getLastRenderTimeUs();
    }

    __attribute__((visibility("default"))) __attribute__((used))
    uint32_t
    get_buffer_available_count(track_index_t trackIndex)
    {
        return engine->mSchedulerMixer.getBufferAvailableCount(trackIndex);
    }

    __attribute__((visibility("default"))) __attribute__((used)) void handle_events_now(track_index_t trackIndex, const uint8_t *eventData, int32_t eventsCount)
    {
        check_engine();

        SchedulerEvent events[eventsCount];

        rawEventDataToEvents(eventData, eventsCount, events);

        engine->mSchedulerMixer.handleEventsNow(trackIndex, events, eventsCount);
    }

    __attribute__((visibility("default"))) __attribute__((used))
    int32_t
    schedule_events(track_index_t trackIndex, const uint8_t *eventData, int32_t eventsCount)
    {
        check_engine();

        SchedulerEvent events[eventsCount];

        rawEventDataToEvents(eventData, eventsCount, events);

        return engine->mSchedulerMixer.scheduleEvents(trackIndex, events, eventsCount);
    }

    __attribute__((visibility("default"))) __attribute__((used)) void clear_events(track_index_t trackIndex, position_frame_t fromFrame)
    {
        check_engine();

        return engine->mSchedulerMixer.clearEvents(trackIndex, fromFrame);
    }

    __attribute__((visibility("default"))) __attribute__((used)) void engine_play()
    {
        check_engine();

        engine->play();
    }

    __attribute__((visibility("default"))) __attribute__((used)) void engine_pause()
    {
        check_engine();

        engine->pause();
    }
}
