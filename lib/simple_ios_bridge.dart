import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';

/// Simple iOS Audio Bridge - bypasses broken CocoaEngine
class SimpleIOSBridge {
  static DynamicLibrary? _lib;
  static bool _initialized = false;

  // Function signatures
  static late final _simple_engine_init = _lib!
      .lookup<NativeFunction<Double Function()>>('simple_engine_init')
      .asFunction<double Function()>();

  static late final _simple_add_track_sf2 = _lib!
      .lookup<NativeFunction<Int32 Function(Pointer<Utf8>, Int32)>>('simple_add_track_sf2')
      .asFunction<int Function(Pointer<Utf8>, int)>();

  static late final _simple_schedule_event = _lib!
      .lookup<NativeFunction<Void Function(Int32, Int32, Int32, Uint8, Uint8)>>('simple_schedule_event')
      .asFunction<void Function(int, int, int, int, int)>();

  static late final _simple_clear_events = _lib!
      .lookup<NativeFunction<Void Function(Int32, Int32)>>('simple_clear_events')
      .asFunction<void Function(int, int)>();

  static late final _simple_play = _lib!
      .lookup<NativeFunction<Void Function()>>('simple_play')
      .asFunction<void Function()>();

  static late final _simple_pause = _lib!
      .lookup<NativeFunction<Void Function()>>('simple_pause')
      .asFunction<void Function()>();

  static late final _simple_get_position = _lib!
      .lookup<NativeFunction<Int32 Function()>>('simple_get_position')
      .asFunction<int Function()>();

  static late final _simple_remove_track = _lib!
      .lookup<NativeFunction<Void Function(Int32)>>('simple_remove_track')
      .asFunction<void Function(int)>();

  /// Initialize the engine
  static Future<int> init() async {
    if (_initialized) return _lib != null ? 0 : -1;

    try {
      _lib = DynamicLibrary.process();

      final sampleRate = _simple_engine_init();
      _initialized = true;

      print('[SimpleIOSBridge] ✅ Initialized at ${sampleRate}Hz');
      return sampleRate.toInt();
    } catch (e) {
      print('[SimpleIOSBridge] ❌ Init failed: $e');
      return -1;
    }
  }

  /// Add SF2 track
  static Future<int> addTrackSf2(String path, int preset) async {
    if (!_initialized) await init();

    final pathPtr = path.toNativeUtf8();
    try {
      final trackId = _simple_add_track_sf2(pathPtr, preset);
      print('[SimpleIOSBridge] Track $trackId created from $path');
      return trackId;
    } finally {
      malloc.free(pathPtr);
    }
  }

  /// Schedule MIDI note
  static void scheduleNote({
    required int trackId,
    required int frame,
    required bool noteOn,
    required int note,
    required int velocity,
  }) {
    if (!_initialized) return;

    _simple_schedule_event(
      trackId,
      frame,
      noteOn ? 1 : 0,
      note,
      velocity,
    );
  }

  /// Clear events from frame
  static void clearEvents(int trackId, int fromFrame) {
    if (!_initialized) return;
    _simple_clear_events(trackId, fromFrame);
  }

  /// Playback controls
  static void play() {
    if (!_initialized) return;
    _simple_play();
  }

  static void pause() {
    if (!_initialized) return;
    _simple_pause();
  }

  /// Get position
  static int getPosition() {
    if (!_initialized) return 0;
    return _simple_get_position();
  }

  /// Remove track
  static void removeTrack(int trackId) {
    if (!_initialized) return;
    _simple_remove_track(trackId);
  }
}
