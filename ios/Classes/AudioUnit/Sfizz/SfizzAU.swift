/*
See LICENSE folder for this sample’s licensing information.

Abstract:
An AUAudioUnit subclass implementing a low-pass filter with resonance.
*/

import Foundation
import AudioToolbox
import AVFoundation
import CoreAudioKit


public class SfizzAU: AUAudioUnit {

    private let kernelAdapter: SfizzDSPKernelAdapter

    lazy private var inputBusArray: AUAudioUnitBusArray = {
        AUAudioUnitBusArray(audioUnit: self,
                            busType: .input,
                            busses: [sfizz_adapter_get_input_bus(kernelAdapter).pointee])
    }()

    lazy private var outputBusArray: AUAudioUnitBusArray = {
        AUAudioUnitBusArray(audioUnit: self,
                            busType: .output,
                            busses: [sfizz_adapter_get_output_bus(kernelAdapter).pointee])
    }()

    /// The filter's input busses
    public override var inputBusses: AUAudioUnitBusArray {
        return inputBusArray
    }

    /// The filter's output busses
    public override var outputBusses: AUAudioUnitBusArray {
        return outputBusArray
    }

    public override init(componentDescription: AudioComponentDescription,
                         options: AudioComponentInstantiationOptions = []) throws {

        // Create adapter to communicate to underlying C++ DSP code
        kernelAdapter = createSfizzDSPKernelAdapter()

        // Init super class
        try super.init(componentDescription: componentDescription, options: options)
    }

    public override var maximumFramesToRender: AUAudioFrameCount {
        get {
            return sfizz_adapter_get_maximum_frames(kernelAdapter)
        }
        set {
            if !renderResourcesAllocated {
                sfizz_adapter_set_maximum_frames(kernelAdapter, newValue)
            }
        }
    }

    public override func allocateRenderResources() throws {
        let inputBus = sfizz_adapter_get_input_bus(kernelAdapter).pointee
        let outputBus = sfizz_adapter_get_output_bus(kernelAdapter).pointee
        if outputBus.format.channelCount != inputBus.format.channelCount {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(kAudioUnitErr_FailedInitialization), userInfo: nil)
        }
        try super.allocateRenderResources()
        sfizz_adapter_allocate_render_resources(kernelAdapter)
    }

    public override func deallocateRenderResources() {
        super.deallocateRenderResources()
        sfizz_adapter_deallocate_render_resources(kernelAdapter)
    }

    public override var internalRenderBlock: AUInternalRenderBlock {
        return sfizz_adapter_get_internal_render_block(kernelAdapter)
    }

    // Boolean indicating that this AU can process the input audio in-place
    // in the input buffer, without requiring a separate output buffer.
    public override var canProcessInPlace: Bool {
        return true
    }
    
    public func loadSfzFile(path: UnsafePointer<CChar>, tuningPath: UnsafePointer<CChar>) -> Bool {
        return sfizz_adapter_load_sfz_file(kernelAdapter, path, tuningPath)
    }
    
    public func loadSfzString(sampleRoot: UnsafePointer<CChar>, sfzString: UnsafePointer<CChar>, tuningString: UnsafePointer<CChar>) -> Bool {
        return sfizz_adapter_load_sfz_string(kernelAdapter, sampleRoot, sfzString, tuningString)
    }
    
    public static var componentDescription: AudioComponentDescription = {
        
        // Ensure that AudioUnit type, subtype, and manufacturer match the extension's Info.plist values
        var componentDescription = AudioComponentDescription()
        componentDescription.componentType = kAudioUnitType_MusicDevice
        componentDescription.componentSubType = 0x7366697a /*'sfizz'*/
        componentDescription.componentManufacturer = 0x6d706673 /*'mpfs'*/
        componentDescription.componentFlags = 0
        componentDescription.componentFlagsMask = 0

        return componentDescription
    }()
    
    public static var componentName = "FlutterSequencerSfizz"
    
    public static func registerAU() -> Void {
        AUAudioUnit.registerSubclass(SfizzAU.self,
                                     as: componentDescription,
                                     name: componentName,
                                     version: UInt32.max)
    }
}
