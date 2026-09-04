/*****************************************************************************
 * MacLCSettingsWindowController.m: Modern System Settings Window for MacLC
 *****************************************************************************
 * Copyright (C) 2026 VLC authors and VideoLAN
 *
 * Authors: MacLC Settings Team
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

#import "settings/MacLCSettingsWindowController.h"
#import "settings/panes/MacLCGeneralSettingsViewController.h"
#import "settings/panes/MacLCPlaybackSettingsViewController.h"
#import "settings/panes/MacLCVideoSettingsViewController.h"
#import "settings/panes/MacLCAudioSettingsViewController.h"
#import "settings/panes/MacLCSubtitlesSettingsViewController.h"
#import "settings/panes/MacLCInterfaceSettingsViewController.h"
#import "settings/panes/MacLCShortcutsSettingsViewController.h"
#import "theme/MacLCDesign.h"
#import "main/VLCMain.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wnullability-completeness"
#import "extensions/NSString+Helpers.h"
#pragma clang diagnostic pop

#import <vlc_configuration.h>

static NSString * const kMacLCLastSelectedPaneKey = @"MacLCLastSelectedSettingsPaneIdentifier";
static NSString * const kMacLCSettingsAutosaveName = @"MacLCSettingsWindowAutosave";

@interface MacLCSettingsWindowController () <NSSplitViewDelegate, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate, NSWindowDelegate, NSToolbarDelegate>
{
    intf_thread_t *_p_intf;
}

@property (nonatomic, strong) NSArray<id<MacLCSettingsPane>> *allPanes;
@property (nonatomic, strong) NSMutableArray<id<MacLCSettingsPane>> *filteredPanes;
@property (nonatomic, strong, nullable) id<MacLCSettingsPane> currentPane;

@property (nonatomic, strong) NSSplitViewController *splitViewController;
@property (nonatomic, strong) NSViewController *sidebarViewController;
@property (nonatomic, strong) NSViewController *detailViewController;

@property (nonatomic, strong) NSSearchField *searchField;
@property (nonatomic, strong) NSTableView *sidebarTableView;
@property (nonatomic, strong) NSTextField *noResultsLabel;
@property (nonatomic, strong) NSScrollView *detailScrollView;

@property (nonatomic, strong) NSArray<NSLayoutConstraint *> *currentPaneConstraints;

@end

@implementation MacLCSettingsWindowController

- (instancetype)initWithIntf:(intf_thread_t *)intf
{
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(200, 200, 860, 620)
                                                   styleMask:NSWindowStyleMaskTitled |
                                                             NSWindowStyleMaskClosable |
                                                             NSWindowStyleMaskMiniaturizable |
                                                             NSWindowStyleMaskResizable |
                                                             NSWindowStyleMaskFullSizeContentView
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];

    self = [super initWithWindow:window];
    if (self) {
        _p_intf = intf;
        _filteredPanes = [NSMutableArray array];
        [self setupWindowAndViews];
    }
    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];
    return self;
}

#pragma mark - Pane Registration

- (void)registerDefaultPanes
{
    NSMutableArray<id<MacLCSettingsPane>> *panes = [NSMutableArray array];

    [panes addObject:[[MacLCGeneralSettingsViewController alloc] initWithIntf:_p_intf]];
    [panes addObject:[[MacLCPlaybackSettingsViewController alloc] initWithIntf:_p_intf]];
    [panes addObject:[[MacLCVideoSettingsViewController alloc] initWithIntf:_p_intf]];

    // =========================================================================
    // HDR-HOOK: MacLCHDRSettingsViewController registration point
    // =========================================================================
    Class hdrClass = NSClassFromString(@"MacLCHDRSettingsViewController");
    if (hdrClass && [hdrClass conformsToProtocol:@protocol(MacLCSettingsPane)]) {
        id<MacLCSettingsPane> hdrPane = [[hdrClass alloc] initWithIntf:_p_intf];
        [panes addObject:hdrPane];
    }
    // =========================================================================

    [panes addObject:[[MacLCAudioSettingsViewController alloc] initWithIntf:_p_intf]];
    [panes addObject:[[MacLCSubtitlesSettingsViewController alloc] initWithIntf:_p_intf]];
    [panes addObject:[[MacLCInterfaceSettingsViewController alloc] initWithIntf:_p_intf]];
    [panes addObject:[[MacLCShortcutsSettingsViewController alloc] initWithIntf:_p_intf]];

    _allPanes = [panes copy];
    [_filteredPanes setArray:_allPanes];
}

#pragma mark - Setup Window and Views

- (void)setupWindowAndViews
{
    NSWindow *window = self.window;
    window.delegate = self;
    window.minSize = NSMakeSize(800, 560);
    window.titlebarAppearsTransparent = YES;
    window.toolbarStyle = NSWindowToolbarStyleUnified;

    NSToolbar *toolbar = [[NSToolbar alloc] initWithIdentifier:@"MacLCSettingsToolbar"];
    toolbar.allowsUserCustomization = NO;
    toolbar.autosavesConfiguration = NO;
    toolbar.delegate = self;
    /* The Apply item supplies its own titled button, so letting the toolbar
     * draw the item label as well printed "Apply" twice, one above the other. */
    toolbar.displayMode = NSToolbarDisplayModeIconOnly;
    window.toolbar = toolbar;

    [window setFrameAutosaveName:kMacLCSettingsAutosaveName];

    [self registerDefaultPanes];

    // Build Sidebar View Controller
    _sidebarViewController = [[NSViewController alloc] init];
    NSView *sidebarView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 240, 600)];
    _sidebarViewController.view = sidebarView;

    _searchField = [[NSSearchField alloc] initWithFrame:NSZeroRect];
    _searchField.translatesAutoresizingMaskIntoConstraints = NO;
    _searchField.placeholderString = _NS("Search");
    _searchField.delegate = self;
    [sidebarView addSubview:_searchField];

    NSScrollView *tableScrollView = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    tableScrollView.translatesAutoresizingMaskIntoConstraints = NO;
    tableScrollView.drawsBackground = NO;
    tableScrollView.hasVerticalScroller = YES;
    tableScrollView.autohidesScrollers = YES;

    _sidebarTableView = [[NSTableView alloc] initWithFrame:NSZeroRect];
    _sidebarTableView.translatesAutoresizingMaskIntoConstraints = NO;
    _sidebarTableView.dataSource = self;
    _sidebarTableView.delegate = self;
    _sidebarTableView.style = NSTableViewStyleSourceList;
    _sidebarTableView.headerView = nil;
    _sidebarTableView.rowHeight = 32.0;

    NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:@"pane"];
    col.resizingMask = NSTableColumnAutoresizingMask;
    [_sidebarTableView addTableColumn:col];

    tableScrollView.documentView = _sidebarTableView;
    [sidebarView addSubview:tableScrollView];

    _noResultsLabel = [NSTextField labelWithString:_NS("No matching settings")];
    _noResultsLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _noResultsLabel.font = [MacLCDesign callout];
    _noResultsLabel.textColor = [MacLCDesign secondaryLabel];
    _noResultsLabel.alignment = NSTextAlignmentCenter;
    _noResultsLabel.hidden = YES;
    [sidebarView addSubview:_noResultsLabel];

    [NSLayoutConstraint activateConstraints:@[
        [_searchField.topAnchor constraintEqualToAnchor:sidebarView.topAnchor constant:44],
        [_searchField.leadingAnchor constraintEqualToAnchor:sidebarView.leadingAnchor constant:12],
        [_searchField.trailingAnchor constraintEqualToAnchor:sidebarView.trailingAnchor constant:-12],

        [tableScrollView.topAnchor constraintEqualToAnchor:_searchField.bottomAnchor constant:10],
        [tableScrollView.leadingAnchor constraintEqualToAnchor:sidebarView.leadingAnchor],
        [tableScrollView.trailingAnchor constraintEqualToAnchor:sidebarView.trailingAnchor],
        [tableScrollView.bottomAnchor constraintEqualToAnchor:sidebarView.bottomAnchor],

        [_noResultsLabel.centerXAnchor constraintEqualToAnchor:sidebarView.centerXAnchor],
        [_noResultsLabel.topAnchor constraintEqualToAnchor:_searchField.bottomAnchor constant:40]
    ]];

    // Build Detail View Controller
    _detailViewController = [[NSViewController alloc] init];
    NSView *detailView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 620, 600)];
    _detailViewController.view = detailView;

    _detailScrollView = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    _detailScrollView.translatesAutoresizingMaskIntoConstraints = NO;
    _detailScrollView.hasVerticalScroller = YES;
    _detailScrollView.hasHorizontalScroller = NO;
    _detailScrollView.autohidesScrollers = YES;
    _detailScrollView.drawsBackground = NO;

    [detailView addSubview:_detailScrollView];

    [NSLayoutConstraint activateConstraints:@[
        [_detailScrollView.leadingAnchor constraintEqualToAnchor:detailView.leadingAnchor],
        [_detailScrollView.trailingAnchor constraintEqualToAnchor:detailView.trailingAnchor],
        /* Pin to the safe area, not the raw top: the window has a transparent
         * titlebar, so anchoring to detailView.topAnchor ran the pane's first
         * card up underneath the title and drew the two texts on top of each
         * other. */
        [_detailScrollView.topAnchor
            constraintEqualToAnchor:detailView.safeAreaLayoutGuide.topAnchor],
        [_detailScrollView.bottomAnchor constraintEqualToAnchor:detailView.bottomAnchor]
    ]];

    // Build Split View Controller
    _splitViewController = [[NSSplitViewController alloc] init];

    NSSplitViewItem *sidebarItem = [NSSplitViewItem sidebarWithViewController:_sidebarViewController];
    sidebarItem.minimumThickness = 200.0;
    sidebarItem.maximumThickness = 300.0;
    [_splitViewController addSplitViewItem:sidebarItem];

    NSSplitViewItem *detailItem = [NSSplitViewItem splitViewItemWithViewController:_detailViewController];
    detailItem.minimumThickness = 500.0;
    [_splitViewController addSplitViewItem:detailItem];

    window.contentViewController = _splitViewController;

    // Restore last selected pane
    NSString *lastPaneID = [[NSUserDefaults standardUserDefaults] stringForKey:kMacLCLastSelectedPaneKey];
    NSInteger selectRow = 0;
    if (lastPaneID.length > 0) {
        for (NSUInteger i = 0; i < _allPanes.count; i++) {
            if ([_allPanes[i].paneIdentifier isEqualToString:lastPaneID]) {
                selectRow = (NSInteger)i;
                break;
            }
        }
    }

    [_sidebarTableView selectRowIndexes:[NSIndexSet indexSetWithIndex:selectRow] byExtendingSelection:NO];
    [self selectPane:_allPanes[selectRow]];
}

#pragma mark - Window Visibility

- (void)showSettingsWindowWithLevel:(NSInteger)windowLevel
{
    [self.window setLevel:windowLevel];
    [self.window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];

    if (_currentPane) {
        [_currentPane loadSettings];
    }
}

#pragma mark - Keyboard Handling (Esc closes window)

- (void)cancelOperation:(id)sender
{
    [self.window performClose:sender];
}

- (void)windowWillClose:(NSNotification *)notification
{
    [self saveChangedSettings];
    if (_currentPane && [_currentPane respondsToSelector:@selector(paneDidDisappear)]) {
        [_currentPane paneDidDisappear];
    }
}

#pragma mark - Sidebar Table View Data Source & Delegate

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
    return _filteredPanes.count;
}

- (nullable NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(nullable NSTableColumn *)tableColumn row:(NSInteger)row
{
    if (row < 0 || row >= (NSInteger)_filteredPanes.count) return nil;
    id<MacLCSettingsPane> pane = _filteredPanes[row];

    NSTableCellView *cell = [tableView makeViewWithIdentifier:@"SidebarCell" owner:self];
    if (!cell) {
        cell = [[NSTableCellView alloc] initWithFrame:NSMakeRect(0, 0, 200, 32)];
        cell.identifier = @"SidebarCell";

        NSImageView *imgView = [[NSImageView alloc] initWithFrame:NSZeroRect];
        imgView.translatesAutoresizingMaskIntoConstraints = NO;
        imgView.imageScaling = NSImageScaleProportionallyDown;
        [cell addSubview:imgView];
        cell.imageView = imgView;

        NSTextField *txtField = [NSTextField labelWithString:@""];
        txtField.translatesAutoresizingMaskIntoConstraints = NO;
        txtField.font = [MacLCDesign body];
        txtField.textColor = [MacLCDesign primaryLabel];
        [cell addSubview:txtField];
        cell.textField = txtField;

        [NSLayoutConstraint activateConstraints:@[
            [imgView.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:8],
            [imgView.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
            [imgView.widthAnchor constraintEqualToConstant:18],
            [imgView.heightAnchor constraintEqualToConstant:18],

            [txtField.leadingAnchor constraintEqualToAnchor:imgView.trailingAnchor constant:10],
            [txtField.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-8],
            [txtField.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor]
        ]];
    }

    cell.textField.stringValue = pane.paneTitle;
    NSImage *symbol = [MacLCDesign symbolNamed:pane.paneSymbolName accessibilityLabel:pane.paneTitle];
    if (symbol) {
        symbol = [symbol copy];
        [symbol setTemplate:YES];
    }
    cell.imageView.image = symbol;

    return cell;
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification
{
    NSInteger selectedRow = _sidebarTableView.selectedRow;
    if (selectedRow >= 0 && selectedRow < (NSInteger)_filteredPanes.count) {
        [self selectPane:_filteredPanes[selectedRow]];
    }
}

#pragma mark - Switching Panes

- (void)selectPane:(id<MacLCSettingsPane>)newPane
{
    if (_currentPane == newPane) return;

    // Save changes if previous pane was modified
    if (_currentPane && [_currentPane respondsToSelector:@selector(hasUnsavedChanges)] && [_currentPane hasUnsavedChanges]) {
        [_currentPane applyChanges];
        fixIntfSettings();
        config_SaveConfigFile(_p_intf);
        [NSNotificationCenter.defaultCenter postNotificationName:VLCConfigurationChangedNotification object:nil];
    }

    if (_currentPane && [_currentPane respondsToSelector:@selector(paneDidDisappear)]) {
        [_currentPane paneDidDisappear];
    }

    _currentPane = newPane;

    if (_currentPaneConstraints) {
        [NSLayoutConstraint deactivateConstraints:_currentPaneConstraints];
        _currentPaneConstraints = nil;
    }

    NSView *paneView = [(NSViewController *)newPane view];
    _detailScrollView.documentView = paneView;

    // Constrain pane view width to scroll view content clip view
    NSClipView *clipView = _detailScrollView.contentView;
    _currentPaneConstraints = @[
        [paneView.leadingAnchor constraintEqualToAnchor:clipView.leadingAnchor],
        [paneView.trailingAnchor constraintEqualToAnchor:clipView.trailingAnchor],
        [paneView.topAnchor constraintEqualToAnchor:clipView.topAnchor]
    ];
    [NSLayoutConstraint activateConstraints:_currentPaneConstraints];

    // Scroll to top
    [clipView scrollPoint:NSZeroPoint];

    [newPane loadSettings];
    if ([newPane respondsToSelector:@selector(paneDidAppear)]) {
        [newPane paneDidAppear];
    }

    self.window.title = newPane.paneTitle;
    [[NSUserDefaults standardUserDefaults] setObject:newPane.paneIdentifier forKey:kMacLCLastSelectedPaneKey];
}

- (void)selectPaneWithIdentifier:(NSString *)identifier
{
    for (NSUInteger i = 0; i < _allPanes.count; i++) {
        if ([_allPanes[i].paneIdentifier isEqualToString:identifier]) {
            [_searchField setStringValue:@""];
            [self updateSearchFilter];
            NSUInteger filteredIdx = [_filteredPanes indexOfObject:_allPanes[i]];
            if (filteredIdx != NSNotFound) {
                [_sidebarTableView selectRowIndexes:[NSIndexSet indexSetWithIndex:filteredIdx] byExtendingSelection:NO];
                [self selectPane:_allPanes[i]];
            }
            break;
        }
    }
}

#pragma mark - Search Filtering

- (void)controlTextDidChange:(NSNotification *)obj
{
    if (obj.object == _searchField) {
        [self updateSearchFilter];
    }
}

- (void)updateSearchFilter
{
    NSString *query = _searchField.stringValue.lowercaseString;
    [_filteredPanes removeAllObjects];

    for (id<MacLCSettingsPane> pane in _allPanes) {
        if (query.length == 0) {
            [_filteredPanes addObject:pane];
            continue;
        }
        if ([pane.paneTitle.lowercaseString containsString:query]) {
            [_filteredPanes addObject:pane];
            continue;
        }
        BOOL match = NO;
        for (NSString *keyword in pane.searchKeywords) {
            if ([keyword containsString:query]) {
                match = YES;
                break;
            }
        }
        if (match) {
            [_filteredPanes addObject:pane];
        }
    }

    if (_filteredPanes.count == 0) {
        _noResultsLabel.hidden = NO;
        _sidebarTableView.hidden = YES;
    } else {
        _noResultsLabel.hidden = YES;
        _sidebarTableView.hidden = NO;
        [_sidebarTableView reloadData];

        // Maintain selection or select first result
        NSUInteger currentIdx = [_filteredPanes indexOfObject:_currentPane];
        if (currentIdx != NSNotFound) {
            [_sidebarTableView selectRowIndexes:[NSIndexSet indexSetWithIndex:currentIdx] byExtendingSelection:NO];
        } else {
            [_sidebarTableView selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
            [self selectPane:_filteredPanes[0]];
        }
    }
}

#pragma mark - Applying and Saving Settings

- (void)saveChangedSettings
{
    BOOL needsSave = NO;
    for (id<MacLCSettingsPane> pane in _allPanes) {
        if (![pane respondsToSelector:@selector(hasUnsavedChanges)] || [pane hasUnsavedChanges]) {
            [pane applyChanges];
            needsSave = YES;
        }
    }

    if (needsSave) {
        fixIntfSettings();
        config_SaveConfigFile(_p_intf);
        [NSNotificationCenter.defaultCenter postNotificationName:VLCConfigurationChangedNotification object:nil];
    }
}

- (void)applyChangesAction:(id)sender
{
    [self saveChangedSettings];
}

#pragma mark - NSToolbarDelegate

- (NSArray<NSToolbarItemIdentifier> *)toolbarDefaultItemIdentifiers:(NSToolbar *)toolbar
{
    return @[NSToolbarFlexibleSpaceItemIdentifier, @"ApplyToolbarItem"];
}

- (NSArray<NSToolbarItemIdentifier> *)toolbarAllowedItemIdentifiers:(NSToolbar *)toolbar
{
    return @[NSToolbarFlexibleSpaceItemIdentifier, @"ApplyToolbarItem"];
}

- (nullable NSToolbarItem *)toolbar:(NSToolbar *)toolbar
              itemForItemIdentifier:(NSToolbarItemIdentifier)itemIdentifier
          willBeInsertedIntoToolbar:(BOOL)flag
{
    if ([itemIdentifier isEqualToString:@"ApplyToolbarItem"]) {
        NSToolbarItem *item = [[NSToolbarItem alloc] initWithItemIdentifier:itemIdentifier];
        item.label = _NS("Apply");
        item.paletteLabel = _NS("Apply Settings");
        item.toolTip = _NS("Save changes immediately to disk");

        NSButton *btn = [NSButton buttonWithTitle:_NS("Apply") target:self action:@selector(applyChangesAction:)];
        btn.bezelStyle = NSBezelStyleRounded;
        item.view = btn;
        return item;
    }
    return nil;
}

@end
