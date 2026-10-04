/*****************************************************************************
 * MacLCCastStatusView.m: Casting video surface status view
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

#import "MacLCCastStatusView.h"

#import "cast/MacLCCastController.h"
#import "extensions/NSString+Helpers.h"
#import "theme/MacLCDesign.h"

@interface MacLCCastStatusView ()
{
    NSImageView *_iconImageView;
    NSTextField *_titleLabel;
    NSTextField *_subtitleLabel;
    NSButton *_playOnMacButton;
    NSStackView *_stackView;
}

- (void)setupUI;
- (void)updateStatus;
- (void)playOnThisMacClicked:(id)sender;

@end

@implementation MacLCCastStatusView

- (instancetype)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (self) {
        [self setupUI];
        [self updateStatus];

        [NSNotificationCenter.defaultCenter addObserver:self
                                               selector:@selector(castStateDidChange:)
                                                   name:MacLCCastStateDidChangeNotification
                                                 object:nil];
    }
    return self;
}

- (void)dealloc
{
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)setupUI
{
    self.translatesAutoresizingMaskIntoConstraints = NO;

    _iconImageView = [[NSImageView alloc] initWithFrame:NSZeroRect];
    _iconImageView.translatesAutoresizingMaskIntoConstraints = NO;
    _iconImageView.imageScaling = NSImageScaleProportionallyUpOrDown;
    _iconImageView.contentTintColor = [NSColor colorWithWhite:1.0 alpha:0.7];

    _titleLabel = [NSTextField labelWithString:@""];
    _titleLabel.font = MacLCDesign.title2;
    _titleLabel.textColor = NSColor.whiteColor;
    _titleLabel.alignment = NSTextAlignmentCenter;
    _titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;

    _subtitleLabel = [NSTextField labelWithString:_NS("Use the controls here or your TV's remote.")];
    _subtitleLabel.font = MacLCDesign.body;
    _subtitleLabel.textColor = [NSColor colorWithWhite:1.0 alpha:0.7];
    _subtitleLabel.alignment = NSTextAlignmentCenter;
    _subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;

    _playOnMacButton = [NSButton buttonWithTitle:_NS("Play on This Mac")
                                          target:self
                                          action:@selector(playOnThisMacClicked:)];
    _playOnMacButton.bezelStyle = NSBezelStyleRounded;
    _playOnMacButton.translatesAutoresizingMaskIntoConstraints = NO;

    _stackView = [NSStackView stackViewWithViews:@[_iconImageView, _titleLabel, _subtitleLabel, _playOnMacButton]];
    _stackView.orientation = NSUserInterfaceLayoutOrientationVertical;
    _stackView.alignment = NSLayoutAttributeCenterX;
    _stackView.translatesAutoresizingMaskIntoConstraints = NO;

    [_stackView setCustomSpacing:12.0 afterView:_iconImageView];
    [_stackView setCustomSpacing:6.0 afterView:_titleLabel];
    [_stackView setCustomSpacing:20.0 afterView:_subtitleLabel];

    [self addSubview:_stackView];

    [NSLayoutConstraint activateConstraints:@[
        [_iconImageView.widthAnchor constraintEqualToConstant:56.0],
        [_iconImageView.heightAnchor constraintEqualToConstant:56.0],
        [_stackView.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        [_stackView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [_stackView.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.leadingAnchor constant:24.0],
        [_stackView.trailingAnchor constraintLessThanOrEqualToAnchor:self.trailingAnchor constant:-24.0]
    ]];
}

- (void)viewDidMoveToWindow
{
    [super viewDidMoveToWindow];
    if (self.window != nil) {
        [self updateStatus];
    }
}

- (void)castStateDidChange:(NSNotification *)notification
{
    [self updateStatus];
}

- (void)updateStatus
{
    MacLCCastController * const controller = MacLCCastController.sharedController;
    const BOOL isCasting = controller.isCasting;

    self.hidden = !isCasting;
    if (!isCasting) {
        return;
    }

    NSString * const destination = controller.destinationName;
    NSString *titleText = nil;

    if (controller.destinationIsAirPlay) {
        titleText = _NS("Playing on AirPlay");
    } else if (destination.length > 0) {
        titleText = [NSString stringWithFormat:_NS("Playing on %@"), destination];
    } else {
        titleText = _NS("Playing on TV");
    }

    _titleLabel.stringValue = titleText;

    NSString * const symbolName = controller.destinationIsAirPlay ? @"airplay.video" : @"tv";
    NSImage *symbol = [MacLCDesign symbolNamed:symbolName pointSize:56 weight:NSFontWeightRegular accessibilityLabel:nil];
    if (!symbol) {
        symbol = [NSImage imageWithSystemSymbolName:symbolName accessibilityDescription:nil];
    }
    _iconImageView.image = symbol;

    // VoiceOver: the whole view is a group labelled "Playing on <name>".
    self.accessibilityElement = YES;
    self.accessibilityRole = NSAccessibilityGroupRole;
    self.accessibilityLabel = titleText;
}

- (void)playOnThisMacClicked:(id)sender
{
    [MacLCCastController.sharedController playOnRendererItem:nil];
}

@end
