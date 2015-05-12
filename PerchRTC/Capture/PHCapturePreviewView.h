//
//  PHCapturePreviewView.h
//  PerchRTC
//
//  Created by Christopher Eagleston on 12/12/2013.
//  Copyright (c) 2013 Perch Communications Inc. All rights reserved.
//

@import AVFoundation;

@interface PHCapturePreviewView : UIView

@property (nonatomic, strong) AVCaptureSession *captureSession;
@property (nonatomic, assign) UIInterfaceOrientation orientation;
@property (nonatomic, strong, readonly) AVCaptureVideoPreviewLayer *previewLayer;
@property (nonatomic, assign) BOOL showsBorder;
@property (copy) NSString *videoGravity;

- (id)initWithFrame:(CGRect)frame andCaptureSession:(AVCaptureSession *)session;

@end
