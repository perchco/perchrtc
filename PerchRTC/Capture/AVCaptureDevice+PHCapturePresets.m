//
//  AVCaptureDevice+PHCapturePresets.m
//  PerchRTC
//
//  Created by Christopher Eagleston on 2014-05-03.
//  Copyright (c) 2014 Perch Communications Inc. All rights reserved.
//

#import "AVCaptureDevice+PHCapturePresets.h"

@implementation AVCaptureDevice (PHCapturePresets)

- (AVCaptureDeviceFormat *)determineBestDeviceFormatForPreset:(PHCapturePreset)capturePreset
{
    NSArray *formats = self.formats;
    AVCaptureDeviceFormat *bestFormat = nil;

    CMVideoDimensions targetDimensions = [[self class] dimensionsForPreset:capturePreset];
    CMPixelFormatType targetPixelFormatType = kCVPixelFormatType_420YpCbCr8BiPlanarFullRange;

    // The list of device formats is always ordered in ascending resolution.

    for (AVCaptureDeviceFormat *format in formats) {
        CMVideoFormatDescriptionRef formatDescription = format.formatDescription;
        CMVideoDimensions videoDimensions = CMVideoFormatDescriptionGetDimensions(formatDescription);
        CMPixelFormatType pixelFormatType = CMFormatDescriptionGetMediaSubType(formatDescription);

        BOOL match = videoDimensions.width == targetDimensions.width
        && videoDimensions.height == targetDimensions.height
        && pixelFormatType == targetPixelFormatType;

        if (match) {

            if (!bestFormat) {
                bestFormat = format;
            }
            else {
                CGFloat fieldOfView = format.videoFieldOfView;
                BOOL isBinned = format.isVideoBinned;
                CGFloat zoomUpscaleThreshold = format.videoZoomFactorUpscaleThreshold;

                BOOL isBetterMatch = fieldOfView >= bestFormat.videoFieldOfView;
                isBetterMatch &= !isBinned;
                isBetterMatch &= zoomUpscaleThreshold >= bestFormat.videoZoomFactorUpscaleThreshold;

                if (isBetterMatch) {
                    bestFormat = format;
                }
            }
        }
    }

    DDLogInfo(@"Best device format was: %@", bestFormat);
    
    return bestFormat;
}

+ (CMVideoDimensions)dimensionsForPreset:(PHCapturePreset)preset
{
    BOOL supported = !(preset == PHCapturePresetWideLowQuality || preset == PHCapturePresetWideMediumQuality);

    NSAssert(supported, @"Capture preset is not implemented.");

    CMVideoDimensions matchingDimensions = {640, 480};

    if (preset == PHCapturePresetAcademyExtraLowQuality) {
        matchingDimensions.width = 352;
        matchingDimensions.height = 288;
    }
    else if (preset == PHCapturePresetAcademyLowQuality) {
        matchingDimensions.width = 480;
        matchingDimensions.height = 360;
    }
    else if (preset == PHCapturePresetAcademyMediumQuality) {
        matchingDimensions.width = 640;
        matchingDimensions.height = 480;
    }
    else if (preset == PHCapturePresetAcademyHighQuality) {
        matchingDimensions.width = 1280;
        matchingDimensions.height = 960;
    }
    else if (preset == PHCapturePresetWideHighQuality) {
        matchingDimensions.width = 960;
        matchingDimensions.height = 540;
    }
    else if (preset == PHCapturePresetWideExtraHighQuality) {
        matchingDimensions.width = 1280;
        matchingDimensions.height = 720;
    }

    return matchingDimensions;
}

@end
