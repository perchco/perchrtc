//
//  UIFont+Fonts.m
//  PerchRTC
//
//  Created by Sam Symons on 2/14/2014.
//  Copyright (c) 2014 Perch Communications Inc. All rights reserved.
//

#import "UIFont+Fonts.h"

@implementation UIFont (Fonts)

+ (UIFont *)perchFontOfSize:(CGFloat)size
{
    return [UIFont fontWithName:@"Avenir" size:size];
}

+ (UIFont *)boldPerchFontOfSize:(CGFloat)size
{
    return [UIFont fontWithName:@"Avenir-Bold" size:size];
}

@end
