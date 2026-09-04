/*****************************************************************************
 * MacLCInterfaceSettingsViewController.m: Interface Settings Pane for MacLC
 *****************************************************************************
 * Copyright (C) 2026 VLC authors and VideoLAN
 *
 * Authors: MacLC Settings Team
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston MA 02110-1301, USA.
 *****************************************************************************/

#import "settings/panes/MacLCInterfaceSettingsViewController.h"
#import "settings/MacLCConfigSafe.h"
#import "settings/MacLCSettingsRow.h"
#import "theme/MacLCDesign.h"
#import "theme/MacLCCardView.h"
#import "preferences/VLCSimplePrefsController.h"
#import "playqueue/VLCPlayQueueTableCellView.h"
#import "views/VLCPlaybackEndViewController.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wnullability-completeness"
#import "extensions/NSString+Helpers.h"
#pragma clang diagnostic pop

#import <vlc_configuration.h>

@interface MacLCInterfaceSettingsViewController ()
{
    intf_thread_t *_p_intf;
}

@property (nonatomic, assign) BOOL hasUnsavedChanges;

// Rows
@property (nonatomic, strong) MacLCSettingsRow *statusIconRow;
@property (nonatomic, strong) MacLCSettingsRow *mediaKeysRow;
@property (nonatomic, strong) MacLCSettingsRow *appleRemoteRow;
@property (nonatomic, strong) MacLCSettingsRow *appleRemoteSysVolRow;
@property (nonatomic, strong) MacLCSettingsRow *appleRemotePrevNextRow;

@property (nonatomic, strong) MacLCSettingsRow *controlItunesRow;

@property (nonatomic, strong) MacLCSettingsRow *trackNumberRow;
@property (nonatomic, strong) MacLCSettingsRow *endOfPlaybackRow;
@property (nonatomic, strong) MacLCSettingsRow *notificationsRow;

@property (nonatomic, strong) MacLCCardView *advancedCard;
@property (nonatomic, strong) NSButton *advancedDisclosureButton;
@property (nonatomic, strong) MacLCSettingsRow *httpRemoteRow;
@property (nonatomic, strong) MacLCSettingsRow *httpPasswordRow;

@end

@implementation MacLCInterfaceSettingsViewController

- (instancetype)initWithIntf:(intf_thread_t *)intf
{
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _p_intf = intf;
    }
    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];
    return self;
}

#pragma mark - MacLCSettingsPane Protocol Properties

- (NSString *)paneTitle
{
    return _NS("Interface");
}

- (NSString *)paneSymbolName
{
    return @"macwindow";
}

- (NSString *)paneIdentifier
{
    return @"interface";
}

- (NSArray<NSString *> *)searchKeywords
{
    return @[
        @"interface", @"status bar", @"menu icon", @"media keys", @"apple remote",
        @"remote", @"volume", @"itunes", @"music", @"spotify", @"track number",
        @"play queue", @"end of playback", @"notifications", @"banner", @"growl",
        @"http", @"web", @"password",
        @"macosx-statusicon", @"macosx-mediakeys", @"macosx-appleremote",
        @"macosx-appleremote-sysvol", @"macosx-appleremote-prevnext",
        @"macosx-control-itunes", @"http-password", @"control", @"extraintf"
    ];
}

#pragma mark - View Lifecycle & Layout

- (void)loadView
{
    NSView *container = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 600, 1000)];
    container.translatesAutoresizingMaskIntoConstraints = NO;
    self.view = container;

    NSStackView *rootStack = [[NSStackView alloc] init];
    rootStack.translatesAutoresizingMaskIntoConstraints = NO;
    rootStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    rootStack.alignment = NSLayoutAttributeLeading;
    rootStack.spacing = [MacLCDesign groupSpacing];

    [container addSubview:rootStack];

    [NSLayoutConstraint activateConstraints:@[
        [rootStack.leadingAnchor constraintEqualToAnchor:container.leadingAnchor
                                                constant:[MacLCDesign windowContentMargin]],
        [rootStack.trailingAnchor constraintEqualToAnchor:container.trailingAnchor
                                                 constant:-[MacLCDesign windowContentMargin]],
        [rootStack.topAnchor constraintEqualToAnchor:container.topAnchor
                                            constant:[MacLCDesign windowContentMargin]],
        [rootStack.bottomAnchor constraintEqualToAnchor:container.bottomAnchor
                                               constant:-[MacLCDesign windowContentMargin]],
        [container.widthAnchor constraintGreaterThanOrEqualToConstant:480]
    ]];

    __weak typeof(self) weakSelf = self;

    // Card 1: Menu Bar & Remote Controls
    MacLCCardView *remoteCard = [MacLCCardView cardViewWithTitle:_NS("Menu Bar & Remote Controls")];
    remoteCard.translatesAutoresizingMaskIntoConstraints = NO;
    [rootStack addArrangedSubview:remoteCard];
    [remoteCard.trailingAnchor constraintEqualToAnchor:rootStack.trailingAnchor].active = YES;

    _statusIconRow = [MacLCSettingsRow checkboxRowWithTitle:_NS("Show Status Bar Menu Icon")
                                                explanation:_NS("Place a playback control menu icon in the macOS status menu bar.")
                                                      state:YES
                                                     action:^(BOOL checked) {
        weakSelf.hasUnsavedChanges = YES;
    }];
    _statusIconRow.defaultHint = _NS("Default: On");
    [remoteCard.contentStackView addArrangedSubview:_statusIconRow];

    _mediaKeysRow = [MacLCSettingsRow checkboxRowWithTitle:_NS("Use Hardware Media Keys")
                                               explanation:_NS("Respond to keyboard Play/Pause, Fast Forward, and Rewind media keys.")
                                                     state:YES
                                                    action:^(BOOL checked) {
        weakSelf.hasUnsavedChanges = YES;
    }];
    _mediaKeysRow.defaultHint = _NS("Default: On");
    [remoteCard.contentStackView addArrangedSubview:_mediaKeysRow];

    _appleRemoteRow = [MacLCSettingsRow checkboxRowWithTitle:_NS("Accept Apple Remote Commands")
                                                 explanation:_NS("Allow infrared hardware Apple Remote signals to control MacLC.")
                                                       state:YES
                                                      action:^(BOOL checked) {
        weakSelf.hasUnsavedChanges = YES;
        weakSelf.appleRemoteSysVolRow.enabled = checked;
        weakSelf.appleRemotePrevNextRow.enabled = checked;
    }];
    _appleRemoteRow.defaultHint = _NS("Default: On");
    [remoteCard.contentStackView addArrangedSubview:_appleRemoteRow];

    _appleRemoteSysVolRow = [MacLCSettingsRow checkboxRowWithTitle:_NS("Apple Remote Controls System Volume")
                                                       explanation:_NS("Adjust macOS master sound volume instead of MacLC internal volume.")
                                                             state:NO
                                                            action:^(BOOL checked) {
        weakSelf.hasUnsavedChanges = YES;
    }];
    _appleRemoteSysVolRow.defaultHint = _NS("Default: Off");
    [remoteCard.contentStackView addArrangedSubview:_appleRemoteSysVolRow];

    _appleRemotePrevNextRow = [MacLCSettingsRow checkboxRowWithTitle:_NS("Apple Remote Next/Prev Track Mode")
                                                         explanation:_NS("Jump directly to adjacent playlist tracks instead of seeking.")
                                                               state:NO
                                                              action:^(BOOL checked) {
        weakSelf.hasUnsavedChanges = YES;
    }];
    _appleRemotePrevNextRow.defaultHint = _NS("Default: Off");
    [remoteCard.contentStackView addArrangedSubview:_appleRemotePrevNextRow];

    // Card 2: External Music Players
    MacLCCardView *playersCard = [MacLCCardView cardViewWithTitle:_NS("External Music Players")];
    playersCard.translatesAutoresizingMaskIntoConstraints = NO;
    [rootStack addArrangedSubview:playersCard];
    [playersCard.trailingAnchor constraintEqualToAnchor:rootStack.trailingAnchor].active = YES;

    _controlItunesRow = [MacLCSettingsRow popUpRowWithTitle:_NS("Pause Music on Playback")
                                                explanation:_NS("Pause Apple Music or Spotify automatically when MacLC begins playback.")
                                                      items:@[_NS("Do Nothing"), _NS("Pause Music / Spotify"), _NS("Pause and Resume Music / Spotify")]
                                                       tags:@[@0, @1, @2]
                                              selectedIndex:1
                                                     action:^(NSInteger selectedIndex, NSInteger tag) {
        weakSelf.hasUnsavedChanges = YES;
    }];
    _controlItunesRow.defaultHint = _NS("Default: Pause Music / Spotify");
    [playersCard.contentStackView addArrangedSubview:_controlItunesRow];

    // Card 3: Play Queue & Notifications
    MacLCCardView *queueCard = [MacLCCardView cardViewWithTitle:_NS("Play Queue & Notifications")];
    queueCard.translatesAutoresizingMaskIntoConstraints = NO;
    [rootStack addArrangedSubview:queueCard];
    [queueCard.trailingAnchor constraintEqualToAnchor:rootStack.trailingAnchor].active = YES;

    _trackNumberRow = [MacLCSettingsRow checkboxRowWithTitle:_NS("Show Track Numbers in Play Queue")
                                                 explanation:_NS("Display index numbers next to media items in the playlist sidebar.")
                                                       state:YES
                                                      action:^(BOOL checked) {
        weakSelf.hasUnsavedChanges = YES;
    }];
    _trackNumberRow.defaultHint = _NS("Default: On");
    [queueCard.contentStackView addArrangedSubview:_trackNumberRow];

    _endOfPlaybackRow = [MacLCSettingsRow checkboxRowWithTitle:_NS("Show End-of-Playback Screen")
                                                   explanation:_NS("Display suggestions and replay shortcuts when a video reaches its end.")
                                                         state:YES
                                                        action:^(BOOL checked) {
        weakSelf.hasUnsavedChanges = YES;
    }];
    _endOfPlaybackRow.defaultHint = _NS("Default: On");
    [queueCard.contentStackView addArrangedSubview:_endOfPlaybackRow];

    _notificationsRow = [MacLCSettingsRow checkboxRowWithTitle:_NS("Post Notifications on Track Change")
                                                   explanation:_NS("Show macOS banner alerts when a new song or video begins playing.")
                                                         state:NO
                                                        action:^(BOOL checked) {
        weakSelf.hasUnsavedChanges = YES;
    }];
    _notificationsRow.defaultHint = _NS("Default: Off");
    [queueCard.contentStackView addArrangedSubview:_notificationsRow];

    // Card 4: the web remote, which the lua interface provides. On a build
    // without lua the option does not exist, so the card is not built at all:
    // a control that cannot do anything is worse than a missing one.
    if (MacLCConfigExists("http-password")) {
        _advancedDisclosureButton = [NSButton buttonWithTitle:_NS("Advanced Web Remote ▶")
                                                       target:self
                                                       action:@selector(toggleAdvancedAction:)];
        _advancedDisclosureButton.bezelStyle = NSBezelStyleInline;
        [rootStack addArrangedSubview:_advancedDisclosureButton];

        _advancedCard = [MacLCCardView cardViewWithTitle:_NS("Web Remote Control (Advanced)")];
        _advancedCard.translatesAutoresizingMaskIntoConstraints = NO;
        _advancedCard.hidden = YES;
        [rootStack addArrangedSubview:_advancedCard];
        [_advancedCard.trailingAnchor constraintEqualToAnchor:rootStack.trailingAnchor].active = YES;

        _httpRemoteRow = [MacLCSettingsRow checkboxRowWithTitle:_NS("Enable HTTP Web Remote")
                                                    explanation:_NS("Host a local web server allowing browser-based and mobile remote control.")
                                                          state:NO
                                                         action:^(BOOL checked) {
            weakSelf.hasUnsavedChanges = YES;
            weakSelf.httpPasswordRow.enabled = checked;
        }];
        _httpRemoteRow.defaultHint = _NS("Default: Off");
        [_advancedCard.contentStackView addArrangedSubview:_httpRemoteRow];

        _httpPasswordRow = [MacLCSettingsRow textFieldRowWithTitle:_NS("Web Remote Password")
                                                       explanation:_NS("Password required for browsers and remote applications to connect.")
                                                              text:@""
                                                       placeholder:@"Password"
                                                          isSecure:YES
                                                            action:^(NSString *text) {
            weakSelf.hasUnsavedChanges = YES;
        }];
        [_advancedCard.contentStackView addArrangedSubview:_httpPasswordRow];

    }

    // Reset button
    NSButton *resetBtn = [NSButton buttonWithTitle:_NS("Reset Interface Settings…")
                                            target:self
                                            action:@selector(resetSectionAction:)];
    resetBtn.translatesAutoresizingMaskIntoConstraints = NO;
    resetBtn.bezelStyle = NSBezelStyleRounded;
    [rootStack addArrangedSubview:resetBtn];

    [self loadSettings];
}

- (void)toggleAdvancedAction:(id)sender
{
    BOOL isHidden = !_advancedCard.hidden;
    _advancedCard.hidden = isHidden;
    _advancedDisclosureButton.title = isHidden ? _NS("Advanced Web Remote ▶")
                                               : _NS("Advanced Web Remote ▼");
}

- (void)resetSectionAction:(id)sender
{
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = _NS("Reset Interface Settings");
    alert.informativeText = _NS("Are you sure you want to reset all Interface options to their default values?");
    [alert addButtonWithTitle:_NS("Reset")];
    [alert addButtonWithTitle:_NS("Cancel")];

    __weak typeof(self) weakSelf = self;
    [alert beginSheetModalForWindow:self.view.window completionHandler:^(NSModalResponse returnCode) {
        if (returnCode == NSAlertFirstButtonReturn) {
            [weakSelf resetToDefaults];
        }
    }];
}

#pragma mark - Module Helpers

- (BOOL)hasModule:(NSString *)moduleName inConfig:(const char *)configName
{
    char *val = MacLCConfigGetPsz(configName);
    if (!val) return NO;
    NSString *modules = toNSStr(val);
    free(val);
    return [[modules componentsSeparatedByString:@":"] containsObject:moduleName];
}

- (void)setModule:(NSString *)moduleName inConfig:(const char *)configName enabled:(BOOL)enable
{
    char *val = MacLCConfigGetPsz(configName);
    NSString *modules = val ? toNSStr(val) : @"";
    if (val) free(val);

    NSMutableArray *components = [[modules componentsSeparatedByString:@":"] mutableCopy];
    if (enable) {
        if (![components containsObject:moduleName]) {
            [components addObject:moduleName];
        }
    } else {
        [components removeObject:moduleName];
    }
    [components removeObject:@""];
    MacLCConfigPutPsz(configName, [[components componentsJoinedByString:@":"] UTF8String]);
}

#pragma mark - Settings Operations

- (void)loadSettings
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

    _statusIconRow.checkboxButton.state = MacLCConfigGetInt("macosx-statusicon", 0) ? NSControlStateValueOn : NSControlStateValueOff;
    _mediaKeysRow.checkboxButton.state = MacLCConfigGetInt("macosx-mediakeys", 0) ? NSControlStateValueOn : NSControlStateValueOff;

    BOOL remote = MacLCConfigGetInt("macosx-appleremote", 0) != 0;
    _appleRemoteRow.checkboxButton.state = remote ? NSControlStateValueOn : NSControlStateValueOff;
    _appleRemoteSysVolRow.checkboxButton.state = MacLCConfigGetInt("macosx-appleremote-sysvol", 0) ? NSControlStateValueOn : NSControlStateValueOff;
    _appleRemotePrevNextRow.checkboxButton.state = MacLCConfigGetInt("macosx-appleremote-prevnext", 0) ? NSControlStateValueOn : NSControlStateValueOff;
    _appleRemoteSysVolRow.enabled = remote;
    _appleRemotePrevNextRow.enabled = remote;

    [_controlItunesRow.popUpButton selectItemWithTag:MacLCConfigGetInt("macosx-control-itunes", 0)];

    _trackNumberRow.checkboxButton.state = [defaults boolForKey:VLCDisplayTrackNumberPlayQueueKey] ? NSControlStateValueOn : NSControlStateValueOff;
    _endOfPlaybackRow.checkboxButton.state = [defaults boolForKey:VLCPlaybackEndViewEnabledKey] ? NSControlStateValueOn : NSControlStateValueOff;

    BOOL notif = [self hasModule:@"growl" inConfig:"control"];
    _notificationsRow.checkboxButton.state = notif ? NSControlStateValueOn : NSControlStateValueOff;

    if (_httpRemoteRow) {
        BOOL http = [self hasModule:@"http" inConfig:"extraintf"];
        _httpRemoteRow.checkboxButton.state = http ? NSControlStateValueOn : NSControlStateValueOff;
        _httpPasswordRow.enabled = http;

        char *pwd = MacLCConfigGetPsz("http-password");
        _httpPasswordRow.textField.stringValue = pwd ? toNSStr(pwd) : @"";
        free(pwd);
    }

    self.hasUnsavedChanges = NO;
}

- (void)applyChanges
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

    MacLCConfigPutInt("macosx-statusicon", _statusIconRow.checkboxButton.state == NSControlStateValueOn);
    MacLCConfigPutInt("macosx-mediakeys", _mediaKeysRow.checkboxButton.state == NSControlStateValueOn);
    MacLCConfigPutInt("macosx-appleremote", _appleRemoteRow.checkboxButton.state == NSControlStateValueOn);
    MacLCConfigPutInt("macosx-appleremote-sysvol", _appleRemoteSysVolRow.checkboxButton.state == NSControlStateValueOn);
    MacLCConfigPutInt("macosx-appleremote-prevnext", _appleRemotePrevNextRow.checkboxButton.state == NSControlStateValueOn);

    MacLCConfigPutInt("macosx-control-itunes", _controlItunesRow.popUpButton.selectedTag);

    BOOL oldTrackNum = [defaults boolForKey:VLCDisplayTrackNumberPlayQueueKey];
    BOOL newTrackNum = _trackNumberRow.checkboxButton.state == NSControlStateValueOn;
    [defaults setBool:newTrackNum forKey:VLCDisplayTrackNumberPlayQueueKey];
    if (oldTrackNum != newTrackNum) {
        [NSNotificationCenter.defaultCenter postNotificationName:VLCDisplayTrackNumberPlayQueueSettingChanged object:nil];
    }

    [defaults setBool:_endOfPlaybackRow.checkboxButton.state == NSControlStateValueOn forKey:VLCPlaybackEndViewEnabledKey];

    [self setModule:@"growl" inConfig:"control" enabled:_notificationsRow.checkboxButton.state == NSControlStateValueOn];

    if (_httpRemoteRow) {
        BOOL http = _httpRemoteRow.checkboxButton.state == NSControlStateValueOn;
        [self setModule:@"http" inConfig:"extraintf" enabled:http];
        MacLCConfigPutPsz("http-password", [_httpPasswordRow.textField.stringValue UTF8String]);
    }

    self.hasUnsavedChanges = NO;
}

- (void)resetToDefaults
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults removeObjectForKey:VLCDisplayTrackNumberPlayQueueKey];
    [defaults removeObjectForKey:VLCPlaybackEndViewEnabledKey];

    module_config_t *item;
    if ((item = config_FindConfig("macosx-statusicon"))) MacLCConfigPutInt("macosx-statusicon", item->orig.i);
    if ((item = config_FindConfig("macosx-mediakeys"))) MacLCConfigPutInt("macosx-mediakeys", item->orig.i);
    if ((item = config_FindConfig("macosx-appleremote"))) MacLCConfigPutInt("macosx-appleremote", item->orig.i);
    if ((item = config_FindConfig("macosx-appleremote-sysvol"))) MacLCConfigPutInt("macosx-appleremote-sysvol", item->orig.i);
    if ((item = config_FindConfig("macosx-appleremote-prevnext"))) MacLCConfigPutInt("macosx-appleremote-prevnext", item->orig.i);
    if ((item = config_FindConfig("macosx-control-itunes"))) MacLCConfigPutInt("macosx-control-itunes", item->orig.i);
    if ((item = config_FindConfig("http-password"))) MacLCConfigPutPsz("http-password", "");

    [self setModule:@"growl" inConfig:"control" enabled:NO];
    [self setModule:@"http" inConfig:"extraintf" enabled:NO];

    [self loadSettings];
    self.hasUnsavedChanges = YES;
}

@end
