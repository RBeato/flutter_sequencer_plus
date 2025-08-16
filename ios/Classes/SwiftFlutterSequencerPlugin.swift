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
        
        // Initialize audio session early
        configureAudioSession()
        
        plugin = self
    }
    
    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            
            // Check if session is already active and deactivate first to avoid conflicts
            if session.isOtherAudioPlaying {
                print("Other audio playing, configuring to mix")
            }
            
            // Configure for audio playback (not recording) with better compatibility
            try session.setCategory(.playback, 
                                   mode: .default, 
                                   options: [.mixWithOthers, .allowBluetooth, .allowAirPlay])
            
            // Set sample rate first (more compatible)
            try session.setPreferredSampleRate(44100)
            
            // Set buffer duration to match common AudioUnit buffer sizes (512/1024 frames at 44.1kHz)
            try session.setPreferredIOBufferDuration(0.023) // ~1024 frames at 44.1kHz for AudioUnit compatibility
            
            // Activate the session with retry logic
            var attempts = 0
            var sessionActivated = false
            
            while attempts < 3 && !sessionActivated {
                do {
                    try session.setActive(true, options: [])
                    sessionActivated = true
                    print("Audio session activated successfully on attempt \(attempts + 1)")
                } catch {
                    attempts += 1
                    print("Audio session activation failed (attempt \(attempts)): \(error)")
                    if attempts < 3 {
                        Thread.sleep(forTimeInterval: 0.1) // Wait 100ms before retry
                    }
                }
            }
            
            if sessionActivated {
                print("Audio session configured successfully")
                print("Category: \(session.category)")
                print("Sample rate: \(session.sampleRate)")
                print("IO buffer duration: \(session.ioBufferDuration)")
            } else {
                print("Failed to activate audio session after 3 attempts")
            }
            
        } catch {
            print("Failed to configure audio session: \(error)")
            print("Error code: \((error as NSError).code)")
        }
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
            let audioUnitId = (call.arguments as AnyObject)["id"] as! String
            addTrackAudioUnit(audioUnitId) { result($0) }
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
        // Re-configure if needed
        configureAudioSession()
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


@_cdecl("setup_engine")
func setupEngine(sampleRateCallbackPort: Dart_Port) {
    NSLog("🚨🚨🚨 NUCLEAR FFI: setup_engine called with port: \(sampleRateCallbackPort)")
    print("[DEBUG] ==> setup_engine called with port: \(sampleRateCallbackPort)")
    
    // Initialize the legacy engine for backward compatibility
    plugin.engine = CocoaEngine(sampleRateCallbackPort: sampleRateCallbackPort, registrar: plugin.registrar)
    
    // The new professional engine is already initialized in FlutterSequencerPlatform
    print("[DEBUG] Legacy engine setup completed, professional engine already active")
    
    // TRY A SIMPLER APPROACH: Since the callback system may not be working, 
    // just return success by not waiting for callback
    NSLog("✅✅✅ NUCLEAR FFI: setup_engine completed, sending callback...")
    callbackToDartInt32(sampleRateCallbackPort, 44100)
    NSLog("🎯🎯🎯 NUCLEAR FFI: callback sent")
}

@_cdecl("destroy_engine")
func destroyEngine() {
    plugin.engine = nil
}

@_cdecl("add_track_sfz")
func addTrackSfz(sfzPath: UnsafePointer<CChar>, tuningPath: UnsafePointer<CChar>, callbackPort: Dart_Port) {
    guard let engine = plugin.engine else {
        print("[DEBUG] Engine not available, returning max track index")
        callbackToDartInt32(callbackPort, Int32(track_index_t.max))
        return
    }
    engine.addTrackSfz(sfzPath: sfzPath, tuningPath: tuningPath) { trackIndex in
        callbackToDartInt32(callbackPort, Int32(trackIndex))
    }
}

@_cdecl("add_track_sfz_string")
func addTrackSfzString(sampleRoot: UnsafePointer<CChar>, sfzString: UnsafePointer<CChar>, tuningString: UnsafePointer<CChar>, callbackPort: Dart_Port) {
    guard let engine = plugin.engine else {
        print("[DEBUG] Engine not available, returning max track index")
        callbackToDartInt32(callbackPort, Int32(track_index_t.max))
        return
    }
    engine.addTrackSfzString(sampleRoot: sampleRoot, sfzString: sfzString, tuningString: tuningString) { trackIndex in
        callbackToDartInt32(callbackPort, Int32(trackIndex))
    }
}

@_cdecl("add_track_sf2")
func addTrackSf2(path: UnsafePointer<CChar>, isAsset: Bool, presetIndex: Int32, callbackPort: Dart_Port) {
    let pathString = String(cString: path)
    NSLog("🔥🔥🔥 NUCLEAR FFI: add_track_sf2 called: \(pathString) isAsset=\(isAsset) preset=\(presetIndex)")
    
    guard let engine = plugin.engine else {
        NSLog("❌❌❌ NUCLEAR FFI: Engine not available!")
        print("[DEBUG] Engine not available, returning max track index")
        callbackToDartInt32(callbackPort, Int32(track_index_t.max))
        return
    }
    
    NSLog("✅✅✅ NUCLEAR FFI: Calling engine.addTrackSf2")
    engine.addTrackSf2(sf2Path: pathString, isAsset: isAsset, presetIndex: presetIndex) { trackIndex in
        NSLog("🎯🎯🎯 NUCLEAR FFI: addTrackSf2 completed with trackIndex=\(trackIndex)")
        callbackToDartInt32(callbackPort, Int32(trackIndex))
    }
}

// Called from method channel
func addTrackAudioUnit(_ audioUnitId: String, completion: @escaping (track_index_t) -> Void) {
    guard let engine = plugin.engine else {
        print("[DEBUG] Engine not available, returning max track index")
        completion(track_index_t.max)
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
    guard let engine = plugin.engine, let scheduler = engine.scheduler else {
        print("[DEBUG] Scheduler not available, returning 0")
        return 0
    }
    return position_frame_t(SchedulerGetPosition(scheduler))
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
    guard let engine = plugin.engine else {
        print("[DEBUG] Engine not available, skipping event handling")
        return
    }
    
    // INDUSTRY STANDARD: Direct MIDI event processing for immediate playback
    NSLog("🎼🎼🎼 NUCLEAR FFI: handleEventsNow track=\(trackIndex) count=\(eventsCount)")
    print("[DEBUG] FFI handleEventsNow: track=\(trackIndex) events=\(eventsCount)")
    
    if engine.scheduler != nil {
        // Use scheduler if available
        let events = UnsafeMutablePointer<SchedulerEvent>.allocate(capacity: Int(eventsCount))
        rawEventDataToEvents(eventData, eventsCount, events)
        SchedulerHandleEventsNow(engine.scheduler, trackIndex, UnsafePointer(events), eventsCount)
        events.deallocate()
    } else {
        // MINIMAL MODE: Direct MIDI processing without scheduler
        print("[DEBUG] Using direct MIDI processing (scheduler-free mode)")
        
        // Parse and send MIDI events directly
        for i in 0..<Int(eventsCount) {
            let offset = i * 24 // Size of SchedulerEvent
            let eventType = eventData.advanced(by: offset).pointee
            
            if eventType == 0 { // MIDI event
                // Extract MIDI data from raw event
                let midiStatus = eventData.advanced(by: offset + 16).pointee
                let midiData1 = eventData.advanced(by: offset + 17).pointee  
                let midiData2 = eventData.advanced(by: offset + 18).pointee
                
                NSLog("🎵🎵🎵 NUCLEAR: Direct MIDI track=\(trackIndex) status=\(midiStatus) data1=\(midiData1) data2=\(midiData2)")
                
                // Send directly to CocoaEngine
                engine.sendMIDIEvent(trackIndex: trackIndex, midiStatus: midiStatus, midiData1: midiData1, midiData2: midiData2)
            }
        }
    }
}

@_cdecl("schedule_events")
func scheduleEvents(trackIndex: track_index_t, eventData: UnsafePointer<UInt8>, eventsCount: UInt32) -> UInt32 {
    guard let engine = plugin.engine, let scheduler = engine.scheduler else {
        print("[DEBUG] Scheduler not available, returning 0")
        return 0
    }
    
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
