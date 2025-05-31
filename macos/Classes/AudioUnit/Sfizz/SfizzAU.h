#import <AudioToolbox/AudioToolbox.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreAudioKit/AudioUnitViewController.h>

NS_ASSUME_NONNULL_BEGIN

@interface SfizzAU : AUAudioUnit

@property (nonatomic, readonly) AUAudioUnitBus *outputBus;
@property (nonatomic, readonly) AUAudioUnitBusArray *outputBusArray;

+ (AudioComponentDescription)componentDescription;
+ (void)registerAU;

- (BOOL)loadSfzFile:(const char *)sfzPath tuningPath:(const char *)tuningPath;
- (BOOL)loadSfzString:(const char *)sampleRoot sfzString:(const char *)sfzString tuningString:(const char *)tuningString;
- (void)setSampleRate:(double)sampleRate;
- (void)setMaximumFramesToRender:(AUAudioFrameCount)maximumFramesToRender;
- (BOOL)allocateRenderResourcesAndReturnError:(NSError **)outError;
- (void)deallocateRenderResources;
- (AUInternalRenderBlock)internalRenderBlock;

@end

NS_ASSUME_NONNULL_END
