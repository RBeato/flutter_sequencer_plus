import Foundation
import AVFoundation
import Flutter

public class CocoaEngine {
    var scheduler: UnsafeMutableRawPointer!
    
    private let engine = AVAudioEngine()
    private var mixer: AVAudioUnit?
    private let outputFormat: AVAudioFormat!
    private let registrar: FlutterPluginRegistrar!

    // Swift Dictionary is not thread-safe, so this must be copied before access
    private var unsafeAvAudioUnits: [track_index_t: AVAudioUnit] = [:]
    private var nextTrackId: track_index_t = 0
    
    init(sampleRateCallbackPort: Dart_Port, registrar: FlutterPluginRegistrar) {
        self.registrar = registrar
        
        print("[DEBUG] CocoaEngine init started")
        
        // PERFORMANCE OPTIMIZED: Configure audio session and engine for immediate playback
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
            print("[DEBUG] Audio session configured for optimal performance")
        } catch {
            print("[ERROR] Audio session setup failed: \(error)")
        }
        
        // Use optimized output format
        outputFormat = engine.outputNode.outputFormat(forBus: 0)
        print("[DEBUG] Engine format: \(outputFormat.sampleRate)Hz, channels: \(outputFormat.channelCount)")
        
        // Skip scheduler for minimal latency
        self.scheduler = nil
        self.mixer = nil
        
        // CRITICAL: Start engine immediately to eliminate first-play delay
        do {
            engine.prepare()
            try engine.start()
            print("[DEBUG] Engine pre-started for zero-latency playback")
        } catch {
            print("[ERROR] Failed to pre-start engine: \(error)")
        }
        
        // Send callback immediately to unblock Dart
        callbackToDartInt32(sampleRateCallbackPort, Int32(outputFormat.sampleRate))
        
        SfizzAU.registerAU()
        print("[DEBUG] CocoaEngine init completed")
    }
    
    deinit {
        print("[DEBUG] CocoaEngine deinit")
        if engine.isRunning {
            engine.stop()
        }
        if scheduler != nil {
            DestroyScheduler(scheduler)
        }
    }
    
    func addTrackSf2(sf2Path: String, isAsset: Bool, presetIndex: Int32, completion: @escaping (track_index_t) -> Void) {
        NSLog("🎵 HIGH-PERF: Adding SF2 track: \(sf2Path)")
        print("[DEBUG] Adding SF2 track with optimized loading: \(sf2Path)")
        
        AudioUnitUtils.loadAudioUnits { [weak self] avAudioUnitComponents in
            guard let self = self else { 
                completion(track_index_t(999))
                return 
            }
            
            let appleSamplerComponent = avAudioUnitComponents.first(where: isAppleSampler)
            
            if let appleSamplerComponent = appleSamplerComponent {
                AudioUnitUtils.instantiate(
                    description: appleSamplerComponent.audioComponentDescription,
                    sampleRate: Double(self.outputFormat.sampleRate),
                    options: [.loadOutOfProcess] // Performance optimization
                ) { [weak self] (avAudioUnit: AVAudioUnit?) in
                    guard let self = self, let avAudioUnit = avAudioUnit else {
                        completion(track_index_t(999))
                        return
                    }
                    
                    // PERFORMANCE: Execute on main thread for immediate connection
                    DispatchQueue.main.async {
                        if let normalizedPath = self.normalizePath(sf2Path, isAsset: isAsset) {
                            let url = URL(fileURLWithPath: normalizedPath)
                            
                            // High-performance SF2 loading with immediate connection
                            loadSoundFont(avAudioUnit: avAudioUnit, soundFontURL: url, presetIndex: presetIndex)
                            let trackIndex = self.nextTrackIndex()
                            
                            // CRITICAL: Connect immediately and register AudioUnit
                            self.performanceConnect(avAudioUnit: avAudioUnit, trackIndex: trackIndex)
                            self.setTrackAudioUnit(trackIndex: trackIndex, avAudioUnit: avAudioUnit)
                            
                            completion(trackIndex)
                        } else {
                            print("[ERROR] Path normalization failed for \(sf2Path)")
                            completion(track_index_t(999))
                        }
                    }
                }
            } else {
                print("[ERROR] Apple Sampler component not found")
                completion(track_index_t(999))
            }
        }
    }
    
    func setTrackAudioUnit(trackIndex: track_index_t, avAudioUnit: AVAudioUnit) {
        // Register with scheduler if available
        if let scheduler = scheduler {
            SchedulerSetTrackAudioUnit(scheduler, trackIndex, avAudioUnit.audioUnit)
            print("[DEBUG] Track \(trackIndex) registered with scheduler")
        }
        updateAvAudioUnits(trackIndex: trackIndex, avAudioUnit: avAudioUnit)
        print("[DEBUG] AudioUnit configured for track \(trackIndex)")
    }
    
    func play() {
        print("[DEBUG] HIGH-PERF play() - Engine running: \(engine.isRunning)")
        print("[DEBUG] Connected AudioUnits: \(self.unsafeAvAudioUnits.count)")
        
        guard Thread.isMainThread else {
            DispatchQueue.main.async { self.play() }
            return
        }
        
        // Start scheduler if available
        if let scheduler = scheduler {
            SchedulerPlay(scheduler)
            print("[DEBUG] Scheduler started")
        }
        
        // Engine should already be running, but ensure it's ready
        if !engine.isRunning {
            do {
                engine.prepare()
                try engine.start()
                print("[DEBUG] Engine started (should have been pre-started)")
            } catch {
                print("[ERROR] Failed to start engine: \(error)")
            }
        } else {
            print("[DEBUG] Engine already running - ready for immediate MIDI")
        }
    }
    
    func pause() {
        print("[DEBUG] CocoaEngine.pause() - Clean SF2 system with proper lifecycle")
        
        guard Thread.isMainThread else {
            DispatchQueue.main.async { self.pause() }
            return
        }
        
        // Pause scheduler if available
        if let scheduler = scheduler {
            SchedulerPause(scheduler)
            print("[DEBUG] Scheduler paused")
        }
        
        // IMPROVED: Proper engine lifecycle management to prevent freezes
        if self.engine.isRunning {
            // Stop engine gracefully
            self.engine.stop()
            
            // Send note off to all connected AudioUnits to prevent hanging notes
            for (trackId, audioUnit) in self.unsafeAvAudioUnits {
                for noteNumber in 0...127 {
                    let noteOffCommand: UInt32 = 0x80 // Note Off, channel 0
                    let _ = MusicDeviceMIDIEvent(audioUnit.audioUnit, noteOffCommand, UInt32(noteNumber), 0, 0)
                }
                print("[DEBUG] Sent all notes off to track \(trackId)")
            }
            
            print("[DEBUG] Engine stopped gracefully")
        }
    }
    
    // Initialize mixer with callback for async completion
    private func initMixer(completion: @escaping () -> Void) {
        let componentDescription = AudioComponentDescription(
            componentType: kAudioUnitType_Mixer,
            componentSubType: kAudioUnitSubType_MultiChannelMixer,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )
        
        AVAudioUnit.instantiate(with: componentDescription, options: []) { avAudioUnit, err in
            if let error = err {
                print("[ERROR] Failed to create mixer: \(error)")
                self.mixer = nil
                completion()
                return
            }
            
            self.mixer = avAudioUnit
            
            if let avAudioUnit = avAudioUnit {
                let hardwareFormat = self.engine.outputNode.outputFormat(forBus: 0)
                
                self.engine.attach(avAudioUnit)
                self.engine.connect(avAudioUnit, to: self.engine.outputNode, format: hardwareFormat)
                print("[DEBUG] Mixer created and connected to output")
                
                completion()
            }
        }
    }
    
    // HIGH-PERFORMANCE connection optimized for immediate playback
    private func performanceConnect(avAudioUnit: AVAudioUnit, trackIndex: track_index_t) {
        do {
            // Attach to engine
            self.engine.attach(avAudioUnit)
            
            // Connect with optimal format
            let format = avAudioUnit.outputFormat(forBus: 0)
            self.engine.connect(avAudioUnit, to: self.engine.mainMixerNode, format: format)
            
            // Update tracking
            updateAvAudioUnits(trackIndex: trackIndex, avAudioUnit: avAudioUnit)
            
            print("[DEBUG] HIGH-PERF: Track \(trackIndex) connected and ready")
            
        } catch {
            print("[ERROR] Performance connection failed: \(error)")
        }
    }
    
    // Helper to start engine when we have connected nodes
    private func startEngineIfNeeded() {
        if !self.engine.isRunning && !self.unsafeAvAudioUnits.isEmpty {
            do {
                print("[DEBUG] Auto-starting engine with connected AudioUnits")
                try self.engine.start()
                print("[DEBUG] Engine auto-started successfully")
            } catch {
                print("[ERROR] Failed to auto-start engine: \(error)")
            }
        }
    }
    
    
    private func updateAvAudioUnits(trackIndex: track_index_t, avAudioUnit: AVAudioUnit?) {
        if let avAudioUnit = avAudioUnit {
            self.unsafeAvAudioUnits[trackIndex] = avAudioUnit
        } else {
            self.unsafeAvAudioUnits.removeValue(forKey: trackIndex)
        }
    }
    
    private func nextTrackIndex() -> track_index_t {
        let trackIndex = nextTrackId
        nextTrackId += 1
        print("[DEBUG] 🎵 Created track with ID: \(trackIndex)")
        return trackIndex
    }
    
    private func normalizePath(_ path: String, isAsset: Bool) -> String? {
        print("[DEBUG] normalizePath called: path=\(path) isAsset=\(isAsset)")
        if (!isAsset) {
            print("[DEBUG] Non-asset path, returning as-is: \(path)")
            return path
        } else {
            let key = registrar.lookupKey(forAsset: path)
            print("[DEBUG] Asset key lookup: \(path) -> \(key)")
            let normalizedPath = Bundle.main.path(forResource: key, ofType: nil)
            print("[DEBUG] Bundle path lookup: \(key) -> \(normalizedPath ?? "nil")")
            return normalizedPath
        }
    }
    
    // HIGH-PERFORMANCE: Optimized MIDI event handling for immediate SF2 playback
    func sendMIDIEvent(trackIndex: track_index_t, midiStatus: UInt8, midiData1: UInt8, midiData2: UInt8) {
        // DIAGNOSTIC: Show all available tracks
        NSLog("🔍 Available AudioUnit tracks: %@", Array(unsafeAvAudioUnits.keys).description)
        NSLog("🎵 Looking for track %d to send MIDI status=0x%02X note=%d vel=%d", trackIndex, midiStatus, midiData1, midiData2)
        
        guard let audioUnit = unsafeAvAudioUnits[trackIndex] else {
            NSLog("❌ CRITICAL: No AudioUnit found for track %d - available: %@", trackIndex, Array(unsafeAvAudioUnits.keys).description)
            return
        }
        
        NSLog("✅ Found AudioUnit for track %d, sending MIDI...", trackIndex)
        
        // PERFORMANCE: Direct MIDI with minimal overhead
        let command = UInt32(midiStatus)
        let data1 = UInt32(midiData1) 
        let data2 = UInt32(midiData2)
        
        let result = MusicDeviceMIDIEvent(audioUnit.audioUnit, command, data1, data2, 0)
        
        if result == noErr {
            NSLog("🎵 SUCCESS: MIDI sent to track %d: status=0x%02X note=%d vel=%d", trackIndex, midiStatus, midiData1, midiData2)
        } else {
            NSLog("❌ MIDI FAILED for track %d: error=%d", trackIndex, Int(result))
            
            // Diagnostic: Check if AudioUnit is still valid
            if !engine.attachedNodes.contains(audioUnit) {
                NSLog("❌ AudioUnit not attached to engine for track %d", trackIndex)
            }
        }
    }
    
    // Test function to play a note on a specific track
    func playTestNote(trackIndex: track_index_t, noteNumber: UInt8 = 60, velocity: UInt8 = 100) {
        print("[DEBUG] Playing test note \(noteNumber) on track \(trackIndex)")
        sendMIDIEvent(trackIndex: trackIndex, midiStatus: 0x90, midiData1: noteNumber, midiData2: velocity)
        
        // Auto-stop note after 1 second
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.sendMIDIEvent(trackIndex: trackIndex, midiStatus: 0x80, midiData1: noteNumber, midiData2: 0)
        }
    }
    
    // Stub methods for compatibility - disabled to prevent crashes
    func addTrackSfz(sfzPath: UnsafePointer<CChar>, tuningPath: UnsafePointer<CChar>, completion: @escaping (track_index_t) -> Void) {
        print("[DEBUG] SFZ tracks disabled in minimal mode")
        completion(track_index_t(999)) // Use a safe error value
    }
    
    func addTrackSfzString(sampleRoot: UnsafePointer<CChar>, sfzString: UnsafePointer<CChar>, tuningString: UnsafePointer<CChar>, completion: @escaping (track_index_t) -> Void) {
        print("[DEBUG] SFZ string tracks disabled in minimal mode")
        completion(track_index_t(999)) // Use a safe error value
    }
    
    func addTrackAudioUnit(audioUnitId: String, completion: @escaping (track_index_t) -> Void) {
        print("[DEBUG] AudioUnit tracks disabled in minimal mode")
        completion(track_index_t(999)) // Use a safe error value
    }
    
    func removeTrack(trackIndex: track_index_t) -> Bool {
        print("[DEBUG] Track removal disabled in minimal mode")
        return false
    }
}