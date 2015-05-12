//
//  PHMediaSession.h
//  PerchRTC
//
//  Created by Christopher Eagleston on 2014-12-16.
//  Copyright (c) 2014 Perch Communications. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "PHMediaConfiguration.h"

#import "RTCTypes.h"


@class PHVideoCaptureKit;
@class RTCMediaStream;
@class RTCSessionDescription;
@class RTCICECandidate;
@class PHPeerConnection;

@class PHMediaSession;

@protocol PHSignalingDelegate <NSObject>

- (void)signalOffer:(RTCSessionDescription *)sdpOffer forConnection:(PHPeerConnection *)connection;
- (void)signalAnswer:(RTCSessionDescription *)sdpAnswer forConnection:(PHPeerConnection *)connection;
- (void)signalICECandidate:(RTCICECandidate *)iceCandidate forConnection:(PHPeerConnection *)connection;

- (void)connection:(PHPeerConnection *)connection addedStream:(RTCMediaStream *)stream;
- (void)connection:(PHPeerConnection *)connection removedStream:(RTCMediaStream *)stream;
- (void)connection:(PHPeerConnection *)connection iceStatusChanged:(RTCICEConnectionState)state;

- (BOOL)session:(PHMediaSession *)session shouldRenegotiateConnectionsWithFormat:(PHVideoFormat)receiverFormat;

@end

@interface PHMediaSession : NSObject

@property (nonatomic, copy, readonly) PHMediaConfiguration *sessionConfiguration;
@property (nonatomic, assign, readonly) NSUInteger connectionCount;

@property (nonatomic, weak, readonly) id<PHSignalingDelegate>delegate;
@property (nonatomic, strong, readonly) RTCMediaStream *localStream;

- (instancetype)initWithDelegate:(id<PHSignalingDelegate>)delegate;
- (instancetype)initWithDelegate:(id<PHSignalingDelegate>)delegate configuration:(PHMediaConfiguration *)config andCapturer:(PHVideoCaptureKit *)capturer;

- (void)addIceServers:(NSArray *)iceServers singleUse:(BOOL)isSingleUse;
- (void)addIceCandidate:(RTCICECandidate *)candidate forPeer:(NSString *)peerId connectionId:(NSString *)connectionId;
- (void)addAnswer:(RTCSessionDescription *)answerSDP forPeer:(NSString *)peerId connectionId:(NSString *)connectionId;
- (void)addOffer:(RTCSessionDescription *)offerSDP forPeer:(NSString *)peerId connectionId:(NSString *)connectionId;

- (void)closeConnectionWithPeer:(NSString *)peerId;

- (PHPeerConnection *)connectionForPeerId:(NSString *)peerId;

- (void)connectToPeer:(NSString *)peerId;
- (void)acceptConnectionFromPeer:(NSString *)peerId withId:(NSString *)connectionId offer:(RTCSessionDescription *)offer;

- (void)restartIceWithPeer:(NSString *)peerId;

- (void)stopLocalMedia;

@end
