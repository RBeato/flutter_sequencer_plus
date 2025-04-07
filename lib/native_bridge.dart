import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart';
import 'models/events.dart';
import 'global_state.dart';

// Core bridge class
class NativeBridge {
  static bool _engineReady = false;
  static bool _assetManagerReady = false;
  static double? _sampleRate;
  static bool _nativeLibraryLoaded = false;
  static DynamicLibrary? _nativeLib;
  
  static const MethodChannel _channel = MethodChannel('flutter_sequencer');
  
  // Enable detailed debugging
  static bool enableDebugLogs = true;
  
  static void debugLog(String message) {
    if (enableDebugLogs) {
      print('🔧 NativeBridge: $message');
    }
  }
  
  // Initialize native library if possible
  static void _tryLoadNativeLibrary() {
    if (_nativeLibraryLoaded) return;
    
    try {
      if (Platform.isAndroid) {
        debugLog('Attempting to load libflutter_sequencer.so');
        _nativeLib = DynamicLibrary.open('libflutter_sequencer.so');
        _nativeLibraryLoaded = true;
        debugLog('Native library loaded successfully');
      } else if (Platform.isIOS) {
        debugLog('On iOS, using DynamicLibrary.executable()');
        _nativeLib = DynamicLibrary.executable();
        _nativeLibraryLoaded = true;
        debugLog('Native library loaded successfully');
      } else {
        debugLog('Platform not supported: ${Platform.operatingSystem}');
      }
    } catch (e) {
      debugLog('❌ Error loading native library: $e');
      _nativeLibraryLoaded = false;
    }
  }
  
  // Call at app startup
  static void initialize() {
    debugLog('Initializing NativeBridge');
    _tryLoadNativeLibrary();
  }
  
  static Future<void> setupAssetManager() async {
    if (_assetManagerReady) {
      debugLog('Asset manager already ready');
      return;
    }
    
    try {
      debugLog('Setting up asset manager via method channel');
      await _channel.invokeMethod('setupAssetManager');
      debugLog('Asset manager setup successful');
      _assetManagerReady = true;
    } catch (e) {
      debugLog('❌ Error setting up asset manager: $e');
      // Continue anyway as some functionality may still work
      _assetManagerReady = true;
    }
  }

  static Future<double> setupEngine() async {
    if (_engineReady) {
      debugLog('Engine already ready with sample rate: $_sampleRate Hz');
      return _sampleRate!;
    }
    
    try {
      // Try using MethodChannel to set up the engine
      debugLog('Setting up engine via method channel');
      final int sampleRateInt = await _channel.invokeMethod('setupEngine');
      _sampleRate = sampleRateInt.toDouble();
      debugLog('Engine setup successful with sample rate: $_sampleRate Hz');
      _engineReady = true;
    } catch (e) {
      debugLog('❌ Failed to set up engine via MethodChannel: $e');
      // Fallback to a default sample rate
      _sampleRate = 44100.0;
      debugLog('Using fallback sample rate: $_sampleRate Hz');
    }
    
    _engineReady = true;
    return _sampleRate!;
  }

  static Future<void> destroyBridge() async {
    if (_nativeLibraryLoaded) {
      try {
        debugLog('Destroying engine');
        final destroyEngineFn = _nativeLib!.lookupFunction<Void Function(), void Function()>('destroy_engine');
        destroyEngineFn();
        debugLog('Engine destroyed successfully');
      } catch (e) {
        debugLog('❌ Error destroying engine: $e');
      }
    }
    _engineReady = false;
  }

  static Future<String?> normalizeAssetDir(String assetDir) async {
    try {
      debugLog('Normalizing asset directory: $assetDir');
      final String? normalized = await _channel.invokeMethod(
        'normalizeAssetDir',
        {'assetDir': assetDir},
      );
      debugLog('Asset directory normalized: $normalized');
      return normalized;
    } catch (e) {
      debugLog('❌ Error normalizing asset dir: $e');
      return null;
    }
  }

  static Future<List<String>> listAudioUnits() async {
    try {
      debugLog('Listing audio units');
      final List<dynamic> result = await _channel.invokeMethod('listAudioUnits');
      debugLog('Found ${result.length} audio units');
      return result.cast<String>();
    } catch (e) {
      debugLog('❌ Error listing audio units: $e');
      return [];
    }
  }

  static Future<int> addTrackAudioUnit(String id) async {
    try {
      debugLog('Adding audio unit track with ID: $id');
      return await _channel.invokeMethod('addTrackAudioUnit', {'id': id});
    } catch (e) {
      debugLog('❌ Error adding audio unit track: $e');
      return -1;
    }
  }

  static Future<int> addTrackSf2(String path, bool isAsset, int presetIndex) async {
    try {
      debugLog('Adding SF2 track: $path (isAsset: $isAsset, presetIndex: $presetIndex)');
      
      // First try method channel approach
      try {
        final result = await _channel.invokeMethod('addTrackSf2', {
          'path': path,
          'isAsset': isAsset,
          'presetIndex': presetIndex,
        });
        debugLog('Successfully added SF2 track via method channel with ID: $result');
        return result;
      } catch (e) {
        debugLog('Method channel approach failed: $e, trying FFI approach');
      }
      
      // FFI approach if method channel fails
      if (!_nativeLibraryLoaded) {
        debugLog('❌ Native library not loaded, cannot add SF2 track');
        return -1;
      }
      
      final completer = Completer<int>();
      final port = ReceivePort();
      
      port.listen((message) {
        completer.complete(message as int);
        port.close();
      });
      
      final allocator = Arena();
      try {
        final pathPointer = path.toNativeUtf8(allocator: allocator);
        
        final addTrackSf2Fn = _nativeLib!.lookupFunction<
          Void Function(Pointer<Utf8>, Bool, Int32, Int64),
          void Function(Pointer<Utf8>, bool, int, int)
        >('add_track_sf2');
        
        addTrackSf2Fn(pathPointer, isAsset, presetIndex, port.sendPort.nativePort);
        
        final result = await completer.future.timeout(
          const Duration(seconds: 5),
          onTimeout: () {
            debugLog('❌ Timeout while waiting for SF2 track creation');
            port.close();
            return -1;
          }
        );
        
        debugLog('Successfully added SF2 track via FFI with ID: $result');
        return result;
      } catch (e) {
        debugLog('❌ Error adding SF2 track via FFI: $e');
        port.close();
        return -1;
      } finally {
        allocator.releaseAll();
      }
    } catch (e) {
      debugLog('❌ Unexpected error adding SF2 track: $e');
      return -1;
    }
  }

  static Future<int> addTrackSfz(String sfzPath, String? tuningPath) async {
    try {
      debugLog('Adding SFZ track: $sfzPath (tuningPath: $tuningPath)');
      
      // First try method channel approach
      try {
        final result = await _channel.invokeMethod('addTrackSfz', {
          'sfzPath': sfzPath,
          'tuningPath': tuningPath,
        });
        debugLog('Successfully added SFZ track via method channel with ID: $result');
        return result;
      } catch (e) {
        debugLog('Method channel approach failed: $e, trying FFI approach');
      }
      
      // Stub implementation that reports failure
      debugLog('❌ SFZ track creation not implemented or native library not loaded');
      return -1;
    } catch (e) {
      debugLog('❌ Error adding SFZ track: $e');
      return -1;
    }
  }

  static Future<int> addTrackSfzString(String sampleRoot, String sfzString, String? tuningString) async {
    try {
      debugLog('Adding SFZ string track with sample root: $sampleRoot');
      
      // First try method channel approach
      try {
        final result = await _channel.invokeMethod('addTrackSfzString', {
          'sampleRoot': sampleRoot,
          'sfzString': sfzString,
          'tuningString': tuningString,
        });
        debugLog('Successfully added SFZ string track via method channel with ID: $result');
        return result;
      } catch (e) {
        debugLog('Method channel approach failed: $e, trying FFI approach');
      }
      
      // Stub implementation that reports failure
      debugLog('❌ SFZ string track creation not implemented or native library not loaded');
      return -1;
    } catch (e) {
      debugLog('❌ Error adding SFZ string track: $e');
      return -1;
    }
  }

  static Future<void> handleTrackEventsNow(int trackIndex, List<SchedulerEvent> events) async {
    try {
      debugLog('Handling ${events.length} events now on track $trackIndex');
      
      // Convert events to binary format
      final eventData = _convertEventsToBinary(events);
      if (eventData == null) {
        debugLog('No events to handle');
        return Future.value();
      }
      
      try {
        await _channel.invokeMethod('handleTrackEventsNow', {
          'trackId': trackIndex,
          'events': eventData,
          'eventCount': events.length,
        });
        debugLog('Successfully handled events via method channel');
        return;
      } catch (e) {
        debugLog('Method channel approach failed: $e, trying FFI approach');
      }
      
      // FFI approach if method channel fails and library is loaded
      if (_nativeLibraryLoaded) {
        try {
          final handleEventsNowFn = _nativeLib!.lookupFunction<
            Void Function(Int32, Pointer<Uint8>, Int32),
            void Function(int, Pointer<Uint8>, int)
          >('handle_events_now');
          
          final allocator = Arena();
          final eventBuffer = allocator.allocate<Uint8>(eventData.length);
          
          // Copy event data to native memory
          for (var i = 0; i < eventData.length; i++) {
            eventBuffer[i] = eventData[i];
          }
          
          // Call native function
          handleEventsNowFn(trackIndex, eventBuffer, events.length);
          
          // Clean up
          allocator.releaseAll();
          debugLog('Successfully handled events via FFI');
          return;
        } catch (e) {
          debugLog('❌ Error handling events via FFI: $e');
        }
      }
    } catch (e) {
      debugLog('❌ Error handling track events: $e');
    }
    return Future.value();
  }

  static Future<int> scheduleTrackEvents(int trackIndex, List<SchedulerEvent> events) async {
    try {
      debugLog('Scheduling ${events.length} events on track $trackIndex');
      
      // Convert events to binary format
      final eventData = _convertEventsToBinary(events);
      if (eventData == null) {
        debugLog('No events to schedule');
        return Future.value(0);
      }
      
      try {
        final result = await _channel.invokeMethod('scheduleTrackEvents', {
          'trackId': trackIndex,
          'events': eventData,
          'eventCount': events.length,
        });
        debugLog('Successfully scheduled ${result ?? 0} events via method channel');
        return result ?? 0;
      } catch (e) {
        debugLog('Method channel approach failed: $e, trying FFI approach');
      }
      
      // FFI approach if method channel fails and library is loaded
      if (_nativeLibraryLoaded) {
        try {
          final scheduleEventsFn = _nativeLib!.lookupFunction<
            Int32 Function(Int32, Pointer<Uint8>, Int32),
            int Function(int, Pointer<Uint8>, int)
          >('schedule_events');
          
          final allocator = Arena();
          final eventBuffer = allocator.allocate<Uint8>(eventData.length);
          
          // Copy event data to native memory
          for (var i = 0; i < eventData.length; i++) {
            eventBuffer[i] = eventData[i];
          }
          
          // Call native function
          final result = scheduleEventsFn(trackIndex, eventBuffer, events.length);
          
          // Clean up
          allocator.releaseAll();
          debugLog('Successfully scheduled $result events via FFI');
          return result;
        } catch (e) {
          debugLog('❌ Error scheduling events via FFI: $e');
        }
      }
    } catch (e) {
      debugLog('❌ Error scheduling track events: $e');
    }
    return Future.value(0);
  }

  static Future<void> clearTrackEvents(int trackIndex, int fromFrame) async {
    try {
      debugLog('Clearing events from frame $fromFrame on track $trackIndex');
      
      try {
        await _channel.invokeMethod('clearTrackEvents', {
          'trackId': trackIndex,
          'fromFrame': fromFrame,
        });
        debugLog('Successfully cleared events via method channel');
        return;
      } catch (e) {
        debugLog('Method channel approach failed: $e, trying FFI approach');
      }
      
      // FFI approach is a fallback and not implemented yet
      debugLog('❌ FFI approach for clearTrackEvents not implemented');
    } catch (e) {
      debugLog('❌ Error clearing track events: $e');
    }
    return Future.value();
  }

  static Future<void> play() async {
    try {
      debugLog('Playing');
      await _channel.invokeMethod('play');
      debugLog('Play command sent successfully');
    } catch (e) {
      debugLog('❌ Error playing: $e');
    }
    return Future.value();
  }

  static Future<void> pause() async {
    try {
      debugLog('Pausing');
      await _channel.invokeMethod('pause');
      debugLog('Pause command sent successfully');
    } catch (e) {
      debugLog('❌ Error pausing: $e');
    }
    return Future.value();
  }
  
  // Stub implementations for various getter methods
  static int getPosition() {
    // Stub implementation
    return 0;
  }
  
  static double getTrackVolume(int trackId) {
    // Stub implementation
    return 1.0;
  }
  
  static void resetTrack(int trackId) {
    // Stub implementation
    debugLog('Resetting track $trackId (stub implementation)');
  }
  
  static int getLastRenderTimeUs() {
    // Return current time as a fallback
    return DateTime.now().microsecondsSinceEpoch;
  }
  
  static void removeTrack(int trackId) {
    // Stub implementation
    debugLog('Removing track $trackId (stub implementation)');
  }
  
  // Helper method to convert events to binary format
  static Uint8List? _convertEventsToBinary(List<SchedulerEvent> events) {
    if (events.isEmpty) {
      return null;
    }
    
    // Calculate total size for all events
    final totalSize = events.length * SCHEDULER_EVENT_SIZE;
    final result = Uint8List(totalSize);
    final buffer = ByteData.view(result.buffer);
    
    // Get global state values
    final sampleRate = _sampleRate ?? 44100.0; // Default
    final tempo = 120.0; // Default
    final correctionFrames = 0; // Default
    
    // Convert each event
    for (var i = 0; i < events.length; i++) {
      final event = events[i];
      final eventData = event.serializeBytes(sampleRate.toInt(), tempo, correctionFrames);
      
      // Copy event data to the buffer
      for (var j = 0; j < SCHEDULER_EVENT_SIZE; j++) {
        buffer.setUint8(i * SCHEDULER_EVENT_SIZE + j, eventData.getUint8(j));
      }
    }
    
    return result;
  }
}
