abstract class NativeBridgeInterface {
  Future<int> addTrackSf2(String path, bool isAsset, int presetIndex);
  Future<int> addTrackSfz(String path, String? tuningPath);
  Future<int> addTrackSfzString(String path, String sfzContent, String? tuningString);
  Future<int> addTrackAudioUnit(String idOrPath);
  Future<String?> normalizeAssetDir(String path);
  void removeTrack(int trackId);
  void handleEventsNow(int trackId, List<dynamic> events, int sampleRate, double tempo);
  void playSequence(int sequenceId);
  void pauseSequence(int sequenceId);
  void setSequenceTempo(int sequenceId, double tempo);
}
