# Flutter Sequencer Modernization & Migration Checklist

> **Purpose:** Update the plugin for compatibility with Flutter 3.19+, Dart 3.x, and modern plugin structure, with minimal, precise changes.  
> **Scope:** iOS & Android, plugin code, build systems, and documentation.

---

## 1. pubspec.yaml Modernization

- [x] Update `environment:` to:
  ```yaml
  environment:
    sdk: '>=3.0.0 <4.0.0'
    flutter: '>=3.19.0'
  ```
- [x] Update all dependencies to latest compatible versions (especially `ffi`, `path`, and dev dependencies).
- [x] Remove deprecated `pedantic` (replace with `lints` or `flutter_lints`).
- [ ] Ensure the `plugin:` section is correct for both platforms.

---

## 2. Dart Code Modernization

- [ ] Ensure all Dart code is migrated to null safety (already appears to be, but verify).
- [ ] Update any deprecated APIs or patterns for Dart 3.x.
- [ ] Run `dart fix --apply` and `dart analyze` to resolve all issues.
- [x] Update `analysis_options.yaml` to use recommended lints.

---

## 3. Android Modernization

- [x] Ensure the plugin uses the new Android embedding (FlutterPlugin interface, not old registrar).
- [x] Update `android/build.gradle` and `android/gradle/wrapper/gradle-wrapper.properties` to use the latest stable Gradle and Android Gradle Plugin (AGP) versions supported by Flutter 3.19+.
- [x] Update `android/src/main/kotlin/com/michaeljperri/flutter_sequencer/FlutterSequencerPlugin.kt` to use modern plugin registration. *(No legacy Registrar code found; only FlutterPlugin interface is used.)*
- [x] Verify and update `CMakeLists.txt` for compatibility with NDK r25+ and CMake 3.22+.
- [x] Remove any deprecated Gradle or manifest settings.
- [x] Test stub and production native library loading on multiple device types.
- [x] Migrate Android example app to plugins block for Gradle (Flutter 3.16+ compatibility).
- [x] Add pluginManagement block to example/android/settings.gradle for Flutter Gradle plugin resolution (Flutter 3.16+).
- [x] Specify version '1.0.0' for dev.flutter.flutter-gradle-plugin in plugins block (Flutter 3.16+).

---

## 4. iOS Modernization

- [ ] Update `ios/flutter_sequencer.podspec` for compatibility with CocoaPods 1.12+ and Xcode 15+.
  - [x] Podspec cleaned up and modernized (duplicate xcconfig removed, deployment target checked, comments added).
  - [x] Ensure the C API bridge (`CallbackManager.h`, `CocoaScheduler.h`, `SchedulerEvent.h`) is properly exposed via `module.modulemap` (created and referenced in podspec as 'FlutterSequencerBridge').
- [x] Verify Swift/Objective-C bridging and plugin registration uses the latest patterns. (Modern hybrid Swift/ObjC registration, C API bridge via module.modulemap, and up-to-date FlutterPlugin protocol.)
- [ ] Test multi-architecture builds (arm64, x86_64) for device and simulator.
  - [ ] Test on Apple Silicon and Intel Macs for simulator compatibility.
  - [ ] Test on real iOS devices for arm64 compatibility.
- [x] Update asset and bundle handling for iOS 17+ compatibility. (Asset lookup now uses Bundle(for: ...) for framework and iOS 17+ compatibility, with fallback to Bundle.main.)
- [x] Fix iOS header/modulemap issues (public headers now copied, module map works, no more 'header not found' errors)
- [ ] Fix AudioUnit framework linker error (build fails at link time with 'Framework AudioUnit not found').
  - [ ] Ensure 'AudioUnit' is listed in the podspec's s.frameworks or s.weak_frameworks, and in the Xcode project 'Link Binary With Libraries' section.

---

## 5. Plugin Structure & Registration

- [ ] Confirm the plugin structure is compatible with federated plugins (if not, document for future refactor).
- [ ] Ensure platform registration is correct in both `pubspec.yaml` and platform code.

---

## 6. Example App & Testing

- [x] Update the example app to use the latest Flutter and Dart versions.
- [ ] Test all core features (sequencing, instrument loading, playback, automation) on both iOS and Android.
- [ ] Add or update integration/unit tests as needed.
- [ ] Test in both demo and production modes.

---

## 7. Documentation

- [ ] Update `README.md` with new minimum Flutter/Dart requirements and migration notes.
- [ ] Update `CHANGELOG.md` with all migration changes.
- [ ] Ensure all public APIs are documented and usage examples are up to date.

---

## 8. Build & Release

- [ ] Run `flutter pub upgrade` and `flutter pub outdated` to ensure all dependencies are current.
- [ ] Run `flutter build` for iOS and Android to verify successful builds.
- [ ] Test on real devices and simulators/emulators for both platforms.
- [ ] Tag and release a new version (e.g., `0.5.0`).

---

## 9. Optional (Recommended for Future)

- [ ] Consider splitting into a federated plugin structure for easier maintenance.
- [ ] Migrate Android code to Kotlin (if any Java remains).
- [ ] Migrate iOS code to Swift (if any Objective-C remains).
- [ ] Add CI/CD for automated testing on both platforms.

---

# References

- [Flutter Upgrade Guide](https://docs.flutter.dev/release/upgrade)
- [Federated Plugin Structure](https://docs.flutter.dev/packages-and-plugins/developing-packages#federated-plugins)
- [Android Plugin Migration](https://docs.flutter.dev/development/packages-and-plugins/plugin-api-migration)
- [Dart Null Safety Migration](https://dart.dev/null-safety/migration-guide)

---

**Instructions:**  
Check off each item as you complete it. For any issues, consult the referenced documentation or the memory bank for project-specific patterns and constraints. 