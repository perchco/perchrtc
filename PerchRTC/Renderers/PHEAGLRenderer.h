//
//  PHEAGLRenderer.h
//  PerchRTC
//
//  Created by Christopher Eagleston on 2015-05-06.
//  Copyright (c) 2015 Perch Communications. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "PHRenderer.h"

@interface PHEAGLRenderer : NSObject <PHRenderer>

- (instancetype)initWithDelegate:(id<PHRendererDelegate>)delegate;

// PHRenderer
@property (nonatomic, weak) id<PHRendererDelegate> delegate;
@property (nonatomic, strong) RTCVideoTrack *videoTrack;
@property (nonatomic, assign, readonly) CGSize videoSize;
@property (nonatomic, strong, readonly) UIView *rendererView;
@property (atomic, assign, readonly) BOOL hasVideoData;

@end
