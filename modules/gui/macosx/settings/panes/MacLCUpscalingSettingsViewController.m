/*****************************************************************************
 * MacLCUpscalingSettingsViewController.m: Upscaling Settings Pane for MacLC
 *****************************************************************************
 * Copyright (C) 2026 Hazen Studio
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

#import "settings/panes/MacLCUpscalingSettingsViewController.h"
#import "settings/MacLCConfigSafe.h"
#import "settings/MacLCSettingsRow.h"
#import "theme/MacLCDesign.h"
#import "theme/MacLCCardView.h"
#import "upscale/MacLCUpscaling.h"
#import "upscale/MacLCUpscalingPanelViewController.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wnullability-completeness"
#import "extensions/NSString+Helpers.h"
#pragma clang diagnostic pop

#import <vlc_configuration.h>
#include "../../../../video_output/apple/maclc_upscale_vars.h"

@interface MacLCUpscalingSettingsViewController ()
{
    intf_thread_t *_p_intf;
}

@property (nonatomic, assign) BOOL hasUnsavedChanges;

@property (nonatomic, strong) MacLCSettingsRow *enabledRow;
@property (nonatomic, strong) MacLCSettingsRow *methodRow;
@property (nonatomic, strong) MacLCSettingsRow *sharpnessRow;
@property (nonatomic, strong) MacLCSettingsRow *targetRow;

@end

@implementation MacLCUpscalingSettingsViewController

- (instancetype)initWithIntf:(intf_thread_t *)intf
{
    self = [super initWithNibName:nil bundle:nil];
    if (self)
        _p_intf = intf;
    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder
{
    return [super initWithCoder:coder];
}

#pragma mark - MacLCSettingsPane Protocol Properties

- (NSString *)paneTitle { return _NS("Upscaling"); }
- (NSString *)paneSymbolName { return @"wand.and.stars"; }
- (NSString *)paneIdentifier { return @"video-upscaling"; }

- (NSArray<NSString *> *)searchKeywords
{
    return @[
        @"upscaling", @"upscale", @"super resolution", @"resolution", @"sharpness",
        @"sharpen", @"metalfx", @"neural", @"anime", @"anime4k", @"fsrcnnx",
        @"fsr", @"nis", @"lanczos", @"4k", @"1080p", @"1440p", @"output size",
        @MACLC_UPSCALE_VAR_ENABLED, @MACLC_UPSCALE_VAR_METHOD,
        @MACLC_UPSCALE_VAR_SHARPNESS, @MACLC_UPSCALE_VAR_TARGET
    ];
}

#pragma mark - View

- (void)loadView
{
    NSView *container = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 600, 480)];
    container.translatesAutoresizingMaskIntoConstraints = NO;
    self.view = container;

    NSStackView *rootStack = [[NSStackView alloc] init];
    rootStack.translatesAutoresizingMaskIntoConstraints = NO;
    rootStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    rootStack.alignment = NSLayoutAttributeLeading;
    rootStack.spacing = [MacLCDesign groupSpacing];
    [container addSubview:rootStack];

    const CGFloat margin = [MacLCDesign windowContentMargin];
    [NSLayoutConstraint activateConstraints:@[
        [rootStack.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:margin],
        [rootStack.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-margin],
        [rootStack.topAnchor constraintEqualToAnchor:container.topAnchor constant:margin],
        /* <= so a window taller than the pane does not stretch the card. */
        [rootStack.bottomAnchor constraintLessThanOrEqualToAnchor:container.bottomAnchor constant:-margin],
        [container.widthAnchor constraintGreaterThanOrEqualToConstant:480]
    ]];

    __weak typeof(self) weakSelf = self;

    MacLCCardView *card = [MacLCCardView cardViewWithTitle:_NS("Upscaling")];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    [rootStack addArrangedSubview:card];
    [card.trailingAnchor constraintEqualToAnchor:rootStack.trailingAnchor].active = YES;

    _enabledRow = [MacLCSettingsRow checkboxRowWithTitle:_NS("Upscale Videos Smaller Than the Window")
                                             explanation:_NS("Sharpens a video that is smaller than its window, so a DVD or a 720p stream looks closer to the screen it is shown on.")
                                                   state:NO
                                                  action:^(BOOL checked) {
        weakSelf.hasUnsavedChanges = YES;
        [weakSelf updateEnabledRows];
    }];
    _enabledRow.defaultHint = _NS("Default: Off");
    [card.contentStackView addArrangedSubview:_enabledRow];

    NSMutableArray<NSString *> *titles = [NSMutableArray array];
    NSMutableArray<NSNumber *> *tags = [NSMutableArray array];
    for (NSInteger m = 0; m < MACLC_UPSCALE_METHOD_COUNT; m++) {
        [titles addObject:[MacLCUpscalingPanelViewController titleForMethod:m]];
        [tags addObject:@(m)];
    }
    _methodRow = [MacLCSettingsRow popUpRowWithTitle:_NS("Method")
                                         explanation:@""
                                               items:titles
                                                tags:tags
                                       selectedIndex:0
                                              action:^(NSInteger selectedIndex, NSInteger tag) {
        weakSelf.hasUnsavedChanges = YES;
        [weakSelf updateEnabledRows];
    }];
    _methodRow.defaultHint = _NS("Default: Auto");
    /* Methods whose model is not downloaded stay greyed: the download, and
     * the FSRCNNX licence, are in the player's Upscaling panel. */
    _methodRow.popUpButton.autoenablesItems = NO;
    [card.contentStackView addArrangedSubview:_methodRow];

    _sharpnessRow = [MacLCSettingsRow sliderRowWithTitle:_NS("Sharpness")
                                             explanation:_NS("How hard Sharp and NIS sharpen edges. Other methods do not sharpen.")
                                                minValue:0
                                                maxValue:100
                                            initialValue:50
                                             valueFormat:@"%.0f"
                                                  action:^(double value) {
        weakSelf.hasUnsavedChanges = YES;
    }];
    _sharpnessRow.defaultHint = _NS("Default: 50");
    [card.contentStackView addArrangedSubview:_sharpnessRow];

    _targetRow = [MacLCSettingsRow popUpRowWithTitle:_NS("Output Size")
                                         explanation:_NS("Caps the size the picture is upscaled to. A smaller cap saves energy on a large display.")
                                               items:@[_NS("Window Size"), _NS("Up to 1080p"),
                                                        _NS("Up to 1440p"), _NS("Up to 4K")]
                                                tags:@[@0, @1080, @1440, @2160]
                                       selectedIndex:0
                                              action:^(NSInteger selectedIndex, NSInteger tag) {
        weakSelf.hasUnsavedChanges = YES;
    }];
    _targetRow.defaultHint = _NS("Default: Window Size");
    [card.contentStackView addArrangedSubview:_targetRow];

    NSButton *resetBtn = [NSButton buttonWithTitle:_NS("Reset Upscaling Settings")
                                            target:self
                                            action:@selector(resetToDefaults)];
    resetBtn.bezelStyle = NSBezelStyleRounded;
    [rootStack addArrangedSubview:resetBtn];

    [self loadSettings];
}

- (void)updateEnabledRows
{
    const BOOL on = _enabledRow.checkboxButton.state == NSControlStateValueOn;
    const NSInteger method = _methodRow.popUpButton.selectedTag;
    _methodRow.enabled = on;
    _methodRow.explanationLabel.stringValue = [MacLCUpscalingPanelViewController summaryForMethod:method];
    _sharpnessRow.enabled = on && (method == MACLC_UPSCALE_SHARP || method == MACLC_UPSCALE_NIS);
    _targetRow.enabled = on;
}

#pragma mark - Settings Operations

- (void)loadSettings
{
    if (!self.viewLoaded)
        return;
    for (NSMenuItem *item in _methodRow.popUpButton.itemArray)
        item.enabled = [MacLCUpscalingPanelViewController isMethodAvailable:item.tag];

    _enabledRow.checkboxButton.state = MacLCUpscaling.enabled ? NSControlStateValueOn : NSControlStateValueOff;
    [_methodRow.popUpButton selectItemWithTag:MacLCUpscaling.method];
    _sharpnessRow.slider.integerValue = MacLCUpscaling.sharpness;
    _sharpnessRow.sliderReadoutLabel.stringValue = [NSString stringWithFormat:@"%ld", (long)MacLCUpscaling.sharpness];
    if (![_targetRow.popUpButton selectItemWithTag:MacLCUpscaling.target])
        [_targetRow.popUpButton selectItemWithTag:0];
    [self updateEnabledRows];
    self.hasUnsavedChanges = NO;
}

- (void)paneDidAppear
{
    /* The player's panel may have changed them, or finished a download. */
    if (!self.hasUnsavedChanges)
        [self loadSettings];
}

- (void)applyChanges
{
    /* The MacLCUpscaling setters also push each value to the playing video. */
    const BOOL on = _enabledRow.checkboxButton.state == NSControlStateValueOn;
    if (MacLCUpscaling.method != _methodRow.popUpButton.selectedTag)
        MacLCUpscaling.method = _methodRow.popUpButton.selectedTag;
    if (MacLCUpscaling.sharpness != _sharpnessRow.slider.integerValue)
        MacLCUpscaling.sharpness = _sharpnessRow.slider.integerValue;
    if (MacLCUpscaling.target != _targetRow.popUpButton.selectedTag)
        MacLCUpscaling.target = _targetRow.popUpButton.selectedTag;
    if (MacLCUpscaling.enabled != on)
        MacLCUpscaling.enabled = on;
    self.hasUnsavedChanges = NO;
}

- (void)resetToDefaults
{
    module_config_t *item;
    _enabledRow.checkboxButton.state = (item = config_FindConfig(MACLC_UPSCALE_VAR_ENABLED)) && item->orig.i
        ? NSControlStateValueOn : NSControlStateValueOff;
    [_methodRow.popUpButton selectItemWithTag:(item = config_FindConfig(MACLC_UPSCALE_VAR_METHOD))
        ? maclc_upscale_parse_method(item->orig.psz) : MACLC_UPSCALE_AUTO];
    _sharpnessRow.slider.integerValue = (item = config_FindConfig(MACLC_UPSCALE_VAR_SHARPNESS)) ? item->orig.i : 50;
    _sharpnessRow.sliderReadoutLabel.stringValue = [NSString stringWithFormat:@"%ld", (long)_sharpnessRow.slider.integerValue];
    [_targetRow.popUpButton selectItemWithTag:(item = config_FindConfig(MACLC_UPSCALE_VAR_TARGET)) ? item->orig.i : 0];
    [self updateEnabledRows];
    self.hasUnsavedChanges = YES;
}

@end
