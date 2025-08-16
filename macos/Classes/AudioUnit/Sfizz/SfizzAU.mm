#import "SfizzAU.h"
#include "sfizz.hpp"
#include <atomic>
#include <memory>

@interface SfizzAU ()
{
    // Initialize _isInitialized in the constructor
    std::atomic_bool _isInitialized;

    std::unique_ptr<sfz::Sfizz> _sfz;
    AVAudioFormat *_format;
    std::atomic_bool _isInitialized;
}

@property AUAudioUnitBus *outputBus;
@property AUAudioUnitBusArray *outputBusArray;

@end

@implementation SfizzAU

+ (AudioComponentDescription)componentDescription {
    AudioComponentDescription desc;
    desc.componentType = kAudioUnitType_MusicDevice;
    desc.componentSubType = 'sfz ';
    desc.componentManufacturer = 'sfz ';
    desc.componentFlags = 0;
    desc.componentFlagsMask = 0;
    return desc;
}

+ (void)registerAU {
    [AUAudioUnit registerSubclass:SfizzAU.self
        asComponentDescription:[self componentDescription]
        name:@"Sfizz"
        version:UINT32_MAX];
}

- (instancetype)initWithComponentDescription:(AudioComponentDescription)componentDescription
                                   options:(AudioComponentInstantiationOptions)options
                                     error:(NSError **)outError {
    self = [super initWithComponentDescription:componentDescription options:options error:outError];
    
    if (self == nil) {
        return nil;
    }
    
    // Initialize with default format
    _format = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:44100 channels:2];
    
    // Create output bus
    _outputBus = [[AUAudioUnitBus alloc] initWithFormat:_format error:nil];
    _outputBusArray = [[AUAudioUnitBusArray alloc] initWithAudioUnit:self
                                                          busType:AUAudioUnitBusTypeOutput
                                                           busses:@[_outputBus]];
    
    // Initialize SFZ engine
    _sfz = std::make_unique<sfz::Sfizz>();
    _sfz->setSamplesPerBlock(512);
    _sfz->setSampleRate(_format.sampleRate);
    _isInitialized = true;
    
    // Set up render block
    self.maximumFramesToRender = 512;
    
    return self;
}

- (BOOL)loadSfzFile:(const char *)sfzPath tuningPath:(const char *)tuningPath {
    if (!_isInitialized) {
        return NO;
    }
    
    bool success = _sfz->loadSfzFile(sfzPath);
    if (success && tuningPath && strlen(tuningPath) > 0) {
        _sfz->loadScalaFile(tuningPath);
    }
    
    return success;
}

- (BOOL)loadSfzString:(const char *)sampleRoot sfzString:(const char *)sfzString tuningString:(const char *)tuningString {
    if (!_isInitialized) {
        return NO;
    }
    
    bool success = _sfz->loadSfzString(sfzString, sampleRoot);
    if (success && tuningString && strlen(tuningString) > 0) {
        _sfz->loadScalaString(tuningString);
    }
    
    return success;
}

- (void)setSampleRate:(double)sampleRate {
    if (_format.sampleRate != sampleRate) {
        _format = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:sampleRate channels:2];
        _sfz->setSampleRate(sampleRate);
    }
}

- (BOOL)allocateRenderResourcesAndReturnError:(NSError **)outError {
    if (![super allocateRenderResourcesAndReturnError:outError]) {
        return NO;
    }
    
    _sfz->setSamplesPerBlock((unsigned)self.maximumFramesToRender);
    _sfz->setSampleRate(self.outputBus.format.sampleRate);
    
    return YES;
}

- (void)deallocateRenderResources {
    [super deallocateRenderResources];
}

- (AUInternalRenderBlock)internalRenderBlock {
    __block std::unique_ptr<sfz::Sfizz>& sfz = _sfz;
    
    return ^AUAudioUnitStatus(
        AudioUnitRenderActionFlags *actionFlags,
        const AudioTimeStamp *timestamp,
        AVAudioFrameCount frameCount,
        NSInteger outputBusNumber,
        AudioBufferList *outputData,
        const AURenderEvent *realtimeEventListHead,
        AURenderPullInputBlock pullInputBlock) {
        
        if (!sfz) {
            return noErr;
        }
        
        // Process MIDI events
        AURenderEvent *event = (AURenderEvent *)realtimeEventListHead;
        while (event != NULL) {
            if (event->head.eventType == AURenderEventMIDI) {
                AUMIDIEvent midiEvent = event->MIDI;
                const uint8_t *midiData = midiEvent.data;
                
                if (midiEvent.length == 3) {
                    // Note on/off
                    uint8_t status = midiData[0] & 0xF0;
                    uint8_t data1 = midiData[1];
                    uint8_t data2 = midiData[2];
                    
                    if (status == 0x90) {
                        // Note on
                        sfz->noteOn(0, data1, data2);
                    } else if (status == 0x80) {
                        // Note off
                        sfz->noteOff(0, data1, data2);
                    } else if (status == 0xB0) {
                        // CC
                        sfz->cc(0, data1, data2);
                    } else if (status == 0xE0) {
                        // Pitch bend
                        int value = (data2 << 7) | data1;
                        float bend = (value - 8192.0f) / 8192.0f;
                        sfz->pitchWheel(0, bend);
                    }
                } else if (midiEvent.length == 2) {
                    // Program change
                    uint8_t status = midiData[0] & 0xF0;
                    if (status == 0xC0) {
                        sfz->programChange(0, midiData[1]);
                    }
                }
            }
            
            event = (AURenderEvent *)event->head.next;
        }
        
        // Get output buffers
        float *outputL = (float *)outputData->mBuffers[0].mData;
        float *outputR = outputData->mNumberBuffers > 1 ? (float *)outputData->mBuffers[1].mData : outputL;
        
        // Clear output
        memset(outputL, 0, frameCount * sizeof(float));
        if (outputR != outputL) {
            memset(outputR, 0, frameCount * sizeof(float));
        }
        
        // Render audio
        float* outputs[2] = {outputL, outputR};
        sfz->renderBlock(outputs, frameCount, outputData->mNumberBuffers);
        
        return noErr;
    };
}

- (NSArray<AUAudioUnitPreset *> *)factoryPresets {
    return @[];
}

- (void)selectPreset:(AUAudioUnitPreset *)preset {
    // Handle preset selection if needed
}

@end
