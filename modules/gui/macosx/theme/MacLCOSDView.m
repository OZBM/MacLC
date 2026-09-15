/*****************************************************************************
 * MacLCOSDView.m: MacLC on-screen display capsule
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

#import "MacLCOSDView.h"

#import "MacLCDesign.h"
#import "MacLCGlassView.h"

static const CGFloat kOSDHeight = 40.0;
static const CGFloat kOSDHorizontalPadding = 16.0;
static const CGFloat kOSDLevelBarWidth = 88.0;
static const CGFloat kOSDLevelBarHeight = 4.0;

@implementation MacLCOSDView
{
    MacLCGlassView *_glass;
    NSImageView *_symbolView;
    NSTextField *_label;
    NSView *_levelTrack;
    NSView *_levelFill;
    NSLayoutConstraint *_levelFillWidth;
    NSLayoutConstraint *_levelTrackWidth;
    NSStackView *_stack;
    NSTimer *_lingerTimer;
    NSTimer *_announceTimer;
    BOOL _presented;
}

- (instancetype)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (self) {
        [self setUp];
    }
    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];
    if (self) {
        [self setUp];
    }
    return self;
}

- (void)setUp
{
    self.wantsLayer = YES;
    self.hidden = YES;
    self.translatesAutoresizingMaskIntoConstraints = NO;
    self.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];

    _glass = [[MacLCGlassView alloc] initWithFrame:self.bounds];
    _glass.translatesAutoresizingMaskIntoConstraints = NO;
    _glass.cornerRadius = kOSDHeight / 2.0;
    _glass.forcesDarkAppearance = YES;
    [self addSubview:_glass];

    _symbolView = [[NSImageView alloc] init];
    _symbolView.translatesAutoresizingMaskIntoConstraints = NO;
    _symbolView.symbolConfiguration =
        [NSImageSymbolConfiguration configurationWithPointSize:15.0
                                                        weight:NSFontWeightMedium];
    _symbolView.contentTintColor = MacLCDesign.primaryLabel;

    _label = [NSTextField labelWithString:@""];
    _label.translatesAutoresizingMaskIntoConstraints = NO;
    _label.font = MacLCDesign.headline;
    _label.textColor = MacLCDesign.primaryLabel;
    _label.lineBreakMode = NSLineBreakByTruncatingTail;
    _label.maximumNumberOfLines = 1;

    _levelTrack = [[NSView alloc] init];
    _levelTrack.translatesAutoresizingMaskIntoConstraints = NO;
    _levelTrack.wantsLayer = YES;
    _levelTrack.layer.cornerRadius = kOSDLevelBarHeight / 2.0;
    _levelFill = [[NSView alloc] init];
    _levelFill.translatesAutoresizingMaskIntoConstraints = NO;
    _levelFill.wantsLayer = YES;
    _levelFill.layer.cornerRadius = kOSDLevelBarHeight / 2.0;
    [_levelTrack addSubview:_levelFill];

    _levelTrackWidth = [_levelTrack.widthAnchor constraintEqualToConstant:kOSDLevelBarWidth];
    _levelFillWidth = [_levelFill.widthAnchor constraintEqualToConstant:0.0];
    [NSLayoutConstraint activateConstraints:@[
        _levelTrackWidth,
        [_levelTrack.heightAnchor constraintEqualToConstant:kOSDLevelBarHeight],
        [_levelFill.leadingAnchor constraintEqualToAnchor:_levelTrack.leadingAnchor],
        [_levelFill.topAnchor constraintEqualToAnchor:_levelTrack.topAnchor],
        [_levelFill.bottomAnchor constraintEqualToAnchor:_levelTrack.bottomAnchor],
        _levelFillWidth,
    ]];

    _stack = [NSStackView stackViewWithViews:@[_symbolView, _label, _levelTrack]];
    _stack.translatesAutoresizingMaskIntoConstraints = NO;
    _stack.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    _stack.alignment = NSLayoutAttributeCenterY;
    _stack.spacing = MacLCDesign.spacingS;
    [_glass.contentView addSubview:_stack];

    [NSLayoutConstraint activateConstraints:@[
        [_glass.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [_glass.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [_glass.topAnchor constraintEqualToAnchor:self.topAnchor],
        [_glass.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        [self.heightAnchor constraintEqualToConstant:kOSDHeight],
        [_stack.leadingAnchor constraintEqualToAnchor:_glass.contentView.leadingAnchor
                                             constant:kOSDHorizontalPadding],
        [_stack.trailingAnchor constraintEqualToAnchor:_glass.contentView.trailingAnchor
                                              constant:-kOSDHorizontalPadding],
        [_stack.centerYAnchor constraintEqualToAnchor:_glass.contentView.centerYAnchor],
    ]];

    [self updateLevelColors];
}

- (void)viewDidChangeEffectiveAppearance
{
    [super viewDidChangeEffectiveAppearance];
    [self updateLevelColors];
}

- (void)updateLevelColors
{
    [self.effectiveAppearance performAsCurrentDrawingAppearance:^{
        self->_levelTrack.layer.backgroundColor = MacLCDesign.quaternaryLabel.CGColor;
        self->_levelFill.layer.backgroundColor = MacLCDesign.primaryLabel.CGColor;
    }];
}

- (void)viewWillMoveToWindow:(nullable NSWindow *)newWindow
{
    [super viewWillMoveToWindow:newWindow];
    if (newWindow == nil) {
        [_lingerTimer invalidate];
        _lingerTimer = nil;
        [_announceTimer invalidate];
        _announceTimer = nil;
    }
}

- (void)dealloc
{
    [_lingerTimer invalidate];
    [_announceTimer invalidate];
}

- (void)showMessage:(NSString *)message
         symbolName:(nullable NSString *)symbolName
              level:(CGFloat)level
{
    _label.stringValue = message;

    NSImage *symbol = symbolName
        ? [NSImage imageWithSystemSymbolName:symbolName accessibilityDescription:nil]
        : nil;
    _symbolView.image = symbol;
    _symbolView.hidden = (symbol == nil);

    const BOOL showsLevel = level >= 0.0;
    _levelTrack.hidden = !showsLevel;
    if (showsLevel) {
        const CGFloat clamped = MIN(MAX(level, 0.0), 1.0);
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
            context.duration = MacLCDesign.reducedMotion ? 0.0 : MacLCDesign.motionQuickDuration;
            context.allowsImplicitAnimation = YES;
            self->_levelFillWidth.animator.constant = kOSDLevelBarWidth * clamped;
        }];
    }

    /* VoiceOver hears the value the user settles on, not every step of a
     * held key or a scrub. */
    self.accessibilityLabel = message;
    [_announceTimer invalidate];
    __weak typeof(self) weakAnnouncer = self;
    _announceTimer = [NSTimer scheduledTimerWithTimeInterval:0.6
                                                     repeats:NO
                                                       block:^(NSTimer *timer) {
        typeof(self) strongSelf = weakAnnouncer;
        if (strongSelf == nil)
            return;
        NSAccessibilityPostNotificationWithUserInfo(NSApp.mainWindow ?: (id)strongSelf,
            NSAccessibilityAnnouncementRequestedNotification,
            @{ NSAccessibilityAnnouncementKey: strongSelf.accessibilityLabel ?: @"",
               NSAccessibilityPriorityKey: @(NSAccessibilityPriorityMedium) });
    }];

    if (!_presented) {
        _presented = YES;
        [MacLCDesign animateEntranceOfView:self];
    }

    [_lingerTimer invalidate];
    __weak typeof(self) weakSelf = self;
    _lingerTimer = [NSTimer scheduledTimerWithTimeInterval:MacLCDesign.hudLinger
                                                   repeats:NO
                                                     block:^(NSTimer * _Nonnull timer) {
        [weakSelf dismiss];
    }];
}

- (void)dismiss
{
    [_lingerTimer invalidate];
    _lingerTimer = nil;
    if (!_presented)
        return;
    _presented = NO;
    __weak typeof(self) weakSelf = self;
    [MacLCDesign animateExitOfView:self completion:^{
        typeof(self) strongSelf = weakSelf;
        if (strongSelf != nil && !strongSelf->_presented)
            strongSelf.hidden = YES;
    }];
}

@end
