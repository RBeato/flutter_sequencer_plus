# Technical Context

## Technologies Used

### Flutter/Dart
- **Flutter SDK**: Used as the primary framework for cross-platform UI
- **Dart**: Primary programming language for the Flutter application and plugin interface
- **Flutter Plugin Architecture**: Used to create the platform-specific implementations

### iOS
- **Swift/Objective-C**: Used for the iOS implementation
- **AVAudioEngine**: Core audio engine for iOS implementation
- **sfizz**: Library for SFZ format instrument support
- **XCode**: Development environment for iOS
- **CocoaPods**: Dependency management
- **AudioUnit**: For iOS instrument support

### Android
- **Kotlin/Java**: Used for the Android implementation
- **JNI (Java Native Interface)**: For interfacing with native C++ code
- **OpenSL ES**: For low-level audio on Android
- **sfizz**: Library for SFZ format instrument support
- **TinySoundFont**: Library for SF2 format support on Android
- **Android NDK**: Native Development Kit for C++ compilation

### C++
- **C++14**: Used for cross-platform core functionality
- **CMake**: Build system for C++ code
- **BaseScheduler**: Core shared C++ scheduler implementation
- **sfizz C++ API**: For SFZ parsing and playback

## Development Setup

### Requirements
- Flutter SDK (latest stable version)
- Android Studio with NDK
- Xcode (for iOS development)
- CMake (for C++ compilation)
- CocoaPods (for iOS dependencies)

### Key Files and Directories
- **ios/**: Contains iOS-specific implementation
  - **Classes/**: Core C++ and Objective-C++ implementation
  - **prepare.sh**: Script to download and build sfizz
  - **overrides.xcconfig**: Architecture configuration for iOS builds
  - **third_party/sfizz/**: sfizz library integration

- **android/**: Contains Android-specific implementation
  - **src/main/**: Kotlin/Java implementation
  - **src/main/cpp/**: C++ native code for Android
  - **third_party/**: External library dependencies (sfizz, TinySoundFont)

- **lib/**: Dart API implementation
  - **models/**: Data models for instruments and events
  - **sequence.dart**: Core sequencing functionality
  - **track.dart**: Track implementation

- **example/**: Example application demonstrating the plugin functionality
  - **lib/components/**: UI components for the example app
  - **lib/main.dart**: Main example application entry point
  - **assets/sf2/**: Sample SoundFont assets

## Technical Constraints

### Architecture Compatibility
- iOS builds must support both arm64 (devices) and x86_64 (simulators)
- Fat libraries must be created to support both architectures
- Xcode build settings must be configured properly to exclude architectures as needed

### Real-time Audio Processing
- Audio processing must occur on a dedicated audio thread
- Audio callbacks must be real-time safe (no memory allocation, locks, etc.)
- Sample buffering requires careful synchronization

### Native Library Integration
- sfizz must be properly integrated on both platforms
- Library paths and version compatibility must be managed
- Build scripts must handle platform-specific compilation

### Asset Management
- SFZ and SF2 assets must be properly bundled and accessible
- Asset paths must be properly normalized and URL-encoded
- iOS and Android have different approaches to asset loading

## Dependencies

### External Libraries
- **sfizz**: SFZ format parsing and playback (https://sfz.tools/sfizz/)
- **TinySoundFont**: SF2 format support for Android
- **CMake**: Build system for C++ code
- **FlutterFFI**: For direct native code access (potential future improvement)

### Critical Paths
- Native audio engine initialization
- Instrument loading and initialization
- Audio thread management
- Event scheduling and processing

## Architecture Overview

The flutter_sequencer plugin uses a layered architecture:

1. **Dart API Layer**: Provides the developer-facing API for sequencing and instrument control
2. **Platform Channel Layer**: Communicates between Dart and native code
3. **Platform-specific Layer**: Implements platform-specific audio functionality
4. **Core C++ Layer**: Shared functionality for scheduling and audio processing
5. **Audio Backend Layer**: Platform-specific audio output (AVAudioEngine for iOS, OpenSL ES for Android)

### Data Flow
1. User creates a Sequence and adds Tracks with Instruments
2. Events (notes, volume changes) are scheduled on Tracks
3. Native code processes events and generates audio
4. Audio output is routed through platform-specific audio APIs 