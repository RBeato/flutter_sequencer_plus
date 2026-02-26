import Foundation
import AVFoundation
import Flutter

public class CocoaEngine {
    var scheduler: UnsafeMutableRawPointer!
    
    private let engine = AVAudioEngine()
    private var mixer: AVAudioUnit?
    private let outputFormat: AVAudioFormat!
    private let registrar: FlutterPluginRegistrar!

    // PERFORMANCE OPTIMIZATION: Thread-safe audio unit tracking with concurrent reads
    private var unsafeAvAudioUnits: [track_index_t: AVAudioUnit] = [:]
    private let audioUnitsQueue = DispatchQueue(label: "com.flutter_sequencer.audiounits", attributes: .concurrent)
    private var nextTrackId: track_index_t = 0
    private let trackIdQueue = DispatchQueue(label: "com.flutter_sequencer.trackid")
    
    // CRITICAL FIX: Position tracking for audio-visual sync
    private var playbackStartSampleTime: AVAudioFramePosition = 0
    private var pausedAtSampleTime: AVAudioFramePosition = 0
    private var isPlaying: Bool = false
    private var isPaused: Bool = false
    
    // PROFESSIONAL AUDIO TIMING: Use native audio sample time instead of DateTime
    private var audioTimebase: AVAudioFramePosition = 0
    private var lastKnownSampleTime: AVAudioFramePosition = 0
    // High-precision timing based on mach_absolute_time
    private var startHostTime: UInt64 = 0
    private var timebaseInfo = mach_timebase_info_data_t()
    
    init(sampleRateCallbackPort: Dart_Port, registrar: FlutterPluginRegistrar) {
        self.registrar = registrar
        
        // PERFORMANCE OPTIMIZED: Configure audio session and engine for immediate playback
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            
            // LOW-LATENCY: Set smallest possible buffer size for tighter timing
            try session.setPreferredIOBufferDuration(0.005) // 5ms buffer (220 samples at 44.1kHz)
            try session.setPreferredSampleRate(44100) // Lock to 44.1kHz
            
            try session.setActive(true)
        } catch {
            print("[ERROR] Audio session setup failed: \(error)")
        }
        
        // Use optimized output format
        outputFormat = engine.outputNode.outputFormat(forBus: 0)
        
        self.mixer = nil

        // Initialize timebase for mach_absolute_time conversions
        mach_timebase_info(&timebaseInfo)

        // CRITICAL: Start engine immediately to eliminate first-play delay
        do {
            engine.prepare()
            try engine.start()
        } catch {
            print("[ERROR] Failed to pre-start engine: \(error)")
        }

        // Initialize C++ scheduler on the output node's AudioUnit
        // AVAudioOutputNode (AVAudioIONode subclass) exposes audioUnit property
        // Render callback fires once per buffer cycle — processes all tracks
        let outputAU = engine.outputNode.audioUnit!
        self.scheduler = InitScheduler(outputAU, outputFormat.sampleRate)
        SchedulerStartGlobalCallback(self.scheduler)

        // Send callback immediately to unblock Dart
        callbackToDartInt32(sampleRateCallbackPort, Int32(outputFormat.sampleRate))

        SfizzAU.registerAU()
    }
    
    deinit {
        if engine.isRunning {
            engine.stop()
        }
        if scheduler != nil {
            DestroyScheduler(scheduler)
        }
    }
    
    func addTrackSf2(sf2Path: String, isAsset: Bool, presetIndex: Int32, completion: @escaping (track_index_t) -> Void) {
        let startTime = CFAbsoluteTimeGetCurrent()
        print("[PERF] 🚀 Starting SF2 track creation: \(sf2Path)")

        AudioUnitUtils.loadAudioUnits { [weak self] avAudioUnitComponents in
            guard let self = self else {
                completion(track_index_t(999))
                return
            }

            let appleSamplerComponent = avAudioUnitComponents.first(where: isAppleSampler)

            if let appleSamplerComponent = appleSamplerComponent {
                let auStartTime = CFAbsoluteTimeGetCurrent()

                AudioUnitUtils.instantiate(
                    description: appleSamplerComponent.audioComponentDescription,
                    sampleRate: Double(self.outputFormat.sampleRate),
                    options: [.loadOutOfProcess] // Performance optimization
                ) { [weak self] (avAudioUnit: AVAudioUnit?) in
                    guard let self = self else {
                        completion(track_index_t(999))
                        return
                    }

                    guard let avAudioUnit = avAudioUnit else {
                        print("[PERF] ❌ AudioUnit instantiation failed")
                        completion(track_index_t(999))
                        return
                    }

                    let auTime = CFAbsoluteTimeGetCurrent() - auStartTime
                    print("[PERF] ⏱️  AudioUnit instantiated in \(Int(auTime * 1000))ms")

                    // PERFORMANCE: Execute SF2 loading on background queue, connection on main
                    let loadStartTime = CFAbsoluteTimeGetCurrent()

                    if let normalizedPath = self.normalizePath(sf2Path, isAsset: isAsset) {
                        let url = URL(fileURLWithPath: normalizedPath)

                        // Load SF2 on background thread
                        DispatchQueue.global(qos: .userInitiated).async {
                            loadSoundFont(avAudioUnit: avAudioUnit, soundFontURL: url, presetIndex: presetIndex)
                            let loadTime = CFAbsoluteTimeGetCurrent() - loadStartTime
                            print("[PERF] ⏱️  SF2 file loaded in \(Int(loadTime * 1000))ms")

                            // Connection must happen on main thread
                            DispatchQueue.main.async {
                                let trackIndex = self.nextTrackIndex()

                                // CRITICAL: Connect immediately and register AudioUnit
                                self.performanceConnect(avAudioUnit: avAudioUnit, trackIndex: trackIndex)

                                self.setTrackAudioUnit(trackIndex: trackIndex, avAudioUnit: avAudioUnit)

                                // Prime the sampler: send a silent note to force sample cache warmup.
                                // This prevents the scratch/glitch on the very first real note.
                                self.primeInstrument(avAudioUnit: avAudioUnit)

                                let totalTime = CFAbsoluteTimeGetCurrent() - startTime
                                print("[PERF] ✅ Track \(trackIndex) ready in \(Int(totalTime * 1000))ms")

                                completion(trackIndex)
                            }
                        }
                    } else {
                        print("[PERF] ❌ Failed to normalize path: \(sf2Path)")
                        completion(track_index_t(999))
                    }
                }
            } else {
                print("[PERF] ❌ Apple Sampler component not found")
                completion(track_index_t(999))
            }
        }
    }

    // PERFORMANCE OPTIMIZATION: Parallel track creation for multiple SF2 files
    func addMultipleTracksSf2Parallel(
        tracks: [(path: String, isAsset: Bool, preset: Int32)],
        completion: @escaping ([track_index_t]) -> Void
    ) {
        let startTime = CFAbsoluteTimeGetCurrent()
        print("[PERF] 🚀 Starting parallel creation of \(tracks.count) tracks")

        let dispatchGroup = DispatchGroup()
        var trackIndices: [track_index_t] = Array(repeating: track_index_t(999), count: tracks.count)
        let indicesQueue = DispatchQueue(label: "com.flutter_sequencer.indices")

        for (index, trackInfo) in tracks.enumerated() {
            dispatchGroup.enter()

            // Each track loads in parallel
            addTrackSf2(sf2Path: trackInfo.path, isAsset: trackInfo.isAsset, presetIndex: trackInfo.preset) { trackIndex in
                indicesQueue.sync {
                    trackIndices[index] = trackIndex
                }
                dispatchGroup.leave()
            }
        }

        dispatchGroup.notify(queue: .main) {
            let totalTime = CFAbsoluteTimeGetCurrent() - startTime
            let successCount = trackIndices.filter { $0 < 999 }.count
            print("[PERF] ✅ Parallel loading complete: \(successCount)/\(tracks.count) tracks in \(Int(totalTime * 1000))ms")
            completion(trackIndices)
        }
    }
    
    func setTrackAudioUnit(trackIndex: track_index_t, avAudioUnit: AVAudioUnit) {
        // Register with scheduler if available
        if let scheduler = scheduler {
            SchedulerSetTrackAudioUnit(scheduler, trackIndex, avAudioUnit.audioUnit)
        }
        updateAvAudioUnits(trackIndex: trackIndex, avAudioUnit: avAudioUnit)
    }
    
    func play() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { self.play() }
            return
        }

        // CRITICAL FIX: Handle pause/resume state properly
        if isPaused {
            // Resume from paused position
            startHostTime = mach_absolute_time()
            isPlaying = true
            isPaused = false
        } else if !isPlaying {
            // Fresh start - CRITICAL: Reset to position 0 for loop start
            playbackStartSampleTime = 0
            pausedAtSampleTime = 0
            startHostTime = mach_absolute_time()
            isPlaying = true

            // PHYSICAL DEVICE FIX: Warm-up period before first playback
            // Physical devices need time for cache warming and thread scheduling
            // This prevents the first-buffer glitch that occurs on real hardware
            warmUpAudioPipeline()
        } else {
            // Already playing, ignore
            return
        }

        // Start scheduler if available
        if let scheduler = scheduler {
            SchedulerPlay(scheduler)
        }

        // Engine should already be running, but ensure it's ready
        if !engine.isRunning {
            do {
                engine.prepare()
                try engine.start()
            } catch {
                print("[ERROR] Failed to start engine: \(error)")
            }
        }
    }

    /// Warm up the audio pipeline before starting playback on physical devices.
    /// This eliminates the first-buffer glitch by forcing cache loads and thread stabilization.
    private func warmUpAudioPipeline() {
        // Get all audio units thread-safely
        let audioUnits = audioUnitsQueue.sync { Array(self.unsafeAvAudioUnits.values) }

        // Send warm-up notes to each track to prime the DSP pipeline
        for audioUnit in audioUnits {
            let au = audioUnit.audioUnit
            // Quick note burst to force cache warming
            MusicDeviceMIDIEvent(au, 0x90, 60, 80, 0)
            MusicDeviceMIDIEvent(au, 0x80, 60, 0, 0)
        }

        // CRITICAL: Brief delay to let audio thread stabilize
        // Physical devices need this to establish RT priority and warm L1/L2 caches
        // This 100ms delay is imperceptible to users but eliminates first-buffer glitches
        usleep(100000) // 100ms = 4-5 audio buffers at 44.1kHz with 512-sample buffer
    }
    
    func pause() {
        
        guard Thread.isMainThread else {
            DispatchQueue.main.async { self.pause() }
            return
        }
        
        // CRITICAL FIX: Save position for resume, don't reset  
        if isPlaying {
            // Calculate current position before pausing
            let now = mach_absolute_time()
            let elapsedSamples = hostTimeDeltaToSamples(startHostTime, now)
            pausedAtSampleTime = playbackStartSampleTime + elapsedSamples
            isPaused = true
            isPlaying = false
        } else {
            // Full stop - reset everything
            isPlaying = false
            isPaused = false
            playbackStartSampleTime = 0
            pausedAtSampleTime = 0
            startHostTime = 0
        }
        
        // Pause scheduler if available
        if let scheduler = scheduler {
            SchedulerPause(scheduler)
        }
        
        // CRITICAL FIX: Keep engine running to preserve SF2 AudioUnit connections
        // Only send note-off messages to stop hanging notes, don't stop the engine (thread-safe)
        if self.engine.isRunning {
            let audioUnits = audioUnitsQueue.sync { Array(self.unsafeAvAudioUnits.values) }
            for audioUnit in audioUnits {
                for noteNumber in 0...127 {
                    let noteOffCommand: UInt32 = 0x80 // Note Off, channel 0
                    let _ = MusicDeviceMIDIEvent(audioUnit.audioUnit, noteOffCommand, UInt32(noteNumber), 0, 0)
                }
            }
        }
    }
    
    func stop() {
        
        guard Thread.isMainThread else {
            DispatchQueue.main.async { self.stop() }
            return
        }
        
        // Reset all playback state
        isPlaying = false
        isPaused = false
        playbackStartSampleTime = 0
        pausedAtSampleTime = 0
        startHostTime = 0
        
        // Stop scheduler if available
        if let scheduler = scheduler {
            SchedulerPause(scheduler)
        }
        
        // Send note-off to all tracks (thread-safe)
        if self.engine.isRunning {
            let audioUnits = audioUnitsQueue.sync { Array(self.unsafeAvAudioUnits.values) }
            for audioUnit in audioUnits {
                for noteNumber in 0...127 {
                    let noteOffCommand: UInt32 = 0x80
                    let _ = MusicDeviceMIDIEvent(audioUnit.audioUnit, noteOffCommand, UInt32(noteNumber), 0, 0)
                }
            }
        }
        
    }
    
    func getPosition() -> UInt32 {
        // Use scheduler position when available (sample-accurate from audio thread)
        if let scheduler = scheduler {
            return SchedulerGetPosition(scheduler)
        }
        // Fallback: mach_absolute_time estimation
        if isPlaying {
            let now = mach_absolute_time()
            let elapsedSamples = hostTimeDeltaToSamples(startHostTime, now)
            let currentSample = playbackStartSampleTime + elapsedSamples
            return UInt32(max(0, currentSample))
        } else if isPaused {
            return UInt32(max(0, pausedAtSampleTime))
        } else {
            return 0
        }
    }

    // Convert host time delta (mach) to samples using current output sample rate
    private func hostTimeDeltaToSamples(_ start: UInt64, _ end: UInt64) -> AVAudioFramePosition {
        let delta = end &- start
        // Convert to nanoseconds: ns = t * numer / denom
        let ns = (delta * UInt64(timebaseInfo.numer)) / UInt64(timebaseInfo.denom)
        // seconds = ns / 1e9; samples = seconds * sampleRate
        let seconds = Double(ns) / 1_000_000_000.0
        let samples = seconds * outputFormat.sampleRate
        return AVAudioFramePosition(samples)
    }
    
    // Initialize mixer with callback for async completion
    private func initMixer(completion: @escaping () -> Void) {
        let componentDescription = AudioComponentDescription(
            componentType: kAudioUnitType_Mixer,
            componentSubType: kAudioUnitSubType_MultiChannelMixer,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )
        
        AVAudioUnit.instantiate(with: componentDescription, options: []) { avAudioUnit, err in
            if let error = err {
                print("[ERROR] Failed to create mixer: \(error)")
                self.mixer = nil
                completion()
                return
            }
            
            self.mixer = avAudioUnit
            
            if let avAudioUnit = avAudioUnit {
                let hardwareFormat = self.engine.outputNode.outputFormat(forBus: 0)
                
                self.engine.attach(avAudioUnit)
                self.engine.connect(avAudioUnit, to: self.engine.outputNode, format: hardwareFormat)
                
                completion()
            }
        }
    }
    
    /// Send multiple warm-up notes to force the AUSampler to fully cache sample data.
    /// Physical devices need more aggressive priming than simulators to prevent
    /// first-note glitches. We prime across multiple notes with realistic velocities.
    private func primeInstrument(avAudioUnit: AVAudioUnit) {
        let au = avAudioUnit.audioUnit

        // AGGRESSIVE PRIMING: Prime multiple notes at different velocities
        // This forces full sample cache warmup and stabilizes the DSP pipeline
        let primingNotes: [(UInt32, UInt32)] = [
            (60, 64),  // Middle C at medium velocity
            (64, 80),  // E at higher velocity
            (67, 96),  // G at near-max velocity
            (48, 100), // Lower octave at max velocity
            (72, 110)  // Higher octave at high velocity
        ]

        for (note, velocity) in primingNotes {
            // Note-on with realistic velocity
            MusicDeviceMIDIEvent(au, 0x90, note, velocity, 0)
            // Immediate note-off to prevent audible sound
            MusicDeviceMIDIEvent(au, 0x80, note, 0, 0)
        }

        // Give the sampler a moment to process these events and warm caches
        // This is non-blocking and happens during track initialization
        usleep(5000) // 5ms sleep to let cache warm up
    }

    // HIGH-PERFORMANCE connection optimized for immediate playback
    private func performanceConnect(avAudioUnit: AVAudioUnit, trackIndex: track_index_t) {
        do {
            // Attach to engine
            self.engine.attach(avAudioUnit)
            
            // Connect with optimal format
            let format = avAudioUnit.outputFormat(forBus: 0)
            self.engine.connect(avAudioUnit, to: self.engine.mainMixerNode, format: format)
            
            // Update tracking
            updateAvAudioUnits(trackIndex: trackIndex, avAudioUnit: avAudioUnit)
            
        } catch {
            print("[ERROR] Performance connection failed: \(error)")
        }
    }
    
    // Helper to start engine when we have connected nodes (thread-safe)
    private func startEngineIfNeeded() {
        let hasUnits = audioUnitsQueue.sync { !self.unsafeAvAudioUnits.isEmpty }
        if !self.engine.isRunning && hasUnits {
            do {
                try self.engine.start()
            } catch {
                print("[ERROR] Failed to auto-start engine: \(error)")
            }
        }
    }
    
    
    // THREAD-SAFE: Write operations use barrier for exclusive access
    private func updateAvAudioUnits(trackIndex: track_index_t, avAudioUnit: AVAudioUnit?) {
        audioUnitsQueue.async(flags: .barrier) {
            if let avAudioUnit = avAudioUnit {
                self.unsafeAvAudioUnits[trackIndex] = avAudioUnit
            } else {
                self.unsafeAvAudioUnits.removeValue(forKey: trackIndex)
            }
        }
    }

    // THREAD-SAFE: Track ID generation with serial queue
    private func nextTrackIndex() -> track_index_t {
        return trackIdQueue.sync {
            let trackIndex = nextTrackId
            nextTrackId += 1
            return trackIndex
        }
    }

    // THREAD-SAFE: Read AudioUnit with concurrent access
    private func getAudioUnit(for trackIndex: track_index_t) -> AVAudioUnit? {
        return audioUnitsQueue.sync {
            return self.unsafeAvAudioUnits[trackIndex]
        }
    }
    
    private func normalizePath(_ path: String, isAsset: Bool) -> String? {
        if (!isAsset) {
            return path
        } else {
            let key = registrar.lookupKey(forAsset: path)
            guard let normalizedPath = Bundle.main.path(forResource: key, ofType: nil) else {
                print("Could not find asset resource for key: \(key) from path: \(path)")
                return nil
            }
            return normalizedPath
        }
    }
    
    // Send MIDI event to track (thread-safe)
    func sendMIDIEvent(trackIndex: track_index_t, midiStatus: UInt8, midiData1: UInt8, midiData2: UInt8) {
        guard let audioUnit = getAudioUnit(for: trackIndex) else {
            return
        }

        let command = UInt32(midiStatus)
        let data1 = UInt32(midiData1)
        let data2 = UInt32(midiData2)

        let _ = MusicDeviceMIDIEvent(audioUnit.audioUnit, command, data1, data2, 0)
    }
    
    // Test function to play a note on a specific track
    func playTestNote(trackIndex: track_index_t, noteNumber: UInt8 = 60, velocity: UInt8 = 100) {
        sendMIDIEvent(trackIndex: trackIndex, midiStatus: 0x90, midiData1: noteNumber, midiData2: velocity)
        
        // Auto-stop note after 1 second
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.sendMIDIEvent(trackIndex: trackIndex, midiStatus: 0x80, midiData1: noteNumber, midiData2: 0)
        }
    }
    
    func addTrackSfz(sfzPath: UnsafePointer<CChar>, tuningPath: UnsafePointer<CChar>, completion: @escaping (track_index_t) -> Void) {
        let sfzPathString = String(cString: sfzPath)
        
        // Create SfizzAU AudioUnit
        let sfizzAUDescription = SfizzAU.componentDescription
        
        AudioUnitUtils.instantiate(
            description: sfizzAUDescription,
            sampleRate: Double(outputFormat.sampleRate),
            options: [.loadOutOfProcess] // Performance optimization
        ) { [weak self] (avAudioUnit: AVAudioUnit?) in
            guard let self = self else {
                completion(track_index_t(999))
                return
            }
            
            guard let avAudioUnit = avAudioUnit else {
                completion(track_index_t(999))
                return
            }
            
            // PERFORMANCE: Execute on main thread for immediate connection
            DispatchQueue.main.async {
                // Cast to SfizzAU and load SFZ file
                if let sfizzAU = avAudioUnit.auAudioUnit as? SfizzAU {
                    // Load the SFZ file
                    let loadResult = sfizzAU.loadSfzFile(path: sfzPath, tuningPath: tuningPath)
                    
                    if loadResult {
                        let trackIndex = self.nextTrackIndex()

                        // CRITICAL: Connect immediately and register AudioUnit
                        self.performanceConnect(avAudioUnit: avAudioUnit, trackIndex: trackIndex)

                        self.setTrackAudioUnit(trackIndex: trackIndex, avAudioUnit: avAudioUnit)

                        self.primeInstrument(avAudioUnit: avAudioUnit)

                        completion(trackIndex)
                    } else {
                        completion(track_index_t(999))
                    }
                } else {
                    completion(track_index_t(999))
                }
            }
        }
    }

    func addTrackSfzString(sampleRoot: UnsafePointer<CChar>, sfzString: UnsafePointer<CChar>, tuningString: UnsafePointer<CChar>, completion: @escaping (track_index_t) -> Void) {

        // Create SfizzAU AudioUnit
        let sfizzAUDescription = SfizzAU.componentDescription

        AudioUnitUtils.instantiate(
            description: sfizzAUDescription,
            sampleRate: Double(outputFormat.sampleRate),
            options: [.loadOutOfProcess] // Performance optimization
        ) { [weak self] (avAudioUnit: AVAudioUnit?) in
            guard let self = self else {
                completion(track_index_t(999))
                return
            }

            guard let avAudioUnit = avAudioUnit else {
                completion(track_index_t(999))
                return
            }

            // PERFORMANCE: Execute on main thread for immediate connection
            DispatchQueue.main.async {
                // Cast to SfizzAU and load SFZ string
                if let sfizzAU = avAudioUnit.auAudioUnit as? SfizzAU {
                    // Load the SFZ string
                    let loadResult = sfizzAU.loadSfzString(sampleRoot: sampleRoot, sfzString: sfzString, tuningString: tuningString)

                    if loadResult {
                        let trackIndex = self.nextTrackIndex()

                        // CRITICAL: Connect immediately and register AudioUnit
                        self.performanceConnect(avAudioUnit: avAudioUnit, trackIndex: trackIndex)

                        self.setTrackAudioUnit(trackIndex: trackIndex, avAudioUnit: avAudioUnit)

                        self.primeInstrument(avAudioUnit: avAudioUnit)

                        completion(trackIndex)
                    } else {
                        completion(track_index_t(999))
                    }
                } else {
                    completion(track_index_t(999))
                }
            }
        }
    }
    
    func addTrackAudioUnit(audioUnitId: String, completion: @escaping (track_index_t) -> Void) {
        
        // Parse audioUnitId (format: "manufacturer.component" or just look for Apple DLS)
        let isAppleDLS = audioUnitId.contains("Apple") || audioUnitId.contains("DLS") || audioUnitId.contains("dls")
        
        AudioUnitUtils.loadAudioUnits { [weak self] avAudioUnitComponents in
            guard let self = self else { 
                completion(track_index_t(999))
                return 
            }
            
            // Look for Apple DLS Music Device specifically
            let targetComponent: AVAudioUnitComponent?
            
            if isAppleDLS {
                // Find Apple's DLS Music Device (built-in GM synthesizer)
                targetComponent = avAudioUnitComponents.first { component in
                    let desc = component.audioComponentDescription
                    return desc.componentManufacturer == kAudioUnitManufacturer_Apple &&
                           desc.componentType == kAudioUnitType_MusicDevice &&
                           desc.componentSubType == kAudioUnitSubType_MIDISynth
                }
            } else {
                // For other AudioUnits, try to find by name matching
                targetComponent = avAudioUnitComponents.first { component in
                    component.name.lowercased().contains(audioUnitId.lowercased()) ||
                    component.manufacturerName.lowercased().contains(audioUnitId.lowercased())
                }
            }
            
            if let audioUnitComponent = targetComponent {
                
                AudioUnitUtils.instantiate(
                    description: audioUnitComponent.audioComponentDescription,
                    sampleRate: Double(self.outputFormat.sampleRate),
                    options: [.loadOutOfProcess] // Performance optimization
                ) { [weak self] (avAudioUnit: AVAudioUnit?) in
                    guard let self = self else {
                        completion(track_index_t(999))
                        return
                    }
                    
                    guard let avAudioUnit = avAudioUnit else {
                        completion(track_index_t(999))
                        return
                    }
                    
                    // PERFORMANCE: Execute on main thread for immediate connection
                    DispatchQueue.main.async {
                        let trackIndex = self.nextTrackIndex()

                        // CRITICAL: Connect immediately and register AudioUnit
                        self.performanceConnect(avAudioUnit: avAudioUnit, trackIndex: trackIndex)

                        self.setTrackAudioUnit(trackIndex: trackIndex, avAudioUnit: avAudioUnit)

                        self.primeInstrument(avAudioUnit: avAudioUnit)

                        completion(trackIndex)
                    }
                }
            } else {
                // Try to find ANY available music device AudioUnit as fallback
                let fallbackComponent = avAudioUnitComponents.first { component in
                    let desc = component.audioComponentDescription
                    return desc.componentType == kAudioUnitType_MusicDevice
                }
                
                if let fallback = fallbackComponent {
                    
                    AudioUnitUtils.instantiate(
                        description: fallback.audioComponentDescription,
                        sampleRate: Double(self.outputFormat.sampleRate),
                        options: [.loadOutOfProcess]
                    ) { [weak self] (avAudioUnit: AVAudioUnit?) in
                        guard let self = self else {
                            completion(track_index_t(999))
                            return
                        }
                        
                        guard let avAudioUnit = avAudioUnit else {
                            completion(track_index_t(999))
                            return
                        }
                        
                        DispatchQueue.main.async {
                            let trackIndex = self.nextTrackIndex()
                            self.performanceConnect(avAudioUnit: avAudioUnit, trackIndex: trackIndex)
                            self.setTrackAudioUnit(trackIndex: trackIndex, avAudioUnit: avAudioUnit)
                            self.primeInstrument(avAudioUnit: avAudioUnit)
                            completion(trackIndex)
                        }
                    }
                } else {
                    completion(track_index_t(999))
                }
            }
        }
    }
    
    func removeTrack(trackIndex: track_index_t) -> Bool {
        return false
    }
}