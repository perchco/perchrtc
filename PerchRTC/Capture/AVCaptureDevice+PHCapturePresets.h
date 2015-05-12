//
//  AVCaptureDevice+PHCapturePresets.h
//  PerchRTC
//
//  Created by Christopher Eagleston on 2014-05-03.
//  Copyright (c) 2014 Perch Communications Inc. All rights reserved.
//

@import AVFoundation;

typedef NS_ENUM(NSUInteger, PHCapturePreset) {

    /**
     *  Produces a low quality 4:3 output (352x288) suitable for older devices.
     */
    PHCapturePresetAcademyExtraLowQuality = 0,

    /**
     *  Produces a low quality 4:3 output (480x360) suitable for older devices.
     */
    PHCapturePresetAcademyLowQuality = 1,

    /**
     *  Produces a medium quality 4:3 output (640x480) suitable for modern devices.
     */
    PHCapturePresetAcademyMediumQuality = 2,

    /**
     *  Produces a high quality 4:3 output (1280x960).
     */
    PHCapturePresetAcademyHighQuality = 3,

    /**
     *  Produces a low quality 16:9 output (480x270) suitable for older devices. (Not implemented, would require scaling.)
     */
    PHCapturePresetWideLowQuality = 4,

    /**
     *  Produces a medium quality 16:9 output (640x360). (Not implemented, would require scaling).
     */
    PHCapturePresetWideMediumQuality = 5,

    /**
     *  Produces a high quality 16:9 540p output (960x540).
     */
    PHCapturePresetWideHighQuality = 6,

    /**
     *  Produces a high quality 16:9 720p output (1280x720).
     */
    PHCapturePresetWideExtraHighQuality = 7,
};

@interface AVCaptureDevice (PHCapturePresets)

/**
 *  Determines the best video capture device format for a given capture preset.
 *  @note The pixel format must be kCVPixelFormatType_420YpCbCr8BiPlanarFullRange for now.
 *  The algorithm prefers (in order) a larger FOV, un-binned video, and a larger zoom upscale threshold.
 *
 *  @param capturePreset The capture preset to use.
 *
 *  @return A suitable capture device format, or nil no match was found.
 */
- (AVCaptureDeviceFormat *)determineBestDeviceFormatForPreset:(PHCapturePreset)capturePreset;

/**
 *  Returns the dimensions that correspond to a give capture preset.
 *
 *  @param preset The capture preset.
 *
 *  @return The capture preset's dimensions.
 */
+ (CMVideoDimensions)dimensionsForPreset:(PHCapturePreset)preset;

@end
