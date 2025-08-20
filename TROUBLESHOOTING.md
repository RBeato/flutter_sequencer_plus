# Flutter Sequencer Plus - Troubleshooting Guide

## No Sound When Importing Package Into Your Project

If the example app works but your own project has no sound, here are the most common issues:

### 1. Missing Asset Configuration ⚠️ **CRITICAL**

Your `pubspec.yaml` **must** include the SF2/SFZ assets:

```yaml
flutter:
  assets:
    - assets/sf2/        # Your soundfont files
    - assets/sfz/        # Your SFZ files (if using)
    - assets/sfz/samples/ # SFZ sample files (if using)
```

**Without this, the package cannot load any sounds!**

### 2. Missing Soundfont Files 🎵

You need to copy the actual SF2/SFZ files to your project:

```bash
# Copy soundfont files to your project
mkdir -p your_project/assets/sf2/
cp flutter_sequencer_plus/example/assets/sf2/*.sf2 your_project/assets/sf2/

# If using SFZ instruments
mkdir -p your_project/assets/sfz/samples/
cp -r flutter_sequencer_plus/example/assets/sfz/* your_project/assets/sfz/
```

### 3. Engine Initialization Issue 🔧

The audio engine must be properly initialized:

```dart
// WRONG - Missing engine initialization
final sequence = Sequence(tempo: 120.0, endBeat: 16.0);
final tracks = await sequence.createTracks([...]);

// CORRECT - Wait for engine to be ready
final sequence = Sequence(tempo: 120.0, endBeat: 16.0);

// Option 1: Use the factory method that waits for engine
final tracks = await sequence.createTracks(instruments);

// Option 2: Manually check engine state
if (!Sequence.globalState.isEngineReady) {
  Sequence.globalState.onEngineReady(() async {
    // Engine is ready, now create tracks
    final tracks = await sequence.createTracks(instruments);
  });
}
```

### 4. Track Synchronization Issue 📊

**Always sync tracks after adding events:**

```dart
// WRONG - Events not synced to audio engine
track.addNote(noteNumber: 60, velocity: 0.8, startBeat: 0.0, durationBeats: 1.0);
sequence.play(); // No sound because events weren't synced

// CORRECT - Sync events before playback
track.addNote(noteNumber: 60, velocity: 0.8, startBeat: 0.0, durationBeats: 1.0);
track.syncBuffer(); // This is critical!
sequence.play();
```

### 5. Platform-Specific Issues 📱

#### Android
- Ensure you have the required permissions in `android/app/src/main/AndroidManifest.xml`:
```xml
<uses-permission android:name="android.permission.RECORD_AUDIO" />
<uses-permission android:name="android.permission.MODIFY_AUDIO_SETTINGS" />
```

#### iOS
- Audio session must be configured. Add to your `main.dart`:
```dart
import 'package:flutter_sequencer/flutter_sequencer.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // iOS: Configure audio session
  if (Platform.isIOS) {
    GlobalState().setKeepEngineRunning(true);
  }
  
  runApp(MyApp());
}
```

### 6. Common Code Issues 💻

#### Missing Instrument Validation
```dart
// WRONG - No error checking
final tracks = await sequence.createTracks([
  Sf2Instrument(path: 'assets/sf2/piano.sf2', isAsset: true),
]);
final track = tracks.first; // Might be null!

// CORRECT - Check for successful track creation
final tracks = await sequence.createTracks([
  Sf2Instrument(path: 'assets/sf2/piano.sf2', isAsset: true),
]);

if (tracks.isEmpty) {
  print('ERROR: Failed to create tracks - check debug console');
  return;
}
```

#### Using Enhanced Error Reporting
```dart
// Use the new error reporting API for detailed debugging
final result = await sequence.createTracksWithErrorInfo([
  Sf2Instrument(path: 'assets/sf2/piano.sf2', isAsset: true),
]);

if (result.hasErrors) {
  for (final error in result.errors) {
    print('Error: ${error.type.name} - ${error.message}');
    if (error.filePath != null) print('File: ${error.filePath}');
    if (error.technicalDetails != null) print('Details: ${error.technicalDetails}');
  }
}
```

### 7. Debugging Steps 🔍

**Step 1: Check Console Output**
Look for these error messages:
- `"[ERROR] SF2 Load FAILED: Cannot open asset"`
- `"[ERROR] Asset normalization failed"`
- `"[ERROR] Native handle_events_now call failed"`

**Step 2: Verify Assets Are Accessible**
```dart
import 'package:flutter/services.dart';

// Test if your SF2 file is accessible
try {
  final data = await rootBundle.load('assets/sf2/piano.sf2');
  print('SF2 file found: ${data.lengthInBytes} bytes');
} catch (e) {
  print('SF2 file NOT found: $e');
}
```

**Step 3: Test with Minimal Example**
```dart
import 'package:flutter_sequencer/flutter_sequencer.dart';

void testAudio() async {
  // Create sequence
  final sequence = Sequence(tempo: 120.0, endBeat: 4.0);
  
  // Create track with error reporting
  final result = await sequence.createTracksWithErrorInfo([
    Sf2Instrument(path: 'assets/sf2/piano.sf2', isAsset: true, presetIndex: 0),
  ]);
  
  if (result.hasErrors) {
    print('Errors: ${result.errors}');
    return;
  }
  
  final track = result.tracks.first;
  
  // Add a simple note
  track.addNote(
    noteNumber: 60, // Middle C
    velocity: 0.8,
    startBeat: 0.0,
    durationBeats: 1.0,
  );
  
  // CRITICAL: Sync before play
  track.syncBuffer();
  
  // Play
  sequence.play();
  
  print('Audio test started - should hear middle C');
}
```

### 8. Platform Requirements 📋

#### Minimum Requirements
- **Android**: API 21+, NDK 25.2.9519653+
- **iOS**: iOS 13.0+
- **macOS**: macOS 10.14+

#### Required Dependencies
```yaml
dependencies:
  flutter_sequencer:
    git:
      url: https://github.com/RBeato/flutter_sequencer_plus.git
      ref: main  # or specific commit
  ffi: ^2.1.0
```

### 9. Quick Fix Checklist ✅

When you have no sound, check in this order:

1. ✅ Assets are declared in `pubspec.yaml`
2. ✅ SF2/SFZ files exist in `assets/sf2/` directory
3. ✅ Called `track.syncBuffer()` after adding events
4. ✅ Engine is ready before creating tracks
5. ✅ No error messages in console
6. ✅ Track creation succeeded (not null/empty)
7. ✅ Device volume is up and not muted
8. ✅ App has audio permissions (Android)

### 10. Working Example Structure 📁

```
your_project/
├── pubspec.yaml (with assets declared)
├── assets/
│   └── sf2/
│       ├── piano.sf2
│       ├── drums.sf2
│       └── other_soundfonts.sf2
└── lib/
    └── main.dart (with proper initialization)
```

## Still Having Issues? 🆘

If you've checked everything above and still have no sound:

1. **Enable debug logging** in your main.dart:
```dart
void main() {
  // Enable all debug output
  GlobalState().setKeepEngineRunning(true);
  runApp(MyApp());
}
```

2. **Compare with working example**: The `example/` folder is a complete working implementation
3. **Test on different devices**: Sometimes emulators have audio issues
4. **Check GitHub issues**: https://github.com/RBeato/flutter_sequencer_plus/issues

## Common Error Messages & Solutions 🚨

| Error Message | Solution |
|---------------|----------|
| `"Cannot open asset"` | Add assets to pubspec.yaml and verify files exist |
| `"Asset normalization failed"` | Check asset paths and ensure files are in correct directory |
| `"Timeout adding SF2 track"` | File may be corrupted or too large |
| `"Invalid preset index"` | Use preset index within valid range (usually 0-127) |
| `"Track creation returned null"` | Instrument loading failed - check console for details |
| No error but no sound | Missing `track.syncBuffer()` call |