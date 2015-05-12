//
//  PHFrameConverter.h
//  PerchRTC
//
//  Created by Christopher Eagleston on 2/7/2014.
//  Copyright (c) 2014 Perch Communications. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreMedia/CoreMedia.h>
#import "RTCVideoRenderer.h"

@class RTCI420Frame;

typedef NS_ENUM(NSUInteger, PHFrameConverterOutput)
{
    PHFrameConverterOutputCGImageBackedByNSData = 0,                // Works. Slower than CVPixelBuffer backing, as our NSData is not shared with the GPU.
    PHFrameConverterOutputCGImageBackedByCVPixelBuffer = 1,         // Fastest option for CGImages. YUV->RGB is out of place, backing store is an IOSurface.
    PHFrameConverterOutputCGImageCopiedFromCVPixelBuffer = 2,       // Works. Slower than above because we have to do an additional copy to create a CGImage.
    PHFrameConverterOutputCMSampleBufferBackedByCVPixelBuffer = 3,  // Sample/pixel buffers is created properly, and is displayed on iOS 8.
    PHFrameConverterOutputCMSampleBufferBackedByCVPixelBufferBGRA = 4,  // Sample/pixel buffers is created properly, and needs testsing iOS 8.
    PHFrameConverterOutputCVPixelBufferCopiedFromSource = 5,        // Pixel buffer appears to be created properly. This could be useful with an OpenGL renderer.
};

@interface PHFrameConverter : NSObject

@property (nonatomic, assign, readonly) CGImageRef frameRef;
@property (nonatomic, assign, readonly) CVPixelBufferRef pixelBuffer;
@property (nonatomic, assign, readonly) CMSampleBufferRef sampleBuffer;
@property (nonatomic, assign, readonly) PHFrameConverterOutput outputType;
@property (nonatomic, assign) BOOL shouldPreallocateBuffers;

- (instancetype)initWithOutput:(PHFrameConverterOutput)output;
+ (instancetype)converterWithOutput:(PHFrameConverterOutput)output;

- (BOOL)prepareForSourceDimensions:(CMVideoDimensions)dimensions;

// Creates a CGImageRef, CVPixelBuffer, or CMSampleBufferRef. You must CFRelease this when you are finished with it.
- (CFTypeRef)copyConvertedFrame:(RTCI420Frame *)frame;
// Gets rid of the output.
- (void)flushFrame;

+ (PHFrameConverterOutput)recommendedOutputFormat;

@end
