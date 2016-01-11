//
//  PHMediaSession.m
//  PerchRTC
//
//  Created by Christopher Eagleston on 2014-12-16.
//  Copyright (c) 2014 Perch Communications. All rights reserved.
//

#import "PHMediaSession.h"

#import "PHAudioSessionController.h"
#import "PHMediaConfiguration.h"
#import "PHPeerConnection.h"
#import "PHSessionDescriptionFactory.h"
#import "PHVideoPublisher.h"

// WebRTC classes.
#import "RTCICECandidate.h"
#import "RTCICEServer.h"
#import "RTCMediaConstraints.h"
#import "RTCMediaStream.h"
#import "RTCPair.h"
#import "RTCPeerConnection.h"
#import "RTCPeerConnectionDelegate.h"
#import "RTCPeerConnectionFactory.h"
#import "RTCSessionDescription.h"
#import "RTCSessionDescriptionDelegate.h"
#import "RTCStatsDelegate.h"
#import "RTCVideoCapturer.h"
#import "RTCVideoSource.h"
#import "RTCVideoTrack.h"
#import "RTCStatsReport.h"
#import "RTCMediaStream.h"
#import "RTCMediaStreamTrack.h"

@import AVFoundation;

static BOOL PHMediaSessionGatherConnectionStats = NO;

@interface PHMediaSession() <RTCPeerConnectionDelegate, RTCSessionDescriptionDelegate, RTCMediaStreamTrackDelegate, RTCStatsDelegate>

@property (nonatomic, strong) PHAudioSessionController *audioController;
@property (nonatomic, weak) PHVideoCaptureKit *captureKit;
@property (nonatomic, strong) RTCMediaStream *localStream;
@property (nonatomic, strong) RTCVideoSource *videoSource;
@property (nonatomic, strong) RTCPeerConnectionFactory *peerConnectionFactory;

@property (nonatomic, strong) NSArray *iceServers;
@property (nonatomic, strong) NSMutableDictionary *peerToConnectionMap;
@property (nonatomic, strong) NSTimer *statsTimer;

@end

@implementation PHMediaSession

#pragma mark - Init & Dealloc

- (instancetype)init
{
    // Results in a parameter assertion. The session must be initialized with a delegate.

    return [self initWithDelegate:nil];
}

- (instancetype)initWithDelegate:(id<PHSignalingDelegate>)delegate
{
    PHMediaConfiguration *config = [PHMediaConfiguration defaultConfiguration];

    return [self initWithDelegate:delegate configuration:config andCapturer:nil];
}

- (instancetype)initWithDelegate:(id<PHSignalingDelegate>)delegate configuration:(PHMediaConfiguration *)config andCapturer:(PHVideoCaptureKit *)capturer
{
    NSParameterAssert(delegate);
    NSParameterAssert(config);

    self = [super init];

    if (self) {
        _captureKit = capturer;
        _delegate = delegate;
        _sessionConfiguration = [config copy];

        [RTCPeerConnectionFactory initializeSSL];

        _peerConnectionFactory = [[RTCPeerConnectionFactory alloc] init];
        _peerToConnectionMap = [NSMutableDictionary dictionary];
        _audioController = [[PHAudioSessionController alloc] init];

        // TODO: Should local media setup and teardown be dynamic?

        [self setupLocalMedia];
    }

    return self;
}

- (void)dealloc
{
    DDLogDebug(@"%s", __PRETTY_FUNCTION__);

    [_peerToConnectionMap removeAllObjects];

    _videoSource = nil;
    _localStream = nil;
    _peerConnectionFactory = nil;

    [RTCPeerConnectionFactory deinitializeSSL];

    [_audioController deactivateSessionWithAudioMode:PHAudioSessionModeAmbient];
}

#pragma mark - Public

- (void)connectToPeer:(NSString *)peerId
{
    [self connectToPeer:peerId iceServers:self.iceServers];
}

- (void)acceptConnectionFromPeer:(NSString *)peerId withId:(NSString *)connectionId offer:(RTCSessionDescription *)offer
{
    [self acceptConnectionFromPeer:peerId withId:connectionId offer:offer iceServers:self.iceServers];
}

- (void)addIceServers:(NSArray *)iceServers singleUse:(BOOL)isSingleUse
{
    NSArray *filteredIceServers = [self filteredIceServers:iceServers];

    if (!isSingleUse) {
        self.iceServers = filteredIceServers;
    }

    [self.peerToConnectionMap enumerateKeysAndObjectsUsingBlock:^(NSString *peerId, PHPeerConnection *peerConnectionWrapper, BOOL *stop)
    {
        if (!peerConnectionWrapper.peerConnection) {
            peerConnectionWrapper.peerConnection = [self peerConnnectionWithServers:filteredIceServers];
            if (peerConnectionWrapper.role == PHPeerConnectionRoleInitiator) {
                RTCMediaConstraints *constraints = [PHSessionDescriptionFactory offerConstraints];
                [peerConnectionWrapper.peerConnection createOfferWithDelegate:self constraints:constraints];
            }
            else {
                RTCSessionDescription *offer = peerConnectionWrapper.queuedOffer;
                [peerConnectionWrapper.peerConnection setRemoteDescriptionWithDelegate:self sessionDescription:offer];
                peerConnectionWrapper.queuedOffer = nil;
            }
        }
    }];
}

- (void)restartIceWithPeer:(NSString *)peerId
{
    DDLogVerbose(@"Restart ICE with peer: %@", peerId);

    PHPeerConnection *connectionWrapper = self.peerToConnectionMap[peerId];
    RTCMediaConstraints *offerConstraints = [PHSessionDescriptionFactory offerConstraintsRestartIce:YES];

    [connectionWrapper.peerConnection createOfferWithDelegate:self constraints:offerConstraints];
}

- (void)closeConnectionWithPeer:(NSString *)peerId
{
    NSParameterAssert(peerId);

    PHPeerConnection *peerConnection = self.peerToConnectionMap[peerId];

    if (!peerConnection) {
        DDLogWarn(@"No connection to close for: %@", peerId);
        return;
    }

    DDLogVerbose(@"Closing connection with peer: %@", peerId);

    RTCMediaStream *remoteStream = peerConnection.remoteStream;
    [peerConnection close];

    if (remoteStream) {
        [self.delegate connection:peerConnection removedStream:remoteStream];
    }

    [self.peerToConnectionMap removeObjectForKey:peerId];

    if ([self activeConnectionCount] == 1) {
        [self renegotiateActiveConnections];
    }
    else if (self.connectionCount == 0) {
        [self stopStatsCollection];
    }
}

- (void)addIceCandidate:(RTCICECandidate *)candidate forPeer:(NSString *)peerId connectionId:(NSString *)connectionId
{
    PHPeerConnection *connectionWrapper = self.peerToConnectionMap[peerId];

    // Handle case where ICE candidates reach us before we are able to fetch ICE servers and create a connection.

    if (!connectionWrapper) {
        DDLogWarn(@"No connection for ICE candidate: %@", candidate);
        return;
    }

    RTCICECandidate *filteredCandidate = [self filteredIceCandidate:candidate];

    if (filteredCandidate) {
        [connectionWrapper addIceCandidate:filteredCandidate];
    }
}

- (void)addAnswer:(RTCSessionDescription *)answerSDP forPeer:(NSString *)peerId connectionId:(NSString *)connectionId
{
    PHPeerConnection *connectionWrapper = self.peerToConnectionMap[peerId];

    [connectionWrapper.peerConnection setRemoteDescriptionWithDelegate:self sessionDescription:answerSDP];
}

- (void)addOffer:(RTCSessionDescription *)offerSDP forPeer:(NSString *)peerId connectionId:(NSString *)connectionId
{
    PHPeerConnection *connectionWrapper = self.peerToConnectionMap[peerId];

    [connectionWrapper.peerConnection setRemoteDescriptionWithDelegate:self sessionDescription:offerSDP];
}

- (PHPeerConnection *)connectionForPeerId:(NSString *)peerId
{
    return self.peerToConnectionMap[peerId];
}

- (NSUInteger)connectionCount
{
    return [self.peerToConnectionMap count];
}

- (NSUInteger)activeConnectionCount
{
    return [[self activeConnections] count];
}

#pragma mark - Private

- (NSArray *)activeConnections
{
    NSSet *keys = [self.peerToConnectionMap keysOfEntriesPassingTest:^BOOL(NSString *peerId, PHPeerConnection *peerConnection, BOOL *stop) {
        RTCPeerConnection *rtcConnection = peerConnection.peerConnection;
        if (rtcConnection.signalingState == RTCSignalingStable && rtcConnection.iceConnectionState != RTCICEConnectionFailed) {
            return YES;
        }
        return NO;
    }];

    return [self.peerToConnectionMap objectsForKeys:[keys allObjects] notFoundMarker:[NSNull null]];
}

- (NSArray *)filteredIceServers:(NSArray *)serversToFilter
{
    PHIceFilter iceFilter = self.sessionConfiguration.iceFilter;

    if (iceFilter == PHIceFilterAny) {
        return serversToFilter;
    }

    NSIndexSet *indexSet = [serversToFilter indexesOfObjectsPassingTest:^BOOL(RTCICEServer *server, NSUInteger idx, BOOL *stop) {
        BOOL pass = NO;

        if (iceFilter & PHIceFilterStun) {
            pass = [server.URI.scheme isEqualToString:@"stun"];
        }
        else if (iceFilter & PHIceFilterTurn) {
            pass = [server.URI.scheme isEqualToString:@"turn"];
        }

        return pass;
    }];

    return [serversToFilter objectsAtIndexes:indexSet];
}

- (RTCICECandidate *)filteredIceCandidate:(RTCICECandidate *)candidate
{
    BOOL sendCandidate = YES;

    // Filter candidates by type.

    PHIceFilter iceFilter = self.sessionConfiguration.iceFilter;

    if (!(iceFilter & PHIceFilterLocal)) {
        sendCandidate = ![candidate.sdp containsString:@"typ host"];
    }
    if (sendCandidate && !(iceFilter & PHIceFilterStun)) {
        sendCandidate = ![candidate.sdp containsString:@"typ srflx"];
    }
    if (sendCandidate && !(iceFilter & PHIceFilterTurn)) {
        sendCandidate = ![candidate.sdp containsString:@"typ relay"];
    }

    // Filter by ice protocol.

    PHIceProtocol iceProtocol = self.sessionConfiguration.iceProtocol;

    NSAssert(iceProtocol != PHIceProtocolNone, @"Must choose an ICE protocol!");

    if (sendCandidate && (iceProtocol == PHIceProtocolTCP)) {
        sendCandidate = [candidate.sdp containsString:@"tcp"];
    }
    else if (sendCandidate && (iceProtocol == PHIceProtocolUDP)) {
        sendCandidate = [candidate.sdp containsString:@"udp"];
    }

    return sendCandidate ? candidate : nil;
}

- (PHPeerConnection *)connectionWrapperWithPeer:(NSString *)peerId connectionId:(NSString *)connectionId andServers:(NSArray *)iceServers
{
    NSParameterAssert(peerId);
    NSParameterAssert(connectionId);

    DDLogInfo(@"Setup peer connection with ICE servers: %@", iceServers);

    RTCPeerConnection *connection = nil;

    if (iceServers) {
        connection = [self peerConnnectionWithServers:iceServers];
    }

    PHPeerConnection *connectionWrapper = [[PHPeerConnection alloc] initWithConnection:connection];
    connectionWrapper.peerId = peerId;
    connectionWrapper.connectionId = connectionId;

    return connectionWrapper;
}

- (RTCPeerConnection *)peerConnnectionWithServers:(NSArray *)iceServers
{
    RTCMediaConstraints *constraints = [PHSessionDescriptionFactory connectionConstraints];
    RTCPeerConnection *connection = [self.peerConnectionFactory peerConnectionWithICEServers:iceServers constraints:constraints delegate:self];

    [connection addStream:self.localStream];

    return connection;
}

- (void)acceptConnectionFromPeer:(NSString *)peerId withId:(NSString *)connectionId offer:(RTCSessionDescription *)offer iceServers:(NSArray *)iceServers
{
    NSParameterAssert(offer);
    NSAssert(self.peerToConnectionMap[peerId] == nil, @"Attempted to connect to a peer which we are already connected!");

    PHPeerConnection *peerConnectionWrapper = [self connectionWrapperWithPeer:peerId connectionId:connectionId andServers:iceServers];
    peerConnectionWrapper.role = PHPeerConnectionRoleReceiver;

    if (peerConnectionWrapper.peerConnection) {
        [peerConnectionWrapper.peerConnection setRemoteDescriptionWithDelegate:self sessionDescription:offer];
    }
    else {
        peerConnectionWrapper.queuedOffer = offer;
    }

    self.peerToConnectionMap[peerId] = peerConnectionWrapper;

    if ([self activeConnectionCount] > 1) {
        [self renegotiateActiveConnections];
    }
}

- (void)connectToPeer:(NSString *)peerId iceServers:(NSArray *)iceServers
{
    NSAssert(self.peerToConnectionMap[peerId] == nil, @"Attempted to connect to a peer which we are already connected!");

    PHPeerConnection *peerConnectionWrapper = [self connectionWrapperWithPeer:peerId connectionId:[self createGUID] andServers:iceServers];
    peerConnectionWrapper.role = PHPeerConnectionRoleInitiator;

    if (peerConnectionWrapper.peerConnection) {
        RTCMediaConstraints *constraints = [PHSessionDescriptionFactory offerConstraints];
        [peerConnectionWrapper.peerConnection createOfferWithDelegate:self constraints:constraints];
    }

    self.peerToConnectionMap[peerId] = peerConnectionWrapper;

    if ([self activeConnectionCount] > 1) {
        [self renegotiateActiveConnections];
    }
}

- (void)renegotiateActiveConnections
{
    NSArray *activeConnections = [self activeConnections];

    [self updateReceiverFormat];

    if (![self.delegate session:self shouldRenegotiateConnectionsWithFormat:self.sessionConfiguration.preferredReceiverFormat]) {
        return;
    }

    [activeConnections enumerateObjectsUsingBlock:^(PHPeerConnection *connectionWrapper, NSUInteger idx, BOOL *stop) {
        if (connectionWrapper.role == PHPeerConnectionRoleInitiator) {
            RTCMediaConstraints *constraints = [PHSessionDescriptionFactory offerConstraints];
            [connectionWrapper.peerConnection createOfferWithDelegate:self constraints:constraints];
        }
    }];
}

- (void)setupLocalMedia
{
    RTCMediaConstraints *videoConstraints = nil;

#if !TARGET_IPHONE_SIMULATOR

    if (self.captureKit) {
        PHVideoFormat captureFormat = [self.captureKit.videoCapturer videoCaptureFormat];
        videoConstraints = [PHSessionDescriptionFactory videoConstraintsForFormat:captureFormat];
    }

#endif

    [self setupLocalMediaWithVideoConstraints:videoConstraints];
}

- (void)setupLocalMediaWithVideoConstraints:(RTCMediaConstraints *)videoConstraints
{
    DDLogInfo(@"Setup local media with video constraints: %@", videoConstraints);

    RTCMediaStream *localMediaStream = [self.peerConnectionFactory mediaStreamWithLabel:[self createGUID]];
    RTCAudioTrack *audioTrack = [self.peerConnectionFactory audioTrackWithID:@"Audio"];

    if (audioTrack) {
        [localMediaStream addAudioTrack:audioTrack];
    }

    // The iOS simulator doesn't provide any sort of camera capture
    // support or emulation (http://goo.gl/rHAnC1) so don't bother
    // trying to open a local video track.

#if !TARGET_IPHONE_SIMULATOR

    RTCVideoCapturer *videoCapturer = nil;

    if (self.captureKit) {
        videoCapturer = (RTCVideoCapturer *)self.captureKit;
    }
    else {
        NSString *frontCameraId = [self frontFacingCameraDevice];

        NSAssert(frontCameraId, @"Unable to get the front camera id");

        videoCapturer = [RTCVideoCapturer capturerWithDeviceName:frontCameraId];
    }

    RTCVideoSource *videoSource = [self.peerConnectionFactory videoSourceWithCapturer:videoCapturer constraints:videoConstraints];
    RTCVideoTrack *localVideoTrack = [self.peerConnectionFactory videoTrackWithID:@"Video" source:videoSource];

    if (localVideoTrack) {
        [localMediaStream addVideoTrack:localVideoTrack];
    }

    self.videoSource = videoSource;

#endif

    self.localStream = localMediaStream;
}

- (void)stopLocalMedia
{
    DDLogDebug(@"%s", __PRETTY_FUNCTION__);

    NSArray *connectionWrappers = [self.peerToConnectionMap allValues];

    for (PHPeerConnection *connectionWrapper in connectionWrappers) {
        [connectionWrapper close];
    }

    [self.localStream removeAudioTrack:[self.localStream.audioTracks firstObject]];
    [self.localStream removeVideoTrack:[self.localStream.videoTracks firstObject]];

    self.videoSource = nil;
    self.localStream = nil;

    self.captureKit = nil;
}

- (NSString *)createGUID
{
    return [[NSUUID UUID] UUIDString];
}

- (NSString *)frontFacingCameraDevice
{
    NSString *cameraID = nil;

    for (AVCaptureDevice* captureDevice in [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo]) {
        if (captureDevice.position == AVCaptureDevicePositionFront) {
            cameraID = [captureDevice localizedName];
            break;
        }
    }

    return cameraID;
}

- (PHPeerConnection *)wrapperForConnection:(RTCPeerConnection *)connection
{
    PHPeerConnection *connectionWrapper = nil;
    NSArray *connectionWrappers = [self.peerToConnectionMap allValues];

    for (PHPeerConnection *wrapper in connectionWrappers) {
        if ([wrapper.peerConnection isEqual:connection]) {
            connectionWrapper = wrapper;
            break;
        }
    }

    return connectionWrapper;
}

#if !TARGET_IPHONE_SIMULATOR
- (PHVideoFormat)activeFormat
{
    PHVideoFormat format;

    if (self.captureKit) {
        format = [self.captureKit.videoCapturer videoCaptureFormat];
    }
    else {
        format.dimensions = (CMVideoDimensions){640, 480};
        format.frameRate = 30;
        format.pixelFormat = PHPixelFormatYUV420BiPlanarFullRange;
    }

    return format;
}
#endif

- (void)startStatsCollectionWithInterval:(NSTimeInterval)interval
{
    NSTimer *statsTimer = [NSTimer timerWithTimeInterval:interval target:self selector:@selector(collectConnectionStats) userInfo:nil repeats:YES];

    [[NSRunLoop mainRunLoop] addTimer:statsTimer forMode:NSRunLoopCommonModes];

    self.statsTimer = statsTimer;
}

- (void)collectConnectionStats
{
    NSArray *connectionWrappers = [self.peerToConnectionMap allValues];

    for (PHPeerConnection *peerConnectionWrapper in connectionWrappers) {
        RTCPeerConnection *peerConnection = peerConnectionWrapper.peerConnection;
        [peerConnection getStatsWithDelegate:self mediaStreamTrack:nil statsOutputLevel:RTCStatsOutputLevelStandard];
    }
}

- (void)stopStatsCollection
{
    [self.statsTimer invalidate];
    self.statsTimer = nil;
}

- (void)updateReceiverFormat
{
    // Checks the preferred receiver format, based upon the number of connected peers.

    BOOL isMultiparty = self.connectionCount > 1;
    PHVideoFormat receiverFormat = self.sessionConfiguration.preferredReceiverFormat;
    NSUInteger audioRate;

    if (isMultiparty) {
        receiverFormat.dimensions = (CMVideoDimensions){352, 288};
        audioRate = PHMediaSessionMaximumAudioRateMultiparty;
    }
    else {
        receiverFormat.dimensions = (CMVideoDimensions){640, 480};
        audioRate = PHMediaSessionMaximumAudioRate;
    }

    self.sessionConfiguration.preferredReceiverFormat = receiverFormat;
    self.sessionConfiguration.maxAudioBitrate = audioRate;
}

#pragma mark - String utilities

- (NSString *)stringForSignalingState:(RTCSignalingState)state
{
    switch (state) {
        case RTCSignalingStable:
            return @"Stable";
            break;
        case RTCSignalingHaveLocalOffer:
            return @"Have Local Offer";
            break;
        case RTCSignalingHaveRemoteOffer:
            return @"Have Remote Offer";
            break;
        case RTCSignalingClosed:
            return @"Closed";
            break;
        default:
            return @"Other state";
            break;
    }
}

- (NSString *)stringForConnectionState:(RTCICEConnectionState)state
{
    switch (state) {
        case RTCICEConnectionNew:
            return @"New";
            break;
        case RTCICEConnectionChecking:
            return @"Checking";
            break;
        case RTCICEConnectionConnected:
            return @"Connected";
            break;
        case RTCICEConnectionCompleted:
            return @"Completed";
            break;
        case RTCICEConnectionFailed:
            return @"Failed";
            break;
        case RTCICEConnectionDisconnected:
            return @"Disconnected";
            break;
        case RTCICEConnectionClosed:
            return @"Closed";
            break;
        default:
            return @"Other state";
            break;
    }
}

- (NSString *)stringForGatheringState:(RTCICEGatheringState)state
{
    switch (state) {
        case RTCICEGatheringNew:
            return @"New";
            break;
        case RTCICEGatheringGathering:
            return @"Gathering";
            break;
        case RTCICEGatheringComplete:
            return @"Complete";
            break;
        default:
            return @"Other state";
            break;
    }
}

#pragma mark - RTCPeerConnectionDelegate

- (void)peerConnectionOnError:(RTCPeerConnection *)peerConnection
{
    // TODO: Connection Error handling.
//    [self.delegate connectionManager:self didErrorWithMessage:@"Media connection error."];
}

- (void)peerConnection:(RTCPeerConnection *)peerConnection signalingStateChanged:(RTCSignalingState)stateChanged
{
    DDLogVerbose(@"Peer connection: Signaling state changed: %@", [self stringForSignalingState:stateChanged]);
}

- (void)peerConnection:(RTCPeerConnection *)peerConnection addedStream:(RTCMediaStream *)stream
{
    dispatch_async(dispatch_get_main_queue(), ^{
        DDLogVerbose(@"Peer connection added stream: %@", stream);

        PHPeerConnection *connectionWrapper = [self wrapperForConnection:peerConnection];

        connectionWrapper.remoteStream = stream;
        RTCVideoTrack *videoTrack = [stream.videoTracks firstObject];
        videoTrack.delegate = self;

        [self.delegate connection:connectionWrapper addedStream:stream];

        if (PHMediaSessionGatherConnectionStats && !self.statsTimer) {
            [self startStatsCollectionWithInterval:5];
        }
    });
}

- (void)peerConnection:(RTCPeerConnection *)peerConnection removedStream:(RTCMediaStream *)stream
{
    dispatch_async(dispatch_get_main_queue(), ^{
        DDLogVerbose(@"Peer connection removed stream: %@", stream);

        PHPeerConnection *connectionWrapper = [self wrapperForConnection:peerConnection];
        connectionWrapper.remoteStream = nil;

        [self.delegate connection:connectionWrapper removedStream:stream];
    });
}

// Triggered when renegotiation is needed, for example the ICE has restarted.
- (void)peerConnectionOnRenegotiationNeeded:(RTCPeerConnection *)peerConnection
{
    // Not sure if this is needed or not. Why does the AppRTC demo not implement it?

    DDLogVerbose(@"Peer connection renegotiation needed: %@", peerConnection);
}

- (void)peerConnection:(RTCPeerConnection *)peerConnection iceConnectionChanged:(RTCICEConnectionState)newState
{
    dispatch_async(dispatch_get_main_queue(), ^{
        DDLogVerbose(@"Peer connection ICE status is: %@", [self stringForConnectionState:newState]);

        PHPeerConnection *connectionWrapper = [self wrapperForConnection:peerConnection];

        if (!connectionWrapper) {
            return;
        }

        if (newState == RTCICEConnectionFailed) {
            connectionWrapper.iceAttempts++;
            [connectionWrapper removeRemoteCandidates];
        }
        else if (newState == RTCICEConnectionConnected) {
            connectionWrapper.iceAttempts = 0;
        }

        [self.delegate connection:connectionWrapper iceStatusChanged:newState];
    });
}

- (void)peerConnection:(RTCPeerConnection *)peerConnection iceGatheringChanged:(RTCICEGatheringState)newState
{
    if (newState == RTCICEGatheringGathering) {
        dispatch_async(dispatch_get_main_queue(), ^{
            DDLogVerbose(@"Peer connection ICE gathering changed: %@", [self stringForGatheringState:newState]);

            if (peerConnection.iceGatheringState == RTCICEGatheringGathering) {
                PHPeerConnection *connectionWrapper = [self wrapperForConnection:peerConnection];
                [connectionWrapper drainRemoteCandidates];
            }
        });
    }
}

- (void)peerConnection:(RTCPeerConnection *)peerConnection gotICECandidate:(RTCICECandidate *)candidate
{
    // Share this ICE candidate with our peers.

    dispatch_async(dispatch_get_main_queue(), ^{
        PHPeerConnection *connectionWrapper = [self wrapperForConnection:peerConnection];

        if (!connectionWrapper) {
            return ;
        }

        RTCICECandidate *filteredCandidate = [self filteredIceCandidate:candidate];

        if (filteredCandidate) {
            [self.delegate signalICECandidate:filteredCandidate forConnection:connectionWrapper];
        }
    });
}

- (void)peerConnection:(RTCPeerConnection *)peerConnection didOpenDataChannel:(RTCDataChannel *)dataChannel
{
    // Not used in this sample.

    DDLogVerbose(@"Peer connection did open data channel: %@", dataChannel);
}

#pragma mark - RTCSessionDescriptionDelegate

- (void)peerConnection:(RTCPeerConnection *)peerConnection didCreateSessionDescription:(RTCSessionDescription *)sdp error:(NSError *)error
{
    if (error) {
        DDLogError(@"Peer connection did create SDP: %@ with error: %@", sdp, error);
        return;
    }

    // Send an SDP.

    dispatch_async(dispatch_get_main_queue(), ^{

        DDLogVerbose(@"Peer connection did create %@", sdp.type);

        // Set the local description.

        PHVideoFormat format = self.sessionConfiguration.preferredReceiverFormat;
        NSUInteger maxVideoRate = PHVideoFormatComputePeakRate(format, PHMediaSessionTargetBpp, PHMediaSessionMaximumVideoRate);
        NSUInteger maxAudioRate = self.sessionConfiguration.maxAudioBitrate;
        PHAudioCodec audioCodec = self.sessionConfiguration.preferredAudioCodec;
        PHVideoCodec videoCodec = self.sessionConfiguration.preferredVideoCodec;

        DDLogVerbose(@"Using max video bandwidth: %lu, audio: %lu", (unsigned long)maxVideoRate, (unsigned long)maxAudioRate);

        RTCSessionDescription *conditionedSDP = [PHSessionDescriptionFactory conditionedSessionDescription:sdp
                                                                                                audioCodec:audioCodec
                                                                                                videoCodec:videoCodec
                                                                                              videoBitRate:maxVideoRate
                                                                                              audioBitRate:maxAudioRate];

        [peerConnection setLocalDescriptionWithDelegate:self sessionDescription:conditionedSDP];
    });
}

- (void)peerConnection:(RTCPeerConnection *)peerConnection didSetSessionDescriptionWithError:(NSError *)error
{
    if (error) {
        DDLogError(@"Peer connection did set SDP with error: %@", error);
        return;
    }

    // Send an Offer/Answer, Create an offer, or drain ICE candidates.

    dispatch_async(dispatch_get_main_queue(), ^{

        DDLogVerbose(@"Peer connection did set session description: %@", peerConnection);

        // Check gathering state.

        PHPeerConnection *connectionWrapper = [self wrapperForConnection:peerConnection];

        if (!connectionWrapper) {
            return;
        }

        if (peerConnection.iceGatheringState != RTCICEGatheringNew) {
            [connectionWrapper drainRemoteCandidates];
        }

        // Check signaling state.

        if (peerConnection.signalingState == RTCSignalingHaveLocalOffer) {
            RTCSessionDescription *conditionedOffer = peerConnection.localDescription;
            [self.delegate signalOffer:conditionedOffer forConnection:connectionWrapper];
        }
        else if (peerConnection.signalingState == RTCSignalingHaveRemoteOffer) {
            RTCMediaConstraints *constraints = [PHSessionDescriptionFactory offerConstraints];
            [peerConnection createAnswerWithDelegate:self constraints:constraints];
        }
        else if (peerConnection.signalingState == RTCSignalingStable) {
            if (connectionWrapper.role == PHPeerConnectionRoleReceiver) {
                RTCSessionDescription *conditionedAnswer = peerConnection.localDescription;
                [self.delegate signalAnswer:conditionedAnswer forConnection:connectionWrapper];
            }
        }
    });
}

#pragma mark - RTCStatsDelegate

- (void)peerConnection:(RTCPeerConnection *)peerConnection didGetStats:(NSArray *)stats
{
    DDLogVerbose(@"Connection stats were:");

    for (RTCStatsReport *report in stats) {
        DDLogVerbose(@"%@ %@", report.type, report.values);
    }
}

#pragma mark - RTCMediaStreamTrackDelegate

- (void)mediaStreamTrackDidChange:(RTCMediaStreamTrack *)mediaStreamTrack
{
    DDLogVerbose(@"Media stream track did change: %@", mediaStreamTrack);
}

@end
