#include <thread>
#include <vector>
#include "AndroidEngine/AndroidEngine.h"
#include "AndroidInstruments/SoundFontInstrument.h"
#include "Utils/OptionArray.h"
#include "Scheduler/BaseScheduler.h"
#include "Scheduler/SchedulerEvent.h"
#include "CallbackManager/CallbackManager.h"
#include "Utils/Logging.h"

// Only include SfizzSamplerInstrument if sfizz is available
#if defined(SFIZZ_AVAILABLE) && SFIZZ_AVAILABLE
#include "IInstrument/SharedInstruments/SfizzSamplerInstrument.h"
#endif

std::unique_ptr<AndroidEngine> engine;

bool check_engine() {
    if (engine == nullptr) {
        LOGE("Engine is not set up. Ensure that setup_engine() is called before calling this method.");
        return false;
    }
    return true;
}

void setInstrumentOutputFormat(IInstrument* instrument) {
    auto sampleRate = engine->getSampleRate();
    auto channelCount = engine->getChannelCount();
    auto isStereo = channelCount > 1;

    instrument->setOutputFormat(sampleRate, isStereo);
}

extern "C" {
    __attribute__((visibility("default"))) __attribute__((used))
    void setup_engine(Dart_Port sampleRateCallbackPort) {
        engine = std::make_unique<AndroidEngine>(sampleRateCallbackPort);
    }

    __attribute__((visibility("default"))) __attribute__((used))
    void destroy_engine() {
        engine.reset();
    }

    __attribute__((visibility("default"))) __attribute__((used))
    void add_track_sf2(const char* filename, bool isAsset, int32_t presetIndex, Dart_Port callbackPort) {
        if (!check_engine()) {
            callbackToDartInt32(callbackPort, -1);
            return;
        }

        // Use a detached thread to avoid blocking the calling thread
        std::thread([=]() {
            try {
                auto sf2Instrument = std::make_unique<SoundFontInstrument>();
                setInstrumentOutputFormat(sf2Instrument.get());

                auto didLoad = sf2Instrument->loadSf2File(filename, isAsset, presetIndex);

                if (didLoad) {
                    auto trackIndex = engine->mSchedulerMixer.addTrack(sf2Instrument.release());
                    callbackToDartInt32(callbackPort, trackIndex);
                } else {
                    callbackToDartInt32(callbackPort, -1);
                }
            } catch (const std::exception& e) {
                LOGE("Error loading SF2 track: %s", e.what());
                callbackToDartInt32(callbackPort, -1);
            }
        }).detach();
    }

    __attribute__((visibility("default"))) __attribute__((used))
    void add_track_sfz(const char* filename, const char* tuningFilename, Dart_Port callbackPort) {
#if defined(SFIZZ_AVAILABLE) && SFIZZ_AVAILABLE
        if (!check_engine()) {
            callbackToDartInt32(callbackPort, -1);
            return;
        }

        std::thread([=]() {
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
            }
        }).detach();
#else
        // SFZ support not available in this build
        callbackToDartInt32(callbackPort, -1);
#endif
    }

    __attribute__((visibility("default"))) __attribute__((used))
    void add_track_sfz_string(const char* sampleRoot, const char* sfzString, const char* tuningString, Dart_Port callbackPort) {
#if defined(SFIZZ_AVAILABLE) && SFIZZ_AVAILABLE
        if (!check_engine()) {
            callbackToDartInt32(callbackPort, -1);
            return;
        }

        std::thread([=]() {
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
            }
        }).detach();
#else
        // SFZ support not available in this build
        callbackToDartInt32(callbackPort, -1);
#endif
    }

__attribute__((visibility("default"))) __attribute__((used))
    void remove_track(track_index_t trackIndex) {
        if (!check_engine()) {
            return;
        }

        engine->mSchedulerMixer.removeTrack(trackIndex);
    }

    __attribute__((visibility("default"))) __attribute__((used))
    void reset_track(track_index_t trackIndex) {
        if (!check_engine()) {
            return;
        }

        engine->mSchedulerMixer.resetTrack(trackIndex);
    }

    __attribute__((visibility("default"))) __attribute__((used))
    float get_track_volume(track_index_t trackIndex) {
        if (!check_engine()) {
            LOGI("Plugin: get_track_volume called without engine - returning default 1.0");
            return 1.0f; // Match iOS behavior - return sensible default instead of 0.0
        }

        float level = engine->mSchedulerMixer.getLevel(trackIndex);
        LOGI("Plugin: get_track_volume track=%d level=%.3f", trackIndex, level);
        return level;
    }

    __attribute__((visibility("default"))) __attribute__((used))
    int32_t get_position() {
        if (!check_engine()) {
            return 0;
        }

        return engine->mSchedulerMixer.getPosition();
    }

    __attribute__((visibility("default"))) __attribute__((used))
    uint64_t get_last_render_time_us() {
        if (!check_engine()) {
            return 0;
        }

        return engine->mSchedulerMixer.getLastRenderTimeUs();
    }

    __attribute__((visibility("default"))) __attribute__((used))
    uint32_t get_buffer_available_count(track_index_t trackIndex) {
        if (!check_engine()) {
            return 0;
        }
        return engine->mSchedulerMixer.getBufferAvailableCount(trackIndex);
    }

    __attribute__((visibility("default"))) __attribute__((used))
    void handle_events_now(track_index_t trackIndex, const uint8_t* eventData, int32_t eventsCount) {
        if (!check_engine()) {
            LOGE("Plugin: handle_events_now called without engine");
            return;
        }

        std::vector<SchedulerEvent> events(eventsCount);
        rawEventDataToEvents(eventData, eventsCount, events.data());

        // Smart logging - only log meaningful MIDI events
        int midiNoteOnCount = 0;
        int midiNoteOffCount = 0;
        int volumeEventCount = 0;
        
        for (int32_t i = 0; i < eventsCount; i++) {
            if (events[i].type == 0) { // MIDI_EVENT
                uint8_t midiStatus = events[i].data[0];
                uint8_t statusCode = midiStatus >> 4;
                if (statusCode == 0x9) midiNoteOnCount++;
                else if (statusCode == 0x8) midiNoteOffCount++;
            } else if (events[i].type == 1) { // VOLUME_EVENT
                volumeEventCount++;
            }
        }
        
        // Only log meaningful MIDI events, reduce volume spam
        if (midiNoteOnCount > 0) {
            LOGI("🎵 Track %d: %d events (NoteOn:%d, NoteOff:%d, Volume:%d)", 
                 trackIndex, eventsCount, midiNoteOnCount, midiNoteOffCount, volumeEventCount);
            
            // Log first MIDI event only for debugging
            for (int32_t i = 0; i < eventsCount && i < 1; i++) {
                if (events[i].type == 0 && events[i].data[0] != 0) { // Only log valid MIDI
                    uint8_t midiStatus = events[i].data[0];
                    uint8_t midiData1 = events[i].data[1];
                    uint8_t midiData2 = events[i].data[2];
                    LOGI("  MIDI[%d]: status=0x%02X note=%d vel=%d", i, midiStatus, midiData1, midiData2);
                }
            }
        } else if (eventsCount > 50) {
            // Only log large batches of volume events occasionally
            static int volumeLogCount = 0;
            if (++volumeLogCount % 10 == 0) {
                LOGI("🔇 Track %d: Large batch %d events (mostly volume)", trackIndex, eventsCount);
            }
        }

        engine->mSchedulerMixer.handleEventsNow(trackIndex, events.data(), eventsCount);
    }

    __attribute__((visibility("default"))) __attribute__((used))
    int32_t schedule_events(track_index_t trackIndex, const uint8_t* eventData, int32_t eventsCount) {
        if (!check_engine()) {
            return -1;
        }

        std::vector<SchedulerEvent> events(eventsCount);

        rawEventDataToEvents(eventData, eventsCount, events.data());

        return engine->mSchedulerMixer.scheduleEvents(trackIndex, events.data(), eventsCount);
    }

    __attribute__((visibility("default"))) __attribute__((used))
    void clear_events(track_index_t trackIndex, position_frame_t fromFrame) {
        if (!check_engine()) {
            return;
        }

        return engine->mSchedulerMixer.clearEvents(trackIndex, fromFrame);
    }

    __attribute__((visibility("default"))) __attribute__((used))
    void engine_play() {
        if (!check_engine()) {
            return;
        }

        engine->play();
    }

    __attribute__((visibility("default"))) __attribute__((used))
    void engine_pause() {
        if (!check_engine()) {
            return;
        }

        engine->pause();
    }
}
