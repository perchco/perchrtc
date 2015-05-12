//
//  PHCapturePreviewView.m
//  PerchRTC
//
//  Created by Christopher Eagleston on 12/12/2013.
//  Copyright (c) 2013 Perch Communications Inc. All rights reserved.
//

@import QuartzCore;

#import "PHCapturePreviewView.h"

@implementation PHCapturePreviewView

- (id)initWithFrame:(CGRect)frame andCaptureSession:(AVCaptureSession *)session
{
    self = [super initWithFrame:frame];
    
    if (self) {
        self.captureSession = session;
        self.previewLayer.connection.videoOrientation = AVCaptureVideoOrientationPortrait;
        
        _orientation = UIInterfaceOrientationPortrait;
    }
    
    return self;
}

+ (Class)layerClass
{
    return [AVCaptureVideoPreviewLayer class];
}

#pragma mark - Getters & Setters

- (AVCaptureVideoPreviewLayer *)previewLayer
{
    return (AVCaptureVideoPreviewLayer *)self.layer;
}

- (AVCaptureSession *)captureSession
{
    return self.previewLayer.session;
}

- (void)setCaptureSession:(AVCaptureSession *)captureSession
{
    self.previewLayer.session = captureSession;
    self.previewLayer.videoGravity = AVLayerVideoGravityResizeAspect;
}

- (void)setOrientation:(UIInterfaceOrientation)orientation
{
    BOOL changed = orientation != _orientation;

    if (changed) {
        _orientation = orientation;

        NSDictionary *interfaceOrientationToVideoOrientationMap = @{
                                                                    @(UIInterfaceOrientationPortrait) : @(AVCaptureVideoOrientationPortrait),
                                                                    @(UIInterfaceOrientationLandscapeLeft) : @(AVCaptureVideoOrientationLandscapeLeft),
                                                                    @(UIInterfaceOrientationLandscapeRight) : @(AVCaptureVideoOrientationLandscapeRight),
                                                                    @(UIInterfaceOrientationPortraitUpsideDown) : @(AVCaptureVideoOrientationPortraitUpsideDown)};

        AVCaptureVideoPreviewLayer *previewLayer = self.previewLayer;
        AVCaptureConnection *previewConnection = previewLayer.connection;

        AVCaptureVideoOrientation videoOrientation = [interfaceOrientationToVideoOrientationMap[@(orientation)] integerValue];
        previewConnection.videoOrientation = videoOrientation;
    }
}

- (void)setVideoGravity:(NSString *)videoGravity
{
    self.previewLayer.videoGravity = videoGravity;
}

- (NSString *)videoGravity
{
    return self.previewLayer.videoGravity;
}

- (void)setShowsBorder:(BOOL)showsBorder
{
    _showsBorder = showsBorder;

    if (showsBorder) {
        self.previewLayer.cornerRadius = 0.0;
        self.previewLayer.borderColor = [UIColor whiteColor].CGColor;
        self.previewLayer.borderWidth = 2.0;
        self.previewLayer.shadowColor = NULL;
    }
    else {
        self.previewLayer.cornerRadius = 0;
        self.previewLayer.borderColor = NULL;
        self.previewLayer.borderWidth = 0;
        self.previewLayer.shadowColor = NULL;
    }
}

@end
