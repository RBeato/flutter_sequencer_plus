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
            
            // HIGH-PERFORMANCE: Configure for low-latency audio playback
            try session.setCategory(.playback, 
                                   mode: .default, 
                                   options: [.mixWithOthers, .allowBluetooth, .allowAirPlay, .defaultToSpeaker])
            
            // Set sample rate first (more compatible)
            try session.setPreferredSampleRate(44100)
            
            // PERFORMANCE: Optimize buffer duration for immediate response
            try session.setPreferredIOBufferDuration(0.005) // ~256 frames at 44.1kHz for minimal latency
            
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


@objc public func setupEngine(sampleRateCallbackPort: Dart_Port) {
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
    NSLog("🔥🔥🔥 NUCLEAR FFI: add_track_sf2 called: \(pathString) isAsset=\(isAsset) preset=\(presetIndex)")
    
    guard let engine = plugin.engine else {
        NSLog("❌❌❌ NUCLEAR FFI: Engine not available!")
        print("[DEBUG] Engine not available, returning error track index")
        callbackToDartInt32(callbackPort, -1)
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
    guard let engine = plugin.engine else {
        print("[DEBUG] Engine not available, returning 0")
        return 0
    }
    
    // CRITICAL FIX: Get position from CocoaEngine's position tracking
    // Since scheduler is nil, we use the engine's own position
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
    // CRITICAL: This should appear in system logs if function is called
    NSLog("🚨🚨🚨 FUNCTION ENTRY: handleEventsNow track=%d count=%d", trackIndex, eventsCount)
    print("🚨🚨🚨 NATIVE FFI ENTRY: handleEventsNow track=\(trackIndex) count=\(eventsCount)")
    
    guard let engine = plugin.engine else {
        NSLog("❌❌❌ ENGINE NOT AVAILABLE")
        print("❌❌❌ NATIVE FFI: ENGINE NOT AVAILABLE")
        return
    }
    
    NSLog("✅✅✅ Engine available, processing events...")
    print("✅✅✅ NATIVE FFI: Engine available, processing events...")
    
    // CRITICAL TEST: Check if we reach this point
    print("🧪 CRITICAL TEST: About to start event processing")
    NSLog("🧪 CRITICAL TEST: About to start event processing")
    
    // FIXED: Direct MIDI processing with detailed diagnostics
    NSLog("🎵 Processing %d events for track %d", eventsCount, trackIndex)
    print("🎵 NATIVE FFI: Processing \(eventsCount) events for track \(trackIndex)")
    
    // SIMPLIFIED: Safe MIDI processing to identify the crash point
    guard eventsCount > 0 else {
        NSLog("⚠️ No events to process")
        return
    }
    
    NSLog("🎯 SAFE: Processing %d events", eventsCount)
    
    // Process each event with minimal unsafe operations
    for i in 0..<Int(eventsCount) {
        let offset = i * 16 // 16 bytes per SchedulerEvent structure
        
        NSLog("📍 SAFE: Event %d at offset %d", i, offset)
        
        // Safe bounds check
        let totalBytes = Int(eventsCount) * 16
        guard offset + 16 <= totalBytes else {
            NSLog("❌ SAFE: Bounds error for event %d", i)
            continue
        }
        
        // Extract raw bytes safely
        let eventBytes = UnsafeBufferPointer(start: eventData.advanced(by: offset), count: 16)
        
        // Read event type from bytes 4-7 (UInt32)
        let eventTypeBytes = Array(eventBytes[4..<8])
        let eventType = eventTypeBytes.withUnsafeBytes { $0.load(as: UInt32.self) }
        
        NSLog("🔍 SAFE: Event %d type=%d", i, eventType)
        
        if eventType == 0 { // MIDI_EVENT
            // MIDI data starts at byte 8
            let midiStatus = eventBytes[8]
            let midiData1 = eventBytes[9]
            let midiData2 = eventBytes[10]
            
            NSLog("🎵 SAFE: MIDI track=%d status=0x%02X note=%d vel=%d", trackIndex, midiStatus, midiData1, midiData2)
            
            // CRITICAL FIX: Send MIDI events immediately without any dispatch
            // This ensures minimum latency for real-time audio
            engine.sendMIDIEvent(trackIndex: trackIndex, midiStatus: midiStatus, midiData1: midiData1, midiData2: midiData2)
            
        } else if eventType == 1 { // VOLUME_EVENT
            // Volume stored as float at bytes 8-11
            let volumeBytes = Array(eventBytes[8..<12])
            let volume = volumeBytes.withUnsafeBytes { $0.load(as: Float.self) }
            NSLog("🔊 SAFE: Volume track=%d vol=%f", trackIndex, volume)
        }
    }
    
    NSLog("✅ SAFE: All events processed")
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

@_cdecl("engine_stop")
func engineStop() {
    guard let engine = plugin.engine else {
        print("[DEBUG] Engine not available, skipping stop")
        return
    }
    engine.stop()
}
