# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**flutter_sequencer** is a professional-grade Flutter plugin for real-time audio sequencing and multi-track music production. It enables multi-track sequences with various instrument formats (SFZ, SF2, AudioUnit) and provides frame-accurate event scheduling for professional audio applications.

**Key differentiators:**
- Only comprehensive Flutter sequencing solution with professional synthesis capabilities
- Cross-platform SF2/SFZ support using sfizz (industry-standard SFZ player)
- Frame-accurate MIDI event scheduling with real-time safety
- Multi-track sequencing with loop support and automation
- Direct AudioUnit integration on iOS/macOS

## Build Commands

### Initial Setup

```bash
# Android preparation (downloads pre-built native libraries)
cd android && ./prepare_android.sh

# iOS/macOS preparation (downloads xcframeworks)
cd ios && ./prepare.sh
cd macos && ./prepare.sh

# macOS development setup (if needed)
./setup_macos.sh
```

### Development Commands

```bash
# Run example app (drum machine)
cd example
flutter pub get
flutter run -d [device-id]

# Platform targeting examples
flutter run -d android
flutter run -d ios
flutter run -d macos

# Clean rebuild
flutter clean && flutter pub get

# Run tests
flutter test                 # Dart tests
cd cpp_test && cmake . && make && ./build/sequencer_test  # C++ tests (if available)
```

### Platform Requirements

- **Android**: NDK 25.2.9519653+, CMake 3.18.1+, MinSDK 21, Gradle 8.5.0+
- **iOS/macOS**: iOS 13.0+/macOS 10.14+, Xcode 14+, CocoaPods
- **Flutter**: 3.19.0+, Dart SDK 3.0.0+

## Architecture

### Layer Structure

1. **Flutter Dart API** (`lib/`):
   - `sequence.dart`: Main sequencer with tempo, looping, multi-track support
   - `track.dart`: Track management with volume automation and MIDI events
   - `models/events.dart`: MIDI event types with frame-accurate scheduling
   - `models/instrument.dart`: Instrument abstractions for SFZ, SF2, AudioUnit
   - `native_bridge.dart`: FFI bridge to native audio engines
   - `global_state.dart`: Centralized state management for sequences and tracks

2. **Native Audio Layer**:
   - **Android** (`android/src/main/cpp/`): C++ with JNI
     - `AndroidEngine`: Oboe-based low-latency audio output
     - `SoundFontInstrument`: TinySoundFont integration for SF2 playback
     - `Plugin.cpp`: Event handling and track management
   - **iOS/macOS** (`ios/Classes/`, `macos/Classes/`): Swift/ObjC with C++ core
     - `CocoaEngine`: AVAudioEngine integration with position tracking
     - `SwiftFlutterSequencerPlugin`: Platform bridge and AudioUnit support
     - `BaseScheduler`: Real-time event scheduling

3. **Audio Engines**:
   - **sfizz**: Professional SFZ player (cross-platform via xcframeworks/libraries)
   - **TinySoundFont**: SF2 support on Android
   - **AVAudioEngine + AudioUnit**: iOS/macOS native sampler support
   - **Oboe**: Android low-latency audio output

### Key Components

- **Real-time Scheduler**: Lock-free event scheduling with circular buffers
- **FFI Bridge**: High-performance communication between Dart and native code
- **Multi-format Instruments**: Unified API for SFZ, SF2, and AudioUnit instruments
- **Audio-visual Sync**: Position tracking for UI synchronization
- **Performance Optimization**: Platform-specific optimizations for Android/iOS

### Thread Model

- **Main/UI Thread**: Flutter UI, user interactions, state management
- **Audio Thread**: Real-time audio processing, event scheduling (lock-free)
- **Asset Loading**: Background loading of samples and instruments
- **FFI Communication**: Efficient cross-thread messaging without blocking audio

## Important Files & Directories

### Core Implementation
- `lib/sequence.dart`: Main sequencer API with tempo/loop/multi-track management
- `lib/native_bridge.dart`: FFI interface with comprehensive error handling
- `example/lib/main.dart`: Full-featured drum machine demonstrating all capabilities

### Platform-Specific Code
- `android/src/main/cpp/`: Android C++ implementation with TinySoundFont
- `ios/Classes/CocoaEngine.swift`: iOS audio engine with position tracking
- `android/prepare_android.sh`: Downloads optimized native libraries
- `ios/prepare.sh`, `macos/prepare.sh`: Downloads sfizz xcframeworks

### Build Configuration
- `android/build.gradle`: NDK configuration and native build setup
- `ios/flutter_sequencer.podspec`: iOS/macOS CocoaPods specification
- `pubspec.yaml`: Plugin metadata and dependencies

### Assets & Examples
- `example/assets/sf2/`: Professional-quality soundfonts for testing
- `example/assets/sfz/`: SFZ instrument examples with samples

## Current Status & Capabilities

### ✅ **Production Ready Features**
- **Cross-platform audio synthesis** (Android, iOS, macOS)
- **Professional SF2/SFZ playback** with parameter control
- **Real-time MIDI sequencing** with frame-accurate timing
- **Multi-track recording/playback** with volume automation
- **Loop support** with seamless transitions
- **Performance optimized** for mobile devices

### 🔄 **Current Limitations**
- **No SFZ support on iOS** (only SF2 and AudioUnit)
- **Limited audio effects** (basic volume/pan only)
- **No real-time audio analysis** (FFT, waveform visualization)
- **No streaming audio** (large samples must fit in RAM)
- **Documentation gaps** in advanced features

### 📊 **Performance Status**
- **Android**: Excellent performance with TinySoundFont, optimized logging
- **iOS**: Good performance with AVAudioEngine, proper audio-visual sync
- **Latency**: ~10-50ms depending on device (suitable for music production)

## Development Workflow

### Getting Started
1. **Clone repository** and run preparation scripts for target platforms
2. **Use example app** (`cd example && flutter run`) to verify setup
3. **Study drum machine implementation** in `example/lib/main.dart`
4. **Review API documentation** in `lib/sequence.dart` and `lib/track.dart`

### Performance Testing
1. **Test on physical devices** (audio latency varies significantly on emulators)
2. **Monitor logs** for performance warnings during development
3. **Use built-in position tracking** for audio-visual synchronization
4. **Profile memory usage** when loading large soundfonts

### Platform-Specific Development
- **Android**: Focus on TinySoundFont integration, NDK optimization
- **iOS**: Leverage AudioUnit ecosystem, AVAudioEngine features
- **Cross-platform**: Use SF2 format for consistent behavior

### Code Architecture Guidelines
- **Follow FFI patterns** established in `native_bridge.dart`
- **Use real-time safe patterns** (no allocation on audio thread)
- **Handle platform differences** gracefully with fallbacks
- **Maintain audio-visual sync** using position tracking APIs

## Realistic Improvement Opportunities

### **High Impact, Low Effort**
1. **Add real-time audio analysis**: FFT, RMS, peak detection for visualization
2. **Implement MIDI 2.0 support**: High-resolution velocity and timing
3. **Add more synthesis parameters**: Filter cutoff, resonance, LFO control
4. **Improve error handling**: Better timeout management and recovery

### **Medium Impact, Medium Effort**
1. **Streaming audio support**: Load large samples on-demand
2. **Audio effects chain**: Reverb, delay, EQ, compression
3. **Advanced loop features**: Crossfading, tempo sync, quantization
4. **Web platform support**: WebAudio backend implementation

### **High Impact, High Effort**
1. **Audio graph system**: Connect instruments through effect nodes
2. **AI-powered features**: Chord progression generation, audio-to-MIDI
3. **Cloud integration**: Sample streaming, collaborative sequencing
4. **Professional DAW features**: Automation curves, advanced mixing

### **Technical Debt & Optimization**
1. **Comprehensive documentation**: API reference, tutorials, best practices
2. **Test coverage expansion**: Unit tests, integration tests, performance benchmarks
3. **Memory optimization**: Reduce RAM usage for large sample libraries
4. **Cross-platform consistency**: Ensure identical behavior across platforms

## Industry Context (2024/2025)

flutter_sequencer is positioned uniquely in the Flutter ecosystem as the **only comprehensive sequencing solution** with professional-grade synthesis capabilities. While other Flutter audio plugins focus on playback or basic recording, flutter_sequencer provides:

- **Professional synthesis engines** (sfizz integration)
- **Real-time event scheduling** with frame-accurate timing
- **Cross-platform instrument support** (SFZ, SF2, AudioUnit)
- **Production-ready performance** suitable for music applications

The plugin aligns with industry trends toward **cross-platform music production tools** and **mobile-first audio development**, as demonstrated by successful professional apps like Abbey Road's Topline songwriting app.