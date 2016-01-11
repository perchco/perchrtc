//
//  PHMuteOverlayView.h
//  PerchRTC
//
//  Created by Sam Symons on 2014-12-30.
//  Copyright (c) 2014 Perch Communications Inc. All rights reserved.
//

typedef NS_ENUM(NSInteger, PHAudioMode) {
    PHAudioModeMuted = 0,
    PHAudioModeOn = 1
};

@interface PHMuteOverlayView : UIView

- (instancetype)initWithMode:(PHAudioMode)mode;

@property (nonatomic, assign) PHAudioMode mode;

@end
