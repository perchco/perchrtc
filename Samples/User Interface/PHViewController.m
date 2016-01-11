//
//  PHViewController.m
//  PerchRTC
//
//  Created by Christopher Eagleston on 2014-08-09.
//  Copyright (c) 2014 Perch Communications. All rights reserved.
//

#import "PHViewController.h"

#import "PHConnectionBroker.h"
#import "PHCredentials.h"
#import "PHEAGLRenderer.h"
#import "PHErrors.h"
#import "PHMediaConfiguration.h"
#import "PHMuteOverlayView.h"
#import "PHQuartzVideoView.h"
#import "PHSampleBufferRenderer.h"
#import "PHSampleBufferView.h"
#import "PHSettingsViewController.h"
#import "XSPeer.h"
#import "XSRoom.h"

#import "RTCMediaStream+PHStreamConfiguration.h"
#import "UIButton+PHButton.h"
#import "UIDevice+PHDeviceAdditions.h"
#import "UIFont+Fonts.h"

#import "AFNetworkReachabilityManager.h"
#import "RTCMediaStream.h"
#import "RTCVideoTrack.h"
#import "RTCEAGLVideoView.h"

@import AVFoundation;

#define PHPhoneLightTextColor [UIColor colorWithRed:0.44 green:0.46 blue:0.48 alpha:1.0]
#define PHPhoneLightBackgroundColor [UIColor colorWithRed:0.93 green:0.94 blue:0.94 alpha:1.0]
#define PHBlue [UIColor colorWithRed:0.173 green:0.667 blue:0.812 alpha:1.0]

static NSTimeInterval PHViewControllerAnimationTime = 0.3;
static CGFloat PHViewControllerDampingRatio = 0.85;
static CGFloat PHViewControllerSpringVelocity = 0.25;
static CGFloat PHViewControllerHorizontalPadding = 10.0;

@interface PHViewController () <PHConnectionBrokerDelegate, PHRendererDelegate, XSRoomObserver>

@property (nonatomic, strong) PHConnectionBroker *connectionBroker;
@property (nonatomic, strong) PHMediaConfiguration *configuration;

@property (nonatomic, strong) UILabel *roomInfoLabel;
@property (nonatomic, strong) UIButton *connectButton;

@property (nonatomic, strong) id<PHRenderer> localRenderer;
@property (nonatomic, strong) NSMutableArray *remoteRenderers;
@property (nonatomic, strong) PHMuteOverlayView *muteOverlayView;

@property (nonatomic, assign) UIInterfaceOrientation lastInterfaceOrientation;
@property (nonatomic, strong) UIBarButtonItem *settingsItem;

@end

@implementation PHViewController

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    
    if (self) {
        _remoteRenderers = [NSMutableArray array];
        _configuration = [PHMediaConfiguration defaultConfiguration];
    }
    
    return self;
}

#pragma mark - UIViewController

- (void)viewDidLoad
{
    [super viewDidLoad];

    self.view.backgroundColor = PHPhoneLightBackgroundColor;
    self.edgesForExtendedLayout = UIRectEdgeAll;

    // Action button

    UIButton *button = [UIButton roundedButtonWithStyle:PHRoundedButtonStyleLight];
    [button setTitle:@"Join" forState:UIControlStateNormal];
    [button addTarget:self action:@selector(buttonPress:) forControlEvents:UIControlEventTouchUpInside];

    if ([UIDevice currentDevice].isPad) {
        button.titleLabel.font = [UIFont perchFontOfSize:18];
    }

    // Room info.

    UILabel *roomLabel = [[UILabel alloc] init];
    roomLabel.text = [NSString stringWithFormat:@"Ready to join %@.", [kPHConnectionManagerDefaultRoomName capitalizedString]];
    roomLabel.textAlignment = NSTextAlignmentCenter;
    roomLabel.textColor = PHPhoneLightTextColor;
    roomLabel.numberOfLines = 0;
    roomLabel.font = [UIFont perchFontOfSize:([UIDevice currentDevice].isPad ? 24.0 : 18.0)];

    [self.view addSubview:roomLabel];
    [self.view addSubview:button];

    self.connectButton = button;
    self.roomInfoLabel = roomLabel;

    // Navigation Bar

    [self configureNavigationBar];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];

    self.lastInterfaceOrientation = self.interfaceOrientation;
}

- (void)viewWillLayoutSubviews
{
    [super viewWillLayoutSubviews];

    CGRect bounds = self.view.bounds;

    CGFloat actionWidth = 124;
    CGFloat buttonHeight = 48;
    CGFloat padding = PHViewControllerHorizontalPadding;

    if ([UIDevice currentDevice].isPad) {
        actionWidth *= 2.0;
    }

    // Connect button.

    self.connectButton.frame = CGRectMake(padding, CGRectGetHeight(bounds) - buttonHeight - padding, actionWidth, buttonHeight);

    // Info Text.

    [self layoutInfoText];

    // Layout local feed.

    [self layoutLocalFeed];

    // Layout remote feeds.

    [self layoutRemoteFeeds];
}

- (void)willAnimateRotationToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation duration:(NSTimeInterval)duration
{
    [super willAnimateRotationToInterfaceOrientation:toInterfaceOrientation duration:duration];

    [self informObserversOfOrientation:toInterfaceOrientation];
}

- (BOOL)prefersStatusBarHidden
{
    id <PHRenderer> remoteRenderer = [self.remoteRenderers firstObject];
    return remoteRenderer.videoTrack != nil;
}

- (UIStatusBarAnimation)preferredStatusBarUpdateAnimation
{
    return UIStatusBarAnimationSlide;
}

#pragma mark - NSObject

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    if ([keyPath isEqualToString:@"peerConnectionState"]) {
        XSPeerConnectionState connectionState = self.connectionBroker.peerConnectionState;
        BOOL reachable = self.connectionBroker.reachability.isReachable;
        BOOL showNotConnected = [self.connectionBroker.remoteStreams count] == 0 && connectionState == XSPeerConnectionStateDisconnected && !reachable;

        if (self.connectionBroker.reachability && showNotConnected) {
            [self showNoInternetMessage];
        }
    }
}

#pragma mark - Private

- (void)informObserversOfOrientation:(UIInterfaceOrientation)toInterfaceOrientation
{
    // Due to an odd implementation detail in RTCVideoCaptureIosObjC (rtc_video_capture_ios_objc.m),
    // we must inform the capturer of orientation changes by posting a 'StatusBarOrientationDidChange' notification.

    if (toInterfaceOrientation != self.lastInterfaceOrientation) {
        self.lastInterfaceOrientation = toInterfaceOrientation;
        [[NSNotificationCenter defaultCenter] postNotificationName:@"StatusBarOrientationDidChange" object:self];
    }
}

- (void)configureNavigationBar
{
    UINavigationBar *navigationBar = self.navigationController.navigationBar;

    navigationBar.translucent = YES;
    [navigationBar setBackgroundImage:nil forBarMetrics:UIBarMetricsDefault];
    navigationBar.tintColor = PHBlue;

    // Set up the Logo image

    UIImage *perchLogo = [UIImage imageNamed:@"logo-orange"];
    self.navigationItem.titleView = [[UIImageView alloc] initWithImage:perchLogo];

    UIImage *icon = [[UIImage imageNamed:@"settings-dark"] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];

    self.settingsItem = [[UIBarButtonItem alloc] initWithImage:icon style:UIBarButtonItemStylePlain target:self action:@selector(settingsPress:)];
    self.navigationItem.rightBarButtonItem = self.settingsItem;
}

- (void)layoutInfoText
{
    CGRect bounds = self.view.bounds;
    CGFloat padding = 15;
    CGSize constrainedSize = CGRectInset(bounds, padding, padding).size;
    CGSize infoTextSize = [self.roomInfoLabel sizeThatFits:constrainedSize];

    self.roomInfoLabel.bounds = (CGRect){CGPointZero, infoTextSize};
    self.roomInfoLabel.center = CGPointMake(CGRectGetMidX(bounds), CGRectGetMidY(bounds));
    self.roomInfoLabel.frame = CGRectIntegral(self.roomInfoLabel.frame);
}

- (void)layoutLocalFeed
{
    CGRect bounds = self.view.bounds;
    CGFloat padding = PHViewControllerHorizontalPadding;
    CGFloat smallerDimension = 90;
    CGSize feedSize = self.localRenderer.videoSize;
    CGSize displaySize = CGSizeZero;

    if ([UIDevice currentDevice].isPad) {
        smallerDimension *= (224.0 / 120.0);
    }
    else if ([UIDevice currentDevice].isLargePhone) {
        smallerDimension *= (140.0 / 120.0);
    }

    if (CGSizeEqualToSize(feedSize, CGSizeZero)) {
        displaySize = CGSizeMake(smallerDimension, smallerDimension);
    }
    else if (feedSize.width > feedSize.height) {
        displaySize = CGSizeMake(smallerDimension * (feedSize.width / feedSize.height), smallerDimension);
    }
    else {
        displaySize = CGSizeMake(smallerDimension, smallerDimension * (feedSize.height / feedSize.width));
    }

    CGRect localFrame = CGRectMake(CGRectGetWidth(bounds) - padding - displaySize.width, CGRectGetHeight(bounds) - padding - displaySize.height, displaySize.width, displaySize.height);
    CGRect localBounds = CGRectMake(0, 0, CGRectGetWidth(localFrame), CGRectGetHeight(localFrame));
    CGPoint localCenter = CGPointMake(CGRectGetMidX(localFrame), CGRectGetMidY(localFrame));

    UIView *localRenderView = self.localRenderer.rendererView;

    localRenderView.bounds = localBounds;
    localRenderView.center = localCenter;

    // Layout mute overlay.

    self.muteOverlayView.bounds = localRenderView.bounds;
    self.muteOverlayView.center = CGPointMake(CGRectGetMidX(localBounds), CGRectGetMidY(localBounds));
}

- (NSUInteger)numActiveRemoteRenderers
{
    __block NSUInteger activeRenderers = 0;

    [self.remoteRenderers enumerateObjectsUsingBlock:^(id<PHRenderer> renderer, NSUInteger idx, BOOL *stop) {
        if (renderer.hasVideoData) {
            activeRenderers++;
        }
    }];

    return activeRenderers;
}

- (BOOL)rendererOrientationsMatch
{
    __block NSUInteger portraitRenderers = 0;

    [self.remoteRenderers enumerateObjectsUsingBlock:^(id<PHRenderer> renderer, NSUInteger idx, BOOL *stop) {
        if (renderer.hasVideoData && renderer.videoSize.height > renderer.videoSize.width) {
            portraitRenderers++;
        }
    }];

    return (portraitRenderers == [self.remoteRenderers count] || portraitRenderers == 0);
}

- (void)layoutRemoteFeeds
{
    CGRect bounds = self.view.bounds;
    BOOL isPortrait = UIInterfaceOrientationIsPortrait(self.interfaceOrientation);

    NSUInteger numRemoteRenderers = [self numActiveRemoteRenderers];

    if (numRemoteRenderers == 1) {
        id<PHRenderer> renderer = [self.remoteRenderers firstObject];
        renderer.rendererView.frame = bounds;
    }
    else if (numRemoteRenderers == 2) {
        CGFloat width = 0;
        CGFloat height = 0;
        CGPoint origin = CGPointZero;
        BOOL rendererOrientationsMatch = [self rendererOrientationsMatch];

        for (id<PHRenderer> renderer in self.remoteRenderers) {
            BOOL rendererIsPortrait = renderer.videoSize.height > renderer.videoSize.width;

            // Two layouts.
            // Both feeds match. Split the difference (vertically in portrait, horiz in landscape).
            // Feeds mismatch. Prefer the feed which matches our orientation (60/40 split).

            if (rendererOrientationsMatch && isPortrait) {
                width = CGRectGetWidth(bounds);
                height = CGRectGetHeight(bounds) * 0.5;
            }
            else if (rendererOrientationsMatch && !isPortrait) {
                width = CGRectGetWidth(bounds) * 0.5;
                height = CGRectGetHeight(bounds);
            }
            else if (!rendererOrientationsMatch && isPortrait) {
                width = CGRectGetWidth(bounds);
                height = rendererIsPortrait ? CGRectGetHeight(bounds) * 0.55 : CGRectGetHeight(bounds) * 0.45;
            }
            else if (!rendererOrientationsMatch && !isPortrait) {
                width = rendererIsPortrait ? CGRectGetWidth(bounds) * 0.45 : CGRectGetWidth(bounds) * 0.55;
                height = CGRectGetHeight(bounds);
            }

            CGRect frame = {origin.x, origin.y, width, height};
            renderer.rendererView.frame = frame;

            if (isPortrait) {
                origin.y += height;
            }
            else {
                origin.x += width;
            }
        }
    }
    else if (numRemoteRenderers > 2) {

        CGFloat width = isPortrait ? CGRectGetWidth(bounds) : (CGRectGetWidth(bounds) / (CGFloat)numRemoteRenderers);
        CGFloat height = isPortrait ? (CGRectGetHeight(bounds) / (CGFloat)numRemoteRenderers) : CGRectGetHeight(bounds);
        CGSize size = CGSizeMake(width, height);
        CGPoint origin = CGPointZero;

        for (id<PHRenderer> renderer in self.remoteRenderers) {
            UIView *rendererView = renderer.rendererView;
            rendererView.frame = (CGRect){origin, size};

            if (isPortrait) {
                origin.y += size.height;
            }
            else {
                origin.x += size.width;
            }
        }
    }
}

- (void)buttonPress:(UIButton *)sender
{
    BOOL wantToConnect = self.connectionBroker.localStream == nil && self.connectionBroker.room == nil;

    if (wantToConnect) {
        [sender setTitle:@"Joining" forState:UIControlStateNormal];
        [self connectWithPermission];
    }
    else {
        [self startDisconnect];
    }

    sender.enabled = NO;
}

- (void)settingsPress:(id)sender
{
    PHSettingsViewController *settingsVC = [[PHSettingsViewController alloc] initWithStyle:UITableViewStyleGrouped];
    settingsVC.settings = self.configuration;

    [self.navigationController pushViewController:settingsVC animated:YES];
}

- (void)startDisconnect
{
    [self.connectButton setTitle:@"Leaving" forState:UIControlStateNormal];
    self.connectButton.enabled = NO;

    // Remove video renderers.

    [self hideAndRemoveRemoteRenderers];
    [self hideLocalRenderer];

    [self.connectionBroker.room removeRoomObserver:self];
    [self.connectionBroker disconnect];
    [self.connectionBroker removeObserver:self forKeyPath:@"peerConnectionState"];
}

// TODO: Support tap to zoom for all renderers.
- (void)handleZoomTap:(UITapGestureRecognizer *)recognizer
{
    UIView *rendererView = recognizer.view;

    if ([rendererView isKindOfClass:[PHSampleBufferView class]]) {
        PHSampleBufferView *sampleView = (PHSampleBufferView *)rendererView;
        NSString *videoGravity = sampleView.videoGravity;
        NSString *updatedGravity = [videoGravity isEqualToString:AVLayerVideoGravityResizeAspect] ? AVLayerVideoGravityResizeAspectFill : AVLayerVideoGravityResizeAspect;
        sampleView.videoGravity = updatedGravity;
        sampleView.bounds = CGRectInset(sampleView.bounds, 1, 1);
        sampleView.bounds = CGRectInset(sampleView.bounds, -1, -1);
    }
}

- (void)handleAudioTap:(UITapGestureRecognizer *)recognizer
{
    RTCMediaStream *stream = self.connectionBroker.localStream;
    BOOL isAudioEnabled = stream.isAudioEnabled;
    BOOL setAudioEnabled = !isAudioEnabled;

    stream.audioEnabled = setAudioEnabled;

    self.muteOverlayView.mode = setAudioEnabled ? PHAudioModeOn : PHAudioModeMuted;

    UIView *renderView = self.localRenderer.rendererView;
    CGAffineTransform transform = renderView.transform;
    CGAffineTransform popTransform = CGAffineTransformConcat(transform, CGAffineTransformMakeScale(1.05, 1.05));

    [UIView animateWithDuration:0.14 delay:0 usingSpringWithDamping:0.8 initialSpringVelocity:0.3 options:UIViewAnimationOptionBeginFromCurrentState animations:^{
        renderView.transform = popTransform;
    } completion:^(BOOL finished) {
        [UIView animateWithDuration:0.16 delay:0 usingSpringWithDamping:0.6 initialSpringVelocity:0 options:UIViewAnimationOptionBeginFromCurrentState animations:^{
            renderView.transform = transform;
        } completion:nil];
    }];
}

- (void)connectWithPermission
{
    [AVCaptureDevice requestAccessForMediaType:AVMediaTypeAudio completionHandler:^(BOOL audioGranted) {
        [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:^(BOOL videoGranted) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (audioGranted && videoGranted) {
                    [self connectToRoom:kPHConnectionManagerDefaultRoomName];
                }
                else {
                    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Error" message:@"Please grant PerchRTC access to both your camera and microphone before connecting." delegate:nil cancelButtonTitle:@"Okay" otherButtonTitles:nil];
                    [alert show];
                }
            });
        }];
    }];
}

- (void)connectToRoom:(NSString *)roomName
{
    NSString *name = [UIDevice currentDevice].name;
    XSRoom *room = [[XSRoom alloc] initWithAuthToken:nil username:name andRoomName:roomName];
    PHConnectionBroker *connectionBroker = [[PHConnectionBroker alloc] initWithDelegate:self];

    [room addRoomObserver:self];

    [connectionBroker addObserver:self forKeyPath:@"peerConnectionState" options:NSKeyValueObservingOptionOld context:NULL];
    [connectionBroker connectToRoom:room withConfiguration:self.configuration];

    self.connectionBroker = connectionBroker;

    [UIApplication sharedApplication].idleTimerDisabled = YES;

    [self.navigationItem setRightBarButtonItem:nil animated:YES];

    [UIView animateWithDuration:0.2 animations:^{
        self.roomInfoLabel.alpha = 0.0;
    }];
}

- (void)removeRendererForStream:(RTCMediaStream *)stream
{
    // When checking for an RTCVideoTrack use indexOfObjectIdenticalTo: instead of containsObject:
    // RTCVideoTrack doesn't implement hash or isEqual: which caused false positives.

    id <PHRenderer> rendererToRemove = nil;

    for (id<PHRenderer> remoteRenderer in self.remoteRenderers) {
        NSUInteger videoTrackIndex = [stream.videoTracks indexOfObjectIdenticalTo:remoteRenderer.videoTrack];
        if (videoTrackIndex != NSNotFound) {
            rendererToRemove = remoteRenderer;
            break;
        }
    }

    if (rendererToRemove) {
        [self hideAndRemoveRenderer:rendererToRemove];
    }
    else {
        DDLogWarn(@"No renderer to remove for stream: %@", stream);
    }
}

- (void)hideAndRemoveRemoteRenderers
{
    NSArray *remoteRenderers = [self.remoteRenderers copy];

    for (id<PHRenderer> rendererToRemove in remoteRenderers) {
        [self hideAndRemoveRenderer:rendererToRemove];
    }
}

- (id<PHRenderer>)rendererForStream:(RTCMediaStream *)stream
{
    NSParameterAssert(stream);

    id<PHRenderer> renderer = nil;
    RTCVideoTrack *videoTrack = [stream.videoTracks firstObject];
    PHRendererType rendererType = self.configuration.rendererType;

    if (rendererType == PHRendererTypeSampleBuffer) {
        renderer = [[PHSampleBufferRenderer alloc] initWithDelegate:self];
    }
    else if (rendererType == PHRendererTypeOpenGLES) {
        renderer = [[PHEAGLRenderer alloc] initWithDelegate:self];
    }
    else if (rendererType == PHRendererTypeQuartz) {
        PHQuartzVideoView *localVideoView = [[PHQuartzVideoView alloc] initWithFrame:CGRectZero];
        localVideoView.delegate = self;
        renderer = localVideoView;
    }
    else {
        DDLogWarn(@"Unsupported renderer type: %lu", (unsigned long)rendererType);
    }

    renderer.videoTrack = videoTrack;

    return renderer;
}

- (void)refreshRemoteRendererAspectRatios
{
    BOOL shouldAspectFill = [self.remoteRenderers count] > 1;

    for (id<PHRenderer> renderer in self.remoteRenderers) {
        UIView *rendererView = renderer.rendererView;
        if ([rendererView isKindOfClass:[PHSampleBufferView class]]) {
            PHSampleBufferView *sampleView = (PHSampleBufferView *)rendererView;
            sampleView.videoGravity = shouldAspectFill ? AVLayerVideoGravityResizeAspectFill : AVLayerVideoGravityResizeAspect;
            if (!CGRectEqualToRect(sampleView.bounds, CGRectZero)) {
                sampleView.bounds = CGRectInset(sampleView.bounds, 1, 1);
                sampleView.bounds = CGRectInset(sampleView.bounds, -1, -1);
            }
        }
    }
}

- (void)showLocalRenderer
{
    CGAffineTransform finalTransform = CGAffineTransformMakeScale(-1, 1);

    [self showRenderer:self.localRenderer withTransform:finalTransform];
}

- (void)showRemoteRenderer:(id<PHRenderer>)renderer
{
    [self showRenderer:renderer withTransform:CGAffineTransformIdentity];
}

- (void)showRenderer:(id<PHRenderer>)renderer withTransform:(CGAffineTransform)finalTransform
{
    [self.view setNeedsLayout];
    [self.view layoutIfNeeded];

    UIView *theView = renderer.rendererView;

    if (renderer == self.localRenderer) {
        [self.view insertSubview:theView belowSubview:self.connectButton];

        self.muteOverlayView = [[PHMuteOverlayView alloc] initWithMode:PHAudioModeOn];
        self.muteOverlayView.userInteractionEnabled = NO;
        self.muteOverlayView.alpha = 0;

        // Reverse the transform since we are a subview....
        self.muteOverlayView.transform = finalTransform;

        [theView addSubview:self.muteOverlayView];
    }
    else {
        [self.view insertSubview:theView aboveSubview:self.roomInfoLabel];
    }

    theView.transform = CGAffineTransformConcat(CGAffineTransformMakeScale(0.01, 0.01), finalTransform);

    [UIView animateWithDuration:PHViewControllerAnimationTime delay:0 usingSpringWithDamping:PHViewControllerDampingRatio initialSpringVelocity:PHViewControllerSpringVelocity options:UIViewAnimationOptionBeginFromCurrentState animations:^{
        theView.transform = finalTransform;
        self.muteOverlayView.alpha = 1.0;
    } completion:^(BOOL finished) {
    }];
}

- (void)hideLocalRenderer
{
    [self hideAndRemoveRenderer:self.localRenderer];
}

- (void)hideAndRemoveRenderer:(id<PHRenderer>)renderer
{
    UIView *theView = renderer.rendererView;
    CGAffineTransform finalTransform = CGAffineTransformConcat(CGAffineTransformMakeScale(0.01, 0.01), theView.transform);
    BOOL removeMute = renderer == self.localRenderer;
    renderer.videoTrack = nil;

    [UIView animateWithDuration:PHViewControllerAnimationTime delay:0 usingSpringWithDamping:PHViewControllerDampingRatio initialSpringVelocity:PHViewControllerSpringVelocity options:UIViewAnimationOptionBeginFromCurrentState animations:^{
        theView.transform = finalTransform;
    } completion:^(BOOL finished) {
        [theView removeFromSuperview];

        if (removeMute) {
            [self.muteOverlayView removeFromSuperview];
            self.muteOverlayView = nil;
        }

        if ([self.remoteRenderers count] > 0) {

            [UIView animateWithDuration:PHViewControllerAnimationTime delay:0 usingSpringWithDamping:PHViewControllerDampingRatio initialSpringVelocity:PHViewControllerSpringVelocity options:UIViewAnimationOptionBeginFromCurrentState animations:^{
                [self.view setNeedsLayout];
                [self.view layoutIfNeeded];
                [self refreshRemoteRendererAspectRatios];
            } completion:nil];
        }
    }];

    if (renderer == self.localRenderer) {
        self.localRenderer = nil;
    }
    else {
        [self.remoteRenderers removeObject:renderer];
    }
}

- (void)showWaitingInterfaceWithDefaultMessage
{
    NSString *message = [NSString stringWithFormat:@"Waiting for someone to join %@.", [kPHConnectionManagerDefaultRoomName capitalizedString]];

    [self showWaitingInterfaceWithMessage:message completion:nil];
}

- (void)showNoInternetMessage
{
    NSString *message = [NSString stringWithFormat:@"Not Connected.\nWe will rejoin %@ once your network is online.", [kPHConnectionManagerDefaultRoomName capitalizedString]];

    [self showWaitingInterfaceWithMessage:message completion:nil];
}

- (void)showConnectingMessage
{
    NSString *message = @"Connecting To Peers";

    if ([self.connectionBroker.room.peers count] == 1) {
        XSPeer *peer = [[self.connectionBroker.room.peers allValues] firstObject];
        message = [NSString stringWithFormat:@"Connecting To %@", peer.identifier];
    }

    [self showWaitingInterfaceWithMessage:message completion:nil];
}

// TODO: Get rid of duplicate animation work.
- (void)showWaitingInterfaceWithMessage:(NSString *)message completion:(void (^)(BOOL finished))completion
{
    BOOL animateChange = [self.roomInfoLabel.text length] > 0 && ![self.roomInfoLabel.text isEqualToString:message];

    [self.navigationController setNavigationBarHidden:NO animated:YES];

    if (animateChange) {
        [UIView animateWithDuration:0.2 animations:^{
            self.roomInfoLabel.hidden = NO;
            self.roomInfoLabel.alpha = 0;
            self.view.backgroundColor = PHPhoneLightBackgroundColor;
            [self.connectButton applyStyle:PHRoundedButtonStyleLight];
            [self setNeedsStatusBarAppearanceUpdate];
        } completion:^(BOOL finished) {
            self.roomInfoLabel.text = message;
            [self layoutInfoText];
            [UIView animateWithDuration:0.2 animations:^{
                self.roomInfoLabel.alpha = 1.0;
            }completion:^(BOOL finished) {
                if (completion) {
                    completion(finished);
                }
            }];
        }];
    }
    else {
        self.roomInfoLabel.text = message;
        [self layoutInfoText];

        [UIView animateWithDuration:0.2 animations:^{
            self.roomInfoLabel.hidden = NO;
            self.roomInfoLabel.alpha = 1.0;
            self.view.backgroundColor = PHPhoneLightBackgroundColor;
            [self.connectButton applyStyle:PHRoundedButtonStyleLight];
            [self setNeedsStatusBarAppearanceUpdate];
        } completion:^(BOOL finished) {
            if (completion) {
                completion(finished);
            }
        }];
    }
}

- (void)showActiveConnectionInterface
{
    [UIView animateWithDuration:0.2 animations:^{
        self.view.backgroundColor = [UIColor blackColor];
        self.roomInfoLabel.alpha = 0;
        [self.connectButton applyStyle:PHRoundedButtonStyleDark];
        [self setNeedsStatusBarAppearanceUpdate];
    } completion:^(BOOL finished) {
        self.roomInfoLabel.text = nil;
        self.roomInfoLabel.hidden = YES;
    }];

    [self.navigationController setNavigationBarHidden:YES animated:YES];
}

#pragma mark - PHConnectionBrokerDelegate

- (void)connectionBroker:(PHConnectionBroker *)broker didAddLocalStream:(RTCMediaStream *)localStream
{
    DDLogVerbose(@"Connection manager did receive local video track: %@", [localStream.videoTracks firstObject]);

#if TARGET_IPHONE_SIMULATOR
    localStream.audioEnabled = NO;
#endif

    // Prepare a renderer for the local stream.

    self.localRenderer = [self rendererForStream:localStream];
    UIView *theView = self.localRenderer.rendererView;

    UITapGestureRecognizer *tapRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleAudioTap:)];
    [theView addGestureRecognizer:tapRecognizer];
}

- (void)connectionBroker:(PHConnectionBroker *)broker didAddStream:(RTCMediaStream *)remoteStream
{
    DDLogVerbose(@"Connection broker did add stream: %@", remoteStream);

    // Prepare a renderer for the remote stream.

    id<PHRenderer> remoteRenderer = [self rendererForStream:remoteStream];
    UIView *theView = remoteRenderer.rendererView;

    [self.remoteRenderers addObject:remoteRenderer];

    UITapGestureRecognizer *tapToZoomRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleZoomTap:)];
    tapToZoomRecognizer.numberOfTapsRequired = 2;
    [theView addGestureRecognizer:tapToZoomRecognizer];
}

- (void)connectionBroker:(PHConnectionBroker *)broker didRemoveStream:(RTCMediaStream *)remoteStream
{
    [self removeRendererForStream:remoteStream];

    if ([broker.remoteStreams count] == 0) {
        [self showWaitingInterfaceWithDefaultMessage];
    }
}

- (void)connectionBrokerDidFinish:(PHConnectionBroker *)broker
{
    self.connectionBroker = nil;

    NSString *message = [NSString stringWithFormat:@"Ready to join %@.", [kPHConnectionManagerDefaultRoomName capitalizedString]];

    [self showWaitingInterfaceWithMessage:message completion:^(BOOL finished) {
        [self.navigationItem setRightBarButtonItem:self.settingsItem animated:YES];
        self.connectButton.enabled = YES;
        [self.connectButton setTitle:@"Join" forState:UIControlStateNormal];
        [UIApplication sharedApplication].idleTimerDisabled = NO;
    }];
}

- (void)connectionBroker:(PHConnectionBroker *)broker didFailWithError:(NSError *)error
{
    DDLogError(@"Connection broker, did encounter error: %@", error);
    
    if ([broker.remoteStreams count] == 0 && broker.peerConnectionState == XSPeerConnectionStateDisconnected) {
        [self showNoInternetMessage];
        
        self.connectButton.enabled = YES;
        [self.connectButton setTitle:@"Leave" forState:UIControlStateNormal];
    }
    else if (error.code == PHErrorCodeFullRoom) {
        [self showWaitingInterfaceWithMessage:[NSString stringWithFormat:@"Sorry, %@ is full.", broker.room.name] completion:nil];

        [self startDisconnect];
    }
}

#pragma mark - PHRendererDelegate

- (void)renderer:(id<PHRenderer>)renderer streamDimensionsDidChange:(CGSize)dimensions
{
    NSString *rendererTitle = renderer == self.localRenderer ? @"local renderer" : @"remote renderer";
    DDLogVerbose(@"Stream dimensions did change for %@: %@, %@", rendererTitle, NSStringFromCGSize(dimensions), renderer);

    [self.view setNeedsLayout];
}

- (void)rendererDidReceiveVideoData:(id<PHRenderer>)renderer
{
    DDLogVerbose(@"Did receive video data for renderer: %@", renderer);

    if (renderer == self.localRenderer) {
        [self showLocalRenderer];
    }
    else {
        [self showActiveConnectionInterface];
        [self refreshRemoteRendererAspectRatios];
        [self showRemoteRenderer:renderer];
    }
}

#pragma mark - XSRoomObserver

- (void)didJoinRoom:(XSRoom *)room
{
    BOOL isWaiting = [room.peers count] == 0;

    [self.connectButton setTitle:@"Leave" forState:UIControlStateNormal];
    self.connectButton.enabled = YES;

    if (isWaiting) {
        [self showWaitingInterfaceWithDefaultMessage];
    }
    else if ([self.connectionBroker.remoteStreams count] == 0) {
        [self showConnectingMessage];
    }
}

- (void)didLeaveRoom:(XSRoom *)room
{

}

- (void)room:(XSRoom *)room didAddPeer:(XSPeer *)peer
{
    if (!self.navigationController.navigationBarHidden) {
        [self showConnectingMessage];
    }
}

- (void)room:(XSRoom *)room didRemovePeer:(XSPeer *)peer
{
    if ([room.peers count] == 0 && [self.connectionBroker.remoteStreams count] == 0) {
        [self showWaitingInterfaceWithDefaultMessage];
    }
}

- (void)room:(XSRoom *)room didReceiveMessage:(XSMessage *)message
{

}

@end
