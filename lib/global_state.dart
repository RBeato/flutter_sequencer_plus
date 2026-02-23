import 'dart:async';
import 'dart:developer' as developer;

import 'constants.dart';
import 'native_bridge.dart';
import 'sequence.dart';
import 'track.dart';

void _seqLog(String message) {
  if (DEBUG_SEQUENCER_LOGS) {
    developer.log(message, name: 'SEQ-Dart');
  }
}

/// A singleton that manages the global state of the sequencer engine. It is
/// responsible for setting up, starting, and stopping the engine. It also
/// maintains the timer for "topping off" the buffers.
class GlobalState {
  static final GlobalState _globalState = GlobalState._internal();

  GlobalState._internal() {
    _setupEngine();
  }

  factory GlobalState() {
    return _globalState;
  }

  var keepEngineRunning = false;
  // Native scheduling enabled for all platforms (iOS uses C++ CocoaScheduler)
  bool iosNativeSchedulingEnabled = true;
  final sequenceIdMap = <int, Sequence>{};
  int? sampleRate;
  var isEngineReady = false;
  Timer? _topOffTimer;
  int lastTickInBuffer = 0;
  final onEngineReadyCallbacks = <Function()>[];
  
  // Position tracking
  int _positionFrames = 0;
  Timer? _positionTimer;
  DateTime? _lastPositionUpdate;
  
  int get currentPosition {
    if (_lastPositionUpdate != null && _getIsPlaying()) {
      // Estimate position based on elapsed time
      final elapsed = DateTime.now().difference(_lastPositionUpdate!);
      final elapsedFrames = (elapsed.inMicroseconds * (sampleRate ?? 44100) / 1000000).round();
      return _positionFrames + elapsedFrames;
    }
    return _positionFrames;
  }
  
  void _startPositionTracking() {
    _lastPositionUpdate = DateTime.now();
    _positionTimer?.cancel();
    // PERFORMANCE: Phase 3 - Optimized to 33ms (~30fps)
    // Balances smooth UI updates with low CPU overhead
    // 30fps matches typical animation frame rate for smooth visual feedback
    _positionTimer = Timer.periodic(const Duration(milliseconds: 33), (_) {
      if (_getIsPlaying()) {
        // Read actual position from native scheduler (driven by render callbacks)
        _positionFrames = NativeBridge.getPosition();
        _lastPositionUpdate = DateTime.now();
      }
    });
  }
  
  void _stopPositionTracking() {
    _positionTimer?.cancel();
    _positionTimer = null;
  }
  
  void resetPosition() {
    _positionFrames = 0;
    _lastPositionUpdate = null;
  }

  /// Calls a function when the sequencer engine is ready. Trying to play the
  /// sequence won't do anything until the engine is ready.
  void onEngineReady(Function() callback) {
    if (isEngineReady) {
      callback();
    } else {
      onEngineReadyCallbacks.add(callback);
    }
  }

  /// Set this to true in your app's initState to leave the audio engine running
  /// even when there is no sequence playing. This may consume more energy.
  /// With this setting enabled, you can use Track.startNoteNow etc to play
  /// an instrument in real time.
  void setKeepEngineRunning(bool nextValue) {
    keepEngineRunning = nextValue;
  }

  /// Enables or disables native scheduling on iOS at runtime.
  /// When false, the library will avoid scheduling events natively on iOS
  /// (intended for Dart-dispatch mode in host apps). When true, native
  /// scheduling is used as in Android.
  void setIosNativeSchedulingEnabled(bool enabled) {
    iosNativeSchedulingEnabled = enabled;
  }

  /// {@template flutter_sequencer_library_private}
  /// For internal use only.
  /// {@endtemplate}
  /// Registers the sequence with the underlying engine.
  int registerSequence(Sequence sequence) {
    var nextId = 0;

    while (sequenceIdMap.containsKey(nextId)) {
      nextId++;
    }

    sequenceIdMap[nextId] = sequence;

    return nextId;
  }

  /// {@macro flutter_sequencer_library_private}
  /// Unregisters the sequence with the underlying engine.
  void unregisterSequence(Sequence sequence) {
    sequenceIdMap.remove(sequence.id);
  }

  /// {@macro flutter_sequencer_library_private}
  void playSequence(int? id) {
    if (!sequenceIdMap.containsKey(id)) return;
    final sequence = sequenceIdMap[id!]!;
    if (sequence.isPlaying || sequence.getIsOver()) return;

    final shouldPlayEngine = !_getIsPlaying();
    final position = NativeBridge.getPosition();

    sequence.isPlaying = true;
    sequence.engineStartFrame = LEAD_FRAMES +
        position -
        sequence.beatToFrames(sequence.pauseBeat);

    _seqLog('playSequence: id=$id, position=$position, engineStartFrame=${sequence.engineStartFrame}, pauseBeat=${sequence.pauseBeat}, shouldPlayEngine=$shouldPlayEngine');

    _syncAllBuffers();

    if (shouldPlayEngine) {
      _playEngine();
    }
  }

  /// {@macro flutter_sequencer_library_private}
  void pauseSequence(int? id) {
    if (!sequenceIdMap.containsKey(id)) return;
    final sequence = sequenceIdMap[id!]!;
    if (!sequence.isPlaying) return;
    final shouldPauseEngine = _getIsPlaying();

    sequence.pauseBeat = sequence.getBeat();
    sequence.isPlaying = false;

    _seqLog('pauseSequence: id=$id, pauseBeat=${sequence.pauseBeat}, shouldPauseEngine=$shouldPauseEngine');

    if (shouldPauseEngine) {
      _pauseEngine();
    }

    sequence.getTracks().forEach((track) {
      track.clearBuffer();
    });
  }

  /// {@macro flutter_sequencer_library_private}
  int usToFrames(int us) {
    if (sampleRate == null) return 0;
    return (us * SECONDS_PER_US * sampleRate!).round();
  }

  /// {@macro flutter_sequencer_library_private}
  int framesToUs(int frames) {
    if (sampleRate == null) return 0;
    return (frames / (SECONDS_PER_US * sampleRate!)).round();
  }

  void _setupEngine() async {
    _seqLog('_setupEngine: starting');
    try {
      sampleRate = await NativeBridge.doSetup();
      isEngineReady = true;
      _seqLog('_setupEngine: ready, sampleRate=$sampleRate');
      for (var callback in onEngineReadyCallbacks) {
        callback();
      }

      if (keepEngineRunning) {
        NativeBridge.play();
      }
    } catch (e) {
      _seqLog('_setupEngine: ERROR $e, using default sampleRate=44100');
      sampleRate = 44100;
      isEngineReady = true;
      for (var callback in onEngineReadyCallbacks) {
        callback();
      }
    }
  }

  bool _getIsPlaying() {
    return sequenceIdMap.values.any((sequence) => sequence.isPlaying);
  }

  void _playEngine() {
    _seqLog('_playEngine: keepEngineRunning=$keepEngineRunning');
    if (!keepEngineRunning) NativeBridge.play();
    _startPositionTracking();

    if (_topOffTimer != null) _topOffTimer!.cancel();
    _topOffTimer = Timer.periodic(Duration(milliseconds: TOP_OFF_PERIOD_MS), (_) {
      _topOffAllBuffers();

      for (var sequence in sequenceIdMap.values) {
        sequence.checkIsOver();
      }
    });
  }

  void _pauseEngine() {
    _seqLog('_pauseEngine: keepEngineRunning=$keepEngineRunning');
    if (!keepEngineRunning) NativeBridge.pause();

    if (_topOffTimer != null) _topOffTimer!.cancel();
    _stopPositionTracking();
  }

  /// Gets all tracks in all sequences.
  List<Track> _getAllTracks() {
    final tracks = <Track>[];

    sequenceIdMap.forEach((_, sequence) {
      sequence.getTracks().forEach((track) {
        tracks.add(track);
      });
    });

    return tracks;
  }

  /// Refills the underlying sequencer engine's event buffer to full capacity.
  void _topOffAllBuffers() {
    for (final track in _getAllTracks()) {
      track.topOffBuffer();
    }
  }

  void _syncAllBuffers(
      [int? absoluteStartFrame, int maxEventsToSync = BUFFER_SIZE]) {
    _getAllTracks().forEach((track) {
      track.syncBuffer(absoluteStartFrame, maxEventsToSync);
    });
  }
}
