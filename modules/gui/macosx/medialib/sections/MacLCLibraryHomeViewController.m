/*****************************************************************************
 * MacLCLibraryHomeViewController.m: featured hero and shelves of home
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

#import "main/VLCMain.h"
#import "library/VLCLibraryWindow.h"
#import "library/VLCLibrarySegment.h"
#import "library/VLCLibraryDataTypes.h"
#import "medialib/MacLCLibraryTypes.h"
#import "medialib/components/MacLCArtworkView.h"
#import "medialib/components/MacLCMediaCardItem.h"
#import "medialib/components/MacLCCollectionLayout.h"
#import "medialib/components/MacLCSectionHeaderView.h"
#import "medialib/components/MacLCEmptyStateView.h"
#import "medialib/components/MacLCHeroView.h"
#import "medialib/data/MacLCLibraryStore.h"
#import "medialib/data/MacLCLibraryActions.h"
#import "medialib/shell/MacLCLibraryFoldersController.h"
#import "theme/MacLCDesign.h"
#import "extensions/NSString+Helpers.h"

static NSString * const MacLCHeroSectionIdentifier = @"hero";
static NSString * const MacLCContinueWatchingSectionIdentifier = @"continueWatching";
static NSString * const MacLCRecentlyAddedSectionIdentifier = @"recentlyAdded";
static NSString * const MacLCRecentlyPlayedSectionIdentifier = @"recentlyPlayed";
static NSString * const MacLCAlbumsSectionIdentifier = @"albums";

static NSString * const MacLCHeroItemIdentifier = @"hero_item";

// MARK: - Internal Hero Collection Item

@interface _MacLCHeroCollectionViewItem : NSCollectionViewItem
@property (nonatomic, strong) MacLCHeroView *heroView;
@end

@implementation _MacLCHeroCollectionViewItem

- (void)loadView
{
    _heroView = [[MacLCHeroView alloc] initWithFrame:NSMakeRect(0, 0, 800, 320)];
    self.view = _heroView;
}

@end

// MARK: - Internal Collection View with Click and Return Key Handling

@interface _MacLCHomeCollectionView : NSCollectionView
@property (nonatomic, copy) void (^doubleClickHandler)(void);
@property (nonatomic, copy) void (^returnKeyHandler)(void);
@end

@implementation _MacLCHomeCollectionView

- (void)mouseDown:(NSEvent *)event
{
    [super mouseDown:event];
    if (event.clickCount == 2 && self.doubleClickHandler) {
        self.doubleClickHandler();
    }
}

- (void)keyDown:(NSEvent *)event
{
    if (event.keyCode == 36 && self.returnKeyHandler) { // Return key
        self.returnKeyHandler();
        return;
    }
    [super keyDown:event];
}

@end

// MARK: - Home Content View Controller

@interface _MacLCLibraryHomeContentViewController : NSViewController <NSCollectionViewDelegate>
{
    NSScrollView *_scrollView;
    _MacLCHomeCollectionView *_collectionView;
    NSCollectionViewDiffableDataSource<NSString *, MacLCLibraryItemID> *_dataSource;
    NSMutableDictionary<MacLCLibraryItemID, id<VLCMediaLibraryItemProtocol>> *_itemsByID;
    NSMutableArray<NSString *> *_activeSections;
    NSView *_emptyStateContainer;

    NSString *_searchString;
    VLCMediaLibraryMediaItem *_heroItem;
    NSString *_heroEyebrow;
}

@property (nonatomic, weak) MacLCLibraryHomeViewController *homeViewController;

- (void)applySearchString:(NSString *)searchString;
- (void)reloadDataAnimated:(BOOL)animated;

@end

@implementation _MacLCLibraryHomeContentViewController

- (void)loadView
{
    NSView *root = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 800, 600)];
    root.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    self.view = root;

    _scrollView = [[NSScrollView alloc] initWithFrame:root.bounds];
    _scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    _scrollView.drawsBackground = NO;
    _scrollView.hasVerticalScroller = YES;
    _scrollView.autohidesScrollers = YES;
    /* The hero runs under the toolbar: insets come from -updateContentInsets. */
    _scrollView.automaticallyAdjustsContentInsets = NO;
    [root addSubview:_scrollView];

    [NSLayoutConstraint activateConstraints:@[
        [_scrollView.leadingAnchor constraintEqualToAnchor:root.leadingAnchor],
        [_scrollView.trailingAnchor constraintEqualToAnchor:root.trailingAnchor],
        [_scrollView.topAnchor constraintEqualToAnchor:root.topAnchor],
        [_scrollView.bottomAnchor constraintEqualToAnchor:root.bottomAnchor],
    ]];

    _collectionView = [[_MacLCHomeCollectionView alloc] initWithFrame:_scrollView.bounds];
    _collectionView.translatesAutoresizingMaskIntoConstraints = NO;
    _collectionView.delegate = self;
    _collectionView.selectable = YES;
    _collectionView.allowsMultipleSelection = YES;
    _collectionView.allowsEmptySelection = YES;
    __weak typeof(self) weakSelf = self;
    _collectionView.doubleClickHandler = ^{
        [weakSelf handleSelectionActivation];
    };
    _collectionView.returnKeyHandler = ^{
        [weakSelf handleSelectionActivation];
    };

    _scrollView.documentView = _collectionView;

    _itemsByID = [NSMutableDictionary dictionary];
    _activeSections = [NSMutableArray array];

    NSCollectionViewCompositionalLayoutSectionProvider provider = ^NSCollectionLayoutSection * _Nullable(NSInteger sectionIndex, id<NSCollectionLayoutEnvironment> environment) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return nil;
        return [strongSelf sectionLayoutForIndex:sectionIndex environment:environment];
    };

    NSCollectionViewCompositionalLayout *layout = [[NSCollectionViewCompositionalLayout alloc] initWithSectionProvider:provider];
    _collectionView.collectionViewLayout = layout;

    /* Register after setting the layout: assigning a layout drops the
     * registrations made before it. */
    [_collectionView registerClass:[_MacLCHeroCollectionViewItem class]
             forItemWithIdentifier:MacLCHeroItemIdentifier];
    [_collectionView registerClass:[MacLCMediaCardItem class]
             forItemWithIdentifier:MacLCMediaCardItemIdentifier];
    [_collectionView registerClass:[MacLCSectionHeaderView class]
        forSupplementaryViewOfKind:MacLCSectionHeaderElementKind
                    withIdentifier:MacLCSectionHeaderViewIdentifier];

    [self configureDataSource];
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(storeDidChange:)
                                                 name:MacLCLibraryStoreDidChangeNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(indexingDidChange:)
                                                 name:MacLCLibraryStoreIndexingDidChangeNotification
                                               object:nil];

    [self reloadDataAnimated:NO];
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewDidLayout
{
    [super viewDidLayout];
    [self updateContentInsets];
}

/* The safe area holds the toolbar, the floating sidebar and inspector, and
 * the Now Playing bar. The hero starts at the very top, under the toolbar's
 * glass; everything else stays inside the safe area. */
- (void)updateContentInsets
{
    const NSEdgeInsets safe = self.view.safeAreaInsets;
    const CGFloat top = _heroItem != nil && _searchString.length == 0 ? 0.0 : safe.top;
    const NSEdgeInsets insets = NSEdgeInsetsMake(top, safe.left, safe.bottom, safe.right);
    const NSEdgeInsets current = _scrollView.contentInsets;
    if (current.top != insets.top || current.left != insets.left ||
        current.bottom != insets.bottom || current.right != insets.right) {
        _scrollView.contentInsets = insets;
        _scrollView.scrollerInsets = NSEdgeInsetsMake(safe.top - top, 0.0, 0.0, 0.0);
    }
}

// MARK: - Layout Configuration

- (NSCollectionLayoutSection *)sectionLayoutForIndex:(NSInteger)sectionIndex
                                         environment:(id<NSCollectionLayoutEnvironment>)environment
{
    if (sectionIndex >= _activeSections.count) {
        return [MacLCCollectionLayout shelfSectionWithShape:MacLCArtworkShapeVideo environment:environment hasSubtitle:YES];
    }

    NSString *sectionID = _activeSections[sectionIndex];
    if ([sectionID isEqualToString:MacLCHeroSectionIdentifier]) {
        CGFloat windowHeight = environment.container.effectiveContentSize.height;
        CGFloat heroHeight = fmin(fmax(windowHeight * 0.42, 280.0), 460.0);
        return [MacLCCollectionLayout fullWidthSectionWithHeight:heroHeight];
    } else if ([sectionID isEqualToString:MacLCContinueWatchingSectionIdentifier]) {
        return [MacLCCollectionLayout shelfSectionWithShape:MacLCArtworkShapeVideo environment:environment hasSubtitle:YES];
    } else if ([sectionID isEqualToString:MacLCRecentlyAddedSectionIdentifier]) {
        return [MacLCCollectionLayout shelfSectionWithShape:MacLCArtworkShapeVideo environment:environment hasSubtitle:YES];
    } else if ([sectionID isEqualToString:MacLCRecentlyPlayedSectionIdentifier]) {
        return [MacLCCollectionLayout shelfSectionWithShape:MacLCArtworkShapeSquare environment:environment hasSubtitle:YES];
    } else if ([sectionID isEqualToString:MacLCAlbumsSectionIdentifier]) {
        return [MacLCCollectionLayout shelfSectionWithShape:MacLCArtworkShapeSquare environment:environment hasSubtitle:YES];
    }

    return [MacLCCollectionLayout shelfSectionWithShape:MacLCArtworkShapeVideo environment:environment hasSubtitle:YES];
}

// MARK: - Data Source

- (void)configureDataSource
{
    __weak typeof(self) weakSelf = self;
    _dataSource = [[NSCollectionViewDiffableDataSource alloc] initWithCollectionView:_collectionView
                                                                        itemProvider:^NSCollectionViewItem * _Nullable(NSCollectionView *collectionView, NSIndexPath *indexPath, id itemID) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return nil;

        if ([itemID isEqualToString:MacLCHeroItemIdentifier]) {
            _MacLCHeroCollectionViewItem *heroItem = [collectionView makeItemWithIdentifier:MacLCHeroItemIdentifier forIndexPath:indexPath];
            heroItem.heroView.mediaItem = strongSelf->_heroItem;
            heroItem.heroView.eyebrow = strongSelf->_heroEyebrow;
            return heroItem;
        }

        MacLCMediaCardItem *cardItem = [collectionView makeItemWithIdentifier:MacLCMediaCardItemIdentifier forIndexPath:indexPath];
        id<VLCMediaLibraryItemProtocol> item = strongSelf->_itemsByID[itemID];
        if (!item) return cardItem;

        if (indexPath.section < strongSelf->_activeSections.count) {
            NSString *sectionID = strongSelf->_activeSections[indexPath.section];
            if ([sectionID isEqualToString:MacLCContinueWatchingSectionIdentifier]) {
                [cardItem configureWithItem:item
                                      shape:MacLCArtworkShapeVideo
                              subtitleStyle:MacLCCardSubtitleStyleTimeLeft];
            } else if ([sectionID isEqualToString:MacLCRecentlyAddedSectionIdentifier]) {
                [cardItem configureWithItem:item
                                      shape:MacLCArtworkShapeVideo
                              subtitleStyle:MacLCCardSubtitleStyleDefault];
            } else if ([sectionID isEqualToString:MacLCRecentlyPlayedSectionIdentifier]) {
                [cardItem configureWithItem:item
                                      shape:MacLCArtworkShapeSquare
                              subtitleStyle:MacLCCardSubtitleStyleDefault];
            } else if ([sectionID isEqualToString:MacLCAlbumsSectionIdentifier]) {
                [cardItem configureWithItem:item
                                      shape:MacLCArtworkShapeSquare
                              subtitleStyle:MacLCCardSubtitleStyleDefault];
            }
        }
        return cardItem;
    }];

    _dataSource.supplementaryViewProvider = ^NSView * _Nullable(NSCollectionView *collectionView, NSString *kind, NSIndexPath *indexPath) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf || ![kind isEqualToString:MacLCSectionHeaderElementKind]) {
            return nil;
        }

        MacLCSectionHeaderView *header = [collectionView makeSupplementaryViewOfKind:kind
                                                                      withIdentifier:MacLCSectionHeaderViewIdentifier
                                                                        forIndexPath:indexPath];
        if (indexPath.section >= strongSelf->_activeSections.count) {
            return header;
        }

        NSString *sectionID = strongSelf->_activeSections[indexPath.section];
        if ([sectionID isEqualToString:MacLCContinueWatchingSectionIdentifier]) {
            header.title = _NS("Continue Watching");
            header.subtitle = nil;
            header.actionTitle = _NS("See All");
            header.action = ^{
                VLCMain.sharedInstance.libraryWindow.librarySegmentType = VLCLibraryVideoSegmentType;
            };
        } else if ([sectionID isEqualToString:MacLCRecentlyAddedSectionIdentifier]) {
            header.title = _NS("Recently Added");
            header.subtitle = nil;
            header.actionTitle = _NS("See All");
            header.action = ^{
                VLCMain.sharedInstance.libraryWindow.librarySegmentType = VLCLibraryVideoSegmentType;
            };
        } else if ([sectionID isEqualToString:MacLCRecentlyPlayedSectionIdentifier]) {
            header.title = _NS("Recently Played");
            header.subtitle = nil;
            header.actionTitle = nil;
            header.action = nil;
        } else if ([sectionID isEqualToString:MacLCAlbumsSectionIdentifier]) {
            header.title = _NS("Albums");
            header.subtitle = nil;
            header.actionTitle = _NS("See All");
            header.action = ^{
                VLCMain.sharedInstance.libraryWindow.librarySegmentType = VLCLibraryAlbumsMusicSubSegmentType;
            };
        } else {
            header.title = @"";
            header.subtitle = nil;
            header.actionTitle = nil;
            header.action = nil;
        }
        return header;
    };
}

// MARK: - Notifications

- (void)storeDidChange:(NSNotification *)notification
{
    NSSet *changed = notification.userInfo[MacLCLibraryStoreChangedCollectionsKey];
    if (changed != nil) {
        BOOL relevant = [changed containsObject:@(MacLCLibraryCollectionContinueWatching)] ||
                        [changed containsObject:@(MacLCLibraryCollectionRecentlyAddedVideos)] ||
                        [changed containsObject:@(MacLCLibraryCollectionRecentlyPlayedMusic)] ||
                        [changed containsObject:@(MacLCLibraryCollectionAlbums)];
        if (!relevant) {
            return;
        }
    }
    [self reloadDataAnimated:YES];
}

- (void)indexingDidChange:(NSNotification *)notification
{
    MacLCLibraryStore *store = MacLCLibraryStore.sharedStore;
    if (store.isLoaded && store.isEmpty) {
        [self reloadDataAnimated:NO];
    }
}

// MARK: - Data Reload

- (void)applySearchString:(NSString *)searchString
{
    _searchString = [searchString copy];
    [self reloadDataAnimated:YES];
}

- (void)reloadDataAnimated:(BOOL)animated
{
    MacLCLibraryStore *store = MacLCLibraryStore.sharedStore;
    if (!store) {
        return;
    }

    NSArray<VLCMediaLibraryMediaItem *> *continueWatching = [store itemsInCollection:MacLCLibraryCollectionContinueWatching];
    NSArray<VLCMediaLibraryMediaItem *> *recentlyAdded = [store itemsInCollection:MacLCLibraryCollectionRecentlyAddedVideos];
    NSArray<VLCMediaLibraryMediaItem *> *recentlyPlayed = [store itemsInCollection:MacLCLibraryCollectionRecentlyPlayedMusic];
    NSArray<VLCMediaLibraryAlbum *> *albums = [store itemsInCollection:MacLCLibraryCollectionAlbums];
    if (albums.count > 20) {
        albums = [albums subarrayWithRange:NSMakeRange(0, 20)];
    }

    // Determine hero
    if (_searchString.length == 0) {
        if (continueWatching.count > 0) {
            _heroItem = continueWatching.firstObject;
            _heroEyebrow = @"CONTINUE WATCHING";
        } else if (recentlyAdded.count > 0) {
            _heroItem = recentlyAdded.firstObject;
            _heroEyebrow = @"RECENTLY ADDED";
        } else {
            _heroItem = nil;
            _heroEyebrow = nil;
        }
    } else {
        _heroItem = nil;
        _heroEyebrow = nil;
    }

    // Filter if search active
    if (_searchString.length > 0) {
        NSPredicate *mediaPredicate = [NSPredicate predicateWithBlock:^BOOL(VLCMediaLibraryMediaItem *item, NSDictionary *bindings) {
            return [item.title localizedStandardContainsString:self->_searchString];
        }];
        NSPredicate *albumPredicate = [NSPredicate predicateWithBlock:^BOOL(VLCMediaLibraryAlbum *item, NSDictionary *bindings) {
            return [item.title localizedStandardContainsString:self->_searchString] ||
                   [item.artistName localizedStandardContainsString:self->_searchString];
        }];
        continueWatching = [continueWatching filteredArrayUsingPredicate:mediaPredicate];
        recentlyAdded = [recentlyAdded filteredArrayUsingPredicate:mediaPredicate];
        recentlyPlayed = [recentlyPlayed filteredArrayUsingPredicate:mediaPredicate];
        albums = [albums filteredArrayUsingPredicate:albumPredicate];
    }

    NSUInteger totalItems = continueWatching.count + recentlyAdded.count + recentlyPlayed.count + albums.count;

    // Check empty states
    if (_searchString.length > 0 && totalItems == 0) {
        _collectionView.hidden = YES;
        [self showSearchEmptyState];
        return;
    }

    if (_searchString.length == 0 && store.isLoaded && store.isEmpty) {
        _collectionView.hidden = YES;
        [self showOnboardingEmptyState];
        return;
    }

    [self hideEmptyState];
    _collectionView.hidden = NO;

    NSDiffableDataSourceSnapshot<NSString *, MacLCLibraryItemID> *snapshot = [[NSDiffableDataSourceSnapshot alloc] init];
    [_activeSections removeAllObjects];
    [_itemsByID removeAllObjects];

    if (_heroItem != nil) {
        [_activeSections addObject:MacLCHeroSectionIdentifier];
        [snapshot appendSectionsWithIdentifiers:@[MacLCHeroSectionIdentifier]];
        [snapshot appendItemsWithIdentifiers:@[MacLCHeroItemIdentifier] intoSectionWithIdentifier:MacLCHeroSectionIdentifier];
    }

    /* A video can be both in progress and recently added: each shelf gets
     * its own identifiers (shelf/item), since a snapshot must not hold the
     * same identifier twice. */
    void (^addShelf)(NSString *sectionID, NSArray *items) = ^(NSString *sectionID, NSArray *items) {
        if (items.count == 0) return;
        NSMutableArray<MacLCLibraryItemID> *sectionItemIDs = [NSMutableArray array];
        NSMutableSet<MacLCLibraryItemID> *seenIDs = [NSMutableSet set];
        for (id<VLCMediaLibraryItemProtocol> item in items) {
            MacLCLibraryItemID const libraryItemID = MacLCLibraryItemIdentifier(item);
            if (!libraryItemID) {
                continue;
            }
            MacLCLibraryItemID const itemID = [NSString stringWithFormat:@"%@/%@", sectionID, libraryItemID];
            if ([seenIDs containsObject:itemID]) {
                continue;
            }
            [seenIDs addObject:itemID];
            self->_itemsByID[itemID] = item;
            [sectionItemIDs addObject:itemID];
        }
        if (sectionItemIDs.count > 0) {
            [self->_activeSections addObject:sectionID];
            [snapshot appendSectionsWithIdentifiers:@[sectionID]];
            [snapshot appendItemsWithIdentifiers:sectionItemIDs intoSectionWithIdentifier:sectionID];
        }
    };

    addShelf(MacLCContinueWatchingSectionIdentifier, continueWatching);
    addShelf(MacLCRecentlyAddedSectionIdentifier, recentlyAdded);
    addShelf(MacLCRecentlyPlayedSectionIdentifier, recentlyPlayed);
    addShelf(MacLCAlbumsSectionIdentifier, albums);

    BOOL shouldAnimate = animated && self.view.window.isVisible && !NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion;
    [_dataSource applySnapshot:snapshot animatingDifferences:shouldAnimate];
    [self updateContentInsets];
    [self.homeViewController chromeDidChange];
}

// MARK: - Empty States

- (void)hideEmptyState
{
    if (_emptyStateContainer) {
        [_emptyStateContainer removeFromSuperview];
        _emptyStateContainer = nil;
    }
}

- (void)showOnboardingEmptyState
{
    [self hideEmptyState];

    _emptyStateContainer = [[NSView alloc] init];
    _emptyStateContainer.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_emptyStateContainer];

    [NSLayoutConstraint activateConstraints:@[
        [_emptyStateContainer.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [_emptyStateContainer.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
        [_emptyStateContainer.widthAnchor constraintLessThanOrEqualToConstant:420],
    ]];

    MacLCLibraryStore *store = MacLCLibraryStore.sharedStore;
    if (store.isIndexing) {
        NSString *location = store.indexingLocation ?: _NS("folder");
        NSString *msg = [NSString stringWithFormat:_NS("Adding media from %@…"), location];
        MacLCEmptyStateView *emptyView = [MacLCEmptyStateView emptyStateWithSymbolName:@"rectangle.stack.badge.play"
                                                                                title:_NS("Add Your Media")
                                                                              message:msg];
        emptyView.translatesAutoresizingMaskIntoConstraints = NO;
        [_emptyStateContainer addSubview:emptyView];

        NSProgressIndicator *spinner = [[NSProgressIndicator alloc] init];
        spinner.translatesAutoresizingMaskIntoConstraints = NO;
        spinner.style = NSProgressIndicatorStyleSpinning;
        spinner.indeterminate = YES;
        spinner.controlSize = NSControlSizeRegular;
        [spinner startAnimation:nil];
        [_emptyStateContainer addSubview:spinner];

        [NSLayoutConstraint activateConstraints:@[
            [emptyView.topAnchor constraintEqualToAnchor:_emptyStateContainer.topAnchor],
            [emptyView.leadingAnchor constraintEqualToAnchor:_emptyStateContainer.leadingAnchor],
            [emptyView.trailingAnchor constraintEqualToAnchor:_emptyStateContainer.trailingAnchor],
            [spinner.topAnchor constraintEqualToAnchor:emptyView.bottomAnchor constant:MacLCDesign.spacingL],
            [spinner.centerXAnchor constraintEqualToAnchor:_emptyStateContainer.centerXAnchor],
            [spinner.bottomAnchor constraintEqualToAnchor:_emptyStateContainer.bottomAnchor],
        ]];
    } else {
        MacLCEmptyStateView *emptyView = [MacLCEmptyStateView emptyStateWithSymbolName:@"rectangle.stack.badge.play"
                                                                                title:_NS("Add Your Media")
                                                                              message:_NS("MacLC organizes the movies, shows and music in the folders you choose. Nothing leaves your Mac.")];
        emptyView.translatesAutoresizingMaskIntoConstraints = NO;
        [_emptyStateContainer addSubview:emptyView];

        [emptyView addButtonWithTitle:_NS("Add Movies & Music Folders")
                            prominent:YES
                               action:^{
            [store addStandardMediaFolders];
        }];

        __weak typeof(self) weakSelf = self;
        [emptyView addButtonWithTitle:_NS("Choose Folder…")
                            prominent:NO
                               action:^{
            [[MacLCLibraryFoldersController sharedController] chooseFoldersToAddForWindow:weakSelf.view.window];
        }];

        [NSLayoutConstraint activateConstraints:@[
            [emptyView.topAnchor constraintEqualToAnchor:_emptyStateContainer.topAnchor],
            [emptyView.leadingAnchor constraintEqualToAnchor:_emptyStateContainer.leadingAnchor],
            [emptyView.trailingAnchor constraintEqualToAnchor:_emptyStateContainer.trailingAnchor],
            [emptyView.bottomAnchor constraintEqualToAnchor:_emptyStateContainer.bottomAnchor],
        ]];
    }
}

- (void)showSearchEmptyState
{
    [self hideEmptyState];

    _emptyStateContainer = [[NSView alloc] init];
    _emptyStateContainer.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_emptyStateContainer];

    [NSLayoutConstraint activateConstraints:@[
        [_emptyStateContainer.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [_emptyStateContainer.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
        [_emptyStateContainer.widthAnchor constraintLessThanOrEqualToConstant:420],
    ]];

    MacLCEmptyStateView *emptyView = [MacLCEmptyStateView emptyStateWithSymbolName:@"magnifyingglass"
                                                                            title:[NSString stringWithFormat:_NS("No Results for “%@”"), _searchString]
                                                                          message:_NS("Check the spelling or try a new search.")];
    emptyView.translatesAutoresizingMaskIntoConstraints = NO;
    [_emptyStateContainer addSubview:emptyView];

    [NSLayoutConstraint activateConstraints:@[
        [emptyView.topAnchor constraintEqualToAnchor:_emptyStateContainer.topAnchor],
        [emptyView.leadingAnchor constraintEqualToAnchor:_emptyStateContainer.leadingAnchor],
        [emptyView.trailingAnchor constraintEqualToAnchor:_emptyStateContainer.trailingAnchor],
        [emptyView.bottomAnchor constraintEqualToAnchor:_emptyStateContainer.bottomAnchor],
    ]];
}

// MARK: - Actions

- (void)handleSelectionActivation
{
    NSSet<NSIndexPath *> *selection = _collectionView.selectionIndexPaths;
    NSIndexPath *indexPath = selection.anyObject;
    if (!indexPath) {
        return;
    }

    MacLCLibraryItemID itemID = [_dataSource itemIdentifierForIndexPath:indexPath];
    if (!itemID || [itemID isEqualToString:MacLCHeroItemIdentifier]) {
        return;
    }

    id<VLCMediaLibraryItemProtocol> item = _itemsByID[itemID];
    if (!item) {
        return;
    }

    if ([item isKindOfClass:[VLCMediaLibraryAlbum class]]) {
        MacLCAlbumDetailViewController *detail = [[MacLCAlbumDetailViewController alloc] initWithAlbum:(VLCMediaLibraryAlbum *)item];
        [self.homeViewController pushViewController:detail];
    } else {
        [MacLCLibraryActions playItems:@[item] startingAt:0];
    }
}

@end

// MARK: - MacLCLibraryHomeViewController

@interface MacLCLibraryHomeViewController ()
{
    _MacLCLibraryHomeContentViewController *_contentViewController;
}
@end

@implementation MacLCLibraryHomeViewController

- (instancetype)init
{
    self = [super initWithSegmentType:VLCLibraryHomeSegmentType];
    return self;
}

- (NSString *)sectionTitle
{
    if (self.topViewController && self.topViewController != self.rootViewController && self.topViewController.title.length > 0) {
        return self.topViewController.title;
    }
    return _NS("Home");
}

- (NSString *)makeSearchPlaceholder
{
    return _NS("Search Home");
}

- (NSViewController *)makeRootViewControllerForViewMode:(MacLCLibraryViewMode)viewMode
{
    _contentViewController = [[_MacLCLibraryHomeContentViewController alloc] initWithNibName:nil bundle:nil];
    _contentViewController.homeViewController = self;
    return _contentViewController;
}

- (void)searchStringDidChange:(NSString *)searchString
{
    if (_contentViewController) {
        [_contentViewController applySearchString:searchString];
    }
}

@end
