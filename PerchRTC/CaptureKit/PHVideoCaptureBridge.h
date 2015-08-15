//
//  PHVideoCapturerBridge.h
//  PerchRTC
//
//  Created by Christopher Eagleston on 2014-11-08.
//  Copyright (c) 2014 Perch Communications. All rights reserved.
//

#ifndef PerchRTC_PHVideoCapturerBridge_h
#define PerchRTC_PHVideoCapturerBridge_h

#if !TARGET_IPHONE_SIMULATOR

#import <CoreMedia/CoreMedia.h>

#include <string.h>
#include <vector>

#include "talk/media/base/videocapturer.h"

#import "PHVideoCaptureKit.h"

namespace perch {

    class VideoCapturerKit : public cricket::VideoCapturer
    {
    public:

        // Constructor, destructor.

        VideoCapturerKit();
        virtual ~VideoCapturerKit();

        void SetCaptureHandler(id<PHVideoCapture> captureHandler);
        void SetOwner(PHVideoCaptureKit *captureKitOwner);

        // Inject captured frames.

        void CopyCapturedFrame(CMSampleBufferRef incomingFrame);
        void HandleDroppedFrame(CMSampleBufferRef droppedFrame);
        void SignalFrameCapturedOnStartThread(const cricket::CapturedFrame* frame);

        // cricket::VideoCapturer implementation.

        cricket::CaptureState Start(const cricket::VideoFormat& capture_format) override;
        void Stop() override;
        bool IsRunning() override;
        bool GetPreferredFourccs(std::vector<uint32>* fourccs) override;
        bool GetBestCaptureFormat(const cricket::VideoFormat& desired,
                                          cricket::VideoFormat* best_format) override;
        bool IsScreencast() const override;
        
    private:
        rtc::Thread* _startThread;  // Set in Start(), unset in Stop().
        id<PHVideoCapture> _captureHandler;
        PHVideoCaptureKit *_owner;
        int64 _initialTimestamp;
        int64 _nextTimestamp;
        int64 _frameDuration;
        cricket::CapturedFrame _planarFrame;
        std::vector<cricket::VideoFormat> _formats;

        DISALLOW_COPY_AND_ASSIGN(VideoCapturerKit);
    };

    class VideoCapturerKitFactory : public cricket::VideoDeviceCapturerFactory
    {
    public:
        VideoCapturerKitFactory() {}
        ~VideoCapturerKitFactory() {}

        cricket::VideoCapturer* Create(const cricket::Device& device) {

            // XXX: WebRTC uses device name to instantiate the capture, which is always 0.
            return new VideoCapturerKit();
        }
    };
 
} // namespace perch

#endif

#endif
