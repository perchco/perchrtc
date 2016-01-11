//
//  RTCMediaStream+PHStreamConfiguration.m
//  PerchRTC
//
//  Created by Christopher Eagleston on 2014-10-04.
//  Copyright (c) 2014 Perch Communications. All rights reserved.
//

#import "RTCMediaStream+PHStreamConfiguration.h"
#import "RTCAudioTrack.h"
#import "RTCVideoTrack.h"

@implementation RTCMediaStream (PHStreamConfiguration)

- (BOOL)isAudioEnabled
{
    RTCAudioTrack *audioTrack = [self.audioTracks firstObject];
    return audioTrack ? audioTrack.isEnabled : YES;
}

- (void)setAudioEnabled:(BOOL)audioEnabled
{
    RTCAudioTrack *audioTrack = [self.audioTracks firstObject];
    [audioTrack setEnabled:audioEnabled];
}

- (BOOL)isVideoEnabled
{
    RTCVideoTrack *videoTrack = [self.videoTracks firstObject];
    return videoTrack ? videoTrack.isEnabled : YES;
}

- (void)setVideoEnabled:(BOOL)videoEnabled
{
    RTCVideoTrack *videoTrack = [self.videoTracks firstObject];
    [videoTrack setEnabled:videoEnabled];
}

@end
