# TODO - Flutter Sequencer Plus

## macOS Platform Fixes Needed

### Remaining C++ Compilation Errors in SfizzAU.mm

The macOS build is very close to working. Only 4 small C++ compilation errors remain in `/macos/Classes/AudioUnit/Sfizz/SfizzAU.mm`:

#### 1. C++11 Initialization Syntax Error
**File:** `SfizzAU.mm:10`
```cpp
// Current (broken):
std::atomic_bool _isInitialized{false};

// Fix needed:
std::atomic_bool _isInitialized;
// Then initialize in constructor: _isInitialized = false;
```

#### 2. Enum Name Mismatch
**File:** `SfizzAU.mm:134`
```cpp
// Current (broken):
if (event->head.eventType == AURenderEventTypeMIDI) {

// Fix needed:
if (event->head.eventType == AURenderEventMIDI) {
```

#### 3. AudioBufferList Member Access Issue
**File:** `SfizzAU.mm:173`
```cpp
// Current (broken):
float *outputR = outputData->mNumberChannels > 1 ? (float *)outputData->mBuffers[1].mData : outputL;

// Fix needed: Access channel count differently or restructure the logic
// AudioBufferList doesn't have mNumberChannels member
```

#### 4. Function Signature Mismatch
**File:** `SfizzAU.mm:182`
```cpp
// Current (broken):
sfz->renderBlock(0, outputL, outputR, frameCount);

// Fix needed: Check sfizz API documentation for correct signature
// Current sfizz expects: renderBlock(float** buffers, size_t numFrames, int numOutputs = 1)
```

#### 5. Missing Method Implementation
**File:** `SfizzAU.mm:18`
```cpp
// Warning: method definition for 'setMaximumFramesToRender:' not found
// Need to implement this method in the @implementation section
```

### Additional macOS Tasks

#### 6. Implement Missing Scheduler Function
**File:** `CocoaEngine.swift:165`
```swift
// TODO: Implement SchedulerSetAudioUnit functionality
// SchedulerSetAudioUnit(scheduler, trackIndex, avAudioUnit.audioUnit)
```
This function was commented out because it doesn't exist in the BaseScheduler. Need to either:
- Implement this function in the scheduler
- Find alternative way to connect AudioUnits to the scheduler
- Remove if not needed for macOS AudioUnit integration

## Status

### ✅ Completed (Working Platforms)
- **Android**: Builds and works correctly
- **iOS**: Builds and works correctly  
- **Package Self-Contained**: Works as dependency from git/pub

### 🔧 In Progress
- **macOS**: 95% complete, just needs the above C++ fixes

## Build Commands

```bash
# Test current builds
flutter build apk          # ✅ Works
flutter build ios --no-codesign  # ✅ Works  
flutter build macos        # ❌ Fails with above errors

# After fixing the above issues:
flutter build macos        # Should work
```

## Architecture Notes

The macOS implementation uses:
- `DEFINES_MODULE = NO` to avoid CocoaPods module conflicts
- Custom bridging header for Swift/C++ interop
- Shared C++ core with iOS (BaseScheduler, CallbackManager)
- AVAudioEngine + AudioUnit integration
- sfizz engine for SFZ file support

## Priority

**Medium Priority**: The core functionality works on Android and iOS. macOS is additional platform support that can be completed when time allows.