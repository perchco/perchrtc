//
//  PHPeerConnection.h
//  PerchRTC
//
//  Created by Christopher Eagleston on 2014-12-16.
//  Copyright (c) 2014 Perch Communications. All rights reserved.
//

#import <Foundation/Foundation.h>

@class RTCPeerConnection;
@class RTCICECandidate;
@class RTCMediaStream;
@class RTCSessionDescription;

typedef NS_ENUM(NSUInteger, PHPeerConnectionRole)
{
    PHPeerConnectionRoleInitiator = 0,
    PHPeerConnectionRoleReceiver = 1
};

@interface PHPeerConnection : NSObject

- (instancetype)initWithConnection:(RTCPeerConnection *)connection;

@property (nonatomic, copy) NSString *connectionId;
@property (nonatomic, copy) NSString *peerId;
@property (nonatomic, strong) RTCPeerConnection *peerConnection;
@property (nonatomic, strong, readonly) NSMutableArray *queuedRemoteCandidates;
@property (nonatomic, strong) RTCSessionDescription *queuedOffer;
@property (nonatomic, assign) PHPeerConnectionRole role;
@property (nonatomic, strong) RTCMediaStream *remoteStream;
@property (nonatomic, assign) NSUInteger iceAttempts;

- (void)addIceCandidate:(RTCICECandidate *)candidate;
- (void)drainRemoteCandidates;
- (void)removeRemoteCandidates;

- (void)close;

@end
