class StepSequencerState {
  final Map<int, Map<int, double>> _velocities = {};

  double? getVelocity(int step, int noteNumber) {
    return _velocities[step]?[noteNumber];
  }

  void setVelocity(int step, int noteNumber, double velocity) {
    _velocities[step] ??= {};
    _velocities[step]![noteNumber] = velocity;
  }

  void iterateEvents(
      Function(int step, int noteNumber, double velocity) callback) {
    _velocities.forEach((step, noteNumberVelocityMap) {
      noteNumberVelocityMap.forEach((noteNumber, velocity) {
        if (velocity > 0) {
          callback(step, noteNumber, velocity);
        }
      });
    });
  }
}
