import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';

import 'cell.dart';

class Grid extends StatelessWidget {
  Grid({
    Key? key,
    required this.getVelocity,
    required this.columnLabels,
    required this.stepCount,
    required this.currentStep,
    required this.onChange,
    required this.onNoteOn,
    required this.onNoteOff,
  }) : super(key: key);

  final Function(int step, int col) getVelocity;
  final List<String> columnLabels;
  final int stepCount;
  final int currentStep;
  final Function(int, int, double) onChange;
  final Function(int) onNoteOn;
  final Function(int) onNoteOff;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columnsCount = columnLabels.length; // Instruments as columns
        final cellSize = min(constraints.maxHeight / stepCount, 40.0);

        // Build grid with steps as rows and notes as columns (transposed)
        return Column(
          children: [
            for (var step = 0; step < stepCount; step++)
              Row(
                children: [
                  for (var col = 0; col < columnsCount; col++)
                    Expanded(
                      child: Cell(
                        size: cellSize,
                        velocity: getVelocity(step, col),
                        isCurrentStep: step == currentStep && currentStep >= 0,
                        onChange: (velocity) {
                          onChange(col, step, velocity);
                          // Trigger note playback when velocity > 0 (note added)
                          if (velocity > 0.0) {
                            onNoteOn(col);
                          }
                        },
                      ),
                    ),
                ],
              ),
          ],
        );
      },
    );
  }
}
