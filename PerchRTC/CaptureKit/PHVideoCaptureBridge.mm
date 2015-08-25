//
//  PHVideoCaptureBridge.cpp
//  PerchRTC
//
//  Created by Christopher Eagleston on 2014-11-08.
//  Copyright (c) 2014 Perch Communications. All rights reserved.
//

#if !TARGET_IPHONE_SIMULATOR

#include "PHVideoCaptureBridge.h"

#include "talk/media/base/videocommon.h"
#include "talk/media/base/videoframe.h"
#include "webrtc/base/timeutils.h"
#include "third_party/libyuv/include/libyuv/convert.h"
#ifdef HAVE_WEBRTC_VIDEO
#include "talk/media/webrtc/webrtcvideoframefactory.h"
#include "webrtc/modules/video_capture/include/video_capture_factory.h"
#endif

#include "webrtc/base/bind.h"

static BOOL VideoCaptureKitUsePooledMemory = YES;

using std::endl;

namespace perch {

    VideoCapturerKit::VideoCapturerKit()
    : _startThread(nullptr)
    {
        _initialTimestamp = time(NULL) * rtc::kNumNanosecsPerSec;
        _nextTimestamp = rtc::kNumNanosecsPerMillisec;

#ifdef HAVE_WEBRTC_VIDEO
        if (VideoCaptureKitUsePooledMemory) {
            set_frame_factory(new cricket::WebRtcPooledVideoFrameFactory());
        }
        else {
            set_frame_factory(new cricket::WebRtcVideoFrameFactory());
        }
#endif
    }

    VideoCapturerKit::~VideoCapturerKit()
    {
        if (_planarFrame.data) {
            free(_planarFrame.data);
        }
//        SignalStateChange(this, capture_state());
        [_owner invalidate];
    }

    cricket::CaptureState VideoCapturerKit::Start(const cricket::VideoFormat& capture_format)
    {
        try {
            if (capture_state() == cricket::CS_RUNNING) {
//                WarnL << "Start called when it's already started." << endl;
                return capture_state();
            }

            // Keep track of which thread capture started on. This is the thread that
            // frames need to be sent to.
            DCHECK(!_startThread);
            _startThread = rtc::Thread::Current();

            _frameDuration = capture_format.interval;

            [_captureHandler prepareForCapture];
            [_captureHandler startCapturing];

            SetCaptureFormat(&capture_format);
            return cricket::CS_RUNNING;
        } catch (...) {}
        return cricket::CS_FAILED;
    }

    void VideoCapturerKit::Stop()
    {
        try {
            if (capture_state() == cricket::CS_STOPPED) {
                return;
            }
            [_captureHandler stopCapturing];

            SetCaptureFormat(NULL);
            _startThread = nullptr;
            SetCaptureState(cricket::CS_STOPPED);
            return;
        } catch (...) {}
        return;
    }

    void VideoCapturerKit::CopyCapturedFrame(CMSampleBufferRef incomingBuffer)
    {
        CVPixelBufferRef videoFrame = CMSampleBufferGetImageBuffer(incomingBuffer);

        const int kYPlaneIndex = 0;
        const int kUVPlaneIndex = 1;

        size_t width = CVPixelBufferGetWidthOfPlane(videoFrame, kYPlaneIndex);
        size_t yPlaneHeight = CVPixelBufferGetHeightOfPlane(videoFrame, kYPlaneIndex);
        CMSampleTimingInfo info;
        CMSampleBufferGetSampleTimingInfo(incomingBuffer, 0, &info);
        int64 timestamp = CMTimeGetSeconds(info.presentationTimeStamp) * rtc::kNumNanosecsPerSec;

        if (capture_state() == cricket::CS_STOPPED) {
            NSLog(@"Tried to copy a frame while stopped %@.", incomingBuffer);
            return;
        }

        // Format Conversion

#if 1
        _planarFrame.time_stamp = timestamp;
        _planarFrame.elapsed_time = _nextTimestamp;
        _planarFrame.width = (int)width;
        _planarFrame.height = (int)yPlaneHeight;

        if (VideoCaptureKitUsePooledMemory) {
            // Our pooled frame factory will convert the buffer, locking as needed.

            _planarFrame.nativeHandle = incomingBuffer;
        }
        else {
            // Deliver an unpadded I420 frame which can be understood by the default frame factory.

            CVPixelBufferLockBaseAddress(videoFrame, kCVPixelBufferLock_ReadOnly);

            uint8_t *baseAddress = (uint8_t*)CVPixelBufferGetBaseAddressOfPlane(videoFrame, kYPlaneIndex);
            uint8_t *uvAddress = (uint8_t*)CVPixelBufferGetBaseAddressOfPlane(videoFrame, kUVPlaneIndex);
            size_t yPlaneBytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(videoFrame, kYPlaneIndex);
            size_t uvPlaneBytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(videoFrame, kUVPlaneIndex);
            size_t uvPlaneHeight = CVPixelBufferGetHeightOfPlane(videoFrame, kUVPlaneIndex);
            size_t chromaWidth = CVPixelBufferGetWidthOfPlane(videoFrame, kUVPlaneIndex);

            size_t ySize = (size_t)(width * yPlaneHeight);
            size_t uSize = (size_t)(chromaWidth * uvPlaneHeight);
            uint8 *yBuffer = (uint8 *)_planarFrame.data;
            uint8 *uBuffer = &yBuffer[ySize];
            uint8 *vBuffer = &yBuffer[ySize + uSize];

            libyuv::NV12ToI420(baseAddress, (int)yPlaneBytesPerRow,
                               uvAddress, (int)uvPlaneBytesPerRow,
                               yBuffer, (int)width,
                               uBuffer, (int)chromaWidth,
                               vBuffer, (int)chromaWidth,
                               (int)width, (int)yPlaneHeight);

            CVPixelBufferUnlockBaseAddress(videoFrame, kCVPixelBufferLock_ReadOnly);
        }

        // Signal the captured frame.

        if (_startThread->IsCurrent()) {
            SignalFrameCaptured(this, &_planarFrame);
        } else {
            _startThread->Invoke<void>(
                                       rtc::Bind(&VideoCapturerKit::SignalFrameCapturedOnStartThread,
                                                 this, &_planarFrame));
        }

#else
        int frameSize = yPlaneBytesPerRow * yPlaneHeight + uvPlaneBytesPerRow * uvPlaneHeight;
        cricket::CapturedFrame frame;
        frame.width = CVPixelBufferGetWidth(videoFrame);
        frame.height = CVPixelBufferGetHeight(videoFrame);
        frame.fourcc = cricket::FOURCC_NV12;
        frame.data_size = frameSize;
        frame.data = baseAddress;
        frame.time_stamp = timestamp;
        frame.elapsed_time = _nextTimestamp;

        if (_startThread->IsCurrent()) {
            SignalFrameCaptured(this, &frame);
        } else {
            _startThread->Invoke<void>(
                                       rtc::Bind(&VideoCapturerKit::SignalFrameCapturedOnStartThread,
                                                 this, &frame));
        }

        CVPixelBufferUnlockBaseAddress(videoFrame, kCVPixelBufferLock_ReadOnly);

#endif
        _nextTimestamp += _frameDuration;

    }

    void VideoCapturerKit::SignalFrameCapturedOnStartThread(const cricket::CapturedFrame* frame)
    {
        DCHECK(_startThread->IsCurrent());
        SignalFrameCaptured(this, frame);
    }

    void VideoCapturerKit::HandleDroppedFrame(CMSampleBufferRef droppedFrame)
    {
        _nextTimestamp += _frameDuration;
    }

    void VideoCapturerKit::SetCaptureHandler(id<PHVideoCapture> captureHandler)
    {
        this->_captureHandler = captureHandler;

        // Default supported formats. Use ResetSupportedFormats to over write.

        PHVideoFormat captureFormat = [captureHandler videoCaptureFormat];

        std::vector<cricket::VideoFormat> formats;
        formats.push_back(cricket::VideoFormat(captureFormat.dimensions.width,
                                               captureFormat.dimensions.height,
                                               cricket::VideoFormat::FpsToInterval(captureFormat.frameRate),
                                               cricket::FOURCC_NV12));
        _formats = formats;
    }

    void VideoCapturerKit::SetOwner(PHVideoCaptureKit *captureKitOwner)
    {
        this->_owner = captureKitOwner;
    }

    bool VideoCapturerKit::IsRunning()
    {
        return this->_captureHandler.isCapturing;
    }

    bool VideoCapturerKit::GetPreferredFourccs(std::vector<uint32>* fourccs)
    {
        if (fourccs) {
            fourccs->push_back(cricket::FOURCC_NV12);
        }
        return (fourccs != NULL);
    }

    bool VideoCapturerKit::GetBestCaptureFormat(const cricket::VideoFormat& desired, cricket::VideoFormat* best_format)
    {
        if (!best_format) {
            return false;
        }
        
        // VideoCapturerKit does not support capability enumeration.
        // Use the desired format as the best format.

        cricket::VideoFormat supportedFormat = _formats.front();

        bool resolutionMatch = supportedFormat.width == desired.width && supportedFormat.height == desired.height;

        if (resolutionMatch) {
            best_format->width = desired.width;
            best_format->height = desired.height;
        }
        else {
            best_format->width = supportedFormat.width;
            best_format->height = supportedFormat.height;
        }

        best_format->fourcc = supportedFormat.fourcc;
        best_format->interval = supportedFormat.interval;

        // Setup a temporary conversion buffer.

        int planarBufferSize = 1.5 * (best_format->width * best_format->height);
        _planarFrame.data_size = planarBufferSize;
        _planarFrame.width = best_format->width;
        _planarFrame.height = best_format->height;

        if (VideoCaptureKitUsePooledMemory) {
            _planarFrame.fourcc = cricket::FOURCC_NV12;
            _planarFrame.data = NULL;
        }
        else {
            _planarFrame.fourcc = cricket::FOURCC_I420;
            _planarFrame.data = malloc(planarBufferSize);
        }

        return true;
    }
    
    bool VideoCapturerKit::IsScreencast() const
    {
        // We don't support screencasts.

        return false;
    }

} // namespace perch

// iOS Device
#endif