//
//  PHCaptureManager.h
//  PerchRTC
//
//  Created by Christopher Eagleston on 12/12/2013.
//  Copyright (c) 2013 Perch Communications Inc. All rights reserved.
//

#import "AVCaptureDevice+PHCapturePresets.h"
#import "PHFormats.h"

@import AVFoundation;

typedef void (^PHCaptureManagerImageBlock)(UIImage *image, NSError *error);
typedef void (^PHCaptureSessionBlock)(void);

@class PHCapturePreviewView;

typedef NS_ENUM(NSUInteger, PHCameraPosition)
{
    PHCameraPositionFront = 0,
    PHCameraPositionBack = 1,
    PHCameraPositionAny = 2,
};

typedef NS_ENUM(NSUInteger, PHCaptureSessionState)
{
    PHCaptureSessionStateIdle = 0,
    PHCaptureSessionStateStarting = 1,
    PHCaptureSessionStateRunning = 2,
    PHCaptureSessionStateStopping = 3,
};

/**
 *  Basic capture device control. Allows for focus, exposure, framerate, scene detect, and (simple) zoom;
 */
@protocol PHCaptureDeviceControl <NSObject>

@property (nonatomic, assign, readonly) BOOL zoomSupported;
@property (nonatomic, assign, readonly) CGFloat maxZoomFactor;
@property (nonatomic, assign, readonly) CGFloat zoomFactor;
@property (nonatomic, assign, readonly) PHCapturePreset deviceCapturePreset;

- (BOOL)setFrameRate:(double)frameRate;
- (BOOL)setExposurePointOfInterest:(CGPoint)point withMode:(AVCaptureExposureMode)exposureMode;
- (BOOL)setFocusPointOfInterest:(CGPoint)point withMode:(AVCaptureFocusMode)focusMode;
- (BOOL)setSceneDetectionEnabled:(BOOL)enabled;
- (BOOL)setSmoothAutofocusEnabled:(BOOL)enabled;
- (BOOL)rampToZoomFactor:(CGFloat)zoomFactor;
- (BOOL)setDeviceCapturePreset:(PHCapturePreset)preset;
- (BOOL)setHDREnabled:(BOOL)enabled;

@end

/**
 *  Video capture. 
 *  Once the Session starts, the delegate will be called back repeatedly on a serial queue owned by the Capture Manager.
 */
@protocol PHCaptureVideo <NSObject>

- (void)prepareVideoCaptureWithFormat:(PHPixelFormat)format delegate:(id<AVCaptureVideoDataOutputSampleBufferDelegate>)delegate;

- (void)prepareVideoCaptureWithFormat:(PHPixelFormat)format orientation:(UIInterfaceOrientation)orientation delegate:(id<AVCaptureVideoDataOutputSampleBufferDelegate>)delegate;

- (void)updateVideoCaptureOrientation:(UIInterfaceOrientation)orientation;

- (void)clearVideoCaptureDelegate;

- (void)teardownVideoCapture;

@end

@class AVCaptureSession;

@interface PHCaptureManager : NSObject <PHCaptureDeviceControl, PHCaptureVideo>

@property (nonatomic, assign, readonly) PHCameraPosition cameraPosition;

// Must have a capture session first!
@property (nonatomic, strong, readonly) PHCapturePreviewView *previewView;

@property (nonatomic, strong) AVCaptureSession *session;

@property (nonatomic, copy) NSString *sessionPreset;

/**
 *  Convenience property, which indicates if the capture is starting or running. Does not support KVO.
 *
 *  @return 'YES' if capture is starting or already running.
 */
@property (atomic, assign, readonly) BOOL isCapturing;

/**
 *  The capture session's current state. Supports KVO.
 *  @note: Observers will be called back on either the main queue, or session queue.
 *  
 *  @return The capture manager's session state.
 */
@property (atomic, assign, readonly) PHCaptureSessionState captureState;

@property (atomic, assign, readonly, getter = isCaptureInterrupted) BOOL captureInterrupted;

/**
 *  Initilizes the capture manager. An AVCaptureSession will be created and bound with the capture manager.
 *
 *  @return A capture manager which controls a capture session.
 */
- (instancetype)init;

/**
 *  Initializes the capture manager with a session.
 *
 *  @param session A freshly initialized session object.
 *
 *  @return A capture manager which controls the provided capture session.
 */
- (instancetype)initWithCaptureSession:(AVCaptureSession *)session;

- (BOOL)supportsPreset:(NSString *)capturePreset;

/**
 *  Allows you to batch configuration changes to the session. Works while the session is stopped or running.
 *  @note It is safe to call prepare/teardown or start/stop methods from PHCaptureVideo.
 *  Also, the session preset may be changed.
 *
 *  @param configureBlock A handler block which applies the changes to the session.
 *  @note If capture is running, this block will be called on the serial session queue.
 */
- (void)configureSession:(PHCaptureSessionBlock)configureBlock;

/**
 *  Starts the capture session.
 */
- (void)startSession;

/**
 *  Stops the capture session asynchronously.
 */
- (void)stopSession;

- (void)stopSessionAndTeardownOutputs:(BOOL)teardownOutputs;

/**
 *  Stops the capture session synchronously.
 */
- (void)stopSessionSync;

/**
 *  Selects a new camera position.
 *
 *  @param cameraPosition The camera position to select.
 */
- (void)selectCameraPosition:(PHCameraPosition)cameraPosition;

- (BOOL)hasCameraForPosition:(PHCameraPosition)cameraPosition;

@end
