/*****************************************************************************
 * MacLCLibraryStore.m: the native library's single source of library data
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

#import "medialib/data/MacLCLibraryStore.h"

#import <vlc_common.h>
#import <vlc_media_library.h>

#import "extensions/NSArray+VLCAdditions.h"
#import "extensions/NSString+Helpers.h"
#import "library/VLCLibraryController.h"
#import "library/VLCLibraryDataTypes.h"
#import "main/VLCMain.h"

NSNotificationName const MacLCLibraryStoreDidChangeNotification = @"MacLCLibraryStoreDidChangeNotification";
NSString * const MacLCLibraryStoreChangedCollectionsKey = @"MacLCLibraryStoreChangedCollectionsKey";
NSNotificationName const MacLCLibraryStoreItemDidUpdateNotification = @"MacLCLibraryStoreItemDidUpdateNotification";
NSNotificationName const MacLCLibraryStoreIndexingDidChangeNotification = @"MacLCLibraryStoreIndexingDidChangeNotification";
NSNotificationName const MacLCLibraryStoreFoldersDidChangeNotification = @"MacLCLibraryStoreFoldersDidChangeNotification";

/* Changes arrive in bursts (a parse updates each media several times): wait
 * this long before refetching, and longer while the library is indexing so
 * big libraries are not reread many times a second. */
static const NSTimeInterval MacLCLibraryStoreQuietDelay = 0.15;
static const NSTimeInterval MacLCLibraryStoreIndexingDelay = 1.0;
static const uint32_t MacLCLibraryStoreRecentLimit = 30;
static const uint32_t MacLCLibraryStoreHistoryLimit = 60;
static const float MacLCLibraryStoreStartedProgress = 0.02f;
static const float MacLCLibraryStoreFinishedProgress = 0.95f;

MacLCLibraryItemID MacLCLibraryItemIdentifier(id<VLCMediaLibraryItemProtocol> item)
{
    NSString *prefix = @"item";
    if ([item isKindOfClass:VLCMediaLibraryMediaItem.class]) {
        prefix = @"media";
    } else if ([item isKindOfClass:VLCMediaLibraryAlbum.class]) {
        prefix = @"album";
    } else if ([item isKindOfClass:VLCMediaLibraryArtist.class]) {
        prefix = @"artist";
    } else if ([item isKindOfClass:VLCMediaLibraryGenre.class]) {
        prefix = @"genre";
    } else if ([item isKindOfClass:VLCMediaLibraryShow.class]) {
        prefix = @"show";
    } else if ([item isKindOfClass:VLCMediaLibraryPlaylist.class]) {
        prefix = @"playlist";
    } else if ([item isKindOfClass:VLCMediaLibraryGroup.class]) {
        prefix = @"group";
    }
    return [NSString stringWithFormat:@"%@:%lld", prefix, item.libraryID];
}

static NSIndexSet *MacLCMediaCollections(void)
{
    NSMutableIndexSet * const set = [NSMutableIndexSet indexSet];
    [set addIndex:MacLCLibraryCollectionVideos];
    [set addIndex:MacLCLibraryCollectionShows];
    [set addIndex:MacLCLibraryCollectionSongs];
    [set addIndex:MacLCLibraryCollectionContinueWatching];
    [set addIndex:MacLCLibraryCollectionRecentlyAddedVideos];
    [set addIndex:MacLCLibraryCollectionRecentlyPlayedMusic];
    [set addIndex:MacLCLibraryCollectionFavoriteVideos];
    [set addIndex:MacLCLibraryCollectionFavoriteSongs];
    [set addIndex:MacLCLibraryCollectionPlaylists];
    return set;
}

static NSComparisonResult MacLCCompareNames(NSString *lhs, NSString *rhs)
{
    return [lhs ?: @"" localizedStandardCompare:rhs ?: @""];
}

@interface MacLCLibraryStore ()
{
    vlc_medialibrary_t *_mediaLibrary;
    /* Set on the fetch queue at termination: the media library is released
     * right after the interface, so nothing may query it any more. */
    BOOL _closed;
    vlc_ml_event_callback_t *_eventCallback;
    dispatch_queue_t _fetchQueue;

    /* Main thread only. */
    NSMutableArray<NSArray *> *_collections;
    NSMutableIndexSet *_loadedCollections;
    NSMutableIndexSet *_pendingCollections;
    BOOL _refetchScheduled;
    BOOL _refetchRunning;
    NSMutableDictionary<NSString *, NSArray *> *_childrenCache;
    NSArray<VLCMediaLibraryEntryPoint *> *_folders;
    BOOL _discovering;
    BOOL _backgroundBusy;
    NSDictionary<NSNumber *, NSString *> *_artistNames;
    NSDictionary<NSNumber *, NSString *> *_albumTitles;
    NSDictionary<NSNumber *, NSString *> *_genreNames;
}

- (void)handleEventWithCollections:(nullable NSIndexSet *)collections
                     updatedItemID:(nullable NSString *)updatedItemID
                    foldersChanged:(BOOL)foldersChanged;
- (void)setDiscovering:(BOOL)discovering location:(nullable NSString *)location;
- (void)setBackgroundBusy:(BOOL)busy;

@end

static void MacLCLibraryStoreEventCallback(void *data, const vlc_ml_event_t *event)
{
    MacLCLibraryStore * const store = (__bridge MacLCLibraryStore *)data;
    NSIndexSet *collections = nil;
    NSString *updatedItemID = nil;
    BOOL foldersChanged = NO;

    switch (event->i_type) {
        case VLC_ML_EVENT_MEDIA_ADDED:
        case VLC_ML_EVENT_MEDIA_DELETED:
            collections = MacLCMediaCollections();
            break;
        case VLC_ML_EVENT_MEDIA_UPDATED:
            collections = MacLCMediaCollections();
            updatedItemID = [NSString stringWithFormat:@"media:%lld", event->modification.i_entity_id];
            break;
        case VLC_ML_EVENT_ARTIST_ADDED:
        case VLC_ML_EVENT_ARTIST_DELETED:
        case VLC_ML_EVENT_ARTIST_UPDATED: {
            NSMutableIndexSet * const set = [NSMutableIndexSet indexSetWithIndex:MacLCLibraryCollectionArtists];
            [set addIndex:MacLCLibraryCollectionFavoriteArtists];
            collections = set;
            if (event->i_type == VLC_ML_EVENT_ARTIST_UPDATED) {
                updatedItemID = [NSString stringWithFormat:@"artist:%lld", event->modification.i_entity_id];
            }
            break;
        }
        case VLC_ML_EVENT_ALBUM_ADDED:
        case VLC_ML_EVENT_ALBUM_DELETED:
        case VLC_ML_EVENT_ALBUM_UPDATED: {
            NSMutableIndexSet * const set = [NSMutableIndexSet indexSetWithIndex:MacLCLibraryCollectionAlbums];
            [set addIndex:MacLCLibraryCollectionFavoriteAlbums];
            collections = set;
            if (event->i_type == VLC_ML_EVENT_ALBUM_UPDATED) {
                updatedItemID = [NSString stringWithFormat:@"album:%lld", event->modification.i_entity_id];
            }
            break;
        }
        case VLC_ML_EVENT_GENRE_ADDED:
        case VLC_ML_EVENT_GENRE_DELETED:
        case VLC_ML_EVENT_GENRE_UPDATED:
            collections = [NSIndexSet indexSetWithIndex:MacLCLibraryCollectionGenres];
            if (event->i_type == VLC_ML_EVENT_GENRE_UPDATED) {
                updatedItemID = [NSString stringWithFormat:@"genre:%lld", event->modification.i_entity_id];
            }
            break;
        case VLC_ML_EVENT_PLAYLIST_ADDED:
        case VLC_ML_EVENT_PLAYLIST_DELETED:
        case VLC_ML_EVENT_PLAYLIST_UPDATED:
            collections = [NSIndexSet indexSetWithIndex:MacLCLibraryCollectionPlaylists];
            if (event->i_type == VLC_ML_EVENT_PLAYLIST_UPDATED) {
                updatedItemID = [NSString stringWithFormat:@"playlist:%lld", event->modification.i_entity_id];
            }
            break;
        case VLC_ML_EVENT_HISTORY_CHANGED: {
            NSMutableIndexSet * const set = [NSMutableIndexSet indexSetWithIndex:MacLCLibraryCollectionContinueWatching];
            [set addIndex:MacLCLibraryCollectionRecentlyPlayedMusic];
            collections = set;
            break;
        }
        case VLC_ML_EVENT_FAVORITES_CHANGED: {
            NSMutableIndexSet * const set = [NSMutableIndexSet indexSetWithIndexesInRange:
                NSMakeRange(MacLCLibraryCollectionFavoriteVideos,
                            MacLCLibraryCollectionFavoriteArtists - MacLCLibraryCollectionFavoriteVideos + 1)];
            collections = set;
            break;
        }
        case VLC_ML_EVENT_FOLDER_ADDED:
        case VLC_ML_EVENT_FOLDER_UPDATED:
        case VLC_ML_EVENT_FOLDER_DELETED:
        case VLC_ML_EVENT_ENTRY_POINT_ADDED:
        case VLC_ML_EVENT_ENTRY_POINT_REMOVED:
        case VLC_ML_EVENT_ENTRY_POINT_BANNED:
        case VLC_ML_EVENT_ENTRY_POINT_UNBANNED:
            foldersChanged = YES;
            break;
        case VLC_ML_EVENT_DISCOVERY_STARTED: {
            dispatch_async(dispatch_get_main_queue(), ^{
                [store setDiscovering:YES location:nil];
            });
            return;
        }
        case VLC_ML_EVENT_DISCOVERY_PROGRESS: {
            NSString * const location = toNSStr(event->discovery_progress.psz_entry_point);
            dispatch_async(dispatch_get_main_queue(), ^{
                [store setDiscovering:YES location:location];
            });
            return;
        }
        case VLC_ML_EVENT_DISCOVERY_COMPLETED:
        case VLC_ML_EVENT_DISCOVERY_FAILED: {
            dispatch_async(dispatch_get_main_queue(), ^{
                [store setDiscovering:NO location:nil];
            });
            return;
        }
        case VLC_ML_EVENT_BACKGROUND_IDLE_CHANGED: {
            const BOOL idle = event->background_idle_changed.b_idle;
            dispatch_async(dispatch_get_main_queue(), ^{
                [store setBackgroundBusy:!idle];
            });
            return;
        }
        default:
            return;
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        [store handleEventWithCollections:collections
                            updatedItemID:updatedItemID
                           foldersChanged:foldersChanged];
    });
}

@implementation MacLCLibraryStore

+ (nullable MacLCLibraryStore *)sharedStore
{
    static MacLCLibraryStore *sharedStore = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        if (!VLCMain.sharedInstance.libraryController.shouldUseMediaLibrary) {
            return;
        }
        vlc_medialibrary_t * const mediaLibrary = vlc_ml_instance_get(getIntf());
        if (mediaLibrary == NULL) {
            return;
        }
        sharedStore = [[MacLCLibraryStore alloc] initWithMediaLibrary:mediaLibrary];
    });
    return sharedStore;
}

- (instancetype)initWithMediaLibrary:(vlc_medialibrary_t *)mediaLibrary
{
    self = [super init];
    if (self) {
        _mediaLibrary = mediaLibrary;
        dispatch_queue_attr_t const attributes =
            dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_USER_INITIATED, 0);
        _fetchQueue = dispatch_queue_create("org.maclc.library-store", attributes);
        _collections = [NSMutableArray arrayWithCapacity:MacLCLibraryCollectionCount];
        for (NSInteger i = 0; i < MacLCLibraryCollectionCount; i++) {
            [_collections addObject:@[]];
        }
        _loadedCollections = [NSMutableIndexSet indexSet];
        _pendingCollections = [NSMutableIndexSet indexSet];
        _childrenCache = [NSMutableDictionary dictionary];
        _folders = @[];

        _eventCallback = vlc_ml_event_register_callback(_mediaLibrary,
                                                        MacLCLibraryStoreEventCallback,
                                                        (__bridge void *)self);
        [NSNotificationCenter.defaultCenter addObserver:self
                                               selector:@selector(applicationWillTerminate:)
                                                   name:NSApplicationWillTerminateNotification
                                                 object:nil];

        [self scheduleRefetchOfCollections:
            [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, MacLCLibraryCollectionCount)]];
        [self reloadFolders];
    }
    return self;
}

- (void)dealloc
{
    [NSNotificationCenter.defaultCenter removeObserver:self];
    if (_eventCallback != NULL) {
        vlc_ml_event_unregister_callback(_mediaLibrary, _eventCallback);
    }
}

- (void)applicationWillTerminate:(NSNotification *)notification
{
    /* The media library asserts that every callback is gone when it is
     * released, which happens right after the interface closes. */
    if (_eventCallback != NULL) {
        vlc_ml_event_unregister_callback(_mediaLibrary, _eventCallback);
        _eventCallback = NULL;
    }
    /* Let a fetch in flight finish, then keep later ones away. */
    dispatch_sync(_fetchQueue, ^{
        self->_closed = YES;
    });
}

// MARK: - State

- (BOOL)isLoaded
{
    return [_loadedCollections containsIndexesInRange:NSMakeRange(0, MacLCLibraryCollectionCount)];
}

- (BOOL)isEmpty
{
    return self.isLoaded
        && [self countOfCollection:MacLCLibraryCollectionVideos] == 0
        && [self countOfCollection:MacLCLibraryCollectionShows] == 0
        && [self countOfCollection:MacLCLibraryCollectionSongs] == 0;
}

- (BOOL)isIndexing
{
    return _discovering || _backgroundBusy;
}

- (void)setDiscovering:(BOOL)discovering location:(nullable NSString *)location
{
    const BOOL wasIndexing = self.isIndexing;
    NSString * const oldLocation = _indexingLocation;
    _discovering = discovering;
    if (location.length > 0) {
        NSURL * const url = [NSURL URLWithString:location];
        NSString * const name = url.lastPathComponent.length > 0 ? url.lastPathComponent : location;
        _indexingLocation = name.stringByRemovingPercentEncoding ?: name;
    } else if (!self.isIndexing) {
        _indexingLocation = nil;
    }
    if (wasIndexing != self.isIndexing || ![oldLocation ?: @"" isEqualToString:_indexingLocation ?: @""]) {
        [NSNotificationCenter.defaultCenter postNotificationName:MacLCLibraryStoreIndexingDidChangeNotification
                                                          object:self];
    }
    if (!self.isIndexing) {
        /* The last burst may have been held back by the indexing delay. */
        [self scheduleRefetchOfCollections:MacLCMediaCollections()];
    }
}

- (void)setBackgroundBusy:(BOOL)busy
{
    const BOOL wasIndexing = self.isIndexing;
    _backgroundBusy = busy;
    if (!self.isIndexing) {
        _indexingLocation = nil;
    }
    if (wasIndexing != self.isIndexing) {
        [NSNotificationCenter.defaultCenter postNotificationName:MacLCLibraryStoreIndexingDidChangeNotification
                                                          object:self];
    }
}

// MARK: - Lists

- (NSArray *)itemsInCollection:(MacLCLibraryCollection)collection
{
    if (collection < 0 || collection >= MacLCLibraryCollectionCount) {
        return @[];
    }
    return _collections[collection];
}

- (NSUInteger)countOfCollection:(MacLCLibraryCollection)collection
{
    return [self itemsInCollection:collection].count;
}

- (void)handleEventWithCollections:(nullable NSIndexSet *)collections
                     updatedItemID:(nullable NSString *)updatedItemID
                    foldersChanged:(BOOL)foldersChanged
{
    if (collections.count > 0) {
        /* Children lists (album tracks, episodes...) can change with any of
         * these events: drop them, detail screens ask again on the change
         * notification. */
        [_childrenCache removeAllObjects];
        [self scheduleRefetchOfCollections:collections];
    }
    if (updatedItemID != nil) {
        [NSNotificationCenter.defaultCenter postNotificationName:MacLCLibraryStoreItemDidUpdateNotification
                                                          object:updatedItemID];
    }
    if (foldersChanged) {
        [self reloadFolders];
    }
}

- (void)scheduleRefetchOfCollections:(NSIndexSet *)collections
{
    [_pendingCollections addIndexes:collections];
    if (_refetchScheduled || _refetchRunning) {
        return;
    }
    _refetchScheduled = YES;
    const NSTimeInterval delay = self.isIndexing ? MacLCLibraryStoreIndexingDelay : MacLCLibraryStoreQuietDelay;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        self->_refetchScheduled = NO;
        [self runPendingRefetch];
    });
}

- (void)runPendingRefetch
{
    if (_pendingCollections.count == 0) {
        return;
    }
    NSIndexSet * const collections = [_pendingCollections copy];
    [_pendingCollections removeAllIndexes];
    _refetchRunning = YES;

    dispatch_async(_fetchQueue, ^{
        if (self->_closed) {
            return;
        }
        NSMutableDictionary<NSNumber *, NSArray *> * const results = [NSMutableDictionary dictionary];
        [collections enumerateIndexesUsingBlock:^(NSUInteger collection, BOOL * const stop) {
            NSArray * const items = [self fetchCollection:(MacLCLibraryCollection)collection];
            if (items != nil) {
                results[@(collection)] = items;
            }
        }];

        dispatch_async(dispatch_get_main_queue(), ^{
            self->_refetchRunning = NO;
            const BOOL wasLoaded = self.isLoaded;
            NSMutableSet<NSNumber *> * const changed = [NSMutableSet set];
            [results enumerateKeysAndObjectsUsingBlock:^(NSNumber * const key, NSArray * const items, BOOL * const stop) {
                const NSUInteger collection = key.unsignedIntegerValue;
                if (collection == MacLCLibraryCollectionArtists) {
                    self->_artistNames = [MacLCLibraryStore namesByIDOfItems:items];
                } else if (collection == MacLCLibraryCollectionAlbums) {
                    self->_albumTitles = [MacLCLibraryStore namesByIDOfItems:items];
                } else if (collection == MacLCLibraryCollectionGenres) {
                    self->_genreNames = [MacLCLibraryStore namesByIDOfItems:items];
                }
                NSArray * const previous = self->_collections[collection];
                const BOOL firstLoad = ![self->_loadedCollections containsIndex:collection];
                [self->_loadedCollections addIndex:collection];
                self->_collections[collection] = items;
                if (firstLoad || ![MacLCLibraryStore list:previous hasSameContentAs:items]) {
                    [changed addObject:key];
                }
            }];
            if (changed.count > 0 || wasLoaded != self.isLoaded) {
                [NSNotificationCenter.defaultCenter postNotificationName:MacLCLibraryStoreDidChangeNotification
                                                                  object:self
                                                                userInfo:@{MacLCLibraryStoreChangedCollectionsKey: changed}];
            }
            /* Events that arrived during the fetch. */
            if (self->_pendingCollections.count > 0) {
                NSIndexSet * const pending = [self->_pendingCollections copy];
                [self->_pendingCollections removeAllIndexes];
                [self scheduleRefetchOfCollections:pending];
            }
        });
    });
}

/* Same objects in the same order with the same displayed values: skips
 * pointless snapshot work when an update did not change a list. */
+ (BOOL)list:(NSArray *)lhs hasSameContentAs:(NSArray *)rhs
{
    if (lhs.count != rhs.count) {
        return NO;
    }
    for (NSUInteger i = 0; i < lhs.count; i++) {
        id<VLCMediaLibraryItemProtocol> const a = lhs[i];
        id<VLCMediaLibraryItemProtocol> const b = rhs[i];
        if (a.libraryID != b.libraryID || ![a.displayString ?: @"" isEqualToString:b.displayString ?: @""]) {
            return NO;
        }
        if ([a isKindOfClass:VLCMediaLibraryMediaItem.class] && [b isKindOfClass:VLCMediaLibraryMediaItem.class]) {
            VLCMediaLibraryMediaItem * const ma = (VLCMediaLibraryMediaItem *)a;
            VLCMediaLibraryMediaItem * const mb = (VLCMediaLibraryMediaItem *)b;
            if (fabsf(ma.progress - mb.progress) > 0.001f || ma.playCount != mb.playCount
                || ma.favorited != mb.favorited || ma.smallArtworkGenerated != mb.smallArtworkGenerated) {
                return NO;
            }
        }
    }
    return YES;
}

+ (NSDictionary<NSNumber *, NSString *> *)namesByIDOfItems:(NSArray<id<VLCMediaLibraryItemProtocol>> *)items
{
    NSMutableDictionary<NSNumber *, NSString *> * const names =
        [NSMutableDictionary dictionaryWithCapacity:items.count];
    for (id<VLCMediaLibraryItemProtocol> const item in items) {
        if (item.displayString.length > 0) {
            names[@(item.libraryID)] = item.displayString;
        }
    }
    return names;
}

- (nullable NSString *)nameOfArtistWithID:(int64_t)artistID
{
    return _artistNames[@(artistID)];
}

- (nullable NSString *)titleOfAlbumWithID:(int64_t)albumID
{
    return _albumTitles[@(albumID)];
}

- (nullable NSString *)nameOfGenreWithID:(int64_t)genreID
{
    return _genreNames[@(genreID)];
}

// MARK: - Fetching (fetch queue)

- (nullable NSArray *)fetchCollection:(MacLCLibraryCollection)collection
{
    vlc_ml_query_params_t params = vlc_ml_query_params_create();
    vlc_medialibrary_t * const ml = _mediaLibrary;

    switch (collection) {
        case MacLCLibraryCollectionVideos: {
            vlc_ml_media_list_t * const list = vlc_ml_list_video_media(ml, &params);
            NSArray<VLCMediaLibraryMediaItem *> * const all = [NSArray arrayFromVlcMediaList:list];
            if (list != NULL) {
                vlc_ml_media_list_release(list);
            }
            if (all == nil) {
                return nil;
            }
            NSMutableArray * const videos = [NSMutableArray arrayWithCapacity:all.count];
            for (VLCMediaLibraryMediaItem * const item in all) {
                if (item.mediaSubType != VLC_ML_MEDIA_SUBTYPE_SHOW_EPISODE) {
                    [videos addObject:item];
                }
            }
            return [MacLCLibraryStore sortedByDisplayString:videos];
        }
        case MacLCLibraryCollectionSongs: {
            vlc_ml_media_list_t * const list = vlc_ml_list_audio_media(ml, &params);
            NSArray * const songs = [NSArray arrayFromVlcMediaList:list];
            if (list != NULL) {
                vlc_ml_media_list_release(list);
            }
            return songs == nil ? nil : [MacLCLibraryStore sortedByDisplayString:songs];
        }
        case MacLCLibraryCollectionShows: {
            vlc_ml_show_list_t * const list = vlc_ml_list_shows(ml, &params);
            if (list == NULL) {
                return nil;
            }
            NSMutableArray * const shows = [NSMutableArray arrayWithCapacity:list->i_nb_items];
            for (size_t i = 0; i < list->i_nb_items; i++) {
                VLCMediaLibraryShow * const show = [[VLCMediaLibraryShow alloc] initWithShow:&list->p_items[i]];
                if (show != nil) {
                    [shows addObject:show];
                }
            }
            vlc_ml_show_list_release(list);
            return [MacLCLibraryStore sortedByDisplayString:shows];
        }
        case MacLCLibraryCollectionArtists:
        case MacLCLibraryCollectionFavoriteArtists: {
            vlc_ml_artist_list_t * const list = collection == MacLCLibraryCollectionArtists
                ? vlc_ml_list_artists(ml, &params, false)
                : vlc_ml_list_favorite_artists(ml, &params);
            if (list == NULL) {
                return nil;
            }
            NSMutableArray * const artists = [NSMutableArray arrayWithCapacity:list->i_nb_items];
            for (size_t i = 0; i < list->i_nb_items; i++) {
                VLCMediaLibraryArtist * const artist = [[VLCMediaLibraryArtist alloc] initWithArtist:&list->p_items[i]];
                if (artist != nil) {
                    [artists addObject:artist];
                }
            }
            vlc_ml_artist_list_release(list);
            return [MacLCLibraryStore sortedArtists:artists];
        }
        case MacLCLibraryCollectionAlbums:
        case MacLCLibraryCollectionFavoriteAlbums: {
            vlc_ml_album_list_t * const list = collection == MacLCLibraryCollectionAlbums
                ? vlc_ml_list_albums(ml, &params)
                : vlc_ml_list_favorite_albums(ml, &params);
            if (list == NULL) {
                return nil;
            }
            NSMutableArray * const albums = [NSMutableArray arrayWithCapacity:list->i_nb_items];
            for (size_t i = 0; i < list->i_nb_items; i++) {
                VLCMediaLibraryAlbum * const album = [[VLCMediaLibraryAlbum alloc] initWithAlbum:&list->p_items[i]];
                if (album != nil) {
                    [albums addObject:album];
                }
            }
            vlc_ml_album_list_release(list);
            return [MacLCLibraryStore sortedByDisplayString:albums];
        }
        case MacLCLibraryCollectionGenres: {
            vlc_ml_genre_list_t * const list = vlc_ml_list_genres(ml, &params);
            if (list == NULL) {
                return nil;
            }
            NSMutableArray * const genres = [NSMutableArray arrayWithCapacity:list->i_nb_items];
            for (size_t i = 0; i < list->i_nb_items; i++) {
                VLCMediaLibraryGenre * const genre = [[VLCMediaLibraryGenre alloc] initWithGenre:&list->p_items[i]];
                if (genre != nil) {
                    [genres addObject:genre];
                }
            }
            vlc_ml_genre_list_release(list);
            return [MacLCLibraryStore sortedByDisplayString:genres];
        }
        case MacLCLibraryCollectionPlaylists: {
            vlc_ml_playlist_list_t * const list = vlc_ml_list_playlists(ml, &params, VLC_ML_PLAYLIST_TYPE_ALL);
            if (list == NULL) {
                return nil;
            }
            NSMutableArray * const playlists = [NSMutableArray arrayWithCapacity:list->i_nb_items];
            for (size_t i = 0; i < list->i_nb_items; i++) {
                VLCMediaLibraryPlaylist * const playlist =
                    [[VLCMediaLibraryPlaylist alloc] initWithPlaylist:&list->p_items[i]];
                if (playlist != nil) {
                    [playlists addObject:playlist];
                }
            }
            vlc_ml_playlist_list_release(list);
            return [MacLCLibraryStore sortedByDisplayString:playlists];
        }
        case MacLCLibraryCollectionContinueWatching: {
            params.i_nbResults = MacLCLibraryStoreHistoryLimit;
            vlc_ml_media_list_t * const list = vlc_ml_list_video_history(ml, &params);
            NSArray<VLCMediaLibraryMediaItem *> * const history = [NSArray arrayFromVlcMediaList:list];
            if (list != NULL) {
                vlc_ml_media_list_release(list);
            }
            if (history == nil) {
                return nil;
            }
            NSMutableArray * const started = [NSMutableArray array];
            for (VLCMediaLibraryMediaItem * const item in history) {
                if (item.progress > MacLCLibraryStoreStartedProgress
                    && item.progress < MacLCLibraryStoreFinishedProgress) {
                    [started addObject:item];
                }
            }
            return started;
        }
        case MacLCLibraryCollectionRecentlyAddedVideos: {
            params.i_sort = VLC_ML_SORTING_INSERTIONDATE;
            params.b_desc = true;
            params.i_nbResults = MacLCLibraryStoreRecentLimit;
            vlc_ml_media_list_t * const list = vlc_ml_list_video_media(ml, &params);
            NSArray * const videos = [NSArray arrayFromVlcMediaList:list];
            if (list != NULL) {
                vlc_ml_media_list_release(list);
            }
            return videos;
        }
        case MacLCLibraryCollectionRecentlyPlayedMusic: {
            params.i_nbResults = MacLCLibraryStoreRecentLimit;
            vlc_ml_media_list_t * const list = vlc_ml_list_audio_history(ml, &params);
            NSArray * const songs = [NSArray arrayFromVlcMediaList:list];
            if (list != NULL) {
                vlc_ml_media_list_release(list);
            }
            return songs;
        }
        case MacLCLibraryCollectionFavoriteVideos:
        case MacLCLibraryCollectionFavoriteSongs: {
            vlc_ml_media_list_t * const list = collection == MacLCLibraryCollectionFavoriteVideos
                ? vlc_ml_list_favorite_videos(ml, &params)
                : vlc_ml_list_favorite_audios(ml, &params);
            NSArray * const media = [NSArray arrayFromVlcMediaList:list];
            if (list != NULL) {
                vlc_ml_media_list_release(list);
            }
            return media == nil ? nil : [MacLCLibraryStore sortedByDisplayString:media];
        }
        default:
            return nil;
    }
}

+ (NSArray *)sortedByDisplayString:(NSArray *)items
{
    return [items sortedArrayUsingComparator:^NSComparisonResult(id<VLCMediaLibraryItemProtocol> const a,
                                                                 id<VLCMediaLibraryItemProtocol> const b) {
        return MacLCCompareNames(a.displayString, b.displayString);
    }];
}

/* Unknown and "various" artists sort last: they are catch-alls, not people. */
+ (NSArray *)sortedArtists:(NSArray<VLCMediaLibraryArtist *> *)artists
{
    return [artists sortedArrayUsingComparator:^NSComparisonResult(VLCMediaLibraryArtist * const a,
                                                                   VLCMediaLibraryArtist * const b) {
        const BOOL aSpecial = a.libraryID <= 2;
        const BOOL bSpecial = b.libraryID <= 2;
        if (aSpecial != bSpecial) {
            return aSpecial ? NSOrderedDescending : NSOrderedAscending;
        }
        return MacLCCompareNames(a.displayString, b.displayString);
    }];
}

// MARK: - Children

- (void)fetchChildrenForKey:(NSString *)key
                      block:(NSArray * (^)(void))fetchBlock
                 completion:(void (^)(NSArray *items))completion
{
    NSArray * const cached = _childrenCache[key];
    if (cached != nil) {
        completion(cached);
        return;
    }
    dispatch_async(_fetchQueue, ^{
        if (self->_closed) {
            return;
        }
        NSArray * const items = fetchBlock() ?: @[];
        dispatch_async(dispatch_get_main_queue(), ^{
            self->_childrenCache[key] = items;
            completion(items);
        });
    });
}

- (void)episodesOfShow:(VLCMediaLibraryShow *)show
            completion:(void (^)(NSArray<VLCMediaLibraryMediaItem *> *))completion
{
    [self fetchChildrenForKey:[MacLCLibraryItemIdentifier(show) stringByAppendingString:@"/episodes"]
                        block:^NSArray *{
        return [show.episodes sortedArrayUsingComparator:^NSComparisonResult(VLCMediaLibraryMediaItem * const a,
                                                                            VLCMediaLibraryMediaItem * const b) {
            const uint32_t seasonA = a.showEpisode.seasonNumber;
            const uint32_t seasonB = b.showEpisode.seasonNumber;
            if (seasonA != seasonB) {
                return seasonA < seasonB ? NSOrderedAscending : NSOrderedDescending;
            }
            const uint32_t episodeA = a.showEpisode.episodeNumber;
            const uint32_t episodeB = b.showEpisode.episodeNumber;
            if (episodeA != episodeB) {
                return episodeA < episodeB ? NSOrderedAscending : NSOrderedDescending;
            }
            return MacLCCompareNames(a.title, b.title);
        }];
    } completion:completion];
}

- (void)tracksOfAlbum:(VLCMediaLibraryAlbum *)album
           completion:(void (^)(NSArray<VLCMediaLibraryMediaItem *> *))completion
{
    [self fetchChildrenForKey:[MacLCLibraryItemIdentifier(album) stringByAppendingString:@"/tracks"]
                        block:^NSArray *{
        return [album.mediaItems sortedArrayUsingComparator:^NSComparisonResult(VLCMediaLibraryMediaItem * const a,
                                                                               VLCMediaLibraryMediaItem * const b) {
            if (a.discNumber != b.discNumber) {
                return a.discNumber < b.discNumber ? NSOrderedAscending : NSOrderedDescending;
            }
            if (a.trackNumber != b.trackNumber) {
                return a.trackNumber < b.trackNumber ? NSOrderedAscending : NSOrderedDescending;
            }
            return MacLCCompareNames(a.title, b.title);
        }];
    } completion:completion];
}

- (void)albumsOfArtist:(VLCMediaLibraryArtist *)artist
            completion:(void (^)(NSArray<VLCMediaLibraryAlbum *> *))completion
{
    [self fetchChildrenForKey:[MacLCLibraryItemIdentifier(artist) stringByAppendingString:@"/albums"]
                        block:^NSArray *{
        return [artist.albums sortedArrayUsingComparator:^NSComparisonResult(VLCMediaLibraryAlbum * const a,
                                                                            VLCMediaLibraryAlbum * const b) {
            if (a.year != b.year && a.year > 0 && b.year > 0) {
                return a.year > b.year ? NSOrderedAscending : NSOrderedDescending;
            }
            return MacLCCompareNames(a.title, b.title);
        }];
    } completion:completion];
}

- (void)tracksOfArtist:(VLCMediaLibraryArtist *)artist
            completion:(void (^)(NSArray<VLCMediaLibraryMediaItem *> *))completion
{
    [self fetchChildrenForKey:[MacLCLibraryItemIdentifier(artist) stringByAppendingString:@"/tracks"]
                        block:^NSArray *{
        return [MacLCLibraryStore sortedByDisplayString:artist.mediaItems ?: @[]];
    } completion:completion];
}

- (void)albumsOfGenre:(VLCMediaLibraryGenre *)genre
           completion:(void (^)(NSArray<VLCMediaLibraryAlbum *> *))completion
{
    [self fetchChildrenForKey:[MacLCLibraryItemIdentifier(genre) stringByAppendingString:@"/albums"]
                        block:^NSArray *{
        return [MacLCLibraryStore sortedByDisplayString:genre.albums ?: @[]];
    } completion:completion];
}

- (void)itemsOfPlaylist:(VLCMediaLibraryPlaylist *)playlist
             completion:(void (^)(NSArray<VLCMediaLibraryMediaItem *> *))completion
{
    /* Playlist order is the user's: never sort it. */
    [self fetchChildrenForKey:[MacLCLibraryItemIdentifier(playlist) stringByAppendingString:@"/items"]
                        block:^NSArray *{
        VLCMediaLibraryPlaylist * const fresh = [VLCMediaLibraryPlaylist playlistForLibraryID:playlist.libraryID];
        return (fresh ?: playlist).mediaItems ?: @[];
    } completion:completion];
}

// MARK: - Folders

- (NSArray<VLCMediaLibraryEntryPoint *> *)folders
{
    return _folders;
}

- (void)reloadFolders
{
    vlc_medialibrary_t * const ml = _mediaLibrary;
    dispatch_async(_fetchQueue, ^{
        if (self->_closed) {
            return;
        }
        vlc_ml_query_params_t params = vlc_ml_query_params_create();
        vlc_ml_folder_list_t * const list = vlc_ml_list_entry_points(ml, &params);
        NSMutableArray * const folders = [NSMutableArray array];
        if (list != NULL) {
            for (size_t i = 0; i < list->i_nb_items; i++) {
                VLCMediaLibraryEntryPoint * const folder =
                    [[VLCMediaLibraryEntryPoint alloc] initWithEntryPoint:&list->p_items[i]];
                if (folder != nil) {
                    [folders addObject:folder];
                }
            }
            vlc_ml_folder_list_release(list);
        }
        [folders sortUsingComparator:^NSComparisonResult(VLCMediaLibraryEntryPoint * const a,
                                                         VLCMediaLibraryEntryPoint * const b) {
            return MacLCCompareNames(a.decodedMRL, b.decodedMRL);
        }];
        dispatch_async(dispatch_get_main_queue(), ^{
            self->_folders = [folders copy];
            [NSNotificationCenter.defaultCenter postNotificationName:MacLCLibraryStoreFoldersDidChangeNotification
                                                              object:self];
        });
    });
}

- (BOOL)hasFolderAtURL:(NSURL *)url
{
    NSString * const path = url.URLByStandardizingPath.path.stringByStandardizingPath;
    for (VLCMediaLibraryEntryPoint * const folder in _folders) {
        NSURL * const folderURL = [NSURL URLWithString:folder.MRL];
        NSString * const folderPath = folderURL.path.stringByStandardizingPath;
        if (folderPath != nil && [folderPath isEqualToString:path]) {
            return YES;
        }
    }
    return NO;
}

- (void)addFolderAtURL:(NSURL *)url
{
    if ([self hasFolderAtURL:url]) {
        return;
    }
    [VLCMain.sharedInstance.libraryController addFolderWithFileURL:url];
    [self reloadFolders];
}

- (void)removeFolderAtURL:(NSURL *)url
{
    [VLCMain.sharedInstance.libraryController removeFolderWithFileURL:url];
    [self reloadFolders];
}

- (void)addStandardMediaFolders
{
    NSFileManager * const fileManager = NSFileManager.defaultManager;
    for (NSNumber * const directory in @[@(NSMoviesDirectory), @(NSMusicDirectory)]) {
        NSURL * const url = [fileManager URLsForDirectory:directory.unsignedIntegerValue
                                                inDomains:NSUserDomainMask].firstObject;
        BOOL isDirectory = NO;
        if (url != nil && [fileManager fileExistsAtPath:url.path isDirectory:&isDirectory] && isDirectory) {
            [self addFolderAtURL:url];
        }
    }
}

- (void)rescanFolders
{
    vlc_medialibrary_t * const ml = _mediaLibrary;
    dispatch_async(_fetchQueue, ^{
        if (self->_closed) {
            return;
        }
        vlc_ml_reload_folder(ml, NULL);
    });
}

// MARK: - Playlists

- (nullable VLCMediaLibraryPlaylist *)createPlaylistNamed:(NSString *)name
                                               withItems:(NSArray<VLCMediaLibraryMediaItem *> *)items
{
    if (_closed) {
        return nil;
    }
    vlc_ml_playlist_t * const created = vlc_ml_playlist_create(_mediaLibrary, name.UTF8String);
    if (created == NULL) {
        return nil;
    }
    VLCMediaLibraryPlaylist * const playlist = [[VLCMediaLibraryPlaylist alloc] initWithPlaylist:created];
    const int64_t playlistID = created->i_id;
    vlc_ml_playlist_release(created);

    if (items.count > 0) {
        int64_t * const ids = calloc(items.count, sizeof(int64_t));
        if (ids != NULL) {
            for (NSUInteger i = 0; i < items.count; i++) {
                ids[i] = items[i].libraryID;
            }
            vlc_ml_playlist_append(_mediaLibrary, playlistID, ids, items.count);
            free(ids);
        }
    }
    [self scheduleRefetchOfCollections:[NSIndexSet indexSetWithIndex:MacLCLibraryCollectionPlaylists]];
    return playlist;
}

- (BOOL)deletePlaylist:(VLCMediaLibraryPlaylist *)playlist
{
    if (_closed) {
        return NO;
    }
    const BOOL deleted = vlc_ml_playlist_delete(_mediaLibrary, playlist.libraryID) == VLC_SUCCESS;
    if (deleted) {
        [_childrenCache removeObjectForKey:[MacLCLibraryItemIdentifier(playlist) stringByAppendingString:@"/items"]];
        [self scheduleRefetchOfCollections:[NSIndexSet indexSetWithIndex:MacLCLibraryCollectionPlaylists]];
    }
    return deleted;
}

@end
