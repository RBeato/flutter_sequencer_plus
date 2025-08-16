import 'dart:async';
import 'dart:ffi';
import 'dart:isolate';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart';

import 'models/events.dart';
import 'ffi/functions.dart';

/// FFI bridge to native audio engine - the actual working system
class NativeBridge {
  static DynamicLibrary? _lib;
  static bool _initialized = false;

  static late final Pointer<NativeFunction<Void Function(Int64)>> _setupEngine;
  static late final Pointer<NativeFunction<Void Function()>> _destroyEngine;
  static late final Pointer<NativeFunction<Void Function(Pointer<Utf8>, Bool, Int32, Int64)>> _addTrackSf2;
  static late final Pointer<NativeFunction<Void Function(Pointer<Utf8>, Pointer<Utf8>, Int64)>> _addTrackSfz;
  static late final Pointer<NativeFunction<Void Function(Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>, Int64)>> _addTrackSfzString;
  static late final Pointer<NativeFunction<Void Function(Uint32)>> _removeTrack;
  static late final Pointer<NativeFunction<Void Function(Uint32)>> _resetTrack;
  static late final Pointer<NativeFunction<Uint32 Function()>> _getPosition;
  static late final Pointer<NativeFunction<Float Function(Uint32)>> _getTrackVolume;
  static late final Pointer<NativeFunction<Uint64 Function()>> _getLastRenderTimeUs;
  static late final Pointer<NativeFunction<Uint32 Function(Uint32)>> _getBufferAvailableCount;
  static late final Pointer<NativeFunction<Void Function(Uint32, Pointer<Uint8>, Uint32)>> _handleEventsNow;
  static late final Pointer<NativeFunction<Uint32 Function(Uint32, Pointer<Uint8>, Uint32)>> _scheduleEvents;
  static late final Pointer<NativeFunction<Void Function(Uint32, Uint32)>> _clearEvents;
  static late final Pointer<NativeFunction<Void Function()>> _enginePlay;
  static late final Pointer<NativeFunction<Void Function()>> _enginePause;

  static void _registerDartPostCObject() {
    try {
      // Get the RegisterDart_PostCObject function from native library
      // Use a simple function pointer type that matches the C signature
      final registerFunc = _lib!.lookupFunction<
          Void Function(Pointer<Void>),
          void Function(Pointer<Void>)
      >('RegisterDart_PostCObject');

      // Get Dart's native PostCObject function pointer
      // Cast it as a simple void pointer to avoid type issues
      final postCObjectPtr = NativeApi.postCObject.cast<Void>();
      
      // Register it with our native code
      registerFunc(postCObjectPtr);
      
      print('[DEBUG] NativeBridge: Successfully registered Dart PostCObject callback');
    } catch (e) {
      print('[ERROR] NativeBridge: Failed to register Dart PostCObject: $e');
    }
  }

  static void _ensureInitialized() {
    if (_initialized) return;

    if (Platform.isIOS || Platform.isMacOS) {
      _lib = DynamicLibrary.process();
    } else if (Platform.isAndroid) {
      _lib = DynamicLibrary.open("libflutter_sequencer.so");
    } else {
      throw UnsupportedError("Platform not supported");
    }

    _setupEngine = _lib!.lookup<NativeFunction<Void Function(Int64)>>('setup_engine');
    _destroyEngine = _lib!.lookup<NativeFunction<Void Function()>>('destroy_engine');
    _addTrackSf2 = _lib!.lookup<NativeFunction<Void Function(Pointer<Utf8>, Bool, Int32, Int64)>>('add_track_sf2');
    _addTrackSfz = _lib!.lookup<NativeFunction<Void Function(Pointer<Utf8>, Pointer<Utf8>, Int64)>>('add_track_sfz');
    _addTrackSfzString = _lib!.lookup<NativeFunction<Void Function(Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>, Int64)>>('add_track_sfz_string');
    _removeTrack = _lib!.lookup<NativeFunction<Void Function(Uint32)>>('remove_track');
    _resetTrack = _lib!.lookup<NativeFunction<Void Function(Uint32)>>('reset_track');
    _getPosition = _lib!.lookup<NativeFunction<Uint32 Function()>>('get_position');
    _getTrackVolume = _lib!.lookup<NativeFunction<Float Function(Uint32)>>('get_track_volume');
    _getLastRenderTimeUs = _lib!.lookup<NativeFunction<Uint64 Function()>>('get_last_render_time_us');
    _getBufferAvailableCount = _lib!.lookup<NativeFunction<Uint32 Function(Uint32)>>('get_buffer_available_count');
    _handleEventsNow = _lib!.lookup<NativeFunction<Void Function(Uint32, Pointer<Uint8>, Uint32)>>('handle_events_now');
    _scheduleEvents = _lib!.lookup<NativeFunction<Uint32 Function(Uint32, Pointer<Uint8>, Uint32)>>('schedule_events');
    _clearEvents = _lib!.lookup<NativeFunction<Void Function(Uint32, Uint32)>>('clear_events');
    _enginePlay = _lib!.lookup<NativeFunction<Void Function()>>('engine_play');
    _enginePause = _lib!.lookup<NativeFunction<Void Function()>>('engine_pause');

    // CRITICAL: Register Dart's PostCObject function to enable FFI callbacks
    // This allows native code to send messages back to Dart
    _registerDartPostCObject();

    _initialized = true;
  }

  static Future<int> doSetup() async {
    print('[DEBUG] NativeBridge: Starting doSetup...');
    try {
      _ensureInitialized();
      print('[DEBUG] NativeBridge: FFI initialized successfully');

      final receivePort = ReceivePort();
      final setupEngine = _setupEngine.asFunction<void Function(int)>();

      print('[DEBUG] NativeBridge: Calling setup_engine FFI function...');
      setupEngine(receivePort.sendPort.nativePort);

      print('[DEBUG] NativeBridge: Waiting for sample rate callback...');
      final sampleRate = await receivePort.first.timeout(
        Duration(seconds: 5),
        onTimeout: () {
          print('[ERROR] NativeBridge: Timeout waiting for sample rate callback');
          return 44100; // Default sample rate
        },
      ) as int;
      receivePort.close();

      print('[DEBUG] NativeBridge: Received sample rate: $sampleRate');
      return sampleRate;
    } catch (e) {
      print('[ERROR] NativeBridge: doSetup failed: $e');
      rethrow;
    }
  }

  static Future<String?> normalizeAssetDir(String assetDir) async {
    // Use platform channel for asset normalization
    try {
      const channel = MethodChannel('flutter_sequencer');
      final result = await channel.invokeMethod('normalizeAssetDir', {'assetDir': assetDir});
      return result as String?;
    } catch (e) {
      print('[ERROR] Asset normalization failed: $e');
      return null;
    }
  }

  static Future<List<String>?> listAudioUnits() async {
    try {
      const channel = MethodChannel('flutter_sequencer');
      final result = await channel.invokeMethod('listAudioUnits');
      return (result as List<dynamic>?)?.cast<String>();
    } catch (e) {
      print('[ERROR] AudioUnit listing failed: $e');
      return null;
    }
  }

  static Future<int> addTrackSf2(String filename, bool isAsset, int patchNumber) async {
    _ensureInitialized();
    print('[DEBUG] NativeBridge: Adding SF2 track: $filename');

    final receivePort = ReceivePort();
    final pathPointer = filename.toNativeUtf8();
    final addTrackSf2 = _addTrackSf2.asFunction<void Function(Pointer<Utf8>, bool, int, int)>();

    addTrackSf2(pathPointer, isAsset, patchNumber, receivePort.sendPort.nativePort);

    try {
      final trackIndex = await receivePort.first.timeout(
        Duration(seconds: 10),
        onTimeout: () {
          print('[ERROR] NativeBridge: Timeout adding SF2 track: $filename');
          return -1; // Return invalid track index on timeout
        },
      ) as int;
      receivePort.close();
      malloc.free(pathPointer);
      
      // Convert max value to -1 for failure indication
      final result = trackIndex == 4294967295 ? -1 : trackIndex; // UInt32.max = 4294967295
      print('[DEBUG] NativeBridge: SF2 track added successfully: $filename -> $result');
      return result;
    } catch (e) {
      print('[ERROR] NativeBridge: Failed to add SF2 track: $filename - $e');
      receivePort.close();
      malloc.free(pathPointer);
      return -1;
    }
  }

  static Future<int> addTrackSfz(String sfzPath, String? tuningPath) async {
    _ensureInitialized();

    final receivePort = ReceivePort();
    final sfzPathPointer = sfzPath.toNativeUtf8();
    final tuningPathPointer = (tuningPath ?? "").toNativeUtf8();
    final addTrackSfz = _addTrackSfz.asFunction<void Function(Pointer<Utf8>, Pointer<Utf8>, int)>();

    addTrackSfz(sfzPathPointer, tuningPathPointer, receivePort.sendPort.nativePort);

    try {
      final trackIndex = await receivePort.first.timeout(
        Duration(seconds: 10),
        onTimeout: () {
          print('[ERROR] NativeBridge: Timeout adding SFZ track: $sfzPath');
          return -1;
        },
      ) as int;
      receivePort.close();
      malloc.free(sfzPathPointer);
      malloc.free(tuningPathPointer);

      return trackIndex;
    } catch (e) {
      print('[ERROR] NativeBridge: Failed to add SFZ track: $sfzPath - $e');
      receivePort.close();
      malloc.free(sfzPathPointer);
      malloc.free(tuningPathPointer);
      return -1;
    }
  }

  static Future<int> addTrackSfzString(
      String sampleRoot, String sfzContent, String? tuningString) async {
    _ensureInitialized();

    final receivePort = ReceivePort();
    final sampleRootPointer = sampleRoot.toNativeUtf8();
    final sfzContentPointer = sfzContent.toNativeUtf8();
    final tuningStringPointer = (tuningString ?? "").toNativeUtf8();
    final addTrackSfzString = _addTrackSfzString.asFunction<void Function(Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>, int)>();

    addTrackSfzString(sampleRootPointer, sfzContentPointer, tuningStringPointer, receivePort.sendPort.nativePort);

    try {
      final trackIndex = await receivePort.first.timeout(
        Duration(seconds: 10),
        onTimeout: () {
          print('[ERROR] NativeBridge: Timeout adding SFZ string track');
          return -1;
        },
      ) as int;
      receivePort.close();
      malloc.free(sampleRootPointer);
      malloc.free(sfzContentPointer);
      malloc.free(tuningStringPointer);

      return trackIndex;
    } catch (e) {
      print('[ERROR] NativeBridge: Failed to add SFZ string track: $e');
      receivePort.close();
      malloc.free(sampleRootPointer);
      malloc.free(sfzContentPointer);
      malloc.free(tuningStringPointer);
      return -1;
    }
  }

  static Future<int?> addTrackAudioUnit(String id) async {
    if (Platform.isAndroid) return -1;
    
    try {
      const channel = MethodChannel('flutter_sequencer');
      final result = await channel.invokeMethod('addTrackAudioUnit', {'id': id});
      return result as int?;
    } catch (e) {
      print('[ERROR] AudioUnit track creation failed: $e');
      return -1;
    }
  }

  static void removeTrack(int trackIndex) {
    _ensureInitialized();
    final removeTrack = _removeTrack.asFunction<void Function(int)>();
    removeTrack(trackIndex);
  }

  static void resetTrack(int trackIndex) {
    _ensureInitialized();
    final resetTrack = _resetTrack.asFunction<void Function(int)>();
    resetTrack(trackIndex);
  }

  static int getPosition() {
    _ensureInitialized();
    final getPosition = _getPosition.asFunction<int Function()>();
    return getPosition();
  }

  static double getTrackVolume(int trackIndex) {
    _ensureInitialized();
    final getTrackVolume = _getTrackVolume.asFunction<double Function(int)>();
    return getTrackVolume(trackIndex);
  }

  static int getLastRenderTimeUs() {
    _ensureInitialized();
    final getLastRenderTimeUs = _getLastRenderTimeUs.asFunction<int Function()>();
    return getLastRenderTimeUs();
  }

  static int getBufferAvailableCount(int trackIndex) {
    _ensureInitialized();
    final getBufferAvailableCount = _getBufferAvailableCount.asFunction<int Function(int)>();
    return getBufferAvailableCount(trackIndex);
  }

  static int handleEventsNow(int trackIndex, List<SchedulerEvent> events,
      int sampleRate, double tempo) {
    if (events.isEmpty) return 0;
    
    print('[DEBUG] NativeBridge.handleEventsNow: track=$trackIndex events=${events.length}');

    _ensureInitialized();
    final serializedData = _serializeEvents(events, sampleRate, tempo);
    final handleEventsNow = _handleEventsNow.asFunction<void Function(int, Pointer<Uint8>, int)>();

    handleEventsNow(trackIndex, serializedData.rawData, serializedData.eventCount);

    malloc.free(serializedData.rawData);
    return events.length;
  }

  static int scheduleEvents(int trackIndex, List<SchedulerEvent> events,
      int sampleRate, double tempo, int frameOffset) {
    if (events.isEmpty) return 0;

    _ensureInitialized();
    final serializedData = _serializeEvents(events, sampleRate, tempo);
    final scheduleEvents = _scheduleEvents.asFunction<int Function(int, Pointer<Uint8>, int)>();

    final result = scheduleEvents(trackIndex, serializedData.rawData, serializedData.eventCount);

    malloc.free(serializedData.rawData);
    return result;
  }

  static void clearEvents(int trackIndex, int fromTick) {
    _ensureInitialized();
    final clearEvents = _clearEvents.asFunction<void Function(int, int)>();
    clearEvents(trackIndex, fromTick);
  }

  static void play() {
    _ensureInitialized();
    final enginePlay = _enginePlay.asFunction<void Function()>();
    enginePlay();
  }

  static void pause() {
    _ensureInitialized();
    final enginePause = _enginePause.asFunction<void Function()>();
    enginePause();
  }

  static _SerializedEventData _serializeEvents(List<SchedulerEvent> events,
      int sampleRate, double tempo) {
    final eventCount = events.length;
    final bytesPerEvent = 24; // Size of SchedulerEvent in C
    final rawData = malloc.allocate<Uint8>(eventCount * bytesPerEvent);

    for (int i = 0; i < eventCount; i++) {
      final event = events[i];
      final offset = i * bytesPerEvent;

      // Serialize based on event type
      if (event is MidiEvent) {
        rawData.elementAt(offset).value = 0; // MIDI event type
        
        // Beat (double) - 8 bytes
        final beatBytes = (event.beat).toDouble();
        (rawData.cast<Double>().elementAt(offset ~/ 8 + 1)).value = beatBytes;
        
        // MIDI data - 3 bytes
        rawData.elementAt(offset + 16).value = event.midiStatus;
        rawData.elementAt(offset + 17).value = event.midiData1;
        rawData.elementAt(offset + 18).value = event.midiData2;
      } else if (event is VolumeEvent) {
        rawData.elementAt(offset).value = 1; // Volume event type
        
        // Beat (double) - 8 bytes  
        final beatBytes = (event.beat).toDouble();
        (rawData.cast<Double>().elementAt(offset ~/ 8 + 1)).value = beatBytes;
        
        // Volume (float) - 4 bytes
        (rawData.cast<Float>().elementAt((offset + 16) ~/ 4)).value = (event.volume ?? 1.0);
      }
    }

    return _SerializedEventData(rawData: rawData, eventCount: eventCount);
  }
}

class _SerializedEventData {
  final Pointer<Uint8> rawData;
  final int eventCount;

  _SerializedEventData({required this.rawData, required this.eventCount});
}
