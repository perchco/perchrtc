//
//  PHEAGLVideoViewContainer.m
//  PerchRTC
//
//  Created by Christopher Eagleston on 2015-05-06.
//  Copyright (c) 2015 Perch Communications. All rights reserved.
//

#import "PHEAGLVideoViewContainer.h"

#import "RTCEAGLVideoView.h"

@import AVFoundation;

@implementation PHEAGLVideoViewContainer

@synthesize videoSize = _videoSize;

- (instancetype)initWithView:(RTCEAGLVideoView *)view
{
    self = [super initWithFrame:CGRectZero];

    if (self) {
        _videoView = view;

        [self addSubview:view];

        self.backgroundColor = [UIColor clearColor];
        self.opaque = YES;
    }

    return self;
}

- (void)layoutSubviews
{
    CGRect bounds = self.bounds;
    CGSize videoSize = self.videoSize;
    CGRect videoFrame = bounds;

    if (!CGSizeEqualToSize(videoSize, CGSizeZero)) {
        videoFrame = AVMakeRectWithAspectRatioInsideRect(videoSize, bounds);
    }

    self.videoView.frame = videoFrame;
}

- (void)setVideoSize:(CGSize)videoSize
{
    if (!CGSizeEqualToSize(videoSize, _videoSize)) {
        _videoSize = videoSize;
        [self setNeedsLayout];
    }
}

@end
