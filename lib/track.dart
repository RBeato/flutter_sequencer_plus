import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;

import 'constants.dart';
import 'models/instrument.dart';
import 'models/events.dart';
import 'native_bridge.dart';
import 'sequence.dart';
import 'global_state.dart';

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
    int? id;

    // First check if the engine is actually ready
    if (!GlobalState().isEngineReady) {
      print('Engine is not ready. Cannot create track.');
      return null;
    }

    try {
      if (instrument is Sf2Instrument) {
        id = await NativeBridge.addTrackSf2(
            instrument.idOrPath, instrument.isAsset, instrument.presetIndex);
      } else if (instrument is SfzInstrument) {
        id = await NativeBridge.addTrackSfz(
            instrument.idOrPath, instrument.tuningPath);
      } else if (instrument is RuntimeSfzInstrument) {
        id = await NativeBridge.addTrackSfzString(
            instrument.sampleRoot, instrument.sfz.buildString(), null);
      } else if (instrument is AudioUnitInstrument) {
        id = await NativeBridge.addTrackAudioUnit(instrument.idOrPath);
      } else {
        throw Exception('Instrument not recognized');
      }
    } catch (e) {
      print('Error creating track: $e');
      return null;
    }

    if (id == -1 || id == null) return null;

    return Track._withId(
      sequence: sequence,
      id: id,
      instrument: instrument,
    );
  }

  /// Handles a Note On event on this track immediately.
  /// The event will not be added to this track's events.
  void startNoteNow({required int noteNumber, required double velocity}) {
    print('Track $id: Starting note $noteNumber with velocity $velocity');
    final event = MidiEvent.ofNoteOn(
      beat: 0, // Immediate processing
      noteNumber: noteNumber,
      velocity: _velocityToMidi(velocity),
    );
    
    try {
      NativeBridge.handleTrackEventsNow(id, [event]);
    } catch (e) {
      print('Error starting note: $e');
    }
  }

  /// Handles a Note Off event on this track immediately.
  /// The event will not be added to this track's events.
  void stopNoteNow({required int noteNumber}) {
    print('Track $id: Stopping note $noteNumber');
    final event = MidiEvent.ofNoteOff(
      beat: 0, // Immediate processing
      noteNumber: noteNumber,
    );
    
    try {
      NativeBridge.handleTrackEventsNow(id, [event]);
    } catch (e) {
      print('Error stopping note: $e');
    }
  }

  /// Handles a MIDI CC event on this track immediately.
  /// The event will not be added to this track's events.
  void midiCCNow({required int ccNumber, required int ccValue}) {
    print('Track $id: Sending MIDI CC $ccNumber with value $ccValue');
    final event = MidiEvent.cc(
      beat: 0, // Immediate processing
      ccNumber: ccNumber, 
      ccValue: ccValue
    );
    
    try {
      NativeBridge.handleTrackEventsNow(id, [event]);
    } catch (e) {
      print('Error sending MIDI CC: $e');
    }
  }

  /// Handles a MIDI pitch bend event on this track immediately.
  /// The event will not be added to this track's events.
  void midiPitchBendNow({required double value}) {
    print('Track $id: Sending pitch bend with value $value');
    final event = MidiEvent.pitchBend(
      beat: 0, // Immediate processing
      value: value
    );
    
    try {
      NativeBridge.handleTrackEventsNow(id, [event]);
    } catch (e) {
      print('Error sending pitch bend: $e');
    }
  }

  /// Handles a Volume Change event on this track immediately.
  /// The event will not be added to this track's events.
  void changeVolumeNow({required double volume}) {
    print('Track $id: Changing volume to $volume');
    final volumeEvent = VolumeEvent(
      beat: 0, // Immediate processing
      volume: volume
    );
    
    try {
      NativeBridge.handleTrackEventsNow(id, [volumeEvent]);
    } catch (e) {
      print('Error changing volume: $e');
    }
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

  /// Syncs events to the backend. This should be called after making changes to
  /// track events to ensure that the changes are synced immediately.
  void syncBuffer([int? absoluteStartFrame, int maxEventsToSync = BUFFER_SIZE]) {
    final position = NativeBridge.getPosition();

    if (absoluteStartFrame == null) {
      absoluteStartFrame = position;
    } else {
      absoluteStartFrame = max(absoluteStartFrame, position);
    }

    // Schedule all events
    if (sequence.isPlaying) {
      final relativeStartFrame = absoluteStartFrame - sequence.engineStartFrame;
      _scheduleEvents(relativeStartFrame, maxEventsToSync);
    } else {
      lastFrameSynced = 0;
    }
  }

  /// Triggers a sync that will fill any available space in the buffer with
  /// any un-synced events.
  void topOffBuffer() {
    // In the updated implementation, we'll simply sync all events that haven't been synced yet
    syncBuffer(lastFrameSynced + 1, BUFFER_SIZE);
  }

  /// {@macro flutter_sequencer_library_private}
  /// Clears any scheduled events in the backend.
  void clearBuffer() {
    // Clear events from a specific frame
    NativeBridge.clearTrackEvents(id, 0);
  }

  /// Resets the track by removing all scheduled events
  void resetTrack() {
    NativeBridge.resetTrack(id);
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

  /// Builds events that can be scheduled in the sequencer engine's event buffer
  /// and adds them to eventsList.
  void _scheduleEvents(int startFrame, [int maxEventsToSync = BUFFER_SIZE]) {
    final eventsToSchedule = <SchedulerEvent>[];
    
    // Find events within the relevant range that need scheduling
    for (final event in events) {
      final eventFrame = sequence.beatToFrames(event.beat);
      if (eventFrame >= startFrame && eventFrame < startFrame + maxEventsToSync) {
        // Make sure each event has the correct frame position
        event.frame = eventFrame - sequence.engineStartFrame;
        eventsToSchedule.add(event);
      }
    }
    
    if (eventsToSchedule.isNotEmpty) {
      print('Scheduling ${eventsToSchedule.length} events on track $id');
      final scheduledCount = NativeBridge.scheduleTrackEvents(id, eventsToSchedule);
      print('Successfully scheduled $scheduledCount events');
      
      // Update the last frame we synced to
      if (eventsToSchedule.isNotEmpty) {
        final lastEventBeat = eventsToSchedule.last.beat;
        lastFrameSynced = sequence.beatToFrames(lastEventBeat);
      }
    }
  }

  /// Compares two events for sorting by time.
  int _compareEvents(SchedulerEvent a, SchedulerEvent b) {
    if (a.beat < b.beat) {
      return -1;
    } else if (a.beat > b.beat) {
      return 1;
    } else {
      return 0;
    }
  }

  int _velocityToMidi(double velocity) {
    return (velocity * 127).round();
  }
}
