//
//  PHRenderer.h
//  PerchRTC
//
//  Created by Christopher Eagleston on 2014-12-18.
//  Copyright (c) 2014 Perch Communications. All rights reserved.
//

#ifndef PerchRTC_PHRenderer_h
#define PerchRTC_PHRenderer_h

@class RTCVideoTrack;

#import "RTCVideoRenderer.h"

@protocol PHRenderer;

@protocol PHRendererDelegate <NSObject>

- (void)renderer:(id<PHRenderer>)renderer streamDimensionsDidChange:(CGSize)dimensions;

- (void)rendererDidReceiveVideoData:(id<PHRenderer>)renderer;

@end

@protocol PHRenderer <RTCVideoRenderer>

@property (nonatomic, weak) id<PHRendererDelegate> delegate;
@property (nonatomic, strong) RTCVideoTrack *videoTrack;
@property (nonatomic, assign, readonly) CGSize videoSize;
@property (nonatomic, strong, readonly) UIView *rendererView;
@property (atomic, assign, readonly) BOOL hasVideoData;

@end


#endif
