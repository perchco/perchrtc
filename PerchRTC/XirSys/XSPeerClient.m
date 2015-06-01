//
//  XSPeerClient.m
//  PerchRTC
//
//  Created by Christopher Eagleston on 2014-09-27.
//  Copyright (c) 2014 Perch Communications. All rights reserved.
//

#import "XSPeerClient.h"

#import "XSMessage.h"
#import "XSPeer.h"
#import "XSRoom.h"

#import <SocketRocket/SRWebSocket.h>

static NSString *kPHConnectionManagerXSWebSocketAddress = @"wss://api.xirsys.com:443";

/**
 *  XirSys requires a keepalive for presence. The timing constant is taken from their Rails Demo.
 */
static NSTimeInterval kXSPeerClientKeepaliveInterval = 20.0;

@interface XSPeerClient() <SRWebSocketDelegate>

@property (nonatomic, strong) dispatch_queue_t processingQueue;
@property (nonatomic, strong) SRWebSocket *negotiationSocket;
@property (nonatomic, strong) NSTimer *presenceKeepAliveTimer;
@property (nonatomic, strong) XSRoom *room;
@property (nonatomic, assign) XSPeerConnectionState connectionState;

@end

@implementation XSPeerClient

#pragma mark - Initialize & Dealloc

- (instancetype)initWithRoom:(XSRoom *)room andDelegate:(id<XSPeerClientDelegate>)delegate
{
    self = [super init];

    if (self) {
        _delegate = delegate;
        _room = room;
        _processingQueue = dispatch_get_main_queue();
        _connectionState = XSPeerConnectionStateDisconnected;

        // TODO: Background processing.
//        _processingQueue = dispatch_queue_create("com.xirsys.websocket.processing", DISPATCH_QUEUE_SERIAL);
    }

    return self;
}

- (void)dealloc
{
    [self cleanupConnection];
}

#pragma mark - NSObject

+ (BOOL)automaticallyNotifiesObserversForKey:(NSString *)key
{
    if ([key isEqualToString:@"connectionState"]) {
        return NO;
    }

    return [super automaticallyNotifiesObserversForKey:key];
}

#pragma mark - Properties

- (NSDictionary *)roomPeers
{
    return self.room.peers;
}

- (void)setConnectionState:(XSPeerConnectionState)connectionState
{
    if (_connectionState != connectionState) {
        [self willChangeValueForKey:@"connectionState"];
        _connectionState = connectionState;
        [self didChangeValueForKey:@"connectionState"];
    }
}

#pragma mark - Public

- (void)connect
{
    [self connectToRoom:self.room];
}

- (void)connectToRoom:(XSRoom *)room
{
    NSParameterAssert(room);

    if (self.room && self.room != room) {
        DDLogError(@"We are already connected to a room.");
        return;
    }

    NSURL *url = [NSURL URLWithString:kPHConnectionManagerXSWebSocketAddress];

    DDLogInfo(@"Opening socket to: %@ with room: %@", url, room);

    NSString *token = room.authToken;
    NSString *escapedToken = [token stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
    NSURL *authorizedURL = [url URLByAppendingPathComponent:[NSString stringWithFormat:@"ws/%@", escapedToken]];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:authorizedURL];

    SRWebSocket *socket = [[SRWebSocket alloc] initWithURLRequest:request];
    [socket setDelegateDispatchQueue:self.processingQueue];
    socket.delegate = self;

    self.negotiationSocket = socket;
    self.room = room;

    [socket open];

    self.connectionState = (XSPeerConnectionState)socket.readyState;

    [self addNotificationObservers];
}

- (void)disconnect
{
    [self removeNotificationObservers];

    if (self.connectionState != XSPeerConnectionStateDisconnected) {
        [self.negotiationSocket close];
        self.connectionState = XSPeerConnectionStateDisconnecting;
    }
    else {
        [self cleanupConnection];
    }
}

- (void)sendMessage:(XSMessage *)message
{
    NSParameterAssert(message);

    message.room = self.room.name;
    message.senderId = self.room.localPeer.identifier;

    NSDictionary *messageDictionary = [message toDictionary];
    NSError *jsonError = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:messageDictionary
                                                   options:0
                                                     error:&jsonError];

    if (!jsonError) {
        DDLogVerbose(@"Send message: %@", message);

        // XirSys expects text frames only for peer messages.

        NSString *jsonString = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];

        if (self.connectionState == XSPeerConnectionStateConnected) {
            [self.negotiationSocket send:jsonString];
        }
        else {
            DDLogWarn(@"Socket is not ready to send a message!");
        }
    }
}

#pragma mark - Private

- (void)scheduleTimer
{
    [self invalidateTimer];

    NSTimer *timer = [NSTimer timerWithTimeInterval:kXSPeerClientKeepaliveInterval target:self selector:@selector(handleTimer:) userInfo:nil repeats:NO];

    [[NSRunLoop mainRunLoop] addTimer:timer forMode:NSRunLoopCommonModes];

    self.presenceKeepAliveTimer = timer;
}

- (void)invalidateTimer
{
    [self.presenceKeepAliveTimer invalidate];
    self.presenceKeepAliveTimer = nil;
}

- (void)handleTimer:(NSTimer *)timer
{
    [self sendPing];

    [self scheduleTimer];
}

- (void)sendPing
{
    [self.negotiationSocket sendPing:nil];
}

- (void)applicationWillEnterForeground
{
    // TODO: @chris Reopen the socket here?
}

- (void)applicationDidEnterBackground
{
    // TODO: @chris Cleanup socket resources here?
}

- (void)cleanupConnection
{
    [self.room clearAuthorizationToken];

    self.negotiationSocket.delegate = nil;
    self.negotiationSocket = nil;
    self.connectionState = XSPeerConnectionStateDisconnected;

    [self invalidateTimer];
}

- (void)addNotificationObservers
{
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];

    [center addObserver:self selector:@selector(applicationWillEnterForeground) name:UIApplicationWillEnterForegroundNotification object:nil];
    [center addObserver:self selector:@selector(applicationDidEnterBackground) name:UIApplicationDidEnterBackgroundNotification object:nil];
}

- (void)removeNotificationObservers
{
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];

    [center removeObserver:self name:UIApplicationWillEnterForegroundNotification object:nil];
    [center removeObserver:self name:UIApplicationDidEnterBackgroundNotification object:nil];
}

#pragma mark - SRWebSocketDelegate

- (void)webSocketDidOpen:(SRWebSocket *)webSocket
{
    self.connectionState = XSPeerConnectionStateConnected;

    [self.delegate clientDidConnect:self];

    [self scheduleTimer];
}

- (void)webSocket:(SRWebSocket *)webSocket didReceiveMessage:(id)messageData
{
    XSMessage *message = nil;
    NSError *error = nil;

    if ([messageData isKindOfClass:[NSData class]]) {
        NSDictionary *messageDictionary = [NSJSONSerialization JSONObjectWithData:messageData options:0 error:&error];
        message = [[XSMessage alloc] initWithJSON:messageDictionary];
    }
    else if ([messageData isKindOfClass:[NSString class]]) {
        NSData *realData = [(NSString *)messageData dataUsingEncoding:NSUTF8StringEncoding];
        NSDictionary *messageDictionary = [NSJSONSerialization JSONObjectWithData:realData options:0 error:&error];
        message = [[XSMessage alloc] initWithJSON:messageDictionary];
    }
    else {
        DDLogWarn(@"Unknown message format: %@", messageData);
    }

    message.targetId = self.room.localPeer.identifier;

    DDLogVerbose(@"WebSocket: did receive message: %@", message);

    [self.room processMessage:message];
}

- (void)webSocket:(SRWebSocket *)webSocket didFailWithError:(NSError *)error
{
    [self cleanupConnection];

    [self.delegate client:self didEncounterError:error];

    [self.delegate clientDidDisconnect:self];
}

- (void)webSocket:(SRWebSocket *)webSocket didCloseWithCode:(NSInteger)code reason:(NSString *)reason wasClean:(BOOL)wasClean
{
    [self cleanupConnection];

    [self.delegate clientDidDisconnect:self];
}

@end
