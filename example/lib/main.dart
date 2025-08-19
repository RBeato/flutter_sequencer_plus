import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_sequencer/global_state.dart';
import 'package:flutter_sequencer/models/instrument.dart';
import 'package:flutter_sequencer/models/events.dart';
import 'package:flutter_sequencer/native_bridge.dart';
import 'package:flutter_sequencer/sequence.dart';
import 'package:flutter_sequencer/track.dart';
import 'package:flutter/services.dart';
import 'dart:io' show Platform;
import 'dart:async';

import 'components/drum_machine/drum_machine.dart';
import 'components/position_view.dart';
import 'components/step_count_selector.dart';
import 'components/tempo_selector.dart';
import 'components/track_selector.dart';
import 'components/transport.dart';
import 'components/debug_console.dart';
import 'models/project_state.dart';
import 'models/step_sequencer_state.dart';
import 'constants.dart';

// Custom SF2 instrument with display name
class CustomSf2Instrument extends Sf2Instrument {
  final String customDisplayName;
  
  CustomSf2Instrument({
    required String path,
    required bool isAsset,
    required this.customDisplayName,
    int presetIndex = 0,
  }) : super(path: path, isAsset: isAsset, presetIndex: presetIndex);
  
  @override
  String get displayName => customDisplayName;
}

void checkAsset() async {
  try {
    // Check new SF2 files
    print('[DEBUG] Checking asset: assets/sf2/DrumsSlavo.sf2');
    final sf2Data1 = await rootBundle.load('assets/sf2/DrumsSlavo.sf2');
    print('[DEBUG] Asset found: assets/sf2/DrumsSlavo.sf2, size: \\${sf2Data1.lengthInBytes} bytes');
    
    print('[DEBUG] Checking asset: assets/sf2/rhodes.sf2');
    final sf2Data2 = await rootBundle.load('assets/sf2/rhodes.sf2');
    print('[DEBUG] Asset found: assets/sf2/rhodes.sf2, size: \\${sf2Data2.lengthInBytes} bytes');
    
    print('[DEBUG] Checking asset: assets/sf2/korg.sf2');
    final sf2Data3 = await rootBundle.load('assets/sf2/korg.sf2');
    print('[DEBUG] Asset found: assets/sf2/korg.sf2, size: \\${sf2Data3.lengthInBytes} bytes');
    
    print('[DEBUG] Checking asset: assets/sf2/Electric_guitar.SF2');
    final sf2Data4 = await rootBundle.load('assets/sf2/Electric_guitar.SF2');
    print('[DEBUG] Asset found: assets/sf2/Electric_guitar.SF2, size: \\${sf2Data4.lengthInBytes} bytes');
  } catch (e, stack) {
    print('[ERROR] Asset NOT found: \\${e.toString()}');
    print('[ERROR] Stack trace: \\${stack.toString()}');
  }
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize audio session with proper settings
  if (Platform.isIOS) {
    print('Running on iOS ${Platform.operatingSystemVersion}');
    _initAudioSession();
  }
  
  runApp(MyApp());
}

// Initialize proper audio session on iOS
Future<void> _initAudioSession() async {
  try {
    const methodChannel = MethodChannel('flutter_sequencer');
    await methodChannel.invokeMethod('initializeAudioSession');
    print('Audio session initialized successfully');
  } catch (e) {
    print('Error initializing audio session: $e');
  }
}

class MyApp extends StatefulWidget {
  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with SingleTickerProviderStateMixin {
  final sequence =
      Sequence(tempo: INITIAL_TEMPO, endBeat: INITIAL_STEP_COUNT.toDouble());
  Map<int, StepSequencerState?> trackStepSequencerStates = {};
  List<Track> tracks = [];
  Map<int, double> trackVolumes = {};
  Track? selectedTrack;
  late Ticker ticker;
  double tempo = INITIAL_TEMPO;
  int stepCount = INITIAL_STEP_COUNT;
  double position = 0.0;
  bool isPlaying = false;
  bool isLooping = INITIAL_IS_LOOPING;
  bool isPaused = false;
  
  // Simple playback system
  Timer? _playbackTimer;
  DateTime? _playbackStartTime;
  double _playbackStartBeat = 0.0;
  double _pausedAtBeat = 0.0;
  
  // Available soundfonts
  final List<Map<String, String>> _availableSoundFonts = [
    {'name': 'Rhodes Piano', 'path': 'assets/sf2/rhodes.sf2'},
    {'name': 'Electric Guitar', 'path': 'assets/sf2/Electric_guitar.SF2'},
    {'name': 'Bass Guitars', 'path': 'assets/sf2/BassGuitars.sf2'},
    {'name': 'Korg Synth', 'path': 'assets/sf2/korg.sf2'},
    {'name': 'General MIDI Bank', 'path': 'assets/sf2/GeneralUser-GS.sf2'},
    {'name': 'Drums (Slavo)', 'path': 'assets/sf2/DrumsSlavo.sf2'},
  ];
  
  // General MIDI instrument presets (GM standard)
  final List<Map<String, dynamic>> _generalMidiPresets = [
    // Piano Family
    {'name': 'Acoustic Grand Piano', 'program': 0},
    {'name': 'Bright Acoustic Piano', 'program': 1},
    {'name': 'Electric Grand Piano', 'program': 2},
    {'name': 'Honky-tonk Piano', 'program': 3},
    {'name': 'Electric Piano 1', 'program': 4},
    {'name': 'Electric Piano 2', 'program': 5},
    {'name': 'Harpsichord', 'program': 6},
    {'name': 'Clavi', 'program': 7},
    // Chromatic Percussion
    {'name': 'Celesta', 'program': 8},
    {'name': 'Glockenspiel', 'program': 9},
    {'name': 'Music Box', 'program': 10},
    {'name': 'Vibraphone', 'program': 11},
    {'name': 'Marimba', 'program': 12},
    {'name': 'Xylophone', 'program': 13},
    {'name': 'Tubular Bells', 'program': 14},
    {'name': 'Dulcimer', 'program': 15},
    // Organ
    {'name': 'Drawbar Organ', 'program': 16},
    {'name': 'Percussive Organ', 'program': 17},
    {'name': 'Rock Organ', 'program': 18},
    {'name': 'Church Organ', 'program': 19},
    {'name': 'Reed Organ', 'program': 20},
    {'name': 'Accordion', 'program': 21},
    {'name': 'Harmonica', 'program': 22},
    {'name': 'Tango Accordion', 'program': 23},
    // Guitar
    {'name': 'Acoustic Guitar (nylon)', 'program': 24},
    {'name': 'Acoustic Guitar (steel)', 'program': 25},
    {'name': 'Electric Guitar (jazz)', 'program': 26},
    {'name': 'Electric Guitar (clean)', 'program': 27},
    {'name': 'Electric Guitar (muted)', 'program': 28},
    {'name': 'Overdriven Guitar', 'program': 29},
    {'name': 'Distortion Guitar', 'program': 30},
    {'name': 'Guitar harmonics', 'program': 31},
    // Bass
    {'name': 'Acoustic Bass', 'program': 32},
    {'name': 'Electric Bass (finger)', 'program': 33},
    {'name': 'Electric Bass (pick)', 'program': 34},
    {'name': 'Fretless Bass', 'program': 35},
    {'name': 'Slap Bass 1', 'program': 36},
    {'name': 'Slap Bass 2', 'program': 37},
    {'name': 'Synth Bass 1', 'program': 38},
    {'name': 'Synth Bass 2', 'program': 39},
    // Strings
    {'name': 'Violin', 'program': 40},
    {'name': 'Viola', 'program': 41},
    {'name': 'Cello', 'program': 42},
    {'name': 'Contrabass', 'program': 43},
    {'name': 'Tremolo Strings', 'program': 44},
    {'name': 'Pizzicato Strings', 'program': 45},
    {'name': 'Orchestral Harp', 'program': 46},
    {'name': 'Timpani', 'program': 47},
    // Ensemble
    {'name': 'String Ensemble 1', 'program': 48},
    {'name': 'String Ensemble 2', 'program': 49},
    {'name': 'SynthStrings 1', 'program': 50},
    {'name': 'SynthStrings 2', 'program': 51},
    {'name': 'Choir Aahs', 'program': 52},
    {'name': 'Voice Oohs', 'program': 53},
    {'name': 'Synth Voice', 'program': 54},
    {'name': 'Orchestra Hit', 'program': 55},
    // Brass
    {'name': 'Trumpet', 'program': 56},
    {'name': 'Trombone', 'program': 57},
    {'name': 'Tuba', 'program': 58},
    {'name': 'Muted Trumpet', 'program': 59},
    {'name': 'French Horn', 'program': 60},
    {'name': 'Brass Section', 'program': 61},
    {'name': 'SynthBrass 1', 'program': 62},
    {'name': 'SynthBrass 2', 'program': 63},
    // Reed
    {'name': 'Soprano Sax', 'program': 64},
    {'name': 'Alto Sax', 'program': 65},
    {'name': 'Tenor Sax', 'program': 66},
    {'name': 'Baritone Sax', 'program': 67},
    {'name': 'Oboe', 'program': 68},
    {'name': 'English Horn', 'program': 69},
    {'name': 'Bassoon', 'program': 70},
    {'name': 'Clarinet', 'program': 71},
    // Pipe
    {'name': 'Piccolo', 'program': 72},
    {'name': 'Flute', 'program': 73},
    {'name': 'Recorder', 'program': 74},
    {'name': 'Pan Flute', 'program': 75},
    {'name': 'Blown Bottle', 'program': 76},
    {'name': 'Shakuhachi', 'program': 77},
    {'name': 'Whistle', 'program': 78},
    {'name': 'Ocarina', 'program': 79},
    // Synth Lead
    {'name': 'Lead 1 (square)', 'program': 80},
    {'name': 'Lead 2 (sawtooth)', 'program': 81},
    {'name': 'Lead 3 (calliope)', 'program': 82},
    {'name': 'Lead 4 (chiff)', 'program': 83},
    {'name': 'Lead 5 (charang)', 'program': 84},
    {'name': 'Lead 6 (voice)', 'program': 85},
    {'name': 'Lead 7 (fifths)', 'program': 86},
    {'name': 'Lead 8 (bass + lead)', 'program': 87},
    // Synth Pad
    {'name': 'Pad 1 (new age)', 'program': 88},
    {'name': 'Pad 2 (warm)', 'program': 89},
    {'name': 'Pad 3 (polysynth)', 'program': 90},
    {'name': 'Pad 4 (choir)', 'program': 91},
    {'name': 'Pad 5 (bowed)', 'program': 92},
    {'name': 'Pad 6 (metallic)', 'program': 93},
    {'name': 'Pad 7 (halo)', 'program': 94},
    {'name': 'Pad 8 (sweep)', 'program': 95},
    // Synth Effects
    {'name': 'FX 1 (rain)', 'program': 96},
    {'name': 'FX 2 (soundtrack)', 'program': 97},
    {'name': 'FX 3 (crystal)', 'program': 98},
    {'name': 'FX 4 (atmosphere)', 'program': 99},
    {'name': 'FX 5 (brightness)', 'program': 100},
    {'name': 'FX 6 (goblins)', 'program': 101},
    {'name': 'FX 7 (echoes)', 'program': 102},
    {'name': 'FX 8 (sci-fi)', 'program': 103},
    // Ethnic
    {'name': 'Sitar', 'program': 104},
    {'name': 'Banjo', 'program': 105},
    {'name': 'Shamisen', 'program': 106},
    {'name': 'Koto', 'program': 107},
    {'name': 'Kalimba', 'program': 108},
    {'name': 'Bag pipe', 'program': 109},
    {'name': 'Fiddle', 'program': 110},
    {'name': 'Shanai', 'program': 111},
    // Percussive
    {'name': 'Tinkle Bell', 'program': 112},
    {'name': 'Agogo', 'program': 113},
    {'name': 'Steel Drums', 'program': 114},
    {'name': 'Woodblock', 'program': 115},
    {'name': 'Taiko Drum', 'program': 116},
    {'name': 'Melodic Tom', 'program': 117},
    {'name': 'Synth Drum', 'program': 118},
    {'name': 'Reverse Cymbal', 'program': 119},
    // Sound Effects
    {'name': 'Guitar Fret Noise', 'program': 120},
    {'name': 'Breath Noise', 'program': 121},
    {'name': 'Seashore', 'program': 122},
    {'name': 'Bird Tweet', 'program': 123},
    {'name': 'Telephone Ring', 'program': 124},
    {'name': 'Helicopter', 'program': 125},
    {'name': 'Applause', 'program': 126},
    {'name': 'Gunshot', 'program': 127},
  ];
  
  // Default lead instrument soundfont
  String _selectedSoundFont = 'assets/sf2/rhodes.sf2';
  int _selectedGMPreset = 0; // Default to Acoustic Grand Piano

  @override
  void initState() {
    super.initState();
    checkAsset();

    GlobalState().setKeepEngineRunning(true);
    
    print('[DEBUG] Platform: ${Platform.isIOS ? "iOS" : "Android"}');
    
    // Initialize tracks with multi-track support
    _initializeTracks();

    ticker = this.createTicker((Duration elapsed) {
      setState(() {
        tempo = sequence.getTempo();
        // MINIMAL iOS FIX: Use timer position on iOS, native on Android
        if (Platform.isIOS) {
          // iOS native position is broken - keep using timer position from _processPlayback
        } else {
          // Android works fine with native position
          position = sequence.getBeat();
        }
        isPlaying = sequence.getIsPlaying();

        // DON'T override trackVolumes - they should only be set by user interaction
        // The ticker was resetting volumes to what the native track reports, 
        // which can be 0 on Android after stopping playback
        // tracks.forEach((track) {
        //   trackVolumes[track.id] = track.getVolume();
        // });
      });
    });
    ticker.start();
  }

  handleTogglePlayPause() {
    print('[DEBUG] handleTogglePlayPause: currently isPlaying=$isPlaying isPaused=$isPaused');
    if (isPlaying) {
      print('[DEBUG] Pausing sequence...');
      _pausePlayback();
      sequence.pause();
    } else {
      print('[DEBUG] Starting/resuming playback...');
      print('[DEBUG] Available tracks: ${tracks.length}');
      for (final track in tracks) {
        print('[DEBUG] Track ${track.id} has ${track.events.length} events');
      }
      
      // Start or resume playback
      if (isPaused) {
        _resumePlayback();
      } else {
        _startSimplePlayback();
      }
      sequence.play();
    }
  }
  
  void _startSimplePlayback() {
    print('[DEBUG] Starting simple playback system...');
    _playbackStartTime = DateTime.now();
    // Always start from beat 0 for consistent playback
    _playbackStartBeat = 0.0;
    _pausedAtBeat = 0.0;
    
    // Clear processed events to ensure clean start
    _processedEvents.clear();
    
    // Reset position to 0 
    setState(() {
      position = 0.0;
      isPlaying = true;
      isPaused = false;
    });
    
    // Ensure engine is running (but don't restart if already running)
    NativeBridge.play();
    
    // Create a high-frequency timer to process events
    _playbackTimer = Timer.periodic(Duration(milliseconds: 10), (timer) {
      _processPlayback();
    });
    
    print('[DEBUG] Playback started from beat 0.0');
  }
  
  void _pausePlayback() {
    print('[DEBUG] Pausing playback system...');
    _playbackTimer?.cancel();
    _playbackTimer = null;
    
    // Save current position for resume
    _pausedAtBeat = position;
    
    // Pause the native engine
    NativeBridge.pause();
    
    setState(() {
      isPlaying = false;
      isPaused = true;
    });
    
    print('[DEBUG] Playback paused at beat $_pausedAtBeat');
  }
  
  void _resumePlayback() {
    print('[DEBUG] Resuming playback from beat $_pausedAtBeat...');
    _playbackStartTime = DateTime.now();
    _playbackStartBeat = _pausedAtBeat;
    
    setState(() {
      isPlaying = true;
      isPaused = false;
    });
    
    // Ensure engine is running
    NativeBridge.play();
    
    // Create a high-frequency timer to process events
    _playbackTimer = Timer.periodic(Duration(milliseconds: 10), (timer) {
      _processPlayback();
    });
    
    print('[DEBUG] Playback resumed from beat $_pausedAtBeat');
  }
  
  void _stopSimplePlayback() {
    print('[DEBUG] Stopping simple playback system...');
    _playbackTimer?.cancel();
    _playbackTimer = null;
    _playbackStartTime = null;
    
    // Send optimized note-off commands to only active tracks
    int totalNotesOff = 0;
    for (final track in tracks) {
      // Only send note-off for commonly used drum/instrument notes instead of all 128
      final noteOffEvents = <MidiEvent>[];
      
      // Common drum notes (36-81) and typical instrument range
      for (int noteNumber = 36; noteNumber <= 81; noteNumber++) {
        noteOffEvents.add(MidiEvent.ofNoteOff(beat: 0.0, noteNumber: noteNumber));
      }
      
      if (noteOffEvents.isNotEmpty) {
        NativeBridge.handleEventsNow(
          track.id, 
          noteOffEvents, 
          GlobalState().sampleRate!, 
          tempo
        );
        totalNotesOff += noteOffEvents.length;
      }
    }
    print('[DEBUG] Sent $totalNotesOff note-offs to stop sustained sounds');
    
    // DON'T stop the engine - keep SF2s loaded!
    print('[DEBUG] Keeping audio engine running to preserve SF2 loading');
  }
  
  void _processPlayback() {
    if (_playbackStartTime == null) return;
    
    // Calculate current beat based on elapsed time
    final elapsed = DateTime.now().difference(_playbackStartTime!);
    final elapsedBeats = (elapsed.inMicroseconds / 1000000.0) * (tempo / 60.0);
    final currentBeat = _playbackStartBeat + elapsedBeats;
    
    // Update position
    setState(() {
      position = currentBeat;
    });
    
    // Check if we've reached the end
    if (currentBeat >= stepCount) {
      print('[DEBUG] Reached end: currentBeat=$currentBeat stepCount=$stepCount isLooping=$isLooping');
      if (isLooping) {
        print('[DEBUG] Looping back to beginning...');
        // Loop back to beginning
        _playbackStartTime = DateTime.now();
        _playbackStartBeat = 0.0;
        setState(() {
          position = 0.0;
        });
        // Clear processed events when looping
        _processedEvents.clear();
      } else {
        print('[DEBUG] Stopping playback (loop is OFF)...');
        // Stop playback and reset everything to beginning
        _stopSimplePlayback();
        
        // Clear all timing state to ensure clean restart
        _processedEvents.clear();
        _playbackStartTime = null;
        _playbackStartBeat = 0.0;
        _pausedAtBeat = 0.0;
        
        setState(() {
          isPlaying = false;
          position = 0.0;
          isPaused = false;
        });
        
        // Sync all tracks to pick up changes made during playback
        tracks.forEach(syncTrack);
        print('[DEBUG] Single playback ended: isPlaying=false, position=0.0, all timing cleared');
        return;
      }
    }
    
    // Process events for current beat
    _processEventsAtBeat(currentBeat);
  }
  
  Set<String> _processedEvents = {}; // Track which events we've already processed
  
  void _processEventsAtBeat(double currentBeat) {
    for (final track in tracks) {
      for (final event in track.events) {
        if (event is MidiEvent) {
          // CRITICAL FIX: Skip Program Change events during playback to prevent SF2 reload spam
          // Program Change commands (0xC0-0xCF) cause Apple AudioUnit to reload SF2 banks
          if ((event.midiStatus & 0xF0) == 0xC0) {
            continue; // Skip Program Change - SF2 preset is already loaded
          }
          
          // Check if this event should trigger now (within reasonable timing window)
          final eventBeat = event.beat;
          final eventKey = '${track.id}-${eventBeat.toStringAsFixed(2)}-${event.midiData1}-${event.midiData2}';
          
          // More forgiving timing check - original working tolerance
          if (eventBeat >= currentBeat - 0.15 && eventBeat <= currentBeat + 0.15) {
            if (!_processedEvents.contains(eventKey)) {
              // Minimal logging to maintain performance
              if (Platform.isIOS && (event.midiStatus & 0xF0) == 0x90 && event.midiData2 > 0) {
                final stepNumber = eventBeat.floor();
                if (stepNumber % 8 == 0) { // Log every 8th step only
                  print('[DEBUG] Playing: track=${track.id} step=$stepNumber beat=${eventBeat.toStringAsFixed(2)}');
                }
              }
              
              // Send MIDI event directly
              NativeBridge.handleEventsNow(
                track.id, 
                [event], 
                GlobalState().sampleRate!, 
                tempo
              );
              
              _processedEvents.add(eventKey);
            }
          }
        }
      }
    }
    
    // Clean up old processed events (older than 1 beat)
    final oldSize = _processedEvents.length;
    _processedEvents.removeWhere((key) {
      final parts = key.split('-');
      if (parts.length >= 2) {
        final eventBeat = double.tryParse(parts[1]) ?? 0.0;
        return eventBeat < currentBeat - 1.0;
      }
      return false;
    });
    
    // Reduce cleanup logging - only log significant cleanups
    if (_processedEvents.length != oldSize && (oldSize - _processedEvents.length) > 5) {
      print('[DEBUG] 🧹 Cleaned ${oldSize - _processedEvents.length} old events, ${_processedEvents.length} remaining');
    }
  }

  handleStop() {
    print('[DEBUG] handleStop called');
    _stopSimplePlayback();
    _processedEvents.clear();
    
    // Reset position to step 0 and clear pause state
    setState(() {
      position = 0.0;
      isPlaying = false;
      isPaused = false;
    });
    _pausedAtBeat = 0.0;
    sequence.stop();
    
    // Sync all tracks to pick up changes made during playback
    tracks.forEach(syncTrack);
    print('[DEBUG] Position reset to 0.0, pause state cleared, all tracks synced after stopping');
  }
  
  @override
  void dispose() {
    _playbackTimer?.cancel();
    ticker.dispose();
    super.dispose();
  }

  handleSetLoop(bool nextIsLooping) {
    if (nextIsLooping) {
      sequence.setLoop(0, stepCount.toDouble());
    } else {
      sequence.unsetLoop();
    }

    setState(() {
      isLooping = nextIsLooping;
    });
  }

  handleToggleLoop() {
    final nextIsLooping = !isLooping;

    handleSetLoop(nextIsLooping);
  }

  handleStepCountChange(int nextStepCount) {
    if (nextStepCount < 1) return;

    sequence.setEndBeat(nextStepCount.toDouble());

    if (isLooping) {
      final nextLoopEndBeat = nextStepCount.toDouble();

      sequence.setLoop(0, nextLoopEndBeat);
    }

    setState(() {
      stepCount = nextStepCount;
      tracks.forEach((track) => syncTrack(track));
    });
  }

  handleTempoChange(double nextTempo) {
    if (nextTempo <= 0) return;
    sequence.setTempo(nextTempo);
  }

  handleTrackChange(Track? nextTrack) {
    String instrumentInfo = '';
    if (nextTrack != null) {
      final inst = nextTrack.instrument;
      if (inst is Sf2Instrument || inst is SfzInstrument) {
        instrumentInfo = 'path=${inst.idOrPath}';
      } else if (inst is AudioUnitInstrument) {
        instrumentInfo = 'id=${inst.idOrPath}';
      } else {
        instrumentInfo = 'type=${inst.runtimeType}';
      }
    }
    print('[DEBUG] Track changed: id=${nextTrack?.id} instrument=${nextTrack?.instrument.runtimeType} $instrumentInfo');
    setState(() {
      selectedTrack = nextTrack;
    });
  }

  handleVolumeChange(double nextVolume) {
    print('[DEBUG] Volume change: trackId=${selectedTrack?.id} newVolume=$nextVolume');
    if (selectedTrack != null) {
      selectedTrack!.changeVolumeNow(volume: nextVolume);
      // Update our UI state immediately (don't wait for ticker)
      setState(() {
        trackVolumes[selectedTrack!.id] = nextVolume;
      });
      print('[DEBUG] Volume UI state updated to $nextVolume for track ${selectedTrack!.id}');
    }
  }


  handleVelocitiesChange(
      int trackId, int step, int noteNumber, double velocity) {
    print('[DEBUG] Velocity change: trackId=$trackId step=$step noteNumber=$noteNumber velocity=$velocity');
    final track = tracks.firstWhere((track) => track.id == trackId);

    trackStepSequencerStates[trackId]!.setVelocity(step, noteNumber, velocity);

    // Always sync track to enable real-time editing
    syncTrack(track);
    print('[DEBUG] Track synced for real-time editing');
  }

  /// Calculate note duration based on tempo
  /// Faster tempos = shorter sustain for musical feel
  double _calculateNoteDuration(double tempo) {
    // Base duration: 1 beat at 120 BPM
    const double baseTempo = 120.0;
    const double baseDuration = 1.6; // Double the previous duration (was 0.8)
    
    // Scale duration inversely with tempo
    // Faster tempo = shorter notes for tighter feel
    double tempoDuration = (baseTempo / tempo) * baseDuration;
    
    // Clamp to reasonable range: 0.2 to 1.8 beats (doubled from 0.1-0.9)
    return tempoDuration.clamp(0.2, 1.8);
  }

  syncTrack(track) {
    // Reduced logging for performance
    track.clearEvents();
    int noteCount = 0;
    final currentTempo = sequence.getTempo();
    final noteDuration = _calculateNoteDuration(currentTempo);
    
    trackStepSequencerStates[track.id]!
        .iterateEvents((step, noteNumber, velocity) {
      if (step < stepCount && velocity > 0) {
        noteCount++;
        track.addNote(
            noteNumber: noteNumber,
            velocity: velocity,
            startBeat: step.toDouble(),
            durationBeats: noteDuration);
      }
    });
    // Only log when there are actual notes to sync
    if (noteCount > 0) {
      print('[DEBUG] Synced track ${track.id}: $noteCount notes (duration: ${noteDuration.toStringAsFixed(2)} beats @ ${currentTempo.toStringAsFixed(0)} BPM)');
    }
    track.syncBuffer();
  }

  loadProjectState(ProjectState projectState) {
    print('[DEBUG] Loading project state');
    handleStop();

    // Clear all track states first
    for (final track in tracks) {
      trackStepSequencerStates[track.id] = StepSequencerState();
    }

    // For reset, just use empty states - for demo, could assign specific patterns
    // But for now, reset should just clear everything
    print('[DEBUG] All track states cleared for reset');

    handleStepCountChange(projectState.stepCount);
    handleTempoChange(projectState.tempo);
    handleSetLoop(projectState.isLooping);

    tracks.forEach(syncTrack);
  }
  
  // Removed _changeSoundFont - use TrackSelector instead
  
  Future<void> _initializeTracks() async {
    // Stop playback
    handleStop();
    
    // Clear existing tracks
    if (tracks.isNotEmpty) {
      for (final track in tracks) {
        track.clearEvents();
        NativeBridge.removeTrack(track.id);
      }
      tracks.clear();
      await Future.delayed(Duration(milliseconds: 200));
    }
    
    // Create instruments for all tracks - one for each available soundfont
    final instruments = <Instrument>[];
    
    // Add all available soundfonts as separate tracks with custom names
    for (var soundfont in _availableSoundFonts) {
      print('[DEBUG] Adding instrument: ${soundfont['name']} -> ${soundfont['path']}');
      
      // Use selected preset for General MIDI Bank, default preset for others
      final presetIndex = (soundfont['path'] == 'assets/sf2/GeneralUser-GS.sf2') 
          ? _selectedGMPreset 
          : 0;
      
      // Create display name with GM preset info if applicable
      String displayName = soundfont['name']!;
      if (soundfont['path'] == 'assets/sf2/GeneralUser-GS.sf2') {
        final preset = _generalMidiPresets.firstWhere(
          (p) => p['program'] == _selectedGMPreset,
          orElse: () => {'name': 'Unknown', 'program': 0}
        );
        displayName = 'GM: ${preset['name']}';
      }
      
      instruments.add(
        CustomSf2Instrument(
          path: soundfont['path']!, 
          isAsset: true, 
          presetIndex: presetIndex,
          customDisplayName: displayName,
        ),
      );
    }
    print('[DEBUG] Total instruments to create: ${instruments.length}');
    
    // Create tracks
    try {
      final newTracks = await sequence.createTracks(instruments);
      print('[DEBUG] Created ${newTracks.length} tracks from ${instruments.length} instruments');
      
      setState(() {
        tracks = newTracks;
        selectedTrack = newTracks.isNotEmpty ? newTracks[0] : null;
        
        // Initialize sequencer states for all tracks
        newTracks.forEach((track) {
          trackStepSequencerStates[track.id] = StepSequencerState();
          trackVolumes[track.id] = 0.7; // Set default volume
          
          // IMPORTANT: Actually set the volume on the native track object
          track.changeVolumeNow(volume: 0.7);
          print('[DEBUG] Set initial volume 0.7 for track ${track.id} (${track.instrument.displayName})');
        });
      });
      
      if (newTracks.isEmpty) {
        print('[ERROR] No tracks were created - all instruments failed to load');
        // Could show an error dialog here if needed
      }
    } catch (e) {
      print('[ERROR] Failed to initialize tracks: $e');
      // Show error dialog to user
      if (mounted) {
        showDialog(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              title: Text('Track Loading Failed'),
              content: Text('Failed to load tracks with GM preset $_selectedGMPreset. Some presets might not be available in the soundfont. Please try a different preset.'),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    // Reset to default preset
                    setState(() {
                      _selectedGMPreset = 0;
                    });
                    _reinitializeTracks();
                  },
                  child: Text('Reset to Default'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text('OK'),
                ),
              ],
            );
          },
        );
      }
      // Ensure UI updates even on error
      setState(() {
        tracks = [];
        selectedTrack = null;
      });
    }
  }

  handleReset() {
    loadProjectState(ProjectState.empty());
  }

  handleLoadDemo() {
    loadProjectState(ProjectState.demo());
  }

  handleSoundFontChange(String newSoundFont) {
    print('[DEBUG] Changing soundfont to: $newSoundFont');
    setState(() {
      _selectedSoundFont = newSoundFont;
    });
    
    // Reinitialize tracks with new soundfont
    _initializeTracks();
  }
  
  Future<void> _reinitializeTracks() async {
    print('[DEBUG] Reinitializing tracks with GM preset $_selectedGMPreset');
    
    // Store current playback state to preserve timing
    final wasPlaying = isPlaying;
    final wasPaused = isPaused;
    final currentPosition = position;
    final currentPlaybackStartTime = _playbackStartTime;
    final currentPlaybackStartBeat = _playbackStartBeat;
    final currentPausedAtBeat = _pausedAtBeat;
    final currentProcessedEvents = Set<String>.from(_processedEvents);
    
    print('[DEBUG] Storing playback state: playing=$wasPlaying paused=$wasPaused position=$currentPosition');
    
    // Store current track states and volumes
    final currentStates = <int, StepSequencerState>{};
    final currentVolumes = <int, double>{};
    for (final track in tracks) {
      if (trackStepSequencerStates.containsKey(track.id)) {
        currentStates[track.id] = trackStepSequencerStates[track.id]!;
      }
      if (trackVolumes.containsKey(track.id)) {
        currentVolumes[track.id] = trackVolumes[track.id]!;
      }
    }
    
    // Recreate tracks with new GM preset
    await _initializeTracks();
    
    // Restore track states and volumes for tracks that still exist
    for (final track in tracks) {
      if (currentStates.containsKey(track.id)) {
        trackStepSequencerStates[track.id] = currentStates[track.id]!;
        syncTrack(track);
      }
      if (currentVolumes.containsKey(track.id)) {
        trackVolumes[track.id] = currentVolumes[track.id]!;
        track.changeVolumeNow(volume: currentVolumes[track.id]!);
        print('[DEBUG] Restored volume ${currentVolumes[track.id]} for track ${track.id}');
      }
    }
    
    // Restore playback state if we were playing
    if (wasPlaying && !wasPaused) {
      print('[DEBUG] Restoring active playback state...');
      _playbackStartTime = currentPlaybackStartTime;
      _playbackStartBeat = currentPlaybackStartBeat;
      _processedEvents = currentProcessedEvents;
      
      setState(() {
        isPlaying = true;
        isPaused = false;
        position = currentPosition;
      });
      
      // Restart playback timer
      _playbackTimer = Timer.periodic(Duration(milliseconds: 10), (timer) {
        _processPlayback();
      });
      
      // Ensure engine is running
      NativeBridge.play();
      print('[DEBUG] Playback state restored and timer restarted');
    } else if (wasPaused) {
      print('[DEBUG] Restoring paused state...');
      _pausedAtBeat = currentPausedAtBeat;
      setState(() {
        isPlaying = false;
        isPaused = true;
        position = currentPosition;
      });
      print('[DEBUG] Paused state restored');
    } else {
      print('[DEBUG] Playback was stopped - maintaining stopped state');
    }
    
    print('[DEBUG] Tracks reinitialized and all states restored');
  }

  Widget _getMainView() {
    if (selectedTrack == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Loading audio tracks...'),
            SizedBox(height: 8),
            Text('Loading SF2 instruments', 
                 style: TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
      );
    }

    if (tracks.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error, size: 48, color: Colors.red),
            SizedBox(height: 16),
            Text('Failed to load audio tracks'),
            SizedBox(height: 8),
            Text('Check console for errors', 
                 style: TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
      );
    }

    // Determine if current track is a drum track based on instrument name
    final isDrumTrackSelected = selectedTrack?.instrument.displayName.toLowerCase().contains('drum') ?? false;

    return Center(
      child: Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          Transport(
            isPlaying: isPlaying,
            isLooping: isLooping,
            onTogglePlayPause: handleTogglePlayPause,
            onStop: handleStop,
            onToggleLoop: handleToggleLoop,
          ),
          PositionView(position: position),
        ]),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            StepCountSelector(
                stepCount: stepCount, onChange: handleStepCountChange),
            TempoSelector(
              selectedTempo: tempo,
              handleChange: handleTempoChange,
            ),
          ],
        ),
        // Note: Preset selector not needed for AudioUnit instruments
        TrackSelector(
          tracks: tracks,
          selectedTrack: selectedTrack,
          handleChange: handleTrackChange,
        ),
        // GM Preset Selector (only show if General MIDI track is selected)
        if (selectedTrack?.instrument.idOrPath.contains('GeneralUser-GS.sf2') == true)
          Container(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              children: [
                Text(
                  'General MIDI Preset',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 4),
                DropdownButton<int>(
                  value: _selectedGMPreset,
                  isExpanded: true,
                  onChanged: (int? newPreset) {
                    if (newPreset != null) {
                      setState(() {
                        _selectedGMPreset = newPreset;
                      });
                      _reinitializeTracks();
                    }
                  },
                  items: _generalMidiPresets.map<DropdownMenuItem<int>>((preset) {
                    return DropdownMenuItem<int>(
                      value: preset['program'],
                      child: Text(
                        '${preset['program']}: ${preset['name']}',
                        style: TextStyle(fontSize: 12),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          MaterialButton(
            child: Text('Reset'),
            onPressed: handleReset,
          ),
          MaterialButton(
            child: Text('Load Demo'),
            onPressed: handleLoadDemo,
          ),
        ]),
        DrumMachineWidget(
          track: selectedTrack!,
          stepCount: stepCount,
          currentStep: (isPlaying || isPaused) ? position.floor() : -1, // Show current step when playing or paused
          rowLabels: isDrumTrackSelected ? ROW_LABELS_DRUMS : ROW_LABELS_PIANO,
          columnPitches:
              isDrumTrackSelected ? ROW_PITCHES_DRUMS : ROW_PITCHES_PIANO,
          volume: trackVolumes[selectedTrack!.id] ?? 0.0,
          stepSequencerState: trackStepSequencerStates[selectedTrack!.id],
          handleVolumeChange: handleVolumeChange,
          handleVelocitiesChange: handleVelocitiesChange,
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData(
          colorScheme: ColorScheme.dark(),
          textTheme:
              Theme.of(context).textTheme.apply(bodyColor: Colors.white)),
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Drum machine example'),
          actions: [
            if (Platform.isIOS)
              IconButton(
                icon: Icon(Icons.bug_report),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => DebugConsole()),
                  );
                },
                tooltip: 'Native Debug Console',
              ),
          ],
        ),
        body: _getMainView(),
      ),
    );
  }
}
