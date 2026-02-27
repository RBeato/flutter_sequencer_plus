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
    private var startupUnmuteWorkItem: DispatchWorkItem?  // Debounced unmute after track loading
    private var fallbackUnmuteWorkItem: DispatchWorkItem?  // 3s fallback unmute
    
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
        
        // PERFORMANCE OPTIMIZED: Configure audio session for stable playback
        do {
            let session = AVAudioSession.sharedInstance()

            // CRITICAL FIX: Use very conservative buffer for weak devices with multiple SF2 tracks
            // 30ms ensures stability on weak/older iPhones with heavy polyphonic SF2 rendering
            // Testing showed 12ms and 20ms still caused glitches on weak devices with 7 SF2 tracks
            let preferredBufferSize = 0.030 // 30ms ≈ 1440 samples at 48kHz

            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])

            // Set buffer size with fallback handling
            do {
                try session.setPreferredIOBufferDuration(preferredBufferSize)
                print("[AUDIO] Buffer size set to \(preferredBufferSize * 1000)ms")
            } catch {
                print("[WARNING] Could not set preferred buffer size: \(error)")
                // Continue with system default buffer size
            }

            // Don't force sample rate - use hardware's native rate to avoid resampling overhead
            // Most modern iOS devices use 48kHz, forcing 44.1kHz causes unnecessary CPU load
            print("[AUDIO] Using hardware sample rate: \(session.sampleRate)Hz")

            try session.setActive(true)
            print("[AUDIO] Audio session activated successfully")
        } catch {
            print("[ERROR] Audio session setup failed: \(error)")
            // CRITICAL: This is a fatal error, audio won't work properly
        }
        
        // Use optimized output format
        outputFormat = engine.outputNode.outputFormat(forBus: 0)
        
        self.mixer = nil

        // Initialize timebase for mach_absolute_time conversions
        mach_timebase_info(&timebaseInfo)

        // Force consistent sample rate through entire audio graph
        engine.connect(engine.mainMixerNode, to: engine.outputNode, format: outputFormat)
        print("[AUDIO] Mixer→Output connected at \(outputFormat.sampleRate)Hz")

        // CRITICAL: Start engine immediately to eliminate first-play delay
        // Mute output during startup to suppress audio graph reconfiguration transients
        // (attaching/connecting AudioUnits to a running engine causes brief pops)
        engine.mainMixerNode.outputVolume = 0
        do {
            engine.prepare()
            try engine.start()
        } catch {
            print("[ERROR] Failed to pre-start engine: \(error)")
        }

        // Fallback unmute: 3s covers even slow SF2 loading on weak devices.
        // The debounced unmute in scheduleStartupUnmute() fires sooner (200ms after
        // the last track connects) and cancels this fallback, so it only fires
        // if no tracks are created or loading takes unusually long.
        let fallback = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            if self.engine.mainMixerNode.outputVolume < 0.01 {
                self.fadeInMixer()
                print("[AUDIO] Output volume fade-in (fallback timer)")
            }
        }
        fallbackUnmuteWorkItem = fallback
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0, execute: fallback)

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

        // CC123 All Notes Off REMOVED from play():
        // Sending CC123 to all 7 AudioUnits creates a subtle release transient
        // on Apple Sampler even when no notes are active. Notes are properly
        // stopped by: (1) individual note-offs in stop/pause, (2) 200ms auto-off
        // for preview notes, (3) LEAD_FRAMES silence gap before first events.

        // Start scheduler if available.
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
    /// Non-blocking approach - no sleep to avoid UI freeze.
    private func warmUpAudioPipeline() {
        // Audio thread RT priority is already set in render callback
        // Instruments already primed during track creation
        // No additional warm-up needed - just ensure engine is running
        if !engine.isRunning {
            do {
                engine.prepare()
                try engine.start()
            } catch {
                print("[WARNING] Warm-up engine start failed: \(error)")
            }
        }
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
        
        // Keep engine running to preserve SF2 AudioUnit connections.
        // Use CC123 (All Notes Off) — single MIDI event per track instead of
        // 128 individual note-offs. Much less MIDI traffic and no burst of events
        // that could cause audio thread contention.
        if self.engine.isRunning {
            let audioUnits = audioUnitsQueue.sync { Array(self.unsafeAvAudioUnits.values) }
            for audioUnit in audioUnits {
                MusicDeviceMIDIEvent(audioUnit.audioUnit, 0xB0, 123, 0, 0)
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

        // CC123 All Notes Off — efficient single event per track
        if self.engine.isRunning {
            let audioUnits = audioUnitsQueue.sync { Array(self.unsafeAvAudioUnits.values) }
            for audioUnit in audioUnits {
                MusicDeviceMIDIEvent(audioUnit.audioUnit, 0xB0, 123, 0, 0)
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
    
    /// Priming DISABLED: Sending MIDI Note On/Off during track creation causes audible
    /// glitches in two scenarios:
    /// 1. During instrument changes while playing (mixer at full volume → audible notes)
    /// 2. During startup (note-on/off at offset 0 → one-sample click in residual signal,
    ///    then amplified by instant unmute transition)
    /// Apple's AUSampler loads samples fast enough that first-note latency is negligible.
    private func primeInstrument(avAudioUnit: AVAudioUnit) {
        // No-op: priming removed to eliminate audio glitches.
        // See git history for previous implementation.
    }

    /// Debounced startup unmute: reschedules 200ms after each track connection.
    /// This ensures ALL tracks are connected before audio becomes audible.
    /// Uses a gradual fade-in to prevent pop from instant 0→1 volume transition.
    private func scheduleStartupUnmute() {
        startupUnmuteWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            // Cancel the 3s fallback — this debounced unmute takes priority
            self.fallbackUnmuteWorkItem?.cancel()
            self.fadeInMixer()
        }
        startupUnmuteWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: workItem)
    }

    /// Gradually fade mixer volume from 0 to 1 over ~50ms to avoid pop.
    /// Uses 5 steps of 10ms each (smooth enough to be inaudible).
    private func fadeInMixer(duration: TimeInterval = 0.05, steps: Int = 5) {
        let stepDuration = duration / Double(steps)
        for i in 1...steps {
            let volume = Float(i) / Float(steps)
            DispatchQueue.main.asyncAfter(deadline: .now() + stepDuration * Double(i)) { [weak self] in
                self?.engine.mainMixerNode.outputVolume = volume
            }
        }
        print("[AUDIO] Output volume fade-in started (\(Int(duration * 1000))ms)")
    }

    // HIGH-PERFORMANCE connection optimized for immediate playback
    private func performanceConnect(avAudioUnit: AVAudioUnit, trackIndex: track_index_t) {
        // Use hardware format for all connections to avoid automatic resampling.
        // AudioUnits may report 44.1kHz internally, but AVAudioEngine connects
        // them at the hardware rate (48kHz). Using the AU's own format would force
        // an unnecessary sample rate converter, adding CPU overhead and latency.
        let hardwareFormat = engine.outputNode.outputFormat(forBus: 0)
        let auFormat = avAudioUnit.outputFormat(forBus: 0)

        // GLITCH FIX: Mute before graph reconfiguration if mixer is audible.
        // engine.attach() + engine.connect() on a running engine causes CoreAudio
        // to briefly reconfigure the audio graph, producing a transient pop.
        // Muting first makes this inaudible; fadeInMixer restores volume after.
        if engine.mainMixerNode.outputVolume > 0 {
            engine.mainMixerNode.outputVolume = 0
        }

        engine.attach(avAudioUnit)
        engine.connect(avAudioUnit, to: engine.mainMixerNode, format: hardwareFormat)
        updateAvAudioUnits(trackIndex: trackIndex, avAudioUnit: avAudioUnit)
        print("[AUDIO] Track \(trackIndex) connected at \(hardwareFormat.sampleRate)Hz (AU reported \(auFormat.sampleRate)Hz)")

        // Reschedule startup unmute — waits 200ms after the LAST track connects,
        // then fades in gradually to avoid pop from instant 0→1 transition
        scheduleStartupUnmute()
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