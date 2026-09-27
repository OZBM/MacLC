/*****************************************************************************
 * MacLCLibraryFavoritesViewController.m: favourite videos, songs, albums, artists
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
#import "library/VLCLibrarySegment.h"
#import "medialib/MacLCLibraryFormatting.h"
#import "medialib/components/MacLCCollectionLayout.h"
#import "medialib/components/MacLCEmptyStateView.h"
#import "medialib/components/MacLCMediaCardItem.h"
#import "medialib/components/MacLCSectionHeaderView.h"
#import "medialib/data/MacLCLibraryActions.h"
#import "medialib/data/MacLCLibraryStore.h"

/* One shelf per favourite kind, in this order. */
static const MacLCLibraryCollection MacLCFavoriteShelves[] = {
    MacLCLibraryCollectionFavoriteVideos,
    MacLCLibraryCollectionFavoriteSongs,
    MacLCLibraryCollectionFavoriteAlbums,
    MacLCLibraryCollectionFavoriteArtists,
};
static const NSUInteger MacLCFavoriteShelfCount = sizeof(MacLCFavoriteShelves) / sizeof(MacLCFavoriteShelves[0]);

static MacLCArtworkShape MacLCShapeForFavoriteShelf(MacLCLibraryCollection collection)
{
    switch (collection) {
        case MacLCLibraryCollectionFavoriteVideos:
            return MacLCArtworkShapeVideo;
        case MacLCLibraryCollectionFavoriteArtists:
            return MacLCArtworkShapeCircle;
        default:
            return MacLCArtworkShapeSquare;
    }
}

static NSString *MacLCTitleForFavoriteShelf(MacLCLibraryCollection collection)
{
    switch (collection) {
        case MacLCLibraryCollectionFavoriteVideos:
            return _NS("Videos");
        case MacLCLibraryCollectionFavoriteSongs:
            return _NS("Songs");
        case MacLCLibraryCollectionFavoriteAlbums:
            return _NS("Albums");
        default:
            return _NS("Artists");
    }
}

@interface MacLCFavoritesContentViewController : NSViewController
@property (nonatomic, weak) MacLCLibraryFavoritesViewController *section;
- (void)reload;
- (void)applySearchString:(NSString *)searchString;
@end

@interface MacLCFavoritesContentViewController ()
{
    NSScrollView *_scrollView;
    NSCollectionView *_collectionView;
    NSCollectionViewDiffableDataSource<NSNumber *, MacLCLibraryItemID> *_dataSource;
    NSMutableDictionary<MacLCLibraryItemID, id<VLCMediaLibraryItemProtocol>> *_itemsByID;
    NSArray<NSNumber *> *_shownShelves;
    NSString *_searchString;
    MacLCEmptyStateView *_emptyState;
}
@end

@implementation MacLCFavoritesContentViewController

- (void)loadView
{
    NSView * const root = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 800, 600)];
    _itemsByID = [NSMutableDictionary dictionary];
    _shownShelves = @[];
    _searchString = @"";

    __weak typeof(self) weakSelf = self;
    NSCollectionViewCompositionalLayout * const layout = [[NSCollectionViewCompositionalLayout alloc]
        initWithSectionProvider:^NSCollectionLayoutSection * _Nullable(NSInteger sectionIndex,
                                                                       id<NSCollectionLayoutEnvironment> environment) {
            MacLCFavoritesContentViewController * const strongSelf = weakSelf;
            if (strongSelf == nil || sectionIndex >= (NSInteger)strongSelf->_shownShelves.count) {
                return nil;
            }
            const MacLCLibraryCollection collection =
                (MacLCLibraryCollection)strongSelf->_shownShelves[(NSUInteger)sectionIndex].integerValue;
            return [MacLCCollectionLayout shelfSectionWithShape:MacLCShapeForFavoriteShelf(collection)
                                                    environment:environment
                                                    hasSubtitle:YES];
        }];

    _collectionView = [[NSCollectionView alloc] initWithFrame:root.bounds];
    _collectionView.collectionViewLayout = layout;
    _collectionView.selectable = YES;
    _collectionView.allowsMultipleSelection = YES;
    _collectionView.backgroundColors = @[NSColor.clearColor];
    [_collectionView registerClass:MacLCMediaCardItem.class forItemWithIdentifier:MacLCMediaCardItemIdentifier];
    [_collectionView registerClass:MacLCSectionHeaderView.class
        forSupplementaryViewOfKind:MacLCSectionHeaderElementKind
                    withIdentifier:MacLCSectionHeaderViewIdentifier];

    _scrollView = [[NSScrollView alloc] initWithFrame:root.bounds];
    _scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    _scrollView.documentView = _collectionView;
    _scrollView.drawsBackground = NO;
    _scrollView.hasVerticalScroller = YES;
    _scrollView.autohidesScrollers = YES;
    [root addSubview:_scrollView];
    [NSLayoutConstraint activateConstraints:@[
        [_scrollView.topAnchor constraintEqualToAnchor:root.topAnchor],
        [_scrollView.bottomAnchor constraintEqualToAnchor:root.bottomAnchor],
        [_scrollView.leadingAnchor constraintEqualToAnchor:root.leadingAnchor],
        [_scrollView.trailingAnchor constraintEqualToAnchor:root.trailingAnchor],
    ]];
    self.view = root;

    _dataSource = [[NSCollectionViewDiffableDataSource alloc]
        initWithCollectionView:_collectionView
                  itemProvider:^NSCollectionViewItem * _Nullable(NSCollectionView * const collectionView,
                                                                 NSIndexPath * const indexPath,
                                                                 MacLCLibraryItemID const identifier) {
        MacLCFavoritesContentViewController * const strongSelf = weakSelf;
        MacLCMediaCardItem * const card = [collectionView makeItemWithIdentifier:MacLCMediaCardItemIdentifier
                                                                    forIndexPath:indexPath];
        id<VLCMediaLibraryItemProtocol> const item = strongSelf->_itemsByID[identifier];
        if (strongSelf == nil || item == nil || indexPath.section >= (NSInteger)strongSelf->_shownShelves.count) {
            return card;
        }
        const MacLCLibraryCollection collection =
            (MacLCLibraryCollection)strongSelf->_shownShelves[(NSUInteger)indexPath.section].integerValue;
        [card configureWithItem:item
                          shape:MacLCShapeForFavoriteShelf(collection)
                  subtitleStyle:MacLCCardSubtitleStyleDefault];
        card.activationHandler = ^(id<VLCMediaLibraryItemProtocol> const activated) {
            [weakSelf activateItem:activated];
        };
        return card;
    }];
    _dataSource.supplementaryViewProvider = ^NSView * _Nullable(NSCollectionView * const collectionView,
                                                                NSString * const kind,
                                                                NSIndexPath * const indexPath) {
        MacLCFavoritesContentViewController * const strongSelf = weakSelf;
        MacLCSectionHeaderView * const header =
            [collectionView makeSupplementaryViewOfKind:kind
                                         withIdentifier:MacLCSectionHeaderViewIdentifier
                                           forIndexPath:indexPath];
        if (strongSelf != nil && indexPath.section < (NSInteger)strongSelf->_shownShelves.count) {
            header.title = MacLCTitleForFavoriteShelf(
                (MacLCLibraryCollection)strongSelf->_shownShelves[(NSUInteger)indexPath.section].integerValue);
        }
        return header;
    };
    [self reload];
}

- (void)activateItem:(id<VLCMediaLibraryItemProtocol>)item
{
    if ([item isKindOfClass:VLCMediaLibraryMediaItem.class]) {
        [MacLCLibraryActions playItems:@[item] startingAt:0];
        return;
    }
    NSViewController *detail = nil;
    if ([item isKindOfClass:VLCMediaLibraryAlbum.class]) {
        detail = [[MacLCAlbumDetailViewController alloc] initWithAlbum:(VLCMediaLibraryAlbum *)item];
    } else if ([item isKindOfClass:VLCMediaLibraryArtist.class]) {
        detail = [[MacLCArtistDetailViewController alloc] initWithArtist:(VLCMediaLibraryArtist *)item];
    }
    if (detail != nil) {
        [self.section pushViewController:detail];
    }
}

- (void)applySearchString:(NSString *)searchString
{
    _searchString = [searchString copy] ?: @"";
    [self reload];
}

- (void)reload
{
    if (!self.isViewLoaded) {
        return;
    }
    MacLCLibraryStore * const store = MacLCLibraryStore.sharedStore;
    NSString * const query = [_searchString stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    NSDiffableDataSourceSnapshot<NSNumber *, MacLCLibraryItemID> * const snapshot =
        [[NSDiffableDataSourceSnapshot alloc] init];
    NSMutableArray<NSNumber *> * const shelves = [NSMutableArray array];
    [_itemsByID removeAllObjects];
    for (NSUInteger i = 0; i < MacLCFavoriteShelfCount; i++) {
        const MacLCLibraryCollection collection = MacLCFavoriteShelves[i];
        NSMutableArray<MacLCLibraryItemID> * const identifiers = [NSMutableArray array];
        for (id<VLCMediaLibraryItemProtocol> const item in [store itemsInCollection:collection]) {
            if (query.length > 0 && ![item.displayString localizedStandardContainsString:query]) {
                continue;
            }
            MacLCLibraryItemID const identifier = MacLCLibraryItemIdentifier(item);
            if (_itemsByID[identifier] != nil) {
                continue;
            }
            _itemsByID[identifier] = item;
            [identifiers addObject:identifier];
        }
        if (identifiers.count == 0) {
            continue;
        }
        [shelves addObject:@(collection)];
        [snapshot appendSectionsWithIdentifiers:@[@(collection)]];
        [snapshot appendItemsWithIdentifiers:identifiers intoSectionWithIdentifier:@(collection)];
    }
    _shownShelves = shelves;
    [_dataSource applySnapshot:snapshot animatingDifferences:NO];

    [_emptyState removeFromSuperview];
    _emptyState = nil;
    if (shelves.count == 0 && store.loaded) {
        _emptyState = query.length > 0
            ? [MacLCEmptyStateView emptyStateWithSymbolName:@"magnifyingglass"
                                                      title:[NSString stringWithFormat:_NS("No Results for “%@”"), query]
                                                    message:_NS("Check the spelling or try a new search.")]
            : [MacLCEmptyStateView emptyStateWithSymbolName:@"star"
                                                      title:_NS("No Favorites")
                                                    message:_NS("Choose Favorite in the menu of a video, song, album or artist to keep it here.")];
        _emptyState.translatesAutoresizingMaskIntoConstraints = NO;
        [self.view addSubview:_emptyState];
        [NSLayoutConstraint activateConstraints:@[
            [_emptyState.centerXAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.centerXAnchor],
            [_emptyState.centerYAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.centerYAnchor],
        ]];
    }
}

@end

@interface MacLCLibraryFavoritesViewController ()
{
    MacLCFavoritesContentViewController *_content;
}
@end

@implementation MacLCLibraryFavoritesViewController

- (instancetype)init
{
    self = [super initWithSegmentType:VLCLibraryFavoritesSegmentType];
    if (self) {
        [NSNotificationCenter.defaultCenter addObserver:self
                                               selector:@selector(storeDidChange:)
                                                   name:MacLCLibraryStoreDidChangeNotification
                                                 object:nil];
    }
    return self;
}

- (void)dealloc
{
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)storeDidChange:(NSNotification *)notification
{
    [_content reload];
    [self chromeDidChange];
}

- (NSString *)sectionTitle
{
    if (self.topViewController != self.rootViewController && self.topViewController.title.length > 0) {
        return self.topViewController.title;
    }
    return _NS("Favorites");
}

- (nullable NSString *)currentSubtitle
{
    NSUInteger count = 0;
    for (NSUInteger i = 0; i < MacLCFavoriteShelfCount; i++) {
        count += [MacLCLibraryStore.sharedStore countOfCollection:MacLCFavoriteShelves[i]];
    }
    return count > 0 ? MacLCCountString(count, _NS("item"), _NS("items")) : nil;
}

- (NSString *)makeSearchPlaceholder
{
    return _NS("Search Favorites");
}

- (NSViewController *)makeRootViewControllerForViewMode:(MacLCLibraryViewMode)viewMode
{
    if (_content == nil) {
        _content = [[MacLCFavoritesContentViewController alloc] initWithNibName:nil bundle:nil];
        _content.section = self;
    }
    return _content;
}

- (void)searchStringDidChange:(NSString *)searchString
{
    if (self.topViewController != self.rootViewController
        && [self.topViewController respondsToSelector:@selector(applySearchString:)]) {
        [(id)self.topViewController applySearchString:searchString];
        return;
    }
    [_content applySearchString:searchString];
}

@end
