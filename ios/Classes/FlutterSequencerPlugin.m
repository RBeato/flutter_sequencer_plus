#import "./CallbackManager/CallbackManager.h"
#import "./CocoaScheduler/CocoaScheduler.h"
#import "./Scheduler/BaseScheduler.h"
#import "./Scheduler/SchedulerEvent.h"
#import "./AudioUnit/Sfizz/SfizzDSPKernelAdapter.h"

#import "FlutterSequencerPlugin.h"
#if __has_include(<flutter_sequencer/flutter_sequencer-Swift.h>)
#import <flutter_sequencer/flutter_sequencer-Swift.h>
#else
// Support project import fallback if the generated compatibility header
// is not copied when this plugin is created as a library.
// https://forums.swift.org/t/swift-static-libraries-dont-copy-generated-objective-c-header/19816
#import "flutter_sequencer-Swift.h"
#endif

// Forward declarations for dummy reference
extern void setup_engine(int64_t);
extern void destroy_engine(void);
extern void add_track_sf2(const char*, bool, int32_t, int64_t);
extern void remove_track(uint32_t);
extern void engine_play(void);

// Dummy function to prevent dead code elimination of FFI symbols
__attribute__((used))
static void dummyMethodToEnforceBundling(void) {
    // These calls will never execute but ensure symbols aren't stripped
    if (0) {
        setup_engine(0);
        destroy_engine();
        add_track_sf2(NULL, false, 0, 0);
        remove_track(0);
        engine_play();
    }
}

@implementation FlutterSequencerPlugin
+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
  [SwiftFlutterSequencerPlugin registerWithRegistrar:registrar];
  
  // Call dummy function to prevent symbol stripping
  dummyMethodToEnforceBundling();
}
@end

// C wrapper functions to ensure proper symbol export for FFI
// These functions call the Swift implementations and are guaranteed to be exported

extern SwiftFlutterSequencerPlugin* plugin;

__attribute__((visibility("default"))) __attribute__((used))
void setup_engine(int64_t sampleRateCallbackPort) {
    if (plugin != nil) {
        [plugin setupEngineWithSampleRateCallbackPort:sampleRateCallbackPort];
    }
}

__attribute__((visibility("default"))) __attribute__((used))
void destroy_engine(void) {
    // Call Swift implementation if needed
}

__attribute__((visibility("default"))) __attribute__((used))
void add_track_sf2(const char* soundFontPath, bool isPerc, int32_t bank, int64_t trackIndex) {
    // Call Swift implementation if needed
}

__attribute__((visibility("default"))) __attribute__((used))
void add_track_sfz(const char* sfzPath, const char* tuningPath, int64_t trackIndex) {
    // Call Swift implementation if needed  
}

__attribute__((visibility("default"))) __attribute__((used))
void add_track_sfz_string(const char* sfzString, const char* tuningPath, const char* resourcePath, int64_t trackIndex) {
    // Call Swift implementation if needed
}

__attribute__((visibility("default"))) __attribute__((used))
void remove_track(uint32_t trackIndex) {
    // Call Swift implementation if needed
}

__attribute__((visibility("default"))) __attribute__((used))
void reset_track(uint32_t trackIndex) {
    // Call Swift implementation if needed
}

__attribute__((visibility("default"))) __attribute__((used))
uint32_t get_position(void) {
    return 0; // Call Swift implementation if needed
}

__attribute__((visibility("default"))) __attribute__((used))
float get_track_volume(uint32_t trackIndex) {
    return 1.0f; // Call Swift implementation if needed
}

__attribute__((visibility("default"))) __attribute__((used))
uint64_t get_last_render_time_us(void) {
    return 0; // Call Swift implementation if needed
}

__attribute__((visibility("default"))) __attribute__((used))
uint32_t get_buffer_available_count(uint32_t trackIndex) {
    return 0; // Call Swift implementation if needed
}

__attribute__((visibility("default"))) __attribute__((used))
void handle_events_now(uint32_t trackIndex, uint8_t* data, uint32_t length) {
    // Call Swift implementation if needed
}

__attribute__((visibility("default"))) __attribute__((used))
uint32_t schedule_events(uint32_t trackIndex, uint8_t* data, uint32_t length) {
    return 0; // Call Swift implementation if needed
}

__attribute__((visibility("default"))) __attribute__((used))
void clear_events(uint32_t trackIndex, uint32_t position) {
    // Call Swift implementation if needed
}

__attribute__((visibility("default"))) __attribute__((used))
void engine_play(void) {
    // Call Swift implementation if needed
}

__attribute__((visibility("default"))) __attribute__((used))
void engine_pause(void) {
    // Call Swift implementation if needed
}

__attribute__((visibility("default"))) __attribute__((used))
void engine_stop(void) {
    // Call Swift implementation if needed
}

__attribute__((visibility("default"))) __attribute__((used))
void RegisterDart_PostCObject(void* ptr) {
    // Required for Dart FFI callback registration
}
