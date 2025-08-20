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

// FFI symbols are exported directly from Swift using @_cdecl
// The dummy references ensure they won't be stripped
