//
//  PHVideoCapturer.m
//  PerchRTC
//
//  Created by Christopher Eagleston on 2014-10-04.
//  Copyright (c) 2014 Perch Communications. All rights reserved.
//

#if !TARGET_IPHONE_SIMULATOR

#import "PHVideoCaptureKit.h"

#include "PHVideoCaptureBridge.h"

#include "talk/media/base/videocapturer.h"
#include "talk/media/devices/devicemanager.h"
#include "webrtc/modules/video_capture/include/video_capture_factory.h"


/**
 *  The intention is for us to own a custom subclass of cricket::videoCapturer.
 *  We pass the video capture kit instance into the connection factory, which returns a stream bound to our capturer.
 *  Capture commands (prepare, unprepare, start, stop, format) flow up to <PHVideoCapture>.
 *  Frames flow down to <PHVideoCaptureConsumer> and then to our C++ capturer class.
 */
@interface PHVideoCaptureKit() <PHVideoCaptureConsumer>
{
    rtc::scoped_ptr<perch::VideoCapturerKit> _rtcCapturerScoped;
    perch::VideoCapturerKit *_rtcCapturer;
}

- (cricket::VideoCapturer *)takeNativeCapturer;

@end

@implementation PHVideoCaptureKit

- (instancetype)initWithCapturer:(id<PHVideoCapture>)capturer
{
    self = [super init];

    if (self) {
        // Surprise, we are the capture consumer!

        _videoCapturer = capturer;
        _videoCapturer.videoCaptureConsumer = self;

#if !TARGET_IPHONE_SIMULATOR
        [self commonInitCustom];
#endif
        
    }

    return self;
}

- (void)dealloc
{
    DDLogDebug(@"%s", __PRETTY_FUNCTION__);
}

#pragma mark - Private

- (cricket::VideoCapturer *)takeNativeCapturer
{
    // Instead of releasing our reference to the capturer like the factory expects, we hold on to it.
    // For external capture to work, we need a way to deliver frames to the cricket::videoCapturer.

    return _rtcCapturerScoped.release();
}

#if !TARGET_IPHONE_SIMULATOR

- (void)commonInitCustom
{
    rtc::scoped_ptr<cricket::DeviceManagerInterface> deviceManagerRef(cricket::DeviceManagerFactory::Create());

    if (!deviceManagerRef->Init()) {
        DDLogError(@"Can't initialize the device manager!");
        return;
    }

    // Use our Custom VideoCapturer factory

    cricket::DeviceManager *deviceManager = static_cast<cricket::DeviceManager*>(deviceManagerRef.get());
    deviceManager->SetVideoDeviceCapturerFactory(new perch::VideoCapturerKitFactory());

    std::vector<cricket::Device> devs;

    if (!deviceManagerRef->GetVideoCaptureDevices(&devs)) {
        DDLogError(@"Can't get video capture devices!");
        return;
    }

    std::vector<cricket::Device>::iterator dev_it = devs.begin();
    cricket::VideoCapturer *capturer = NULL;

    for (; dev_it != devs.end(); ++dev_it) {
        capturer = deviceManagerRef->CreateVideoCapturer(*dev_it);

        if (capturer != NULL) {
            break;
        }
    }

    perch::VideoCapturerKit *perchCapturer = (perch::VideoCapturerKit *)capturer;
    perchCapturer->SetCaptureHandler(_videoCapturer);
    perchCapturer->SetOwner(self);
    _rtcCapturer = perchCapturer;

    _rtcCapturerScoped.reset(perchCapturer);
}

#endif // Not iPhone Simulator

- (void)invalidate
{
    _rtcCapturer = nil;
//    [self.videoCapturer unprepareCapture];
}

#pragma mark - PHVideoCaptureConsumer

- (void)consumeFrame:(CMSampleBufferRef)frame
{
    // Send it to our custom cricket::videoCapturer subclass..

    if (_rtcCapturer) {
        _rtcCapturer->CopyCapturedFrame(frame);
    }
}

- (void)droppedFrame:(CMSampleBufferRef)frame
{
    if (_rtcCapturer) {
        _rtcCapturer->HandleDroppedFrame(frame);
    }
}

- (void)prepareForCaptureFormatChange
{
    // TODO: Inform our cricket::videoCapturer subclass of the impending format change.
}

@end

// iOS Device
#endif
