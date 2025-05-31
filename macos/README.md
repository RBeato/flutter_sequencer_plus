# Flutter Sequencer Plus - macOS Implementation

This directory contains the macOS implementation of the Flutter Sequencer Plus plugin.

## Features

- Audio playback using AVFoundation
- SFZ and SF2 soundfont support
- Audio Unit integration
- MIDI input handling

## Setup

1. Ensure you have the following dependencies installed:
   - Xcode 12.0 or later
   - Flutter SDK with macOS desktop support enabled
   - CocoaPods

2. Add the following to your app's `macos/Podfile`:

```ruby
target 'Runner' do
  use_frameworks!
  
  # Add these if not already present
  pod 'libsndfile', '~> 1.0.31'
  pod 'libvorbis', '~> 1.3.7'
  pod 'libogg', '~> 1.3.5'
  pod 'libflac', '~> 1.3.3'
  pod 'opus', '~> 1.3.1'
  pod 'mpg123', '~> 1.29.3'
end
```

3. Run `pod install` in the `macos` directory.

## Building

To build the plugin, run:

```bash
cd example
flutter build macos
```

## Debugging

Common issues and solutions:

1. **Module not found**: Ensure all required headers are included in the module map.
2. **Linker errors**: Check that all dependencies are properly linked in the Xcode project.
3. **Audio Unit registration**: Make sure to call `SfizzAU.registerAU()` during app startup.

## Architecture

The macOS implementation uses the following components:

- `CocoaEngine`: Manages the audio engine and track playback
- `SfizzAU`: Implements the Audio Unit for SFZ playback
- `SwiftFlutterSequencerPlugin`: Handles communication with Flutter

## License

See the main project README for license information.
