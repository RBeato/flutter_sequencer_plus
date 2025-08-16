import Foundation
import AVFoundation
import AudioToolbox

/// Professional AudioUnit utilities for high-performance audio processing
/// Optimized for real-time operation and minimal latency
public class AudioUnitUtils {
    
    // MARK: - AudioUnit Discovery
    
    /// Find AudioUnits matching specific criteria
    public static func findAudioUnits(matching identifier: String) -> [AVAudioUnitComponent] {
        var componentDescription = AudioComponentDescription()
        
        // Parse identifier to determine component type
        if identifier.contains("sampler") {
            componentDescription.componentType = kAudioUnitType_MusicDevice
            componentDescription.componentSubType = kAudioUnitSubType_Sampler
            componentDescription.componentManufacturer = kAudioUnitManufacturer_Apple
        } else if identifier.contains("synth") {
            componentDescription.componentType = kAudioUnitType_MusicDevice
            componentDescription.componentSubType = kAudioUnitSubType_MIDISynth
            componentDescription.componentManufacturer = kAudioUnitManufacturer_Apple
        } else {
            // Try to find by exact identifier
            return AVAudioUnitComponentManager.shared().components { (desc, _) in
                return desc.name.contains(identifier) || desc.typeName.contains(identifier)
            }
        }
        
        componentDescription.componentFlags = 0
        componentDescription.componentFlagsMask = 0
        
        return AVAudioUnitComponentManager.shared().components(matching: componentDescription)
    }
    
    /// Get all available music device AudioUnits
    public static func getAllMusicDevices() -> [AVAudioUnitComponent] {
        var componentDescription = AudioComponentDescription()
        componentDescription.componentType = kAudioUnitType_MusicDevice
        componentDescription.componentSubType = 0
        componentDescription.componentManufacturer = 0
        componentDescription.componentFlags = 0
        componentDescription.componentFlagsMask = 0
        
        return AVAudioUnitComponentManager.shared().components(matching: componentDescription)
    }
    
    /// Check if Apple Sampler is available
    public static func isAppleSamplerAvailable() -> Bool {
        let samplerComponents = findAudioUnits(matching: "sampler")
        return !samplerComponents.isEmpty
    }
}

// MARK: - AudioUnit Configuration
extension AudioUnitUtils {
    
    /// Configure AudioUnit for optimal performance
    public static func configureForOptimalPerformance(_ audioUnit: AudioUnit, sampleRate: Double) throws {
        var result: OSStatus
        
        // Set sample rate
        var sampleRateValue = Float64(sampleRate)
        result = AudioUnitSetProperty(audioUnit,
                                    kAudioUnitProperty_SampleRate,
                                    kAudioUnitScope_Global,
                                    0,
                                    &sampleRateValue,
                                    UInt32(MemoryLayout<Float64>.size))
        if result != noErr {
            throw AudioUnitError.configurationFailed(result)
        }
        
        // Set maximum frames per slice for low latency
        var maxFrames: UInt32 = 256
        result = AudioUnitSetProperty(audioUnit,
                                    kAudioUnitProperty_MaximumFramesPerSlice,
                                    kAudioUnitScope_Global,
                                    0,
                                    &maxFrames,
                                    UInt32(MemoryLayout<UInt32>.size))
        if result != noErr {
            throw AudioUnitError.configurationFailed(result)
        }
        
        // Enable high-quality processing  
        var renderQuality: UInt32 = 127 // Max quality value
        result = AudioUnitSetProperty(audioUnit,
                                    kAudioUnitProperty_RenderQuality,
                                    kAudioUnitScope_Global,
                                    0,
                                    &renderQuality,
                                    UInt32(MemoryLayout<UInt32>.size))
        // Note: Not all AudioUnits support this property, so we don't throw on error
        
        print("[AudioUnitUtils] AudioUnit configured for optimal performance")
    }
    
    /// Set AudioUnit stream format
    public static func setStreamFormat(_ audioUnit: AudioUnit, format: AudioStreamBasicDescription, scope: AudioUnitScope) throws {
        var mutableFormat = format
        let result = AudioUnitSetProperty(audioUnit,
                                        kAudioUnitProperty_StreamFormat,
                                        scope,
                                        0,
                                        &mutableFormat,
                                        UInt32(MemoryLayout<AudioStreamBasicDescription>.size))
        if result != noErr {
            throw AudioUnitError.configurationFailed(result)
        }
    }
}

// MARK: - SoundFont Management
extension AudioUnitUtils {
    
    /// Load SoundFont into AudioUnit with advanced error handling
    public static func loadSoundFont(audioUnit: AudioUnit, url: URL, presetIndex: Int = 0) throws {
        var mutableURL = url
        
        // Verify file exists
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw AudioUnitError.fileNotFound(url.path)
        }
        
        // Get file size for memory management
        let fileAttributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let fileSize = fileAttributes[.size] as? Int64 ?? 0
        let sizeInMB = Double(fileSize) / (1024 * 1024)
        
        print("[AudioUnitUtils] Loading SoundFont: \(url.lastPathComponent) (\(String(format: "%.1f", sizeInMB)) MB)")
        
        // Load with memory optimization for large files
        if sizeInMB > 50 {
            try optimizeForLargeSoundFont(audioUnit: audioUnit)
        }
        
        // Load SoundFont
        let result = AudioUnitSetProperty(audioUnit,
                                        kMusicDeviceProperty_SoundBankURL,
                                        kAudioUnitScope_Global,
                                        0,
                                        &mutableURL,
                                        UInt32(MemoryLayout<URL>.size))
        
        if result != noErr {
            throw AudioUnitError.soundFontLoadFailed(result)
        }
        
        // Set initial program
        try setProgram(audioUnit: audioUnit, program: UInt8(presetIndex))
        
        print("[AudioUnitUtils] SoundFont loaded successfully")
    }
    
    private static func optimizeForLargeSoundFont(audioUnit: AudioUnit) throws {
        // Disable preload for large files
        var preload: UInt32 = 0
        let result = AudioUnitSetProperty(audioUnit,
                                        kAUMIDISynthProperty_EnablePreload,
                                        kAudioUnitScope_Global,
                                        0,
                                        &preload,
                                        UInt32(MemoryLayout<UInt32>.size))
        
        // Set conservative polyphony
        var polyphony: UInt32 = 16
        let polyphonyResult = AudioUnitSetProperty(audioUnit,
                                                 2012, // kMusicDeviceProperty_MaxPolyphony
                                                 kAudioUnitScope_Global,
                                                 0,
                                                 &polyphony,
                                                 UInt32(MemoryLayout<UInt32>.size))
        
        print("[AudioUnitUtils] Optimized for large SoundFont")
    }
    
    /// Set program (preset) on AudioUnit
    public static func setProgram(audioUnit: AudioUnit, program: UInt8, channel: UInt8 = 0) throws {
        let command = UInt32(0xC0 | channel) // Program Change
        let result = MusicDeviceMIDIEvent(audioUnit, command, UInt32(program), 0, 0)
        
        if result != noErr {
            throw AudioUnitError.programChangeFailed(result)
        }
    }
}

// MARK: - MIDI Utilities
extension AudioUnitUtils {
    
    /// Send MIDI event to AudioUnit with error handling
    public static func sendMIDIEvent(audioUnit: AudioUnit, event: MIDIEvent) throws {
        let command = UInt32(event.type.rawValue | event.channel)
        let result = MusicDeviceMIDIEvent(audioUnit,
                                        command,
                                        UInt32(event.data1),
                                        UInt32(event.data2),
                                        UInt32(event.timestamp))
        
        if result != noErr {
            throw AudioUnitError.midiEventFailed(result)
        }
    }
    
    /// Send All Notes Off to AudioUnit
    public static func sendAllNotesOff(audioUnit: AudioUnit, channel: UInt8 = 0) {
        let allNotesOff = MIDIEvent(type: .controlChange, channel: channel, data1: 123, data2: 0)
        try? sendMIDIEvent(audioUnit: audioUnit, event: allNotesOff)
    }
    
    /// Send All Sound Off to AudioUnit
    public static func sendAllSoundOff(audioUnit: AudioUnit, channel: UInt8 = 0) {
        let allSoundOff = MIDIEvent(type: .controlChange, channel: channel, data1: 120, data2: 0)
        try? sendMIDIEvent(audioUnit: audioUnit, event: allSoundOff)
    }
}

// MARK: - Performance Utilities
extension AudioUnitUtils {
    
    /// Get AudioUnit latency
    public static func getLatency(audioUnit: AudioUnit) -> Double {
        var latency: Float64 = 0
        var size = UInt32(MemoryLayout<Float64>.size)
        
        let result = AudioUnitGetProperty(audioUnit,
                                        kAudioUnitProperty_Latency,
                                        kAudioUnitScope_Global,
                                        0,
                                        &latency,
                                        &size)
        
        return result == noErr ? latency : 0.0
    }
    
    /// Get AudioUnit CPU usage
    public static func getCPUUsage(audioUnit: AudioUnit) -> Double {
        var cpuUsage: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        
        let result = AudioUnitGetProperty(audioUnit,
                                        kAudioUnitProperty_CPULoad,
                                        kAudioUnitScope_Global,
                                        0,
                                        &cpuUsage,
                                        &size)
        
        return result == noErr ? Double(cpuUsage) : 0.0
    }
}

// MARK: - Error Types
public enum AudioUnitError: Error {
    case configurationFailed(OSStatus)
    case fileNotFound(String)
    case soundFontLoadFailed(OSStatus)
    case programChangeFailed(OSStatus)
    case midiEventFailed(OSStatus)
    case initializationFailed(OSStatus)
    
    public var localizedDescription: String {
        switch self {
        case .configurationFailed(let status):
            return "AudioUnit configuration failed: \(status)"
        case .fileNotFound(let path):
            return "File not found: \(path)"
        case .soundFontLoadFailed(let status):
            return "SoundFont load failed: \(status)"
        case .programChangeFailed(let status):
            return "Program change failed: \(status)"
        case .midiEventFailed(let status):
            return "MIDI event failed: \(status)"
        case .initializationFailed(let status):
            return "AudioUnit initialization failed: \(status)"
        }
    }
}

// MARK: - Legacy Compatibility
extension AudioUnitUtils {
    
    /// Filter closure for blacklisted AudioUnits
    static let filterClosure: (AVAudioUnitComponent) -> Bool = {
        let blacklist = ["AUNewPitch", "AURoundTripAAC", "AUNetSend"]
        return !blacklist.contains($0.name)
    }
    
    /// Get AudioUnit ID in legacy format
    public static func getAudioUnitId(_ component: AVAudioUnitComponent) -> String {
        return "\(component.manufacturerName).\(component.name)"
    }
    
    /// Load AudioUnits with completion handler
    public static func loadAudioUnits(completion: @escaping ([AVAudioUnitComponent]) -> Void) {
        DispatchQueue.global(qos: .default).async {
            let allComponentsDescription = AudioComponentDescription(
                componentType: kAudioUnitType_MusicDevice,
                componentSubType: 0,
                componentManufacturer: 0,
                componentFlags: 0,
                componentFlagsMask: 0
            )

            let components = AVAudioUnitComponentManager.shared()
                .components(matching: allComponentsDescription)
                .filter(self.filterClosure)

            DispatchQueue.main.async {
                completion(components)
            }
        }
    }
    
    /// Instantiate AudioUnit with completion handler (legacy compatibility)
    public static func instantiate(
        description: AudioComponentDescription,
        sampleRate: Double,
        options: AudioComponentInstantiationOptions,
        completion: @escaping (AVAudioUnit?) -> Void
    ) {
        AVAudioUnit.instantiate(with: description, options: options) { (avAudioUnit, error) in
            if let error = error {
                print("[AudioUnitUtils] Failed to instantiate AudioUnit: \(error)")
                completion(nil)
            } else {
                completion(avAudioUnit)
            }
        }
    }
}

// MARK: - AudioUnit Information
public struct AudioUnitInfo {
    let name: String
    let manufacturer: String
    let type: String
    let subtype: String
    let version: String
    let componentDescription: AudioComponentDescription
    
    public init(component: AVAudioUnitComponent) {
        self.name = component.name
        self.manufacturer = component.manufacturerName
        self.type = component.typeName
        self.subtype = component.localizedTypeName
        self.version = "1.0.0" // Static version since versionNumber is not available
        self.componentDescription = component.audioComponentDescription
    }
}