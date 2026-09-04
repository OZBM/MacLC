/*****************************************************************************
 * MacLCCardView.h: MacLC macOS design token layer - Card container view
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

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * MacLCCardView is a titled container view designed for group layouts (such as
 * settings panes in the macOS System Settings style).
 *
 * Visual specification:
 * - A rounded card surface styled with `MacLCDesign.cardBackground`,
 *   `MacLCDesign.cornerRadiusMedium` (8 pt), and a subtle border using `MacLCDesign.separator`.
 * - An optional section title label positioned above the card container in `MacLCDesign.headline`
 *   and `MacLCDesign.primaryLabel`.
 * - A vertical `contentStackView` with standard internal padding that consumers populate
 *   with settings rows, controls, or custom content views.
 *
 * Usage example:
 * @code
 * MacLCCardView *card = [MacLCCardView cardViewWithTitle:@"Playback"];
 * [card.contentStackView addArrangedSubview:mySettingsRowView];
 * [parentView addSubview:card];
 * @endcode
 */
@interface MacLCCardView : NSView

/**
 * Convenience factory method returning a card view configured with an optional title.
 *
 * @param title The title string displayed above the card container.
 *              Pass nil or empty string for an untitled card.
 * @return A configured MacLCCardView instance ready for subviews to be added to `contentStackView`.
 */
+ (instancetype)cardViewWithTitle:(nullable NSString *)title;

/**
 * Designated initializer creating a card view configured with an optional title.
 *
 * @param title The title string displayed above the card container.
 *              Pass nil or empty string for an untitled card.
 */
- (instancetype)initWithTitle:(nullable NSString *)title NS_DESIGNATED_INITIALIZER;

- (instancetype)initWithFrame:(NSRect)frameRect NS_DESIGNATED_INITIALIZER;
- (nullable instancetype)initWithCoder:(NSCoder *)coder NS_DESIGNATED_INITIALIZER;

/**
 * The title text displayed above the card container.
 * Setting this updates the title label text and dynamically adjusts layout visibility.
 * When nil or empty, the title label is hidden and card top margins collapse cleanly.
 */
@property (nonatomic, copy, nullable) NSString *title;

/**
 * The read-only label displaying the card title. Styled with `MacLCDesign.headline`
 * and `MacLCDesign.primaryLabel`. Hidden when `title` is nil or empty.
 */
@property (nonatomic, readonly) NSTextField *titleLabel;

/**
 * The inner container view representing the rounded card surface.
 * Layer-backed, styled with `MacLCDesign.cornerRadiusMedium` (8 pt), `MacLCDesign.cardBackground`,
 * and a 1-pt border using `MacLCDesign.separator`.
 */
@property (nonatomic, readonly) NSView *cardContainerView;

/**
 * The vertical stack view hosted inside the card container.
 * Consumers add arranged subviews (such as settings rows or form controls) to this stack.
 * Default insets: 16 pt (`MacLCDesign.spacingL`) on all sides; inter-item spacing: 12 pt (`MacLCDesign.spacingM`).
 */
@property (nonatomic, readonly) NSStackView *contentStackView;

@end

NS_ASSUME_NONNULL_END
