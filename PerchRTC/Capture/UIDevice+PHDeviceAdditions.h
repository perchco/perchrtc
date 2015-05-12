//
//  UIDevice+PHDeviceAdditions.h
//  PerchRTC
//
//  Created by Christopher Eagleston on 2014-12-18.
//  Copyright (c) 2014 Perch Communications. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface UIDevice (PHDeviceAdditions)

@property (nonatomic, assign, readonly, getter=isLowPerformance) BOOL lowPerformance;
@property (nonatomic, assign, readonly, getter=isMediumPerformance) BOOL mediumPerformance;

@property (nonatomic, assign, readonly) BOOL supportsOS8;
@property (nonatomic, assign, readonly) BOOL isPad;
@property (nonatomic, assign, readonly) BOOL isLargePhone;

@end