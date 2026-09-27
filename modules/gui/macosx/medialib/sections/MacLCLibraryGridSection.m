/*****************************************************************************
 * MacLCLibraryGridSection.m: a section showing one library list
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

#import "medialib/sections/MacLCLibraryGridSection.h"

#import "extensions/NSString+Helpers.h"
#import "library/VLCLibraryDataTypes.h"
#import "medialib/MacLCLibraryFormatting.h"
#import "medialib/components/MacLCEmptyStateView.h"
#import "medialib/data/MacLCLibraryStore.h"
#import "medialib/sections/MacLCLibraryGridViewController.h"

NSString * const MacLCSortKeyTitle = @"title";
NSString * const MacLCSortKeyDuration = @"duration";
NSString * const MacLCSortKeyLastPlayed = @"lastPlayed";
NSString * const MacLCSortKeyYear = @"year";
NSString * const MacLCSortKeyArtist = @"artist";

/* Holds the list's scroll view as a view controller, so the section's stack
 * can show it like any other root. */
@interface MacLCLibraryListRootViewController : NSViewController
@property (nonatomic) MacLCTrackListController *listController;
@property (nonatomic, nullable) MacLCEmptyStateView *emptyState;
@end

@implementation MacLCLibraryListRootViewController

- (void)loadView
{
    NSView * const root = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 800, 600)];
    NSScrollView * const scrollView = self.listController.scrollView;
    scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    [root addSubview:scrollView];
    [NSLayoutConstraint activateConstraints:@[
        [scrollView.topAnchor constraintEqualToAnchor:root.topAnchor],
        [scrollView.bottomAnchor constraintEqualToAnchor:root.bottomAnchor],
        [scrollView.leadingAnchor constraintEqualToAnchor:root.leadingAnchor],
        [scrollView.trailingAnchor constraintEqualToAnchor:root.trailingAnchor],
    ]];
    self.view = root;
}

- (void)setEmptyState:(nullable MacLCEmptyStateView *)emptyState
{
    [_emptyState removeFromSuperview];
    _emptyState = emptyState;
    if (emptyState == nil) {
        return;
    }
    emptyState.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:emptyState];
    [NSLayoutConstraint activateConstraints:@[
        [emptyState.centerXAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.centerXAnchor],
        [emptyState.centerYAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.centerYAnchor],
    ]];
}

@end

@interface MacLCLibraryGridSection ()
{
    NSString *_title;
    MacLCLibraryCollection _collection;
    MacLCArtworkShape _shape;
    MacLCCardSubtitleStyle _subtitleStyle;
    NSString *_countSingular;
    NSString *_countPlural;
    NSString *_emptySymbol;
    NSString *_emptyTitle;
    NSString *_emptyMessage;
    NSString *_emptyActionTitle;
    void (^_emptyActionHandler)(void);
    NSString *_searchString;

    MacLCLibraryGridViewController *_grid;
    MacLCLibraryListRootViewController *_list;
    NSArray<id<VLCMediaLibraryItemProtocol>> *_sortedItems;
    NSString *_sortKey;
    BOOL _sortDescending;
}
@end

@implementation MacLCLibraryGridSection

- (instancetype)initWithSegmentType:(NSInteger)segmentType
                              title:(NSString *)title
                         collection:(MacLCLibraryCollection)collection
                              shape:(MacLCArtworkShape)shape
                      subtitleStyle:(MacLCCardSubtitleStyle)subtitleStyle
{
    self = [super initWithSegmentType:segmentType];
    if (self) {
        _title = [title copy];
        _collection = collection;
        _shape = shape;
        _subtitleStyle = subtitleStyle;
        _countSingular = @"item";
        _countPlural = @"items";
        _searchString = @"";
        _sortedItems = @[];
        _sortOptions = @[MacLCSortKeyTitle];

        NSUserDefaults * const defaults = NSUserDefaults.standardUserDefaults;
        NSString * const viewModeKey = [self defaultsKey:@"ViewMode"];
        if ([defaults objectForKey:viewModeKey] != nil) {
            [super setViewMode:(MacLCLibraryViewMode)[defaults integerForKey:viewModeKey]];
        }

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

- (NSString *)defaultsKey:(NSString *)suffix
{
    return [NSString stringWithFormat:@"MacLCLibrarySection.%ld.%@", (long)self.segmentType, suffix];
}

- (void)setCountNounSingular:(NSString *)singular plural:(NSString *)plural
{
    _countSingular = [singular copy];
    _countPlural = [plural copy];
}

- (void)setEmptyStateActionTitle:(NSString *)title handler:(void (^)(void))handler
{
    _emptyActionTitle = [title copy];
    _emptyActionHandler = [handler copy];
    [_grid setEmptyStateActionTitle:title handler:handler];
}

- (void)setEmptyStateSymbolName:(NSString *)symbolName title:(NSString *)title message:(nullable NSString *)message
{
    _emptySymbol = [symbolName copy];
    _emptyTitle = [title copy];
    _emptyMessage = [message copy];
    [_grid setEmptyStateSymbolName:symbolName title:title message:message];
}

- (void)setSortOptions:(NSArray<NSString *> *)sortOptions
{
    _sortOptions = [sortOptions copy];
    NSUserDefaults * const defaults = NSUserDefaults.standardUserDefaults;
    NSString * const savedKey = [defaults stringForKey:[self defaultsKey:@"SortKey"]];
    _sortKey = [_sortOptions containsObject:savedKey] ? savedKey : _sortOptions.firstObject;
    _sortDescending = [defaults boolForKey:[self defaultsKey:@"SortDescending"]];
}

// MARK: - Chrome

- (NSString *)sectionTitle
{
    if (self.topViewController != self.rootViewController && self.topViewController.title.length > 0) {
        return self.topViewController.title;
    }
    return _title;
}

- (NSString *)makeSearchPlaceholder
{
    return [NSString stringWithFormat:_NS("Search %@"), _title];
}

- (BOOL)sectionSupportsViewModes
{
    return self.listColumns != 0 && !self.listOnly;
}

- (nullable NSString *)currentSubtitle
{
    const NSUInteger count = [MacLCLibraryStore.sharedStore countOfCollection:_collection];
    /* An empty section says so in its empty state, not as "0 playlists". */
    if (count == 0) {
        return nil;
    }
    return MacLCCountString(count, _countSingular, _countPlural);
}

- (void)setViewMode:(MacLCLibraryViewMode)viewMode
{
    [super setViewMode:viewMode];
    [NSUserDefaults.standardUserDefaults setInteger:viewMode forKey:[self defaultsKey:@"ViewMode"]];
}

// MARK: - Root

- (NSViewController *)makeRootViewControllerForViewMode:(MacLCLibraryViewMode)viewMode
{
    const BOOL list = self.listOnly || (viewMode == MacLCLibraryViewModeList && self.listColumns != 0);
    if (list) {
        if (_list == nil) {
            _list = [[MacLCLibraryListRootViewController alloc] initWithNibName:nil bundle:nil];
            _list.listController = [[MacLCTrackListController alloc]
                initWithColumns:self.listColumns
                   autosaveName:[self defaultsKey:@"Columns"]];
            _list.listController.sortable = self.listOnly;
        }
        [self refreshContents];
        return _list;
    }
    if (_grid == nil) {
        _grid = [[MacLCLibraryGridViewController alloc] initWithShape:_shape subtitleStyle:_subtitleStyle];
        if (_emptyTitle != nil) {
            [_grid setEmptyStateSymbolName:_emptySymbol title:_emptyTitle message:_emptyMessage];
            [_grid setEmptyStateActionTitle:_emptyActionTitle handler:_emptyActionHandler];
        }
        __weak typeof(self) weakSelf = self;
        if (self.detailFactory != nil) {
            _grid.openHandler = ^(id<VLCMediaLibraryItemProtocol> const item) {
                [weakSelf openItem:item];
            };
        }
    }
    [self refreshContents];
    return _grid;
}

- (void)openItem:(id<VLCMediaLibraryItemProtocol>)item
{
    NSViewController * const detail = self.detailFactory != nil ? self.detailFactory(item) : nil;
    if (detail != nil) {
        [self pushViewController:detail];
    }
}

- (nullable NSViewController *)detailViewControllerForItem:(id<VLCMediaLibraryItemProtocol>)item
{
    return self.detailFactory != nil ? self.detailFactory(item) : nil;
}

- (void)showItem:(id<VLCMediaLibraryItemProtocol>)item
{
    [self view];
    while (self.canGoBack) {
        [self popViewController];
    }
    NSViewController * const detail = [self detailViewControllerForItem:item];
    if (detail != nil) {
        [self pushViewController:detail];
    } else {
        [_grid showItem:item];
    }
}

// MARK: - Contents

- (void)storeDidChange:(NSNotification *)notification
{
    NSSet<NSNumber *> * const changed = notification.userInfo[MacLCLibraryStoreChangedCollectionsKey];
    if (changed == nil || [changed containsObject:@(_collection)]) {
        [self refreshContents];
    }
}

- (void)refreshContents
{
    NSArray * const items = [MacLCLibraryStore.sharedStore itemsInCollection:_collection];
    _sortedItems = [self sortedItems:items];
    _grid.items = _sortedItems;
    if (_list != nil) {
        NSMutableArray<VLCMediaLibraryMediaItem *> * const media = [NSMutableArray arrayWithCapacity:_sortedItems.count];
        for (id const item in _sortedItems) {
            if ([item isKindOfClass:VLCMediaLibraryMediaItem.class]) {
                [media addObject:item];
            }
        }
        _list.listController.items = media;
        [self updateListEmptyState];
    }
    [self chromeDidChange];
}

- (void)updateListEmptyState
{
    if (_list == nil || !_list.isViewLoaded) {
        return;
    }
    MacLCEmptyStateView *emptyState = nil;
    if (_list.listController.numberOfVisibleRows == 0) {
        if (_searchString.length > 0) {
            emptyState = [MacLCEmptyStateView emptyStateWithSymbolName:@"magnifyingglass"
                                                                 title:[NSString stringWithFormat:_NS("No Results for “%@”"), _searchString]
                                                               message:_NS("Check the spelling or try a new search.")];
        } else if (_emptyTitle != nil && MacLCLibraryStore.sharedStore.loaded) {
            emptyState = [MacLCEmptyStateView emptyStateWithSymbolName:_emptySymbol ?: @"square.dashed"
                                                                 title:_emptyTitle
                                                               message:_emptyMessage];
        }
    }
    _list.emptyState = emptyState;
}

- (void)searchStringDidChange:(NSString *)searchString
{
    _searchString = [searchString copy] ?: @"";
    [_grid applySearchString:_searchString];
    [_list.listController applySearchString:_searchString];
    [self updateListEmptyState];
    if (self.topViewController != self.rootViewController
        && [self.topViewController respondsToSelector:@selector(applySearchString:)]) {
        [(id)self.topViewController applySearchString:_searchString];
    }
}

// MARK: - Sorting

- (NSArray *)sortedItems:(NSArray *)items
{
    NSString * const key = _sortKey ?: MacLCSortKeyTitle;
    const BOOL descending = _sortDescending;
    NSArray * const sorted = [items sortedArrayWithOptions:NSSortStable usingComparator:
        ^NSComparisonResult(id<VLCMediaLibraryItemProtocol> const a, id<VLCMediaLibraryItemProtocol> const b) {
            NSComparisonResult result = NSOrderedSame;
            if ([key isEqualToString:MacLCSortKeyDuration]
                && [a isKindOfClass:VLCMediaLibraryMediaItem.class] && [b isKindOfClass:VLCMediaLibraryMediaItem.class]) {
                const int64_t da = ((VLCMediaLibraryMediaItem *)a).duration, db = ((VLCMediaLibraryMediaItem *)b).duration;
                result = da == db ? NSOrderedSame : (da < db ? NSOrderedAscending : NSOrderedDescending);
            } else if ([key isEqualToString:MacLCSortKeyLastPlayed]
                       && [a isKindOfClass:VLCMediaLibraryMediaItem.class] && [b isKindOfClass:VLCMediaLibraryMediaItem.class]) {
                /* Most recent first reads as "ascending" for this key. */
                const time_t pa = ((VLCMediaLibraryMediaItem *)a).lastPlayedDate, pb = ((VLCMediaLibraryMediaItem *)b).lastPlayedDate;
                result = pa == pb ? NSOrderedSame : (pa > pb ? NSOrderedAscending : NSOrderedDescending);
            } else if ([key isEqualToString:MacLCSortKeyYear]
                       && [a isKindOfClass:VLCMediaLibraryAlbum.class] && [b isKindOfClass:VLCMediaLibraryAlbum.class]) {
                const unsigned int ya = ((VLCMediaLibraryAlbum *)a).year, yb = ((VLCMediaLibraryAlbum *)b).year;
                result = ya == yb ? NSOrderedSame : (ya > yb ? NSOrderedAscending : NSOrderedDescending);
            } else if ([key isEqualToString:MacLCSortKeyArtist]
                       && [a isKindOfClass:VLCMediaLibraryAlbum.class] && [b isKindOfClass:VLCMediaLibraryAlbum.class]) {
                result = [((VLCMediaLibraryAlbum *)a).artistName ?: @""
                          localizedStandardCompare:((VLCMediaLibraryAlbum *)b).artistName ?: @""];
            }
            if (result == NSOrderedSame) {
                result = [a.displayString ?: @"" localizedStandardCompare:b.displayString ?: @""];
            }
            return descending ? -result : result;
        }];
    return sorted;
}

+ (NSString *)titleForSortKey:(NSString *)key
{
    if ([key isEqualToString:MacLCSortKeyDuration]) {
        return _NS("Duration");
    }
    if ([key isEqualToString:MacLCSortKeyLastPlayed]) {
        return _NS("Recently Played");
    }
    if ([key isEqualToString:MacLCSortKeyYear]) {
        return _NS("Year");
    }
    if ([key isEqualToString:MacLCSortKeyArtist]) {
        return _NS("Artist");
    }
    return _NS("Title");
}

- (nullable NSMenu *)makeSortMenu
{
    if (self.listOnly || self.sortOptions.count == 0) {
        return nil;
    }
    NSMenu * const menu = [[NSMenu alloc] initWithTitle:_NS("Sort By")];
    for (NSString * const key in self.sortOptions) {
        NSMenuItem * const item = [menu addItemWithTitle:[MacLCLibraryGridSection titleForSortKey:key]
                                                  action:@selector(sortKeyChosen:)
                                           keyEquivalent:@""];
        item.target = self;
        item.representedObject = key;
        item.state = [key isEqualToString:_sortKey] ? NSControlStateValueOn : NSControlStateValueOff;
    }
    [menu addItem:NSMenuItem.separatorItem];
    NSMenuItem * const ascending = [menu addItemWithTitle:_NS("Ascending") action:@selector(sortOrderChosen:) keyEquivalent:@""];
    ascending.target = self;
    ascending.tag = 0;
    ascending.state = _sortDescending ? NSControlStateValueOff : NSControlStateValueOn;
    NSMenuItem * const descending = [menu addItemWithTitle:_NS("Descending") action:@selector(sortOrderChosen:) keyEquivalent:@""];
    descending.target = self;
    descending.tag = 1;
    descending.state = _sortDescending ? NSControlStateValueOn : NSControlStateValueOff;
    return menu;
}

- (void)sortKeyChosen:(NSMenuItem *)sender
{
    _sortKey = sender.representedObject;
    [NSUserDefaults.standardUserDefaults setObject:_sortKey forKey:[self defaultsKey:@"SortKey"]];
    [self refreshContents];
    [self chromeDidChange]; // the toolbar rebuilds its sort menu with the new check mark
}

- (void)sortOrderChosen:(NSMenuItem *)sender
{
    _sortDescending = sender.tag == 1;
    [NSUserDefaults.standardUserDefaults setBool:_sortDescending forKey:[self defaultsKey:@"SortDescending"]];
    [self refreshContents];
    [self chromeDidChange];
}

@end
