/*****************************************************************************
 * MacLCLibraryStore.h: the native library's single source of library data
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
@class VLCMediaLibraryMediaItem;
@class VLCMediaLibraryAlbum;
@class VLCMediaLibraryArtist;
@class VLCMediaLibraryGenre;
@class VLCMediaLibraryShow;
@class VLCMediaLibraryPlaylist;
@class VLCMediaLibraryEntryPoint;

NS_ASSUME_NONNULL_BEGIN

/// Posted on the main thread, at most every 150 ms, after one or more lists
/// changed. userInfo[MacLCLibraryStoreChangedCollectionsKey] is an NSSet of
/// NSNumber (MacLCLibraryCollection) naming the lists that changed.
extern NSNotificationName const MacLCLibraryStoreDidChangeNotification;
extern NSString * const MacLCLibraryStoreChangedCollectionsKey;

/// Posted on the main thread when an object's metadata changed without the
/// list changing (title, progress, favourite, artwork). The notification
/// object is the MacLCLibraryItemID of the object.
extern NSNotificationName const MacLCLibraryStoreItemDidUpdateNotification;

/// Posted on the main thread when indexing starts, progresses or stops.
/// Read `indexing` and `indexingLocation` from the store.
extern NSNotificationName const MacLCLibraryStoreIndexingDidChangeNotification;

/// Posted on the main thread when the list of library folders changed.
extern NSNotificationName const MacLCLibraryStoreFoldersDidChangeNotification;

/// Builds the identifier of a library object ("media:42", "album:7",
/// "artist:3", "genre:5", "show:2", "playlist:9", "group:4").
FOUNDATION_EXPORT MacLCLibraryItemID MacLCLibraryItemIdentifier(id<VLCMediaLibraryItemProtocol> item);

/// Main-thread facade over the media library for every native library screen.
/// It wraps VLCLibraryModel (which already fetches on background queues),
/// derives the lists MacLC needs, coalesces change bursts during indexing,
/// and never blocks the main thread on a database query.
@interface MacLCLibraryStore : NSObject

/// The shared store, or nil when the media library is unavailable.
@property (class, readonly, nullable) MacLCLibraryStore *sharedStore;

/// Whether the library has no media at all (every list empty), known once the
/// first load finished. Before that, `loaded` is NO.
@property (readonly, getter=isLoaded) BOOL loaded;
@property (readonly, getter=isEmpty) BOOL empty;

/// Indexing state (discovery or parsing running) and the folder being
/// scanned, for the sidebar's footer-free progress affordance.
@property (readonly, getter=isIndexing) BOOL indexing;
@property (readonly, copy, nullable) NSString *indexingLocation;

/// The current contents of a list, in the store's default order. Cheap:
/// returns the cached array. Main thread only.
- (NSArray *)itemsInCollection:(MacLCLibraryCollection)collection;
- (NSUInteger)countOfCollection:(MacLCLibraryCollection)collection;

/// Children of a container. Each call returns what is cached and, when the
/// cache is cold, fetches in the background and calls the completion on the
/// main thread (the completion is also called, synchronously, when the
/// answer is already cached).
- (void)episodesOfShow:(VLCMediaLibraryShow *)show
            completion:(void (^)(NSArray<VLCMediaLibraryMediaItem *> *episodes))completion;
- (void)tracksOfAlbum:(VLCMediaLibraryAlbum *)album
           completion:(void (^)(NSArray<VLCMediaLibraryMediaItem *> *tracks))completion;
- (void)albumsOfArtist:(VLCMediaLibraryArtist *)artist
            completion:(void (^)(NSArray<VLCMediaLibraryAlbum *> *albums))completion;
- (void)tracksOfArtist:(VLCMediaLibraryArtist *)artist
            completion:(void (^)(NSArray<VLCMediaLibraryMediaItem *> *tracks))completion;
- (void)albumsOfGenre:(VLCMediaLibraryGenre *)genre
           completion:(void (^)(NSArray<VLCMediaLibraryAlbum *> *albums))completion;
- (void)itemsOfPlaylist:(VLCMediaLibraryPlaylist *)playlist
             completion:(void (^)(NSArray<VLCMediaLibraryMediaItem *> *items))completion;

/// Library folders ("entry points") and their management.
@property (readonly) NSArray<VLCMediaLibraryEntryPoint *> *folders;
- (void)addFolderAtURL:(NSURL *)url;
- (void)removeFolderAtURL:(NSURL *)url;
/// Adds ~/Movies and ~/Music (the one-click choice of the empty library).
- (void)addStandardMediaFolders;
/// Rescans every folder.
- (void)rescanFolders;

/// Playlists.
- (nullable VLCMediaLibraryPlaylist *)createPlaylistNamed:(NSString *)name
                                               withItems:(NSArray<VLCMediaLibraryMediaItem *> *)items;
- (BOOL)deletePlaylist:(VLCMediaLibraryPlaylist *)playlist;

@end

NS_ASSUME_NONNULL_END
