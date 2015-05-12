//
//  PHFormats.h
//  PerchRTC
//
//  Created by Christopher Eagleston on 2014-11-17.
//  Copyright (c) 2014 Perch Communications. All rights reserved.
//

#ifndef PerchRTC_PHFormats_h
#define PerchRTC_PHFormats_h

#import <CoreMedia/CoreMedia.h>

typedef NS_ENUM(OSType, PHPixelFormat)
{
    PHPixelFormat32BGRA = kCVPixelFormatType_32BGRA,
    PHPixelFormatYUV420BiPlanarVideoRange = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
    PHPixelFormatYUV420BiPlanarFullRange = kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
};

typedef struct PHVideoFormat {
    CMVideoDimensions dimensions;
    PHPixelFormat pixelFormat;
    double frameRate;
} PHVideoFormat;

static double PHMediaSessionFrameWeightExponentDenominator = 3.5;

static inline NSUInteger PHVideoFormatComputePeakRate(PHVideoFormat format, double targetBpp, NSUInteger maxRate)
{
    // Perform a naive estimate of the maximum encoder rate suitable for the given video format.
    // Apply an exponential frame rate weighting so that lower FPS is not data starved.
    // Units are kbps.

    double frameRate = format.frameRate;
    double frameRateWeight = exp((30.0 - frameRate) / (PHMediaSessionFrameWeightExponentDenominator * frameRate));
    double pixelRate = (double)format.dimensions.width * (double)format.dimensions.height * frameRate;
    double recommendedRate = pixelRate * targetBpp * frameRateWeight;
    recommendedRate = MIN(recommendedRate, maxRate);

    return round(recommendedRate);
}

#endif
