/*****************************************************************************
 * MacLCAudioSettingsViewController.m: Audio Settings Pane for MacLC
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

#import "settings/panes/MacLCAudioSettingsViewController.h"
#import "settings/MacLCConfigSafe.h"
#import "settings/MacLCSettingsRow.h"
#import "theme/MacLCDesign.h"
#import "theme/MacLCCardView.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wnullability-completeness"
#import "extensions/NSString+Helpers.h"
#pragma clang diagnostic pop

#import <vlc_configuration.h>
#import <vlc_plugin.h>
#import <vlc_modules.h>
#import <vlc_aout.h>

@interface MacLCAudioSettingsViewController ()
{
    intf_thread_t *_p_intf;
}

@property (nonatomic, assign) BOOL hasUnsavedChanges;

// Rows
@property (nonatomic, strong) MacLCSettingsRow *audioEnableRow;
@property (nonatomic, strong) MacLCSettingsRow *saveVolumeRow;
@property (nonatomic, strong) MacLCSettingsRow *defaultVolumeRow;
@property (nonatomic, strong) MacLCSettingsRow *maxVolumeRow;
@property (nonatomic, strong) MacLCSettingsRow *audioLangRow;

@property (nonatomic, strong) MacLCSettingsRow *replayGainRow;
@property (nonatomic, strong) MacLCSettingsRow *normVolRow;
@property (nonatomic, strong) MacLCSettingsRow *normMaxLevelRow;

@property (nonatomic, strong) MacLCCardView *advancedCard;
@property (nonatomic, strong) NSButton *advancedDisclosureButton;
@property (nonatomic, strong) MacLCSettingsRow *headphoneRow;
@property (nonatomic, strong) MacLCSettingsRow *headphoneDimRow;
@property (nonatomic, strong) MacLCSettingsRow *visualRow;

@property (nonatomic, strong, nullable) MacLCCardView *lastfmCard;
@property (nonatomic, strong, nullable) MacLCSettingsRow *lastfmEnableRow;
@property (nonatomic, strong, nullable) MacLCSettingsRow *lastfmUserRow;
@property (nonatomic, strong, nullable) MacLCSettingsRow *lastfmPasswordRow;

@end

@implementation MacLCAudioSettingsViewController

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
    return _NS("Audio");
}

- (NSString *)paneSymbolName
{
    return @"speaker.wave.3";
}

- (NSString *)paneIdentifier
{
    return @"audio";
}

- (NSArray<NSString *> *)searchKeywords
{
    return @[
        @"audio", @"sound", @"volume", @"headphone", @"speaker", @"normalization",
        @"replaygain", @"scrobble", @"last.fm", @"visualization", @"language",
        @"audio", @"volume-save", @"auhal-volume", @"macosx-max-volume",
        @"audio-language", @"audio-replay-gain-mode", @"normvol", @"norm-max-level",
        @"headphone", @"headphone-dim", @"audio-visual", @"lastfm-username",
        @"lastfm-password"
    ];
}

#pragma mark - View Lifecycle & Layout

- (void)loadView
{
    NSView *container = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 600, 1150)];
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

    // Card 1: Audio Output & Volume
    MacLCCardView *volumeCard = [MacLCCardView cardViewWithTitle:_NS("Audio Output & Volume")];
    volumeCard.translatesAutoresizingMaskIntoConstraints = NO;
    [rootStack addArrangedSubview:volumeCard];
    [volumeCard.trailingAnchor constraintEqualToAnchor:rootStack.trailingAnchor].active = YES;

    _audioEnableRow = [MacLCSettingsRow checkboxRowWithTitle:_NS("Enable Audio")
                                                 explanation:_NS("Output sound during media playback.")
                                                       state:YES
                                                      action:^(BOOL checked) {
        weakSelf.hasUnsavedChanges = YES;
    }];
    _audioEnableRow.defaultHint = _NS("Default: On");
    [volumeCard.contentStackView addArrangedSubview:_audioEnableRow];

    _saveVolumeRow = [MacLCSettingsRow checkboxRowWithTitle:_NS("Remember Volume Across Launches")
                                                explanation:_NS("Restore the previous volume level when MacLC opens rather than resetting to default.")
                                                      state:YES
                                                     action:^(BOOL checked) {
        weakSelf.hasUnsavedChanges = YES;
        weakSelf.defaultVolumeRow.enabled = !checked;
    }];
    _saveVolumeRow.defaultHint = _NS("Default: On");
    [volumeCard.contentStackView addArrangedSubview:_saveVolumeRow];

    _defaultVolumeRow = [MacLCSettingsRow sliderRowWithTitle:_NS("Default Volume Level")
                                                 explanation:_NS("Volume percentage applied when opening files if not remembering previous volume.")
                                                    minValue:0
                                                    maxValue:200
                                                initialValue:100
                                                 valueFormat:@"%.0f%%"
                                                      action:^(double value) {
        weakSelf.hasUnsavedChanges = YES;
    }];
    _defaultVolumeRow.defaultHint = _NS("Default: 100%");
    [volumeCard.contentStackView addArrangedSubview:_defaultVolumeRow];

    _maxVolumeRow = [MacLCSettingsRow stepperRowWithTitle:_NS("Maximum Volume Boost")
                                              explanation:_NS("Upper limit available on the player volume slider (up to 200%).")
                                                 minValue:60
                                                 maxValue:200
                                             initialValue:125
                                                stepValue:5
                                              valueFormat:@"%.0f%%"
                                                   action:^(double value) {
        weakSelf.hasUnsavedChanges = YES;
    }];
    _maxVolumeRow.defaultHint = _NS("Default: 125%");
    [volumeCard.contentStackView addArrangedSubview:_maxVolumeRow];

    _audioLangRow = [MacLCSettingsRow textFieldRowWithTitle:_NS("Preferred Audio Languages")
                                                explanation:_NS("Comma-separated two-letter language codes (e.g. en, ja) for automatic track selection.")
                                                       text:@""
                                                placeholder:@"en, ja"
                                                   isSecure:NO
                                                     action:^(NSString *text) {
        weakSelf.hasUnsavedChanges = YES;
    }];
    _audioLangRow.defaultHint = _NS("Default: Empty");
    [volumeCard.contentStackView addArrangedSubview:_audioLangRow];

    // Card 2: Normalization & ReplayGain
    MacLCCardView *normCard = [MacLCCardView cardViewWithTitle:_NS("Volume Normalization & ReplayGain")];
    normCard.translatesAutoresizingMaskIntoConstraints = NO;
    [rootStack addArrangedSubview:normCard];
    [normCard.trailingAnchor constraintEqualToAnchor:rootStack.trailingAnchor].active = YES;

    _replayGainRow = [MacLCSettingsRow popUpRowWithTitle:_NS("ReplayGain Mode")
                                             explanation:_NS("Prevent sudden volume jumps between different songs using embedded album/track tags.")
                                                   items:@[_NS("Disabled"), _NS("Track"), _NS("Album")]
                                                    tags:@[@0, @1, @2]
                                           selectedIndex:0
                                                  action:^(NSInteger selectedIndex, NSInteger tag) {
        weakSelf.hasUnsavedChanges = YES;
    }];
    _replayGainRow.defaultHint = _NS("Default: Disabled");
    [normCard.contentStackView addArrangedSubview:_replayGainRow];

    _normVolRow = [MacLCSettingsRow checkboxRowWithTitle:_NS("Dynamic Volume Normalizer")
                                             explanation:_NS("Compress wide volume fluctuations so whispers and explosions play at consistent levels.")
                                                   state:NO
                                                  action:^(BOOL checked) {
        weakSelf.hasUnsavedChanges = YES;
        weakSelf.normMaxLevelRow.enabled = checked;
    }];
    _normVolRow.defaultHint = _NS("Default: Off");
    [normCard.contentStackView addArrangedSubview:_normVolRow];

    _normMaxLevelRow = [MacLCSettingsRow sliderRowWithTitle:_NS("Max Normalization Multiplier")
                                                explanation:_NS("Maximum amplification factor applied to quiet passages.")
                                                   minValue:0.5
                                                   maxValue:10.0
                                               initialValue:2.0
                                                valueFormat:@"%.1fx"
                                                     action:^(double value) {
        weakSelf.hasUnsavedChanges = YES;
    }];
    _normMaxLevelRow.defaultHint = _NS("Default: 2.0x");
    [normCard.contentStackView addArrangedSubview:_normMaxLevelRow];

    // Card 3: Advanced Headphones & Spatial Audio (collapsed disclosure)
    _advancedDisclosureButton = [NSButton buttonWithTitle:_NS("Advanced Headphones & Effects ▶")
                                                   target:self
                                                   action:@selector(toggleAdvancedAction:)];
    _advancedDisclosureButton.bezelStyle = NSBezelStyleInline;
    [rootStack addArrangedSubview:_advancedDisclosureButton];

    _advancedCard = [MacLCCardView cardViewWithTitle:_NS("Headphones & Effects (Advanced)")];
    _advancedCard.translatesAutoresizingMaskIntoConstraints = NO;
    _advancedCard.hidden = YES;
    [rootStack addArrangedSubview:_advancedCard];
    [_advancedCard.trailingAnchor constraintEqualToAnchor:rootStack.trailingAnchor].active = YES;

    _headphoneRow = [MacLCSettingsRow checkboxRowWithTitle:_NS("Headphone Surround Spatializer")
                                               explanation:_NS("Simulate room acoustic dimensions when listening to multi-channel surround on headphones.")
                                                     state:NO
                                                    action:^(BOOL checked) {
        weakSelf.hasUnsavedChanges = YES;
        weakSelf.headphoneDimRow.enabled = checked;
    }];
    _headphoneRow.defaultHint = _NS("Default: Off");
    [_advancedCard.contentStackView addArrangedSubview:_headphoneRow];

    _headphoneDimRow = [MacLCSettingsRow stepperRowWithTitle:_NS("Room Dimension")
                                                 explanation:_NS("Simulated listening room characteristic in meters.")
                                                    minValue:5
                                                    maxValue:30
                                                initialValue:10
                                                   stepValue:1
                                                 valueFormat:@"%.0f m"
                                                      action:^(double value) {
        weakSelf.hasUnsavedChanges = YES;
    }];
    _headphoneDimRow.defaultHint = _NS("Default: 10 m");
    [_advancedCard.contentStackView addArrangedSubview:_headphoneDimRow];

    _visualRow = [MacLCSettingsRow popUpRowWithTitle:_NS("Audio Visualizations")
                                         explanation:_NS("Display animated graphic patterns synchronized to playing audio.")
                                               items:@[_NS("Disabled"), @"Goom", @"Visualizer"]
                                                tags:@[@0, @1, @2]
                                       selectedIndex:0
                                              action:^(NSInteger selectedIndex, NSInteger tag) {
        weakSelf.hasUnsavedChanges = YES;
    }];
    _visualRow.defaultHint = _NS("Default: Disabled");
    [_advancedCard.contentStackView addArrangedSubview:_visualRow];

    // Card 4: Last.fm (if module exists)
    if (module_exists("audioscrobbler")) {
        _lastfmCard = [MacLCCardView cardViewWithTitle:_NS("Last.fm Scrobbling")];
        _lastfmCard.translatesAutoresizingMaskIntoConstraints = NO;
        [rootStack addArrangedSubview:_lastfmCard];
        [_lastfmCard.trailingAnchor constraintEqualToAnchor:rootStack.trailingAnchor].active = YES;

        _lastfmEnableRow = [MacLCSettingsRow checkboxRowWithTitle:_NS("Scrobble to Last.fm")
                                                      explanation:_NS("Automatically submit played tracks and artists to your Last.fm music profile.")
                                                            state:NO
                                                           action:^(BOOL checked) {
            weakSelf.hasUnsavedChanges = YES;
            weakSelf.lastfmUserRow.enabled = checked;
            weakSelf.lastfmPasswordRow.enabled = checked;
        }];
        _lastfmEnableRow.defaultHint = _NS("Default: Off");
        [_lastfmCard.contentStackView addArrangedSubview:_lastfmEnableRow];

        _lastfmUserRow = [MacLCSettingsRow textFieldRowWithTitle:_NS("Username")
                                                     explanation:_NS("Your Last.fm user account handle.")
                                                            text:@""
                                                     placeholder:@"Username"
                                                        isSecure:NO
                                                          action:^(NSString *text) {
            weakSelf.hasUnsavedChanges = YES;
        }];
        [_lastfmCard.contentStackView addArrangedSubview:_lastfmUserRow];

        _lastfmPasswordRow = [MacLCSettingsRow textFieldRowWithTitle:_NS("Password")
                                                         explanation:_NS("Your Last.fm user account password.")
                                                                text:@""
                                                         placeholder:@"Password"
                                                            isSecure:YES
                                                              action:^(NSString *text) {
            weakSelf.hasUnsavedChanges = YES;
        }];
        [_lastfmCard.contentStackView addArrangedSubview:_lastfmPasswordRow];
    }

    // Reset button
    NSButton *resetBtn = [NSButton buttonWithTitle:_NS("Reset Audio Settings…")
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
    _advancedDisclosureButton.title = isHidden ? _NS("Advanced Headphones & Effects ▶")
                                               : _NS("Advanced Headphones & Effects ▼");
}

- (void)resetSectionAction:(id)sender
{
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = _NS("Reset Audio Settings");
    alert.informativeText = _NS("Are you sure you want to reset all Audio options to their default values?");
    [alert addButtonWithTitle:_NS("Reset")];
    [alert addButtonWithTitle:_NS("Cancel")];

    __weak typeof(self) weakSelf = self;
    [alert beginSheetModalForWindow:self.view.window completionHandler:^(NSModalResponse returnCode) {
        if (returnCode == NSAlertFirstButtonReturn) {
            [weakSelf resetToDefaults];
        }
    }];
}

#pragma mark - Filter Helpers

- (BOOL)hasAudioFilter:(NSString *)filterName
{
    char *val = MacLCConfigGetPsz("audio-filter");
    if (!val) return NO;
    NSString *filters = toNSStr(val);
    free(val);
    return [[filters componentsSeparatedByString:@":"] containsObject:filterName];
}

- (void)setAudioFilter:(NSString *)filterName enabled:(BOOL)enable
{
    char *val = MacLCConfigGetPsz("audio-filter");
    NSString *filters = val ? toNSStr(val) : @"";
    if (val) free(val);

    NSMutableArray *components = [[filters componentsSeparatedByString:@":"] mutableCopy];
    if (enable) {
        if (![components containsObject:filterName]) {
            [components addObject:filterName];
        }
    } else {
        [components removeObject:filterName];
    }
    [components removeObject:@""];
    MacLCConfigPutPsz("audio-filter", [[components componentsJoinedByString:@":"] UTF8String]);
}

#pragma mark - Settings Operations

- (void)loadSettings
{
    _audioEnableRow.checkboxButton.state = MacLCConfigGetInt("audio", 0) ? NSControlStateValueOn : NSControlStateValueOff;

    BOOL saveVol = MacLCConfigGetInt("volume-save", 0) != 0;
    _saveVolumeRow.checkboxButton.state = saveVol ? NSControlStateValueOn : NSControlStateValueOff;
    _defaultVolumeRow.enabled = !saveVol;

    int vol = (int)MacLCConfigGetInt("auhal-volume", 0);
    double volPct = vol * 200.0 / (double)AOUT_VOLUME_MAX;
    if (volPct < 0) volPct = 100;
    _defaultVolumeRow.slider.doubleValue = volPct;
    _defaultVolumeRow.sliderReadoutLabel.stringValue = [NSString stringWithFormat:@"%.0f%%", volPct];

    int maxVol = (int)MacLCConfigGetInt("macosx-max-volume", 0);
    if (maxVol < 60) maxVol = 125;
    _maxVolumeRow.stepper.doubleValue = maxVol;
    _maxVolumeRow.sliderReadoutLabel.stringValue = [NSString stringWithFormat:@"%d%%", maxVol];

    char *lang = MacLCConfigGetPsz("audio-language");
    _audioLangRow.textField.stringValue = lang ? toNSStr(lang) : @"";
    free(lang);

    char *rg = MacLCConfigGetPsz("audio-replay-gain-mode");
    NSString *rgStr = rg ? toNSStr(rg) : @"none";
    free(rg);
    if ([rgStr isEqualToString:@"track"]) [_replayGainRow.popUpButton selectItemWithTag:1];
    else if ([rgStr isEqualToString:@"album"]) [_replayGainRow.popUpButton selectItemWithTag:2];
    else [_replayGainRow.popUpButton selectItemWithTag:0];

    BOOL norm = [self hasAudioFilter:@"normvol"];
    _normVolRow.checkboxButton.state = norm ? NSControlStateValueOn : NSControlStateValueOff;
    _normMaxLevelRow.enabled = norm;

    float normLvl = MacLCConfigGetFloat("norm-max-level", 0.0f);
    if (normLvl <= 0.0f) normLvl = 2.0f;
    _normMaxLevelRow.slider.doubleValue = normLvl;
    _normMaxLevelRow.sliderReadoutLabel.stringValue = [NSString stringWithFormat:@"%.1fx", normLvl];

    BOOL headphone = [self hasAudioFilter:@"headphone"];
    _headphoneRow.checkboxButton.state = headphone ? NSControlStateValueOn : NSControlStateValueOff;
    _headphoneDimRow.enabled = headphone;

    int dim = (int)MacLCConfigGetInt("headphone-dim", 0);
    if (dim < 5) dim = 10;
    _headphoneDimRow.stepper.doubleValue = dim;
    _headphoneDimRow.sliderReadoutLabel.stringValue = [NSString stringWithFormat:@"%d m", dim];

    char *vis = MacLCConfigGetPsz("audio-visual");
    NSString *visStr = vis ? toNSStr(vis) : @"";
    free(vis);
    if ([visStr isEqualToString:@"goom"]) [_visualRow.popUpButton selectItemWithTag:1];
    else if ([visStr isEqualToString:@"visual"]) [_visualRow.popUpButton selectItemWithTag:2];
    else [_visualRow.popUpButton selectItemWithTag:0];

    if (_lastfmCard) {
        BOOL scrobble = config_ExistIntf("audioscrobbler");
        _lastfmEnableRow.checkboxButton.state = scrobble ? NSControlStateValueOn : NSControlStateValueOff;
        _lastfmUserRow.enabled = scrobble;
        _lastfmPasswordRow.enabled = scrobble;

        char *usr = MacLCConfigGetPsz("lastfm-username");
        _lastfmUserRow.textField.stringValue = usr ? toNSStr(usr) : @"";
        free(usr);

        char *pwd = MacLCConfigGetPsz("lastfm-password");
        _lastfmPasswordRow.textField.stringValue = pwd ? toNSStr(pwd) : @"";
        free(pwd);
    }

    self.hasUnsavedChanges = NO;
}

- (void)applyChanges
{
    MacLCConfigPutInt("audio", _audioEnableRow.checkboxButton.state == NSControlStateValueOn);

    BOOL saveVol = _saveVolumeRow.checkboxButton.state == NSControlStateValueOn;
    MacLCConfigPutInt("volume-save", saveVol);
    var_SetBool(_p_intf, "volume-save", saveVol);

    if (!saveVol) {
        int auhalVol = (int)(_defaultVolumeRow.slider.doubleValue * (double)AOUT_VOLUME_MAX / 200.0);
        MacLCConfigPutInt("auhal-volume", auhalVol);
    }

    MacLCConfigPutInt("macosx-max-volume", (int)_maxVolumeRow.stepper.doubleValue);
    MacLCConfigPutPsz("audio-language", [_audioLangRow.textField.stringValue UTF8String]);

    NSInteger rgTag = _replayGainRow.popUpButton.selectedTag;
    const char *rgMode = "none";
    if (rgTag == 1) rgMode = "track";
    else if (rgTag == 2) rgMode = "album";
    MacLCConfigPutPsz("audio-replay-gain-mode", rgMode);

    [self setAudioFilter:@"normvol" enabled:_normVolRow.checkboxButton.state == NSControlStateValueOn];
    MacLCConfigPutFloat("norm-max-level", (float)_normMaxLevelRow.slider.doubleValue);

    [self setAudioFilter:@"headphone" enabled:_headphoneRow.checkboxButton.state == NSControlStateValueOn];
    MacLCConfigPutInt("headphone-dim", (int)_headphoneDimRow.stepper.doubleValue);

    NSInteger visTag = _visualRow.popUpButton.selectedTag;
    const char *visMode = "";
    if (visTag == 1) visMode = "goom";
    else if (visTag == 2) visMode = "visual";
    MacLCConfigPutPsz("audio-visual", visMode);

    if (_lastfmCard) {
        if (_lastfmEnableRow.checkboxButton.state == NSControlStateValueOn) {
            config_AddIntf("audioscrobbler");
        } else {
            config_RemoveIntf("audioscrobbler");
        }
        MacLCConfigPutPsz("lastfm-username", [_lastfmUserRow.textField.stringValue UTF8String]);
        MacLCConfigPutPsz("lastfm-password", [_lastfmPasswordRow.textField.stringValue UTF8String]);
    }

    self.hasUnsavedChanges = NO;
}

- (void)resetToDefaults
{
    module_config_t *item;
    if ((item = config_FindConfig("audio"))) MacLCConfigPutInt("audio", item->orig.i);
    if ((item = config_FindConfig("volume-save"))) MacLCConfigPutInt("volume-save", item->orig.i);
    if ((item = config_FindConfig("auhal-volume"))) MacLCConfigPutInt("auhal-volume", item->orig.i);
    if ((item = config_FindConfig("macosx-max-volume"))) MacLCConfigPutInt("macosx-max-volume", item->orig.i);
    if ((item = config_FindConfig("audio-language"))) MacLCConfigPutPsz("audio-language", item->orig.psz ? item->orig.psz : "");
    if ((item = config_FindConfig("audio-replay-gain-mode"))) MacLCConfigPutPsz("audio-replay-gain-mode", item->orig.psz ? item->orig.psz : "none");
    if ((item = config_FindConfig("norm-max-level"))) MacLCConfigPutFloat("norm-max-level", item->orig.f);
    if ((item = config_FindConfig("headphone-dim"))) MacLCConfigPutInt("headphone-dim", item->orig.i);
    if ((item = config_FindConfig("audio-visual"))) MacLCConfigPutPsz("audio-visual", item->orig.psz ? item->orig.psz : "");
    if ((item = config_FindConfig("audio-filter"))) MacLCConfigPutPsz("audio-filter", item->orig.psz ? item->orig.psz : "");

    if (_lastfmCard) {
        config_RemoveIntf("audioscrobbler");
        if ((item = config_FindConfig("lastfm-username"))) MacLCConfigPutPsz("lastfm-username", "");
        if ((item = config_FindConfig("lastfm-password"))) MacLCConfigPutPsz("lastfm-password", "");
    }

    [self loadSettings];
    self.hasUnsavedChanges = YES;
}

@end
