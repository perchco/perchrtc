//
//  PHVideoView.h
//  PerchRTC
//
//  Created by Christopher Eagleston on 2/5/2014.
//  Copyright (c) 2014 Perch Communications. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "PHRenderer.h"

@class RTCVideoTrack;
@class PHQuartzVideoView;

/**
 *  PHQuartzVideoView demonstrates a Core Graphics based approach to rendering WebRTC video.
 *
 *  TODO: This class falls into the trap of a view performing model tasks (frame rendering in addition to display)
 */
@interface PHQuartzVideoView : UIView <PHRenderer>

// PHRenderer
@property (nonatomic, weak) id<PHRendererDelegate> delegate;
@property (nonatomic, assign, readonly) CGSize videoSize;
@property (nonatomic, strong) RTCVideoTrack *videoTrack;
@property (nonatomic, strong, readonly) UIView *rendererView;
@property (atomic, assign, readonly) BOOL hasVideoData;

@end
