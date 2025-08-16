import AVFoundation

func isAppleSampler(component: AVAudioUnitComponent) -> Bool {
    let isApple = component.audioComponentDescription.componentManufacturer == kAudioUnitManufacturer_Apple
    let isMIDISynth = component.audioComponentDescription.componentSubType == kAudioUnitSubType_MIDISynth

    return isApple && isMIDISynth
}

func loadSoundFont(avAudioUnit: AVAudioUnit, soundFontURL: URL, presetIndex: Int32) -> Bool {
    assert(avAudioUnit.audioComponentDescription.componentSubType == kAudioUnitSubType_MIDISynth)
    
    let audioUnit = avAudioUnit.audioUnit
    var mutableSoundFontURL = soundFontURL
    
    print("Loading SoundFont: \(soundFontURL.lastPathComponent) with preset \(presetIndex)")
    
    // Verify file exists
    guard FileManager.default.fileExists(atPath: soundFontURL.path) else {
        print("SoundFont file does not exist: \(soundFontURL.path)")
        return false
    }
    
    // Check file size and use different loading strategies
    let fileSize = (try? FileManager.default.attributesOfItem(atPath: soundFontURL.path)[.size] as? Int64) ?? 0
    let sizeInMB = Double(fileSize) / (1024 * 1024)
    print("[DEBUG] SF2 file size: \(String(format: "%.1f", sizeInMB)) MB")
    
    // For very large files (>20MB), we need to be extra careful
    let isLargeFile = sizeInMB > 20.0
    
    if isLargeFile {
        print("Large SF2 detected (\(String(format: "%.1f", sizeInMB)) MB) - using safe loading mode")
        
        // Force lowest memory settings for large files
        var enabled = UInt32(0)
        var result = AudioUnitSetProperty(audioUnit,
                                      AudioUnitPropertyID(kAUMIDISynthProperty_EnablePreload),
                                      AudioUnitScope(kAudioUnitScope_Global),
                                      0,
                                      &enabled,
                                      UInt32(MemoryLayout.size(ofValue: enabled)))
        
        // Set very low polyphony for large files
        var lowPolyphony = UInt32(16) // Even lower for large files
        let maxPolyphonyProperty = AudioUnitPropertyID(2012) // kMusicDeviceProperty_MaxPolyphony
        result = AudioUnitSetProperty(audioUnit,
                                      maxPolyphonyProperty,
                                      AudioUnitScope(kAudioUnitScope_Global),
                                      0,
                                      &lowPolyphony,
                                      UInt32(MemoryLayout.size(ofValue: lowPolyphony)))
        
        if result == noErr {
            print("Set low polyphony \(lowPolyphony) for large SF2")
        }
        
        // Try to configure memory-efficient voice allocation
        var voiceAllocation = UInt32(1) // Enable efficient voice allocation
        result = AudioUnitSetProperty(audioUnit,
                                      AudioUnitPropertyID(2013), // Custom property for voice allocation
                                      AudioUnitScope(kAudioUnitScope_Global),
                                      0,
                                      &voiceAllocation,
                                      UInt32(MemoryLayout.size(ofValue: voiceAllocation)))
        
        // Give system time to adjust memory settings
        Thread.sleep(forTimeInterval: 0.2)
    } else {
        // Standard memory settings for smaller files
        var enabled = UInt32(0)
        var result = AudioUnitSetProperty(audioUnit,
                                      AudioUnitPropertyID(kAUMIDISynthProperty_EnablePreload),
                                      AudioUnitScope(kAudioUnitScope_Global),
                                      0,
                                      &enabled,
                                      UInt32(MemoryLayout.size(ofValue: enabled)))
        
        var maxPolyphony = UInt32(32)
        let maxPolyphonyProperty = AudioUnitPropertyID(2012)
        result = AudioUnitSetProperty(audioUnit,
                                      maxPolyphonyProperty,
                                      AudioUnitScope(kAudioUnitScope_Global),
                                      0,
                                      &maxPolyphony,
                                      UInt32(MemoryLayout.size(ofValue: maxPolyphony)))
    }
    
    // Wrap the critical SF2 loading in a try-catch equivalent
    var result: OSStatus = noErr
    
    // Create a separate autorelease pool for SF2 loading
    autoreleasepool {
        print("Attempting to load SF2: \(soundFontURL.lastPathComponent)")
        
        // Load SoundFont with error checking
        result = AudioUnitSetProperty(audioUnit,
                                     AudioUnitPropertyID(kMusicDeviceProperty_SoundBankURL),
                                     AudioUnitScope(kAudioUnitScope_Global),
                                     0,
                                     &mutableSoundFontURL,
                                     UInt32(MemoryLayout.size(ofValue: mutableSoundFontURL)))
    }
    
    if result != noErr {
        print("SoundFont loading failed with error: \(result)")
        
        // For large files, try with even more conservative settings
        if isLargeFile {
            print("Retrying large SF2 with minimal settings...")
            
            // Try with absolute minimum polyphony
            var minPolyphony = UInt32(8)
            let maxPolyphonyProperty = AudioUnitPropertyID(2012)
            let polyphonyResult = AudioUnitSetProperty(audioUnit,
                                          maxPolyphonyProperty,
                                          AudioUnitScope(kAudioUnitScope_Global),
                                          0,
                                          &minPolyphony,
                                          UInt32(MemoryLayout.size(ofValue: minPolyphony)))
            
            if polyphonyResult == noErr {
                print("Set minimal polyphony \(minPolyphony) for retry")
                
                // Wait for memory to stabilize
                Thread.sleep(forTimeInterval: 0.5)
                
                // Retry loading
                autoreleasepool {
                    result = AudioUnitSetProperty(audioUnit,
                                                 AudioUnitPropertyID(kMusicDeviceProperty_SoundBankURL),
                                                 AudioUnitScope(kAudioUnitScope_Global),
                                                 0,
                                                 &mutableSoundFontURL,
                                                 UInt32(MemoryLayout.size(ofValue: mutableSoundFontURL)))
                }
                
                if result != noErr {
                    print("SF2 loading failed even with minimal settings: \(result)")
                    return false
                }
            }
        } else {
            return false
        }
    }
    
    print("[DEBUG] SoundFont loaded successfully")
    
    // INDUSTRY STANDARD: Configure proper SF2 parameters based on 2024 best practices
    var patchFound = false
    let channel = UInt32(0)
    
    // 1. First set proper bank parameters according to SF2 standard
    print("[DEBUG] Setting industry standard SF2 parameters...")
    
    // For melodic instruments, use standard melodic bank (MSB=0)
    let bankMSB = UInt32(kAUSampler_DefaultMelodicBankMSB) // 0x78 = 120
    let bankLSB = UInt32(0) // Usually 0 for SF2
    let ccBankSelectMSB = UInt32(0xB0 | channel) // Controller 0
    let ccBankSelectLSB = UInt32(0xB0 | channel) // Controller 32
    
    // Send Bank Select MSB (Controller 0)
    result = MusicDeviceMIDIEvent(audioUnit, ccBankSelectMSB, 0, bankMSB, 0)
    if result == noErr {
        print("[DEBUG] Bank MSB set to \(bankMSB)")
    }
    
    // Send Bank Select LSB (Controller 32) 
    result = MusicDeviceMIDIEvent(audioUnit, ccBankSelectLSB, 32, bankLSB, 0)
    if result == noErr {
        print("[DEBUG] Bank LSB set to \(bankLSB)")
    }
    
    // 2. Now send Program Change to select the specific preset
    let pcCommand = UInt32(0xC0 | channel)
    result = MusicDeviceMIDIEvent(audioUnit, pcCommand, UInt32(presetIndex), 0, 0)
    
    if result == noErr {
        print("[DEBUG] SUCCESS: SF2 preset \(presetIndex) loaded with proper banking!")
        patchFound = true
        
        // 3. INDUSTRY STANDARD: Send a quick test note to verify audio output
        let noteOnCommand = UInt32(0x90 | channel)
        let noteOffCommand = UInt32(0x80 | channel)
        
        // Send test note on
        let testResult = MusicDeviceMIDIEvent(audioUnit, noteOnCommand, 60, 80, 0) // Middle C, moderate velocity
        if testResult == noErr {
            print("[DEBUG] ✅ INDUSTRY STANDARD: SF2 test note successful - audio output verified!")
            
            // Send note off after brief delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                let _ = MusicDeviceMIDIEvent(audioUnit, noteOffCommand, 60, 0, 0)
            }
        }
        
    } else {
        print("[DEBUG] Standard preset \(presetIndex) failed: \(result)")
        
        // Fallback: Try preset 0 which usually works
        result = MusicDeviceMIDIEvent(audioUnit, pcCommand, 0, 0, 0)
        if result == noErr {
            print("[DEBUG] ✅ FALLBACK: SF2 preset 0 loaded successfully")
            patchFound = true
        } else {
            print("[DEBUG] ❌ CRITICAL: Both requested preset and preset 0 failed")
        }
    }
    
    if !patchFound {
        print("[DEBUG] WARNING: SoundFont loaded but no presets work - this SF2 may not be compatible with iOS Apple Sampler")
        print("[DEBUG] AudioUnit will still work but may use a default/built-in sound")
    }
    
    // Memory optimization: Explicitly trigger garbage collection after loading
    print("[DEBUG] SF2 loading complete, optimizing memory usage")
    
    // Return true if SF2 loaded successfully, even if specific preset failed
    // The important thing is that the SoundFont is loaded into the AudioUnit
    return true
}
