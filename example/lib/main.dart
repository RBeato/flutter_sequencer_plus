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
import 'dart:math' as dart_math;
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

// Performance-optimized event scheduling
class ScheduledEvent {
  final Track track;
  final MidiEvent event;
  final double originalBeat;
  final double effectiveBeat;
  
  ScheduledEvent({
    required this.track,
    required this.event,
    required this.originalBeat,
    double? effectiveBeat,
  }) : effectiveBeat = effectiveBeat ?? originalBeat;
}

// Custom SFZ instrument with display name
class CustomSfzInstrument extends SfzInstrument {
  final String customDisplayName;
  
  CustomSfzInstrument({
    required String path,
    required bool isAsset,
    required this.customDisplayName,
    String? tuningPath,
  }) : super(path: path, isAsset: isAsset, tuningPath: tuningPath);
  
  @override
  String get displayName => customDisplayName;
}

// Custom AudioUnit instrument with display name  
class CustomAudioUnitInstrument extends AudioUnitInstrument {
  final String customDisplayName;
  
  CustomAudioUnitInstrument({
    required String audioUnitId,
    required this.customDisplayName,
  }) : super(manufacturerName: audioUnitId.split('.').first, componentName: audioUnitId.split('.').last);
  
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
  int _loopCycle = 0; // increments on each loop wrap
  // When true, rely entirely on native scheduling (Android); on iOS we use Dart dispatch
  final bool _useNativeScheduling = !Platform.isIOS;
  
  
  // Simple playback system
  Timer? _playbackTimer;
  
  // AUDIO STABILITY: Track buffer underruns
  int _audioGlitches = 0;
  DateTime? _lastGlitchTime;
  double _pausedAtBeat = 0.0;
  double _playbackStartBeat = 0.0;
  double? _lastNativePosition;
  
  // Available sound instruments (SF2 + SFZ + AudioUnit)
  final List<Map<String, String>> _availableSoundFonts = [
    {'name': 'J Piano', 'path': 'assets/sf2/j_piano.sf2', 'type': 'sf2'},
    {'name': 'Rhodes Piano', 'path': 'assets/sf2/rhodes.sf2', 'type': 'sf2'},
    {'name': 'Electric Guitar', 'path': 'assets/sf2/Electric_guitar.SF2', 'type': 'sf2'},
    {'name': 'Bass Guitars', 'path': 'assets/sf2/BassGuitars.sf2', 'type': 'sf2'},
    {'name': 'Korg Synth', 'path': 'assets/sf2/korg.sf2', 'type': 'sf2'},
    {'name': 'General MIDI Bank', 'path': 'assets/sf2/GeneralUser-GS.sf2', 'type': 'sf2'},
    {'name': 'Drums (Slavo)', 'path': 'assets/sf2/DrumsSlavo.sf2', 'type': 'sf2'},
    // SFZ DISABLED: Causes crashes on iOS - needs further investigation of sfizz AudioUnit integration
    // {'name': '🎹 SFZ Piano (sfizz)', 'path': 'assets/sfz/GMPiano.sfz', 'type': 'sfz', 'tuning': 'assets/sfz/meanquar.scl'},
    // TEMPORARY SAFETY FIX: Only enable AudioUnit on iOS Simulator to prevent physical device crashes
    // TODO: Re-enable on physical devices once AudioUnit loading is stable
    // if (Platform.isIOS) {'name': '🍎 Apple AudioUnit (128 GM Sounds)', 'path': 'Apple.DLSMusicDevice', 'type': 'audiounit'},
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
  
  // Default lead instrument soundfont - now using j_piano.sf2
  String _selectedSoundFont = 'assets/sf2/j_piano.sf2';
  int _selectedGMPreset = 0; // Default to Acoustic Grand Piano

  @override
  void initState() {
    super.initState();
    checkAsset();

    GlobalState().setKeepEngineRunning(true);
    
    print('[DEBUG] Platform: ${Platform.isIOS ? "iOS" : "Android"}');
    print('[DEBUG] Initial state: isLooping=$isLooping (INITIAL_IS_LOOPING=$INITIAL_IS_LOOPING)');
    
    // Initialize tracks with multi-track support
    _initializeTracks();
    
    // CRITICAL: Set initial loop state after tracks are initialized
    WidgetsBinding.instance.addPostFrameCallback((_) {
      print('[DEBUG] Setting initial loop state: $isLooping');
      if (isLooping) {
        handleSetLoop(true);
      }
    });

    ticker = this.createTicker((Duration elapsed) {
      setState(() {
        tempo = sequence.getTempo();
        // HYBRID FIX: Let _processPlayback() handle position updates using native timing
        // This eliminates the conflict between ticker and _processPlayback position updates
        // position = sequence.getBeat(); // REMOVED - handled by _processPlayback()
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
    print('[DEBUG] handleTogglePlayPause: currently isPlaying=$isPlaying isPaused=$isPaused isLooping=$isLooping');
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
    print('[TIMING-FIX] Starting corrected real-time playback...');
    
    // Reset all state
    _playbackStartTime = DateTime.now();
    _playbackStartBeat = 0.0;
    _pausedAtBeat = 0.0;
    // Reset loop cycle and event cache for deterministic first loop
    _loopCycle = 0;
    _processedEvents.clear();
    
    setState(() {
      position = 0.0;
      isPlaying = true;
      isPaused = false;
    });
    
    // Force sequence to start at beat 0.0 FIRST
    sequence.setBeat(0.0);
    
    // Start native audio engine
    NativeBridge.play();
    sequence.play();
    
    // Start real-time event processing with native timing sync
    _playbackTimer = Timer.periodic(Duration(milliseconds: 2), (timer) {
      _processPlayback();
    });
    
    print('[TIMING-FIX] Real-time playback started with native sync');
  }
  
  void _scheduleAllEventsToNativeEngine() {
    print('[NATIVE-TIMING] Pre-scheduling all events to native audio engine...');
    
    int totalEventsScheduled = 0;
    
    for (final track in tracks) {
      final stepSequencerState = trackStepSequencerStates[track.id];
      if (stepSequencerState == null) continue;
      
      List<SchedulerEvent> trackEvents = [];
      
      // Generate all events for this track
      stepSequencerState.iterateEvents((step, noteNumber, velocity) {
        if (step < stepCount && velocity > 0) {
          final beat = step.toDouble();
          final midiVelocity = (velocity * 127).round().clamp(1, 127);
          
          trackEvents.add(MidiEvent.ofNoteOn(
            beat: beat,
            noteNumber: noteNumber,
            velocity: midiVelocity,
          ));
        }
      });
      
      if (trackEvents.isNotEmpty) {
        // Schedule ALL events for this track at once to native engine
        // This eliminates real-time Dart processing completely
        final scheduled = NativeBridge.scheduleEvents(
          track.id,
          trackEvents,
          GlobalState().sampleRate!,
          tempo,
          0 // Frame offset = 0 for immediate scheduling
        );
        
        totalEventsScheduled += scheduled;
        print('[NATIVE-TIMING] Scheduled $scheduled events for track ${track.id}');
      }
    }
    
    print('[NATIVE-TIMING] Total events pre-scheduled to native engine: $totalEventsScheduled');
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
    print('[DEBUG] Resuming native audio playback from beat $_pausedAtBeat...');
    // Native timing handles resume automatically
    
    setState(() {
      isPlaying = true;
      isPaused = false;
    });
    
    // Ensure engine is running
    NativeBridge.play();
    
    // HIGH-PRECISION TIMING: Use 2ms timer for professional audio timing
    // At 120 BPM, 16th notes are 125ms apart - 2ms timer = 1.6% max jitter (professional grade)
    _playbackTimer = Timer.periodic(Duration(milliseconds: 2), (timer) {
      _processPlayback();
    });
    
    print('[DEBUG] Playback resumed from beat $_pausedAtBeat');
  }
  
  void _stopSimplePlayback() {
    print('[DEBUG] Stopping native audio playback...');
    // Timer cleanup is no longer needed - using native timing
    
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
  
  // Track playback start time to ensure proper position
  DateTime? _playbackStartTime;
  
  void _processPlayback() {
    // Only process if our internal state says we should be playing
    if (!isPlaying) return;
    
    // Initialize playback start time
    if (_playbackStartTime == null) {
      _playbackStartTime = DateTime.now();
    }
    
    // Get native beat from audio engine for accurate timing
    final nativeBeat = sequence.getBeat(true);
    // Position tracking for timing calculations (if needed)
    
    // Position tracking disabled for performance
    
    // REMOVED: Loop boundary event cache clearing (no longer needed without deduplication)
    
    // Update position from native audio engine
    setState(() {
      position = nativeBeat;
    });
    
    // Avoid double-trigger: only dispatch from Dart when native scheduling is disabled (iOS)
    if (!_useNativeScheduling) {
      _processEventsAtBeat(nativeBeat);
    }

    // Robust loop-cycle tracking using absolute frame position
    if (!_useNativeScheduling && isLooping && stepCount > 0) {
      final posFrames = NativeBridge.getPosition();
      final loopLenFrames = (stepCount * (60.0 / tempo) * (GlobalState().sampleRate ?? 44100)).round();
      if (loopLenFrames > 0) {
        final computedCycle = posFrames ~/ loopLenFrames;
        if (computedCycle != _loopCycle) {
          _loopCycle = computedCycle;
          final framesPerBeat = (60.0 / tempo * (GlobalState().sampleRate ?? 44100)).round();
          print('[DIAG] Loop cycle advanced -> cycle=$_loopCycle posFrames=$posFrames loopLenFrames=$loopLenFrames framesPerBeat=$framesPerBeat');
          // Prevent overlap: send All Notes Off (CC123), All Sound Off (CC120), and Sustain Off (CC64=0)
          for (final track in tracks) {
            final msgs = [
              MidiEvent.cc(beat: 0.0, ccNumber: 123, ccValue: 0), // All Notes Off
              MidiEvent.cc(beat: 0.0, ccNumber: 120, ccValue: 0), // All Sound Off
              MidiEvent.cc(beat: 0.0, ccNumber: 64,  ccValue: 0), // Sustain Off
            ];
            NativeBridge.handleEventsNow(track.id, msgs, GlobalState().sampleRate!, tempo);
          }
          // Prune cache each cycle to bound memory and allow fresh dispatch for new cycle
          _processedEvents.clear();
        }
      }
    }
    // no-op
    
    // Check if we've reached the end (only for non-looping mode)
    if (!isLooping && nativeBeat >= stepCount) {
      print('[DEBUG] Reached end: nativeBeat=$nativeBeat stepCount=$stepCount isLooping=$isLooping');
      print('[DEBUG] Stopping playback (loop is OFF)...');
      // Stop playback and reset everything to beginning
      _stopSimplePlayback();
      
      setState(() {
        isPlaying = false;
        position = 0.0;
        isPaused = false;
      });
      
      print('[DEBUG] Single playback ended');
      return;
    }
  }
  
  Set<String> _processedEvents = {}; // Track processed events with position-based deduplication
  
  // PERFORMANCE OPTIMIZATION: Pre-computed event timeline
  List<ScheduledEvent> _eventTimeline = [];
  bool _timelineNeedsRebuild = true;
  double _lastTimelineStepCount = 0;
  double _lastTimelineTempo = 0;
  // Retrigger guard per event key
  final Map<String, int> _lastSentUs = {}; // key -> microseconds
  static const int _minRetriggerUs = 8000; // 8ms guard
  
  void _processEventsAtBeat(double currentBeat) {
    // no-op
    
    // PERFORMANCE OPTIMIZATION: Use pre-computed event timeline instead of scanning all events
    _ensureEventTimeline();
    
    // LOOKAHEAD SCHEDULING: Process events slightly ahead of time to reduce FFI latency
    final lookaheadMs = 5.0; // 5ms lookahead for professional timing
    final lookaheadBeats = (lookaheadMs / 1000.0) * (tempo / 60.0);
    // IMPORTANT: when looping, do NOT look behind at cycle start, to avoid previous-cycle duplicates
    final bool nearLoopStart = isLooping && (currentBeat % stepCount) < 0.25;
    final scheduleWindowStart = nearLoopStart ? currentBeat : currentBeat - 0.2;
    final scheduleWindowEnd = currentBeat + lookaheadBeats + 0.2;
    
    // OPTIMIZED: Process only events in current time window using binary search
    final eventsToProcess = _getEventsInTimeWindow(scheduleWindowStart, scheduleWindowEnd, currentBeat);
    
    for (final scheduledEvent in eventsToProcess) {
      final event = scheduledEvent.event;
      final track = scheduledEvent.track;
      // Snap effectiveBeat to nearest step index to stabilize dedup at integer steps
      final snappedBeat = (scheduledEvent.effectiveBeat).roundToDouble();
      final effectiveBeat = snappedBeat;
      
      // Loop-aware deduplication: include robust loopCycle derived from absolute frames
      final stepIndex = effectiveBeat.floor();
      final eventKey = '${track.id}-${_loopCycle}-step$stepIndex-${event.midiData1}-${event.midiData2}';
      
      final nowUs = DateTime.now().microsecondsSinceEpoch;
      final lastUs = _lastSentUs[eventKey] ?? 0;
      final withinGuard = (nowUs - lastUs) < _minRetriggerUs;
      if (!_processedEvents.contains(eventKey) && !withinGuard) {
        _processedEvents.add(eventKey);
        _lastSentUs[eventKey] = nowUs;
        // SEND log for verification at loop start
        final stepNumber = stepIndex;
        if (DEBUG_SEQUENCER_LOGS && stepNumber == 0 && (event.midiStatus & 0xF0) == 0x90 && event.midiData2 > 0) {
          print('[SEND] loopCycle=${_loopCycle} track=${track.id} step=0 beat=${effectiveBeat.toStringAsFixed(3)} note=${event.midiData1}');
        }
        
        NativeBridge.handleEventsNow(
          track.id,
          [event],
          GlobalState().sampleRate!,
          tempo,
        );
      }
    }
    
    // REMOVED: No longer need to clean up processed events (deduplication disabled)
  }

  handleStop() {
    print('[DEBUG] handleStop called');
    _stopSimplePlayback();
    // Don't clear processed events - let loop-aware deduplication handle it
    
    // Reset position to step 0 and clear pause state
    setState(() {
      position = 0.0;
      isPlaying = false;
      isPaused = false;
    });
    _pausedAtBeat = 0.0;
    sequence.stop();
    
    // PERFORMANCE: Sync all tracks efficiently
    for (final track in tracks) {
      markTrackDirty(track.id);
      syncTrack(track);
    }
    print('[DEBUG] Position reset to 0.0, pause state cleared, all tracks synced after stopping');
  }
  
  @override
  void dispose() {
    _playbackTimer?.cancel();
    ticker.dispose();
    super.dispose();
  }

  handleSetLoop(bool nextIsLooping) {
    print('[DEBUG] handleSetLoop called: $nextIsLooping (current: $isLooping)');
    
    if (nextIsLooping) {
      // NATIVE LOOP: Let native system handle all loop timing
      sequence.setLoop(0, stepCount.toDouble());
      print('[NATIVE-LOOP] Enabled native looping: 0 to ${stepCount} beats');
    } else {
      // NATIVE LOOP: Disable native looping
      sequence.unsetLoop();
      print('[NATIVE-LOOP] Disabled native looping');
    }

    setState(() {
      isLooping = nextIsLooping;
    });
    
    print('[DEBUG] handleSetLoop completed: isLooping=$isLooping');
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
      // PERFORMANCE: Mark all tracks dirty and sync in batch
      for (final track in tracks) {
        markTrackDirty(track.id);
        syncTrack(track);
      }
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

    // PERFORMANCE: Mark track dirty and sync efficiently
    markTrackDirty(trackId);
    syncTrack(track);
    print('[DEBUG] Track marked dirty and synced for real-time editing');
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

  // NATIVE BUFFER PRE-SCHEDULING: Schedule all events upfront instead of real-time
  void _preScheduleAllEvents() {
    print('[NATIVE] Pre-scheduling all events into native buffers...');
    
    final currentTempo = sequence.getTempo();
    final noteDuration = _calculateNoteDuration(currentTempo);
    final sampleRate = 44100; // Default sample rate
    
    int totalEventsScheduled = 0;
    
    for (final track in tracks) {
      final trackId = track.id;
      final stepSequencerState = trackStepSequencerStates[trackId];
      if (stepSequencerState == null) continue;
      
      List<SchedulerEvent> eventsToSchedule = [];
      
      // Use the iterateEvents method to get all velocity data
      stepSequencerState.iterateEvents((step, noteNumber, velocity) {
        if (step < stepCount && velocity > 0) {
          final beat = step.toDouble();
          final midiVelocity = (velocity * 127).round().clamp(1, 127);
          
          // Note ON event
          eventsToSchedule.add(MidiEvent(
            beat: beat,
            midiStatus: 0x90, // Note ON
            midiData1: noteNumber,
            midiData2: midiVelocity,
          ));
          
          // Note OFF event 
          eventsToSchedule.add(MidiEvent(
            beat: beat + noteDuration,
            midiStatus: 0x80, // Note OFF
            midiData1: noteNumber,
            midiData2: 0,
          ));
        }
      });
      
      if (eventsToSchedule.isNotEmpty) {
        // Pre-schedule all events for this track in the native buffer
        final eventsSynced = NativeBridge.scheduleEvents(
          trackId,
          eventsToSchedule,
          sampleRate, 
          currentTempo,
          0, // Frame offset (start immediately)
        );
        
        totalEventsScheduled += eventsToSchedule.length;
        print('[NATIVE] Track $trackId: ${eventsToSchedule.length} events pre-scheduled');
      }
    }
    
    print('[NATIVE] Total $totalEventsScheduled events pre-scheduled across ${tracks.length} tracks');
    print('[NATIVE] Native audio engine now handles all timing and event delivery automatically');
  }

  // PERFORMANCE OPTIMIZATION: Track dirty state and batch updates
  final Map<int, bool> _tracksDirty = {};
  final Map<int, int> _trackEventCounts = {};
  final Map<int, double> _trackLastSyncTempo = {};
  
  void markTrackDirty(int trackId) {
    _tracksDirty[trackId] = true;
    _timelineNeedsRebuild = true;
  }
  
  void syncTrack(Track track) {
    final trackId = track.id;
    final currentTempo = sequence.getTempo();
    final noteDuration = _calculateNoteDuration(currentTempo);
    
    // PERFORMANCE: Skip sync if track hasn't changed and tempo is stable
    final wasTempoChange = (_trackLastSyncTempo[trackId] ?? 0.0 - currentTempo).abs() > 0.01;
    if (!(_tracksDirty[trackId] ?? true) && !wasTempoChange) {
      return; // Track is up to date
    }
    
    // PERFORMANCE: Only clear and rebuild if necessary
    track.clearEvents();
    int noteCount = 0;
    
    trackStepSequencerStates[trackId]!
        .iterateEvents((step, noteNumber, velocity) {
      if (step < stepCount && velocity > 0) {
        noteCount++;
        // Prevent overlap into next loop: clip duration at loop end with epsilon (1 sample) safety
        final remainingBeats = (isLooping ? (stepCount - step) : double.infinity).toDouble();
        final sr = GlobalState().sampleRate ?? 44100;
        final epsilonBeats = (tempo > 0) ? (tempo / (60.0 * sr)) : 0.0; // one-sample in beats
        double maxAllowed = remainingBeats.isFinite ? (remainingBeats - epsilonBeats) : double.infinity;
        if (maxAllowed < 0.01) maxAllowed = 0.01;
        final clippedDuration = remainingBeats.isFinite
            ? dart_math.min(noteDuration, maxAllowed)
            : noteDuration;
        track.addNote(
            noteNumber: noteNumber,
            velocity: velocity,
            startBeat: step.toDouble(),
            durationBeats: clippedDuration);
      }
    });
    
    // PERFORMANCE: Only sync buffer if events actually changed
    final eventCountChanged = (_trackEventCounts[trackId] ?? 0) != noteCount;
    if (eventCountChanged || wasTempoChange) {
      // Avoid double triggers: only schedule to native when using native scheduling mode
      if (_useNativeScheduling) {
        track.syncBuffer();
      }
      _trackEventCounts[trackId] = noteCount;
      _timelineNeedsRebuild = true; // Mark timeline for rebuild
      
      // Only log when there are actual notes to sync
      if (noteCount > 0) {
        print('[DEBUG] Synced track ${trackId}: $noteCount notes (duration: ${noteDuration.toStringAsFixed(2)} beats @ ${currentTempo.toStringAsFixed(0)} BPM)');
      }
    }
    
    // Clear dirty flag and update tempo tracking
    _tracksDirty[trackId] = false;
    _trackLastSyncTempo[trackId] = currentTempo;
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

    // PERFORMANCE: Sync all tracks efficiently
    for (final track in tracks) {
      markTrackDirty(track.id);
      syncTrack(track);
    }
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
    
    // Add all available sound instruments as separate tracks with custom names
    for (var instrument in _availableSoundFonts) {
      print('[DEBUG] Adding instrument: ${instrument['name']} -> ${instrument['path']} (${instrument['type']})');
      
      final instrumentType = instrument['type'] ?? 'sf2';
      String displayName = instrument['name']!;
      
      if (instrumentType == 'sfz') {
        // Create SFZ instrument
        instruments.add(
          CustomSfzInstrument(
            path: instrument['path']!, 
            isAsset: true, 
            tuningPath: instrument['tuning'], // Optional tuning file
            customDisplayName: displayName,
          ),
        );
      } else if (instrumentType == 'audiounit') {
        // Create AudioUnit instrument (iOS only)
        instruments.add(
          CustomAudioUnitInstrument(
            audioUnitId: instrument['path']!,
            customDisplayName: displayName,
          ),
        );
      } else {
        // Create SF2 instrument
        // Use selected preset for General MIDI Bank, default preset for others
        final presetIndex = (instrument['path'] == 'assets/sf2/GeneralUser-GS.sf2') 
            ? _selectedGMPreset 
            : 0;
        
        // Create display name with GM preset info if applicable
        if (instrument['path'] == 'assets/sf2/GeneralUser-GS.sf2') {
          final preset = _generalMidiPresets.firstWhere(
            (p) => p['program'] == _selectedGMPreset,
            orElse: () => {'name': 'Unknown', 'program': 0}
          );
          displayName = 'GM: ${preset['name']}';
        }
        
        instruments.add(
          CustomSf2Instrument(
            path: instrument['path']!, 
            isAsset: true, 
            presetIndex: presetIndex,
            customDisplayName: displayName,
          ),
        );
      }
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
    final currentPausedAtBeat = _pausedAtBeat;
    final backupProcessedEvents = Set<String>.from(_processedEvents);
    
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
        markTrackDirty(track.id);
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
      _processedEvents = backupProcessedEvents;
      
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

  /// Test SFZ playback with a simple melody
  void _testSfzPlayback() {
    if (selectedTrack == null || !(selectedTrack!.instrument is SfzInstrument)) {
      print('[ERROR] Cannot test SFZ - no SFZ track selected');
      return;
    }
    
    print('[DEBUG] 🎵 Testing SFZ playback on track ${selectedTrack!.id}...');
    
    // Stop current playback
    if (isPlaying) {
      handleStop();
    }
    
    // Clear the current track's events
    selectedTrack!.clearEvents();
    
    // Add a simple test melody (C major scale)
    final testNotes = [60, 62, 64, 65, 67, 69, 71, 72]; // C4 to C5
    final noteDuration = 0.4; // Short notes for quick test
    
    for (int i = 0; i < testNotes.length; i++) {
      final noteNumber = testNotes[i];
      final startBeat = i * 0.5; // Play notes every half beat
      
      selectedTrack!.addNote(
        noteNumber: noteNumber,
        velocity: 80, // Medium velocity
        startBeat: startBeat,
        durationBeats: noteDuration,
      );
      
      print('[DEBUG] Added test note: ${noteNumber} at beat ${startBeat}');
    }
    
    // Sync the track
    selectedTrack!.syncBuffer();
    
    // Set up sequencer for test playback
    setState(() {
      stepCount = 8; // Enough steps for our test
    });
    sequence.setEndBeat(stepCount.toDouble());
    
    // Start playback automatically
    print('[DEBUG] 🎵 Starting SFZ test playback...');
    handleTogglePlayPause();
    
    // Show a snackbar to inform the user
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('🎵 Playing SFZ test melody (C major scale)'),
          duration: Duration(seconds: 3),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  /// Test AudioUnit playback with GM presets demonstration
  void _testAudioUnitPlayback() {
    if (selectedTrack == null || !(selectedTrack!.instrument is AudioUnitInstrument)) {
      print('[ERROR] Cannot test AudioUnit - no AudioUnit track selected');
      return;
    }
    
    print('[DEBUG] 🍎 Testing Apple AudioUnit playback on track ${selectedTrack!.id}...');
    
    // Stop current playback
    if (isPlaying) {
      handleStop();
    }
    
    // Clear the current track's events
    selectedTrack!.clearEvents();
    
    // Demo different GM presets with characteristic melodies
    final gmTests = [
      // Piano (0) - C major arpeggio
      {'preset': 0, 'notes': [60, 64, 67, 72], 'name': 'Piano'},
      // Electric Piano (4) - Jazz chord progression
      {'preset': 4, 'notes': [60, 63, 65, 69], 'name': 'Electric Piano'},
      // Violin (40) - Classical melody
      {'preset': 40, 'notes': [67, 69, 71, 72], 'name': 'Violin'},
      // Trumpet (56) - Fanfare
      {'preset': 56, 'notes': [60, 64, 67, 64], 'name': 'Trumpet'},
    ];
    
    final noteDuration = 0.8; // Longer notes to hear each preset
    
    for (int testIndex = 0; testIndex < gmTests.length; testIndex++) {
      final test = gmTests[testIndex];
      final preset = test['preset'] as int;
      final notes = test['notes'] as List<int>;
      final name = test['name'] as String;
      
      // Add program change to switch to this preset (MIDI status 0xC0 = Program Change)
      selectedTrack!.events.add(MidiEvent(
        beat: testIndex * 4.0, // Switch preset every 4 beats
        midiStatus: 0xC0, // Program Change command
        midiData1: preset, // Program number (0-127)
        midiData2: 0, // Unused for Program Change
      ));
      
      // Add the characteristic melody for this preset
      for (int i = 0; i < notes.length; i++) {
        final noteNumber = notes[i];
        final startBeat = testIndex * 4.0 + i * 0.8; // Notes every 0.8 beats
        
        selectedTrack!.addNote(
          noteNumber: noteNumber,
          velocity: 90, // Strong velocity for clear sound
          startBeat: startBeat,
          durationBeats: noteDuration,
        );
        
        print('[DEBUG] Added AudioUnit test: preset $preset ($name) note $noteNumber at beat $startBeat');
      }
    }
    
    // Sync the track
    selectedTrack!.syncBuffer();
    
    // Set up sequencer for test playback (needs 16 beats for all tests)
    setState(() {
      stepCount = 16;
    });
    sequence.setEndBeat(stepCount.toDouble());
    
    // Start playback automatically
    print('[DEBUG] 🍎 Starting Apple AudioUnit test playback...');
    handleTogglePlayPause();
    
    // Show a snackbar to inform the user
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('🍎 Testing Apple AudioUnit: Piano→E.Piano→Violin→Trumpet'),
          duration: Duration(seconds: 5),
          backgroundColor: Colors.orange,
        ),
      );
    }
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
        // SFZ Status Indicator
        if (selectedTrack != null)
          Container(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Container(
              padding: EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: selectedTrack!.instrument is SfzInstrument 
                    ? Colors.green.withValues(alpha: 0.2)
                    : selectedTrack!.instrument is AudioUnitInstrument
                    ? Colors.orange.withValues(alpha: 0.2)
                    : Colors.blue.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: selectedTrack!.instrument is SfzInstrument 
                      ? Colors.green 
                      : selectedTrack!.instrument is AudioUnitInstrument
                      ? Colors.orange
                      : Colors.blue,
                  width: 2,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    selectedTrack!.instrument is SfzInstrument 
                        ? Icons.music_note 
                        : selectedTrack!.instrument is AudioUnitInstrument
                        ? Icons.apple
                        : Icons.audiotrack,
                    color: selectedTrack!.instrument is SfzInstrument 
                        ? Colors.green 
                        : selectedTrack!.instrument is AudioUnitInstrument
                        ? Colors.orange
                        : Colors.blue,
                    size: 20,
                  ),
                  SizedBox(width: 8),
                  Text(
                    selectedTrack!.instrument is SfzInstrument 
                        ? '🎵 SFZ ENGINE ACTIVE (sfizz)' 
                        : selectedTrack!.instrument is AudioUnitInstrument
                        ? '🍎 APPLE AUDIOUNIT ACTIVE (DLS)'
                        : 'SF2 Engine Active',
                    style: TextStyle(
                      color: selectedTrack!.instrument is SfzInstrument 
                          ? Colors.green 
                          : selectedTrack!.instrument is AudioUnitInstrument
                          ? Colors.orange
                          : Colors.blue,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  SizedBox(width: 8),
                  if (selectedTrack!.instrument is SfzInstrument)
                    MaterialButton(
                      minWidth: 80,
                      height: 32,
                      color: Colors.green,
                      child: Text(
                        'Test SFZ',
                        style: TextStyle(color: Colors.white, fontSize: 12),
                      ),
                      onPressed: () => _testSfzPlayback(),
                    ),
                  if (selectedTrack!.instrument is AudioUnitInstrument)
                    MaterialButton(
                      minWidth: 100,
                      height: 32,
                      color: Colors.orange,
                      child: Text(
                        'Test AudioUnit',
                        style: TextStyle(color: Colors.white, fontSize: 12),
                      ),
                      onPressed: () => _testAudioUnitPlayback(),
                    ),
                ],
              ),
            ),
          ),
        // GM Preset Selector (show for General MIDI SF2 or AudioUnit tracks)
        if (selectedTrack?.instrument.idOrPath.contains('GeneralUser-GS.sf2') == true || 
            selectedTrack?.instrument is AudioUnitInstrument)
          Container(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              children: [
                Text(
                  selectedTrack?.instrument is AudioUnitInstrument 
                      ? 'Apple AudioUnit Preset (128 GM Sounds)'
                      : 'General MIDI Preset',
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
          title: const Text('Multi-Instrument Sequencer (SF2 + SFZ)'),
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
  
  
  // PERFORMANCE OPTIMIZATION: Pre-computed event scheduling system
  void _ensureEventTimeline() {
    // Rebuild timeline only when necessary
    if (!_timelineNeedsRebuild && 
        _lastTimelineStepCount == stepCount && 
        (_lastTimelineTempo - tempo).abs() < 0.01) {
      return; // Timeline is up to date
    }
    
    // Performance: Rebuilding event timeline
    _eventTimeline.clear();
    
    // Build sorted timeline of all events
    for (final track in tracks) {
      for (final event in track.events) {
        if (event is MidiEvent) {
          // Skip Program Change events during playback to prevent SF2 reload spam
          if ((event.midiStatus & 0xF0) == 0xC0) {
            continue;
          }
          
          _eventTimeline.add(ScheduledEvent(
            track: track,
            event: event,
            originalBeat: event.beat,
          ));
        }
      }
    }
    
    // Sort by beat for efficient binary search
    _eventTimeline.sort((a, b) => a.originalBeat.compareTo(b.originalBeat));
    
    _timelineNeedsRebuild = false;
    _lastTimelineStepCount = stepCount.toDouble();
    _lastTimelineTempo = tempo;
    
    // Performance: Event timeline built
  }
  
  List<ScheduledEvent> _getEventsInTimeWindow(double windowStart, double windowEnd, double currentBeat) {
    final eventsToProcess = <ScheduledEvent>[];
    
    for (final scheduledEvent in _eventTimeline) {
      final eventBeat = scheduledEvent.originalBeat;
      
      // Calculate effective beat (handle looping robustly)
      double? effectiveBeat;
      if (isLooping) {
        // Only consider current and next cycle candidates. Avoid previous-cycle candidate to prevent duplicates at step 0
        for (final k in [0, 1]) {
          final candidate = eventBeat + k * stepCount;
          if (candidate >= windowStart && candidate <= windowEnd) {
            effectiveBeat = candidate;
            break;
          }
        }
        if (effectiveBeat == null) {
          continue; // Not in window for this cycle
        }
      } else {
        if (eventBeat < windowStart || eventBeat > windowEnd) {
          continue;
        }
        effectiveBeat = eventBeat;
      }
      
      // Create processed event with effective beat
      eventsToProcess.add(ScheduledEvent(
        track: scheduledEvent.track,
        event: scheduledEvent.event,
        originalBeat: scheduledEvent.originalBeat,
        effectiveBeat: effectiveBeat,
      ));
    }
    
    return eventsToProcess;
  }
  
  // REMOVED: Event cleanup method (no longer needed without deduplication)
  
}
