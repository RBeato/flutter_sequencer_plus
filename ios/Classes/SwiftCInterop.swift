// SwiftCInterop.swift - Shared C function declarations and types for Swift/C++ interop
// This file should be imported by all Swift files that need to interact with C++ code

import Foundation
import AudioToolbox
import CoreAudio

// Type aliases for C++ types
typealias track_index_t = UInt32
typealias position_frame_t = UInt64
typealias Dart_Port = Int64
typealias SchedulerEvent = OpaquePointer
typealias SfizzDSPKernelAdapter = OpaquePointer
typealias Dart_CObject = OpaquePointer

// C function declarations - Sfizz DSP Kernel Adapter
@_silgen_name("createSfizzDSPKernelAdapter")
func createSfizzDSPKernelAdapter() -> SfizzDSPKernelAdapter

@_silgen_name("sfizz_adapter_get_input_bus")
func sfizz_adapter_get_input_bus(_ adapter: SfizzDSPKernelAdapter) -> UnsafeMutablePointer<AUAudioUnitBus>

@_silgen_name("sfizz_adapter_get_output_bus")
func sfizz_adapter_get_output_bus(_ adapter: SfizzDSPKernelAdapter) -> UnsafeMutablePointer<AUAudioUnitBus>

@_silgen_name("sfizz_adapter_get_maximum_frames")
func sfizz_adapter_get_maximum_frames(_ adapter: SfizzDSPKernelAdapter) -> AUAudioFrameCount

@_silgen_name("sfizz_adapter_set_maximum_frames")
func sfizz_adapter_set_maximum_frames(_ adapter: SfizzDSPKernelAdapter, _ frames: AUAudioFrameCount)

@_silgen_name("sfizz_adapter_allocate_render_resources")
func sfizz_adapter_allocate_render_resources(_ adapter: SfizzDSPKernelAdapter)

@_silgen_name("sfizz_adapter_deallocate_render_resources")
func sfizz_adapter_deallocate_render_resources(_ adapter: SfizzDSPKernelAdapter)

@_silgen_name("sfizz_adapter_get_internal_render_block")
func sfizz_adapter_get_internal_render_block(_ adapter: SfizzDSPKernelAdapter) -> AUInternalRenderBlock

@_silgen_name("sfizz_adapter_load_sfz_file")
func sfizz_adapter_load_sfz_file(_ adapter: SfizzDSPKernelAdapter, _ path: UnsafePointer<CChar>, _ tuningPath: UnsafePointer<CChar>) -> Bool

@_silgen_name("sfizz_adapter_load_sfz_string")
func sfizz_adapter_load_sfz_string(_ adapter: SfizzDSPKernelAdapter, _ sampleRoot: UnsafePointer<CChar>, _ sfzString: UnsafePointer<CChar>, _ tuningString: UnsafePointer<CChar>) -> Bool

// C function declarations - Scheduler functions
@_silgen_name("InitScheduler")
func InitScheduler(_ mixerAudioUnit: AudioUnit, _ sampleRate: Double) -> UnsafeMutableRawPointer

@_silgen_name("DestroyScheduler")
func DestroyScheduler(_ scheduler: UnsafeMutableRawPointer)

@_silgen_name("SchedulerPause")
func SchedulerPause(_ scheduler: UnsafeMutableRawPointer)

@_silgen_name("SchedulerPlay")
func SchedulerPlay(_ scheduler: UnsafeMutableRawPointer)

@_silgen_name("SchedulerAddTrack")
func SchedulerAddTrack(_ scheduler: UnsafeMutableRawPointer) -> Int32

@_silgen_name("SchedulerSetTrackAudioUnit")
func SchedulerSetTrackAudioUnit(_ scheduler: UnsafeMutableRawPointer, _ trackIndex: track_index_t, _ audioUnit: AudioUnit)

@_silgen_name("SchedulerRemoveTrack")
func SchedulerRemoveTrack(_ scheduler: UnsafeMutableRawPointer, _ trackIndex: track_index_t)

@_silgen_name("SchedulerResetTrack")
func SchedulerResetTrack(_ scheduler: UnsafeMutableRawPointer, _ trackIndex: track_index_t)

@_silgen_name("SchedulerGetTrackVolume")
func SchedulerGetTrackVolume(_ scheduler: UnsafeMutableRawPointer, _ trackIndex: track_index_t) -> Float32

@_silgen_name("SchedulerGetLastRenderTimeUs")
func SchedulerGetLastRenderTimeUs(_ scheduler: UnsafeMutableRawPointer) -> UInt64

@_silgen_name("SchedulerGetBufferAvailableCount")
func SchedulerGetBufferAvailableCount(_ scheduler: UnsafeMutableRawPointer, _ trackIndex: track_index_t) -> UInt32

@_silgen_name("SchedulerHandleEventsNow")
func SchedulerHandleEventsNow(_ scheduler: UnsafeMutableRawPointer, _ trackIndex: track_index_t, _ events: UnsafePointer<SchedulerEvent>, _ numEvents: UInt32)

@_silgen_name("SchedulerAddEvents")
func SchedulerAddEvents(_ scheduler: UnsafeMutableRawPointer, _ trackIndex: track_index_t, _ events: UnsafePointer<SchedulerEvent>, _ numEvents: UInt32) -> UInt32

@_silgen_name("SchedulerClearEvents")
func SchedulerClearEvents(_ scheduler: UnsafeMutableRawPointer, _ trackIndex: track_index_t, _ fromFrame: position_frame_t)

@_silgen_name("SchedulerGetPosition")
func SchedulerGetPosition(_ scheduler: UnsafeMutableRawPointer) -> UInt32

// C function declarations - Callback functions
@_silgen_name("RegisterDart_PostCObject")
func RegisterDart_PostCObject(_ dartPostCObject: @escaping @convention(c) (Int64, UnsafeMutablePointer<Dart_CObject>?) -> Bool)

@_silgen_name("callbackToDartInt32")
func callbackToDartInt32(_ port: Dart_Port, _ value: Int32)

@_silgen_name("callbackToDartStrArray")
func callbackToDartStrArray(_ port: Dart_Port, _ strings: UnsafePointer<UnsafePointer<CChar>?>, _ count: Int32)

// C function declarations - Event processing
@_silgen_name("rawEventDataToEvents")
func rawEventDataToEvents(_ rawData: UnsafePointer<UInt8>, _ eventsCount: UInt32, _ events: UnsafeMutablePointer<SchedulerEvent>)