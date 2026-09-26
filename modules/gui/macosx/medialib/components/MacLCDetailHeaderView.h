/*****************************************************************************
 * MacLCDetailHeaderView.h: header of album, artist, show, genre and playlist
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

#import "medialib/MacLCLibraryTypes.h"

@class MacLCArtworkView;

NS_ASSUME_NONNULL_BEGIN

/// Layout (content layer, no glass), 24 pt insets:
///   [artwork]  title                      (MacLCDesign.title1, bold, 2 lines max)
///              subtitle                   (title3, accent-free link style when
///                                          subtitleAction is set: labelColor,
///                                          underline on hover, pointing hand)
///              detail                     (subheadline, secondaryLabel)
///              [▶ Play] [⤮ Shuffle] [···] (buttons row, 16 pt above bottom)
/// Artwork: 200 pt square/circle, or 320 × 180 for the video shape; artwork
/// and text column are vertically centred. The Play button is the one
/// prominent control of the screen (NSBezelStyleGlass, tintProminence
/// Primary, accent bezelColor on macOS 26); Shuffle is a standard glass
/// button; "···" is an NSPopUpButton pull-down with ellipsis.circle, shown
/// only when moreMenu is set. Below 640 pt of width the artwork shrinks to
/// 140 pt (square) / 224 × 126 (video).
@interface MacLCDetailHeaderView : NSView

- (instancetype)initWithArtworkShape:(MacLCArtworkShape)shape NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithFrame:(NSRect)frameRect NS_UNAVAILABLE;
- (nullable instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;

@property (readonly) MacLCArtworkView *artworkView;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy, nullable) NSString *subtitle;
@property (nonatomic, copy, nullable) void (^subtitleAction)(void);
@property (nonatomic, copy, nullable) NSString *detail;

/// "Play" / "Resume" (play.fill) and "Shuffle" (shuffle). A nil title hides
/// the button.
- (void)setPrimaryActionTitle:(nullable NSString *)title
                   symbolName:(nullable NSString *)symbolName
                       action:(nullable void (^)(void))action;
- (void)setSecondaryActionTitle:(nullable NSString *)title
                     symbolName:(nullable NSString *)symbolName
                         action:(nullable void (^)(void))action;
@property (nonatomic, nullable) NSMenu *moreMenu;

@end

NS_ASSUME_NONNULL_END
