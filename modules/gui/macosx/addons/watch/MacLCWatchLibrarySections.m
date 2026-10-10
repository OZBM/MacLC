/*****************************************************************************
 * MacLCWatchLibrarySections.m: Favorites and History sections for Watch
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

#import "addons/watch/MacLCWatchLibrarySections.h"
#import "addons/watch/MacLCWatchSections.h"
#import "addons/watch/MacLCWatchComponents.h"
#import "addons/watch/MacLCWatchLibrary.h"
#import "addons/watch/MacLCWatchPlayback.h"
#import "addons/watch/MacLCWatchLibraryViews.h"
#import "addons/watch/MacLCStreamPicker.h"
#import "addons/MacLCAddons.h"

#import "medialib/components/MacLCEmptyStateView.h"
#import "medialib/components/MacLCSectionHeaderView.h"
#import "theme/MacLCDesign.h"
#import "main/VLCMain.h"
#import "library/VLCLibraryWindow.h"
#import "library/VLCLibrarySegment.h"
#import "extensions/NSString+Helpers.h"

static NSString * const MacLCWatchFavoritesFilterKey = @"MacLCWatchFavoritesFilter";

#pragma mark - Custom Collection View

@interface _MacLCWatchLibraryCollectionView : NSCollectionView
@property (nonatomic, copy, nullable) void (^doubleClickHandler)(void);
@property (nonatomic, copy, nullable) void (^returnKeyHandler)(void);
@end

@implementation _MacLCWatchLibraryCollectionView

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

#pragma mark - MacLCWatchResumeEntry

void MacLCWatchResumeEntry(MacLCWatchEntry *entry, MacLCWatchSectionViewController *section)
{
    if (!entry || !section) {
        return;
    }

    MacLCWatchResumeTarget * const target = entry.resumeTarget;
    if (!target) {
        [section showDetailForItem:entry.item showStreams:NO];
        return;
    }

    if (target.kind == MacLCWatchResumeKindResume) {
        MacLCWatchProgress * const progress = target.progress;
        BOOL resumed = NO;
        if (progress && progress.streamMRL.length > 0) {
            resumed = [[MacLCWatchPlayback sharedPlayback] resumeProgress:progress item:entry.item];
        }
        if (!resumed) {
            [section showDetailForItem:entry.item showStreams:YES];
        }
        return;
    }

    if (target.kind == MacLCWatchResumeKindNextUp) {
        MacLCAddonItem * const item = entry.item;
        if (!item) {
            return;
        }

        [MacLCAddonStore.sharedStore fetchMetaForItem:item completion:^(MacLCAddonMeta * _Nullable meta, NSError * _Nullable error) {
            if (error || !meta) {
                [section showDetailForItem:item showStreams:NO];
                return;
            }

            MacLCAddonVideo *matchedVideo = nil;
            for (MacLCAddonVideo *video in meta.videos) {
                if (target.videoIdentifier.length > 0 && [video.identifier isEqualToString:target.videoIdentifier]) {
                    matchedVideo = video;
                    break;
                }
                if (video.season == target.season && video.episode == target.episode) {
                    matchedVideo = video;
                    break;
                }
            }

            if (!matchedVideo) {
                [section showDetailForItem:item showStreams:NO];
                return;
            }

            NSWindow * const window = section.view.window ?: [VLCMain sharedInstance].libraryWindow;
            if (!window) {
                [section showDetailForItem:item showStreams:YES];
                return;
            }

            MacLCStreamPickerController * const picker =
                [[MacLCStreamPickerController alloc] initWithItem:item video:matchedVideo];

            static NSMutableSet<MacLCStreamPickerController *> *sActivePickers;
            static dispatch_once_t onceToken;
            dispatch_once(&onceToken, ^{
                sActivePickers = [NSMutableSet set];
            });
            [sActivePickers addObject:picker];

            __weak MacLCStreamPickerController *weakPicker = picker;
            picker.completionHandler = ^(BOOL played) {
                MacLCStreamPickerController *strongPicker = weakPicker;
                if (strongPicker) {
                    [sActivePickers removeObject:strongPicker];
                }
            };

            [picker beginSheetModalForWindow:window];
        }];
    }
}

#pragma mark - Favorites Content View Controller

@interface _MacLCWatchFavoritesContentViewController : NSViewController
- (instancetype)initWithSection:(MacLCWatchSectionViewController *)section;
- (void)applySearchString:(NSString *)searchString;
@end

@interface _MacLCWatchFavoritesContentViewController ()
{
    __weak MacLCWatchSectionViewController *_section;
    NSView *_headerContainer;
    NSSegmentedControl *_segmentedFilter;
    NSTextField *_countLabel;
    NSScrollView *_scrollView;
    _MacLCWatchLibraryCollectionView *_collectionView;
    NSCollectionViewDiffableDataSource<NSString *, NSString *> *_dataSource;
    NSMutableDictionary<NSString *, MacLCAddonItem *> *_itemsByID;
    NSString *_searchString;
    MacLCEmptyStateView *_emptyStateView;
}
@end

@implementation _MacLCWatchFavoritesContentViewController

- (instancetype)initWithSection:(MacLCWatchSectionViewController *)section
{
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _section = section;
        _itemsByID = [NSMutableDictionary dictionary];
        _searchString = @"";
    }
    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)loadView
{
    NSView * const root = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 800, 600)];
    root.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    self.view = root;

    _headerContainer = [[NSView alloc] init];
    _headerContainer.translatesAutoresizingMaskIntoConstraints = NO;
    [root addSubview:_headerContainer];

    _segmentedFilter = [NSSegmentedControl segmentedControlWithLabels:@[_NS("All"), _NS("Movies"), _NS("TV Shows")]
                                                         trackingMode:NSSegmentSwitchTrackingSelectOne
                                                               target:self
                                                               action:@selector(filterChanged:)];
    _segmentedFilter.translatesAutoresizingMaskIntoConstraints = NO;
    NSInteger savedFilter = [[NSUserDefaults standardUserDefaults] integerForKey:MacLCWatchFavoritesFilterKey];
    if (savedFilter < 0 || savedFilter > 2) {
        savedFilter = 0;
    }
    _segmentedFilter.selectedSegment = savedFilter;
    _segmentedFilter.accessibilityLabel = _NS("Filter Favorites");
    [_headerContainer addSubview:_segmentedFilter];

    _countLabel = [NSTextField labelWithString:@""];
    _countLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _countLabel.font = MacLCDesign.footnote;
    _countLabel.textColor = MacLCDesign.secondaryLabel;
    _countLabel.alignment = NSTextAlignmentRight;
    [_headerContainer addSubview:_countLabel];

    [NSLayoutConstraint activateConstraints:@[
        [_headerContainer.topAnchor constraintEqualToAnchor:root.safeAreaLayoutGuide.topAnchor constant:16.0],
        [_headerContainer.leadingAnchor constraintEqualToAnchor:root.safeAreaLayoutGuide.leadingAnchor constant:40.0],
        [_headerContainer.trailingAnchor constraintEqualToAnchor:root.safeAreaLayoutGuide.trailingAnchor constant:-40.0],
        [_headerContainer.heightAnchor constraintEqualToConstant:32.0],

        [_segmentedFilter.leadingAnchor constraintEqualToAnchor:_headerContainer.leadingAnchor],
        [_segmentedFilter.centerYAnchor constraintEqualToAnchor:_headerContainer.centerYAnchor],

        [_countLabel.trailingAnchor constraintEqualToAnchor:_headerContainer.trailingAnchor],
        [_countLabel.centerYAnchor constraintEqualToAnchor:_headerContainer.centerYAnchor],
        [_countLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:_segmentedFilter.trailingAnchor constant:12.0],
    ]];

    _scrollView = [[NSScrollView alloc] init];
    _scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    _scrollView.drawsBackground = NO;
    _scrollView.hasVerticalScroller = YES;
    _scrollView.autohidesScrollers = YES;
    _scrollView.automaticallyAdjustsContentInsets = NO;
    [root addSubview:_scrollView];

    [NSLayoutConstraint activateConstraints:@[
        [_scrollView.topAnchor constraintEqualToAnchor:_headerContainer.bottomAnchor constant:16.0],
        [_scrollView.leadingAnchor constraintEqualToAnchor:root.leadingAnchor],
        [_scrollView.trailingAnchor constraintEqualToAnchor:root.trailingAnchor],
        [_scrollView.bottomAnchor constraintEqualToAnchor:root.bottomAnchor],
    ]];

    _collectionView = [[_MacLCWatchLibraryCollectionView alloc] initWithFrame:root.bounds];
    _collectionView.autoresizingMask = NSViewWidthSizable;
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

    NSCollectionViewCompositionalLayoutSectionProvider provider = ^NSCollectionLayoutSection * _Nullable(NSInteger sectionIndex, id<NSCollectionLayoutEnvironment> environment) {
        return [MacLCWatchLayout posterGridSectionWithEnvironment:environment hasHeader:NO];
    };
    _collectionView.collectionViewLayout = [[NSCollectionViewCompositionalLayout alloc] initWithSectionProvider:provider];

    [_collectionView registerClass:[MacLCWatchPosterItem class]
             forItemWithIdentifier:MacLCWatchPosterItemIdentifier];

    _scrollView.documentView = _collectionView;

    _dataSource = [[NSCollectionViewDiffableDataSource alloc] initWithCollectionView:_collectionView
                                                                        itemProvider:^NSCollectionViewItem * _Nullable(NSCollectionView *collectionView, NSIndexPath *indexPath, id itemID) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return nil;

        MacLCWatchPosterItem *posterItem = [collectionView makeItemWithIdentifier:MacLCWatchPosterItemIdentifier
                                                                     forIndexPath:indexPath];
        MacLCAddonItem *item = strongSelf->_itemsByID[itemID];
        [posterItem configureWithItem:item rank:0];
        posterItem.activationHandler = ^(MacLCAddonItem *clicked) {
            [strongSelf->_section showDetailForItem:clicked showStreams:NO];
        };
        posterItem.view.menu = [MacLCWatchActions menuForItem:item video:nil inHistory:NO];
        return posterItem;
    }];
}

- (void)viewDidLayout
{
    [super viewDidLayout];
    /* The sidebar floats over the content: start the grid after it, as the
     * Watch pages do (the header follows the safe area by constraints). */
    const NSEdgeInsets safe = self.view.safeAreaInsets;
    const NSEdgeInsets insets = NSEdgeInsetsMake(0.0, safe.left, safe.bottom, safe.right);
    const NSEdgeInsets current = _scrollView.contentInsets;
    if (current.left != insets.left || current.bottom != insets.bottom || current.right != insets.right) {
        _scrollView.contentInsets = insets;
    }
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(watchLibraryDidChange:)
                                                 name:MacLCWatchLibraryDidChangeNotification
                                               object:nil];

    [self reloadFavoritesAnimated:NO];
}

- (void)filterChanged:(NSSegmentedControl *)sender
{
    [[NSUserDefaults standardUserDefaults] setInteger:sender.selectedSegment
                                               forKey:MacLCWatchFavoritesFilterKey];
    [self reloadFavoritesAnimated:YES];
}

- (void)applySearchString:(NSString *)searchString
{
    _searchString = [searchString copy] ?: @"";
    [self reloadFavoritesAnimated:YES];
}

- (void)watchLibraryDidChange:(NSNotification *)notification
{
    NSSet<NSString *> *changedTitles = notification.userInfo[MacLCWatchLibraryChangedTitlesKey];
    if (changedTitles != nil) {
        BOOL relevant = NO;
        for (MacLCAddonItem *item in _itemsByID.allValues) {
            if ([changedTitles containsObject:item.identifier]) {
                relevant = YES;
                break;
            }
        }
        if (!relevant) {
            for (MacLCWatchEntry *entry in [MacLCWatchLibrary sharedLibrary].favoriteEntries) {
                if ([changedTitles containsObject:entry.identifier]) {
                    relevant = YES;
                    break;
                }
            }
        }
        if (!relevant) {
            return;
        }
    }

    [self reloadFavoritesAnimated:YES];
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

- (void)reloadFavoritesAnimated:(BOOL)animated
{
    NSArray<MacLCWatchEntry *> *allFavorites = [MacLCWatchLibrary sharedLibrary].favoriteEntries;

    [_emptyStateView removeFromSuperview];
    _emptyStateView = nil;

    if (allFavorites.count == 0) {
        _headerContainer.hidden = YES;
        _collectionView.hidden = YES;

        _emptyStateView = [MacLCEmptyStateView emptyStateWithSymbolName:@"heart"
                                                                  title:_NS("No Favorites Yet")
                                                                message:_NS("Add movies and shows you want to watch later: tap the heart on a poster, or on a title's page.")];
        _emptyStateView.translatesAutoresizingMaskIntoConstraints = NO;
        [self.view addSubview:_emptyStateView];
        [NSLayoutConstraint activateConstraints:@[
            [_emptyStateView.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
            [_emptyStateView.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
        ]];

        NSDiffableDataSourceSnapshot<NSString *, NSString *> *emptySnapshot = [[NSDiffableDataSourceSnapshot alloc] init];
        [_dataSource applySnapshot:emptySnapshot animatingDifferences:NO];
        [_itemsByID removeAllObjects];
        return;
    }

    _headerContainer.hidden = NO;

    NSInteger const filterIndex = _segmentedFilter.selectedSegment;
    NSMutableArray<MacLCWatchEntry *> *filtered = [NSMutableArray arrayWithCapacity:allFavorites.count];
    for (MacLCWatchEntry *entry in allFavorites) {
        if (filterIndex == 1 && ![entry.type isEqualToString:@"movie"]) {
            continue;
        }
        if (filterIndex == 2 && !([entry.type isEqualToString:@"series"] || [entry.type isEqualToString:@"tv"])) {
            continue;
        }
        if (_searchString.length > 0) {
            NSString *title = entry.item.name ?: @"";
            if ([title rangeOfString:_searchString
                             options:NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch].location == NSNotFound) {
                continue;
            }
        }
        [filtered addObject:entry];
    }

    const NSUInteger count = filtered.count;
    if (count == 1) {
        _countLabel.stringValue = _NS("1 title");
    } else {
        _countLabel.stringValue = [NSString stringWithFormat:_NS("%lu titles"), (unsigned long)count];
    }

    if (count == 0) {
        _collectionView.hidden = YES;

        NSString *title = _NS("No Results");
        NSString *message = nil;
        if (_searchString.length > 0) {
            message = [NSString stringWithFormat:_NS("No favorites matching “%@” were found."), _searchString];
        } else if (filterIndex == 1) {
            message = _NS("No Favorite Movies");
        } else {
            message = _NS("No Favorite TV Shows");
        }

        _emptyStateView = [MacLCEmptyStateView emptyStateWithSymbolName:@"heart"
                                                                  title:title
                                                                message:message];
        _emptyStateView.translatesAutoresizingMaskIntoConstraints = NO;
        [self.view addSubview:_emptyStateView];
        [NSLayoutConstraint activateConstraints:@[
            [_emptyStateView.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
            [_emptyStateView.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
        ]];

        NSDiffableDataSourceSnapshot<NSString *, NSString *> *emptySnapshot = [[NSDiffableDataSourceSnapshot alloc] init];
        [_dataSource applySnapshot:emptySnapshot animatingDifferences:NO];
        [_itemsByID removeAllObjects];
        return;
    }

    _collectionView.hidden = NO;

    NSDiffableDataSourceSnapshot<NSString *, NSString *> *snapshot = [[NSDiffableDataSourceSnapshot alloc] init];
    NSString * const sectionID = @"favorites_grid";
    [snapshot appendSectionsWithIdentifiers:@[sectionID]];

    [_itemsByID removeAllObjects];
    NSMutableArray<NSString *> *itemIDs = [NSMutableArray arrayWithCapacity:count];
    for (NSUInteger idx = 0; idx < count; idx++) {
        MacLCWatchEntry *entry = filtered[idx];
        NSString *itemID = [NSString stringWithFormat:@"fav_%lu_%@", (unsigned long)idx, entry.identifier];
        [itemIDs addObject:itemID];
        _itemsByID[itemID] = entry.item;
    }
    [snapshot appendItemsWithIdentifiers:itemIDs intoSectionWithIdentifier:sectionID];

    const BOOL reduceMotion = NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion;
    const BOOL animate = animated && !reduceMotion && self.view.window.isVisible;
    [_dataSource applySnapshot:snapshot animatingDifferences:animate];
}

@end

#pragma mark - MacLCWatchFavoritesSectionViewController

@implementation MacLCWatchFavoritesSectionViewController

- (instancetype)init
{
    self = [super initWithMediaType:nil segmentType:VLCLibraryWatchFavoritesSegmentType];
    return self;
}

- (NSViewController *)makeRootViewControllerForViewMode:(MacLCLibraryViewMode)viewMode
{
    return [[_MacLCWatchFavoritesContentViewController alloc] initWithSection:self];
}

- (NSString *)sectionTitle
{
    if (self.topViewController && self.topViewController != self.rootViewController && self.topViewController.title.length > 0) {
        return self.topViewController.title;
    }
    return _NS("Favorites");
}

- (NSString *)makeSearchPlaceholder
{
    return _NS("Search Favorites");
}

@end

#pragma mark - History Content View Controller

@interface _MacLCWatchHistoryContentViewController : NSViewController
- (instancetype)initWithSection:(MacLCWatchSectionViewController *)section;
- (void)applySearchString:(NSString *)searchString;
@end

@interface _MacLCWatchHistoryContentViewController ()
{
    __weak MacLCWatchSectionViewController *_section;
    NSView *_headerContainer;
    NSTextField *_countLabel;
    NSButton *_clearHistoryButton;
    NSScrollView *_scrollView;
    _MacLCWatchLibraryCollectionView *_collectionView;
    NSCollectionViewDiffableDataSource<NSString *, NSString *> *_dataSource;
    NSMutableDictionary<NSString *, MacLCWatchEntry *> *_entriesByID;
    NSMutableDictionary<NSString *, NSString *> *_sectionTitlesByID;
    NSMutableArray<NSString *> *_activeSections;
    NSString *_searchString;
    MacLCEmptyStateView *_emptyStateView;
}
@end

@implementation _MacLCWatchHistoryContentViewController

- (instancetype)initWithSection:(MacLCWatchSectionViewController *)section
{
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _section = section;
        _entriesByID = [NSMutableDictionary dictionary];
        _sectionTitlesByID = [NSMutableDictionary dictionary];
        _activeSections = [NSMutableArray array];
        _searchString = @"";
    }
    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)loadView
{
    NSView * const root = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 800, 600)];
    root.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    self.view = root;

    _headerContainer = [[NSView alloc] init];
    _headerContainer.translatesAutoresizingMaskIntoConstraints = NO;
    [root addSubview:_headerContainer];

    _countLabel = [NSTextField labelWithString:@""];
    _countLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _countLabel.font = MacLCDesign.footnote;
    _countLabel.textColor = MacLCDesign.secondaryLabel;
    [_headerContainer addSubview:_countLabel];

    _clearHistoryButton = [NSButton buttonWithTitle:_NS("Clear History…")
                                             target:self
                                             action:@selector(clearHistoryClicked:)];
    _clearHistoryButton.translatesAutoresizingMaskIntoConstraints = NO;
    _clearHistoryButton.bordered = NO;
    _clearHistoryButton.font = MacLCDesign.subheadline;
    _clearHistoryButton.contentTintColor = MacLCDesign.secondaryLabel;
    _clearHistoryButton.accessibilityLabel = _NS("Clear History…");
    [_headerContainer addSubview:_clearHistoryButton];

    [NSLayoutConstraint activateConstraints:@[
        [_headerContainer.topAnchor constraintEqualToAnchor:root.safeAreaLayoutGuide.topAnchor constant:16.0],
        [_headerContainer.leadingAnchor constraintEqualToAnchor:root.safeAreaLayoutGuide.leadingAnchor constant:40.0],
        [_headerContainer.trailingAnchor constraintEqualToAnchor:root.safeAreaLayoutGuide.trailingAnchor constant:-40.0],
        [_headerContainer.heightAnchor constraintEqualToConstant:32.0],

        [_countLabel.leadingAnchor constraintEqualToAnchor:_headerContainer.leadingAnchor],
        [_countLabel.centerYAnchor constraintEqualToAnchor:_headerContainer.centerYAnchor],

        [_clearHistoryButton.trailingAnchor constraintEqualToAnchor:_headerContainer.trailingAnchor],
        [_clearHistoryButton.centerYAnchor constraintEqualToAnchor:_headerContainer.centerYAnchor],
        [_clearHistoryButton.leadingAnchor constraintGreaterThanOrEqualToAnchor:_countLabel.trailingAnchor constant:12.0],
    ]];

    _scrollView = [[NSScrollView alloc] init];
    _scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    _scrollView.drawsBackground = NO;
    _scrollView.hasVerticalScroller = YES;
    _scrollView.autohidesScrollers = YES;
    _scrollView.automaticallyAdjustsContentInsets = NO;
    [root addSubview:_scrollView];

    [NSLayoutConstraint activateConstraints:@[
        [_scrollView.topAnchor constraintEqualToAnchor:_headerContainer.bottomAnchor constant:16.0],
        [_scrollView.leadingAnchor constraintEqualToAnchor:root.leadingAnchor],
        [_scrollView.trailingAnchor constraintEqualToAnchor:root.trailingAnchor],
        [_scrollView.bottomAnchor constraintEqualToAnchor:root.bottomAnchor],
    ]];

    _collectionView = [[_MacLCWatchLibraryCollectionView alloc] initWithFrame:root.bounds];
    _collectionView.autoresizingMask = NSViewWidthSizable;
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

    NSCollectionViewCompositionalLayoutSectionProvider provider = ^NSCollectionLayoutSection * _Nullable(NSInteger sectionIndex, id<NSCollectionLayoutEnvironment> environment) {
        return [MacLCWatchLayout continueGridSectionWithEnvironment:environment hasHeader:YES];
    };
    _collectionView.collectionViewLayout = [[NSCollectionViewCompositionalLayout alloc] initWithSectionProvider:provider];

    [_collectionView registerClass:[MacLCWatchContinueItem class]
             forItemWithIdentifier:MacLCWatchContinueItemIdentifier];
    [_collectionView registerClass:[MacLCSectionHeaderView class]
        forSupplementaryViewOfKind:MacLCWatchHeaderElementKind
                    withIdentifier:MacLCSectionHeaderViewIdentifier];

    _scrollView.documentView = _collectionView;

    _dataSource = [[NSCollectionViewDiffableDataSource alloc] initWithCollectionView:_collectionView
                                                                        itemProvider:^NSCollectionViewItem * _Nullable(NSCollectionView *collectionView, NSIndexPath *indexPath, id itemID) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return nil;

        MacLCWatchContinueItem *cItem = [collectionView makeItemWithIdentifier:MacLCWatchContinueItemIdentifier
                                                                   forIndexPath:indexPath];
        MacLCWatchEntry *entry = strongSelf->_entriesByID[itemID];
        if (entry) {
            [cItem configureWithEntry:entry];
        }

        NSString *secID = (indexPath.section < (NSInteger)strongSelf->_activeSections.count) ? strongSelf->_activeSections[indexPath.section] : @"";
        const BOOL isTodayOrYesterday = [secID isEqualToString:@"sec_today"] || [secID isEqualToString:@"sec_yesterday"];
        cItem.showsLastPlayed = !isTodayOrYesterday;
        cItem.inHistory = YES;
        cItem.activationHandler = ^(MacLCWatchEntry *e) {
            MacLCWatchResumeEntry(e, strongSelf->_section);
        };
        cItem.detailsHandler = ^(MacLCWatchEntry *e) {
            [strongSelf->_section showDetailForItem:e.item showStreams:NO];
        };
        return cItem;
    }];

    _dataSource.supplementaryViewProvider = ^NSView * _Nullable(NSCollectionView *collectionView, NSString *kind, NSIndexPath *indexPath) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf || ![kind isEqualToString:MacLCWatchHeaderElementKind]) {
            return nil;
        }

        MacLCSectionHeaderView *header = [collectionView makeSupplementaryViewOfKind:kind
                                                                      withIdentifier:MacLCSectionHeaderViewIdentifier
                                                                        forIndexPath:indexPath];
        if (indexPath.section < (NSInteger)strongSelf->_activeSections.count) {
            NSString *secID = strongSelf->_activeSections[indexPath.section];
            header.title = strongSelf->_sectionTitlesByID[secID] ?: @"";
        }
        header.subtitle = nil;
        header.actionTitle = nil;
        header.action = nil;
        return header;
    };
}

- (void)viewDidLayout
{
    [super viewDidLayout];
    /* The sidebar floats over the content: start the grid after it, as the
     * Watch pages do (the header follows the safe area by constraints). */
    const NSEdgeInsets safe = self.view.safeAreaInsets;
    const NSEdgeInsets insets = NSEdgeInsetsMake(0.0, safe.left, safe.bottom, safe.right);
    const NSEdgeInsets current = _scrollView.contentInsets;
    if (current.left != insets.left || current.bottom != insets.bottom || current.right != insets.right) {
        _scrollView.contentInsets = insets;
    }
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(watchLibraryDidChange:)
                                                 name:MacLCWatchLibraryDidChangeNotification
                                               object:nil];

    [self reloadHistoryAnimated:NO];
}

- (void)applySearchString:(NSString *)searchString
{
    _searchString = [searchString copy] ?: @"";
    [self reloadHistoryAnimated:YES];
}

- (void)clearHistoryClicked:(id)sender
{
    NSWindow * const window = self.view.window ?: [VLCMain sharedInstance].libraryWindow;

    NSAlert * const alert = [[NSAlert alloc] init];
    alert.alertStyle = NSAlertStyleWarning;
    alert.messageText = _NS("Clear your watch history?");
    alert.informativeText = _NS("Resume points and watched marks for all movies and shows are removed. Favorites stay.");

    NSButton * const clearButton = [alert addButtonWithTitle:_NS("Clear History")];
    clearButton.hasDestructiveAction = YES;
    NSButton * const cancelButton = [alert addButtonWithTitle:_NS("Cancel")];
    clearButton.keyEquivalent = @"";
    cancelButton.keyEquivalent = @"\r";

    void (^handler)(NSModalResponse) = ^(NSModalResponse response) {
        if (response == NSAlertFirstButtonReturn) {
            [[MacLCWatchLibrary sharedLibrary] clearHistory];
        }
    };

    if (window) {
        [alert beginSheetModalForWindow:window completionHandler:handler];
    } else {
        NSModalResponse res = [alert runModal];
        handler(res);
    }
}

- (void)watchLibraryDidChange:(NSNotification *)notification
{
    NSSet<NSString *> *changedTitles = notification.userInfo[MacLCWatchLibraryChangedTitlesKey];
    if (changedTitles != nil) {
        BOOL relevant = NO;
        for (MacLCWatchEntry *entry in _entriesByID.allValues) {
            if ([changedTitles containsObject:entry.identifier]) {
                relevant = YES;
                break;
            }
        }
        if (!relevant) {
            for (MacLCWatchEntry *entry in [MacLCWatchLibrary sharedLibrary].historyEntries) {
                if ([changedTitles containsObject:entry.identifier]) {
                    relevant = YES;
                    break;
                }
            }
        }
        if (!relevant) {
            return;
        }
    }

    [self reloadHistoryAnimated:YES];
}

- (void)handleSelectionActivation
{
    NSIndexPath *indexPath = _collectionView.selectionIndexPaths.anyObject;
    if (!indexPath) return;
    NSString *itemID = [_dataSource itemIdentifierForIndexPath:indexPath];
    if (!itemID) return;
    MacLCWatchEntry *entry = _entriesByID[itemID];
    if (entry) {
        MacLCWatchResumeEntry(entry, _section);
    }
}

- (void)reloadHistoryAnimated:(BOOL)animated
{
    NSArray<MacLCWatchEntry *> *allHistory = [MacLCWatchLibrary sharedLibrary].historyEntries;

    [_emptyStateView removeFromSuperview];
    _emptyStateView = nil;

    if (allHistory.count == 0) {
        _headerContainer.hidden = YES;
        _collectionView.hidden = YES;

        _emptyStateView = [MacLCEmptyStateView emptyStateWithSymbolName:@"clock"
                                                                  title:_NS("No History Yet")
                                                                message:_NS("Movies and shows you watch appear here, so you can pick them up again.")];
        _emptyStateView.translatesAutoresizingMaskIntoConstraints = NO;
        [self.view addSubview:_emptyStateView];
        [NSLayoutConstraint activateConstraints:@[
            [_emptyStateView.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
            [_emptyStateView.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
        ]];

        NSDiffableDataSourceSnapshot<NSString *, NSString *> *emptySnapshot = [[NSDiffableDataSourceSnapshot alloc] init];
        [_dataSource applySnapshot:emptySnapshot animatingDifferences:NO];
        [_entriesByID removeAllObjects];
        [_sectionTitlesByID removeAllObjects];
        [_activeSections removeAllObjects];
        return;
    }

    _headerContainer.hidden = NO;

    NSMutableArray<MacLCWatchEntry *> *filtered = [NSMutableArray arrayWithCapacity:allHistory.count];
    for (MacLCWatchEntry *entry in allHistory) {
        if (_searchString.length > 0) {
            NSString *title = entry.item.name ?: @"";
            if ([title rangeOfString:_searchString
                             options:NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch].location == NSNotFound) {
                continue;
            }
        }
        [filtered addObject:entry];
    }

    const NSUInteger totalCount = filtered.count;
    if (totalCount == 1) {
        _countLabel.stringValue = _NS("1 title");
    } else {
        _countLabel.stringValue = [NSString stringWithFormat:_NS("%lu titles"), (unsigned long)totalCount];
    }

    if (totalCount == 0) {
        _collectionView.hidden = YES;

        _emptyStateView = [MacLCEmptyStateView emptyStateWithSymbolName:@"clock"
                                                                  title:_NS("No Results")
                                                                message:[NSString stringWithFormat:_NS("No history results for “%@” were found."), _searchString]];
        _emptyStateView.translatesAutoresizingMaskIntoConstraints = NO;
        [self.view addSubview:_emptyStateView];
        [NSLayoutConstraint activateConstraints:@[
            [_emptyStateView.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
            [_emptyStateView.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
        ]];

        NSDiffableDataSourceSnapshot<NSString *, NSString *> *emptySnapshot = [[NSDiffableDataSourceSnapshot alloc] init];
        [_dataSource applySnapshot:emptySnapshot animatingDifferences:NO];
        [_entriesByID removeAllObjects];
        [_sectionTitlesByID removeAllObjects];
        [_activeSections removeAllObjects];
        return;
    }

    _collectionView.hidden = NO;

    NSCalendar *calendar = [NSCalendar currentCalendar];
    NSDate *now = [NSDate date];
    NSDate *startOfToday = [calendar startOfDayForDate:now];
    NSDate *startOfWeek = nil;
    [calendar rangeOfUnit:NSCalendarUnitWeekOfYear startDate:&startOfWeek interval:NULL forDate:now];
    NSDate *startOfMonth = nil;
    [calendar rangeOfUnit:NSCalendarUnitMonth startDate:&startOfMonth interval:NULL forDate:now];
    NSDate *startOfYear = nil;
    [calendar rangeOfUnit:NSCalendarUnitYear startDate:&startOfYear interval:NULL forDate:now];

    NSMutableArray<MacLCWatchEntry *> *todayEntries = [NSMutableArray array];
    NSMutableArray<MacLCWatchEntry *> *yesterdayEntries = [NSMutableArray array];
    NSMutableArray<MacLCWatchEntry *> *thisWeekEntries = [NSMutableArray array];
    NSMutableArray<MacLCWatchEntry *> *thisMonthEntries = [NSMutableArray array];
    NSMutableDictionary<NSNumber *, NSMutableArray<MacLCWatchEntry *> *> *monthBuckets = [NSMutableDictionary dictionary];
    NSMutableArray<NSNumber *> *orderedMonthKeys = [NSMutableArray array];
    NSMutableDictionary<NSNumber *, NSMutableArray<MacLCWatchEntry *> *> *yearBuckets = [NSMutableDictionary dictionary];
    NSMutableArray<NSNumber *> *orderedYearKeys = [NSMutableArray array];

    for (MacLCWatchEntry *entry in filtered) {
        NSDate *date = entry.lastPlayed ?: [NSDate distantPast];
        if ([calendar isDateInToday:date] || [date compare:startOfToday] != NSOrderedAscending) {
            [todayEntries addObject:entry];
        } else if ([calendar isDateInYesterday:date]) {
            [yesterdayEntries addObject:entry];
        } else if (startOfWeek && [date compare:startOfWeek] != NSOrderedAscending) {
            [thisWeekEntries addObject:entry];
        } else if (startOfMonth && [date compare:startOfMonth] != NSOrderedAscending) {
            [thisMonthEntries addObject:entry];
        } else if (startOfYear && [date compare:startOfYear] != NSOrderedAscending) {
            NSInteger m = [calendar component:NSCalendarUnitMonth fromDate:date];
            NSNumber *key = @(m);
            if (!monthBuckets[key]) {
                monthBuckets[key] = [NSMutableArray array];
                [orderedMonthKeys addObject:key];
            }
            [monthBuckets[key] addObject:entry];
        } else {
            NSInteger y = [calendar component:NSCalendarUnitYear fromDate:date];
            NSNumber *key = @(y);
            if (!yearBuckets[key]) {
                yearBuckets[key] = [NSMutableArray array];
                [orderedYearKeys addObject:key];
            }
            [yearBuckets[key] addObject:entry];
        }
    }

    NSDiffableDataSourceSnapshot<NSString *, NSString *> *snapshot = [[NSDiffableDataSourceSnapshot alloc] init];
    [_entriesByID removeAllObjects];
    [_sectionTitlesByID removeAllObjects];
    [_activeSections removeAllObjects];

    void (^appendGroup)(NSString *, NSString *, NSArray<MacLCWatchEntry *> *) = ^(NSString *secID, NSString *title, NSArray<MacLCWatchEntry *> *groupEntries) {
        if (groupEntries.count == 0) return;
        [self->_activeSections addObject:secID];
        self->_sectionTitlesByID[secID] = title;
        [snapshot appendSectionsWithIdentifiers:@[secID]];

        NSMutableArray<NSString *> *itemIDs = [NSMutableArray arrayWithCapacity:groupEntries.count];
        for (NSUInteger idx = 0; idx < groupEntries.count; idx++) {
            MacLCWatchEntry *entry = groupEntries[idx];
            NSString *itemID = [NSString stringWithFormat:@"%@/%lu_%@", secID, (unsigned long)idx, entry.identifier];
            [itemIDs addObject:itemID];
            self->_entriesByID[itemID] = entry;
        }
        [snapshot appendItemsWithIdentifiers:itemIDs intoSectionWithIdentifier:secID];
    };

    appendGroup(@"sec_today", _NS("Today"), todayEntries);
    appendGroup(@"sec_yesterday", _NS("Yesterday"), yesterdayEntries);
    appendGroup(@"sec_this_week", _NS("This Week"), thisWeekEntries);
    appendGroup(@"sec_this_month", _NS("This Month"), thisMonthEntries);

    NSDateFormatter *monthFormatter = [[NSDateFormatter alloc] init];
    [monthFormatter setLocalizedDateFormatFromTemplate:@"MMMM"];

    for (NSNumber *mKey in orderedMonthKeys) {
        NSArray<MacLCWatchEntry *> *mEntries = monthBuckets[mKey];
        if (mEntries.count > 0) {
            NSDate *sampleDate = mEntries.firstObject.lastPlayed ?: now;
            NSString *secID = [NSString stringWithFormat:@"sec_month_%ld", (long)mKey.integerValue];
            NSString *title = [monthFormatter stringFromDate:sampleDate];
            appendGroup(secID, title, mEntries);
        }
    }

    for (NSNumber *yKey in orderedYearKeys) {
        NSArray<MacLCWatchEntry *> *yEntries = yearBuckets[yKey];
        if (yEntries.count > 0) {
            NSString *secID = [NSString stringWithFormat:@"sec_year_%ld", (long)yKey.integerValue];
            NSString *title = [NSString stringWithFormat:@"%ld", (long)yKey.integerValue];
            appendGroup(secID, title, yEntries);
        }
    }

    const BOOL reduceMotion = NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion;
    const BOOL animate = animated && !reduceMotion && self.view.window.isVisible;
    [_dataSource applySnapshot:snapshot animatingDifferences:animate];
}

@end

#pragma mark - MacLCWatchHistorySectionViewController

@implementation MacLCWatchHistorySectionViewController

- (instancetype)init
{
    self = [super initWithMediaType:nil segmentType:VLCLibraryWatchHistorySegmentType];
    return self;
}

- (NSViewController *)makeRootViewControllerForViewMode:(MacLCLibraryViewMode)viewMode
{
    return [[_MacLCWatchHistoryContentViewController alloc] initWithSection:self];
}

- (NSString *)sectionTitle
{
    if (self.topViewController && self.topViewController != self.rootViewController && self.topViewController.title.length > 0) {
        return self.topViewController.title;
    }
    return _NS("History");
}

- (NSString *)makeSearchPlaceholder
{
    return _NS("Search History");
}

@end
