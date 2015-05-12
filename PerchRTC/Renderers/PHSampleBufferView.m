//
//  PHVideoSampleView.m
//  PerchRTC
//
//  Created by Christopher Eagleston on 2/6/2014.
//  Copyright (c) 2014 Perch Communications. All rights reserved.
//

#import "PHSampleBufferView.h"
#import <AVFoundation/AVFoundation.h>

#if defined(__IPHONE_8_0) && __IPHONE_OS_VERSION_MAX_ALLOWED >= __IPHONE_8_0

#elif defined(__IPHONE_7_0) && __IPHONE_OS_VERSION_MAX_ALLOWED >= __IPHONE_7_0
#import "AVSampleBufferDisplayLayer.h"

#else
#error Your SDK is too old for PHSampleBufferView! Need at least 7.0.

#endif

@interface PHSampleBufferView()

@property (nonatomic, strong, readonly) AVSampleBufferDisplayLayer *displayLayer;

@end

@implementation PHSampleBufferView

- (id)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        // Initialization code
        self.displayLayer.videoGravity = AVLayerVideoGravityResizeAspect;

//        [self setupTimebase];
    }
    return self;
}

+ (Class)layerClass
{
    return [AVSampleBufferDisplayLayer class];
}

- (AVSampleBufferDisplayLayer *)displayLayer
{
    return (AVSampleBufferDisplayLayer *)self.layer;
}

- (void)setVideoGravity:(NSString *)videoGravity
{
    self.displayLayer.videoGravity = videoGravity;
}

- (NSString *)videoGravity
{
    return self.displayLayer.videoGravity;
}

#pragma mark - Private

- (Float64)playbackRate
{
    return CMTimebaseGetRate(self.displayLayer.controlTimebase);
}

- (void)setPlaybackRate:(Float64)playbackRate
{
    CMTimebaseSetRate(self.displayLayer.controlTimebase, playbackRate);
}

- (void)setPlaybackAudioSample:(Float64)playbackAudioSample
{
    CMTime time = CMTimebaseGetTime(self.displayLayer.controlTimebase);
    time.value = playbackAudioSample;
    CMTimebaseSetTime(self.displayLayer.controlTimebase, time);
}

- (void)setupTimebase
{
    CMTimebaseRef controlTimebase = NULL;
    CMClockRef clock = NULL;
    BOOL useHostClock = YES;
    if (useHostClock) {
        clock = CMClockGetHostTimeClock();
    }
    else {
        CMAudioClockCreate(kCFAllocatorDefault, &clock);
    }
    OSStatus status = CMTimebaseCreateWithMasterClock(kCFAllocatorDefault, clock, &controlTimebase);


    if (status) {
        NSLog(@"Failed to create timebase with status: %d", (int)status);
    }
    else {
        CMTimebaseSetRate(controlTimebase, 1.0);
        CMTimebaseSetTime(controlTimebase, CMTimeMakeWithSeconds(CACurrentMediaTime(), 24));
    }

    self.displayLayer.controlTimebase = controlTimebase;

    if (controlTimebase != NULL) {
        CFRelease(controlTimebase);
    }
    if (!useHostClock && clock != NULL) {
        CFRelease(clock);
    }
}

#pragma mark - Public

- (void)addSampleProviderWithBlock:(PHVideoSampleRequestBlock)providerBlock inQueue:(dispatch_queue_t)providerQueue
{
    [self.displayLayer flush];
    [self.displayLayer requestMediaDataWhenReadyOnQueue:providerQueue usingBlock:^
    {
        while (self.displayLayer.readyForMoreMediaData)
        {
            CMSampleBufferRef nextSampleBuffer = providerBlock();

            if (nextSampleBuffer) {
                [self.displayLayer enqueueSampleBuffer:nextSampleBuffer];
                CFRelease(nextSampleBuffer);
            }
            else {
//                [self.displayLayer stopRequestingMediaData];
                break;
            }
        }

    }];
}

- (void)stopSampleProvider
{
    [self.displayLayer stopRequestingMediaData];
}

- (void)displaySampleBuffer:(CMSampleBufferRef)sampleBuffer
{
    if (self.displayLayer.isReadyForMoreMediaData) {
        [self.displayLayer enqueueSampleBuffer:sampleBuffer];
    }
#if defined(__IPHONE_8_0) && __IPHONE_OS_VERSION_MAX_ALLOWED >= __IPHONE_8_0
    else if (self.displayLayer.error) {
        NSLog(@"Display layer error: %@", self.displayLayer.error);
    }
#endif
}

- (void)flush
{
    [self.displayLayer flushAndRemoveImage];
}

@end
