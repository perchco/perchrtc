//
//  RTCMediaStream+PHStreamConfiguration.h
//  PerchRTC
//
//  Created by Christopher Eagleston on 2014-10-04.
//  Copyright (c) 2014 Perch Communications. All rights reserved.
//

#import "RTCMediaStream.h"

/**
 *  Helper methods on RTCMediaStream which allow you to easily enable and disable audio/video.
 *  @Note: These methods assume your stream contains no more than 1 audio and 1 video track.
 */
@interface RTCMediaStream (PHStreamConfiguration)

@property (nonatomic, assign, getter = isAudioEnabled) BOOL audioEnabled;
@property (nonatomic, assign, getter = isVideoEnabled) BOOL videoEnabled;

@end
