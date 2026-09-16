/*****************************************************************************
 * MacLCHDRPanelViewController.m: MacLC's HDR options popover
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

#import "MacLCHDRPanelViewController.h"

#import "extensions/NSString+Helpers.h"
#import "hdr/MacLCHDRController.h"
#import "hdr/MacLCToneCurveView.h"
#import "hdr/MacLCTradeoffMeterView.h"
#import "theme/MacLCDesign.h"

#include "../../video_output/apple/maclc_hdr_vars.h"

static const CGFloat kPanelWidth = 380.0;
static const CGFloat kPanelPadding = 16.0;

#pragma mark - Format row

/* One presentation the video offers: selectable like a radio button. */
@interface MacLCHDRFormatRow : NSView
@property (nonatomic) MacLCHDRPresentation presentation;
@property (nonatomic, getter=isSelected) BOOL selected;
@property (nonatomic, getter=isEnabled) BOOL enabled;
@property (nonatomic, weak) id target;
@property (nonatomic) SEL action;
- (void)configureWithTitle:(NSString *)title
                   summary:(NSString *)summary
               recommended:(BOOL)recommended;
@end

@implementation MacLCHDRFormatRow
{
    NSImageView *_indicator;
    NSTextField *_title;
    NSTextField *_summary;
    NSTextField *_pill;
    NSTrackingArea *_tracking;
    BOOL _hovered;
}

- (instancetype)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (self) {
        _enabled = YES;
        self.wantsLayer = YES;
        self.layer.cornerRadius = MacLCDesign.cornerRadiusMedium;
        self.translatesAutoresizingMaskIntoConstraints = NO;

        _indicator = [[NSImageView alloc] init];
        _indicator.translatesAutoresizingMaskIntoConstraints = NO;
        _indicator.symbolConfiguration =
            [NSImageSymbolConfiguration configurationWithPointSize:15.0 weight:NSFontWeightRegular];

        _title = [NSTextField labelWithString:@""];
        _title.font = MacLCDesign.bodyEmphasized;
        _title.textColor = MacLCDesign.primaryLabel;

        _summary = [NSTextField wrappingLabelWithString:@""];
        _summary.font = MacLCDesign.footnote;
        _summary.textColor = MacLCDesign.secondaryLabel;
        _summary.preferredMaxLayoutWidth = kPanelWidth - 2 * kPanelPadding - 70.0;

        _pill = [NSTextField labelWithString:_NS("Recommended")];
        _pill.font = MacLCDesign.badgeFont;
        _pill.textColor = MacLCDesign.accent;
        _pill.wantsLayer = YES;
        _pill.alignment = NSTextAlignmentCenter;

        NSStackView *titleRow = [NSStackView stackViewWithViews:@[_title, _pill]];
        titleRow.spacing = MacLCDesign.spacingS;
        titleRow.alignment = NSLayoutAttributeFirstBaseline;
        NSStackView *texts = [NSStackView stackViewWithViews:@[titleRow, _summary]];
        texts.orientation = NSUserInterfaceLayoutOrientationVertical;
        texts.alignment = NSLayoutAttributeLeading;
        texts.spacing = 2.0;
        texts.translatesAutoresizingMaskIntoConstraints = NO;

        [self addSubview:_indicator];
        [self addSubview:texts];
        [NSLayoutConstraint activateConstraints:@[
            [_indicator.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:10.0],
            [_indicator.topAnchor constraintEqualToAnchor:self.topAnchor constant:9.0],
            [_indicator.widthAnchor constraintEqualToConstant:18.0],
            [texts.leadingAnchor constraintEqualToAnchor:_indicator.trailingAnchor constant:10.0],
            [texts.trailingAnchor constraintLessThanOrEqualToAnchor:self.trailingAnchor constant:-10.0],
            [texts.topAnchor constraintEqualToAnchor:self.topAnchor constant:8.0],
            [texts.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-8.0],
        ]];
    }
    return self;
}

- (void)configureWithTitle:(NSString *)title
                   summary:(NSString *)summary
               recommended:(BOOL)recommended
{
    _title.stringValue = title;
    _summary.stringValue = summary;
    _pill.hidden = !recommended;
    [self refreshAppearance];
    self.accessibilityLabel = recommended
        ? [NSString stringWithFormat:_NS("%@, recommended. %@"), title, summary]
        : [NSString stringWithFormat:@"%@. %@", title, summary];
}

- (void)setSelected:(BOOL)selected
{
    _selected = selected;
    [self refreshAppearance];
}

- (void)setEnabled:(BOOL)enabled
{
    _enabled = enabled;
    [self refreshAppearance];
}

- (void)refreshAppearance
{
    NSString *symbol = _selected ? @"checkmark.circle.fill" : @"circle";
    _indicator.image = [NSImage imageWithSystemSymbolName:symbol accessibilityDescription:nil];
    _indicator.contentTintColor = _selected ? MacLCDesign.accent : MacLCDesign.tertiaryLabel;
    _title.textColor = _enabled ? MacLCDesign.primaryLabel : MacLCDesign.tertiaryLabel;
    [self.effectiveAppearance performAsCurrentDrawingAppearance:^{
        NSColor *fill = self->_selected ? [MacLCDesign.accent colorWithAlphaComponent:0.12]
                      : (self->_hovered && self->_enabled
                            ? [MacLCDesign.primaryLabel colorWithAlphaComponent:0.06]
                            : NSColor.clearColor);
        self.layer.backgroundColor = fill.CGColor;
    }];
}

- (void)viewDidChangeEffectiveAppearance
{
    [super viewDidChangeEffectiveAppearance];
    [self refreshAppearance];
}

- (void)updateTrackingAreas
{
    [super updateTrackingAreas];
    if (_tracking)
        [self removeTrackingArea:_tracking];
    _tracking = [[NSTrackingArea alloc] initWithRect:self.bounds
        options:NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways | NSTrackingInVisibleRect
          owner:self userInfo:nil];
    [self addTrackingArea:_tracking];
}

- (void)mouseEntered:(NSEvent *)event { _hovered = YES; [self refreshAppearance]; }
- (void)mouseExited:(NSEvent *)event { _hovered = NO; [self refreshAppearance]; }

- (void)mouseUp:(NSEvent *)event
{
    const NSPoint p = [self convertPoint:event.locationInWindow fromView:nil];
    if (_enabled && NSPointInRect(p, self.bounds))
        [self activate];
}

- (void)mouseDown:(NSEvent *)event { /* handled on mouse up */ }

- (void)activate
{
    if (_enabled && _target && _action)
        [NSApp sendAction:_action to:_target from:self];
}

- (BOOL)acceptsFirstResponder { return _enabled; }
- (BOOL)canBecomeKeyView { return _enabled; }

- (void)keyDown:(NSEvent *)event
{
    if ([event.charactersIgnoringModifiers isEqualToString:@" "]
        || [event.charactersIgnoringModifiers isEqualToString:@"\r"])
        [self activate];
    else
        [super keyDown:event];
}

- (void)drawFocusRingMask
{
    NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:self.bounds
                                                         xRadius:MacLCDesign.cornerRadiusMedium
                                                         yRadius:MacLCDesign.cornerRadiusMedium];
    [path fill];
}

- (NSRect)focusRingMaskBounds { return self.bounds; }

- (BOOL)isAccessibilityElement { return YES; }
- (NSAccessibilityRole)accessibilityRole { return NSAccessibilityRadioButtonRole; }
- (id)accessibilityValue { return @(_selected); }
- (BOOL)isAccessibilityEnabled { return _enabled; }
- (BOOL)accessibilityPerformPress { [self activate]; return YES; }

@end

#pragma mark - Panel

@implementation MacLCHDRPanelViewController
{
    NSTextField *_titleLabel;
    NSTextField *_detailLabel;
    NSTextField *_warningLabel;
    NSStackView *_formatStack;
    NSSegmentedControl *_pictureControl;
    MacLCToneCurveView *_curveView;
    MacLCTradeoffMeterView *_meterView;
    NSTextField *_pictureSummary;
    NSImageView *_displayIcon;
    NSTextField *_displayName;
    NSTextField *_displayDetail;
    NSStackView *_adviceRow;
    NSTextField *_adviceLabel;
    NSPopUpButton *_cardPolicyPopup;
    NSButton *_defaultButton;
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
    [gPopover close];

    NSPopover *popover = [[NSPopover alloc] init];
    popover.behavior = NSPopoverBehaviorTransient;
    popover.animates = !MacLCDesign.reducedMotion;
    popover.contentViewController = [[MacLCHDRPanelViewController alloc] init];
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
    [gPopover close];
}

- (void)loadView
{
    NSView *root = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, kPanelWidth, 400)];
    root.translatesAutoresizingMaskIntoConstraints = NO;

    /* Header */
    _titleLabel = [NSTextField labelWithString:@""];
    _titleLabel.font = MacLCDesign.title3;
    _detailLabel = [NSTextField wrappingLabelWithString:@""];
    _detailLabel.font = MacLCDesign.footnote;
    _detailLabel.textColor = MacLCDesign.secondaryLabel;
    _warningLabel = [NSTextField wrappingLabelWithString:@""];
    _warningLabel.font = MacLCDesign.footnote;
    _warningLabel.textColor = MacLCDesign.warning;

    /* Format */
    _formatStack = [[NSStackView alloc] init];
    _formatStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    _formatStack.alignment = NSLayoutAttributeLeading;
    _formatStack.spacing = 2.0;

    /* Picture */
    _pictureControl = [NSSegmentedControl segmentedControlWithLabels:@[
            _NS("Accurate"), _NS("Balanced"), _NS("Bright")]
                                                        trackingMode:NSSegmentSwitchTrackingSelectOne
                                                              target:self
                                                              action:@selector(pictureChanged:)];
    _pictureControl.segmentDistribution = NSSegmentDistributionFillEqually;
    _pictureControl.translatesAutoresizingMaskIntoConstraints = NO;
    [_pictureControl setToolTip:MacLCHDRPictureModeSummary(MacLCHDRPictureModeAccurate) forSegment:0];
    [_pictureControl setToolTip:MacLCHDRPictureModeSummary(MacLCHDRPictureModeBalanced) forSegment:1];
    [_pictureControl setToolTip:MacLCHDRPictureModeSummary(MacLCHDRPictureModeBright) forSegment:2];

    _curveView = [[MacLCToneCurveView alloc] initWithFrame:NSMakeRect(0, 0, kPanelWidth - 2 * kPanelPadding, 112)];
    _curveView.translatesAutoresizingMaskIntoConstraints = NO;
    _meterView = [[MacLCTradeoffMeterView alloc] initWithFrame:NSZeroRect];
    _pictureSummary = [NSTextField wrappingLabelWithString:@""];
    _pictureSummary.font = MacLCDesign.footnote;
    _pictureSummary.textColor = MacLCDesign.secondaryLabel;

    /* Display */
    _displayIcon = [[NSImageView alloc] init];
    _displayIcon.image = [NSImage imageWithSystemSymbolName:@"display" accessibilityDescription:nil];
    _displayIcon.symbolConfiguration =
        [NSImageSymbolConfiguration configurationWithPointSize:17.0 weight:NSFontWeightRegular];
    _displayIcon.contentTintColor = MacLCDesign.secondaryLabel;
    _displayName = [NSTextField labelWithString:@""];
    _displayName.font = MacLCDesign.body;
    _displayDetail = [NSTextField wrappingLabelWithString:@""];
    _displayDetail.font = MacLCDesign.footnote;
    _displayDetail.textColor = MacLCDesign.secondaryLabel;
    NSStackView *displayTexts = [NSStackView stackViewWithViews:@[_displayName, _displayDetail]];
    displayTexts.orientation = NSUserInterfaceLayoutOrientationVertical;
    displayTexts.alignment = NSLayoutAttributeLeading;
    displayTexts.spacing = 2.0;
    NSStackView *displayRow = [NSStackView stackViewWithViews:@[_displayIcon, displayTexts]];
    displayRow.alignment = NSLayoutAttributeTop;
    displayRow.spacing = MacLCDesign.spacingS;

    NSImageView *sun = [[NSImageView alloc] init];
    sun.image = [NSImage imageWithSystemSymbolName:@"sun.max" accessibilityDescription:nil];
    sun.contentTintColor = MacLCDesign.warning;
    _adviceLabel = [NSTextField wrappingLabelWithString:@""];
    _adviceLabel.font = MacLCDesign.footnote;
    _adviceLabel.textColor = MacLCDesign.primaryLabel;
    _adviceRow = [NSStackView stackViewWithViews:@[sun, _adviceLabel]];
    _adviceRow.alignment = NSLayoutAttributeTop;
    _adviceRow.spacing = MacLCDesign.spacingS;

    /* Footer */
    NSTextField *cardLabel = [NSTextField labelWithString:_NS("Show on open:")];
    cardLabel.font = MacLCDesign.footnote;
    cardLabel.textColor = MacLCDesign.secondaryLabel;
    _cardPolicyPopup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    _cardPolicyPopup.controlSize = NSControlSizeSmall;
    _cardPolicyPopup.font = MacLCDesign.footnote;
    [_cardPolicyPopup addItemsWithTitles:@[_NS("Always"), _NS("When There’s a Choice"), _NS("Never")]];
    _cardPolicyPopup.target = self;
    _cardPolicyPopup.action = @selector(cardPolicyChanged:);
    _defaultButton = [NSButton buttonWithTitle:_NS("Use for All HDR Videos")
                                        target:self
                                        action:@selector(useAsDefault:)];
    _defaultButton.bezelStyle = NSBezelStyleAccessoryBarAction;
    _defaultButton.controlSize = NSControlSizeSmall;
    _defaultButton.toolTip = _NS("Makes this format and picture mode the default for every HDR video.");
    NSView *spacer = [[NSView alloc] init];
    [spacer setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
    NSStackView *footer = [NSStackView stackViewWithViews:@[cardLabel, _cardPolicyPopup, spacer, _defaultButton]];
    footer.spacing = MacLCDesign.spacingXS;

    NSStackView *stack = [NSStackView stackViewWithViews:@[
        _titleLabel, _detailLabel, _warningLabel,
        [self sectionHeader:_NS("Format")], _formatStack,
        [self sectionHeader:_NS("Picture")], _pictureControl, _curveView, _meterView, _pictureSummary,
        [self sectionHeader:_NS("Display")], displayRow, _adviceRow,
        [self separator], footer,
    ]];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = MacLCDesign.spacingS;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [stack setCustomSpacing:2.0 afterView:_titleLabel];
    [stack setCustomSpacing:MacLCDesign.spacingM afterView:_warningLabel];
    [stack setCustomSpacing:MacLCDesign.spacingM afterView:_formatStack];
    [stack setCustomSpacing:MacLCDesign.spacingM afterView:_pictureSummary];
    [stack setCustomSpacing:MacLCDesign.spacingM afterView:_adviceRow];

    [root addSubview:stack];
    const CGFloat inner = kPanelWidth - 2 * kPanelPadding;
    [NSLayoutConstraint activateConstraints:@[
        [root.widthAnchor constraintEqualToConstant:kPanelWidth],
        [stack.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:kPanelPadding],
        [stack.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-kPanelPadding],
        [stack.topAnchor constraintEqualToAnchor:root.topAnchor constant:kPanelPadding],
        [stack.bottomAnchor constraintEqualToAnchor:root.bottomAnchor constant:-kPanelPadding],
        [_formatStack.widthAnchor constraintEqualToConstant:inner],
        [_pictureControl.widthAnchor constraintEqualToConstant:inner],
        [_curveView.widthAnchor constraintEqualToConstant:inner],
        [_curveView.heightAnchor constraintEqualToConstant:112.0],
        [_meterView.widthAnchor constraintEqualToConstant:inner],
        [footer.widthAnchor constraintEqualToConstant:inner],
    ]];
    _detailLabel.preferredMaxLayoutWidth = inner;
    _warningLabel.preferredMaxLayoutWidth = inner;
    _pictureSummary.preferredMaxLayoutWidth = inner;
    _displayDetail.preferredMaxLayoutWidth = inner - 30.0;
    _adviceLabel.preferredMaxLayoutWidth = inner - 30.0;

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
    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(stateDidChange:)
                                               name:MacLCHDRStateDidChangeNotification
                                             object:nil];
    [[MacLCHDRController sharedController] refresh];
    [self updateAnimated:NO];
}

- (void)viewDidDisappear
{
    [super viewDidDisappear];
    [NSNotificationCenter.defaultCenter removeObserver:self
                                                  name:MacLCHDRStateDidChangeNotification
                                                object:nil];
}

- (void)stateDidChange:(NSNotification *)notification
{
    [self updateAnimated:YES];
}

#pragma mark - Content

- (NSString *)formatDetailsForStream:(MacLCHDRStreamInfo *)stream
{
    NSNumberFormatter *formatter = [[NSNumberFormatter alloc] init];
    formatter.numberStyle = NSNumberFormatterDecimalStyle;
    formatter.maximumFractionDigits = 0;

    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    if (stream.doviProfile > 0)
        [parts addObject:[NSString stringWithFormat:_NS("Dolby Vision profile %ld"), (long)stream.doviProfile]];
    if (stream.pixelSize.width > 0)
        [parts addObject:[NSString stringWithFormat:@"%.0f×%.0f",
                          stream.pixelSize.width, stream.pixelSize.height]];
    if (stream.bitDepth > 0)
        [parts addObject:[NSString stringWithFormat:_NS("%lu-bit"), (unsigned long)stream.bitDepth]];
    if (stream.masteringPeakNits > 0)
        [parts addObject:[NSString stringWithFormat:_NS("mastered at %@ nits"),
                          [formatter stringFromNumber:@(stream.masteringPeakNits)]]];
    if (stream.maxCLL > 0)
        [parts addObject:[NSString stringWithFormat:_NS("brightest pixel %@ nits"),
                          [formatter stringFromNumber:@(stream.maxCLL)]]];
    return [parts componentsJoinedByString:@" · "];
}

- (void)updateAnimated:(BOOL)animated
{
    if (!self.isViewLoaded)
        return;

    MacLCHDRController *controller = [MacLCHDRController sharedController];
    MacLCHDRStreamInfo *stream = controller.stream;
    MacLCDisplayInfo *display = controller.display;
    MacLCHDRRecommendation *recommendation = controller.recommendation;
    const MacLCHDRPresentation active = controller.activePresentation;

    if (stream == nil || !stream.isHDR) {
        _titleLabel.stringValue = _NS("No HDR video playing");
        _detailLabel.stringValue = _NS("Open an HDR10, HDR10+, Dolby Vision or HLG video to choose how it is shown.");
    } else {
        _titleLabel.stringValue = MacLCHDRPresentationDisplayName(active);
        _detailLabel.stringValue = [self formatDetailsForStream:stream];
    }
    _warningLabel.stringValue = recommendation.warning ?: @"";
    _warningLabel.hidden = recommendation.warning == nil;

    /* Format rows */
    for (NSView *view in _formatStack.arrangedSubviews.copy)
        [_formatStack removeView:view];
    for (NSNumber *number in stream.availablePresentations) {
        const MacLCHDRPresentation p = number.integerValue;
        NSString *why = nil;
        const BOOL selectable = [recommendation isPresentationSelectable:p reason:&why];
        MacLCHDRFormatRow *row = [[MacLCHDRFormatRow alloc] initWithFrame:NSZeroRect];
        row.presentation = p;
        [row configureWithTitle:MacLCHDRPresentationDisplayName(p)
                        summary:selectable ? MacLCHDRPresentationSummary(p) : (why ?: @"")
                    recommended:recommendation.presentation == p];
        row.selected = (p == active);
        row.enabled = selectable;
        row.target = self;
        row.action = @selector(formatChosen:);
        [_formatStack addArrangedSubview:row];
        [row.widthAnchor constraintEqualToAnchor:_formatStack.widthAnchor].active = YES;
    }

    /* Picture */
    const BOOL pq = stream.transfer == TRANSFER_FUNC_SMPTE_ST2084
                 && active != MacLCHDRPresentationSDR
                 && active != MacLCHDRPresentationHLG;
    MacLCHDRPictureMode mode = controller.activePictureMode;
    const BOOL needsToneMapping =
        maclc_hdr_needs_tone_mapping((float)stream.contentPeakNits,
                                     (float)display.contentPeakNits);
    if (mode == MacLCHDRPictureModeAuto)
        mode = needsToneMapping ? MacLCHDRPictureModeBalanced : MacLCHDRPictureModeAccurate;
    _pictureControl.enabled = pq;
    _pictureControl.selectedSegment = pq ? (NSInteger)mode - 1 : -1;
    _curveView.hidden = !pq;
    _meterView.hidden = !pq;
    if (pq) {
        [_curveView setPictureMode:mode
                   contentPeakNits:stream.contentPeakNits
                   displayPeakNits:display.contentPeakNits
                      sdrWhiteNits:display.sdrWhiteNits
                          animated:animated];
        [_meterView showPictureMode:mode needsToneMapping:needsToneMapping animated:animated];
        _pictureSummary.stringValue = MacLCHDRPictureModeSummary(mode);
    } else if (active == MacLCHDRPresentationHLG) {
        _pictureSummary.stringValue = _NS("HLG adapts to your display on its own, so there is nothing to tune.");
    } else if (active == MacLCHDRPresentationSDR) {
        _pictureSummary.stringValue = _NS("Picture modes apply to HDR presentations. Standard range is shown as is.");
    } else {
        _pictureSummary.stringValue = _NS("Picture modes apply to HDR10, HDR10+ and Dolby Vision video.");
    }

    /* Display */
    NSNumberFormatter *formatter = [[NSNumberFormatter alloc] init];
    formatter.numberStyle = NSNumberFormatterDecimalStyle;
    formatter.maximumFractionDigits = 0;
    _displayName.stringValue = display.localizedName.length ? display.localizedName : _NS("Display");
    if (!display.supportsHDR)
        _displayDetail.stringValue = _NS("Standard range. MacLC converts HDR video for this display.");
    else
        _displayDetail.stringValue = [NSString stringWithFormat:_NS("HDR · up to %@ nits · white at %@ nits"),
                                      [formatter stringFromNumber:@(display.panelPeakNits)],
                                      [formatter stringFromNumber:@(display.sdrWhiteNits)]];
    NSString *advice = recommendation.brightnessAdvice;
    if (recommendation.brightnessAdviceSuggestsBright && pq && mode == MacLCHDRPictureModeBright)
        advice = nil;
    _adviceLabel.stringValue = advice ?: @"";
    _adviceRow.hidden = advice == nil;

    /* Footer */
    [_cardPolicyPopup selectItemAtIndex:(NSInteger)controller.cardPolicy];
    _defaultButton.enabled = stream.isHDR;

    self.preferredContentSize = self.view.fittingSize;
}

#pragma mark - Actions

- (void)formatChosen:(MacLCHDRFormatRow *)row
{
    [[MacLCHDRController sharedController] applyPresentation:row.presentation];
    NSAccessibilityPostNotificationWithUserInfo(self.view,
        NSAccessibilityAnnouncementRequestedNotification,
        @{ NSAccessibilityAnnouncementKey:
               [NSString stringWithFormat:_NS("Playing in %@"),
                MacLCHDRPresentationDisplayName(row.presentation)] });
}

- (void)pictureChanged:(NSSegmentedControl *)sender
{
    const MacLCHDRPictureMode mode = (MacLCHDRPictureMode)(sender.selectedSegment + 1);
    [[MacLCHDRController sharedController] applyPictureMode:mode];
}

- (void)cardPolicyChanged:(NSPopUpButton *)sender
{
    [MacLCHDRController sharedController].cardPolicy = (MacLCHDRCardPolicy)sender.indexOfSelectedItem;
}

- (void)useAsDefault:(id)sender
{
    [[MacLCHDRController sharedController] useCurrentChoiceAsDefault];
    _defaultButton.title = _NS("Saved as Default");
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        self->_defaultButton.title = _NS("Use for All HDR Videos");
    });
}

@end
