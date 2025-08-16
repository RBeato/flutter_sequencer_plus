import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import '../../../constants.dart';

class Cell extends StatelessWidget {
  Cell({
    Key? key,
    required this.size,
    required this.velocity,
    required this.isCurrentStep,
    required this.onChange,
  }) : super(key: key);

  final double size;
  final double velocity;
  final bool isCurrentStep;
  final Function(double) onChange;

  @override
  Widget build(BuildContext context) {
    // Enhanced visual feedback for current step
    final baseColor = velocity > 0 
        ? (isCurrentStep ? Colors.lightBlue : Colors.pink)
        : (isCurrentStep ? Colors.grey.shade700 : Colors.black);
    
    final highlightColor = isCurrentStep 
        ? (velocity > 0 ? Colors.cyan : Colors.white30)
        : baseColor;
    
    final borderColor = isCurrentStep 
        ? Colors.cyan 
        : Colors.white70;
    
    final borderWidth = isCurrentStep ? 2.0 : 1.0;
    
    final box = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Color.lerp(Colors.black, highlightColor, velocity > 0 ? velocity : (isCurrentStep ? 0.3 : 0)),
        border: Border.all(color: borderColor, width: borderWidth),
        // Add glow effect for current step
        boxShadow: isCurrentStep ? [
          BoxShadow(
            color: Colors.cyan.withValues(alpha: 0.5),
            blurRadius: 8,
            spreadRadius: 1,
          )
        ] : null,
      ),
      child: Transform(
          transform:
              Matrix4.translationValues(0, (-1 * size * velocity) + 2, 0),
          child: Container(
              width: size,
              decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(
                    color: isCurrentStep ? Colors.cyan : Colors.white,
                    width: isCurrentStep ? 2.0 : 1.0,
                  ))))),
    );

    return GestureDetector(
      onTap: () {
        final nextVelocity = velocity == 0.0 ? DEFAULT_VELOCITY : 0.0;

        onChange(nextVelocity);
      },
      onVerticalDragUpdate: (details) {
        final renderBox = context.findRenderObject() as RenderBox;
        final yPos = renderBox.globalToLocal(details.globalPosition).dy;
        final nextVelocity = 1.0 - (yPos / size).clamp(0.0, 1.0);

        onChange(nextVelocity);
      },
      child: box,
    );
  }
}
