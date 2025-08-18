import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_sequencer/track.dart';

import '../../models/step_sequencer_state.dart';

import 'volume_slider.dart';
import 'grid/grid.dart';

class DrumMachineWidget extends StatefulWidget {
  const DrumMachineWidget({
    Key? key,
    required this.track,
    required this.stepCount,
    required this.currentStep,
    required this.rowLabels,
    required this.columnPitches,
    required this.volume,
    required this.stepSequencerState,
    required this.handleVolumeChange,
    required this.handleVelocitiesChange,
  }) : super(key: key);

  final Track track;
  final int stepCount;
  final int currentStep;
  final List<String> rowLabels;
  final List<int> columnPitches;
  final double volume;
  final StepSequencerState? stepSequencerState;
  final Function(double) handleVolumeChange;
  final Function(int, int, int, double) handleVelocitiesChange;

  @override
  _DrumMachineWidgetState createState() => _DrumMachineWidgetState();
}

class _DrumMachineWidgetState extends State<DrumMachineWidget>
    with SingleTickerProviderStateMixin {
  Ticker? ticker;

  @override
  void dispose() {
    super.dispose();
  }

  double? getVelocity(int step, int col) {
    return widget.stepSequencerState!
        .getVelocity(step, widget.columnPitches[col]);
  }

  void handleVelocityChange(int col, int step, double velocity) {
    widget.handleVelocitiesChange(
        widget.track.id, step, widget.columnPitches[col], velocity);
  }

  void handleVolumeChange(double nextVolume) {
    widget.handleVolumeChange(nextVolume);
  }

  void handleNoteOn(int col) {
    widget.track
        .startNoteNow(noteNumber: widget.columnPitches[col], velocity: .75);
  }

  void handleNoteOff(int col) {
    widget.track.stopNoteNow(noteNumber: widget.columnPitches[col]);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
        padding: EdgeInsets.fromLTRB(32, 16, 32, 0),
        decoration: BoxDecoration(
          color: Colors.black54,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min, // Important: prevent infinite height
          children: [
            VolumeSlider(value: widget.volume, onChange: handleVolumeChange),
              // Grid layout - vertical (steps as rows, notes as columns)
              Container(
                height: 300, // Fixed height to prevent unbounded constraints
                child: Row(
                  children: [
                    // Step indicator column (0-based) - vertical on left
                    Container(
                      width: 40,
                      child: Column(
                        children: [
                          // Header spacer
                          Container(height: 24),
                          // Step numbers vertically
                          for (int i = 0; i < widget.stepCount; i++)
                            Expanded(
                              child: Container(
                                margin: EdgeInsets.symmetric(vertical: 1),
                                decoration: BoxDecoration(
                                  color: (i == widget.currentStep && widget.currentStep >= 0)
                                      ? Colors.cyan 
                                      : Colors.grey.withValues(alpha: 0.3),
                                  borderRadius: BorderRadius.circular(2),
                                ),
                                child: Center(
                                  child: Text(
                                    '$i',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: (i == widget.currentStep && widget.currentStep >= 0)
                                          ? Colors.black 
                                          : Colors.white70,
                                      fontWeight: (i == widget.currentStep && widget.currentStep >= 0)
                                          ? FontWeight.bold 
                                          : FontWeight.normal,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    // Main grid area
                    Expanded(
                      child: Column(
                        children: [
                          // Instrument header row - horizontal across top
                          Container(
                            padding: EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                            height: 24,
                            child: Row(
                              children: [
                                for (int col = 0; col < widget.rowLabels.length; col++)
                                  Expanded(
                                    child: Container(
                                      margin: EdgeInsets.symmetric(horizontal: 1),
                                      child: Center(
                                        child: Text(
                                          widget.rowLabels[col],
                                          style: TextStyle(
                                            fontSize: 8,
                                            color: Colors.white70,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          // Grid component
                          Expanded(
                            child: Grid(
                                columnLabels: widget.rowLabels,
                                getVelocity: getVelocity,
                                stepCount: widget.stepCount,
                                currentStep: widget.currentStep,
                                onChange: handleVelocityChange,
                                onNoteOn: handleNoteOn,
                                onNoteOff: handleNoteOff)
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
        ));
  }
}
