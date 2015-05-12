//
//  XSMessage.m
//  PerchRTC
//
//  Created by Christopher Eagleston on 2014-08-10.
//  Copyright (c) 2014 Perch Communications. All rights reserved.
//

#import "XSMessage.h"

// Message keys

// Types

NSString * const kXSMessageTypeKey = @"type";

// Content

NSString * const kXSMessageSenderIdKey = @"userid";
NSString * const kXSMessageTargetIdKey = @"targetUserId";
NSString * const kXSMessageDataKey = @"message";
NSString * const kXSMessagePeerDataKey = @"data";
NSString * const kXSMessageRoomKey = @"room";
NSString * const kXSMessageConnectionIdKey = @"connectionId";
NSString * const kXSMessageEventName = @"eventName";

// Server message event types

NSString * const kXSMessageRoomJoin = @"peer_connected";
NSString * const kXSMessageRoomLeave = @"peer_removed";
NSString * const kXSMessageRoomUsersUpdate = @"peers";

// Server message payloads.

NSString * const kXSMessageRoomUsersUpdateDataKey = @"users";

// Peer message event types.

NSString * const kXSMessageEventICE = @"receiveice";
NSString * const kXSMessageEventOffer = @"receiveoffer";
NSString * const kXSMessageEventAnswer = @"receiveanswer";
NSString * const kXSMessageEventBye = @"receivebye";

// Peer message payloads.

NSString * const kXSMessageOfferDataKey = @"offer";
NSString * const kXSMessageAnswerDataKey = @"answer";
NSString * const kXSMessageICECandidateDataKey = @"iceCandidate";
NSString * const kXSMessageByeDataKey = @"bye";

@implementation XSMessage

#pragma mark - Initialize & Dealloc

- (id)initWithJSON:(NSDictionary *)json
{
    self = [super init];

    if (self) {
        _data = json[kXSMessageDataKey];
        _room = json[kXSMessageRoomKey];
        _senderId = json[kXSMessageSenderIdKey];
        _targetId = json[kXSMessageTargetIdKey];

        _type = json[kXSMessageTypeKey];
        if (!_type) {
            _type = json[kXSMessageEventName];
        }
    }

    return self;
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"<%@: type: %@ senderId: %@ targetId: %@>", NSStringFromClass([self class]), self.type, self.senderId, self.targetId];
}

#pragma mark - Class

+ (XSMessage *)messageWithEventType:(NSString *)eventType userId:(NSString *)targetUserId messageData:(NSDictionary *)messageData
{
    NSDictionary *messageDictionary = @{kXSMessageEventName : eventType,
                                        kXSMessageTargetIdKey : targetUserId,
                                        kXSMessageDataKey : messageData};
    return [[XSMessage alloc] initWithJSON:messageDictionary];
}

+ (XSMessage *)offerWithUserId:(NSString *)targetUserId connectionId:(NSString *)connectionId andData:(NSDictionary *)offerData
{
    NSDictionary *messageData = @{kXSMessageConnectionIdKey : connectionId,
                                  kXSMessageOfferDataKey : offerData};

    return [XSMessage messageWithEventType:kXSMessageEventOffer userId:targetUserId messageData:messageData];
}

+ (XSMessage *)answerWithUserId:(NSString *)targetUserId connectionId:(NSString *)connectionId andData:(NSDictionary *)answerData
{
    NSDictionary *messageData = @{kXSMessageConnectionIdKey : connectionId,
                                  kXSMessageAnswerDataKey : answerData};

    return [XSMessage messageWithEventType:kXSMessageEventAnswer userId:targetUserId messageData:messageData];
}

+ (XSMessage *)iceCredentialsWithUserId:(NSString *)targetUserId connectionId:(NSString *)connectionId andData:(NSDictionary *)iceData
{
    NSDictionary *messageData = @{kXSMessageConnectionIdKey : connectionId,
                                  kXSMessageICECandidateDataKey : iceData};

    return [XSMessage messageWithEventType:kXSMessageEventICE userId:targetUserId messageData:messageData];
}

+ (XSMessage *)byeWithUserId:(NSString *)targetUserId connectionId:(NSString *)connectionId andData:(NSDictionary *)byeData
{
    NSDictionary *messageData = @{kXSMessageConnectionIdKey : connectionId,
                                  kXSMessageByeDataKey : byeData};

    return [XSMessage messageWithEventType:kXSMessageEventBye userId:targetUserId messageData:messageData];
}

#pragma mark - Public

- (NSDictionary *)toDictionary
{
    return @{ kXSMessageEventName : self.type,
              kXSMessageTargetIdKey : self.targetId,
              kXSMessagePeerDataKey : self.data };
}

@end
