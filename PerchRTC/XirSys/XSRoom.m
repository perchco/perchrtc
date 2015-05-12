//
//  XSRoom.m
//  PerchRTC
//
//  Created by Christopher Eagleston on 2014-09-28.
//  Copyright (c) 2014 Perch Communications. All rights reserved.
//

#import "XSRoom.h"

#import "XSPeer.h"

@interface XSRoom()

@property (nonatomic, strong) NSMutableSet *mutableRoomObservers;
@property (nonatomic, strong) NSMutableDictionary *mutableRoomPeers;
@property (nonatomic, assign, getter = isJoined) BOOL joined;
@property (nonatomic, copy) NSString *authToken;

@end

@implementation XSRoom

- (instancetype)initWithAuthToken:(NSString *)token username:(NSString *)username andRoomName:(NSString *)name
{
    self = [super init];
    if (self) {
        _mutableRoomObservers = [NSMutableSet set];
        _mutableRoomPeers = [NSMutableDictionary dictionary];
        _localPeer = [[XSPeer alloc] initWithId:username];
        _authToken = token;
        _name = name;
        _joined = NO;
    }
    return self;
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"<%@: name: %@ peers: %@>", NSStringFromClass([self class]), self.name, [self.mutableRoomPeers allValues]];
}

- (void)cleanup
{
    [self clearAuthorizationToken];
    self.mutableRoomPeers = nil;
}

#pragma mark - Properties

- (NSDictionary *)peers
{
    NSMutableDictionary *mutablePeersCopy = [self.mutableRoomPeers mutableCopy];
    [mutablePeersCopy removeObjectForKey:self.localPeer.identifier];

    return [mutablePeersCopy copy];
}

#pragma mark - Public

- (void)addRoomObserver:(id<XSRoomObserver>)observer
{
    NSParameterAssert(observer);

    NSValue *observerValue = [NSValue valueWithNonretainedObject:observer];
    [self.mutableRoomObservers addObject:observerValue];
}

- (void)removeRoomObserver:(id<XSRoomObserver>)observer
{
    NSParameterAssert(observer);

    NSValue *observerValue = [NSValue valueWithNonretainedObject:observer];
    [self.mutableRoomObservers removeObject:observerValue];
}

- (void)authorizeWithToken:(NSString *)authToken
{
    NSParameterAssert(authToken);

    self.authToken = authToken;
}

- (void)clearAuthorizationToken
{
    self.authToken = nil;
    self.joined = NO;
    [self.mutableRoomPeers removeAllObjects];
}

#pragma mark - Private

- (BOOL)broadcastMessage:(XSMessage *)message
{
    NSParameterAssert(message);

    NSSet *observers = [self.mutableRoomObservers copy];

    for (NSValue *observerValue in observers) {
        id<XSRoomObserver> observer = [observerValue nonretainedObjectValue];
        [observer room:self didReceiveMessage:message];
    }

    return [observers count] > 0;
}

- (void)informObserverPeerAdded:(XSPeer *)peer
{
    NSParameterAssert(peer);
    NSSet *observers = [self.mutableRoomObservers copy];

    for (NSValue *observerValue in observers) {
        id<XSRoomObserver> observer = [observerValue nonretainedObjectValue];
        [observer room:self didAddPeer:peer];
    }
}

- (void)informObserverPeerLost:(XSPeer *)peer
{
    NSParameterAssert(peer);
    NSSet *observers = [self.mutableRoomObservers copy];

    for (NSValue *observerValue in observers) {
        id<XSRoomObserver> observer = [observerValue nonretainedObjectValue];
        [observer room:self didRemovePeer:peer];
    }
}

- (void)informObserverJoined
{
    NSSet *observers = [self.mutableRoomObservers copy];

    for (NSValue *observerValue in observers) {
        id<XSRoomObserver> observer = [observerValue nonretainedObjectValue];
        [observer didJoinRoom:self];
    }
}

- (BOOL)handleServerMessage:(XSMessage *)message
{
    BOOL handled = YES;

    NSString *type = message.type;

    if ([type isEqualToString:kXSMessageRoomJoin]) {
        NSString *userId = message.senderId;
        if ([userId isKindOfClass:[NSString class]]) {
            XSPeer *peer = [[XSPeer alloc] initWithId:(NSString *)userId];
            self.mutableRoomPeers[peer.identifier] = peer;
            [self informObserverPeerAdded:peer];
        }
    }
    else if ([type isEqualToString:kXSMessageRoomLeave]) {
        NSString *userId = message.senderId;
        if ([userId isKindOfClass:[NSString class]]) {
            XSPeer *peerToRemove = self.mutableRoomPeers[userId];

            if (peerToRemove) {
                [self.mutableRoomPeers removeObjectForKey:userId];
                [self informObserverPeerLost:peerToRemove];
            }
            else {
                DDLogWarn(@"No peer to remove for message: %@", message);
            }
        }
    }
    else if ([type isEqualToString:kXSMessageRoomUsersUpdate]) {
        NSArray *users = message.data[kXSMessageRoomUsersUpdateDataKey];

        // Create XSPeers
        for (NSDictionary *peerDictionary in users) {

            if ([peerDictionary isKindOfClass:[NSDictionary class]]) {
                XSPeer *peer = [[XSPeer alloc] initWithJSON:peerDictionary];
                self.mutableRoomPeers[peer.identifier] = peer;
            }
            else if ([peerDictionary isKindOfClass:[NSString class]]) {
                XSPeer *peer = [[XSPeer alloc] initWithId:(NSString *)peerDictionary];
                self.mutableRoomPeers[peer.identifier] = peer;
            }
        }

        self.joined = YES;

        [self informObserverJoined];
    }
    else {
        handled = NO;
    }
    
    return handled;
}

#pragma mark - XSMessageProcessor

- (BOOL)processMessage:(XSMessage *)message
{
    BOOL processed = [self handleServerMessage:message];

    if (!processed) {
        processed = [self broadcastMessage:message];
    }

    return processed;
}

@end
