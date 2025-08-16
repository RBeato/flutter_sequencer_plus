import Foundation
import AVFoundation

/// High-precision master clock for sample-accurate sequencing
/// Uses Core Audio's sample time for ultimate accuracy
public class MasterClock {
    
    // MARK: - Core Properties
    private let sampleRate: Double
    private let bufferSize: Int
    
    // MARK: - Timing State
    private var isRunning = false
    private var startSampleTime: AVAudioFramePosition = 0
    private var pausedSampleTime: AVAudioFramePosition = 0
    private var currentTempo: Double = 120.0
    
    // MARK: - High-Resolution Timing
    private var hostTimeToSampleTime: Double = 0.0
    private var sampleTimeToHostTime: Double = 0.0
    private var timebaseInfo = mach_timebase_info_data_t()
    
    // MARK: - Beat Tracking
    private var beatsPerMinute: Double = 120.0
    private var samplesPerBeat: Double
    private var ticksPerBeat: Int = 96
    
    // MARK: - Synchronization
    private let clockQueue = DispatchQueue(label: "com.sequencer.clock", qos: .userInteractive)
    
    public init(sampleRate: Double, bufferSize: Int) {
        self.sampleRate = sampleRate
        self.bufferSize = bufferSize
        self.samplesPerBeat = (60.0 / currentTempo) * sampleRate
        
        setupTimebase()
        calculateTimebaseRatios()
        
        print("[MasterClock] Initialized: \(sampleRate)Hz, \(bufferSize) samples/buffer")
    }
    
    deinit {
        stop()
    }
}

// MARK: - Timebase Setup
extension MasterClock {
    
    private func setupTimebase() {
        let result = mach_timebase_info(&timebaseInfo)
        if result != KERN_SUCCESS {
            print("[MasterClock] Warning: Failed to get timebase info")
        }
    }
    
    private func calculateTimebaseRatios() {
        // Convert between host time (mach_absolute_time) and sample time
        let hostTimeFrequency = Double(timebaseInfo.denom) / Double(timebaseInfo.numer) * 1_000_000_000.0
        
        hostTimeToSampleTime = sampleRate / hostTimeFrequency
        sampleTimeToHostTime = hostTimeFrequency / sampleRate
    }
    
    private func calculateSamplesPerBeat(tempo: Double) -> Double {
        // 60 seconds per minute / beats per minute * samples per second
        return (60.0 / tempo) * sampleRate
    }
}

// MARK: - Transport Control
extension MasterClock {
    
    /// Start the master clock
    public func start() {
        clockQueue.sync {
            guard !isRunning else { return }
            
            let currentHostTime = mach_absolute_time()
            startSampleTime = hostTimeToSampleTime(currentHostTime)
            pausedSampleTime = 0
            isRunning = true
            
            print("[MasterClock] Started at sample time \(startSampleTime)")
        }
    }
    
    /// Stop the master clock
    public func stop() {
        clockQueue.sync {
            guard isRunning else { return }
            
            isRunning = false
            startSampleTime = 0
            pausedSampleTime = 0
            
            print("[MasterClock] Stopped")
        }
    }
    
    /// Pause the master clock
    public func pause() {
        clockQueue.sync {
            guard isRunning else { return }
            
            let currentHostTime = mach_absolute_time()
            pausedSampleTime = hostTimeToSampleTime(currentHostTime) - startSampleTime
            isRunning = false
            
            print("[MasterClock] Paused at sample time \(pausedSampleTime)")
        }
    }
    
    /// Resume the master clock
    public func resume() {
        clockQueue.sync {
            guard !isRunning else { return }
            
            let currentHostTime = mach_absolute_time()
            startSampleTime = hostTimeToSampleTime(currentHostTime) - pausedSampleTime
            isRunning = true
            
            print("[MasterClock] Resumed from sample time \(pausedSampleTime)")
        }
    }
}

// MARK: - Tempo Control
extension MasterClock {
    
    /// Set the tempo in BPM
    public func setTempo(_ bpm: Double) {
        clockQueue.sync {
            let oldTempo = currentTempo
            currentTempo = max(1.0, min(300.0, bpm))
            beatsPerMinute = currentTempo
            samplesPerBeat = calculateSamplesPerBeat(tempo: currentTempo)
            
            // Adjust timing to maintain beat position when tempo changes
            if isRunning {
                let currentBeatPosition = getCurrentBeat()
                let timingAdjustment = currentBeatPosition * (calculateSamplesPerBeat(tempo: oldTempo) - samplesPerBeat)
                startSampleTime += AVAudioFramePosition(timingAdjustment)
            }
            
            print("[MasterClock] Tempo changed to \(currentTempo) BPM")
        }
    }
    
    /// Get current tempo
    public var tempo: Double {
        return clockQueue.sync { currentTempo }
    }
}

// MARK: - Time Queries
extension MasterClock {
    
    /// Get current sample position
    public var currentSamplePosition: AVAudioFramePosition {
        return clockQueue.sync {
            guard isRunning else { return pausedSampleTime }
            
            let currentHostTime = mach_absolute_time()
            return hostTimeToSampleTime(currentHostTime) - startSampleTime
        }
    }
    
    /// Get current beat position
    public var currentBeat: Double {
        return getCurrentBeat()
    }
    
    private func getCurrentBeat() -> Double {
        let samplePosition = currentSamplePosition
        return Double(samplePosition) / samplesPerBeat
    }
    
    /// Get current tick position
    public var currentTick: Int {
        let beat = currentBeat
        return Int(beat * Double(ticksPerBeat))
    }
    
    /// Convert beat to sample position
    public func beatToSamplePosition(_ beat: Double) -> AVAudioFramePosition {
        return AVAudioFramePosition(beat * samplesPerBeat)
    }
    
    /// Convert sample position to beat
    public func samplePositionToBeat(_ samplePosition: AVAudioFramePosition) -> Double {
        return Double(samplePosition) / samplesPerBeat
    }
    
    /// Convert beat to host time
    public func beatToHostTime(_ beat: Double) -> UInt64 {
        let samplePosition = beatToSamplePosition(beat)
        return sampleTimeToHostTime(samplePosition + startSampleTime)
    }
    
    /// Get time until next beat
    public var timeToNextBeat: Double {
        let currentBeatPosition = currentBeat
        let nextBeat = floor(currentBeatPosition) + 1.0
        let samplesUntilNextBeat = (nextBeat - currentBeatPosition) * samplesPerBeat
        return samplesUntilNextBeat / sampleRate
    }
    
    /// Get samples per beat at current tempo
    public var currentSamplesPerBeat: Double {
        return samplesPerBeat
    }
}

// MARK: - Time Conversion Utilities
extension MasterClock {
    
    private func hostTimeToSampleTime(_ hostTime: UInt64) -> AVAudioFramePosition {
        let nanoseconds = hostTime * UInt64(timebaseInfo.numer) / UInt64(timebaseInfo.denom)
        let seconds = Double(nanoseconds) / 1_000_000_000.0
        return AVAudioFramePosition(seconds * sampleRate)
    }
    
    private func sampleTimeToHostTime(_ sampleTime: AVAudioFramePosition) -> UInt64 {
        let seconds = Double(sampleTime) / sampleRate
        let nanoseconds = UInt64(seconds * 1_000_000_000.0)
        return nanoseconds * UInt64(timebaseInfo.denom) / UInt64(timebaseInfo.numer)
    }
}

// MARK: - Clock Synchronization
extension MasterClock {
    
    /// Sync to external clock source
    public func syncToExternalClock(sampleTime: AVAudioFramePosition, hostTime: UInt64) {
        clockQueue.sync {
            let expectedSampleTime = hostTimeToSampleTime(hostTime)
            let drift = expectedSampleTime - sampleTime
            
            // Adjust clock if drift is significant (> 1 sample)
            if abs(drift) > 1 {
                startSampleTime += drift
                print("[MasterClock] Synced to external clock, drift: \(drift) samples")
            }
        }
    }
    
    /// Get clock drift relative to system time
    public var clockDrift: AVAudioFramePosition {
        return clockQueue.sync {
            let currentHostTime = mach_absolute_time()
            let expectedSampleTime = hostTimeToSampleTime(currentHostTime) - startSampleTime
            let actualSampleTime = currentSamplePosition
            
            return expectedSampleTime - actualSampleTime
        }
    }
}

// MARK: - Performance Monitoring
extension MasterClock {
    
    public struct ClockMetrics {
        let isRunning: Bool
        let currentBeat: Double
        let currentTempo: Double
        let samplePosition: AVAudioFramePosition
        let clockDrift: AVAudioFramePosition
        let timeToNextBeat: Double
    }
    
    public var metrics: ClockMetrics {
        return ClockMetrics(
            isRunning: isRunning,
            currentBeat: currentBeat,
            currentTempo: currentTempo,
            samplePosition: currentSamplePosition,
            clockDrift: clockDrift,
            timeToNextBeat: timeToNextBeat
        )
    }
}