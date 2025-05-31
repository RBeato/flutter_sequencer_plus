import AVFoundation
import AudioToolbox

public class AudioUnitUtils {
    public static let filterClosure: (AVAudioUnitComponent) -> Bool = {
        let blacklist = ["AUNewPitch", "AURoundTripAAC", "AUNetSend"]
        let name = $0.name
        return !blacklist.contains($0.name)
    }
    
    public static func getAudioUnitId(_ component: AVAudioUnitComponent) -> String {
        return "\(component.manufacturerName).\(component.name)"
    }
    
    public static func loadAudioUnits(completion: @escaping ([AVAudioUnitComponent]) -> Void) {
        DispatchQueue.global(qos: .default).async {
            let allComponentsDescription = AudioComponentDescription(componentType: kAudioUnitType_MusicDevice,
                                                        componentSubType: 0,
                                                        componentManufacturer: 0,
                                                        componentFlags: 0,
                                                        componentFlagsMask: 0)

            let components =
                AVAudioUnitComponentManager.shared()
                    .components(matching: allComponentsDescription)
                    .filter(self.filterClosure)

            DispatchQueue.main.async {
                completion(components)
            }
        }
    }
    
    static func instantiate(description: AudioComponentDescription, sampleRate: Double, options: AudioComponentInstantiationOptions, completion: @escaping (AVAudioUnit) -> Void) {
        AVAudioUnit.instantiate(with: description, options: options) { avAudioUnit, error in
            guard error == nil, let avAudioUnit = avAudioUnit else { 
                print("Error instantiating AudioUnit: \(error?.localizedDescription ?? "unknown error")")
                return 
            }
    
            completion(avAudioUnit)
        }
    }
    
    static func setSampleRate(avAudioUnit: AVAudioUnit, sampleRate: Double) {
        var _sampleRate = sampleRate
        let size = UInt32(MemoryLayout.size(ofValue: _sampleRate))
        
        AudioUnitSetProperty(
            avAudioUnit.audioUnit,
            AudioUnitPropertyID(kAudioUnitProperty_SampleRate),
            AudioUnitScope(kAudioUnitScope_Output),
            0,
            &_sampleRate,
            size)
    }
    
    static func destroy(avAudioUnit: AVAudioUnit) {
        AudioUnitUninitialize(avAudioUnit.audioUnit)
    }
}
