import Flutter
import Foundation
import AudioToolbox
import CoreAudio
import AVFoundation

var plugin: SwiftFlutterSequencerPlugin!

enum PluginError: Error {
    case engineNotReady
}

public class SwiftFlutterSequencerPlugin: NSObject, FlutterPlugin {
    public var registrar: FlutterPluginRegistrar!
    public var engine: CocoaEngine?
    public static var staticRegistrar: FlutterPluginRegistrar?

    public static func register(with registrar: FlutterPluginRegistrar) {
        plugin = SwiftFlutterSequencerPlugin()
        plugin.registrar = registrar
        staticRegistrar = registrar

        let channel = FlutterMethodChannel(name: "flutter_sequencer", binaryMessenger: registrar.messenger())
        registrar.addMethodCallDelegate(plugin, channel: channel)
    }

    public override init() {
        super.init()
        configureAudioSession()
        plugin = self
    }

    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback,
                                   mode: .default,
                                   options: [.mixWithOthers, .defaultToSpeaker])
            try session.setPreferredSampleRate(44100)
            // Sequencer-optimized buffer: 512 samples at 44.1kHz = ~11.6ms
            try session.setPreferredIOBufferDuration(0.012)
            try session.setActive(true, options: [])
        } catch {
            // Non-fatal: will work with system defaults
        }
    }

    deinit {
        plugin = nil
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        if call.method == "setupAssetManager" {
            result(nil)
        } else if call.method == "normalizeAssetDir" {
            let assetDir = (call.arguments as AnyObject)["assetDir"] as! String
            result(normalizeAssetDir(registrar: registrar, assetDir: assetDir))
        } else if call.method == "listAudioUnits" {
            listAudioUnits { result($0) }
        } else if call.method == "addTrackAudioUnit" {
            let audioUnitId = (call.arguments as AnyObject)["audioUnitId"] as! String
            createAudioUnitTrack(audioUnitId) { result($0) }
        } else if call.method == "initializeAudioSession" {
            configureAudioSession()
            result(true)
        } else if call.method == "getDebugLog" {
            result("Debug logging disabled")
        } else if call.method == "clearDebugLog" {
            result(true)
        } else if call.method == "dumpAudioUnitStates" {
            result(true)
        }
    }
}

// MARK: - Method Channel Helpers

func normalizeAssetDir(registrar: FlutterPluginRegistrar, assetDir: String) -> String? {
    let key = registrar.lookupKey(forAsset: assetDir)
    return Bundle.main.path(forResource: key, ofType: nil)
}

func listAudioUnits(completion: @escaping ([String]) -> Void) {
    AudioUnitUtils.loadAudioUnits { loadedComponents in
        completion(loadedComponents.map(AudioUnitUtils.getAudioUnitId))
    }
}

func createAudioUnitTrack(_ audioUnitId: String, completion: @escaping (Int) -> Void) {
    guard let engine = plugin.engine else {
        completion(-1)
        return
    }

    var hasCompleted = false

    DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
        if !hasCompleted {
            hasCompleted = true
            completion(-1)
        }
    }

    engine.addTrackAudioUnit(audioUnitId: audioUnitId) { trackIndex in
        DispatchQueue.main.async {
            if !hasCompleted {
                hasCompleted = true
                completion(Int(trackIndex))
            }
        }
    }
}

// MARK: - FFI Entry Points (called from Dart via dart:ffi)
// All scheduling routes through the C++ CocoaScheduler for maximum performance.
// Zero Swift/ObjC overhead on the audio thread.

@_cdecl("setup_engine")
func setupEngine(sampleRateCallbackPort: Dart_Port) {
    seqLog("FFI setup_engine: callbackPort=\(sampleRateCallbackPort)")
    plugin.engine = CocoaEngine(sampleRateCallbackPort: sampleRateCallbackPort, registrar: plugin.registrar)
}

@_cdecl("destroy_engine")
func destroyEngine() {
    seqLog("FFI destroy_engine")
    plugin.engine = nil
}

@_cdecl("add_track_sfz")
func addTrackSfz(sfzPath: UnsafePointer<CChar>, tuningPath: UnsafePointer<CChar>, callbackPort: Dart_Port) {
    guard let engine = plugin.engine else {
        callbackToDartInt32(callbackPort, -1)
        return
    }
    engine.addTrackSfz(sfzPath: sfzPath, tuningPath: tuningPath) { trackIndex in
        callbackToDartInt32(callbackPort, Int32(trackIndex))
    }
}

@_cdecl("add_track_sfz_string")
func addTrackSfzString(sampleRoot: UnsafePointer<CChar>, sfzString: UnsafePointer<CChar>, tuningString: UnsafePointer<CChar>, callbackPort: Dart_Port) {
    guard let engine = plugin.engine else {
        callbackToDartInt32(callbackPort, -1)
        return
    }
    engine.addTrackSfzString(sampleRoot: sampleRoot, sfzString: sfzString, tuningString: tuningString) { trackIndex in
        callbackToDartInt32(callbackPort, Int32(trackIndex))
    }
}

@_cdecl("add_track_sf2")
func addTrackSf2(path: UnsafePointer<CChar>, isAsset: Bool, presetIndex: Int32, callbackPort: Dart_Port) {
    let pathString = String(cString: path)
    seqLog("FFI add_track_sf2: path=\(pathString), isAsset=\(isAsset), preset=\(presetIndex)")

    guard let engine = plugin.engine else {
        seqLog("FFI add_track_sf2: engine is nil!")
        callbackToDartInt32(callbackPort, -1)
        return
    }

    engine.addTrackSf2(sf2Path: pathString, isAsset: isAsset, presetIndex: presetIndex) { trackIndex in
        seqLog("FFI add_track_sf2: completed, trackIndex=\(trackIndex)")
        callbackToDartInt32(callbackPort, Int32(trackIndex))
    }
}

func addTrackAudioUnit(_ audioUnitId: String, completion: @escaping (track_index_t) -> Void) {
    guard let engine = plugin.engine else {
        completion(track_index_t(999))
        return
    }
    engine.addTrackAudioUnit(audioUnitId: audioUnitId, completion: completion)
}

@_cdecl("remove_track")
func removeTrack(trackIndex: track_index_t) {
    guard let engine = plugin.engine else { return }
    let _ = engine.removeTrack(trackIndex: trackIndex)
}

@_cdecl("reset_track")
func resetTrack(trackIndex: track_index_t) {
    guard let engine = plugin.engine, let scheduler = engine.scheduler else { return }
    SchedulerResetTrack(scheduler, trackIndex)
}

@_cdecl("get_position")
func getPosition() -> position_frame_t {
    guard let engine = plugin.engine else { return 0 }
    return position_frame_t(engine.getPosition())
}

@_cdecl("get_track_volume")
func getTrackVolume(trackIndex: track_index_t) -> Float32 {
    guard let engine = plugin.engine, let scheduler = engine.scheduler else { return 1.0 }
    return SchedulerGetTrackVolume(scheduler, trackIndex)
}

@_cdecl("get_last_render_time_us")
func getLastRenderTimeUs() -> UInt64 {
    guard let engine = plugin.engine, let scheduler = engine.scheduler else { return 0 }
    return SchedulerGetLastRenderTimeUs(scheduler)
}

@_cdecl("get_buffer_available_count")
func getBufferAvailableCount(trackIndex: track_index_t) -> UInt32 {
    guard let engine = plugin.engine, let scheduler = engine.scheduler else { return 0 }
    return SchedulerGetBufferAvailableCount(scheduler, trackIndex)
}

@_cdecl("handle_events_now")
func handleEventsNow(trackIndex: track_index_t, eventData: UnsafePointer<UInt8>, eventsCount: UInt32) {
    guard let engine = plugin.engine, let scheduler = engine.scheduler else { return }
    // Dart serializes events in C++ SchedulerEvent layout (16 bytes each).
    // Cast directly — avoids allocating via OpaquePointer which is only 8 bytes,
    // causing a 2x buffer overflow when rawEventDataToEvents writes 16-byte structs.
    let eventsPtr = UnsafeRawPointer(eventData).assumingMemoryBound(to: SchedulerEvent.self)
    SchedulerHandleEventsNow(scheduler, trackIndex, eventsPtr, eventsCount)
}

@_cdecl("schedule_events")
func scheduleEvents(trackIndex: track_index_t, eventData: UnsafePointer<UInt8>, eventsCount: UInt32) -> UInt32 {
    guard let engine = plugin.engine, let scheduler = engine.scheduler else { return 0 }
    // Dart serializes events in C++ SchedulerEvent layout (16 bytes each).
    // Cast directly — avoids allocating via OpaquePointer which is only 8 bytes,
    // causing a 2x buffer overflow when rawEventDataToEvents writes 16-byte structs.
    let eventsPtr = UnsafeRawPointer(eventData).assumingMemoryBound(to: SchedulerEvent.self)
    return SchedulerAddEvents(scheduler, trackIndex, eventsPtr, eventsCount)
}

@_cdecl("clear_events")
func clearEvents(trackIndex: track_index_t, fromFrame: position_frame_t) {
    guard let engine = plugin.engine, let scheduler = engine.scheduler else { return }
    SchedulerClearEvents(scheduler, trackIndex, fromFrame)
}

@_cdecl("engine_play")
func enginePlay() {
    seqLog("FFI engine_play")
    guard let engine = plugin.engine else {
        seqLog("FFI engine_play: engine is nil!")
        return
    }
    engine.play()
}

@_cdecl("engine_pause")
func enginePause() {
    seqLog("FFI engine_pause")
    guard let engine = plugin.engine else {
        seqLog("FFI engine_pause: engine is nil!")
        return
    }
    engine.pause()
}

@_cdecl("engine_stop")
func engineStop() {
    seqLog("FFI engine_stop")
    guard let engine = plugin.engine else {
        seqLog("FFI engine_stop: engine is nil!")
        return
    }
    engine.stop()
}
