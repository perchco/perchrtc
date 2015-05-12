//
//  PHConnectionManager.m
//  PerchRTC
//
//  Created by Christopher Eagleston on 2014-08-09.
//  Copyright (c) 2014 Perch Communications. All rights reserved.
//

#import "PHConnectionBroker.h"

#if !TARGET_IPHONE_SIMULATOR
#import "PHVideoCaptureKit.h"
#import "PHVideoPublisher.h"
#endif

#import "PHErrors.h"
#import "PHCredentials.h"
#import "PHMediaSession.h"
#import "PHPeerConnection.h"

#import "RTCICECandidate.h"
#import "RTCICEServer.h"
#import "RTCMediaStream.h"
#import "RTCPeerConnection.h"
#import "RTCSessionDescription.h"
#import "RTCMediaStream.h"

#import "XSClient.h"
#import "XSMessage.h"
#import "XSPeer.h"
#import "XSPeerClient.h"
#import "XSRoom.h"
#import "XSServer.h"

#import "AFNetworkReachabilityManager.h"

@import AVFoundation;

static NSUInteger kPHConnectionManagerMaxIceAttempts = 3;

// This is the maximum number of remote peers allowed in the room, not including yourself.
// In this case we only allow 3 people in one room.
static NSUInteger kPHConnectionManagerMaxRoomPeers = 2;

#if !TARGET_IPHONE_SIMULATOR
static BOOL kPHConnectionManagerUseCaptureKit = YES;
#endif

@interface PHConnectionBroker() <PHSignalingDelegate, XSPeerClientDelegate, XSRoomObserver>

@property (nonatomic, strong) XSClient *apiClient;
@property (nonatomic, strong) XSPeerClient *peerClient;
@property (nonatomic, strong) NSMutableArray *mutableRemoteStreams;

@property (nonatomic, strong) PHMediaSession *mediaSession;

#if !TARGET_IPHONE_SIMULATOR
@property (nonatomic, strong) PHVideoPublisher *publisher;
#endif

@property (nonatomic, strong) AFNetworkReachabilityManager *reachability;

@property (nonatomic, strong) NSURLSessionDataTask *socketTokenTask;
@property (nonatomic, strong) NSURLSessionDataTask *iceServersTask;

@end

@implementation PHConnectionBroker

#pragma mark - Init & Dealloc

- (instancetype)initWithDelegate:(id<PHConnectionBrokerDelegate>)delegate
{
    self = [super init];
    if (self) {
        _delegate = delegate;
        _mutableRemoteStreams = [NSMutableArray array];
    }
    return self;
}

- (void)dealloc
{
    DDLogDebug(@"%s", __PRETTY_FUNCTION__);
}

#pragma mark - NSObject

+ (NSSet *)keyPathsForValuesAffectingPeerConnectionState
{
    return [NSSet setWithObject:@"peerClient.connectionState"];
}

#pragma mark - Public

// Fetch the ice servers, and socket credentials in order to connect with the room.
- (BOOL)connectToRoom:(XSRoom *)room withConfiguration:(PHMediaConfiguration *)configuration
{
    NSParameterAssert(room);

    DDLogInfo(@"Connect to room: %@", room);

    if (!self.apiClient) {
        [self setupAPIClient];
    }

    [self setupPeerClientWithRoom:room];

    // With XirSys, we need to ask for tokens on demand, as they expire very quickly.

    [self authorizePeerClient];

    if (!self.reachability) {
        [self setupReachability];
    }

    if (!self.mediaSession) {
        [self setupMediaSessionWithConfiguration:configuration];
    }

    return YES;
}

- (void)disconnect
{
    [self disconnectPrivate];
}

- (XSPeerConnectionState)peerConnectionState
{
    return self.peerClient.connectionState;
}

- (XSRoom *)room
{
    return self.peerClient.room;
}

- (RTCMediaStream *)localStream
{
    return self.mediaSession.localStream;
}

- (NSArray *)remoteStreams
{
    return [self.mutableRemoteStreams copy];
}

#pragma mark - Private

- (void)setupAPIClient
{
    XSClient *apiClient = [[XSClient alloc] initWithUsername:kPHConnectionManagerXSUsername secretKey:kPHConnectionManagerXSSecretKey];
    self.apiClient = apiClient;
}

- (void)setupMediaSessionWithConfiguration:(PHMediaConfiguration *)config
{
    PHVideoCaptureKit *captureKit = nil;
#if !TARGET_IPHONE_SIMULATOR
    if (kPHConnectionManagerUseCaptureKit) {
        self.publisher = [[PHVideoPublisher alloc] init];
        captureKit = self.publisher.captureKit;
    }
#endif
    self.mediaSession = [[PHMediaSession alloc] initWithDelegate:self configuration:config andCapturer:captureKit];

    dispatch_async(dispatch_get_main_queue(), ^{
        [self.delegate connectionBroker:self didAddLocalStream:self.localStream];
    });
}

- (void)setupPeerClientWithRoom:(XSRoom *)room
{
    [room addRoomObserver:self];

    XSPeerClient *peerClient = [[XSPeerClient alloc] initWithRoom:room andDelegate:self];

    self.peerClient = peerClient;
}

- (void)setupReachability
{
    self.reachability = [AFNetworkReachabilityManager managerForDomain:@"api.xirsys.com"];

    __weak typeof(self) weakSelf = self;

    [self.reachability setReachabilityStatusChangeBlock:^(AFNetworkReachabilityStatus status) {
        [weakSelf checkAuthorizationStatus];
    }];

    [self.reachability startMonitoring];
}

- (void)authorizePeerClient
{
    DDLogDebug(@"%s", __PRETTY_FUNCTION__);

    XSObjectCompletion socketTokenHandler = ^(id object, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!error) {
                NSString *token = [self parseSocketCredentials:object];
                [self.room authorizeWithToken:token];
                [self.peerClient connect];
            }
            else {
                [self.delegate connectionBroker:self didFailWithError:error];
            }

            self.socketTokenTask = nil;
        });
    };

    self.socketTokenTask = [self.apiClient getTokenForDomain:kPHConnectionManagerDomain
                                                 application:kPHConnectionManagerApplication
                                                        room:self.room.name
                                                    username:self.room.localPeer.identifier
                                                      secure:YES
                                                  completion:socketTokenHandler];
}

- (void)checkAuthorizationStatus
{
    BOOL isAuthorized = [self.room.authToken length] > 0;
    BOOL authorizationInProgress = self.socketTokenTask != nil;
    BOOL isReachable = self.reachability.isReachable;

    if (!isAuthorized && !authorizationInProgress && isReachable) {
        [self authorizePeerClient];
    }
}

- (void)fetchICEServersAndSetupPeerConnectionForRoom:(XSRoom *)room peer:(XSPeer *)peer connectionId:(NSString *)connectionId offer:(RTCSessionDescription *)offerSDP
{
    XSArrayCompletion iceServersHandler = ^(NSArray *collection, NSError *error) {

        dispatch_async(dispatch_get_main_queue(), ^{
            if (!error) {
                NSArray *servers = [self parseIceServers:collection];

                [self.mediaSession addIceServers:servers singleUse:YES];
            }
            else {
                [self.delegate connectionBroker:self didFailWithError:error];
            }

            self.iceServersTask = nil;
        });
    };

    if (offerSDP) {
        [self.mediaSession acceptConnectionFromPeer:peer.identifier withId:connectionId offer:offerSDP];
    }
    else {
        [self.mediaSession connectToPeer:peer.identifier];
    }

    if (!self.iceServersTask) {
        DDLogVerbose(@"Fetching ICE servers for room: %@", room);

        self.iceServersTask = [self.apiClient getIceServersForDomain:kPHConnectionManagerDomain
                                                         application:kPHConnectionManagerApplication
                                                                room:room.name
                                                            username:room.localPeer.identifier
                                                              secure:YES
                                                          completion:iceServersHandler];
    }
    else {
        DDLogVerbose(@"Not fetching ICE servers, a request is already in progress.");
    }
}

- (void)checkCaptureFormat
{
#if !TARGET_IPHONE_SIMULATOR

    // Reduce capture quality for multi-party.

    PHCapturePreset preset = [PHVideoPublisher recommendedCapturePreset];

    if (self.mediaSession.connectionCount > 1) {
        preset = PHCapturePresetAcademyExtraLowQuality;
    }

    [self.publisher updateCaptureFormat:preset];
#endif
}

- (void)disconnectPrivate
{
    DDLogInfo(@"Connection broker: Disconnect.");

    // We are assuming that its possible to send messages to the room immediately before closing the socket in teardownConnection.
    // This has worked so far in my testing.

    if (self.peerClient.connectionState == XSPeerConnectionStateConnected) {
        [self sendByeToConnectedPeers];
    }

    [self.peerClient disconnect];

    [self teardownAPIClient];

    [self teardownMedia];

    if (self.peerConnectionState == XSPeerConnectionStateDisconnected) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self.delegate connectionBrokerDidFinish:self];
        });
    }
}

- (void)teardownAPIClient
{
    [self.iceServersTask cancel];
    self.iceServersTask = nil;

    [self.socketTokenTask cancel];
    self.socketTokenTask = nil;

    self.apiClient = nil;
}

- (void)teardownReachability
{
    [self.reachability stopMonitoring];
    self.reachability = nil;
}

- (void)teardownMedia
{
    [self.mutableRemoteStreams removeAllObjects];

    [self.mediaSession stopLocalMedia];
}

- (void)sendSessionDescription:(RTCSessionDescription *)sdp toPeer:(NSString *)peerId connectionId:(NSString *)connectionId
{
    DDLogVerbose(@"Send session description to peer: %@", peerId);

    NSDictionary *json = @{@"sdp" : sdp.description, @"type" : sdp.type};
    XSMessage *message = nil;

    // Generate a connection Id for offers.

    if ([sdp.type isEqualToString:@"offer"]) {
        message = [XSMessage offerWithUserId:peerId connectionId:connectionId andData:json];
    }
    else {
        message = [XSMessage answerWithUserId:peerId connectionId:connectionId andData:json];
    }

    [self.peerClient sendMessage:message];
}

- (void)sendByeToConnectedPeers
{
    NSArray *peers = [self.room.peers allValues];

    for (XSPeer *peer in peers) {
        PHPeerConnection *connection = [self.mediaSession connectionForPeerId:peer.identifier];

        if (connection) {
            [self sendByeToPeer:peer connectionId:connection.connectionId];
        }
    }
}

- (void)sendByeToPeer:(XSPeer *)peer connectionId:(NSString *)connectionId
{
    XSMessage *message = [XSMessage byeWithUserId:peer.identifier connectionId:connectionId andData:@{}];
    [self.peerClient sendMessage:message];
}

- (NSArray *)parseIceServers:(NSArray *)iceServers
{
    NSMutableArray *rtcServers = [NSMutableArray array];

    for (XSServer *server in iceServers) {
        RTCICEServer *rtcServer = [[self class] iceServerFromXSServer:server];

        if (rtcServer) {
            [rtcServers addObject:rtcServer];
        }
    }

    return rtcServers;
}

- (NSString *)parseSocketCredentials:(id)socketData
{
    NSString *token = nil;

    // ..Parse the socket credentials

    if ([socketData isKindOfClass:[NSDictionary class]]) {
        token = socketData[@"token"];
    }

    return token;
}

- (void)handleICEMessage:(XSMessage *)message
{
    NSDictionary *messageData = message.data[@"data"];
    NSDictionary *iceData = messageData[kXSMessageICECandidateDataKey];
    NSString *connectionId = messageData[kXSMessageConnectionIdKey];
    BOOL shouldAccept = [connectionId length] > 0;

    if (!shouldAccept) {
        DDLogWarn(@"Discarding ICE Message :%@", message);
        return;
    }

    NSString *mid = iceData[@"id"];
    NSNumber *sdpLineIndex = iceData[@"label"];
    NSString *sdp = iceData[@"candidate"];
    RTCICECandidate *candidate = [[RTCICECandidate alloc] initWithMid:mid
                                                                index:sdpLineIndex.intValue
                                                                  sdp:sdp];

    [self.mediaSession addIceCandidate:candidate forPeer:message.senderId connectionId:connectionId];;
}

- (void)handleOffer:(XSMessage *)message
{
    NSDictionary *messageData = message.data[@"data"];
    NSString *connectionId = messageData[kXSMessageConnectionIdKey];
    NSString *peerId = message.senderId;
    PHPeerConnection *peerConnection = [self.mediaSession connectionForPeerId:peerId];
    BOOL shouldAccept = !peerConnection && [connectionId length] > 0;
    BOOL shouldRenegotiate = peerConnection && [peerConnection.connectionId isEqualToString:connectionId];

    NSString *sdpString = messageData[kXSMessageOfferDataKey][@"sdp"];
    NSString *sdpType = messageData[kXSMessageOfferDataKey][@"type"];
    RTCSessionDescription *sdp = [[RTCSessionDescription alloc] initWithType:sdpType sdp:sdpString];
    XSPeer *peer = self.peerClient.room.peers[peerId];

    if (shouldAccept) {
        [self fetchICEServersAndSetupPeerConnectionForRoom:self.peerClient.room peer:peer connectionId:connectionId offer:sdp];
    }
    else if (shouldRenegotiate) {
        [self.mediaSession addOffer:sdp forPeer:message.senderId connectionId:connectionId];
    }
    else {
        [self sendByeToPeer:self.room.peers[message.senderId] connectionId:connectionId];
    }
}

- (void)handleAnswer:(XSMessage *)message
{
    NSDictionary *messageData = message.data[@"data"];
    NSString *connectionId = messageData[kXSMessageConnectionIdKey];
    NSString *sdpString = messageData[kXSMessageAnswerDataKey][@"sdp"];
    NSString *sdpType = messageData[kXSMessageAnswerDataKey][@"type"];
    RTCSessionDescription *sdp = [[RTCSessionDescription alloc] initWithType:sdpType sdp:sdpString];

    [self.mediaSession addAnswer:sdp forPeer:message.senderId connectionId:connectionId];
}

- (void)handleBye:(XSMessage *)message
{
    NSDictionary *messageData = message.data[@"data"];
    NSString *connectionId = messageData[kXSMessageConnectionIdKey];

    [self.mediaSession closeConnectionWithPeer:message.senderId];
}

- (void)evaluatePeerCandidate:(XSPeer *)peer
{
    NSLog(@"%s", __PRETTY_FUNCTION__);

    PHPeerConnection *peerConnection = [self.mediaSession connectionForPeerId:peer.identifier];

    if (!peerConnection) {
        [self fetchICEServersAndSetupPeerConnectionForRoom:self.room peer:peer connectionId:nil offer:nil];
    }
    else {
        DDLogWarn(@"Not opening a peer connection with: %@ because one already exists.", peer.identifier);
    }
}

- (BOOL)isRoomFull:(XSRoom *)room
{
    return [room.peers count] > kPHConnectionManagerMaxRoomPeers;
}

#pragma mark - Class

+ (RTCICEServer *)iceServerFromXSServer:(XSServer *)server
{
    // We can't pass in nil strings to the RTCICEServer.

    RTCICEServer *iceServer = [[RTCICEServer alloc] initWithURI:server.URL
                                                       username:(server.username ? server.username : @"")
                                                       password:(server.credential ? server.credential : @"")];
    return iceServer;
}

#pragma mark - PHSignalingDelegate

- (void)signalOffer:(RTCSessionDescription *)sdpOffer forConnection:(PHPeerConnection *)connection
{
    [self sendSessionDescription:sdpOffer toPeer:connection.peerId connectionId:connection.connectionId];
}

- (void)signalAnswer:(RTCSessionDescription *)sdpAnswer forConnection:(PHPeerConnection *)connection
{
    [self sendSessionDescription:sdpAnswer toPeer:connection.peerId connectionId:connection.connectionId];
}

- (void)signalICECandidate:(RTCICECandidate *)iceCandidate forConnection:(PHPeerConnection *)connection
{
    DDLogVerbose(@"Send ICE candidate: %@", iceCandidate.sdpMid);

    NSDictionary *json = @{
                           @"label" : @(iceCandidate.sdpMLineIndex),
                           @"id" : iceCandidate.sdpMid,
                           @"candidate" : iceCandidate.sdp
                           };

    XSMessage *message = [XSMessage iceCredentialsWithUserId:connection.peerId connectionId:connection.connectionId andData:json];

    [self.peerClient sendMessage:message];
}

- (void)connection:(PHPeerConnection *)connection addedStream:(RTCMediaStream *)stream
{
    [self.mutableRemoteStreams addObject:stream];

    [self.delegate connectionBroker:self didAddStream:stream];
}

- (void)connection:(PHPeerConnection *)connection removedStream:(RTCMediaStream *)stream
{
    [self.mutableRemoteStreams removeObject:stream];

    [self.delegate connectionBroker:self didRemoveStream:stream];
}

- (void)connection:(PHPeerConnection *)connection iceStatusChanged:(RTCICEConnectionState)state
{
    switch (state) {
        case RTCICEConnectionNew:
        case RTCICEConnectionChecking:
        case RTCICEConnectionCompleted:
        case RTCICEConnectionConnected:
            break;
        case RTCICEConnectionClosed:
        {
            [self.mediaSession closeConnectionWithPeer:connection.peerId];
            break;
        }
        case RTCICEConnectionDisconnected:
        {
            // We had an active connection, but we lost it.
            // Recover with an ice-restart?

            BOOL peerReachable = self.room.peers[connection.peerId] != nil;
            BOOL closeConnection = self.peerConnectionState != XSPeerConnectionStateConnected || !peerReachable;

            if (closeConnection) {
                [self.mediaSession closeConnectionWithPeer:connection.peerId];
            }

            break;
        }
        case RTCICEConnectionFailed:
        {
            // The connection failed during the ICE candidate phase.
            // While the peer is available on the signaling server we should retry with an ice-restart.

            BOOL peerReachable = self.room.peers[connection.peerId] != nil;
            BOOL isInitiator = connection.role == PHPeerConnectionRoleInitiator;
            BOOL canAttemptRestart = connection.iceAttempts <= kPHConnectionManagerMaxIceAttempts;

            BOOL restartICE = isInitiator && peerReachable && canAttemptRestart;
            BOOL closeConnection = !peerReachable || !canAttemptRestart;

            if (restartICE) {
                [self.mediaSession restartIceWithPeer:connection.peerId];
            }
            else if (closeConnection) {
                [self.mediaSession closeConnectionWithPeer:connection.peerId];
            }

            break;
        }
    }
}

- (BOOL)session:(PHMediaSession *)session shouldRenegotiateConnectionsWithFormat:(PHVideoFormat)receiverFormat
{
    [self checkCaptureFormat];

    return YES;
}

#pragma mark - XSPeerClientDelegate

- (void)clientDidConnect:(XSPeerClient *)client
{
    // Wait for join event to come. Potentially inform our delegate of signaling connection status?
}

- (void)clientDidDisconnect:(XSPeerClient *)client
{
    // If this was a final disconnection, let our delegate know.

    if (!self.apiClient) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self.delegate connectionBrokerDidFinish:self];
        });
    }

    // Wait for reachability to re-authorize the connection.
}

- (void)client:(XSPeerClient *)client didEncounterError:(NSError *)error
{
    [self.delegate connectionBroker:self didFailWithError:error];
}

#pragma mark - XSRoomObserver

- (void)didJoinRoom:(XSRoom *)room
{
    // Prevent multi-party connections when there are too many participants.

    if ([self isRoomFull:room]) {
        [self.peerClient disconnect];
        NSError *error = [[NSError alloc] initWithDomain:PHErrorDomain code:PHErrorCodeFullRoom userInfo:nil];
        [self.delegate connectionBroker:self didFailWithError:error];
        
        return;
    }

    // If we are the first peer, wait for another.
    // If other peers already exist then wait for an offer.

    DDLogVerbose(@"Joined room with peers: %@", room.peers);
}

// TODO: Leave observer event is not fired.
- (void)didLeaveRoom:(XSRoom *)room
{
}

- (void)room:(XSRoom *)room didAddPeer:(XSPeer *)peer
{
    if (![self isRoomFull:room]) {
        [self evaluatePeerCandidate:peer];
    }
}

- (void)room:(XSRoom *)room didRemovePeer:(XSPeer *)peer
{
    NSString *peerId = peer.identifier;
    PHPeerConnection *peerConnectionWrapper = [self.mediaSession connectionForPeerId:peerId];

    if (!peerConnectionWrapper) {
        return;
    }

    RTCICEConnectionState iceState = peerConnectionWrapper.peerConnection.iceConnectionState;

    switch (iceState) {
        case RTCICEConnectionDisconnected:
        case RTCICEConnectionNew:
        case RTCICEConnectionFailed:
            [self.mediaSession closeConnectionWithPeer:peerId];
            break;
        default:
            break;
    }
}

- (void)room:(XSRoom *)room didReceiveMessage:(XSMessage *)message
{
    NSString *type = message.type;

    // Handle incoming SDP offers, and answers.
    // Handle ICE credentials from peers.

    if ([type isEqualToString:kXSMessageEventICE]) {
        [self handleICEMessage:message];
    }
    else if ([type isEqualToString:kXSMessageEventOffer]) {
        [self handleOffer:message];
    }
    else if ([type isEqualToString:kXSMessageEventAnswer]) {
        [self handleAnswer:message];
    }
    else if ([type isEqualToString:kXSMessageEventBye]) {
        [self handleBye:message];
    }
}

@end
