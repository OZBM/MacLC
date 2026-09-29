/*****************************************************************************
 * MacLCLibrarySidebarViewController.m: the library window's source list
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

#import "medialib/shell/MacLCLibrarySidebarViewController.h"

#import "extensions/NSString+Helpers.h"

#import "library/VLCLibraryController.h"
#import "library/VLCLibraryDataTypes.h"
#import "library/VLCLibrarySegment.h"
#import "library/VLCLibrarySegmentBookmarkedLocation.h"
#import "library/VLCLibraryWindow.h"

#import "main/VLCMain.h"

#import "theme/MacLCDesign.h"

#import "medialib/data/MacLCLibraryActions.h"
#import "medialib/data/MacLCLibraryStore.h"
#import "medialib/shell/MacLCLibraryFoldersController.h"
#import "medialib/shell/MacLCLibraryRouter.h"

// MARK: - Sidebar row model

/// A single row in the sidebar outline. Groups (Library, Playlists, Locations)
/// are flagged as headers.
@interface MacLCSidebarItem : NSObject
@property (copy) NSString *title;
@property (strong) NSImage *image;
@property NSInteger segmentType;
@property BOOL isHeader;
@property (strong) NSMutableArray<MacLCSidebarItem *> *children;
/// For playlist rows, the underlying object to pass through the router.
@property (strong) VLCMediaLibraryPlaylist *playlist;
/// For bookmarked-folder rows, the underlying object.
@property (strong) VLCLibrarySegmentBookmarkedLocation *bookmark;
@end

@implementation MacLCSidebarItem
- (instancetype)init
{
    self = [super init];
    if (self) {
        _segmentType = VLCLibraryLowSentinelSegment;
        _children = [NSMutableArray array];
    }
    return self;
}
@end

// MARK: - Private

static NSUserInterfaceItemIdentifier const kHeaderCellID = @"MacLCSidebarHeaderCell";
static NSUserInterfaceItemIdentifier const kRowCellID = @"MacLCSidebarRowCell";
static NSUserInterfaceItemIdentifier const kOutlineColumnID = @"MacLCSidebarOutlineColumn";

@interface MacLCLibrarySidebarViewController () <NSMenuDelegate, NSOutlineViewDataSource, NSOutlineViewDelegate>
{
    NSScrollView *_scrollView;
    NSOutlineView *_outlineView;
    VLCLibraryWindow *__weak _libraryWindow;
    NSArray<MacLCSidebarItem *> *_rootItems;
    BOOL _updatingSelection;
    BOOL _observingWindow;
    NSProgressIndicator *_indexingSpinner;
}
@end

@implementation MacLCLibrarySidebarViewController

#pragma mark - Init

- (instancetype)initWithLibraryWindow:(VLCLibraryWindow *)libraryWindow
{
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _libraryWindow = libraryWindow;
    }
    return self;
}

#pragma mark - View lifecycle

- (void)loadView
{
    NSView * const container = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 220, 400)];

    _outlineView = [[NSOutlineView alloc] initWithFrame:container.bounds];
    _outlineView.style = NSTableViewStyleSourceList;
    _outlineView.floatsGroupRows = NO;
    _outlineView.headerView = nil;
    _outlineView.rowSizeStyle = NSTableViewRowSizeStyleDefault;
    /* Empty when the screen shown has no row (the Playlists list). */
    _outlineView.allowsEmptySelection = YES;
    _outlineView.indentationPerLevel = 0;

    NSTableColumn * const column =
        [[NSTableColumn alloc] initWithIdentifier:kOutlineColumnID];
    column.resizingMask = NSTableColumnAutoresizingMask;
    [_outlineView addTableColumn:column];
    _outlineView.outlineTableColumn = column;
    /* The only column spans the sidebar, whatever its width. */
    _outlineView.columnAutoresizingStyle = NSTableViewFirstColumnOnlyAutoresizingStyle;
    _outlineView.autoresizingMask = NSViewWidthSizable;

    _outlineView.dataSource = self;
    _outlineView.delegate = self;
    /* The context menu is rebuilt for the clicked row each time it opens. */
    _outlineView.menu = [[NSMenu alloc] initWithTitle:@""];
    _outlineView.menu.delegate = self;

    _scrollView = [[NSScrollView alloc] initWithFrame:container.bounds];
    _scrollView.documentView = _outlineView;
    _scrollView.hasVerticalScroller = YES;
    _scrollView.autohidesScrollers = YES;
    _scrollView.drawsBackground = NO;
    _scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    [container addSubview:_scrollView];
    [NSLayoutConstraint activateConstraints:@[
        [_scrollView.topAnchor constraintEqualToAnchor:container.topAnchor],
        [_scrollView.bottomAnchor constraintEqualToAnchor:container.bottomAnchor],
        [_scrollView.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [_scrollView.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
    ]];

    self.view = container;
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    [self rebuildModel];
    /* The outline view asked for its rows when it got its data source, before
     * the model existed. */
    [_outlineView reloadData];

    // Expand all headers by default.
    for (MacLCSidebarItem * const item in _rootItems) {
        if (item.isHeader) {
            [_outlineView expandItem:item];
        }
    }

    NSNotificationCenter * const nc = NSNotificationCenter.defaultCenter;
    [nc addObserver:self
           selector:@selector(storeDidChange:)
               name:MacLCLibraryStoreDidChangeNotification
             object:nil];
    [nc addObserver:self
           selector:@selector(storeIndexingDidChange:)
               name:MacLCLibraryStoreIndexingDidChangeNotification
             object:nil];
    [nc addObserver:self
           selector:@selector(bookmarkedLocationsChanged:)
               name:VLCLibraryBookmarkedLocationsChanged
             object:nil];

    // Select the window's current segment, and follow it.
    [self selectRowForSegmentType:_libraryWindow.librarySegmentType];
    [_libraryWindow addObserver:self forKeyPath:@"librarySegmentType" options:0 context:nil];
    _observingWindow = YES;
}

- (void)dealloc
{
    [NSNotificationCenter.defaultCenter removeObserver:self];
    if (_observingWindow) {
        [_libraryWindow removeObserver:self forKeyPath:@"librarySegmentType"];
    }
}

- (void)viewDidLayout
{
    [super viewDidLayout];
    [_outlineView sizeLastColumnToFit];
}

#pragma mark - Model

- (void)rebuildModel
{
    NSMutableArray<MacLCSidebarItem *> * const items = [NSMutableArray array];

    BOOL const hasLibrary =
        VLCMain.sharedInstance.libraryController.shouldUseMediaLibrary;

    if (hasLibrary) {
        // Home (top-level, not under a header)
        MacLCSidebarItem * const home = [[MacLCSidebarItem alloc] init];
        home.title = _NS("Home");
        home.image = [MacLCDesign symbolNamed:@"house" accessibilityLabel:_NS("Home")];
        home.segmentType = VLCLibraryHomeSegmentType;
        [items addObject:home];

        // Library header
        MacLCSidebarItem * const libHeader = [[MacLCSidebarItem alloc] init];
        libHeader.title = _NS("Library");
        libHeader.isHeader = YES;
        libHeader.segmentType = VLCLibraryHeaderSegmentType;

        MacLCSidebarItem * const videos = [[MacLCSidebarItem alloc] init];
        videos.title = _NS("Videos");
        videos.image = [MacLCDesign symbolNamed:@"film" accessibilityLabel:_NS("Videos")];
        videos.segmentType = VLCLibraryVideoSegmentType;

        MacLCSidebarItem * const shows = [[MacLCSidebarItem alloc] init];
        shows.title = _NS("Shows");
        shows.image = [MacLCDesign symbolNamed:@"tv" accessibilityLabel:_NS("Shows")];
        shows.segmentType = VLCLibraryShowsVideoSubSegmentType;

        MacLCSidebarItem * const artists = [[MacLCSidebarItem alloc] init];
        artists.title = _NS("Artists");
        artists.image = [MacLCDesign symbolNamed:@"music.mic" accessibilityLabel:_NS("Artists")];
        artists.segmentType = VLCLibraryArtistsMusicSubSegmentType;

        MacLCSidebarItem * const albums = [[MacLCSidebarItem alloc] init];
        albums.title = _NS("Albums");
        albums.image = [MacLCDesign symbolNamed:@"square.stack" accessibilityLabel:_NS("Albums")];
        albums.segmentType = VLCLibraryAlbumsMusicSubSegmentType;

        MacLCSidebarItem * const songs = [[MacLCSidebarItem alloc] init];
        songs.title = _NS("Songs");
        songs.image = [MacLCDesign symbolNamed:@"music.note" accessibilityLabel:_NS("Songs")];
        songs.segmentType = VLCLibrarySongsMusicSubSegmentType;

        MacLCSidebarItem * const genres = [[MacLCSidebarItem alloc] init];
        genres.title = _NS("Genres");
        genres.image = [MacLCDesign symbolNamed:@"guitars" accessibilityLabel:_NS("Genres")];
        genres.segmentType = VLCLibraryGenresMusicSubSegmentType;

        MacLCSidebarItem * const favorites = [[MacLCSidebarItem alloc] init];
        favorites.title = _NS("Favorites");
        favorites.image = [MacLCDesign symbolNamed:@"star" accessibilityLabel:_NS("Favorites")];
        favorites.segmentType = VLCLibraryFavoritesSegmentType;

        [libHeader.children addObjectsFromArray:@[
            videos, shows, artists, albums, songs, genres, favorites
        ]];
        [items addObject:libHeader];

        // Playlists header
        MacLCSidebarItem * const playlistsHeader = [[MacLCSidebarItem alloc] init];
        playlistsHeader.title = _NS("Playlists");
        playlistsHeader.isHeader = YES;
        playlistsHeader.segmentType = VLCLibraryPlaylistsSegmentType;

        MacLCLibraryStore * const store = MacLCLibraryStore.sharedStore;
        NSArray * const playlists =
            [store itemsInCollection:MacLCLibraryCollectionPlaylists];
        for (VLCMediaLibraryPlaylist * const pl in playlists) {
            MacLCSidebarItem * const row = [[MacLCSidebarItem alloc] init];
            row.title = pl.displayString;
            row.image = [MacLCDesign symbolNamed:@"music.note.list"
                              accessibilityLabel:_NS("Playlist")];
            row.segmentType = VLCLibraryPlaylistsSegmentType;
            row.playlist = pl;
            [playlistsHeader.children addObject:row];
        }
        [items addObject:playlistsHeader];
    }

    // Locations header
    MacLCSidebarItem * const locationsHeader = [[MacLCSidebarItem alloc] init];
    locationsHeader.title = _NS("Locations");
    locationsHeader.isHeader = YES;
    locationsHeader.segmentType = VLCLibraryBrowseSegmentType;

    MacLCSidebarItem * const browse = [[MacLCSidebarItem alloc] init];
    browse.title = _NS("Browse");
    browse.image = [MacLCDesign symbolNamed:@"folder" accessibilityLabel:_NS("Browse")];
    browse.segmentType = VLCLibraryBrowseSegmentType;
    [locationsHeader.children addObject:browse];

    // Bookmarked locations
    NSArray<NSString *> * const bookmarkMrls =
        [NSUserDefaults.standardUserDefaults stringArrayForKey:VLCLibraryBookmarkedLocationsKey];
    for (NSString * const mrl in bookmarkMrls) {
        /* Network locations and unparsable MRLs have no local path. */
        NSString * const path = [NSURL URLWithString:mrl].path;
        if (path.length == 0 || ![NSFileManager.defaultManager fileExistsAtPath:path]) {
            continue;
        }
        MacLCSidebarItem * const row = [[MacLCSidebarItem alloc] init];
        row.title = mrl.lastPathComponent;
        row.image = [MacLCDesign symbolNamed:@"folder" accessibilityLabel:_NS("Bookmarked location")];
        row.segmentType = VLCLibraryBrowseBookmarkedLocationSubSegmentType;
        row.bookmark = [[VLCLibrarySegmentBookmarkedLocation alloc]
            initWithSegmentType:VLCLibraryBrowseBookmarkedLocationSubSegmentType
                           name:mrl.lastPathComponent
                            mrl:mrl];
        [locationsHeader.children addObject:row];
    }
    [items addObject:locationsHeader];

    _rootItems = [items copy];
}

#pragma mark - NSOutlineViewDataSource

- (NSInteger)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(id)item
{
    if (item == nil) {
        return (NSInteger)_rootItems.count;
    }
    return (NSInteger)((MacLCSidebarItem *)item).children.count;
}

- (id)outlineView:(NSOutlineView *)outlineView child:(NSInteger)index ofItem:(id)item
{
    if (item == nil) {
        return _rootItems[index];
    }
    return ((MacLCSidebarItem *)item).children[index];
}

- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item
{
    return ((MacLCSidebarItem *)item).isHeader;
}

#pragma mark - NSOutlineViewDelegate

- (BOOL)outlineView:(NSOutlineView *)outlineView isGroupItem:(id)item
{
    return ((MacLCSidebarItem *)item).isHeader;
}

- (BOOL)outlineView:(NSOutlineView *)outlineView shouldSelectItem:(id)item
{
    return !((MacLCSidebarItem *)item).isHeader;
}

- (NSView *)outlineView:(NSOutlineView *)outlineView
      viewForTableColumn:(NSTableColumn *)tableColumn
                    item:(id)item
{
    MacLCSidebarItem * const sidebarItem = (MacLCSidebarItem *)item;

    if (sidebarItem.isHeader) {
        NSTableCellView *cell =
            [outlineView makeViewWithIdentifier:kHeaderCellID owner:self];
        if (cell == nil) {
            cell = [[NSTableCellView alloc] init];
            cell.identifier = kHeaderCellID;

            NSTextField * const label = [NSTextField labelWithString:@""];
            label.font = [NSFont systemFontOfSize:11 weight:NSFontWeightSemibold];
            label.textColor = MacLCDesign.secondaryLabel;
            label.lineBreakMode = NSLineBreakByTruncatingTail;
            label.translatesAutoresizingMaskIntoConstraints = NO;
            [cell addSubview:label];
            cell.textField = label;

            [NSLayoutConstraint activateConstraints:@[
                [label.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor
                                                    constant:MacLCDesign.spacingXS],
                [label.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor
                                                     constant:-MacLCDesign.spacingXS],
                [label.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
            ]];
        }
        cell.textField.stringValue = sidebarItem.title;
        return cell;
    }

    NSTableCellView *cell =
        [outlineView makeViewWithIdentifier:kRowCellID owner:self];
    if (cell == nil) {
        cell = [[NSTableCellView alloc] init];
        cell.identifier = kRowCellID;

        NSImageView * const imageView = [NSImageView imageViewWithImage:
            [NSImage imageWithSystemSymbolName:@"questionmark"
                      accessibilityDescription:nil]];
        imageView.translatesAutoresizingMaskIntoConstraints = NO;
        NSImageSymbolConfiguration * const config =
            [NSImageSymbolConfiguration configurationWithScale:NSImageSymbolScaleMedium];
        imageView.symbolConfiguration = config;
        [cell addSubview:imageView];
        cell.imageView = imageView;

        NSTextField * const label = [NSTextField labelWithString:@""];
        label.font = [NSFont preferredFontForTextStyle:NSFontTextStyleBody
                                               options:@{}];
        label.lineBreakMode = NSLineBreakByTruncatingTail;
        label.translatesAutoresizingMaskIntoConstraints = NO;
        [cell addSubview:label];
        cell.textField = label;

        [NSLayoutConstraint activateConstraints:@[
            [imageView.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor
                                                    constant:MacLCDesign.spacingXS],
            [imageView.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
            [imageView.widthAnchor constraintEqualToConstant:20],
            [imageView.heightAnchor constraintEqualToConstant:20],
            [label.leadingAnchor constraintEqualToAnchor:imageView.trailingAnchor
                                                constant:MacLCDesign.spacingS],
            [label.trailingAnchor constraintLessThanOrEqualToAnchor:cell.trailingAnchor
                                                           constant:-MacLCDesign.spacingXS],
            [label.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
        ]];
    }

    cell.imageView.image = sidebarItem.image;
    cell.imageView.contentTintColor = nil; // Source list auto-tints with accent.
    cell.textField.stringValue = sidebarItem.title;

    return cell;
}

- (void)outlineViewSelectionDidChange:(NSNotification *)notification
{
    if (_updatingSelection) {
        return;
    }

    MacLCSidebarItem * const item =
        [_outlineView itemAtRow:_outlineView.selectedRow];
    if (item == nil || item.isHeader) {
        return;
    }

    // Playlist rows go through the router.
    if (item.playlist != nil) {
        MacLCLibraryRouter * const router =
            [MacLCLibraryRouter routerForLibraryWindow:_libraryWindow];
        [router showPlaylist:item.playlist];
        return;
    }

    // Bookmarked-folder rows navigate to that folder in Browse.
    if (item.bookmark != nil) {
        _libraryWindow.librarySegmentType = VLCLibraryBrowseSegmentType;
        [_libraryWindow browseFolderByMrl:item.bookmark.mrl];
        return;
    }

    // Standard segment types.
    _libraryWindow.librarySegmentType = item.segmentType;
}

#pragma mark - Context menus

- (NSMenu *)outlineView:(NSOutlineView *)outlineView
   menuForItem:(id)item
{
    MacLCSidebarItem * const sidebarItem = (MacLCSidebarItem *)item;

    // Playlist rows: Play, Shuffle, Rename…, Delete Playlist…
    if (sidebarItem.playlist != nil) {
        NSMenu * const menu = [[NSMenu alloc] initWithTitle:@""];
        VLCMediaLibraryPlaylist * const playlist = sidebarItem.playlist;

        NSMenuItem * const playItem =
            [[NSMenuItem alloc] initWithTitle:_NS("Play")
                                      action:@selector(contextPlayPlaylist:)
                               keyEquivalent:@""];
        playItem.representedObject = playlist;
        playItem.target = self;
        [menu addItem:playItem];

        NSMenuItem * const shuffleItem =
            [[NSMenuItem alloc] initWithTitle:_NS("Shuffle")
                                      action:@selector(contextShufflePlaylist:)
                               keyEquivalent:@""];
        shuffleItem.representedObject = playlist;
        shuffleItem.target = self;
        [menu addItem:shuffleItem];

        [menu addItem:NSMenuItem.separatorItem];

        NSMenuItem * const renameItem =
            [[NSMenuItem alloc] initWithTitle:_NS("Rename\u2026")
                                      action:@selector(contextRenamePlaylist:)
                               keyEquivalent:@""];
        renameItem.representedObject = playlist;
        renameItem.target = self;
        [menu addItem:renameItem];

        NSMenuItem * const deleteItem =
            [[NSMenuItem alloc] initWithTitle:_NS("Delete Playlist\u2026")
                                      action:@selector(contextDeletePlaylist:)
                               keyEquivalent:@""];
        deleteItem.representedObject = playlist;
        deleteItem.target = self;
        [menu addItem:deleteItem];

        return menu;
    }

    // Library header: Library Folders…
    if (sidebarItem.isHeader &&
        sidebarItem.segmentType == VLCLibraryHeaderSegmentType) {
        NSMenu * const menu = [[NSMenu alloc] initWithTitle:@""];
        NSMenuItem * const foldersItem =
            [[NSMenuItem alloc] initWithTitle:_NS("Library Folders\u2026")
                                      action:@selector(contextShowLibraryFolders:)
                               keyEquivalent:@""];
        foldersItem.target = self;
        [menu addItem:foldersItem];
        return menu;
    }

    // Bookmarked folders: Remove from Sidebar
    if (sidebarItem.bookmark != nil) {
        NSMenu * const menu = [[NSMenu alloc] initWithTitle:@""];
        NSMenuItem * const removeItem =
            [[NSMenuItem alloc] initWithTitle:_NS("Remove from Sidebar")
                                      action:@selector(contextRemoveBookmark:)
                               keyEquivalent:@""];
        removeItem.representedObject = sidebarItem.bookmark;
        removeItem.target = self;
        [menu addItem:removeItem];
        return menu;
    }

    return nil;
}

- (void)contextPlayPlaylist:(NSMenuItem *)sender
{
    VLCMediaLibraryPlaylist * const playlist = sender.representedObject;
    [MacLCLibraryActions playItems:@[playlist] startingAt:0];
}

- (void)contextShufflePlaylist:(NSMenuItem *)sender
{
    VLCMediaLibraryPlaylist * const playlist = sender.representedObject;
    [MacLCLibraryActions shuffleItems:@[playlist]];
}

- (void)contextRenamePlaylist:(NSMenuItem *)sender
{
    VLCMediaLibraryPlaylist * const playlist = sender.representedObject;
    [MacLCLibraryActions renamePlaylist:playlist fromWindow:_libraryWindow];
}

- (void)contextDeletePlaylist:(NSMenuItem *)sender
{
    VLCMediaLibraryPlaylist * const playlist = sender.representedObject;
    [MacLCLibraryActions deletePlaylist:playlist fromWindow:_libraryWindow];
}

- (void)contextShowLibraryFolders:(NSMenuItem *)sender
{
    [MacLCLibraryFoldersController.sharedController beginSheetForWindow:_libraryWindow];
}

- (void)contextRemoveBookmark:(NSMenuItem *)sender
{
    VLCLibrarySegmentBookmarkedLocation * const bookmark = sender.representedObject;
    NSMutableArray<NSString *> * const locations =
        [[NSUserDefaults.standardUserDefaults
            stringArrayForKey:VLCLibraryBookmarkedLocationsKey] mutableCopy];
    [locations removeObject:bookmark.mrl];
    [NSUserDefaults.standardUserDefaults setObject:locations
                                            forKey:VLCLibraryBookmarkedLocationsKey];
    [NSNotificationCenter.defaultCenter
        postNotificationName:VLCLibraryBookmarkedLocationsChanged
                      object:nil];
}

#pragma mark - Right-click delivery

- (void)menuNeedsUpdate:(NSMenu *)menu
{
    [menu removeAllItems];
    const NSInteger row = _outlineView.clickedRow;
    if (row < 0) {
        return;
    }
    NSMenu * const rowMenu = [self outlineView:_outlineView menuForItem:[_outlineView itemAtRow:row]];
    for (NSMenuItem * const item in rowMenu.itemArray.copy) {
        [rowMenu removeItem:item];
        [menu addItem:item];
    }
}

#pragma mark - selectSegment:

- (void)selectSegment:(NSInteger)segmentType
{
    [self selectRowForSegmentType:segmentType];
    /* Callers expect the old sidebar's behaviour: selecting navigates. */
    if (_libraryWindow.librarySegmentType != segmentType) {
        _libraryWindow.librarySegmentType = segmentType;
    }
}

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary *)change
                       context:(void *)context
{
    [self selectRowForSegmentType:_libraryWindow.librarySegmentType];
}

/* Moves the selection to the segment's row without navigating. A playlist or
 * bookmark row stays selected when its segment is the one shown. */
- (void)selectRowForSegmentType:(NSInteger)segmentType
{
    const NSInteger selectedRow = _outlineView.selectedRow;
    if (selectedRow >= 0 &&
        ((MacLCSidebarItem *)[_outlineView itemAtRow:selectedRow]).segmentType == segmentType) {
        return;
    }

    _updatingSelection = YES;

    MacLCSidebarItem * const target = [self itemForSegmentType:segmentType];
    if (target != nil) {
        // Ensure the header is expanded.
        for (MacLCSidebarItem * const root in _rootItems) {
            if (root.isHeader && [root.children containsObject:target]) {
                [_outlineView expandItem:root];
                break;
            }
        }
        const NSInteger row = [_outlineView rowForItem:target];
        if (row >= 0) {
            [_outlineView selectRowIndexes:[NSIndexSet indexSetWithIndex:row]
                      byExtendingSelection:NO];
        }
    } else {
        [_outlineView deselectAll:nil];
    }

    _updatingSelection = NO;
}

- (MacLCSidebarItem *)itemForSegmentType:(NSInteger)segmentType
{
    for (MacLCSidebarItem * const root in _rootItems) {
        if (!root.isHeader && root.segmentType == segmentType) {
            return root;
        }
        for (MacLCSidebarItem * const child in root.children) {
            /* A playlist or bookmark row stands for one item, not for its
             * whole segment: only a click selects it. */
            if (child.segmentType == segmentType && child.playlist == nil && child.bookmark == nil) {
                return child;
            }
        }
    }
    return nil;
}

#pragma mark - Notifications

- (void)storeDidChange:(NSNotification *)notification
{
    NSSet<NSNumber *> * const changedCollections =
        notification.userInfo[MacLCLibraryStoreChangedCollectionsKey];
    if (changedCollections == nil ||
        [changedCollections containsObject:@(MacLCLibraryCollectionPlaylists)]) {
        [self reloadPlaylistRows];
    }
}

- (void)storeIndexingDidChange:(NSNotification *)notification
{
    [self updateIndexingUI];
}

- (void)bookmarkedLocationsChanged:(NSNotification *)notification
{
    [self reloadBookmarkRows];
}

- (void)reloadPlaylistRows
{
    MacLCSidebarItem *playlistsHeader = nil;
    for (MacLCSidebarItem * const root in _rootItems) {
        if (root.isHeader && root.segmentType == VLCLibraryPlaylistsSegmentType) {
            playlistsHeader = root;
            break;
        }
    }
    if (playlistsHeader == nil) {
        return;
    }

    [playlistsHeader.children removeAllObjects];
    MacLCLibraryStore * const store = MacLCLibraryStore.sharedStore;
    NSArray * const playlists =
        [store itemsInCollection:MacLCLibraryCollectionPlaylists];
    for (VLCMediaLibraryPlaylist * const pl in playlists) {
        MacLCSidebarItem * const row = [[MacLCSidebarItem alloc] init];
        row.title = pl.displayString;
        row.image = [MacLCDesign symbolNamed:@"music.note.list"
                          accessibilityLabel:_NS("Playlist")];
        row.segmentType = VLCLibraryPlaylistsSegmentType;
        row.playlist = pl;
        [playlistsHeader.children addObject:row];
    }

    [_outlineView reloadItem:playlistsHeader reloadChildren:YES];
    [_outlineView expandItem:playlistsHeader];
}

- (void)reloadBookmarkRows
{
    // Rebuild the whole model and reload (bookmarks change rarely).
    NSInteger const selectedSegment =
        _libraryWindow.librarySegmentType;
    [self rebuildModel];
    [_outlineView reloadData];
    for (MacLCSidebarItem * const root in _rootItems) {
        if (root.isHeader) {
            [_outlineView expandItem:root];
        }
    }
    [self selectSegment:selectedSegment];
}

- (void)updateIndexingUI
{
    MacLCLibraryStore * const store = MacLCLibraryStore.sharedStore;
    if (store == nil) {
        return;
    }
    // Find the Library header and update its tooltip with indexing location.
    for (MacLCSidebarItem * const root in _rootItems) {
        if (root.isHeader && root.segmentType == VLCLibraryHeaderSegmentType) {
            const NSInteger row = [_outlineView rowForItem:root];
            if (row >= 0) {
                NSView * const cellView = [_outlineView viewAtColumn:0 row:row
                                                     makeIfNecessary:NO];
                if (store.isIndexing && store.indexingLocation.length > 0) {
                    cellView.toolTip = [NSString stringWithFormat:
                        _NS("Adding media from %@"), store.indexingLocation];
                } else {
                    cellView.toolTip = nil;
                }
            }
            break;
        }
    }
}

@end
