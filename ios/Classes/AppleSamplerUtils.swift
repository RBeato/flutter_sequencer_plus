import AVFoundation

func isAppleSampler(component: AVAudioUnitComponent) -> Bool {
    let isApple = component.audioComponentDescription.componentManufacturer == kAudioUnitManufacturer_Apple
    let isMIDISynth = component.audioComponentDescription.componentSubType == kAudioUnitSubType_MIDISynth

    return isApple && isMIDISynth
}

func loadSoundFont(avAudioUnit: AVAudioUnit, soundFontURL: URL, presetIndex: Int32) {
    assert(avAudioUnit.audioComponentDescription.componentSubType == kAudioUnitSubType_MIDISynth)

    let audioUnit = avAudioUnit.audioUnit

    // Validate URL exists and is accessible
    guard FileManager.default.fileExists(atPath: soundFontURL.path) else {
        print("SoundFont file does not exist at path: \(soundFontURL.path)")
        return
    }

    // CRITICAL FIX: Convert Swift URL to CFURL for AudioToolbox compatibility
    // AudioUnitSetProperty requires a CFURLRef pointer, not a Swift URL struct
    // This prevents the _TtCs12_SwiftObject doesNotRecognizeSelector crash
    // We must use withUnsafePointer to pass the CFURL reference correctly
    let cfURL = soundFontURL as CFURL

    // Load SoundFont with error handling using proper CFURL pointer passing
    var result: OSStatus = noErr
    withUnsafePointer(to: cfURL) { cfURLPointer in
        result = AudioUnitSetProperty(audioUnit,
                                     AudioUnitPropertyID(kMusicDeviceProperty_SoundBankURL),
                                     AudioUnitScope(kAudioUnitScope_Global),
                                     0,
                                     cfURLPointer,
                                     UInt32(MemoryLayout<CFURL>.size))
    }

    guard result == noErr else {
        print("SoundFont could not be loaded, AudioUnitSetProperty failed with error: \(result)")
        return
    }

    var enabled = UInt32(1)
    
    // Enable preload
    result = AudioUnitSetProperty(audioUnit,
                                  AudioUnitPropertyID(kAUMIDISynthProperty_EnablePreload),
                                  AudioUnitScope(kAudioUnitScope_Global),
                                  0,
                                  &enabled,
                                  UInt32(MemoryLayout.size(ofValue: enabled)))
    guard result == noErr else {
        print("Preload could not be enabled, error: \(result)")
        return
    }
    
    // Send program change command for patch to preload - handle failure gracefully
    let channel = UInt32(0)
    let pcCommand = UInt32(0xC0 | channel)
    let patch1 = UInt32(presetIndex)
    result = MusicDeviceMIDIEvent(audioUnit, pcCommand, patch1, 0, 0)
    if result != noErr {
        // Try preset 0 as fallback
        let _ = MusicDeviceMIDIEvent(audioUnit, pcCommand, 0, 0, 0)
    }
    
    // Disable preload
    enabled = UInt32(0)
    result = AudioUnitSetProperty(audioUnit,
                                  AudioUnitPropertyID(kAUMIDISynthProperty_EnablePreload),
                                  AudioUnitScope(kAudioUnitScope_Global),
                                  0,
                                  &enabled,
                                  UInt32(MemoryLayout.size(ofValue: enabled)))

    if result != noErr {
        print("Warning: Preload could not be disabled, error: \(result)")
    }

    // Final program change - try requested preset, fall back to 0 if needed
    result = MusicDeviceMIDIEvent(audioUnit, pcCommand, patch1, 0, 0)
    if result != noErr {
        let _ = MusicDeviceMIDIEvent(audioUnit, pcCommand, 0, 0, 0)
    }
}