/*****************************************************************************
 * MacLCPlaybackSettingsViewController.m: Playback Settings Pane for MacLC
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

#import "settings/panes/MacLCPlaybackSettingsViewController.h"
#import "settings/MacLCConfigSafe.h"
#import "settings/MacLCSettingsRow.h"
#import "theme/MacLCDesign.h"
#import "theme/MacLCCardView.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wnullability-completeness"
#import "extensions/NSString+Helpers.h"
#pragma clang diagnostic pop

#import <vlc_configuration.h>

@interface MacLCPlaybackSettingsViewController ()
{
    intf_thread_t *_p_intf;
}

@property (nonatomic, assign) BOOL hasUnsavedChanges;

// Rows
@property (nonatomic, strong) MacLCSettingsRow *rateRow;
@property (nonatomic, strong) MacLCSettingsRow *fastSeekRow;
@property (nonatomic, strong) MacLCSettingsRow *autostartRow;

@property (nonatomic, strong) MacLCSettingsRow *loopRow;
@property (nonatomic, strong) MacLCSettingsRow *repeatRow;
@property (nonatomic, strong) MacLCSettingsRow *randomRow;

@property (nonatomic, strong) MacLCSettingsRow *extraShortJumpRow;
@property (nonatomic, strong) MacLCSettingsRow *shortJumpRow;
@property (nonatomic, strong) MacLCSettingsRow *mediumJumpRow;
@property (nonatomic, strong) MacLCSettingsRow *longJumpRow;

@property (nonatomic, strong) MacLCCardView *advancedCard;
@property (nonatomic, strong) NSButton *advancedDisclosureButton;
@property (nonatomic, strong) MacLCSettingsRow *hardwareDecRow;
@property (nonatomic, strong) MacLCSettingsRow *aviIndexRow;
@property (nonatomic, strong) MacLCSettingsRow *skipLoopRow;

@end

@implementation MacLCPlaybackSettingsViewController

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
    return _NS("Playback");
}

- (NSString *)paneSymbolName
{
    return @"play.circle";
}

- (NSString *)paneIdentifier
{
    return @"playback";
}

- (NSArray<NSString *> *)searchKeywords
{
    return @[
        @"playback", @"speed", @"rate", @"seek", @"fast seek", @"autostart",
        @"repeat", @"loop", @"shuffle", @"random", @"jump", @"skip",
        @"seconds", @"hardware decoding", @"videotoolbox", @"avi", @"index",
        @"in-loop filter", @"deblock",
        @"rate", @"input-fast-seek", @"playlist-autostart", @"loop", @"repeat",
        @"random", @"extrashort-jump-size", @"short-jump-size", @"medium-jump-size",
        @"long-jump-size", @"videotoolbox-hw-decoder-only", @"avi-index",
        @"avcodec-skiploopfilter"
    ];
}

#pragma mark - View Lifecycle & Layout

- (void)loadView
{
    NSView *container = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 600, 950)];
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

    // Card 1: Playback Behavior
    MacLCCardView *behaviorCard = [MacLCCardView cardViewWithTitle:_NS("Playback Behavior")];
    behaviorCard.translatesAutoresizingMaskIntoConstraints = NO;
    [rootStack addArrangedSubview:behaviorCard];
    [behaviorCard.trailingAnchor constraintEqualToAnchor:rootStack.trailingAnchor].active = YES;

    _rateRow = [MacLCSettingsRow stepperRowWithTitle:_NS("Default Playback Speed")
                                         explanation:_NS("Set the initial playback speed for newly opened media files.")
                                            minValue:0.25
                                            maxValue:4.0
                                        initialValue:1.0
                                           stepValue:0.25
                                         valueFormat:@"%.2fx"
                                              action:^(double value) {
        weakSelf.hasUnsavedChanges = YES;
    }];
    _rateRow.defaultHint = _NS("Default: 1.00x");
    [behaviorCard.contentStackView addArrangedSubview:_rateRow];

    _fastSeekRow = [MacLCSettingsRow checkboxRowWithTitle:_NS("Fast Keyframe Seeking")
                                              explanation:_NS("Jump directly to keyframes when scrubbing for immediate response.")
                                                    state:NO
                                                   action:^(BOOL checked) {
        weakSelf.hasUnsavedChanges = YES;
    }];
    _fastSeekRow.defaultHint = _NS("Default: Off");
    [behaviorCard.contentStackView addArrangedSubview:_fastSeekRow];

    _autostartRow = [MacLCSettingsRow checkboxRowWithTitle:_NS("Auto-Start Playlist Items")
                                               explanation:_NS("Automatically begin playback as soon as media items are added.")
                                                     state:YES
                                                    action:^(BOOL checked) {
        weakSelf.hasUnsavedChanges = YES;
    }];
    _autostartRow.defaultHint = _NS("Default: On");
    [behaviorCard.contentStackView addArrangedSubview:_autostartRow];

    // Card 2: Repeat & Shuffle Defaults
    MacLCCardView *repeatCard = [MacLCCardView cardViewWithTitle:_NS("Repeat & Shuffle Defaults")];
    repeatCard.translatesAutoresizingMaskIntoConstraints = NO;
    [rootStack addArrangedSubview:repeatCard];
    [repeatCard.trailingAnchor constraintEqualToAnchor:rootStack.trailingAnchor].active = YES;

    _loopRow = [MacLCSettingsRow checkboxRowWithTitle:_NS("Repeat Playlist")
                                          explanation:_NS("Restart playback from the beginning when the last playlist item finishes.")
                                                state:NO
                                               action:^(BOOL checked) {
        weakSelf.hasUnsavedChanges = YES;
    }];
    _loopRow.defaultHint = _NS("Default: Off");
    [repeatCard.contentStackView addArrangedSubview:_loopRow];

    _repeatRow = [MacLCSettingsRow checkboxRowWithTitle:_NS("Repeat Current Item")
                                            explanation:_NS("Continuously loop the currently playing video or audio track.")
                                                  state:NO
                                                 action:^(BOOL checked) {
        weakSelf.hasUnsavedChanges = YES;
    }];
    _repeatRow.defaultHint = _NS("Default: Off");
    [repeatCard.contentStackView addArrangedSubview:_repeatRow];

    _randomRow = [MacLCSettingsRow checkboxRowWithTitle:_NS("Shuffle Playback")
                                            explanation:_NS("Play playlist tracks in randomized sequence by default.")
                                                  state:NO
                                                 action:^(BOOL checked) {
        weakSelf.hasUnsavedChanges = YES;
    }];
    _randomRow.defaultHint = _NS("Default: Off");
    [repeatCard.contentStackView addArrangedSubview:_randomRow];

    // Card 3: Skip & Jump Amounts
    MacLCCardView *skipCard = [MacLCCardView cardViewWithTitle:_NS("Skip & Jump Amounts")];
    skipCard.translatesAutoresizingMaskIntoConstraints = NO;
    [rootStack addArrangedSubview:skipCard];
    [skipCard.trailingAnchor constraintEqualToAnchor:rootStack.trailingAnchor].active = YES;

    _extraShortJumpRow = [MacLCSettingsRow stepperRowWithTitle:_NS("Extra-Short Jump")
                                                   explanation:_NS("Number of seconds to skip forward or backward on extra-short jumps.")
                                                      minValue:1
                                                      maxValue:30
                                                  initialValue:3
                                                     stepValue:1
                                                   valueFormat:@"%.0f s"
                                                        action:^(double value) {
        weakSelf.hasUnsavedChanges = YES;
    }];
    _extraShortJumpRow.defaultHint = _NS("Default: 3 s");
    [skipCard.contentStackView addArrangedSubview:_extraShortJumpRow];

    _shortJumpRow = [MacLCSettingsRow stepperRowWithTitle:_NS("Short Jump")
                                              explanation:_NS("Number of seconds to skip forward or backward on short jumps.")
                                                 minValue:1
                                                 maxValue:60
                                             initialValue:10
                                                stepValue:1
                                              valueFormat:@"%.0f s"
                                                   action:^(double value) {
        weakSelf.hasUnsavedChanges = YES;
    }];
    _shortJumpRow.defaultHint = _NS("Default: 10 s");
    [skipCard.contentStackView addArrangedSubview:_shortJumpRow];

    _mediumJumpRow = [MacLCSettingsRow stepperRowWithTitle:_NS("Medium Jump")
                                               explanation:_NS("Number of seconds to skip forward or backward on medium jumps.")
                                                  minValue:5
                                                  maxValue:300
                                              initialValue:60
                                                 stepValue:5
                                               valueFormat:@"%.0f s"
                                                    action:^(double value) {
        weakSelf.hasUnsavedChanges = YES;
    }];
    _mediumJumpRow.defaultHint = _NS("Default: 60 s");
    [skipCard.contentStackView addArrangedSubview:_mediumJumpRow];

    _longJumpRow = [MacLCSettingsRow stepperRowWithTitle:_NS("Long Jump")
                                             explanation:_NS("Number of seconds to skip forward or backward on long jumps.")
                                                minValue:30
                                                maxValue:1800
                                            initialValue:300
                                               stepValue:30
                                             valueFormat:@"%.0f s"
                                                  action:^(double value) {
        weakSelf.hasUnsavedChanges = YES;
    }];
    _longJumpRow.defaultHint = _NS("Default: 300 s");
    [skipCard.contentStackView addArrangedSubview:_longJumpRow];

    // Card 4: Advanced Hardware Decoding (collapsed disclosure)
    _advancedDisclosureButton = [NSButton buttonWithTitle:_NS("Advanced Playback & Hardware Decoding ▶")
                                                   target:self
                                                   action:@selector(toggleAdvancedAction:)];
    _advancedDisclosureButton.bezelStyle = NSBezelStyleInline;
    [rootStack addArrangedSubview:_advancedDisclosureButton];

    _advancedCard = [MacLCCardView cardViewWithTitle:_NS("Hardware & Codecs (Advanced)")];
    _advancedCard.translatesAutoresizingMaskIntoConstraints = NO;
    _advancedCard.hidden = YES;
    [rootStack addArrangedSubview:_advancedCard];
    [_advancedCard.trailingAnchor constraintEqualToAnchor:rootStack.trailingAnchor].active = YES;

    _hardwareDecRow = [MacLCSettingsRow checkboxRowWithTitle:_NS("Require Hardware Acceleration")
                                                 explanation:_NS("Use Apple VideoToolbox hardware decoding for smoother video and reduced battery usage.")
                                                       state:YES
                                                      action:^(BOOL checked) {
        weakSelf.hasUnsavedChanges = YES;
    }];
    _hardwareDecRow.defaultHint = _NS("Default: On");
    [_advancedCard.contentStackView addArrangedSubview:_hardwareDecRow];

    _aviIndexRow = [MacLCSettingsRow popUpRowWithTitle:_NS("Repair Broken AVI Files")
                                           explanation:_NS("Automatically rebuild damaged index blocks when opening AVI files.")
                                                 items:@[_NS("Ask"), _NS("Always Fix"), _NS("Never Fix")]
                                                  tags:@[@0, @1, @2]
                                         selectedIndex:0
                                                action:^(NSInteger selectedIndex, NSInteger tag) {
        weakSelf.hasUnsavedChanges = YES;
    }];
    _aviIndexRow.defaultHint = _NS("Default: Ask");
    [_advancedCard.contentStackView addArrangedSubview:_aviIndexRow];

    _skipLoopRow = [MacLCSettingsRow popUpRowWithTitle:_NS("Skip In-Loop Deblocking Filter")
                                           explanation:_NS("Skip H.264/HEVC deblocking filter stages on slow systems; may introduce blocky artifacts.")
                                                 items:@[_NS("None"), _NS("Non-Reference"), _NS("Bidirectional"), _NS("Non-Key"), _NS("All")]
                                                  tags:@[@0, @1, @2, @3, @4]
                                         selectedIndex:0
                                                action:^(NSInteger selectedIndex, NSInteger tag) {
        weakSelf.hasUnsavedChanges = YES;
    }];
    _skipLoopRow.warning = YES;
    _skipLoopRow.defaultHint = _NS("Default: None");
    [_advancedCard.contentStackView addArrangedSubview:_skipLoopRow];

    // Reset button
    NSButton *resetBtn = [NSButton buttonWithTitle:_NS("Reset Playback Settings…")
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
    _advancedDisclosureButton.title = isHidden ? _NS("Advanced Playback & Hardware Decoding ▶")
                                               : _NS("Advanced Playback & Hardware Decoding ▼");
}

- (void)resetSectionAction:(id)sender
{
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = _NS("Reset Playback Settings");
    alert.informativeText = _NS("Are you sure you want to reset all Playback options to their default values?");
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
    // Rate
    float rate = MacLCConfigGetFloat("rate", 0.0f);
    if (rate <= 0.0f) rate = 1.0f;
    _rateRow.stepper.doubleValue = rate;
    _rateRow.sliderReadoutLabel.stringValue = [NSString stringWithFormat:@"%.2fx", rate];

    // Fast seek
    _fastSeekRow.checkboxButton.state = MacLCConfigGetInt("input-fast-seek", 0) ? NSControlStateValueOn : NSControlStateValueOff;

    // Autostart
    _autostartRow.checkboxButton.state = MacLCConfigGetInt("playlist-autostart", 0) ? NSControlStateValueOn : NSControlStateValueOff;

    // Loop & Repeat & Random
    _loopRow.checkboxButton.state = MacLCConfigGetInt("loop", 0) ? NSControlStateValueOn : NSControlStateValueOff;
    _repeatRow.checkboxButton.state = MacLCConfigGetInt("repeat", 0) ? NSControlStateValueOn : NSControlStateValueOff;
    _randomRow.checkboxButton.state = MacLCConfigGetInt("random", 0) ? NSControlStateValueOn : NSControlStateValueOff;

    // Jump sizes
    _extraShortJumpRow.stepper.doubleValue = MacLCConfigGetInt("extrashort-jump-size", 0);
    _extraShortJumpRow.sliderReadoutLabel.stringValue = [NSString stringWithFormat:@"%.0f s", _extraShortJumpRow.stepper.doubleValue];

    _shortJumpRow.stepper.doubleValue = MacLCConfigGetInt("short-jump-size", 0);
    _shortJumpRow.sliderReadoutLabel.stringValue = [NSString stringWithFormat:@"%.0f s", _shortJumpRow.stepper.doubleValue];

    _mediumJumpRow.stepper.doubleValue = MacLCConfigGetInt("medium-jump-size", 0);
    _mediumJumpRow.sliderReadoutLabel.stringValue = [NSString stringWithFormat:@"%.0f s", _mediumJumpRow.stepper.doubleValue];

    _longJumpRow.stepper.doubleValue = MacLCConfigGetInt("long-jump-size", 0);
    _longJumpRow.sliderReadoutLabel.stringValue = [NSString stringWithFormat:@"%.0f s", _longJumpRow.stepper.doubleValue];

    // Advanced options
    _hardwareDecRow.checkboxButton.state = MacLCConfigGetInt("videotoolbox-hw-decoder-only", 0) ? NSControlStateValueOn : NSControlStateValueOff;
    [_aviIndexRow.popUpButton selectItemWithTag:MacLCConfigGetInt("avi-index", 0)];
    [_skipLoopRow.popUpButton selectItemWithTag:MacLCConfigGetInt("avcodec-skiploopfilter", 0)];

    self.hasUnsavedChanges = NO;
}

- (void)applyChanges
{
    MacLCConfigPutFloat("rate", (float)_rateRow.stepper.doubleValue);
    MacLCConfigPutInt("input-fast-seek", _fastSeekRow.checkboxButton.state == NSControlStateValueOn);
    MacLCConfigPutInt("playlist-autostart", _autostartRow.checkboxButton.state == NSControlStateValueOn);

    MacLCConfigPutInt("loop", _loopRow.checkboxButton.state == NSControlStateValueOn);
    MacLCConfigPutInt("repeat", _repeatRow.checkboxButton.state == NSControlStateValueOn);
    MacLCConfigPutInt("random", _randomRow.checkboxButton.state == NSControlStateValueOn);

    MacLCConfigPutInt("extrashort-jump-size", (int)_extraShortJumpRow.stepper.doubleValue);
    MacLCConfigPutInt("short-jump-size", (int)_shortJumpRow.stepper.doubleValue);
    MacLCConfigPutInt("medium-jump-size", (int)_mediumJumpRow.stepper.doubleValue);
    MacLCConfigPutInt("long-jump-size", (int)_longJumpRow.stepper.doubleValue);

    MacLCConfigPutInt("videotoolbox-hw-decoder-only", _hardwareDecRow.checkboxButton.state == NSControlStateValueOn);
    MacLCConfigPutInt("avi-index", _aviIndexRow.popUpButton.selectedTag);
    MacLCConfigPutInt("avcodec-skiploopfilter", _skipLoopRow.popUpButton.selectedTag);

    self.hasUnsavedChanges = NO;
}

- (void)resetToDefaults
{
    module_config_t *item;
    if ((item = config_FindConfig("rate"))) MacLCConfigPutFloat("rate", item->orig.f);
    if ((item = config_FindConfig("input-fast-seek"))) MacLCConfigPutInt("input-fast-seek", item->orig.i);
    if ((item = config_FindConfig("playlist-autostart"))) MacLCConfigPutInt("playlist-autostart", item->orig.i);
    if ((item = config_FindConfig("loop"))) MacLCConfigPutInt("loop", item->orig.i);
    if ((item = config_FindConfig("repeat"))) MacLCConfigPutInt("repeat", item->orig.i);
    if ((item = config_FindConfig("random"))) MacLCConfigPutInt("random", item->orig.i);
    if ((item = config_FindConfig("extrashort-jump-size"))) MacLCConfigPutInt("extrashort-jump-size", item->orig.i);
    if ((item = config_FindConfig("short-jump-size"))) MacLCConfigPutInt("short-jump-size", item->orig.i);
    if ((item = config_FindConfig("medium-jump-size"))) MacLCConfigPutInt("medium-jump-size", item->orig.i);
    if ((item = config_FindConfig("long-jump-size"))) MacLCConfigPutInt("long-jump-size", item->orig.i);
    if ((item = config_FindConfig("videotoolbox-hw-decoder-only"))) MacLCConfigPutInt("videotoolbox-hw-decoder-only", item->orig.i);
    if ((item = config_FindConfig("avi-index"))) MacLCConfigPutInt("avi-index", item->orig.i);
    if ((item = config_FindConfig("avcodec-skiploopfilter"))) MacLCConfigPutInt("avcodec-skiploopfilter", item->orig.i);

    [self loadSettings];
    self.hasUnsavedChanges = YES;
}

@end
