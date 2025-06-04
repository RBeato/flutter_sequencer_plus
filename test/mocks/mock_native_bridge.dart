import 'package:flutter_sequencer/native_bridge_interface.dart';
import 'package:mocktail/mocktail.dart';

class MockNativeBridge extends Mock implements NativeBridgeInterface {
  @override
  Future<int> addTrackSf2(String path, bool isAsset, int presetIndex) async {
    return 1; // Return a mock track ID
  }

  @override
  Future<int> addTrackSfz(String path, String? tuningPath) async {
    return 2; // Return a mock track ID for SFZ
  }

  @override
  Future<int> addTrackSfzString(
      String path, String sfzContent, String? tuningString) async {
    return 3; // Return a mock track ID for runtime SFZ
  }

  @override
  Future<int> addTrackAudioUnit(String idOrPath) async {
    return 4; // Return a mock track ID for AudioUnit
  }

  @override
  Future<String?> normalizeAssetDir(String path) async {
    return '/mocked/asset/path';
  }

  @override
  void removeTrack(int trackId) {
    // No-op for testing
  }

  @override
  void handleEventsNow(
      int trackId, List<dynamic> events, int sampleRate, double tempo) {
    // No-op for testing
  }

  @override
  void playSequence(int sequenceId) {
    // No-op for testing
  }

  @override
  void pauseSequence(int sequenceId) {
    // No-op for testing
  }

  @override
  void setSequenceTempo(int sequenceId, double tempo) {
    // No-op for testing
  }
}
