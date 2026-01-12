import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';

/// AudioKit-based native audio engine bridge for iOS
/// Performance target: 1-3% CPU (better than Android's 3-5%)
class AudioKitBridge {
  static DynamicLibrary? _lib;
  static bool _initialized = false;

  /// Initialize the FFI library
  static void initialize() {
    if (_initialized) return;

    if (Platform.isIOS || Platform.isMacOS) {
      _lib = DynamicLibrary.process();
      _initialized = true;
      print('[AudioKitBridge] ✅ FFI library loaded');
    } else {
      throw UnsupportedError('AudioKit bridge only supported on iOS/macOS');
    }
  }

  // MARK: - FFI Function Lookups

  static late final _audiokit_engine_init = _lib!
      .lookup<NativeFunction<Double Function()>>('audiokit_engine_init')
      .asFunction<double Function()>();

  static late final _audiokit_add_track_sf2 = _lib!
      .lookup<NativeFunction<Int32 Function(Pointer<Utf8>, Int32)>>(
          'audiokit_add_track_sf2')
      .asFunction<int Function(Pointer<Utf8>, int)>();

  static late final _audiokit_remove_track = _lib!
      .lookup<NativeFunction<Void Function(Int32)>>('audiokit_remove_track')
      .asFunction<void Function(int)>();

  static late final _audiokit_schedule_event = _lib!
      .lookup<
          NativeFunction<
              Void Function(
                  Int32, Double, Bool, Uint8, Uint8)>>('audiokit_schedule_event')
      .asFunction<void Function(int, double, bool, int, int)>();

  static late final _audiokit_clear_events = _lib!
      .lookup<NativeFunction<Void Function(Int32, Double)>>(
          'audiokit_clear_events')
      .asFunction<void Function(int, double)>();

  static late final _audiokit_clear_all_events = _lib!
      .lookup<NativeFunction<Void Function(Int32)>>('audiokit_clear_all_events')
      .asFunction<void Function(int)>();

  static late final _audiokit_play = _lib!
      .lookup<NativeFunction<Void Function()>>('audiokit_play')
      .asFunction<void Function()>();

  static late final _audiokit_pause = _lib!
      .lookup<NativeFunction<Void Function()>>('audiokit_pause')
      .asFunction<void Function()>();

  static late final _audiokit_stop = _lib!
      .lookup<NativeFunction<Void Function()>>('audiokit_stop')
      .asFunction<void Function()>();

  static late final _audiokit_set_tempo = _lib!
      .lookup<NativeFunction<Void Function(Double)>>('audiokit_set_tempo')
      .asFunction<void Function(double)>();

  static late final _audiokit_get_position = _lib!
      .lookup<NativeFunction<Int32 Function()>>('audiokit_get_position')
      .asFunction<int Function()>();

  static late final _audiokit_get_beat = _lib!
      .lookup<NativeFunction<Double Function()>>('audiokit_get_beat')
      .asFunction<double Function()>();

  static late final _audiokit_get_sample_rate = _lib!
      .lookup<NativeFunction<Double Function()>>('audiokit_get_sample_rate')
      .asFunction<double Function()>();

  static late final _audiokit_get_tempo = _lib!
      .lookup<NativeFunction<Double Function()>>('audiokit_get_tempo')
      .asFunction<double Function()>();

  static late final _audiokit_set_track_volume = _lib!
      .lookup<NativeFunction<Void Function(Int32, Float)>>(
          'audiokit_set_track_volume')
      .asFunction<void Function(int, double)>();

  static late final _audiokit_set_master_volume = _lib!
      .lookup<NativeFunction<Void Function(Float)>>('audiokit_set_master_volume')
      .asFunction<void Function(double)>();

  static late final _audiokit_destroy = _lib!
      .lookup<NativeFunction<Void Function()>>('audiokit_destroy')
      .asFunction<void Function()>();

  // MARK: - Public API

  /// Initialize AudioKit engine and return sample rate
  static double initEngine() {
    initialize();
    final sampleRate = _audiokit_engine_init();
    print('[AudioKitBridge] Engine initialized: ${sampleRate}Hz');
    return sampleRate;
  }

  /// Add track with SF2 soundfont
  /// Returns trackId or -1 on failure
  static int addTrackSF2(String sf2Path, int preset) {
    final pathPtr = sf2Path.toNativeUtf8();
    try {
      final trackId = _audiokit_add_track_sf2(pathPtr, preset);
      if (trackId >= 0) {
        print('[AudioKitBridge] Track $trackId added: $sf2Path');
      } else {
        print('[AudioKitBridge] Failed to add track: $sf2Path');
      }
      return trackId;
    } finally {
      malloc.free(pathPtr);
    }
  }

  /// Remove track
  static void removeTrack(int trackId) {
    _audiokit_remove_track(trackId);
    print('[AudioKitBridge] Track $trackId removed');
  }

  /// Schedule MIDI event at specific beat
  static void scheduleEvent({
    required int trackId,
    required double beat,
    required bool noteOn,
    required int note,
    required int velocity,
  }) {
    _audiokit_schedule_event(trackId, beat, noteOn, note, velocity);
  }

  /// Clear events from specified beat onwards
  static void clearEvents(int trackId, double fromBeat) {
    _audiokit_clear_events(trackId, fromBeat);
  }

  /// Clear all events for track
  static void clearAllEvents(int trackId) {
    _audiokit_clear_all_events(trackId);
  }

  /// Start playback
  static void play() {
    _audiokit_play();
    print('[AudioKitBridge] ▶️  Playing');
  }

  /// Pause playback
  static void pause() {
    _audiokit_pause();
    print('[AudioKitBridge] ⏸️  Paused');
  }

  /// Stop playback
  static void stop() {
    _audiokit_stop();
    print('[AudioKitBridge] ⏹️  Stopped');
  }

  /// Set tempo in BPM
  static void setTempo(double bpm) {
    _audiokit_set_tempo(bpm);
    print('[AudioKitBridge] 🎵 Tempo: $bpm BPM');
  }

  /// Get current position in frames
  static int getPosition() {
    return _audiokit_get_position();
  }

  /// Get current beat
  static double getBeat() {
    return _audiokit_get_beat();
  }

  /// Get sample rate
  static double getSampleRate() {
    return _audiokit_get_sample_rate();
  }

  /// Get current tempo
  static double getTempo() {
    return _audiokit_get_tempo();
  }

  /// Set track volume (0.0 to 1.0)
  static void setTrackVolume(int trackId, double volume) {
    _audiokit_set_track_volume(trackId, volume.clamp(0.0, 1.0));
  }

  /// Set master volume (0.0 to 1.0)
  static void setMasterVolume(double volume) {
    _audiokit_set_master_volume(volume.clamp(0.0, 1.0));
  }

  /// Cleanup and destroy engine
  static void destroy() {
    _audiokit_destroy();
    print('[AudioKitBridge] Engine destroyed');
  }
}
