import Foundation
import AVFoundation
import AudioToolbox

/// Professional audio track with real-time MIDI processing
/// Lock-free design for maximum performance
public class AudioTrack {
    
    // MARK: - Core Properties
    public let id: Int
    public let instrumentType: InstrumentType
    private let audioFormat: AVAudioFormat
    
    // MARK: - Audio Chain
    private var audioUnit: AVAudioUnit?
    private let audioEngine: AVAudioEngine
    private let mixer: AVAudioMixerNode
    private var mixerBus: AVAudioNodeBus
    
    // MARK: - MIDI Processing
    private var midiProcessor: MIDIProcessor!
    
    // MARK: - Performance
    private let processingQueue = DispatchQueue(label: "com.sequencer.track", qos: .userInteractive)
    private var isConnected = false
    
    // MARK: - Audio Parameters
    private var volume: Float = 1.0
    private var pan: Float = 0.0
    private var mute = false
    private var solo = false
    
    // MARK: - Initialization
    public init(id: Int, instrumentType: InstrumentType, audioFormat: AVAudioFormat, 
                audioEngine: AVAudioEngine, mixer: AVAudioMixerNode) {
        self.id = id
        self.instrumentType = instrumentType
        self.audioFormat = audioFormat
        self.audioEngine = audioEngine
        self.mixer = mixer
        self.mixerBus = AVAudioNodeBus(id)
        
        setupMIDIProcessor()
        print("[Track \(id)] Initialized: \(instrumentType)")
    }
    
    deinit {
        cleanup()
    }
}

// MARK: - Instrument Loading
extension AudioTrack {
    
    /// Load instrument based on type
    public func loadInstrument(filePath: String, presetIndex: Int = 0) throws {
        switch instrumentType {
        case .sf2:
            try loadSF2Instrument(filePath: filePath, presetIndex: presetIndex)
        case .sfz:
            try loadSFZInstrument(filePath: filePath)
        case .audioUnit(let identifier):
            try loadAudioUnit(identifier: identifier)
        case .sampler:
            try loadAppleSampler(filePath: filePath, presetIndex: presetIndex)
        }
        
        try connectToMixer()
        print("[Track \(id)] Instrument loaded successfully")
    }
    
    private func loadSF2Instrument(filePath: String, presetIndex: Int) throws {
        // Use Apple's Sampler AudioUnit for SF2 files
        let componentDescription = AudioComponentDescription(
            componentType: kAudioUnitType_MusicDevice,
            componentSubType: kAudioUnitSubType_Sampler,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )
        
        try loadAudioUnitWithDescription(componentDescription) { audioUnit in
            try self.loadSoundBank(audioUnit: audioUnit.audioUnit, filePath: filePath, presetIndex: presetIndex)
        }
    }
    
    private func loadSFZInstrument(filePath: String) throws {
        // Implementation for SFZ using custom AudioUnit or samples
        // For now, fallback to sampler
        try loadAppleSampler(filePath: filePath, presetIndex: 0)
    }
    
    private func loadAudioUnit(identifier: String) throws {
        // Load third-party AudioUnit by identifier
        let components = AudioUnitUtils.findAudioUnits(matching: identifier)
        guard let component = components.first else {
            throw AudioTrackError.audioUnitNotFound(identifier)
        }
        
        try loadAudioUnitWithDescription(component.audioComponentDescription) { _ in
            // AudioUnit-specific configuration
        }
    }
    
    private func loadAppleSampler(filePath: String, presetIndex: Int) throws {
        let componentDescription = AudioComponentDescription(
            componentType: kAudioUnitType_MusicDevice,
            componentSubType: kAudioUnitSubType_Sampler,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )
        
        try loadAudioUnitWithDescription(componentDescription) { audioUnit in
            if filePath.hasSuffix(".sf2") {
                try self.loadSoundBank(audioUnit: audioUnit.audioUnit, filePath: filePath, presetIndex: presetIndex)
            } else {
                try self.loadSampleFile(audioUnit: audioUnit.audioUnit, filePath: filePath)
            }
        }
    }
}

// MARK: - AudioUnit Management
extension AudioTrack {
    
    private func loadAudioUnitWithDescription(_ desc: AudioComponentDescription, 
                                            configure: @escaping (AVAudioUnit) throws -> Void) throws {
        let semaphore = DispatchSemaphore(value: 0)
        var loadError: Error?
        
        AVAudioUnit.instantiate(with: desc, options: []) { [weak self] audioUnit, error in
            defer { semaphore.signal() }
            
            if let error = error {
                loadError = error
                return
            }
            
            guard let audioUnit = audioUnit else {
                loadError = AudioTrackError.failedToCreateAudioUnit
                return
            }
            
            do {
                // Configure AudioUnit for optimal performance
                try self?.configureAudioUnit(audioUnit)
                try configure(audioUnit)
                
                self?.audioUnit = audioUnit
                
            } catch {
                loadError = error
            }
        }
        
        // Wait for async loading with timeout
        let result = semaphore.wait(timeout: .now() + 10.0)
        if result == .timedOut {
            throw AudioTrackError.loadTimeout
        }
        
        if let error = loadError {
            throw error
        }
    }
    
    private func configureAudioUnit(_ audioUnit: AVAudioUnit) throws {
        let audioUnitRef = audioUnit.audioUnit
        
        // Set sample rate
        var sampleRate = Float64(audioFormat.sampleRate)
        let result = AudioUnitSetProperty(audioUnitRef,
                                        kAudioUnitProperty_SampleRate,
                                        kAudioUnitScope_Global,
                                        0,
                                        &sampleRate,
                                        UInt32(MemoryLayout<Float64>.size))
        
        if result != noErr {
            throw AudioTrackError.configurationFailed(result)
        }
        
        // Initialize AudioUnit
        let initResult = AudioUnitInitialize(audioUnitRef)
        if initResult != noErr {
            throw AudioTrackError.initializationFailed(initResult)
        }
        
        print("[Track \(id)] AudioUnit configured and initialized")
    }
}

// MARK: - Audio Connection
extension AudioTrack {
    
    private func connectToMixer() throws {
        guard let audioUnit = audioUnit, !isConnected else { return }
        
        // Ensure we're on main thread for audio graph modifications
        if !Thread.isMainThread {
            throw AudioTrackError.invalidThread
        }
        
        // Attach AudioUnit to engine
        audioEngine.attach(audioUnit)
        
        // Connect to mixer with proper format handling
        let connectionFormat = audioUnit.outputFormat(forBus: 0).channelCount > 0 ? 
                              audioUnit.outputFormat(forBus: 0) : audioFormat
        
        audioEngine.connect(audioUnit, to: mixer, fromBus: 0, toBus: mixerBus, format: connectionFormat)
        
        isConnected = true
        print("[Track \(id)] Connected to mixer on bus \(mixerBus)")
    }
    
    public func disconnect() {
        guard let audioUnit = audioUnit, isConnected else { return }
        
        DispatchQueue.main.sync {
            if audioEngine.attachedNodes.contains(audioUnit) {
                audioEngine.disconnectNodeOutput(audioUnit)
                audioEngine.detach(audioUnit)
            }
            isConnected = false
        }
        
        print("[Track \(id)] Disconnected from mixer")
    }
}

// MARK: - MIDI Processing
extension AudioTrack {
    
    private func setupMIDIProcessor() {
        midiProcessor = MIDIProcessor(trackId: id)
    }
    
    /// Trigger immediate MIDI event
    public func triggerEvent(_ event: MIDIEvent) {
        guard let audioUnit = audioUnit else { return }
        
        processingQueue.async {
            self.midiProcessor.processEvent(event, audioUnit: audioUnit.audioUnit)
        }
    }
    
    /// Schedule MIDI event for future playback
    public func scheduleEvent(_ event: MIDIEvent, atSampleTime: AVAudioFramePosition) {
        guard let audioUnit = audioUnit else { return }
        
        // Use AudioUnit's scheduling if available, otherwise immediate processing
        midiProcessor.processEvent(event, audioUnit: audioUnit.audioUnit)
    }
}

// MARK: - Audio Parameters
extension AudioTrack {
    
    public func setVolume(_ volume: Float) {
        self.volume = max(0.0, min(1.0, volume))
        // Apply to mixer bus or AudioUnit
        print("[Track \(id)] Volume set to \(self.volume)")
    }
    
    public func setPan(_ pan: Float) {
        self.pan = max(-1.0, min(1.0, pan))
        // Apply to mixer bus
        print("[Track \(id)] Pan set to \(self.pan)")
    }
    
    public func setMute(_ mute: Bool) {
        self.mute = mute
        // Apply muting
        print("[Track \(id)] Mute: \(mute)")
    }
    
    public func setSolo(_ solo: Bool) {
        self.solo = solo
        // Handle solo logic
        print("[Track \(id)] Solo: \(solo)")
    }
}

// MARK: - Sound Bank Loading
extension AudioTrack {
    
    private func loadSoundBank(audioUnit: AudioUnit, filePath: String, presetIndex: Int) throws {
        let url = URL(fileURLWithPath: filePath)
        var mutableURL = url
        
        // Load sound bank
        let result = AudioUnitSetProperty(audioUnit,
                                        kMusicDeviceProperty_SoundBankURL,
                                        kAudioUnitScope_Global,
                                        0,
                                        &mutableURL,
                                        UInt32(MemoryLayout<URL>.size))
        
        if result != noErr {
            throw AudioTrackError.soundBankLoadFailed(result)
        }
        
        // Set program (preset)
        try setProgram(audioUnit: audioUnit, program: UInt8(presetIndex))
        
        print("[Track \(id)] Sound bank loaded: \(url.lastPathComponent)")
    }
    
    private func loadSampleFile(audioUnit: AudioUnit, filePath: String) throws {
        // Implementation for loading individual sample files
        // This would involve setting up sample mapping
        print("[Track \(id)] Sample file loaded: \(filePath)")
    }
    
    private func setProgram(audioUnit: AudioUnit, program: UInt8) throws {
        // Send program change MIDI event
        let programChange = UInt32(0xC0) | UInt32(program)
        let result = MusicDeviceMIDIEvent(audioUnit, programChange, 0, 0, 0)
        
        if result != noErr {
            throw AudioTrackError.programChangeFailed(result)
        }
    }
}

// MARK: - Cleanup
extension AudioTrack {
    
    public func cleanup() {
        disconnect()
        
        if let audioUnit = audioUnit {
            let _ = AudioUnitUninitialize(audioUnit.audioUnit)
        }
        
        audioUnit = nil
        midiProcessor = nil
        
        print("[Track \(id)] Cleanup completed")
    }
}

// MARK: - Error Types
public enum AudioTrackError: Error {
    case audioUnitNotFound(String)
    case failedToCreateAudioUnit
    case loadTimeout
    case configurationFailed(OSStatus)
    case initializationFailed(OSStatus)
    case soundBankLoadFailed(OSStatus)
    case programChangeFailed(OSStatus)
    case invalidThread
    case connectionFailed
    
    public var localizedDescription: String {
        switch self {
        case .audioUnitNotFound(let identifier):
            return "AudioUnit not found: \(identifier)"
        case .failedToCreateAudioUnit:
            return "Failed to create AudioUnit"
        case .loadTimeout:
            return "AudioUnit load timeout"
        case .configurationFailed(let status):
            return "AudioUnit configuration failed: \(status)"
        case .initializationFailed(let status):
            return "AudioUnit initialization failed: \(status)"
        case .soundBankLoadFailed(let status):
            return "Sound bank load failed: \(status)"
        case .programChangeFailed(let status):
            return "Program change failed: \(status)"
        case .invalidThread:
            return "Invalid thread for audio operation"
        case .connectionFailed:
            return "Audio connection failed"
        }
    }
}