# Flutter Sequencer Plus - API Reference

A comprehensive Flutter plugin for real-time audio sequencing and synthesis with multi-track support and various instrument formats.

## Table of Contents

- [Installation](#installation)
- [Quick Start](#quick-start)
- [Core Concepts](#core-concepts)
- [API Reference](#api-reference)
  - [Sequence](#sequence)
  - [Track](#track) 
  - [Instruments](#instruments)
  - [Events](#events)
  - [Global State](#global-state)
- [Usage Examples](#usage-examples)
- [Platform Support](#platform-support)
- [Performance Considerations](#performance-considerations)

## Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  flutter_sequencer: ^1.0.0
```

Run `flutter pub get` to install the package.

## Quick Start

```dart
import 'package:flutter_sequencer/flutter_sequencer.dart';

// Create a sequence
final sequence = Sequence(
  tempo: 120.0,
  endBeat: 16.0, // 4 bars in 4/4 time
);

// Create instruments
final kickDrum = Sf2Instrument(
  path: 'assets/drums.sf2',
  isAsset: true,
  presetIndex: 36, // GM Kick drum
);

// Create tracks
final tracks = await sequence.createTracks([kickDrum]);
final kickTrack = tracks.first;

// Add events
kickTrack.addNote(
  noteNumber: 36,
  velocity: 0.8,
  startBeat: 0.0,
  durationBeats: 0.25,
);

// Sync and play
kickTrack.syncBuffer();
sequence.play();
```

## Core Concepts

### Sequence
A `Sequence` represents a complete musical arrangement with multiple tracks, tempo, looping, and playback controls.

### Track
A `Track` belongs to a sequence and contains scheduled events for a specific instrument.

### Instrument
An `Instrument` defines the sound source (SFZ, SF2, or AudioUnit) that will render audio for a track.

### Events
`Events` are scheduled musical actions like note on/off, volume changes, and MIDI control changes.

## API Reference

### Sequence

The main controller for multi-track audio sequencing.

#### Constructor

```dart
Sequence({
  required double tempo,
  required double endBeat,
})
```

- `tempo`: Beats per minute (BPM)
- `endBeat`: Final beat where the sequence stops

#### Properties

```dart
bool isPlaying           // Current playback state
double tempo            // Current tempo in BPM
double endBeat          // End position in beats
double pauseBeat        // Position when paused
LoopState loopState     // Current loop state
double loopStartBeat    // Loop start position
double loopEndBeat      // Loop end position
```

#### Methods

**Playback Control**

```dart
void play()                    // Start playback
void pause()                   // Pause playback
void stop()                    // Stop and reset to beginning
void setBeat(double beat)      // Jump to specific beat position
```

**Track Management**

```dart
Future<List<Track>> createTracks(List<Instrument> instruments)
Future<TracksCreationResult> createTracksWithErrorInfo(List<Instrument> instruments)
List<Track> deleteTrack(Track track)
List<Track> getTracks()
```

**Tempo and Timing**

```dart
void setTempo(double nextTempo)
double getBeat([bool estimateFramesSinceLastRender = true])
double getTempo()
```

**Looping**

```dart
void setLoop(double loopStartBeat, double loopEndBeat)
void unsetLoop()
```

**State Queries**

```dart
bool getIsPlaying()
bool getIsOver()
```

**Cleanup**

```dart
void destroy()  // Release all resources
```

#### Usage Example

```dart
final sequence = Sequence(tempo: 120.0, endBeat: 32.0);

// Set up looping
sequence.setLoop(0.0, 16.0);

// Control playback
sequence.play();
await Future.delayed(Duration(seconds: 10));
sequence.pause();
sequence.setBeat(8.0);  // Jump to beat 8
sequence.play();
```

### Track

Represents an individual instrument track with events and real-time control.

#### Properties

```dart
final Sequence sequence     // Parent sequence
final int id               // Unique track identifier
final Instrument instrument // Associated instrument
final List<SchedulerEvent> events // Scheduled events
```

#### Static Methods

```dart
static Future<Track?> build({
  required Sequence sequence,
  required Instrument instrument,
})

static Future<InstrumentLoadResult<Track>> buildWithErrorInfo({
  required Sequence sequence,
  required Instrument instrument,
})
```

#### Real-time Event Methods

**Note Control**

```dart
void startNoteNow({
  required int noteNumber,    // MIDI note (0-127)
  required double velocity,   // Velocity (0.0-1.0)
})

void stopNoteNow({
  required int noteNumber,
})
```

**MIDI Control**

```dart
void midiCCNow({
  required int ccNumber,     // MIDI CC number (0-127)
  required int ccValue,      // CC value (0-127)
})

void midiPitchBendNow({
  required double value,     // Pitch bend (-1.0 to 1.0)
})
```

**Volume Control**

```dart
void changeVolumeNow({
  required double volume,    // Volume level (0.0-1.0)
})

double getVolume()          // Get current volume
```

#### Scheduled Event Methods

**Note Events**

```dart
void addNote({
  required int noteNumber,
  required double velocity,
  required double startBeat,
  required double durationBeats,
})

void addNoteOn({
  required int noteNumber,
  required double velocity,
  required double beat,
})

void addNoteOff({
  required int noteNumber,
  required double beat,
})
```

**MIDI Events**

```dart
void addMidiCC({
  required int ccNumber,
  required int ccValue,
  required double beat,
})

void addMidiPitchBend({
  required double value,
  required double beat,
})
```

**Volume Events**

```dart
void addVolumeChange({
  required double volume,
  required double beat,
})
```

**Event Management**

```dart
void clearEvents()                    // Clear all scheduled events
void syncBuffer([int? absoluteStartFrame, int maxEventsToSync])  // Sync events to engine
```

#### Usage Example

```dart
// Simple usage (current behavior)
final tracks = await sequence.createTracks([
  Sf2Instrument(path: 'assets/piano.sf2', isAsset: true),
]);
if (tracks.isNotEmpty) {
  final pianoTrack = tracks.first;
}

// Enhanced error reporting
final result = await sequence.createTracksWithErrorInfo([
  Sf2Instrument(path: 'assets/piano.sf2', isAsset: true),
  Sf2Instrument(path: 'assets/invalid.sf2', isAsset: true),
]);

print('${result.summary}');
for (final error in result.errors) {
  print('Error: $error');
}

if (result.tracks.isNotEmpty) {
  final pianoTrack = result.tracks.first;
}

// Add scheduled notes
pianoTrack.addNote(
  noteNumber: 60,  // Middle C
  velocity: 0.7,
  startBeat: 0.0,
  durationBeats: 1.0,
);

// Real-time note triggering
pianoTrack.startNoteNow(
  noteNumber: 64,  // E
  velocity: 0.8,
);

// MIDI control
pianoTrack.midiCCNow(ccNumber: 7, ccValue: 100);  // Volume

// Sync changes
pianoTrack.syncBuffer();
```

### Instruments

#### Base Class

```dart
abstract class Instrument {
  final String idOrPath;      // File path or identifier
  final bool isAsset;         // Whether instrument is in assets
  final int presetIndex;      // Preset/program number
  
  String get displayName;     // User-friendly name
}
```

#### SfzInstrument

For SFZ format instruments using the sfizz engine.

```dart
class SfzInstrument extends Instrument {
  final String? tuningPath;   // Optional Scala tuning file
  
  SfzInstrument({
    required String path,
    required bool isAsset,
    this.tuningPath,
  });
}
```

**Usage:**

```dart
final guitar = SfzInstrument(
  path: 'assets/instruments/guitar.sfz',
  isAsset: true,
  tuningPath: 'assets/tuning/just_intonation.scl',
);
```

#### RuntimeSfzInstrument

For dynamically generated SFZ instruments.

```dart
class RuntimeSfzInstrument extends Instrument {
  final String sampleRoot;     // Root directory for samples
  final Sfz sfz;              // SFZ configuration object
  final String? tuningString; // Scala tuning content
  
  RuntimeSfzInstrument({
    required String id,
    required bool isAsset,
    required this.sampleRoot,
    required this.sfz,
    this.tuningString,
  });
}
```

**Usage:**

```dart
final drumKit = RuntimeSfzInstrument(
  id: 'custom_drums',
  isAsset: true,
  sampleRoot: 'assets/samples/drums/',
  sfz: Sfz()
    ..regions.add(SfzRegion()
      ..sample = 'kick.wav'
      ..keyRange = SfzRange(36, 36)
      ..velocityRange = SfzRange(1, 127)),
);
```

#### Sf2Instrument

For SoundFont 2 (.sf2) instruments.

```dart
class Sf2Instrument extends Instrument {
  Sf2Instrument({
    required String path,
    required bool isAsset,
    int presetIndex = 0,      // GM instrument number
  });
}
```

**Usage:**

```dart
final piano = Sf2Instrument(
  path: 'assets/soundfonts/piano.sf2',
  isAsset: true,
  presetIndex: 0,  // Acoustic Grand Piano
);

final drums = Sf2Instrument(
  path: 'assets/soundfonts/drums.sf2',
  isAsset: true,
  presetIndex: 128,  // Standard drum kit
);
```

#### AudioUnitInstrument (iOS/macOS Only)

For Apple AudioUnit instruments.

```dart
class AudioUnitInstrument extends Instrument {
  AudioUnitInstrument({
    required String manufacturerName,
    required String componentName,
  });
}
```

**Usage:**

```dart
final auSampler = AudioUnitInstrument(
  manufacturerName: 'Apple',
  componentName: 'AUSampler',
);
```

### Events

#### Base Event Class

```dart
abstract class SchedulerEvent {
  double beat;                // Beat position
  final int type;             // Event type constant
  
  static const MIDI_EVENT = 0;
  static const VOLUME_EVENT = 1;
}
```

#### MidiEvent

Represents MIDI messages (notes, CC, pitch bend, etc.).

```dart
class MidiEvent extends SchedulerEvent {
  final int midiStatus;       // MIDI status byte
  final int midiData1;        // First data byte
  final int midiData2;        // Second data byte
  
  // Factory constructors
  static MidiEvent ofNoteOn({
    required double beat,
    required int noteNumber,   // 0-127
    required int velocity,     // 0-127
  })
  
  static MidiEvent ofNoteOff({
    required double beat,
    required int noteNumber,   // 0-127
  })
  
  static MidiEvent cc({
    required double beat,
    required int ccNumber,     // 0-127
    required int ccValue,      // 0-127
  })
  
  static MidiEvent pitchBend({
    required double beat,
    required double value,     // -1.0 to 1.0
  })
}
```

#### VolumeEvent

Represents track volume changes.

```dart
class VolumeEvent extends SchedulerEvent {
  final double? volume;       // Volume level (0.0-1.0)
  
  VolumeEvent({
    required double beat,
    required this.volume,
  });
}
```

### Global State

The `GlobalState` singleton manages engine lifecycle and shared resources.

```dart
class GlobalState {
  bool get isEngineReady      // Engine initialization status
  int? get sampleRate         // Audio sample rate
  
  void onEngineReady(Function callback)  // Register engine ready callback
}
```

**Access via Sequence:**

```dart
final globalState = Sequence.globalState;
if (globalState.isEngineReady) {
  // Engine is ready for use
}
```

## Usage Examples

### Basic Drum Machine

```dart
class DrumMachine {
  late Sequence sequence;
  late Track kickTrack, snareTrack, hihatTrack;
  
  Future<void> initialize() async {
    sequence = Sequence(tempo: 120.0, endBeat: 16.0);
    
    final tracks = await sequence.createTracks([
      Sf2Instrument(path: 'assets/drums.sf2', isAsset: true, presetIndex: 36), // Kick
      Sf2Instrument(path: 'assets/drums.sf2', isAsset: true, presetIndex: 38), // Snare  
      Sf2Instrument(path: 'assets/drums.sf2', isAsset: true, presetIndex: 42), // Hi-hat
    ]);
    
    kickTrack = tracks[0];
    snareTrack = tracks[1]; 
    hihatTrack = tracks[2];
    
    // Program basic pattern
    createBasicPattern();
  }
  
  void createBasicPattern() {
    // Kick on beats 1 and 3
    for (int bar = 0; bar < 4; bar++) {
      kickTrack.addNote(
        noteNumber: 36,
        velocity: 0.8,
        startBeat: bar * 4.0,
        durationBeats: 0.1,
      );
      kickTrack.addNote(
        noteNumber: 36,
        velocity: 0.8,
        startBeat: bar * 4.0 + 2.0,
        durationBeats: 0.1,
      );
    }
    
    // Snare on beats 2 and 4
    for (int bar = 0; bar < 4; bar++) {
      snareTrack.addNote(
        noteNumber: 38,
        velocity: 0.7,
        startBeat: bar * 4.0 + 1.0,
        durationBeats: 0.1,
      );
      snareTrack.addNote(
        noteNumber: 38,
        velocity: 0.7,
        startBeat: bar * 4.0 + 3.0,
        durationBeats: 0.1,
      );
    }
    
    // Hi-hat on every eighth note
    for (double beat = 0; beat < 16; beat += 0.5) {
      hihatTrack.addNote(
        noteNumber: 42,
        velocity: 0.5,
        startBeat: beat,
        durationBeats: 0.1,
      );
    }
    
    // Sync all tracks
    kickTrack.syncBuffer();
    snareTrack.syncBuffer();
    hihatTrack.syncBuffer();
  }
  
  void play() => sequence.play();
  void pause() => sequence.pause();
  void stop() => sequence.stop();
}
```

### Real-time Instrument Controller

```dart
class LiveInstrument {
  late Sequence sequence;
  late Track instrumentTrack;
  
  Future<void> initialize(Instrument instrument) async {
    sequence = Sequence(tempo: 120.0, endBeat: 999.0);
    
    final tracks = await sequence.createTracks([instrument]);
    instrumentTrack = tracks.first;
    
    // Start sequence for real-time events
    sequence.play();
  }
  
  void playNote(int noteNumber, double velocity) {
    instrumentTrack.startNoteNow(
      noteNumber: noteNumber,
      velocity: velocity,
    );
  }
  
  void stopNote(int noteNumber) {
    instrumentTrack.stopNoteNow(noteNumber: noteNumber);
  }
  
  void setVolume(double volume) {
    instrumentTrack.changeVolumeNow(volume: volume);
  }
  
  void bendPitch(double amount) {
    instrumentTrack.midiPitchBendNow(value: amount);
  }
}
```

### Step Sequencer with Grid

```dart
class StepSequencer {
  late Sequence sequence;
  late List<Track> tracks;
  final int steps = 16;
  final int trackCount = 8;
  
  List<List<bool>> pattern = [];  // [track][step]
  List<double> trackVolumes = [];
  
  Future<void> initialize(List<Instrument> instruments) async {
    sequence = Sequence(tempo: 120.0, endBeat: 4.0);  // 1 bar
    tracks = await sequence.createTracks(instruments);
    
    // Initialize pattern grid
    pattern = List.generate(trackCount, (_) => List.filled(steps, false));
    trackVolumes = List.filled(trackCount, 0.8);
    
    sequence.setLoop(0.0, 4.0);  // Loop 1 bar
  }
  
  void toggleStep(int trackIndex, int stepIndex) {
    pattern[trackIndex][stepIndex] = !pattern[trackIndex][stepIndex];
    updateTrackPattern(trackIndex);
  }
  
  void updateTrackPattern(int trackIndex) {
    final track = tracks[trackIndex];
    track.clearEvents();
    
    for (int step = 0; step < steps; step++) {
      if (pattern[trackIndex][step]) {
        final beat = (step / steps) * 4.0;  // Convert step to beat
        
        track.addNote(
          noteNumber: 60 + trackIndex,  // Different notes per track
          velocity: trackVolumes[trackIndex],
          startBeat: beat,
          durationBeats: 0.1,
        );
      }
    }
    
    track.syncBuffer();
  }
  
  void setTrackVolume(int trackIndex, double volume) {
    trackVolumes[trackIndex] = volume;
    tracks[trackIndex].changeVolumeNow(volume: volume);
  }
  
  void play() => sequence.play();
  void pause() => sequence.pause();
}
```

## Platform Support

| Platform | SFZ | SF2 | AudioUnit | Notes |
|----------|-----|-----|-----------|-------|
| Android  | ✅  | ✅  | ❌        | Uses sfizz + TinySoundFont |
| iOS      | ✅  | ✅  | ✅        | Native AVAudioEngine |
| macOS    | ✅  | ✅  | ✅        | Native AVAudioEngine |
| Web      | ❌  | ❌  | ❌        | Not supported |
| Windows  | ❌  | ❌  | ❌        | Not supported |
| Linux    | ❌  | ❌  | ❌        | Not supported |

### Platform-Specific Notes

**Android:**
- Requires NDK 25.2.9519653+
- Uses C++ native libraries
- SF2 support via TinySoundFont
- SFZ support via sfizz

**iOS/macOS:**
- Native AVAudioEngine integration
- AudioUnit support for system instruments
- Better performance and lower latency
- Built-in SF2 support via Apple's SoundFont AudioUnit

## Error Handling

### Enhanced Error Reporting (New)

The package now provides detailed error information for invalid instrument files:

```dart
// Check individual track creation
final trackResult = await Track.buildWithErrorInfo(
  sequence: sequence,
  instrument: Sf2Instrument(path: 'assets/drums.sf2', isAsset: true),
);

if (trackResult.isError) {
  final error = trackResult.error!;
  print('Failed to load instrument:');
  print('  Type: ${error.type.name}');
  print('  Message: ${error.message}');
  if (error.filePath != null) print('  File: ${error.filePath}');
  if (error.technicalDetails != null) print('  Details: ${error.technicalDetails}');
}

// Check multiple track creation
final result = await sequence.createTracksWithErrorInfo(instruments);
if (result.hasErrors) {
  print('Some instruments failed to load:');
  for (final error in result.errors) {
    print('- ${error.message} (${error.filePath})');
  }
}
```

### Error Types

| Error Type | Description | Common Causes |
|------------|-------------|---------------|
| `fileNotFound` | File does not exist | Wrong path, file missing |
| `invalidFormat` | Corrupted or invalid file | Bad SF2/SFZ, unsupported version |
| `assetNotFound` | Asset not in bundle | Missing from pubspec.yaml |
| `presetIndexInvalid` | Preset index out of range | Index > available presets |
| `timeout` | Loading took too long | Large file, slow storage |
| `audioEngineError` | Audio system error | Platform-specific issue |

### Console Output

Error details are also logged to console:

```
[ERROR] SF2 Load FAILED: Cannot open asset drums.sf2
[ERROR] SF2 Invalid preset index 200 (max: 127), using preset 0
[ERROR] NativeBridge: Timeout adding SF2 track: large_soundfont.sf2
```

## Performance Considerations

### Real-time Safety

The audio engine operates on a separate real-time thread. Follow these guidelines:

1. **Avoid blocking operations** in audio callbacks
2. **Pre-allocate** memory where possible
3. **Use lock-free** communication patterns
4. **Minimize** string operations in hot paths

### Buffer Management

```dart
// Sync events before playback
track.syncBuffer();

// For real-time changes during playback
track.addNote(...);
track.syncBuffer();  // Sync immediately
```

### Memory Optimization

```dart
// Clean up when done
sequence.destroy();

// Clear events when not needed
track.clearEvents();
```

### Threading Model

- **Main Thread**: Flutter UI and API calls
- **Audio Thread**: Real-time audio processing  
- **Worker Threads**: Asset loading and file I/O
- **Lock-free Communication**: Between threads via circular buffers

### Best Practices

1. **Preload instruments** before playback
2. **Batch event changes** and sync once
3. **Use appropriate buffer sizes** for your latency requirements
4. **Monitor CPU usage** in debug builds
5. **Test on target hardware** for performance validation

---

For more examples and advanced usage, see the `/example` directory in the package repository.