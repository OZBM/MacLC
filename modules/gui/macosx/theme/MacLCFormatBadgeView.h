/*****************************************************************************
 * MacLCFormatBadgeView.h: MacLC format presentation badge view
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

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * MacLCFormatBadgeView is a compact pill badge used to indicate media stream formats
 * (such as DOLBY VISION, HDR10+, HDR10, HLG, SDR) across transport controls and HDR cards.
 *
 * Visual specification (DESIGN_SPEC §4-§5):
 * - Typography: 10 pt semibold with +0.6 pt tracking (uppercase display).
 * - Geometry: 4 pt corner radius, 4 pt horizontal and 2 pt vertical padding.
 * - Inactive state: 1 pt stroke in `MacLCDesign.secondaryLabel`, text in `MacLCDesign.secondaryLabel`.
 * - Active state: 14% fill in `MacLCDesign.primaryLabel`, text in `MacLCDesign.primaryLabel`.
 * - Accessibility: VoiceOver label retains natural case (e.g. "Dolby Vision").
 */
@interface MacLCFormatBadgeView : NSView

/**
 * Convenience factory method returning a badge configured with a title and inactive state.
 *
 * @param title The natural-case format title (e.g. @"Dolby Vision", @"HDR10+").
 * @return An initialized MacLCFormatBadgeView instance.
 */
+ (instancetype)badgeWithTitle:(NSString *)title;

/**
 * Convenience factory method returning a badge configured with a title and active state.
 *
 * @param title The natural-case format title.
 * @param active Whether the badge represents the currently active presentation.
 * @return An initialized MacLCFormatBadgeView instance.
 */
+ (instancetype)badgeWithTitle:(NSString *)title active:(BOOL)active;

/**
 * Designated initializer creating a badge view with a title and active state.
 */
- (instancetype)initWithTitle:(NSString *)title active:(BOOL)active NS_DESIGNATED_INITIALIZER;

- (instancetype)initWithFrame:(NSRect)frameRect NS_DESIGNATED_INITIALIZER;
- (nullable instancetype)initWithCoder:(NSCoder *)coder NS_DESIGNATED_INITIALIZER;

/**
 * The natural-case format title (e.g. @"Dolby Vision", @"HDR10+").
 * Displayed uppercase; accessibilityLabel uses natural case.
 */
@property (nonatomic, copy) NSString *title;

/**
 * Indicates whether this format presentation is currently active.
 * Setting this updates styling between neutral outlined and filled accent.
 */
@property (nonatomic, getter=isActive) BOOL active;

@end

NS_ASSUME_NONNULL_END
