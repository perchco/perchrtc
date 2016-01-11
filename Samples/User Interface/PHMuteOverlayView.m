//
//  PHMuteOverlayView.m
//  PerchRTC
//
//  Created by Sam Symons on 2014-12-30.
//  Copyright (c) 2014 Perch Communications Inc. All rights reserved.
//

#import "PHMuteOverlayView.h"

const CGFloat PHOverlayViewDisplayedAlpha = 0.60;
const CGFloat PHOverlayViewHiddenAlpha = 0.0;
const CGFloat PHOverlayViewMuteIconPadding = 23.0;

@interface PHMuteOverlayView ()

@property (nonatomic, strong) UIView *overlayView;
@property (nonatomic, strong) NSArray *imageViews;

- (UIImageView *)imageViewWithWithImageNamed:(NSString *)imageName;

@end

@implementation PHMuteOverlayView

- (instancetype)initWithMode:(PHAudioMode)mode
{
    self = [super initWithFrame:CGRectZero];
    
    if (self) {
        _imageViews = @[
                        [self imageViewWithWithImageNamed:@"mute-icon-muted"],
                        [self imageViewWithWithImageNamed:@"mute-icon-unmuted"] // no image for manual "on"
                        ];

        for (UIImageView *imageView in self.imageViews) {
            [self addSubview:imageView];
        }

        _mode = mode;

        [self showImageViewForMode:mode animated:NO];
    }
    
    return self;
}

#pragma mark - UIView

- (void)layoutSubviews
{
    [super layoutSubviews];
    
    self.overlayView.frame = self.bounds;

    [self layoutForMode:PHAudioModeMuted];
    [self layoutForMode:PHAudioModeOn];
}

#pragma mark - Properties

- (void)setMode:(PHAudioMode)mode
{
    _mode = mode;

    [self showImageViewForMode:mode];
}

- (UIView *)overlayView
{
    if (!_overlayView) {
        _overlayView = [[UIView alloc] init];
        _overlayView.backgroundColor = [UIColor blackColor];
        _overlayView.alpha = PHOverlayViewHiddenAlpha;
        
        [self insertSubview:_overlayView atIndex:0];
    }
    
    return _overlayView;
}

#pragma mark - Public

- (void)showImageViewForMode:(PHAudioMode)mode
{
    [self showImageViewForMode:mode animated:YES];
}

#pragma mark - Private

- (void)showImageViewForMode:(PHAudioMode)mode animated:(BOOL)animated
{
    UIImageView *imageViewForMode = self.imageViews[self.mode];
    NSTimeInterval duration = animated ? 0.2 : 0;

    [UIView animateWithDuration:duration animations:^{
        for (UIImageView *imageView in self.imageViews) {
            if (imageView == imageViewForMode) {
                imageView.alpha = 1.0;
            }
            else {
                imageView.alpha = 0;
            }
        }

        if (mode == PHAudioModeMuted) {
            self.overlayView.alpha = PHOverlayViewDisplayedAlpha;
        }
        else {
            self.overlayView.alpha = PHOverlayViewHiddenAlpha;
        }
    }];
}

- (UIImageView *)imageViewWithWithImageNamed:(NSString *)imageName
{
    UIImage *image = [UIImage imageNamed:imageName];
    UIImageView *imageView = [[UIImageView alloc] initWithImage:image];
    imageView.alpha = 0;
    
    return imageView;
}

- (void)layoutForMode:(PHAudioMode)mode
{
    UIImageView *imageView = self.imageViews[mode];
    CGRect bounds = self.bounds;

    CGPoint center = CGPointMake(CGRectGetWidth(bounds) - PHOverlayViewMuteIconPadding, CGRectGetHeight(bounds) - PHOverlayViewMuteIconPadding);

    imageView.center = center;
}

@end
