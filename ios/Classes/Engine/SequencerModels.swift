import Foundation
import AVFoundation

/// Core data models for the professional sequencer engine

// MARK: - MIDI Event Types

/// MIDI event type enumeration
public enum MIDIEventType: UInt8 {
    case noteOff = 0x80
    case noteOn = 0x90
    case polyphonicKeyPressure = 0xA0
    case controlChange = 0xB0
    case programChange = 0xC0
    case channelPressure = 0xD0
    case pitchBend = 0xE0
    case systemExclusive = 0xF0
}

/// High-performance MIDI event structure
public struct MIDIEvent {
    public let type: MIDIEventType
    public let channel: UInt8
    public let data1: UInt8
    public let data2: UInt8
    public let timestamp: UInt64
    
    public init(type: MIDIEventType, channel: UInt8, data1: UInt8, data2: UInt8, timestamp: UInt64 = 0) {
        self.type = type
        self.channel = channel
        self.data1 = data1
        self.data2 = data2
        self.timestamp = timestamp
    }
}

// MARK: - Instrument Types

/// Supported instrument types
public enum InstrumentType {
    case sf2(soundFont: String)
    case sfz(sample: String)
    case audioUnit(identifier: String)
    case sampler
}

// MARK: - Track Configuration

/// Audio track configuration
public struct TrackConfiguration {
    public let instrumentType: InstrumentType
    public let filePath: String
    public let presetIndex: Int
    public let volume: Float
    public let pan: Float
    public let isMuted: Bool
    public let isSolo: Bool
    
    public init(
        instrumentType: InstrumentType,
        filePath: String,
        presetIndex: Int = 0,
        volume: Float = 1.0,
        pan: Float = 0.0,
        isMuted: Bool = false,
        isSolo: Bool = false
    ) {
        self.instrumentType = instrumentType
        self.filePath = filePath
        self.presetIndex = presetIndex
        self.volume = volume
        self.pan = pan
        self.isMuted = isMuted
        self.isSolo = isSolo
    }
}

// MARK: - Sequencer Events

/// Sequencer event for lock-free event processing
public struct SequencerEvent {
    public let trackId: Int
    public let midiEvent: MIDIEvent
    public let beat: Double
    public let sampleTime: AVAudioFramePosition
    public let timestamp: UInt64
    
    public init(trackId: Int, midiEvent: MIDIEvent, beat: Double, sampleTime: AVAudioFramePosition = 0, timestamp: UInt64 = 0) {
        self.trackId = trackId
        self.midiEvent = midiEvent
        self.beat = beat
        self.sampleTime = sampleTime
        self.timestamp = timestamp
    }
}

// MARK: - Performance Metrics

/// Engine performance metrics
public struct EngineMetrics {
    public let cpuUsage: Double
    public let memoryUsage: Double
    public let audioLatency: Double
    public let droppedFrames: Int
    public let renderTime: Double
    
    public init(
        cpuUsage: Double = 0.0,
        memoryUsage: Double = 0.0,
        audioLatency: Double = 0.0,
        droppedFrames: Int = 0,
        renderTime: Double = 0.0
    ) {
        self.cpuUsage = cpuUsage
        self.memoryUsage = memoryUsage
        self.audioLatency = audioLatency
        self.droppedFrames = droppedFrames
        self.renderTime = renderTime
    }
}

// MARK: - Audio Format Utilities

/// Standard audio format for the sequencer
public struct SequencerAudioFormat {
    public static let standardFormat = AVAudioFormat(
        standardFormatWithSampleRate: 44100.0,
        channels: 2
    )!
    
    public static let bufferFrameCapacity: AVAudioFrameCount = 256
    
    public static func createAudioBuffer() -> AVAudioPCMBuffer {
        return AVAudioPCMBuffer(pcmFormat: standardFormat, frameCapacity: bufferFrameCapacity)!
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let midiEventProcessed = Notification.Name("MIDIEventProcessed")
    static let sequencerPositionChanged = Notification.Name("SequencerPositionChanged")
    static let trackAdded = Notification.Name("TrackAdded")
    static let trackRemoved = Notification.Name("TrackRemoved")
    static let engineStarted = Notification.Name("EngineStarted")
    static let engineStopped = Notification.Name("EngineStopped")
}

// MARK: - Error Types

/// Sequencer-specific errors
public enum SequencerError: Error {
    case engineNotInitialized
    case trackNotFound(Int)
    case invalidAudioFormat
    case audioSessionError(Error)
    case instrumentLoadError(String)
    case bufferUnderrun
    case midiProcessingError(String)
    
    public var localizedDescription: String {
        switch self {
        case .engineNotInitialized:
            return "Audio engine not initialized"
        case .trackNotFound(let id):
            return "Track not found: \(id)"
        case .invalidAudioFormat:
            return "Invalid audio format"
        case .audioSessionError(let error):
            return "Audio session error: \(error.localizedDescription)"
        case .instrumentLoadError(let message):
            return "Instrument load error: \(message)"
        case .bufferUnderrun:
            return "Audio buffer underrun"
        case .midiProcessingError(let message):
            return "MIDI processing error: \(message)"
        }
    }
}

// MARK: - Track State

/// Audio track state
public enum TrackState {
    case idle
    case loading
    case ready
    case playing
    case error(Error)
}

/// Track information
public struct TrackInfo {
    public let id: Int
    public let name: String
    public let instrumentType: InstrumentType
    public let state: TrackState
    public let configuration: TrackConfiguration
    
    public init(
        id: Int,
        name: String,
        instrumentType: InstrumentType,
        state: TrackState,
        configuration: TrackConfiguration
    ) {
        self.id = id
        self.name = name
        self.instrumentType = instrumentType
        self.state = state
        self.configuration = configuration
    }
}

// MARK: - Sequencer State

/// Overall sequencer state
public enum SequencerState {
    case stopped
    case playing
    case paused
    case recording
}

/// Sequencer information
public struct SequencerInfo {
    public let state: SequencerState
    public let currentBeat: Double
    public let tempo: Double
    public let trackCount: Int
    public let isLooping: Bool
    
    public init(
        state: SequencerState,
        currentBeat: Double,
        tempo: Double,
        trackCount: Int,
        isLooping: Bool
    ) {
        self.state = state
        self.currentBeat = currentBeat
        self.tempo = tempo
        self.trackCount = trackCount
        self.isLooping = isLooping
    }
}