import 'package:flutter/material.dart';
import 'package:flutter_sequencer/models/instrument.dart';
import 'package:flutter_sequencer/sequence.dart';
import 'package:flutter_sequencer/track.dart';
import 'package:flutter_sequencer/native_bridge.dart';
import 'dart:developer' as developer;
import 'dart:io' show Platform;
import 'package:flutter/services.dart';

// Global log function that prints to both console and dev tools
void debugLog(String message, {Object? error}) {
  print('📢 DEBUG: $message'); // Console output
  developer.log(message, error: error); // DevTools output
}

// Enable verbose logging on Android
Future<void> enableNativeLogging() async {
  try {
    debugLog('Attempting to enable verbose native logging');
    if (Platform.isAndroid) {
      const platform = MethodChannel('flutter_sequencer');
      final result = await platform.invokeMethod('enableVerboseLogging');
      debugLog('Native logging enabled: $result');
    } else {
      debugLog('Not on Android, skipping verbose logging setup');
    }
  } catch (e) {
    debugLog('Error enabling native logging: $e', error: e);
  }
}

void main() {
  debugLog('App starting...');
  WidgetsFlutterBinding.ensureInitialized();
  debugLog('Flutter binding initialized');
  enableNativeLogging();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Sequencer Test',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const TestPage(),
    );
  }
}

class TestPage extends StatefulWidget {
  const TestPage({super.key});

  @override
  State<TestPage> createState() => _TestPageState();
}

class _TestPageState extends State<TestPage> {
  String _status = 'Not initialized';
  Sequence? _sequence;
  Track? _track;
  
  @override
  void initState() {
    super.initState();
    debugLog('TestPage initialized');
  }
  
  @override
  void dispose() {
    if (_sequence != null) {
      try {
        debugLog('Disposing sequence (ID: ${_sequence!.id})');
        _sequence!.destroy();
      } catch (e) {
        debugLog('Error disposing sequence: $e', error: e);
      }
    }
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Audio Test'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Status: $_status',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 24),
            
            ElevatedButton(
              onPressed: _initialize,
              child: const Text('1. Initialize Engine'),
            ),
            const SizedBox(height: 16),
            
            ElevatedButton(
              onPressed: _createSequence,
              child: const Text('2. Create Sequence'),
            ),
            const SizedBox(height: 16),
            
            ElevatedButton(
              onPressed: _loadSF2,
              child: const Text('3. Load SF2 Instrument'),
            ),
            const SizedBox(height: 16),
            
            ElevatedButton(
              onPressed: _playNote,
              child: const Text('4. Play Test Note'),
            ),
            const SizedBox(height: 16),
            
            ElevatedButton(
              onPressed: _togglePlayPause,
              child: const Text('5. Toggle Play/Pause'),
            ),
            const SizedBox(height: 16),
            
            ElevatedButton(
              onPressed: _tryPlayingAltNotes,
              child: const Text('6. Try Different Notes'),
            ),
          ],
        ),
      ),
    );
  }
  
  Future<void> _initialize() async {
    try {
      debugLog('🔄 [STEP 1] Initializing audio engine...');
      
      // On Android, try to enable verbose logging if not done already
      if (Platform.isAndroid) {
        await enableNativeLogging();
      }
      
      debugLog('Calling NativeBridge.doSetup()');
      final result = await NativeBridge.doSetup();
      debugLog('🟢 [STEP 1] Engine setup result: $result');
      debugLog('Native audio engine should be initialized now');
      setState(() {
        _status = 'Engine initialized (result: $result)';
      });
    } catch (e) {
      debugLog('🔴 [STEP 1] ERROR: $e', error: e);
      setState(() {
        _status = 'Init error: $e';
      });
    }
  }
  
  Future<void> _createSequence() async {
    try {
      debugLog('🔄 [STEP 2] Creating sequence...');
      final sequence = Sequence(tempo: 120, endBeat: 16);
      debugLog('🟢 [STEP 2] Sequence created with ID: ${sequence.id}');
      debugLog('Global state sampleRate: ${Sequence.globalState.sampleRate}');
      
      setState(() {
        _sequence = sequence;
        _status = 'Sequence created (ID: ${sequence.id})';
      });
    } catch (e) {
      debugLog('🔴 [STEP 2] ERROR: $e', error: e);
      setState(() {
        _status = 'Sequence error: $e';
      });
    }
  }
  
  Future<void> _loadSF2() async {
    if (_sequence == null) {
      debugLog('🔴 [STEP 3] ERROR: Sequence not created');
      setState(() {
        _status = 'ERROR: Create sequence first';
      });
      return;
    }
    
    try {
      debugLog('🔄 [STEP 3] Loading SF2 instrument...');
      
      // First check if the asset exists
      final assetPath = 'assets/sf2/TR-808.sf2';
      debugLog('Asset path: $assetPath');
      
      try {
        debugLog('Checking if asset exists by loading byte data...');
        final ByteData? assetData = await rootBundle.load(assetPath);
        if (assetData == null) {
          debugLog('🔴 Asset not found, null data returned');
        } else {
          debugLog('✅ Asset found! Size: ${assetData.lengthInBytes} bytes');
        }
      } catch (e) {
        debugLog('🔴 Error loading asset data: $e');
      }
      
      debugLog('Creating Sf2Instrument object');
      final instrument = Sf2Instrument(
        path: assetPath,
        isAsset: true,
        presetIndex: 0,
      );
      debugLog('Sf2Instrument object created: ${instrument.displayName}');
      
      // Try alternative presets if needed
      // debugLog('Trying different preset numbers...');
      // final instrument = Sf2Instrument(
      //   path: assetPath,
      //   isAsset: true,
      //   presetIndex: 10, // Try different preset numbers
      // );
      
      debugLog('Calling Track.build to create track in native code');
      final track = await Track.build(
        sequence: _sequence!,
        instrument: instrument,
      );
      
      if (track == null) {
        debugLog('🔴 [STEP 3] ERROR: Track creation returned null');
        setState(() {
          _status = 'Track creation failed';
        });
        return;
      }
      
      debugLog('🟢 [STEP 3] Track created with ID: ${track.id}');
      debugLog('Track uses instrument: ${track.instrument.displayName}');
      setState(() {
        _track = track;
        _status = 'SF2 loaded (Track ID: ${track.id})';
      });
    } catch (e) {
      debugLog('🔴 [STEP 3] ERROR: $e', error: e);
      setState(() {
        _status = 'SF2 error: $e';
      });
    }
  }
  
  void _playNote() {
    if (_track == null) {
      debugLog('🔴 [STEP 4] ERROR: Track not created');
      setState(() {
        _status = 'ERROR: Load instrument first';
      });
      return;
    }
    
    try {
      debugLog('🔄 [STEP 4] Playing test note...');
      
      // Check if sequence is playing
      final isPlaying = _sequence?.isPlaying ?? false;
      debugLog('Sequence playing state: $isPlaying');
      
      // Bass drum (MIDI note 36)
      debugLog('Calling track.startNoteNow with note 36, velocity 1.0');
      _track!.startNoteNow(noteNumber: 36, velocity: 1.0);
      debugLog('🟢 [STEP 4] Note triggered');
      
      // Schedule note off after a short delay
      Future.delayed(const Duration(milliseconds: 300), () {
        try {
          debugLog('Calling track.stopNoteNow with note 36');
          _track!.stopNoteNow(noteNumber: 36);
          debugLog('Note stopped');
        } catch (e) {
          debugLog('Error stopping note: $e', error: e);
        }
      });
      
      setState(() {
        _status = 'Note played (MIDI note 36)';
      });
    } catch (e) {
      debugLog('🔴 [STEP 4] ERROR: $e', error: e);
      setState(() {
        _status = 'Note error: $e';
      });
    }
  }
  
  void _togglePlayPause() {
    if (_sequence == null) {
      debugLog('🔴 [STEP 5] ERROR: Sequence not created');
      setState(() {
        _status = 'ERROR: Create sequence first';
      });
      return;
    }
    
    try {
      debugLog('🔄 [STEP 5] Toggling play/pause...');
      
      final wasPlaying = _sequence!.isPlaying;
      debugLog('Current playing state: $wasPlaying');
      
      if (wasPlaying) {
        debugLog('Calling sequence.pause()');
        _sequence!.pause();
        debugLog('🟢 [STEP 5] Sequence paused');
        setState(() {
          _status = 'Sequence paused';
        });
      } else {
        debugLog('Calling sequence.play()');
        _sequence!.play();
        debugLog('🟢 [STEP 5] Sequence playing');
        setState(() {
          _status = 'Sequence playing';
        });
      }
    } catch (e) {
      debugLog('🔴 [STEP 5] ERROR: $e', error: e);
      setState(() {
        _status = 'Play/pause error: $e';
      });
    }
  }
  
  // Try playing different notes to see if any work
  void _tryPlayingAltNotes() {
    if (_track == null) {
      debugLog('🔴 [STEP 6] ERROR: Track not created');
      setState(() {
        _status = 'ERROR: Load instrument first';
      });
      return;
    }
    
    try {
      debugLog('🔄 [STEP 6] Trying different notes...');
      
      // Try a few different notes from different octaves
      _playMidiNote(36);  // Bass drum in GM drums
      Future.delayed(Duration(milliseconds: 500), () => _playMidiNote(38)); // Snare
      Future.delayed(Duration(milliseconds: 1000), () => _playMidiNote(42)); // Closed hi-hat
      Future.delayed(Duration(milliseconds: 1500), () => _playMidiNote(60)); // Middle C
      Future.delayed(Duration(milliseconds: 2000), () => _playMidiNote(72)); // C in higher octave
      
      setState(() {
        _status = 'Playing multiple test notes';
      });
    } catch (e) {
      debugLog('🔴 [STEP 6] ERROR: $e', error: e);
      setState(() {
        _status = 'Multi-note error: $e';
      });
    }
  }
  
  // Helper to play a midi note with logging
  void _playMidiNote(int noteNumber) {
    try {
      debugLog('Playing MIDI note $noteNumber');
      _track!.startNoteNow(noteNumber: noteNumber, velocity: 1.0);
      
      Future.delayed(const Duration(milliseconds: 300), () {
        try {
          _track!.stopNoteNow(noteNumber: noteNumber);
          debugLog('Stopped MIDI note $noteNumber');
        } catch (e) {
          debugLog('Error stopping note $noteNumber: $e');
        }
      });
    } catch (e) {
      debugLog('Error playing note $noteNumber: $e');
    }
  }
}
