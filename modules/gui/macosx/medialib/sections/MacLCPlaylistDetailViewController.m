/*****************************************************************************
 * MacLCPlaylistDetailViewController.m: a playlist, in the owner's order
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

#import "medialib/sections/MacLCLibrarySections.h"

#import <vlc_common.h>
#import <vlc_media_library.h>

#import "extensions/NSString+Helpers.h"
#import "library/VLCLibraryController.h"
#import "library/VLCLibraryDataTypes.h"
#import "main/VLCMain.h"
#import "medialib/MacLCLibraryFormatting.h"
#import "medialib/components/MacLCArtworkView.h"
#import "medialib/components/MacLCDetailHeaderView.h"
#import "medialib/components/MacLCEmptyStateView.h"
#import "medialib/components/MacLCTrackListController.h"
#import "medialib/data/MacLCLibraryActions.h"
#import "medialib/data/MacLCLibraryStore.h"

@interface MacLCPlaylistDetailViewController ()
{
    VLCMediaLibraryPlaylist *_playlist;
    MacLCTrackListController *_itemList;
    MacLCEmptyStateView *_emptyState;
}
@end

@implementation MacLCPlaylistDetailViewController

- (instancetype)initWithPlaylist:(VLCMediaLibraryPlaylist *)playlist
{
    self = [super initWithArtworkShape:MacLCArtworkShapeSquare];
    if (self) {
        _playlist = playlist;
        self.title = playlist.displayString ?: @"";
    }
    return self;
}

- (void)viewDidLoad
{
    _itemList = [[MacLCTrackListController alloc] initWithColumns:MacLCTrackListColumnNumber
                                                                  | MacLCTrackListColumnTitle
                                                                  | MacLCTrackListColumnArtist
                                                                  | MacLCTrackListColumnAlbum
                                                                  | MacLCTrackListColumnDuration
                                                      autosaveName:@"MacLCPlaylistItems"];
    __weak typeof(self) weakSelf = self;
    VLCMediaLibraryPlaylist * const playlist = _playlist;
    _itemList.deleteHandler = ^(NSIndexSet * const rows) {
        [MacLCLibraryActions removeItemsAtIndexes:rows fromPlaylist:playlist];
    };
    _itemList.reorderHandler = ^(NSIndexSet * const rows, NSUInteger destination) {
        [weakSelf moveRows:rows toRow:destination];
    };
    [self setBodyView:_itemList.scrollView];

    MacLCDetailHeaderView * const header = self.headerView;
    [header.artworkView setArtworkFromItem:playlist];
    header.title = self.title;
    [header setPrimaryActionTitle:_NS("Play") symbolName:@"play.fill" action:^{
        [MacLCLibraryActions playItems:@[playlist] startingAt:0];
    }];
    [header setSecondaryActionTitle:_NS("Shuffle") symbolName:@"shuffle" action:^{
        [MacLCLibraryActions shuffleItems:@[playlist]];
    }];
    [super viewDidLoad];
}

- (void)viewDidAppear
{
    [super viewDidAppear];
    /* Rename and delete need the window for their sheets. */
    self.headerView.moreMenu = [MacLCLibraryActions contextMenuForItems:@[_playlist] window:self.view.window];
}

/* The media library moves one block at a time: move each row, top to
 * bottom, keeping track of where the earlier moves put the next ones. */
- (void)moveRows:(NSIndexSet *)rows toRow:(NSUInteger)destination
{
    if (!VLCMain.sharedInstance.libraryController.shouldUseMediaLibrary) {
        return;
    }
    vlc_medialibrary_t * const ml = vlc_ml_instance_get(getIntf());
    const int64_t playlistID = _playlist.libraryID;
    NSMutableArray<NSNumber *> * const sources = [NSMutableArray array];
    [rows enumerateIndexesUsingBlock:^(NSUInteger index, BOOL * const stop) {
        [sources addObject:@(index)];
    }];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSUInteger target = destination;
        NSUInteger movedAbove = 0;
        for (NSNumber * const source in sources) {
            NSUInteger from = source.unsignedIntegerValue;
            if (from < destination) {
                from -= movedAbove;
                vlc_ml_playlist_move(ml, playlistID, (uint32_t)from, (uint32_t)(target - 1), 1);
                movedAbove += 1;
            } else {
                vlc_ml_playlist_move(ml, playlistID, (uint32_t)from, (uint32_t)target, 1);
                target += 1;
            }
        }
    });
}

- (void)reloadContents
{
    __weak typeof(self) weakSelf = self;
    [MacLCLibraryStore.sharedStore itemsOfPlaylist:_playlist completion:^(NSArray<VLCMediaLibraryMediaItem *> * const items) {
        [weakSelf showItems:items];
    }];
}

- (void)showItems:(NSArray<VLCMediaLibraryMediaItem *> *)items
{
    _itemList.items = items;
    int64_t duration = 0;
    for (VLCMediaLibraryMediaItem * const item in items) {
        duration += MAX(item.duration, 0);
    }
    self.headerView.detail = MacLCJoinedDetails(@[
        MacLCCountString(items.count, _NS("item"), _NS("items")),
        MacLCDurationString(duration),
    ]);

    [_emptyState removeFromSuperview];
    _emptyState = nil;
    if (items.count == 0) {
        _emptyState = [MacLCEmptyStateView emptyStateWithSymbolName:@"music.note.list"
                                                              title:_NS("This Playlist Is Empty")
                                                            message:_NS("Add songs and videos with Add to Playlist in their menu.")];
        _emptyState.translatesAutoresizingMaskIntoConstraints = NO;
        [_itemList.scrollView addSubview:_emptyState];
        [NSLayoutConstraint activateConstraints:@[
            [_emptyState.centerXAnchor constraintEqualToAnchor:_itemList.scrollView.centerXAnchor],
            [_emptyState.centerYAnchor constraintEqualToAnchor:_itemList.scrollView.centerYAnchor],
        ]];
    }
}

- (void)applySearchString:(NSString *)searchString
{
    [_itemList applySearchString:searchString];
}

@end
