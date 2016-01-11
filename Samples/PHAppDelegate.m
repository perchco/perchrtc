//
//  PHAppDelegate.m
//  PerchRTC
//
//  Created by Christopher Eagleston on 2014-08-09.
//  Copyright (c) 2014 Perch Communications. All rights reserved.
//

#import "PHAppDelegate.h"

#import "PHViewController.h"

#import "UIFont+Fonts.h"

#import <CocoaLumberjack/DDASLLogger.h>
#import <CocoaLumberjack/DDTTYLogger.h>

#define PHBlue [UIColor colorWithRed:0.173 green:0.667 blue:0.812 alpha:1.0]

@implementation PHAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    [DDLog addLogger:[DDASLLogger sharedInstance]];
    [DDLog addLogger:[DDTTYLogger sharedInstance]];

    [self configureAppearance];

    PHViewController *vc = [[PHViewController alloc] init];
    UINavigationController *navC = [[UINavigationController alloc] initWithRootViewController:vc];
    navC.navigationBar.tintColor = PHBlue;

    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    self.window.backgroundColor = [UIColor whiteColor];
    self.window.rootViewController = navC;
    [self.window makeKeyAndVisible];

    return YES;
}

- (void)applicationWillResignActive:(UIApplication *)application
{
    // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
    // Use this method to pause ongoing tasks, disable timers, and throttle down OpenGL ES frame rates. Games should use this method to pause the game.
}

- (void)applicationDidEnterBackground:(UIApplication *)application
{
    // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later. 
    // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
}

- (void)applicationWillEnterForeground:(UIApplication *)application
{
    // Called as part of the transition from the background to the inactive state; here you can undo many of the changes made on entering the background.
}

- (void)applicationDidBecomeActive:(UIApplication *)application
{
    // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
}

- (void)applicationWillTerminate:(UIApplication *)application
{
    // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
}

- (void)configureAppearance
{
    UIFont *titleFont = [UIFont perchFontOfSize:20];
    NSDictionary *barItemAttributes = @{NSFontAttributeName: [UIFont perchFontOfSize:18.0]};
    NSDictionary *titleTextAttributes = @{ NSForegroundColorAttributeName : PHBlue,
                                           NSFontAttributeName : titleFont};

    [[UIBarButtonItem appearanceWhenContainedIn:[UINavigationBar class], nil] setTitleTextAttributes:barItemAttributes forState:UIControlStateNormal];

    UIImage *backChevron = [[UIImage imageNamed:@"back-chevron"] imageWithAlignmentRectInsets:UIEdgeInsetsMake(0, 0, -2.5, 0)];
    UIImage *backChevronMask = [[UIImage imageNamed:@"back-chevron-mask"] imageWithAlignmentRectInsets:UIEdgeInsetsMake(0, 0, -2.5, 0)];

    [[UINavigationBar appearance] setBackIndicatorImage:backChevron];
    [[UINavigationBar appearance] setBackIndicatorTransitionMaskImage:backChevronMask];
    [[UINavigationBar appearance] setTitleTextAttributes:titleTextAttributes];

    [[UIBarButtonItem appearance] setBackButtonTitlePositionAdjustment:UIOffsetMake(-4, 0) forBarMetrics:UIBarMetricsDefault];
}

@end
