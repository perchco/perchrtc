//
//  PHSessionDescriptionFactory.h
//  PerchRTC
//
//  Created by Christopher Eagleston on 2015-01-17.
//  Copyright (c) 2015 Perch Communications. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "PHMediaSession.h"
#import "PHFormats.h"

@class RTCMediaConstraints;

@interface PHSessionDescriptionFactory : NSObject

+ (RTCMediaConstraints *)offerConstraints;

+ (RTCMediaConstraints *)offerConstraintsRestartIce:(BOOL)restartICE;

+ (RTCMediaConstraints *)connectionConstraints;

+ (RTCMediaConstraints *)videoConstraints;

+ (RTCMediaConstraints *)videoConstraintsForFormat:(PHVideoFormat)videoFormat;

+ (RTCSessionDescription *)conditionedSessionDescription:(RTCSessionDescription *)sessionDescription
                                              audioCodec:(PHAudioCodec)audioCodec
                                              videoCodec:(PHVideoCodec)videoCodec
                                            videoBitRate:(NSUInteger)videoBitRate
                                            audioBitRate:(NSUInteger)audioBitRate;


@end
