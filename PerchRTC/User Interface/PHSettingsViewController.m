//
//  PHSettingsViewController.m
//  PerchRTC
//
//  Created by Christopher Eagleston on 2015-05-07.
//  Copyright (c) 2015 Perch Communications. All rights reserved.
//

#import "PHSettingsViewController.h"

#import "PHMediaConfiguration.h"

#import "UIFont+Fonts.h"

#define PHSlateTwo [UIColor colorWithRed:(41./255.) green:(45./255.) blue:(48./255.) alpha:1.0]
#define PHVeryLightGray [UIColor colorWithRed:0.73f green:0.76f blue:0.78f alpha:1.0f]

typedef NS_ENUM(NSUInteger, PHSettingsSection)
{
    PHSettingsSectionRenderers = 0,
    PHSettingsSectionAudioCodec,
    PHSettingsSectionIceFilter,
    PHSettingsSectionIceProtocol,
    PHSettingsSectionNumberOfSections
};

@interface PHSettingsViewController ()

@end

@implementation PHSettingsViewController

- (void)viewDidLoad
{
    [super viewDidLoad];

    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"CellIdentifier"];
    [self.tableView registerClass:[UITableViewHeaderFooterView class] forHeaderFooterViewReuseIdentifier:@"HeaderIdentifier"];

    self.title = @"Settings";

    // Set up the footer:

    UILabel *versionLabel = [[UILabel alloc] init];
    versionLabel.textColor = PHVeryLightGray;
    versionLabel.font = [UIFont perchFontOfSize:13.0];
    versionLabel.text = [[self class] versionString];
    versionLabel.textAlignment = NSTextAlignmentCenter;

    [versionLabel sizeToFit];

    self.tableView.tableFooterView = versionLabel;
}

+ (NSString *)versionString
{
    NSBundle *bundle = [NSBundle mainBundle];

    NSString *appName = @"PerchRTC";
    NSString *appVersion = [[bundle infoDictionary] objectForKey:@"CFBundleShortVersionString"];
    NSString *buildNumber = [bundle objectForInfoDictionaryKey:(NSString *)kCFBundleVersionKey];

#ifdef DEBUG
    return [NSString stringWithFormat:@"%@ %@ - Build %@", appName, appVersion, buildNumber];
#else
    return [NSString stringWithFormat:@"%@ %@", appName, appVersion];
#endif
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return PHSettingsSectionNumberOfSections;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    NSUInteger numRows;

    switch (section) {
        case PHSettingsSectionRenderers:
            numRows = 3;
            break;
        case PHSettingsSectionAudioCodec:
            numRows = 2;
            break;
        case PHSettingsSectionIceFilter:
            numRows = 4;
            break;
        case PHSettingsSectionIceProtocol:
            numRows = 3;
            break;
        default:
            numRows = 0;
            break;
    }

    return numRows;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section
{
    UITableViewHeaderFooterView *headerView = [tableView dequeueReusableHeaderFooterViewWithIdentifier:@"HeaderIdentifier"];

    NSString *title;

    switch (section) {
        case PHSettingsSectionRenderers:
            title = @"Renderer";
            break;
        case PHSettingsSectionAudioCodec:
            title = @"Audio Codec";
            break;
        case PHSettingsSectionIceFilter:
            title = @"ICE Filter";
            break;
        case PHSettingsSectionIceProtocol:
            title = @"ICE Protocol";
            break;
        default:
            title = @"";
            break;
    }

    headerView.textLabel.text = title;

    return headerView;
}

- (CGFloat) tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section
{
    return 32.0f;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"CellIdentifier" forIndexPath:indexPath];
    cell.backgroundColor = [UIColor colorWithRed:0.98f green:0.98f blue:0.98f alpha:1.0f];

    cell.textLabel.font = [UIFont perchFontOfSize:16.0];
    cell.textLabel.textColor = PHSlateTwo;

    // Configure the cell...

    [self configureCell:cell forRowAtIndexPath:indexPath];
    
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    // Update model...

    [self applySettingSelectionForIndexPath:indexPath];

    // Reload the section.

    [tableView reloadSections:[NSIndexSet indexSetWithIndex:indexPath.section] withRowAnimation:UITableViewRowAnimationNone];

    [tableView selectRowAtIndexPath:indexPath animated:NO scrollPosition:UITableViewScrollPositionNone];
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}

- (void)applySettingSelectionForIndexPath:(NSIndexPath *)indexPath
{
    PHSettingsSection section = indexPath.section;
    NSUInteger row = indexPath.row;

    switch (section) {
        case PHSettingsSectionRenderers:
            self.settings.rendererType = row;
            break;
        case PHSettingsSectionAudioCodec:
            self.settings.preferredAudioCodec = row;
            break;
        case PHSettingsSectionIceFilter:

            if (row == 3) {
                self.settings.iceFilter = PHIceFilterAny;
            }
            else {
                self.settings.iceFilter = 1UL << row;
            }
            break;
        case PHSettingsSectionIceProtocol:

            if (row == 2) {
                self.settings.iceProtocol = PHIceProtocolAny;
            }
            else {
                self.settings.iceProtocol = 1UL << row;
            }
            break;
        default:
            break;
    }
}

- (void)configureCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath
{
    NSUInteger row = indexPath.row;
    PHSettingsSection section = indexPath.section;
    NSArray *sectionTitles = nil;
    BOOL selected = NO;
    PHRendererType renderer = self.settings.rendererType;
    PHAudioCodec codec = self.settings.preferredAudioCodec;
    PHIceProtocol protocol = self.settings.iceProtocol;
    PHIceFilter filter = self.settings.iceFilter;

    switch (section) {
        case PHSettingsSectionRenderers:
            sectionTitles = @[@"Sample Buffer", @"OpenGL ES", @"Quartz"];
            selected = row == renderer;
            break;
        case PHSettingsSectionAudioCodec:
            sectionTitles = @[@"Opus", @"ISAC"];
            selected = row == codec;
            break;
        case PHSettingsSectionIceFilter:

            sectionTitles = @[@"Local", @"STUN", @"TURN", @"Any"];

            if (row == 3 && (filter == PHIceFilterAny)) {
                selected = YES;
            }
            else if (row == 0 && (filter == PHIceFilterLocal)) {
                selected = YES;
            }
            else if (row == 1 && (filter == PHIceFilterStun)) {
                selected = YES;
            }
            else if (row == 2 && (filter == PHIceFilterTurn)) {
                selected = YES;
            }

            break;
        case PHSettingsSectionIceProtocol:

            sectionTitles = @[@"UDP", @"TCP", @"Any"];

            if (row == 2 && (protocol == PHIceProtocolAny)) {
                selected = YES;
            }
            else if (row == 0 && (protocol == PHIceProtocolUDP)) {
                selected = YES;
            }
            else if (row == 1 && (protocol == PHIceProtocolTCP)) {
                selected = YES;
            }
            break;
        default:
            sectionTitles = @[];
            break;
    }

    cell.textLabel.text = sectionTitles[indexPath.row];
    cell.accessoryType = selected ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
}

@end
