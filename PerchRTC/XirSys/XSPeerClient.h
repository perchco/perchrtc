//
//  XSPeerClient.h
//  PerchRTC
//
//  Created by Christopher Eagleston on 2014-09-27.
//  Copyright (c) 2014 Perch Communications. All rights reserved.
//

#import <Foundation/Foundation.h>

@class XSPeer;
@class XSMessage;
@class XSPeerClient;
@class XSRoom;

@protocol XSPeerClientDelegate <NSObject>

- (void)clientDidConnect:(XSPeerClient *)client;
- (void)clientDidDisconnect:(XSPeerClient *)client;

- (void)client:(XSPeerClient *)client didEncounterError:(NSError *)error;

@end

typedef NS_ENUM(NSUInteger, XSPeerConnectionState)
{
    XSPeerConnectionStateConnecting = 0,
    XSPeerConnectionStateConnected = 1,
    XSPeerConnectionStateDisconnecting = 2,
    XSPeerConnectionStateDisconnected = 3
};

/**
 *  XSPeerClient uses a XirSys signaling server to discover and communicate with other Peers.
 *  The client maintains a WebSocket connection, and can join & leave rooms.
 *  Once connected to a room, presence and message notifications flow to registered XSRoomObservers.
 *  Messages can be sent to peers via the client (may move to XSRoom. TBD.).
 */
@interface XSPeerClient : NSObject

@property (nonatomic, strong, readonly) XSRoom *room;

@property (nonatomic, assign, readonly) XSPeerConnectionState connectionState;

@property (nonatomic, weak) id<XSPeerClientDelegate> delegate;

/**
 *  Returns the a dictionary of connected XSPeers, keyed by identifier.
 *  @note: Does not include the local peer.
 */
@property (nonatomic, strong, readonly) NSDictionary *roomPeers;

- (instancetype)initWithRoom:(XSRoom *)room andDelegate:(id<XSPeerClientDelegate>)delegate;

- (void)connect;

/**
 *  Connects to a room on the signaling server.
 *
 *  @param room Room to connect with.
 */
- (void)connectToRoom:(XSRoom *)room;

/**
 *  Disconnects from the server.
 */
- (void)disconnect;

/**
 *  Sends a message to the room.
 *
 *  @param message The message to send.
 *  @note Messages are addressed to particular users via the targetId property.
 */
- (void)sendMessage:(XSMessage *)message;

@end
