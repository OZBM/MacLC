/*****************************************************************************
 * MacLCLibraryActions.m: what people can do with library items
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

#import "medialib/data/MacLCLibraryActions.h"

#import <objc/runtime.h>

#import <vlc_common.h>
#import <vlc_media_library.h>
#import <vlc_playlist.h>

#import "extensions/NSString+Helpers.h"
#import "library/VLCLibraryController.h"
#import "library/VLCLibraryDataTypes.h"
#import "library/VLCLibraryRepresentedItem.h"
#import "main/VLCMain.h"
#import "medialib/data/MacLCLibraryStore.h"
#import "panels/VLCInformationWindowController.h"
#import "playqueue/VLCPlayQueueController.h"

/* The target of the contextual menu items: holds the selection they act on. */
@interface MacLCLibraryActionsMenuTarget : NSObject
@property (copy) NSArray<id<VLCMediaLibraryItemProtocol>> *items;
@property (weak, nullable) NSWindow *window;
@end

@implementation MacLCLibraryActionsMenuTarget

- (void)play:(id)sender { [MacLCLibraryActions playItems:self.items startingAt:0]; }
- (void)playNext:(id)sender { [MacLCLibraryActions playNext:self.items]; }
- (void)addToUpNext:(id)sender { [MacLCLibraryActions addToUpNext:self.items]; }
- (void)favorite:(id)sender { [MacLCLibraryActions setFavorite:YES forItems:self.items]; }
- (void)unfavorite:(id)sender { [MacLCLibraryActions setFavorite:NO forItems:self.items]; }
- (void)markWatched:(id)sender { [MacLCLibraryActions setWatched:YES forItems:self.items]; }
- (void)markUnwatched:(id)sender { [MacLCLibraryActions setWatched:NO forItems:self.items]; }
- (void)showInFinder:(id)sender { [MacLCLibraryActions showInFinder:self.items]; }
- (void)getInfo:(id)sender { [MacLCLibraryActions showInfoForItem:self.items.firstObject]; }
- (void)newPlaylist:(id)sender { [MacLCLibraryActions newPlaylistWithItems:self.items fromWindow:self.window]; }

- (void)addToPlaylist:(NSMenuItem *)sender
{
    VLCMediaLibraryPlaylist * const playlist = sender.representedObject;
    if (playlist != nil) {
        [MacLCLibraryActions addItems:self.items toPlaylist:playlist];
    }
}

- (void)renamePlaylist:(id)sender
{
    VLCMediaLibraryPlaylist * const playlist = (VLCMediaLibraryPlaylist *)self.items.firstObject;
    [MacLCLibraryActions renamePlaylist:playlist fromWindow:self.window];
}

- (void)deletePlaylist:(id)sender
{
    VLCMediaLibraryPlaylist * const playlist = (VLCMediaLibraryPlaylist *)self.items.firstObject;
    [MacLCLibraryActions deletePlaylist:playlist fromWindow:self.window];
}

@end

@implementation MacLCLibraryActions

// MARK: - Expansion (background queue)

+ (dispatch_queue_t)actionQueue
{
    static dispatch_queue_t queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        dispatch_queue_attr_t const attributes =
            dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_USER_INITIATED, 0);
        queue = dispatch_queue_create("org.maclc.library-actions", attributes);
    });
    return queue;
}

+ (NSComparisonResult)compareTrack:(VLCMediaLibraryMediaItem *)a with:(VLCMediaLibraryMediaItem *)b
{
    if (a.albumID != b.albumID) {
        return a.albumID < b.albumID ? NSOrderedAscending : NSOrderedDescending;
    }
    if (a.discNumber != b.discNumber) {
        return a.discNumber < b.discNumber ? NSOrderedAscending : NSOrderedDescending;
    }
    if (a.trackNumber != b.trackNumber) {
        return a.trackNumber < b.trackNumber ? NSOrderedAscending : NSOrderedDescending;
    }
    return [a.title ?: @"" localizedStandardCompare:b.title ?: @""];
}

/* The media of each item, containers expanded in their natural order. */
+ (NSArray<VLCMediaLibraryMediaItem *> *)mediaOfItems:(NSArray<id<VLCMediaLibraryItemProtocol>> *)items
{
    NSMutableArray<VLCMediaLibraryMediaItem *> * const media = [NSMutableArray array];
    for (id<VLCMediaLibraryItemProtocol> const item in items) {
        if ([item isKindOfClass:VLCMediaLibraryMediaItem.class]) {
            [media addObject:(VLCMediaLibraryMediaItem *)item];
        } else if ([item isKindOfClass:VLCMediaLibraryShow.class]) {
            NSArray<VLCMediaLibraryMediaItem *> * const episodes =
                [((VLCMediaLibraryShow *)item).episodes sortedArrayUsingComparator:
                    ^NSComparisonResult(VLCMediaLibraryMediaItem * const a, VLCMediaLibraryMediaItem * const b) {
                        const uint32_t sa = a.showEpisode.seasonNumber, sb = b.showEpisode.seasonNumber;
                        if (sa != sb) {
                            return sa < sb ? NSOrderedAscending : NSOrderedDescending;
                        }
                        const uint32_t ea = a.showEpisode.episodeNumber, eb = b.showEpisode.episodeNumber;
                        return ea == eb ? NSOrderedSame : (ea < eb ? NSOrderedAscending : NSOrderedDescending);
                    }];
            [media addObjectsFromArray:episodes ?: @[]];
        } else if ([item isKindOfClass:VLCMediaLibraryPlaylist.class]) {
            [media addObjectsFromArray:item.mediaItems ?: @[]];
        } else {
            /* Albums, artists, genres, groups: album then track order. */
            NSArray<VLCMediaLibraryMediaItem *> * const tracks = item.mediaItems ?: @[];
            [media addObjectsFromArray:[tracks sortedArrayUsingComparator:
                ^NSComparisonResult(VLCMediaLibraryMediaItem * const a, VLCMediaLibraryMediaItem * const b) {
                    return [MacLCLibraryActions compareTrack:a with:b];
                }]];
        }
    }
    return media;
}

// MARK: - Play queue

+ (nullable vlc_medialibrary_t *)mediaLibrary
{
    if (!VLCMain.sharedInstance.libraryController.shouldUseMediaLibrary) {
        return NULL;
    }
    return vlc_ml_instance_get(getIntf());
}

/* New references the caller releases with releaseInputItems. */
+ (NSMutableData *)inputItemsForMedia:(NSArray<VLCMediaLibraryMediaItem *> *)media
                         mediaLibrary:(vlc_medialibrary_t *)ml
{
    NSMutableData * const buffer = [NSMutableData dataWithCapacity:media.count * sizeof(input_item_t *)];
    for (VLCMediaLibraryMediaItem * const item in media) {
        input_item_t * const inputItem = vlc_ml_get_input_item(ml, item.libraryID);
        if (inputItem != NULL) {
            [buffer appendBytes:&inputItem length:sizeof(input_item_t *)];
        }
    }
    return buffer;
}

+ (void)releaseInputItems:(NSData *)buffer
{
    input_item_t * const *items = buffer.bytes;
    const size_t count = buffer.length / sizeof(input_item_t *);
    for (size_t i = 0; i < count; i++) {
        input_item_Release(items[i]);
    }
}

+ (void)playItems:(NSArray<id<VLCMediaLibraryItemProtocol>> *)items startingAt:(NSUInteger)startIndex
{
    [self playItems:items startingAt:startIndex shuffled:NO];
}

+ (void)shuffleItems:(NSArray<id<VLCMediaLibraryItemProtocol>> *)items
{
    [self playItems:items startingAt:0 shuffled:YES];
}

+ (void)playItems:(NSArray<id<VLCMediaLibraryItemProtocol>> *)items
       startingAt:(NSUInteger)startIndex
         shuffled:(BOOL)shuffled
{
    vlc_medialibrary_t * const ml = [self mediaLibrary];
    vlc_playlist_t * const playlist = VLCMain.sharedInstance.playQueueController.p_playlist;
    if (ml == NULL || playlist == NULL || items.count == 0) {
        return;
    }
    NSArray * const selection = [items copy];
    dispatch_async([self actionQueue], ^{
        NSMutableArray<VLCMediaLibraryMediaItem *> *media = [[MacLCLibraryActions mediaOfItems:selection] mutableCopy];
        if (media.count == 0) {
            return;
        }
        /* startIndex counts selection items; containers expand, so map it to
         * the first media of that item. */
        NSUInteger start = 0;
        if (!shuffled && startIndex > 0 && startIndex < selection.count) {
            NSArray * const before = [MacLCLibraryActions mediaOfItems:
                [selection subarrayWithRange:NSMakeRange(0, startIndex)]];
            start = MIN(before.count, media.count - 1);
        }
        if (shuffled) {
            for (NSUInteger i = media.count - 1; i > 0; i--) {
                [media exchangeObjectAtIndex:i withObjectAtIndex:arc4random_uniform((uint32_t)(i + 1))];
            }
        }

        /* Start the chosen media at once, then fill the queue around it:
         * playback does not wait for a thousand-song album to load. */
        NSData * const first = [MacLCLibraryActions inputItemsForMedia:@[media[start]] mediaLibrary:ml];
        if (first.length == 0) {
            return;
        }
        vlc_playlist_Lock(playlist);
        vlc_playlist_Clear(playlist);
        vlc_playlist_SetPlaybackOrder(playlist, VLC_PLAYLIST_PLAYBACK_ORDER_NORMAL);
        vlc_playlist_Insert(playlist, 0, (input_item_t * const *)first.bytes, 1);
        vlc_playlist_PlayAt(playlist, 0);
        vlc_playlist_Unlock(playlist);
        [MacLCLibraryActions releaseInputItems:first];

        NSData * const before = [MacLCLibraryActions inputItemsForMedia:
            [media subarrayWithRange:NSMakeRange(0, start)] mediaLibrary:ml];
        NSData * const after = [MacLCLibraryActions inputItemsForMedia:
            [media subarrayWithRange:NSMakeRange(start + 1, media.count - start - 1)] mediaLibrary:ml];
        vlc_playlist_Lock(playlist);
        if (after.length > 0) {
            vlc_playlist_Insert(playlist, vlc_playlist_Count(playlist),
                                (input_item_t * const *)after.bytes, after.length / sizeof(input_item_t *));
        }
        if (before.length > 0) {
            vlc_playlist_Insert(playlist, 0,
                                (input_item_t * const *)before.bytes, before.length / sizeof(input_item_t *));
        }
        vlc_playlist_Unlock(playlist);
        [MacLCLibraryActions releaseInputItems:before];
        [MacLCLibraryActions releaseInputItems:after];
    });
}

+ (void)insertItems:(NSArray<id<VLCMediaLibraryItemProtocol>> *)items afterCurrent:(BOOL)afterCurrent
{
    vlc_medialibrary_t * const ml = [self mediaLibrary];
    vlc_playlist_t * const playlist = VLCMain.sharedInstance.playQueueController.p_playlist;
    if (ml == NULL || playlist == NULL || items.count == 0) {
        return;
    }
    NSArray * const selection = [items copy];
    dispatch_async([self actionQueue], ^{
        NSData * const inputItems = [MacLCLibraryActions inputItemsForMedia:[MacLCLibraryActions mediaOfItems:selection]
                                                              mediaLibrary:ml];
        const size_t count = inputItems.length / sizeof(input_item_t *);
        if (count == 0) {
            return;
        }
        vlc_playlist_Lock(playlist);
        size_t index = vlc_playlist_Count(playlist);
        if (afterCurrent) {
            const ssize_t current = vlc_playlist_GetCurrentIndex(playlist);
            index = current >= 0 ? (size_t)current + 1 : 0;
        }
        vlc_playlist_Insert(playlist, index, (input_item_t * const *)inputItems.bytes, count);
        vlc_playlist_Unlock(playlist);
        [MacLCLibraryActions releaseInputItems:inputItems];
    });
}

+ (void)playNext:(NSArray<id<VLCMediaLibraryItemProtocol>> *)items
{
    [self insertItems:items afterCurrent:YES];
}

+ (void)addToUpNext:(NSArray<id<VLCMediaLibraryItemProtocol>> *)items
{
    [self insertItems:items afterCurrent:NO];
}

// MARK: - Library changes

+ (void)setFavorite:(BOOL)favorite forItems:(NSArray<id<VLCMediaLibraryItemProtocol>> *)items
{
    NSArray * const selection = [items copy];
    dispatch_async([self actionQueue], ^{
        for (id<VLCMediaLibraryItemProtocol> const item in selection) {
            [item setFavorite:favorite];
        }
    });
}

+ (void)setWatched:(BOOL)watched forItems:(NSArray<id<VLCMediaLibraryItemProtocol>> *)items
{
    vlc_medialibrary_t * const ml = [self mediaLibrary];
    if (ml == NULL) {
        return;
    }
    NSArray * const selection = [items copy];
    dispatch_async([self actionQueue], ^{
        for (VLCMediaLibraryMediaItem * const media in [MacLCLibraryActions mediaOfItems:selection]) {
            if (media.mediaType == VLC_ML_MEDIA_TYPE_VIDEO) {
                vlc_ml_media_set_played(ml, media.libraryID, watched);
            }
        }
    });
}

+ (void)addItems:(NSArray<id<VLCMediaLibraryItemProtocol>> *)items toPlaylist:(VLCMediaLibraryPlaylist *)playlist
{
    vlc_medialibrary_t * const ml = [self mediaLibrary];
    if (ml == NULL) {
        return;
    }
    NSArray * const selection = [items copy];
    const int64_t playlistID = playlist.libraryID;
    dispatch_async([self actionQueue], ^{
        NSArray<VLCMediaLibraryMediaItem *> * const media = [MacLCLibraryActions mediaOfItems:selection];
        if (media.count == 0) {
            return;
        }
        int64_t * const ids = calloc(media.count, sizeof(int64_t));
        if (ids == NULL) {
            return;
        }
        for (NSUInteger i = 0; i < media.count; i++) {
            ids[i] = media[i].libraryID;
        }
        vlc_ml_playlist_append(ml, playlistID, ids, media.count);
        free(ids);
    });
}

+ (nullable NSString *)askForNameWithMessage:(NSString *)message
                                 buttonTitle:(NSString *)buttonTitle
                                 initialName:(NSString *)initialName
                                      window:(nullable NSWindow *)window
                                  completion:(void (^)(NSString *name))completion
{
    NSAlert * const alert = [[NSAlert alloc] init];
    alert.messageText = message;
    [alert addButtonWithTitle:buttonTitle];
    [alert addButtonWithTitle:_NS("Cancel")];
    NSTextField * const field = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 260, 24)];
    field.stringValue = initialName;
    field.placeholderString = _NS("Playlist Name");
    alert.accessoryView = field;
    alert.window.initialFirstResponder = field;

    void (^handler)(NSModalResponse) = ^(NSModalResponse response) {
        NSString * const name = [field.stringValue stringByTrimmingCharactersInSet:
                                 NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (response == NSAlertFirstButtonReturn && name.length > 0) {
            completion(name);
        }
    };
    if (window != nil) {
        [alert beginSheetModalForWindow:window completionHandler:handler];
    } else {
        handler([alert runModal]);
    }
    return nil;
}

+ (void)newPlaylistWithItems:(NSArray<id<VLCMediaLibraryItemProtocol>> *)items fromWindow:(nullable NSWindow *)window
{
    NSArray * const selection = [items copy];
    [self askForNameWithMessage:_NS("New Playlist")
                    buttonTitle:_NS("Create")
                    initialName:_NS("Untitled Playlist")
                         window:window
                     completion:^(NSString * const name) {
        MacLCLibraryStore * const store = MacLCLibraryStore.sharedStore;
        VLCMediaLibraryPlaylist * const playlist = [store createPlaylistNamed:name withItems:@[]];
        if (playlist != nil && selection.count > 0) {
            [MacLCLibraryActions addItems:selection toPlaylist:playlist];
        }
    }];
}

+ (void)renamePlaylist:(VLCMediaLibraryPlaylist *)playlist fromWindow:(nullable NSWindow *)window
{
    [self askForNameWithMessage:_NS("Rename Playlist")
                    buttonTitle:_NS("Rename")
                    initialName:playlist.displayString ?: @""
                         window:window
                     completion:^(NSString * const name) {
        dispatch_async([MacLCLibraryActions actionQueue], ^{
            [playlist renameTo:name];
        });
    }];
}

+ (void)deletePlaylist:(VLCMediaLibraryPlaylist *)playlist fromWindow:(nullable NSWindow *)window
{
    NSAlert * const alert = [[NSAlert alloc] init];
    alert.alertStyle = NSAlertStyleWarning;
    alert.messageText = [NSString stringWithFormat:_NS("Delete “%@”?"), playlist.displayString ?: @""];
    alert.informativeText = _NS("The songs and videos stay in your library.");
    NSButton * const deleteButton = [alert addButtonWithTitle:_NS("Delete")];
    deleteButton.hasDestructiveAction = YES;
    NSButton * const cancelButton = [alert addButtonWithTitle:_NS("Cancel")];
    /* Cancel is the default and Escape answers it; Delete needs a click. */
    deleteButton.keyEquivalent = @"";
    cancelButton.keyEquivalent = @"\r";

    void (^handler)(NSModalResponse) = ^(NSModalResponse response) {
        if (response == NSAlertFirstButtonReturn) {
            [MacLCLibraryStore.sharedStore deletePlaylist:playlist];
        }
    };
    if (window != nil) {
        [alert beginSheetModalForWindow:window completionHandler:handler];
    } else {
        handler([alert runModal]);
    }
}

+ (void)removeItemsAtIndexes:(NSIndexSet *)indexes fromPlaylist:(VLCMediaLibraryPlaylist *)playlist
{
    NSMutableArray<NSNumber *> * const positions = [NSMutableArray arrayWithCapacity:indexes.count];
    [indexes enumerateIndexesUsingBlock:^(NSUInteger index, BOOL * const stop) {
        [positions addObject:@(index)];
    }];
    dispatch_async([self actionQueue], ^{
        [playlist removeMediaItemsAtPositions:positions];
    });
}

// MARK: - Finder and information

+ (void)showInFinder:(NSArray<id<VLCMediaLibraryItemProtocol>> *)items
{
    NSMutableArray<NSURL *> * const urls = [NSMutableArray array];
    for (id<VLCMediaLibraryItemProtocol> const item in items) {
        VLCMediaLibraryMediaItem * const media = [item isKindOfClass:VLCMediaLibraryMediaItem.class]
            ? (VLCMediaLibraryMediaItem *)item : item.firstMediaItem;
        NSURL * const url = media.files.firstObject.fileURL;
        if (url.isFileURL) {
            [urls addObject:url];
        }
    }
    if (urls.count > 0) {
        [NSWorkspace.sharedWorkspace activateFileViewerSelectingURLs:urls];
    }
}

+ (void)showInfoForItem:(id<VLCMediaLibraryItemProtocol>)item
{
    if (item == nil) {
        return;
    }
    static VLCInformationWindowController *informationWindowController;
    if (informationWindowController == nil) {
        informationWindowController = [[VLCInformationWindowController alloc] init];
    }
    VLCLibraryRepresentedItem * const represented =
        [[VLCLibraryRepresentedItem alloc] initWithItem:item parentType:VLCMediaLibraryParentGroupTypeUnknown];
    [informationWindowController setRepresentedMediaLibraryItems:@[represented]];
    [informationWindowController showWindow:nil];
}

// MARK: - Menu

+ (NSMenuItem *)addItemTo:(NSMenu *)menu title:(NSString *)title action:(SEL)action target:(id)target
{
    NSMenuItem * const item = [menu addItemWithTitle:title action:action keyEquivalent:@""];
    item.target = target;
    return item;
}

+ (NSMenu *)contextMenuForItems:(NSArray<id<VLCMediaLibraryItemProtocol>> *)items window:(nullable NSWindow *)window
{
    NSMenu * const menu = [[NSMenu alloc] initWithTitle:@""];
    if (items.count == 0) {
        return menu;
    }
    MacLCLibraryActionsMenuTarget * const target = [[MacLCLibraryActionsMenuTarget alloc] init];
    target.items = items;
    target.window = window;
    /* NSMenuItem.target is weak: keep the target alive with the menu. */
    menu.identifier = @"MacLCLibraryContextMenu";
    objc_setAssociatedObject(menu, @selector(contextMenuForItems:window:), target, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    BOOL allPlaylists = YES, anyVideo = NO, anyFavorite = NO, allFavorite = YES, anyFileBacked = NO;
    for (id<VLCMediaLibraryItemProtocol> const item in items) {
        allPlaylists = allPlaylists && [item isKindOfClass:VLCMediaLibraryPlaylist.class];
        if ([item isKindOfClass:VLCMediaLibraryMediaItem.class]) {
            VLCMediaLibraryMediaItem * const media = (VLCMediaLibraryMediaItem *)item;
            anyVideo = anyVideo || media.mediaType == VLC_ML_MEDIA_TYPE_VIDEO;
            anyFileBacked = anyFileBacked || media.files.firstObject.fileURL.isFileURL;
        } else if ([item isKindOfClass:VLCMediaLibraryShow.class]) {
            anyVideo = YES;
            anyFileBacked = YES;
        } else if (![item isKindOfClass:VLCMediaLibraryPlaylist.class]) {
            anyFileBacked = YES;
        }
        anyFavorite = anyFavorite || item.favorited;
        allFavorite = allFavorite && item.favorited;
    }

    [self addItemTo:menu title:_NS("Play") action:@selector(play:) target:target];
    [self addItemTo:menu title:_NS("Play Next") action:@selector(playNext:) target:target];
    [self addItemTo:menu title:_NS("Add to Up Next") action:@selector(addToUpNext:) target:target];
    [menu addItem:NSMenuItem.separatorItem];

    NSMenuItem * const playlistsItem = [menu addItemWithTitle:_NS("Add to Playlist") action:nil keyEquivalent:@""];
    NSMenu * const playlistsMenu = [[NSMenu alloc] initWithTitle:_NS("Add to Playlist")];
    [self addItemTo:playlistsMenu title:_NS("New Playlist…") action:@selector(newPlaylist:) target:target];
    NSArray<VLCMediaLibraryPlaylist *> * const playlists =
        [MacLCLibraryStore.sharedStore itemsInCollection:MacLCLibraryCollectionPlaylists];
    if (playlists.count > 0) {
        [playlistsMenu addItem:NSMenuItem.separatorItem];
        for (VLCMediaLibraryPlaylist * const playlist in playlists) {
            if (allPlaylists && [items containsObject:playlist]) {
                continue;
            }
            NSMenuItem * const item = [self addItemTo:playlistsMenu
                                                title:playlist.displayString ?: @""
                                               action:@selector(addToPlaylist:)
                                               target:target];
            item.representedObject = playlist;
        }
    }
    playlistsItem.submenu = playlistsMenu;

    if (allFavorite) {
        [self addItemTo:menu title:_NS("Remove from Favorites") action:@selector(unfavorite:) target:target];
    } else {
        [self addItemTo:menu title:_NS("Favorite") action:@selector(favorite:) target:target];
    }
    (void)anyFavorite;

    if (anyVideo) {
        [menu addItem:NSMenuItem.separatorItem];
        [self addItemTo:menu title:_NS("Mark as Watched") action:@selector(markWatched:) target:target];
        [self addItemTo:menu title:_NS("Mark as Unwatched") action:@selector(markUnwatched:) target:target];
    }

    [menu addItem:NSMenuItem.separatorItem];
    if (anyFileBacked) {
        [self addItemTo:menu title:_NS("Show in Finder") action:@selector(showInFinder:) target:target];
    }
    [self addItemTo:menu title:_NS("Get Info") action:@selector(getInfo:) target:target];

    if (allPlaylists && items.count == 1) {
        [menu addItem:NSMenuItem.separatorItem];
        [self addItemTo:menu title:_NS("Rename…") action:@selector(renamePlaylist:) target:target];
        [self addItemTo:menu title:_NS("Delete Playlist…") action:@selector(deletePlaylist:) target:target];
    }
    return menu;
}

// MARK: - Drag and drop

+ (nullable id<NSPasteboardWriting>)pasteboardWriterForItem:(id<VLCMediaLibraryItemProtocol>)item
{
    NSPasteboardItem * const pasteboardItem = [[NSPasteboardItem alloc] init];
    VLCMediaLibraryMediaItem * const media = [item isKindOfClass:VLCMediaLibraryMediaItem.class]
        ? (VLCMediaLibraryMediaItem *)item : item.firstMediaItem;
    NSURL * const fileURL = media.files.firstObject.fileURL;
    if (fileURL.isFileURL) {
        [pasteboardItem setString:fileURL.absoluteString forType:NSPasteboardTypeFileURL];
    }
    NSArray<VLCMediaLibraryMediaItem *> * const mediaItems =
        media == item ? @[media] : (item.mediaItems ?: @[]);
    NSData * const data = [NSKeyedArchiver archivedDataWithRootObject:mediaItems
                                                requiringSecureCoding:YES
                                                                error:nil];
    if (data != nil) {
        [pasteboardItem setData:data forType:VLCMediaLibraryMediaItemPasteboardType];
    }
    return pasteboardItem.types.count > 0 ? pasteboardItem : nil;
}

@end
