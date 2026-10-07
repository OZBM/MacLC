/*****************************************************************************
 * MacLCWatchBrowse.m: Home, Movies and TV Shows browse screens and catalogs
 *****************************************************************************
 * Copyright (C) 2026 Hazen Studio
 *
 * This program is free software; you can redistribute it and/or modify it
 * under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation; either version 2.1 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin Street, Fifth Floor, Boston MA 02110-1301, USA.
 *****************************************************************************/

#import "addons/watch/MacLCWatchSections.h"
#import "addons/watch/MacLCWatchComponents.h"
#import "addons/MacLCAddons.h"

#import "main/VLCMain.h"
#import "library/VLCLibrarySegment.h"
#import "settings/MacLCSettingsWindowController.h"
#import "medialib/components/MacLCSectionHeaderView.h"
#import "medialib/components/MacLCEmptyStateView.h"
#import "theme/MacLCDesign.h"
#import "extensions/NSString+Helpers.h"

static NSString * const MacLCWatchHeroSectionIdentifier = @"watch_hero_section";
static NSString * const MacLCWatchHeroItemIdentifier = @"watch_hero_item";

typedef NS_ENUM(NSInteger, MacLCWatchShelfState) {
    MacLCWatchShelfStateUnloaded = 0,
    MacLCWatchShelfStateLoading,
    MacLCWatchShelfStateLoaded,
    MacLCWatchShelfStateFailed,
};

static NSString *PluralTypeName(NSString *type)
{
    if ([type isEqualToString:@"movie"]) {
        return _NS("Movies");
    } else if ([type isEqualToString:@"series"]) {
        return _NS("TV Shows");
    } else if (type.length > 0) {
        NSString *firstChar = [[type substringToIndex:1] uppercaseString];
        NSString *rest = [type substringFromIndex:1];
        return [firstChar stringByAppendingString:rest];
    }
    return @"";
}

static NSString *UpperSingularTypeName(NSString *type)
{
    if ([type isEqualToString:@"movie"]) {
        return @"MOVIE";
    } else if ([type isEqualToString:@"series"] || [type isEqualToString:@"tv"]) {
        return @"TV SHOW";
    } else if (type.length > 0) {
        return [type uppercaseString];
    }
    return @"";
}

static NSString *CatalogKey(MacLCAddonTitleCatalog *cat)
{
    return [NSString stringWithFormat:@"%@_%@_%@", cat.addon.identifier ?: @"", cat.type ?: @"", cat.identifier ?: @""];
}

static NSString *ErrorMessageForError(NSError * _Nullable error, NSString *serviceName)
{
    NSString * const unresolvedHost = MacLCAddonsUnresolvedHost(error);
    if (unresolvedHost) {
        return [NSString stringWithFormat:_NS("MacLC can't find the server “%@”. Check your network settings, then try again."), unresolvedHost];
    } else if (error && [error.domain isEqualToString:NSURLErrorDomain]) {
        return _NS("Check your internet connection, then try again.");
    } else if (error && [error.domain isEqualToString:MacLCAddonsErrorDomain]) {
        if (error.code == MacLCAddonsErrorHTTPStatus) {
            NSNumber *status = error.userInfo[@"status"];
            long code = status ? status.longValue : 0;
            return [NSString stringWithFormat:_NS("The service answered with error %ld. Try again in a moment."), code];
        } else if (error.code == MacLCAddonsErrorBadResponse ||
                   error.code == MacLCAddonsErrorNotAnAddon ||
                   error.code == MacLCAddonsErrorBadAddress) {
            return _NS("If you changed the add-on address in Settings, check it.");
        }
    }
    return _NS("Check your internet connection, then try again.");
}

#pragma mark - Internal Hero Collection Item

@interface _MacLCWatchHeroCollectionViewItem : NSCollectionViewItem
@property (nonatomic, strong) MacLCWatchHeroView *heroView;
@end

@implementation _MacLCWatchHeroCollectionViewItem

- (void)loadView
{
    _heroView = [[MacLCWatchHeroView alloc] initWithFrame:NSMakeRect(0, 0, 800, 420)];
    self.view = _heroView;
}

@end

#pragma mark - Internal Collection View with Click and Return Key Handling

@interface _MacLCWatchCollectionView : NSCollectionView
@property (nonatomic, copy) void (^doubleClickHandler)(void);
@property (nonatomic, copy) void (^returnKeyHandler)(void);
@end

@implementation _MacLCWatchCollectionView

- (void)mouseDown:(NSEvent *)event
{
    [super mouseDown:event];
    if (event.clickCount == 2 && self.doubleClickHandler) {
        self.doubleClickHandler();
    }
}

- (void)keyDown:(NSEvent *)event
{
    if (event.keyCode == 36 && self.returnKeyHandler) {
        self.returnKeyHandler();
        return;
    }
    [super keyDown:event];
}

@end

#pragma mark - MacLCWatchSectionViewController

@interface MacLCWatchSectionViewController ()
{
    NSString *_mediaType;
}
@end

@implementation MacLCWatchSectionViewController

- (instancetype)initWithMediaType:(nullable NSString *)mediaType segmentType:(NSInteger)segmentType
{
    self = [super initWithSegmentType:segmentType];
    if (self) {
        _mediaType = [mediaType copy];
    }
    return self;
}

- (instancetype)initWithSegmentType:(NSInteger)segmentType
{
    NSString *mediaType = nil;
    if (segmentType == VLCLibraryWatchMoviesSegmentType) {
        mediaType = @"movie";
    } else if (segmentType == VLCLibraryWatchShowsSegmentType) {
        mediaType = @"series";
    }
    return [self initWithMediaType:mediaType segmentType:segmentType];
}

- (nullable NSString *)mediaType
{
    return _mediaType;
}

- (NSViewController *)makeRootViewControllerForViewMode:(MacLCLibraryViewMode)viewMode
{
    return [[MacLCWatchBrowseViewController alloc] initWithSection:self];
}

- (BOOL)sectionSupportsViewModes
{
    return NO;
}

- (nullable NSMenu *)makeSortMenu
{
    return nil;
}

- (NSString *)sectionTitle
{
    if (self.topViewController && self.topViewController != self.rootViewController && self.topViewController.title.length > 0) {
        return self.topViewController.title;
    }
    if ([_mediaType isEqualToString:@"movie"]) {
        return _NS("Movies");
    } else if ([_mediaType isEqualToString:@"series"]) {
        return _NS("TV Shows");
    }
    return _NS("Home");
}

- (NSString *)makeSearchPlaceholder
{
    if ([_mediaType isEqualToString:@"movie"]) {
        return _NS("Search Movies");
    } else if ([_mediaType isEqualToString:@"series"]) {
        return _NS("Search TV Shows");
    }
    return _NS("Search Movies and TV Shows");
}

- (void)showDetailForItem:(MacLCAddonItem *)item showStreams:(BOOL)showStreams
{
    if (!item) {
        return;
    }
    MacLCWatchDetailViewController *detailVC = [[MacLCWatchDetailViewController alloc] initWithItem:item showStreams:showStreams];
    [self pushViewController:detailVC];
}

- (BOOL)showsPictureUnderToolbar
{
    NSViewController * const top = self.topViewController;
    if ([top isKindOfClass:MacLCWatchDetailViewController.class])
        return YES;
    return top == self.rootViewController
        && [top isKindOfClass:MacLCWatchBrowseViewController.class]
        && [(MacLCWatchBrowseViewController *)top showsPictureAtTop];
}

- (void)debugOpenFirstFeaturedShowingStreams:(BOOL)showStreams
{
    NSViewController *root = self.rootViewController;
    if (![root isKindOfClass:[MacLCWatchBrowseViewController class]]) {
        return;
    }
    MacLCWatchBrowseViewController *browseVC = (MacLCWatchBrowseViewController *)root;
    if (browseVC.featuredItems.count > 0) {
        [self showDetailForItem:browseVC.featuredItems.firstObject showStreams:showStreams];
    } else {
        __weak typeof(self) weakSelf = self;
        browseVC.featuredItemsLoadedHandler = ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            NSViewController *currentRoot = strongSelf.rootViewController;
            if ([currentRoot isKindOfClass:[MacLCWatchBrowseViewController class]]) {
                MacLCWatchBrowseViewController *b = (MacLCWatchBrowseViewController *)currentRoot;
                if (b.featuredItems.count > 0) {
                    [strongSelf showDetailForItem:b.featuredItems.firstObject showStreams:showStreams];
                }
            }
        };
    }
}

@end

#pragma mark - MacLCWatchHomeSectionViewController

@implementation MacLCWatchHomeSectionViewController

- (instancetype)init
{
    self = [super initWithMediaType:nil segmentType:VLCLibraryWatchHomeSegmentType];
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
    return _NS("Search Movies and TV Shows");
}

@end

#pragma mark - MacLCWatchMoviesSectionViewController

@implementation MacLCWatchMoviesSectionViewController

- (instancetype)init
{
    self = [super initWithMediaType:@"movie" segmentType:VLCLibraryWatchMoviesSegmentType];
    return self;
}

- (NSString *)sectionTitle
{
    if (self.topViewController && self.topViewController != self.rootViewController && self.topViewController.title.length > 0) {
        return self.topViewController.title;
    }
    return _NS("Movies");
}

- (NSString *)makeSearchPlaceholder
{
    return _NS("Search Movies");
}

@end

#pragma mark - MacLCWatchShowsSectionViewController

@implementation MacLCWatchShowsSectionViewController

- (instancetype)init
{
    self = [super initWithMediaType:@"series" segmentType:VLCLibraryWatchShowsSegmentType];
    return self;
}

- (NSString *)sectionTitle
{
    if (self.topViewController && self.topViewController != self.rootViewController && self.topViewController.title.length > 0) {
        return self.topViewController.title;
    }
    return _NS("TV Shows");
}

- (NSString *)makeSearchPlaceholder
{
    return _NS("Search TV Shows");
}

@end

#pragma mark - MacLCWatchBrowseViewController

@interface MacLCWatchBrowseViewController () <NSCollectionViewDelegate>
{
    __weak MacLCWatchSectionViewController *_section;
    BOOL _showsPictureAtTop;
    NSMutableSet<NSString *> *_rankedSectionIDs;

    NSScrollView *_scrollView;
    _MacLCWatchCollectionView *_collectionView;
    NSCollectionViewDiffableDataSource<NSString *, NSString *> *_dataSource;

    NSMutableArray<NSString *> *_activeSections;
    NSMutableDictionary<NSString *, MacLCAddonItem *> *_itemsByID;
    NSMutableDictionary<NSString *, NSNumber *> *_ranksByID;
    NSMutableDictionary<NSString *, NSString *> *_shelfTitlesBySectionID;
    NSMutableDictionary<NSString *, NSString *> *_shelfSubtitlesBySectionID;
    NSMutableDictionary<NSString *, NSString *> *_shelfActionTitlesBySectionID;
    NSMutableDictionary<NSString *, void (^)(void)> *_shelfActionsBySectionID;

    NSMutableArray<MacLCAddonTitleCatalog *> *_matchingCatalogs;
    NSMutableArray<MacLCAddonTitleCatalog *> *_topCatalogs;
    MacLCAddonTitleCatalog *_topCatalog;

    NSMutableDictionary<NSString *, NSArray<MacLCAddonItem *> *> *_catalogItems;
    NSMutableDictionary<NSString *, NSNumber *> *_catalogFailed;
    NSMutableDictionary<NSString *, NSArray<MacLCAddonItem *> *> *_topItemsByCatalogKey;

    NSMutableDictionary<NSString *, NSNumber *> *_genreShelvesState;
    NSMutableDictionary<NSString *, NSArray<MacLCAddonItem *> *> *_genreItems;

    NSMutableArray<MacLCAddonRequest *> *_activeRequests;

    NSArray<MacLCAddonItem *> *_featuredItems;
    NSArray<NSString *> *_featuredEyebrows;
    BOOL _hasFiredFeaturedLoadedHandler;
    MacLCWatchHeroView *_heroItemView;

    NSUInteger _failedCatalogCount;
    NSUInteger _completedCatalogCount;
    NSError *_lastError;

    BOOL _isSearching;
    NSString *_pendingSearchQuery;
    NSString *_currentSearchQuery;
    NSUInteger _searchGeneration;
    MacLCAddonRequest *_searchRequest;
    NSPoint _savedBrowseScrollPoint;

    NSView *_emptyStateContainer;
}

@property (nonatomic, weak) MacLCWatchSectionViewController *section;

@end

@implementation MacLCWatchBrowseViewController

- (instancetype)initWithSection:(MacLCWatchSectionViewController *)section
{
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _section = section;
        _activeSections = [NSMutableArray array];
        _itemsByID = [NSMutableDictionary dictionary];
        _ranksByID = [NSMutableDictionary dictionary];
        _shelfTitlesBySectionID = [NSMutableDictionary dictionary];
        _shelfSubtitlesBySectionID = [NSMutableDictionary dictionary];
        _shelfActionTitlesBySectionID = [NSMutableDictionary dictionary];
        _shelfActionsBySectionID = [NSMutableDictionary dictionary];

        _matchingCatalogs = [NSMutableArray array];
        _topCatalogs = [NSMutableArray array];
        _catalogItems = [NSMutableDictionary dictionary];
        _catalogFailed = [NSMutableDictionary dictionary];
        _topItemsByCatalogKey = [NSMutableDictionary dictionary];

        _genreShelvesState = [NSMutableDictionary dictionary];
        _genreItems = [NSMutableDictionary dictionary];

        _activeRequests = [NSMutableArray array];
        _featuredItems = @[];
        _featuredEyebrows = @[];
    }
    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    for (MacLCAddonRequest *req in _activeRequests) {
        [req cancel];
    }
    [_searchRequest cancel];
}

- (void)loadView
{
    NSView *root = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 800, 600)];
    root.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    root.wantsLayer = YES;
    self.view = root;

    _scrollView = [[NSScrollView alloc] initWithFrame:root.bounds];
    _scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    _scrollView.drawsBackground = NO;
    _scrollView.hasVerticalScroller = YES;
    _scrollView.autohidesScrollers = YES;
    _scrollView.automaticallyAdjustsContentInsets = NO;
    [root addSubview:_scrollView];

    [NSLayoutConstraint activateConstraints:@[
        [_scrollView.leadingAnchor constraintEqualToAnchor:root.leadingAnchor],
        [_scrollView.trailingAnchor constraintEqualToAnchor:root.trailingAnchor],
        [_scrollView.topAnchor constraintEqualToAnchor:root.topAnchor],
        [_scrollView.bottomAnchor constraintEqualToAnchor:root.bottomAnchor],
    ]];

    _collectionView = [[_MacLCWatchCollectionView alloc] initWithFrame:_scrollView.bounds];
    _collectionView.autoresizingMask = NSViewWidthSizable; /* a document view sized by its clip view */
    _collectionView.delegate = self;
    _collectionView.selectable = YES;
    _collectionView.allowsMultipleSelection = NO;
    _collectionView.allowsEmptySelection = YES;

    __weak typeof(self) weakSelf = self;
    _collectionView.doubleClickHandler = ^{
        [weakSelf handleSelectionActivation];
    };
    _collectionView.returnKeyHandler = ^{
        [weakSelf handleSelectionActivation];
    };

    _scrollView.documentView = _collectionView;

    NSCollectionViewCompositionalLayoutSectionProvider provider = ^NSCollectionLayoutSection * _Nullable(NSInteger sectionIndex, id<NSCollectionLayoutEnvironment> environment) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return nil;
        return [strongSelf sectionLayoutForIndex:sectionIndex environment:environment];
    };

    NSCollectionViewCompositionalLayout *layout = [[NSCollectionViewCompositionalLayout alloc] initWithSectionProvider:provider];
    _collectionView.collectionViewLayout = layout;

    [_collectionView registerClass:[_MacLCWatchHeroCollectionViewItem class]
             forItemWithIdentifier:MacLCWatchHeroItemIdentifier];
    [_collectionView registerClass:[MacLCWatchPosterItem class]
             forItemWithIdentifier:MacLCWatchPosterItemIdentifier];
    [_collectionView registerClass:[MacLCSectionHeaderView class]
        forSupplementaryViewOfKind:MacLCWatchHeaderElementKind
                    withIdentifier:MacLCSectionHeaderViewIdentifier];

    [self configureDataSource];
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(addonsDidChange:)
                                                 name:MacLCAddonsDidChangeNotification
                                               object:nil];

    /* Add-ons change their catalogs (Cinemeta adds a year every January):
     * fetch the manifests again once per launch. */
    _scrollView.contentView.postsBoundsChangedNotifications = YES;
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(clipViewBoundsDidChange:)
                                                 name:NSViewBoundsDidChangeNotification
                                               object:_scrollView.contentView];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(preferredScrollerStyleDidChange:)
                                                 name:NSPreferredScrollerStyleDidChangeNotification
                                               object:nil];

    static dispatch_once_t refreshOnce;
    dispatch_once(&refreshOnce, ^{
        [MacLCAddonStore.sharedStore refreshManifests];
    });

    [self reloadData];
}

- (void)viewDidLayout
{
    [super viewDidLayout];
    [self updateContentInsets];
}

- (void)updateContentInsets
{
    const NSEdgeInsets safe = self.view.safeAreaInsets;
    const CGFloat top = (_isSearching || _featuredItems.count == 0) ? safe.top : 0.0;
    const NSEdgeInsets insets = NSEdgeInsetsMake(top, safe.left, safe.bottom, safe.right);
    const NSEdgeInsets current = _scrollView.contentInsets;
    if (current.top != insets.top || current.left != insets.left ||
        current.bottom != insets.bottom || current.right != insets.right) {
        _scrollView.contentInsets = insets;
        _scrollView.scrollerInsets = NSEdgeInsetsMake(safe.top - top, 0.0, 0.0, 0.0);
    }

    /* The window title would sit on the picture: the section hides it then. */
    /* ...until the carousel has scrolled out from under the toolbar. */
    const CGFloat heroHeight = [MacLCWatchHeroView heightForAvailableHeight:self.view.bounds.size.height];
    const CGFloat scrolled = NSMinY(_scrollView.contentView.bounds);
    const BOOL pictureAtTop = top == 0.0 && _emptyStateContainer == nil
        && scrolled + safe.top < heroHeight;
    if (pictureAtTop != _showsPictureAtTop) {
        _showsPictureAtTop = pictureAtTop;
        [_section chromeDidChange];
    }
}

- (BOOL)showsPictureAtTop
{
    return _showsPictureAtTop;
}

- (void)clipViewBoundsDidChange:(NSNotification *)notification
{
    [self updateContentInsets];
}

- (void)preferredScrollerStyleDidChange:(NSNotification *)notification
{
    /* Shelves reserve room for always-visible scroll bars (MacLCWatchLayout). */
    [_collectionView.collectionViewLayout invalidateLayout];
}

#pragma mark - Layout

- (NSCollectionLayoutSection *)sectionLayoutForIndex:(NSInteger)sectionIndex
                                         environment:(id<NSCollectionLayoutEnvironment>)environment
{
    if (_isSearching) {
        return [MacLCWatchLayout posterGridSectionWithEnvironment:environment hasHeader:YES];
    }

    if (sectionIndex >= (NSInteger)_activeSections.count) {
        return [MacLCWatchLayout posterShelfSectionWithEnvironment:environment];
    }

    NSString *sectionID = _activeSections[sectionIndex];
    if ([sectionID isEqualToString:MacLCWatchHeroSectionIdentifier]) {
        CGFloat windowHeight = environment.container.effectiveContentSize.height;
        CGFloat heroHeight = [MacLCWatchHeroView heightForAvailableHeight:windowHeight];
        return [MacLCWatchLayout fullWidthSectionWithHeight:heroHeight];
    }
    if ([_rankedSectionIDs containsObject:sectionID]) {
        return [MacLCWatchLayout rankedPosterShelfSectionWithEnvironment:environment];
    }

    return [MacLCWatchLayout posterShelfSectionWithEnvironment:environment];
}

#pragma mark - Data Source

- (void)configureDataSource
{
    __weak typeof(self) weakSelf = self;
    _dataSource = [[NSCollectionViewDiffableDataSource alloc] initWithCollectionView:_collectionView
                                                                        itemProvider:^NSCollectionViewItem * _Nullable(NSCollectionView *collectionView, NSIndexPath *indexPath, id itemID) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return nil;

        if ([itemID isEqualToString:MacLCWatchHeroItemIdentifier]) {
            _MacLCWatchHeroCollectionViewItem *heroItem = [collectionView makeItemWithIdentifier:MacLCWatchHeroItemIdentifier forIndexPath:indexPath];
            heroItem.heroView.items = strongSelf->_featuredItems ?: @[];
            heroItem.heroView.eyebrows = strongSelf->_featuredEyebrows ?: @[];
            heroItem.heroView.detailsHandler = ^(MacLCAddonItem *item) {
                [weakSelf.section showDetailForItem:item showStreams:NO];
            };
            heroItem.heroView.playHandler = ^(MacLCAddonItem *item) {
                [weakSelf.section showDetailForItem:item showStreams:YES];
            };
            strongSelf->_heroItemView = heroItem.heroView;
            return heroItem;
        }

        MacLCWatchPosterItem *posterItem = [collectionView makeItemWithIdentifier:MacLCWatchPosterItemIdentifier forIndexPath:indexPath];
        if ([itemID containsString:@"/__placeholder__"]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wnonnull"
            NSString * const placeholderSection = [itemID componentsSeparatedByString:@"/__placeholder__"].firstObject;
            [posterItem configureWithItem:nil
                                     rank:[strongSelf->_rankedSectionIDs containsObject:placeholderSection] ? -1 : 0];
#pragma clang diagnostic pop
            posterItem.activationHandler = nil;
            return posterItem;
        }

        MacLCAddonItem *item = strongSelf->_itemsByID[itemID];
        NSNumber *rankNum = strongSelf->_ranksByID[itemID];
        NSInteger rank = rankNum ? rankNum.integerValue : 0;
        [posterItem configureWithItem:item rank:rank];
        posterItem.activationHandler = ^(MacLCAddonItem *clickedItem) {
            [weakSelf.section showDetailForItem:clickedItem showStreams:NO];
        };
        return posterItem;
    }];

    _dataSource.supplementaryViewProvider = ^NSView * _Nullable(NSCollectionView *collectionView, NSString *kind, NSIndexPath *indexPath) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf || ![kind isEqualToString:MacLCWatchHeaderElementKind]) {
            return nil;
        }

        MacLCSectionHeaderView *header = [collectionView makeSupplementaryViewOfKind:kind
                                                                      withIdentifier:MacLCSectionHeaderViewIdentifier
                                                                        forIndexPath:indexPath];
        if (indexPath.section >= (NSInteger)strongSelf->_activeSections.count) {
            return header;
        }

        NSString *sectionID = strongSelf->_activeSections[indexPath.section];
        header.title = strongSelf->_shelfTitlesBySectionID[sectionID] ?: @"";
        header.subtitle = strongSelf->_shelfSubtitlesBySectionID[sectionID];
        header.actionTitle = strongSelf->_shelfActionTitlesBySectionID[sectionID];
        header.action = strongSelf->_shelfActionsBySectionID[sectionID];
        return header;
    };
}

#pragma mark - Reload Data

- (void)reloadData
{
    for (MacLCAddonRequest *req in _activeRequests) {
        [req cancel];
    }
    [_activeRequests removeAllObjects];

    [_searchRequest cancel];
    _searchRequest = nil;

    _matchingCatalogs = [NSMutableArray array];
    for (MacLCAddonTitleCatalog *cat in MacLCAddonStore.sharedStore.titleCatalogs) {
        if (!self.section.mediaType || [cat.type isEqualToString:self.section.mediaType]) {
            [_matchingCatalogs addObject:cat];
        }
    }

    if (_matchingCatalogs.count == 0) {
        [self showNoCatalogsEmptyState];
        return;
    }

    [self hideEmptyState];
    _collectionView.hidden = NO;

    _failedCatalogCount = 0;
    _completedCatalogCount = 0;
    _lastError = nil;

    [_catalogItems removeAllObjects];
    [_catalogFailed removeAllObjects];
    [_topItemsByCatalogKey removeAllObjects];
    [_topCatalogs removeAllObjects];
    _topCatalog = nil;
    [_genreShelvesState removeAllObjects];
    [_genreItems removeAllObjects];

    for (MacLCAddonTitleCatalog *cat in _matchingCatalogs) {
        if ([cat.identifier isEqualToString:@"top"]) {
            [_topCatalogs addObject:cat];
            if (!_topCatalog) {
                _topCatalog = cat;
            }
        }
    }
    if (!_topCatalog && _matchingCatalogs.count > 0) {
        _topCatalog = _matchingCatalogs.firstObject;
        [_topCatalogs addObject:_topCatalog];
    }

    if (self.section.mediaType != nil && _topCatalog != nil) {
        for (NSString *genre in _topCatalog.genres) {
            _genreShelvesState[genre] = @(MacLCWatchShelfStateUnloaded);
        }
    }

    [self rebuildBrowseSnapshotAnimated:NO];
    [self updateContentInsets];

    for (MacLCAddonTitleCatalog *cat in _matchingCatalogs) {
        __weak typeof(self) weakSelf = self;
        MacLCAddonRequest *req = [MacLCAddonStore.sharedStore fetchTitleCatalog:cat
                                                                          genre:nil
                                                                           skip:0
                                                                     completion:^(NSArray<MacLCAddonItem *> * _Nullable items, NSError * _Nullable error) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            [strongSelf handleCatalogLoaded:cat items:items error:error];
        }];
        if (req) {
            [_activeRequests addObject:req];
        }
    }

    if (self.section.mediaType != nil && _topCatalog != nil) {
        [self prefetchGenreShelvesNearSection:0];
    }
}

- (void)handleCatalogLoaded:(MacLCAddonTitleCatalog *)catalog
                      items:(nullable NSArray<MacLCAddonItem *> *)items
                      error:(nullable NSError *)error
{
    NSString *catKey = CatalogKey(catalog);
    _completedCatalogCount++;

    if (error || items == nil) {
        _failedCatalogCount++;
        _lastError = error;
        _catalogFailed[catKey] = @YES;

        if (_failedCatalogCount == _matchingCatalogs.count) {
            [self showCantLoadAddonsEmptyState:_lastError serviceName:catalog.addon.name];
            return;
        }
    } else {
        _catalogItems[catKey] = items ?: @[];
        if ([catalog.identifier isEqualToString:@"top"] || catalog == _topCatalog) {
            _topItemsByCatalogKey[catKey] = items ?: @[];
            [self updateFeaturedCarousel];
        }
    }

    [self rebuildBrowseSnapshotAnimated:YES];
}

- (void)updateFeaturedCarousel
{
    NSMutableArray<MacLCAddonItem *> *featured = [NSMutableArray array];
    NSMutableArray<NSString *> *eyebrows = [NSMutableArray array];

    /* Six titles, taken in turn from each "top" catalog. */
    for (NSUInteger idx = 0; idx < 6; idx++) {
        for (MacLCAddonTitleCatalog *cat in _topCatalogs) {
            NSString *key = CatalogKey(cat);
            NSArray<MacLCAddonItem *> *items = _topItemsByCatalogKey[key];
            if (idx < items.count && featured.count < 6) {
                [featured addObject:items[idx]];
                NSString *typeUpper = UpperSingularTypeName(cat.type);
                NSString *catNameUpper = [cat.name uppercaseString];
                NSString *eyebrow = [NSString stringWithFormat:@"%@ %@", catNameUpper, typeUpper];
                if ([catNameUpper containsString:typeUpper]) {
                    eyebrow = catNameUpper;
                }
                [eyebrows addObject:eyebrow];
            }
        }
    }

    _featuredItems = [featured copy];
    _featuredEyebrows = [eyebrows copy];
    /* The carousel now goes under the toolbar (top inset 0). */
    [self updateContentInsets];

    if (_featuredItems.count > 0 && !_hasFiredFeaturedLoadedHandler) {
        _hasFiredFeaturedLoadedHandler = YES;
        if (self.featuredItemsLoadedHandler) {
            void (^handler)(void) = self.featuredItemsLoadedHandler;
            self.featuredItemsLoadedHandler = nil;
            handler();
        }
    }

    if (_heroItemView) {
        _heroItemView.items = _featuredItems;
        _heroItemView.eyebrows = _featuredEyebrows;
    }
}

- (void)prefetchGenreShelvesNearSection:(NSInteger)sectionIndex
{
    if (self.section.mediaType == nil || !_topCatalog) {
        return;
    }

    const NSInteger maxSection = sectionIndex + 2;
    for (NSInteger s = sectionIndex; s <= maxSection && s < (NSInteger)_activeSections.count; s++) {
        NSString *secID = _activeSections[s];
        if (![secID hasPrefix:@"genre_"]) {
            continue;
        }
        NSString *genre = [secID substringFromIndex:6];
        NSNumber *state = _genreShelvesState[genre];
        if (!state || [state integerValue] == MacLCWatchShelfStateUnloaded) {
            _genreShelvesState[genre] = @(MacLCWatchShelfStateLoading);
            __weak typeof(self) weakSelf = self;
            MacLCAddonRequest *req = [MacLCAddonStore.sharedStore fetchTitleCatalog:_topCatalog
                                                                              genre:genre
                                                                               skip:0
                                                                         completion:^(NSArray<MacLCAddonItem *> * _Nullable items, NSError * _Nullable error) {
                __strong typeof(weakSelf) strongSelf = weakSelf;
                if (!strongSelf) return;
                [strongSelf handleGenreShelfLoaded:genre items:items error:error];
            }];
            if (req) {
                [_activeRequests addObject:req];
            }
        }
    }
}

- (void)handleGenreShelfLoaded:(NSString *)genre
                         items:(nullable NSArray<MacLCAddonItem *> *)items
                         error:(nullable NSError *)error
{
    if (error || items.count == 0) {
        _genreShelvesState[genre] = @(MacLCWatchShelfStateFailed);
    } else {
        _genreShelvesState[genre] = @(MacLCWatchShelfStateLoaded);
        _genreItems[genre] = items;
    }
    [self rebuildBrowseSnapshotAnimated:YES];
}

- (void)rebuildBrowseSnapshotAnimated:(BOOL)animated
{
    if (_isSearching) {
        return;
    }

    NSDiffableDataSourceSnapshot<NSString *, NSString *> *snapshot = [[NSDiffableDataSourceSnapshot alloc] init];
    [_activeSections removeAllObjects];
    [_itemsByID removeAllObjects];
    [_ranksByID removeAllObjects];
    [_shelfTitlesBySectionID removeAllObjects];
    [_shelfSubtitlesBySectionID removeAllObjects];
    [_shelfActionTitlesBySectionID removeAllObjects];
    [_shelfActionsBySectionID removeAllObjects];

    if (_featuredItems.count > 0) {
        [_activeSections addObject:MacLCWatchHeroSectionIdentifier];
        [snapshot appendSectionsWithIdentifiers:@[MacLCWatchHeroSectionIdentifier]];
        [snapshot appendItemsWithIdentifiers:@[MacLCWatchHeroItemIdentifier] intoSectionWithIdentifier:MacLCWatchHeroSectionIdentifier];
    }

    MacLCAddon *firstAddon = MacLCAddonStore.sharedStore.installedAddons.firstObject;

    for (MacLCAddonTitleCatalog *catalog in _matchingCatalogs) {
        NSString *catKey = CatalogKey(catalog);
        if ([_catalogFailed[catKey] boolValue]) {
            continue;
        }

        NSString *sectionID = [NSString stringWithFormat:@"catalog_%@", catKey];
        [_activeSections addObject:sectionID];
        [snapshot appendSectionsWithIdentifiers:@[sectionID]];

        BOOL isTop = [catalog.identifier isEqualToString:@"top"];
        if (isTop) {
            if (_rankedSectionIDs == nil)
                _rankedSectionIDs = [NSMutableSet set];
            [_rankedSectionIDs addObject:sectionID];
        }
        NSString *title = nil;
        if (isTop) {
            title = [NSString stringWithFormat:_NS("Top 10 %@"), PluralTypeName(catalog.type)];
        } else {
            NSString *plural = PluralTypeName(catalog.type);
            title = catalog.name;
            if (plural.length > 0 && ![catalog.name.lowercaseString containsString:plural.lowercaseString]) {
                title = [NSString stringWithFormat:@"%@ %@", catalog.name, plural];
            }
        }
        _shelfTitlesBySectionID[sectionID] = title ?: @"";

        if (firstAddon && ![catalog.addon.identifier isEqualToString:firstAddon.identifier]) {
            _shelfSubtitlesBySectionID[sectionID] = catalog.addon.name;
        }

        _shelfActionTitlesBySectionID[sectionID] = _NS("See All");
        __weak typeof(self) weakSelf = self;
        _shelfActionsBySectionID[sectionID] = ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            MacLCWatchCatalogViewController *catalogVC =
                [[MacLCWatchCatalogViewController alloc] initWithSection:strongSelf.section
                                                                 catalog:catalog
                                                                   genre:nil
                                                                   title:title ?: @""];
            [strongSelf.section pushViewController:catalogVC];
        };

        NSArray<MacLCAddonItem *> *loadedItems = _catalogItems[catKey];
        if (loadedItems != nil) {
            NSArray<MacLCAddonItem *> *displayItems = (isTop && loadedItems.count > 10) ?
                [loadedItems subarrayWithRange:NSMakeRange(0, 10)] : loadedItems;

            NSMutableArray<NSString *> *itemIDs = [NSMutableArray array];
            for (NSUInteger idx = 0; idx < displayItems.count; idx++) {
                MacLCAddonItem *item = displayItems[idx];
                NSString *itemID = [NSString stringWithFormat:@"%@/%lu_%@", sectionID, (unsigned long)idx, item.identifier];
                [itemIDs addObject:itemID];
                _itemsByID[itemID] = item;
                if (isTop) {
                    _ranksByID[itemID] = @(idx + 1);
                } else {
                    _ranksByID[itemID] = @0;
                }
            }
            [snapshot appendItemsWithIdentifiers:itemIDs intoSectionWithIdentifier:sectionID];
        } else {
            NSMutableArray<NSString *> *placeholders = [NSMutableArray array];
            for (int i = 0; i < 8; i++) {
                NSString *pID = [NSString stringWithFormat:@"%@/__placeholder__%d", sectionID, i];
                [placeholders addObject:pID];
            }
            [snapshot appendItemsWithIdentifiers:placeholders intoSectionWithIdentifier:sectionID];
        }
    }

    if (self.section.mediaType != nil && _topCatalog != nil) {
        for (NSString *genre in _topCatalog.genres) {
            NSNumber *state = _genreShelvesState[genre];
            if (state != nil && [state integerValue] == MacLCWatchShelfStateFailed) {
                continue;
            }

            NSString *sectionID = [NSString stringWithFormat:@"genre_%@", genre];
            [_activeSections addObject:sectionID];
            [snapshot appendSectionsWithIdentifiers:@[sectionID]];

            NSString *title = [NSString stringWithFormat:_NS("Popular in %@"), genre];
            _shelfTitlesBySectionID[sectionID] = title;
            if (firstAddon && ![_topCatalog.addon.identifier isEqualToString:firstAddon.identifier]) {
                _shelfSubtitlesBySectionID[sectionID] = _topCatalog.addon.name;
            }

            _shelfActionTitlesBySectionID[sectionID] = _NS("See All");
            __weak typeof(self) weakSelf = self;
            _shelfActionsBySectionID[sectionID] = ^{
                __strong typeof(weakSelf) strongSelf = weakSelf;
                if (!strongSelf) return;
                MacLCWatchCatalogViewController *catalogVC =
                    [[MacLCWatchCatalogViewController alloc] initWithSection:strongSelf.section
                                                                     catalog:strongSelf->_topCatalog
                                                                       genre:genre
                                                                       title:title];
                [strongSelf.section pushViewController:catalogVC];
            };

            NSArray<MacLCAddonItem *> *genreItems = _genreItems[genre];
            if (genreItems != nil) {
                NSMutableArray<NSString *> *itemIDs = [NSMutableArray array];
                for (NSUInteger idx = 0; idx < genreItems.count; idx++) {
                    MacLCAddonItem *item = genreItems[idx];
                    NSString *itemID = [NSString stringWithFormat:@"%@/%lu_%@", sectionID, (unsigned long)idx, item.identifier];
                    [itemIDs addObject:itemID];
                    _itemsByID[itemID] = item;
                    _ranksByID[itemID] = @0;
                }
                [snapshot appendItemsWithIdentifiers:itemIDs intoSectionWithIdentifier:sectionID];
            } else {
                NSMutableArray<NSString *> *placeholders = [NSMutableArray array];
                for (int i = 0; i < 8; i++) {
                    NSString *pID = [NSString stringWithFormat:@"%@/__placeholder__%d", sectionID, i];
                    [placeholders addObject:pID];
                }
                [snapshot appendItemsWithIdentifiers:placeholders intoSectionWithIdentifier:sectionID];
            }
        }
    }

    BOOL reduceMotion = NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion;
    BOOL animate = animated && !reduceMotion && self.view.window.isVisible;
    [_dataSource applySnapshot:snapshot animatingDifferences:animate];
}

#pragma mark - Search

- (void)applySearchString:(NSString *)searchString
{
    _pendingSearchQuery = [searchString copy];
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(executeSearch) object:nil];
    NSString *trimmed = [searchString stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length < 2) {
        [self executeSearch];
    } else {
        [self performSelector:@selector(executeSearch) withObject:nil afterDelay:0.3 inModes:@[NSRunLoopCommonModes, NSDefaultRunLoopMode]];
    }
}

- (void)executeSearch
{
    NSString *trimmed = [_pendingSearchQuery stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length < 2) {
        if (_isSearching) {
            _isSearching = NO;
            _currentSearchQuery = nil;
            [_searchRequest cancel];
            _searchRequest = nil;
            [self hideEmptyState];
            _collectionView.hidden = NO;
            [self rebuildBrowseSnapshotAnimated:NO];
            [_scrollView.contentView setBoundsOrigin:_savedBrowseScrollPoint];
            [_scrollView reflectScrolledClipView:_scrollView.contentView];
            [self updateContentInsets];
        }
        return;
    }

    if (!_isSearching) {
        _isSearching = YES;
        _savedBrowseScrollPoint = _scrollView.contentView.bounds.origin;
    }

    _currentSearchQuery = trimmed;
    [_searchRequest cancel];
    _searchGeneration++;
    const NSUInteger currentGen = _searchGeneration;

    __weak typeof(self) weakSelf = self;
    _searchRequest = [MacLCAddonStore.sharedStore searchTitles:trimmed completion:^(NSArray<MacLCAddonSearchGroup *> *groups) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf || strongSelf->_searchGeneration != currentGen || !strongSelf->_isSearching) {
            return;
        }

        strongSelf->_searchRequest = nil;

        NSMutableArray<MacLCAddonSearchGroup *> *matchingGroups = [NSMutableArray array];
        NSUInteger totalItems = 0;
        for (MacLCAddonSearchGroup *group in groups) {
            if (strongSelf.section.mediaType == nil || [group.type isEqualToString:strongSelf.section.mediaType]) {
                if (group.items.count > 0) {
                    [matchingGroups addObject:group];
                    totalItems += group.items.count;
                }
            }
        }

        if (totalItems == 0) {
            [strongSelf showSearchEmptyStateWithQuery:trimmed];
        } else {
            [strongSelf hideEmptyState];
            strongSelf->_collectionView.hidden = NO;
            [strongSelf buildSearchSnapshotWithGroups:matchingGroups];
            [strongSelf updateContentInsets];
            [strongSelf->_scrollView.contentView setBoundsOrigin:NSMakePoint(0, 0)];
            [strongSelf->_scrollView reflectScrolledClipView:strongSelf->_scrollView.contentView];
        }
    }];
}

- (void)buildSearchSnapshotWithGroups:(NSArray<MacLCAddonSearchGroup *> *)groups
{
    NSDiffableDataSourceSnapshot<NSString *, NSString *> *snapshot = [[NSDiffableDataSourceSnapshot alloc] init];
    [_activeSections removeAllObjects];
    [_itemsByID removeAllObjects];
    [_ranksByID removeAllObjects];
    [_shelfTitlesBySectionID removeAllObjects];
    [_shelfSubtitlesBySectionID removeAllObjects];
    [_shelfActionTitlesBySectionID removeAllObjects];
    [_shelfActionsBySectionID removeAllObjects];

    MacLCAddon *firstAddon = MacLCAddonStore.sharedStore.installedAddons.firstObject;

    for (NSUInteger gIdx = 0; gIdx < groups.count; gIdx++) {
        MacLCAddonSearchGroup *group = groups[gIdx];
        if (group.items.count == 0) continue;

        NSString *sectionID = [NSString stringWithFormat:@"search_group_%lu", (unsigned long)gIdx];
        [_activeSections addObject:sectionID];
        [snapshot appendSectionsWithIdentifiers:@[sectionID]];

        NSString *title = nil;
        if ([group.type isEqualToString:@"movie"]) {
            title = _NS("Movies");
        } else if ([group.type isEqualToString:@"series"]) {
            title = _NS("TV Shows");
        } else if (group.catalogName.length > 0) {
            title = group.catalogName;
        } else {
            title = PluralTypeName(group.type);
        }
        _shelfTitlesBySectionID[sectionID] = title;

        if (firstAddon && ![group.addon.identifier isEqualToString:firstAddon.identifier]) {
            _shelfSubtitlesBySectionID[sectionID] = group.addon.name;
        }

        NSMutableArray<NSString *> *itemIDs = [NSMutableArray array];
        for (NSUInteger idx = 0; idx < group.items.count; idx++) {
            MacLCAddonItem *item = group.items[idx];
            NSString *itemID = [NSString stringWithFormat:@"%@/%lu_%@", sectionID, (unsigned long)idx, item.identifier];
            [itemIDs addObject:itemID];
            _itemsByID[itemID] = item;
            _ranksByID[itemID] = @0;
        }
        [snapshot appendItemsWithIdentifiers:itemIDs intoSectionWithIdentifier:sectionID];
    }

    BOOL reduceMotion = NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion;
    BOOL animate = !reduceMotion && self.view.window.isVisible;
    [_dataSource applySnapshot:snapshot animatingDifferences:animate];
}

#pragma mark - Empty States

- (void)hideEmptyState
{
    if (_emptyStateContainer) {
        [_emptyStateContainer removeFromSuperview];
        _emptyStateContainer = nil;
    }
    self.view.needsLayout = YES; /* insets and title follow (-updateContentInsets) */
}

- (void)showNoCatalogsEmptyState
{
    [self hideEmptyState];
    _collectionView.hidden = YES;

    _emptyStateContainer = [[NSView alloc] init];
    _emptyStateContainer.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_emptyStateContainer];

    [NSLayoutConstraint activateConstraints:@[
        [_emptyStateContainer.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [_emptyStateContainer.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
        [_emptyStateContainer.widthAnchor constraintLessThanOrEqualToConstant:420],
    ]];

    MacLCEmptyStateView *emptyView = [MacLCEmptyStateView emptyStateWithSymbolName:@"film.stack"
                                                                            title:_NS("No Catalogs")
                                                                          message:_NS("Install an add-on with catalogs to see movies and shows here.")];
    emptyView.translatesAutoresizingMaskIntoConstraints = NO;
    [_emptyStateContainer addSubview:emptyView];

    __weak typeof(self) weakSelf = self;
    [emptyView addButtonWithTitle:_NS("Browse Add-ons…")
                        prominent:YES
                           action:^{
        [weakSelf openAddonsSettings];
    }];

    [NSLayoutConstraint activateConstraints:@[
        [emptyView.topAnchor constraintEqualToAnchor:_emptyStateContainer.topAnchor],
        [emptyView.leadingAnchor constraintEqualToAnchor:_emptyStateContainer.leadingAnchor],
        [emptyView.trailingAnchor constraintEqualToAnchor:_emptyStateContainer.trailingAnchor],
        [emptyView.bottomAnchor constraintEqualToAnchor:_emptyStateContainer.bottomAnchor],
    ]];
}

- (void)showCantLoadAddonsEmptyState:(nullable NSError *)error serviceName:(nullable NSString *)serviceName
{
    [self hideEmptyState];
    _collectionView.hidden = YES;

    _emptyStateContainer = [[NSView alloc] init];
    _emptyStateContainer.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_emptyStateContainer];

    [NSLayoutConstraint activateConstraints:@[
        [_emptyStateContainer.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [_emptyStateContainer.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
        [_emptyStateContainer.widthAnchor constraintLessThanOrEqualToConstant:420],
    ]];

    NSString *msg = ErrorMessageForError(error, serviceName ?: _NS("Add-on"));
    MacLCEmptyStateView *emptyView = [MacLCEmptyStateView emptyStateWithSymbolName:@"wifi.exclamationmark"
                                                                            title:_NS("Can't Load Add-ons")
                                                                          message:msg];
    emptyView.translatesAutoresizingMaskIntoConstraints = NO;
    [_emptyStateContainer addSubview:emptyView];

    __weak typeof(self) weakSelf = self;
    [emptyView addButtonWithTitle:_NS("Try Again")
                        prominent:NO
                           action:^{
        [weakSelf reloadData];
    }];

    [NSLayoutConstraint activateConstraints:@[
        [emptyView.topAnchor constraintEqualToAnchor:_emptyStateContainer.topAnchor],
        [emptyView.leadingAnchor constraintEqualToAnchor:_emptyStateContainer.leadingAnchor],
        [emptyView.trailingAnchor constraintEqualToAnchor:_emptyStateContainer.trailingAnchor],
        [emptyView.bottomAnchor constraintEqualToAnchor:_emptyStateContainer.bottomAnchor],
    ]];
}

- (void)showSearchEmptyStateWithQuery:(NSString *)query
{
    [self hideEmptyState];
    _collectionView.hidden = YES;

    _emptyStateContainer = [[NSView alloc] init];
    _emptyStateContainer.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_emptyStateContainer];

    [NSLayoutConstraint activateConstraints:@[
        [_emptyStateContainer.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [_emptyStateContainer.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
        [_emptyStateContainer.widthAnchor constraintLessThanOrEqualToConstant:420],
    ]];

    NSString *title = [NSString stringWithFormat:_NS("No Results for “%@”"), query];
    MacLCEmptyStateView *emptyView = [MacLCEmptyStateView emptyStateWithSymbolName:@"magnifyingglass"
                                                                            title:title
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

- (void)openAddonsSettings
{
    MacLCSettingsWindowController *swc = VLCMain.sharedInstance.settingsWindowController;
    [swc showSettingsWindowWithLevel:NSNormalWindowLevel];
    [swc selectPaneWithIdentifier:@"addons"];
}

#pragma mark - Properties & Hooks

- (NSArray<MacLCAddonItem *> *)featuredItems
{
    return _featuredItems ?: @[];
}

- (void)setFeaturedItemsLoadedHandler:(nullable void (^)(void))featuredItemsLoadedHandler
{
    _featuredItemsLoadedHandler = [featuredItemsLoadedHandler copy];
    if (_featuredItems.count > 0 && _featuredItemsLoadedHandler != nil) {
        void (^handler)(void) = _featuredItemsLoadedHandler;
        _featuredItemsLoadedHandler = nil;
        _hasFiredFeaturedLoadedHandler = YES;
        handler();
    }
}

- (void)handleSelectionActivation
{
    NSIndexPath *indexPath = _collectionView.selectionIndexPaths.anyObject;
    if (!indexPath) return;
    NSString *itemID = [_dataSource itemIdentifierForIndexPath:indexPath];
    if (!itemID || [itemID isEqualToString:MacLCWatchHeroItemIdentifier]) return;
    MacLCAddonItem *item = _itemsByID[itemID];
    if (item) {
        [self.section showDetailForItem:item showStreams:NO];
    }
}

- (void)addonsDidChange:(NSNotification *)notification
{
    if (_isSearching) {
        [self executeSearch];
    } else {
        [self reloadData];
    }
}

#pragma mark - NSCollectionViewDelegate

- (void)collectionView:(NSCollectionView *)collectionView
willDisplaySupplementaryView:(NSView *)view
        forElementKind:(NSString *)elementKind
           atIndexPath:(NSIndexPath *)indexPath
{
    if ([elementKind isEqualToString:MacLCWatchHeaderElementKind]) {
        [self prefetchGenreShelvesNearSection:indexPath.section];
    }
}

- (void)collectionView:(NSCollectionView *)collectionView
        willDisplayItem:(NSCollectionViewItem *)item
forRepresentedObjectAtIndexPath:(NSIndexPath *)indexPath
{
    [self prefetchGenreShelvesNearSection:indexPath.section];
}

@end

#pragma mark - MacLCWatchCatalogViewController

@interface MacLCWatchCatalogViewController () <NSCollectionViewDelegate>
{
    __weak MacLCWatchSectionViewController *_section;
    MacLCAddonTitleCatalog *_catalog;
    NSString *_genre;
    NSString *_headerTitle;

    NSScrollView *_scrollView;
    _MacLCWatchCollectionView *_collectionView;
    NSCollectionViewDiffableDataSource<NSString *, NSString *> *_dataSource;

    NSMutableArray<MacLCAddonItem *> *_items;
    NSMutableSet<NSString *> *_seenItemIDs;
    NSMutableDictionary<NSString *, MacLCAddonItem *> *_itemsByID;

    MacLCAddonRequest *_currentRequest;
    BOOL _isLoadingPage;
    BOOL _hasReachedEnd;
    NSView *_emptyStateContainer;
}
@end

@implementation MacLCWatchCatalogViewController

- (instancetype)initWithSection:(MacLCWatchSectionViewController *)section
                        catalog:(MacLCAddonTitleCatalog *)catalog
                          genre:(nullable NSString *)genre
                          title:(NSString *)title
{
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _section = section;
        _catalog = catalog;
        _genre = [genre copy];
        _headerTitle = [title copy];
        self.title = title;

        _items = [NSMutableArray array];
        _seenItemIDs = [NSMutableSet set];
        _itemsByID = [NSMutableDictionary dictionary];
    }
    return self;
}

- (void)dealloc
{
    [_currentRequest cancel];
}

- (void)loadView
{
    NSView *root = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 800, 600)];
    root.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    root.wantsLayer = YES;
    self.view = root;

    _scrollView = [[NSScrollView alloc] initWithFrame:root.bounds];
    _scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    _scrollView.drawsBackground = NO;
    _scrollView.hasVerticalScroller = YES;
    _scrollView.autohidesScrollers = YES;
    _scrollView.automaticallyAdjustsContentInsets = NO;
    [root addSubview:_scrollView];

    [NSLayoutConstraint activateConstraints:@[
        [_scrollView.leadingAnchor constraintEqualToAnchor:root.leadingAnchor],
        [_scrollView.trailingAnchor constraintEqualToAnchor:root.trailingAnchor],
        [_scrollView.topAnchor constraintEqualToAnchor:root.topAnchor],
        [_scrollView.bottomAnchor constraintEqualToAnchor:root.bottomAnchor],
    ]];

    _collectionView = [[_MacLCWatchCollectionView alloc] initWithFrame:_scrollView.bounds];
    _collectionView.autoresizingMask = NSViewWidthSizable;
    _collectionView.delegate = self;
    _collectionView.selectable = YES;
    _collectionView.allowsMultipleSelection = NO;
    _collectionView.allowsEmptySelection = YES;

    __weak typeof(self) weakSelf = self;
    _collectionView.doubleClickHandler = ^{
        [weakSelf handleSelectionActivation];
    };
    _collectionView.returnKeyHandler = ^{
        [weakSelf handleSelectionActivation];
    };

    _scrollView.documentView = _collectionView;

    NSCollectionViewCompositionalLayoutSectionProvider provider = ^NSCollectionLayoutSection * _Nullable(NSInteger sectionIndex, id<NSCollectionLayoutEnvironment> environment) {
        return [MacLCWatchLayout posterGridSectionWithEnvironment:environment hasHeader:YES];
    };

    _collectionView.collectionViewLayout = [[NSCollectionViewCompositionalLayout alloc] initWithSectionProvider:provider];

    [_collectionView registerClass:[MacLCWatchPosterItem class]
             forItemWithIdentifier:MacLCWatchPosterItemIdentifier];
    [_collectionView registerClass:[MacLCSectionHeaderView class]
        forSupplementaryViewOfKind:MacLCWatchHeaderElementKind
                    withIdentifier:MacLCSectionHeaderViewIdentifier];

    [self configureDataSource];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    [self loadNextPage];
}

- (void)viewDidLayout
{
    [super viewDidLayout];
    [self updateContentInsets];
}

- (void)updateContentInsets
{
    const NSEdgeInsets safe = self.view.safeAreaInsets;
    const NSEdgeInsets current = _scrollView.contentInsets;
    if (current.top != safe.top || current.left != safe.left ||
        current.bottom != safe.bottom || current.right != safe.right) {
        _scrollView.contentInsets = safe;
        _scrollView.scrollerInsets = NSEdgeInsetsZero;
    }
}

- (void)showDetailForItem:(MacLCAddonItem *)item
{
    [_section showDetailForItem:item showStreams:NO];
}

- (void)configureDataSource
{
    __weak typeof(self) weakSelf = self;
    _dataSource = [[NSCollectionViewDiffableDataSource alloc] initWithCollectionView:_collectionView
                                                                        itemProvider:^NSCollectionViewItem * _Nullable(NSCollectionView *collectionView, NSIndexPath *indexPath, id itemID) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return nil;

        MacLCWatchPosterItem *posterItem = [collectionView makeItemWithIdentifier:MacLCWatchPosterItemIdentifier forIndexPath:indexPath];
        MacLCAddonItem *item = strongSelf->_itemsByID[itemID];
        [posterItem configureWithItem:item rank:0];
        posterItem.activationHandler = ^(MacLCAddonItem *clickedItem) {
            [weakSelf showDetailForItem:clickedItem];
        };
        return posterItem;
    }];

    _dataSource.supplementaryViewProvider = ^NSView * _Nullable(NSCollectionView *collectionView, NSString *kind, NSIndexPath *indexPath) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf || ![kind isEqualToString:MacLCWatchHeaderElementKind]) {
            return nil;
        }

        MacLCSectionHeaderView *header = [collectionView makeSupplementaryViewOfKind:kind
                                                                      withIdentifier:MacLCSectionHeaderViewIdentifier
                                                                        forIndexPath:indexPath];
        header.title = strongSelf->_headerTitle ?: @"";
        header.subtitle = nil;
        header.actionTitle = nil;
        header.action = nil;
        return header;
    };
}

- (void)loadNextPage
{
    if (_isLoadingPage || _hasReachedEnd) {
        return;
    }
    if (_items.count > 0 && !_catalog.supportsSkip) {
        _hasReachedEnd = YES;
        return;
    }

    _isLoadingPage = YES;
    const NSUInteger skip = _items.count;
    __weak typeof(self) weakSelf = self;
    _currentRequest = [MacLCAddonStore.sharedStore fetchTitleCatalog:_catalog
                                                               genre:_genre
                                                                skip:skip
                                                          completion:^(NSArray<MacLCAddonItem *> * _Nullable newItems, NSError * _Nullable error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;

        strongSelf->_isLoadingPage = NO;
        strongSelf->_currentRequest = nil;

        if (error || !newItems) {
            if (strongSelf->_items.count == 0) {
                [strongSelf showFailedEmptyState:error serviceName:strongSelf->_catalog.addon.name];
            } else {
                strongSelf->_hasReachedEnd = YES;
            }
            return;
        }

        if (newItems.count == 0) {
            strongSelf->_hasReachedEnd = YES;
            return;
        }

        NSUInteger freshCount = 0;
        for (MacLCAddonItem *item in newItems) {
            if (![strongSelf->_seenItemIDs containsObject:item.identifier]) {
                [strongSelf->_seenItemIDs addObject:item.identifier];
                [strongSelf->_items addObject:item];
                NSString *uniqueID = [NSString stringWithFormat:@"grid_%lu_%@", (unsigned long)strongSelf->_items.count, item.identifier];
                strongSelf->_itemsByID[uniqueID] = item;
                freshCount++;
            }
        }

        if (freshCount == 0) {
            strongSelf->_hasReachedEnd = YES;
            return;
        }

        [strongSelf hideEmptyState];
        strongSelf->_collectionView.hidden = NO;

        NSDiffableDataSourceSnapshot<NSString *, NSString *> *snapshot = [[NSDiffableDataSourceSnapshot alloc] init];
        [snapshot appendSectionsWithIdentifiers:@[@"catalog_grid"]];
        NSMutableArray<NSString *> *allIDs = [NSMutableArray array];
        for (NSUInteger i = 0; i < strongSelf->_items.count; i++) {
            MacLCAddonItem *it = strongSelf->_items[i];
            NSString *uID = [NSString stringWithFormat:@"grid_%lu_%@", (unsigned long)(i + 1), it.identifier];
            [allIDs addObject:uID];
        }
        [snapshot appendItemsWithIdentifiers:allIDs intoSectionWithIdentifier:@"catalog_grid"];

        BOOL reduceMotion = NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion;
        BOOL animate = !reduceMotion && strongSelf.view.window.isVisible;
        [strongSelf->_dataSource applySnapshot:snapshot animatingDifferences:animate];
    }];
}

- (void)hideEmptyState
{
    if (_emptyStateContainer) {
        [_emptyStateContainer removeFromSuperview];
        _emptyStateContainer = nil;
    }
}

- (void)showFailedEmptyState:(nullable NSError *)error serviceName:(nullable NSString *)serviceName
{
    [self hideEmptyState];
    _collectionView.hidden = YES;

    _emptyStateContainer = [[NSView alloc] init];
    _emptyStateContainer.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_emptyStateContainer];

    [NSLayoutConstraint activateConstraints:@[
        [_emptyStateContainer.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [_emptyStateContainer.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
        [_emptyStateContainer.widthAnchor constraintLessThanOrEqualToConstant:420],
    ]];

    NSString *msg = ErrorMessageForError(error, serviceName ?: _NS("Add-on"));
    MacLCEmptyStateView *emptyView = [MacLCEmptyStateView emptyStateWithSymbolName:@"wifi.exclamationmark"
                                                                            title:_NS("Can't Load Add-ons")
                                                                          message:msg];
    emptyView.translatesAutoresizingMaskIntoConstraints = NO;
    [_emptyStateContainer addSubview:emptyView];

    __weak typeof(self) weakSelf = self;
    [emptyView addButtonWithTitle:_NS("Try Again")
                        prominent:NO
                           action:^{
        [weakSelf loadNextPage];
    }];

    [NSLayoutConstraint activateConstraints:@[
        [emptyView.topAnchor constraintEqualToAnchor:_emptyStateContainer.topAnchor],
        [emptyView.leadingAnchor constraintEqualToAnchor:_emptyStateContainer.leadingAnchor],
        [emptyView.trailingAnchor constraintEqualToAnchor:_emptyStateContainer.trailingAnchor],
        [emptyView.bottomAnchor constraintEqualToAnchor:_emptyStateContainer.bottomAnchor],
    ]];
}

- (void)handleSelectionActivation
{
    NSIndexPath *indexPath = _collectionView.selectionIndexPaths.anyObject;
    if (!indexPath) return;
    NSString *itemID = [_dataSource itemIdentifierForIndexPath:indexPath];
    if (!itemID) return;
    MacLCAddonItem *item = _itemsByID[itemID];
    if (item) {
        [_section showDetailForItem:item showStreams:NO];
    }
}

#pragma mark - NSCollectionViewDelegate

- (void)collectionView:(NSCollectionView *)collectionView
        willDisplayItem:(NSCollectionViewItem *)item
forRepresentedObjectAtIndexPath:(NSIndexPath *)indexPath
{
    if (indexPath.item >= (NSInteger)_items.count - 8) {
        [self loadNextPage];
    }
}

@end
