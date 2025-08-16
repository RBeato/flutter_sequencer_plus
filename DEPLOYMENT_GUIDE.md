# Flutter Sequencer Plus - Deployment & Testing Guide

## Overview
This guide provides comprehensive instructions for building, testing, and deploying Flutter Sequencer Plus for production use on iOS and Android platforms.

## Prerequisites

### iOS Development
- Xcode 15.0+ with iOS 13.0+ SDK
- Valid Apple Developer Account
- macOS 10.14+ (Mojave) or later
- CocoaPods 1.10+

### Android Development  
- Android Studio with Android SDK 21+
- NDK 25.2.9519653+
- CMake 3.22.1+
- Gradle 8.5.0+

### Flutter Environment
- Flutter 3.0+ (stable channel recommended)
- Dart 2.17+

## Initial Setup

### 1. Clone and Setup
```bash
git clone <repository-url>
cd flutter_sequencer_plus
```

### 2. Platform-Specific Setup

#### iOS Setup
```bash
cd ios
./prepare.sh  # Downloads required xcframeworks
cd ../example/ios
pod install   # Install CocoaPods dependencies
```

#### Android Setup
```bash
cd android
./prepare_android.sh  # Downloads native libraries
```

### 3. Flutter Dependencies
```bash
cd example
flutter pub get
```

## Development & Testing

### Local Development

#### iOS Simulator
```bash
cd example
flutter run -d ios
```

#### iOS Device (Debug)
```bash
# Ensure device is connected and trusted
flutter run -d ios --debug --verbose
```

#### Android Emulator/Device
```bash
flutter run -d android --debug --verbose
```

### Debugging

#### Native iOS Debugging
1. Open `example/ios/Runner.xcworkspace` in Xcode
2. Set breakpoints in Swift/Objective-C code
3. Run project from Xcode for native debugging
4. Use Flutter Inspector for Dart debugging

#### Native Android Debugging
1. Open `example/android` in Android Studio
2. Set breakpoints in Kotlin/Java code
3. Run with debugger attached
4. Use `flutter logs` for real-time logging

#### Debug Configurations
Use the provided `.vscode/launch.json` configurations:
- Flutter (Debug - iOS Simulator)
- Flutter (Debug - iOS Device)
- Flutter (Debug - Android)

### Performance Profiling
```bash
# Profile mode for performance analysis
flutter run --profile -d ios
flutter run --profile -d android
```

## Production Builds

### iOS Production Build

#### 1. Archive Build
```bash
cd example
flutter build ios --release --no-codesign
```

#### 2. Xcode Archive & Upload
1. Open `example/ios/Runner.xcworkspace` in Xcode
2. Select "Any iOS Device" as target
3. Product → Archive
4. Upload to App Store Connect

#### 3. TestFlight Configuration
- Ensure proper entitlements are set in `Runner.entitlements`
- Audio permissions configured in `Info.plist`
- Background audio capability enabled

### Android Production Build

#### 1. Release APK
```bash
cd example
flutter build apk --release
```

#### 2. App Bundle (Recommended for Play Store)
```bash
flutter build appbundle --release
```

#### 3. Signing Configuration
Update `example/android/app/build.gradle.kts`:
```kotlin
signingConfigs {
    release {
        storeFile file('path/to/keystore.jks')
        storePassword 'your-store-password'
        keyAlias 'your-key-alias'
        keyPassword 'your-key-password'
    }
}
```

## Troubleshooting Common Issues

### iOS Issues

#### 1. Sfizz Framework Loading Issues
- Ensure xcframeworks are properly downloaded via `prepare.sh`
- Check that `ENABLE_BITCODE = NO` in build settings
- Verify entitlements allow JIT compilation

#### 2. Audio Session Issues
- Verify background audio capability is enabled
- Check microphone permission if using audio input
- Ensure proper audio session category in native code

#### 3. TestFlight Rejection
- Review entitlements for security compliance
- Ensure no debug symbols in release build
- Check for proper code signing

### Android Issues

#### 1. Native Library Loading
- Ensure NDK version matches requirements (25.2.9519653)
- Check ABI filters match target devices
- Verify native libraries exist in APK

#### 2. Audio Permissions
- Add required audio permissions to manifest
- Request runtime permissions for audio features
- Test on various Android versions (21+)

#### 3. CMake Build Issues
- Verify CMake version compatibility
- Check NDK path configuration
- Ensure proper C++ standard flags

## Performance Optimization

### Audio Latency
- iOS: Configure audio session for low latency
- Android: Use AAUDIO API where available
- Both: Minimize buffer sizes while avoiding dropouts

### Memory Management
- Monitor memory usage during long sessions
- Implement proper cleanup in native code
- Use profiling tools to identify leaks

### Battery Usage
- Optimize audio processing for efficiency
- Use appropriate wake locks sparingly
- Monitor background processing

## Testing Strategy

### Unit Tests
```bash
flutter test
```

### Integration Tests
```bash
flutter test integration_test/
```

### Device Testing Matrix
- iOS: iPhone 8+ to iPhone 15 Pro
- Android: Minimum API 21, test on various manufacturers
- Audio: Test with different audio hardware configurations

### TestFlight Beta Testing
1. Upload build via Xcode
2. Configure test groups
3. Collect crash reports and feedback
4. Iterate based on tester feedback

### Play Store Internal Testing
1. Upload AAB to Play Console
2. Configure internal test track
3. Share with internal testers
4. Monitor crash reports in Play Console

## Deployment Checklist

### Pre-Release
- [ ] All unit tests passing
- [ ] Integration tests validated
- [ ] Performance profiling completed
- [ ] Memory leak testing done
- [ ] Audio functionality verified on target devices
- [ ] Permissions properly configured
- [ ] Native libraries bundled correctly

### iOS Release
- [ ] Build archived successfully
- [ ] Code signing configured
- [ ] TestFlight testing completed
- [ ] App Store review guidelines followed
- [ ] Privacy policy updated if needed

### Android Release
- [ ] Release build generated
- [ ] APK/AAB signed properly
- [ ] Google Play requirements met
- [ ] Internal testing completed
- [ ] Target API level compliance verified

## Monitoring & Analytics

### Crash Reporting
- iOS: Xcode Organizer, Firebase Crashlytics
- Android: Play Console, Firebase Crashlytics

### Performance Monitoring
- Use Flutter Observatory for Dart performance
- Monitor native performance with platform tools
- Track audio-specific metrics (latency, dropouts)

### User Analytics
- Implement analytics for feature usage
- Monitor audio engine performance metrics
- Track user engagement patterns

## Support & Maintenance

### Regular Updates
- Keep Flutter SDK updated
- Update native dependencies as needed
- Monitor for security vulnerabilities

### User Support
- Maintain comprehensive documentation
- Provide clear error messages
- Implement proper logging for debugging

This guide ensures professional-grade deployment and testing for Flutter Sequencer Plus across all target platforms and environments.