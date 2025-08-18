import AVFoundation

func isAppleSampler(component: AVAudioUnitComponent) -> Bool {
    let isApple = component.audioComponentDescription.componentManufacturer == kAudioUnitManufacturer_Apple
    let isMIDISynth = component.audioComponentDescription.componentSubType == kAudioUnitSubType_MIDISynth

    return isApple && isMIDISynth
}

func loadSoundFont(avAudioUnit: AVAudioUnit, soundFontURL: URL, presetIndex: Int32) {
    assert(avAudioUnit.audioComponentDescription.componentSubType == kAudioUnitSubType_MIDISynth)
    
    let audioUnit = avAudioUnit.audioUnit
    var mutableSoundFontURL = soundFontURL
    
    // Load SoundFont
    var result = AudioUnitSetProperty(audioUnit,
                                 AudioUnitPropertyID(kMusicDeviceProperty_SoundBankURL),
                                 AudioUnitScope(kAudioUnitScope_Global),
                                 0,
                                 &mutableSoundFontURL,
                                 UInt32(MemoryLayout.size(ofValue: mutableSoundFontURL)))
    assert(result == noErr, "SoundFont could not be loaded")

    var enabled = UInt32(1)
    
    // Enable preload
    result = AudioUnitSetProperty(audioUnit,
                                  AudioUnitPropertyID(kAUMIDISynthProperty_EnablePreload),
                                  AudioUnitScope(kAudioUnitScope_Global),
                                  0,
                                  &enabled,
                                  UInt32(MemoryLayout.size(ofValue: enabled)))
    assert(result == noErr, "Preload could not be enabled")
    
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

    assert(result == noErr, "Preload could not be disabled")

    // Final program change - try requested preset, fall back to 0 if needed
    result = MusicDeviceMIDIEvent(audioUnit, pcCommand, patch1, 0, 0)
    if result != noErr {
        let _ = MusicDeviceMIDIEvent(audioUnit, pcCommand, 0, 0, 0)
    }
}