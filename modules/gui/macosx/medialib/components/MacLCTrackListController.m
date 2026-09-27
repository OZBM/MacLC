/*****************************************************************************
 * MacLCTrackListController.m: the library's one table of media items
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

#import "medialib/components/MacLCTrackListController.h"

#import <vlc_common.h>
#import <vlc_media_library.h>

#import "extensions/NSString+Helpers.h"
#import "library/VLCInputItem.h"
#import "library/VLCLibraryDataTypes.h"
#import "main/VLCMain.h"
#import "medialib/components/MacLCArtworkView.h"
#import "medialib/data/MacLCLibraryActions.h"
#import "medialib/data/MacLCLibraryStore.h"
#import "medialib/data/MacLCMediaFormat.h"
#import "playqueue/VLCPlayerController.h"
#import "playqueue/VLCPlayQueueController.h"
#import "theme/MacLCDesign.h"

static NSPasteboardType const MacLCTrackListRowPasteboardType = @"org.maclc.track-list.rows";

static NSUserInterfaceItemIdentifier const MacLCColumnNumber = @"number";
static NSUserInterfaceItemIdentifier const MacLCColumnThumbnail = @"thumbnail";
static NSUserInterfaceItemIdentifier const MacLCColumnTitle = @"title";
static NSUserInterfaceItemIdentifier const MacLCColumnArtist = @"artist";
static NSUserInterfaceItemIdentifier const MacLCColumnAlbum = @"album";
static NSUserInterfaceItemIdentifier const MacLCColumnGenre = @"genre";
static NSUserInterfaceItemIdentifier const MacLCColumnDuration = @"duration";
static NSUserInterfaceItemIdentifier const MacLCColumnPlays = @"plays";
static NSUserInterfaceItemIdentifier const MacLCColumnDate = @"date";
static NSUserInterfaceItemIdentifier const MacLCColumnFormat = @"format";

/* Right-click acts on the clicked row (selected first unless already part of
 * the selection); Return plays; Delete removes. */
@interface MacLCTrackTableView : NSTableView
@property (nonatomic, weak) MacLCTrackListController *listController;
@end

@interface MacLCTrackListController ()
- (void)activateRow:(NSInteger)row;
- (void)deleteSelectedRows;
- (NSMenu *)menuForRow:(NSInteger)row;
@end

@implementation MacLCTrackTableView

- (NSMenu *)menuForEvent:(NSEvent *)event
{
    const NSInteger row = [self rowAtPoint:[self convertPoint:event.locationInWindow fromView:nil]];
    if (row < 0) {
        return nil;
    }
    if (![self.selectedRowIndexes containsIndex:(NSUInteger)row]) {
        [self selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row] byExtendingSelection:NO];
    }
    return [self.listController menuForRow:row];
}

- (void)keyDown:(NSEvent *)event
{
    if (event.keyCode == 36 || event.keyCode == 76) {
        [self.listController activateRow:self.selectedRow];
        return;
    }
    if (event.keyCode == 51 || event.keyCode == 117) {
        [self.listController deleteSelectedRows];
        return;
    }
    [super keyDown:event];
}

@end

@interface MacLCTrackListController ()
{
    MacLCTrackListColumns _columns;
    NSScrollView *_scrollView;
    MacLCTrackTableView *_tableView;
    NSArray<VLCMediaLibraryMediaItem *> *_items;
    NSArray<VLCMediaLibraryMediaItem *> *_visibleItems;
    NSString *_searchString;
    NSString *_playingMRL;
    NSDateFormatter *_dateFormatter;
}
@end

@implementation MacLCTrackListController

- (instancetype)initWithColumns:(MacLCTrackListColumns)columns autosaveName:(nullable NSString *)autosaveName
{
    self = [super init];
    if (self) {
        _columns = columns;
        _items = @[];
        _visibleItems = @[];
        _searchString = @"";
        _dateFormatter = [[NSDateFormatter alloc] init];
        _dateFormatter.dateStyle = NSDateFormatterMediumStyle;
        _dateFormatter.timeStyle = NSDateFormatterNoStyle;
        _dateFormatter.doesRelativeDateFormatting = YES;
        [self buildTableWithAutosaveName:autosaveName];

        NSNotificationCenter * const center = NSNotificationCenter.defaultCenter;
        [center addObserver:self selector:@selector(currentMediaChanged:)
                       name:VLCPlayerCurrentMediaItemChanged object:nil];
        [center addObserver:self selector:@selector(storeChanged:)
                       name:MacLCLibraryStoreDidChangeNotification object:nil];
        [self updatePlayingMRL];
    }
    return self;
}

- (void)dealloc
{
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (NSScrollView *)scrollView
{
    return _scrollView;
}

- (NSTableView *)tableView
{
    return _tableView;
}

// MARK: - Table

- (void)addColumn:(NSUserInterfaceItemIdentifier)identifier
            title:(NSString *)title
            width:(CGFloat)width
         minWidth:(CGFloat)minWidth
         sortable:(BOOL)sortable
       rightAlign:(BOOL)rightAlign
{
    NSTableColumn * const column = [[NSTableColumn alloc] initWithIdentifier:identifier];
    column.title = title;
    column.width = width;
    column.minWidth = minWidth;
    column.headerCell.alignment = rightAlign ? NSTextAlignmentRight : NSTextAlignmentLeft;
    /* Numbers keep their width; the text columns share the spare room (with
     * every column growing, Time took half an album's list). */
    column.resizingMask = rightAlign ? NSTableColumnUserResizingMask
                                     : NSTableColumnAutoresizingMask | NSTableColumnUserResizingMask;
    if (sortable) {
        column.sortDescriptorPrototype = [NSSortDescriptor sortDescriptorWithKey:identifier ascending:YES];
    }
    [_tableView addTableColumn:column];
}

- (void)buildTableWithAutosaveName:(nullable NSString *)autosaveName
{
    _tableView = [[MacLCTrackTableView alloc] initWithFrame:NSMakeRect(0, 0, 600, 400)];
    _tableView.listController = self;
    _tableView.style = NSTableViewStyleFullWidth;
    _tableView.usesAlternatingRowBackgroundColors = YES;
    _tableView.intercellSpacing = NSMakeSize(10.0, 0.0);
    _tableView.gridStyleMask = NSTableViewGridNone;
    _tableView.allowsMultipleSelection = YES;
    _tableView.allowsColumnReordering = YES;
    _tableView.allowsColumnResizing = YES;
    _tableView.columnAutoresizingStyle = NSTableViewUniformColumnAutoresizingStyle;
    _tableView.rowHeight = (_columns & MacLCTrackListColumnThumbnail) ? 44.0 : 28.0;
    _tableView.dataSource = self;
    _tableView.delegate = self;
    _tableView.target = self;
    _tableView.doubleAction = @selector(doubleClicked:);
    [_tableView setDraggingSourceOperationMask:NSDragOperationCopy forLocal:NO];
    [_tableView setDraggingSourceOperationMask:NSDragOperationCopy | NSDragOperationMove forLocal:YES];

    if (_columns & MacLCTrackListColumnNumber) {
        [self addColumn:MacLCColumnNumber title:@"#" width:36 minWidth:28 sortable:NO rightAlign:YES];
    }
    if (_columns & MacLCTrackListColumnThumbnail) {
        [self addColumn:MacLCColumnThumbnail title:@"" width:64 minWidth:64 sortable:NO rightAlign:NO];
        _tableView.tableColumns.lastObject.resizingMask = NSTableColumnNoResizing;
    }
    if (_columns & MacLCTrackListColumnTitle) {
        [self addColumn:MacLCColumnTitle title:_NS("Title") width:260 minWidth:120 sortable:YES rightAlign:NO];
    }
    if (_columns & MacLCTrackListColumnArtist) {
        [self addColumn:MacLCColumnArtist title:_NS("Artist") width:160 minWidth:80 sortable:YES rightAlign:NO];
    }
    if (_columns & MacLCTrackListColumnAlbum) {
        [self addColumn:MacLCColumnAlbum title:_NS("Album") width:160 minWidth:80 sortable:YES rightAlign:NO];
    }
    if (_columns & MacLCTrackListColumnGenre) {
        [self addColumn:MacLCColumnGenre title:_NS("Genre") width:110 minWidth:60 sortable:YES rightAlign:NO];
    }
    if (_columns & MacLCTrackListColumnFormat) {
        [self addColumn:MacLCColumnFormat title:_NS("Format") width:120 minWidth:60 sortable:NO rightAlign:NO];
    }
    if (_columns & MacLCTrackListColumnDateAdded) {
        [self addColumn:MacLCColumnDate title:_NS("Date Modified") width:120 minWidth:80 sortable:YES rightAlign:NO];
    }
    if (_columns & MacLCTrackListColumnPlays) {
        [self addColumn:MacLCColumnPlays title:_NS("Plays") width:52 minWidth:40 sortable:YES rightAlign:YES];
    }
    if (_columns & MacLCTrackListColumnDuration) {
        [self addColumn:MacLCColumnDuration title:_NS("Time") width:64 minWidth:52 sortable:YES rightAlign:YES];
    }
    if (autosaveName.length > 0) {
        _tableView.autosaveName = autosaveName;
        _tableView.autosaveTableColumns = YES;
    }

    _scrollView = [[NSScrollView alloc] initWithFrame:_tableView.frame];
    _scrollView.documentView = _tableView;
    _scrollView.hasVerticalScroller = YES;
    _scrollView.autohidesScrollers = YES;
    _scrollView.drawsBackground = NO;
    _scrollView.automaticallyAdjustsContentInsets = YES;
    _scrollView.translatesAutoresizingMaskIntoConstraints = NO;
}

- (void)setSortable:(BOOL)sortable
{
    _sortable = sortable;
    for (NSTableColumn * const column in _tableView.tableColumns) {
        if (!sortable) {
            column.sortDescriptorPrototype = nil;
        } else if (column.sortDescriptorPrototype == nil
                   && ![column.identifier isEqualToString:MacLCColumnNumber]
                   && ![column.identifier isEqualToString:MacLCColumnThumbnail]
                   && ![column.identifier isEqualToString:MacLCColumnFormat]) {
            column.sortDescriptorPrototype = [NSSortDescriptor sortDescriptorWithKey:column.identifier ascending:YES];
        }
    }
}

- (void)setReorderHandler:(void (^)(NSIndexSet *, NSUInteger))reorderHandler
{
    _reorderHandler = [reorderHandler copy];
    if (reorderHandler != nil) {
        [_tableView registerForDraggedTypes:@[MacLCTrackListRowPasteboardType]];
    } else {
        [_tableView unregisterDraggedTypes];
    }
}

// MARK: - Contents

- (NSArray<VLCMediaLibraryMediaItem *> *)items
{
    return _items;
}

- (void)setItems:(NSArray<VLCMediaLibraryMediaItem *> *)items
{
    NSArray<VLCMediaLibraryMediaItem *> * const previouslySelected =
        [_visibleItems objectsAtIndexes:[_tableView.selectedRowIndexes indexesPassingTest:
            ^BOOL(NSUInteger index, BOOL * const stop) { return index < self->_visibleItems.count; }]];
    _items = [items copy] ?: @[];
    [self rebuildVisibleItems];
    [_tableView reloadData];

    NSMutableIndexSet * const selection = [NSMutableIndexSet indexSet];
    for (VLCMediaLibraryMediaItem * const item in previouslySelected) {
        const NSUInteger index = [_visibleItems indexOfObjectPassingTest:
            ^BOOL(VLCMediaLibraryMediaItem * const candidate, NSUInteger idx, BOOL * const stop) {
                return candidate.libraryID == item.libraryID;
            }];
        if (index != NSNotFound) {
            [selection addIndex:index];
        }
    }
    [_tableView selectRowIndexes:selection byExtendingSelection:NO];
}

- (void)applySearchString:(NSString *)searchString
{
    _searchString = [searchString copy] ?: @"";
    [self rebuildVisibleItems];
    [_tableView reloadData];
}

- (NSUInteger)numberOfVisibleRows
{
    return _visibleItems.count;
}

- (NSString *)artistOf:(VLCMediaLibraryMediaItem *)item
{
    return [MacLCLibraryStore.sharedStore nameOfArtistWithID:item.artistID] ?: @"";
}

- (NSString *)albumOf:(VLCMediaLibraryMediaItem *)item
{
    return [MacLCLibraryStore.sharedStore titleOfAlbumWithID:item.albumID] ?: @"";
}

- (NSString *)genreOf:(VLCMediaLibraryMediaItem *)item
{
    return [MacLCLibraryStore.sharedStore nameOfGenreWithID:item.genreID] ?: @"";
}

- (time_t)dateOf:(VLCMediaLibraryMediaItem *)item
{
    return item.files.firstObject.lastModificationDate;
}

- (void)rebuildVisibleItems
{
    NSString * const query = [_searchString stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    NSArray<VLCMediaLibraryMediaItem *> *visible = _items;
    if (query.length > 0) {
        NSMutableArray * const filtered = [NSMutableArray array];
        for (VLCMediaLibraryMediaItem * const item in _items) {
            if ([item.displayString localizedStandardContainsString:query]
                || [[self artistOf:item] localizedStandardContainsString:query]
                || [[self albumOf:item] localizedStandardContainsString:query]) {
                [filtered addObject:item];
            }
        }
        visible = filtered;
    }

    NSSortDescriptor * const sort = _tableView.sortDescriptors.firstObject;
    if (sort != nil) {
        NSString * const key = sort.key;
        const BOOL ascending = sort.ascending;
        visible = [visible sortedArrayWithOptions:NSSortStable usingComparator:
            ^NSComparisonResult(VLCMediaLibraryMediaItem * const a, VLCMediaLibraryMediaItem * const b) {
                NSComparisonResult result = NSOrderedSame;
                if ([key isEqualToString:MacLCColumnTitle]) {
                    result = [a.displayString ?: @"" localizedStandardCompare:b.displayString ?: @""];
                } else if ([key isEqualToString:MacLCColumnArtist]) {
                    result = [[self artistOf:a] localizedStandardCompare:[self artistOf:b]];
                } else if ([key isEqualToString:MacLCColumnAlbum]) {
                    result = [[self albumOf:a] localizedStandardCompare:[self albumOf:b]];
                } else if ([key isEqualToString:MacLCColumnGenre]) {
                    result = [[self genreOf:a] localizedStandardCompare:[self genreOf:b]];
                } else if ([key isEqualToString:MacLCColumnDuration]) {
                    result = a.duration == b.duration ? NSOrderedSame
                        : (a.duration < b.duration ? NSOrderedAscending : NSOrderedDescending);
                } else if ([key isEqualToString:MacLCColumnPlays]) {
                    result = a.playCount == b.playCount ? NSOrderedSame
                        : (a.playCount < b.playCount ? NSOrderedAscending : NSOrderedDescending);
                } else if ([key isEqualToString:MacLCColumnDate]) {
                    const time_t da = [self dateOf:a], db = [self dateOf:b];
                    result = da == db ? NSOrderedSame : (da < db ? NSOrderedAscending : NSOrderedDescending);
                }
                return ascending ? result : -result;
            }];
    }
    _visibleItems = visible;
}

// MARK: - Now playing

- (void)updatePlayingMRL
{
    _playingMRL = VLCMain.sharedInstance.playQueueController.currentlyPlayingInputItem.MRL;
}

- (void)currentMediaChanged:(NSNotification *)notification
{
    [self updatePlayingMRL];
    [_tableView reloadData];
}

- (void)storeChanged:(NSNotification *)notification
{
    /* Artist, album and genre names may have arrived. */
    [_tableView reloadData];
}

- (BOOL)isPlaying:(VLCMediaLibraryMediaItem *)item
{
    if (_playingMRL.length == 0) {
        return NO;
    }
    NSString * const mrl = item.files.firstObject.MRL;
    return mrl != nil && [mrl isEqualToString:_playingMRL];
}

// MARK: - NSTableViewDataSource

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
    return (NSInteger)_visibleItems.count;
}

- (void)tableView:(NSTableView *)tableView sortDescriptorsDidChange:(NSArray<NSSortDescriptor *> *)oldDescriptors
{
    [self rebuildVisibleItems];
    [_tableView reloadData];
}

- (id<NSPasteboardWriting>)tableView:(NSTableView *)tableView pasteboardWriterForRow:(NSInteger)row
{
    if (row < 0 || row >= (NSInteger)_visibleItems.count) {
        return nil;
    }
    NSPasteboardItem * const pasteboardItem =
        (NSPasteboardItem *)[MacLCLibraryActions pasteboardWriterForItem:_visibleItems[(NSUInteger)row]]
        ?: [[NSPasteboardItem alloc] init];
    if ([pasteboardItem isKindOfClass:NSPasteboardItem.class] && _reorderHandler != nil) {
        [pasteboardItem setString:[NSString stringWithFormat:@"%ld", (long)row] forType:MacLCTrackListRowPasteboardType];
    }
    return pasteboardItem;
}

- (NSDragOperation)tableView:(NSTableView *)tableView
                validateDrop:(id<NSDraggingInfo>)info
                 proposedRow:(NSInteger)row
       proposedDropOperation:(NSTableViewDropOperation)dropOperation
{
    if (_reorderHandler == nil || info.draggingSource != _tableView || _searchString.length > 0
        || _tableView.sortDescriptors.count > 0) {
        return NSDragOperationNone;
    }
    [tableView setDropRow:row dropOperation:NSTableViewDropAbove];
    return NSDragOperationMove;
}

- (BOOL)tableView:(NSTableView *)tableView
       acceptDrop:(id<NSDraggingInfo>)info
              row:(NSInteger)row
    dropOperation:(NSTableViewDropOperation)dropOperation
{
    if (_reorderHandler == nil) {
        return NO;
    }
    NSMutableIndexSet * const rows = [NSMutableIndexSet indexSet];
    for (NSPasteboardItem * const item in info.draggingPasteboard.pasteboardItems) {
        NSString * const value = [item stringForType:MacLCTrackListRowPasteboardType];
        if (value != nil) {
            [rows addIndex:(NSUInteger)value.integerValue];
        }
    }
    if (rows.count == 0) {
        return NO;
    }
    _reorderHandler(rows, (NSUInteger)MAX(row, 0));
    return YES;
}

- (NSString *)tableView:(NSTableView *)tableView
    typeSelectStringForTableColumn:(NSTableColumn *)tableColumn
                               row:(NSInteger)row
{
    if (![tableColumn.identifier isEqualToString:MacLCColumnTitle] || row >= (NSInteger)_visibleItems.count) {
        return nil;
    }
    return _visibleItems[(NSUInteger)row].displayString;
}

// MARK: - NSTableViewDelegate

- (NSTableCellView *)textCellForTable:(NSTableView *)tableView identifier:(NSString *)identifier
{
    NSTableCellView *cell = [tableView makeViewWithIdentifier:identifier owner:self];
    if (cell != nil) {
        return cell;
    }
    cell = [[NSTableCellView alloc] initWithFrame:NSMakeRect(0, 0, 100, 24)];
    cell.identifier = identifier;
    NSTextField * const field = [NSTextField labelWithString:@""];
    field.translatesAutoresizingMaskIntoConstraints = NO;
    field.lineBreakMode = NSLineBreakByTruncatingTail;
    field.font = MacLCDesign.body;
    [cell addSubview:field];
    cell.textField = field;
    NSImageView * const imageView = [[NSImageView alloc] initWithFrame:NSZeroRect];
    imageView.translatesAutoresizingMaskIntoConstraints = NO;
    imageView.hidden = YES;
    [cell addSubview:imageView];
    cell.imageView = imageView;
    [NSLayoutConstraint activateConstraints:@[
        [field.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:2.0],
        [field.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-2.0],
        [field.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
        [imageView.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-2.0],
        [imageView.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
    ]];
    return cell;
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
    if (row < 0 || row >= (NSInteger)_visibleItems.count) {
        return nil;
    }
    VLCMediaLibraryMediaItem * const item = _visibleItems[(NSUInteger)row];
    NSString * const identifier = tableColumn.identifier;
    const BOOL playing = [self isPlaying:item];

    if ([identifier isEqualToString:MacLCColumnThumbnail]) {
        MacLCArtworkView *artwork = [tableView makeViewWithIdentifier:identifier owner:self];
        if (artwork == nil) {
            artwork = [[MacLCArtworkView alloc] initWithShape:MacLCArtworkShapeVideo];
            artwork.identifier = identifier;
        }
        artwork.progress = item.progress > 0.02f && item.progress < 0.95f ? item.progress : 0.0;
        [artwork setArtworkFromItem:item];
        return artwork;
    }

    NSTableCellView * const cell = [self textCellForTable:tableView identifier:identifier];
    NSTextField * const field = cell.textField;
    field.textColor = NSColor.labelColor;
    field.font = MacLCDesign.body;
    field.alignment = NSTextAlignmentLeft;
    cell.imageView.hidden = YES;

    if ([identifier isEqualToString:MacLCColumnNumber]) {
        field.alignment = NSTextAlignmentRight;
        field.textColor = NSColor.tertiaryLabelColor;
        field.font = [MacLCDesign monospacedDigitFontForTextStyle:NSFontTextStyleBody];
        if (playing) {
            field.stringValue = @"";
            cell.imageView.image = [NSImage imageWithSystemSymbolName:@"speaker.wave.2.fill"
                                             accessibilityDescription:_NS("Now Playing")];
            cell.imageView.contentTintColor = MacLCDesign.accent;
            cell.imageView.hidden = NO;
        } else {
            const int number = item.mediaSubType == VLC_ML_MEDIA_SUBTYPE_SHOW_EPISODE
                ? (int)item.showEpisode.episodeNumber : item.trackNumber;
            field.stringValue = number > 0 ? [NSString stringWithFormat:@"%d", number] : @"";
        }
    } else if ([identifier isEqualToString:MacLCColumnTitle]) {
        field.stringValue = item.displayString ?: @"";
        if (playing) {
            field.font = [NSFont systemFontOfSize:MacLCDesign.body.pointSize weight:NSFontWeightSemibold];
            if (!(_columns & MacLCTrackListColumnNumber)) {
                cell.imageView.image = [NSImage imageWithSystemSymbolName:@"speaker.wave.2.fill"
                                                 accessibilityDescription:_NS("Now Playing")];
                cell.imageView.contentTintColor = MacLCDesign.accent;
                cell.imageView.hidden = NO;
            }
        }
    } else if ([identifier isEqualToString:MacLCColumnArtist]) {
        field.stringValue = [self artistOf:item];
        field.textColor = NSColor.secondaryLabelColor;
    } else if ([identifier isEqualToString:MacLCColumnAlbum]) {
        field.stringValue = [self albumOf:item];
        field.textColor = NSColor.secondaryLabelColor;
    } else if ([identifier isEqualToString:MacLCColumnGenre]) {
        field.stringValue = [self genreOf:item];
        field.textColor = NSColor.secondaryLabelColor;
    } else if ([identifier isEqualToString:MacLCColumnDuration]) {
        field.alignment = NSTextAlignmentRight;
        field.font = [MacLCDesign monospacedDigitFontForTextStyle:NSFontTextStyleBody];
        field.textColor = NSColor.secondaryLabelColor;
        field.stringValue = [MacLCTrackListController stringForDuration:item.duration];
    } else if ([identifier isEqualToString:MacLCColumnPlays]) {
        field.alignment = NSTextAlignmentRight;
        field.textColor = NSColor.secondaryLabelColor;
        field.stringValue = item.playCount > 0 ? [NSString stringWithFormat:@"%u", item.playCount] : @"";
    } else if ([identifier isEqualToString:MacLCColumnDate]) {
        const time_t date = [self dateOf:item];
        field.textColor = NSColor.secondaryLabelColor;
        field.stringValue = date > 0
            ? [_dateFormatter stringFromDate:[NSDate dateWithTimeIntervalSince1970:(NSTimeInterval)date]] : @"";
    } else if ([identifier isEqualToString:MacLCColumnFormat]) {
        field.textColor = NSColor.secondaryLabelColor;
        field.stringValue = [[MacLCMediaFormat formatForMediaItem:item].badges componentsJoinedByString:@" · "];
    }
    return cell;
}

+ (NSString *)stringForDuration:(int64_t)milliseconds
{
    if (milliseconds <= 0) {
        return @"";
    }
    const int64_t seconds = milliseconds / 1000;
    if (seconds >= 3600) {
        return [NSString stringWithFormat:@"%lld:%02lld:%02lld", seconds / 3600, (seconds / 60) % 60, seconds % 60];
    }
    return [NSString stringWithFormat:@"%lld:%02lld", seconds / 60, seconds % 60];
}

// MARK: - Actions

- (void)doubleClicked:(id)sender
{
    [self activateRow:_tableView.clickedRow];
}

- (void)activateRow:(NSInteger)row
{
    if (row < 0 || row >= (NSInteger)_visibleItems.count) {
        return;
    }
    [MacLCLibraryActions playItems:_visibleItems startingAt:(NSUInteger)row];
}

- (void)deleteSelectedRows
{
    if (_deleteHandler != nil && _tableView.selectedRowIndexes.count > 0) {
        _deleteHandler(_tableView.selectedRowIndexes);
    }
}

- (NSMenu *)menuForRow:(NSInteger)row
{
    NSIndexSet * const rows = [_tableView.selectedRowIndexes indexesPassingTest:
        ^BOOL(NSUInteger index, BOOL * const stop) { return index < self->_visibleItems.count; }];
    NSArray * const items = [_visibleItems objectsAtIndexes:rows];
    return [MacLCLibraryActions contextMenuForItems:items window:_tableView.window];
}

@end
