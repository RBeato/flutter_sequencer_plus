//
//  iOSAudioCore_C.h
//  flutter_sequencer
//
//  Pure C header for Swift bridging - exposes C API from iOSAudioCore.cpp
//

#ifndef iOSAudioCore_C_h
#define iOSAudioCore_C_h

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

// Opaque handle type for the audio core
typedef struct iOSAudioCore* iOSAudioCoreHandle;

// === Lifecycle ===

/// Creates a new audio core instance
iOSAudioCoreHandle ios_audio_core_create(void);

/// Initializes the audio engine (must be called before use)
bool ios_audio_core_initialize(iOSAudioCoreHandle handle);

/// Destroys the audio core and releases all resources
void ios_audio_core_destroy(iOSAudioCoreHandle handle);

// === Playback Control ===

/// Starts audio playback
void ios_audio_core_play(iOSAudioCoreHandle handle);

/// Pauses audio playback
void ios_audio_core_pause(iOSAudioCoreHandle handle);

/// Returns true if audio is currently playing
bool ios_audio_core_is_playing(iOSAudioCoreHandle handle);

// === Track Management ===

/// Adds a track using an SF2 file
/// Returns track index (>=0) on success, -1 on failure
int ios_audio_core_add_track_sf2(iOSAudioCoreHandle handle, const char* path, int presetIndex);

/// Removes a track by index
void ios_audio_core_remove_track(iOSAudioCoreHandle handle, int trackIndex);

/// Sets track volume (0.0 - 1.0)
void ios_audio_core_set_track_volume(iOSAudioCoreHandle handle, int trackIndex, float volume);

/// Gets track volume
float ios_audio_core_get_track_volume(iOSAudioCoreHandle handle, int trackIndex);

// === Event Scheduling ===

/// Schedules a MIDI event at a specific timestamp
/// timestamp: frame number when event should fire
/// status: MIDI status byte (0x90 = note on, 0x80 = note off)
/// data1: MIDI data byte 1 (note number)
/// data2: MIDI data byte 2 (velocity)
void ios_audio_core_schedule_event(iOSAudioCoreHandle handle, int trackIndex,
                                   int64_t timestamp, uint8_t status,
                                   uint8_t data1, uint8_t data2);

// === Position & Timing ===

/// Gets current playback position in frames
int64_t ios_audio_core_get_position(iOSAudioCoreHandle handle);

/// Gets audio engine sample rate
double ios_audio_core_get_sample_rate(iOSAudioCoreHandle handle);

#ifdef __cplusplus
}
#endif

#endif /* iOSAudioCore_C_h */
