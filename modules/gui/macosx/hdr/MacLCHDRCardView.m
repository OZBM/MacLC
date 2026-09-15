/*****************************************************************************
 * MacLCHDRCardView.m: the card MacLC shows when an HDR video starts
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

#import "MacLCHDRCardView.h"

#import "extensions/NSString+Helpers.h"
#import "hdr/MacLCHDRController.h"
#import "hdr/MacLCHDRPanelViewController.h"
#import "theme/MacLCDesign.h"
#import "theme/MacLCFormatBadgeView.h"
#import "theme/MacLCGlassView.h"
#import "theme/MacLCSymbolButton.h"

static const CGFloat kCardWidth = 320.0;
static const CGFloat kCardPadding = 16.0;

@implementation MacLCHDRCardView
{
    MacLCGlassView *_glass;
    NSStackView *_badges;
    NSTextField *_headline;
    NSTextField *_reason;
    NSStackView *_adviceRow;
    NSTextField *_advice;
    NSButton *_optionsButton;
    NSTimer *_lingerTimer;
    NSTrackingArea *_tracking;
    BOOL _hovered;
    BOOL _dismissing;
}

+ (void)presentInView:(NSView *)hostView fullScreen:(BOOL)fullScreen
{
    [self dismissFromView:hostView];

    MacLCHDRCardView *card = [[MacLCHDRCardView alloc] initWithFrame:NSZeroRect];
    [hostView addSubview:card positioned:NSWindowAbove relativeTo:nil];
    const CGFloat inset = fullScreen ? MacLCDesign.overlayInsetFullScreen
                                     : MacLCDesign.overlayInsetWindowed;
    [NSLayoutConstraint activateConstraints:@[
        [card.trailingAnchor constraintEqualToAnchor:hostView.trailingAnchor constant:-inset],
        [card.topAnchor constraintEqualToAnchor:hostView.safeAreaLayoutGuide.topAnchor constant:inset],
        [card.widthAnchor constraintEqualToConstant:kCardWidth],
    ]];
    [card update];
    [MacLCDesign animateEntranceOfView:card];
    [card startLingerTimer];

    NSString *announcement = [NSString stringWithFormat:@"%@. %@",
                              card->_headline.stringValue, card->_reason.stringValue];
    NSAccessibilityPostNotificationWithUserInfo(hostView.window ?: (id)hostView,
        NSAccessibilityAnnouncementRequestedNotification,
        @{ NSAccessibilityAnnouncementKey: announcement,
           NSAccessibilityPriorityKey: @(NSAccessibilityPriorityMedium) });
}

+ (void)dismissFromView:(NSView *)hostView
{
    for (NSView *subview in hostView.subviews.copy)
        if ([subview isKindOfClass:[MacLCHDRCardView class]])
            [(MacLCHDRCardView *)subview dismissAnimated:NO];
}

- (instancetype)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (self) {
        [self setUp];
    }
    return self;
}

- (void)setUp
{
    self.translatesAutoresizingMaskIntoConstraints = NO;
    self.wantsLayer = YES;
    self.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];

    _glass = [[MacLCGlassView alloc] initWithFrame:NSZeroRect];
    _glass.translatesAutoresizingMaskIntoConstraints = NO;
    _glass.cornerRadius = MacLCDesign.cardCornerRadius;
    _glass.forcesDarkAppearance = YES;
    [self addSubview:_glass];

    _badges = [[NSStackView alloc] init];
    _badges.spacing = 6.0;

    MacLCSymbolButton *close =
        [MacLCSymbolButton buttonWithSymbolName:@"xmark"
                                          label:_NS("Close")
                                      pointSize:11.0
                                         target:self
                                         action:@selector(closeClicked:)];
    NSView *spacer = [[NSView alloc] init];
    [spacer setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
    NSStackView *topRow = [NSStackView stackViewWithViews:@[_badges, spacer, close]];
    topRow.alignment = NSLayoutAttributeCenterY;

    _headline = [NSTextField labelWithString:@""];
    _headline.font = MacLCDesign.headline;
    _headline.textColor = MacLCDesign.primaryLabel;

    _reason = [NSTextField wrappingLabelWithString:@""];
    _reason.font = MacLCDesign.callout;
    _reason.textColor = MacLCDesign.secondaryLabel;
    _reason.preferredMaxLayoutWidth = kCardWidth - 2 * kCardPadding;

    NSImageView *sun = [[NSImageView alloc] init];
    sun.image = [NSImage imageWithSystemSymbolName:@"sun.max" accessibilityDescription:nil];
    sun.contentTintColor = MacLCDesign.warning;
    _advice = [NSTextField wrappingLabelWithString:@""];
    _advice.font = MacLCDesign.footnote;
    _advice.textColor = MacLCDesign.primaryLabel;
    _advice.preferredMaxLayoutWidth = kCardWidth - 2 * kCardPadding - 24.0;
    _adviceRow = [NSStackView stackViewWithViews:@[sun, _advice]];
    _adviceRow.alignment = NSLayoutAttributeTop;
    _adviceRow.spacing = 6.0;

    _optionsButton = [NSButton buttonWithTitle:_NS("Options…")
                                        target:self
                                        action:@selector(optionsClicked:)];
    _optionsButton.controlSize = NSControlSizeSmall;
    _optionsButton.keyEquivalent = @"";
    NSStackView *buttons = [NSStackView stackViewWithViews:@[_optionsButton]];

    NSStackView *stack = [NSStackView stackViewWithViews:@[topRow, _headline, _reason, _adviceRow, buttons]];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 6.0;
    [stack setCustomSpacing:10.0 afterView:topRow];
    [stack setCustomSpacing:10.0 afterView:_adviceRow];
    [stack setCustomSpacing:10.0 afterView:_reason];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [_glass.contentView addSubview:stack];

    [NSLayoutConstraint activateConstraints:@[
        [_glass.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [_glass.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [_glass.topAnchor constraintEqualToAnchor:self.topAnchor],
        [_glass.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:_glass.contentView.leadingAnchor constant:kCardPadding],
        [stack.trailingAnchor constraintEqualToAnchor:_glass.contentView.trailingAnchor constant:-kCardPadding],
        [stack.topAnchor constraintEqualToAnchor:_glass.contentView.topAnchor constant:12.0],
        [stack.bottomAnchor constraintEqualToAnchor:_glass.contentView.bottomAnchor constant:-kCardPadding],
        [topRow.widthAnchor constraintEqualToAnchor:stack.widthAnchor],
    ]];

    self.accessibilityElement = YES;
    self.accessibilityRole = NSAccessibilityGroupRole;
    self.accessibilityLabel = _NS("HDR");

    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(stateDidChange:)
                                               name:MacLCHDRStateDidChangeNotification
                                             object:nil];
}

- (void)dealloc
{
    [_lingerTimer invalidate];
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)stateDidChange:(NSNotification *)notification
{
    [self update];
}

- (void)update
{
    MacLCHDRController *controller = [MacLCHDRController sharedController];
    MacLCHDRStreamInfo *stream = controller.stream;
    MacLCHDRRecommendation *recommendation = controller.recommendation;
    const MacLCHDRPresentation active = controller.activePresentation;

    for (NSView *view in _badges.arrangedSubviews.copy)
        [_badges removeView:view];
    for (NSNumber *number in stream.availablePresentations) {
        const MacLCHDRPresentation p = number.integerValue;
        if (p == MacLCHDRPresentationSDR)
            continue;
        [_badges addArrangedSubview:[MacLCFormatBadgeView badgeWithTitle:MacLCHDRPresentationBadgeTitle(p)
                                                                  active:(p == active)]];
    }

    _headline.stringValue = [NSString stringWithFormat:_NS("Playing in %@"),
                             MacLCHDRPresentationDisplayName(active)];
    /* The reason explains MacLC's pick; when the user picked something else,
     * say what that choice does instead. */
    _reason.stringValue = (recommendation && recommendation.presentation == active)
        ? recommendation.reason
        : MacLCHDRPresentationSummary(active);
    NSString *advice = recommendation.brightnessAdvice ?: recommendation.warning;
    _advice.stringValue = advice ?: @"";
    _adviceRow.hidden = advice == nil;
}

#pragma mark - Lifetime

- (void)startLingerTimer
{
    [_lingerTimer invalidate];
    __weak typeof(self) weakSelf = self;
    _lingerTimer = [NSTimer scheduledTimerWithTimeInterval:MacLCDesign.hdrCardLinger
                                                   repeats:NO
                                                     block:^(NSTimer *timer) {
        typeof(self) strongSelf = weakSelf;
        if (strongSelf != nil && !strongSelf->_hovered)
            [strongSelf dismissAnimated:YES];
    }];
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

- (void)mouseEntered:(NSEvent *)event
{
    _hovered = YES;
    [_lingerTimer invalidate];
    _lingerTimer = nil;
}

- (void)mouseExited:(NSEvent *)event
{
    _hovered = NO;
    [self startLingerTimer];
}

/* Clicks on the card never reach the video underneath (no pause toggle). */
- (void)mouseDown:(NSEvent *)event {}
- (void)mouseUp:(NSEvent *)event {}

- (void)dismissAnimated:(BOOL)animated
{
    if (_dismissing)
        return;
    _dismissing = YES;
    [_lingerTimer invalidate];
    _lingerTimer = nil;
    if (!animated) {
        [self removeFromSuperview];
        return;
    }
    __weak typeof(self) weakSelf = self;
    [MacLCDesign animateExitOfView:self completion:^{
        [weakSelf removeFromSuperview];
    }];
}

#pragma mark - Actions

- (void)closeClicked:(id)sender
{
    [self dismissAnimated:YES];
}

- (void)optionsClicked:(id)sender
{
    NSView *host = self.superview;
    if (host != nil)
        [MacLCHDRPanelViewController showRelativeToRect:self.frame
                                                 ofView:host
                                          preferredEdge:NSRectEdgeMinX];
    [self dismissAnimated:YES];
}

@end
