/*****************************************************************************
 * MacLCAlbumDetailViewController.m: an album and its tracks
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

#import "extensions/NSString+Helpers.h"
#import "library/VLCLibraryDataTypes.h"
#import "medialib/MacLCLibraryFormatting.h"
#import "medialib/components/MacLCArtworkView.h"
#import "medialib/components/MacLCDetailHeaderView.h"
#import "medialib/components/MacLCTrackListController.h"
#import "medialib/data/MacLCLibraryActions.h"
#import "medialib/data/MacLCLibraryStore.h"

@interface MacLCAlbumDetailViewController ()
{
    VLCMediaLibraryAlbum *_album;
    MacLCTrackListController *_trackList;
    NSArray<VLCMediaLibraryMediaItem *> *_tracks;
    NSString *_genre;
}
@end

@implementation MacLCAlbumDetailViewController

- (instancetype)initWithAlbum:(VLCMediaLibraryAlbum *)album
{
    self = [super initWithArtworkShape:MacLCArtworkShapeSquare];
    if (self) {
        _album = album;
        _tracks = @[];
        self.title = album.title ?: album.displayString;
    }
    return self;
}

- (void)viewDidLoad
{
    _trackList = [[MacLCTrackListController alloc] initWithColumns:MacLCTrackListColumnNumber
                                                                   | MacLCTrackListColumnTitle
                                                                   | MacLCTrackListColumnDuration
                                                       autosaveName:@"MacLCAlbumTracks"];
    [self setBodyView:_trackList.scrollView];

    MacLCDetailHeaderView * const header = self.headerView;
    [header.artworkView setArtworkFromItem:_album];
    header.title = self.title;
    header.subtitle = _album.artistName.length > 0 ? _album.artistName : nil;
    __weak typeof(self) weakSelf = self;
    VLCMediaLibraryAlbum * const album = _album;
    if (album.artistID > 0) {
        header.subtitleAction = ^{
            [weakSelf showArtist];
        };
    }
    [header setPrimaryActionTitle:_NS("Play") symbolName:@"play.fill" action:^{
        [MacLCLibraryActions playItems:@[album] startingAt:0];
    }];
    [header setSecondaryActionTitle:_NS("Shuffle") symbolName:@"shuffle" action:^{
        [MacLCLibraryActions shuffleItems:@[album]];
    }];
    header.moreMenu = [MacLCLibraryActions contextMenuForItems:@[album] window:nil];

    /* The genre string is looked up in the database: once, off the main thread. */
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString * const genre = album.genreString;
        dispatch_async(dispatch_get_main_queue(), ^{
            MacLCAlbumDetailViewController * const strongSelf = weakSelf;
            if (strongSelf != nil) {
                strongSelf->_genre = genre;
                [strongSelf updateDetail];
            }
        });
    });

    [super viewDidLoad];
}

- (void)showArtist
{
    VLCMediaLibraryArtist * const artist = [VLCMediaLibraryArtist artistWithID:_album.artistID];
    MacLCLibrarySectionViewController * const section = (MacLCLibrarySectionViewController *)self.parentViewController;
    if (artist != nil && [section isKindOfClass:MacLCLibrarySectionViewController.class]) {
        [section pushViewController:[[MacLCArtistDetailViewController alloc] initWithArtist:artist]];
    }
}

- (void)reloadContents
{
    __weak typeof(self) weakSelf = self;
    [MacLCLibraryStore.sharedStore tracksOfAlbum:_album completion:^(NSArray<VLCMediaLibraryMediaItem *> * const tracks) {
        MacLCAlbumDetailViewController * const strongSelf = weakSelf;
        if (strongSelf == nil) {
            return;
        }
        strongSelf->_tracks = tracks;
        strongSelf->_trackList.items = tracks;
        [strongSelf updateDetail];
    }];
}

- (void)updateDetail
{
    int64_t duration = 0;
    for (VLCMediaLibraryMediaItem * const track in _tracks) {
        duration += MAX(track.duration, 0);
    }
    NSString * const songs = _tracks.count > 0
        ? [NSString stringWithFormat:@"%@, %@", MacLCCountString(_tracks.count, _NS("song"), _NS("songs")),
           MacLCDurationString(duration)]
        : @"";
    self.headerView.detail = MacLCJoinedDetails(@[
        _genre ?: @"",
        _album.year > 0 ? [NSString stringWithFormat:@"%u", _album.year] : @"",
        songs,
    ]);
}

- (void)applySearchString:(NSString *)searchString
{
    [_trackList applySearchString:searchString];
}

@end
