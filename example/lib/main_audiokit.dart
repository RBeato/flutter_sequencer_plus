import 'package:flutter/material.dart';
import 'package:flutter_sequencer/audiokit_bridge.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'dart:io';

void main() {
  runApp(const AudioKitTestApp());
}

class AudioKitTestApp extends StatelessWidget {
  const AudioKitTestApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AudioKit Engine Test',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        brightness: Brightness.dark,
      ),
      home: const AudioKitTestPage(),
    );
  }
}

class AudioKitTestPage extends StatefulWidget {
  const AudioKitTestPage({super.key});

  @override
  State<AudioKitTestPage> createState() => _AudioKitTestPageState();
}

class _AudioKitTestPageState extends State<AudioKitTestPage> {
  bool _initialized = false;
  int? _trackId;
  bool _isPlaying = false;
  double _tempo = 120.0;
  String _status = 'Not initialized';

  @override
  void initState() {
    super.initState();
    _initializeAudioKit();
  }

  Future<void> _initializeAudioKit() async {
    try {
      setState(() => _status = 'Initializing AudioKit engine...');

      // Initialize engine
      final sampleRate = AudioKitBridge.initEngine();
      setState(() => _status = 'Engine initialized: ${sampleRate}Hz');

      // Copy SF2 to temporary location
      setState(() => _status = 'Loading soundfont...');
      final sf2Path = await _copySF2Asset();

      // Add track with piano soundfont
      final trackId = AudioKitBridge.addTrackSF2(sf2Path, 0);
      if (trackId < 0) {
        setState(() => _status = 'ERROR: Failed to load soundfont');
        return;
      }

      setState(() {
        _trackId = trackId;
        _initialized = true;
        _status = 'Ready! Track ID: $trackId';
      });

      // Schedule a simple test pattern (C major arpeggio)
      _scheduleTestPattern();
    } catch (e) {
      setState(() => _status = 'ERROR: $e');
    }
  }

  Future<String> _copySF2Asset() async {
    final bytes = await rootBundle.load('assets/sf2/Piano.SF2');
    final dir = Directory.systemTemp;
    final file = File('${dir.path}/Piano.SF2');
    await file.writeAsBytes(bytes.buffer.asUint8List());
    return file.path;
  }

  void _scheduleTestPattern() {
    if (_trackId == null) return;

    // Clear existing events
    AudioKitBridge.clearAllEvents(_trackId!);

    // C major arpeggio: C4, E4, G4, C5
    final notes = [60, 64, 67, 72]; // MIDI note numbers
    final beatDuration = 0.5; // Each note lasts 0.5 beats

    for (int i = 0; i < notes.length; i++) {
      final beat = i * beatDuration;

      // Note on
      AudioKitBridge.scheduleEvent(
        trackId: _trackId!,
        beat: beat,
        noteOn: true,
        note: notes[i],
        velocity: 100,
      );

      // Note off
      AudioKitBridge.scheduleEvent(
        trackId: _trackId!,
        beat: beat + beatDuration * 0.9, // Slight gap
        noteOn: false,
        note: notes[i],
        velocity: 0,
      );
    }

    setState(() => _status = 'Test pattern scheduled (C major arpeggio)');
  }

  void _togglePlayback() {
    if (!_initialized) return;

    if (_isPlaying) {
      AudioKitBridge.pause();
      setState(() {
        _isPlaying = false;
        _status = 'Paused';
      });
    } else {
      AudioKitBridge.play();
      setState(() {
        _isPlaying = true;
        _status = 'Playing at ${_tempo.toStringAsFixed(0)} BPM';
      });
    }
  }

  void _stop() {
    if (!_initialized) return;

    AudioKitBridge.stop();
    setState(() {
      _isPlaying = false;
      _status = 'Stopped';
    });
  }

  void _changeTempo(double newTempo) {
    AudioKitBridge.setTempo(newTempo);
    setState(() {
      _tempo = newTempo;
      _status = 'Tempo: ${_tempo.toStringAsFixed(0)} BPM';
    });
  }

  @override
  void dispose() {
    if (_initialized) {
      AudioKitBridge.stop();
      if (_trackId != null) {
        AudioKitBridge.removeTrack(_trackId!);
      }
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AudioKit Engine Test'),
        backgroundColor: Colors.blue.shade900,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Status card
            Card(
              color: _initialized ? Colors.green.shade900 : Colors.orange.shade900,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Status',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(_status),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Playback controls
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton.icon(
                  onPressed: _initialized ? _togglePlayback : null,
                  icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow),
                  label: Text(_isPlaying ? 'Pause' : 'Play'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isPlaying ? Colors.orange : Colors.green,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 16,
                    ),
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: _initialized ? _stop : null,
                  icon: const Icon(Icons.stop),
                  label: const Text('Stop'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 16,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),

            // Tempo control
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Tempo: ${_tempo.toStringAsFixed(0)} BPM',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Slider(
                      value: _tempo,
                      min: 40,
                      max: 240,
                      divisions: 200,
                      label: _tempo.toStringAsFixed(0),
                      onChanged: _initialized ? _changeTempo : null,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 32),

            // Info card
            Card(
              color: Colors.blue.shade900,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'AudioKit Engine Info',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 8),
                    const Text('• Professional AudioKit-based engine'),
                    const Text('• Target: 1-3% CPU usage'),
                    const Text('• SF2 soundfont support'),
                    const Text('• Beat-based event scheduling'),
                    const Text('• 5ms update rate (200Hz)'),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
