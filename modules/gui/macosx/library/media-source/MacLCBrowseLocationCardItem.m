/*****************************************************************************
 * MacLCBrowseLocationCardItem.m: Location card item for Browse home
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

#import "MacLCBrowseLocationCardItem.h"

#import "theme/MacLCDesign.h"

NSString * const MacLCBrowseLocationCardItemIdentifier = @"MacLCBrowseLocationCardItemIdentifier";

/* Card padding (14) + icon badge (36) + gap (12) + trailing padding (12). */
static const CGFloat MacLCBrowseCardTextInset = 14. + 36. + 12. + 12.;

/* Height a wrapping label needs at a width, at most maxLines lines, measured
 * with a copy of its own cell so insets and leading match what it draws. */
static CGFloat MacLCBrowseCardLabelHeight(NSTextField *label, CGFloat width, NSInteger maxLines)
{
    NSTextFieldCell * const probe = [label.cell copy];
    NSMutableString * const sample = [NSMutableString stringWithString:@"X"];
    for (NSInteger line = 1; line < maxLines; line++) {
        [sample appendString:@"\nX"];
    }
    probe.stringValue = sample;
    const CGFloat maxHeight = ceil([probe cellSizeForBounds:NSMakeRect(0, 0, 10000., 10000.)].height);
    if (width <= 0.) {
        return maxHeight;
    }
    /* The cell draws its text slightly inset from its bounds: measure a
     * little narrower so a title that barely fits wraps instead of being cut. */
    const CGFloat needed = ceil([label.cell cellSizeForBounds:NSMakeRect(0, 0, MAX(width - 6., 1.), 10000.)].height);
    return MIN(needed, maxHeight);
}

@interface MacLCBrowseLocationCardView ()
{
    NSView *_iconBadgeView;
    NSImageView *_iconImageView;
    NSTextField *_titleLabel;
    NSTextField *_subtitleLabel;
    NSLayoutConstraint *_titleHeightConstraint;
    NSTrackingArea *_trackingArea;
    BOOL _isHovered;
}

@property (nonatomic, readonly) BOOL isHovered;

@end

@implementation MacLCBrowseLocationCardView

- (instancetype)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (self) {
        self.wantsLayer = YES;
        self.layerContentsRedrawPolicy = NSViewLayerContentsRedrawOnSetNeedsDisplay;

        _iconBadgeView = [[NSView alloc] initWithFrame:NSZeroRect];
        _iconBadgeView.translatesAutoresizingMaskIntoConstraints = NO;
        _iconBadgeView.wantsLayer = YES;
        _iconBadgeView.layer.cornerRadius = 8.0;
        _iconBadgeView.layer.masksToBounds = YES;
        [self addSubview:_iconBadgeView];

        _iconImageView = [[NSImageView alloc] initWithFrame:NSZeroRect];
        _iconImageView.translatesAutoresizingMaskIntoConstraints = NO;
        _iconImageView.imageScaling = NSImageScaleProportionallyUpOrDown;
        _iconImageView.contentTintColor = MacLCDesign.accent;
        [_iconBadgeView addSubview:_iconImageView];

        /* Long names ("Bonjour Network Discovery") get a second line before
         * they are truncated. */
        _titleLabel = [NSTextField wrappingLabelWithString:@""];
        _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _titleLabel.font = MacLCDesign.headline;
        _titleLabel.textColor = MacLCDesign.primaryLabel;
        _titleLabel.lineBreakMode = NSLineBreakByWordWrapping;
        _titleLabel.maximumNumberOfLines = 2;
        _titleLabel.cell.truncatesLastVisibleLine = YES;
        _titleLabel.drawsBackground = NO;
        _titleLabel.selectable = NO;
        [_titleLabel setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
                                              forOrientation:NSLayoutConstraintOrientationHorizontal];

        _subtitleLabel = [NSTextField labelWithString:@""];
        _subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _subtitleLabel.font = MacLCDesign.footnote;
        _subtitleLabel.textColor = MacLCDesign.secondaryLabel;
        _subtitleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        _subtitleLabel.maximumNumberOfLines = 1;
        _subtitleLabel.drawsBackground = NO;
        [_subtitleLabel setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
                                                 forOrientation:NSLayoutConstraintOrientationHorizontal];

        NSStackView * const textStack = [NSStackView stackViewWithViews:@[_titleLabel, _subtitleLabel]];
        textStack.translatesAutoresizingMaskIntoConstraints = NO;
        textStack.orientation = NSUserInterfaceLayoutOrientationVertical;
        textStack.alignment = NSLayoutAttributeLeading;
        textStack.spacing = 1.0;
        [self addSubview:textStack];

        [NSLayoutConstraint activateConstraints:@[
            [_iconBadgeView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:14.0],
            [_iconBadgeView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_iconBadgeView.widthAnchor constraintEqualToConstant:36.0],
            [_iconBadgeView.heightAnchor constraintEqualToConstant:36.0],

            [_iconImageView.centerXAnchor constraintEqualToAnchor:_iconBadgeView.centerXAnchor],
            [_iconImageView.centerYAnchor constraintEqualToAnchor:_iconBadgeView.centerYAnchor],
            [_iconImageView.widthAnchor constraintEqualToConstant:20.0],
            [_iconImageView.heightAnchor constraintEqualToConstant:20.0],

            [textStack.leadingAnchor constraintEqualToAnchor:_iconBadgeView.trailingAnchor constant:12.0],
            [textStack.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-12.0],
            [textStack.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [textStack.topAnchor constraintGreaterThanOrEqualToAnchor:self.topAnchor constant:6.0],
            [textStack.bottomAnchor constraintLessThanOrEqualToAnchor:self.bottomAnchor constant:-6.0],
            [_titleLabel.widthAnchor constraintEqualToAnchor:textStack.widthAnchor],
            [_subtitleLabel.widthAnchor constraintEqualToAnchor:textStack.widthAnchor],
        ]];

        _titleHeightConstraint = [_titleLabel.heightAnchor constraintEqualToConstant:
                                  MacLCBrowseCardLabelHeight(_titleLabel, 0., 1)];
        _titleHeightConstraint.active = YES;

        [self setAccessibilityElement:YES];
        [self setAccessibilityRole:NSAccessibilityButtonRole];
    }
    return self;
}

- (void)layout
{
    [super layout];

    /* One or two lines, depending on the title and the card width. The label
     * sits in a stack view that is laid out after this view, so its own frame
     * is not current yet: derive the text width from the card's layout. */
    const CGFloat textWidth = MAX(NSWidth(self.bounds) - MacLCBrowseCardTextInset, 1.);
    _titleLabel.preferredMaxLayoutWidth = textWidth;
    const CGFloat titleHeight = MacLCBrowseCardLabelHeight(_titleLabel, textWidth, 2);
    if (fabs(_titleHeightConstraint.constant - titleHeight) > 0.5) {
        _titleHeightConstraint.constant = titleHeight;
        [super layout];
    }
}

- (BOOL)wantsUpdateLayer
{
    return YES;
}

- (void)updateLayer
{
    [super updateLayer];

    self.layer.cornerRadius = MacLCDesign.cornerRadiusMedium;
    self.layer.masksToBounds = YES;

    if (self.isSelected) {
        self.layer.borderWidth = 2.0;
        self.layer.borderColor = MacLCDesign.accent.CGColor;
    } else {
        self.layer.borderWidth = 1.0;
        self.layer.borderColor = MacLCDesign.separator.CGColor;
    }

    NSColor *baseColor = MacLCDesign.cardBackground;
    if (_isHovered) {
        baseColor = [baseColor blendedColorWithFraction:0.14 ofColor:NSColor.labelColor] ?: baseColor;
    }
    self.layer.backgroundColor = baseColor.CGColor;

    _iconBadgeView.layer.backgroundColor = [MacLCDesign.accent colorWithAlphaComponent:0.12].CGColor;
}

- (void)updateTrackingAreas
{
    [super updateTrackingAreas];
    if (_trackingArea != nil) {
        [self removeTrackingArea:_trackingArea];
    }
    _trackingArea = [[NSTrackingArea alloc] initWithRect:self.bounds
                                                 options:NSTrackingMouseEnteredAndExited |
                                                         NSTrackingActiveInActiveApp |
                                                         NSTrackingInVisibleRect
                                                   owner:self
                                                userInfo:nil];
    [self addTrackingArea:_trackingArea];
}

- (void)mouseEntered:(NSEvent *)event
{
    _isHovered = YES;
    CGColorRef const fromColor = self.layer.backgroundColor;
    NSColor * const toNSColor = [MacLCDesign.cardBackground blendedColorWithFraction:0.14 ofColor:NSColor.labelColor] ?: MacLCDesign.cardBackground;
    CGColorRef const toColor = toNSColor.CGColor;
    if (!MacLCDesign.reducedMotion && fromColor != NULL && toColor != NULL) {
        CABasicAnimation * const animation = [CABasicAnimation animationWithKeyPath:@"backgroundColor"];
        animation.fromValue = (__bridge id)fromColor;
        animation.toValue = (__bridge id)toColor;
        animation.duration = MacLCDesign.motionQuickDuration;
        animation.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
        [self.layer addAnimation:animation forKey:@"hoverBackground"];
    }
    self.layer.backgroundColor = toColor;
    [self setNeedsDisplay:YES];
}

- (void)mouseExited:(NSEvent *)event
{
    _isHovered = NO;
    CGColorRef const fromColor = self.layer.backgroundColor;
    CGColorRef const toColor = MacLCDesign.cardBackground.CGColor;
    if (!MacLCDesign.reducedMotion && fromColor != NULL && toColor != NULL) {
        CABasicAnimation * const animation = [CABasicAnimation animationWithKeyPath:@"backgroundColor"];
        animation.fromValue = (__bridge id)fromColor;
        animation.toValue = (__bridge id)toColor;
        animation.duration = MacLCDesign.motionQuickDuration;
        animation.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
        [self.layer addAnimation:animation forKey:@"hoverBackground"];
    }
    self.layer.backgroundColor = toColor;
    [self setNeedsDisplay:YES];
}

- (void)setTitle:(NSString *)title
{
    _title = [title copy];
    _titleLabel.stringValue = title ?: @"";
    self.needsLayout = YES;
    [self updateAccessibilityLabel];
}

- (void)setSubtitle:(NSString *)subtitle
{
    _subtitle = [subtitle copy];
    _subtitleLabel.stringValue = subtitle ?: @"";
    [self updateAccessibilityLabel];
}

- (void)setSymbolName:(NSString *)symbolName
{
    _symbolName = [symbolName copy];
    NSImage * const symbolImage = [MacLCDesign symbolNamed:symbolName
                                                 pointSize:20.0
                                                    weight:NSFontWeightSemibold
                                        accessibilityLabel:self.title];
    _iconImageView.image = symbolImage;
    _iconImageView.contentTintColor = MacLCDesign.accent;
}

- (void)setSelected:(BOOL)selected
{
    if (_selected != selected) {
        _selected = selected;
        [self setNeedsDisplay:YES];
    }
}

- (void)updateAccessibilityLabel
{
    NSString * const combined = [NSString stringWithFormat:@"%@, %@",
                                 self.title ?: @"",
                                 self.subtitle ?: @""];
    [self setAccessibilityLabel:combined];
}

@end


@implementation MacLCBrowseLocationCardItem

- (void)loadView
{
    self.view = [[MacLCBrowseLocationCardView alloc] initWithFrame:NSMakeRect(0, 0, 220, 64)];
}

- (MacLCBrowseLocationCardView *)cardView
{
    return (MacLCBrowseLocationCardView *)self.view;
}

- (void)setTitle:(nullable NSString *)title
{
    [super setTitle:title];
    self.cardView.title = title;
}

- (void)setSubtitle:(NSString *)subtitle
{
    _subtitle = [subtitle copy];
    self.cardView.subtitle = subtitle;
}

- (void)setSymbolName:(NSString *)symbolName
{
    _symbolName = [symbolName copy];
    self.cardView.symbolName = symbolName;
}

- (void)setSelected:(BOOL)selected
{
    [super setSelected:selected];
    self.cardView.selected = selected;
}

- (void)prepareForReuse
{
    [super prepareForReuse];
    self.title = @"";
    self.subtitle = @"";
    self.symbolName = @"folder.fill";
    self.selected = NO;
}

@end
