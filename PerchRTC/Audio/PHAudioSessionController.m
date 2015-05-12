//
//  PHAudioSessionController.m
//  PerchRTC
//
//  Created by Christopher Eagleston on 2014-08-16.
//  Copyright (c) 2014 Perch Communications Inc. All rights reserved.
//

#import "PHAudioSessionController.h"

#import "UIDevice+PHDeviceAdditions.h"

@import AVFoundation;

@interface PHAudioSessionController()

@property (nonatomic, strong) AVAudioSession *audioSession;

@property (nonatomic, assign) PHAudioSessionMode sessionMode;

@property (nonatomic, assign, getter = isAudioInterrupted) BOOL audioInterrupted;

@property (nonatomic, assign, getter = isMediaServerRestarting) BOOL mediaServerRestarting;

@end

@implementation PHAudioSessionController

#pragma mark - Initialize & Dealloc

- (instancetype)init
{
    return [self initWithAudioSession:[AVAudioSession sharedInstance]];
}

- (instancetype)initWithAudioSession:(AVAudioSession *)session
{
    self = [super init];

    if (self) {
        _audioSession = session;
        _sessionMode = PHAudioSessionModeAmbient;
        _mediaServerRestarting = NO;
        _audioInterrupted = NO;

        [self registerForNotifications];
    }

    return self;
}

- (void)dealloc
{
    [self unregisterForNotifications];
}

#pragma mark - NSObject

- (BOOL)isEqual:(id)object
{
    BOOL equal = NO;

    if ([object isKindOfClass:[PHAudioSessionController class]]) {
        PHAudioSessionController *otherController = (PHAudioSessionController *)object;
        equal = [self.audioSession isEqual:otherController.audioSession];
    }

    return equal;
}

#pragma mark - Class methods

+ (instancetype)sharedController
{
    static PHAudioSessionController *controller = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        controller = [[PHAudioSessionController alloc] init];
    });

    return controller;
}

#pragma mark - Public

- (NSError *)activateWithAudioMode:(PHAudioSessionMode)sessionMode
{
    return [self activateSession:YES withAudioMode:sessionMode];
}

- (NSError *)deactivateSession
{
    DDLogVerbose(@"Deactivate audio session with mode: %lu", (unsigned long)self.sessionMode);

    NSError *deactiveError = nil;

    [self.audioSession setActive:NO withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation error:&deactiveError];

    return deactiveError;
}

- (NSError *)deactivateSessionWithAudioMode:(PHAudioSessionMode)sessionMode
{
    return [self activateSession:NO withAudioMode:sessionMode];
}

#pragma mark - Private

- (void)activateAudioSession
{
    [self activateSession:YES withAudioMode:self.sessionMode];
}

- (NSError *)activateSession:(BOOL)active withAudioMode:(PHAudioSessionMode)sessionMode
{
    DDLogVerbose(@"Activate audio session with mode: %lu", (unsigned long)sessionMode);

    if (self.mediaServerRestarting) {
        DDLogVerbose(@"Media server is restarting, delaying activation.");

        self.sessionMode = sessionMode;

        // TODO - Return interrupted error.

        return nil;
    }

    NSError *modeError = nil;
    NSError *categoryError = nil;
    NSError *activeError = nil;
    NSError *returnError = nil;
    NSError *overrideError = nil;
    NSString *category = nil;
    NSString *mode = nil;
    AVAudioSessionPortOverride outputPortOverride = AVAudioSessionPortOverrideNone;
    AVAudioSession *audioSession = self.audioSession;

    if (sessionMode == PHAudioSessionModeVoiceStreaming) {
        category = AVAudioSessionCategoryPlayAndRecord;
        mode = AVAudioSessionModeVoiceChat;
    }
    else if (sessionMode == PHAudioSessionModeMediaStreaming) {
        category = AVAudioSessionCategoryPlayAndRecord;
        mode = AVAudioSessionModeVideoChat;
    }
    else if (sessionMode == PHAudioSessionModePlayback) {
        category = AVAudioSessionCategoryPlayback;
        mode = AVAudioSessionModeMoviePlayback;
    }
    else if (sessionMode == PHAudioSessionModeAmbient) {
        category = AVAudioSessionCategorySoloAmbient;
        mode = AVAudioSessionModeDefault;
    }

    [audioSession setCategory:category error:&categoryError];
    [audioSession setMode:mode error:&modeError];
    [audioSession overrideOutputAudioPort:outputPortOverride error:&overrideError];

    AVAudioSessionSetActiveOptions options = !active ? AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation : 0;
    [audioSession setActive:active withOptions:options error:&activeError];

    if (modeError) {
        DDLogError(@"Error changing audio session mode: %@", modeError);
        returnError = modeError;
    }
    if (categoryError) {
        DDLogError(@"Error changing audio session category: %@", categoryError);
        returnError = categoryError;
    }
    if (activeError) {
        DDLogError(@"Error activating the audio session: %@", activeError);
        returnError = activeError;
    }
    if (overrideError) {
        DDLogError(@"Error overriding the audio output port: %@", overrideError);
        returnError = overrideError;
    }

    self.sessionMode = sessionMode;
    
    return returnError;
}

- (void)registerForNotifications
{
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    AVAudioSession *session = self.audioSession;

    [center addObserver:self selector:@selector(mediaResetNotification:) name:AVAudioSessionMediaServicesWereResetNotification object:session];
    [center addObserver:self selector:@selector(mediaLostNotification:) name:AVAudioSessionMediaServicesWereLostNotification object:session];
    [center addObserver:self selector:@selector(audioInterruptionNotification:) name:AVAudioSessionInterruptionNotification object:session];
    [center addObserver:self selector:@selector(audioRouteChangeNotification:) name:AVAudioSessionRouteChangeNotification object:session];
}

- (void)unregisterForNotifications
{
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    AVAudioSession *session = self.audioSession;
    NSArray *notificationNames = @[AVAudioSessionMediaServicesWereResetNotification, AVAudioSessionMediaServicesWereLostNotification, AVAudioSessionInterruptionNotification, AVAudioSessionRouteChangeNotification];

    for (NSString *notificationName in notificationNames) {
        [center removeObserver:self name:notificationName object:session];
    }
}

// https://developer.apple.com/library/ios/qa/qa1749/_index.html
- (void)mediaResetNotification:(NSNotification *)note
{
    self.mediaServerRestarting = NO;
    self.audioInterrupted = NO;

    [self activateAudioSession];

    DDLogVerbose(@"Media services were reset.");
}

- (void)mediaLostNotification:(NSNotification *)note
{
    self.mediaServerRestarting = YES;
    self.audioInterrupted = NO;

    DDLogVerbose(@"Media services were lost.");
}

// https://developer.apple.com/library/ios/documentation/Audio/Conceptual/AudioSessionProgrammingGuide/HandlingAudioInterruptions/HandlingAudioInterruptions.html
- (void)audioInterruptionNotification:(NSNotification *)note
{
    NSDictionary *userInfo = note.userInfo;
    AVAudioSessionInterruptionOptions interruptionOptions = [userInfo[AVAudioSessionInterruptionOptionKey] unsignedIntegerValue];
    AVAudioSessionInterruptionType interruptionType = [userInfo[AVAudioSessionInterruptionTypeKey] unsignedIntegerValue];

    if (interruptionType == AVAudioSessionInterruptionTypeEnded && interruptionOptions == AVAudioSessionInterruptionOptionShouldResume) {
//        [self activateAudioSession];
    }
    else if (interruptionType == AVAudioSessionInterruptionTypeBegan) {
        // Let others know about the interruption?
    }

    self.audioInterrupted = interruptionType == AVAudioSessionInterruptionTypeBegan ? YES : NO;

    DDLogVerbose(@"Audio interruption with info: %@", userInfo);
}

- (void)audioRouteChangeNotification:(NSNotification *)note
{
    NSDictionary *userInfo = note.userInfo;
    AVAudioSessionRouteChangeReason reason = [userInfo[AVAudioSessionRouteChangeReasonKey] unsignedIntegerValue];

    switch (reason) {
        case AVAudioSessionRouteChangeReasonUnknown:
            break;
        case AVAudioSessionRouteChangeReasonNewDeviceAvailable:
            break;
        case AVAudioSessionRouteChangeReasonOldDeviceUnavailable:
            break;
        case AVAudioSessionRouteChangeReasonCategoryChange:
            DDLogVerbose(@"Audio Category Change!");
            [self checkAudioMode];
            break;
        case AVAudioSessionRouteChangeReasonOverride:
            DDLogVerbose(@"Audio Override!");
            break;
        case AVAudioSessionRouteChangeReasonWakeFromSleep:
            break;
        case AVAudioSessionRouteChangeReasonNoSuitableRouteForCategory:
            DDLogError(@"No audio route for category: %@", self.audioSession.category);
            break;
        case AVAudioSessionRouteChangeReasonRouteConfigurationChange:
            DDLogVerbose(@"Route configuration change!");
            break;
        default:
            break;
    }

    DDLogVerbose(@"Audio route changed with reason: %lu info: %@", (unsigned long)reason, userInfo);
}

- (void)checkAudioMode
{
    if (self.sessionMode == PHAudioSessionModeAmbient) {
        [self activateWithAudioMode:PHAudioSessionModeMediaStreaming];
    }
}

@end
