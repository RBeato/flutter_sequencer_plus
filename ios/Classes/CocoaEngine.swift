import Foundation
import AVFoundation
import Flutter

// Toggle Swift-side debug logging: set to true to enable, false to disable
let SEQ_SWIFT_DEBUG = false

func seqLog(_ message: String) {
    if SEQ_SWIFT_DEBUG {
        print("[SEQ-Swift] \(message)")
    }
}

/// High-performance iOS audio engine using AVAudioEngine + native C++ scheduler.
/// Architecture matches Android: all event scheduling happens in C++ via render callbacks.
/// Expected CPU: 3-5% for 8-track drum machine (down from 6-25% with old approach).
public class CocoaEngine {
    var scheduler: UnsafeMutableRawPointer!

    private let engine = AVAudioEngine()
    private var mixer: AVAudioUnit?
    public let outputFormat: AVAudioFormat!
    private let registrar: FlutterPluginRegistrar!

    // Thread-safe audio unit tracking
    private var unsafeAvAudioUnits: [track_index_t: AVAudioUnit] = [:]
    private let audioUnitsQueue = DispatchQueue(label: "com.flutter_sequencer.audiounits", attributes: .concurrent)
    private var nextTrackId: track_index_t = 0
    private let trackIdQueue = DispatchQueue(label: "com.flutter_sequencer.trackid")

    init(sampleRateCallbackPort: Dart_Port, registrar: FlutterPluginRegistrar) {
        self.registrar = registrar
        seqLog("CocoaEngine.init: starting")

        // Configure audio session for sequencing (larger buffer = less CPU)
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setPreferredIOBufferDuration(0.012)
            try session.setPreferredSampleRate(44100)
            try session.setActive(true)
            seqLog("AudioSession: sampleRate=\(session.sampleRate), ioBuffer=\(session.ioBufferDuration)s")
        } catch {
            seqLog("AudioSession: setup error: \(error)")
        }

        outputFormat = engine.outputNode.outputFormat(forBus: 0)
        seqLog("OutputFormat: sampleRate=\(outputFormat.sampleRate), channels=\(outputFormat.channelCount)")
        self.scheduler = nil
        self.mixer = nil

        SfizzAU.registerAU()

        initMixer(sampleRateCallbackPort: sampleRateCallbackPort)
    }

    deinit {
        if engine.isRunning {
            engine.stop()
        }
        if scheduler != nil {
            DestroyScheduler(scheduler)
        }
    }

    // MARK: - Mixer & Scheduler Initialization

    /// Creates a MultiChannelMixer AudioUnit, connects it to the output,
    /// then creates the C++ CocoaScheduler and callbacks to Dart with the sample rate.
    private func initMixer(sampleRateCallbackPort: Dart_Port) {
        let componentDescription = AudioComponentDescription(
            componentType: kAudioUnitType_Mixer,
            componentSubType: kAudioUnitSubType_MultiChannelMixer,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )

        seqLog("initMixer: instantiating MultiChannelMixer...")
        AVAudioUnit.instantiate(with: componentDescription, options: []) { [weak self] avAudioUnit, err in
            guard let self = self else { return }

            guard let mixerUnit = avAudioUnit, err == nil else {
                seqLog("initMixer: FAILED to create mixer (err=\(String(describing: err))). Fallback mode.")
                self.startEngineAndCallback(sampleRateCallbackPort)
                return
            }

            self.mixer = mixerUnit
            seqLog("initMixer: mixer created, audioUnit=\(mixerUnit.audioUnit)")

            let hardwareFormat = self.engine.outputNode.outputFormat(forBus: 0)
            self.engine.attach(mixerUnit)
            self.engine.connect(mixerUnit, to: self.engine.outputNode, format: hardwareFormat)

            var busCount: UInt32 = 64
            AudioUnitSetProperty(
                mixerUnit.audioUnit,
                kAudioUnitProperty_ElementCount,
                kAudioUnitScope_Input,
                0,
                &busCount,
                UInt32(MemoryLayout<UInt32>.size)
            )

            let sampleRate = Double(self.outputFormat.sampleRate)
            self.scheduler = InitScheduler(mixerUnit.audioUnit, sampleRate)
            seqLog("initMixer: scheduler created at \(self.scheduler!), sampleRate=\(sampleRate)")

            self.startEngineAndCallback(sampleRateCallbackPort)
        }
    }

    private func startEngineAndCallback(_ sampleRateCallbackPort: Dart_Port) {
        do {
            engine.prepare()
            try engine.start()
            seqLog("startEngine: AVAudioEngine started, isRunning=\(engine.isRunning)")
        } catch {
            seqLog("startEngine: AVAudioEngine start error: \(error)")
        }

        seqLog("startEngine: calling back to Dart with sampleRate=\(Int32(outputFormat.sampleRate))")
        callbackToDartInt32(sampleRateCallbackPort, Int32(outputFormat.sampleRate))
    }

    // MARK: - Track Creation

    func addTrackSf2(sf2Path: String, isAsset: Bool, presetIndex: Int32, completion: @escaping (track_index_t) -> Void) {
        AudioUnitUtils.loadAudioUnits { [weak self] avAudioUnitComponents in
            guard let self = self else {
                completion(track_index_t(999))
                return
            }

            guard let appleSamplerComponent = avAudioUnitComponents.first(where: isAppleSampler) else {
                completion(track_index_t(999))
                return
            }

            // CRITICAL: Load in-process for real-time safety.
            // Out-of-process AUs use XPC, and MusicDeviceMIDIEvent on an XPC proxy
            // allocates memory - NOT real-time safe when called from render callbacks.
            // In-process AUs handle MusicDeviceMIDIEvent directly in the audio thread.
            AudioUnitUtils.instantiate(
                description: appleSamplerComponent.audioComponentDescription,
                sampleRate: Double(self.outputFormat.sampleRate),
                options: []
            ) { [weak self] (avAudioUnit: AVAudioUnit?) in
                guard let self = self, let avAudioUnit = avAudioUnit else {
                    completion(track_index_t(999))
                    return
                }

                if let normalizedPath = self.normalizePath(sf2Path, isAsset: isAsset) {
                    let url = URL(fileURLWithPath: normalizedPath)

                    DispatchQueue.global(qos: .userInitiated).async {
                        loadSoundFont(avAudioUnit: avAudioUnit, soundFontURL: url, presetIndex: presetIndex)

                        DispatchQueue.main.async {
                            let trackIndex = self.nextTrackIndex()
                            self.connectAndRegisterTrack(avAudioUnit: avAudioUnit, trackIndex: trackIndex)
                            completion(trackIndex)
                        }
                    }
                } else {
                    completion(track_index_t(999))
                }
            }
        }
    }

    func addTrackSfz(sfzPath: UnsafePointer<CChar>, tuningPath: UnsafePointer<CChar>, completion: @escaping (track_index_t) -> Void) {
        let sfizzAUDescription = SfizzAU.componentDescription

        AudioUnitUtils.instantiate(
            description: sfizzAUDescription,
            sampleRate: Double(outputFormat.sampleRate),
            options: []
        ) { [weak self] (avAudioUnit: AVAudioUnit?) in
            guard let self = self, let avAudioUnit = avAudioUnit else {
                completion(track_index_t(999))
                return
            }

            DispatchQueue.main.async {
                if let sfizzAU = avAudioUnit.auAudioUnit as? SfizzAU,
                   sfizzAU.loadSfzFile(path: sfzPath, tuningPath: tuningPath) {
                    let trackIndex = self.nextTrackIndex()
                    self.connectAndRegisterTrack(avAudioUnit: avAudioUnit, trackIndex: trackIndex)
                    completion(trackIndex)
                } else {
                    completion(track_index_t(999))
                }
            }
        }
    }

    func addTrackSfzString(sampleRoot: UnsafePointer<CChar>, sfzString: UnsafePointer<CChar>, tuningString: UnsafePointer<CChar>, completion: @escaping (track_index_t) -> Void) {
        let sfizzAUDescription = SfizzAU.componentDescription

        AudioUnitUtils.instantiate(
            description: sfizzAUDescription,
            sampleRate: Double(outputFormat.sampleRate),
            options: []
        ) { [weak self] (avAudioUnit: AVAudioUnit?) in
            guard let self = self, let avAudioUnit = avAudioUnit else {
                completion(track_index_t(999))
                return
            }

            DispatchQueue.main.async {
                if let sfizzAU = avAudioUnit.auAudioUnit as? SfizzAU,
                   sfizzAU.loadSfzString(sampleRoot: sampleRoot, sfzString: sfzString, tuningString: tuningString) {
                    let trackIndex = self.nextTrackIndex()
                    self.connectAndRegisterTrack(avAudioUnit: avAudioUnit, trackIndex: trackIndex)
                    completion(trackIndex)
                } else {
                    completion(track_index_t(999))
                }
            }
        }
    }

    func addTrackAudioUnit(audioUnitId: String, completion: @escaping (track_index_t) -> Void) {
        let isAppleDLS = audioUnitId.contains("Apple") || audioUnitId.contains("DLS") || audioUnitId.contains("dls")

        AudioUnitUtils.loadAudioUnits { [weak self] avAudioUnitComponents in
            guard let self = self else {
                completion(track_index_t(999))
                return
            }

            let targetComponent: AVAudioUnitComponent?
            if isAppleDLS {
                targetComponent = avAudioUnitComponents.first { component in
                    let desc = component.audioComponentDescription
                    return desc.componentManufacturer == kAudioUnitManufacturer_Apple &&
                           desc.componentType == kAudioUnitType_MusicDevice &&
                           desc.componentSubType == kAudioUnitSubType_MIDISynth
                }
            } else {
                targetComponent = avAudioUnitComponents.first { component in
                    component.name.lowercased().contains(audioUnitId.lowercased()) ||
                    component.manufacturerName.lowercased().contains(audioUnitId.lowercased())
                }
            }

            let componentToUse = targetComponent ?? avAudioUnitComponents.first { component in
                component.audioComponentDescription.componentType == kAudioUnitType_MusicDevice
            }

            guard let audioUnitComponent = componentToUse else {
                completion(track_index_t(999))
                return
            }

            AudioUnitUtils.instantiate(
                description: audioUnitComponent.audioComponentDescription,
                sampleRate: Double(self.outputFormat.sampleRate),
                options: []
            ) { [weak self] (avAudioUnit: AVAudioUnit?) in
                guard let self = self, let avAudioUnit = avAudioUnit else {
                    completion(track_index_t(999))
                    return
                }

                DispatchQueue.main.async {
                    let trackIndex = self.nextTrackIndex()
                    self.connectAndRegisterTrack(avAudioUnit: avAudioUnit, trackIndex: trackIndex)
                    completion(trackIndex)
                }
            }
        }
    }

    // MARK: - Track Connection & Registration

    /// Connects an AudioUnit to the mixer on the correct bus and registers it with the C++ scheduler.
    /// This is the critical path that enables native scheduling.
    private func connectAndRegisterTrack(avAudioUnit: AVAudioUnit, trackIndex: track_index_t) {
        seqLog("connectTrack: track \(trackIndex), AU=\(avAudioUnit.audioUnit)")
        self.engine.attach(avAudioUnit)

        let format = avAudioUnit.outputFormat(forBus: 0)
        seqLog("connectTrack: track \(trackIndex) format: sampleRate=\(format.sampleRate), ch=\(format.channelCount)")

        if let mixerUnit = self.mixer {
            self.engine.connect(avAudioUnit, to: mixerUnit, fromBus: 0, toBus: Int(trackIndex), format: format)
            seqLog("connectTrack: track \(trackIndex) -> mixer bus \(trackIndex)")
        } else {
            self.engine.connect(avAudioUnit, to: self.engine.mainMixerNode, format: format)
            seqLog("connectTrack: track \(trackIndex) -> mainMixer (NO custom mixer!)")
        }

        if let scheduler = self.scheduler {
            SchedulerSetTrackAudioUnit(scheduler, trackIndex, avAudioUnit.audioUnit)
            seqLog("connectTrack: track \(trackIndex) registered with scheduler")
        } else {
            seqLog("connectTrack: track \(trackIndex) - WARNING: scheduler is nil!")
        }

        updateAvAudioUnits(trackIndex: trackIndex, avAudioUnit: avAudioUnit)

        if !self.engine.isRunning {
            do {
                try self.engine.start()
                seqLog("connectTrack: restarted engine")
            } catch {
                seqLog("connectTrack: engine start error: \(error)")
            }
        }
    }

    // MARK: - Playback Control

    func play() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { self.play() }
            return
        }

        seqLog("play(): scheduler=\(String(describing: scheduler)), engineRunning=\(engine.isRunning)")
        if let scheduler = scheduler {
            SchedulerPlay(scheduler)
        } else {
            seqLog("play(): WARNING - scheduler is nil!")
        }

        if !engine.isRunning {
            do {
                engine.prepare()
                try engine.start()
                seqLog("play(): engine restarted")
            } catch {
                seqLog("play(): engine start error: \(error)")
            }
        }
    }

    func pause() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { self.pause() }
            return
        }

        seqLog("pause(): scheduler=\(String(describing: scheduler))")
        if let scheduler = scheduler {
            SchedulerPause(scheduler)
        }

        let audioUnits = audioUnitsQueue.sync { Array(self.unsafeAvAudioUnits.values) }
        seqLog("pause(): sending note-off to \(audioUnits.count) tracks")
        for audioUnit in audioUnits {
            for noteNumber: UInt32 in 0...127 {
                MusicDeviceMIDIEvent(audioUnit.audioUnit, 0x80, noteNumber, 0, 0)
            }
        }
    }

    func stop() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { self.stop() }
            return
        }

        seqLog("stop()")
        if let scheduler = scheduler {
            SchedulerPause(scheduler)
        }

        let audioUnits = audioUnitsQueue.sync { Array(self.unsafeAvAudioUnits.values) }
        for audioUnit in audioUnits {
            for noteNumber: UInt32 in 0...127 {
                MusicDeviceMIDIEvent(audioUnit.audioUnit, 0x80, noteNumber, 0, 0)
            }
        }
    }

    func getPosition() -> UInt32 {
        if let scheduler = scheduler {
            return SchedulerGetPosition(scheduler)
        }
        return 0
    }

    func removeTrack(trackIndex: track_index_t) -> Bool {
        if let scheduler = scheduler {
            SchedulerRemoveTrack(scheduler, trackIndex)
        }
        updateAvAudioUnits(trackIndex: trackIndex, avAudioUnit: nil)
        return true
    }

    // MARK: - Utilities

    private func updateAvAudioUnits(trackIndex: track_index_t, avAudioUnit: AVAudioUnit?) {
        audioUnitsQueue.async(flags: .barrier) {
            if let avAudioUnit = avAudioUnit {
                self.unsafeAvAudioUnits[trackIndex] = avAudioUnit
            } else {
                self.unsafeAvAudioUnits.removeValue(forKey: trackIndex)
            }
        }
    }

    private func nextTrackIndex() -> track_index_t {
        return trackIdQueue.sync {
            let trackIndex = nextTrackId
            nextTrackId += 1
            return trackIndex
        }
    }

    func normalizePath(_ path: String, isAsset: Bool) -> String? {
        if !isAsset {
            return path
        } else {
            let key = registrar.lookupKey(forAsset: path)
            return Bundle.main.path(forResource: key, ofType: nil)
        }
    }
}
