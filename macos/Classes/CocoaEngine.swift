import Foundation
import AVFoundation
import FlutterMacOS

public class CocoaEngine {
    var scheduler: UnsafeMutableRawPointer!
    
    private let engine = AVAudioEngine()
    private var mixer: AVAudioUnit?
    private let outputFormat: AVAudioFormat!
    private let registrar: FlutterPluginRegistrar!

    // Swift Dictionary is not thread-safe, so this must be copied before access
    private var unsafeAvAudioUnits: [track_index_t: AVAudioUnit] = [:]
    
    public init(sampleRateCallbackPort: Dart_Port, registrar: FlutterPluginRegistrar) {
        outputFormat = engine.outputNode.outputFormat(forBus: 0)
        
        self.registrar = registrar

        initMixer {
            self.scheduler = InitScheduler(self.mixer!.audioUnit, self.outputFormat.sampleRate)
            
            // Register SFZ audio unit
            SfizzAU.registerAU()
            
            callbackToDartInt32(sampleRateCallbackPort, Int32(self.outputFormat.sampleRate))
        }
    }
    
    deinit {
        DestroyScheduler(scheduler)
    }
    
    func play() {
        do {
            try engine.start()
            SchedulerPlay(scheduler)
        } catch let error {
            print("AVAudioEngine start error: \(error)")
        }
    }
    
    func pause() {
        SchedulerPause(scheduler)
        engine.pause()
    }
    
    func addTrackSfz(sfzPath: UnsafePointer<CChar>, tuningPath: UnsafePointer<CChar>, completion: @escaping (track_index_t) -> Void) {
        AudioUnitUtils.instantiate(
            description: SfizzAU.componentDescription,
            sampleRate: self.outputFormat.sampleRate,
            options: AudioComponentInstantiationOptions.loadOutOfProcess
        ) { avAudioUnit in
            AudioUnitUtils.setSampleRate(avAudioUnit: avAudioUnit, sampleRate: self.outputFormat.sampleRate)
            let sfizzAU = avAudioUnit.auAudioUnit as! SfizzAU
            
            if (sfizzAU.loadSfzFile(path: sfzPath, tuningPath: tuningPath)) {
                let trackIndex = SchedulerAddTrack(self.scheduler)
                self.setTrackAudioUnit(trackIndex: trackIndex, avAudioUnit: avAudioUnit)
                completion(trackIndex)
            } else {
                completion(-1)
            }
        }
    }
    
    func addTrackSfzString(sampleRoot: UnsafePointer<CChar>, sfzString: UnsafePointer<CChar>, tuningString: UnsafePointer<CChar>, completion: @escaping (track_index_t) -> Void) {
        AudioUnitUtils.instantiate(
            description: SfizzAU.componentDescription,
            sampleRate: self.outputFormat.sampleRate,
            options: AudioComponentInstantiationOptions.loadOutOfProcess
        ) { avAudioUnit in
            AudioUnitUtils.setSampleRate(avAudioUnit: avAudioUnit, sampleRate: self.outputFormat.sampleRate)
            let sfizzAU = avAudioUnit.auAudioUnit as! SfizzAU
            
            if (sfizzAU.loadSfzString(sampleRoot: sampleRoot, sfzString: sfzString, tuningString: tuningString)) {
                let trackIndex = SchedulerAddTrack(self.scheduler)
                self.setTrackAudioUnit(trackIndex: trackIndex, avAudioUnit: avAudioUnit)
                completion(trackIndex)
            } else {
                completion(-1)
            }
        }
    }
    
    func addTrackSf2(sf2Path: String, isAsset: Bool, presetIndex: Int32, completion: @escaping (Int32) -> Void) {
        let trackIndex = SchedulerAddTrack(scheduler)
        
        if let normalizedPath = normalizePath(sf2Path, isAsset: isAsset) {
            // macOS implementation for SF2 instrument creation
            // This would use AVAudioUnitSampler or similar
            print("Loading SF2 from: \(normalizedPath)")
        }
        
        completion(trackIndex)
    }
    
    func addTrackAudioUnit(audioUnitId: String, completion: @escaping (Int32) -> Void) {
        let trackIndex = SchedulerAddTrack(self.scheduler)
        
        // macOS implementation for AudioUnit loading
        // Similar to iOS but may need adjustments for macOS AudioUnits
        
        completion(trackIndex)
    }
    
    func removeTrack(trackIndex: track_index_t) -> Bool {
        // Remove from scheduler
        let result = SchedulerRemoveTrack(scheduler, trackIndex)
        
        // Remove from audio engine
        if let audioUnit = unsafeAvAudioUnits[trackIndex] {
            audioUnit.removeTap(onBus: 0)
            engine.detach(audioUnit)
            
            var copy = unsafeAvAudioUnits
            copy.removeValue(forKey: trackIndex)
            unsafeAvAudioUnits = copy
        }
        
        return result
    }
    
    private func initMixer(completion: @escaping () -> Void) {
        let mixerDescription = AudioComponentDescription(componentType: kAudioUnitType_Mixer,
                                                      componentSubType: kAudioUnitSubType_MultiChannelMixer,
                                                      componentManufacturer: kAudioUnitManufacturer_Apple,
                                                      componentFlags: 0,
                                                      componentFlagsMask: 0)
        AVAudioUnit.instantiate(with: mixerDescription) { avAudioUnit, error in
            guard error == nil, let avAudioUnit = avAudioUnit else {
                print("Error creating mixer: \(error?.localizedDescription ?? "unknown error")")
                return
            }
            
            self.mixer = avAudioUnit
            self.engine.attach(avAudioUnit)
            self.engine.connect(avAudioUnit, to: self.engine.outputNode, format: self.outputFormat)
            
            do {
                try self.engine.start()
                completion()
            } catch {
                print("Error starting audio engine: \(error.localizedDescription)")
            }
        }
    }
    
    private func setTrackAudioUnit(trackIndex: track_index_t, avAudioUnit: AVAudioUnit) {
        // Remove existing audio unit if any
        if let existingAU = unsafeAvAudioUnits[trackIndex] {
            engine.disconnectNodeInput(existingAU)
            engine.detach(existingAU)
        }
        
        // Add new audio unit
        engine.attach(avAudioUnit)
        engine.connect(avAudioUnit, to: mixer!, format: outputFormat)
        
        // Store reference
        unsafeAvAudioUnits[trackIndex] = avAudioUnit
        
        // Update scheduler
        // TODO: Implement SchedulerSetAudioUnit functionality
        // SchedulerSetAudioUnit(scheduler, trackIndex, avAudioUnit.audioUnit)
    }
    
    private func normalizePath(_ path: String, isAsset: Bool) -> String? {
        if !isAsset {
            return path
        } else {
            let key = registrar.lookupKey(forAsset: path)
            return Bundle.main.path(forResource: key, ofType: nil)
        }
    }
}

// External C functions that need to be defined elsewhere
@_silgen_name("InitScheduler")
func InitScheduler(_ mixer: AudioUnit, _ sampleRate: Double) -> UnsafeMutableRawPointer!

@_silgen_name("DestroyScheduler")
func DestroyScheduler(_ scheduler: UnsafeMutableRawPointer!)

@_silgen_name("SchedulerAddTrack")
func SchedulerAddTrack(_ scheduler: UnsafeMutableRawPointer!) -> Int32

@_silgen_name("SchedulerRemoveTrack")
func SchedulerRemoveTrack(_ scheduler: UnsafeMutableRawPointer!, _ trackIndex: Int32) -> Bool

@_silgen_name("SchedulerPlay")
func SchedulerPlay(_ scheduler: UnsafeMutableRawPointer!)

@_silgen_name("SchedulerPause")
func SchedulerPause(_ scheduler: UnsafeMutableRawPointer!)

@_silgen_name("SchedulerGetPosition")
func SchedulerGetPosition(_ scheduler: UnsafeMutableRawPointer!) -> UInt32

@_silgen_name("SchedulerGetTrackVolume")
func SchedulerGetTrackVolume(_ scheduler: UnsafeMutableRawPointer!, _ trackIndex: Int32) -> Float32

@_silgen_name("SchedulerGetLastRenderTimeUs")
func SchedulerGetLastRenderTimeUs(_ scheduler: UnsafeMutableRawPointer!) -> UInt64

@_silgen_name("SchedulerGetBufferAvailableCount")
func SchedulerGetBufferAvailableCount(_ scheduler: UnsafeMutableRawPointer!, _ trackIndex: Int32) -> UInt32

@_silgen_name("SchedulerHandleEventsNow")
func SchedulerHandleEventsNow(_ scheduler: UnsafeMutableRawPointer!, _ trackIndex: Int32, _ events: UnsafePointer<SchedulerEvent>!, _ eventsCount: UInt32)

@_silgen_name("SchedulerAddEvents")
func SchedulerAddEvents(_ scheduler: UnsafeMutableRawPointer!, _ trackIndex: Int32, _ events: UnsafePointer<SchedulerEvent>!, _ eventsCount: UInt32) -> UInt32

@_silgen_name("SchedulerClearEvents")
func SchedulerClearEvents(_ scheduler: UnsafeMutableRawPointer!, _ trackIndex: Int32, _ fromFrame: UInt32)

@_silgen_name("SchedulerResetTrack")
func SchedulerResetTrack(_ scheduler: UnsafeMutableRawPointer!, _ trackIndex: Int32)

// track_index_t is defined in CommonTypes.h
