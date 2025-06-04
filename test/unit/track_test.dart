import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_sequencer/sequence.dart';
import 'package:flutter_sequencer/track.dart';
import 'package:flutter_sequencer/models/instrument.dart';
import 'package:flutter_sequencer/models/events.dart';
import '../test_helpers.dart';

void main() {
  group('Track', () {
    late Sequence sequence;
    late Sf2Instrument sf2Instrument;
    late SfzInstrument sfzInstrument;
    late RuntimeSfzInstrument runtimeSfzInstrument;
    
    setUp(() {
      setupTestEnvironment();
      sequence = Sequence(tempo: 120.0, endBeat: 16.0);
      sf2Instrument = Sf2Instrument(
        path: 'test_assets/test.sf2',
        isAsset: false,
        presetIndex: 0,
      );
      
      sfzInstrument = SfzInstrument(
        path: 'test_assets/test.sfz',
        isAsset: false,
      );
      
      runtimeSfzInstrument = RuntimeSfzInstrument(
        sampleRoot: 'test_assets/samples',
        isAsset: false,
        sfz: SfzContent()..addRegion(sample: 'kick.wav'),
      );
    });

    test('creates SF2 track', () async {
      final track = await Track.build(sequence: sequence, instrument: sf2Instrument);
      expect(track, isNotNull);
      expect(track?.instrument, equals(sf2Instrument));
    });

    test('creates SFZ track', () async {
      final track = await Track.build(sequence: sequence, instrument: sfzInstrument);
      expect(track, isNotNull);
      expect(track?.instrument, equals(sfzInstrument));
    });

    test('creates runtime SFZ track', () async {
      final track = await Track.build(sequence: sequence, instrument: runtimeSfzInstrument);
      expect(track, isNotNull);
      expect(track?.instrument, equals(runtimeSfzInstrument));
    });

    test('handles note on/off events', () async {
      final track = await Track.build(sequence: sequence, instrument: sf2Instrument);
      expect(track, isNotNull);
      
      // Test note on/off
      track!.startNoteNow(noteNumber: 60, velocity: 0.8);
      track.stopNoteNow(noteNumber: 60);
      
      // Verify events can be added
      final event = MidiEvent.ofNoteOn(beat: 1.0, noteNumber: 60, velocity: 100);
      track.addEvent(event);
      expect(track.events, hasLength(1));
    });

    test('handles control change events', () async {
      final track = await Track.build(sequence: sequence, instrument: sf2Instrument);
      expect(track, isNotNull);
      
      // Test control change
      track.controlChangeNow(controllerNumber: 7, value: 100);
      
      // Verify control change event can be added
      final event = MidiEvent.ofControlChange(
        beat: 1.0,
        controllerNumber: 7,
        value: 100,
      );
      track.addEvent(event);
      expect(track.events, hasLength(1));
    });

    test('handles program change events', () async {
      final track = await Track.build(sequence: sequence, instrument: sf2Instrument);
      expect(track, isNotNull);
      
      // Test program change
      track.programChangeNow(programNumber: 5);
      
      // Verify program change event can be added
      final event = MidiEvent.ofProgramChange(
        beat: 1.0,
        programNumber: 5,
      );
      track.addEvent(event);
      expect(track.events, hasLength(1));
    });

    test('clears events', () async {
      final track = await Track.build(sequence: sequence, instrument: sf2Instrument);
      expect(track, isNotNull);
      
      // Add some events
      track.addEvent(MidiEvent.ofNoteOn(beat: 1.0, noteNumber: 60, velocity: 100));
      track.addEvent(MidiEvent.ofNoteOff(beat: 2.0, noteNumber: 60, velocity: 0));
      
      // Clear events
      track.clearEvents();
      
      expect(track.events, isEmpty);
    });
  });
}
