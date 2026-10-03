/*****************************************************************************
 * MacLCSDRToHDRPanelViewController.m: MacLC's SDR to HDR options popover
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

#import "MacLCSDRToHDRPanelViewController.h"

#import "main/VLCMain.h"
#import "playqueue/VLCPlayQueueController.h"
#import "playqueue/VLCPlayerController.h"
#import "windows/video/VLCVideoOutputProvider.h"
#import "settings/MacLCSettingsWindowController.h"
#import "hdr/MacLCHDRController.h"
#import "hdr/MacLCHDRPanelViewController.h"
#import "hdr/MacLCExpansionCurveView.h"
#import "hdr/MacLCTradeoffMeterView.h"
#import "hdr/MacLCDisplayInfo.h"
#import "coreinteraction/MacLCOSDController.h"
#import "theme/MacLCDesign.h"
#import "extensions/NSString+Helpers.h"

#include "../../video_output/apple/maclc_sdr2hdr.h"

static const CGFloat kPanelWidth = 380.0;
static const CGFloat kPanelPadding = 16.0;

#pragma mark - Hold to Compare Button

@interface MacLCHoldToCompareButton : NSButton
@end

@implementation MacLCHoldToCompareButton

/* Identifies the latest keyboard press. It outlives the button: the panel can
 * close, and take the button with it, before the original is put away. */
static NSUInteger keyboardPress;

/* Keyboard (Space) and VoiceOver cannot hold a button: a press shows the
 * original for three seconds instead, and a second press ends it early. */
- (void)showOriginalBriefly
{
    MacLCSDRToHDRState *state = [MacLCSDRToHDRState sharedState];
    if (state.comparing) {
        [state setComparing:NO];
        [[MacLCOSDController sharedController] showMessage:_NS("HDR") symbolName:@"sun.max"];
        keyboardPress++;
        return;
    }
    [state setComparing:YES];
    [[MacLCOSDController sharedController] showMessage:_NS("Original") symbolName:@"square.split.2x1"];
    NSAccessibilityPostNotificationWithUserInfo(self.window ?: NSApp.keyWindow,
        NSAccessibilityAnnouncementRequestedNotification,
        @{ NSAccessibilityAnnouncementKey: _NS("Original") });
    const NSUInteger press = ++keyboardPress;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (keyboardPress != press || !state.comparing)
            return;
        [state setComparing:NO];
        [[MacLCOSDController sharedController] showMessage:_NS("HDR") symbolName:@"sun.max"];
    });
}

- (void)performClick:(id)sender
{
    if (self.isEnabled)
        [self showOriginalBriefly];
}

- (BOOL)accessibilityPerformPress
{
    if (!self.isEnabled)
        return NO;
    [self showOriginalBriefly];
    return YES;
}

- (void)mouseDown:(NSEvent *)event
{
    if (!self.isEnabled) {
        [super mouseDown:event];
        return;
    }
    [[MacLCSDRToHDRState sharedState] setComparing:YES];
    [[MacLCOSDController sharedController] showMessage:_NS("Original") symbolName:@"square.split.2x1"];
    [super mouseDown:event];
    [[MacLCSDRToHDRState sharedState] setComparing:NO];
    [[MacLCOSDController sharedController] showMessage:_NS("HDR") symbolName:@"sun.max"];
}

@end

#pragma mark - Panel View Controller

@implementation MacLCSDRToHDRPanelViewController
{
    NSTextField *_titleLabel;
    NSSwitch *_switchControl;
    NSTextField *_streamInfoLabel;
    NSTextField *_peakDetailLabel;

    NSTextField *_qualityHeader;
    NSSegmentedControl *_qualitySegment;
    NSTextField *_autoStatusLabel;

    MacLCExpansionCurveView *_curveView;
    MacLCTradeoffMeterView *_meterView;
    NSTextField *_qualitySummaryLabel;

    NSTextField *_highlightsTitleLabel;
    NSTextField *_highlightsValueLabel;
    NSImageView *_sunMinView;
    NSImageView *_sunMaxView;
    NSSlider *_boostSlider;
    NSTextField *_highlightsCaptionLabel;

    MacLCHoldToCompareButton *_compareButton;
    BOOL _polling;
    NSButton *_settingsButton;

    NSArray<NSView *> *_dimmableViews;
}

static NSPopover *gPopover;
static __weak NSView *gAnchor;

+ (void)showRelativeToView:(NSView *)view preferredEdge:(NSRectEdge)edge
{
    if (gPopover.isShown && gAnchor == view) {
        [gPopover performClose:nil];
        return;
    }
    [self showRelativeToRect:view.bounds ofView:view preferredEdge:edge];
}

+ (void)showRelativeToRect:(NSRect)rect ofView:(NSView *)view preferredEdge:(NSRectEdge)edge
{
    [MacLCHDRPanelViewController closePanel];
    [gPopover close];

    NSPopover *popover = [[NSPopover alloc] init];
    popover.behavior = NSPopoverBehaviorTransient;
    popover.animates = !MacLCDesign.reducedMotion;
    popover.contentViewController = [[MacLCSDRToHDRPanelViewController alloc] init];
    gPopover = popover;
    gAnchor = view;
    [popover showRelativeToRect:rect ofView:view preferredEdge:edge];
}

+ (void)showForKeyWindow
{
    NSView *content = NSApp.keyWindow.contentView ?: NSApp.mainWindow.contentView;
    if (content == nil)
        return;
    [self showRelativeToView:content preferredEdge:NSRectEdgeMinY];
}

+ (void)closePanel
{
    if (gPopover.isShown) {
        [gPopover performClose:nil];
    }
    gPopover = nil;
    gAnchor = nil;
}

#pragma mark - View Lifecycle

- (void)loadView
{
    NSView *root = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, kPanelWidth, 540)];
    root.translatesAutoresizingMaskIntoConstraints = NO;

    const CGFloat inner = kPanelWidth - 2 * kPanelPadding;

    /* Header */
    _titleLabel = [NSTextField labelWithString:_NS("SDR to HDR")];
    _titleLabel.font = MacLCDesign.title3;
    _titleLabel.textColor = MacLCDesign.primaryLabel;

    _switchControl = [[NSSwitch alloc] init];
    _switchControl.controlSize = NSControlSizeSmall;
    _switchControl.target = self;
    _switchControl.action = @selector(switchToggled:);
    _switchControl.accessibilityLabel = _NS("Play SDR video in HDR");
    _switchControl.translatesAutoresizingMaskIntoConstraints = NO;

    _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    NSView *headerRow = [[NSView alloc] init];
    headerRow.translatesAutoresizingMaskIntoConstraints = NO;
    [headerRow addSubview:_titleLabel];
    [headerRow addSubview:_switchControl];
    [NSLayoutConstraint activateConstraints:@[
        [_titleLabel.leadingAnchor constraintEqualToAnchor:headerRow.leadingAnchor],
        [_titleLabel.centerYAnchor constraintEqualToAnchor:headerRow.centerYAnchor],
        [_titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_switchControl.leadingAnchor
                                                             constant:-MacLCDesign.spacingS],
        [_switchControl.trailingAnchor constraintEqualToAnchor:headerRow.trailingAnchor],
        [_switchControl.centerYAnchor constraintEqualToAnchor:headerRow.centerYAnchor],
        [headerRow.heightAnchor constraintGreaterThanOrEqualToConstant:28.0],
    ]];

    _streamInfoLabel = [NSTextField wrappingLabelWithString:@""];
    _streamInfoLabel.font = MacLCDesign.footnote;
    _streamInfoLabel.textColor = MacLCDesign.secondaryLabel;
    _streamInfoLabel.preferredMaxLayoutWidth = inner;

    _peakDetailLabel = [NSTextField wrappingLabelWithString:@""];
    _peakDetailLabel.font = MacLCDesign.footnote;
    _peakDetailLabel.textColor = MacLCDesign.primaryLabel;
    _peakDetailLabel.preferredMaxLayoutWidth = inner;

    /* Quality section */
    _qualityHeader = [self sectionHeader:_NS("Quality")];

    _qualitySegment = [NSSegmentedControl segmentedControlWithLabels:@[
        _NS("Auto"), _NS("Fast"), _NS("Balanced"), _NS("High"), _NS("Maximum")
    ] trackingMode:NSSegmentSwitchTrackingSelectOne target:self action:@selector(qualityChanged:)];
    _qualitySegment.segmentDistribution = NSSegmentDistributionFillEqually;
    _qualitySegment.translatesAutoresizingMaskIntoConstraints = NO;

    [_qualitySegment setToolTip:[MacLCSDRToHDRState summaryForQuality:MacLCSDRToHDRQualityAuto] forSegment:0];
    [_qualitySegment setToolTip:[MacLCSDRToHDRState summaryForQuality:MacLCSDRToHDRQualityFast] forSegment:1];
    [_qualitySegment setToolTip:[MacLCSDRToHDRState summaryForQuality:MacLCSDRToHDRQualityBalanced] forSegment:2];
    [_qualitySegment setToolTip:[MacLCSDRToHDRState summaryForQuality:MacLCSDRToHDRQualityHigh] forSegment:3];
    [_qualitySegment setToolTip:[MacLCSDRToHDRState summaryForQuality:MacLCSDRToHDRQualityMaximum] forSegment:4];

    _qualitySegment.accessibilityLabel = _NS("Quality");

    _autoStatusLabel = [NSTextField wrappingLabelWithString:@""];
    _autoStatusLabel.font = MacLCDesign.footnote;
    _autoStatusLabel.textColor = MacLCDesign.secondaryLabel;
    _autoStatusLabel.preferredMaxLayoutWidth = inner;

    /* Curve View */
    _curveView = [[MacLCExpansionCurveView alloc] initWithFrame:NSMakeRect(0, 0, inner, 110)];
    _curveView.translatesAutoresizingMaskIntoConstraints = NO;

    /* Tradeoff Meter */
    _meterView = [[MacLCTradeoffMeterView alloc] initWithFrame:NSZeroRect];
    [_meterView setTitles:@[
        _NS("Highlight pop"),
        _NS("True to original"),
        _NS("Smooth gradients"),
        _NS("Battery")
    ]];

    _qualitySummaryLabel = [NSTextField wrappingLabelWithString:@""];
    _qualitySummaryLabel.font = MacLCDesign.footnote;
    _qualitySummaryLabel.textColor = MacLCDesign.secondaryLabel;
    _qualitySummaryLabel.preferredMaxLayoutWidth = inner;

    /* Highlights section */
    _highlightsTitleLabel = [NSTextField labelWithString:_NS("Highlights up to:")];
    _highlightsTitleLabel.font = MacLCDesign.body;
    _highlightsTitleLabel.textColor = MacLCDesign.primaryLabel;

    _highlightsValueLabel = [NSTextField labelWithString:@"400 cd/m²"];
    _highlightsValueLabel.font = [MacLCDesign monospacedDigitFontForTextStyle:NSFontTextStyleBody];
    _highlightsValueLabel.textColor = MacLCDesign.primaryLabel;

    _highlightsTitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _highlightsValueLabel.translatesAutoresizingMaskIntoConstraints = NO;
    NSView *highlightsHeaderRow = [[NSView alloc] init];
    highlightsHeaderRow.translatesAutoresizingMaskIntoConstraints = NO;
    [highlightsHeaderRow addSubview:_highlightsTitleLabel];
    [highlightsHeaderRow addSubview:_highlightsValueLabel];
    [NSLayoutConstraint activateConstraints:@[
        [_highlightsTitleLabel.leadingAnchor constraintEqualToAnchor:highlightsHeaderRow.leadingAnchor],
        [_highlightsTitleLabel.centerYAnchor constraintEqualToAnchor:highlightsHeaderRow.centerYAnchor],
        [_highlightsValueLabel.trailingAnchor constraintEqualToAnchor:highlightsHeaderRow.trailingAnchor],
        [_highlightsValueLabel.centerYAnchor constraintEqualToAnchor:highlightsHeaderRow.centerYAnchor],
        [_highlightsValueLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:_highlightsTitleLabel.trailingAnchor
                                                                         constant:MacLCDesign.spacingS],
        [highlightsHeaderRow.heightAnchor constraintGreaterThanOrEqualToConstant:20.0],
    ]];

    _sunMinView = [[NSImageView alloc] init];
    _sunMinView.image = [NSImage imageWithSystemSymbolName:@"sun.min" accessibilityDescription:nil];
    _sunMinView.contentTintColor = MacLCDesign.secondaryLabel;
    _sunMinView.translatesAutoresizingMaskIntoConstraints = NO;
    _sunMinView.accessibilityElement = NO;

    _sunMaxView = [[NSImageView alloc] init];
    _sunMaxView.image = [NSImage imageWithSystemSymbolName:@"sun.max" accessibilityDescription:nil];
    _sunMaxView.contentTintColor = MacLCDesign.secondaryLabel;
    _sunMaxView.translatesAutoresizingMaskIntoConstraints = NO;
    _sunMaxView.accessibilityElement = NO;

    _boostSlider = [[NSSlider alloc] init];
    _boostSlider.minValue = 0.0;
    _boostSlider.maxValue = 4.0;
    _boostSlider.numberOfTickMarks = 5;
    _boostSlider.allowsTickMarkValuesOnly = NO;
    _boostSlider.continuous = YES;
    _boostSlider.target = self;
    _boostSlider.action = @selector(sliderChanged:);
    _boostSlider.translatesAutoresizingMaskIntoConstraints = NO;
    _boostSlider.accessibilityLabel = _NS("Highlights up to");

    NSView *sliderRow = [[NSView alloc] init];
    sliderRow.translatesAutoresizingMaskIntoConstraints = NO;
    [sliderRow addSubview:_sunMinView];
    [sliderRow addSubview:_boostSlider];
    [sliderRow addSubview:_sunMaxView];
    [NSLayoutConstraint activateConstraints:@[
        [_sunMinView.leadingAnchor constraintEqualToAnchor:sliderRow.leadingAnchor],
        [_sunMinView.centerYAnchor constraintEqualToAnchor:sliderRow.centerYAnchor],
        [_sunMinView.widthAnchor constraintEqualToConstant:16],
        [_sunMinView.heightAnchor constraintEqualToConstant:16],

        [_boostSlider.leadingAnchor constraintEqualToAnchor:_sunMinView.trailingAnchor constant:8.0],
        [_boostSlider.trailingAnchor constraintEqualToAnchor:_sunMaxView.leadingAnchor constant:-8.0],
        [_boostSlider.centerYAnchor constraintEqualToAnchor:sliderRow.centerYAnchor],

        [_sunMaxView.trailingAnchor constraintEqualToAnchor:sliderRow.trailingAnchor],
        [_sunMaxView.centerYAnchor constraintEqualToAnchor:sliderRow.centerYAnchor],
        [_sunMaxView.widthAnchor constraintEqualToConstant:16],
        [_sunMaxView.heightAnchor constraintEqualToConstant:16],
        [sliderRow.heightAnchor constraintGreaterThanOrEqualToConstant:24.0],
    ]];

    _highlightsCaptionLabel = [NSTextField wrappingLabelWithString:@""];
    _highlightsCaptionLabel.font = MacLCDesign.footnote;
    _highlightsCaptionLabel.textColor = MacLCDesign.secondaryLabel;
    _highlightsCaptionLabel.preferredMaxLayoutWidth = inner;

    /* Footer */
    _compareButton = [[MacLCHoldToCompareButton alloc] init];
    _compareButton.title = _NS("Hold to Compare");
    _compareButton.bezelStyle = NSBezelStyleRounded;
    _compareButton.toolTip = _NS("Shows the original SDR picture while you hold it. You can also hold M.");
    _compareButton.translatesAutoresizingMaskIntoConstraints = NO;

    _settingsButton = [[NSButton alloc] init];
    _settingsButton.title = _NS("Settings…");
    _settingsButton.bezelStyle = NSBezelStyleRounded;
    _settingsButton.target = self;
    _settingsButton.action = @selector(openSettings:);
    _settingsButton.translatesAutoresizingMaskIntoConstraints = NO;

    _compareButton.translatesAutoresizingMaskIntoConstraints = NO;
    _settingsButton.translatesAutoresizingMaskIntoConstraints = NO;
    NSView *footer = [[NSView alloc] init];
    footer.translatesAutoresizingMaskIntoConstraints = NO;
    [footer addSubview:_compareButton];
    [footer addSubview:_settingsButton];
    [NSLayoutConstraint activateConstraints:@[
        [_compareButton.leadingAnchor constraintEqualToAnchor:footer.leadingAnchor],
        [_compareButton.centerYAnchor constraintEqualToAnchor:footer.centerYAnchor],
        [_settingsButton.trailingAnchor constraintEqualToAnchor:footer.trailingAnchor],
        [_settingsButton.centerYAnchor constraintEqualToAnchor:footer.centerYAnchor],
        [footer.heightAnchor constraintGreaterThanOrEqualToConstant:32.0],
    ]];

    /* Root stack view */
    NSStackView *stack = [NSStackView stackViewWithViews:@[
        headerRow,
        _streamInfoLabel,
        _peakDetailLabel,
        _qualityHeader,
        _qualitySegment,
        _autoStatusLabel,
        _curveView,
        _meterView,
        _qualitySummaryLabel,
        highlightsHeaderRow,
        sliderRow,
        _highlightsCaptionLabel,
        [self separator],
        footer,
    ]];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = MacLCDesign.spacingS;
    stack.translatesAutoresizingMaskIntoConstraints = NO;

    [stack setCustomSpacing:2.0 afterView:headerRow];
    [stack setCustomSpacing:2.0 afterView:_streamInfoLabel];
    [stack setCustomSpacing:MacLCDesign.spacingM afterView:_peakDetailLabel];
    [stack setCustomSpacing:MacLCDesign.spacingXS afterView:_qualityHeader];
    [stack setCustomSpacing:4.0 afterView:_qualitySegment];
    [stack setCustomSpacing:MacLCDesign.spacingS afterView:_autoStatusLabel];
    [stack setCustomSpacing:MacLCDesign.spacingS afterView:_curveView];
    [stack setCustomSpacing:4.0 afterView:_meterView];
    [stack setCustomSpacing:MacLCDesign.spacingM afterView:_qualitySummaryLabel];
    [stack setCustomSpacing:2.0 afterView:highlightsHeaderRow];
    [stack setCustomSpacing:4.0 afterView:sliderRow];
    [stack setCustomSpacing:MacLCDesign.spacingM afterView:_highlightsCaptionLabel];

    [root addSubview:stack];

    [NSLayoutConstraint activateConstraints:@[
        [root.widthAnchor constraintEqualToConstant:kPanelWidth],
        [stack.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:kPanelPadding],
        [stack.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-kPanelPadding],
        [stack.topAnchor constraintEqualToAnchor:root.topAnchor constant:kPanelPadding],
        [stack.bottomAnchor constraintEqualToAnchor:root.bottomAnchor constant:-kPanelPadding],

        [headerRow.widthAnchor constraintEqualToConstant:inner],
        [_streamInfoLabel.widthAnchor constraintEqualToConstant:inner],
        [_peakDetailLabel.widthAnchor constraintEqualToConstant:inner],
        [_qualitySegment.widthAnchor constraintEqualToConstant:inner],
        [_autoStatusLabel.widthAnchor constraintEqualToConstant:inner],
        [_curveView.widthAnchor constraintEqualToConstant:inner],
        [_curveView.heightAnchor constraintEqualToConstant:110.0],
        [_meterView.widthAnchor constraintEqualToConstant:inner],
        [_qualitySummaryLabel.widthAnchor constraintEqualToConstant:inner],
        [highlightsHeaderRow.widthAnchor constraintEqualToConstant:inner],
        [sliderRow.widthAnchor constraintEqualToConstant:inner],
        [_highlightsCaptionLabel.widthAnchor constraintEqualToConstant:inner],
        [footer.widthAnchor constraintEqualToConstant:inner],
    ]];

    _dimmableViews = @[
        _qualityHeader, _qualitySegment, _autoStatusLabel,
        _curveView, _meterView, _qualitySummaryLabel,
        highlightsHeaderRow, sliderRow, _highlightsCaptionLabel,
        _compareButton
    ];

    self.view = root;
}

- (NSTextField *)sectionHeader:(NSString *)title
{
    NSTextField *label = [NSTextField labelWithString:title];
    label.font = [NSFont systemFontOfSize:MacLCDesign.subheadline.pointSize weight:NSFontWeightSemibold];
    label.textColor = MacLCDesign.secondaryLabel;
    return label;
}

- (NSBox *)separator
{
    NSBox *box = [[NSBox alloc] init];
    box.boxType = NSBoxSeparator;
    box.translatesAutoresizingMaskIntoConstraints = NO;
    [box.widthAnchor constraintEqualToConstant:kPanelWidth - 2 * kPanelPadding].active = YES;
    return box;
}

- (void)viewWillAppear
{
    [super viewWillAppear];
    if (!_polling) {
        _polling = YES;
        [[MacLCSDRToHDRState sharedState] startPolling];
    }
    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(stateDidChange:)
                                               name:MacLCSDRToHDRStateDidChangeNotification
                                             object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(stateDidChange:)
                                               name:MacLCHDRStateDidChangeNotification
                                             object:nil];
    [[MacLCSDRToHDRState sharedState] refresh];
    [self updateAnimated:NO];
}

- (void)viewDidDisappear
{
    [super viewDidDisappear];
    if (_polling) {
        _polling = NO;
        [[MacLCSDRToHDRState sharedState] stopPolling];
    }
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)dealloc
{
    /* A popover torn down without disappearing must not keep the state
     * polling the video output. */
    if (_polling)
        [[MacLCSDRToHDRState sharedState] stopPolling];
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)stateDidChange:(NSNotification *)notification
{
    [self updateAnimated:YES];
}

#pragma mark - Content Updating

- (void)updateAnimated:(BOOL)animated
{
    if (!self.isViewLoaded)
        return;

    MacLCSDRToHDRState *state = [MacLCSDRToHDRState sharedState];
    MacLCHDRController *hdrCtrl = [MacLCHDRController sharedController];
    MacLCDisplayInfo *display = hdrCtrl.display;
    MacLCHDRStreamInfo *stream = hdrCtrl.stream;

    /* The current headroom stays at 1 until something on screen asks for
     * extended range, so whether the display can do HDR at all is read from
     * its effective headroom (the potential one until then); the video output
     * says when it could not expand for lack of headroom right now. */
    const float headroom = (float)display.effectiveHeadroom;
    const BOOL hasHeadroom = headroom > 1.0f;
    const BOOL noHeadroomNow = [state.reason isEqualToString:@"no-headroom"];
    const BOOL enabled = state.enabled && hasHeadroom;

    /* Switch */
    _switchControl.state = state.enabled ? NSControlStateValueOn : NSControlStateValueOff;
    _switchControl.enabled = hasHeadroom;

    /* Stream info */
    if (stream && stream.pixelSize.width > 0 && stream.pixelSize.height > 0) {
        NSString *primaries = (stream.primaries == COLOR_PRIMARIES_BT2020) ? @"BT.2020" : @"BT.709";
        _streamInfoLabel.stringValue = [NSString stringWithFormat:@"%.0f×%.0f · SDR · %@",
                                        stream.pixelSize.width, stream.pixelSize.height, primaries];
        _streamInfoLabel.hidden = NO;
    } else {
        _streamInfoLabel.stringValue = @"";
        _streamInfoLabel.hidden = YES;
    }

    /* Detail / Headroom line */
    NSNumberFormatter *formatter = [[NSNumberFormatter alloc] init];
    formatter.numberStyle = NSNumberFormatterDecimalStyle;
    formatter.maximumFractionDigits = 0;

    if (!hasHeadroom || noHeadroomNow) {
        if (display.potentialHeadroom > 1.0) {
            _peakDetailLabel.stringValue = [NSString stringWithFormat:@"%@ %@",
                _NS("This display has no extended range right now, so SDR video plays as graded."),
                _NS("Lower the brightness a little to give HDR room.")];
        } else {
            _peakDetailLabel.stringValue =
                _NS("This display has no extended range right now, so SDR video plays as graded.");
        }
        _peakDetailLabel.textColor = MacLCDesign.secondaryLabel;
        _peakDetailLabel.hidden = NO;
    } else if (state.enabled) {
        float peak = state.activePeakNits > 0 ? state.activePeakNits : maclc_sdr2hdr_boost_to_nits(state.boost);
        _peakDetailLabel.stringValue = [NSString stringWithFormat:_NS("Highlights reach %@ cd/m² now."),
                                        [formatter stringFromNumber:@((NSInteger)roundf(peak))]];
        _peakDetailLabel.textColor = MacLCDesign.primaryLabel;
        _peakDetailLabel.hidden = NO;
    } else {
        _peakDetailLabel.stringValue = @"";
        _peakDetailLabel.hidden = YES;
    }

    /* Quality selection */
    _qualitySegment.selectedSegment = (NSInteger)state.quality;
    _qualitySegment.enabled = enabled;

    /* A missing model disables its level: only Maximum's when High still
     * runs in its place, both when the output fell back to Balanced. */
    BOOL modelMissing = [state.reason isEqualToString:@"model-missing"];
    BOOL highRuns = modelMissing && state.activeQuality == MacLCSDRToHDRQualityHigh;
    [_qualitySegment setEnabled:enabled && !(modelMissing && !highRuns) forSegment:3];
    [_qualitySegment setEnabled:enabled && !modelMissing forSegment:4];
    [_qualitySegment setToolTip:(modelMissing && !highRuns)
        ? _NS("The model for High isn't installed.")
        : [MacLCSDRToHDRState summaryForQuality:MacLCSDRToHDRQualityHigh] forSegment:3];
    [_qualitySegment setToolTip:modelMissing
        ? _NS("The model for Maximum isn't installed.")
        : [MacLCSDRToHDRState summaryForQuality:MacLCSDRToHDRQualityMaximum] forSegment:4];

    /* Status line */
    if (state.quality == MacLCSDRToHDRQualityAuto) {
        NSString *exp = [MacLCSDRToHDRState explanationForReason:state.reason];
        NSString *activeName = [MacLCSDRToHDRState displayNameForQuality:state.activeQuality];
        if (exp.length > 0) {
            _autoStatusLabel.stringValue = [NSString stringWithFormat:_NS("Using %@ — %@."), activeName, exp];
        } else {
            _autoStatusLabel.stringValue = [NSString stringWithFormat:_NS("Using %@."), activeName];
        }
        _autoStatusLabel.hidden = !enabled;
    } else if ((state.quality == MacLCSDRToHDRQualityHigh || state.quality == MacLCSDRToHDRQualityMaximum) && modelMissing) {
        if (state.quality == MacLCSDRToHDRQualityHigh)
            _autoStatusLabel.stringValue = _NS("High needs the MacLC model, which isn't installed. Using Balanced instead.");
        else
            _autoStatusLabel.stringValue = highRuns
                ? _NS("Maximum needs its own model, which isn't installed. Using High instead.")
                : _NS("Maximum needs the MacLC model, which isn't installed. Using Balanced instead.");
        _autoStatusLabel.hidden = !enabled;
    } else {
        _autoStatusLabel.stringValue = @"";
        _autoStatusLabel.hidden = YES;
    }

    /* Curve view */
    [_curveView setQuality:state.quality
                     boost:state.boost
                  midtones:state.midtones
                  headroom:headroom
                   enabled:enabled
                  animated:animated];

    /* Tradeoff meter */
    MacLCSDRToHDRQuality effectiveQ = state.quality;
    if (effectiveQ == MacLCSDRToHDRQualityAuto) {
        effectiveQ = state.activeQuality;
        if (effectiveQ == MacLCSDRToHDRQualityAuto) {
            effectiveQ = MacLCSDRToHDRQualityFast;
        }
    }
    NSUInteger pop = 3, trueVal = 2, smooth = 3, battery = 2;
    switch (effectiveQ) {
        case MacLCSDRToHDRQualityFast:
            pop = 3; trueVal = 1; smooth = 1; battery = 3;
            break;
        case MacLCSDRToHDRQualityBalanced:
            pop = 2; trueVal = 2; smooth = 3; battery = 2;
            break;
        case MacLCSDRToHDRQualityHigh:
            pop = 3; trueVal = 3; smooth = 3; battery = 2;
            break;
        case MacLCSDRToHDRQualityMaximum:
            pop = 3; trueVal = 3; smooth = 3; battery = 1;
            break;
        default:
            break;
    }
    if (state.boost <= 2.0f) {
        pop = MIN(pop, 1);
    } else if (state.boost <= 4.0f) {
        pop = MIN(pop, 2);
    }
    [_meterView showLevels:@[@(pop), @(trueVal), @(smooth), @(battery)] animated:animated];

    /* Quality summary */
    _qualitySummaryLabel.stringValue = [MacLCSDRToHDRState summaryForQuality:state.quality];

    /* Slider */
    float log2Boost = log2f(fmaxf(1.0f, state.boost));
    _boostSlider.floatValue = log2Boost;
    _boostSlider.enabled = enabled;

    float roundedNits = roundf(maclc_sdr2hdr_boost_to_nits(state.boost) / 10.0f) * 10.0f;
    NSString *nitsString = [NSString stringWithFormat:@"%@ cd/m²",
                            [formatter stringFromNumber:@((NSInteger)roundedNits)]];
    _highlightsValueLabel.stringValue = nitsString;
    _boostSlider.toolTip = nitsString;

    /* Caption */
    float displayPeak = (float)display.contentPeakNits;
    if (displayPeak <= 0) {
        displayPeak = maclc_hdr_peak_for_headroom(headroom);
    }
    if (roundedNits > displayPeak) {
        _highlightsCaptionLabel.stringValue = [NSString stringWithFormat:
            _NS("Like an HDR master graded to %@ cd/m². This display can show up to %@ cd/m² right now, so highlights stop there."),
            [formatter stringFromNumber:@((NSInteger)roundedNits)],
            [formatter stringFromNumber:@((NSInteger)roundf(displayPeak))]];
    } else {
        _highlightsCaptionLabel.stringValue = [NSString stringWithFormat:
            _NS("Like an HDR master graded to %@ cd/m². This display can show up to %@ cd/m² right now."),
            [formatter stringFromNumber:@((NSInteger)roundedNits)],
            [formatter stringFromNumber:@((NSInteger)roundf(displayPeak))]];
    }

    /* Compare button */
    _compareButton.enabled = enabled;

    /* Dimming */
    const CGFloat alpha = enabled ? 1.0 : 0.4;
    for (NSView *v in _dimmableViews) {
        v.alphaValue = alpha;
    }

    self.preferredContentSize = self.view.fittingSize;
}

#pragma mark - Actions

- (void)switchToggled:(NSSwitch *)sender
{
    const BOOL on = (sender.state == NSControlStateValueOn);
    [MacLCSDRToHDRState sharedState].enabled = on;
    if (on) {
        NSString *name = [MacLCSDRToHDRState displayNameForQuality:[MacLCSDRToHDRState sharedState].activeQuality];
        [[MacLCOSDController sharedController] showMessage:[NSString stringWithFormat:_NS("SDR to HDR: %@"), name]
                                                symbolName:@"sun.max"];
    } else {
        [[MacLCOSDController sharedController] showMessage:_NS("SDR to HDR Off")
                                                symbolName:@"sun.min"];
    }
}

- (void)qualityChanged:(NSSegmentedControl *)sender
{
    const MacLCSDRToHDRQuality q = (MacLCSDRToHDRQuality)sender.selectedSegment;
    [MacLCSDRToHDRState sharedState].quality = q;

    NSString *name = [MacLCSDRToHDRState displayNameForQuality:q];
    NSAccessibilityPostNotificationWithUserInfo(self.view,
        NSAccessibilityAnnouncementRequestedNotification,
        @{ NSAccessibilityAnnouncementKey: [NSString stringWithFormat:_NS("SDR to HDR: %@"), name] });

    [[MacLCOSDController sharedController] showMessage:[NSString stringWithFormat:_NS("SDR to HDR: %@"), name]
                                            symbolName:@"sun.max"];
}

- (void)sliderChanged:(NSSlider *)sender
{
    float boost = powf(2.0f, sender.floatValue);
    [MacLCSDRToHDRState sharedState].boost = boost;
}

- (void)openSettings:(id)sender
{
    [MacLCSDRToHDRPanelViewController closePanel];

    MacLCSettingsWindowController *swc = VLCMain.sharedInstance.settingsWindowController;
    NSInteger i_level = VLCMain.sharedInstance.voutProvider.currentStatusWindowLevel;
    [swc showSettingsWindowWithLevel:i_level];
    [swc selectPaneWithIdentifier:@"video-hdr"];
}

@end
