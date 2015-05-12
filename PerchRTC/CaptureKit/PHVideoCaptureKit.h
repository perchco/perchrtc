//
//  PHVideoCapturer.h
//  PerchRTC
//
//  Created by Christopher Eagleston on 2014-10-04.
//  Copyright (c) 2014 Perch Communications. All rights reserved.
//

#if !TARGET_IPHONE_SIMULATOR

#import <Foundation/Foundation.h>

#import "PHFormats.h"

@protocol PHVideoCaptureConsumer <NSObject>

/**
 *  Provides a frame to the capture consumer. 
*   @note By the time this method returns the consumer will have copied the contents of the sample buffer.
 *
 *  @param frame A CMSampleBufferRef containing a CVPixelBufferRef.
 */
- (void)consumeFrame:(CMSampleBufferRef)frame;

- (void)droppedFrame:(CMSampleBufferRef)frame;

/**
 *  Allows for you to inform the capture consumer that a format change is coming.
 *  At this point you should be ready for clients to query your updated format.
 */
- (void)prepareForCaptureFormatChange;

@end

@protocol PHVideoCapture <NSObject>

@property (nonatomic, assign, readonly, getter = isCapturing) BOOL capturing;

/**
 * The consumer of the video capturer's frames.
 */
@property (atomic, assign) id<PHVideoCaptureConsumer> videoCaptureConsumer;

/**
 *  Prepare to capture video. If you are running an AVCaptureSession you should select a device, format, and add outputs now.
 */
- (void)prepareForCapture;

/**
 *  Destroy expensive resources related to capture now.
 */
- (void)unprepareCapture;

/**
 *  Start your capture session, and begin delivering frames to the capture consumer as soon as possible.
 */
- (void)startCapturing;

/**
 *  Stop your capture session, and do not deliver any more frames to the capture consumer.
 */
- (void)stopCapturing;

- (PHVideoFormat)videoCaptureFormat;

@end

/**
 *  PHVideoCaptureKit allows you to provide your own video capture implementation in place of RTCVideoCapturer.
 */
@interface PHVideoCaptureKit : NSObject

@property (nonatomic, weak, readonly) id<PHVideoCapture> videoCapturer;

- (void)invalidate;

/**
 *  Initializes a capture kit instance.
 *
 *  @param capturer An object which implements the PHVideoCapture protocol.
 *
 *  @return A PHVideoCaptureKit instance which is bound to the capturer instance.
 */
- (instancetype)initWithCapturer:(id<PHVideoCapture>)capturer;

@end

#endif
