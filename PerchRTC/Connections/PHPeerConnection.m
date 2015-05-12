//
//  PHPeerConnection.m
//  PerchRTC
//
//  Created by Christopher Eagleston on 2014-12-16.
//  Copyright (c) 2014 Perch Communications. All rights reserved.
//

#import "PHPeerConnection.h"

#import "RTCPeerConnection.h"

@interface PHPeerConnection()

@property (nonatomic, strong) NSMutableArray *queuedRemoteCandidates;

@end

@implementation PHPeerConnection

- (instancetype)initWithConnection:(RTCPeerConnection *)connection
{
    self = [super init];

    if (self) {
        _peerConnection = connection;
        _role = PHPeerConnectionRoleInitiator;
        _iceAttempts = 0;
    }

    return self;
}

#pragma mark - NSObject

- (NSUInteger)hash
{
    return [self.peerConnection hash];
}

- (BOOL)isEqual:(id)object
{
    if ([object isKindOfClass:[PHPeerConnection class]]) {
        PHPeerConnection *otherConnection = (PHPeerConnection *)object;
        return [otherConnection.peerConnection isEqual:self.peerConnection];
    }

    return NO;
}

#pragma mark - Public

- (void)addIceCandidate:(RTCICECandidate *)candidate
{
    BOOL queueCandidates = self.peerConnection == nil || self.peerConnection.signalingState != RTCSignalingStable;

    if (queueCandidates) {
        if (!self.queuedRemoteCandidates) {
            self.queuedRemoteCandidates = [NSMutableArray array];
        }
        DDLogVerbose(@"Queued a remote ICE candidate for later.");
        [self.queuedRemoteCandidates addObject:candidate];
    }
    else {
        DDLogVerbose(@"Adding a remote ICE candidate.");
        [self.peerConnection addICECandidate:candidate];
    }
}

- (void)drainRemoteCandidates
{
    DDLogVerbose(@"Drain %lu remote ICE candidates.", (unsigned long)[self.queuedRemoteCandidates count]);

    for (RTCICECandidate *candidate in self.queuedRemoteCandidates) {
        [self.peerConnection addICECandidate:candidate];
    }
    self.queuedRemoteCandidates = nil;
}

- (void)removeRemoteCandidates
{
    DDLogDebug(@"%s", __PRETTY_FUNCTION__);

    [self.queuedRemoteCandidates removeAllObjects];
    self.queuedRemoteCandidates = nil;
}

- (void)close
{
    RTCMediaStream *localStream = [self.peerConnection.localStreams firstObject];
    [self.peerConnection removeStream:localStream];
    [self.peerConnection close];

    self.remoteStream = nil;
    self.peerConnection = nil;
}

@end
