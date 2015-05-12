//
//  PHCaptureManager.m
//  PerchRTC
//
//  Created by Christopher Eagleston on 12/12/2013.
//  Copyright (c) 2013 Perch Communications Inc. All rights reserved.
//

#import "PHCaptureManager.h"

#import "PHCapturePreviewView.h"

#import <CoreVideo/CoreVideo.h>

@interface PHCaptureManager () <AVCaptureVideoDataOutputSampleBufferDelegate>

@property (nonatomic, strong) NSMutableArray *constructorBlocks;

@property (nonatomic, strong) AVCaptureVideoDataOutput *videoDataOutput;

@property (nonatomic, strong) AVCaptureDeviceInput *videoInput;
@property (nonatomic, strong) AVCaptureDeviceInput *audioInput;
@property (nonatomic, weak) id deviceConnectedObserver;
@property (nonatomic, weak) id deviceDisconnectedObserver;
@property (nonatomic, weak) id deviceSceneObserver;
@property (nonatomic, weak) id captureStartObserver;
@property (nonatomic, weak) id sessionInterruptionStartObserver;
@property (nonatomic, weak) id sessionInterruptionEndObserver;
@property (nonatomic, weak) id sessionRuntimeErrorObserver;
@property (nonatomic, assign) PHCameraPosition cameraPosition;

@property (nonatomic, strong) dispatch_queue_t sessionQueue;
@property (nonatomic, strong) dispatch_queue_t videoCaptureQueue;

@property (atomic, assign) PHCaptureSessionState captureState;
@property (atomic, assign, getter = isCaptureInterrupted) BOOL captureInterrupted;
@property (nonatomic, assign, getter = isMetadataPaused) BOOL metadataPaused;

@end

@implementation PHCaptureManager

@synthesize previewView = _previewView;
@synthesize deviceCapturePreset = _deviceCapturePreset;

#pragma mark - Initializers & Dealloc

- (instancetype)init
{
    AVCaptureSession *session = [[AVCaptureSession alloc] init];
    id me = [self initWithCaptureSession:session];
    return me;
}

// Note: We make sure to observe capture sessions that we were constructed with.
- (instancetype)initWithCaptureSession:(AVCaptureSession *)session
{
    DDLogDebug(@"%s", __PRETTY_FUNCTION__);

    self = [super init];
    if (self) {
        _session = session;
        _sessionQueue = dispatch_queue_create("com.perch.capture", DISPATCH_QUEUE_SERIAL);
        dispatch_set_target_queue(_sessionQueue, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0));

        _constructorBlocks = [NSMutableArray array];
        _cameraPosition = PHCameraPositionAny;
        _captureState = PHCaptureSessionStateIdle;
        _captureInterrupted = NO;

        [self prepareCapture];
        [self addObservers];
    }
    
    return self;
}

- (void)dealloc
{
    DDLogInfo(@"%s", __PRETTY_FUNCTION__);

    [self removeObservers];
    [self stopSessionSync];
    [self teardownCapture];

    _sessionQueue = nil;
}

#pragma mark - Properties

- (BOOL)supportsPreset:(NSString *)capturePreset
{
    return [self.session canSetSessionPreset:capturePreset];
}

- (PHCapturePreviewView *)previewView
{
    NSAssert(self.session, @"Must have a capture session.");

    if (!_previewView) {
        PHCapturePreviewView *previewView = [[PHCapturePreviewView alloc] initWithFrame:CGRectZero andCaptureSession:self.session];
        _previewView = previewView;
    }

    return _previewView;
}

- (void)setSession:(AVCaptureSession *)session
{
    BOOL changed = session != _session;
    if (changed) {
        _session = session;

        // Find currently active video input
        for (AVCaptureDeviceInput *input in _session.inputs) {
            AVCaptureDevice *inputDevice = input.device;
            BOOL videoDevice = [inputDevice hasMediaType:AVMediaTypeVideo];
            if (videoDevice) {
                _videoInput = input;
                break;
            }
        }

        // Log the outputs
        for (AVCaptureOutput *output in session.outputs) {
            DDLogVerbose(@"Found session output %@", output);
        }
    }
}

- (void)setSessionPreset:(NSString *)sessionPreset
{
    DDLogInfo(@"PHCaptureManager: Set session preset: %@", sessionPreset);
    
    self.session.sessionPreset = sessionPreset;
}

- (NSString *)sessionPreset
{
    return self.session.sessionPreset;
}

- (BOOL)isCapturing
{
    PHCaptureSessionState state = self.captureState;

    return (state == PHCaptureSessionStateStarting || state == PHCaptureSessionStateRunning);
}

#pragma mark - Public

- (void)configureSession:(PHCaptureSessionBlock)configureBlock
{
    PHCaptureSessionBlock configureWrapper = ^(void) {

        [self.session beginConfiguration];

        configureBlock();

        [self.session commitConfiguration];
    };

    // If we are capturing then do the configuration on the session queue.

    if (self.isCapturing) {
        [self enqueueSessionBlock:configureWrapper];
    }
    else {
        configureWrapper();
    }
}

- (void)startSession
{
    [self enqueueSessionBlock:^
     {
         DDLogInfo(@"Start capture session.");

         self.captureState = PHCaptureSessionStateStarting;

         [self.session startRunning];

         self.captureState = PHCaptureSessionStateRunning;
     }];
}

- (void)stopSession
{
    [self stopSessionAndTeardownOutputs:NO];
}

- (void)stopSessionAndTeardownOutputs:(BOOL)teardownOutputs
{
    [self enqueueSessionBlock:^
     {
         DDLogInfo(@"Stop capture session async.");

         self.captureState = PHCaptureSessionStateStopping;

         [self.session stopRunning];

         if (teardownOutputs) {
             [self.session beginConfiguration];

             [self teardownVideoCapture];
             [self setSceneDetectionEnabled:NO];

             [self.session commitConfiguration];
         }

         self.captureState = PHCaptureSessionStateIdle;
     }];
}

- (void)stopSessionSync
{
    if (self.isCapturing) {

        [self enqueueSessionBlockSync:^
         {
             DDLogInfo(@"Stop capture session synchronous!");

             self.captureState = PHCaptureSessionStateStopping;

             [self.session stopRunning];

             self.captureState = PHCaptureSessionStateIdle;
         }];
    }
}

- (void)selectCameraPosition:(PHCameraPosition)cameraPosition
{
    _cameraPosition = cameraPosition;

    PHCaptureSessionBlock selectCameraHandler = ^
    {
        AVCaptureDevicePosition position = cameraPosition == PHCameraPositionFront ? AVCaptureDevicePositionFront : AVCaptureDevicePositionBack;
        AVCaptureDevice *videoDevice = [self cameraWithPosition:position];
        AVCaptureDeviceInput *videoInput = [[AVCaptureDeviceInput alloc] initWithDevice:videoDevice error:NULL];

        // Figure out the current state of the session, so we can replicate it as well as possible with the new deivce.

        AVCaptureVideoOrientation lastOrientation = AVCaptureVideoOrientationPortrait;

        if (self.videoDataOutput) {
            lastOrientation = [self videoOutputConnection].videoOrientation;
        }

        // Change the inputs.

        [self.session removeInput:self.videoInput];
        [self.session addInput:videoInput];
        self.videoInput = videoInput;

        // Apply our custom capture preset if necessary.

        if ([self.sessionPreset isEqualToString:AVCaptureSessionPresetInputPriority]) {
            [self setDeviceCapturePreset:self.deviceCapturePreset];
        }

        if (self.videoDataOutput) {
            [self videoOutputConnection].videoOrientation = lastOrientation;
        }

        NSArray *focusModes = @[@(AVCaptureFocusModeLocked), @(AVCaptureFocusModeAutoFocus), @(AVCaptureFocusModeContinuousAutoFocus)];
        for (NSNumber *focusMode in focusModes) {
            BOOL supported = [self.videoInput.device isFocusModeSupported:[focusMode integerValue]];
            DDLogVerbose(@"Focus mode %ld supported %d", (long)[focusMode integerValue], supported);
        }
        NSArray *exposures = @[@(AVCaptureExposureModeLocked), @(AVCaptureExposureModeAutoExpose), @(AVCaptureExposureModeContinuousAutoExposure)];
        for (NSNumber *exposure in exposures) {
            BOOL supported = [self.videoInput.device isExposureModeSupported:[exposure integerValue]];
            DDLogVerbose(@"Exposure mode %ld supported %d", (long)[exposure integerValue], supported);
        }
    };
    
    [self configureSession:selectCameraHandler];
}

- (BOOL)hasCameraForPosition:(PHCameraPosition)cameraPosition
{
    BOOL hasCamera = NO;

    if (cameraPosition == PHCameraPositionBack) {
        hasCamera = [self backFacingCamera] != nil;
    }
    else {
        hasCamera = [self frontFacingCamera] != nil;
    }

    return hasCamera;
}

#pragma mark - Private

/**
 *  Prepares the session for capture, adding inputs as necessary. A default preset of 640x480 is chosen by default. The session should be prepared before startSession is called.
 *
 *  @return YES if successful.
 */
- (BOOL)prepareCapture
{
	BOOL success = YES;
    BOOL prepareAudio = NO;
    BOOL prepareVideo = YES;

	AVCaptureDevice *audioDevice = [self audioDevice];
	AVCaptureDevice *videoDevice = [self frontFacingCamera];
    _cameraPosition = PHCameraPositionFront;
    _session.automaticallyConfiguresApplicationAudioSession = prepareAudio;

	if (!videoDevice) {
        _cameraPosition = PHCameraPositionBack;
		videoDevice = [self backFacingCamera];
	}

	AVCaptureDeviceInput *audioInput = nil;
	AVCaptureDeviceInput *videoInput = nil;

	AVCaptureSession *aSession = _session;
	aSession.sessionPreset = AVCaptureSessionPreset640x480;

    // Audio Input

	if (prepareAudio) {
        audioInput = [[AVCaptureDeviceInput alloc] initWithDevice:audioDevice error:nil];

        if ([aSession canAddInput:audioInput]) {
            [aSession addInput:audioInput];
        }
    }

    // Video Input

    if (prepareVideo) {
        videoInput = [[AVCaptureDeviceInput alloc] initWithDevice:videoDevice error:nil];

        if ([aSession canAddInput:videoInput]) {
            [aSession addInput:videoInput];
        }
    }

	_session = aSession;
	_audioInput = audioInput;
	_videoInput = videoInput;

	return success;
}

/**
 *  Gets rid of our references to the capture session.
 */
- (void)teardownCapture
{
    _session = nil;
    _videoInput = nil;
    _audioInput = nil;
}

/**
 *  Allows you to asynchronously run a block on the session's serial queue.
 *
 *  @param sessionBlock The block to execute.
 */
- (void)enqueueSessionBlock:(PHCaptureSessionBlock)sessionBlock
{
	if (_sessionQueue) {
		dispatch_async(_sessionQueue, sessionBlock);
	}
}

/**
 *  Allows you to synchronously run a block on the session's serial queue.
 *
 *  @param sessionBlock The block to execute.
 */
- (void)enqueueSessionBlockSync:(PHCaptureSessionBlock)sessionBlock
{
	if (_sessionQueue) {
		dispatch_sync(_sessionQueue, sessionBlock);
	}
}

- (void)enqueueMainThreadBlock:(PHCaptureSessionBlock)sessionBlock
{
	dispatch_async(dispatch_get_main_queue(), sessionBlock);
}

- (void)addObservers
{
	__weak PHCaptureManager *weakSelf = self;

	// Device connection

	void (^deviceConnectedBlock)(NSNotification *) = ^(NSNotification *notification)
    {
		PHCaptureSessionBlock connectionSessionBlock = ^(void)
        {
			__strong PHCaptureManager *strongSelf = weakSelf;

			AVCaptureDevice *device = [notification object];
			BOOL sessionHasDeviceWithMatchingMediaType = NO;
			NSString *deviceMediaType = nil;

			if ([device hasMediaType:AVMediaTypeVideo]) {
				deviceMediaType = AVMediaTypeVideo;
			}

			if (deviceMediaType != nil) {
				for (AVCaptureDeviceInput *input in strongSelf.session.inputs)
				{
					if ([input.device hasMediaType:deviceMediaType]) {
						sessionHasDeviceWithMatchingMediaType = YES;
						break;
					}
				}
			}

			if (!sessionHasDeviceWithMatchingMediaType) {
				NSError	*error;
				AVCaptureDeviceInput *input = [AVCaptureDeviceInput deviceInputWithDevice:device error:&error];
                
				if ([strongSelf.session canAddInput:input]) {
					[strongSelf.session addInput:input];
				}
                
                if (error) {
                    DDLogError(@"Failed to get device input, with error: %@", error);
                }
			}

			// Optionally, inform our delegate of the device configuration change here..
		};

		DDLogVerbose(@"Device connected %@", notification.object);
		[weakSelf enqueueSessionBlock:connectionSessionBlock];
	};

	// Device disconnection

	void (^deviceDisconnectedBlock)(NSNotification *) = ^(NSNotification *notification) {

		PHCaptureSessionBlock disconnectionSessionBlock = ^(void)
        {
			__strong PHCaptureManager *strongSelf = weakSelf;
			AVCaptureDevice *device = [notification object];

			if ([device hasMediaType:AVMediaTypeAudio]) {
				[strongSelf.session removeInput:strongSelf.audioInput];
				strongSelf.audioInput = nil;
			}
			else if ([device hasMediaType:AVMediaTypeVideo]) {
				[strongSelf.session removeInput:strongSelf.videoInput];
				strongSelf.videoInput = nil;
			}

			// Optionally, inform our delegate of the device configuration change here..
		};

		DDLogVerbose(@"Device disconnected %@", notification.object);
		[weakSelf enqueueSessionBlock:disconnectionSessionBlock];
	};

    // Device scene change

	void (^sceneChangeBlock)(NSNotification *) = ^(NSNotification *notification)
    {
		PHCaptureSessionBlock sessionBlock = ^(void)
        {
			__strong PHCaptureManager *strongSelf = weakSelf;
            [strongSelf setExposurePointOfInterest:CGPointMake(0.5, 0.5) withMode:AVCaptureExposureModeContinuousAutoExposure];
            [strongSelf setFocusPointOfInterest:CGPointMake(0.5, 0.5) withMode:AVCaptureFocusModeContinuousAutoFocus];
		};

		[weakSelf enqueueSessionBlock:sessionBlock];
	};

	// Capture session start

	void (^captureStartBlock)(NSNotification *) = ^(NSNotification *notification)
    {
        DDLogVerbose(@"Capture session started %@", notification.object);
	};

    // Capture interruptions
    
	void (^interruptionStartBlock)(NSNotification *) = ^(NSNotification *notification)
    {
        DDLogVerbose(@"Capture session interruption did start. %@", notification.object);

        [weakSelf enqueueSessionBlock:^{
            weakSelf.captureInterrupted = YES;
        }];
	};

	void (^interruptionEndBlock)(NSNotification *) = ^(NSNotification *notification)
    {
        DDLogVerbose(@"Capture session interruption did end. %@", notification.object);
        [weakSelf enqueueSessionBlock:^{
            weakSelf.captureInterrupted = NO;
        }];
	};

    // Runtime errors.

	void (^runtimeErrorBlock)(NSNotification *) = ^(NSNotification *notification)
    {
        NSDictionary *userInfo = notification.userInfo;
        NSError *error = userInfo[AVCaptureSessionErrorKey];

        DDLogVerbose(@"Capture session encountered runtime error. %@", error);

        // TODO - @chris After encountering a reset, it may be better to rebuild the session from scratch in iOS 8.
        // TODO - @chris Need to wait until the session enters the foreground to restart it.

        BOOL wasCapturing = weakSelf.isCapturing;

        if (error.code == AVErrorDeviceIsNotAvailableInBackground) {
            NSLog( @"device not available in background" );

            // Since we can't resume running while in the background we need to remember this for next time we come to the foreground

            if ( wasCapturing ) {
                // TODO - @chris Remember to start capture here.
            }
        }
        else if (error.code == AVErrorMediaServicesWereReset) {

            if (wasCapturing) {
                [weakSelf startSession];
            }
        }
        else {
            DDLogVerbose(@"Session encountered a non-recoverable error: %@", error);
        }
	};

	NSNotificationCenter *notificationCenter = [NSNotificationCenter defaultCenter];
    NSOperationQueue *queue = [NSOperationQueue mainQueue];

	self.deviceConnectedObserver = [notificationCenter addObserverForName:AVCaptureDeviceWasConnectedNotification object:nil queue:queue usingBlock:deviceConnectedBlock];
	self.deviceDisconnectedObserver = [notificationCenter addObserverForName:AVCaptureDeviceWasDisconnectedNotification object:nil queue:queue usingBlock:deviceDisconnectedBlock];
    self.captureStartObserver = [notificationCenter addObserverForName:AVCaptureSessionDidStartRunningNotification object:nil queue:queue usingBlock:captureStartBlock];
    self.deviceSceneObserver = [notificationCenter addObserverForName:AVCaptureDeviceSubjectAreaDidChangeNotification object:nil queue:queue usingBlock:sceneChangeBlock];
    self.sessionInterruptionStartObserver = [notificationCenter addObserverForName:AVCaptureSessionWasInterruptedNotification object:nil queue:queue usingBlock:interruptionStartBlock];
    self.sessionInterruptionEndObserver = [notificationCenter addObserverForName:AVCaptureSessionInterruptionEndedNotification object:nil queue:queue usingBlock:interruptionEndBlock];
    self.sessionRuntimeErrorObserver = [notificationCenter addObserverForName:AVCaptureSessionRuntimeErrorNotification object:nil queue:queue usingBlock:runtimeErrorBlock];
}

- (void)removeObservers
{
	NSNotificationCenter *notificationCenter = [NSNotificationCenter defaultCenter];

    if (_deviceConnectedObserver) {
        [notificationCenter removeObserver:_deviceConnectedObserver];
    }
    if (_deviceDisconnectedObserver) {
        [notificationCenter removeObserver:_deviceDisconnectedObserver];
    }
    if (_captureStartObserver) {
        [notificationCenter removeObserver:_captureStartObserver];
    }
    if (_deviceSceneObserver) {
        [notificationCenter removeObserver:_deviceSceneObserver];
    }
    if (_sessionInterruptionEndObserver) {
        [notificationCenter removeObserver:_sessionInterruptionEndObserver];
    }
    if (_sessionInterruptionStartObserver) {
        [notificationCenter removeObserver:_sessionInterruptionStartObserver];
    }
    if (_sessionRuntimeErrorObserver) {
        [notificationCenter removeObserver:_sessionRuntimeErrorObserver];
    }
}

+ (AVCaptureVideoOrientation)videoOrientationForInterfaceOrientation:(UIInterfaceOrientation)orientation
{
    NSDictionary *interfaceOrientationToVideoOrientationMap = @{
                                                                @(UIInterfaceOrientationPortrait) : @(AVCaptureVideoOrientationPortrait),
                                                                @(UIInterfaceOrientationLandscapeLeft) : @(AVCaptureVideoOrientationLandscapeLeft),
                                                                @(UIInterfaceOrientationLandscapeRight) : @(AVCaptureVideoOrientationLandscapeRight),
                                                                @(UIInterfaceOrientationPortraitUpsideDown) : @(AVCaptureVideoOrientationPortraitUpsideDown)};
    return [interfaceOrientationToVideoOrientationMap[@(orientation)] integerValue];
}

+ (AVCaptureVideoOrientation)videoOrientationForDeviceOrientation:(UIDeviceOrientation)orientation
{
    NSDictionary *mapping = @{@(UIDeviceOrientationPortrait) : @(AVCaptureVideoOrientationPortrait),
                              @(UIDeviceOrientationPortraitUpsideDown) : @(AVCaptureVideoOrientationPortraitUpsideDown),
                              @(UIDeviceOrientationLandscapeLeft) : @(AVCaptureVideoOrientationLandscapeRight),
                              @(UIDeviceOrientationLandscapeRight) : @(AVCaptureVideoOrientationLandscapeLeft),
                              @(UIDeviceOrientationFaceUp) : @(AVCaptureVideoOrientationPortrait),
                              @(UIDeviceOrientationFaceDown) : @(AVCaptureVideoOrientationPortrait),
                              @(UIDeviceOrientationUnknown) : @(AVCaptureVideoOrientationPortrait)};
    return [mapping[@(orientation)] integerValue];
}

#pragma mark - Private helpers

// Find a front facing camera, returning nil if one is not found
- (AVCaptureDevice *) frontFacingCamera
{
    return [self cameraWithPosition:AVCaptureDevicePositionFront];
}

// Find a back facing camera, returning nil if one is not found
- (AVCaptureDevice *) backFacingCamera
{
    return [self cameraWithPosition:AVCaptureDevicePositionBack];
}

// Find and return the first audio device, returning nil if one is not found
- (AVCaptureDevice *) audioDevice
{
    NSArray *devices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeAudio];
    return [devices firstObject];
}

// Find a camera with the specificed AVCaptureDevicePosition, returning nil if one is not found
- (AVCaptureDevice *) cameraWithPosition:(AVCaptureDevicePosition) position
{
    NSArray *devices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
    for (AVCaptureDevice *device in devices) {
        BOOL matches = device.position == position;
		if (matches) {
            return device;
        }
    }
    return nil;
}

- (AVCaptureConnection *)videoOutputConnection
{
    return [self safeVideoConnectionForCaptureOutput:self.videoDataOutput];
}

- (AVCaptureConnection *)safeVideoConnectionForCaptureOutput:(AVCaptureOutput *)output
{
    AVCaptureConnection *connection = nil;

    if ([output isKindOfClass:[AVCaptureOutput class]]) {
        connection = [self videoConnectionForCaptureOutput:output];
    }

    return connection;
}

- (AVCaptureConnection *)videoConnectionForCaptureOutput:(AVCaptureOutput *)output
{
    NSParameterAssert(output);

    AVCaptureConnection *videoConnection = nil;
	for (AVCaptureConnection *connection in output.connections) {
		for (AVCaptureInputPort *port in [connection inputPorts]) {
			if ([[port mediaType] isEqual:AVMediaTypeVideo]) {
				videoConnection = connection;
				break;
			}
		}
    }
    return videoConnection;
}

- (BOOL)prepareVideoOutputWithFormat:(PHPixelFormat)format orientation:(AVCaptureVideoOrientation)orientation andDelegate:(id<AVCaptureVideoDataOutputSampleBufferDelegate>)delegate
{
    NSAssert(self.session, @"Must have a capture session.");
    NSAssert(self.videoDataOutput == nil, @"There is already a video data output!");

    self.videoCaptureQueue = dispatch_queue_create("com.perch.videocapture", DISPATCH_QUEUE_SERIAL);

    NSDictionary *videoSettings = @{(NSString *)kCVPixelBufferPixelFormatTypeKey : @(format)};
    AVCaptureVideoDataOutput *videoOutput = [[AVCaptureVideoDataOutput alloc] init];
    videoOutput.videoSettings = videoSettings;
    videoOutput.alwaysDiscardsLateVideoFrames = YES;
    [videoOutput setSampleBufferDelegate:delegate queue:self.videoCaptureQueue];

    BOOL canAdd = [self.session canAddOutput:videoOutput];
    if (canAdd) {
        [self.session addOutput:videoOutput];
        self.videoDataOutput = videoOutput;

        AVCaptureConnection *connection = [self videoOutputConnection];
        connection.videoOrientation = orientation;
    }

    return canAdd;
}

- (void)teardownVideoOutput
{
    if (self.videoDataOutput) {
        [self.session removeOutput:self.videoDataOutput];
        self.videoDataOutput = nil;
    }

    self.videoCaptureQueue = nil;
}

#pragma mark - PHCaptureDeviceControl

- (AVFrameRateRange *)frameRateRangeForFrameRate:(double)frameRate
{
    NSArray *supportedFrameRateRanges = self.videoInput.device.activeFormat.videoSupportedFrameRateRanges;
    for (AVFrameRateRange *range in supportedFrameRateRanges)
    {
        BOOL validRange = range.minFrameRate <= frameRate && frameRate <= range.maxFrameRate;
        if (validRange) {
            return range;
        }
    }
    return nil;
}

- (BOOL)setFrameRate:(double)frameRate
{
    BOOL success = YES;

    if (!self.videoInput) {
        success = NO;
    }
    else {
        PHCaptureSessionBlock frameRateHandler = ^
        {
            AVFrameRateRange *frameRateRange = [self frameRateRangeForFrameRate:frameRate];
            if (frameRateRange == nil) {
                DDLogError(@"unsupported frameRate %f", frameRate);
            }

            CMTime requestedDuration = frameRateRange.maxFrameDuration;
            requestedDuration.value = 1;
            requestedDuration.timescale = (CMTimeScale)floor(frameRate);
            NSError *error = nil;

            if ([self.videoInput.device lockForConfiguration:&error]) {
                [self.videoInput.device setActiveVideoMinFrameDuration:requestedDuration];
                [self.videoInput.device setActiveVideoMaxFrameDuration:requestedDuration];
                [self.videoInput.device unlockForConfiguration];
            }
            else {
                DDLogError(@"Couldn't lock the device: %@", error);
            }
        };

        if (self.isCapturing) {
            [self enqueueSessionBlock:frameRateHandler];
        }
        else {
            frameRateHandler();
        }
    }

    return success;
}

- (BOOL)setExposurePointOfInterest:(CGPoint)point withMode:(AVCaptureExposureMode)exposureMode
{
    AVCaptureDevice *currentDevice = self.videoInput.device;
    BOOL pointOfInterestSupported = [currentDevice isExposurePointOfInterestSupported];
    BOOL exposureModeSupported = [currentDevice isExposureModeSupported:exposureMode];

    if (pointOfInterestSupported && exposureModeSupported) {

        if ([currentDevice lockForConfiguration:nil]) {
            currentDevice.exposurePointOfInterest = point;
            currentDevice.exposureMode = exposureMode;
            [currentDevice unlockForConfiguration];
        }
    }
    return (pointOfInterestSupported && exposureModeSupported);
}

- (BOOL)setFocusPointOfInterest:(CGPoint)point withMode:(AVCaptureFocusMode)focusMode
{
    AVCaptureDevice *currentDevice = self.videoInput.device;
    BOOL modeSupported = [currentDevice isFocusModeSupported:focusMode];
    BOOL pointOfInterestSupported = [currentDevice isFocusPointOfInterestSupported];

    if (modeSupported && pointOfInterestSupported) {

        if ([currentDevice lockForConfiguration:nil]) {
            [currentDevice setFocusPointOfInterest:point];
            [currentDevice setFocusMode:focusMode];
            [currentDevice unlockForConfiguration];
        }
    }
    
    return (modeSupported && pointOfInterestSupported);
}

- (BOOL)setSceneDetectionEnabled:(BOOL)enabled
{
    AVCaptureDevice *currentDevice = self.videoInput.device;
    BOOL locked = [currentDevice lockForConfiguration:nil];
    if (locked) {
        [currentDevice setSubjectAreaChangeMonitoringEnabled:enabled];
        [currentDevice unlockForConfiguration];
    }
    return locked;
}

- (BOOL)setSmoothAutofocusEnabled:(BOOL)enabled
{
    AVCaptureDevice *currentDevice = self.videoInput.device;
    BOOL supported = [currentDevice isSmoothAutoFocusSupported];
    if (supported) {
        if ([currentDevice lockForConfiguration:nil]) {
            [currentDevice setSmoothAutoFocusEnabled:enabled];
            [currentDevice unlockForConfiguration];
        }
    }
    return supported;
}

- (CGFloat)zoomFactor
{
    return self.videoInput.device.videoZoomFactor;
}

- (BOOL)zoomSupported
{
    AVCaptureDevice *currentDevice = self.videoInput.device;
    return currentDevice.activeFormat.videoMaxZoomFactor > 1;
}

- (CGFloat)maxZoomFactor
{
    AVCaptureDevice *currentDevice = self.videoInput.device;
    return currentDevice.activeFormat.videoZoomFactorUpscaleThreshold;
}

- (BOOL)rampToZoomFactor:(CGFloat)zoomFactor
{
    AVCaptureDevice *currentDevice = self.videoInput.device;
    BOOL supported = [self zoomSupported];
    CGFloat actualZoomFactor = MAX(1, zoomFactor);

    if (supported) {
        if ([currentDevice lockForConfiguration:nil]) {
            CGFloat idealFactor = MIN(currentDevice.activeFormat.videoZoomFactorUpscaleThreshold, actualZoomFactor);
            CGFloat appliedZoomFactor = idealFactor;
            [currentDevice rampToVideoZoomFactor:appliedZoomFactor withRate:2.0];
            [currentDevice unlockForConfiguration];
        }
    }
    return supported;
}

- (BOOL)setDeviceCapturePreset:(PHCapturePreset)preset
{
    BOOL success = NO;
    AVCaptureDevice *currentDevice = self.videoInput.device;

    if (currentDevice) {
        AVCaptureDeviceFormat *requestedFormat = [currentDevice determineBestDeviceFormatForPreset:preset];

        if ([currentDevice lockForConfiguration:nil]) {
            currentDevice.activeFormat = requestedFormat;
            [currentDevice unlockForConfiguration];
            success = YES;
            _deviceCapturePreset = preset;
        }
    }

    return success;
}

- (BOOL)setHDREnabled:(BOOL)enabled
{
    BOOL success = NO;

    AVCaptureDevice *currentDevice = self.videoInput.device;

    if (currentDevice) {
        AVCaptureDeviceFormat *format = currentDevice.activeFormat;

        if (format.videoHDRSupported && [currentDevice lockForConfiguration:nil]) {
            currentDevice.automaticallyAdjustsVideoHDREnabled = NO;
            currentDevice.videoHDREnabled = enabled;
            [currentDevice unlockForConfiguration];
            success = YES;
        }
    }

    return success;
}

#pragma mark - PHCaptureVideo

- (void)prepareVideoCaptureWithFormat:(PHPixelFormat)format delegate:(id<AVCaptureVideoDataOutputSampleBufferDelegate>)delegate
{
    [self prepareVideoOutputWithFormat:format orientation:AVCaptureVideoOrientationPortrait andDelegate:delegate];
}

- (void)prepareVideoCaptureWithFormat:(PHPixelFormat)format orientation:(UIInterfaceOrientation)orientation delegate:(id<AVCaptureVideoDataOutputSampleBufferDelegate>)delegate
{
    AVCaptureVideoOrientation videoOrientation = [[self class] videoOrientationForInterfaceOrientation:orientation];
    [self prepareVideoOutputWithFormat:format orientation:videoOrientation andDelegate:delegate];
}

- (void)updateVideoCaptureOrientation:(UIInterfaceOrientation)orientation
{
    [self enqueueSessionBlock:^{
        AVCaptureConnection *connection = [self videoOutputConnection];
        connection.videoOrientation = [[self class] videoOrientationForInterfaceOrientation:orientation];
    }];
}

- (void)clearVideoCaptureDelegate
{
    [self.videoDataOutput setSampleBufferDelegate:nil queue:nil];
}

- (void)teardownVideoCapture
{
    [self teardownVideoOutput];
}

@end
