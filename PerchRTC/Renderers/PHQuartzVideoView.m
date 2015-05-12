//
//  PHVideoView.m
//  PerchRTC
//
//  Created by Christopher Eagleston on 2/5/2014.
//  Copyright (c) 2014 Perch Communications. All rights reserved.
//

#import "PHQuartzVideoView.h"

#import "PHFrameConverter.h"

#import <CoreVideo/CoreVideo.h>
#import <nighthawk-webrtc/RTCVideoTrack.h>
#import <QuartzCore/QuartzCore.h>

@interface PHQuartzVideoView()

@property (nonatomic, strong) PHFrameConverter *displayConverter;
@property (nonatomic, assign) CGImageRef currentFrame;
@property (nonatomic, assign) CGSize videoSize;
@property (atomic, assign) BOOL hasVideoData;

@end

@implementation PHQuartzVideoView

- (id)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        // Initialization code
        self.layer.contentsGravity = kCAGravityResizeAspect;
        self.layer.opaque = YES;
        self.layer.needsDisplayOnBoundsChange = NO;

        [self commonSetup];
    }
    return self;
}

- (void)dealloc
{
    [self destroyConverters];
}

#pragma mark - Private

- (void)commonSetup
{
    PHFrameConverterOutput output = PHFrameConverterOutputCGImageBackedByCVPixelBuffer;
    self.displayConverter = [PHFrameConverter converterWithOutput:output];

    _hasVideoData = NO;
}

- (void)destroyConverters
{
    [self.displayConverter flushFrame];
    self.displayConverter = nil;
}

- (void)processFrame:(RTCI420Frame *)frame
{
    // .. And now for some expensive work.

    PHFrameConverter *availableConverter = self.displayConverter;
    CFTypeRef outputFrame = [availableConverter copyConvertedFrame:frame];

    // .. Display the result.

    if (outputFrame) {
        [self outputFrame:(CGImageRef)outputFrame];
    }
}

- (void)outputFrame:(CGImageRef)frame
{
    dispatch_async(dispatch_get_main_queue(), ^{

        if (self.currentFrame != NULL) {
            CFRelease(self.currentFrame);
        }

        self.currentFrame = frame;

        [self.layer setNeedsDisplay];
    });
}

#pragma mark - Properties

- (void)setContentMode:(UIViewContentMode)contentMode
{
    DDLogDebug(@"%s", __PRETTY_FUNCTION__);

    [super setContentMode:contentMode];

    // Make sure the layer's contents gravity matches.

    static NSDictionary *contentModeToGravityMap = nil;
    if (!contentModeToGravityMap) {

        contentModeToGravityMap = @{ @(UIViewContentModeScaleToFill) : kCAGravityResizeAspectFill,
                                     @(UIViewContentModeScaleAspectFit) : kCAGravityResizeAspect,
                                     @(UIViewContentModeRedraw) : kCAGravityCenter,
                                     @(UIViewContentModeCenter) : kCAGravityCenter,
                                     @(UIViewContentModeTop) : kCAGravityTop,
                                     @(UIViewContentModeBottom) : kCAGravityBottom,
                                     @(UIViewContentModeLeft) : kCAGravityLeft,
                                     @(UIViewContentModeRight) : kCAGravityRight,
                                     @(UIViewContentModeTopLeft) : kCAGravityTopLeft,
                                     @(UIViewContentModeTopRight) : kCAGravityTopRight,
                                     @(UIViewContentModeBottomLeft) : kCAGravityBottomLeft,
                                     @(UIViewContentModeBottomRight) : kCAGravityBottomRight };
    }

    NSString *gravity = contentModeToGravityMap[@(contentMode)];
    self.layer.contentsGravity = gravity;
    [self.layer setNeedsLayout];
}

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
    return self;
}

#pragma mark - CALayerDelegate

- (void)displayLayer:(CALayer *)layer
{
    self.layer.contents = (__bridge id)self.currentFrame;
}

#pragma mark - RTCVideoRenderDelegate

- (void)renderFrame:(RTCI420Frame *)frame
{
    if (!_hasVideoData) {
        self.hasVideoData = YES;

        dispatch_async(dispatch_get_main_queue(), ^{
            [self.delegate rendererDidReceiveVideoData:self];
        });
    }

    [self processFrame:frame];
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
