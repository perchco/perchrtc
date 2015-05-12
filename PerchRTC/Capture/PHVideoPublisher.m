//
//  PHVideoPublisher.m
//  PerchRTC
//
//  Created by Christopher Eagleston on 2014-11-16.
//  Copyright (c) 2014 Perch Communications. All rights reserved.
//

#if !TARGET_IPHONE_SIMULATOR

#import "PHVideoPublisher.h"
#import "PHCaptureManager.h"

#import "UIDevice+PHDeviceAdditions.h"

@import AVFoundation;

static PHCapturePreset kCapturePreset = PHCapturePresetAcademyMediumQuality;
static PHCapturePreset kCapturePresetMediumPerformance = PHCapturePresetAcademyLowQuality;
static PHCapturePreset kCapturePresetLowPerformance = PHCapturePresetAcademyLowQuality;
static double kCaptureFPS = 30;
static double kCaptureFPSMediumPerformance = 20;
static double kCaptureFPSLowPerformance = 15;
static PHPixelFormat kCapturePixelFormat = PHPixelFormatYUV420BiPlanarFullRange;

@interface PHVideoPublisher() <AVCaptureVideoDataOutputSampleBufferDelegate>

@property (nonatomic, strong) PHCaptureManager *capturePipeline;
@property (nonatomic, strong) PHVideoCaptureKit *captureKit;
@property (nonatomic, assign) PHCapturePreset capturePreset;

@end

@implementation PHVideoPublisher

- (instancetype)init
{
    self = [super init];

    if (self) {

        _capturePreset = [[self class] recommendedCapturePreset];
        _captureKit = [[PHVideoCaptureKit alloc] initWithCapturer:self];

        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleOrientationNotification) name:@"StatusBarOrientationDidChange" object:nil];
    }

    return self;
}

- (void)dealloc
{
    DDLogDebug(@"%s", __PRETTY_FUNCTION__);

    [[NSNotificationCenter defaultCenter] removeObserver:self name:@"StatusBarOrientationDidChange" object:nil];
}

#pragma mark - Class

+ (PHCapturePreset)recommendedCapturePreset
{
    BOOL isLowPerformance = [UIDevice currentDevice].isLowPerformance;
    BOOL isMediumPerformance = [UIDevice currentDevice].isMediumPerformance;

    PHCapturePreset preset = kCapturePreset;

    // Must choose a capture preset before creating the capture kit instance, as it will query our video capture format.

    if (isLowPerformance) {
        preset = kCapturePresetLowPerformance;
    }
    else if (isMediumPerformance ){
        preset = kCapturePresetMediumPerformance;
    }

    return preset;
}

#pragma mark - Public

- (PHCapturePreviewView *)previewView
{
    return self.capturePipeline.previewView;
}

- (void)updateVideoOrientation:(UIInterfaceOrientation)orientation
{
    [self.capturePipeline updateVideoCaptureOrientation:orientation];
}

- (void)updateCaptureFormat:(PHCapturePreset)preset
{
    if (self.capturePreset != preset) {
        self.capturePreset = preset;

        double captureFPS = [self videoCaptureFormat].frameRate;

        [self.capturePipeline configureSession:^{
            [self.capturePipeline setDeviceCapturePreset:preset];
            [self.capturePipeline setFrameRate:captureFPS];
        }];
    }
}

#pragma mark - Private

- (void)handleOrientationNotification
{
    [self updateVideoOrientation:[UIApplication sharedApplication].statusBarOrientation];
}

// TODO: Support dynamic capture formats.
- (void)reconfigureCaptureForUpdatedVideoFormat
{
    [self.videoCaptureConsumer prepareForCaptureFormatChange];

    PHVideoFormat videoFormat = [self videoCaptureFormat];

    [self.capturePipeline configureSession:^{
        [self.capturePipeline setFrameRate:videoFormat.frameRate];
    }];
}

#pragma mark - PHVideoCapture

- (BOOL)isCapturing
{
    return self.capturePipeline.isCapturing;
}

- (void)prepareForCapture
{
    PHCapturePreset capturePreset = self.capturePreset;
    PHVideoFormat videoFormat = [self videoCaptureFormat];
    UIInterfaceOrientation orientation = [UIApplication sharedApplication].statusBarOrientation;

    PHCaptureManager *manager = [[PHCaptureManager alloc] init];
    double captureFPS = videoFormat.frameRate;

    [manager configureSession:^{
        [manager setDeviceCapturePreset:capturePreset];
        [manager setFrameRate:captureFPS];
        [manager prepareVideoCaptureWithFormat:kCapturePixelFormat orientation:orientation delegate:self];

        if ([[UIDevice currentDevice] supportsOS8]) {
            [manager setHDREnabled:YES];
        }
        
        [manager setSceneDetectionEnabled:YES];
    }];

    self.capturePipeline = manager;
}

- (void)unprepareCapture
{
    [self.capturePipeline teardownVideoCapture];
}

/**
 *  Start your capture session, and begin delivering frames to the capture consumer as soon as possible.
 */
- (void)startCapturing
{
    [self.capturePipeline startSession];
}

/**
 *  Stop your capture session, and do not deliver any more frames to the capture consumer.
 */
- (void)stopCapturing
{
    [self.capturePipeline clearVideoCaptureDelegate];
    [self.capturePipeline stopSession];
}

- (PHVideoFormat)videoCaptureFormat
{
    BOOL isLowPerformance = [UIDevice currentDevice].isLowPerformance;
    BOOL isMediumPerformance = [UIDevice currentDevice].isMediumPerformance;

    PHVideoFormat format;
    PHCapturePreset capturePreset = self.capturePreset;
    format.dimensions = [AVCaptureDevice dimensionsForPreset:capturePreset];
    format.frameRate = isLowPerformance ? kCaptureFPSLowPerformance : (isMediumPerformance ? kCaptureFPSMediumPerformance : kCaptureFPS);
    format.pixelFormat = kCapturePixelFormat;

    return format;
}

#pragma mark - AVCaptureVideoDataOutputSampleBufferDelegate

- (void)captureOutput:(AVCaptureOutput *)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection
{
    [_videoCaptureConsumer consumeFrame:sampleBuffer];
}

- (void)captureOutput:(AVCaptureOutput *)captureOutput didDropSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection
{
    [_videoCaptureConsumer droppedFrame:sampleBuffer];
}

@end

// iOS Device
#endif
