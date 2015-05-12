//
//  XSPeer.h
//  PerchRTC
//
//  Created by Christopher Eagleston on 2014-08-10.
//  Copyright (c) 2014 Perch Communications. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface XSPeer : NSObject

@property (nonatomic, copy) NSString *identifier;
@property (nonatomic, copy) NSString *connectionId;

- (id)initWithId:(NSString *)userId;

- (id)initWithJSON:(NSDictionary *)json;

@end
