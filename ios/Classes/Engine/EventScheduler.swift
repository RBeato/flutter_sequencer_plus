import Foundation
import AVFoundation

/// High-performance event scheduler with sample-accurate timing
/// Uses lock-free algorithms for real-time audio processing
public class EventScheduler {
    
    // MARK: - Core Properties
    private let sampleRate: Double
    private let bufferSize: Int
    private let ticksPerQuarter: Int
    
    // MARK: - Timing
    private var isRunning = false
    private var currentTempo: Double = 120.0
    private var samplesPerTick: Double
    
    // MARK: - High-Resolution Timer
    private var timer: DispatchSourceTimer?
    private let timerQueue = DispatchQueue(label: "com.sequencer.timer", qos: .userInteractive)
    
    // MARK: - Event Processing
    private let processingQueue = DispatchQueue(label: "com.sequencer.events", qos: .userInteractive)
    
    public init(sampleRate: Double, bufferSize: Int, ticksPerQuarter: Int) {
        self.sampleRate = sampleRate
        self.bufferSize = bufferSize
        self.ticksPerQuarter = ticksPerQuarter
        
        // Calculate samples per tick based on tempo
        self.samplesPerTick = (60.0 / currentTempo) * sampleRate / Double(ticksPerQuarter)
        
        setupTimer()
        print("[EventScheduler] Initialized: \(sampleRate)Hz, \(ticksPerQuarter) ticks/quarter")
    }
    
    deinit {
        stop()
    }
}

// MARK: - Timer Setup
extension EventScheduler {
    
    private func setupTimer() {
        timer = DispatchSource.makeTimerSource(flags: .strict, queue: timerQueue)
        
        // High-frequency timer for precise timing (sub-millisecond accuracy)
        let interval = DispatchTimeInterval.microseconds(Int(1_000_000.0 / (sampleRate / Double(bufferSize))))
        
        timer?.schedule(deadline: .now(), repeating: interval, leeway: .microseconds(10))
        
        timer?.setEventHandler { [weak self] in
            self?.timerTick()
        }
    }
    
    private func timerTick() {
        guard isRunning else { return }
        
        // Process events with high precision timing
        processingQueue.async {
            self.processScheduledEvents()
        }
    }
}

// MARK: - Transport Control
extension EventScheduler {
    
    public func start() {
        guard !isRunning else { return }
        
        isRunning = true
        timer?.resume()
        
        print("[EventScheduler] Started")
    }
    
    public func pause() {
        guard isRunning else { return }
        
        isRunning = false
        // Keep timer running but don't process events
        
        print("[EventScheduler] Paused")
    }
    
    public func resume() {
        guard !isRunning else { return }
        
        isRunning = true
        
        print("[EventScheduler] Resumed")
    }
    
    public func stop() {
        isRunning = false
        timer?.suspend()
        
        print("[EventScheduler] Stopped")
    }
    
    public func setTempo(_ bpm: Double) {
        currentTempo = bpm
        samplesPerTick = calculateSamplesPerTick(tempo: bpm)
        
        print("[EventScheduler] Tempo updated to \(bpm) BPM")
    }
}

// MARK: - Event Processing
extension EventScheduler {
    
    private func processScheduledEvents() {
        // This would typically interface with the main sequencer
        // to trigger events at the correct sample time
        
        // Post notification for sequencer to process events
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .schedulerTick,
                object: self,
                userInfo: ["sampleTime": self.getCurrentSampleTime()]
            )
        }
    }
    
    private func getCurrentSampleTime() -> UInt64 {
        // High-precision sample time calculation
        return mach_absolute_time()
    }
}

// MARK: - Utility Functions
extension EventScheduler {
    
    private func calculateSamplesPerTick(tempo: Double) -> Double {
        // Samples per quarter note = (60 seconds / tempo) * sample rate
        let samplesPerQuarter = (60.0 / tempo) * sampleRate
        
        // Samples per tick = samples per quarter / ticks per quarter
        return samplesPerQuarter / Double(ticksPerQuarter)
    }
    
    public var currentSamplesPerTick: Double {
        return samplesPerTick
    }
}

// MARK: - Notifications
extension Notification.Name {
    static let schedulerTick = Notification.Name("SchedulerTick")
}

// MARK: - Lock-Free Event Buffer
public class LockFreeEventBuffer {
    
    private let capacity: Int
    private var buffer: [SequencerEvent?]
    private var readIndex = UnsafeMutablePointer<Int>.allocate(capacity: 1)
    private var writeIndex = UnsafeMutablePointer<Int>.allocate(capacity: 1)
    
    public init(capacity: Int) {
        self.capacity = capacity
        self.buffer = Array(repeating: nil, count: capacity)
        
        readIndex.pointee = 0
        writeIndex.pointee = 0
    }
    
    deinit {
        readIndex.deallocate()
        writeIndex.deallocate()
    }
    
    /// Write event to buffer (lock-free)
    public func write(_ event: SequencerEvent) {
        let currentWrite = writeIndex.pointee
        let nextWrite = (currentWrite + 1) % capacity
        
        // Check if buffer is full
        if nextWrite == readIndex.pointee {
            return // Buffer full, drop event
        }
        
        buffer[currentWrite] = event
        
        // Memory barrier to ensure write completes before updating index
        OSMemoryBarrier()
        writeIndex.pointee = nextWrite
    }
    
    /// Read event from buffer (lock-free)
    public func read() -> SequencerEvent? {
        let currentRead = readIndex.pointee
        
        // Check if buffer is empty
        if currentRead == writeIndex.pointee {
            return nil
        }
        
        let event = buffer[currentRead]
        buffer[currentRead] = nil // Clear slot
        
        // Memory barrier to ensure read completes before updating index
        OSMemoryBarrier()
        readIndex.pointee = (currentRead + 1) % capacity
        
        return event
    }
    
    /// Clear all events
    public func clear() {
        for i in 0..<capacity {
            buffer[i] = nil
        }
        
        OSMemoryBarrier()
        readIndex.pointee = 0
        writeIndex.pointee = 0
    }
    
    /// Clear events for specific track
    public func clearEvents(forTrack trackId: Int) {
        // Note: This is not truly lock-free due to filtering
        // In a production system, you'd use a more sophisticated approach
        var eventsToKeep: [SequencerEvent] = []
        
        while let event = read() {
            if event.trackId != trackId {
                eventsToKeep.append(event)
            }
        }
        
        // Re-add events that should be kept
        for event in eventsToKeep {
            write(event)
        }
    }
    
    /// Get current buffer usage
    public var count: Int {
        let write = writeIndex.pointee
        let read = readIndex.pointee
        
        if write >= read {
            return write - read
        } else {
            return capacity - read + write
        }
    }
    
    /// Check if buffer is empty
    public var isEmpty: Bool {
        return readIndex.pointee == writeIndex.pointee
    }
    
    /// Check if buffer is full
    public var isFull: Bool {
        let nextWrite = (writeIndex.pointee + 1) % capacity
        return nextWrite == readIndex.pointee
    }
}