/*****************************************************************************
 * MacLCCardView.m: MacLC macOS design token layer - Card container view
 *****************************************************************************
 * Copyright (C) 2026 VLC authors and VideoLAN
 *
 * Authors: MacLC Design System Team
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

#import "MacLCCardView.h"
#import "MacLCDesign.h"

@interface MacLCCardView ()

@property (nonatomic, strong) NSLayoutConstraint *cardWithTitleTopConstraint;
@property (nonatomic, strong) NSLayoutConstraint *cardNoTitleTopConstraint;

@end

/**
 * A vertical stack that makes every row it is given as wide as the card.
 *
 * NSStackView's leading alignment leaves each arranged view at its fitting
 * width, which left a settings row only as wide as its own longest line - so
 * its control sat immediately after a short explanation and far to the right
 * after a long one. Setting the stack's alignment to NSLayoutAttributeWidth
 * instead makes the rows trail-align at unequal widths, which is no better.
 * Constraining each row explicitly is the one arrangement that does what a
 * card wants.
 */
@interface MacLCCardContentStackView : NSStackView
@end

@implementation MacLCCardContentStackView

- (void)addArrangedSubview:(NSView *)view
{
    [super addArrangedSubview:view];
    const CGFloat horizontalInsets = self.edgeInsets.left + self.edgeInsets.right;
    [view.widthAnchor constraintEqualToAnchor:self.widthAnchor
                                     constant:-horizontalInsets].active = YES;
}

@end

@implementation MacLCCardView

+ (instancetype)cardViewWithTitle:(nullable NSString *)title
{
    return [[self alloc] initWithTitle:title];
}

- (instancetype)initWithTitle:(nullable NSString *)title
{
    self = [super initWithFrame:NSZeroRect];
    if (self) {
        [self commonInitWithTitle:title];
    }
    return self;
}

- (instancetype)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (self) {
        [self commonInitWithTitle:nil];
    }
    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];
    if (self) {
        [self commonInitWithTitle:nil];
    }
    return self;
}

- (void)commonInitWithTitle:(nullable NSString *)title
{
    self.translatesAutoresizingMaskIntoConstraints = NO;

    _title = [title copy];

    _titleLabel = [NSTextField labelWithString:(_title ?: @"")];
    _titleLabel.font = MacLCDesign.headline;
    _titleLabel.textColor = MacLCDesign.primaryLabel;
    _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [_titleLabel setContentHuggingPriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationVertical];
    _titleLabel.hidden = (_title.length == 0);

    _cardContainerView = [[NSView alloc] initWithFrame:NSZeroRect];
    _cardContainerView.wantsLayer = YES;
    _cardContainerView.layer.cornerRadius = MacLCDesign.cornerRadiusMedium;
    _cardContainerView.layer.masksToBounds = YES;
    _cardContainerView.layer.borderWidth = 1.0;
    _cardContainerView.translatesAutoresizingMaskIntoConstraints = NO;

    _contentStackView = [[MacLCCardContentStackView alloc] initWithFrame:NSZeroRect];
    _contentStackView.orientation = NSUserInterfaceLayoutOrientationVertical;
    _contentStackView.alignment = NSLayoutAttributeLeading;
    _contentStackView.spacing = MacLCDesign.spacingM;
    _contentStackView.edgeInsets = NSEdgeInsetsMake(MacLCDesign.spacingL,
                                                    MacLCDesign.spacingL,
                                                    MacLCDesign.spacingL,
                                                    MacLCDesign.spacingL);
    _contentStackView.translatesAutoresizingMaskIntoConstraints = NO;
    [_contentStackView setHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];

    [self addSubview:_titleLabel];
    [self addSubview:_cardContainerView];
    [_cardContainerView addSubview:_contentStackView];

    [NSLayoutConstraint activateConstraints:@[
        [_contentStackView.topAnchor constraintEqualToAnchor:_cardContainerView.topAnchor],
        [_contentStackView.leadingAnchor constraintEqualToAnchor:_cardContainerView.leadingAnchor],
        [_contentStackView.trailingAnchor constraintEqualToAnchor:_cardContainerView.trailingAnchor],
        [_contentStackView.bottomAnchor constraintEqualToAnchor:_cardContainerView.bottomAnchor]
    ]];

    _cardWithTitleTopConstraint = [_cardContainerView.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor
                                                                               constant:MacLCDesign.spacingS];
    _cardNoTitleTopConstraint = [_cardContainerView.topAnchor constraintEqualToAnchor:self.topAnchor];

    [NSLayoutConstraint activateConstraints:@[
        [_titleLabel.topAnchor constraintEqualToAnchor:self.topAnchor],
        [_titleLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:MacLCDesign.spacingXS],
        [_titleLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [_cardContainerView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [_cardContainerView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [_cardContainerView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor]
    ]];

    const BOOL hasTitle = (_title.length > 0);
    _cardWithTitleTopConstraint.active = hasTitle;
    _cardNoTitleTopConstraint.active = !hasTitle;

    [self updateCardColors];
}

- (void)setTitle:(nullable NSString *)title
{
    _title = [title copy];
    const BOOL hasTitle = (_title.length > 0);
    self.titleLabel.stringValue = _title ?: @"";
    self.titleLabel.hidden = !hasTitle;
    self.cardWithTitleTopConstraint.active = hasTitle;
    self.cardNoTitleTopConstraint.active = !hasTitle;
    [self invalidateIntrinsicContentSize];
}

- (void)viewDidChangeEffectiveAppearance
{
    [super viewDidChangeEffectiveAppearance];
    [self updateCardColors];
}

- (void)updateCardColors
{
    self.cardContainerView.layer.backgroundColor = MacLCDesign.cardBackground.CGColor;
    self.cardContainerView.layer.borderColor = MacLCDesign.separator.CGColor;
}

@end
