import Foundation
import AVFoundation
import Flutter

public class CocoaEngine {
    var scheduler: UnsafeMutableRawPointer!
    
    private let engine = AVAudioEngine()
    private var mixer: AVAudioUnit?
    private let outputFormat: AVAudioFormat!
    private let registrar: FlutterPluginRegistrar!

    // Swift Dictionary is not thread-safe, so this must be copied before access
    private var unsafeAvAudioUnits: [track_index_t: AVAudioUnit] = [:]
    private var nextTrackId: track_index_t = 0
    
    // CRITICAL FIX: Position tracking for audio-visual sync
    private var playbackStartSampleTime: AVAudioFramePosition = 0
    private var pausedAtSampleTime: AVAudioFramePosition = 0
    private var isPlaying: Bool = false
    private var isPaused: Bool = false
    private var playbackStartTime: Date?
    
    init(sampleRateCallbackPort: Dart_Port, registrar: FlutterPluginRegistrar) {
        self.registrar = registrar
        
        print("[DEBUG] CocoaEngine init started")
        
        // PERFORMANCE OPTIMIZED: Configure audio session and engine for immediate playback
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
            print("[DEBUG] Audio session configured for optimal performance")
        } catch {
            print("[ERROR] Audio session setup failed: \(error)")
        }
        
        // Use optimized output format
        outputFormat = engine.outputNode.outputFormat(forBus: 0)
        print("[DEBUG] Engine format: \(outputFormat.sampleRate)Hz, channels: \(outputFormat.channelCount)")
        
        // Skip scheduler for minimal latency
        self.scheduler = nil
        self.mixer = nil
        
        // CRITICAL: Start engine immediately to eliminate first-play delay
        do {
            engine.prepare()
            try engine.start()
            print("[DEBUG] Engine pre-started for zero-latency playback")
        } catch {
            print("[ERROR] Failed to pre-start engine: \(error)")
        }
        
        // Send callback immediately to unblock Dart
        callbackToDartInt32(sampleRateCallbackPort, Int32(outputFormat.sampleRate))
        
        SfizzAU.registerAU()
        print("[DEBUG] CocoaEngine init completed")
    }
    
    deinit {
        print("[DEBUG] CocoaEngine deinit")
        if engine.isRunning {
            engine.stop()
        }
        if scheduler != nil {
            DestroyScheduler(scheduler)
        }
    }
    
    func addTrackSf2(sf2Path: String, isAsset: Bool, presetIndex: Int32, completion: @escaping (track_index_t) -> Void) {
        NSLog("🎵 HIGH-PERF: Adding SF2 track: \(sf2Path)")
        print("🎵 DIAGNOSTIC: Starting addTrackSf2 for: \(sf2Path)")
        
        AudioUnitUtils.loadAudioUnits { [weak self] avAudioUnitComponents in
            guard let self = self else { 
                print("❌ DIAGNOSTIC: Self is nil in loadAudioUnits callback")
                completion(track_index_t(999))
                return 
            }
            
            print("🔍 DIAGNOSTIC: Loaded \(avAudioUnitComponents.count) AudioUnit components")
            
            let appleSamplerComponent = avAudioUnitComponents.first(where: isAppleSampler)
            
            if let appleSamplerComponent = appleSamplerComponent {
                print("✅ DIAGNOSTIC: Found Apple Sampler component: \(appleSamplerComponent.name)")
                
                AudioUnitUtils.instantiate(
                    description: appleSamplerComponent.audioComponentDescription,
                    sampleRate: Double(self.outputFormat.sampleRate),
                    options: [.loadOutOfProcess] // Performance optimization
                ) { [weak self] (avAudioUnit: AVAudioUnit?) in
                    print("🔄 DIAGNOSTIC: AudioUnit instantiate callback called")
                    guard let self = self else {
                        print("❌ DIAGNOSTIC: Self is nil in instantiate callback")
                        completion(track_index_t(999))
                        return
                    }
                    
                    guard let avAudioUnit = avAudioUnit else {
                        print("❌ DIAGNOSTIC: AudioUnit instantiation failed - avAudioUnit is nil")
                        completion(track_index_t(999))
                        return
                    }
                    
                    print("✅ DIAGNOSTIC: AudioUnit instantiated successfully")
                    
                    // PERFORMANCE: Execute on main thread for immediate connection
                    DispatchQueue.main.async {
                        print("🔄 DIAGNOSTIC: Executing on main thread")
                        if let normalizedPath = self.normalizePath(sf2Path, isAsset: isAsset) {
                            print("✅ DIAGNOSTIC: Path normalized: \(normalizedPath)")
                            let url = URL(fileURLWithPath: normalizedPath)
                            
                            print("🎵 DIAGNOSTIC: Loading SoundFont...")
                            // High-performance SF2 loading with immediate connection
                            loadSoundFont(avAudioUnit: avAudioUnit, soundFontURL: url, presetIndex: presetIndex)
                            print("✅ DIAGNOSTIC: SoundFont loaded")
                            
                            let trackIndex = self.nextTrackIndex()
                            print("🎯 DIAGNOSTIC: Created track index: \(trackIndex)")
                            
                            // CRITICAL: Connect immediately and register AudioUnit
                            self.performanceConnect(avAudioUnit: avAudioUnit, trackIndex: trackIndex)
                            print("✅ DIAGNOSTIC: AudioUnit connected")
                            
                            self.setTrackAudioUnit(trackIndex: trackIndex, avAudioUnit: avAudioUnit)
                            print("✅ DIAGNOSTIC: AudioUnit registered with track \(trackIndex)")
                            
                            completion(trackIndex)
                            print("🎉 DIAGNOSTIC: SF2 track creation completed successfully!")
                        } else {
                            print("❌ DIAGNOSTIC: Path normalization failed for \(sf2Path)")
                            completion(track_index_t(999))
                        }
                    }
                }
            } else {
                print("❌ DIAGNOSTIC: Apple Sampler component not found in \(avAudioUnitComponents.count) components")
                for component in avAudioUnitComponents {
                    print("   - Available: \(component.name) by \(component.manufacturerName)")
                }
                completion(track_index_t(999))
            }
        }
    }
    
    func setTrackAudioUnit(trackIndex: track_index_t, avAudioUnit: AVAudioUnit) {
        // Register with scheduler if available
        if let scheduler = scheduler {
            SchedulerSetTrackAudioUnit(scheduler, trackIndex, avAudioUnit.audioUnit)
            print("[DEBUG] Track \(trackIndex) registered with scheduler")
        }
        updateAvAudioUnits(trackIndex: trackIndex, avAudioUnit: avAudioUnit)
        print("[DEBUG] AudioUnit configured for track \(trackIndex)")
    }
    
    func play() {
        print("[DEBUG] HIGH-PERF play() - Engine running: \(engine.isRunning)")
        print("[DEBUG] Connected AudioUnits: \(self.unsafeAvAudioUnits.count)")
        print("[DEBUG] Play state: isPlaying=\(isPlaying), isPaused=\(isPaused)")
        
        guard Thread.isMainThread else {
            DispatchQueue.main.async { self.play() }
            return
        }
        
        // CRITICAL FIX: Handle pause/resume state properly
        if isPaused {
            // Resume from paused position
            playbackStartTime = Date()
            isPlaying = true
            isPaused = false
            print("[DEBUG] RESUMING from sample \(pausedAtSampleTime)")
        } else if !isPlaying {
            // Fresh start
            playbackStartSampleTime = 0
            pausedAtSampleTime = 0
            playbackStartTime = Date()
            isPlaying = true
            print("[DEBUG] STARTING fresh from position 0")
        } else {
            print("[DEBUG] Already playing, ignoring play() call")
            return
        }
        
        // Start scheduler if available
        if let scheduler = scheduler {
            SchedulerPlay(scheduler)
            print("[DEBUG] Scheduler started")
        }
        
        // Engine should already be running, but ensure it's ready
        if !engine.isRunning {
            do {
                engine.prepare()
                try engine.start()
                print("[DEBUG] Engine started (should have been pre-started)")
            } catch {
                print("[ERROR] Failed to start engine: \(error)")
            }
        } else {
            print("[DEBUG] Engine already running - ready for immediate MIDI")
        }
    }
    
    func pause() {
        print("[DEBUG] CocoaEngine.pause() - Current state: isPlaying=\(isPlaying)")
        
        guard Thread.isMainThread else {
            DispatchQueue.main.async { self.pause() }
            return
        }
        
        // CRITICAL FIX: Save position for resume, don't reset  
        if isPlaying {
            // Calculate current position before pausing
            if let startTime = playbackStartTime {
                let elapsed = Date().timeIntervalSince(startTime)
                pausedAtSampleTime = playbackStartSampleTime + AVAudioFramePosition(elapsed * outputFormat.sampleRate)
            } else {
                pausedAtSampleTime = playbackStartSampleTime
            }
            isPaused = true
            isPlaying = false
            print("[DEBUG] PAUSED at sample \(pausedAtSampleTime)")
        } else {
            // Full stop - reset everything
            isPlaying = false
            isPaused = false
            playbackStartSampleTime = 0
            pausedAtSampleTime = 0
            playbackStartTime = nil
            print("[DEBUG] STOPPED - all positions reset to 0")
        }
        
        // Pause scheduler if available
        if let scheduler = scheduler {
            SchedulerPause(scheduler)
            print("[DEBUG] Scheduler paused")
        }
        
        // CRITICAL FIX: Keep engine running to preserve SF2 AudioUnit connections
        // Only send note-off messages to stop hanging notes, don't stop the engine
        if self.engine.isRunning {
            // Send note off to all connected AudioUnits to prevent hanging notes
            for (trackId, audioUnit) in self.unsafeAvAudioUnits {
                for noteNumber in 0...127 {
                    let noteOffCommand: UInt32 = 0x80 // Note Off, channel 0
                    let _ = MusicDeviceMIDIEvent(audioUnit.audioUnit, noteOffCommand, UInt32(noteNumber), 0, 0)
                }
                print("[DEBUG] Sent all notes off to track \(trackId)")
            }
            
            print("[DEBUG] Engine kept running to preserve SF2 connections")
        }
    }
    
    func stop() {
        print("[DEBUG] CocoaEngine.stop() - Full stop and reset")
        
        guard Thread.isMainThread else {
            DispatchQueue.main.async { self.stop() }
            return
        }
        
        // Reset all playback state
        isPlaying = false
        isPaused = false
        playbackStartSampleTime = 0
        pausedAtSampleTime = 0
        playbackStartTime = nil
        
        // Stop scheduler if available
        if let scheduler = scheduler {
            SchedulerPause(scheduler)
        }
        
        // Send note-off to all tracks
        if self.engine.isRunning {
            for (trackId, audioUnit) in self.unsafeAvAudioUnits {
                for noteNumber in 0...127 {
                    let noteOffCommand: UInt32 = 0x80
                    let _ = MusicDeviceMIDIEvent(audioUnit.audioUnit, noteOffCommand, UInt32(noteNumber), 0, 0)
                }
            }
        }
        
        print("[DEBUG] Stop complete - all state reset")
    }
    
    func getPosition() -> UInt32 {
        // CRITICAL FIX: Return actual position for proper sync
        if isPlaying, let startTime = playbackStartTime {
            let elapsed = Date().timeIntervalSince(startTime)
            let currentSample = playbackStartSampleTime + AVAudioFramePosition(elapsed * outputFormat.sampleRate)
            return UInt32(max(0, currentSample))
        } else if isPaused {
            return UInt32(max(0, pausedAtSampleTime))
        } else {
            return 0
        }
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
                print("[DEBUG] Mixer created and connected to output")
                
                completion()
            }
        }
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
            
            print("[DEBUG] HIGH-PERF: Track \(trackIndex) connected and ready")
            
        } catch {
            print("[ERROR] Performance connection failed: \(error)")
        }
    }
    
    // Helper to start engine when we have connected nodes
    private func startEngineIfNeeded() {
        if !self.engine.isRunning && !self.unsafeAvAudioUnits.isEmpty {
            do {
                print("[DEBUG] Auto-starting engine with connected AudioUnits")
                try self.engine.start()
                print("[DEBUG] Engine auto-started successfully")
            } catch {
                print("[ERROR] Failed to auto-start engine: \(error)")
            }
        }
    }
    
    
    private func updateAvAudioUnits(trackIndex: track_index_t, avAudioUnit: AVAudioUnit?) {
        if let avAudioUnit = avAudioUnit {
            self.unsafeAvAudioUnits[trackIndex] = avAudioUnit
        } else {
            self.unsafeAvAudioUnits.removeValue(forKey: trackIndex)
        }
    }
    
    private func nextTrackIndex() -> track_index_t {
        let trackIndex = nextTrackId
        nextTrackId += 1
        print("[DEBUG] 🎵 Created track with ID: \(trackIndex)")
        return trackIndex
    }
    
    private func normalizePath(_ path: String, isAsset: Bool) -> String? {
        print("[DEBUG] normalizePath called: path=\(path) isAsset=\(isAsset)")
        if (!isAsset) {
            print("[DEBUG] Non-asset path, returning as-is: \(path)")
            return path
        } else {
            let key = registrar.lookupKey(forAsset: path)
            print("[DEBUG] Asset key lookup: \(path) -> \(key)")
            let normalizedPath = Bundle.main.path(forResource: key, ofType: nil)
            print("[DEBUG] Bundle path lookup: \(key) -> \(normalizedPath ?? "nil")")
            return normalizedPath
        }
    }
    
    // HIGH-PERFORMANCE: Optimized MIDI event handling for immediate SF2 playback
    func sendMIDIEvent(trackIndex: track_index_t, midiStatus: UInt8, midiData1: UInt8, midiData2: UInt8) {
        // DIAGNOSTIC: Show all available tracks
        NSLog("🔍 Available AudioUnit tracks: %@", Array(unsafeAvAudioUnits.keys).description)
        NSLog("🎵 Looking for track %d to send MIDI status=0x%02X note=%d vel=%d", trackIndex, midiStatus, midiData1, midiData2)
        
        guard let audioUnit = unsafeAvAudioUnits[trackIndex] else {
            NSLog("❌ CRITICAL: No AudioUnit found for track %d - available: %@", trackIndex, Array(unsafeAvAudioUnits.keys).description)
            return
        }
        
        NSLog("✅ Found AudioUnit for track %d, sending MIDI...", trackIndex)
        
        // PERFORMANCE: Direct MIDI with minimal overhead
        let command = UInt32(midiStatus)
        let data1 = UInt32(midiData1) 
        let data2 = UInt32(midiData2)
        
        let result = MusicDeviceMIDIEvent(audioUnit.audioUnit, command, data1, data2, 0)
        
        if result == noErr {
            NSLog("🎵 SUCCESS: MIDI sent to track %d: status=0x%02X note=%d vel=%d", trackIndex, midiStatus, midiData1, midiData2)
        } else {
            NSLog("❌ MIDI FAILED for track %d: error=%d", trackIndex, Int(result))
            
            // Diagnostic: Check if AudioUnit is still valid
            if !engine.attachedNodes.contains(audioUnit) {
                NSLog("❌ AudioUnit not attached to engine for track %d", trackIndex)
            }
        }
    }
    
    // Test function to play a note on a specific track
    func playTestNote(trackIndex: track_index_t, noteNumber: UInt8 = 60, velocity: UInt8 = 100) {
        print("[DEBUG] Playing test note \(noteNumber) on track \(trackIndex)")
        sendMIDIEvent(trackIndex: trackIndex, midiStatus: 0x90, midiData1: noteNumber, midiData2: velocity)
        
        // Auto-stop note after 1 second
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.sendMIDIEvent(trackIndex: trackIndex, midiStatus: 0x80, midiData1: noteNumber, midiData2: 0)
        }
    }
    
    func addTrackSfz(sfzPath: UnsafePointer<CChar>, tuningPath: UnsafePointer<CChar>, completion: @escaping (track_index_t) -> Void) {
        let sfzPathString = String(cString: sfzPath)
        NSLog("🎵 HIGH-PERF: Adding SFZ track: \(sfzPathString)")
        print("🎵 DIAGNOSTIC: Starting addTrackSfz for: \(sfzPathString)")
        
        // Create SfizzAU AudioUnit
        let sfizzAUDescription = SfizzAU.componentDescription
        
        AudioUnitUtils.instantiate(
            description: sfizzAUDescription,
            sampleRate: Double(outputFormat.sampleRate),
            options: [.loadOutOfProcess] // Performance optimization
        ) { [weak self] (avAudioUnit: AVAudioUnit?) in
            print("🔄 DIAGNOSTIC: SfizzAU instantiate callback called")
            guard let self = self else {
                print("❌ DIAGNOSTIC: Self is nil in SfizzAU instantiate callback")
                completion(track_index_t(999))
                return
            }
            
            guard let avAudioUnit = avAudioUnit else {
                print("❌ DIAGNOSTIC: SfizzAU instantiation failed - avAudioUnit is nil")
                completion(track_index_t(999))
                return
            }
            
            print("✅ DIAGNOSTIC: SfizzAU instantiated successfully")
            
            // PERFORMANCE: Execute on main thread for immediate connection
            DispatchQueue.main.async {
                print("🔄 DIAGNOSTIC: Executing SFZ setup on main thread")
                
                // Cast to SfizzAU and load SFZ file
                if let sfizzAU = avAudioUnit.auAudioUnit as? SfizzAU {
                    print("✅ DIAGNOSTIC: Successfully cast to SfizzAU")
                    
                    // Load the SFZ file
                    let loadResult = sfizzAU.loadSfzFile(path: sfzPath, tuningPath: tuningPath)
                    
                    if loadResult {
                        print("✅ DIAGNOSTIC: SFZ file loaded successfully")
                        
                        let trackIndex = self.nextTrackIndex()
                        print("🎯 DIAGNOSTIC: Created SFZ track index: \(trackIndex)")
                        
                        // CRITICAL: Connect immediately and register AudioUnit
                        self.performanceConnect(avAudioUnit: avAudioUnit, trackIndex: trackIndex)
                        print("✅ DIAGNOSTIC: SfizzAU connected")
                        
                        self.setTrackAudioUnit(trackIndex: trackIndex, avAudioUnit: avAudioUnit)
                        print("✅ DIAGNOSTIC: SfizzAU registered with track \(trackIndex)")
                        
                        completion(trackIndex)
                        print("🎉 DIAGNOSTIC: SFZ track creation completed successfully!")
                    } else {
                        print("❌ DIAGNOSTIC: Failed to load SFZ file: \(sfzPathString)")
                        completion(track_index_t(999))
                    }
                } else {
                    print("❌ DIAGNOSTIC: Failed to cast to SfizzAU")
                    completion(track_index_t(999))
                }
            }
        }
    }
    
    func addTrackSfzString(sampleRoot: UnsafePointer<CChar>, sfzString: UnsafePointer<CChar>, tuningString: UnsafePointer<CChar>, completion: @escaping (track_index_t) -> Void) {
        let sampleRootString = String(cString: sampleRoot)
        NSLog("🎵 HIGH-PERF: Adding SFZ string track with sample root: \(sampleRootString)")
        print("🎵 DIAGNOSTIC: Starting addTrackSfzString")
        
        // Create SfizzAU AudioUnit
        let sfizzAUDescription = SfizzAU.componentDescription
        
        AudioUnitUtils.instantiate(
            description: sfizzAUDescription,
            sampleRate: Double(outputFormat.sampleRate),
            options: [.loadOutOfProcess] // Performance optimization
        ) { [weak self] (avAudioUnit: AVAudioUnit?) in
            print("🔄 DIAGNOSTIC: SfizzAU string instantiate callback called")
            guard let self = self else {
                print("❌ DIAGNOSTIC: Self is nil in SfizzAU string instantiate callback")
                completion(track_index_t(999))
                return
            }
            
            guard let avAudioUnit = avAudioUnit else {
                print("❌ DIAGNOSTIC: SfizzAU string instantiation failed - avAudioUnit is nil")
                completion(track_index_t(999))
                return
            }
            
            print("✅ DIAGNOSTIC: SfizzAU string instantiated successfully")
            
            // PERFORMANCE: Execute on main thread for immediate connection
            DispatchQueue.main.async {
                print("🔄 DIAGNOSTIC: Executing SFZ string setup on main thread")
                
                // Cast to SfizzAU and load SFZ string
                if let sfizzAU = avAudioUnit.auAudioUnit as? SfizzAU {
                    print("✅ DIAGNOSTIC: Successfully cast to SfizzAU for string loading")
                    
                    // Load the SFZ string
                    let loadResult = sfizzAU.loadSfzString(sampleRoot: sampleRoot, sfzString: sfzString, tuningString: tuningString)
                    
                    if loadResult {
                        print("✅ DIAGNOSTIC: SFZ string loaded successfully")
                        
                        let trackIndex = self.nextTrackIndex()
                        print("🎯 DIAGNOSTIC: Created SFZ string track index: \(trackIndex)")
                        
                        // CRITICAL: Connect immediately and register AudioUnit
                        self.performanceConnect(avAudioUnit: avAudioUnit, trackIndex: trackIndex)
                        print("✅ DIAGNOSTIC: SfizzAU string connected")
                        
                        self.setTrackAudioUnit(trackIndex: trackIndex, avAudioUnit: avAudioUnit)
                        print("✅ DIAGNOSTIC: SfizzAU string registered with track \(trackIndex)")
                        
                        completion(trackIndex)
                        print("🎉 DIAGNOSTIC: SFZ string track creation completed successfully!")
                    } else {
                        print("❌ DIAGNOSTIC: Failed to load SFZ string")
                        completion(track_index_t(999))
                    }
                } else {
                    print("❌ DIAGNOSTIC: Failed to cast to SfizzAU for string loading")
                    completion(track_index_t(999))
                }
            }
        }
    }
    
    func addTrackAudioUnit(audioUnitId: String, completion: @escaping (track_index_t) -> Void) {
        NSLog("🎵 HIGH-PERF: Adding AudioUnit track: \(audioUnitId)")
        print("🎵 DIAGNOSTIC: Starting addTrackAudioUnit for: \(audioUnitId)")
        
        // Parse audioUnitId (format: "manufacturer.component" or just look for Apple DLS)
        let isAppleDLS = audioUnitId.contains("Apple") || audioUnitId.contains("DLS") || audioUnitId.contains("dls")
        
        AudioUnitUtils.loadAudioUnits { [weak self] avAudioUnitComponents in
            guard let self = self else { 
                print("❌ DIAGNOSTIC: Self is nil in AudioUnit loadAudioUnits callback")
                completion(track_index_t(999))
                return 
            }
            
            print("🔍 DIAGNOSTIC: Loaded \(avAudioUnitComponents.count) AudioUnit components")
            
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
                print("✅ DIAGNOSTIC: Found AudioUnit component: \(audioUnitComponent.name) by \(audioUnitComponent.manufacturerName)")
                
                AudioUnitUtils.instantiate(
                    description: audioUnitComponent.audioComponentDescription,
                    sampleRate: Double(self.outputFormat.sampleRate),
                    options: [.loadOutOfProcess] // Performance optimization
                ) { [weak self] (avAudioUnit: AVAudioUnit?) in
                    print("🔄 DIAGNOSTIC: AudioUnit instantiate callback called")
                    guard let self = self else {
                        print("❌ DIAGNOSTIC: Self is nil in AudioUnit instantiate callback")
                        completion(track_index_t(999))
                        return
                    }
                    
                    guard let avAudioUnit = avAudioUnit else {
                        print("❌ DIAGNOSTIC: AudioUnit instantiation failed - avAudioUnit is nil")
                        completion(track_index_t(999))
                        return
                    }
                    
                    print("✅ DIAGNOSTIC: AudioUnit instantiated successfully")
                    
                    // PERFORMANCE: Execute on main thread for immediate connection
                    DispatchQueue.main.async {
                        print("🔄 DIAGNOSTIC: Executing AudioUnit setup on main thread")
                        
                        let trackIndex = self.nextTrackIndex()
                        print("🎯 DIAGNOSTIC: Created AudioUnit track index: \(trackIndex)")
                        
                        // CRITICAL: Connect immediately and register AudioUnit
                        self.performanceConnect(avAudioUnit: avAudioUnit, trackIndex: trackIndex)
                        print("✅ DIAGNOSTIC: AudioUnit connected")
                        
                        self.setTrackAudioUnit(trackIndex: trackIndex, avAudioUnit: avAudioUnit)
                        print("✅ DIAGNOSTIC: AudioUnit registered with track \(trackIndex)")
                        
                        completion(trackIndex)
                        print("🎉 DIAGNOSTIC: AudioUnit track creation completed successfully!")
                    }
                }
            } else {
                print("❌ DIAGNOSTIC: AudioUnit component not found for ID: \(audioUnitId)")
                print("🔍 Available AudioUnits (\(avAudioUnitComponents.count) found):")
                for component in avAudioUnitComponents {
                    let desc = component.audioComponentDescription
                    print("   - \(component.name) by \(component.manufacturerName)")
                    print("     Type: \(desc.componentType), Subtype: \(desc.componentSubType), Manufacturer: \(desc.componentManufacturer)")
                }
                
                // Try to find ANY available music device AudioUnit as fallback
                let fallbackComponent = avAudioUnitComponents.first { component in
                    let desc = component.audioComponentDescription
                    return desc.componentType == kAudioUnitType_MusicDevice
                }
                
                if let fallback = fallbackComponent {
                    print("🔄 DIAGNOSTIC: Trying fallback AudioUnit: \(fallback.name)")
                    
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
                            print("❌ DIAGNOSTIC: Fallback AudioUnit instantiation failed")
                            completion(track_index_t(999))
                            return
                        }
                        
                        DispatchQueue.main.async {
                            let trackIndex = self.nextTrackIndex()
                            self.performanceConnect(avAudioUnit: avAudioUnit, trackIndex: trackIndex)
                            self.setTrackAudioUnit(trackIndex: trackIndex, avAudioUnit: avAudioUnit)
                            print("✅ DIAGNOSTIC: Fallback AudioUnit connected: \(fallback.name)")
                            completion(trackIndex)
                        }
                    }
                } else {
                    print("❌ DIAGNOSTIC: No suitable AudioUnit found (no music devices available)")
                    completion(track_index_t(999))
                }
            }
        }
    }
    
    func removeTrack(trackIndex: track_index_t) -> Bool {
        print("[DEBUG] Track removal disabled in minimal mode")
        return false
    }
}