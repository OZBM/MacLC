/*****************************************************************************
 * MacLCLibraryActions.h: what people can do with library items
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

@protocol VLCMediaLibraryItemProtocol;
@class VLCMediaLibraryMediaItem;
@class VLCMediaLibraryPlaylist;

NS_ASSUME_NONNULL_BEGIN

/// Every action on library items goes through here, so the context menus,
/// the keyboard, double-clicks and the detail headers behave the same.
/// Main thread only.
@interface MacLCLibraryActions : NSObject

/// Replaces the play queue with the media of `items` (containers expand to
/// their media, in order) and plays from the media at `startIndex`.
/// A video that was stopped part-way resumes where it stopped.
+ (void)playItems:(NSArray<id<VLCMediaLibraryItemProtocol>> *)items
       startingAt:(NSUInteger)startIndex;
/// Same with a shuffled order.
+ (void)shuffleItems:(NSArray<id<VLCMediaLibraryItemProtocol>> *)items;
/// Inserts the media right after the current one ("Play Next").
+ (void)playNext:(NSArray<id<VLCMediaLibraryItemProtocol>> *)items;
/// Appends the media to the end of the queue ("Add to Up Next").
+ (void)addToUpNext:(NSArray<id<VLCMediaLibraryItemProtocol>> *)items;

+ (void)setFavorite:(BOOL)favorite forItems:(NSArray<id<VLCMediaLibraryItemProtocol>> *)items;
+ (void)addItems:(NSArray<id<VLCMediaLibraryItemProtocol>> *)items
      toPlaylist:(VLCMediaLibraryPlaylist *)playlist;
/// Asks for a name (sheet on `window`) and creates a playlist with the items.
+ (void)newPlaylistWithItems:(NSArray<id<VLCMediaLibraryItemProtocol>> *)items
            fromWindow:(nullable NSWindow *)window;
+ (void)renamePlaylist:(VLCMediaLibraryPlaylist *)playlist fromWindow:(nullable NSWindow *)window;
/// Confirms with an alert (destructive, Cancel is the default) and deletes.
+ (void)deletePlaylist:(VLCMediaLibraryPlaylist *)playlist fromWindow:(nullable NSWindow *)window;
+ (void)removeItemsAtIndexes:(NSIndexSet *)indexes fromPlaylist:(VLCMediaLibraryPlaylist *)playlist;

+ (void)showInFinder:(NSArray<id<VLCMediaLibraryItemProtocol>> *)items;
/// Opens the media information panel for the first media.
+ (void)showInfoForItem:(id<VLCMediaLibraryItemProtocol>)item;
/// Marks videos watched (progress cleared, counted as played) or unwatched.
+ (void)setWatched:(BOOL)watched forItems:(NSArray<id<VLCMediaLibraryItemProtocol>> *)items;

/// The contextual menu for a selection, in this order and with these titles:
/// Play, Play Next, Add to Up Next | Add to Playlist ▸ (New Playlist…,
/// separator, playlists), Favorite / Remove from Favorites |
/// Mark as Watched / Mark as Unwatched (videos only) | Show in Finder,
/// Get Info | Rename…, Delete Playlist… (playlists only).
/// Items that do not apply are omitted, not disabled.
+ (NSMenu *)contextMenuForItems:(NSArray<id<VLCMediaLibraryItemProtocol>> *)items
                         window:(nullable NSWindow *)window;

/// Pasteboard writer for dragging items out (file URLs of file-backed
/// media, plus the internal media-library pasteboard type).
+ (nullable id<NSPasteboardWriting>)pasteboardWriterForItem:(id<VLCMediaLibraryItemProtocol>)item;

@end

NS_ASSUME_NONNULL_END
