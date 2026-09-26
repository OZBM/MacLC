/*****************************************************************************
 * MacLCSectionHeaderView.h: title row above a shelf or a grid
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

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

extern NSUserInterfaceItemIdentifier const MacLCSectionHeaderViewIdentifier;

/// A collection view supplementary view: title (MacLCDesign.title2, bold,
/// labelColor, title case: "Continue Watching") on the leading edge, an
/// optional subtitle under it (subheadline, secondaryLabel), and an optional
/// trailing borderless button ("See All" + chevron.forward, secondaryLabel,
/// accent on hover). Height 44 (58 with subtitle). Accessibility: the title
/// is a heading (NSAccessibilityHeadingRole trait via accessibilityRole).
@interface MacLCSectionHeaderView : NSView <NSCollectionViewElement>

@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy, nullable) NSString *subtitle;
@property (nonatomic, copy, nullable) NSString *actionTitle;
@property (nonatomic, copy, nullable) void (^action)(void);

+ (CGFloat)heightWithSubtitle:(BOOL)hasSubtitle;

@end

NS_ASSUME_NONNULL_END
