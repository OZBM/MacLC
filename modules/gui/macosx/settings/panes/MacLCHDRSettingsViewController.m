/*****************************************************************************
 * MacLCHDRSettingsViewController.m: HDR & Colour settings pane for MacLC
 *****************************************************************************
 * Copyright (C) 2026 VLC authors and VideoLAN
 *
 * Authors: MacLC Team
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

#import "settings/panes/MacLCHDRSettingsViewController.h"

#import "theme/MacLCDesign.h"
#import "theme/MacLCCardView.h"
#import "extensions/NSString+Helpers.h"

#import "main/VLCMain.h"
#import "playqueue/VLCPlayQueueController.h"
#import "playqueue/VLCPlayerController.h"
#import "library/VLCInputItem.h"
#import "windows/video/VLCVideoOutputProvider.h"
#import "windows/video/VLCVideoWindowCommon.h"
#import "windows/video/VLCVoutView.h"
#import "windows/video/VLCMainVideoViewController.h"

#import <AVFoundation/AVFoundation.h>
#import <QuartzCore/QuartzCore.h>

#include <vlc_common.h>
#include <vlc_configuration.h>
#include <vlc_interface.h>
#include <vlc_input_item.h>
#include <vlc_es.h>

#define SDR_NOMINAL_WHITE_NITS 100.0f

#pragma mark - Helper Row View

@interface MacLCSettingsRowView : NSView

@property (nonatomic, readonly) NSTextField *titleLabel;
@property (nonatomic, readonly) NSTextField *explanationLabel;
@property (nonatomic, readonly) NSView *controlView;
@property (nonatomic, readonly) BOOL isRisky;
@property (nonatomic, assign) BOOL isEngineSpecific;

- (instancetype)initWithTitle:(NSString *)title
                  explanation:(NSString *)explanation
                      control:(NSView *)control
                      isRisky:(BOOL)isRisky;

- (void)setRowEnabled:(BOOL)enabled;

@end

@implementation MacLCSettingsRowView {
    NSImageView *_warningImageView;
}

- (instancetype)initWithTitle:(NSString *)title
                  explanation:(NSString *)explanation
                      control:(NSView *)control
                      isRisky:(BOOL)isRisky
{
    self = [super initWithFrame:NSZeroRect];
    if (self) {
        _isRisky = isRisky;
        _controlView = control;
        self.translatesAutoresizingMaskIntoConstraints = NO;

        _titleLabel = [NSTextField labelWithString:title];
        _titleLabel.font = MacLCDesign.bodyEmphasized;
        _titleLabel.textColor = MacLCDesign.primaryLabel;
        _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [_titleLabel setContentHuggingPriority:NSLayoutPriorityDefaultHigh forOrientation:NSLayoutConstraintOrientationHorizontal];

        _explanationLabel = [NSTextField wrappingLabelWithString:explanation];
        _explanationLabel.font = MacLCDesign.caption;
        _explanationLabel.textColor = MacLCDesign.secondaryLabel;
        _explanationLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _explanationLabel.accessibilityRole = NSAccessibilityStaticTextRole;
        [_explanationLabel setContentCompressionResistancePriority:NSLayoutPriorityFittingSizeCompression forOrientation:NSLayoutConstraintOrientationHorizontal];

        control.translatesAutoresizingMaskIntoConstraints = NO;
        [control setAccessibilityLabel:title];
        [control setAccessibilityHelp:explanation];

        [self addSubview:_titleLabel];
        [self addSubview:_explanationLabel];
        [self addSubview:control];

        if (isRisky) {
            _warningImageView = [[NSImageView alloc] initWithFrame:NSZeroRect];
            _warningImageView.translatesAutoresizingMaskIntoConstraints = NO;
            _warningImageView.image = [MacLCDesign symbolNamed:@"exclamationmark.triangle.fill"
                                                     pointSize:14
                                                        weight:NSFontWeightMedium
                                            accessibilityLabel:_NS("Warning")];
            _warningImageView.contentTintColor = MacLCDesign.warning;
            [self addSubview:_warningImageView];

            [NSLayoutConstraint activateConstraints:@[
                [_warningImageView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
                [_warningImageView.centerYAnchor constraintEqualToAnchor:_titleLabel.centerYAnchor],
                [_warningImageView.widthAnchor constraintEqualToConstant:16],
                [_warningImageView.heightAnchor constraintEqualToConstant:16],
                [_titleLabel.leadingAnchor constraintEqualToAnchor:_warningImageView.trailingAnchor constant:MacLCDesign.spacingXS]
            ]];
        } else {
            [NSLayoutConstraint activateConstraints:@[
                [_titleLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor]
            ]];
        }

        [NSLayoutConstraint activateConstraints:@[
            [_titleLabel.topAnchor constraintEqualToAnchor:self.topAnchor],
            [control.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [control.centerYAnchor constraintEqualToAnchor:_titleLabel.centerYAnchor],
            [control.leadingAnchor constraintGreaterThanOrEqualToAnchor:_titleLabel.trailingAnchor constant:MacLCDesign.spacingM],

            [_explanationLabel.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor constant:MacLCDesign.spacingXS],
            [_explanationLabel.leadingAnchor constraintEqualToAnchor:_titleLabel.leadingAnchor],
            [_explanationLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [_explanationLabel.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],

            [self.heightAnchor constraintGreaterThanOrEqualToConstant:MacLCDesign.rowMinimumHeight]
        ]];
    }
    return self;
}

- (void)setRowEnabled:(BOOL)enabled
{
    if ([_controlView isKindOfClass:[NSControl class]]) {
        ((NSControl *)_controlView).enabled = enabled;
    }
    _titleLabel.textColor = enabled ? MacLCDesign.primaryLabel : MacLCDesign.tertiaryLabel;
    _explanationLabel.textColor = enabled ? MacLCDesign.secondaryLabel : MacLCDesign.tertiaryLabel;
    if (_warningImageView) {
        _warningImageView.alphaValue = enabled ? 1.0 : 0.4;
    }
}

@end

#pragma mark - Telemetry Status Row

@interface MacLCStatusRowView : NSView

@property (nonatomic, readonly) NSTextField *titleLabel;
@property (nonatomic, readonly) NSTextField *valueLabel;

- (instancetype)initWithTitle:(NSString *)title initialValue:(NSString *)initialValue;
- (void)setValue:(NSString *)value;

@end

@implementation MacLCStatusRowView

- (instancetype)initWithTitle:(NSString *)title initialValue:(NSString *)initialValue
{
    self = [super initWithFrame:NSZeroRect];
    if (self) {
        self.translatesAutoresizingMaskIntoConstraints = NO;

        _titleLabel = [NSTextField labelWithString:title];
        _titleLabel.font = MacLCDesign.caption;
        _titleLabel.textColor = MacLCDesign.secondaryLabel;
        _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;

        _valueLabel = [NSTextField wrappingLabelWithString:initialValue];
        _valueLabel.font = MacLCDesign.bodyEmphasized;
        _valueLabel.textColor = MacLCDesign.primaryLabel;
        _valueLabel.translatesAutoresizingMaskIntoConstraints = NO;

        [self addSubview:_titleLabel];
        [self addSubview:_valueLabel];

        [NSLayoutConstraint activateConstraints:@[
            [_titleLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [_titleLabel.topAnchor constraintEqualToAnchor:self.topAnchor],
            [_titleLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],

            [_valueLabel.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor constant:MacLCDesign.spacingXXS],
            [_valueLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [_valueLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [_valueLabel.bottomAnchor constraintEqualToAnchor:self.bottomAnchor]
        ]];
    }
    return self;
}

- (void)setValue:(NSString *)value
{
    _valueLabel.stringValue = value;
}

@end

#pragma mark - Main View Controller

@implementation MacLCHDRSettingsViewController {
    intf_thread_t *_p_intf;
    BOOL _observingNotifications;
    BOOL _hasUnsavedChanges;

    // Root Stack
    NSStackView *_mainStackView;

    // Status Card Views
    MacLCStatusRowView *_statusDisplayRow;
    MacLCStatusRowView *_statusHeadroomRow;
    MacLCStatusRowView *_statusEngineRow;
    MacLCStatusRowView *_statusPlaybackRow;

    // Primary Control (macosx-hdr-mode)
    NSArray<NSButton *> *_hdrModeRadioButtons;
    NSInteger _currentHdrMode;

    // Brightness Headroom (macosx-edr-headroom)
    NSButton *_headroomAutoCheckbox;
    NSSlider *_headroomSlider;
    NSTextField *_headroomValueLabel;
    NSTextField *_headroomDisplayCapabilityLabel;
    float _currentHeadroom;

    // Advanced Disclosure
    NSButton *_advancedDisclosureButton;
    NSStackView *_advancedStackView;
    BOOL _advancedExpanded;

    // Picture Processing Controls
    NSPopUpButton *_toneMappingPopup;
    NSSlider *_toneMappingParamSlider;
    NSTextField *_toneMappingParamLabel;
    NSPopUpButton *_gamutMappingPopup;
    NSButton *_inverseToneMappingCheckbox;

    // Sharpness & Smoothing Controls
    NSPopUpButton *_upscalerPopup;
    NSPopUpButton *_downscalerPopup;
    NSPopUpButton *_ditherPopup;

    // Video Engine Controls
    NSPopUpButton *_voutPopup;
    NSButton *_legacyFallbackCheckbox;

    // Decoding Controls
    NSButton *_hwDecodeOnlyCheckbox;
    NSPopUpButton *_cvpxChromaPopup;

    // All engine-specific row views
    NSMutableArray<MacLCSettingsRowView *> *_openGLEngineRows;
}

- (instancetype)initWithIntf:(intf_thread_t *)intf
{
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _p_intf = intf;
        _hasUnsavedChanges = NO;
        _advancedExpanded = NO;
        _openGLEngineRows = [[NSMutableArray alloc] init];
    }
    return self;
}

- (void)dealloc
{
    [self stopObserving];
}

- (void)loadView
{
    NSView *rootView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 520, 900)];
    rootView.translatesAutoresizingMaskIntoConstraints = NO;

    _mainStackView = [[NSStackView alloc] init];
    _mainStackView.orientation = NSUserInterfaceLayoutOrientationVertical;
    _mainStackView.alignment = NSLayoutAttributeLeading;
    _mainStackView.spacing = MacLCDesign.groupSpacing;
    _mainStackView.translatesAutoresizingMaskIntoConstraints = NO;
    _mainStackView.edgeInsets = NSEdgeInsetsMake(MacLCDesign.windowContentMargin,
                                                 MacLCDesign.windowContentMargin,
                                                 MacLCDesign.windowContentMargin,
                                                 MacLCDesign.windowContentMargin);

    [rootView addSubview:_mainStackView];

    [NSLayoutConstraint activateConstraints:@[
        [_mainStackView.topAnchor constraintEqualToAnchor:rootView.topAnchor],
        [_mainStackView.leadingAnchor constraintEqualToAnchor:rootView.leadingAnchor],
        [_mainStackView.trailingAnchor constraintEqualToAnchor:rootView.trailingAnchor],
        [_mainStackView.bottomAnchor constraintEqualToAnchor:rootView.bottomAnchor],
        [rootView.widthAnchor constraintGreaterThanOrEqualToConstant:480]
    ]];

    [self buildStatusCard];
    [self buildPrimaryControlCard];
    [self buildHeadroomCard];
    [self buildAdvancedSection];
    [self buildFooter];

    self.view = rootView;

    [self loadSettings];
    [self refreshLiveStatus];
    [self updateEngineDependentRowsState];
}

#pragma mark - MacLCSettingsPane Protocol

- (NSString *)paneTitle
{
    return _NS("HDR & Colour");
}

- (NSString *)paneSymbolName
{
    return @"sun.max.fill";
}

- (NSString *)paneIdentifier
{
    return @"video-hdr";
}

- (NSArray<NSString *> *)searchKeywords
{
    return @[
        @"hdr", @"edr", @"high dynamic range", @"xdr", @"brightness",
        @"headroom", @"nits", @"tone mapping", @"gamut", @"bt.2020",
        @"bt.2390", @"hable", @"reinhard", @"upscaler", @"downscaler",
        @"lanczos", @"spline", @"dither", @"videotoolbox", @"hardware decoding",
        @"cvpx", @"p010", @"bgra", @"sdr", @"hlg", @"dolby vision",
        @"samplebufferdisplay", @"caopengllayer",
        @"macosx-hdr-mode", @"macosx-edr-headroom", @"force-darwin-legacy-display",
        @"gl-tone-mapping-function", @"gl-tone-mapping-param", @"gl-gamut-mapping",
        @"gl-inverse-tone-mapping", @"gl-upscaler", @"gl-downscaler",
        @"dither-algo", @"vout", @"videotoolbox-hw-decoder-only",
        @"videotoolbox-cvpx-chroma"
    ];
}

- (BOOL)hasUnsavedChanges
{
    return _hasUnsavedChanges;
}

- (void)paneDidAppear
{
    [self startObserving];
    [self refreshLiveStatus];
}

- (void)paneDidDisappear
{
    [self stopObserving];
}

#pragma mark - Load / Apply / Reset

- (void)loadSettings
{
    /* Primary mode */
    _currentHdrMode = config_GetInt("macosx-hdr-mode");
    if (_currentHdrMode < 0 || _currentHdrMode > 3) {
        _currentHdrMode = 0;
    }
    for (NSButton *btn in _hdrModeRadioButtons) {
        btn.state = (btn.tag == _currentHdrMode) ? NSControlStateValueOn : NSControlStateValueOff;
    }

    /* Headroom */
    _currentHeadroom = config_GetFloat("macosx-edr-headroom");
    [self updateHeadroomControlsWithVal:_currentHeadroom];

    /* Picture processing */
    [_toneMappingPopup selectItemWithTag:config_GetInt("gl-tone-mapping-function")];
    float param = config_GetFloat("gl-tone-mapping-param");
    _toneMappingParamSlider.floatValue = param;
    _toneMappingParamLabel.stringValue = (param == 0.0f) ? _NS("0.0 (Optimal default)") : [NSString stringWithFormat:@"%.2f", param];
    [_gamutMappingPopup selectItemWithTag:config_GetInt("gl-gamut-mapping")];
    _inverseToneMappingCheckbox.state = config_GetInt("gl-inverse-tone-mapping") ? NSControlStateValueOn : NSControlStateValueOff;

    /* Sharpness and smoothing */
    [_upscalerPopup selectItemWithTag:config_GetInt("gl-upscaler")];
    [_downscalerPopup selectItemWithTag:config_GetInt("gl-downscaler")];
    [_ditherPopup selectItemWithTag:config_GetInt("dither-algo")];

    /* Video engine */
    char *psz_vout = config_GetPsz("vout");
    if (psz_vout && strlen(psz_vout) > 0) {
        [_voutPopup selectItemWithTag:[self tagForVoutString:[NSString stringWithUTF8String:psz_vout]]];
    } else {
        [_voutPopup selectItemWithTag:0]; /* "any" */
    }
    free(psz_vout);

    _legacyFallbackCheckbox.state = config_GetInt("force-darwin-legacy-display") ? NSControlStateValueOn : NSControlStateValueOff;

    /* Decoding */
    _hwDecodeOnlyCheckbox.state = config_GetInt("videotoolbox-hw-decoder-only") ? NSControlStateValueOn : NSControlStateValueOff;
    char *psz_chroma = config_GetPsz("videotoolbox-cvpx-chroma");
    if (psz_chroma && strlen(psz_chroma) > 0) {
        [_cvpxChromaPopup selectItemWithTag:[self tagForChromaString:[NSString stringWithUTF8String:psz_chroma]]];
    } else {
        [_cvpxChromaPopup selectItemWithTag:0];
    }
    free(psz_chroma);

    _hasUnsavedChanges = NO;
    [self updateEngineDependentRowsState];
}

- (void)applyChanges
{
    /* Primary */
    config_PutInt("macosx-hdr-mode", _currentHdrMode);

    /* Headroom */
    config_PutFloat("macosx-edr-headroom", _currentHeadroom);

    /* Picture processing */
    config_PutInt("gl-tone-mapping-function", (int)_toneMappingPopup.selectedTag);
    config_PutFloat("gl-tone-mapping-param", _toneMappingParamSlider.floatValue);
    config_PutInt("gl-gamut-mapping", (int)_gamutMappingPopup.selectedTag);
    config_PutInt("gl-inverse-tone-mapping", (_inverseToneMappingCheckbox.state == NSControlStateValueOn) ? 1 : 0);

    /* Sharpness and smoothing */
    config_PutInt("gl-upscaler", (int)_upscalerPopup.selectedTag);
    config_PutInt("gl-downscaler", (int)_downscalerPopup.selectedTag);
    config_PutInt("dither-algo", (int)_ditherPopup.selectedTag);

    /* Video engine */
    NSString *voutVal = [self voutStringForTag:_voutPopup.selectedTag];
    config_PutPsz("vout", [voutVal UTF8String]);
    config_PutInt("force-darwin-legacy-display", (_legacyFallbackCheckbox.state == NSControlStateValueOn) ? 1 : 0);

    /* Decoding */
    config_PutInt("videotoolbox-hw-decoder-only", (_hwDecodeOnlyCheckbox.state == NSControlStateValueOn) ? 1 : 0);
    NSString *chromaVal = [self chromaStringForTag:_cvpxChromaPopup.selectedTag];
    config_PutPsz("videotoolbox-cvpx-chroma", [chromaVal UTF8String]);

    _hasUnsavedChanges = NO;
}

- (void)resetToDefaults
{
    _currentHdrMode = 0;
    for (NSButton *btn in _hdrModeRadioButtons) {
        btn.state = (btn.tag == 0) ? NSControlStateValueOn : NSControlStateValueOff;
    }

    _currentHeadroom = 0.0f;
    [self updateHeadroomControlsWithVal:0.0f];

    [_toneMappingPopup selectItemWithTag:0];
    _toneMappingParamSlider.floatValue = 0.0f;
    _toneMappingParamLabel.stringValue = _NS("0.0 (Optimal default)");
    [_gamutMappingPopup selectItemWithTag:0];
    _inverseToneMappingCheckbox.state = NSControlStateValueOff;

    [_upscalerPopup selectItemWithTag:0];
    [_downscalerPopup selectItemWithTag:0];
    [_ditherPopup selectItemWithTag:-1];

    [_voutPopup selectItemWithTag:0];
    _legacyFallbackCheckbox.state = NSControlStateValueOff;

    _hwDecodeOnlyCheckbox.state = NSControlStateValueOn;
    [_cvpxChromaPopup selectItemWithTag:0];

    _hasUnsavedChanges = YES;
    [self updateEngineDependentRowsState];
}

#pragma mark - UI Construction

- (void)buildStatusCard
{
    MacLCCardView *card = [MacLCCardView cardViewWithTitle:_NS("What's happening right now")];
    card.translatesAutoresizingMaskIntoConstraints = NO;

    _statusDisplayRow = [[MacLCStatusRowView alloc] initWithTitle:_NS("CONNECTED DISPLAY")
                                                     initialValue:_NS("Detecting display...")];
    _statusHeadroomRow = [[MacLCStatusRowView alloc] initWithTitle:_NS("EDR HEADROOM")
                                                      initialValue:_NS("Measuring headroom...")];
    _statusEngineRow = [[MacLCStatusRowView alloc] initWithTitle:_NS("ACTIVE VIDEO ENGINE")
                                                    initialValue:_NS("Querying engine...")];
    _statusPlaybackRow = [[MacLCStatusRowView alloc] initWithTitle:_NS("PLAYBACK STREAM & TONE-MAPPING")
                                                      initialValue:_NS("Checking playback...")];

    [card.contentStackView addArrangedSubview:_statusDisplayRow];
    [card.contentStackView addArrangedSubview:_statusHeadroomRow];
    [card.contentStackView addArrangedSubview:_statusEngineRow];
    [card.contentStackView addArrangedSubview:_statusPlaybackRow];

    [_mainStackView addArrangedSubview:card];
    [card.widthAnchor constraintEqualToAnchor:_mainStackView.widthAnchor constant:-2 * MacLCDesign.windowContentMargin].active = YES;
}

- (void)buildPrimaryControlCard
{
    MacLCCardView *card = [MacLCCardView cardViewWithTitle:_NS("HDR Playback")];
    card.translatesAutoresizingMaskIntoConstraints = NO;

    NSMutableArray *buttons = [[NSMutableArray alloc] init];

    struct {
        NSInteger tag;
        NSString *title;
        NSString *explanation;
        BOOL isRisky;
        BOOL isRecommended;
    } modes[] = {
        {
            0,
            _NS("Automatic (Recommended)"),
            _NS("HDR on displays that can show it, tone-mapped on displays that cannot."),
            NO,
            YES
        },
        {
            1,
            _NS("Always use HDR"),
            _NS("Forces an HDR signal even for ordinary video, which makes normal videos look very dark with unnatural colour."),
            YES,
            NO
        },
        {
            2,
            _NS("Convert HDR to SDR"),
            _NS("HDR films play at normal brightness and keep highlight detail, but lose the bright specular punch on an XDR display."),
            NO,
            NO
        },
        {
            3,
            _NS("Turn HDR off"),
            _NS("Bright areas clip to flat white and colours look washed out. Only for troubleshooting."),
            NO,
            NO
        }
    };

    for (size_t i = 0; i < 4; i++) {
        NSView *container = [[NSView alloc] init];
        container.translatesAutoresizingMaskIntoConstraints = NO;

        NSButton *radio = [NSButton radioButtonWithTitle:modes[i].title target:self action:@selector(hdrModeRadioClicked:)];
        radio.tag = modes[i].tag;
        radio.font = MacLCDesign.bodyEmphasized;
        radio.translatesAutoresizingMaskIntoConstraints = NO;
        [buttons addObject:radio];

        NSTextField *explanationLabel = [NSTextField wrappingLabelWithString:modes[i].explanation];
        explanationLabel.font = MacLCDesign.caption;
        explanationLabel.textColor = MacLCDesign.secondaryLabel;
        explanationLabel.translatesAutoresizingMaskIntoConstraints = NO;
        explanationLabel.accessibilityRole = NSAccessibilityStaticTextRole;

        [container addSubview:radio];
        [container addSubview:explanationLabel];

        if (modes[i].isRisky) {
            NSImageView *warnIcon = [[NSImageView alloc] init];
            warnIcon.translatesAutoresizingMaskIntoConstraints = NO;
            warnIcon.image = [MacLCDesign symbolNamed:@"exclamationmark.triangle.fill"
                                            pointSize:13
                                               weight:NSFontWeightMedium
                                   accessibilityLabel:_NS("Warning")];
            warnIcon.contentTintColor = MacLCDesign.warning;
            [container addSubview:warnIcon];

            [NSLayoutConstraint activateConstraints:@[
                [warnIcon.leadingAnchor constraintEqualToAnchor:radio.trailingAnchor constant:MacLCDesign.spacingXS],
                [warnIcon.centerYAnchor constraintEqualToAnchor:radio.centerYAnchor],
                [warnIcon.widthAnchor constraintEqualToConstant:14],
                [warnIcon.heightAnchor constraintEqualToConstant:14]
            ]];
        }

        [NSLayoutConstraint activateConstraints:@[
            [radio.topAnchor constraintEqualToAnchor:container.topAnchor],
            [radio.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],

            [explanationLabel.topAnchor constraintEqualToAnchor:radio.bottomAnchor constant:MacLCDesign.spacingXXS],
            [explanationLabel.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:20],
            [explanationLabel.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
            [explanationLabel.bottomAnchor constraintEqualToAnchor:container.bottomAnchor]
        ]];

        [card.contentStackView addArrangedSubview:container];
        [container.widthAnchor constraintEqualToAnchor:card.contentStackView.widthAnchor].active = YES;
    }

    _hdrModeRadioButtons = buttons;
    [_mainStackView addArrangedSubview:card];
    [card.widthAnchor constraintEqualToAnchor:_mainStackView.widthAnchor constant:-2 * MacLCDesign.windowContentMargin].active = YES;
}

- (void)buildHeadroomCard
{
    MacLCCardView *card = [MacLCCardView cardViewWithTitle:_NS("Brightness Headroom")];
    card.translatesAutoresizingMaskIntoConstraints = NO;

    NSView *topRow = [[NSView alloc] init];
    topRow.translatesAutoresizingMaskIntoConstraints = NO;

    _headroomAutoCheckbox = [NSButton checkboxWithTitle:_NS("Automatic (follow display)")
                                                 target:self
                                                 action:@selector(headroomAutoToggled:)];
    _headroomAutoCheckbox.font = MacLCDesign.bodyEmphasized;
    _headroomAutoCheckbox.translatesAutoresizingMaskIntoConstraints = NO;

    _headroomValueLabel = [NSTextField labelWithString:@"Auto"];
    _headroomValueLabel.font = [MacLCDesign monospacedDigitFontForTextStyle:NSFontTextStyleBody];
    _headroomValueLabel.textColor = MacLCDesign.primaryLabel;
    _headroomValueLabel.translatesAutoresizingMaskIntoConstraints = NO;

    [topRow addSubview:_headroomAutoCheckbox];
    [topRow addSubview:_headroomValueLabel];

    [NSLayoutConstraint activateConstraints:@[
        [_headroomAutoCheckbox.leadingAnchor constraintEqualToAnchor:topRow.leadingAnchor],
        [_headroomAutoCheckbox.topAnchor constraintEqualToAnchor:topRow.topAnchor],
        [_headroomAutoCheckbox.bottomAnchor constraintEqualToAnchor:topRow.bottomAnchor],

        [_headroomValueLabel.trailingAnchor constraintEqualToAnchor:topRow.trailingAnchor],
        [_headroomValueLabel.centerYAnchor constraintEqualToAnchor:_headroomAutoCheckbox.centerYAnchor]
    ]];

    _headroomSlider = [[NSSlider alloc] init];
    _headroomSlider.minValue = 1.0;
    _headroomSlider.maxValue = 4.0;
    _headroomSlider.numberOfTickMarks = 7;
    _headroomSlider.allowsTickMarkValuesOnly = NO;
    _headroomSlider.continuous = YES;
    _headroomSlider.target = self;
    _headroomSlider.action = @selector(headroomSliderChanged:);
    _headroomSlider.translatesAutoresizingMaskIntoConstraints = NO;
    [_headroomSlider setAccessibilityLabel:_NS("Brightness Headroom Scaling")];

    _headroomDisplayCapabilityLabel = [NSTextField labelWithString:@""];
    _headroomDisplayCapabilityLabel.font = MacLCDesign.caption;
    _headroomDisplayCapabilityLabel.textColor = MacLCDesign.secondaryLabel;
    _headroomDisplayCapabilityLabel.translatesAutoresizingMaskIntoConstraints = NO;

    NSTextField *explanationLabel = [NSTextField wrappingLabelWithString:
        _NS("Controls the maximum extended dynamic range brightness scaling factor. Setting this to Automatic allows macOS to smoothly adapt highlight brilliance to the physical display panel and ambient room lighting. Raising this manually forces brighter specular highlights, but can clip bright areas and rapidly drain battery.")];
    explanationLabel.font = MacLCDesign.caption;
    explanationLabel.textColor = MacLCDesign.secondaryLabel;
    explanationLabel.translatesAutoresizingMaskIntoConstraints = NO;
    explanationLabel.accessibilityRole = NSAccessibilityStaticTextRole;

    [card.contentStackView addArrangedSubview:topRow];
    [card.contentStackView addArrangedSubview:_headroomSlider];
    [card.contentStackView addArrangedSubview:_headroomDisplayCapabilityLabel];
    [card.contentStackView addArrangedSubview:explanationLabel];

    [topRow.widthAnchor constraintEqualToAnchor:card.contentStackView.widthAnchor].active = YES;
    [_headroomSlider.widthAnchor constraintEqualToAnchor:card.contentStackView.widthAnchor].active = YES;
    [_headroomDisplayCapabilityLabel.widthAnchor constraintEqualToAnchor:card.contentStackView.widthAnchor].active = YES;
    [explanationLabel.widthAnchor constraintEqualToAnchor:card.contentStackView.widthAnchor].active = YES;

    [_mainStackView addArrangedSubview:card];
    [card.widthAnchor constraintEqualToAnchor:_mainStackView.widthAnchor constant:-2 * MacLCDesign.windowContentMargin].active = YES;
}

- (void)buildAdvancedSection
{
    _advancedDisclosureButton = [NSButton buttonWithTitle:_NS("Advanced Options")
                                                   target:self
                                                   action:@selector(toggleAdvancedDisclosure:)];
    _advancedDisclosureButton.bezelStyle = NSBezelStyleInline;
    _advancedDisclosureButton.bordered = NO;
    _advancedDisclosureButton.font = MacLCDesign.headline;
    _advancedDisclosureButton.image = [MacLCDesign symbolNamed:@"chevron.right"
                                                     pointSize:13
                                                        weight:NSFontWeightSemibold
                                            accessibilityLabel:_NS("Expand Advanced Options")];
    _advancedDisclosureButton.imagePosition = NSImageLeading;
    _advancedDisclosureButton.contentTintColor = MacLCDesign.primaryLabel;
    _advancedDisclosureButton.translatesAutoresizingMaskIntoConstraints = NO;

    [_mainStackView addArrangedSubview:_advancedDisclosureButton];

    _advancedStackView = [[NSStackView alloc] init];
    _advancedStackView.orientation = NSUserInterfaceLayoutOrientationVertical;
    _advancedStackView.alignment = NSLayoutAttributeLeading;
    _advancedStackView.spacing = MacLCDesign.groupSpacing;
    _advancedStackView.translatesAutoresizingMaskIntoConstraints = NO;
    _advancedStackView.hidden = YES;

    [self buildPictureProcessingCard];
    [self buildSharpnessCard];
    [self buildVideoEngineCard];
    [self buildDecodingCard];

    [_mainStackView addArrangedSubview:_advancedStackView];
    [_advancedStackView.widthAnchor constraintEqualToAnchor:_mainStackView.widthAnchor constant:-2 * MacLCDesign.windowContentMargin].active = YES;
}

- (void)buildPictureProcessingCard
{
    MacLCCardView *card = [MacLCCardView cardViewWithTitle:_NS("Picture Processing")];
    card.translatesAutoresizingMaskIntoConstraints = NO;

    // 1. Tone mapping curve
    _toneMappingPopup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    _toneMappingPopup.target = self;
    _toneMappingPopup.action = @selector(controlValueChanged:);
    struct { NSInteger tag; NSString *title; } toneMapModes[] = {
        { 0, _NS("Automatic (recommended)") },
        { 1, _NS("Hard clip") },
        { 2, _NS("ITU-R BT.2390 EETF") },
        { 3, _NS("Reinhard") },
        { 4, _NS("Mobius") },
        { 5, _NS("Hable (filmic)") },
        { 6, _NS("Gamma-Power law") },
        { 7, _NS("Linear stretch") },
        { 8, _NS("ITU-R BT.2446A") },
        { 9, _NS("Single-pivot spline") },
    };
    for (size_t i = 0; i < 10; i++) {
        [_toneMappingPopup addItemWithTitle:toneMapModes[i].title];
        [_toneMappingPopup lastItem].tag = toneMapModes[i].tag;
    }
    MacLCSettingsRowView *row1 = [[MacLCSettingsRowView alloc] initWithTitle:_NS("Tone-mapping curve")
                                                                 explanation:_NS("Algorithm to use for tone mapping HDR into the display dynamic range. (OpenGL video engine only)")
                                                                     control:_toneMappingPopup
                                                                     isRisky:NO];
    row1.isEngineSpecific = YES;
    [_openGLEngineRows addObject:row1];
    [card.contentStackView addArrangedSubview:row1];
    [row1.widthAnchor constraintEqualToAnchor:card.contentStackView.widthAnchor].active = YES;

    // 2. Tone mapping param
    NSView *paramContainer = [[NSView alloc] init];
    paramContainer.translatesAutoresizingMaskIntoConstraints = NO;

    _toneMappingParamSlider = [[NSSlider alloc] init];
    _toneMappingParamSlider.minValue = 0.0;
    _toneMappingParamSlider.maxValue = 5.0;
    _toneMappingParamSlider.continuous = YES;
    _toneMappingParamSlider.target = self;
    _toneMappingParamSlider.action = @selector(toneParamChanged:);
    _toneMappingParamSlider.translatesAutoresizingMaskIntoConstraints = NO;

    _toneMappingParamLabel = [NSTextField labelWithString:_NS("0.0 (Optimal default)")];
    _toneMappingParamLabel.font = [MacLCDesign monospacedDigitFontForTextStyle:NSFontTextStyleCaption1];
    _toneMappingParamLabel.textColor = MacLCDesign.secondaryLabel;
    _toneMappingParamLabel.translatesAutoresizingMaskIntoConstraints = NO;

    [paramContainer addSubview:_toneMappingParamSlider];
    [paramContainer addSubview:_toneMappingParamLabel];

    [NSLayoutConstraint activateConstraints:@[
        [_toneMappingParamSlider.leadingAnchor constraintEqualToAnchor:paramContainer.leadingAnchor],
        [_toneMappingParamSlider.topAnchor constraintEqualToAnchor:paramContainer.topAnchor],
        [_toneMappingParamSlider.bottomAnchor constraintEqualToAnchor:paramContainer.bottomAnchor],
        [_toneMappingParamSlider.widthAnchor constraintEqualToConstant:140],

        [_toneMappingParamLabel.leadingAnchor constraintEqualToAnchor:_toneMappingParamSlider.trailingAnchor constant:MacLCDesign.spacingS],
        [_toneMappingParamLabel.trailingAnchor constraintEqualToAnchor:paramContainer.trailingAnchor],
        [_toneMappingParamLabel.centerYAnchor constraintEqualToAnchor:_toneMappingParamSlider.centerYAnchor]
    ]];

    MacLCSettingsRowView *row2 = [[MacLCSettingsRowView alloc] initWithTitle:_NS("Tone-mapping parameter")
                                                                 explanation:_NS("Fine-tunes the tone curve rolloff. 0.0 uses the algorithm optimal default. (OpenGL video engine only)")
                                                                     control:paramContainer
                                                                     isRisky:NO];
    row2.isEngineSpecific = YES;
    [_openGLEngineRows addObject:row2];
    [card.contentStackView addArrangedSubview:row2];
    [row2.widthAnchor constraintEqualToAnchor:card.contentStackView.widthAnchor].active = YES;

    // 3. Gamut mapping
    _gamutMappingPopup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    _gamutMappingPopup.target = self;
    _gamutMappingPopup.action = @selector(controlValueChanged:);
    struct { NSInteger tag; NSString *title; } gamutModes[] = {
        { 0, _NS("Automatic (recommended)") },
        { 1, _NS("Clip (flattens out-of-gamut colors)") },
        { 2, _NS("Perceptual (compresses colors gently)") },
        { 3, _NS("Relative colorimetric") },
        { 4, _NS("Saturation preserving") },
        { 5, _NS("Absolute colorimetric") },
        { 6, _NS("Desaturate") }
    };
    for (size_t i = 0; i < 7; i++) {
        [_gamutMappingPopup addItemWithTitle:gamutModes[i].title];
        [_gamutMappingPopup lastItem].tag = gamutModes[i].tag;
    }
    MacLCSettingsRowView *row3 = [[MacLCSettingsRowView alloc] initWithTitle:_NS("Gamut mapping")
                                                                 explanation:_NS("Algorithm to translate wide BT.2020 cinema colors into the display color space. (OpenGL video engine only)")
                                                                     control:_gamutMappingPopup
                                                                     isRisky:NO];
    row3.isEngineSpecific = YES;
    [_openGLEngineRows addObject:row3];
    [card.contentStackView addArrangedSubview:row3];
    [row3.widthAnchor constraintEqualToAnchor:card.contentStackView.widthAnchor].active = YES;

    // 4. SDR to HDR expansion
    _inverseToneMappingCheckbox = [NSButton checkboxWithTitle:_NS("Enable inverse tone mapping")
                                                       target:self
                                                       action:@selector(controlValueChanged:)];
    _inverseToneMappingCheckbox.font = MacLCDesign.body;
    MacLCSettingsRowView *row4 = [[MacLCSettingsRowView alloc] initWithTitle:_NS("SDR-to-HDR expansion")
                                                                 explanation:_NS("Artificially expands standard SDR video into HDR highlights. May cause exaggerated colors and distorted skin tones. (OpenGL video engine only)")
                                                                     control:_inverseToneMappingCheckbox
                                                                     isRisky:NO];
    row4.isEngineSpecific = YES;
    [_openGLEngineRows addObject:row4];
    [card.contentStackView addArrangedSubview:row4];
    [row4.widthAnchor constraintEqualToAnchor:card.contentStackView.widthAnchor].active = YES;

    [_advancedStackView addArrangedSubview:card];
    [card.widthAnchor constraintEqualToAnchor:_advancedStackView.widthAnchor].active = YES;
}

- (void)buildSharpnessCard
{
    MacLCCardView *card = [MacLCCardView cardViewWithTitle:_NS("Sharpness and Smoothing")];
    card.translatesAutoresizingMaskIntoConstraints = NO;

    // 1. Upscaler
    _upscalerPopup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    _upscalerPopup.target = self;
    _upscalerPopup.action = @selector(controlValueChanged:);

    // 2. Downscaler
    _downscalerPopup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    _downscalerPopup.target = self;
    _downscalerPopup.action = @selector(controlValueChanged:);

    struct { NSInteger tag; NSString *title; } scalers[] = {
        { 0, _NS("Built-in (Fast Bilinear)") },
        { 1, _NS("Bicubic Mitchell-Netravali") },
        { 2, _NS("Bicubic Catmull-Rom") },
        { 3, _NS("Lanczos (Sharp 3-tap)") },
        { 4, _NS("Spline16") },
        { 5, _NS("Spline36 (High quality)") },
        { 6, _NS("Spline64") },
        { 7, _NS("EWA Lanczos (Jinc)") },
    };
    for (size_t i = 0; i < 8; i++) {
        [_upscalerPopup addItemWithTitle:scalers[i].title];
        [_upscalerPopup lastItem].tag = scalers[i].tag;

        [_downscalerPopup addItemWithTitle:scalers[i].title];
        [_downscalerPopup lastItem].tag = scalers[i].tag;
    }

    MacLCSettingsRowView *row1 = [[MacLCSettingsRowView alloc] initWithTitle:_NS("Upscaler filter")
                                                                 explanation:_NS("Scaling filter applied when upscaling lower-resolution video on high-resolution displays. (OpenGL video engine only)")
                                                                     control:_upscalerPopup
                                                                     isRisky:NO];
    row1.isEngineSpecific = YES;
    [_openGLEngineRows addObject:row1];
    [card.contentStackView addArrangedSubview:row1];
    [row1.widthAnchor constraintEqualToAnchor:card.contentStackView.widthAnchor].active = YES;

    MacLCSettingsRowView *row2 = [[MacLCSettingsRowView alloc] initWithTitle:_NS("Downscaler filter")
                                                                 explanation:_NS("Filter applied when playing high-resolution video on a smaller display, reducing shimmering lines. (OpenGL video engine only)")
                                                                     control:_downscalerPopup
                                                                     isRisky:NO];
    row2.isEngineSpecific = YES;
    [_openGLEngineRows addObject:row2];
    [card.contentStackView addArrangedSubview:row2];
    [row2.widthAnchor constraintEqualToAnchor:card.contentStackView.widthAnchor].active = YES;

    // 3. Dithering
    _ditherPopup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    _ditherPopup.target = self;
    _ditherPopup.action = @selector(controlValueChanged:);
    struct { NSInteger tag; NSString *title; } ditherModes[] = {
        { -1, _NS("Disabled (no dithering)") },
        { 0,  _NS("Blue Noise (high quality grain)") },
        { 1,  _NS("White Noise (random dither)") },
        { 2,  _NS("Bayer 16x16 (ordered dither)") }
    };
    for (size_t i = 0; i < 4; i++) {
        [_ditherPopup addItemWithTitle:ditherModes[i].title];
        [_ditherPopup lastItem].tag = ditherModes[i].tag;
    }
    MacLCSettingsRowView *row3 = [[MacLCSettingsRowView alloc] initWithTitle:_NS("Dithering algorithm")
                                                                 explanation:_NS("Adds imperceptible pattern noise to eliminate visible color stepping and gradient banding on lower bit-depth panels. (OpenGL video engine only)")
                                                                     control:_ditherPopup
                                                                     isRisky:NO];
    row3.isEngineSpecific = YES;
    [_openGLEngineRows addObject:row3];
    [card.contentStackView addArrangedSubview:row3];
    [row3.widthAnchor constraintEqualToAnchor:card.contentStackView.widthAnchor].active = YES;

    [_advancedStackView addArrangedSubview:card];
    [card.widthAnchor constraintEqualToAnchor:_advancedStackView.widthAnchor].active = YES;
}

- (void)buildVideoEngineCard
{
    MacLCCardView *card = [MacLCCardView cardViewWithTitle:_NS("Video Engine & Compatibility")];
    card.translatesAutoresizingMaskIntoConstraints = NO;

    // 1. Output module
    _voutPopup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    _voutPopup.target = self;
    _voutPopup.action = @selector(engineControlChanged:);
    [_voutPopup addItemWithTitle:_NS("Automatic (Apple Native recommended)")];
    [_voutPopup lastItem].tag = 0;
    [_voutPopup addItemWithTitle:_NS("Apple Native CoreMedia (AVSampleBufferDisplay)")];
    [_voutPopup lastItem].tag = 1;
    [_voutPopup addItemWithTitle:_NS("OpenGL Core Layer (CAOpenGLLayer)")];
    [_voutPopup lastItem].tag = 2;

    MacLCSettingsRowView *row1 = [[MacLCSettingsRowView alloc] initWithTitle:_NS("Video output engine")
                                                                 explanation:_NS("The underlying macOS display engine. Selecting an unsupported module causes video output failure with audio-only playback.")
                                                                     control:_voutPopup
                                                                     isRisky:YES];
    [card.contentStackView addArrangedSubview:row1];
    [row1.widthAnchor constraintEqualToAnchor:card.contentStackView.widthAnchor].active = YES;

    // 2. Legacy fallback
    _legacyFallbackCheckbox = [NSButton checkboxWithTitle:_NS("Force fallback to legacy display")
                                                   target:self
                                                   action:@selector(engineControlChanged:)];
    _legacyFallbackCheckbox.font = MacLCDesign.body;

    MacLCSettingsRowView *row2 = [[MacLCSettingsRowView alloc] initWithTitle:_NS("Legacy display fallback")
                                                                 explanation:_NS("Forces video output to OpenGL. If OpenGL context fails, video fails with a black screen. Note: This option is volatile and is reset when MacLC restarts.")
                                                                     control:_legacyFallbackCheckbox
                                                                     isRisky:YES];
    [card.contentStackView addArrangedSubview:row2];
    [row2.widthAnchor constraintEqualToAnchor:card.contentStackView.widthAnchor].active = YES;

    [_advancedStackView addArrangedSubview:card];
    [card.widthAnchor constraintEqualToAnchor:_advancedStackView.widthAnchor].active = YES;
}

- (void)buildDecodingCard
{
    MacLCCardView *card = [MacLCCardView cardViewWithTitle:_NS("Hardware Decoding & Precision")];
    card.translatesAutoresizingMaskIntoConstraints = NO;

    // 1. Hardware decoding only
    _hwDecodeOnlyCheckbox = [NSButton checkboxWithTitle:_NS("Use hardware decoders only")
                                                 target:self
                                                 action:@selector(controlValueChanged:)];
    _hwDecodeOnlyCheckbox.font = MacLCDesign.body;
    MacLCSettingsRowView *row1 = [[MacLCSettingsRowView alloc] initWithTitle:_NS("Hardware decoding only")
                                                                 explanation:_NS("Requires hardware acceleration. If enabled, video formats without Apple Silicon hardware decode (such as AV1 on M1/M2) will fail to open.")
                                                                     control:_hwDecodeOnlyCheckbox
                                                                     isRisky:YES];
    [card.contentStackView addArrangedSubview:row1];
    [row1.widthAnchor constraintEqualToAnchor:card.contentStackView.widthAnchor].active = YES;

    // 2. Decoder pixel format
    _cvpxChromaPopup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    _cvpxChromaPopup.target = self;
    _cvpxChromaPopup.action = @selector(controlValueChanged:);
    struct { NSInteger tag; NSString *title; } chromaModes[] = {
        { 0, _NS("Auto (Best quality 10-bit P010)") },
        { 1, _NS("Y'CbCr 10-bit 4:2:0 (Video Range - HDR)") },
        { 2, _NS("Y'CbCr 10-bit 4:2:0 (Full Range - HDR)") },
        { 3, _NS("BGRA 8-bit (Clamps HDR to 8-bit)") },
        { 4, _NS("Y'CbCr 8-bit 4:2:0 (Planar)") },
        { 5, _NS("Y'CbCr 8-bit 4:2:0 (Bi-Planar)") },
    };
    for (size_t i = 0; i < 6; i++) {
        [_cvpxChromaPopup addItemWithTitle:chromaModes[i].title];
        [_cvpxChromaPopup lastItem].tag = chromaModes[i].tag;
    }
    MacLCSettingsRowView *row2 = [[MacLCSettingsRowView alloc] initWithTitle:_NS("Decoder pixel format")
                                                                 explanation:_NS("Forces VideoToolbox pixel format. Incompatible formats abort the decoder session, stopping playback immediately. 8-bit formats cause color banding.")
                                                                     control:_cvpxChromaPopup
                                                                     isRisky:YES];
    [card.contentStackView addArrangedSubview:row2];
    [row2.widthAnchor constraintEqualToAnchor:card.contentStackView.widthAnchor].active = YES;

    [_advancedStackView addArrangedSubview:card];
    [card.widthAnchor constraintEqualToAnchor:_advancedStackView.widthAnchor].active = YES;
}

- (void)buildFooter
{
    NSView *footerView = [[NSView alloc] init];
    footerView.translatesAutoresizingMaskIntoConstraints = NO;

    NSButton *resetButton = [NSButton buttonWithTitle:_NS("Reset HDR settings to defaults")
                                               target:self
                                               action:@selector(resetToDefaults)];
    resetButton.bezelStyle = NSBezelStyleRounded;
    resetButton.font = MacLCDesign.body;
    resetButton.translatesAutoresizingMaskIntoConstraints = NO;
    [resetButton setAccessibilityLabel:_NS("Reset HDR settings to defaults")];

    [footerView addSubview:resetButton];

    [NSLayoutConstraint activateConstraints:@[
        [resetButton.trailingAnchor constraintEqualToAnchor:footerView.trailingAnchor],
        [resetButton.topAnchor constraintEqualToAnchor:footerView.topAnchor constant:MacLCDesign.spacingM],
        [resetButton.bottomAnchor constraintEqualToAnchor:footerView.bottomAnchor constant:-MacLCDesign.spacingS],
        [footerView.heightAnchor constraintGreaterThanOrEqualToConstant:44]
    ]];

    [_mainStackView addArrangedSubview:footerView];
    [footerView.widthAnchor constraintEqualToAnchor:_mainStackView.widthAnchor constant:-2 * MacLCDesign.windowContentMargin].active = YES;
}

#pragma mark - Live Status Telemetry

- (void)refreshLiveStatus
{
    NSScreen *screen = self.view.window.screen ?: [NSScreen mainScreen];

    // Row 1: Display Name & EDR capability
    NSString *displayName = screen.localizedName ?: _NS("Connected Display");
    CGFloat maxPotentialEDR = screen.maximumPotentialExtendedDynamicRangeColorComponentValue;
    BOOL isEDRCapable = (maxPotentialEDR > 1.0);
    NSString *capString = isEDRCapable ? _NS("HDR / EDR Supported") : _NS("SDR Only");
    [_statusDisplayRow setValue:[NSString stringWithFormat:@"%@  •  %@", displayName, capString]];

    // Row 2: Current & Maximum Headroom
    CGFloat currentEDR = screen.maximumExtendedDynamicRangeColorComponentValue;
    CGFloat currentNits = currentEDR * SDR_NOMINAL_WHITE_NITS;
    CGFloat maxNits = maxPotentialEDR * SDR_NOMINAL_WHITE_NITS;
    [_statusHeadroomRow setValue:[NSString stringWithFormat:_NS("Current: %.1fx (~%.0f nits)  •  Maximum: %.1fx (~%.0f nits)"),
                                  currentEDR, currentNits, maxPotentialEDR, maxNits]];

    // Row 3: Video output engine in use
    NSString *activeEngineName = nil;
    VLCVideoOutputProvider *voutProvider = VLCMain.sharedInstance.voutProvider;
    NSDictionary *windows = voutProvider.voutWindows;
    if (windows.count > 0) {
        for (VLCVideoWindowCommon *win in windows.allValues) {
            NSView *voutView = win.videoViewController.voutView;
            if (voutView) {
                for (NSView *sub in voutView.subviews) {
                    if ([sub.layer isKindOfClass:[AVSampleBufferDisplayLayer class]] ||
                        [NSStringFromClass(sub.class) containsString:@"SampleBuffer"]) {
                        activeEngineName = _NS("Apple Native CoreMedia (AVSampleBufferDisplayLayer)");
                        break;
                    } else if ([sub.layer isKindOfClass:[CAOpenGLLayer class]] ||
                               [NSStringFromClass(sub.class) containsString:@"VideoLayer"]) {
                        activeEngineName = _NS("OpenGL Core Layer (CAOpenGLLayer)");
                        break;
                    }
                }
            }
            if (activeEngineName) break;
        }
    }

    if (!activeEngineName) {
        BOOL forceLegacy = config_GetInt("force-darwin-legacy-display") || (_legacyFallbackCheckbox.state == NSControlStateValueOn);
        if (forceLegacy || _voutPopup.selectedTag == 2) {
            activeEngineName = _NS("OpenGL Core Layer (caopengllayer, standby)");
        } else {
            activeEngineName = _NS("Apple Native CoreMedia (samplebufferdisplay, standby)");
        }
    }
    [_statusEngineRow setValue:activeEngineName];

    // Row 4: Colour transfer & tone-mapping status
    VLCPlayerController *playerController = VLCMain.sharedInstance.playQueueController.playerController;
    enum vlc_player_state state = playerController.playerState;
    if (state == VLC_PLAYER_STATE_PLAYING || state == VLC_PLAYER_STATE_PAUSED) {
        VLCInputItem *item = playerController.currentMedia;
        input_item_t *p_input = item.vlcInputItem;
        NSString *transferStr = _NS("SDR");
        BOOL isHDR = NO;

        if (p_input) {
            vlc_mutex_lock(&p_input->lock);
            const struct input_item_es *item_es;
            vlc_vector_foreach_ref(item_es, &p_input->es_vec) {
                if (item_es->es.i_cat != VIDEO_ES) continue;
                const video_format_t *fmt = &item_es->es.video;
                if (fmt->dovi.rpu_present) {
                    transferStr = _NS("Dolby Vision");
                    isHDR = YES;
                } else if (fmt->transfer == TRANSFER_FUNC_SMPTE_ST2084) {
                    transferStr = _NS("HDR10 (PQ)");
                    isHDR = YES;
                } else if (fmt->transfer == TRANSFER_FUNC_HLG) {
                    transferStr = _NS("HLG");
                    isHDR = YES;
                }
                break;
            }
            vlc_mutex_unlock(&p_input->lock);
        }

        NSString *toneMapStr = nil;
        if (isHDR) {
            if (_currentHdrMode == 2) {
                toneMapStr = _NS("Tone-mapping active (forced SDR conversion)");
            } else if (_currentHdrMode == 3) {
                toneMapStr = _NS("No tone-mapping (HDR disabled, clipped to SDR)");
            } else if (!isEDRCapable) {
                toneMapStr = _NS("Tone-mapping active (automatic hardware tone-mapping for SDR display)");
            } else {
                toneMapStr = _NS("Native EDR passthrough (no SDR tone-mapping)");
            }
        } else {
            toneMapStr = _NS("None (standard dynamic range content)");
        }

        [_statusPlaybackRow setValue:[NSString stringWithFormat:@"%@  •  %@", transferStr, toneMapStr]];
    } else {
        [_statusPlaybackRow setValue:_NS("No video currently playing")];
    }

    // Also update headroom display capability hint
    _headroomDisplayCapabilityLabel.stringValue = [NSString stringWithFormat:_NS("Display measured peak headroom: %.1fx (~%.0f nits)"),
                                                   currentEDR, currentNits];
}

#pragma mark - Notifications

- (void)startObserving
{
    if (_observingNotifications) return;

    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self selector:@selector(screenParametersChanged:)
               name:NSApplicationDidChangeScreenParametersNotification object:nil];
    [nc addObserver:self selector:@selector(screenParametersChanged:)
               name:NSWindowDidChangeScreenNotification object:nil];
    [nc addObserver:self selector:@selector(playbackChanged:)
               name:VLCPlayerCurrentMediaItemChanged object:nil];
    [nc addObserver:self selector:@selector(playbackChanged:)
               name:VLCPlayerStateChanged object:nil];

    _observingNotifications = YES;
}

- (void)stopObserving
{
    if (!_observingNotifications) return;

    [[NSNotificationCenter defaultCenter] removeObserver:self];
    _observingNotifications = NO;
}

- (void)screenParametersChanged:(NSNotification *)note
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self refreshLiveStatus];
    });
}

- (void)playbackChanged:(NSNotification *)note
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self refreshLiveStatus];
    });
}

#pragma mark - Actions

- (void)hdrModeRadioClicked:(NSButton *)sender
{
    _currentHdrMode = sender.tag;
    for (NSButton *btn in _hdrModeRadioButtons) {
        btn.state = (btn == sender) ? NSControlStateValueOn : NSControlStateValueOff;
    }
    _hasUnsavedChanges = YES;
    [self refreshLiveStatus];
}

- (void)headroomAutoToggled:(NSButton *)sender
{
    if (sender.state == NSControlStateValueOn) {
        _currentHeadroom = 0.0f;
    } else {
        _currentHeadroom = _headroomSlider.floatValue;
    }
    [self updateHeadroomControlsWithVal:_currentHeadroom];
    _hasUnsavedChanges = YES;
    [self refreshLiveStatus];
}

- (void)headroomSliderChanged:(NSSlider *)sender
{
    _currentHeadroom = sender.floatValue;
    _headroomAutoCheckbox.state = NSControlStateValueOff;
    [self updateHeadroomControlsWithVal:_currentHeadroom];
    _hasUnsavedChanges = YES;
    [self refreshLiveStatus];
}

- (void)updateHeadroomControlsWithVal:(float)val
{
    NSScreen *screen = self.view.window.screen ?: [NSScreen mainScreen];
    CGFloat screenMax = screen.maximumExtendedDynamicRangeColorComponentValue;

    if (val == 0.0f) {
        _headroomAutoCheckbox.state = NSControlStateValueOn;
        _headroomSlider.enabled = NO;
        _headroomSlider.floatValue = screenMax;
        _headroomValueLabel.stringValue = [NSString stringWithFormat:_NS("Auto (%.1fx)"), screenMax];
    } else {
        _headroomAutoCheckbox.state = NSControlStateValueOff;
        _headroomSlider.enabled = YES;
        _headroomSlider.floatValue = val;
        _headroomValueLabel.stringValue = [NSString stringWithFormat:@"%.1fx", val];
    }
}

- (void)toggleAdvancedDisclosure:(id)sender
{
    _advancedExpanded = !_advancedExpanded;
    _advancedDisclosureButton.image = [MacLCDesign symbolNamed:_advancedExpanded ? @"chevron.down" : @"chevron.right"
                                                     pointSize:13
                                                        weight:NSFontWeightSemibold
                                            accessibilityLabel:_advancedExpanded ? _NS("Collapse Advanced Options") : _NS("Expand Advanced Options")];
    [MacLCDesign performAnimated:^{
        self->_advancedStackView.hidden = !self->_advancedExpanded;
    }];
}

- (void)toneParamChanged:(NSSlider *)sender
{
    float val = sender.floatValue;
    _toneMappingParamLabel.stringValue = (val == 0.0f) ? _NS("0.0 (Optimal default)") : [NSString stringWithFormat:@"%.2f", val];
    _hasUnsavedChanges = YES;
}

- (void)controlValueChanged:(id)sender
{
    _hasUnsavedChanges = YES;
}

- (void)engineControlChanged:(id)sender
{
    _hasUnsavedChanges = YES;
    [self updateEngineDependentRowsState];
    [self refreshLiveStatus];
}

- (void)updateEngineDependentRowsState
{
    BOOL isLegacy = (_legacyFallbackCheckbox.state == NSControlStateValueOn);
    BOOL isOpenGL = isLegacy || (_voutPopup.selectedTag == 2);

    for (MacLCSettingsRowView *row in _openGLEngineRows) {
        [row setRowEnabled:isOpenGL];
    }
}

#pragma mark - String Mapping Helpers

- (NSInteger)tagForVoutString:(NSString *)vout
{
    if ([vout isEqualToString:@"samplebufferdisplay"]) return 1;
    if ([vout isEqualToString:@"caopengllayer"]) return 2;
    return 0; // "any"
}

- (NSString *)voutStringForTag:(NSInteger)tag
{
    switch (tag) {
        case 1: return @"samplebufferdisplay";
        case 2: return @"caopengllayer";
        default: return @"any";
    }
}

- (NSInteger)tagForChromaString:(NSString *)chroma
{
    if ([chroma isEqualToString:@"x420"]) return 1;
    if ([chroma isEqualToString:@"xf20"]) return 2;
    if ([chroma isEqualToString:@"BGRA"]) return 3;
    if ([chroma isEqualToString:@"y420"]) return 4;
    if ([chroma isEqualToString:@"420v"]) return 5;
    return 0; // auto
}

- (NSString *)chromaStringForTag:(NSInteger)tag
{
    switch (tag) {
        case 1: return @"x420";
        case 2: return @"xf20";
        case 3: return @"BGRA";
        case 4: return @"y420";
        case 5: return @"420v";
        default: return @"";
    }
}

@end
