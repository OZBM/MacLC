/*****************************************************************************
 * MacLCSectionHeaderView.m: title row above a shelf or a grid
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

#import "medialib/components/MacLCSectionHeaderView.h"
#import "theme/MacLCDesign.h"
#import "extensions/NSString+Helpers.h"

NSUserInterfaceItemIdentifier const MacLCSectionHeaderViewIdentifier = @"MacLCSectionHeaderViewIdentifier";

@interface MacLCSectionHeaderActionButton : NSButton

@property (nonatomic, copy, nullable) void (^actionBlock)(void);
@property (nonatomic, strong) NSTrackingArea *trackingArea;
@property (nonatomic, assign) BOOL isHovered;

@end

@implementation MacLCSectionHeaderActionButton

- (instancetype)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (self) {
        self.bordered = NO;
        self.imagePosition = NSImageRight;
        self.font = MacLCDesign.subheadline;
        self.contentTintColor = MacLCDesign.secondaryLabel;
        self.target = self;
        self.action = @selector(buttonClicked:);
        self.translatesAutoresizingMaskIntoConstraints = NO;

        NSImageSymbolConfiguration *config = [NSImageSymbolConfiguration configurationWithScale:NSImageSymbolScaleSmall];
        NSImage *chevron = [NSImage imageWithSystemSymbolName:@"chevron.forward" accessibilityDescription:nil];
        if (chevron) {
            chevron = [chevron imageWithSymbolConfiguration:config];
        }
        self.image = chevron;
    }
    return self;
}

- (void)updateTrackingAreas
{
    [super updateTrackingAreas];
    if (_trackingArea) {
        [self removeTrackingArea:_trackingArea];
    }
    _trackingArea = [[NSTrackingArea alloc] initWithRect:self.bounds
                                                 options:(NSTrackingActiveInKeyWindow |
                                                          NSTrackingMouseEnteredAndExited |
                                                          NSTrackingInVisibleRect)
                                                   owner:self
                                                userInfo:nil];
    [self addTrackingArea:_trackingArea];
}

- (void)mouseEntered:(NSEvent *)event
{
    _isHovered = YES;
    [self updateColorsAnimated:YES];
}

- (void)mouseExited:(NSEvent *)event
{
    _isHovered = NO;
    [self updateColorsAnimated:YES];
}

- (void)resetCursorRects
{
    [super resetCursorRects];
    [self addCursorRect:self.bounds cursor:[NSCursor pointingHandCursor]];
}

- (void)updateColorsAnimated:(BOOL)animated
{
    NSColor *targetColor = _isHovered ? MacLCDesign.accent : MacLCDesign.secondaryLabel;
    if (animated && !MacLCDesign.reducedMotion) {
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext * _Nonnull context) {
            context.duration = MacLCDesign.motionQuickDuration;
            self.contentTintColor = targetColor;
        }];
    } else {
        self.contentTintColor = targetColor;
    }
}

- (void)buttonClicked:(id)sender
{
    if (self.actionBlock) {
        self.actionBlock();
    }
}

@end

@interface MacLCSectionHeaderView ()

@property (nonatomic, strong) NSTextField *titleLabel;
@property (nonatomic, strong) NSTextField *subtitleLabel;
@property (nonatomic, strong) MacLCSectionHeaderActionButton *actionButton;
@property (nonatomic, strong) NSLayoutConstraint *titleCenterYConstraint;
@property (nonatomic, strong) NSLayoutConstraint *titleTopConstraint;

@end

@implementation MacLCSectionHeaderView

- (instancetype)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (self) {
        self.wantsLayer = YES;
        self.translatesAutoresizingMaskIntoConstraints = NO;

        _titleLabel = [NSTextField labelWithString:@""];
        _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _titleLabel.font = [NSFont systemFontOfSize:MacLCDesign.title2.pointSize weight:NSFontWeightBold];
        _titleLabel.textColor = MacLCDesign.primaryLabel;
        _titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        _titleLabel.accessibilityRole = NSAccessibilityHeadingRole;
        [self addSubview:_titleLabel];

        _subtitleLabel = [NSTextField labelWithString:@""];
        _subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _subtitleLabel.font = MacLCDesign.subheadline;
        _subtitleLabel.textColor = MacLCDesign.secondaryLabel;
        _subtitleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        _subtitleLabel.hidden = YES;
        [self addSubview:_subtitleLabel];

        _actionButton = [[MacLCSectionHeaderActionButton alloc] initWithFrame:NSZeroRect];
        _actionButton.hidden = YES;
        [self addSubview:_actionButton];

        _titleCenterYConstraint = [_titleLabel.centerYAnchor constraintEqualToAnchor:self.centerYAnchor];
        _titleTopConstraint = [_titleLabel.topAnchor constraintEqualToAnchor:self.topAnchor constant:6.0];

        [NSLayoutConstraint activateConstraints:@[
            [_titleLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [_titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_actionButton.leadingAnchor constant:-12.0],
            _titleCenterYConstraint,

            [_subtitleLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [_subtitleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_actionButton.leadingAnchor constant:-12.0],
            [_subtitleLabel.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor constant:2.0],

            [_actionButton.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [_actionButton.centerYAnchor constraintEqualToAnchor:_titleLabel.centerYAnchor],
        ]];
    }
    return self;
}

- (void)setTitle:(NSString *)title
{
    _title = [title copy];
    _titleLabel.stringValue = title ?: @"";
}

- (void)setSubtitle:(nullable NSString *)subtitle
{
    _subtitle = [subtitle copy];
    if (subtitle.length > 0) {
        _subtitleLabel.stringValue = subtitle;
        _subtitleLabel.hidden = NO;
        _titleCenterYConstraint.active = NO;
        _titleTopConstraint.active = YES;
    } else {
        _subtitleLabel.stringValue = @"";
        _subtitleLabel.hidden = YES;
        _titleTopConstraint.active = NO;
        _titleCenterYConstraint.active = YES;
    }
}

- (void)setActionTitle:(nullable NSString *)actionTitle
{
    _actionTitle = [actionTitle copy];
    if (actionTitle.length > 0) {
        _actionButton.title = [NSString stringWithFormat:@"%@ ", actionTitle];
        _actionButton.accessibilityLabel = actionTitle;
        _actionButton.toolTip = actionTitle;
        _actionButton.hidden = NO;
    } else {
        _actionButton.title = @"";
        _actionButton.hidden = YES;
    }
}

- (void)setAction:(nullable void (^)(void))action
{
    _action = [action copy];
    _actionButton.actionBlock = action;
}

- (void)prepareForReuse
{
    [super prepareForReuse];
    self.title = @"";
    self.subtitle = nil;
    self.actionTitle = nil;
    self.action = nil;
}

+ (CGFloat)heightWithSubtitle:(BOOL)hasSubtitle
{
    return hasSubtitle ? 58.0 : 44.0;
}

@end
