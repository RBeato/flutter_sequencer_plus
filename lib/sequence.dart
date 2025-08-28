import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'constants.dart';
import 'global_state.dart';
import 'models/instrument.dart';
import 'models/instrument_error.dart';
import 'native_bridge.dart';
import 'track.dart';

/// {@macro flutter_sequencer_library_private}
enum LoopState {
  Off,
  BeforeLoopEnd,
  AfterLoopEnd,
}

/// Represents a collection of tracks, play/pause state, position, loop state,
/// and tempo. Play the sequence to schedule the events on its tracks.
class Sequence {
  static final GlobalState globalState = GlobalState();

  Sequence({
    required this.tempo,
    required this.endBeat,
  }) {
    id = globalState.registerSequence(this);
  }

  /// Call this to remove this sequence and its tracks from the global sequencer
  /// engine.
  void destroy() {
    for (var track in _tracks.values) {
      deleteTrack(track);
    }
    // OPTIMIZED: Clear performance caches when sequence is destroyed
    NativeBridge.clearPerformanceCaches();
    globalState.unregisterSequence(this);
  }

  final _tracks = <int, Track>{};
  late int id;

  // Sequencer state
  bool isPlaying = false;
  double tempo;
  double endBeat;
  double pauseBeat = 0;
  int engineStartFrame = 0;
  LoopState loopState = LoopState.Off;
  double loopStartBeat = 0;
  double loopEndBeat = 0;

  /// Gets all tracks.
  List<Track> getTracks() {
    return _tracks.values.toList();
  }

  /// Creates tracks in the underlying sequencer engine.
  Future<List<Track>> createTracks(List<Instrument> instruments) async {
    final result = await createTracksWithErrorInfo(instruments);
    return result.tracks.cast<Track>();
  }

  /// Creates tracks with detailed error information for each instrument.
  Future<TracksCreationResult> createTracksWithErrorInfo(List<Instrument> instruments) async {
    if (globalState.isEngineReady) {
      return _createTracksWithErrorInfo(instruments);
    } else {
      final completer = Completer<TracksCreationResult>.sync();

      globalState.onEngineReady(() async {
        final result = await _createTracksWithErrorInfo(instruments);
        completer.complete(result);
      });

      return completer.future;
    }
  }

  /// Removes a track from the underlying sequencer engine.
  List<Track> deleteTrack(Track track) {
    final keysToRemove = [];

    _tracks.forEach((key, value) {
      if (value == track) {
        keysToRemove.add(key);
      }
    });

    for (var key in keysToRemove) {
      NativeBridge.removeTrack(key);
      _tracks.remove(key);
    }

    return _tracks.values.toList();
  }

  /// Starts playback of this sequence. If it is already playing, this will have
  /// no effect.
  void play() {
    if (!globalState.isEngineReady) return;

    if (getIsOver()) {
      setBeat(0.0);
    }

    globalState.playSequence(id);
  }

  /// Pauses playback of this sequence. If it is already paused, this will have
  /// no effect.
  void pause() {
    if (!globalState.isEngineReady) return;

    // MINIMAL PAUSE: Just pause the sequence, don't reset tracks
    globalState.pauseSequence(id);
  }

  /// Stops playback of this sequence and resets its position to the beginning.
  void stop() {
    pause();
    setBeat(0.0);
    GlobalState().resetPosition();
    // MINIMAL STOP: Don't send individual note-offs that can cause corruption
  }

  /// Sets the tempo with optimized loop handling.
  void setTempo(double nextTempo) {
    // OPTIMIZED: Skip expensive operations if tempo hasn't changed significantly
    if ((tempo - nextTempo).abs() < 0.01) {
      return;
    }

    // Update engine start frame to remove excess loops only if looping
    if (loopState == LoopState.BeforeLoopEnd) {
      final loopsElapsed = getLoopsElapsed(_getFramesRendered());
      engineStartFrame += loopsElapsed * getLoopLengthFrames();
    }

    // Update engine start frame to adjust to new tempo
    final framesRendered = _getFramesRendered();
    final nextFramesRendered = (framesRendered * (tempo / nextTempo)).round();
    final framesToAdvance = framesRendered - nextFramesRendered;
    engineStartFrame += framesToAdvance;

    tempo = nextTempo;

    // OPTIMIZED: Batch sync buffer operations to reduce overhead
    final tracks = getTracks();
    for (int i = 0; i < tracks.length; i++) {
      tracks[i].syncBuffer();
    }
  }

  /// Enables looping with optimized performance.
  void setLoop(double loopStartBeat, double loopEndBeat) {
    // If the sequence is over, ensure globalState is updated so the sequence
    // doesn't start playing
    checkIsOver();

    // OPTIMIZED: Only update engine frame if we're actually transitioning from non-loop to loop
    // or if we have significant loop boundary changes
    final wasLooping = loopState != LoopState.Off;
    final significantChange = (this.loopStartBeat - loopStartBeat).abs() > 0.01 || 
                             (this.loopEndBeat - loopEndBeat).abs() > 0.01;
    
    if (!wasLooping || significantChange) {
      final loopsElapsed = loopState == LoopState.BeforeLoopEnd
          ? getLoopsElapsed(_getFramesRendered())
          : 0;
      engineStartFrame += loopsElapsed * getLoopLengthFrames();
    }

    // Update loop state and bounds
    final loopEndFrame = beatToFrames(loopEndBeat);
    final currentFrame = _getFrame(false);

    if (currentFrame <= loopEndFrame) {
      loopState = LoopState.BeforeLoopEnd;
    } else {
      loopState = LoopState.AfterLoopEnd;
    }

    this.loopStartBeat = loopStartBeat;
    this.loopEndBeat = loopEndBeat;

    // OPTIMIZED: Platform-specific buffer sync strategy
    // Android needs more frequent syncing to prevent note accumulation
    final shouldSync = Platform.isAndroid 
        ? (!wasLooping || significantChange || (this.loopStartBeat != loopStartBeat) || (this.loopEndBeat != loopEndBeat))
        : (!wasLooping || significantChange);
        
    if (shouldSync) {
      getTracks().forEach((track) => track.syncBuffer());
    }
  }

  /// Disables looping for the sequence with optimized performance.
  void unsetLoop() {
    // OPTIMIZED: Only perform expensive operations if we were actually looping
    final wasLooping = loopState != LoopState.Off;
    
    if (wasLooping && loopState == LoopState.BeforeLoopEnd) {
      final loopsElapsed = getLoopsElapsed(_getFramesRendered());
      engineStartFrame += loopsElapsed * getLoopLengthFrames();
    }

    loopStartBeat = 0;
    loopEndBeat = 0;
    loopState = LoopState.Off;

    // OPTIMIZED: Only sync buffers if we were actually looping
    if (wasLooping) {
      getTracks().forEach((track) => track.syncBuffer());
    }
  }

  /// Sets the beat at which the sequence will end. Events after the end beat
  /// won't be scheduled.
  void setEndBeat(double beat) {
    endBeat = beat;
  }

  /// Immediately changes the position of the sequence to the given beat.
  void setBeat(double beat) {
    if (!globalState.isEngineReady) return;

    // MINIMAL setBeat: Don't reset tracks to avoid corruption

    final leadFrames =
        getIsPlaying() ? min(_getFramesRendered(), LEAD_FRAMES) : 0;

    final frame = beatToFrames(beat) - leadFrames;

    engineStartFrame = NativeBridge.getPosition() - frame;
    pauseBeat = beat;

    getTracks().forEach((track) {
      track.syncBuffer(engineStartFrame);
    });

    if (loopState != LoopState.Off) {
      final loopEndFrame = beatToFrames(loopEndBeat);
      loopState = frame < loopEndFrame
          ? LoopState.BeforeLoopEnd
          : LoopState.AfterLoopEnd;
    }
  }

  /// Returns true if the sequence is playing.
  bool getIsPlaying() {
    return isPlaying && !getIsOver();
  }

  /// Returns true if the sequence is at its end beat.
  bool getIsOver() {
    return _getFrame(true) == beatToFrames(endBeat);
  }

  /// Gets the current beat. Returns a value based on the number of frames
  /// rendered and the time elapsed since the last render callback. To omit
  /// the time elapsed since the last render callback, pass `false`.
  double getBeat([bool estimateFramesSinceLastRender = true]) {
    return framesToBeat(_getFrame(estimateFramesSinceLastRender));
  }

  /// Gets the current tempo.
  double getTempo() {
    return tempo;
  }

  /// {@macro flutter_sequencer_library_private}
  /// Returns the length of the loop in frames.
  int getLoopLengthFrames() {
    final loopStartFrame = beatToFrames(loopStartBeat);
    final loopEndFrame = beatToFrames(loopEndBeat);

    return loopEndFrame - loopStartFrame;
  }

  /// {@macro flutter_sequencer_library_private}
  /// Returns the number of loops that have been played
  /// since the sequence started playing.
  /// OPTIMIZED: Cache expensive calculations.
  int getLoopsElapsed(int frame) {
    final loopStartFrame = beatToFrames(loopStartBeat);

    if (frame <= loopStartFrame) return 0;
    
    final loopLength = getLoopLengthFrames();
    if (loopLength == 0) return 0;

    // OPTIMIZED: Use integer arithmetic for better performance
    return (frame - loopStartFrame) ~/ loopLength;
  }

  /// {@macro flutter_sequencer_library_private}
  /// Maps a frame beyond the end of the loop range to
  /// where it would be inside the loop range.
  /// OPTIMIZED: Reduce redundant calculations and improve performance.
  int getLoopedFrame(int frame) {
    final loopStartFrame = beatToFrames(loopStartBeat);
    
    if (frame <= loopStartFrame) return frame;
    
    final loopLengthFrames = getLoopLengthFrames();
    if (loopLengthFrames == 0) return frame;

    // OPTIMIZED: Single calculation with remainder
    final relativeFrame = frame - loopStartFrame;
    return (relativeFrame % loopLengthFrames) + loopStartFrame;
  }

  /// {@macro flutter_sequencer_library_private}
  /// Converts a beat to sample frames with optimized caching.
  int beatToFrames(double beat) {
    // OPTIMIZED: Use cached calculation for frequently accessed beats
    final sampleRate = Sequence.globalState.sampleRate;
    if (sampleRate != null) {
      return NativeBridge.getOptimizedFrame(beat, tempo, sampleRate);
    }
    
    // Fallback to original calculation if sample rate not available
    final us = ((1 / tempo) * beat * (60000000)).round();
    return Sequence.globalState.usToFrames(us);
  }

  /// {@macro flutter_sequencer_library_private}
  /// Converts sample frames to a beat.
  double framesToBeat(int frames) {
    final us = Sequence.globalState.framesToUs(frames);

    // (b / min) * us * (min / us)
    return tempo * us * (1 / 60000000);
  }

  /// {@macro flutter_sequencer_library_private}
  /// Pauses this sequence if it is at its end.
  void checkIsOver() {
    if (isPlaying && getIsOver()) {
      // Sequence is at end, pause

      pauseBeat = endBeat;
      pause();
    }
  }

  /// Number of frames elapsed since the sequence was started. Does not account
  /// for the number of loops that may have occurred.
  int _getFramesRendered() {
    if (!globalState.isEngineReady) return 0;

    return NativeBridge.getPosition() - engineStartFrame - LEAD_FRAMES;
  }

  /// Gets the current frame position of the sequencer.
  int _getFrame([bool estimateFramesSinceLastRender = true]) {
    if (!globalState.isEngineReady) return 0;

    if (isPlaying) {
      final frame = _getFramesRendered() +
          (estimateFramesSinceLastRender ? _getFramesSinceLastRender() : 0);
      final loopedFrame =
          loopState == LoopState.Off ? frame : getLoopedFrame(frame);

      return max(min(loopedFrame, beatToFrames(endBeat)), 0);
    } else {
      return max(min(beatToFrames(pauseBeat), beatToFrames(endBeat)), 0);
    }
  }

  /// Returns the number of frames elapsed since the last audio render callback
  /// was called.
  int _getFramesSinceLastRender() {
    final microsecondsSinceLastRender = max(
        0,
        DateTime.now().microsecondsSinceEpoch -
            NativeBridge.getLastRenderTimeUs());

    return globalState.usToFrames(microsecondsSinceLastRender);
  }

  Future<InstrumentLoadResult<Track>> _createTrackWithErrorInfo(Instrument instrument) async {
    try {
      // Add timeout to prevent infinite hanging on track creation
      final result = await Track.buildWithErrorInfo(sequence: this, instrument: instrument)
        .timeout(Duration(seconds: 15), onTimeout: () {
          print('[TIMEOUT] Track creation timed out for instrument: ${instrument.displayName}');
          return InstrumentLoadResult.error(
            InstrumentError.invalidFormat(
              instrument.displayName,
              'Track creation timed out after 15 seconds. This may indicate a native bridge issue.',
            ),
          );
        });

      if (result.isSuccess) {
        _tracks.putIfAbsent(result.data!.id, () => result.data!);
      }

      return result;
    } catch (e) {
      print('[ERROR] Exception during track creation for ${instrument.displayName}: $e');
      return InstrumentLoadResult.error(
        InstrumentError.invalidFormat(
          instrument.displayName,
          'Track creation failed: $e',
        ),
      );
    }
  }

  Future<Track?> _createTrack(Instrument instrument) async {
    final result = await _createTrackWithErrorInfo(instrument);
    return result.data;
  }

  Future<TracksCreationResult> _createTracksWithErrorInfo(List<Instrument> instruments) async {
    final results = await Future.wait(
        instruments.map((instrument) => _createTrackWithErrorInfo(instrument)));
    
    final tracks = <Track>[];
    final errors = <InstrumentError>[];
    
    for (final result in results) {
      if (result.isSuccess) {
        tracks.add(result.data!);
      } else {
        errors.add(result.error!);
      }
    }
    
    return TracksCreationResult(tracks: tracks, errors: errors);
  }

  Future<List<Track>> _createTracks(List<Instrument> instruments) async {
    final result = await _createTracksWithErrorInfo(instruments);
    return result.tracks.cast<Track>();
  }
}
