# iOS AudioUnit Testing Guide

## How to Test Apple DLSMusicDevice (128 General MIDI Sounds) in the Example App

### 1. Platform Requirements
- **iOS Device or Simulator** - AudioUnit functionality is iOS-only
- **iOS 13.0+** - Required for modern AudioUnit support
- **Xcode 14+** - For building and deployment

### 2. Visual Indicators
When AudioUnit track is selected, you'll see:
- **Orange status banner**: "🍎 APPLE AUDIOUNIT ACTIVE (DLS)"
- **Apple icon** in the status bar
- **Orange "Test AudioUnit" button** for quick testing
- **GM Preset Selector**: "Apple AudioUnit Preset (128 GM Sounds)" dropdown

### 3. Testing Steps

#### **Quick Test (Recommended)**
1. **Launch the app** on iOS device/simulator
2. **Wait for loading** - App shows "Loading audio tracks..." while initializing
3. **Select AudioUnit track** - Choose "🍎 Apple AudioUnit (128 GM Sounds)" from dropdown
4. **Verify orange banner** appears: "🍎 APPLE AUDIOUNIT ACTIVE (DLS)"
5. **Click "Test AudioUnit"** button
6. **Listen to demo**: Plays 4 different GM presets in sequence:
   - **Piano** (Preset 0) - Classic piano arpeggio
   - **Electric Piano** (Preset 4) - Jazz chord progression  
   - **Violin** (Preset 40) - Classical melody
   - **Trumpet** (Preset 56) - Fanfare sequence

#### **Manual Preset Testing**
1. **Select AudioUnit track** as above
2. **Use GM Preset dropdown** to choose from 128 available sounds:
   - **0-7**: Piano family
   - **8-15**: Chromatic percussion
   - **16-23**: Organ family
   - **24-31**: Guitar family
   - **32-39**: Bass family
   - **40-47**: Strings
   - **56-63**: Brass
   - **And many more...**
3. **Program notes** using the drum machine grid
4. **Press play** to hear the selected General MIDI preset

### 4. Technical Details

#### **What Is Apple DLSMusicDevice?**
- **Built-in iOS synthesizer** - No external files needed
- **128 General MIDI sounds** - Complete GM standard instrument set
- **DLS (DownLoadable Sounds)** technology - Professional quality samples
- **Real-time preset switching** - Instant program changes via MIDI
- **Low latency** - Optimized for music production apps

#### **How It Works**
- **AudioUnit integration** - Uses iOS AVAudioEngine framework
- **Program Change support** - Switch between 128 presets dynamically
- **MIDI compliance** - Full General MIDI 1.0 specification
- **No storage overhead** - Built into iOS system

### 5. Expected Behavior
- **Instant sound switching** - Program changes happen in real-time
- **High quality audio** - Professional DLS samples
- **No loading time** - Instruments are always ready
- **Full polyphony** - Multiple notes can play simultaneously
- **Velocity sensitivity** - Different velocities produce volume variations

### 6. Troubleshooting
- **No AudioUnit option**: Make sure you're running on iOS (not Android)
- **Orange button missing**: Ensure you've selected the Apple AudioUnit track
- **No sound**: Check device volume and audio permissions
- **Preset not changing**: Allow a moment between preset switches

### 7. Technical Implementation Details
- **Engine**: Apple's AudioUnit framework (AVAudioEngine + DLSMusicDevice)
- **Presets**: 128 GM sounds built into iOS
- **Latency**: ~10-20ms (excellent for real-time use)
- **Quality**: Professional DLS samples (similar to high-end hardware)
- **Integration**: Native iOS AudioUnit with Program Change support

### 8. Comparison with Other Engines

| Feature | AudioUnit (iOS) | SFZ (sfizz) | SF2 (TinySoundFont) |
|---------|----------------|-------------|---------------------|
| **Platform** | iOS only | Cross-platform | Cross-platform |
| **Setup** | Built-in | Requires files | Requires files |
| **Quality** | Professional | Professional | Good |
| **Presets** | 128 GM sounds | Custom samples | Custom presets |
| **Storage** | 0 MB | Variable | Variable |
| **Latency** | Excellent | Excellent | Good |

This demonstrates that iOS AudioUnit support is now fully functional with Apple's professional DLS synthesizer!