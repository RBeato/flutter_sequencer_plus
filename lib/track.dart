import 'dart:io';
import 'dart:math';
import 'dart:async';
import 'dart:developer' as developer;

import 'package:path/path.dart' as p;

import 'constants.dart';
import 'models/instrument.dart';
import 'models/events.dart';
import 'models/instrument_error.dart';
import 'native_bridge.dart';
import 'sequence.dart';

void _seqLog(String message) {
  if (DEBUG_SEQUENCER_LOGS) {
    developer.log(message, name: 'SEQ-Dart');
  }
}

/// Represents a track. A track belongs to a sequence and has a collection of
/// events.
class Track {
  final Sequence sequence;
  final int id;
  final Instrument instrument;
  final events = <SchedulerEvent>[];
  int lastFrameSynced = 0;

  Track._withId(
      {required this.sequence, required this.id, required this.instrument});

  /// Creates a track in the underlying sequencer engine.
  static Future<Track?> build(
      {required Sequence sequence, required Instrument instrument}) async {
    final result = await buildWithErrorInfo(sequence: sequence, instrument: instrument);
    return result.data;
  }

  /// Creates a track with detailed error information.
  static Future<InstrumentLoadResult<Track>> buildWithErrorInfo(
      {required Sequence sequence, required Instrument instrument}) async {
    int? id;

    try {
      if (instrument is Sf2Instrument) {
        id = await NativeBridge.addTrackSf2(
            instrument.idOrPath, instrument.isAsset, instrument.presetIndex);
        
        if (id == -1) {
          return InstrumentLoadResult.error(
            InstrumentError.invalidFormat(
              instrument.idOrPath,
              'SF2 file could not be loaded. Check debug console for technical details.',
            ),
          );
        }
      } else if (instrument is SfzInstrument) {
        final sfzFile = File(instrument.idOrPath);
        String? normalizedSfzPath;

        if (instrument.isAsset) {
          final normalizedSfzDir =
              await NativeBridge.normalizeAssetDir(sfzFile.parent.path);

          if (normalizedSfzDir == null) {
            return InstrumentLoadResult.error(
              InstrumentError.assetNotFound(sfzFile.parent.path),
            );
          }
          normalizedSfzPath = '$normalizedSfzDir/${p.basename(sfzFile.path)}';
        } else {
          if (!sfzFile.existsSync()) {
            return InstrumentLoadResult.error(
              InstrumentError.fileNotFound(instrument.idOrPath),
            );
          }
          normalizedSfzPath = sfzFile.path;
        }

        id = await NativeBridge.addTrackSfz(
            normalizedSfzPath, instrument.tuningPath);
            
        if (id == -1) {
          return InstrumentLoadResult.error(
            InstrumentError.invalidFormat(
              instrument.idOrPath,
              'SFZ file could not be loaded. Check debug console for technical details.',
            ),
          );
        }
      } else if (instrument is RuntimeSfzInstrument) {
        final sfzContent = instrument.sfz.buildString();
        String? normalizedSampleRoot;

        if (instrument.isAsset) {
          normalizedSampleRoot =
              await NativeBridge.normalizeAssetDir(instrument.sampleRoot);

          if (normalizedSampleRoot == null) {
            return InstrumentLoadResult.error(
              InstrumentError.assetNotFound(instrument.sampleRoot),
            );
          }
        } else {
          final sampleDir = Directory(instrument.sampleRoot);
          if (!sampleDir.existsSync()) {
            return InstrumentLoadResult.error(
              InstrumentError.fileNotFound(instrument.sampleRoot),
            );
          }
          normalizedSampleRoot = instrument.sampleRoot;
        }

        // Sfizz uses the parent path of this (line 73 of Parser.cpp)
        final fakeSfzDir = '$normalizedSampleRoot/does_not_exist.sfz';

        id = await NativeBridge.addTrackSfzString(
            fakeSfzDir, sfzContent, instrument.tuningString);
            
        if (id == -1) {
          return InstrumentLoadResult.error(
            InstrumentError.invalidFormat(
              instrument.idOrPath,
              'Runtime SFZ could not be loaded. Check debug console for technical details.',
            ),
          );
        }
      } else if (instrument is AudioUnitInstrument) {
        id = await NativeBridge.addTrackAudioUnit(instrument.idOrPath);
        
        if (id == -1) {
          return InstrumentLoadResult.error(
            InstrumentError.invalidFormat(
              instrument.idOrPath,
              'AudioUnit could not be loaded. Check if the AudioUnit exists on this system.',
            ),
          );
        }
      } else {
        return InstrumentLoadResult.error(
          InstrumentError(
            type: InstrumentErrorType.unknown,
            message: 'Instrument type not recognized',
            technicalDetails: 'Supported types: SfzInstrument, Sf2Instrument, RuntimeSfzInstrument, AudioUnitInstrument',
          ),
        );
      }

      final track = Track._withId(
        sequence: sequence,
        id: id!,
        instrument: instrument,
      );
      
      return InstrumentLoadResult.success(track);
      
    } catch (e) {
      return InstrumentLoadResult.error(
        InstrumentError(
          type: InstrumentErrorType.unknown,
          message: 'Unexpected error during instrument loading',
          filePath: instrument.idOrPath,
          technicalDetails: e.toString(),
        ),
      );
    }
  }

  // Debounce map to prevent rapid overlapping notes
  static final Map<String, DateTime> _lastNoteTime = {};
  static const Duration _debounceMs = Duration(milliseconds: 50);

  /// Calculate shorter duration for real-time tapped notes
  /// Tapped notes should be punchy, not sustained
  double _calculateTapNoteDuration(double tempo) {
    // Doubled duration for more sustain on taps
    // Base: 0.4 beats at 120 BPM, scale with tempo (was 0.2)
    const double baseTempo = 120.0;
    const double baseDuration = 0.4; // Double the previous duration
    
    double tapDuration = (baseTempo / tempo) * baseDuration;
    
    // Clamp to doubled range: 0.1 to 0.6 beats (was 0.05-0.3)
    return tapDuration.clamp(0.1, 0.6);
  }

  /// Handles a Note On event on this track immediately.
  /// The event will not be added to this track's events.
  void startNoteNow({required int noteNumber, required double velocity}) {
    // Debounce rapid tapping to prevent audio overlapping/freezing
    final noteKey = '$id-$noteNumber';
    final now = DateTime.now();
    final lastTime = _lastNoteTime[noteKey];
    
    if (lastTime != null && now.difference(lastTime) < _debounceMs) {
      // Skip this note - too rapid
      return;
    }
    _lastNoteTime[noteKey] = now;
    
    final nextBeat = sequence.getBeat();
    final midiVelocity = _velocityToMidi(velocity);
    // Send Note ON immediately
    final noteOnEvent = MidiEvent.ofNoteOn(
        beat: nextBeat,
        noteNumber: noteNumber,
        velocity: midiVelocity);
    NativeBridge.handleEventsNow(
        id, [noteOnEvent], Sequence.globalState.sampleRate!, sequence.tempo);
    
    // Schedule automatic Note OFF for short, punchy sustain
    final tapDuration = _calculateTapNoteDuration(sequence.tempo);
    final noteOffBeat = nextBeat + tapDuration;
    
    // Use a timer to send note off after the calculated duration
    Timer(Duration(milliseconds: (tapDuration * 60000 / sequence.tempo).round()), () {
      final noteOffEvent = MidiEvent.ofNoteOff(
          beat: noteOffBeat,
          noteNumber: noteNumber);
      NativeBridge.handleEventsNow(
          id, [noteOffEvent], Sequence.globalState.sampleRate!, sequence.tempo);
    });
  }

  /// Handles a Note Off event on this track immediately.
  /// The event will not be added to this track's events.
  void stopNoteNow({required int noteNumber}) {
    final nextBeat = sequence.getBeat();
    final event = MidiEvent.ofNoteOff(beat: nextBeat, noteNumber: noteNumber);

    NativeBridge.handleEventsNow(
        id, [event], Sequence.globalState.sampleRate!, sequence.tempo);
  }

  /// Handles a MIDI CC event on this track immediately.
  /// The event will not be added to this track's events.
  void midiCCNow({required int ccNumber, required int ccValue}) {
    final nextBeat = sequence.getBeat();
    final event =
        MidiEvent.cc(beat: nextBeat, ccNumber: ccNumber, ccValue: ccValue);

    NativeBridge.handleEventsNow(
        id, [event], Sequence.globalState.sampleRate!, sequence.tempo);
  }

  /// Handles a MIDI pitch bend event on this track immediately.
  /// The event will not be added to this track's events.
  void midiPitchBendNow({required double value}) {
    final nextBeat = sequence.getBeat();
    final event = MidiEvent.pitchBend(beat: nextBeat, value: value);

    NativeBridge.handleEventsNow(
        id, [event], Sequence.globalState.sampleRate!, sequence.tempo);
  }

  /// Handles a Volume Change event on this track immediately.
  /// The event will not be added to this track's events.
  void changeVolumeNow({required double volume}) {
    final nextBeat = sequence.getBeat();
    final event = VolumeEvent(beat: nextBeat, volume: volume);

    NativeBridge.handleEventsNow(
        id, [event], Sequence.globalState.sampleRate!, sequence.tempo);
  }

  /// Adds a Note On and Note Off event to this track.
  /// This does not sync the events to the backend.
  void addNote(
      {required int noteNumber,
      required double velocity,
      required double startBeat,
      required double durationBeats}) {
    addNoteOn(
      noteNumber: noteNumber,
      velocity: velocity,
      beat: startBeat,
    );

    addNoteOff(
      noteNumber: noteNumber,
      beat: startBeat + durationBeats,
    );
  }

  /// Adds a Note On event to this track.
  /// This does not sync the events to the backend.
  void addNoteOn(
      {required int noteNumber,
      required double velocity,
      required double beat}) {
    assert(velocity > 0 && velocity <= 1);

    final noteOnEvent = MidiEvent.ofNoteOn(
      beat: beat,
      noteNumber: noteNumber,
      velocity: _velocityToMidi(velocity),
    );

    _addEvent(noteOnEvent);
  }

  /// Adds a Note Off event to this track.
  /// This does not sync the events to the backend.
  void addNoteOff({required int noteNumber, required double beat}) {
    final noteOffEvent = MidiEvent.ofNoteOff(
      beat: beat,
      noteNumber: noteNumber,
    );

    _addEvent(noteOffEvent);
  }

  /// Adds a MIDI CC event to this track.
  /// This does not sync the events to the backend.
  void addMidiCC(
      {required int ccNumber, required int ccValue, required double beat}) {
    final ccEvent =
        MidiEvent.cc(beat: beat, ccNumber: ccNumber, ccValue: ccValue);

    _addEvent(ccEvent);
  }

  /// Adds a MIDI pitch bend event to this track.
  /// The value must be between -1 and 1.
  /// This does not sync the events to the backend.
  void addMidiPitchBend({required double value, required double beat}) {
    final pitchBendEvent = MidiEvent.pitchBend(beat: beat, value: value);

    _addEvent(pitchBendEvent);
  }

  /// Adds a Volume event to this track.
  /// This does not sync the events to the backend.
  void addVolumeChange({required double volume, required double beat}) {
    final volumeChangeEvent = VolumeEvent(beat: beat, volume: volume);

    _addEvent(volumeChangeEvent);
  }

  /// Gets the current volume of the track.
  double getVolume() {
    return NativeBridge.getTrackVolume(id);
  }

  /// Clears all events on this track.
  /// This does not sync the events to the backend.
  void clearEvents() {
    events.clear();
  }

  /// Syncs events to the backend with optimized performance for loops.
  /// This should be called after making changes to track events to ensure 
  /// that the changes are synced immediately.
  void syncBuffer(
      [int? absoluteStartFrame, int maxEventsToSync = BUFFER_SIZE]) {
    final position = NativeBridge.getPosition();

    if (absoluteStartFrame == null) {
      absoluteStartFrame = position;
    } else {
      absoluteStartFrame = max(absoluteStartFrame, position);
    }

    final positionDiff = (absoluteStartFrame - lastFrameSynced).abs();

    // SEAMLESS LOOP FIX: NEVER clear events during looping to prevent audible restart
    final isLooping = sequence.loopState != LoopState.Off;
    final clearThreshold = isLooping ? 999999 : 100;

    if (positionDiff > clearThreshold && !isLooping) {
      _seqLog('syncBuffer: track $id clearing events, positionDiff=$positionDiff, startFrame=$absoluteStartFrame');
      NativeBridge.clearEvents(id, absoluteStartFrame);
    }

    if (sequence.isPlaying) {
      final relativeStartFrame = absoluteStartFrame - sequence.engineStartFrame;
      _scheduleEventsOptimized(relativeStartFrame, maxEventsToSync);
    } else {
      lastFrameSynced = 0;
    }
  }

  /// {@macro flutter_sequencer_library_private}
  /// Triggers a sync that will fill any available space in the buffer with
  /// any un-synced events.
  void topOffBuffer() {
    final bufferAvailableCount = NativeBridge.getBufferAvailableCount(id);

    if (bufferAvailableCount > 0) {
      syncBuffer(lastFrameSynced + 1, bufferAvailableCount);
    }
  }

  /// {@macro flutter_sequencer_library_private}
  /// Clears any scheduled events in the backend.
  void clearBuffer() {
    NativeBridge.clearEvents(id, 0);
  }

  /// Adds an event to the event list at the appropriate index given the sort
  /// order determined by _compareEvents.
  void _addEvent(SchedulerEvent eventToAdd) {
    int index;

    if (events.isEmpty) {
      index = 0;
    } else {
      final indexWhereResult =
          events.indexWhere((e) => _compareEvents(e, eventToAdd) == 1);

      if (indexWhereResult == -1) {
        index = events.length;
      } else {
        index = indexWhereResult;
      }
    }

    events.insert(index, eventToAdd);
  }

  /// Optimized version of _scheduleEvents with reduced loop overhead
  void _scheduleEventsOptimized(int startFrame, [int maxEventsToSync = BUFFER_SIZE]) {
    final isBeforeLoopEnd = sequence.loopState == LoopState.BeforeLoopEnd;
    
    if (!isBeforeLoopEnd) {
      if (DEBUG_SEQUENCER_LOGS) {
        _seqLog('_scheduleEventsOptimized: track $id, no loop, startFrame=$startFrame, endBeat=${sequence.endBeat}');
      }
      _scheduleEventsInRange(
          maxEventsToSync,
          startFrame,
          sequence.beatToFrames(sequence.endBeat),
          0);
      return;
    }

    // Loop case: pre-calculate values to reduce repeated calculations
    final loopLength = sequence.getLoopLengthFrames();
    final loopsElapsed = sequence.getLoopsElapsed(startFrame);
    final loopStartFrame = sequence.beatToFrames(sequence.loopStartBeat);
    final loopEndFrame = sequence.beatToFrames(sequence.loopEndBeat);

    if (DEBUG_SEQUENCER_LOGS) {
      _seqLog('_scheduleEventsOptimized: track $id, LOOP mode, loopsElapsed=$loopsElapsed, loopStart=$loopStartFrame, loopEnd=$loopEndFrame, loopLen=$loopLength');
    }

    var eventsSyncedCount = _scheduleEventsInRange(
        maxEventsToSync,
        sequence.getLoopedFrame(startFrame),
        loopEndFrame,
        loopLength * loopsElapsed);

    // OPTIMIZED: Limit loop iterations to prevent performance issues
    var loopIndex = loopsElapsed + 1;
    var lastBatchCount = 0;
    var maxLoopIterations = 10; // Safety limit to prevent infinite loops

    while (eventsSyncedCount < maxEventsToSync && maxLoopIterations > 0) {
      if (DEBUG_SEQUENCER_LOGS) {
        _seqLog('_scheduleEventsOptimized: track $id, loop iteration $loopIndex, synced=$eventsSyncedCount/$maxEventsToSync');
      }
      lastBatchCount = _scheduleEventsInRange(
          maxEventsToSync - eventsSyncedCount,
          loopStartFrame,
          loopEndFrame,
          loopLength * loopIndex);

      eventsSyncedCount += lastBatchCount;
      if (lastBatchCount == 0) break;
      loopIndex++;
      maxLoopIterations--;
    }
  }
  
  /// Legacy method redirected to optimized version
  void _scheduleEvents(int startFrame, [int maxEventsToSync = BUFFER_SIZE]) {
    _scheduleEventsOptimized(startFrame, maxEventsToSync);
  }

  int _scheduleEventsInRange(
      int maxEventsToSync, int startFrame, int? endFrame, int frameOffset) {
    final eventsToSync = <SchedulerEvent>[];
    final sampleRate = Sequence.globalState.sampleRate!;
    final tempo = sequence.tempo;

    for (var eventIndex = 0; eventIndex < events.length; eventIndex++) {
      if (eventsToSync.length >= maxEventsToSync) break;

      final event = events[eventIndex];
      final eventFrame = sequence.beatToFrames(event.beat);

      if (eventFrame < startFrame) continue;
      if (endFrame != null && eventFrame > endFrame) break;

      eventsToSync.add(event);
    }

    if (eventsToSync.isEmpty) {
      return 0;
    }

    var eventsSyncedCount = NativeBridge.scheduleEvents(
        id,
        eventsToSync,
        sampleRate,
        tempo,
        sequence.engineStartFrame + frameOffset);
    
    // ANDROID REAL-TIME EDITING FIX: If buffer is full during playback, clear old events and retry
    if (eventsSyncedCount == 0 && eventsToSync.isNotEmpty && sequence.isPlaying && Platform.isAndroid) {
      // Android buffer full, clearing and retrying
      
      // Clear events that are more than 1 second in the past to make room for new events
      final currentFrame = NativeBridge.getPosition();
      final clearBeforeFrame = currentFrame - (sampleRate * 1); // 1 second ago
      NativeBridge.clearEvents(id, clearBeforeFrame);
      
      // Retry scheduling the events
      eventsSyncedCount = NativeBridge.scheduleEvents(
          id,
          eventsToSync,
          sampleRate,
          tempo,
          sequence.engineStartFrame + frameOffset);
      // Buffer cleared, retrying events
    }

    if (eventsSyncedCount > 0) {
      final lastEvent = eventsToSync[eventsSyncedCount - 1];
      final lastEventFrame = sequence.beatToFrames(lastEvent.beat);
      lastFrameSynced = sequence.engineStartFrame + lastEventFrame + frameOffset;
      if (DEBUG_SEQUENCER_LOGS) {
        final firstEvent = eventsToSync.first;
        final firstFrame = sequence.beatToFrames(firstEvent.beat) + sequence.engineStartFrame + frameOffset;
        final lastAbs = lastEventFrame + sequence.engineStartFrame + frameOffset;
        _seqLog('_scheduleEventsInRange: track $id, synced=$eventsSyncedCount, frames=$firstFrame..$lastAbs, offset=$frameOffset');
      }
    }

    return eventsSyncedCount;
  }

  /// Used for ordering events.
  int _compareEvents(SchedulerEvent eventA, SchedulerEvent eventB) {
    final beatComparison = eventA.beat.compareTo(eventB.beat);

    if (beatComparison != 0) {
      return beatComparison;
    } else {
      // Beats are the same

      if (eventA is VolumeEvent && eventB is! VolumeEvent) {
        // Volume should come before anything else
        return -1;
      } else if (eventB is VolumeEvent && eventA is! VolumeEvent) {
        return 1;
      } else if (eventA is MidiEvent && eventB is MidiEvent) {
        // Note off should come before note on if the note is the same
        if (eventA.midiData1 == eventB.midiData1 &&
            eventA.midiStatus == MIDI_STATUS_NOTE_OFF &&
            eventB.midiStatus == MIDI_STATUS_NOTE_ON) {
          return -1;
        } else if (eventA.midiData1 == eventB.midiData1 &&
            eventA.midiStatus == MIDI_STATUS_NOTE_ON &&
            eventB.midiStatus == MIDI_STATUS_NOTE_OFF) {
          return 1;
        } else {
          return 0;
        }
      } else {
        return 0;
      }
    }
  }

  int _velocityToMidi(double velocity) {
    return (velocity * 127).round();
  }
}
