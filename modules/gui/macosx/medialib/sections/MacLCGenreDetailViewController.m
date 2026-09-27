/*****************************************************************************
 * MacLCGenreDetailViewController.m: the albums of a genre
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
#import "medialib/data/MacLCLibraryActions.h"
#import "medialib/data/MacLCLibraryStore.h"
#import "medialib/sections/MacLCLibraryGridViewController.h"

@interface MacLCGenreDetailViewController ()
{
    VLCMediaLibraryGenre *_genre;
    MacLCLibraryGridViewController *_albumGrid;
}
@end

@implementation MacLCGenreDetailViewController

- (instancetype)initWithGenre:(VLCMediaLibraryGenre *)genre
{
    self = [super initWithArtworkShape:MacLCArtworkShapeSquare];
    if (self) {
        _genre = genre;
        self.title = genre.name.length > 0 ? genre.name : genre.displayString;
    }
    return self;
}

- (void)viewDidLoad
{
    _albumGrid = [[MacLCLibraryGridViewController alloc] initWithShape:MacLCArtworkShapeSquare
                                                          subtitleStyle:MacLCCardSubtitleStyleDefault];
    __weak typeof(self) weakSelf = self;
    _albumGrid.openHandler = ^(id<VLCMediaLibraryItemProtocol> const item) {
        MacLCGenreDetailViewController * const strongSelf = weakSelf;
        MacLCLibrarySectionViewController * const section =
            (MacLCLibrarySectionViewController *)strongSelf.parentViewController;
        if ([section isKindOfClass:MacLCLibrarySectionViewController.class]) {
            [section pushViewController:[[MacLCAlbumDetailViewController alloc] initWithAlbum:(VLCMediaLibraryAlbum *)item]];
        }
    };
    [self addChildViewController:_albumGrid];
    [self setBodyView:_albumGrid.view];

    MacLCDetailHeaderView * const header = self.headerView;
    [header.artworkView setArtworkFromItem:_genre];
    header.title = self.title;
    VLCMediaLibraryGenre * const genre = _genre;
    [header setPrimaryActionTitle:_NS("Play") symbolName:@"play.fill" action:^{
        [MacLCLibraryActions playItems:@[genre] startingAt:0];
    }];
    [header setSecondaryActionTitle:_NS("Shuffle") symbolName:@"shuffle" action:^{
        [MacLCLibraryActions shuffleItems:@[genre]];
    }];
    [super viewDidLoad];
}

- (void)reloadContents
{
    __weak typeof(self) weakSelf = self;
    [MacLCLibraryStore.sharedStore albumsOfGenre:_genre completion:^(NSArray<VLCMediaLibraryAlbum *> * const albums) {
        MacLCGenreDetailViewController * const strongSelf = weakSelf;
        if (strongSelf == nil) {
            return;
        }
        strongSelf->_albumGrid.items = albums;
        strongSelf.headerView.detail = MacLCJoinedDetails(@[
            MacLCCountString(albums.count, _NS("album"), _NS("albums")),
            strongSelf->_genre.numberOfTracks > 0
                ? MacLCCountString(strongSelf->_genre.numberOfTracks, _NS("song"), _NS("songs")) : @"",
        ]);
    }];
}

- (void)applySearchString:(NSString *)searchString
{
    [_albumGrid applySearchString:searchString];
}

@end
