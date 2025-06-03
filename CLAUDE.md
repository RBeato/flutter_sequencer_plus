# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Flutter Sequencer Plus is a comprehensive Flutter plugin for audio sequencing and synthesis. It enables multi-track sequences with various instrument formats (SFZ, SF2, AudioUnit).

## Build Commands

### Initial Setup

```bash
# macOS development setup
./setup_macos.sh

# Platform-specific preparation
cd android && ./prepare_android.sh  # Downloads Android native libraries
cd ios && ./prepare.sh               # Downloads iOS xcframeworks
cd macos && ./prepare.sh             # Downloads macOS xcframeworks
```

### Development Commands

```bash
# Run example app
cd example
flutter pub get
flutter run -d [platform]  # platform: macos, ios, android

# Clean rebuild
flutter clean
flutter pub get

# Run tests
flutter test                 # Dart tests
cd cpp_test && cmake . && make && ./build/sequencer_test  # C++ tests
```

### Platform-Specific Notes

- **Android**: Requires NDK 25.2.9519653+, CMake 3.18.1+, MinSDK 21, Gradle 8.5.0+
- **iOS/macOS**: Requires iOS 13.0+/macOS 10.14+, Xcode, CocoaPods
- **Native Libraries**: Downloads from GitHub releases, works with dummy libraries for compilation

## Architecture

### Layer Structure

1. **Dart API** (`lib/`): High-level interfaces for sequences, tracks, instruments
   - `sequence.dart`: Main sequencer interface
   - `track.dart`: Track management
   - `models/`: Data models for events, instruments
   - `native_bridge.dart`: FFI interface to native code

2. **Native Layer**:
   - **Android** (`android/src/main/cpp/`): C++ with JNI, uses sfizz + TinySoundFont
   - **iOS/macOS** (`ios/Classes/`, `macos/Classes/`): Swift/ObjC with C++ core
   - **Shared C++**: Scheduler (`BaseScheduler`), CallbackManager, Buffer implementations

3. **Audio Engines**:
   - **sfizz**: Primary SFZ player (cross-platform)
   - **TinySoundFont**: SF2 support on Android
   - **AVAudioEngine**: iOS/macOS audio framework
   - **AudioUnit**: iOS sampler support

### Key Components

- **Scheduler**: Real-time safe event scheduling with lock-free buffers
- **CallbackManager**: Thread-safe callback system for UI updates
- **Instruments**: Abstraction for different audio sources (SFZ, SF2, AudioUnit)
- **Engine**: Platform-specific audio output management

### Thread Model

- Main thread: Flutter UI and API calls
- Audio thread: Real-time audio processing
- Worker threads: Asset loading, file I/O
- Lock-free communication between threads

## Important Files

- `android/prepare_android.sh`: Downloads pre-built Android libraries
- `ios/prepare.sh`, `macos/prepare.sh`: Downloads xcframeworks
- `example/lib/main.dart`: Drum machine example implementation
- `memory-bank/`: Development documentation and progress tracking
- Platform configurations: `android/build.gradle`, `ios/flutter_sequencer.podspec`

## Current Status

- Demo mode fully functional for development
- Production mode requires native library integration
- Active development on macOS support (`mac` branch)
- Example app demonstrates core functionality

## Development Workflow

1. Use platform prepare scripts to download native dependencies
2. Work in demo mode for rapid development
3. Test with example app for integration verification
4. Check memory-bank/ for known issues and progress
5. Follow platform-specific build configurations carefully