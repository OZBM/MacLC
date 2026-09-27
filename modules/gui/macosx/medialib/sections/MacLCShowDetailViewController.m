/*****************************************************************************
 * MacLCShowDetailViewController.m: a show, season by season
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

@interface MacLCShowDetailViewController ()
{
    VLCMediaLibraryShow *_show;
    MacLCTrackListController *_episodeList;
    NSArray<VLCMediaLibraryMediaItem *> *_episodes;
    NSArray<NSNumber *> *_seasons;
    uint32_t _selectedSeason;
    NSPopUpButton *_seasonButton;
}
@end

@implementation MacLCShowDetailViewController

- (instancetype)initWithShow:(VLCMediaLibraryShow *)show
{
    self = [super initWithArtworkShape:MacLCArtworkShapeVideo];
    if (self) {
        _show = show;
        _episodes = @[];
        _seasons = @[];
        _selectedSeason = UINT32_MAX;
        self.title = show.name.length > 0 ? show.name : show.displayString;
    }
    return self;
}

- (void)viewDidLoad
{
    _episodeList = [[MacLCTrackListController alloc] initWithColumns:MacLCTrackListColumnThumbnail
                                                                     | MacLCTrackListColumnNumber
                                                                     | MacLCTrackListColumnTitle
                                                                     | MacLCTrackListColumnDuration
                                                         autosaveName:@"MacLCShowEpisodes"];
    [self setBodyView:_episodeList.scrollView];

    _seasonButton = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    _seasonButton.target = self;
    _seasonButton.action = @selector(seasonChanged:);
    _seasonButton.accessibilityLabel = _NS("Season");

    MacLCDetailHeaderView * const header = self.headerView;
    [header.artworkView setArtworkFromItem:_show];
    header.title = self.title;
    header.moreMenu = [MacLCLibraryActions contextMenuForItems:@[_show] window:nil];
    [super viewDidLoad];
}

- (void)reloadContents
{
    __weak typeof(self) weakSelf = self;
    [MacLCLibraryStore.sharedStore episodesOfShow:_show completion:^(NSArray<VLCMediaLibraryMediaItem *> * const episodes) {
        [weakSelf showEpisodes:episodes];
    }];
}

- (void)showEpisodes:(NSArray<VLCMediaLibraryMediaItem *> *)episodes
{
    _episodes = episodes;
    NSMutableOrderedSet<NSNumber *> * const seasons = [NSMutableOrderedSet orderedSet];
    for (VLCMediaLibraryMediaItem * const episode in episodes) {
        [seasons addObject:@(episode.showEpisode.seasonNumber)];
    }
    _seasons = seasons.array;
    if (![_seasons containsObject:@(_selectedSeason)]) {
        _selectedSeason = _seasons.firstObject.unsignedIntValue;
    }

    [_seasonButton removeAllItems];
    for (NSNumber * const season in _seasons) {
        [_seasonButton addItemWithTitle:season.unsignedIntValue > 0
            ? [NSString stringWithFormat:_NS("Season %u"), season.unsignedIntValue]
            : _NS("Episodes")];
        _seasonButton.lastItem.representedObject = season;
    }
    const NSUInteger selectedIndex = [_seasons indexOfObject:@(_selectedSeason)];
    if (selectedIndex != NSNotFound) {
        [_seasonButton selectItemAtIndex:(NSInteger)selectedIndex];
    }
    self.choiceView = _seasons.count > 1 ? _seasonButton : nil;
    [self showSelectedSeason];
    [self updateHeader];
}

- (void)seasonChanged:(NSPopUpButton *)sender
{
    _selectedSeason = [sender.selectedItem.representedObject unsignedIntValue];
    [self showSelectedSeason];
}

- (void)showSelectedSeason
{
    NSMutableArray<VLCMediaLibraryMediaItem *> * const episodes = [NSMutableArray array];
    for (VLCMediaLibraryMediaItem * const episode in _episodes) {
        if (_seasons.count <= 1 || episode.showEpisode.seasonNumber == _selectedSeason) {
            [episodes addObject:episode];
        }
    }
    _episodeList.items = episodes;
}

/* The episode people most likely want: the one they stopped in, else the
 * first they have not watched, else the first. */
- (NSUInteger)indexOfNextEpisodeResuming:(BOOL *)resuming
{
    *resuming = NO;
    for (NSUInteger i = 0; i < _episodes.count; i++) {
        const float progress = _episodes[i].progress;
        if (progress > 0.02f && progress < 0.95f) {
            *resuming = YES;
            return i;
        }
    }
    for (NSUInteger i = 0; i < _episodes.count; i++) {
        if (_episodes[i].playCount == 0) {
            return i;
        }
    }
    return 0;
}

- (void)updateHeader
{
    MacLCDetailHeaderView * const header = self.headerView;
    header.detail = MacLCJoinedDetails(@[
        _seasons.count > 1 ? MacLCCountString(_seasons.count, _NS("season"), _NS("seasons")) : @"",
        MacLCCountString(_episodes.count, _NS("episode"), _NS("episodes")),
    ]);
    if (_episodes.count == 0) {
        [header setPrimaryActionTitle:nil symbolName:nil action:nil];
        return;
    }
    BOOL resuming = NO;
    const NSUInteger index = [self indexOfNextEpisodeResuming:&resuming];
    VLCMediaLibraryMediaItem * const next = _episodes[index];
    NSString * const code = [NSString stringWithFormat:_NS("S%u E%u"),
                             next.showEpisode.seasonNumber, next.showEpisode.episodeNumber];
    NSString * const title = [NSString stringWithFormat:resuming ? _NS("Resume %@") : _NS("Play %@"), code];
    NSArray * const episodes = _episodes;
    [header setPrimaryActionTitle:title symbolName:@"play.fill" action:^{
        [MacLCLibraryActions playItems:episodes startingAt:index];
    }];
}

- (void)applySearchString:(NSString *)searchString
{
    [_episodeList applySearchString:searchString];
}

@end
