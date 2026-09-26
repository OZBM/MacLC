/*****************************************************************************
 * MacLCMediaCardItem.h: artwork card of every library grid and shelf
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

@protocol VLCMediaLibraryItemProtocol;
@class MacLCArtworkView;

NS_ASSUME_NONNULL_BEGIN

extern NSUserInterfaceItemIdentifier const MacLCMediaCardItemIdentifier;

/// Which secondary line a card shows under its title.
typedef NS_ENUM(NSInteger, MacLCCardSubtitleStyle) {
    /// The type's default (see MacLCMediaCardItem.m): video "1 h 42 min · 2021",
    /// show "2 seasons · 4 episodes", album its artist, artist "3 albums",
    /// playlist "12 items · 48 min", genre "5 albums".
    MacLCCardSubtitleStyleDefault = 0,
    /// Time left for a started video: "23 min left".
    MacLCCardSubtitleStyleTimeLeft,
    /// No second line.
    MacLCCardSubtitleStyleNone,
};

/// Built in code (no XIB). Layout, top to bottom: artwork (full width, shape
/// aspect), 8 pt, title (MacLCDesign.body, medium weight, 1 line, tail
/// truncation), 2 pt, subtitle (MacLCDesign.subheadline, secondaryLabel,
/// 1 line). Text is leading-aligned, centred for the circle shape.
/// Double-click or Return plays (MacLCLibraryActions); the play affordance
/// on hover plays too; right-click shows MacLCLibraryActions' context menu
/// for the collection view's selection (or this item when not selected).
@interface MacLCMediaCardItem : NSCollectionViewItem

@property (readonly) MacLCArtworkView *artworkView;
@property (readonly, nullable) id<VLCMediaLibraryItemProtocol> libraryItem;

- (void)configureWithItem:(id<VLCMediaLibraryItemProtocol>)item
                    shape:(MacLCArtworkShape)shape
            subtitleStyle:(MacLCCardSubtitleStyle)subtitleStyle;

/// Height of the text block under the artwork (title + subtitle), so layouts
/// can size items: artwork height + 8 + this.
+ (CGFloat)textBlockHeightWithSubtitle:(BOOL)hasSubtitle;

@end

NS_ASSUME_NONNULL_END
