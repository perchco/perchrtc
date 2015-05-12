//
//  PHAudioSessionController.h
//  PerchRTC
//
//  Created by Christopher Eagleston on 2014-08-16.
//  Copyright (c) 2014 Perch Communications Inc. All rights reserved.
//

#import <Foundation/Foundation.h>

@class AVAudioSession;

typedef NS_ENUM(NSUInteger, PHAudioSessionMode)
{
    /**
     *  Ambient playback of sound effects, respecting the ringer setting.
     */
    PHAudioSessionModeAmbient = 0,
    /**
     *  Playback of important sound effects, defeating the ringer and interrupting other apps.
     */
    PHAudioSessionModePlayback = 1,
    /**
     *  Playback and recording of voice audio. Allows use of the iPhone earpiece speaker.
     */
    PHAudioSessionModeVoiceStreaming = 2,
    /**
     *  Playback and recording of voice audio, suitable for use with video.
     */
    PHAudioSessionModeMediaStreaming = 3,
};

@interface PHAudioSessionController : NSObject

@property (nonatomic, assign, readonly) PHAudioSessionMode sessionMode;

@property (nonatomic, assign, readonly, getter = isMediaServerRestarting) BOOL mediaServerRestarting;

@property (nonatomic, assign, readonly, getter = isAudioInterrupted) BOOL audioInterrupted;

- (instancetype)initWithAudioSession:(AVAudioSession *)session;

+ (instancetype)sharedController;

- (NSError *)activateWithAudioMode:(PHAudioSessionMode)sessionMode;

- (NSError *)deactivateSession;

- (NSError *)deactivateSessionWithAudioMode:(PHAudioSessionMode)sessionMode;

@end
