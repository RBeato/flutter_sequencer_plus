import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_sequencer/sequence.dart';
import 'package:flutter_sequencer/track.dart';
import 'package:flutter_sequencer/models/instrument.dart';
import 'package:flutter_sequencer/models/events.dart';
import '../test_helpers.dart';

void main() {
  group('Sequencer Integration', () {
    late Sequence sequence;
    
    setUp(() {
      setupTestEnvironment();
      sequence = Sequence(tempo: 120.0, endBeat: 16.0);
    });

    test('plays sequence with multiple tracks', () async {
      // Create multiple tracks with different instruments
      final instruments = [
        Sf2Instrument(path: 'drums.sf2', isAsset: false, presetIndex: 0),
        Sf2Instrument(path: 'bass.sf2', isAsset: false, presetIndex: 0),
      ];
      
      // Create tracks
      final tracks = await sequence.createTracks(instruments);
      expect(tracks, hasLength(2));
      
      // Add events to tracks
      final drumTrack = tracks[0];
      final bassTrack = tracks[1];
      
      // Add drum pattern (kick on 1 and 3, snare on 2 and 4)
      drumTrack.addEvent(MidiEvent.ofNoteOn(beat: 0.0, noteNumber: 36, velocity: 100)); // Kick
      drumTrack.addEvent(MidiEvent.ofNoteOff(beat: 0.5, noteNumber: 36, velocity: 0));
      
      drumTrack.addEvent(MidiEvent.ofNoteOn(beat: 1.0, noteNumber: 38, velocity: 100)); // Snare
      drumTrack.addEvent(MidiEvent.ofNoteOff(beat: 1.5, noteNumber: 38, velocity: 0));
      
      drumTrack.addEvent(MidiEvent.ofNoteOn(beat: 2.0, noteNumber: 36, velocity: 100)); // Kick
      drumTrack.addEvent(MidiEvent.ofNoteOff(beat: 2.5, noteNumber: 36, velocity: 0));
      
      drumTrack.addEvent(MidiEvent.ofNoteOn(beat: 3.0, noteNumber: 38, velocity: 100)); // Snare
      drumTrack.addEvent(MidiEvent.ofNoteOff(beat: 3.5, noteNumber: 38, velocity: 0));
      
      // Add bass line
      bassTrack.addEvent(MidiEvent.ofNoteOn(beat: 0.0, noteNumber: 48, velocity: 100));
      bassTrack.addEvent(MidiEvent.ofNoteOff(beat: 1.0, noteNumber: 48, velocity: 0));
      
      bassTrack.addEvent(MidiEvent.ofNoteOn(beat: 2.0, noteNumber: 50, velocity: 100));
      bassTrack.addEvent(MidiEvent.ofNoteOff(beat: 3.0, noteNumber: 50, velocity: 0));
      
      // Start playback
      sequence.play();
      expect(sequence.isPlaying, true);
      
      // Simulate some time passing
      await Future.delayed(Duration(milliseconds: 100));
      
      // Pause
      sequence.pause();
      expect(sequence.isPlaying, false);
    });

    test('handles tempo changes during playback', () async {
      final instrument = Sf2Instrument(path: 'piano.sf2', isAsset: false, presetIndex: 0);
      final tracks = await sequence.createTracks([instrument]);
      final track = tracks[0];
      
      // Add a simple note
      track.addEvent(MidiEvent.ofNoteOn(beat: 0.0, noteNumber: 60, velocity: 100));
      track.addEvent(MidiEvent.ofNoteOff(beat: 1.0, noteNumber: 60, velocity: 0));
      
      // Start playback
      sequence.play();
      
      // Change tempo during playback
      sequence.setTempo(180.0);
      expect(sequence.tempo, 180.0);
      
      // Wait a bit
      await Future.delayed(Duration(milliseconds: 100));
      
      sequence.pause();
    });

    test('handles loop mode', () async {
      final instrument = Sf2Instrument(path: 'piano.sf2', isAsset: false, presetIndex: 0);
      final tracks = await sequence.createTracks([instrument]);
      final track = tracks[0];
      
      // Add a note in the loop range
      track.addEvent(MidiEvent.ofNoteOn(beat: 1.0, noteNumber: 60, velocity: 100));
      track.addEvent(MidiEvent.ofNoteOff(beat: 1.5, noteNumber: 60, velocity: 0));
      
      // Set loop points and enable looping
      sequence.setLoopPoints(0.0, 2.0);
      sequence.setLoopOn();
      
      // Start playback
      sequence.play();
      
      // Simulate some time passing with looping
      await Future.delayed(Duration(milliseconds: 100));
      
      // Disable looping
      sequence.setLoopOff();
      
      // Clean up
      sequence.pause();
    });
  });
}
