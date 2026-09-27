/*****************************************************************************
 * MacLCArtistDetailViewController.m: an artist's albums and songs
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
#import "medialib/sections/MacLCLibraryGridViewController.h"

@interface MacLCArtistDetailViewController ()
{
    VLCMediaLibraryArtist *_artist;
    MacLCLibraryGridViewController *_albumGrid;
    MacLCTrackListController *_songList;
    NSSegmentedControl *_switch;
    NSUInteger _albumCount;
    NSUInteger _songCount;
}
@end

@implementation MacLCArtistDetailViewController

- (instancetype)initWithArtist:(VLCMediaLibraryArtist *)artist
{
    self = [super initWithArtworkShape:MacLCArtworkShapeCircle];
    if (self) {
        _artist = artist;
        self.title = artist.name.length > 0 ? artist.name : artist.displayString;
    }
    return self;
}

- (void)viewDidLoad
{
    _albumGrid = [[MacLCLibraryGridViewController alloc] initWithShape:MacLCArtworkShapeSquare
                                                          subtitleStyle:MacLCCardSubtitleStyleDefault];
    __weak typeof(self) weakSelf = self;
    _albumGrid.openHandler = ^(id<VLCMediaLibraryItemProtocol> const item) {
        [weakSelf openAlbum:(VLCMediaLibraryAlbum *)item];
    };
    [self addChildViewController:_albumGrid];

    _songList = [[MacLCTrackListController alloc] initWithColumns:MacLCTrackListColumnTitle
                                                                  | MacLCTrackListColumnAlbum
                                                                  | MacLCTrackListColumnDuration
                                                      autosaveName:@"MacLCArtistSongs"];
    _songList.sortable = YES;

    _switch = [NSSegmentedControl segmentedControlWithLabels:@[_NS("Albums"), _NS("Songs")]
                                                trackingMode:NSSegmentSwitchTrackingSelectOne
                                                      target:self
                                                      action:@selector(switchChanged:)];
    _switch.selectedSegment = 0;
    _switch.accessibilityLabel = _NS("Show");
    self.choiceView = _switch;
    [self setBodyView:_albumGrid.view];

    MacLCDetailHeaderView * const header = self.headerView;
    [header.artworkView setArtworkFromItem:_artist];
    header.title = self.title;
    VLCMediaLibraryArtist * const artist = _artist;
    [header setPrimaryActionTitle:_NS("Play") symbolName:@"play.fill" action:^{
        [MacLCLibraryActions playItems:@[artist] startingAt:0];
    }];
    [header setSecondaryActionTitle:_NS("Shuffle") symbolName:@"shuffle" action:^{
        [MacLCLibraryActions shuffleItems:@[artist]];
    }];
    header.moreMenu = [MacLCLibraryActions contextMenuForItems:@[artist] window:nil];
    [super viewDidLoad];
}

- (void)switchChanged:(NSSegmentedControl *)sender
{
    [self setBodyView:sender.selectedSegment == 0 ? _albumGrid.view : _songList.scrollView];
}

- (void)openAlbum:(VLCMediaLibraryAlbum *)album
{
    MacLCLibrarySectionViewController * const section = (MacLCLibrarySectionViewController *)self.parentViewController;
    if ([section isKindOfClass:MacLCLibrarySectionViewController.class]) {
        [section pushViewController:[[MacLCAlbumDetailViewController alloc] initWithAlbum:album]];
    }
}

- (void)reloadContents
{
    __weak typeof(self) weakSelf = self;
    MacLCLibraryStore * const store = MacLCLibraryStore.sharedStore;
    [store albumsOfArtist:_artist completion:^(NSArray<VLCMediaLibraryAlbum *> * const albums) {
        MacLCArtistDetailViewController * const strongSelf = weakSelf;
        if (strongSelf != nil) {
            strongSelf->_albumCount = albums.count;
            strongSelf->_albumGrid.items = albums;
            [strongSelf updateDetail];
        }
    }];
    [store tracksOfArtist:_artist completion:^(NSArray<VLCMediaLibraryMediaItem *> * const tracks) {
        MacLCArtistDetailViewController * const strongSelf = weakSelf;
        if (strongSelf != nil) {
            strongSelf->_songCount = tracks.count;
            strongSelf->_songList.items = tracks;
            [strongSelf updateDetail];
        }
    }];
}

- (void)updateDetail
{
    self.headerView.detail = MacLCJoinedDetails(@[
        _albumCount > 0 ? MacLCCountString(_albumCount, _NS("album"), _NS("albums")) : @"",
        _songCount > 0 ? MacLCCountString(_songCount, _NS("song"), _NS("songs")) : @"",
    ]);
}

- (void)applySearchString:(NSString *)searchString
{
    [_albumGrid applySearchString:searchString];
    [_songList applySearchString:searchString];
}

@end
