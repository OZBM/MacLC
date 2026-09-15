/*****************************************************************************
 * MacLCFormatBadgeView.m: MacLC format presentation badge view
 *****************************************************************************
 * Copyright (C) 2026 Hazen Studio
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

#import "MacLCFormatBadgeView.h"
#import "MacLCDesign.h"

@implementation MacLCFormatBadgeView

+ (instancetype)badgeWithTitle:(NSString *)title
{
    return [[self alloc] initWithTitle:title active:NO];
}

+ (instancetype)badgeWithTitle:(NSString *)title active:(BOOL)active
{
    return [[self alloc] initWithTitle:title active:active];
}

- (instancetype)initWithTitle:(NSString *)title active:(BOOL)active
{
    self = [super initWithFrame:NSZeroRect];
    if (self) {
        _title = [title copy];
        _active = active;
        [self commonInit];
    }
    return self;
}

- (instancetype)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (self) {
        _title = @"";
        _active = NO;
        [self commonInit];
    }
    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];
    if (self) {
        _title = @"";
        _active = NO;
        [self commonInit];
    }
    return self;
}

- (void)commonInit
{
    self.translatesAutoresizingMaskIntoConstraints = NO;
    [self setContentHuggingPriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
    [self setContentHuggingPriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationVertical];
    [self setContentCompressionResistancePriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
    [self setContentCompressionResistancePriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationVertical];

    self.accessibilityLabel = _title;
}

- (void)setTitle:(NSString *)title
{
    if (![_title isEqualToString:title]) {
        _title = [title copy];
        self.accessibilityLabel = _title;
        [self invalidateIntrinsicContentSize];
        [self setNeedsDisplay:YES];
    }
}

- (void)setActive:(BOOL)active
{
    if (_active != active) {
        _active = active;
        [self setNeedsDisplay:YES];
    }
}

- (void)viewDidChangeEffectiveAppearance
{
    [super viewDidChangeEffectiveAppearance];
    [self setNeedsDisplay:YES];
}

- (NSSize)intrinsicContentSize
{
    if (self.title.length == 0) {
        return NSZeroSize;
    }

    NSString * const displayText = [self.title uppercaseStringWithLocale:[NSLocale currentLocale]];
    NSColor * const textColor = self.isActive ? MacLCDesign.primaryLabel : MacLCDesign.secondaryLabel;
    NSDictionary * const attrs = [MacLCDesign badgeTextAttributesWithColor:textColor];
    const NSSize textSize = [displayText sizeWithAttributes:attrs];

    // Padding: 4 pt horizontal on each side, 2 pt vertical on each side (DESIGN_SPEC §4: 4×2)
    const CGFloat width = ceil(textSize.width) + 8.0;
    const CGFloat height = ceil(textSize.height) + 4.0;
    return NSMakeSize(width, height);
}

- (void)drawRect:(NSRect)dirtyRect
{
    [super drawRect:dirtyRect];

    const NSRect bounds = self.bounds;
    if (NSIsEmptyRect(bounds)) {
        return;
    }

    const CGFloat radius = 4.0;

    if (self.isActive) {
        NSBezierPath * const fillPath = [NSBezierPath bezierPathWithRoundedRect:bounds xRadius:radius yRadius:radius];
        NSColor * const fillColor = [MacLCDesign.primaryLabel colorWithAlphaComponent:0.14];
        [fillColor setFill];
        [fillPath fill];
    } else {
        const NSRect strokeRect = NSInsetRect(bounds, 0.5, 0.5);
        NSBezierPath * const strokePath = [NSBezierPath bezierPathWithRoundedRect:strokeRect xRadius:radius yRadius:radius];
        strokePath.lineWidth = 1.0;
        [MacLCDesign.secondaryLabel setStroke];
        [strokePath stroke];
    }

    if (self.title.length > 0) {
        NSString * const displayText = [self.title uppercaseStringWithLocale:[NSLocale currentLocale]];
        NSColor * const textColor = self.isActive ? MacLCDesign.primaryLabel : MacLCDesign.secondaryLabel;
        NSDictionary * const attrs = [MacLCDesign badgeTextAttributesWithColor:textColor];
        const NSSize textSize = [displayText sizeWithAttributes:attrs];

        const NSRect textRect = NSMakeRect(
            floor((bounds.size.width - textSize.width) / 2.0),
            floor((bounds.size.height - textSize.height) / 2.0),
            ceil(textSize.width),
            ceil(textSize.height)
        );

        [displayText drawInRect:textRect withAttributes:attrs];
    }
}

#pragma mark - Accessibility

- (BOOL)isAccessibilityElement
{
    return YES;
}

- (NSAccessibilityRole)accessibilityRole
{
    return NSAccessibilityStaticTextRole;
}

- (nullable NSString *)accessibilityLabel
{
    return self.title;
}

- (nullable NSString *)accessibilityValue
{
    return self.isActive ? @"Active" : nil;
}

@end
