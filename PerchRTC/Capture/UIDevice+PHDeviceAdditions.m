//
//  UIDevice+PHDeviceAdditions.m
//  PerchRTC
//
//  Created by Christopher Eagleston on 2014-12-18.
//  Copyright (c) 2014 Perch Communications. All rights reserved.
//

#import "UIDevice+PHDeviceAdditions.h"

#import <sys/utsname.h>

NSString *PHDeviceName() {
    struct utsname systemInfo;
    uname(&systemInfo);

    return [NSString stringWithCString:systemInfo.machine encoding:NSUTF8StringEncoding];
}

@implementation UIDevice (PHDeviceAdditions)

- (BOOL)isLowPerformance
{
    NSString *deviceName = PHDeviceName();
    BOOL isLowPerformance = [[self lowPerformanceDevices] containsObject:deviceName];

    return isLowPerformance;
}

- (NSArray *)lowPerformanceDevices
{
    return @[ @"iPod1,1", @"iPod2,1", @"iPod3,1", @"iPod4,1", @"iPod5,1",
              @"iPhone1,1", @"iPhone1,2", @"iPhone2,1", @"iPhone3,1", @"iPhone4,1",
              @"iPad1,1", @"iPad2,1", @"iPad2,4", @"iPad2,5", @"iPad2,6", @"iPad2,7" ];
}

- (BOOL)isMediumPerformance
{
    NSString *deviceName = PHDeviceName();
    BOOL isMediumPerformance = [[self mediumPerformanceDevices] containsObject:deviceName];

    return isMediumPerformance;
}

- (NSArray *)mediumPerformanceDevices
{
    return @[@"iPad3,1", @"iPad3,4", @"iPhone5,1", @"iPhone5,2"];
}

- (BOOL)supportsOS8
{
    return [[self systemVersion] compare:@"8.0" options:NSNumericSearch] != NSOrderedAscending;
}

- (BOOL)isPad
{
    return self.userInterfaceIdiom == UIUserInterfaceIdiomPad;
}

- (BOOL)isLargePhone
{
    BOOL isLarge = NO;

    if (self.userInterfaceIdiom == UIUserInterfaceIdiomPhone) {
        CGRect screenBounds = [UIScreen mainScreen].bounds;
        isLarge = CGRectGetWidth(screenBounds) > 480.0 || CGRectGetHeight(screenBounds) > 480.0;
    }

    return isLarge;
}

@end
