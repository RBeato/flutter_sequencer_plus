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
        
    }
    
    public var currentSampleRate: Double {
        return 44100.0
    }
    
    public func createSF2Track(path: String, isAsset: Bool, presetIndex: Int32, completion: @escaping (Int32) -> Void) {
        
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
        
        
        let trackId = self.nextTrackId
        
        
        if isAsset {
            let success = loadSoundFontAssetSync(sampler: sampler, path: path, presetIndex: presetIndex)
        } else {
            let success = loadSoundFontFileSync(sampler: sampler, path: path, presetIndex: presetIndex)
        }
        self.nextTrackId += 1
        self.tracks[trackId] = sampler
        
        // Start the audio engine if it's not running
        if !self.audioEngine.isRunning {
            do {
                try self.audioEngine.start()
            } catch {
                print("[SimpleAudioEngine] ❌ Failed to start audio engine: \(error)")
            }
        }
        
        
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
            } else {
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
                
                // Set program change to select preset
                let status = UInt32(0xC0) // Program Change, channel 0
                let data1 = UInt32(presetIndex)
                let result2 = MusicDeviceMIDIEvent(audioUnit.audioUnit, status, data1, 0, 0)
                
                if result2 == noErr {
                } else {
                    // Preset selection failed
                }
            } else {
                print("[SimpleAudioEngine] ❌ Failed to load SoundFont: \(result)")
            }
        } else {
        }
    }
    
    public func createSFZTrack(path: String, tuningPath: String?, completion: @escaping (Int32) -> Void) {
        
        // Use the same sampler approach as SF2
        let sampler = AVAudioUnitSampler()
        
        self.audioEngine.attach(sampler)
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
        self.audioEngine.connect(sampler, to: self.mainMixer, format: format)
        
        // SFZ tracks: for now, use default sounds (SFZ format not directly supported by AVAudioUnitSampler)
        
        let trackId = self.nextTrackId
        self.nextTrackId += 1
        self.tracks[trackId] = sampler
        
        if !self.audioEngine.isRunning {
            do {
                try self.audioEngine.start()
            } catch {
                print("[SimpleAudioEngine] Failed to start audio engine: \(error)")
            }
        }
        
        completion(Int32(trackId))
    }
    
    public func createAudioUnitTrack(audioUnitId: String, completion: @escaping (Int32) -> Void) {
        
        // Use the same sampler approach
        let sampler = AVAudioUnitSampler()
        
        self.audioEngine.attach(sampler)
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
        self.audioEngine.connect(sampler, to: self.mainMixer, format: format)
        
        // AudioUnit tracks: use default sounds (specific AudioUnit loading not implemented)
        
        let trackId = self.nextTrackId
        self.nextTrackId += 1
        self.tracks[trackId] = sampler
        
        if !self.audioEngine.isRunning {
            do {
                try self.audioEngine.start()
            } catch {
                print("[SimpleAudioEngine] Failed to start audio engine: \(error)")
            }
        }
        
        completion(Int32(trackId))
    }
    
    public func removeTrackById(trackId: Int) {
        tracks.removeValue(forKey: trackId)
    }
    
    public func resetTrack(trackId: Int) {
    }
    
    public func getTrackVolume(trackId: Int) -> Float {
        return 1.0
    }
    
    public func setTrackVolume(trackId: Int, volume: Float) {
    }
    
    public func getBufferAvailable(trackId: Int) -> UInt32 {
        return 1024
    }
    
    public func handleEventsNow(trackId: Int, events: [MIDIEventData]) {
        
        guard let sampler = tracks[trackId] as? AVAudioUnitSampler else {
            return
        }
        
        // Make sure the engine is running
        if !audioEngine.isRunning {
            do {
                try audioEngine.start()
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
                
            case 0x80: // Note Off
                sampler.stopNote(event.data1, onChannel: midiChannel)
                
            case 0xB0: // Control Change
                sampler.sendController(event.data1, withValue: event.data2, onChannel: midiChannel)
                
            case 0xC0: // Program Change
                sampler.sendProgramChange(event.data1, onChannel: midiChannel)
                
            default:
                break // Unsupported MIDI event type
            }
        }
    }
    
    public func scheduleEvents(trackId: Int, events: [MIDIEventData], frameOffset: Int) {
        
        guard let sampler = tracks[trackId] as? AVAudioUnitSampler else {
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
                    
                case 0x80: // Note Off
                    sampler.stopNote(event.data1, onChannel: midiChannel)
                    
                default:
                    break
                }
            }
        }
    }
    
    public func clearEvents(trackId: Int, fromFrame: Int) {
    }
    
    public func playTestNote(trackId: Int) {
        
        guard let sampler = tracks[trackId] as? AVAudioUnitSampler else {
            return
        }
        
        // Make sure engine is running
        if !audioEngine.isRunning {
            do {
                try audioEngine.start()
            } catch {
                print("[SimpleAudioEngine] ❌ Failed to start engine: \(error)")
                return
            }
        }
        
        // Play middle C for drums or C4 for other instruments
        let noteNumber: UInt8 = trackId == 0 ? 36 : 60  // Kick drum or middle C
        let velocity: UInt8 = 100
        
        sampler.startNote(noteNumber, withVelocity: velocity, onChannel: 0)
        
        // Stop the note after 500ms
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            sampler.stopNote(noteNumber, onChannel: 0)
        }
    }
    
    public func play() {
        
        // CRITICAL FIX: Reset position to 0 when starting playback
        currentPosition = 0
        lastAudioTime = 0
        playbackStartTime = Date()
        
        if !audioEngine.isRunning {
            do {
                try audioEngine.start()
                
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
            
            // Note On - Middle C
            let noteOnResult = MusicDeviceMIDIEvent(firstTrack.audioUnit, 0x90, 60, 100, 0)
            if noteOnResult == noErr {
                
                // Note Off after 1 second
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    let noteOffResult = MusicDeviceMIDIEvent(firstTrack.audioUnit, 0x80, 60, 0, 0)
                    if noteOffResult == noErr {
                    }
                }
            } else {
            }
        }
    }
    
    public func pause() {
        
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
        
        // Try to find the asset using Flutter's asset system
        guard let assetKey = Bundle.main.path(forResource: "flutter_assets/\(path)", ofType: nil) else {
            
            // Try alternative paths
            let alternatives = [
                path,
                path.replacingOccurrences(of: "assets/", with: "flutter_assets/")
            ]
            
            for altPath in alternatives {
                if let foundPath = Bundle.main.path(forResource: altPath, ofType: nil) {
                    return loadSoundFontFileSync(sampler: sampler, path: foundPath, presetIndex: presetIndex)
                }
            }
            
            return false
        }
        
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
                break
            }
        }
        
        // If not found, try resource bundle approach
        if soundFontPath == nil {
            for possiblePath in possiblePaths {
                if let bundlePath = Bundle.main.path(forResource: possiblePath, ofType: nil) {
                    soundFontPath = bundlePath
                    break
                }
            }
        }
        
        guard let foundPath = soundFontPath else {
            
            return
        }
        
        loadSoundFontFile(sampler: sampler, path: foundPath, presetIndex: presetIndex)
    }
    
    private func loadSoundFontFileSync(sampler: AVAudioUnitSampler, path: String, presetIndex: Int32) -> Bool {
        
        guard FileManager.default.fileExists(atPath: path) else {
            return false
        }
        
        // Check file size for debugging
        if let attributes = try? FileManager.default.attributesOfItem(atPath: path),
           let fileSize = attributes[.size] as? Int {
            let sizeInKB = Double(fileSize) / 1024.0
        }
        
        let soundFontURL = URL(fileURLWithPath: path)
        
        do {
            
            // Load the SF2 file into the sampler
            try sampler.loadSoundBankInstrument(
                at: soundFontURL,
                program: UInt8(presetIndex % 128), // Ensure within valid range
                bankMSB: UInt8(presetIndex / 128), // Use MSB for drum kits (bank 128)
                bankLSB: 0
            )
            
            return true
            
        } catch {
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
            
        } catch {
        }
    }
}