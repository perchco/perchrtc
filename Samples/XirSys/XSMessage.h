//
//  XSMessage.h
//  PerchRTC
//
//  Created by Christopher Eagleston on 2014-08-10.
//  Copyright (c) 2014 Perch Communications. All rights reserved.
//

#import <Foundation/Foundation.h>

// Content

extern NSString * const kXSMessageConnectionIdKey;

// User message event types.

extern NSString * const kXSMessageRoomJoin;
extern NSString * const kXSMessageRoomLeave;
extern NSString * const kXSMessageRoomUsersUpdate;

// Server message payloads.

extern NSString * const kXSMessageRoomUsersUpdateDataKey;

// Peer message event types.

extern NSString * const kXSMessageEventICE;
extern NSString * const kXSMessageEventOffer;
extern NSString * const kXSMessageEventAnswer;
extern NSString * const kXSMessageEventBye;

// Peer message payloads.

extern NSString * const kXSMessageOfferDataKey;
extern NSString * const kXSMessageAnswerDataKey;
extern NSString * const kXSMessageICECandidateDataKey;
extern NSString * const kXSMessageByeDataKey;


@interface XSMessage : NSObject

@property (nonatomic, copy) NSString *targetId;
@property (nonatomic, copy) NSString *senderId;
@property (nonatomic, copy) NSString *type;
@property (nonatomic, copy) NSString *room;
@property (nonatomic, copy) NSDictionary *data;

- (id)initWithJSON:(NSDictionary *)json;

- (NSDictionary *)toDictionary;

+ (XSMessage *)messageWithEventType:(NSString *)eventType userId:(NSString *)targetUserId messageData:(NSDictionary *)messageData;

+ (XSMessage *)offerWithUserId:(NSString *)targetUserId connectionId:(NSString *)connectionId andData:(NSDictionary *)offerData;

+ (XSMessage *)answerWithUserId:(NSString *)targetUserId connectionId:(NSString *)connectionId andData:(NSDictionary *)answerData;

+ (XSMessage *)iceCredentialsWithUserId:(NSString *)targetUserId connectionId:(NSString *)connectionId andData:(NSDictionary *)iceData;

+ (XSMessage *)byeWithUserId:(NSString *)targetUserId connectionId:(NSString *)connectionId andData:(NSDictionary *)byeData;

@end

@protocol XSMessageProcessor <NSObject>

- (BOOL)processMessage:(XSMessage *)message;

@end
