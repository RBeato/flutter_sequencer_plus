import 'package:flutter/material.dart';
import 'package:flutter_sequencer/simple_ios_bridge.dart';
import 'dart:io';

/// Simple test page for new iOS engine
class SimpleTestPage extends StatefulWidget {
  @override
  _SimpleTestPageState createState() => _SimpleTestPageState();
}

class _SimpleTestPageState extends State<SimpleTestPage> {
  int? trackId;
  bool isPlaying = false;
  String status = 'Not initialized';

  @override
  void initState() {
    super.initState();
    _initEngine();
  }

  Future<void> _initEngine() async {
    if (!Platform.isIOS) {
      setState(() => status = 'Android not supported in simple engine');
      return;
    }

    try {
      final sampleRate = await SimpleIOSBridge.init();
      setState(() => status = 'Initialized at ${sampleRate}Hz');
    } catch (e) {
      setState(() => status = 'Init failed: $e');
    }
  }

  Future<void> _loadTrack() async {
    try {
      // Use the drums soundfont from assets
      final path = '/data/user/0/com.example.exampleNew/cache/assets/sf2/DrumsSlavo.sf2';

      final id = await SimpleIOSBridge.addTrackSf2(path, 0);

      if (id >= 0) {
        setState(() {
          trackId = id;
          status = 'Track $id loaded';
        });

        // Schedule some test notes
        _scheduleTestPattern();
      } else {
        setState(() => status = 'Failed to load track');
      }
    } catch (e) {
      setState(() => status = 'Load error: $e');
    }
  }

  void _scheduleTestPattern() {
    if (trackId == null) return;

    final sampleRate = 44100;
    final beatsPerMinute = 120.0;
    final framesPerBeat = (60.0 / beatsPerMinute * sampleRate).toInt();

    // Schedule a simple pattern: kick on 1,3, snare on 2,4
    for (int beat = 0; beat < 8; beat++) {
      final frame = beat * framesPerBeat;

      if (beat % 2 == 0) {
        // Kick drum (note 36)
        SimpleIOSBridge.scheduleNote(
          trackId: trackId!,
          frame: frame,
          noteOn: true,
          note: 36,
          velocity: 100,
        );
        SimpleIOSBridge.scheduleNote(
          trackId: trackId!,
          frame: frame + (framesPerBeat ~/ 4),
          noteOn: false,
          note: 36,
          velocity: 0,
        );
      } else {
        // Snare drum (note 38)
        SimpleIOSBridge.scheduleNote(
          trackId: trackId!,
          frame: frame,
          noteOn: true,
          note: 38,
          velocity: 100,
        );
        SimpleIOSBridge.scheduleNote(
          trackId: trackId!,
          frame: frame + (framesPerBeat ~/ 4),
          noteOn: false,
          note: 38,
          velocity: 0,
        );
      }
    }

    setState(() => status = 'Pattern scheduled (8 beats)');
  }

  void _togglePlayback() {
    if (isPlaying) {
      SimpleIOSBridge.pause();
      setState(() {
        isPlaying = false;
        status = 'Paused';
      });
    } else {
      SimpleIOSBridge.play();
      setState(() {
        isPlaying = true;
        status = 'Playing';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Simple iOS Engine Test'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              status,
              style: TextStyle(fontSize: 16),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 40),
            ElevatedButton(
              onPressed: trackId == null ? _loadTrack : null,
              child: Text('Load Track'),
            ),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: trackId != null ? _togglePlayback : null,
              child: Text(isPlaying ? 'Pause' : 'Play'),
            ),
          ],
        ),
      ),
    );
  }
}
