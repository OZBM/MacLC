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
#import "addons/watch/MacLCExplainer.h"
#import "addons/watch/MacLCWatchDiscovery.h"
#import "addons/watch/MacLCWatchDiscoveryViews.h"
#import "addons/MacLCAddons.h"
#import "addons/watch/MacLCWatchLibrary.h"
#import "addons/watch/MacLCWatchPlayback.h"
#import "addons/watch/MacLCWatchLibraryViews.h"
#import "addons/watch/MacLCWatchLibrarySections.h"

#import "main/VLCMain.h"
#import "library/VLCLibraryWindow.h"
#import "library/VLCLibrarySegment.h"
#import "settings/MacLCSettingsWindowController.h"
#import "medialib/components/MacLCEmptyStateView.h"
#import "theme/MacLCDesign.h"
#import "extensions/NSString+Helpers.h"

static NSString * const MacLCWatchHeroItemIdentifier = @"watch_hero_item";
static NSString * const MacLCWatchServiceBarItemIdentifier = @"watch_service_bar_item";
static NSString * const MacLCWatchCollectionHeaderItemIdentifier = @"watch_collection_header_item";

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

#pragma mark - Internal Collection Items

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

@interface _MacLCWatchServiceBarCollectionViewItem : NSCollectionViewItem
@property (nonatomic, strong) MacLCWatchServiceBar *serviceBar;
@end

@implementation _MacLCWatchServiceBarCollectionViewItem

- (void)loadView
{
    _serviceBar = [[MacLCWatchServiceBar alloc] initWithFrame:NSMakeRect(0, 0, 800, [MacLCWatchServiceBar height])];
    _serviceBar.autoresizingMask = NSViewWidthSizable;
    self.view = _serviceBar;
}

@end

@interface _MacLCWatchCollectionHeaderCollectionViewItem : NSCollectionViewItem
@property (nonatomic, strong) MacLCWatchCollectionHeaderView *headerView;
@end

@implementation _MacLCWatchCollectionHeaderCollectionViewItem

- (void)loadView
{
    _headerView = [[MacLCWatchCollectionHeaderView alloc] initWithFrame:NSMakeRect(0, 0, 800, 300)];
    _headerView.autoresizingMask = NSViewWidthSizable;
    self.view = _headerView;
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
    NSMutableDictionary<NSString *, NSString *> *_shelfExplainerTopicsBySectionID;
    NSMutableDictionary<NSString *, NSString *> *_shelfActionTitlesBySectionID;
    NSMutableDictionary<NSString *, void (^)(void)> *_shelfActionsBySectionID;
    NSMutableDictionary<NSString *, NSNumber *> *_shelfShowsPagingBySectionID;

    NSMutableDictionary<NSString *, MacLCWatchCollection *> *_collectionsByID;
    NSMutableDictionary<NSString *, NSString *> *_genresByID;
    NSMutableDictionary<NSString *, MacLCWatchEntry *> *_continueEntriesByID;

    NSMapTable<NSString *, NSScrollView *> *_shelfScrollViewsBySectionID;
    NSMapTable<NSClipView *, NSString *> *_sectionIDByClipView;
    NSMutableSet<NSClipView *> *_observedShelfClipViews;

    NSString *_selectedServiceCode;
    MacLCWatchServicesSheetController *_servicesSheetController;

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
        _shelfExplainerTopicsBySectionID = [NSMutableDictionary dictionary];
        _shelfActionTitlesBySectionID = [NSMutableDictionary dictionary];
        _shelfActionsBySectionID = [NSMutableDictionary dictionary];
        _shelfShowsPagingBySectionID = [NSMutableDictionary dictionary];

        _collectionsByID = [NSMutableDictionary dictionary];
        _genresByID = [NSMutableDictionary dictionary];
        _continueEntriesByID = [NSMutableDictionary dictionary];
        _rankedSectionIDs = [NSMutableSet set];

        _shelfScrollViewsBySectionID = [NSMapTable strongToWeakObjectsMapTable];
        _sectionIDByClipView = [NSMapTable weakToStrongObjectsMapTable];
        _observedShelfClipViews = [NSMutableSet set];

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
    [_collectionView registerClass:[_MacLCWatchServiceBarCollectionViewItem class]
             forItemWithIdentifier:MacLCWatchServiceBarItemIdentifier];
    [_collectionView registerClass:[MacLCWatchContinueItem class]
             forItemWithIdentifier:MacLCWatchContinueItemIdentifier];
    [_collectionView registerClass:[MacLCWatchPosterItem class]
             forItemWithIdentifier:MacLCWatchPosterItemIdentifier];
    [_collectionView registerClass:[MacLCWatchCollectionCard class]
             forItemWithIdentifier:MacLCWatchCollectionCardIdentifier];
    [_collectionView registerClass:[MacLCWatchGenreTile class]
             forItemWithIdentifier:MacLCWatchGenreTileIdentifier];
    [_collectionView registerClass:[MacLCWatchShelfHeaderView class]
        forSupplementaryViewOfKind:MacLCWatchHeaderElementKind
                    withIdentifier:MacLCWatchShelfHeaderIdentifier];

    [self configureDataSource];
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(addonsDidChange:)
                                                 name:MacLCAddonsDidChangeNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(discoveryDidChange:)
                                                 name:MacLCWatchDiscoveryDidChangeNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(watchLibraryDidChange:)
                                                 name:MacLCWatchLibraryDidChangeNotification
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

    NSString *defaultsKey = [NSString stringWithFormat:@"MacLCWatchService.%@", self.section.sectionTitle];
    NSString *savedCode = [[NSUserDefaults standardUserDefaults] stringForKey:defaultsKey];
    if (savedCode.length > 0) {
        MacLCWatchService *service = [MacLCWatchDiscovery serviceForCode:savedCode];
        if (service && [[MacLCWatchDiscovery sharedDiscovery].activeServices containsObject:service]) {
            _selectedServiceCode = [savedCode copy];
        } else {
            _selectedServiceCode = nil;
            [[NSUserDefaults standardUserDefaults] removeObjectForKey:defaultsKey];
        }
    }

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
    CGFloat offset = NSMinY(_scrollView.contentView.bounds);
    [_heroItemView setScrollOffset:offset];
}

- (void)preferredScrollerStyleDidChange:(NSNotification *)notification
{
    for (NSString *secID in _shelfScrollViewsBySectionID) {
        NSScrollView *sv = [_shelfScrollViewsBySectionID objectForKey:secID];
        if (sv) {
            [MacLCWatchShelfScrolling configureShelfScrollView:sv];
        }
    }
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
    if ([sectionID containsString:@"hero_section"]) {
        CGFloat windowHeight = environment.container.effectiveContentSize.height;
        CGFloat heroHeight = [MacLCWatchHeroView heightForAvailableHeight:windowHeight];
        return [MacLCWatchLayout fullWidthSectionWithHeight:heroHeight];
    }
    if ([sectionID containsString:@"services_bar_section"]) {
        return [MacLCWatchLayout insetBarSectionWithHeight:[MacLCWatchServiceBar height]];
    }
    if ([sectionID containsString:@"continue_section"]) {
        return [MacLCWatchLayout continueShelfSectionWithEnvironment:environment];
    }
    if ([sectionID containsString:@"edit_section"]) {
        return [MacLCWatchLayout collectionShelfSectionWithEnvironment:environment];
    }
    if ([sectionID containsString:@"genre_tiles_section"]) {
        return [MacLCWatchLayout genreShelfSectionWithEnvironment:environment];
    }
    if ([_rankedSectionIDs containsObject:sectionID]) {
        return [MacLCWatchLayout rankedPosterShelfSectionWithEnvironment:environment];
    }

    return [MacLCWatchLayout posterShelfSectionWithEnvironment:environment];
}

- (CGFloat)itemPitchForSectionID:(NSString *)sectionID
{
    if ([sectionID containsString:@"continue_section"]) {
        return 300.0 + 20.0;
    } else if ([sectionID containsString:@"edit_section"]) {
        return 340.0 + 20.0;
    } else if ([sectionID containsString:@"genre_tiles_section"]) {
        return 196.0 + 16.0;
    } else if ([_rankedSectionIDs containsObject:sectionID]) {
        return 220.0 + 20.0;
    }
    return 168.0 + 20.0;
}

#pragma mark - Data Source

- (void)configureDataSource
{
    __weak typeof(self) weakSelf = self;
    _dataSource = [[NSCollectionViewDiffableDataSource alloc] initWithCollectionView:_collectionView
                                                                        itemProvider:^NSCollectionViewItem * _Nullable(NSCollectionView *collectionView, NSIndexPath *indexPath, id itemID) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return nil;

        if ([itemID containsString:@"hero_item"]) {
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
            [strongSelf->_heroItemView setScrollOffset:NSMinY(strongSelf->_scrollView.contentView.bounds)];
            return heroItem;
        }

        if ([itemID containsString:@"services_bar_item"]) {
            _MacLCWatchServiceBarCollectionViewItem *barItem = [collectionView makeItemWithIdentifier:MacLCWatchServiceBarItemIdentifier forIndexPath:indexPath];
            barItem.serviceBar.services = [MacLCWatchDiscovery sharedDiscovery].activeServices ?: @[];
            barItem.serviceBar.selectedCode = strongSelf->_selectedServiceCode;
            barItem.serviceBar.selectionHandler = ^(NSString * _Nullable code) {
                [weakSelf handleServiceSelection:code];
            };
            barItem.serviceBar.chooseServicesHandler = ^{
                [weakSelf handleChooseServices];
            };
            return barItem;
        }

        if ([itemID containsString:@"continue/"]) {
            MacLCWatchContinueItem *cItem = [collectionView makeItemWithIdentifier:MacLCWatchContinueItemIdentifier forIndexPath:indexPath];
            MacLCWatchEntry *entry = strongSelf->_continueEntriesByID[itemID];
            if (entry) {
                [cItem configureWithEntry:entry];
            }
            cItem.showsLastPlayed = NO;
            cItem.activationHandler = ^(MacLCWatchEntry *e) {
                MacLCWatchResumeEntry(e, weakSelf.section);
            };
            cItem.detailsHandler = ^(MacLCWatchEntry *e) {
                [weakSelf.section showDetailForItem:e.item showStreams:NO];
            };
            return cItem;
        }

        if ([itemID containsString:@"edit/"]) {
            MacLCWatchCollectionCard *card = [collectionView makeItemWithIdentifier:MacLCWatchCollectionCardIdentifier forIndexPath:indexPath];
            MacLCWatchCollection *coll = strongSelf->_collectionsByID[itemID];
            NSArray<MacLCAddonItem *> *resolved = coll ? [[MacLCWatchDiscovery sharedDiscovery] resolvedItemsForCollection:coll] : nil;
            if (coll) {
                [card configureWithCollection:coll items:resolved];
            }
            card.activationHandler = ^(MacLCWatchCollection *c) {
                __strong typeof(weakSelf) currentSelf = weakSelf;
                if (!currentSelf) return;
                MacLCWatchCollectionViewController *vc = [[MacLCWatchCollectionViewController alloc] initWithSection:currentSelf.section collection:c];
                [currentSelf.section pushViewController:vc];
            };
            return card;
        }

        if ([itemID containsString:@"genre_tile/"]) {
            MacLCWatchGenreTile *tile = [collectionView makeItemWithIdentifier:MacLCWatchGenreTileIdentifier forIndexPath:indexPath];
            NSString *genre = strongSelf->_genresByID[itemID];
            if (genre) {
                NSArray<MacLCAddonItem *> *posters = [strongSelf postersForGenre:genre];
                [tile configureWithGenre:genre posters:posters];
            }
            tile.activationHandler = ^(NSString *g) {
                [weakSelf handleGenreTileActivated:g];
            };
            return tile;
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

        MacLCWatchShelfHeaderView *header = [collectionView makeSupplementaryViewOfKind:kind
                                                                      withIdentifier:MacLCWatchShelfHeaderIdentifier
                                                                        forIndexPath:indexPath];
        if (indexPath.section >= (NSInteger)strongSelf->_activeSections.count) {
            return header;
        }

        NSString *sectionID = strongSelf->_activeSections[indexPath.section];
        header.title = strongSelf->_shelfTitlesBySectionID[sectionID] ?: @"";
        header.subtitle = strongSelf->_shelfSubtitlesBySectionID[sectionID];
        header.explainerTopic = strongSelf->_shelfExplainerTopicsBySectionID[sectionID];
        header.actionTitle = strongSelf->_shelfActionTitlesBySectionID[sectionID];
        header.action = strongSelf->_shelfActionsBySectionID[sectionID];

        BOOL showsPaging = [strongSelf->_shelfShowsPagingBySectionID[sectionID] boolValue];
        header.showsPaging = showsPaging;

        if (showsPaging) {
            NSScrollView *shelfScrollView = [strongSelf->_shelfScrollViewsBySectionID objectForKey:sectionID];
            if (shelfScrollView) {
                header.canPageBack = [MacLCWatchShelfScrolling shelf:shelfScrollView canScrollInDirection:-1];
                header.canPageForward = [MacLCWatchShelfScrolling shelf:shelfScrollView canScrollInDirection:1];
            } else {
                header.canPageBack = NO;
                header.canPageForward = YES;
            }

            header.pageHandler = ^(NSInteger direction) {
                __strong typeof(weakSelf) currentSelf = weakSelf;
                if (!currentSelf) return;
                NSScrollView *sv = [currentSelf->_shelfScrollViewsBySectionID objectForKey:sectionID];
                if (sv) {
                    CGFloat pitch = [currentSelf itemPitchForSectionID:sectionID];
                    [MacLCWatchShelfScrolling scrollShelf:sv direction:direction itemPitch:pitch];
                }
            };
        } else {
            header.pageHandler = nil;
        }

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
    MacLCAddon *servicesAddon = [MacLCWatchDiscovery sharedDiscovery].servicesAddon;
    for (MacLCAddonTitleCatalog *cat in MacLCAddonStore.sharedStore.titleCatalogs) {
        if (!self.section.mediaType || [cat.type isEqualToString:self.section.mediaType]) {
            if ((servicesAddon && [cat.addon.identifier isEqualToString:servicesAddon.identifier]) ||
                [cat.addon.identifier isEqualToString:@"pw.ers.netflix-catalog"]) {
                continue;
            }
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

    if (_selectedServiceCode != nil) {
        MacLCWatchService *service = [MacLCWatchDiscovery serviceForCode:_selectedServiceCode];
        if (service) {
            [self ensureServiceCatalogsLoaded:service];
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

    if (self.section.mediaType != nil && _topCatalog != nil && _selectedServiceCode == nil) {
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
            if (_selectedServiceCode == nil) {
                [self updateFeaturedCarousel];
            }
        }
    }

    [self rebuildBrowseSnapshotAnimated:YES];
}

- (void)updateFeaturedCarousel
{
    NSMutableArray<MacLCAddonItem *> *featured = [NSMutableArray array];
    NSMutableArray<NSString *> *eyebrows = [NSMutableArray array];

    if (_selectedServiceCode != nil) {
        MacLCWatchService *service = [MacLCWatchDiscovery serviceForCode:_selectedServiceCode];
        if (service) {
            NSArray<MacLCAddonItem *> *serviceItems = [self itemsForService:service];
            NSString *serviceEyebrow = [NSString stringWithFormat:@"POPULAR ON %@", service.name.uppercaseString];
            for (NSUInteger idx = 0; idx < 6 && idx < serviceItems.count; idx++) {
                [featured addObject:serviceItems[idx]];
                [eyebrows addObject:serviceEyebrow];
            }
        }
    } else {
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
    }

    _featuredItems = [featured copy];
    _featuredEyebrows = [eyebrows copy];
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
        [_heroItemView setScrollOffset:NSMinY(_scrollView.contentView.bounds)];
    }
}

#pragma mark - Services Scope

- (NSArray<MacLCAddonItem *> *)itemsForService:(MacLCWatchService *)service
{
    if (!service) return @[];
    if (self.section.mediaType != nil) {
        MacLCAddonTitleCatalog *cat = [[MacLCWatchDiscovery sharedDiscovery] catalogForService:service type:self.section.mediaType];
        return cat ? (_catalogItems[CatalogKey(cat)] ?: @[]) : @[];
    } else {
        MacLCAddonTitleCatalog *movieCat = [[MacLCWatchDiscovery sharedDiscovery] catalogForService:service type:@"movie"];
        MacLCAddonTitleCatalog *seriesCat = [[MacLCWatchDiscovery sharedDiscovery] catalogForService:service type:@"series"];
        NSArray<MacLCAddonItem *> *movies = movieCat ? (_catalogItems[CatalogKey(movieCat)] ?: @[]) : @[];
        NSArray<MacLCAddonItem *> *series = seriesCat ? (_catalogItems[CatalogKey(seriesCat)] ?: @[]) : @[];
        NSMutableArray<MacLCAddonItem *> *combined = [NSMutableArray arrayWithCapacity:movies.count + series.count];
        NSUInteger maxCount = MAX(movies.count, series.count);
        for (NSUInteger i = 0; i < maxCount; i++) {
            if (i < movies.count) [combined addObject:movies[i]];
            if (i < series.count) [combined addObject:series[i]];
        }
        return [combined copy];
    }
}

- (BOOL)isServiceLoaded:(MacLCWatchService *)service
{
    if (!service) return YES;
    if (self.section.mediaType != nil) {
        MacLCAddonTitleCatalog *cat = [[MacLCWatchDiscovery sharedDiscovery] catalogForService:service type:self.section.mediaType];
        return cat == nil || _catalogItems[CatalogKey(cat)] != nil || [_catalogFailed[CatalogKey(cat)] boolValue];
    } else {
        MacLCAddonTitleCatalog *movieCat = [[MacLCWatchDiscovery sharedDiscovery] catalogForService:service type:@"movie"];
        MacLCAddonTitleCatalog *seriesCat = [[MacLCWatchDiscovery sharedDiscovery] catalogForService:service type:@"series"];
        BOOL movieDone = movieCat == nil || _catalogItems[CatalogKey(movieCat)] != nil || [_catalogFailed[CatalogKey(movieCat)] boolValue];
        BOOL seriesDone = seriesCat == nil || _catalogItems[CatalogKey(seriesCat)] != nil || [_catalogFailed[CatalogKey(seriesCat)] boolValue];
        return movieDone && seriesDone;
    }
}

- (void)ensureServiceCatalogsLoaded:(MacLCWatchService *)service
{
    if (!service) return;
    NSMutableArray<MacLCAddonTitleCatalog *> *catalogsToFetch = [NSMutableArray array];
    if (self.section.mediaType != nil) {
        MacLCAddonTitleCatalog *cat = [[MacLCWatchDiscovery sharedDiscovery] catalogForService:service type:self.section.mediaType];
        if (cat && _catalogItems[CatalogKey(cat)] == nil && ![_catalogFailed[CatalogKey(cat)] boolValue]) {
            [catalogsToFetch addObject:cat];
        }
    } else {
        MacLCAddonTitleCatalog *movieCat = [[MacLCWatchDiscovery sharedDiscovery] catalogForService:service type:@"movie"];
        if (movieCat && _catalogItems[CatalogKey(movieCat)] == nil && ![_catalogFailed[CatalogKey(movieCat)] boolValue]) {
            [catalogsToFetch addObject:movieCat];
        }
        MacLCAddonTitleCatalog *seriesCat = [[MacLCWatchDiscovery sharedDiscovery] catalogForService:service type:@"series"];
        if (seriesCat && _catalogItems[CatalogKey(seriesCat)] == nil && ![_catalogFailed[CatalogKey(seriesCat)] boolValue]) {
            [catalogsToFetch addObject:seriesCat];
        }
    }

    for (MacLCAddonTitleCatalog *cat in catalogsToFetch) {
        __weak typeof(self) weakSelf = self;
        MacLCAddonRequest *req = [MacLCAddonStore.sharedStore fetchTitleCatalog:cat
                                                                          genre:nil
                                                                           skip:0
                                                                     completion:^(NSArray<MacLCAddonItem *> * _Nullable items, NSError * _Nullable error) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            NSString *catKey = CatalogKey(cat);
            if (error || items == nil) {
                strongSelf->_catalogFailed[catKey] = @YES;
            } else {
                strongSelf->_catalogItems[catKey] = items ?: @[];
            }
            if ([strongSelf->_selectedServiceCode isEqualToString:service.code]) {
                [strongSelf updateFeaturedCarousel];
                [strongSelf rebuildBrowseSnapshotAnimated:YES];
            }
        }];
        if (req) {
            [_activeRequests addObject:req];
        }
    }
}

- (void)handleServiceSelection:(nullable NSString *)code
{
    if ((code == nil && _selectedServiceCode == nil) ||
        [code isEqualToString:_selectedServiceCode]) {
        return;
    }

    if (_selectedServiceCode == nil) {
        _savedBrowseScrollPoint = _scrollView.contentView.bounds.origin;
    }

    _selectedServiceCode = [code copy];

    NSString *defaultsKey = [NSString stringWithFormat:@"MacLCWatchService.%@", self.section.sectionTitle];
    if (_selectedServiceCode) {
        [[NSUserDefaults standardUserDefaults] setObject:_selectedServiceCode forKey:defaultsKey];
    } else {
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:defaultsKey];
    }

    if (_selectedServiceCode != nil) {
        MacLCWatchService *service = [MacLCWatchDiscovery serviceForCode:_selectedServiceCode];
        if (service) {
            [self ensureServiceCatalogsLoaded:service];
        }
    }

    [self updateFeaturedCarousel];

    BOOL reduceMotion = NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion;
    if (reduceMotion) {
        [self applyScopeChange];
    } else {
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
            context.duration = 0.1;
            self->_collectionView.animator.alphaValue = 0.0;
        } completionHandler:^{
            [self applyScopeChange];
            [NSAnimationContext runAnimationGroup:^(NSAnimationContext *ctx2) {
                ctx2.duration = 0.1;
                self->_collectionView.animator.alphaValue = 1.0;
            }];
        }];
    }
}

- (void)applyScopeChange
{
    [_shelfScrollViewsBySectionID removeAllObjects];
    [_sectionIDByClipView removeAllObjects];

    [self rebuildBrowseSnapshotAnimated:NO];
    if (_selectedServiceCode == nil) {
        [_scrollView.contentView setBoundsOrigin:_savedBrowseScrollPoint];
        [_scrollView reflectScrolledClipView:_scrollView.contentView];
    } else {
        [_scrollView.contentView setBoundsOrigin:NSMakePoint(0, 0)];
        [_scrollView reflectScrolledClipView:_scrollView.contentView];
    }
    [self updateContentInsets];
    CGFloat offset = NSMinY(_scrollView.contentView.bounds);
    [_heroItemView setScrollOffset:offset];
}

- (void)handleChooseServices
{
    NSWindow *window = self.view.window;
    if (!window) return;
    _servicesSheetController = [[MacLCWatchServicesSheetController alloc] init];
    __weak typeof(self) weakSelf = self;
    [_servicesSheetController beginSheetModalForWindow:window completion:^(BOOL saved) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        strongSelf->_servicesSheetController = nil;
        if (saved) {
            [strongSelf reloadData];
        }
    }];
}

#pragma mark - Prefetching & Genres

- (void)prefetchGenreShelvesNearSection:(NSInteger)sectionIndex
{
    if (self.section.mediaType == nil || !_topCatalog || _selectedServiceCode != nil) {
        return;
    }

    const NSInteger maxSection = sectionIndex + 2;
    for (NSInteger s = sectionIndex; s <= maxSection && s < (NSInteger)_activeSections.count; s++) {
        NSString *secID = _activeSections[s];
        if (![secID containsString:@"popular_genre_"]) {
            continue;
        }
        NSRange r = [secID rangeOfString:@"popular_genre_"];
        NSString *genre = [secID substringFromIndex:r.location + r.length];
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

- (NSArray<MacLCAddonItem *> *)postersForGenre:(NSString *)genre
{
    NSMutableArray<MacLCAddonItem *> *posters = [NSMutableArray arrayWithCapacity:2];
    for (NSArray<MacLCAddonItem *> *catalogItems in _catalogItems.allValues) {
        for (MacLCAddonItem *item in catalogItems) {
            for (NSString *g in item.genres) {
                if ([g caseInsensitiveCompare:genre] == NSOrderedSame) {
                    [posters addObject:item];
                    break;
                }
            }
            if (posters.count >= 2) {
                return [posters copy];
            }
        }
    }
    return [posters copy];
}

- (void)handleGenreTileActivated:(NSString *)genre
{
    if (!_topCatalog) {
        return;
    }
    NSString *title = nil;
    if ([self.section.mediaType isEqualToString:@"series"]) {
        title = [NSString stringWithFormat:_NS("%@ Shows"), genre];
    } else {
        title = [NSString stringWithFormat:_NS("%@ Movies"), genre];
    }
    MacLCWatchCatalogViewController *catalogVC =
        [[MacLCWatchCatalogViewController alloc] initWithSection:self.section
                                                         catalog:_topCatalog
                                                           genre:genre
                                                           title:title];
    [self.section pushViewController:catalogVC];
}

#pragma mark - Browse Snapshot Rebuilding

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
    [_shelfExplainerTopicsBySectionID removeAllObjects];
    [_shelfActionTitlesBySectionID removeAllObjects];
    [_shelfActionsBySectionID removeAllObjects];
    [_shelfShowsPagingBySectionID removeAllObjects];
    [_collectionsByID removeAllObjects];
    [_genresByID removeAllObjects];
    [_continueEntriesByID removeAllObjects];
    [_rankedSectionIDs removeAllObjects];

    NSString *scopePrefix = _selectedServiceCode ? [NSString stringWithFormat:@"service_%@:", _selectedServiceCode] : @"all:";
    MacLCAddon *firstAddon = MacLCAddonStore.sharedStore.installedAddons.firstObject;

    /* 1. Carousel */
    if (_featuredItems.count > 0) {
        NSString *heroSectionID = [NSString stringWithFormat:@"%@hero_section", scopePrefix];
        [_activeSections addObject:heroSectionID];
        [snapshot appendSectionsWithIdentifiers:@[heroSectionID]];
        NSString *heroItemID = [NSString stringWithFormat:@"%@hero_item", scopePrefix];
        [snapshot appendItemsWithIdentifiers:@[heroItemID] intoSectionWithIdentifier:heroSectionID];
    }

    /* 2. Services bar */
    NSString *barSectionID = [NSString stringWithFormat:@"%@services_bar_section", scopePrefix];
    [_activeSections addObject:barSectionID];
    [snapshot appendSectionsWithIdentifiers:@[barSectionID]];
    NSString *barItemID = [NSString stringWithFormat:@"%@services_bar_item", scopePrefix];
    [snapshot appendItemsWithIdentifiers:@[barItemID] intoSectionWithIdentifier:barSectionID];

    /* Continue Watching shelf (shown even while scoped to a service) */
    NSArray<MacLCWatchEntry *> *continueEntries = [self filteredContinueWatchingEntries];
    if (continueEntries.count > 0) {
        NSString *continueSectionID = [NSString stringWithFormat:@"%@continue_section", scopePrefix];
        [_activeSections addObject:continueSectionID];
        [snapshot appendSectionsWithIdentifiers:@[continueSectionID]];
        _shelfTitlesBySectionID[continueSectionID] = _NS("Continue Watching");
        _shelfShowsPagingBySectionID[continueSectionID] = @YES;

        NSMutableArray<NSString *> *itemIDs = [NSMutableArray arrayWithCapacity:continueEntries.count];
        for (MacLCWatchEntry *entry in continueEntries) {
            NSString *itemID = [NSString stringWithFormat:@"%@continue/%@", scopePrefix, entry.identifier];
            [itemIDs addObject:itemID];
            _continueEntriesByID[itemID] = entry;
        }
        [snapshot appendItemsWithIdentifiers:itemIDs intoSectionWithIdentifier:continueSectionID];
    }

    /* Favorites shelf (hidden while a service scope is selected) */
    if (_selectedServiceCode == nil) {
        NSArray<MacLCWatchEntry *> *favEntries = [self filteredFavoriteEntries];
        if (favEntries.count > 0) {
            NSString *favSectionID = [NSString stringWithFormat:@"%@favorites_section", scopePrefix];
            [_activeSections addObject:favSectionID];
            [snapshot appendSectionsWithIdentifiers:@[favSectionID]];
            _shelfTitlesBySectionID[favSectionID] = _NS("Favorites");
            _shelfActionTitlesBySectionID[favSectionID] = _NS("See All");
            _shelfActionsBySectionID[favSectionID] = ^{
                [VLCMain sharedInstance].libraryWindow.librarySegmentType = VLCLibraryWatchFavoritesSegmentType;
            };
            _shelfShowsPagingBySectionID[favSectionID] = @YES;

            NSMutableArray<NSString *> *itemIDs = [NSMutableArray arrayWithCapacity:favEntries.count];
            for (NSUInteger idx = 0; idx < favEntries.count; idx++) {
                MacLCWatchEntry *entry = favEntries[idx];
                NSString *itemID = [NSString stringWithFormat:@"%@fav/%lu_%@", scopePrefix, (unsigned long)idx, entry.identifier];
                [itemIDs addObject:itemID];
                _itemsByID[itemID] = entry.item;
                _ranksByID[itemID] = @0;
            }
            [snapshot appendItemsWithIdentifiers:itemIDs intoSectionWithIdentifier:favSectionID];
        }
    }

    if (_selectedServiceCode != nil) {
        /* Scoped to a service */
        MacLCWatchService *service = [MacLCWatchDiscovery serviceForCode:_selectedServiceCode];
        if (service) {
            NSString *topSectionID = [NSString stringWithFormat:@"%@top_service", scopePrefix];
            [_activeSections addObject:topSectionID];
            [snapshot appendSectionsWithIdentifiers:@[topSectionID]];
            [_rankedSectionIDs addObject:topSectionID];

            NSString *topTitle = [NSString stringWithFormat:_NS("Top on %@"), service.name];
            _shelfTitlesBySectionID[topSectionID] = topTitle;
            _shelfShowsPagingBySectionID[topSectionID] = @YES;

            MacLCAddonTitleCatalog *serviceCat = nil;
            if (self.section.mediaType != nil) {
                serviceCat = [[MacLCWatchDiscovery sharedDiscovery] catalogForService:service type:self.section.mediaType];
            }
            if (serviceCat != nil) {
                _shelfActionTitlesBySectionID[topSectionID] = _NS("See All");
                __weak typeof(self) weakSelf = self;
                _shelfActionsBySectionID[topSectionID] = ^{
                    __strong typeof(weakSelf) strongSelf = weakSelf;
                    if (!strongSelf) return;
                    MacLCWatchCatalogViewController *catalogVC =
                        [[MacLCWatchCatalogViewController alloc] initWithSection:strongSelf.section
                                                                         catalog:serviceCat
                                                                           genre:nil
                                                                           title:topTitle];
                    [strongSelf.section pushViewController:catalogVC];
                };
            }

            NSArray<MacLCAddonItem *> *allServiceItems = [self itemsForService:service];
            BOOL isLoaded = [self isServiceLoaded:service];
            if (allServiceItems.count > 0) {
                NSUInteger count = MIN(allServiceItems.count, 20);
                NSMutableArray<NSString *> *itemIDs = [NSMutableArray arrayWithCapacity:count];
                for (NSUInteger idx = 0; idx < count; idx++) {
                    MacLCAddonItem *item = allServiceItems[idx];
                    NSString *itemID = [NSString stringWithFormat:@"%@/%lu_%@", topSectionID, (unsigned long)idx, item.identifier];
                    [itemIDs addObject:itemID];
                    _itemsByID[itemID] = item;
                    if (idx < 10) {
                        _ranksByID[itemID] = @(idx + 1);
                    } else {
                        _ranksByID[itemID] = @0;
                    }
                }
                [snapshot appendItemsWithIdentifiers:itemIDs intoSectionWithIdentifier:topSectionID];
            } else if (!isLoaded) {
                NSMutableArray<NSString *> *placeholders = [NSMutableArray arrayWithCapacity:8];
                for (int i = 0; i < 8; i++) {
                    NSString *pID = [NSString stringWithFormat:@"%@/__placeholder__%d", topSectionID, i];
                    [placeholders addObject:pID];
                }
                [snapshot appendItemsWithIdentifiers:placeholders intoSectionWithIdentifier:topSectionID];
            }

            /* Genre shelves for service */
            if (allServiceItems.count > 0) {
                NSArray<NSString *> *genres = [[MacLCWatchDiscovery sharedDiscovery] genresForMediaType:self.section.mediaType];
                for (NSString *genre in genres) {
                    NSArray<MacLCAddonItem *> *matched = [MacLCWatchDiscovery items:allServiceItems matchingGenre:genre];
                    if (matched.count >= 4) {
                        NSString *sectionID = [NSString stringWithFormat:@"%@service_genre_%@", scopePrefix, genre];
                        [_activeSections addObject:sectionID];
                        [snapshot appendSectionsWithIdentifiers:@[sectionID]];

                        _shelfTitlesBySectionID[sectionID] = [NSString stringWithFormat:@"%@ · %@", service.name, genre];
                        _shelfShowsPagingBySectionID[sectionID] = @YES;

                        NSMutableArray<NSString *> *itemIDs = [NSMutableArray arrayWithCapacity:matched.count];
                        for (NSUInteger idx = 0; idx < matched.count; idx++) {
                            MacLCAddonItem *item = matched[idx];
                            NSString *itemID = [NSString stringWithFormat:@"%@/%lu_%@", sectionID, (unsigned long)idx, item.identifier];
                            [itemIDs addObject:itemID];
                            _itemsByID[itemID] = item;
                            _ranksByID[itemID] = @0;
                        }
                        [snapshot appendItemsWithIdentifiers:itemIDs intoSectionWithIdentifier:sectionID];
                    }
                }
            }
        }
    } else {
        /* Unscoped ("All") */

        /* 3. The Edit */
        NSString *editSectionID = [NSString stringWithFormat:@"%@edit_section", scopePrefix];
        NSArray<MacLCWatchCollection *> *collections = [[MacLCWatchDiscovery sharedDiscovery] editForDate:[NSDate date]
                                                                                                mediaType:self.section.mediaType
                                                                                                    count:3];
        if (collections.count > 0) {
            [_activeSections addObject:editSectionID];
            [snapshot appendSectionsWithIdentifiers:@[editSectionID]];

            _shelfTitlesBySectionID[editSectionID] = _NS("The Edit");

            NSDate *nextDate = [[MacLCWatchDiscovery sharedDiscovery] nextEditDateAfter:[NSDate date]];
            NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
            [formatter setLocalizedDateFormatFromTemplate:@"MMM d"];
            NSString *dateStr = [formatter stringFromDate:nextDate];
            _shelfSubtitlesBySectionID[editSectionID] = [NSString stringWithFormat:_NS("New collections every two weeks · Next on %@"), dateStr];
            _shelfExplainerTopicsBySectionID[editSectionID] = MacLCExplainerTopicCollections;
            _shelfShowsPagingBySectionID[editSectionID] = @YES;

            NSMutableArray<NSString *> *cardIDs = [NSMutableArray arrayWithCapacity:collections.count];
            for (MacLCWatchCollection *coll in collections) {
                NSString *cardID = [NSString stringWithFormat:@"%@edit/%@", scopePrefix, coll.identifier];
                [cardIDs addObject:cardID];
                _collectionsByID[cardID] = coll;
            }
            [snapshot appendItemsWithIdentifiers:cardIDs intoSectionWithIdentifier:editSectionID];
        }

        /* 4. Top 10 */
        for (MacLCAddonTitleCatalog *topCat in _topCatalogs) {
            NSString *catKey = CatalogKey(topCat);
            if ([_catalogFailed[catKey] boolValue]) {
                continue;
            }

            NSString *sectionID = [NSString stringWithFormat:@"%@top_%@", scopePrefix, catKey];
            [_activeSections addObject:sectionID];
            [snapshot appendSectionsWithIdentifiers:@[sectionID]];
            [_rankedSectionIDs addObject:sectionID];

            NSString *title = [NSString stringWithFormat:_NS("Top 10 %@"), PluralTypeName(topCat.type)];
            _shelfTitlesBySectionID[sectionID] = title;
            if (firstAddon && ![topCat.addon.identifier isEqualToString:firstAddon.identifier]) {
                _shelfSubtitlesBySectionID[sectionID] = topCat.addon.name;
            }
            _shelfActionTitlesBySectionID[sectionID] = _NS("See All");
            __weak typeof(self) weakSelf = self;
            _shelfActionsBySectionID[sectionID] = ^{
                __strong typeof(weakSelf) strongSelf = weakSelf;
                if (!strongSelf) return;
                MacLCWatchCatalogViewController *catalogVC =
                    [[MacLCWatchCatalogViewController alloc] initWithSection:strongSelf.section
                                                                     catalog:topCat
                                                                       genre:nil
                                                                       title:title];
                [strongSelf.section pushViewController:catalogVC];
            };
            _shelfShowsPagingBySectionID[sectionID] = @YES;

            NSArray<MacLCAddonItem *> *loadedItems = _catalogItems[catKey];
            if (loadedItems != nil) {
                NSArray<MacLCAddonItem *> *displayItems = loadedItems.count > 10 ?
                    [loadedItems subarrayWithRange:NSMakeRange(0, 10)] : loadedItems;
                NSMutableArray<NSString *> *itemIDs = [NSMutableArray arrayWithCapacity:displayItems.count];
                for (NSUInteger idx = 0; idx < displayItems.count; idx++) {
                    MacLCAddonItem *item = displayItems[idx];
                    NSString *itemID = [NSString stringWithFormat:@"%@/%lu_%@", sectionID, (unsigned long)idx, item.identifier];
                    [itemIDs addObject:itemID];
                    _itemsByID[itemID] = item;
                    _ranksByID[itemID] = @(idx + 1);
                }
                [snapshot appendItemsWithIdentifiers:itemIDs intoSectionWithIdentifier:sectionID];
            } else {
                NSMutableArray<NSString *> *placeholders = [NSMutableArray arrayWithCapacity:8];
                for (int i = 0; i < 8; i++) {
                    NSString *pID = [NSString stringWithFormat:@"%@/__placeholder__%d", sectionID, i];
                    [placeholders addObject:pID];
                }
                [snapshot appendItemsWithIdentifiers:placeholders intoSectionWithIdentifier:sectionID];
            }
        }

        /* 5. Browse by Genre */
        NSArray<NSString *> *genres = [[MacLCWatchDiscovery sharedDiscovery] genresForMediaType:self.section.mediaType];
        if (genres.count > 0) {
            NSString *genreTilesSectionID = [NSString stringWithFormat:@"%@genre_tiles_section", scopePrefix];
            [_activeSections addObject:genreTilesSectionID];
            [snapshot appendSectionsWithIdentifiers:@[genreTilesSectionID]];

            _shelfTitlesBySectionID[genreTilesSectionID] = _NS("Browse by Genre");
            _shelfShowsPagingBySectionID[genreTilesSectionID] = @YES;

            NSMutableArray<NSString *> *tileIDs = [NSMutableArray arrayWithCapacity:genres.count];
            for (NSString *genre in genres) {
                NSString *tileID = [NSString stringWithFormat:@"%@genre_tile/%@", scopePrefix, genre];
                [tileIDs addObject:tileID];
                _genresByID[tileID] = genre;
            }
            [snapshot appendItemsWithIdentifiers:tileIDs intoSectionWithIdentifier:genreTilesSectionID];
        }

        /* 6. Other catalog shelves */
        MacLCAddon *servicesAddon = [MacLCWatchDiscovery sharedDiscovery].servicesAddon;
        for (MacLCAddonTitleCatalog *catalog in _matchingCatalogs) {
            if ([catalog.identifier isEqualToString:@"top"]) {
                continue;
            }
            if ((servicesAddon && [catalog.addon.identifier isEqualToString:servicesAddon.identifier]) ||
                [catalog.addon.identifier isEqualToString:@"pw.ers.netflix-catalog"]) {
                continue;
            }
            NSString *catKey = CatalogKey(catalog);
            if ([_catalogFailed[catKey] boolValue]) {
                continue;
            }

            NSString *sectionID = [NSString stringWithFormat:@"%@catalog_%@", scopePrefix, catKey];
            [_activeSections addObject:sectionID];
            [snapshot appendSectionsWithIdentifiers:@[sectionID]];

            NSString *plural = PluralTypeName(catalog.type);
            NSString *title = catalog.name;
            if (plural.length > 0 && ![catalog.name.lowercaseString containsString:plural.lowercaseString]) {
                title = [NSString stringWithFormat:@"%@ %@", catalog.name, plural];
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
            _shelfShowsPagingBySectionID[sectionID] = @YES;

            NSArray<MacLCAddonItem *> *loadedItems = _catalogItems[catKey];
            if (loadedItems != nil) {
                NSMutableArray<NSString *> *itemIDs = [NSMutableArray arrayWithCapacity:loadedItems.count];
                for (NSUInteger idx = 0; idx < loadedItems.count; idx++) {
                    MacLCAddonItem *item = loadedItems[idx];
                    NSString *itemID = [NSString stringWithFormat:@"%@/%lu_%@", sectionID, (unsigned long)idx, item.identifier];
                    [itemIDs addObject:itemID];
                    _itemsByID[itemID] = item;
                    _ranksByID[itemID] = @0;
                }
                [snapshot appendItemsWithIdentifiers:itemIDs intoSectionWithIdentifier:sectionID];
            } else {
                NSMutableArray<NSString *> *placeholders = [NSMutableArray arrayWithCapacity:8];
                for (int i = 0; i < 8; i++) {
                    NSString *pID = [NSString stringWithFormat:@"%@/__placeholder__%d", sectionID, i];
                    [placeholders addObject:pID];
                }
                [snapshot appendItemsWithIdentifiers:placeholders intoSectionWithIdentifier:sectionID];
            }
        }

        /* 7. Genre shelves (Movies and TV Shows only) */
        if (self.section.mediaType != nil && _topCatalog != nil) {
            for (NSString *genre in _topCatalog.genres) {
                NSNumber *state = _genreShelvesState[genre];
                if (state != nil && [state integerValue] == MacLCWatchShelfStateFailed) {
                    continue;
                }

                NSString *sectionID = [NSString stringWithFormat:@"%@popular_genre_%@", scopePrefix, genre];
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
                _shelfShowsPagingBySectionID[sectionID] = @YES;

                NSArray<MacLCAddonItem *> *genreItems = _genreItems[genre];
                if (genreItems != nil) {
                    NSMutableArray<NSString *> *itemIDs = [NSMutableArray arrayWithCapacity:genreItems.count];
                    for (NSUInteger idx = 0; idx < genreItems.count; idx++) {
                        MacLCAddonItem *item = genreItems[idx];
                        NSString *itemID = [NSString stringWithFormat:@"%@/%lu_%@", sectionID, (unsigned long)idx, item.identifier];
                        [itemIDs addObject:itemID];
                        _itemsByID[itemID] = item;
                        _ranksByID[itemID] = @0;
                    }
                    [snapshot appendItemsWithIdentifiers:itemIDs intoSectionWithIdentifier:sectionID];
                } else {
                    NSMutableArray<NSString *> *placeholders = [NSMutableArray arrayWithCapacity:8];
                    for (int i = 0; i < 8; i++) {
                        NSString *pID = [NSString stringWithFormat:@"%@/__placeholder__%d", sectionID, i];
                        [placeholders addObject:pID];
                    }
                    [snapshot appendItemsWithIdentifiers:placeholders intoSectionWithIdentifier:sectionID];
                }
            }
        }
    }

    BOOL reduceMotion = NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion;
    BOOL animate = animated && !reduceMotion && self.view.window.isVisible;
    [_dataSource applySnapshot:snapshot animatingDifferences:animate];
}

#pragma mark - Shelf Bounds & Paging Updates

- (void)updateHeaderPagingStateForSectionID:(NSString *)sectionID
{
    NSInteger sectionIndex = [_activeSections indexOfObject:sectionID];
    if (sectionIndex == NSNotFound) return;

    NSIndexPath *headerIndexPath = [NSIndexPath indexPathForItem:0 inSection:sectionIndex];
    MacLCWatchShelfHeaderView *header = (MacLCWatchShelfHeaderView *)[_collectionView supplementaryViewForElementKind:MacLCWatchHeaderElementKind atIndexPath:headerIndexPath];
    if ([header isKindOfClass:[MacLCWatchShelfHeaderView class]]) {
        NSScrollView *sv = [_shelfScrollViewsBySectionID objectForKey:sectionID];
        if (sv) {
            header.canPageBack = [MacLCWatchShelfScrolling shelf:sv canScrollInDirection:-1];
            header.canPageForward = [MacLCWatchShelfScrolling shelf:sv canScrollInDirection:1];
        }
    }
}

- (void)shelfClipViewBoundsDidChange:(NSNotification *)notification
{
    NSClipView *clipView = (NSClipView *)notification.object;
    if (![clipView isKindOfClass:[NSClipView class]]) return;

    NSString *sectionID = [_sectionIDByClipView objectForKey:clipView];
    if (sectionID) {
        [self updateHeaderPagingStateForSectionID:sectionID];
    }
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
    [_shelfExplainerTopicsBySectionID removeAllObjects];
    [_shelfActionTitlesBySectionID removeAllObjects];
    [_shelfActionsBySectionID removeAllObjects];
    [_shelfShowsPagingBySectionID removeAllObjects];
    [_collectionsByID removeAllObjects];
    [_genresByID removeAllObjects];
    [_rankedSectionIDs removeAllObjects];

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
        _shelfShowsPagingBySectionID[sectionID] = @NO;

        NSMutableArray<NSString *> *itemIDs = [NSMutableArray arrayWithCapacity:group.items.count];
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
    if (!itemID || [itemID containsString:@"hero_item"] || [itemID containsString:@"services_bar_item"] || [itemID containsString:@"/__placeholder__"]) return;

    if ([itemID containsString:@"continue/"]) {
        MacLCWatchEntry *entry = _continueEntriesByID[itemID];
        if (entry) {
            MacLCWatchResumeEntry(entry, _section);
        }
        return;
    }

    if ([itemID containsString:@"edit/"]) {
        MacLCWatchCollection *coll = _collectionsByID[itemID];
        if (coll) {
            MacLCWatchCollectionViewController *vc = [[MacLCWatchCollectionViewController alloc] initWithSection:_section collection:coll];
            [_section pushViewController:vc];
        }
        return;
    }

    if ([itemID containsString:@"genre_tile/"]) {
        NSString *genre = _genresByID[itemID];
        if (genre) {
            [self handleGenreTileActivated:genre];
        }
        return;
    }

    MacLCAddonItem *item = _itemsByID[itemID];
    if (item) {
        [self.section showDetailForItem:item showStreams:NO];
    }
}

- (NSArray<MacLCWatchEntry *> *)filteredContinueWatchingEntries
{
    NSArray<MacLCWatchEntry *> *all = [MacLCWatchLibrary sharedLibrary].continueWatchingEntries;
    NSString *type = self.section.mediaType;
    if (!type) {
        return all;
    }
    NSMutableArray<MacLCWatchEntry *> *filtered = [NSMutableArray arrayWithCapacity:all.count];
    for (MacLCWatchEntry *entry in all) {
        if ([entry.type isEqualToString:type]) {
            [filtered addObject:entry];
        }
    }
    return filtered;
}

- (NSArray<MacLCWatchEntry *> *)filteredFavoriteEntries
{
    NSArray<MacLCWatchEntry *> *all = [MacLCWatchLibrary sharedLibrary].favoriteEntries;
    NSString *type = self.section.mediaType;
    NSMutableArray<MacLCWatchEntry *> *filtered = [NSMutableArray arrayWithCapacity:all.count];
    for (MacLCWatchEntry *entry in all) {
        if (!type || [entry.type isEqualToString:type]) {
            [filtered addObject:entry];
            if (filtered.count == 20) {
                break;
            }
        }
    }
    return filtered;
}

- (void)watchLibraryDidChange:(NSNotification *)notification
{
    if (_isSearching) {
        return;
    }

    NSSet<NSString *> *changedTitles = notification.userInfo[MacLCWatchLibraryChangedTitlesKey];
    if (changedTitles != nil) {
        BOOL relevant = NO;
        for (MacLCWatchEntry *entry in _continueEntriesByID.allValues) {
            if ([changedTitles containsObject:entry.identifier]) {
                relevant = YES;
                break;
            }
        }
        if (!relevant) {
            for (MacLCWatchEntry *entry in [self filteredContinueWatchingEntries]) {
                if ([changedTitles containsObject:entry.identifier]) {
                    relevant = YES;
                    break;
                }
            }
        }
        if (!relevant && _selectedServiceCode == nil) {
            for (MacLCWatchEntry *entry in [self filteredFavoriteEntries]) {
                if ([changedTitles containsObject:entry.identifier]) {
                    relevant = YES;
                    break;
                }
            }
        }
        if (!relevant && _selectedServiceCode == nil) {
            for (NSString *key in _itemsByID.allKeys) {
                if ([key containsString:@"favorites_section"] || [key containsString:@"fav/"]) {
                    MacLCAddonItem *item = _itemsByID[key];
                    if ([changedTitles containsObject:item.identifier]) {
                        relevant = YES;
                        break;
                    }
                }
            }
        }
        if (!relevant) {
            return;
        }
    }

    [self updateLibraryShelvesAnimated:YES];
}

- (void)updateLibraryShelvesAnimated:(BOOL)animated
{
    NSDiffableDataSourceSnapshot<NSString *, NSString *> *snapshot = [_dataSource snapshot];
    if (snapshot.sectionIdentifiers.count == 0) {
        [self rebuildBrowseSnapshotAnimated:NO];
        return;
    }

    NSString *scopePrefix = _selectedServiceCode ? [NSString stringWithFormat:@"service_%@:", _selectedServiceCode] : @"all:";
    NSString *barSectionID = [NSString stringWithFormat:@"%@services_bar_section", scopePrefix];
    NSString *continueSectionID = [NSString stringWithFormat:@"%@continue_section", scopePrefix];
    NSString *favSectionID = [NSString stringWithFormat:@"%@favorites_section", scopePrefix];

    NSArray<MacLCWatchEntry *> *newContinue = [self filteredContinueWatchingEntries];
    if (newContinue.count > 0) {
        if ([snapshot.sectionIdentifiers containsObject:continueSectionID]) {
            NSArray<NSString *> *oldItems = [snapshot itemIdentifiersInSectionWithIdentifier:continueSectionID];
            for (NSString *oID in oldItems) {
                [_continueEntriesByID removeObjectForKey:oID];
            }
            [snapshot deleteItemsWithIdentifiers:oldItems];
        } else {
            if ([snapshot.sectionIdentifiers containsObject:barSectionID]) {
                [snapshot insertSectionsWithIdentifiers:@[continueSectionID] afterSectionWithIdentifier:barSectionID];
            } else {
                [snapshot appendSectionsWithIdentifiers:@[continueSectionID]];
            }
            NSUInteger barIdx = [_activeSections indexOfObject:barSectionID];
            if (barIdx != NSNotFound) {
                [_activeSections insertObject:continueSectionID atIndex:barIdx + 1];
            } else {
                [_activeSections addObject:continueSectionID];
            }
            _shelfTitlesBySectionID[continueSectionID] = _NS("Continue Watching");
            _shelfShowsPagingBySectionID[continueSectionID] = @YES;
        }

        NSMutableArray<NSString *> *itemIDs = [NSMutableArray arrayWithCapacity:newContinue.count];
        for (MacLCWatchEntry *entry in newContinue) {
            NSString *itemID = [NSString stringWithFormat:@"%@continue/%@", scopePrefix, entry.identifier];
            [itemIDs addObject:itemID];
            _continueEntriesByID[itemID] = entry;
        }
        [snapshot appendItemsWithIdentifiers:itemIDs intoSectionWithIdentifier:continueSectionID];
    } else {
        if ([snapshot.sectionIdentifiers containsObject:continueSectionID]) {
            NSArray<NSString *> *oldItems = [snapshot itemIdentifiersInSectionWithIdentifier:continueSectionID];
            for (NSString *oID in oldItems) {
                [_continueEntriesByID removeObjectForKey:oID];
            }
            [snapshot deleteSectionsWithIdentifiers:@[continueSectionID]];
            [_activeSections removeObject:continueSectionID];
            [_shelfTitlesBySectionID removeObjectForKey:continueSectionID];
            [_shelfShowsPagingBySectionID removeObjectForKey:continueSectionID];
        }
    }

    if (_selectedServiceCode == nil) {
        NSArray<MacLCWatchEntry *> *newFavs = [self filteredFavoriteEntries];
        if (newFavs.count > 0) {
            if ([snapshot.sectionIdentifiers containsObject:favSectionID]) {
                NSArray<NSString *> *oldItems = [snapshot itemIdentifiersInSectionWithIdentifier:favSectionID];
                for (NSString *oID in oldItems) {
                    [_itemsByID removeObjectForKey:oID];
                    [_ranksByID removeObjectForKey:oID];
                }
                [snapshot deleteItemsWithIdentifiers:oldItems];
            } else {
                if ([snapshot.sectionIdentifiers containsObject:continueSectionID]) {
                    [snapshot insertSectionsWithIdentifiers:@[favSectionID] afterSectionWithIdentifier:continueSectionID];
                    NSUInteger cIdx = [_activeSections indexOfObject:continueSectionID];
                    [_activeSections insertObject:favSectionID atIndex:cIdx + 1];
                } else if ([snapshot.sectionIdentifiers containsObject:barSectionID]) {
                    [snapshot insertSectionsWithIdentifiers:@[favSectionID] afterSectionWithIdentifier:barSectionID];
                    NSUInteger bIdx = [_activeSections indexOfObject:barSectionID];
                    [_activeSections insertObject:favSectionID atIndex:bIdx + 1];
                } else {
                    [snapshot appendSectionsWithIdentifiers:@[favSectionID]];
                    [_activeSections addObject:favSectionID];
                }

                _shelfTitlesBySectionID[favSectionID] = _NS("Favorites");
                _shelfActionTitlesBySectionID[favSectionID] = _NS("See All");
                _shelfActionsBySectionID[favSectionID] = ^{
                    [VLCMain sharedInstance].libraryWindow.librarySegmentType = VLCLibraryWatchFavoritesSegmentType;
                };
                _shelfShowsPagingBySectionID[favSectionID] = @YES;
            }

            NSMutableArray<NSString *> *itemIDs = [NSMutableArray arrayWithCapacity:newFavs.count];
            for (NSUInteger idx = 0; idx < newFavs.count; idx++) {
                MacLCWatchEntry *entry = newFavs[idx];
                NSString *itemID = [NSString stringWithFormat:@"%@fav/%lu_%@", scopePrefix, (unsigned long)idx, entry.identifier];
                [itemIDs addObject:itemID];
                _itemsByID[itemID] = entry.item;
                _ranksByID[itemID] = @0;
            }
            [snapshot appendItemsWithIdentifiers:itemIDs intoSectionWithIdentifier:favSectionID];
        } else {
            if ([snapshot.sectionIdentifiers containsObject:favSectionID]) {
                NSArray<NSString *> *oldItems = [snapshot itemIdentifiersInSectionWithIdentifier:favSectionID];
                for (NSString *oID in oldItems) {
                    [_itemsByID removeObjectForKey:oID];
                    [_ranksByID removeObjectForKey:oID];
                }
                [snapshot deleteSectionsWithIdentifiers:@[favSectionID]];
                [_activeSections removeObject:favSectionID];
                [_shelfTitlesBySectionID removeObjectForKey:favSectionID];
                [_shelfActionTitlesBySectionID removeObjectForKey:favSectionID];
                [_shelfActionsBySectionID removeObjectForKey:favSectionID];
                [_shelfShowsPagingBySectionID removeObjectForKey:favSectionID];
            }
        }
    } else {
        if ([snapshot.sectionIdentifiers containsObject:favSectionID]) {
            NSArray<NSString *> *oldItems = [snapshot itemIdentifiersInSectionWithIdentifier:favSectionID];
            for (NSString *oID in oldItems) {
                [_itemsByID removeObjectForKey:oID];
                [_ranksByID removeObjectForKey:oID];
            }
            [snapshot deleteSectionsWithIdentifiers:@[favSectionID]];
            [_activeSections removeObject:favSectionID];
            [_shelfTitlesBySectionID removeObjectForKey:favSectionID];
            [_shelfActionTitlesBySectionID removeObjectForKey:favSectionID];
            [_shelfActionsBySectionID removeObjectForKey:favSectionID];
            [_shelfShowsPagingBySectionID removeObjectForKey:favSectionID];
        }
    }

    const BOOL reduceMotion = NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion;
    const BOOL animate = animated && !reduceMotion && self.view.window.isVisible;
    [_dataSource applySnapshot:snapshot animatingDifferences:animate];
}

- (void)addonsDidChange:(NSNotification *)notification
{
    if (_isSearching) {
        [self executeSearch];
    } else {
        [self reloadData];
    }
}

- (void)discoveryDidChange:(NSNotification *)notification
{
    if (_isSearching) {
        return;
    }
    if (_selectedServiceCode != nil) {
        MacLCWatchService *service = [MacLCWatchDiscovery serviceForCode:_selectedServiceCode];
        if (!service || ![[MacLCWatchDiscovery sharedDiscovery].activeServices containsObject:service]) {
            _selectedServiceCode = nil;
            NSString *defaultsKey = [NSString stringWithFormat:@"MacLCWatchService.%@", self.section.sectionTitle];
            [[NSUserDefaults standardUserDefaults] removeObjectForKey:defaultsKey];
        }
    }
    [self reloadData];
}

#pragma mark - NSCollectionViewDelegate

- (void)collectionView:(NSCollectionView *)collectionView
willDisplaySupplementaryView:(NSView *)view
        forElementKind:(NSString *)elementKind
           atIndexPath:(NSIndexPath *)indexPath
{
    if ([elementKind isEqualToString:MacLCWatchHeaderElementKind]) {
        if (indexPath.section < (NSInteger)_activeSections.count) {
            NSString *sectionID = _activeSections[indexPath.section];
            [self updateHeaderPagingStateForSectionID:sectionID];
        }
        [self prefetchGenreShelvesNearSection:indexPath.section];
    }
}

- (void)collectionView:(NSCollectionView *)collectionView
        willDisplayItem:(NSCollectionViewItem *)item
forRepresentedObjectAtIndexPath:(NSIndexPath *)indexPath
{
    if (indexPath.section < (NSInteger)_activeSections.count) {
        NSString *sectionID = _activeSections[indexPath.section];

        NSScrollView *shelfScrollView = [MacLCWatchShelfScrolling shelfScrollViewForView:item.view outerScrollView:_scrollView];
        if (shelfScrollView) {
            [MacLCWatchShelfScrolling configureShelfScrollView:shelfScrollView];
            [_shelfScrollViewsBySectionID setObject:shelfScrollView forKey:sectionID];
            [_sectionIDByClipView setObject:sectionID forKey:shelfScrollView.contentView];

            if (![_observedShelfClipViews containsObject:shelfScrollView.contentView]) {
                [_observedShelfClipViews addObject:shelfScrollView.contentView];
                shelfScrollView.contentView.postsBoundsChangedNotifications = YES;
                [[NSNotificationCenter defaultCenter] addObserver:self
                                                         selector:@selector(shelfClipViewBoundsDidChange:)
                                                             name:NSViewBoundsDidChangeNotification
                                                           object:shelfScrollView.contentView];
            }

            [self updateHeaderPagingStateForSectionID:sectionID];
        }

        if ([item isKindOfClass:[_MacLCWatchHeroCollectionViewItem class]]) {
            _heroItemView = ((_MacLCWatchHeroCollectionViewItem *)item).heroView;
            [_heroItemView setScrollOffset:NSMinY(_scrollView.contentView.bounds)];
        }

        if ([item isKindOfClass:[MacLCWatchCollectionCard class]]) {
            MacLCWatchCollectionCard *card = (MacLCWatchCollectionCard *)item;
            MacLCWatchCollection *coll = card.collection;
            if (coll) {
                NSArray<MacLCAddonItem *> *resolved = [[MacLCWatchDiscovery sharedDiscovery] resolvedItemsForCollection:coll];
                if (!resolved) {
                    __weak typeof(card) weakCard = card;
                    MacLCAddonRequest *req = [[MacLCWatchDiscovery sharedDiscovery] resolveCollection:coll completion:^(NSArray<MacLCAddonItem *> *items) {
                        __strong typeof(weakCard) strongCard = weakCard;
                        if (strongCard && [strongCard.collection.identifier isEqualToString:coll.identifier]) {
                            [strongCard configureWithCollection:coll items:items];
                        }
                    }];
                    if (req) {
                        [_activeRequests addObject:req];
                    }
                }
            }
        }
    }

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
    [_collectionView registerClass:[MacLCWatchShelfHeaderView class]
        forSupplementaryViewOfKind:MacLCWatchHeaderElementKind
                    withIdentifier:MacLCWatchShelfHeaderIdentifier];

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

        MacLCWatchShelfHeaderView *header = [collectionView makeSupplementaryViewOfKind:kind
                                                                      withIdentifier:MacLCWatchShelfHeaderIdentifier
                                                                        forIndexPath:indexPath];
        header.title = strongSelf->_headerTitle ?: @"";
        header.subtitle = nil;
        header.explainerTopic = nil;
        header.actionTitle = nil;
        header.action = nil;
        header.showsPaging = NO;
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

#pragma mark - MacLCWatchCollectionViewController

@interface MacLCWatchCollectionViewController () <NSCollectionViewDelegate>
{
    __weak MacLCWatchSectionViewController *_section;
    MacLCWatchCollection *_collection;

    NSScrollView *_scrollView;
    _MacLCWatchCollectionView *_collectionView;
    NSCollectionViewDiffableDataSource<NSString *, NSString *> *_dataSource;

    NSArray<MacLCAddonItem *> *_items;
    NSMutableDictionary<NSString *, MacLCAddonItem *> *_itemsByID;

    MacLCAddonRequest *_resolveRequest;
    NSView *_emptyStateContainer;
    _MacLCWatchCollectionHeaderCollectionViewItem *_headerItemView;
}
@end

@implementation MacLCWatchCollectionViewController

- (instancetype)initWithSection:(MacLCWatchSectionViewController *)section
                     collection:(MacLCWatchCollection *)collection
{
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _section = section;
        _collection = collection;
        _itemsByID = [NSMutableDictionary dictionary];
        self.title = collection.title;
    }
    return self;
}

- (void)dealloc
{
    [_resolveRequest cancel];
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
        if (sectionIndex == 0) {
            return [MacLCWatchLayout fullWidthSectionWithHeight:300.0];
        }
        return [MacLCWatchLayout posterGridSectionWithEnvironment:environment hasHeader:NO];
    };

    _collectionView.collectionViewLayout = [[NSCollectionViewCompositionalLayout alloc] initWithSectionProvider:provider];

    [_collectionView registerClass:[_MacLCWatchCollectionHeaderCollectionViewItem class]
             forItemWithIdentifier:MacLCWatchCollectionHeaderItemIdentifier];
    [_collectionView registerClass:[MacLCWatchPosterItem class]
             forItemWithIdentifier:MacLCWatchPosterItemIdentifier];

    [self configureDataSource];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    [self startResolving];
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

- (void)updateHeaderView
{
    if (!_headerItemView) return;

    NSDate *nextDate = [[MacLCWatchDiscovery sharedDiscovery] nextEditDateAfter:[NSDate date]];
    NSDate *lastDay = [NSDate dateWithTimeInterval:-86400 sinceDate:nextDate];
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    [formatter setLocalizedDateFormatFromTemplate:@"MMM d"];
    NSString *lastDayStr = [[formatter stringFromDate:lastDay] uppercaseString];
    NSString *eyebrow = [NSString stringWithFormat:@"THE EDIT · UNTIL %@", lastDayStr];

    [_headerItemView.headerView configureWithCollection:_collection items:_items ?: @[] eyebrow:eyebrow];
}

- (void)startResolving
{
    NSArray<MacLCAddonItem *> *resolved = [[MacLCWatchDiscovery sharedDiscovery] resolvedItemsForCollection:_collection];
    if (resolved) {
        _items = [resolved copy];
        [self rebuildSnapshotAnimated:NO];
        if (_items.count == 0) {
            [self showEmptyState];
        }
    } else {
        [self rebuildSnapshotAnimated:NO];
        __weak typeof(self) weakSelf = self;
        _resolveRequest = [[MacLCWatchDiscovery sharedDiscovery] resolveCollection:_collection completion:^(NSArray<MacLCAddonItem *> *items) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            strongSelf->_resolveRequest = nil;
            strongSelf->_items = [items copy];
            [strongSelf updateHeaderView];
            if (strongSelf->_items.count == 0) {
                [strongSelf rebuildSnapshotAnimated:YES];
                [strongSelf showEmptyState];
            } else {
                [strongSelf hideEmptyState];
                [strongSelf rebuildSnapshotAnimated:YES];
            }
        }];
    }
}

- (void)configureDataSource
{
    __weak typeof(self) weakSelf = self;
    _dataSource = [[NSCollectionViewDiffableDataSource alloc] initWithCollectionView:_collectionView
                                                                        itemProvider:^NSCollectionViewItem * _Nullable(NSCollectionView *collectionView, NSIndexPath *indexPath, id itemID) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return nil;

        if ([itemID isEqualToString:MacLCWatchCollectionHeaderItemIdentifier]) {
            _MacLCWatchCollectionHeaderCollectionViewItem *headerItem = [collectionView makeItemWithIdentifier:MacLCWatchCollectionHeaderItemIdentifier forIndexPath:indexPath];
            strongSelf->_headerItemView = headerItem;
            [strongSelf updateHeaderView];
            return headerItem;
        }

        MacLCWatchPosterItem *posterItem = [collectionView makeItemWithIdentifier:MacLCWatchPosterItemIdentifier forIndexPath:indexPath];
        if ([itemID hasPrefix:@"placeholder_"]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wnonnull"
            [posterItem configureWithItem:nil rank:0];
#pragma clang diagnostic pop
            posterItem.activationHandler = nil;
            return posterItem;
        }

        MacLCAddonItem *item = strongSelf->_itemsByID[itemID];
        [posterItem configureWithItem:item rank:0];
        posterItem.activationHandler = ^(MacLCAddonItem *clickedItem) {
            [weakSelf showDetailForItem:clickedItem];
        };
        return posterItem;
    }];
}

- (void)rebuildSnapshotAnimated:(BOOL)animated
{
    NSDiffableDataSourceSnapshot<NSString *, NSString *> *snapshot = [[NSDiffableDataSourceSnapshot alloc] init];
    [_itemsByID removeAllObjects];

    [snapshot appendSectionsWithIdentifiers:@[@"collection_header_section", @"collection_grid_section"]];
    [snapshot appendItemsWithIdentifiers:@[MacLCWatchCollectionHeaderItemIdentifier] intoSectionWithIdentifier:@"collection_header_section"];

    if (_items != nil) {
        NSMutableArray<NSString *> *itemIDs = [NSMutableArray arrayWithCapacity:_items.count];
        for (NSUInteger idx = 0; idx < _items.count; idx++) {
            MacLCAddonItem *item = _items[idx];
            NSString *itemID = [NSString stringWithFormat:@"item_%lu_%@", (unsigned long)idx, item.identifier];
            [itemIDs addObject:itemID];
            _itemsByID[itemID] = item;
        }
        [snapshot appendItemsWithIdentifiers:itemIDs intoSectionWithIdentifier:@"collection_grid_section"];
    } else {
        NSUInteger count = _collection.entries.count > 0 ? _collection.entries.count : 8;
        NSMutableArray<NSString *> *placeholderIDs = [NSMutableArray arrayWithCapacity:count];
        for (NSUInteger idx = 0; idx < count; idx++) {
            [placeholderIDs addObject:[NSString stringWithFormat:@"placeholder_%lu", (unsigned long)idx]];
        }
        [snapshot appendItemsWithIdentifiers:placeholderIDs intoSectionWithIdentifier:@"collection_grid_section"];
    }

    BOOL reduceMotion = NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion;
    BOOL animate = animated && !reduceMotion && self.view.window.isVisible;
    [_dataSource applySnapshot:snapshot animatingDifferences:animate];
}

- (void)showEmptyState
{
    if (_emptyStateContainer) return;
    _emptyStateContainer = [[NSView alloc] init];
    _emptyStateContainer.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_emptyStateContainer];

    [NSLayoutConstraint activateConstraints:@[
        [_emptyStateContainer.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [_emptyStateContainer.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor constant:100],
        [_emptyStateContainer.widthAnchor constraintLessThanOrEqualToConstant:420],
    ]];

    MacLCEmptyStateView *emptyView = [MacLCEmptyStateView emptyStateWithSymbolName:@"film.stack"
                                                                            title:_NS("Nothing to Show Yet")
                                                                          message:_NS("None of these titles were found in your catalog add-ons.")];
    emptyView.translatesAutoresizingMaskIntoConstraints = NO;
    [_emptyStateContainer addSubview:emptyView];

    [NSLayoutConstraint activateConstraints:@[
        [emptyView.topAnchor constraintEqualToAnchor:_emptyStateContainer.topAnchor],
        [emptyView.leadingAnchor constraintEqualToAnchor:_emptyStateContainer.leadingAnchor],
        [emptyView.trailingAnchor constraintEqualToAnchor:_emptyStateContainer.trailingAnchor],
        [emptyView.bottomAnchor constraintEqualToAnchor:_emptyStateContainer.bottomAnchor],
    ]];
}

- (void)hideEmptyState
{
    if (_emptyStateContainer) {
        [_emptyStateContainer removeFromSuperview];
        _emptyStateContainer = nil;
    }
}

- (void)handleSelectionActivation
{
    NSIndexPath *indexPath = _collectionView.selectionIndexPaths.anyObject;
    if (!indexPath || indexPath.section == 0) return;
    NSString *itemID = [_dataSource itemIdentifierForIndexPath:indexPath];
    if (!itemID || [itemID hasPrefix:@"placeholder_"]) return;
    MacLCAddonItem *item = _itemsByID[itemID];
    if (item) {
        [_section showDetailForItem:item showStreams:NO];
    }
}

@end
