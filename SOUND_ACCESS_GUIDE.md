# Flutter Sequencer Plus - Sound Access & Control Guide

## Overview
Flutter Sequencer Plus is a multi-track audio sequencer that loads different instruments (SF2/SFZ) and allows both scheduled playback and real-time triggering. Each instrument becomes a separate track that can be controlled independently.

## Core Architecture

### 1. Sequence → Tracks → Instruments
```
Sequence (tempo, playback control)
├── Track 1 (Piano - j_piano.sf2)
├── Track 2 (Rhodes - rhodes.sf2) 
├── Track 3 (Guitar - Electric_guitar.SF2)
├── Track 4 (Bass - BassGuitars.sf2)
├── Track 5 (Synth - korg.sf2)
├── Track 6 (GM Bank - GeneralUser-GS.sf2)
└── Track 7 (Drums - DrumsSlavo.sf2)
```

### 2. Each Track Can Play Notes Two Ways:
- **Scheduled Events**: Pre-programmed sequences that play during sequence playback
- **Real-time Events**: Immediate note triggering (like piano keys)

## Proper Sound Access Methods

### Method 1: Real-time Note Triggering (Immediate Sound)
```dart
// Get specific track by index (based on order of instrument creation)
final pianoTrack = tracks[0];  // j_piano.sf2
final rhodesTrack = tracks[1]; // rhodes.sf2
final guitaTrack = tracks[2];  // Electric_guitar.SF2

// Play note immediately (like pressing a piano key)
pianoTrack.startNoteNow(
  noteNumber: 60,    // Middle C (MIDI note 0-127)
  velocity: 0.8,     // Volume (0.0-1.0)
);

// Stop note immediately
pianoTrack.stopNoteNow(noteNumber: 60);
```

### Method 2: Scheduled Sequence Playback
```dart
// Add events to track for sequence playback
pianoTrack.addNote(
  noteNumber: 60,        // Middle C
  velocity: 0.8,         // Volume
  startBeat: 0.0,        // When to play (in beats)
  durationBeats: 1.0,    // How long to play
);

// CRITICAL: Must sync after adding events
pianoTrack.syncBuffer();

// Start sequence playback
sequence.play();
```

### Method 3: Track Selection & Control
```dart
// Control which track is active for user input
int selectedTrackIndex = 0;  // Piano
final activeTrack = tracks[selectedTrackIndex];

// Change active track
void selectTrack(int trackIndex) {
  selectedTrackIndex = trackIndex;
  // Now user input goes to tracks[trackIndex]
}

// Play on currently selected track
void playNoteOnSelectedTrack(int noteNumber) {
  final activeTrack = tracks[selectedTrackIndex];
  activeTrack.startNoteNow(
    noteNumber: noteNumber,
    velocity: 0.8,
  );
}
```

## Track Identification & Naming

### Standard Track Order (as created in example):
```dart
final instruments = [
  // Index 0: Piano
  Sf2Instrument(path: 'assets/sf2/j_piano.sf2', isAsset: true),
  
  // Index 1: Rhodes Piano  
  Sf2Instrument(path: 'assets/sf2/rhodes.sf2', isAsset: true),
  
  // Index 2: Electric Guitar
  Sf2Instrument(path: 'assets/sf2/Electric_guitar.SF2', isAsset: true),
  
  // Index 3: Bass Guitars
  Sf2Instrument(path: 'assets/sf2/BassGuitars.sf2', isAsset: true),
  
  // Index 4: Korg Synth
  Sf2Instrument(path: 'assets/sf2/korg.sf2', isAsset: true),
  
  // Index 5: General MIDI Bank (with preset selection)
  Sf2Instrument(path: 'assets/sf2/GeneralUser-GS.sf2', isAsset: true, presetIndex: selectedPreset),
  
  // Index 6: Drums
  Sf2Instrument(path: 'assets/sf2/DrumsSlavo.sf2', isAsset: true),
];
```

### Track Mapping Helper
```dart
// Create a map for easier track access
final Map<String, Track> trackMap = {
  'piano': tracks[0],
  'rhodes': tracks[1], 
  'guitar': tracks[2],
  'bass': tracks[3],
  'synth': tracks[4],
  'gm': tracks[5],
  'drums': tracks[6],
};

// Access tracks by name
trackMap['piano']!.startNoteNow(noteNumber: 60, velocity: 0.8);
trackMap['drums']!.startNoteNow(noteNumber: 36, velocity: 1.0); // Kick drum
```

## Common Control Patterns

### Pattern 1: Instrument Selector with Real-time Play
```dart
class InstrumentController {
  List<Track> tracks;
  int selectedTrackIndex = 0;
  
  // Switch active instrument
  void selectInstrument(int trackIndex) {
    selectedTrackIndex = trackIndex;
  }
  
  // Play note on selected instrument
  void playNote(int midiNote, double velocity) {
    tracks[selectedTrackIndex].startNoteNow(
      noteNumber: midiNote,
      velocity: velocity,
    );
  }
  
  // Stop note on selected instrument  
  void stopNote(int midiNote) {
    tracks[selectedTrackIndex].stopNoteNow(noteNumber: midiNote);
  }
}
```

### Pattern 2: Multi-track Sequencer Grid
```dart
class SequencerGrid {
  List<Track> tracks;
  List<List<bool>> grid; // [track][step] = note on/off
  
  // Toggle step in grid
  void toggleStep(int trackIndex, int stepIndex) {
    grid[trackIndex][stepIndex] = !grid[trackIndex][stepIndex];
    rebuildTrackSequence(trackIndex);
  }
  
  // Rebuild track events from grid
  void rebuildTrackSequence(int trackIndex) {
    final track = tracks[trackIndex];
    track.clearEvents();
    
    for (int step = 0; step < grid[trackIndex].length; step++) {
      if (grid[trackIndex][step]) {
        final beat = (step / 4.0);  // 16th notes
        track.addNote(
          noteNumber: getTrackNote(trackIndex),
          velocity: 0.8,
          startBeat: beat,
          durationBeats: 0.2,
        );
      }
    }
    
    track.syncBuffer(); // Critical!
  }
}
```

### Pattern 3: Real-time MIDI Controller
```dart
class MidiController {
  final Map<String, Track> tracks;
  
  // Route MIDI input to specific tracks
  void handleMidiNote(int channel, int note, int velocity) {
    Track? targetTrack;
    
    switch (channel) {
      case 0: targetTrack = tracks['piano']; break;
      case 1: targetTrack = tracks['rhodes']; break;
      case 9: targetTrack = tracks['drums']; break; // MIDI channel 10
      default: targetTrack = tracks['gm']; break;
    }
    
    if (velocity > 0) {
      targetTrack?.startNoteNow(
        noteNumber: note,
        velocity: velocity / 127.0,
      );
    } else {
      targetTrack?.stopNoteNow(noteNumber: note);
    }
  }
}
```

## MIDI Note Mappings

### Piano/Keyboard Instruments (tracks 0-5)
```dart
// Standard MIDI notes
const int MIDDLE_C = 60;
const int C3 = 48;
const int C4 = 60;  // Middle C
const int C5 = 72;

// Chromatic scale from Middle C
final notes = [60, 61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71]; // C to B
```

### Drum Kit (track 6) - General MIDI Drum Map
```dart
const Map<String, int> DRUM_NOTES = {
  'kick': 36,        // C2
  'snare': 38,       // D2  
  'closedHat': 42,   // F#2
  'openHat': 46,     // A#2
  'crash': 49,       // C#3
  'ride': 51,        // D#3
  'tom1': 50,        // D3
  'tom2': 47,        // B2
  'tom3': 43,        // G2
};

// Play drums
tracks[6].startNoteNow(noteNumber: DRUM_NOTES['kick']!, velocity: 1.0);
```

## Volume & Expression Control

### Per-Track Volume
```dart
// Set track volume (0.0 to 1.0)
tracks[0].changeVolumeNow(volume: 0.5);

// Get current volume
final currentVolume = tracks[0].getVolume();
```

### MIDI Expression Controls
```dart
// Volume (CC 7)
tracks[0].midiCCNow(ccNumber: 7, ccValue: 100);

// Expression (CC 11) 
tracks[0].midiCCNow(ccNumber: 11, ccValue: 80);

// Pan (CC 10) - 0=left, 64=center, 127=right
tracks[0].midiCCNow(ccNumber: 10, ccValue: 64);

// Sustain Pedal (CC 64)
tracks[0].midiCCNow(ccNumber: 64, ccValue: 127); // On
tracks[0].midiCCNow(ccNumber: 64, ccValue: 0);   // Off
```

### Pitch Bend
```dart
// Pitch bend (-1.0 to 1.0)
tracks[0].midiPitchBendNow(value: 0.5);  // Bend up
tracks[0].midiPitchBendNow(value: 0.0);  // Center
tracks[0].midiPitchBendNow(value: -0.5); // Bend down
```

## Common Mistakes & Fixes

### ❌ Wrong: Playing all tracks at once
```dart
// This plays the same note on ALL tracks
for (final track in tracks) {
  track.startNoteNow(noteNumber: 60, velocity: 0.8);
}
```

### ✅ Correct: Play on selected track only
```dart
// This plays on only the selected track
final selectedTrack = tracks[selectedTrackIndex];
selectedTrack.startNoteNow(noteNumber: 60, velocity: 0.8);
```

### ❌ Wrong: Forgetting to sync after adding scheduled events
```dart
track.addNote(...);
sequence.play(); // No sound - events not synced!
```

### ✅ Correct: Always sync after adding events
```dart
track.addNote(...);
track.syncBuffer(); // Critical!
sequence.play(); // Now it works
```

### ❌ Wrong: Mixing real-time and scheduled on same track
```dart
// Adding scheduled events while real-time playing can cause conflicts
track.addNote(noteNumber: 60, ...); // Scheduled
track.startNoteNow(noteNumber: 60, ...); // Real-time - may conflict
```

### ✅ Correct: Use separate tracks or clear events
```dart
// Option 1: Use separate tracks for different purposes
realTimeTrack.startNoteNow(noteNumber: 60, ...);
sequenceTrack.addNote(noteNumber: 60, ...);

// Option 2: Clear scheduled events before real-time use
track.clearEvents();
track.syncBuffer();
track.startNoteNow(noteNumber: 60, ...);
```

## Expected Behavior

### When Working Correctly:
1. **Track Selection**: User can select which instrument/track to play
2. **Real-time Response**: Notes play immediately when triggered
3. **Multiple Tracks**: Each track sounds different (piano vs guitar vs drums)
4. **Volume Control**: Each track can have independent volume
5. **No Conflicts**: Real-time and scheduled events don't interfere

### If You're Getting Sound But Not As Intended:
- **All tracks playing**: Check your track selection logic
- **Wrong instrument sound**: Verify track index mapping
- **Delayed response**: Use `startNoteNow()` instead of scheduled events
- **No track switching**: Ensure you're updating the selected track index
- **Volume issues**: Check per-track volume settings

## Debugging Track Issues
```dart
// Print track information
for (int i = 0; i < tracks.length; i++) {
  print('Track $i: ${tracks[i].instrument.displayName}');
}

// Test each track individually  
void testTrack(int trackIndex) {
  print('Testing track $trackIndex');
  tracks[trackIndex].startNoteNow(noteNumber: 60, velocity: 0.8);
  
  // Stop after 1 second
  Timer(Duration(seconds: 1), () {
    tracks[trackIndex].stopNoteNow(noteNumber: 60);
  });
}
```

This guide should help the other LLM understand exactly how sounds are intended to be accessed and controlled in your Flutter Sequencer Plus implementation.