# Android Native Library Loading Guide

## Problem Overview

The Flutter Sequencer plugin relies on a native C++ library (`libflutter_sequencer.so`) that must be properly packaged, distributed, and loaded on Android devices. Several issues can arise in this process:

1. Native libraries not being properly built for all required ABIs (arm64-v8a, armeabi-v7a, x86, x86_64)
2. Libraries not being correctly packaged in the AAR/APK
3. Library naming inconsistencies (`libflutter_sequencer.so` vs `flutter_sequencer.so`)
4. Library loading mechanism failures

## Recent Fixes

We've implemented several improvements to address these issues:

1. **Build System Enhancements**:
   - Improved native library copying in the Gradle build process
   - Added proper ABI structure preservation in the jniLibs directory
   - Created verification tasks to validate library presence
   - Added creation of alternative library names for compatibility

2. **CMake Improvements**:
   - Implemented a backup copy mechanism in CMake to ensure libraries are in the correct locations
   - Added diagnostic output to track ABI and library paths
   
3. **Loading Mechanism Enhancements**:
   - Implemented a multi-step loading approach in `NativeBridge.dart`
   - Added fallback paths and library names
   - Implemented path discovery via method channel

## How Library Loading Works

The library loading process follows these steps:

1. **Build Time**:
   - C++ source code is compiled for each ABI via CMake
   - Libraries are copied to the `src/main/jniLibs/<ABI>/` directories
   - Alternative library names are created as symlinks/copies
   - Libraries are packaged into the AAR/APK

2. **Runtime**:
   - When the plugin initializes, the `NativeBridge` class attempts to load the library
   - First, it tries to get the precise library path via the `getNativeLibraryPath` method channel
   - Then, it tries several library name variations using `DynamicLibrary.open()`
   - If those fail, it attempts to load the library via the platform `System.loadLibrary()` method
   - As a last resort, it tries to access the library via `DynamicLibrary.process()`

## Troubleshooting Steps

If you encounter native library loading issues on Android, follow these steps:

### 1. Verify Library Presence

Run the verification task to check if libraries are properly built and packaged:

```bash
cd android
./gradlew verifyNativeLibraries
```

This will output information about which ABIs have properly built libraries.

### 2. Enable Debug Logging

Enable detailed debug logging in your Flutter application:

```dart
import 'package:flutter_sequencer/native_bridge.dart';

// In your app initialization
NativeBridge.enableDebugLogs = true;
```

This will output detailed loading attempts and errors to the console.

### 3. Check for Library Path Failures

If you see errors like "Failed to load X: dlopen failed", this indicates the library couldn't be found or loaded. Possible solutions:

- Ensure your app is building for the correct ABI that matches your test device
- Check if the library exists in the expected location by examining the app bundle
- Verify permissions on the library files

### 4. Manual Verification

For advanced troubleshooting, you can examine the APK contents:

```bash
# Unzip the APK
unzip app-debug.apk -d apk-contents

# Check for native libraries
ls -la apk-contents/lib/
```

Look for `lib/<ABI>/libflutter_sequencer.so` files.

## Common Errors and Solutions

| Error | Possible Solutions |
|-------|-------------------|
| `UnsatisfiedLinkError: ... libflutter_sequencer.so` | 1. Rebuild the project to ensure libraries are properly packaged<br>2. Check if library is present in the APK<br>3. Try using an alternative loading method |
| Libraries built for wrong architecture | Make sure `abiFilters` in `build.gradle` match your test device |
| Libraries not found in APK | Check that the Gradle copy tasks are running correctly |
| `dlopen failed: library "X" not found` | The library path is incorrectly specified or the library is missing |

## Prevention Strategies

To prevent these issues in your projects:

1. **During Development**:
   - Run with `--debug` flag which has better error reporting
   - Periodically verify the native libraries are being built and packaged correctly
   
2. **CI/CD Setup**:
   - Add a verification step to your CI pipeline
   - Build for all supported ABIs
   
3. **Testing**:
   - Test on multiple device types (emulator and physical)
   - Test on devices with different architectures 