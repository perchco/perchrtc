//
//  PHMediaConfiguration.m
//  PerchRTC
//
//  Created by Christopher Eagleston on 2015-05-07.
//  Copyright (c) 2015 Perch Communications. All rights reserved.
//

#import "PHMediaConfiguration.h"

@implementation PHMediaConfiguration

+ (instancetype)defaultConfiguration
{
    PHMediaConfiguration *config = [[PHMediaConfiguration alloc] init];

    config.rendererType = PHRendererTypeSampleBuffer;
    config.iceFilter = PHIceFilterAny;
    config.iceProtocol = PHIceProtocolAny;
    config.maxAudioBitrate = PHMediaSessionMaximumAudioRate;
    config.preferredAudioCodec = PHAudioCodecOpus;

    PHVideoFormat format;
    format.dimensions = (CMVideoDimensions){640, 480};
    format.frameRate = 30;
    format.pixelFormat = PHPixelFormatYUV420BiPlanarFullRange;

    config.preferredReceiverFormat = format;

    return config;
}

- (instancetype)copyWithZone:(NSZone *)zone
{
    PHMediaConfiguration *copy = [[PHMediaConfiguration alloc] init];

    copy.rendererType = self.rendererType;
    copy.iceFilter = self.iceFilter;
    copy.iceProtocol = self.iceProtocol;
    copy.maxAudioBitrate = self.maxAudioBitrate;
    copy.preferredAudioCodec = self.preferredAudioCodec;
    copy.preferredReceiverFormat = self.preferredReceiverFormat;

    return copy;
}

@end
