#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import <Flutter/Flutter.h>
#import "AudioUnit/Sfizz/SfizzDSPKernelAdapter.h"
#import "CallbackManager/CallbackManager.h"
#import "Scheduler/SchedulerEvent.h"

extern "C" {

// Sfizz DSP Kernel Adapter functions
SfizzDSPKernelAdapter* createSfizzDSPKernelAdapter(void) {
    return [[SfizzDSPKernelAdapter alloc] init];
}

AUAudioUnitBus* sfizz_adapter_get_input_bus(SfizzDSPKernelAdapter* adapter) {
    return adapter.inputBus;
}

AUAudioUnitBus* sfizz_adapter_get_output_bus(SfizzDSPKernelAdapter* adapter) {
    return adapter.outputBus;
}

AUAudioFrameCount sfizz_adapter_get_maximum_frames(SfizzDSPKernelAdapter* adapter) {
    return adapter.maximumFramesToRender;
}

void sfizz_adapter_set_maximum_frames(SfizzDSPKernelAdapter* adapter, AUAudioFrameCount frames) {
    adapter.maximumFramesToRender = frames;
}

void sfizz_adapter_allocate_render_resources(SfizzDSPKernelAdapter* adapter) {
    [adapter allocateRenderResources];
}

void sfizz_adapter_deallocate_render_resources(SfizzDSPKernelAdapter* adapter) {
    [adapter deallocateRenderResources];
}

AUInternalRenderBlock sfizz_adapter_get_internal_render_block(SfizzDSPKernelAdapter* adapter) {
    return [adapter internalRenderBlock];
}

bool sfizz_adapter_load_sfz_file(SfizzDSPKernelAdapter* adapter, const char* path, const char* tuningPath) {
    return [adapter loadSfzFile:path tuningPath:tuningPath];
}

bool sfizz_adapter_load_sfz_string(SfizzDSPKernelAdapter* adapter, const char* sampleRoot, const char* sfzString, const char* tuningString) {
    return [adapter loadSfzString:sampleRoot sfzString:sfzString tuningString:tuningString];
}

// Note: callbackToDartInt32, callbackToDartStrArray, and rawEventDataToEvents
// are exposed directly from C++ via @_silgen_name in SwiftCInterop.swift
// No wrapper functions needed.

}