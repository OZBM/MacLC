/*****************************************************************************
 * MacLCFrameInterpolationPanelViewController.m
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

#import "MacLCFrameInterpolationPanelViewController.h"

#import "main/VLCMain.h"

#import "MacLCFrameInterpolation.h"
#import "extensions/NSString+Helpers.h"
#import "playqueue/VLCPlayQueueController.h"
#import "playqueue/VLCPlayerController.h"
#import "theme/MacLCDesign.h"

static const CGFloat kPanelWidth = 360.0;
static const CGFloat kPanelPadding = 16.0;

@implementation MacLCFrameInterpolationPanelViewController
{
    NSTextField *_titleLabel;
    NSTextField *_detailLabel;
    NSSwitch *_switchControl;
    NSTextField *_switchLabel;
    NSPopUpButton *_enginePopup;
    NSTextField *_engineSummary;
    NSStackView *_svpRifeRow;
    NSTextField *_svpRifeLabel;
    NSSwitch *_svpRifeSwitch;
    NSPopUpButton *_targetPopup;
    NSTextField *_resultLabel;
    NSStackView *_mainStack;
}

static NSPopover *gPopover;
static __weak NSView *gAnchor;

+ (void)showRelativeToView:(NSView *)view preferredEdge:(NSRectEdge)edge
{
    if (gPopover.isShown && gAnchor == view) {
        [gPopover performClose:nil];
        return;
    }
    [gPopover close];

    NSPopover * const popover = [[NSPopover alloc] init];
    popover.behavior = NSPopoverBehaviorTransient;
    popover.animates = !MacLCDesign.reducedMotion;
    popover.contentViewController =
        [[MacLCFrameInterpolationPanelViewController alloc] init];
    gPopover = popover;
    gAnchor = view;
    [popover showRelativeToRect:view.bounds ofView:view preferredEdge:edge];
}

+ (void)closePanel
{
    [gPopover close];
}

- (void)loadView
{
    NSView * const root = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, kPanelWidth, 260)];
    root.translatesAutoresizingMaskIntoConstraints = NO;

    _titleLabel = [NSTextField labelWithString:_NS("Motion Interpolation")];
    _titleLabel.font = MacLCDesign.title3;

    _detailLabel = [NSTextField wrappingLabelWithString:
        _NS("Makes up the frames between the ones the video carries, so motion "
            "runs at the rate of the display instead of stepping.")];
    _detailLabel.font = MacLCDesign.footnote;
    _detailLabel.textColor = MacLCDesign.secondaryLabel;

    _switchLabel = [NSTextField labelWithString:_NS("Interpolate Frames")];
    _switchLabel.font = MacLCDesign.body;
    _switchControl = [NSSwitch new];
    _switchControl.target = self;
    _switchControl.action = @selector(switchChanged:);
    _switchControl.translatesAutoresizingMaskIntoConstraints = NO;
    NSView * const spacer = [[NSView alloc] initWithFrame:NSZeroRect];
    spacer.translatesAutoresizingMaskIntoConstraints = NO;
    NSStackView * const switchRow =
        [NSStackView stackViewWithViews:@[_switchLabel, spacer, _switchControl]];
    switchRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    switchRow.alignment = NSLayoutAttributeCenterY;
    switchRow.spacing = MacLCDesign.spacingS;
    [switchRow setHuggingPriority:NSLayoutPriorityDefaultLow
                   forOrientation:NSLayoutConstraintOrientationHorizontal];

    _enginePopup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    _enginePopup.autoenablesItems = NO;
    for (MacLCFrameInterpolationEngine engine = MacLCFrameInterpolationEngineAutomatic;
         engine <= MacLCFrameInterpolationEngineRIFE; engine++) {
        [_enginePopup addItemWithTitle:[MacLCFrameInterpolation nameForEngine:engine]];
        _enginePopup.lastItem.tag = engine;
        _enginePopup.lastItem.toolTip = [MacLCFrameInterpolation summaryForEngine:engine];
    }
    _enginePopup.target = self;
    _enginePopup.action = @selector(engineChanged:);
    _enginePopup.translatesAutoresizingMaskIntoConstraints = NO;

    _engineSummary = [NSTextField wrappingLabelWithString:@""];
    _engineSummary.font = MacLCDesign.footnote;
    _engineSummary.textColor = MacLCDesign.secondaryLabel;

    _svpRifeLabel = [NSTextField labelWithString:_NS("RIFE neural network")];
    _svpRifeLabel.font = MacLCDesign.body;
    _svpRifeSwitch = [NSSwitch new];
    _svpRifeSwitch.target = self;
    _svpRifeSwitch.action = @selector(svpRifeChanged:);
    _svpRifeSwitch.accessibilityLabel = _NS("RIFE neural network");
    _svpRifeSwitch.translatesAutoresizingMaskIntoConstraints = NO;
    NSView * const rifeSpacer = [[NSView alloc] initWithFrame:NSZeroRect];
    rifeSpacer.translatesAutoresizingMaskIntoConstraints = NO;
    _svpRifeRow =
        [NSStackView stackViewWithViews:@[_svpRifeLabel, rifeSpacer, _svpRifeSwitch]];
    _svpRifeRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    _svpRifeRow.alignment = NSLayoutAttributeCenterY;
    _svpRifeRow.spacing = MacLCDesign.spacingS;
    [_svpRifeRow setHuggingPriority:NSLayoutPriorityDefaultLow
                     forOrientation:NSLayoutConstraintOrientationHorizontal];
    _svpRifeRow.translatesAutoresizingMaskIntoConstraints = NO;

    _targetPopup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    for (MacLCFrameInterpolationTarget target = MacLCFrameInterpolationTargetDisplay;
         target <= MacLCFrameInterpolationTargetDouble; target++) {
        [_targetPopup addItemWithTitle:[MacLCFrameInterpolation nameForTarget:target]];
        _targetPopup.lastItem.tag = target;
    }
    _targetPopup.target = self;
    _targetPopup.action = @selector(targetChanged:);
    _targetPopup.translatesAutoresizingMaskIntoConstraints = NO;

    _resultLabel = [NSTextField wrappingLabelWithString:@""];
    _resultLabel.font = MacLCDesign.footnote;
    _resultLabel.textColor = MacLCDesign.secondaryLabel;

    NSStackView * const stack = [NSStackView stackViewWithViews:@[
        _titleLabel, _detailLabel,
        switchRow,
        [self sectionHeader:_NS("Method")], _enginePopup, _engineSummary,
        _svpRifeRow,
        [self sectionHeader:_NS("Frame Rate")], _targetPopup,
        [self separator], _resultLabel,
    ]];
    _mainStack = stack;
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = MacLCDesign.spacingS;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [stack setCustomSpacing:2.0 afterView:_titleLabel];
    [stack setCustomSpacing:MacLCDesign.spacingM afterView:_detailLabel];
    [stack setCustomSpacing:MacLCDesign.spacingM afterView:switchRow];
    [stack setCustomSpacing:MacLCDesign.spacingM afterView:_engineSummary];

    [root addSubview:stack];
    const CGFloat inner = kPanelWidth - 2 * kPanelPadding;
    [NSLayoutConstraint activateConstraints:@[
        [root.widthAnchor constraintEqualToConstant:kPanelWidth],
        [stack.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:kPanelPadding],
        [stack.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-kPanelPadding],
        [stack.topAnchor constraintEqualToAnchor:root.topAnchor constant:kPanelPadding],
        [stack.bottomAnchor constraintEqualToAnchor:root.bottomAnchor constant:-kPanelPadding],
        [switchRow.widthAnchor constraintEqualToConstant:inner],
        [_enginePopup.widthAnchor constraintEqualToConstant:inner],
        [_svpRifeRow.widthAnchor constraintEqualToConstant:inner],
        [_targetPopup.widthAnchor constraintEqualToConstant:inner],
    ]];
    _detailLabel.preferredMaxLayoutWidth = inner;
    _engineSummary.preferredMaxLayoutWidth = inner;
    _resultLabel.preferredMaxLayoutWidth = inner;

    self.view = root;
}

- (NSTextField *)sectionHeader:(NSString *)title
{
    NSTextField * const label = [NSTextField labelWithString:title];
    label.font = [NSFont systemFontOfSize:MacLCDesign.subheadline.pointSize
                                   weight:NSFontWeightSemibold];
    label.textColor = MacLCDesign.secondaryLabel;
    return label;
}

- (NSBox *)separator
{
    NSBox * const box = [[NSBox alloc] init];
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
                                               name:MacLCFrameInterpolationChangedNotification
                                             object:nil];
    [self update];
}

- (void)viewDidDisappear
{
    [super viewDidDisappear];
    [NSNotificationCenter.defaultCenter removeObserver:self
                                                  name:MacLCFrameInterpolationChangedNotification
                                                object:nil];
}

- (void)stateDidChange:(NSNotification *)notification
{
    [self update];
}

- (void)update
{
    const BOOL enabled = MacLCFrameInterpolation.isEnabled;
    _switchControl.state = enabled ? NSControlStateValueOn : NSControlStateValueOff;

    for (NSMenuItem *item in _enginePopup.itemArray) {
        NSString * const reason =
            [MacLCFrameInterpolation unavailabilityReasonForEngine:(MacLCFrameInterpolationEngine)item.tag];
        [item setEnabled:(reason == nil)];
        item.toolTip = reason ?: [MacLCFrameInterpolation summaryForEngine:(MacLCFrameInterpolationEngine)item.tag];
    }

    [_enginePopup selectItemWithTag:MacLCFrameInterpolation.engine];
    [_targetPopup selectItemWithTag:MacLCFrameInterpolation.target];
    _enginePopup.enabled = enabled;
    _targetPopup.enabled = enabled;

    NSString * const unavailability =
        [MacLCFrameInterpolation unavailabilityReasonForEngine:MacLCFrameInterpolation.engine];
    if (unavailability != nil) {
        _engineSummary.stringValue = unavailability;
        _engineSummary.textColor = MacLCDesign.warning;
    } else {
        _engineSummary.stringValue =
            [MacLCFrameInterpolation summaryForEngine:MacLCFrameInterpolation.engine];
        _engineSummary.textColor =
            enabled ? MacLCDesign.secondaryLabel : MacLCDesign.tertiaryLabel;
    }

    const BOOL isSVP = (MacLCFrameInterpolation.engine == MacLCFrameInterpolationEngineSVP);
    _svpRifeRow.hidden = !isSVP;
    _svpRifeSwitch.state = MacLCFrameInterpolation.isRIFEEnabled ? NSControlStateValueOn : NSControlStateValueOff;
    _svpRifeSwitch.enabled = enabled;
    if (isSVP) {
        [_mainStack setCustomSpacing:MacLCDesign.spacingS afterView:_engineSummary];
        [_mainStack setCustomSpacing:MacLCDesign.spacingM afterView:_svpRifeRow];
    } else {
        [_mainStack setCustomSpacing:MacLCDesign.spacingM afterView:_engineSummary];
        [_mainStack setCustomSpacing:0.0 afterView:_svpRifeRow];
    }

    VLCPlayerController * const player =
        VLCMain.sharedInstance.playQueueController.playerController;
    const unsigned source = player.selectedVideoTrack.videoFrameRate;
    const unsigned output =
        [MacLCFrameInterpolation outputFrameRateForSourceFrameRate:source];

    if (source == 0) {
        _resultLabel.stringValue =
            _NS("Nothing is playing, so there is no frame rate to work from yet.");
    } else if (output == 0) {
        _resultLabel.stringValue =
            [NSString stringWithFormat:
                _NS("This video runs at %u fps, which the display already matches: "
                    "there is nothing to interpolate."), source];
    } else if (enabled) {
        _resultLabel.stringValue =
            [NSString stringWithFormat:_NS("Playing %u fps as %u fps."), source, output];
    } else {
        _resultLabel.stringValue =
            [NSString stringWithFormat:_NS("Would play %u fps as %u fps."), source, output];
    }

    self.preferredContentSize = self.view.fittingSize;
}

#pragma mark - actions

- (void)switchChanged:(id)sender
{
    [MacLCFrameInterpolation
        setEnabled:_switchControl.state == NSControlStateValueOn];
    [self update];
}

- (void)svpRifeChanged:(id)sender
{
    MacLCFrameInterpolation.RIFEEnabled = (_svpRifeSwitch.state == NSControlStateValueOn);
    [self update];
}

- (void)engineChanged:(id)sender
{
    MacLCFrameInterpolation.engine =
        (MacLCFrameInterpolationEngine)_enginePopup.selectedTag;
    [self update];
}

- (void)targetChanged:(id)sender
{
    MacLCFrameInterpolation.target =
        (MacLCFrameInterpolationTarget)_targetPopup.selectedTag;
    [self update];
}

@end
