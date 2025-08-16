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
        
        // Configure audio session FIRST
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true)
            print("[DEBUG] Audio session configured")
        } catch {
            print("[ERROR] Audio session setup failed: \(error)")
        }
        
        // Get a SAFE output format - use standard 44.1kHz stereo
        outputFormat = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
        print("[DEBUG] Using safe output format: 44.1kHz stereo")
        
        // Initialize a SIMPLE mixer without complex configuration
        initSimpleMixer()
        
        // ULTRA-MINIMAL: Disable scheduler to avoid crashes
        self.scheduler = nil
        callbackToDartInt32(sampleRateCallbackPort, 44100)
        print("[DEBUG] Scheduler DISABLED for minimal mode")
        
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
        NSLog("🚨🚨🚨 NUCLEAR CocoaEngine: Adding SF2 track: \(sf2Path) isAsset=\(isAsset) preset=\(presetIndex)")
        print("[DEBUG] Adding SF2 track: \(sf2Path)")
        
        AudioUnitUtils.loadAudioUnits { [weak self] avAudioUnitComponents in
            guard let self = self else { 
                completion(track_index_t.max)
                return 
            }
            
            let appleSamplerComponent = avAudioUnitComponents.first(where: isAppleSampler)
            
            if let appleSamplerComponent = appleSamplerComponent {
                AudioUnitUtils.instantiate(
                    description: appleSamplerComponent.audioComponentDescription,
                    sampleRate: 44100,
                    options: []
                ) { [weak self] (avAudioUnit: AVAudioUnit?) in
                    guard let self = self, let avAudioUnit = avAudioUnit else {
                        completion(track_index_t.max)
                        return
                    }
                    
                    DispatchQueue.main.async {
                        if let normalizedPath = self.normalizePath(sf2Path, isAsset: isAsset) {
                            let url = URL(fileURLWithPath: normalizedPath)
                            
                            // Simple SF2 loading without complex memory management
                            NSLog("🎼🎼🎼 NUCLEAR: Loading SF2 file: \(url.path)")
                            print("[DEBUG] About to call loadSoundFont for: \(url.lastPathComponent)")
                            let loadSuccess = loadSoundFont(avAudioUnit: avAudioUnit, soundFontURL: url, presetIndex: presetIndex)
                            print("[DEBUG] loadSoundFont returned: \(loadSuccess)")
                            if loadSuccess {
                                let trackIndex = self.nextTrackIndex()
                                NSLog("✅✅✅ NUCLEAR: SF2 loaded successfully! Track=\(trackIndex) File=\(url.lastPathComponent)")
                                self.setTrackAudioUnit(trackIndex: trackIndex, avAudioUnit: avAudioUnit)
                                completion(trackIndex)
                            } else {
                                NSLog("❌❌❌ NUCLEAR: SF2 loading FAILED for \(sf2Path)")
                                print("[DEBUG] SF2 loading failed for \(sf2Path)")
                                completion(track_index_t.max) // Return max value to indicate failure
                            }
                        } else {
                            NSLog("❌❌❌ NUCLEAR: Path normalization FAILED for \(sf2Path)")
                            print("[DEBUG] Path normalization failed for \(sf2Path)")
                            completion(track_index_t.max) // Return max value to indicate failure
                        }
                    }
                }
            } else {
                print("[DEBUG] Apple Sampler component not found")
                completion(track_index_t.max) // Return max value to indicate failure
            }
        }
    }
    
    func setTrackAudioUnit(trackIndex: track_index_t, avAudioUnit: AVAudioUnit) {
        // MINIMAL: Skip scheduler operations
        updateAvAudioUnits(trackIndex: trackIndex, avAudioUnit: avAudioUnit)
        simpleConnect(avAudioUnit: avAudioUnit)
        print("[DEBUG] AudioUnit connected without scheduler")
    }
    
    func play() {
        print("[DEBUG] CocoaEngine.play() called - Clean SF2 system")
        print("[DEBUG] Current thread: \(Thread.isMainThread ? "main" : "background")")
        print("[DEBUG] Connected AudioUnits: \(self.unsafeAvAudioUnits.count)")
        
        guard Thread.isMainThread else {
            print("[DEBUG] Dispatching to main thread...")
            DispatchQueue.main.async { self.play() }
            return
        }
        
        // Check if we have any connected audio units
        if self.unsafeAvAudioUnits.isEmpty {
            print("[ERROR] No audio units connected, cannot start engine")
            return
        }
        
        do {
            // IMPROVED: Proper lifecycle management
            if !self.engine.isRunning {
                print("[DEBUG] Starting engine with \(self.unsafeAvAudioUnits.count) connected units")
                
                // Prepare engine before starting to avoid crashes
                self.engine.prepare()
                try self.engine.start()
                print("[DEBUG] Engine started successfully")
            }
            
        } catch {
            print("[ERROR] Play failed: \(error)")
        }
    }
    
    func pause() {
        print("[DEBUG] CocoaEngine.pause() - Clean SF2 system with proper lifecycle")
        
        guard Thread.isMainThread else {
            DispatchQueue.main.async { self.pause() }
            return
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
    
    // MINIMAL mixer initialization - just use the engine's main mixer
    private func initSimpleMixer() {
        // Use the engine's built-in main mixer node instead of creating a custom one
        self.mixer = nil // We'll use the main mixer node directly
        print("[DEBUG] Using engine main mixer node")
    }
    
    // MINIMAL connection - connect directly to main mixer
    private func simpleConnect(avAudioUnit: AVAudioUnit) {
        // Simple connection to main mixer without bus management
        do {
            self.engine.attach(avAudioUnit)
            self.engine.connect(avAudioUnit, to: self.engine.mainMixerNode, format: self.outputFormat)
            print("[DEBUG] Simple connection to main mixer completed")
            
            // Start the engine as soon as we have a connected AudioUnit
            self.startEngineIfNeeded()
            
            // Test sound immediately after connection
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.testSound(avAudioUnit: avAudioUnit)
            }
        } catch {
            print("[ERROR] Simple connection failed: \(error)")
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
    
    // Test function to trigger a simple sound
    private func testSound(avAudioUnit: AVAudioUnit) {
        print("[DEBUG] Testing sound on connected AudioUnit")
        
        // Send a simple note-on MIDI message
        let noteOnCommand: UInt32 = 0x90 // Note On, channel 0
        let noteNumber: UInt32 = 60 // Middle C
        let velocity: UInt32 = 100
        
        let result = MusicDeviceMIDIEvent(avAudioUnit.audioUnit, noteOnCommand, noteNumber, velocity, 0)
        if result == noErr {
            print("[DEBUG] Note ON sent successfully")
            
            // Send note off after 1 second
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                let noteOffCommand: UInt32 = 0x80 // Note Off, channel 0
                let result2 = MusicDeviceMIDIEvent(avAudioUnit.audioUnit, noteOffCommand, noteNumber, 0, 0)
                if result2 == noErr {
                    print("[DEBUG] Note OFF sent successfully")
                }
            }
        } else {
            print("[ERROR] Failed to send MIDI note: \(result)")
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
    
    // INDUSTRY STANDARD: MIDI event handling for SF2 playback
    func sendMIDIEvent(trackIndex: track_index_t, midiStatus: UInt8, midiData1: UInt8, midiData2: UInt8) {
        guard let audioUnit = unsafeAvAudioUnits[trackIndex] else {
            print("[DEBUG] No AudioUnit found for track \(trackIndex)")
            return
        }
        
        let command = UInt32(midiStatus)
        let data1 = UInt32(midiData1)
        let data2 = UInt32(midiData2)
        
        let result = MusicDeviceMIDIEvent(audioUnit.audioUnit, command, data1, data2, 0)
        if result == noErr {
            print("[DEBUG] MIDI sent to track \(trackIndex): status=\(midiStatus) data1=\(midiData1) data2=\(midiData2)")
        } else {
            print("[DEBUG] MIDI send failed for track \(trackIndex): \(result)")
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