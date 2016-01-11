//
//  UIButton+PHButton.m
//  PerchRTC
//
//  Created by Christopher Eagleston on 1/17/2014.
//  Copyright (c) 2014 Perch Communications Inc. All rights reserved.
//

#import "UIButton+PHButton.h"

#import "UIFont+Fonts.h"

@implementation UIButton (PHButton)

+ (UIButton *)buttonWithImageNamed:(NSString *)imageName
{
    return [self buttonWithImageNamed:imageName target:nil action:NULL];
}

+ (UIButton *)buttonWithImageNamed:(NSString *)imageName target:(id)target action:(SEL)action
{
    UIImage *image = [UIImage imageNamed:imageName];
    return [self buttonWithImage:image target:target action:action];
}

+ (UIButton *)buttonWithImage:(UIImage *)image target:(id)target action:(SEL)action
{
    return [self buttonWithImage:image renderingMode:UIImageRenderingModeAlwaysOriginal target:target action:action];
}

+ (UIButton *)buttonWithImage:(UIImage *)image renderingMode:(UIImageRenderingMode)renderingMode target:(id)target action:(SEL)action
{
    UIImage *updatedImage = [image imageWithRenderingMode:renderingMode];
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    button.frame = CGRectMake(0, 0, image.size.width, image.size.height);

    [button setImage:updatedImage forState:UIControlStateNormal];
    [button addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];

    return button;
}

+ (UIButton *)roundedButtonWithStyle:(PHRoundedButtonStyle)style
{
    UIButton *button = [[UIButton alloc] init];

    [button applyStyle:style];

    return button;
}

- (void)applyStyle:(PHRoundedButtonStyle)style
{
    UIButton *button = self;

    button.titleLabel.font = [UIFont perchFontOfSize:16.0];
    button.contentEdgeInsets = UIEdgeInsetsMake(0.0, 15.0, 0.0, 15.0);
    button.adjustsImageWhenDisabled = NO;

    UIEdgeInsets insets = UIEdgeInsetsMake(6.0, 6.0, 6.0, 6.0);
    UIImage *defaultImage = nil;
    UIImage *highlighted = nil;

    switch (style) {
        case PHRoundedButtonStyleLight:
            button.titleLabel.textColor = [UIColor colorWithRed:0.44 green:0.46 blue:0.48 alpha:1.0];
            [button setTitleColor:[UIColor colorWithRed:0.44 green:0.46 blue:0.48 alpha:1.0] forState:UIControlStateNormal];

            defaultImage = [[UIImage imageNamed:@"rounded-button-light-default"] resizableImageWithCapInsets:insets];
            highlighted = [[UIImage imageNamed:@"rounded-button-light-highlighted"] resizableImageWithCapInsets:insets];

            break;
        case PHRoundedButtonStyleDark:
            button.titleLabel.textColor = [UIColor colorWithRed:0.73 green:0.76 blue:0.78 alpha:1.0];
            [button setTitleColor:[UIColor colorWithRed:0.73 green:0.76 blue:0.78 alpha:1.0] forState:UIControlStateNormal];

            defaultImage = [[UIImage imageNamed:@"rounded-button-default"] resizableImageWithCapInsets:insets];
            highlighted = [[UIImage imageNamed:@"rounded-button-highlighted"] resizableImageWithCapInsets:insets];

            break;
    }

    [button setTitleColor:[UIColor colorWithRed:0.11 green:0.65 blue:0.84 alpha:1.0] forState:UIControlStateHighlighted];
    [button setBackgroundImage:defaultImage forState:UIControlStateNormal];
    [button setBackgroundImage:highlighted forState:UIControlStateHighlighted];
}

@end
