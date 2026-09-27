/*****************************************************************************
 * MacLCLibraryGridViewController.m: the artwork grid shared by the sections
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

#import "medialib/sections/MacLCLibraryGridViewController.h"

#import "extensions/NSString+Helpers.h"
#import "library/VLCLibraryDataTypes.h"
#import "medialib/components/MacLCCollectionLayout.h"
#import "medialib/components/MacLCEmptyStateView.h"
#import "medialib/data/MacLCLibraryActions.h"
#import "medialib/data/MacLCLibraryStore.h"

static NSString * const MacLCGridSectionIdentifier = @"grid";

/* Return opens or plays the selection, like a double-click. */
@interface MacLCLibraryGridCollectionView : NSCollectionView
@property (nonatomic, copy, nullable) void (^returnHandler)(void);
@end

@implementation MacLCLibraryGridCollectionView

- (void)keyDown:(NSEvent *)event
{
    if ((event.keyCode == 36 || event.keyCode == 76) && self.returnHandler != nil) {
        self.returnHandler();
        return;
    }
    [super keyDown:event];
}

@end

@interface MacLCLibraryGridViewController () <NSCollectionViewDelegate>
{
    MacLCArtworkShape _shape;
    MacLCCardSubtitleStyle _subtitleStyle;
    NSScrollView *_scrollView;
    MacLCLibraryGridCollectionView *_collectionView;
    NSCollectionViewDiffableDataSource<NSString *, MacLCLibraryItemID> *_dataSource;
    NSMutableDictionary<MacLCLibraryItemID, id<VLCMediaLibraryItemProtocol>> *_itemsByID;
    NSArray<id<VLCMediaLibraryItemProtocol>> *_visibleItems;
    NSString *_searchString;
    NSString *_emptySymbolName;
    NSString *_emptyTitle;
    NSString *_emptyMessage;
    NSString *_emptyActionTitle;
    void (^_emptyActionHandler)(void);
    MacLCEmptyStateView *_emptyStateView;
}
@end

@implementation MacLCLibraryGridViewController

- (instancetype)initWithShape:(MacLCArtworkShape)shape subtitleStyle:(MacLCCardSubtitleStyle)subtitleStyle
{
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _shape = shape;
        _subtitleStyle = subtitleStyle;
        _items = @[];
        _visibleItems = @[];
        _itemsByID = [NSMutableDictionary dictionary];
        _searchString = @"";
    }
    return self;
}

- (void)dealloc
{
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)loadView
{
    NSView * const root = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 800, 600)];

    _collectionView = [[MacLCLibraryGridCollectionView alloc] initWithFrame:root.bounds];
    _collectionView.collectionViewLayout =
        [MacLCCollectionLayout gridLayoutWithShape:_shape
                                       hasSubtitle:_subtitleStyle != MacLCCardSubtitleStyleNone];
    _collectionView.selectable = YES;
    _collectionView.allowsMultipleSelection = YES;
    _collectionView.allowsEmptySelection = YES;
    _collectionView.backgroundColors = @[NSColor.clearColor];
    _collectionView.delegate = self;
    [_collectionView registerClass:MacLCMediaCardItem.class forItemWithIdentifier:MacLCMediaCardItemIdentifier];
    [_collectionView setDraggingSourceOperationMask:NSDragOperationCopy forLocal:NO];
    [_collectionView setDraggingSourceOperationMask:NSDragOperationCopy | NSDragOperationGeneric forLocal:YES];
    __weak typeof(self) weakSelf = self;
    _collectionView.returnHandler = ^{
        [weakSelf activateSelection];
    };

    _scrollView = [[NSScrollView alloc] initWithFrame:root.bounds];
    _scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    _scrollView.documentView = _collectionView;
    _scrollView.drawsBackground = NO;
    _scrollView.hasVerticalScroller = YES;
    _scrollView.autohidesScrollers = YES;
    _scrollView.automaticallyAdjustsContentInsets = YES;
    [root addSubview:_scrollView];
    [NSLayoutConstraint activateConstraints:@[
        [_scrollView.topAnchor constraintEqualToAnchor:root.topAnchor],
        [_scrollView.bottomAnchor constraintEqualToAnchor:root.bottomAnchor],
        [_scrollView.leadingAnchor constraintEqualToAnchor:root.leadingAnchor],
        [_scrollView.trailingAnchor constraintEqualToAnchor:root.trailingAnchor],
    ]];

    self.view = root;
    [self configureDataSource];
    [self applySnapshotAnimated:NO];
}

- (NSCollectionView *)collectionView
{
    [self view];
    return _collectionView;
}

- (void)configureDataSource
{
    __weak typeof(self) weakSelf = self;
    const MacLCArtworkShape shape = _shape;
    const MacLCCardSubtitleStyle subtitleStyle = _subtitleStyle;
    _dataSource = [[NSCollectionViewDiffableDataSource alloc]
        initWithCollectionView:_collectionView
                  itemProvider:^NSCollectionViewItem * _Nullable(NSCollectionView * const collectionView,
                                                                 NSIndexPath * const indexPath,
                                                                 MacLCLibraryItemID const identifier) {
        MacLCLibraryGridViewController * const strongSelf = weakSelf;
        id<VLCMediaLibraryItemProtocol> const item = strongSelf != nil ? strongSelf->_itemsByID[identifier] : nil;
        MacLCMediaCardItem * const card = [collectionView makeItemWithIdentifier:MacLCMediaCardItemIdentifier
                                                                    forIndexPath:indexPath];
        if (item != nil) {
            [card configureWithItem:item shape:shape subtitleStyle:subtitleStyle];
            card.activationHandler = ^(id<VLCMediaLibraryItemProtocol> const activated) {
                [weakSelf activateItem:activated];
            };
        }
        return card;
    }];

    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(itemDidUpdate:)
                                               name:MacLCLibraryStoreItemDidUpdateNotification
                                             object:nil];
}

// MARK: - Contents

- (void)setItems:(NSArray<id<VLCMediaLibraryItemProtocol>> *)items
{
    _items = [items copy] ?: @[];
    [_itemsByID removeAllObjects];
    for (id<VLCMediaLibraryItemProtocol> const item in _items) {
        _itemsByID[MacLCLibraryItemIdentifier(item)] = item;
    }
    if (self.isViewLoaded) {
        [self applySnapshotAnimated:YES];
    }
}

- (void)applySearchString:(NSString *)searchString
{
    _searchString = [searchString copy] ?: @"";
    if (self.isViewLoaded) {
        [self applySnapshotAnimated:NO];
    }
}

- (NSArray<id<VLCMediaLibraryItemProtocol>> *)visibleItems
{
    return _visibleItems;
}

+ (BOOL)item:(id<VLCMediaLibraryItemProtocol>)item matches:(NSString *)query
{
    if ([item.displayString localizedStandardContainsString:query]) {
        return YES;
    }
    if ([item isKindOfClass:VLCMediaLibraryAlbum.class]) {
        return [((VLCMediaLibraryAlbum *)item).artistName localizedStandardContainsString:query];
    }
    if ([item isKindOfClass:VLCMediaLibraryMediaItem.class]) {
        return [item.primaryDetailString localizedStandardContainsString:query];
    }
    return NO;
}

- (void)applySnapshotAnimated:(BOOL)animated
{
    NSString * const query = [_searchString stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    NSMutableArray * const visible = [NSMutableArray arrayWithCapacity:_items.count];
    NSMutableArray<MacLCLibraryItemID> * const identifiers = [NSMutableArray arrayWithCapacity:_items.count];
    NSMutableSet<MacLCLibraryItemID> * const seen = [NSMutableSet setWithCapacity:_items.count];
    for (id<VLCMediaLibraryItemProtocol> const item in _items) {
        if (query.length > 0 && ![MacLCLibraryGridViewController item:item matches:query]) {
            continue;
        }
        MacLCLibraryItemID const identifier = MacLCLibraryItemIdentifier(item);
        if ([seen containsObject:identifier]) {
            continue;
        }
        [seen addObject:identifier];
        [identifiers addObject:identifier];
        [visible addObject:item];
    }
    _visibleItems = visible;

    NSDiffableDataSourceSnapshot<NSString *, MacLCLibraryItemID> * const snapshot =
        [[NSDiffableDataSourceSnapshot alloc] init];
    [snapshot appendSectionsWithIdentifiers:@[MacLCGridSectionIdentifier]];
    [snapshot appendItemsWithIdentifiers:identifiers intoSectionWithIdentifier:MacLCGridSectionIdentifier];

    /* Items whose metadata changed keep their identifier: reconfigure the
     * ones on screen so titles, progress and badges stay current. */
    const BOOL animate = animated && self.view.window.isVisible
        && !NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion;
    [_dataSource applySnapshot:snapshot animatingDifferences:animate];
    [self refreshVisibleCards];
    [self updateEmptyStateWithQuery:query];
}

- (void)refreshVisibleCards
{
    for (NSIndexPath * const indexPath in _collectionView.indexPathsForVisibleItems) {
        MacLCMediaCardItem * const card = (MacLCMediaCardItem *)[_collectionView itemAtIndexPath:indexPath];
        MacLCLibraryItemID const identifier = [_dataSource itemIdentifierForIndexPath:indexPath];
        id<VLCMediaLibraryItemProtocol> const item = identifier != nil ? _itemsByID[identifier] : nil;
        if ([card isKindOfClass:MacLCMediaCardItem.class] && item != nil && card.libraryItem != item) {
            [card configureWithItem:item shape:_shape subtitleStyle:_subtitleStyle];
        }
    }
}

- (void)itemDidUpdate:(NSNotification *)notification
{
    /* The store refetches the list right after; nothing to do until then. */
}

// MARK: - Empty state

- (void)setEmptyStateSymbolName:(NSString *)symbolName title:(NSString *)title message:(nullable NSString *)message
{
    _emptySymbolName = [symbolName copy];
    _emptyTitle = [title copy];
    _emptyMessage = [message copy];
    if (self.isViewLoaded) {
        [self updateEmptyStateWithQuery:_searchString];
    }
}

- (void)setEmptyStateActionTitle:(NSString *)title handler:(void (^)(void))handler
{
    _emptyActionTitle = [title copy];
    _emptyActionHandler = [handler copy];
    if (self.isViewLoaded) {
        [self updateEmptyStateWithQuery:_searchString];
    }
}

- (void)updateEmptyStateWithQuery:(NSString *)query
{
    [_emptyStateView removeFromSuperview];
    _emptyStateView = nil;
    if (_visibleItems.count > 0) {
        return;
    }
    if (query.length > 0) {
        _emptyStateView = [MacLCEmptyStateView emptyStateWithSymbolName:@"magnifyingglass"
                                                                  title:[NSString stringWithFormat:_NS("No Results for “%@”"), query]
                                                                message:_NS("Check the spelling or try a new search.")];
    } else if (_emptyTitle != nil && MacLCLibraryStore.sharedStore.loaded) {
        _emptyStateView = [MacLCEmptyStateView emptyStateWithSymbolName:_emptySymbolName ?: @"square.dashed"
                                                                  title:_emptyTitle
                                                                message:_emptyMessage];
        if (_emptyActionTitle != nil && _emptyActionHandler != nil) {
            [_emptyStateView addButtonWithTitle:_emptyActionTitle prominent:YES action:_emptyActionHandler];
        }
    }
    if (_emptyStateView == nil) {
        return;
    }
    _emptyStateView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_emptyStateView];
    [NSLayoutConstraint activateConstraints:@[
        [_emptyStateView.centerXAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.centerXAnchor],
        [_emptyStateView.centerYAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.centerYAnchor],
        [_emptyStateView.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.view.leadingAnchor constant:24.0],
        [_emptyStateView.trailingAnchor constraintLessThanOrEqualToAnchor:self.view.trailingAnchor constant:-24.0],
    ]];
}

// MARK: - Activation

- (void)activateItem:(id<VLCMediaLibraryItemProtocol>)item
{
    if (self.openHandler != nil) {
        self.openHandler(item);
        return;
    }
    NSUInteger index = [_visibleItems indexOfObjectPassingTest:^BOOL(id<VLCMediaLibraryItemProtocol> const candidate,
                                                                     NSUInteger idx, BOOL * const stop) {
        return candidate.libraryID == item.libraryID && candidate.class == item.class;
    }];
    if (index == NSNotFound) {
        [MacLCLibraryActions playItems:@[item] startingAt:0];
    } else {
        [MacLCLibraryActions playItems:_visibleItems startingAt:index];
    }
}

- (void)activateSelection
{
    NSIndexPath * const first = [_collectionView.selectionIndexPaths.allObjects sortedArrayUsingSelector:@selector(compare:)].firstObject;
    MacLCLibraryItemID const identifier = first != nil ? [_dataSource itemIdentifierForIndexPath:first] : nil;
    id<VLCMediaLibraryItemProtocol> const item = identifier != nil ? _itemsByID[identifier] : nil;
    if (item != nil) {
        [self activateItem:item];
    }
}

- (void)showItem:(id<VLCMediaLibraryItemProtocol>)item
{
    [self view];
    NSIndexPath * const indexPath = [_dataSource indexPathForItemIdentifier:MacLCLibraryItemIdentifier(item)];
    if (indexPath == nil) {
        return;
    }
    NSSet<NSIndexPath *> * const selection = [NSSet setWithObject:indexPath];
    _collectionView.selectionIndexPaths = selection;
    [_collectionView scrollToItemsAtIndexPaths:selection scrollPosition:NSCollectionViewScrollPositionCenteredVertically];
    [self.view.window makeFirstResponder:_collectionView];
}

// MARK: - NSCollectionViewDelegate

- (id<NSPasteboardWriting>)collectionView:(NSCollectionView *)collectionView
       pasteboardWriterForItemAtIndexPath:(NSIndexPath *)indexPath
{
    MacLCLibraryItemID const identifier = [_dataSource itemIdentifierForIndexPath:indexPath];
    id<VLCMediaLibraryItemProtocol> const item = identifier != nil ? _itemsByID[identifier] : nil;
    return item != nil ? [MacLCLibraryActions pasteboardWriterForItem:item] : nil;
}

- (BOOL)collectionView:(NSCollectionView *)collectionView
    canDragItemsAtIndexPaths:(NSSet<NSIndexPath *> *)indexPaths
                   withEvent:(NSEvent *)event
{
    return YES;
}

@end
