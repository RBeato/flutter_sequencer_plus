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
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        // Initialize main plugin
        plugin = SwiftFlutterSequencerPlugin()
        plugin.registrar = registrar
        
        // Register main channel for Flutter method calls
        let channel = FlutterMethodChannel(name: "flutter_sequencer", binaryMessenger: registrar.messenger())
        registrar.addMethodCallDelegate(plugin, channel: channel)
        
        print("[DEBUG] FlutterSequencerPlugin registered (FFI system active)")
    }
    
    public override init() {
        super.init()
        // Audio session now configured by CocoaEngine init - no duplicate config needed
        plugin = self
    }
    
    deinit {
        plugin = nil
    }
    
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        if (call.method == "setupAssetManager") {
            result(nil)
        } else if (call.method == "normalizeAssetDir") {
            let assetDir = (call.arguments as AnyObject)["assetDir"] as! String

            result(normalizeAssetDir(registrar: registrar, assetDir: assetDir))
        } else if (call.method == "listAudioUnits") {
            listAudioUnits { result($0) }
        } else if (call.method == "addTrackAudioUnit") {
            let audioUnitId = (call.arguments as AnyObject)["audioUnitId"] as! String
            createAudioUnitTrack(audioUnitId) { result($0) }
        } else if (call.method == "initializeAudioSession") {
            initializeAudioSession(result)
        } else if (call.method == "getDebugLog") {
            getDebugLog(result)
        } else if (call.method == "clearDebugLog") {
            clearDebugLog(result)
        } else if (call.method == "dumpAudioUnitStates") {
            dumpAudioUnitStates(result)
        }
    }
    
    private func initializeAudioSession(_ result: @escaping FlutterResult) {
        // Audio session configured by CocoaEngine - just report success
        // Reconfiguring here caused error -50 conflicts
        result(true)
    }
    
    private func getDebugLog(_ result: @escaping FlutterResult) {
        result("Debug logging disabled")
    }
    
    private func clearDebugLog(_ result: @escaping FlutterResult) {
        result(true)
    }
    
    private func dumpAudioUnitStates(_ result: @escaping FlutterResult) {
        result(true)
    }
}

// Called from method channel
func normalizeAssetDir(registrar: FlutterPluginRegistrar, assetDir: String) -> String? {
    let key = registrar.lookupKey(forAsset: assetDir)
    let path = Bundle.main.path(forResource: key, ofType: nil)
    
    return path
}

// Called from method channel
func listAudioUnits(completion: @escaping ([String]) -> Void) {
    AudioUnitUtils.loadAudioUnits { loadedComponents in
        let ids = loadedComponents.map(AudioUnitUtils.getAudioUnitId)
        
        completion(ids)
    }
}

// Called from method channel
func createAudioUnitTrack(_ audioUnitId: String, completion: @escaping (Int) -> Void) {
    NSLog("🎵 Method Channel: Adding AudioUnit track: \(audioUnitId)")
    
    // TEMPORARY SAFETY FIX: Skip AudioUnit creation on physical devices to prevent crashes
    // This will help isolate if AudioUnit loading is causing the crashes
    #if targetEnvironment(simulator)
    NSLog("🎵 AudioUnit creation enabled on simulator")
    
    guard let engine = plugin.engine else {
        print("[ERROR] Engine not available for AudioUnit track creation")
        completion(-1)
        return
    }
    
    // Add timeout to prevent hanging
    var hasCompleted = false
    let completionQueue = DispatchQueue.main
    
    // Set a timeout for AudioUnit creation
    completionQueue.asyncAfter(deadline: .now() + 5.0) {  // Reduced to 5 seconds for testing
        if !hasCompleted {
            NSLog("⏰ AudioUnit track creation timed out after 5 seconds")
            hasCompleted = true
            completion(-1)
        }
    }
    
    engine.addTrackAudioUnit(audioUnitId: audioUnitId) { trackIndex in
        completionQueue.async {
            if !hasCompleted {
                hasCompleted = true
                NSLog("🎵 Method Channel: AudioUnit track created with index: \(trackIndex)")
                completion(Int(trackIndex))
            }
        }
    }
    #else
    NSLog("🚫 AudioUnit creation disabled on physical device to prevent crashes")
    NSLog("📱 Physical device detected - skipping AudioUnit for safety")
    completion(-1)
    #endif
}


@_cdecl("setup_engine")
func setupEngine(sampleRateCallbackPort: Dart_Port) {
    // CocoaEngine init starts AVAudioEngine, creates C++ scheduler on mixer, and sends sample rate callback
    plugin.engine = CocoaEngine(sampleRateCallbackPort: sampleRateCallbackPort, registrar: plugin.registrar)
}

@_cdecl("destroy_engine")
func destroyEngine() {
    plugin.engine = nil
}

@_cdecl("add_track_sfz")
func addTrackSfz(sfzPath: UnsafePointer<CChar>, tuningPath: UnsafePointer<CChar>, callbackPort: Dart_Port) {
    guard let engine = plugin.engine else {
        print("[DEBUG] Engine not available, returning error track index")
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
        print("[DEBUG] Engine not available, returning error track index")
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

    guard let engine = plugin.engine else {
        callbackToDartInt32(callbackPort, -1)
        return
    }

    engine.addTrackSf2(sf2Path: pathString, isAsset: isAsset, presetIndex: presetIndex) { trackIndex in
        callbackToDartInt32(callbackPort, Int32(trackIndex))
    }
}

// Called from method channel
func addTrackAudioUnit(_ audioUnitId: String, completion: @escaping (track_index_t) -> Void) {
    guard let engine = plugin.engine else {
        print("[DEBUG] Engine not available, returning error track index")
        completion(track_index_t(999))
        return
    }
    engine.addTrackAudioUnit(audioUnitId: audioUnitId, completion: completion)
}

@_cdecl("remove_track")
func removeTrack(trackIndex: track_index_t) {
    guard let engine = plugin.engine else {
        print("[DEBUG] Engine not available, skipping remove track")
        return
    }
    let _ = engine.removeTrack(trackIndex: trackIndex)
}

@_cdecl("reset_track")
func resetTrack(trackIndex: track_index_t) {
    guard let engine = plugin.engine, let scheduler = engine.scheduler else {
        print("[DEBUG] Scheduler not available, skipping reset track")
        return
    }
    
    // Ensure we're on the main thread for safety
    if Thread.isMainThread {
        SchedulerResetTrack(scheduler, trackIndex)
    } else {
        DispatchQueue.main.sync {
            SchedulerResetTrack(scheduler, trackIndex)
        }
    }
}

@_cdecl("get_position")
func getPosition() -> position_frame_t {
    guard let engine = plugin.engine else { return 0 }
    return position_frame_t(engine.getPosition())
}

@_cdecl("get_track_volume")
func getTrackVolume(trackIndex: track_index_t) -> Float32 {
    guard let engine = plugin.engine, let scheduler = engine.scheduler else {
        print("[DEBUG] Scheduler not available, returning default volume")
        return 1.0
    }
    return SchedulerGetTrackVolume(scheduler, trackIndex)
}

@_cdecl("get_last_render_time_us")
func getLastRenderTimeUs() -> UInt64 {
    guard let engine = plugin.engine, let scheduler = engine.scheduler else {
        print("[DEBUG] Scheduler not available, returning 0")
        return 0
    }
    return SchedulerGetLastRenderTimeUs(scheduler)
}

@_cdecl("get_buffer_available_count")
func getBufferAvailableCount(trackIndex: track_index_t) -> UInt32 {
    guard let engine = plugin.engine, let scheduler = engine.scheduler else {
        print("[DEBUG] Scheduler not available, returning 0")
        return 0
    }
    return SchedulerGetBufferAvailableCount(scheduler, trackIndex)
}

@_cdecl("handle_events_now")
func handleEventsNow(trackIndex: track_index_t, eventData: UnsafePointer<UInt8>, eventsCount: UInt32) {
    guard let engine = plugin.engine else { return }
    guard eventsCount > 0 && eventsCount <= 4096 else { return }

    // Use scheduler for immediate event dispatch when available
    if let scheduler = engine.scheduler {
        let events = UnsafeMutablePointer<SchedulerEvent>.allocate(capacity: Int(eventsCount))
        rawEventDataToEvents(eventData, eventsCount, events)
        SchedulerHandleEventsNow(scheduler, trackIndex, UnsafePointer(events), eventsCount)
        events.deallocate()
        return
    }

    // Fallback: direct MIDI dispatch (for when scheduler is nil)
    for i in 0..<Int(eventsCount) {
        let offset = i * 16
        let eventBytes = UnsafeBufferPointer(start: eventData.advanced(by: offset), count: 16)

        let eventTypeBytes = Array(eventBytes[4..<8])
        let eventType = eventTypeBytes.withUnsafeBytes { $0.load(as: UInt32.self) }

        if eventType == 0 { // MIDI_EVENT
            let midiStatus = eventBytes[8]
            let midiData1 = eventBytes[9]
            let midiData2 = eventBytes[10]
            engine.sendMIDIEvent(trackIndex: trackIndex, midiStatus: midiStatus, midiData1: midiData1, midiData2: midiData2)
        }
    }
}

@_cdecl("schedule_events")
func scheduleEvents(trackIndex: track_index_t, eventData: UnsafePointer<UInt8>, eventsCount: UInt32) -> UInt32 {
    guard let engine = plugin.engine, let scheduler = engine.scheduler else {
        print("[DEBUG] Scheduler not available, returning 0")
        return 0
    }
    guard eventsCount > 0 && eventsCount <= 4096 else { return 0 }

    let events = UnsafeMutablePointer<SchedulerEvent>.allocate(capacity: Int(eventsCount))
    
    rawEventDataToEvents(eventData, eventsCount, events)
    
    let result = SchedulerAddEvents(scheduler, trackIndex, UnsafePointer(events), eventsCount)
    
    events.deallocate()
    
    return result
}

@_cdecl("clear_events")
func clearEvents(trackIndex: track_index_t, fromFrame: position_frame_t) {
    guard let engine = plugin.engine, let scheduler = engine.scheduler else {
        print("[DEBUG] Scheduler not available, skipping clear events")
        return
    }
    SchedulerClearEvents(scheduler, trackIndex, fromFrame)
}

@_cdecl("engine_play")
func enginePlay() {
    guard let engine = plugin.engine else {
        print("[DEBUG] Engine not available, skipping play")
        return
    }
    engine.play()
}

@_cdecl("engine_pause")
func enginePause() {
    guard let engine = plugin.engine else {
        print("[DEBUG] Engine not available, skipping pause")
        return
    }
    engine.pause()
}

@_cdecl("engine_stop")
func engineStop() {
    guard let engine = plugin.engine else {
        print("[DEBUG] Engine not available, skipping stop")
        return
    }
    engine.stop()
}
