//
//  PHMediaConfiguration.h
//  PerchRTC
//
//  Created by Christopher Eagleston on 2015-05-07.
//  Copyright (c) 2015 Perch Communications. All rights reserved.
//

#import "PHFormats.h"

typedef NS_OPTIONS(NSUInteger, PHRendererType)
{
    PHRendererTypeSampleBuffer,
    PHRendererTypeOpenGLES,
    PHRendererTypeQuartz
};

typedef NS_ENUM(NSUInteger, PHAudioCodec)
{
    /* The Opus audio codec is wideband, and higher quality. */
    PHAudioCodecOpus = 0,
    /* ISAC is lower quality, but more compatible. */
    PHAudioCodecISAC = 1
};

typedef NS_ENUM(NSUInteger, PHVideoCodec)
{
    /* Stable, software VP8 encode & decode via libvpx */
    PHVideoCodecVP8 = 0,
    /* Experimental, hardware H.264 encode & decode via VideoToolbox. */
    PHVideoCodecH264 = 1
};

typedef NS_OPTIONS(NSUInteger, PHIceFilter)
{
    PHIceFilterLocal = (1UL << 0),
    PHIceFilterStun = (1UL << 1),
    PHIceFilterTurn = (1UL << 2),
    PHIceFilterAny = (PHIceFilterStun | PHIceFilterTurn | PHIceFilterLocal)
};

typedef NS_OPTIONS(NSUInteger, PHIceProtocol)
{
    /* You must choose at least one protocol. */
    PHIceProtocolNone = 0,
    PHIceProtocolUDP = (1UL << 0),
    PHIceProtocolTCP = (1UL << 1),
    PHIceProtocolAny = (PHIceProtocolUDP | PHIceProtocolTCP)
};

static NSUInteger PHMediaSessionMaximumAudioRate = 64;
static NSUInteger PHMediaSessionMaximumAudioRateMultiparty = 48;
static NSUInteger PHMediaSessionMaximumVideoRate = 1000;
static double PHMediaSessionTargetBpp = 0.00008403125;

@interface PHMediaConfiguration : NSObject <NSCopying>

/*
 Defaults:
 PHIceFilterAny
 PHIceProtocolAny
 PHAudioCodecOpus
 PHVideoCodecVP8
 640x480 @ 30 fps, Bi-Planar Full Range 
 */
+ (instancetype)defaultConfiguration;

@property (nonatomic, assign) PHRendererType rendererType;
@property (nonatomic, assign) PHIceFilter iceFilter;
@property (nonatomic, assign) PHIceProtocol iceProtocol;
@property (nonatomic, assign) PHAudioCodec preferredAudioCodec;
@property (nonatomic, assign) PHVideoCodec preferredVideoCodec;
@property (nonatomic, assign) NSUInteger maxAudioBitrate;
@property (nonatomic, assign) PHVideoFormat preferredReceiverFormat;

@end
