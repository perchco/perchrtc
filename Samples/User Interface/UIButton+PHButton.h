//
//  UIButton+PHButton.h
//  PerchRTC
//
//  Created by Christopher Eagleston on 1/17/2014.
//  Copyright (c) 2014 Perch Communications Inc. All rights reserved.
//

typedef NS_ENUM(NSUInteger, PHRoundedButtonStyle) {
    PHRoundedButtonStyleLight,
    PHRoundedButtonStyleDark
};

@interface UIButton (PHButton)

+ (UIButton *)buttonWithImageNamed:(NSString *)imageName;
+ (UIButton *)buttonWithImageNamed:(NSString *)imageName target:(id)target action:(SEL)action;
+ (UIButton *)buttonWithImage:(UIImage *)image target:(id)target action:(SEL)action;
+ (UIButton *)buttonWithImage:(UIImage *)image renderingMode:(UIImageRenderingMode)renderingMode target:(id)target action:(SEL)action;

+ (UIButton *)roundedButtonWithStyle:(PHRoundedButtonStyle)style;

- (void)applyStyle:(PHRoundedButtonStyle)style;

@end
