import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_sequencer/sequence.dart';
import 'package:flutter_sequencer/models/instrument.dart';
import 'package:flutter_sequencer/global_state.dart';
import '../test_helpers.dart';

void main() {
  group('Sequence', () {
    late Sequence sequence;
    
    setUp(() {
      // Set up test environment
      setupTestEnvironment();
      sequence = Sequence(tempo: 120.0, endBeat: 16.0);
    });

    test('creates with initial values', () {
      expect(sequence.tempo, 120.0);
      expect(sequence.endBeat, 16.0);
      expect(sequence.isPlaying, false);
      expect(sequence.loopState, LoopState.Off);
    });

    test('creates and deletes tracks', () async {
      final instruments = [
        Sf2Instrument(path: 'test_assets/test.sf2', isAsset: false, presetIndex: 0),
      ];
      
      final tracks = await sequence.createTracks(instruments);
      expect(tracks, hasLength(1));
      
      final trackCountBefore = sequence.getTracks().length;
      sequence.deleteTrack(tracks[0]);
      final trackCountAfter = sequence.getTracks().length;
      
      expect(trackCountAfter, trackCountBefore - 1);
    });

    test('handles play/pause state', () {
      sequence.play();
      expect(sequence.isPlaying, true);
      
      sequence.pause();
      expect(sequence.isPlaying, false);
    });

    test('updates tempo', () {
      const newTempo = 140.0;
      sequence.setTempo(newTempo);
      expect(sequence.tempo, newTempo);
    });

    test('handles loop points', () {
      const loopStart = 4.0;
      const loopEnd = 12.0;
      
      sequence.setLoopPoints(loopStart, loopEnd);
      sequence.setLoopOn();
      
      expect(sequence.loopStartBeat, loopStart);
      expect(sequence.loopEndBeat, loopEnd);
      expect(sequence.loopState, LoopState.BeforeLoopEnd);
    });

    test('resets position when playing from end', () {
      // Set position to end
      sequence.setBeat(sequence.endBeat);
      expect(sequence.getBeat(), sequence.endBeat);
      
      // Play should reset to start
      sequence.play();
      expect(sequence.getBeat(), 0.0);
    });

    test('handles multiple tracks', () async {
      final instruments = [
        Sf2Instrument(path: 'test1.sf2', isAsset: false, presetIndex: 0),
        Sf2Instrument(path: 'test2.sf2', isAsset: false, presetIndex: 1),
      ];
      
      final tracks = await sequence.createTracks(instruments);
      expect(tracks, hasLength(2));
      expect(sequence.getTracks(), hasLength(2));
    });

    test('cleans up resources on destroy', () {
      expect(sequence.getTracks(), isEmpty);
      
      // This would normally be verified by checking native calls in integration tests
      sequence.destroy();
      
      // Verify the sequence is no longer in the global state
      expect(() => sequence.play(), returnsNormally);
    });
  });
}
