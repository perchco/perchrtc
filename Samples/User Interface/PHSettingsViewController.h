//
//  PHSettingsViewController.h
//  PerchRTC
//
//  Created by Christopher Eagleston on 2015-05-07.
//  Copyright (c) 2015 Perch Communications. All rights reserved.
//

#import <UIKit/UIKit.h>

@class PHMediaConfiguration;

@interface PHSettingsViewController : UITableViewController

@property (nonatomic, strong) PHMediaConfiguration *settings;

@end
