//
//  PHSampleBufferRenderer.h
//  PerchRTC
//
//  Created by Christopher Eagleston on 2014-10-11.
//  Copyright (c) 2014 Perch Communications. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "PHFrameConverter.h"

#import "PHRenderer.h"

@class PHSampleBufferRenderer;
@class PHSampleBufferView;

@interface PHSampleBufferRenderer : NSObject <PHRenderer>

@property (nonatomic, strong, readonly) PHSampleBufferView *sampleView;
@property (nonatomic, assign, readonly) PHFrameConverterOutput output;

// PHRenderer
@property (nonatomic, weak) id<PHRendererDelegate> delegate;
@property (nonatomic, strong) RTCVideoTrack *videoTrack;
@property (nonatomic, assign, readonly) CGSize videoSize;
@property (nonatomic, strong, readonly) UIView *rendererView;
@property (atomic, assign, readonly) BOOL hasVideoData;

- (instancetype)initWithDelegate:(id<PHRendererDelegate>)delegate;
- (instancetype)initWithOutput:(PHFrameConverterOutput)output andDelegate:(id<PHRendererDelegate>)delegate;

@end
