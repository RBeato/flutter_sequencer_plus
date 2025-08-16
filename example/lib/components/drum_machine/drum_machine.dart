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
    return Expanded(
        child: Container(
            padding: EdgeInsets.fromLTRB(32, 16, 32, 0),
            decoration: BoxDecoration(
              color: Colors.black54,
            ),
            child: Column(children: [
              VolumeSlider(value: widget.volume, onChange: handleVolumeChange),
              // Grid layout with row labels on the left
              Row(
                children: [
                  // Row labels column
                  Container(
                    width: 40,
                    child: Column(
                      children: [
                        // Header spacer
                        Container(height: 24),
                        // Row labels
                        for (int row = 0; row < widget.rowLabels.length; row++)
                          Container(
                            height: 50,
                            margin: EdgeInsets.symmetric(vertical: 1),
                            child: Center(
                              child: Text(
                                widget.rowLabels[row],
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.white70,
                                  fontWeight: FontWeight.bold,
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
                        // Step indicator header (0-based)
                        Container(
                          padding: EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                          height: 24,
                          child: Row(
                            children: [
                              for (int i = 0; i < widget.stepCount; i++)
                                Expanded(
                                  child: Container(
                                    margin: EdgeInsets.symmetric(horizontal: 1),
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
                                          fontSize: 8,
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
            ])));
  }
}
