/*****************************************************************************
 * MacLCGeneralSettingsViewController.m: General Settings Pane for MacLC
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

#import "settings/panes/MacLCGeneralSettingsViewController.h"
#import "settings/MacLCConfigSafe.h"
#import "settings/MacLCSettingsRow.h"
#import "theme/MacLCDesign.h"
#import "theme/MacLCCardView.h"
#import "main/VLCMain.h"
#import "preferences/prefs.h"
#import "preferences/VLCSimplePrefsController.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wnullability-completeness"
#import "extensions/NSString+Helpers.h"
#pragma clang diagnostic pop

#import <vlc_configuration.h>

static struct {
    const char * const iso;
    const char * const name;
} const kLanguages[] = {
    { "auto",  "System Default" },
    { "en",    "English" },
    { "fr",    "Français" },
    { "de",    "Deutsch" },
    { "es",    "Español" },
    { "it",    "Italiano" },
    { "ja",    "日本語" },
    { "zh_CN", "简体中文" },
    { "nl",    "Nederlands" },
    { "pt_PT", "Português" },
    { "ru",    "Русский" },
    { "ko",    "한국어" }
};

@interface MacLCGeneralSettingsViewController ()
{
    intf_thread_t *_p_intf;
}

@property (nonatomic, assign) BOOL hasUnsavedChanges;

// Rows
@property (nonatomic, strong) MacLCSettingsRow *languageRow;
@property (nonatomic, strong) MacLCSettingsRow *appearanceRow;
@property (nonatomic, strong) MacLCSettingsRow *iconChangeRow;
@property (nonatomic, strong) MacLCSettingsRow *continuePlaybackRow;
@property (nonatomic, strong) MacLCSettingsRow *recentItemsRow;
@property (nonatomic, strong) MacLCSettingsRow *autoloadExtensionsRow;
@property (nonatomic, strong) MacLCSettingsRow *metadataNetworkRow;
@property (nonatomic, strong) MacLCSettingsRow *updatesRow;
@property (nonatomic, strong) MacLCSettingsRow *showAllRow;

@end

@implementation MacLCGeneralSettingsViewController

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
    return _NS("General");
}

- (NSString *)paneSymbolName
{
    return @"gearshape";
}

- (NSString *)paneIdentifier
{
    return @"general";
}

- (NSArray<NSString *> *)searchKeywords
{
    return @[
        @"general", @"appearance", @"language", @"dark", @"light", @"icon",
        @"startup", @"resume", @"continue", @"playback", @"recent", @"items",
        @"extensions", @"privacy", @"network", @"metadata", @"artwork", @"updates",
        @"advanced", @"preferences", @"all settings",
        @"macosx-icon-change", @"macosx-continue-playback", @"macosx-recentitems",
        @"macosx-autoload-extensions", @"metadata-network-access"
    ];
}

#pragma mark - View Lifecycle & Layout

- (void)loadView
{
    NSView *container = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 600, 750)];
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

    // Card 1: Appearance & Language
    MacLCCardView *appearanceCard = [MacLCCardView cardViewWithTitle:_NS("Appearance & Language")];
    appearanceCard.translatesAutoresizingMaskIntoConstraints = NO;
    [rootStack addArrangedSubview:appearanceCard];
    [appearanceCard.trailingAnchor constraintEqualToAnchor:rootStack.trailingAnchor].active = YES;

    NSMutableArray<NSString *> *langNames = [NSMutableArray array];
    for (size_t i = 0; i < sizeof(kLanguages) / sizeof(kLanguages[0]); i++) {
        [langNames addObject:toNSStr(kLanguages[i].name)];
    }

    _languageRow = [MacLCSettingsRow popUpRowWithTitle:_NS("Interface Language")
                                           explanation:_NS("Choose the display language for menus, labels, and dialogs.")
                                                 items:langNames
                                                  tags:nil
                                         selectedIndex:0
                                                action:^(NSInteger selectedIndex, NSInteger tag) {
        weakSelf.hasUnsavedChanges = YES;
    }];
    _languageRow.defaultHint = _NS("Default: System Default");
    [appearanceCard.contentStackView addArrangedSubview:_languageRow];

    _appearanceRow = [MacLCSettingsRow popUpRowWithTitle:_NS("Appearance")
                                             explanation:_NS("Match your macOS appearance or lock MacLC to light or dark mode.")
                                                   items:@[_NS("System"), _NS("Light"), _NS("Dark")]
                                                    tags:@[@0, @1, @2]
                                           selectedIndex:0
                                                  action:^(NSInteger selectedIndex, NSInteger tag) {
        weakSelf.hasUnsavedChanges = YES;
    }];
    _appearanceRow.defaultHint = _NS("Default: System");
    [appearanceCard.contentStackView addArrangedSubview:_appearanceRow];

    _iconChangeRow = [MacLCSettingsRow checkboxRowWithTitle:_NS("Dynamic Application Icon")
                                                explanation:_NS("Allow the Dock icon to change for festive occasions or playback states.")
                                                      state:YES
                                                     action:^(BOOL checked) {
        weakSelf.hasUnsavedChanges = YES;
    }];
    _iconChangeRow.defaultHint = _NS("Default: On");
    [appearanceCard.contentStackView addArrangedSubview:_iconChangeRow];

    // Card 2: Startup & History
    MacLCCardView *startupCard = [MacLCCardView cardViewWithTitle:_NS("Startup & History")];
    startupCard.translatesAutoresizingMaskIntoConstraints = NO;
    [rootStack addArrangedSubview:startupCard];
    [startupCard.trailingAnchor constraintEqualToAnchor:rootStack.trailingAnchor].active = YES;

    _continuePlaybackRow = [MacLCSettingsRow popUpRowWithTitle:_NS("Continue Playback")
                                                   explanation:_NS("Resume playback from your last position when reopening recent media.")
                                                         items:@[_NS("Ask"), _NS("Always"), _NS("Never")]
                                                          tags:@[@0, @1, @2]
                                                 selectedIndex:0
                                                        action:^(NSInteger selectedIndex, NSInteger tag) {
        weakSelf.hasUnsavedChanges = YES;
    }];
    _continuePlaybackRow.defaultHint = _NS("Default: Ask");
    [startupCard.contentStackView addArrangedSubview:_continuePlaybackRow];

    _recentItemsRow = [MacLCSettingsRow checkboxRowWithTitle:_NS("Keep Recent Media Items")
                                                 explanation:_NS("Record recently played items in the Open Recent menu and resume list.")
                                                       state:YES
                                                      action:^(BOOL checked) {
        weakSelf.hasUnsavedChanges = YES;
        weakSelf.continuePlaybackRow.enabled = checked;
    }];
    _recentItemsRow.defaultHint = _NS("Default: On");
    [startupCard.contentStackView addArrangedSubview:_recentItemsRow];

    _autoloadExtensionsRow = [MacLCSettingsRow checkboxRowWithTitle:_NS("Load Extensions on Launch")
                                                        explanation:_NS("Automatically enable installed MacLC extensions when the app starts.")
                                                              state:YES
                                                             action:^(BOOL checked) {
        weakSelf.hasUnsavedChanges = YES;
    }];
    _autoloadExtensionsRow.defaultHint = _NS("Default: On");
    [startupCard.contentStackView addArrangedSubview:_autoloadExtensionsRow];

    // Card 3: Privacy & Network Access
    MacLCCardView *privacyCard = [MacLCCardView cardViewWithTitle:_NS("Privacy & Network")];
    privacyCard.translatesAutoresizingMaskIntoConstraints = NO;
    [rootStack addArrangedSubview:privacyCard];
    [privacyCard.trailingAnchor constraintEqualToAnchor:rootStack.trailingAnchor].active = YES;

    _metadataNetworkRow = [MacLCSettingsRow checkboxRowWithTitle:_NS("Fetch Artwork and Metadata Online")
                                                     explanation:_NS("Allow MacLC to query the internet for cover artwork and track information.")
                                                           state:NO
                                                          action:^(BOOL checked) {
        weakSelf.hasUnsavedChanges = YES;
    }];
    _metadataNetworkRow.defaultHint = _NS("Default: Off");
    [privacyCard.contentStackView addArrangedSubview:_metadataNetworkRow];

#ifdef HAVE_SPARKLE
    _updatesRow = [MacLCSettingsRow checkboxRowWithTitle:_NS("Check for Updates Automatically")
                                             explanation:_NS("Periodically verify whether a newer version of MacLC is available.")
                                                   state:YES
                                                  action:^(BOOL checked) {
        weakSelf.hasUnsavedChanges = YES;
    }];
    _updatesRow.defaultHint = _NS("Default: On");
    [privacyCard.contentStackView addArrangedSubview:_updatesRow];
#endif

    // Card 4: All Settings (Escape hatch)
    MacLCCardView *advancedCard = [MacLCCardView cardViewWithTitle:_NS("Advanced Preferences")];
    advancedCard.translatesAutoresizingMaskIntoConstraints = NO;
    [rootStack addArrangedSubview:advancedCard];
    [advancedCard.trailingAnchor constraintEqualToAnchor:rootStack.trailingAnchor].active = YES;

    NSButton *showAllBtn = [NSButton buttonWithTitle:_NS("Show All Settings…")
                                              target:self
                                              action:@selector(showAllSettingsAction:)];
    showAllBtn.bezelStyle = NSBezelStyleRounded;
    _showAllRow = [MacLCSettingsRow rowWithTitle:_NS("Full VLC Preferences Tree")
                                     explanation:_NS("Open the exhaustive preferences tree to adjust low-level engine parameters.")
                                         control:showAllBtn];
    [advancedCard.contentStackView addArrangedSubview:_showAllRow];

    // Reset button at bottom
    NSButton *resetBtn = [NSButton buttonWithTitle:_NS("Reset General Settings…")
                                            target:self
                                            action:@selector(resetSectionAction:)];
    resetBtn.translatesAutoresizingMaskIntoConstraints = NO;
    resetBtn.bezelStyle = NSBezelStyleRounded;
    [rootStack addArrangedSubview:resetBtn];

    [self loadSettings];
}

- (void)showAllSettingsAction:(id)sender
{
    [VLCMain.sharedInstance.preferences showPrefsWithLevel:[self.view.window level]];
}

- (void)resetSectionAction:(id)sender
{
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = _NS("Reset General Settings");
    alert.informativeText = _NS("Are you sure you want to reset all General options to their default values?");
    [alert addButtonWithTitle:_NS("Reset")];
    [alert addButtonWithTitle:_NS("Cancel")];

    __weak typeof(self) weakSelf = self;
    [alert beginSheetModalForWindow:self.view.window completionHandler:^(NSModalResponse returnCode) {
        if (returnCode == NSAlertFirstButtonReturn) {
            [weakSelf resetToDefaults];
        }
    }];
}

#pragma mark - Settings Operations

- (void)loadSettings
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

    // Language
    NSString *currentLang = [defaults stringForKey:@"language"] ?: @"auto";
    NSInteger langIndex = 0;
    for (size_t i = 0; i < sizeof(kLanguages) / sizeof(kLanguages[0]); i++) {
        if ([currentLang isEqualToString:toNSStr(kLanguages[i].iso)]) {
            langIndex = (NSInteger)i;
            break;
        }
    }
    [_languageRow.popUpButton selectItemAtIndex:langIndex];

    // Appearance
    NSString *appearancePref = [defaults stringForKey:@"MacLCAppearanceMode"] ?: @"system";
    NSInteger appIdx = 0;
    if ([appearancePref isEqualToString:@"light"]) appIdx = 1;
    else if ([appearancePref isEqualToString:@"dark"]) appIdx = 2;
    [_appearanceRow.popUpButton selectItemAtIndex:appIdx];

    // Icon change
    _iconChangeRow.checkboxButton.state = MacLCConfigGetInt("macosx-icon-change", 0) ? NSControlStateValueOn : NSControlStateValueOff;

    // Continue playback
    NSInteger continueVal = MacLCConfigGetInt("macosx-continue-playback", 0);
    [_continuePlaybackRow.popUpButton selectItemWithTag:continueVal];

    // Recent items
    BOOL recent = MacLCConfigGetInt("macosx-recentitems", 0) != 0;
    _recentItemsRow.checkboxButton.state = recent ? NSControlStateValueOn : NSControlStateValueOff;
    _continuePlaybackRow.enabled = recent;

    // Autoload extensions
    _autoloadExtensionsRow.checkboxButton.state = MacLCConfigGetInt("macosx-autoload-extensions", 0) ? NSControlStateValueOn : NSControlStateValueOff;

    // Metadata network access
    _metadataNetworkRow.checkboxButton.state = MacLCConfigGetInt("metadata-network-access", 0) ? NSControlStateValueOn : NSControlStateValueOff;

#ifdef HAVE_SPARKLE
    if (_updatesRow && VLCMain.sharedInstance.sparkleUpdaterController.updater) {
        BOOL updates = VLCMain.sharedInstance.sparkleUpdaterController.updater.automaticallyChecksForUpdates;
        _updatesRow.checkboxButton.state = updates ? NSControlStateValueOn : NSControlStateValueOff;
    }
#endif

    self.hasUnsavedChanges = NO;
}

- (void)applyChanges
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

    // Language
    NSInteger langIdx = _languageRow.popUpButton.indexOfSelectedItem;
    if (langIdx >= 0 && langIdx < (NSInteger)(sizeof(kLanguages) / sizeof(kLanguages[0]))) {
        NSString *iso = toNSStr(kLanguages[langIdx].iso);
        [defaults setObject:iso forKey:@"language"];
        [VLCSimplePrefsController updateRightToLeftSettings];
    }

    // Appearance
    NSInteger appIdx = _appearanceRow.popUpButton.selectedTag;
    NSString *appMode = @"system";
    if (appIdx == 1) appMode = @"light";
    else if (appIdx == 2) appMode = @"dark";
    [defaults setObject:appMode forKey:@"MacLCAppearanceMode"];

    // Options
    MacLCConfigPutInt("macosx-icon-change", _iconChangeRow.checkboxButton.state == NSControlStateValueOn);
    MacLCConfigPutInt("macosx-continue-playback", _continuePlaybackRow.popUpButton.selectedTag);
    MacLCConfigPutInt("macosx-recentitems", _recentItemsRow.checkboxButton.state == NSControlStateValueOn);
    MacLCConfigPutInt("macosx-autoload-extensions", _autoloadExtensionsRow.checkboxButton.state == NSControlStateValueOn);
    MacLCConfigPutInt("metadata-network-access", _metadataNetworkRow.checkboxButton.state == NSControlStateValueOn);

#ifdef HAVE_SPARKLE
    if (_updatesRow && VLCMain.sharedInstance.sparkleUpdaterController.updater) {
        VLCMain.sharedInstance.sparkleUpdaterController.updater.automaticallyChecksForUpdates =
            (_updatesRow.checkboxButton.state == NSControlStateValueOn);
    }
#endif

    self.hasUnsavedChanges = NO;
}

- (void)resetToDefaults
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults removeObjectForKey:@"language"];
    [defaults removeObjectForKey:@"MacLCAppearanceMode"];

    module_config_t *item;
    if ((item = config_FindConfig("macosx-icon-change"))) MacLCConfigPutInt("macosx-icon-change", item->orig.i);
    if ((item = config_FindConfig("macosx-continue-playback"))) MacLCConfigPutInt("macosx-continue-playback", item->orig.i);
    if ((item = config_FindConfig("macosx-recentitems"))) MacLCConfigPutInt("macosx-recentitems", item->orig.i);
    if ((item = config_FindConfig("macosx-autoload-extensions"))) MacLCConfigPutInt("macosx-autoload-extensions", item->orig.i);
    if ((item = config_FindConfig("metadata-network-access"))) MacLCConfigPutInt("metadata-network-access", item->orig.i);

    [self loadSettings];
    self.hasUnsavedChanges = YES;
}

@end
