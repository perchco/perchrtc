//
//  PHSampleBufferRenderer.m
//  PerchRTC
//
//  Created by Christopher Eagleston on 2014-10-11.
//  Copyright (c) 2014 Perch Communications. All rights reserved.
//

#import "PHSampleBufferRenderer.h"

#import "PHFrameConverter.h"
#import "PHSampleBufferView.h"

#import "UIDevice+PHDeviceAdditions.h"
#import "RTCVideoTrack.h"

@import AVFoundation;

static Float64 PHSampleBufferAdaptorMinFPS = 200.;
static NSUInteger PHSampleBufferAdaptorDropSkipAmount = 4;
static NSUInteger PHSampleBufferAdaptorDropThreshold = 2;

@interface PHSampleBufferRenderer()

@property (nonatomic, assign) CMTime lastTime;
@property (nonatomic, assign) CMClockRef adapterClock;
@property (nonatomic, assign) NSUInteger adapterCounter;

@property (nonatomic, strong) PHFrameConverter *displayConverter;
@property (nonatomic, assign) CGSize videoSize;
@property (nonatomic, strong) PHSampleBufferView *sampleView;
@property (atomic, assign) BOOL renderingPaused;
@property (atomic, assign) BOOL hasVideoData;

@end

@implementation PHSampleBufferRenderer

- (instancetype)initWithDelegate:(id<PHRendererDelegate>)delegate
{
    return [self initWithOutput:PHFrameConverterOutputCMSampleBufferBackedByCVPixelBuffer andDelegate:delegate];
}

- (instancetype)initWithOutput:(PHFrameConverterOutput)output andDelegate:(id<PHRendererDelegate>)delegate
{
    self = [super init];

    if (self) {
        _delegate = delegate;
        _output = output;
        _renderingPaused = NO;
        [self commonSetup];
    }

    return self;
}

- (void)dealloc
{
    [self destroyConverters];

    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];

    [center removeObserver:self name:UIApplicationDidEnterBackgroundNotification object:nil];
    [center removeObserver:self name:UIApplicationWillEnterForegroundNotification object:nil];
    [center removeObserver:self name:UIApplicationWillResignActiveNotification object:nil];

    [self.sampleView removeObserver:self forKeyPath:@"layer.status"];
}

#pragma mark - NSObject

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    if ([keyPath isEqual:@"layer.status"]) {
        AVSampleBufferDisplayLayer *displayLayer = (AVSampleBufferDisplayLayer *)self.sampleView.layer;
        DDLogDebug(@"Layer status changed to: %ld", (long)displayLayer.status);

        [self restoreFailedSampleViewIfForegrounded];
    }
}

#pragma mark - Private

- (void)didEnterBackground
{
    self.renderingPaused = YES;
}

- (void)willEnterForeground
{
    // Due to an odd choice with Apple's AVSampleBufferDisplayLayer APIs, the layer's status transitions from rendering to failed
    // immediately upon entering the background, even if rendering is stopped well before the state transition occurs.
    // The only way to fix this is to create a new layer from scratch.

    BOOL needsRestore = YES;

    if ([[UIDevice currentDevice] supportsOS8]) {
        AVSampleBufferDisplayLayer *displayLayer = (AVSampleBufferDisplayLayer *)self.sampleView.layer;
        needsRestore = displayLayer.status == AVQueuedSampleBufferRenderingStatusFailed;
    }

    if (needsRestore) {
        [self restoreFailedSampleView];
    }

    self.renderingPaused = NO;
}

- (void)willBecomeInactive
{
    self.renderingPaused = NO;
}

- (void)restoreFailedSampleViewIfForegrounded
{
    AVSampleBufferDisplayLayer *displayLayer = (AVSampleBufferDisplayLayer *)self.sampleView.layer;

    if (displayLayer.status == AVQueuedSampleBufferRenderingStatusFailed && [UIApplication sharedApplication].applicationState != UIApplicationStateBackground) {
        [self restoreFailedSampleView];
    }
}

- (void)commonSetup
{
    PHFrameConverterOutput output = _output;
    _displayConverter = [PHFrameConverter converterWithOutput:output];
    _sampleView = [[PHSampleBufferView alloc] initWithFrame:CGRectZero];

    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];

    [center addObserver:self selector:@selector(didEnterBackground) name:UIApplicationDidEnterBackgroundNotification object:nil];
    [center addObserver:self selector:@selector(willEnterForeground) name:UIApplicationWillEnterForegroundNotification object:nil];
    [center addObserver:self selector:@selector(willBecomeInactive) name:UIApplicationWillResignActiveNotification object:nil];

    [_sampleView addObserver:self forKeyPath:@"layer.status" options:NSKeyValueObservingOptionNew context:NULL];

    // fps timer.

    CMClockRef hostClock = CMClockGetHostTimeClock();
    _adapterClock = hostClock;
    _lastTime = CMClockGetTime(hostClock);
}

- (void)restoreFailedSampleView
{
    UIView *lastSuperview = self.sampleView.superview;
    NSArray *lastSubviews = self.sampleView.subviews;
    NSArray *lastGestureRecognizers = self.sampleView.gestureRecognizers;
    NSUInteger lastIndex = [lastSuperview.subviews indexOfObject:self.sampleView];
    CGRect lastFrame = self.sampleView.frame;
    CGAffineTransform lastTransform = self.sampleView.transform;

    [self.sampleView flush];

    // In versions prior to iOS 8.3, flushing the layer does not restore it to AVQueuedSampleBufferRenderingStatusUnknown.

    BOOL needsWorkaround = [[[UIDevice currentDevice] systemVersion] compare:@"8.3" options:NSNumericSearch] == NSOrderedAscending;

    if (!needsWorkaround) {
        return;
    }

    [self.sampleView removeFromSuperview];

    [self.sampleView removeObserver:self forKeyPath:@"layer.status"];
    self.sampleView = [[PHSampleBufferView alloc] initWithFrame:lastFrame];
    self.sampleView.transform = lastTransform;
    [self.sampleView addObserver:self forKeyPath:@"layer.status" options:NSKeyValueObservingOptionNew context:NULL];

    [lastSuperview insertSubview:self.sampleView atIndex:lastIndex];

    [lastSubviews enumerateObjectsUsingBlock:^(UIView *subview, NSUInteger idx, BOOL *stop) {
        [self.sampleView addSubview:subview];
    }];

    [lastGestureRecognizers enumerateObjectsUsingBlock:^(UIGestureRecognizer *recognizer, NSUInteger idx, BOOL *stop) {
        [self.sampleView addGestureRecognizer:recognizer];
    }];
}

- (void)destroyConverters
{
    [_displayConverter flushFrame];
    _displayConverter = nil;
}

- (void)processFrame:(RTCI420Frame *)frame
{
    CMTime adaptedTime = CMClockGetTime(_adapterClock);
    CMTime difference = CMTimeSubtract(adaptedTime, _lastTime);
    Float64 frameRate = 1 / CMTimeGetSeconds(difference);
    _lastTime = adaptedTime;

    // Check if we should adapt the input.

    if (frameRate > PHSampleBufferAdaptorMinFPS) {

        _adapterCounter++;

        // Drop frames above the threshold.

        if (_adapterCounter > PHSampleBufferAdaptorDropThreshold) {

            BOOL acceptFrame = ((_adapterCounter - PHSampleBufferAdaptorDropThreshold) % PHSampleBufferAdaptorDropSkipAmount) == 0;

            if (!acceptFrame) {
                return;
            }
        }
    }
    else {
        _adapterCounter = 0;
    }

    PHFrameConverter *availableConverter = self.displayConverter;

    // .. Copy their incoming frame into our CVPixelBufferRef and wrap that in a CMSampleBufferRef.

    CMSampleBufferRef outputFrame = (CMSampleBufferRef)[availableConverter copyConvertedFrame:frame];

    // .. Display the result.

    if (outputFrame) {
        [self outputSampleBuffer:outputFrame];
    }
}

- (void)outputSampleBuffer:(CMSampleBufferRef)sampleBuffer
{
    [_sampleView displaySampleBuffer:sampleBuffer];

    CFRelease(sampleBuffer);
}

#pragma mark - Properties

- (void)setVideoTrack:(RTCVideoTrack *)videoTrack
{
    if (_videoTrack != videoTrack) {
        [_videoTrack removeRenderer:self];
        _videoTrack = videoTrack;
        [_videoTrack addRenderer:self];
    }
}

- (UIView *)rendererView
{
    return self.sampleView;
}

#pragma mark - RTCVideoRendererDelegate

- (void)renderFrame:(RTCI420Frame *)frame
{
    if (!_hasVideoData) {
        self.hasVideoData = YES;

        dispatch_async(dispatch_get_main_queue(), ^{
            [self.delegate rendererDidReceiveVideoData:self];
        });
    }

    if (!_renderingPaused) {
        [self processFrame:frame];
    }
}

- (void)setSize:(CGSize)size
{
    self.videoSize = size;

    CMVideoDimensions dimensions = {(int32_t)size.width, (int32_t)size.height};
    [self.displayConverter prepareForSourceDimensions:dimensions];

    dispatch_async(dispatch_get_main_queue(), ^{
        [self.delegate renderer:self streamDimensionsDidChange:size];
    });
}

@end
