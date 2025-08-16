#ifndef FlutterSequencer_Bridging_Header_h
#define FlutterSequencer_Bridging_Header_h

// Include necessary headers for Swift/C++ interop
#import <Foundation/Foundation.h>
#import <CoreAudio/CoreAudio.h>
#import <AudioToolbox/AudioToolbox.h>
#import <CoreAudioKit/CoreAudioKit.h>

// Include C++ headers that need to be exposed to Swift
#ifdef __cplusplus
extern "C" {
#endif

// Include your C++ headers here
#include "CallbackManager/CallbackManager.h"
#include "Scheduler/BaseScheduler.h"
#include "Scheduler/Buffer.h"
#include "Scheduler/SchedulerEvent.h"
#include "IInstrument/IInstrument.h"
#include "AudioUnit/Sfizz/SfizzDSPKernelAdapter.h"

#ifdef __cplusplus
}
#endif

#endif /* FlutterSequencer_Bridging_Header_h */
