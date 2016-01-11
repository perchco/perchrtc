//
//  PHCredentials.h
//  PerchRTC
//
//  Created by Sam Symons on 2015-05-08.
//  Copyright (c) 2015 Perch Communications. All rights reserved.
//

#ifndef PerchRTC_PHCredentials_h
#define PerchRTC_PHCredentials_h

#error Please enter your XirSys credentials (http://xirsys.com/pricing/)

static NSString *kPHConnectionManagerDomain = @"";
static NSString *kPHConnectionManagerApplication = @"default";
static NSString *kPHConnectionManagerXSUsername = @"";
static NSString *kPHConnectionManagerXSSecretKey = @"";

#ifdef DEBUG
static NSString *kPHConnectionManagerDefaultRoomName = @"default";
#else
static NSString *kPHConnectionManagerDefaultRoomName = @"default";
#endif

#endif
