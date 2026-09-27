/*****************************************************************************
 * MacLCLibraryGridViewController.h: the artwork grid shared by the sections
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
#import "medialib/components/MacLCMediaCardItem.h"

@protocol VLCMediaLibraryItemProtocol;

NS_ASSUME_NONNULL_BEGIN

/// One scrolling grid of MacLCMediaCardItem, used as the grid root of the
/// Videos, Shows, Artists, Albums, Genres and Playlists sections and inside
/// detail screens. Owns a diffable data source keyed by MacLCLibraryItemID,
/// filters in memory, shows an empty state, plays or opens items on
/// double-click / Return, drags items out, and keeps its selection across
/// updates. Main thread only.
@interface MacLCLibraryGridViewController : NSViewController

- (instancetype)initWithShape:(MacLCArtworkShape)shape
                subtitleStyle:(MacLCCardSubtitleStyle)subtitleStyle NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithNibName:(nullable NSNibName)nibNameOrNil
                         bundle:(nullable NSBundle *)nibBundleOrNil NS_UNAVAILABLE;
- (nullable instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;

/// Every item; the grid shows the ones matching the search string.
@property (nonatomic, copy) NSArray<id<VLCMediaLibraryItemProtocol>> *items;

/// Double-click or Return on an item. nil plays the visible items from it.
@property (nonatomic, copy, nullable) void (^openHandler)(id<VLCMediaLibraryItemProtocol> item);

/// Empty state for an empty list (not for an empty search).
- (void)setEmptyStateSymbolName:(NSString *)symbolName
                          title:(NSString *)title
                        message:(nullable NSString *)message;
/// A prominent button under that empty state (the next action to take).
- (void)setEmptyStateActionTitle:(nullable NSString *)title handler:(nullable void (^)(void))handler;

- (void)applySearchString:(NSString *)searchString;
/// Scrolls to the item, selects it and makes the grid first responder.
- (void)showItem:(id<VLCMediaLibraryItemProtocol>)item;

@property (readonly) NSArray<id<VLCMediaLibraryItemProtocol>> *visibleItems;
@property (readonly) NSCollectionView *collectionView;

@end

NS_ASSUME_NONNULL_END
