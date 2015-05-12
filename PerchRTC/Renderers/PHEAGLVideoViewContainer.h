//
//  PHEAGLVideoViewContainer.h
//  PerchRTC
//
//  Created by Christopher Eagleston on 2015-05-06.
//  Copyright (c) 2015 Perch Communications. All rights reserved.
//

#import <UIKit/UIKit.h>

@class RTCEAGLVideoView;

@interface PHEAGLVideoViewContainer : UIView

- (instancetype)initWithView:(RTCEAGLVideoView *)view;

@property (nonatomic, assign) CGSize videoSize;
@property (nonatomic, strong, readonly) RTCEAGLVideoView *videoView;

@end
