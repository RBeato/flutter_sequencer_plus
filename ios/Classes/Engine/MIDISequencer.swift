import Foundation
import AVFoundation
import AudioToolbox

/// High-performance MIDI sequencer with sample-accurate timing
/// Lock-free design for real-time audio processing
public class MIDISequencer {
    
    // MARK: - Core Properties
    private let audioFormat: AVAudioFormat
    private let sampleRate: Double
    private let bufferSize: Int
    
    // MARK: - Sequencing State
    private var isPlaying = false
    private var isPaused = false
    private var currentTempo: Double = 120.0
    private var ticksPerQuarter: Int = 96
    
    // MARK: - Event Management
    private var eventScheduler: EventScheduler!
    private var eventBuffer: LockFreeEventBuffer!
    
    // MARK: - Timing
    private var samplePosition: AVAudioFramePosition = 0
    private var lastRenderTime: UInt64 = 0
    
    // MARK: - Track Management
    private var trackEvents: [Int: [SequencerEvent]] = [:]
    private let trackQueue = DispatchQueue(label: "com.sequencer.midi", qos: .userInteractive)
    
    // MARK: - Performance
    private var renderCallback: AURenderCallback?
    private let callbackQueue = DispatchQueue(label: "com.sequencer.render", qos: .userInteractive)
    
    // MARK: - Initialization
    public init(audioFormat: AVAudioFormat, sampleRate: Double) {
        self.audioFormat = audioFormat
        self.sampleRate = sampleRate
        self.bufferSize = Int(audioFormat.commonFormat == .pcmFormatFloat32 ? 256 : 512)
        
        setupEventScheduler()
        setupEventBuffer()
        setupRenderCallback()
        
        print("[MIDISequencer] Initialized: \(sampleRate)Hz, buffer: \(bufferSize)")
    }
    
    deinit {
        stop()
        cleanup()
    }
}

// MARK: - Setup
extension MIDISequencer {
    
    private func setupEventScheduler() {
        eventScheduler = EventScheduler(
            sampleRate: sampleRate,
            bufferSize: bufferSize,
            ticksPerQuarter: ticksPerQuarter
        )
    }
    
    private func setupEventBuffer() {
        eventBuffer = LockFreeEventBuffer(capacity: 8192) // Large buffer for complex sequences
    }
    
    private func setupRenderCallback() {
        // Note: For now we'll handle timing through the event scheduler
        // instead of direct render callbacks due to C function pointer limitations
        print("[MIDISequencer] Render callback setup deferred to event scheduler")
    }
}

// MARK: - Transport Control
extension MIDISequencer {
    
    /// Start sequencer playback
    public func start() throws {
        guard !isPlaying else { return }
        
        // Reset timing
        samplePosition = 0
        lastRenderTime = mach_absolute_time()
        
        // Start event processing
        eventScheduler.start()
        
        isPlaying = true
        isPaused = false
        
        print("[MIDISequencer] Started at tempo \(currentTempo) BPM")
    }
    
    /// Pause sequencer playback
    public func pause() {
        guard isPlaying && !isPaused else { return }
        
        isPaused = true
        eventScheduler.pause()
        
        print("[MIDISequencer] Paused")
    }
    
    /// Resume sequencer playback
    public func resume() {
        guard isPlaying && isPaused else { return }
        
        isPaused = false
        eventScheduler.resume()
        
        print("[MIDISequencer] Resumed")
    }
    
    /// Stop sequencer playback
    public func stop() {
        guard isPlaying else { return }
        
        isPlaying = false
        isPaused = false
        
        eventScheduler.stop()
        
        // Send all notes off to all tracks
        sendAllNotesOff()
    }
    
    /// Play the sequencer (alias for start)
    public func play() {
        do {
            try start()
        } catch {
            print("[MIDISequencer] Failed to start: \(error)")
        }
    }
    
    /// Set playback tempo
    public func setTempo(_ bpm: Double) {
        currentTempo = max(1.0, min(300.0, bpm))
        eventScheduler.setTempo(currentTempo)
        
        print("[MIDISequencer] Tempo set to \(currentTempo) BPM")
    }
}

// MARK: - Event Scheduling
extension MIDISequencer {
    
    /// Schedule a MIDI event at a specific beat
    public func scheduleEvent(event: MIDIEvent, trackId: Int, atBeat: Double) {
        let sampleTime = beatToSamples(atBeat)
        let sequencerEvent = SequencerEvent(
            trackId: trackId,
            midiEvent: event,
            beat: atBeat,
            sampleTime: sampleTime
        )
        
        trackQueue.async {
            self.eventBuffer.write(sequencerEvent)
        }
    }
    
    /// Schedule multiple events
    public func scheduleEvents(_ events: [(MIDIEvent, Int, Double)]) {
        trackQueue.async {
            for (event, trackId, beat) in events {
                let sampleTime = self.beatToSamples(beat)
                let sequencerEvent = SequencerEvent(
                    trackId: trackId,
                    midiEvent: event,
                    beat: beat,
                    sampleTime: sampleTime
                )
                self.eventBuffer.write(sequencerEvent)
            }
        }
    }
    
    /// Clear all scheduled events
    public func clearEvents(forTrack trackId: Int? = nil) {
        trackQueue.async {
            if let trackId = trackId {
                self.eventBuffer.clearEvents(forTrack: trackId)
            } else {
                self.eventBuffer.clear()
            }
        }
    }
}

// MARK: - Real-time Rendering
extension MIDISequencer {
    
    private func renderAudio(frames: UInt32, timestamp: UnsafePointer<AudioTimeStamp>?) -> OSStatus {
        guard isPlaying && !isPaused else { return noErr }
        
        let frameCount = Int(frames)
        let currentTime = mach_absolute_time()
        
        // Process events for this render cycle
        processEventsForBuffer(frameCount: frameCount, currentTime: currentTime)
        
        // Update position
        samplePosition += AVAudioFramePosition(frameCount)
        lastRenderTime = currentTime
        
        return noErr
    }
    
    private func processEventsForBuffer(frameCount: Int, currentTime: UInt64) {
        let bufferStartSample = samplePosition
        let bufferEndSample = bufferStartSample + AVAudioFramePosition(frameCount)
        
        // Read events that should be processed in this buffer
        var eventsToProcess: [SequencerEvent] = []
        
        while let event = eventBuffer.read() {
            if event.sampleTime >= bufferStartSample && event.sampleTime < bufferEndSample {
                eventsToProcess.append(event)
            } else if event.sampleTime >= bufferEndSample {
                // Put back event for next buffer
                eventBuffer.write(event)
                break
            }
            // Skip events that are too late (already passed)
        }
        
        // Sort events by sample time for precise timing
        eventsToProcess.sort { $0.sampleTime < $1.sampleTime }
        
        // Process events
        for event in eventsToProcess {
            let sampleOffset = Int(event.sampleTime - bufferStartSample)
            processEvent(event, sampleOffset: sampleOffset)
        }
    }
    
    private func processEvent(_ event: SequencerEvent, sampleOffset: Int) {
        // Notify delegates about event processing
        NotificationCenter.default.post(
            name: .midiEventProcessed,
            object: self,
            userInfo: [
                "event": event,
                "sampleOffset": sampleOffset
            ]
        )
    }
}

// MARK: - Utility Functions
extension MIDISequencer {
    
    private func beatToSamples(_ beat: Double) -> AVAudioFramePosition {
        let samplesPerBeat = (60.0 / currentTempo) * sampleRate
        return AVAudioFramePosition(beat * samplesPerBeat)
    }
    
    private func samplesToBeat(_ samples: AVAudioFramePosition) -> Double {
        let samplesPerBeat = (60.0 / currentTempo) * sampleRate
        return Double(samples) / samplesPerBeat
    }
    
    /// Get current beat position
    public var currentBeat: Double {
        return samplesToBeat(samplePosition)
    }
    
    /// Get current sample position
    public var currentSamplePosition: AVAudioFramePosition {
        return samplePosition
    }
    
    private func sendAllNotesOff() {
        // Send All Notes Off (CC 123) to all channels
        for channel in 0..<16 {
            let allNotesOff = MIDIEvent(
                type: .controlChange,
                channel: UInt8(channel),
                data1: 123, // All Notes Off
                data2: 0
            )
            
            // Immediate processing for cleanup
            NotificationCenter.default.post(
                name: .midiEventProcessed,
                object: self,
                userInfo: ["event": SequencerEvent(
                    trackId: -1, // All tracks
                    midiEvent: allNotesOff,
                    beat: currentBeat,
                    sampleTime: samplePosition
                )]
            )
        }
    }
}

// MARK: - Cleanup
extension MIDISequencer {
    
    private func cleanup() {
        eventScheduler = nil
        eventBuffer = nil
        renderCallback = nil
        trackEvents.removeAll()
        
        print("[MIDISequencer] Cleanup completed")
    }
}

// MARK: - Type Imports
// Data types and notifications are defined in SequencerModels.swift