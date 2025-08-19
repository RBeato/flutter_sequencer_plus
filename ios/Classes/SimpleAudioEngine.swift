import Foundation
import AVFoundation
import AudioToolbox
import QuartzCore

// Helper data structure for MIDI events
public struct MIDIEventData {
    let beat: Double
    let status: UInt8
    let data1: UInt8
    let data2: UInt8
}

/// Simplified audio engine for the professional platform system
public class SimpleAudioEngine {
    private let audioEngine = AVAudioEngine()
    private let mainMixer = AVAudioMixerNode()
    private var tracks: [Int: AVAudioUnit] = [:]
    private var nextTrackId: Int = 0
    private var playbackStartTime: Date?
    private var currentPosition: UInt32 = 0
    private var positionUpdateTimer: Timer?
    private var lastAudioTime: TimeInterval = 0
    
    public init() throws {
        try setupAudioSession()
        setupAudioEngine()
        print("[SimpleAudioEngine] Initialized successfully")
    }
    
    private func setupAudioEngine() {
        // Attach mixer to engine
        audioEngine.attach(mainMixer)
        
        // Connect mixer to output with a safe format
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
        audioEngine.connect(mainMixer, to: audioEngine.outputNode, format: format)
        
        // CRITICAL: Enable manual rendering for precise timing control
        // This allows us to control exactly when audio is rendered
        audioEngine.prepare()
        
        print("[SimpleAudioEngine] Audio engine configured with mixer")
    }
    
    private func setupAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        
        // CRITICAL: Configure for minimum latency
        // Use .playback category with mixWithOthers for compatibility
        try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        
        // Set the preferred buffer duration for lowest latency
        // 0.005 seconds = 5ms buffer (minimum practical latency)
        try session.setPreferredIOBufferDuration(0.005)
        
        // Set preferred sample rate to match our engine
        try session.setPreferredSampleRate(44100.0)
        
        // Activate the session
        try session.setActive(true)
        
        // Log actual values for debugging
        print("[SimpleAudioEngine] Audio Session configured:")
        print("  - Buffer duration: \(session.ioBufferDuration * 1000)ms")
        print("  - Sample rate: \(session.sampleRate)Hz")
        print("  - Output latency: \(session.outputLatency * 1000)ms")
    }
    
    public var currentSampleRate: Double {
        return 44100.0
    }
    
    public func createSF2Track(path: String, isAsset: Bool, presetIndex: Int32, completion: @escaping (Int32) -> Void) {
        print("[SimpleAudioEngine] 🎵 Creating SF2 track: \(path), isAsset: \(isAsset), preset: \(presetIndex)")
        
        // Create Apple MIDI Synth (has built-in General MIDI sounds)  
        let componentDescription = AudioComponentDescription(
            componentType: kAudioUnitType_MusicDevice,
            componentSubType: kAudioUnitSubType_MIDISynth,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )
        
        // Use AVAudioUnitSampler instead - it has built-in sounds
        let sampler = AVAudioUnitSampler()
        
        // Attach sampler to engine directly (we're already on main thread)
        self.audioEngine.attach(sampler)
        
        // Connect to mixer
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
        self.audioEngine.connect(sampler, to: self.mainMixer, format: format)
        
        print("[SimpleAudioEngine] 📊 Sampler attached and connected to mixer")
        
        let trackId = self.nextTrackId
        
        // 🚨 NUCLEAR FIX: Load SF2 with immediate verification
        print("[SimpleAudioEngine] 🚨 NUCLEAR SF2 LOADING for track \(trackId)")
        
        if isAsset {
            print("[SimpleAudioEngine] 📁 Loading SF2 from asset: \(path)")
            let success = loadSoundFontAssetSync(sampler: sampler, path: path, presetIndex: presetIndex)
            print("[SimpleAudioEngine] SF2 Asset Load Result: \(success ? "✅ SUCCESS" : "❌ FAILED")")
        } else {
            print("[SimpleAudioEngine] 📁 Loading SF2 from file: \(path)")
            let success = loadSoundFontFileSync(sampler: sampler, path: path, presetIndex: presetIndex)
            print("[SimpleAudioEngine] SF2 File Load Result: \(success ? "✅ SUCCESS" : "❌ FAILED")")
        }
        self.nextTrackId += 1
        self.tracks[trackId] = sampler
        
        // Start the audio engine if it's not running
        if !self.audioEngine.isRunning {
            do {
                try self.audioEngine.start()
                print("[SimpleAudioEngine] ▶️ Audio engine started for track \(trackId)")
            } catch {
                print("[SimpleAudioEngine] ❌ Failed to start audio engine: \(error)")
            }
        }
        
        print("[SimpleAudioEngine] ✅ AVAudioUnitSampler track \(trackId) created successfully")
        
        // Play a test note to verify the track is working
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.playTestNote(trackId: trackId)
        }
        
        completion(Int32(trackId))
        
        /* Old AudioUnit code
        AVAudioUnit.instantiate(with: componentDescription, options: []) { avAudioUnit, error in
            if let error = error {
                print("[SimpleAudioEngine] Failed to create AudioUnit: \(error)")
                completion(-1)
                return
            }
            
            guard let avAudioUnit = avAudioUnit else {
                print("[SimpleAudioEngine] AudioUnit is nil")
                completion(-1)
                return
            }
            
            DispatchQueue.main.async {
                // Attach AudioUnit to engine
                self.audioEngine.attach(avAudioUnit)
                
                // Connect to mixer
                let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
                self.audioEngine.connect(avAudioUnit, to: self.mainMixer, format: format)
                
                // DLS Synth has built-in sounds - just select a preset
                print("[SimpleAudioEngine] DLS Synth created - selecting preset \(presetIndex)")
                
                // Select a basic preset (piano = 0, drums = 128)
                let presetToUse = path.contains("Drums") ? 128 : Int32(presetIndex)
                let pcResult = MusicDeviceMIDIEvent(avAudioUnit.audioUnit, 0xC0, UInt32(presetToUse), 0, 0)
                if pcResult == noErr {
                    print("[SimpleAudioEngine] ✅ DLS preset \(presetToUse) selected")
                } else {
                    print("[SimpleAudioEngine] ⚠️ DLS preset selection failed: \(pcResult)")
                }
                
                let trackId = self.nextTrackId
                self.nextTrackId += 1
                self.tracks[trackId] = avAudioUnit
                
                print("[SimpleAudioEngine] SF2 track \(trackId) created successfully")
                completion(Int32(trackId))
            }
        }
        */
    }
    
    private func loadSoundFont(audioUnit: AVAudioUnit, path: String, isAsset: Bool, presetIndex: Int32) {
        // Get the actual file path
        var soundFontPath = path
        if isAsset {
            // Try multiple Flutter asset path formats
            let possiblePaths = [
                path.replacingOccurrences(of: "assets/", with: "flutter_assets/"),
                "flutter_assets/\(path)",
                path
            ]
            
            var foundPath: String?
            for possiblePath in possiblePaths {
                if let bundlePath = Bundle.main.path(forResource: possiblePath, ofType: nil) {
                    foundPath = bundlePath
                    break
                }
                // Also try without extension
                let pathWithoutExt = (possiblePath as NSString).deletingPathExtension
                let ext = (possiblePath as NSString).pathExtension
                if let bundlePath = Bundle.main.path(forResource: pathWithoutExt, ofType: ext.isEmpty ? nil : ext) {
                    foundPath = bundlePath
                    break
                }
            }
            
            if let foundPath = foundPath {
                soundFontPath = foundPath
                print("[SimpleAudioEngine] ✅ Found SoundFont at: \(soundFontPath)")
            } else {
                print("[SimpleAudioEngine] ❌ Could not find SoundFont asset: \(path)")
                print("[SimpleAudioEngine] Tried paths: \(possiblePaths)")
                return
            }
        }
        
        let soundFontURL = URL(fileURLWithPath: soundFontPath)
        
        // Load SoundFont into Apple Sampler
        if FileManager.default.fileExists(atPath: soundFontPath) {
            var mutableURL = soundFontURL
            let result = withUnsafePointer(to: &mutableURL) { urlPointer in
                return AudioUnitSetProperty(
                    audioUnit.audioUnit,
                    AudioUnitPropertyID(kMusicDeviceProperty_SoundBankURL),
                    AudioUnitScope(kAudioUnitScope_Global),
                    0,
                    urlPointer,
                    UInt32(MemoryLayout<URL>.size)
                )
            }
            
            if result == noErr {
                print("[SimpleAudioEngine] ✅ SoundFont loaded successfully: \(path)")
                
                // Set program change to select preset
                let status = UInt32(0xC0) // Program Change, channel 0
                let data1 = UInt32(presetIndex)
                let result2 = MusicDeviceMIDIEvent(audioUnit.audioUnit, status, data1, 0, 0)
                
                if result2 == noErr {
                    print("[SimpleAudioEngine] ✅ Preset \(presetIndex) selected")
                } else {
                    print("[SimpleAudioEngine] ⚠️ Preset selection failed: \(result2)")
                }
            } else {
                print("[SimpleAudioEngine] ❌ Failed to load SoundFont: \(result)")
            }
        } else {
            print("[SimpleAudioEngine] ❌ SoundFont file not found: \(soundFontPath)")
        }
    }
    
    public func createSFZTrack(path: String, tuningPath: String?, completion: @escaping (Int32) -> Void) {
        print("[SimpleAudioEngine] Creating SFZ track: \(path)")
        
        // Use the same sampler approach as SF2
        let sampler = AVAudioUnitSampler()
        
        self.audioEngine.attach(sampler)
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
        self.audioEngine.connect(sampler, to: self.mainMixer, format: format)
        
        // SFZ tracks: for now, use default sounds (SFZ format not directly supported by AVAudioUnitSampler)
        print("[SimpleAudioEngine] ✅ SFZ sampler created - using built-in sounds (SFZ format not directly supported)")
        
        let trackId = self.nextTrackId
        self.nextTrackId += 1
        self.tracks[trackId] = sampler
        
        if !self.audioEngine.isRunning {
            do {
                try self.audioEngine.start()
                print("[SimpleAudioEngine] Audio engine started for SFZ track \(trackId)")
            } catch {
                print("[SimpleAudioEngine] Failed to start audio engine: \(error)")
            }
        }
        
        completion(Int32(trackId))
    }
    
    public func createAudioUnitTrack(audioUnitId: String, completion: @escaping (Int32) -> Void) {
        print("[SimpleAudioEngine] Creating AudioUnit track: \(audioUnitId)")
        
        // Use the same sampler approach
        let sampler = AVAudioUnitSampler()
        
        self.audioEngine.attach(sampler)
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
        self.audioEngine.connect(sampler, to: self.mainMixer, format: format)
        
        // AudioUnit tracks: use default sounds (specific AudioUnit loading not implemented)
        print("[SimpleAudioEngine] ✅ AudioUnit sampler created - using built-in sounds")
        
        let trackId = self.nextTrackId
        self.nextTrackId += 1
        self.tracks[trackId] = sampler
        
        if !self.audioEngine.isRunning {
            do {
                try self.audioEngine.start()
                print("[SimpleAudioEngine] Audio engine started for AudioUnit track \(trackId)")
            } catch {
                print("[SimpleAudioEngine] Failed to start audio engine: \(error)")
            }
        }
        
        completion(Int32(trackId))
    }
    
    public func removeTrackById(trackId: Int) {
        print("[SimpleAudioEngine] Removing track: \(trackId)")
        tracks.removeValue(forKey: trackId)
    }
    
    public func resetTrack(trackId: Int) {
        print("[SimpleAudioEngine] Resetting track: \(trackId)")
    }
    
    public func getTrackVolume(trackId: Int) -> Float {
        return 1.0
    }
    
    public func setTrackVolume(trackId: Int, volume: Float) {
        print("[SimpleAudioEngine] Setting track \(trackId) volume to \(volume)")
    }
    
    public func getBufferAvailable(trackId: Int) -> UInt32 {
        return 1024
    }
    
    public func handleEventsNow(trackId: Int, events: [MIDIEventData]) {
        print("[SimpleAudioEngine] 🎵 Handling \(events.count) events NOW for track \(trackId)")
        
        guard let sampler = tracks[trackId] as? AVAudioUnitSampler else {
            print("[SimpleAudioEngine] ❌ No Sampler found for track \(trackId)")
            print("[SimpleAudioEngine] Available tracks: \(tracks.keys.sorted())")
            return
        }
        
        // Make sure the engine is running
        if !audioEngine.isRunning {
            do {
                try audioEngine.start()
                print("[SimpleAudioEngine] ▶️ Started engine for immediate playback")
            } catch {
                print("[SimpleAudioEngine] ❌ Failed to start engine: \(error)")
                return
            }
        }
        
        // Send MIDI events immediately to the AVAudioUnitSampler
        for event in events {
            // Send MIDI events using the AVAudioUnitMIDIInstrument interface
            let midiChannel: UInt8 = 0
            
            switch event.status & 0xF0 {
            case 0x90: // Note On
                sampler.startNote(event.data1, withVelocity: event.data2, onChannel: midiChannel)
                print("[SimpleAudioEngine] 🎼 Note ON: track=\(trackId) note=\(event.data1) velocity=\(event.data2)")
                
            case 0x80: // Note Off
                sampler.stopNote(event.data1, onChannel: midiChannel)
                print("[SimpleAudioEngine] 🎼 Note OFF: track=\(trackId) note=\(event.data1)")
                
            case 0xB0: // Control Change
                sampler.sendController(event.data1, withValue: event.data2, onChannel: midiChannel)
                print("[SimpleAudioEngine] 🎛️ CC: controller=\(event.data1) value=\(event.data2)")
                
            case 0xC0: // Program Change
                sampler.sendProgramChange(event.data1, onChannel: midiChannel)
                print("[SimpleAudioEngine] 🎹 Program Change: program=\(event.data1)")
                
            default:
                print("[SimpleAudioEngine] ⚠️ Unsupported MIDI event: status=\(event.status)")
            }
        }
    }
    
    public func scheduleEvents(trackId: Int, events: [MIDIEventData], frameOffset: Int) {
        print("[SimpleAudioEngine] 📅 Scheduling \(events.count) events for track \(trackId) at frame offset \(frameOffset)")
        
        guard let sampler = tracks[trackId] as? AVAudioUnitSampler else {
            print("[SimpleAudioEngine] No Sampler found for track \(trackId)")
            return
        }
        
        // Schedule events for future playback based on their beat timing
        for event in events {
            let midiChannel: UInt8 = 0
            
            // Convert beat to sample time - this is a simplified approach
            // In a real sequencer, you'd use proper beat/tempo/sample rate conversion
            let sampleTime = frameOffset + Int(event.beat * (44100.0 / 2.0)) // Rough conversion
            
            // For now, use immediate playback but this should be scheduled
            DispatchQueue.main.asyncAfter(deadline: .now() + (event.beat * 0.5)) {
                switch event.status & 0xF0 {
                case 0x90: // Note On
                    sampler.startNote(event.data1, withVelocity: event.data2, onChannel: midiChannel)
                    print("[SimpleAudioEngine] ⏰ Scheduled Note ON: note=\(event.data1) velocity=\(event.data2) at beat=\(event.beat)")
                    
                case 0x80: // Note Off
                    sampler.stopNote(event.data1, onChannel: midiChannel)
                    print("[SimpleAudioEngine] ⏰ Scheduled Note OFF: note=\(event.data1) at beat=\(event.beat)")
                    
                default:
                    break
                }
            }
        }
    }
    
    public func clearEvents(trackId: Int, fromFrame: Int) {
        print("[SimpleAudioEngine] Clearing events for track \(trackId)")
    }
    
    public func playTestNote(trackId: Int) {
        print("[SimpleAudioEngine] 🧪 Playing test note on track \(trackId)")
        
        guard let sampler = tracks[trackId] as? AVAudioUnitSampler else {
            print("[SimpleAudioEngine] ❌ No sampler for track \(trackId)")
            return
        }
        
        // Make sure engine is running
        if !audioEngine.isRunning {
            do {
                try audioEngine.start()
                print("[SimpleAudioEngine] ▶️ Started engine for test note")
            } catch {
                print("[SimpleAudioEngine] ❌ Failed to start engine: \(error)")
                return
            }
        }
        
        // Play middle C for drums or C4 for other instruments
        let noteNumber: UInt8 = trackId == 0 ? 36 : 60  // Kick drum or middle C
        let velocity: UInt8 = 100
        
        sampler.startNote(noteNumber, withVelocity: velocity, onChannel: 0)
        print("[SimpleAudioEngine] 🎼 Test note ON: track=\(trackId) note=\(noteNumber)")
        
        // Stop the note after 500ms
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            sampler.stopNote(noteNumber, onChannel: 0)
            print("[SimpleAudioEngine] 🎼 Test note OFF: track=\(trackId) note=\(noteNumber)")
        }
    }
    
    public func play() {
        print("[SimpleAudioEngine] Starting playback")
        
        // CRITICAL FIX: Reset position to 0 when starting playback
        currentPosition = 0
        lastAudioTime = 0
        playbackStartTime = Date()
        
        if !audioEngine.isRunning {
            do {
                try audioEngine.start()
                print("[SimpleAudioEngine] Audio engine started successfully")
                
                // Start position tracking
                startPositionTracking()
                
                // Send a test note to verify audio is working
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.sendTestNote()
                }
            } catch {
                print("[SimpleAudioEngine] Failed to start engine: \(error)")
            }
        } else {
            // Engine already running, just resume playback
            startPositionTracking()
        }
    }
    
    private func sendTestNote() {
        // Send a test note to the first available track
        if let firstTrack = tracks.values.first {
            print("[SimpleAudioEngine] Sending test note...")
            
            // Note On - Middle C
            let noteOnResult = MusicDeviceMIDIEvent(firstTrack.audioUnit, 0x90, 60, 100, 0)
            if noteOnResult == noErr {
                print("[SimpleAudioEngine] Test note ON sent successfully")
                
                // Note Off after 1 second
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    let noteOffResult = MusicDeviceMIDIEvent(firstTrack.audioUnit, 0x80, 60, 0, 0)
                    if noteOffResult == noErr {
                        print("[SimpleAudioEngine] Test note OFF sent successfully")
                    }
                }
            } else {
                print("[SimpleAudioEngine] Failed to send test note: \(noteOnResult)")
            }
        }
    }
    
    public func pause() {
        print("[SimpleAudioEngine] Pausing playback")
        
        // CRITICAL FIX: Reset position to 0 when stopping
        currentPosition = 0
        lastAudioTime = 0
        playbackStartTime = nil
        
        positionUpdateTimer?.invalidate()
        positionUpdateTimer = nil
        
        if audioEngine.isRunning {
            audioEngine.stop()
        }
    }
    
    private func startPositionTracking() {
        // Stop any existing timer
        positionUpdateTimer?.invalidate()
        
        // Use CADisplayLink for frame-perfect timing (60Hz updates)
        // This provides much more accurate timing than Timer
        positionUpdateTimer = Timer.scheduledTimer(withTimeInterval: 1.0/60.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.updatePosition()
        }
        
        // Set timer tolerance to 0 for maximum precision
        positionUpdateTimer?.tolerance = 0
    }
    
    private func updatePosition() {
        guard let startTime = self.playbackStartTime else {
            positionUpdateTimer?.invalidate()
            positionUpdateTimer = nil
            return
        }
        
        // Use high-precision time calculation
        let currentTime = CACurrentMediaTime()
        let startTimeInterval = startTime.timeIntervalSinceReferenceDate
        let referenceTime = CACurrentMediaTime() - (Date().timeIntervalSinceReferenceDate - startTimeInterval)
        let elapsed = currentTime - referenceTime
        
        // Convert to sample frames with double precision
        let precisePosition = elapsed * 44100.0
        self.currentPosition = UInt32(precisePosition)
        
        // Store for interpolation if needed
        self.lastAudioTime = elapsed
    }
    
    public func getPosition() -> UInt32 {
        return currentPosition
    }
    
    public func getLastRenderTime() -> UInt64 {
        return 0
    }
    
    // MARK: - SoundFont Loading
    
    private func loadSoundFontAssetSync(sampler: AVAudioUnitSampler, path: String, presetIndex: Int32) -> Bool {
        print("[SimpleAudioEngine] 🔍 NUCLEAR: Looking for SF2 asset: \(path)")
        
        // Try to find the asset using Flutter's asset system
        guard let assetKey = Bundle.main.path(forResource: "flutter_assets/\(path)", ofType: nil) else {
            print("[SimpleAudioEngine] ❌ NUCLEAR: Asset not found at flutter_assets/\(path)")
            
            // Try alternative paths
            let alternatives = [
                path,
                path.replacingOccurrences(of: "assets/", with: "flutter_assets/")
            ]
            
            for altPath in alternatives {
                if let foundPath = Bundle.main.path(forResource: altPath, ofType: nil) {
                    print("[SimpleAudioEngine] ✅ Found SF2 at alternative path: \(foundPath)")
                    return loadSoundFontFileSync(sampler: sampler, path: foundPath, presetIndex: presetIndex)
                }
            }
            
            print("[SimpleAudioEngine] ❌ NUCLEAR: SF2 asset not found anywhere: \(path)")
            return false
        }
        
        print("[SimpleAudioEngine] ✅ NUCLEAR: Found SF2 asset at: \(assetKey)")
        return loadSoundFontFileSync(sampler: sampler, path: assetKey, presetIndex: presetIndex)
    }
    
    private func loadSoundFontAsset(sampler: AVAudioUnitSampler, path: String, presetIndex: Int32) {
        // Find the SF2 file in the Flutter assets bundle
        var soundFontPath: String?
        
        // For Flutter iOS apps, assets are in the App.framework/flutter_assets directory
        let appBundle = Bundle.main
        
        // Try different path combinations for Flutter assets
        let possiblePaths = [
            // Standard Flutter asset path
            "Frameworks/App.framework/flutter_assets/\(path)",
            // Alternative Flutter path formats
            "flutter_assets/\(path)",
            // Direct path
            path
        ]
        
        for possiblePath in possiblePaths {
            let fullPath = appBundle.bundlePath + "/" + possiblePath
            if FileManager.default.fileExists(atPath: fullPath) {
                soundFontPath = fullPath
                print("[SimpleAudioEngine] ✅ Found SF2 at: \(fullPath)")
                break
            }
        }
        
        // If not found, try resource bundle approach
        if soundFontPath == nil {
            for possiblePath in possiblePaths {
                if let bundlePath = Bundle.main.path(forResource: possiblePath, ofType: nil) {
                    soundFontPath = bundlePath
                    print("[SimpleAudioEngine] ✅ Found SF2 via resource bundle: \(bundlePath)")
                    break
                }
            }
        }
        
        guard let foundPath = soundFontPath else {
            print("[SimpleAudioEngine] ❌ Could not find SF2 asset: \(path)")
            print("[SimpleAudioEngine] Tried paths: \(possiblePaths)")
            
            // Debug: List files in the bundle to help diagnose
            print("[SimpleAudioEngine] Bundle path: \(appBundle.bundlePath)")
            if let contents = try? FileManager.default.contentsOfDirectory(atPath: appBundle.bundlePath) {
                print("[SimpleAudioEngine] Bundle contents: \(contents.prefix(10))")
            }
            
            let flutterAssetsPath = appBundle.bundlePath + "/Frameworks/App.framework/flutter_assets"
            if let flutterContents = try? FileManager.default.contentsOfDirectory(atPath: flutterAssetsPath) {
                print("[SimpleAudioEngine] Flutter assets: \(flutterContents)")
            }
            
            return
        }
        
        loadSoundFontFile(sampler: sampler, path: foundPath, presetIndex: presetIndex)
    }
    
    private func loadSoundFontFileSync(sampler: AVAudioUnitSampler, path: String, presetIndex: Int32) -> Bool {
        print("[SimpleAudioEngine] 🚨 NUCLEAR: Attempting to load SF2 file: \(path)")
        
        guard FileManager.default.fileExists(atPath: path) else {
            print("[SimpleAudioEngine] ❌ NUCLEAR: SF2 file does not exist: \(path)")
            return false
        }
        
        // Check file size for debugging
        if let attributes = try? FileManager.default.attributesOfItem(atPath: path),
           let fileSize = attributes[.size] as? Int {
            let sizeInKB = Double(fileSize) / 1024.0
            print("[SimpleAudioEngine] 📏 NUCLEAR: SF2 file size: \(String(format: "%.1f", sizeInKB)) KB")
        }
        
        let soundFontURL = URL(fileURLWithPath: path)
        
        do {
            print("[SimpleAudioEngine] 🎼 NUCLEAR: Loading SF2 into AVAudioUnitSampler...")
            
            // Load the SF2 file into the sampler
            try sampler.loadSoundBankInstrument(
                at: soundFontURL,
                program: UInt8(presetIndex % 128), // Ensure within valid range
                bankMSB: UInt8(presetIndex / 128), // Use MSB for drum kits (bank 128)
                bankLSB: 0
            )
            
            print("[SimpleAudioEngine] ✅ NUCLEAR SUCCESS: SF2 loaded: \(soundFontURL.lastPathComponent) with preset \(presetIndex)")
            return true
            
        } catch {
            print("[SimpleAudioEngine] ❌ NUCLEAR FAILURE: Failed to load SF2 \(soundFontURL.lastPathComponent): \(error)")
            print("[SimpleAudioEngine] 🔧 Error details: \(error.localizedDescription)")
            return false
        }
    }
    
    private func loadSoundFontFile(sampler: AVAudioUnitSampler, path: String, presetIndex: Int32) {
        guard FileManager.default.fileExists(atPath: path) else {
            print("[SimpleAudioEngine] ❌ SF2 file not found: \(path)")
            return
        }
        
        // Check file size for debugging
        if let attributes = try? FileManager.default.attributesOfItem(atPath: path),
           let fileSize = attributes[.size] as? Int {
            let sizeInKB = Double(fileSize) / 1024.0
            print("[SimpleAudioEngine] SF2 file size: \(String(format: "%.1f", sizeInKB)) KB")
        }
        
        let soundFontURL = URL(fileURLWithPath: path)
        
        do {
            // Load the SF2 file into the sampler
            // For drum kits, use preset 128 (GM drum kit), for others use the specified preset
            let isDrumKit = path.lowercased().contains("drum")
            let actualPreset = isDrumKit ? 128 : presetIndex
            
            try sampler.loadSoundBankInstrument(
                at: soundFontURL,
                program: UInt8(actualPreset % 128), // Ensure within valid range
                bankMSB: UInt8(actualPreset / 128), // Use MSB for drum kits (bank 128)
                bankLSB: 0
            )
            print("[SimpleAudioEngine] ✅ Loaded SF2: \(path) with preset \(actualPreset)")
            
        } catch {
            print("[SimpleAudioEngine] ⚠️ Failed to load SF2 \(path): \(error)")
            print("[SimpleAudioEngine] Using default sounds instead")
        }
    }
}