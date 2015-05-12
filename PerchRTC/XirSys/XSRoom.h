//
//  XSRoom.h
//  PerchRTC
//
//  Created by Christopher Eagleston on 2014-09-28.
//  Copyright (c) 2014 Perch Communications. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "XSMessage.h"

@class XSPeer;
@class XSRoom;

@protocol XSRoomObserver <NSObject>

- (void)didJoinRoom:(XSRoom *)room;
- (void)didLeaveRoom:(XSRoom *)room;

- (void)room:(XSRoom *)room didAddPeer:(XSPeer *)peer;
- (void)room:(XSRoom *)room didRemovePeer:(XSPeer *)peer;

- (void)room:(XSRoom *)room didReceiveMessage:(XSMessage *)message;

@end


@interface XSRoom : NSObject <XSMessageProcessor>

- (instancetype)initWithAuthToken:(NSString *)token username:(NSString *)username andRoomName:(NSString *)name;

@property (nonatomic, copy, readonly) NSString *name;

/**
 *  Auth token which identifies the local peer, and allows it access to the room.
 */
@property (nonatomic, copy, readonly) NSString *authToken;

/**
 *  The local peer.
 */
@property (nonatomic, copy, readonly) XSPeer *localPeer;

@property (nonatomic, assign, readonly, getter = isJoined) BOOL joined;

/**
 *  Returns a dictionary of connected XSPeers, keyed by identifier.
 *  @note: Does not include the local peer.
 */
@property (nonatomic, strong, readonly) NSDictionary *peers;

- (void)addRoomObserver:(id<XSRoomObserver>)observer;

- (void)removeRoomObserver:(id<XSRoomObserver>)observer;

- (void)authorizeWithToken:(NSString *)authToken;

- (void)clearAuthorizationToken;

@end
