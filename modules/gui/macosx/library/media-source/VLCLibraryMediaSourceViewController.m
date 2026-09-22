/*****************************************************************************
 * VLCLibraryMediaSourceViewController.m: MacOS X interface module
 *****************************************************************************
 * Copyright (C) 2023 VLC authors and VideoLAN
 *
 * Authors: Claudio Cambra <developer@claudiocambra.com>
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

#import "VLCLibraryMediaSourceViewController.h"

#import "VLCLibraryMediaSourceViewNavigationStack.h"
#import "VLCMediaSourceBaseDataSource.h"
#import "VLCMediaSourceDataSource.h"

#import "extensions/NSFont+VLCAdditions.h"
#import "extensions/NSString+Helpers.h"
#import "extensions/NSTextField+VLCAdditions.h"
#import "extensions/NSView+VLCAdditions.h"
#import "extensions/NSWindow+VLCAdditions.h"

#import "library/VLCInputNodePathControl.h"
#import "library/VLCLibraryCollectionView.h"
#import "library/VLCLibraryCollectionView.h"
#import "library/VLCLibraryCollectionViewFlowLayout.h"
#import "library/VLCLibraryCollectionViewFlowLayout.h"
#import "library/VLCLibraryController.h"
#import "library/VLCLibrarySegment.h"
#import "library/VLCLibraryWindow.h"

#import "main/VLCMain.h"

#import "MacLCBrowseHeaderView.h"
#import "MacLCBrowseEmptyView.h"

#import "views/VLCLoadingOverlayView.h"
#import "views/VLCMediaItemCollectionViewItem.h"
#import "views/VLCUIUnits.h"

@interface VLCLibraryMediaSourceViewController () <MacLCBrowseHeaderViewDelegate>
{
    VLCLoadingOverlayView *_loadingOverlayView;
    MacLCBrowseHeaderView *_browseHeaderView;
    NSLayoutConstraint *_browseHeaderHeightConstraint;
    MacLCBrowseEmptyView *_browseEmptyView;
    id _keyEventMonitor;
}

@end

@implementation VLCLibraryMediaSourceViewController

- (MacLCBrowseHeaderView *)browseHeaderView
{
    return _browseHeaderView;
}

- (MacLCBrowseEmptyView *)browseEmptyView
{
    return _browseEmptyView;
}

// The shared mediaSourceView is the source of truth for the active overlay.
- (nullable VLCLoadingOverlayView *)currentLoadingOverlayInMediaSourceView
{
    for (NSView * const subview in self.mediaSourceView.subviews) {
        if ([subview isKindOfClass:VLCLoadingOverlayView.class]) {
            return (VLCLoadingOverlayView *)subview;
        }
    }
    return nil;
}

- (instancetype)initWithLibraryWindow:(VLCLibraryWindow *)libraryWindow
{
    self = [super initWithLibraryWindow:libraryWindow];
    if (self) {
        [self setupPropertiesFromLibraryWindow:libraryWindow];
        [self setupPathControlView];
        [self setupBaseDataSource];
        [self setupCollectionView];
        [self setupMediaSourceLibraryViews];
        [self setupPlaceholderLabel];

        NSNotificationCenter * const defaultCenter = NSNotificationCenter.defaultCenter;
        [defaultCenter addObserver:self
                          selector:@selector(updatePlaceholderLabel:)
                              name:VLCMediaSourceBaseDataSourceNodeChanged
                            object:nil];
        [defaultCenter addObserver:self
                          selector:@selector(updatePlaceholderLabel:)
                              name:VLCMediaSourceDataSourceNodeChanged
                            object:nil];
        [defaultCenter addObserver:self
                          selector:@selector(mediaSourceLoadingStarted:)
                              name:VLCMediaSourceDataSourceLoadingStarted
                            object:nil];
        [defaultCenter addObserver:self
                          selector:@selector(mediaSourceLoadingEnded:)
                              name:VLCMediaSourceDataSourceLoadingEnded
                            object:nil];
    }
    return self;
}

- (void)dealloc
{
    if (_keyEventMonitor != nil) {
        [NSEvent removeMonitor:_keyEventMonitor];
        _keyEventMonitor = nil;
    }
    [NSNotificationCenter.defaultCenter removeObserver:self];
    [_browseEmptyView removeFromSuperview];
    [_browseHeaderView removeFromSuperview];
    [self.browsePlaceholderLabel removeFromSuperview];
}

- (void)setupPropertiesFromLibraryWindow:(VLCLibraryWindow *)libraryWindow
{
    NSParameterAssert(libraryWindow);
    _mediaSourceView = libraryWindow.mediaSourceView;
    _mediaSourceTableView = libraryWindow.mediaSourceTableView;
    _collectionView = libraryWindow.mediaSourceCollectionView;
    _collectionViewScrollView = libraryWindow.mediaSourceCollectionViewScrollView;
    _tableView = libraryWindow.mediaSourceTableView;
    _tableViewScrollView = libraryWindow.mediaSourceTableViewScrollView;
    _homeButton = libraryWindow.mediaSourceHomeButton;
    _pathControl = libraryWindow.mediaSourcePathControl;
    _pathControlVisualEffectView = libraryWindow.mediaSourcePathControlVisualEffectView;
    _gridVsListSegmentedControl = libraryWindow.gridVsListSegmentedControl;
}

- (void)setupBaseDataSource
{
    _baseDataSource = [[VLCMediaSourceBaseDataSource alloc] init];
    _baseDataSource.browseHeaderView = _browseHeaderView;
    _baseDataSource.collectionView = _collectionView;
    _baseDataSource.collectionViewScrollView = _collectionViewScrollView;
    _baseDataSource.homeButton = _homeButton;
    _baseDataSource.pathControl = _pathControl;
    _baseDataSource.pathControlContainerView = self.pathControlContainerView;
    _baseDataSource.tableView = _tableView;
    _baseDataSource.tableViewScrollView = _tableViewScrollView;
    [_baseDataSource setupViews];

    _navigationStack = [[VLCLibraryMediaSourceViewNavigationStack alloc] init];
    self.navigationStack.libraryWindow = self.libraryWindow;
    self.navigationStack.baseDataSource = self.baseDataSource;

    self.baseDataSource.navigationStack = self.navigationStack;
    [self.baseDataSource updateHeaderPathBreadcrumbs];
}

- (void)setupCollectionView
{
    self.collectionView.allowsMultipleSelection = YES;

    VLCLibraryCollectionViewFlowLayout * const mediaSourceCollectionViewLayout = VLCLibraryCollectionViewFlowLayout.standardLayout;
    self.collectionView.collectionViewLayout = mediaSourceCollectionViewLayout;
    mediaSourceCollectionViewLayout.itemSize = VLCUIUnits.defaultVideoItemCollectionViewItemSize;

    __weak typeof(self) weakSelf = self;
    _keyEventMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown handler:^NSEvent *(NSEvent *event) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return event;
        }

        NSWindow * const window = strongSelf.collectionView.window;
        if (window == nil || !window.isKeyWindow) {
            return event;
        }

        NSResponder * const firstResponder = window.firstResponder;
        const BOOL isCollectionViewFocused = (firstResponder == strongSelf.collectionView) ||
            ([firstResponder isKindOfClass:NSView.class] && [(NSView *)firstResponder isDescendantOf:strongSelf.collectionView]);
        NSTableView * const tableView = strongSelf.mediaSourceTableView;
        const BOOL isTableViewFocused = tableView != nil && firstResponder == tableView;
        if (!isCollectionViewFocused && !isTableViewFocused) {
            return event;
        }

        const BOOL isReturn = event.keyCode == 36 || event.keyCode == 76 ||
            (event.characters.length > 0 &&
             ([event.characters characterAtIndex:0] == '\r' || [event.characters characterAtIndex:0] == '\n'));
        if (!isReturn) {
            return event;
        }
        if (isCollectionViewFocused && [strongSelf openSelectedCollectionItem]) {
            return nil;
        }
        /* The table's double action belongs to the data source on screen. */
        if (isTableViewFocused && tableView.selectedRow >= 0 && tableView.doubleAction != NULL &&
            [NSApp sendAction:tableView.doubleAction to:tableView.target from:tableView]) {
            return nil;
        }
        return event;
    }];
}

- (BOOL)openSelectedCollectionItem
{
    NSSet<NSIndexPath *> * const selection = self.collectionView.selectionIndexPaths;
    if (selection.count == 0) {
        return NO;
    }
    NSIndexPath * const selectedIndexPath = selection.anyObject;

    if (self.baseDataSource.childDataSource != nil) {
        [self.baseDataSource.childDataSource openItemAtIndexPath:selectedIndexPath];
        return YES;
    } else {
        [self.baseDataSource openHomeItemAtIndexPath:selectedIndexPath];
        return YES;
    }
}

- (void)setupMediaSourceLibraryViews
{
    _mediaSourceTableView.rowHeight = 32.0;

    _collectionViewScrollView.automaticallyAdjustsContentInsets = NO;
    _collectionViewScrollView.scrollerInsets = VLCUIUnits.libraryViewScrollViewScrollerInsets;

    _tableViewScrollView.automaticallyAdjustsContentInsets = NO;
    _tableViewScrollView.scrollerInsets = NSEdgeInsetsMake(0, 0, -VLCUIUnits.libraryViewScrollViewContentInsets.bottom, 0);

    [self applyBrowseHeaderLayoutForMode:_browseHeaderView.mode];
}

/* The content starts below the header, whose height depends on its mode. */
- (void)applyBrowseHeaderLayoutForMode:(MacLCBrowseHeaderMode)mode
{
    const CGFloat headerHeight = [MacLCBrowseHeaderView preferredHeightForMode:mode];
    _browseHeaderHeightConstraint.constant = headerHeight;

    const CGFloat topInset = VLCUIUnits.libraryWindowContentSafeTopInset + 8.0 + headerHeight +
        (mode == MacLCBrowseHeaderModeHome ? 6.0 : 2.0);
    const CGFloat bottomInset = VLCUIUnits.libraryViewScrollViewContentInsets.bottom;
    _collectionViewScrollView.contentInsets = NSEdgeInsetsMake(topInset, 0, bottomInset, 0);
    _tableViewScrollView.contentInsets = NSEdgeInsetsMake(topInset, 0, bottomInset, 0);
}

- (void)setupPlaceholderLabel
{
    _browsePlaceholderLabel = [NSTextField defaultLabelWithString:@""];
    self.browsePlaceholderLabel.hidden = YES;

    _browseEmptyView = [[MacLCBrowseEmptyView alloc] initWithFrame:NSMakeRect(0, 0, 360.0, 160.0)];
    _browseEmptyView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.mediaSourceView addSubview:_browseEmptyView];
    [NSLayoutConstraint activateConstraints:@[
        [_browseEmptyView.centerXAnchor constraintEqualToAnchor:self.mediaSourceView.centerXAnchor],
        [_browseEmptyView.centerYAnchor constraintEqualToAnchor:self.mediaSourceView.centerYAnchor constant:20.0],
        [_browseEmptyView.widthAnchor constraintEqualToConstant:360.0],
        [_browseEmptyView.heightAnchor constraintEqualToConstant:160.0],
    ]];
    [self updatePlaceholderLabel:nil];
}

- (void)setupPathControlView
{
    self.pathControlVisualEffectView.hidden = YES;
    self.homeButton.hidden = YES;
    self.pathControl.hidden = YES;

    _browseHeaderView = [[MacLCBrowseHeaderView alloc] initWithFrame:NSMakeRect(0, 0, self.mediaSourceView.bounds.size.width, 44.0)];
    _browseHeaderView.translatesAutoresizingMaskIntoConstraints = NO;
    _browseHeaderView.delegate = self;
    [self.mediaSourceView addSubview:_browseHeaderView];

    _browseHeaderHeightConstraint =
        [_browseHeaderView.heightAnchor constraintEqualToConstant:[MacLCBrowseHeaderView preferredHeightForMode:_browseHeaderView.mode]];
    [NSLayoutConstraint activateConstraints:@[
        _browseHeaderHeightConstraint,
        [_browseHeaderView.topAnchor constraintEqualToAnchor:self.mediaSourceView.topAnchor
                                                    constant:VLCUIUnits.libraryWindowContentSafeTopInset + 8.0],
        [_browseHeaderView.leadingAnchor constraintEqualToAnchor:self.mediaSourceView.leadingAnchor
                                                        constant:20.0],
        [_browseHeaderView.trailingAnchor constraintLessThanOrEqualToAnchor:self.mediaSourceView.trailingAnchor
                                                                   constant:-20.0],
    ]];
}

- (void)updatePlaceholderLabel:(NSNotification *)notification
{
    _loadingOverlayView = [self currentLoadingOverlayInMediaSourceView];
    const BOOL isBrowsingFolder = (self.baseDataSource.childDataSource != nil);
    const BOOL hasItems = self.baseDataSource.hasDisplayedItems;
    _browseEmptyView.hidden = !isBrowsingFolder || hasItems || (_loadingOverlayView != nil);
    self.browsePlaceholderLabel.hidden = YES;
}

- (void)prepareLoadingOverlay
{
    _loadingOverlayView = [self currentLoadingOverlayInMediaSourceView];

    if (_loadingOverlayView != nil)
        return;
    if (!_loadingOverlayView)
        _loadingOverlayView = [[VLCLoadingOverlayView alloc] init];
    _loadingOverlayView.translatesAutoresizingMaskIntoConstraints = NO;
    _loadingOverlayView.wantsLayer = YES;
    _loadingOverlayView.alphaValue = 0.0;
    [self.mediaSourceView addSubview:_loadingOverlayView];
    [_loadingOverlayView applyConstraintsToFillSuperview];
    [_loadingOverlayView.indicator startAnimation:self];
}

- (void)mediaSourceLoadingStarted:(NSNotification *)notification
{
    [_browseHeaderView startLoading];

    if (!self.baseDataSource.hasDisplayedItems) {
        [self prepareLoadingOverlay];
        _loadingOverlayView.alphaValue = 1.0;
    }
    [self updatePlaceholderLabel:nil];
}

- (void)mediaSourceLoadingEnded:(NSNotification *)notification
{
    [_browseHeaderView stopLoading];

    _loadingOverlayView = [self currentLoadingOverlayInMediaSourceView];
    if (_loadingOverlayView == nil) {
        [self updatePlaceholderLabel:nil];
        return;
    }

    [NSAnimationContext runAnimationGroup:^(NSAnimationContext * __unused context) {
        _loadingOverlayView.animator.alphaValue = 0.0;
    } completionHandler:^{
        [_loadingOverlayView removeFromSuperview];
        [_loadingOverlayView.indicator stopAnimation:self];
        [self updatePlaceholderLabel:nil];
    }];
}

- (NSView *)pathControlContainerView
{
    return self.pathControlVisualEffectView;
}

#pragma mark - MacLCBrowseHeaderViewDelegate

- (void)browseHeaderDidClickHome:(MacLCBrowseHeaderView *)headerView
{
    [self.baseDataSource returnHome];
}

- (void)browseHeader:(MacLCBrowseHeaderView *)headerView didClickSegmentAtIndex:(NSInteger)index
{
    [self.baseDataSource navigateToBreadcrumbIndex:index];
}

- (void)browseHeader:(MacLCBrowseHeaderView *)headerView didChangeMode:(MacLCBrowseHeaderMode)mode
{
    [self applyBrowseHeaderLayoutForMode:mode];
}

- (void)presentBrowseView
{
    [self.libraryWindow displayLibraryView:self.mediaSourceView];
    _loadingOverlayView = [self currentLoadingOverlayInMediaSourceView];
    [self mediaSourceLoadingEnded:nil];

    _baseDataSource.mediaSourceMode = VLCMediaSourceModeLAN;
    [_baseDataSource reloadViews];
    [_baseDataSource updateHeaderPathBreadcrumbs];
}

- (void)browseFolderByMrl:(NSString *)mrl
{
    [self presentBrowseView];
    [self.baseDataSource browseFolderByMrl:mrl];
}

@end
