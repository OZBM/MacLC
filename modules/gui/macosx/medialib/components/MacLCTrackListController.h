/*****************************************************************************
 * MacLCTrackListController.h: the library's one table of media items
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

@class VLCMediaLibraryMediaItem;

NS_ASSUME_NONNULL_BEGIN

typedef NS_OPTIONS(NSUInteger, MacLCTrackListColumns) {
    /// Track number (album order), right-aligned, tertiaryLabel, 36 pt.
    MacLCTrackListColumnNumber     = 1 << 0,
    /// 16:9 thumbnail 64 × 36 in the row, for videos and episodes.
    MacLCTrackListColumnThumbnail  = 1 << 1,
    MacLCTrackListColumnTitle      = 1 << 2,
    MacLCTrackListColumnArtist     = 1 << 3,
    MacLCTrackListColumnAlbum      = 1 << 4,
    MacLCTrackListColumnGenre      = 1 << 5,
    /// "4:12" or "1:42:05", monospaced digits, right-aligned, 64 pt.
    MacLCTrackListColumnDuration   = 1 << 6,
    MacLCTrackListColumnPlays      = 1 << 7,
    /// Relative date ("Today", "Sep 12"), secondaryLabel.
    MacLCTrackListColumnDateAdded  = 1 << 8,
    /// Picture badges text ("4K · HDR10"), secondaryLabel.
    MacLCTrackListColumnFormat     = 1 << 9,
};

/// Owns a scroll view and an NSTableView (style full width, alternating rows,
/// row height 28, 44 with the thumbnail column; column headers sortable when
/// `sortable`; autosaved column widths under `autosaveName`). The row playing
/// now shows speaker.wave.2.fill (accent) in place of its number.
/// Behaviour: double-click or Return plays the list from the clicked row
/// (MacLCLibraryActions playItems:startingAt:); Space is left to the menu's
/// Play/Pause; right-click shows MacLCLibraryActions' context menu for the
/// selection; rows drag out as MacLCLibraryActions' pasteboard writers;
/// Delete calls deleteHandler when set; drag-reordering within the table
/// calls reorderHandler when set. Type-to-select on the title.
@interface MacLCTrackListController : NSObject <NSTableViewDataSource, NSTableViewDelegate>

- (instancetype)initWithColumns:(MacLCTrackListColumns)columns
                   autosaveName:(nullable NSString *)autosaveName NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@property (readonly) NSScrollView *scrollView;
@property (readonly) NSTableView *tableView;

/// Replacing the items keeps the selection of items still present.
@property (nonatomic, copy) NSArray<VLCMediaLibraryMediaItem *> *items;
@property (nonatomic) BOOL sortable;

@property (nonatomic, copy, nullable) void (^deleteHandler)(NSIndexSet *rows);
@property (nonatomic, copy, nullable) void (^reorderHandler)(NSIndexSet *rows, NSUInteger destinationRow);

/// Filters rows whose title, artist or album contains the string
/// (case- and diacritic-insensitive). Empty shows everything.
- (void)applySearchString:(NSString *)searchString;
@property (readonly) NSUInteger numberOfVisibleRows;

@end

NS_ASSUME_NONNULL_END
