import 'package:flutter/material.dart';

class Transport extends StatelessWidget {
  const Transport({
    Key? key,
    required this.isPlaying,
    required this.isLooping,
    required this.onTogglePlayPause,
    required this.onStop,
    required this.onToggleLoop,
    this.loopCount = 0,
  }) : super(key: key);

  final bool isPlaying;
  final bool isLooping;
  final Function() onTogglePlayPause;
  final Function() onStop;
  final Function() onToggleLoop;
  final int loopCount;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
            onPressed: onTogglePlayPause,
            color: Colors.pink,
            icon: Icon(isPlaying ? Icons.pause : Icons.play_arrow)),
        IconButton(
          icon: Icon(Icons.stop),
          onPressed: onStop,
          color: Colors.pink,
        ),
        IconButton(
          icon: Icon(Icons.repeat),
          onPressed: onToggleLoop,
          color: isLooping ? Colors.pink : Colors.black54,
        ),
        if (isLooping && isPlaying)
          Container(
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            margin: EdgeInsets.only(left: 8),
            decoration: BoxDecoration(
              color: Colors.pink.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.pink, width: 1),
            ),
            child: Text(
              'Loop: $loopCount',
              style: TextStyle(
                color: Colors.pink,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
      ],
    );
  }
}
