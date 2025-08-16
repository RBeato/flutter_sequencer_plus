import Foundation
import AudioToolbox

/// High-performance MIDI processor for real-time event processing
/// Optimized for minimal latency and maximum throughput
public class MIDIProcessor {
    
    // MARK: - Core Properties
    public let trackId: Int
    
    // MARK: - MIDI State
    private var activeNotes: Set<UInt8> = []
    private var controllerValues: [UInt8: UInt8] = [:]
    private var currentProgram: UInt8 = 0
    private var pitchBendValue: UInt16 = 8192 // Center position
    
    // MARK: - Performance Optimization
    private let processingQueue = DispatchQueue(label: "com.sequencer.midi.processor", qos: .userInteractive)
    
    // MARK: - Statistics
    private var eventsProcessed: UInt64 = 0
    private var lastProcessTime: UInt64 = 0
    
    public init(trackId: Int) {
        self.trackId = trackId
        initializeControllers()
        print("[MIDIProcessor] Initialized for track \(trackId)")
    }
    
    deinit {
        // Send note-offs for any active notes
        cleanup()
    }
}

// MARK: - Initialization
extension MIDIProcessor {
    
    private func initializeControllers() {
        // Initialize common MIDI controllers to default values
        controllerValues[1] = 0      // Modulation
        controllerValues[7] = 100    // Channel Volume
        controllerValues[10] = 64    // Pan
        controllerValues[11] = 127   // Expression
        controllerValues[64] = 0     // Sustain Pedal
        controllerValues[91] = 0     // Reverb Send
        controllerValues[93] = 0     // Chorus Send
    }
}

// MARK: - Event Processing
extension MIDIProcessor {
    
    /// Process MIDI event with optimal performance
    public func processEvent(_ event: MIDIEvent, audioUnit: AudioUnit) {
        let startTime = mach_absolute_time()
        
        // Fast path for most common events
        switch event.type {
        case .noteOn:
            processNoteOn(event, audioUnit: audioUnit)
        case .noteOff:
            processNoteOff(event, audioUnit: audioUnit)
        case .controlChange:
            processControlChange(event, audioUnit: audioUnit)
        case .programChange:
            processProgramChange(event, audioUnit: audioUnit)
        case .pitchBend:
            processPitchBend(event, audioUnit: audioUnit)
        case .polyphonicKeyPressure, .channelPressure, .systemExclusive:
            // Handle other MIDI event types as needed
            break
        }
        
        // Update statistics
        eventsProcessed += 1
        lastProcessTime = mach_absolute_time() - startTime
    }
    
    /// Process multiple events efficiently
    public func processEvents(_ events: [MIDIEvent], audioUnit: AudioUnit) {
        for event in events {
            processEvent(event, audioUnit: audioUnit)
        }
    }
}

// MARK: - MIDI Event Handlers
extension MIDIProcessor {
    
    private func processNoteOn(_ event: MIDIEvent, audioUnit: AudioUnit) {
        let noteNumber = event.data1
        let velocity = event.data2
        
        // Handle velocity 0 as note off (MIDI standard)
        if velocity == 0 {
            processNoteOff(event, audioUnit: audioUnit)
            return
        }
        
        // Track active notes
        activeNotes.insert(noteNumber)
        
        // Send MIDI event to AudioUnit
        let midiCommand = UInt32(event.type.rawValue | event.channel)
        let result = MusicDeviceMIDIEvent(audioUnit, midiCommand, UInt32(noteNumber), UInt32(velocity), UInt32(event.timestamp))
        
        if result != noErr {
            print("[MIDIProcessor] Note ON failed: \(result)")
        }
    }
    
    private func processNoteOff(_ event: MIDIEvent, audioUnit: AudioUnit) {
        let noteNumber = event.data1
        let velocity = event.data2
        
        // Remove from active notes
        activeNotes.remove(noteNumber)
        
        // Send MIDI event to AudioUnit
        let midiCommand = UInt32(event.type.rawValue | event.channel)
        let result = MusicDeviceMIDIEvent(audioUnit, midiCommand, UInt32(noteNumber), UInt32(velocity), UInt32(event.timestamp))
        
        if result != noErr {
            print("[MIDIProcessor] Note OFF failed: \(result)")
        }
    }
    
    private func processControlChange(_ event: MIDIEvent, audioUnit: AudioUnit) {
        let controller = event.data1
        let value = event.data2
        
        // Update internal state
        controllerValues[controller] = value
        
        // Handle special controllers
        switch controller {
        case 64: // Sustain Pedal
            handleSustainPedal(value: value, audioUnit: audioUnit)
        case 120: // All Sound Off
            handleAllSoundOff(audioUnit: audioUnit)
        case 121: // Reset All Controllers
            handleResetAllControllers(audioUnit: audioUnit)
        case 123: // All Notes Off
            handleAllNotesOff(audioUnit: audioUnit)
        default:
            // Standard controller
            break
        }
        
        // Send MIDI event to AudioUnit
        let midiCommand = UInt32(event.type.rawValue | event.channel)
        let result = MusicDeviceMIDIEvent(audioUnit, midiCommand, UInt32(controller), UInt32(value), UInt32(event.timestamp))
        
        if result != noErr {
            print("[MIDIProcessor] CC failed: \(result)")
        }
    }
    
    private func processProgramChange(_ event: MIDIEvent, audioUnit: AudioUnit) {
        let program = event.data1
        currentProgram = program
        
        // Send MIDI event to AudioUnit
        let midiCommand = UInt32(event.type.rawValue | event.channel)
        let result = MusicDeviceMIDIEvent(audioUnit, midiCommand, UInt32(program), 0, UInt32(event.timestamp))
        
        if result != noErr {
            print("[MIDIProcessor] Program Change failed: \(result)")
        }
    }
    
    private func processPitchBend(_ event: MIDIEvent, audioUnit: AudioUnit) {
        // Pitch bend uses 14-bit value (data1 = LSB, data2 = MSB)
        let lsb = UInt16(event.data1)
        let msb = UInt16(event.data2)
        let pitchBend = (msb << 7) | lsb
        
        pitchBendValue = pitchBend
        
        // Send MIDI event to AudioUnit
        let midiCommand = UInt32(event.type.rawValue | event.channel)
        let result = MusicDeviceMIDIEvent(audioUnit, midiCommand, UInt32(lsb), UInt32(msb), UInt32(event.timestamp))
        
        if result != noErr {
            print("[MIDIProcessor] Pitch Bend failed: \(result)")
        }
    }
}

// MARK: - Special MIDI Handlers
extension MIDIProcessor {
    
    private func handleSustainPedal(value: UInt8, audioUnit: AudioUnit) {
        // Sustain pedal logic is handled by the AudioUnit
        // This is just for state tracking
    }
    
    private func handleAllSoundOff(audioUnit: AudioUnit) {
        // Immediately stop all sound
        activeNotes.removeAll()
    }
    
    private func handleResetAllControllers(audioUnit: AudioUnit) {
        // Reset controllers to default values
        initializeControllers()
        pitchBendValue = 8192
    }
    
    private func handleAllNotesOff(audioUnit: AudioUnit) {
        // Send note-off for all active notes
        for noteNumber in activeNotes {
            let noteOffEvent = MIDIEvent(
                type: .noteOff,
                channel: 0, // Use channel from current context
                data1: noteNumber,
                data2: 0
            )
            processNoteOff(noteOffEvent, audioUnit: audioUnit)
        }
        activeNotes.removeAll()
    }
}

// MARK: - State Management
extension MIDIProcessor {
    
    /// Get current active notes
    public var currentActiveNotes: Set<UInt8> {
        return activeNotes
    }
    
    /// Get controller value
    public func getControllerValue(_ controller: UInt8) -> UInt8? {
        return controllerValues[controller]
    }
    
    /// Get current program
    public var currentProgramNumber: UInt8 {
        return currentProgram
    }
    
    /// Get current pitch bend value
    public var currentPitchBend: UInt16 {
        return pitchBendValue
    }
    
    /// Check if note is currently active
    public func isNoteActive(_ noteNumber: UInt8) -> Bool {
        return activeNotes.contains(noteNumber)
    }
}

// MARK: - Performance Monitoring
extension MIDIProcessor {
    
    public struct ProcessorMetrics {
        let eventsProcessed: UInt64
        let lastProcessTimeNanoseconds: UInt64
        let activeNoteCount: Int
    }
    
    public var metrics: ProcessorMetrics {
        return ProcessorMetrics(
            eventsProcessed: eventsProcessed,
            lastProcessTimeNanoseconds: lastProcessTime,
            activeNoteCount: activeNotes.count
        )
    }
}

// MARK: - Cleanup
extension MIDIProcessor {
    
    public func cleanup() {
        // This would send note-offs for active notes if AudioUnit is still available
        activeNotes.removeAll()
        controllerValues.removeAll()
        
        print("[MIDIProcessor] Cleanup completed for track \(trackId)")
    }
    
    /// Panic - stop all sound immediately
    public func panic(audioUnit: AudioUnit) {
        handleAllSoundOff(audioUnit: audioUnit)
        handleAllNotesOff(audioUnit: audioUnit)
        
        // Send additional reset messages
        for channel in 0..<16 {
            // All Sound Off
            let allSoundOff = MIDIEvent(type: .controlChange, channel: UInt8(channel), data1: 120, data2: 0)
            processControlChange(allSoundOff, audioUnit: audioUnit)
            
            // All Notes Off
            let allNotesOff = MIDIEvent(type: .controlChange, channel: UInt8(channel), data1: 123, data2: 0)
            processControlChange(allNotesOff, audioUnit: audioUnit)
            
            // Reset All Controllers
            let resetControllers = MIDIEvent(type: .controlChange, channel: UInt8(channel), data1: 121, data2: 0)
            processControlChange(resetControllers, audioUnit: audioUnit)
        }
        
        print("[MIDIProcessor] Panic executed for track \(trackId)")
    }
}