//
//  XSPeer.m
//  PerchRTC
//
//  Created by Christopher Eagleston on 2014-08-10.
//  Copyright (c) 2014 Perch Communications. All rights reserved.
//

#import "XSPeer.h"

@implementation XSPeer

- (id)initWithId:(NSString *)userId
{
    return [self initWithJSON:@{@"id": userId}];
}

- (id)initWithJSON:(NSDictionary *)json
{
    self = [super init];

    if (self) {
        _identifier = json[@"id"];
    }

    return self;
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"<%@: %@>", NSStringFromClass([self class]), self.identifier];
}

@end
