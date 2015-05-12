//
//  PHVideoPublisher.h
//  PerchRTC
//
//  Created by Christopher Eagleston on 2014-11-16.
//  Copyright (c) 2014 Perch Communications. All rights reserved.
//

#if !TARGET_IPHONE_SIMULATOR

#import <Foundation/Foundation.h>

#import "PHVideoCaptureKit.h"

#import "AVCaptureDevice+PHCapturePresets.h"

@class PHCapturePreviewView;

@interface PHVideoPublisher : NSObject <PHVideoCapture>

@property (nonatomic, strong, readonly) PHVideoCaptureKit *captureKit;

@property (nonatomic, strong, readonly) PHCapturePreviewView *previewView;

@property (nonatomic, assign, readonly, getter = isCapturing) BOOL capturing;

@property (nonatomic, assign, readonly) PHCapturePreset capturePreset;

@property (atomic, assign) id<PHVideoCaptureConsumer> videoCaptureConsumer;

- (void)updateVideoOrientation:(UIInterfaceOrientation)orientation;

- (void)updateCaptureFormat:(PHCapturePreset)preset;

+ (PHCapturePreset)recommendedCapturePreset;

@end

#endif