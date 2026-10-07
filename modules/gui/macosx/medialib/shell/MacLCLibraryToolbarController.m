/*****************************************************************************
 * MacLCLibraryToolbarController.m: the library window's Liquid Glass toolbar
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

#import "medialib/shell/MacLCLibraryToolbarController.h"

#import "extensions/NSString+Helpers.h"
#import "library/VLCLibrarySegment.h"
#import "library/VLCLibraryWindow.h"
#import "library/VLCLibraryWindowSplitViewController.h"
#import "medialib/sections/MacLCLibrarySectionViewController.h"
#import "medialib/shell/MacLCLibraryRouter.h"

static NSToolbarIdentifier const MacLCLibraryToolbarIdentifier = @"MacLCLibraryToolbar";
static NSToolbarItemIdentifier const MacLCToolbarSidebarSeparator = @"MacLCToolbarSidebarSeparator";
static NSToolbarItemIdentifier const MacLCToolbarInspectorSeparator = @"MacLCToolbarInspectorSeparator";
static NSToolbarItemIdentifier const MacLCToolbarNavigation = @"MacLCToolbarNavigation";
static NSToolbarItemIdentifier const MacLCToolbarViewMode = @"MacLCToolbarViewMode";
static NSToolbarItemIdentifier const MacLCToolbarSort = @"MacLCToolbarSort";
static NSToolbarItemIdentifier const MacLCToolbarSearch = @"MacLCToolbarSearch";
static NSToolbarItemIdentifier const MacLCToolbarUpNext = @"MacLCToolbarUpNext";

static const NSTimeInterval MacLCSearchDebounce = 0.12;

@interface MacLCLibraryToolbarController () <NSSearchFieldDelegate>
{
    __weak VLCLibraryWindow *_libraryWindow;
    NSToolbar *_legacyToolbar;
    NSToolbarItemGroup *_navigationGroup;
    NSToolbarItemGroup *_viewModeGroup;
    NSMenuToolbarItem *_sortItem;
    NSSearchToolbarItem *_searchItem;
    NSString *_pendingSearch;
    BOOL _searchScheduled;
}
@end

@implementation MacLCLibraryToolbarController

- (instancetype)initWithLibraryWindow:(VLCLibraryWindow *)libraryWindow
{
    self = [super init];
    if (self) {
        _libraryWindow = libraryWindow;
        _toolbar = [[NSToolbar alloc] initWithIdentifier:MacLCLibraryToolbarIdentifier];
        _toolbar.delegate = self;
        _toolbar.displayMode = NSToolbarDisplayModeIconOnly;
        _toolbar.allowsUserCustomization = YES;
        _toolbar.autosavesConfiguration = YES;

        NSNotificationCenter * const center = NSNotificationCenter.defaultCenter;
        [center addObserver:self selector:@selector(chromeDidChange:)
                       name:MacLCLibrarySectionChromeDidChangeNotification object:nil];
        [center addObserver:self selector:@selector(chromeDidChange:)
                       name:MacLCLibraryRouterSectionDidChangeNotification object:nil];
        [libraryWindow addObserver:self forKeyPath:@"librarySegmentType" options:0 context:nil];
    }
    return self;
}

- (void)dealloc
{
    [NSNotificationCenter.defaultCenter removeObserver:self];
    [_libraryWindow removeObserver:self forKeyPath:@"librarySegmentType"];
}

- (void)install
{
    VLCLibraryWindow * const window = _libraryWindow;
    /* Keep the XIB toolbar alive: its controls still back a few legacy
     * paths of the Browse section (view mode, filtering). */
    _legacyToolbar = window.toolbar;
    window.toolbar = _toolbar;
    window.toolbarStyle = NSWindowToolbarStyleUnified;
    window.titleVisibility = NSWindowTitleVisible;
    window.titlebarSeparatorStyle = NSTitlebarSeparatorStyleAutomatic;
    window.styleMask |= NSWindowStyleMaskFullSizeContentView;
    [self updateItems];
}

- (void)refreshWindowTitle
{
    MacLCLibrarySectionViewController * const section = [self currentSection];
    if (section != nil && !_libraryWindow.embeddedVideoPlaybackActive) {
        _libraryWindow.title = section.sectionTitle ?: @"";
        _libraryWindow.subtitle = section.sectionSubtitle ?: @"";
    }
    [self updateItems];
}

- (void)focusSearchField
{
    [_searchItem beginSearchInteraction];
    /* When the field is already expanded, make sure typing goes into it. */
    NSSearchField * const field = _searchItem.searchField;
    if (field.window != nil && field.window.firstResponder != field.currentEditor) {
        [field.window makeFirstResponder:field];
    }
}

// MARK: - Current section

- (nullable MacLCLibrarySectionViewController *)currentSection
{
    VLCLibraryWindow * const window = _libraryWindow;
    if (window == nil || ![MacLCLibraryRouter handlesSegmentType:window.librarySegmentType]) {
        return nil;
    }
    return [MacLCLibraryRouter routerForLibraryWindow:window].currentSection;
}

- (BOOL)isBrowsing
{
    const NSInteger segment = _libraryWindow.librarySegmentType;
    return segment == VLCLibraryBrowseSegmentType || segment == VLCLibraryBrowseBookmarkedLocationSubSegmentType;
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    /* Watch hides the title over its pictures (MacLCLibraryRouter); Browse,
     * which the router does not show, gets it back. */
    if (![MacLCLibraryRouter handlesSegmentType:_libraryWindow.librarySegmentType]) {
        _libraryWindow.titleVisibility = NSWindowTitleVisible;
    }
    [self updateItems];
}

- (void)chromeDidChange:(NSNotification *)notification
{
    [self updateItems];
}

- (void)updateItems
{
    MacLCLibrarySectionViewController * const section = [self currentSection];
    const BOOL browsing = [self isBrowsing];

    if (browsing && !_libraryWindow.embeddedVideoPlaybackActive) {
        _libraryWindow.title = _NS("Browse");
        _libraryWindow.subtitle = @"";
    }

    _navigationGroup.subitems.firstObject.enabled = self.canGoBack;
    _navigationGroup.subitems.lastObject.enabled = self.canGoForward;
    _navigationGroup.hidden = section == nil && !browsing;

    _viewModeGroup.hidden = !self.canChangeViewMode;
    if (self.canChangeViewMode) {
        _viewModeGroup.selectedIndex = self.viewMode == MacLCLibraryViewModeList ? 1 : 0;
    }

    NSMenu * const sortMenu = section.sortMenu;
    _sortItem.hidden = sortMenu == nil;
    if (sortMenu != nil) {
        _sortItem.menu = sortMenu;
    }

    NSString * const placeholder = section != nil ? section.searchPlaceholder : _NS("Search");
    _searchItem.searchField.placeholderString = placeholder;
    _searchItem.searchField.accessibilityLabel = placeholder;
}

// MARK: - Actions

- (void)navigate:(NSToolbarItemGroup *)sender
{
    if (sender.selectedIndex == 0) {
        [self goBack];
    } else {
        [self goForward];
    }
}

- (BOOL)canGoBack
{
    MacLCLibrarySectionViewController * const section = [self currentSection];
    return section != nil ? section.canGoBack : [self isBrowsing];
}

- (BOOL)canGoForward
{
    return [self currentSection] == nil && [self isBrowsing];
}

- (void)goBack
{
    MacLCLibrarySectionViewController * const section = [self currentSection];
    if (section != nil) {
        [section goBack];
    } else if ([self isBrowsing]) {
        [_libraryWindow backwardsNavigationAction:self];
    }
    [self updateItems];
}

- (void)goForward
{
    if ([self canGoForward]) {
        [_libraryWindow forwardsNavigationAction:self];
    }
    [self updateItems];
}

- (BOOL)canChangeViewMode
{
    MacLCLibrarySectionViewController * const section = [self currentSection];
    return section != nil ? section.supportsViewModes : [self isBrowsing];
}

- (MacLCLibraryViewMode)viewMode
{
    MacLCLibrarySectionViewController * const section = [self currentSection];
    if (section != nil) {
        return section.viewMode;
    }
    return _libraryWindow.gridVsListSegmentedControl.selectedSegment == 1 ? MacLCLibraryViewModeList
                                                                           : MacLCLibraryViewModeGrid;
}

- (void)showViewMode:(MacLCLibraryViewMode)viewMode
{
    MacLCLibrarySectionViewController * const section = [self currentSection];
    if (section != nil) {
        section.viewMode = viewMode;
    } else if ([self isBrowsing]) {
        NSSegmentedControl * const legacy = _libraryWindow.gridVsListSegmentedControl;
        legacy.selectedSegment = viewMode == MacLCLibraryViewModeList ? 1 : 0;
        [_libraryWindow gridVsListSegmentedControlAction:legacy];
    }
    [self updateItems];
}

- (nullable NSMenu *)sortMenu
{
    return [self currentSection].sortMenu;
}

- (void)viewModeChanged:(NSToolbarItemGroup *)sender
{
    [self showViewMode:sender.selectedIndex == 1 ? MacLCLibraryViewModeList : MacLCLibraryViewModeGrid];
}

- (void)toggleUpNext:(id)sender
{
    [_libraryWindow.splitViewController toggleMultifunctionSidebar:sender];
}

- (void)controlTextDidChange:(NSNotification *)notification
{
    _pendingSearch = _searchItem.searchField.stringValue ?: @"";
    if (_searchScheduled) {
        return;
    }
    _searchScheduled = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(MacLCSearchDebounce * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        self->_searchScheduled = NO;
        [self applySearch:self->_pendingSearch];
    });
}

- (void)searchFieldDidEndSearching:(NSSearchField *)sender
{
    /* A debounced search still pending must not bring the query back. */
    _pendingSearch = @"";
    [self applySearch:@""];
}

- (void)applySearch:(NSString *)searchString
{
    MacLCLibrarySectionViewController * const section = [self currentSection];
    if (section != nil) {
        [section applySearchString:searchString];
        return;
    }
    if ([self isBrowsing]) {
        NSSearchField * const legacy = _libraryWindow.librarySearchField;
        legacy.stringValue = searchString;
        [_libraryWindow filterLibrary:legacy];
    }
}

// MARK: - NSToolbarDelegate

- (NSArray<NSToolbarItemIdentifier> *)toolbarDefaultItemIdentifiers:(NSToolbar *)toolbar
{
    return @[
        NSToolbarToggleSidebarItemIdentifier,
        MacLCToolbarSidebarSeparator,
        MacLCToolbarNavigation,
        NSToolbarFlexibleSpaceItemIdentifier,
        MacLCToolbarViewMode,
        MacLCToolbarSort,
        MacLCToolbarSearch,
        MacLCToolbarInspectorSeparator,
        MacLCToolbarUpNext,
    ];
}

- (NSArray<NSToolbarItemIdentifier> *)toolbarAllowedItemIdentifiers:(NSToolbar *)toolbar
{
    return [[self toolbarDefaultItemIdentifiers:toolbar] arrayByAddingObjectsFromArray:@[
        NSToolbarSpaceItemIdentifier,
    ]];
}

- (nullable NSToolbarItem *)toolbar:(NSToolbar *)toolbar
              itemForItemIdentifier:(NSToolbarItemIdentifier)itemIdentifier
          willBeInsertedIntoToolbar:(BOOL)flag
{
    VLCLibraryWindowSplitViewController * const splitViewController = _libraryWindow.splitViewController;

    if ([itemIdentifier isEqualToString:MacLCToolbarSidebarSeparator] && splitViewController != nil) {
        return [NSTrackingSeparatorToolbarItem
            trackingSeparatorToolbarItemWithIdentifier:itemIdentifier
                                             splitView:splitViewController.splitView
                                          dividerIndex:VLCLibraryWindowNavigationSidebarSplitViewDividerIndex];
    }
    if ([itemIdentifier isEqualToString:MacLCToolbarInspectorSeparator] && splitViewController != nil) {
        return [NSTrackingSeparatorToolbarItem
            trackingSeparatorToolbarItemWithIdentifier:itemIdentifier
                                             splitView:splitViewController.splitView
                                          dividerIndex:VLCLibraryWindowLibraryTargetViewSplitViewDividerIndex];
    }
    if ([itemIdentifier isEqualToString:MacLCToolbarNavigation]) {
        NSImage * const back = [NSImage imageWithSystemSymbolName:@"chevron.backward" accessibilityDescription:_NS("Back")];
        NSImage * const forward = [NSImage imageWithSystemSymbolName:@"chevron.forward" accessibilityDescription:_NS("Forward")];
        _navigationGroup = [NSToolbarItemGroup groupWithItemIdentifier:itemIdentifier
                                                                images:@[back, forward]
                                                         selectionMode:NSToolbarItemGroupSelectionModeMomentary
                                                                labels:@[_NS("Back"), _NS("Forward")]
                                                                target:self
                                                                action:@selector(navigate:)];
        _navigationGroup.label = _NS("Back/Forward");
        _navigationGroup.paletteLabel = _NS("Back/Forward");
        _navigationGroup.toolTip = _NS("See the previous or next screen");
        _navigationGroup.navigational = YES;
        [self updateItems];
        return _navigationGroup;
    }
    if ([itemIdentifier isEqualToString:MacLCToolbarViewMode]) {
        NSImage * const grid = [NSImage imageWithSystemSymbolName:@"square.grid.2x2" accessibilityDescription:_NS("Grid")];
        NSImage * const list = [NSImage imageWithSystemSymbolName:@"list.bullet" accessibilityDescription:_NS("List")];
        _viewModeGroup = [NSToolbarItemGroup groupWithItemIdentifier:itemIdentifier
                                                              images:@[grid, list]
                                                       selectionMode:NSToolbarItemGroupSelectionModeSelectOne
                                                              labels:@[_NS("Grid"), _NS("List")]
                                                              target:self
                                                              action:@selector(viewModeChanged:)];
        _viewModeGroup.label = _NS("View");
        _viewModeGroup.paletteLabel = _NS("View as Grid or List");
        _viewModeGroup.toolTip = _NS("Show items as a grid or a list");
        [self updateItems];
        return _viewModeGroup;
    }
    if ([itemIdentifier isEqualToString:MacLCToolbarSort]) {
        _sortItem = [[NSMenuToolbarItem alloc] initWithItemIdentifier:itemIdentifier];
        _sortItem.image = [NSImage imageWithSystemSymbolName:@"arrow.up.arrow.down" accessibilityDescription:_NS("Sort")];
        _sortItem.label = _NS("Sort");
        _sortItem.paletteLabel = _NS("Sort");
        _sortItem.toolTip = _NS("Choose how items are sorted");
        _sortItem.showsIndicator = NO;
        [self updateItems];
        return _sortItem;
    }
    if ([itemIdentifier isEqualToString:MacLCToolbarSearch]) {
        _searchItem = [[NSSearchToolbarItem alloc] initWithItemIdentifier:itemIdentifier];
        _searchItem.label = _NS("Search");
        _searchItem.paletteLabel = _NS("Search");
        _searchItem.searchField.delegate = self;
        _searchItem.searchField.sendsSearchStringImmediately = YES;
        _searchItem.resignsFirstResponderWithCancel = YES;
        [self updateItems];
        return _searchItem;
    }
    if ([itemIdentifier isEqualToString:MacLCToolbarUpNext]) {
        NSToolbarItem * const item = [[NSToolbarItem alloc] initWithItemIdentifier:itemIdentifier];
        item.image = [NSImage imageWithSystemSymbolName:@"text.line.first.and.arrowtriangle.forward"
                               accessibilityDescription:_NS("Up Next")];
        item.label = _NS("Up Next");
        item.paletteLabel = _NS("Up Next");
        item.toolTip = _NS("Show or hide what plays next");
        item.target = self;
        item.action = @selector(toggleUpNext:);
        return item;
    }
    return nil;
}

@end
