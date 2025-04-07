# Product Context

## Why This Project Exists

Flutter Sequencer exists to bring powerful audio sequencing capabilities to Flutter applications. There's a significant gap in the Flutter ecosystem for music production and sequencing tools, and this project aims to fill that gap by providing:

1. A high-quality audio engine for music production applications
2. Support for professional audio formats including SFZ and SF2
3. Multi-track sequencing with precise timing control
4. An easy-to-use API for Flutter developers

This plugin enables app developers to create music creation tools, interactive music learning applications, game audio engines, and other music-centric applications using Flutter.

## Problems It Solves

### For Developers
1. **Audio Integration Complexity**: Simplifies the complexity of integrating audio engines with Flutter by providing a ready-to-use solution
2. **Cross-Platform Consistency**: Ensures consistent audio behavior across both iOS and Android platforms
3. **Sample Format Support**: Provides support for industry-standard sample formats without requiring developers to implement their own parsers
4. **Sequencing Logic**: Eliminates the need to implement complex timing and sequencing logic

### For End Users
1. **Music Creation**: Enables users to create music through sequencing interfaces
2. **Interactive Learning**: Allows for interactive music education applications
3. **Game Audio**: Provides dynamic audio capabilities for games
4. **Live Performance**: Supports real-time performance applications

## How It Should Work

### Core Functionality

1. **Instrument Management**:
   - Load instruments from soundfonts (SF2) or SFZ files
   - Support both bundled assets and user-provided files
   - Provide flexible preset selection for soundfonts

2. **Sequencing**:
   - Create multi-track sequences
   - Schedule notes with precise timing
   - Control playback (play, pause, stop)
   - Support looping with customizable loop points
   - Allow tempo control

3. **Real-time Control**:
   - Trigger notes in real-time for live performance
   - Change track volume dynamically
   - Add MIDI CC and pitch bend events

4. **Automation**:
   - Schedule volume changes over time
   - Support MIDI CC automation for parameter control

### User Workflow

1. **Setup**:
   ```dart
   // Create a sequence
   final sequence = Sequence(tempo: 120.0, endBeat: 16.0);
   
   // Create tracks with instruments
   final tracks = await sequence.createTracks([
     Sf2Instrument(path: "assets/sf2/piano.sf2", isAsset: true),
     Sf2Instrument(path: "assets/sf2/drums.sf2", isAsset: true)
   ]);
   ```

2. **Adding Notes**:
   ```dart
   // Add notes to a track
   tracks[0].addNote(
     noteNumber: 60,  // Middle C
     velocity: 0.7,   // 70% velocity
     startBeat: 0.0,  // Start at beginning
     durationBeats: 1.0 // One beat duration
   );
   ```

3. **Controlling Playback**:
   ```dart
   // Start playback
   sequence.play();
   
   // Pause playback
   sequence.pause();
   
   // Stop and rewind
   sequence.stop();
   
   // Set loop points
   sequence.setLoop(0.0, 8.0); // Loop first 8 beats
   ```

4. **Real-time Control**:
   ```dart
   // Trigger a note immediately
   track.startNoteNow(noteNumber: 60, velocity: 0.7);
   
   // Stop a note immediately
   track.stopNoteNow(noteNumber: 60);
   
   // Change volume immediately
   track.changeVolumeNow(volume: 0.5);
   ```

## User Experience Goals

1. **Low Latency**: Audio should trigger with minimal perceivable delay
2. **Stability**: The plugin should be stable and avoid audio glitches or crashes
3. **Ease of Use**: Simple, intuitive API for basic functionality
4. **Flexibility**: Advanced options available for more complex use cases
5. **Resource Efficiency**: Minimal battery and CPU usage

## Target Applications

1. **Music Production Apps**: DAW-like applications for mobile music creation
2. **Music Education**: Interactive applications for learning music
3. **Games**: Games with dynamic, sequenced audio
4. **Interactive Media**: Applications combining audio with other media
5. **Performance Tools**: Live performance applications for musicians

## Future Possibilities

1. **Audio Effects**: Add support for audio effects like reverb and delay
2. **Audio Graph**: Create a full audio graph with mixing and routing
3. **Audio Recording**: Support recording of audio input
4. **Web Support**: Extend to web platform
5. **MIDI Device Integration**: Connect to external MIDI hardware
6. **More Instrument Formats**: Support additional sample formats

The Flutter Sequencer project provides a solid foundation for audio and music applications in the Flutter ecosystem, addressing a significant gap in current Flutter capabilities. 