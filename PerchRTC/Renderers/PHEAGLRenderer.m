//
//  PHEAGLRenderer.m
//  PerchRTC
//
//  Created by Christopher Eagleston on 2015-05-06.
//  Copyright (c) 2015 Perch Communications. All rights reserved.
//

#import "PHEAGLRenderer.h"

#import "PHEAGLVideoViewContainer.h"

#import "RTCEAGLVideoView.h"
#import "RTCVideoTrack.h"

@interface PHEAGLRenderer() <RTCEAGLVideoViewDelegate>

@property (nonatomic, strong) PHEAGLVideoViewContainer *containerView;
@property (nonatomic, strong) RTCEAGLVideoView *openGLView;
@property (nonatomic, assign) CGSize videoSize;
@property (atomic, assign) BOOL hasVideoData;

@end

@implementation PHEAGLRenderer

- (instancetype)initWithDelegate:(id<PHRendererDelegate>)delegate
{
    self = [super init];

    if (self) {
        _delegate = delegate;
        _openGLView = [[RTCEAGLVideoView alloc] initWithFrame:CGRectZero];
        _containerView = [[PHEAGLVideoViewContainer alloc] initWithView:_openGLView];
        _openGLView.delegate = self;
    }

    return self;
}

#pragma mark - Public

- (void)setVideoTrack:(RTCVideoTrack *)videoTrack
{
    if (_videoTrack != videoTrack) {
        [_videoTrack removeRenderer:self.openGLView];
        _videoTrack = videoTrack;
        [_videoTrack addRenderer:self.openGLView];
    }
}

- (UIView *)rendererView
{
    return self.containerView;
}

#pragma mark - RTCEAGLVideoViewDelegate

- (void)videoView:(RTCEAGLVideoView*)videoView didChangeVideoSize:(CGSize)size
{
    self.videoSize = size;

    if (!_hasVideoData) {
        self.hasVideoData = YES;

        dispatch_async(dispatch_get_main_queue(), ^{
            [self.delegate rendererDidReceiveVideoData:self];
        });
    }

    self.containerView.videoSize = size;

    [self.delegate renderer:self streamDimensionsDidChange:size];
}

#pragma mark - RTCVideoRenderer

- (void)setSize:(CGSize)size
{
    // Do nothing.
}

- (void)renderFrame:(RTCI420Frame *)frame
{
    // Do nothing.
}

@end
