/*****************************************************************************
 * MacLCUpNextViewController.m: the play queue, as the window's inspector
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

#import "medialib/shell/MacLCUpNextViewController.h"

#import <vlc_common.h>
#import <vlc_playlist.h>

#import "extensions/NSString+Helpers.h"
#import "library/VLCInputItem.h"
#import "library/VLCLibraryController.h"
#import "library/VLCLibraryDataTypes.h"
#import "library/VLCLibraryImageCache.h"
#import "library/VLCLibraryWindow.h"
#import "library/VLCLibraryWindowChaptersSidebarViewController.h"
#import "main/VLCMain.h"
#import "medialib/MacLCLibraryFormatting.h"
#import "medialib/components/MacLCEmptyStateView.h"
#import "medialib/components/MacLCTrackListController.h"
#import "medialib/data/MacLCLibraryActions.h"
#import "playqueue/VLCPlayerController.h"
#import "playqueue/VLCPlayQueueController.h"
#import "playqueue/VLCPlayQueueItem.h"
#import "playqueue/VLCPlayQueueModel.h"
#import "theme/MacLCDesign.h"
#import "windows/VLCOpenInputMetadata.h"

static NSPasteboardType const MacLCUpNextRowPasteboardType = @"org.maclc.up-next.rows";
static NSUserInterfaceItemIdentifier const MacLCUpNextCellIdentifier = @"MacLCUpNextCell";

/* One queue row: artwork, title over subtitle, duration. */
@interface MacLCUpNextCellView : NSTableCellView
@property (nonatomic, readonly) NSImageView *artworkView;
@property (nonatomic, readonly) NSTextField *titleField;
@property (nonatomic, readonly) NSTextField *subtitleField;
@property (nonatomic, readonly) NSTextField *durationField;
@property (nonatomic, readonly) NSImageView *playingView;
@property (nonatomic) uint64_t representedID;
@end

@implementation MacLCUpNextCellView

- (instancetype)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (self) {
        self.identifier = MacLCUpNextCellIdentifier;

        _artworkView = [[NSImageView alloc] initWithFrame:NSZeroRect];
        _artworkView.imageScaling = NSImageScaleProportionallyUpOrDown;
        _artworkView.wantsLayer = YES;
        _artworkView.layer.cornerRadius = 5.0;
        _artworkView.layer.cornerCurve = kCACornerCurveContinuous;
        _artworkView.layer.masksToBounds = YES;
        _artworkView.translatesAutoresizingMaskIntoConstraints = NO;

        _titleField = [NSTextField labelWithString:@""];
        _titleField.font = MacLCDesign.body;
        _titleField.lineBreakMode = NSLineBreakByTruncatingTail;
        _subtitleField = [NSTextField labelWithString:@""];
        _subtitleField.font = MacLCDesign.subheadline;
        _subtitleField.textColor = NSColor.secondaryLabelColor;
        _subtitleField.lineBreakMode = NSLineBreakByTruncatingTail;
        _durationField = [NSTextField labelWithString:@""];
        _durationField.font = [MacLCDesign monospacedDigitFontForTextStyle:NSFontTextStyleSubheadline];
        _durationField.textColor = NSColor.secondaryLabelColor;
        _durationField.alignment = NSTextAlignmentRight;
        [_durationField setContentCompressionResistancePriority:NSLayoutPriorityRequired
                                                 forOrientation:NSLayoutConstraintOrientationHorizontal];
        _playingView = [NSImageView imageViewWithImage:
            [NSImage imageWithSystemSymbolName:@"speaker.wave.2.fill" accessibilityDescription:_NS("Now Playing")]];
        _playingView.contentTintColor = MacLCDesign.accent;
        _playingView.hidden = YES;

        NSStackView * const text = [NSStackView stackViewWithViews:@[_titleField, _subtitleField]];
        text.orientation = NSUserInterfaceLayoutOrientationVertical;
        text.alignment = NSLayoutAttributeLeading;
        text.spacing = 1.0;
        NSStackView * const row = [NSStackView stackViewWithViews:@[_artworkView, text, _playingView, _durationField]];
        row.orientation = NSUserInterfaceLayoutOrientationHorizontal;
        row.spacing = 10.0;
        row.alignment = NSLayoutAttributeCenterY;
        [row setHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
        [text setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
                                       forOrientation:NSLayoutConstraintOrientationHorizontal];
        row.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:row];
        [NSLayoutConstraint activateConstraints:@[
            [_artworkView.widthAnchor constraintEqualToConstant:40.0],
            [_artworkView.heightAnchor constraintEqualToConstant:40.0],
            [row.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:6.0],
            [row.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-8.0],
            [row.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        ]];
        self.textField = _titleField;
        self.imageView = _artworkView;
    }
    return self;
}

@end

@interface MacLCUpNextTableView : NSTableView
@property (nonatomic, copy, nullable) void (^deleteHandler)(void);
@property (nonatomic, copy, nullable) void (^returnHandler)(void);
@property (nonatomic, copy, nullable) NSMenu * _Nullable (^menuProvider)(NSInteger row);
@end

@implementation MacLCUpNextTableView

- (void)keyDown:(NSEvent *)event
{
    if ((event.keyCode == 51 || event.keyCode == 117) && self.deleteHandler != nil) {
        self.deleteHandler();
        return;
    }
    if ((event.keyCode == 36 || event.keyCode == 76) && self.returnHandler != nil) {
        self.returnHandler();
        return;
    }
    [super keyDown:event];
}

- (NSMenu *)menuForEvent:(NSEvent *)event
{
    const NSInteger row = [self rowAtPoint:[self convertPoint:event.locationInWindow fromView:nil]];
    if (row < 0 || self.menuProvider == nil) {
        return nil;
    }
    if (![self.selectedRowIndexes containsIndex:(NSUInteger)row]) {
        [self selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row] byExtendingSelection:NO];
    }
    return self.menuProvider(row);
}

@end

@interface MacLCUpNextViewController () <NSTableViewDataSource, NSTableViewDelegate>
{
    __weak VLCLibraryWindow *_libraryWindow;
    NSScrollView *_scrollView;
    MacLCUpNextTableView *_tableView;
    NSSegmentedControl *_segmentedControl;
    NSPopUpButton *_moreButton;
    MacLCEmptyStateView *_emptyState;
    VLCLibraryWindowChaptersSidebarViewController *_chaptersViewController;
    NSArray<VLCPlayQueueItem *> *_items;
}
@end

@implementation MacLCUpNextViewController

- (instancetype)initWithLibraryWindow:(VLCLibraryWindow *)libraryWindow
{
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _libraryWindow = libraryWindow;
        _items = @[];
    }
    return self;
}

- (void)dealloc
{
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (VLCPlayQueueController *)playQueue
{
    return VLCMain.sharedInstance.playQueueController;
}

- (void)loadView
{
    NSView * const root = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 320, 600)];

    NSTextField * const title = [NSTextField labelWithString:_NS("Up Next")];
    title.font = MacLCDesign.headline;
    title.accessibilityRole = NSAccessibilityStaticTextRole;

    _segmentedControl = [NSSegmentedControl segmentedControlWithLabels:@[_NS("Queue"), _NS("Chapters")]
                                                          trackingMode:NSSegmentSwitchTrackingSelectOne
                                                                target:self
                                                                action:@selector(segmentedControlChanged:)];
    _segmentedControl.segmentStyle = NSSegmentStyleAutomatic;
    _segmentedControl.controlSize = NSControlSizeSmall;
    _segmentedControl.accessibilityLabel = _NS("Up Next View");
    _segmentedControl.selectedSegment = 0;
    _segmentedControl.hidden = YES;

    _moreButton = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:YES];
    _moreButton.bezelStyle = NSBezelStyleGlass;
    _moreButton.controlSize = NSControlSizeRegular;
    _moreButton.imagePosition = NSImageOnly;
    ((NSPopUpButtonCell *)_moreButton.cell).arrowPosition = NSPopUpNoArrow;
    _moreButton.toolTip = _NS("Up Next Options");
    _moreButton.accessibilityLabel = _NS("Up Next Options");
    _moreButton.menu.delegate = (id<NSMenuDelegate>)self;
    [self rebuildMoreMenu];

    NSStackView * const trailingControls = [NSStackView stackViewWithViews:@[_segmentedControl, _moreButton]];
    trailingControls.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    trailingControls.spacing = MacLCDesign.spacingS;
    trailingControls.alignment = NSLayoutAttributeCenterY;

    /* Title leading, controls trailing, whatever the inspector's width (a
     * stack view kept them side by side). */
    NSView * const header = [[NSView alloc] initWithFrame:NSZeroRect];
    header.translatesAutoresizingMaskIntoConstraints = NO;
    title.translatesAutoresizingMaskIntoConstraints = NO;
    trailingControls.translatesAutoresizingMaskIntoConstraints = NO;
    [header addSubview:title];
    [header addSubview:trailingControls];
    NSLayoutConstraint * const compactHeight = [header.heightAnchor constraintEqualToConstant:28.0];
    compactHeight.priority = NSLayoutPriorityDefaultLow;
    [NSLayoutConstraint activateConstraints:@[
        [title.leadingAnchor constraintEqualToAnchor:header.leadingAnchor],
        [title.centerYAnchor constraintEqualToAnchor:header.centerYAnchor],
        [trailingControls.trailingAnchor constraintEqualToAnchor:header.trailingAnchor],
        [trailingControls.centerYAnchor constraintEqualToAnchor:header.centerYAnchor],
        [trailingControls.leadingAnchor constraintGreaterThanOrEqualToAnchor:title.trailingAnchor constant:8.0],
        [header.heightAnchor constraintGreaterThanOrEqualToAnchor:trailingControls.heightAnchor],
        [header.heightAnchor constraintGreaterThanOrEqualToAnchor:title.heightAnchor],
        compactHeight,
    ]];
    [root addSubview:header];

    _tableView = [[MacLCUpNextTableView alloc] initWithFrame:NSMakeRect(0, 0, 320, 400)];
    _tableView.style = NSTableViewStyleInset;
    _tableView.rowHeight = 52.0;
    _tableView.headerView = nil;
    _tableView.allowsMultipleSelection = YES;
    _tableView.dataSource = self;
    _tableView.delegate = self;
    _tableView.target = self;
    _tableView.doubleAction = @selector(doubleClicked:);
    [_tableView addTableColumn:[[NSTableColumn alloc] initWithIdentifier:@"item"]];
    _tableView.tableColumns.firstObject.resizingMask = NSTableColumnAutoresizingMask;
    _tableView.columnAutoresizingStyle = NSTableViewFirstColumnOnlyAutoresizingStyle;
    /* The only column spans the inspector (it stayed at 100 pt otherwise). */
    _tableView.autoresizingMask = NSViewWidthSizable;
    [_tableView registerForDraggedTypes:@[MacLCUpNextRowPasteboardType, NSPasteboardTypeFileURL,
                                          VLCMediaLibraryMediaItemPasteboardType, VLCMediaLibraryMediaItemUTI]];
    [_tableView setDraggingSourceOperationMask:NSDragOperationMove forLocal:YES];
    __weak typeof(self) weakSelf = self;
    _tableView.deleteHandler = ^{
        [weakSelf removeSelection:nil];
    };
    _tableView.returnHandler = ^{
        [weakSelf playRow:weakSelf.tableViewSelectedRow];
    };
    _tableView.menuProvider = ^NSMenu *(NSInteger row) {
        return [weakSelf contextMenu];
    };

    _scrollView = [[NSScrollView alloc] initWithFrame:root.bounds];
    _scrollView.documentView = _tableView;
    _scrollView.drawsBackground = NO;
    _scrollView.hasVerticalScroller = YES;
    _scrollView.autohidesScrollers = YES;
    _scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    [root addSubview:_scrollView];

    [NSLayoutConstraint activateConstraints:@[
        [header.topAnchor constraintEqualToAnchor:root.safeAreaLayoutGuide.topAnchor constant:8.0],
        [header.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:16.0],
        [header.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-12.0],
        [_scrollView.topAnchor constraintEqualToAnchor:header.bottomAnchor constant:6.0],
        [_scrollView.leadingAnchor constraintEqualToAnchor:root.leadingAnchor],
        [_scrollView.trailingAnchor constraintEqualToAnchor:root.trailingAnchor],
        [_scrollView.bottomAnchor constraintEqualToAnchor:root.bottomAnchor],
    ]];
    self.view = root;

    NSNotificationCenter * const center = NSNotificationCenter.defaultCenter;
    [center addObserver:self selector:@selector(queueChanged:) name:VLCPlayQueueItemsChanged object:nil];
    [center addObserver:self selector:@selector(queueChanged:) name:VLCPlayQueueCurrentItemIndexChanged object:nil];
    [center addObserver:self selector:@selector(queueChanged:) name:VLCPlayerCurrentMediaItemChanged object:nil];
    [center addObserver:self selector:@selector(orderChanged:) name:VLCPlaybackOrderChanged object:nil];
    [center addObserver:self selector:@selector(orderChanged:) name:VLCPlaybackRepeatChanged object:nil];
    [center addObserver:self selector:@selector(chaptersChanged:) name:VLCPlayerTitleListChanged object:nil];
    [center addObserver:self selector:@selector(chaptersChanged:) name:VLCPlayerTitleSelectionChanged object:nil];
    [self reload];
    [self updateChaptersAvailability];
}

- (void)viewDidLayout
{
    [super viewDidLayout];
    [_tableView sizeLastColumnToFit];
}

- (NSInteger)tableViewSelectedRow
{
    return _tableView.selectedRow;
}

// MARK: - Contents

- (void)segmentedControlChanged:(NSSegmentedControl *)sender
{
    [self updateViewMode];
}

- (void)chaptersChanged:(NSNotification *)notification
{
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self updateChaptersAvailability];
        });
        return;
    }
    [self updateChaptersAvailability];
}

- (void)updateChaptersAvailability
{
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self updateChaptersAvailability];
        });
        return;
    }

    const BOOL hasChapters = self.playQueue.playerController.numberOfChaptersForCurrentTitle > 0;
    _segmentedControl.hidden = !hasChapters;
    if (!hasChapters && _segmentedControl.selectedSegment != 0) {
        _segmentedControl.selectedSegment = 0;
    }
    [self updateViewMode];
}

- (void)updateViewMode
{
    const BOOL showChapters = (_segmentedControl.selectedSegment == 1 && !_segmentedControl.isHidden);
    if (showChapters) {
        if (_chaptersViewController == nil) {
            _chaptersViewController = [[VLCLibraryWindowChaptersSidebarViewController alloc] initWithLibraryWindow:_libraryWindow];
            [self addChildViewController:_chaptersViewController];
            NSView * const chaptersView = _chaptersViewController.view;
            chaptersView.translatesAutoresizingMaskIntoConstraints = NO;
            [self.view addSubview:chaptersView];
            [NSLayoutConstraint activateConstraints:@[
                [chaptersView.topAnchor constraintEqualToAnchor:_scrollView.topAnchor],
                [chaptersView.leadingAnchor constraintEqualToAnchor:_scrollView.leadingAnchor],
                [chaptersView.trailingAnchor constraintEqualToAnchor:_scrollView.trailingAnchor],
                [chaptersView.bottomAnchor constraintEqualToAnchor:_scrollView.bottomAnchor],
            ]];
        }
        _chaptersViewController.view.hidden = NO;
        _scrollView.hidden = YES;
        _emptyState.hidden = YES;
    } else {
        if (_chaptersViewController != nil) {
            _chaptersViewController.view.hidden = YES;
        }
        _scrollView.hidden = NO;
        _emptyState.hidden = NO;
    }
}

- (void)queueChanged:(NSNotification *)notification
{
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self reload];
            [self updateChaptersAvailability];
        });
        return;
    }
    [self reload];
    [self updateChaptersAvailability];
}

- (void)orderChanged:(NSNotification *)notification
{
    [self rebuildMoreMenu];
}

- (void)reload
{
    _items = [self.playQueue.playQueueModel.playQueueItems copy] ?: @[];
    [_tableView reloadData];

    [_emptyState removeFromSuperview];
    _emptyState = nil;
    if (_items.count == 0) {
        _emptyState = [MacLCEmptyStateView emptyStateWithSymbolName:@"list.bullet"
                                                              title:_NS("Nothing Up Next")
                                                            message:_NS("Add songs and videos with Play Next or Add to Up Next.")];
        _emptyState.translatesAutoresizingMaskIntoConstraints = NO;
        [self.view addSubview:_emptyState];
        [NSLayoutConstraint activateConstraints:@[
            [_emptyState.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
            [_emptyState.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
            [_emptyState.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.view.leadingAnchor constant:16.0],
            [_emptyState.trailingAnchor constraintLessThanOrEqualToAnchor:self.view.trailingAnchor constant:-16.0],
        ]];
    }
    [self updateViewMode];
}

- (void)rebuildMoreMenu
{
    VLCPlayQueueController * const queue = self.playQueue;
    NSMenu * const menu = [[NSMenu alloc] initWithTitle:@""];
    NSMenuItem * const titleItem = [menu addItemWithTitle:@"" action:nil keyEquivalent:@""];
    titleItem.image = [NSImage imageWithSystemSymbolName:@"ellipsis" accessibilityDescription:_NS("Up Next Options")];

    NSMenuItem * const shuffle = [menu addItemWithTitle:_NS("Shuffle") action:@selector(toggleShuffle:) keyEquivalent:@""];
    shuffle.target = self;
    shuffle.state = queue.playbackOrder == VLC_PLAYLIST_PLAYBACK_ORDER_RANDOM ? NSControlStateValueOn : NSControlStateValueOff;

    NSMenuItem * const repeat = [menu addItemWithTitle:_NS("Repeat") action:nil keyEquivalent:@""];
    NSMenu * const repeatMenu = [[NSMenu alloc] initWithTitle:_NS("Repeat")];
    const enum vlc_playlist_playback_repeat current = queue.playbackRepeat;
    NSArray * const modes = @[@[_NS("Off"), @(VLC_PLAYLIST_PLAYBACK_REPEAT_NONE)],
                              @[_NS("All"), @(VLC_PLAYLIST_PLAYBACK_REPEAT_ALL)],
                              @[_NS("One"), @(VLC_PLAYLIST_PLAYBACK_REPEAT_CURRENT)]];
    for (NSArray * const mode in modes) {
        NSMenuItem * const item = [repeatMenu addItemWithTitle:mode[0] action:@selector(setRepeat:) keyEquivalent:@""];
        item.target = self;
        item.tag = [mode[1] integerValue];
        item.state = (NSInteger)current == item.tag ? NSControlStateValueOn : NSControlStateValueOff;
    }
    repeat.submenu = repeatMenu;

    [menu addItem:NSMenuItem.separatorItem];
    NSMenuItem * const save = [menu addItemWithTitle:_NS("Save as Playlist…") action:@selector(saveAsPlaylist:) keyEquivalent:@""];
    save.target = self;
    NSMenuItem * const clear = [menu addItemWithTitle:_NS("Clear Up Next") action:@selector(clearQueue:) keyEquivalent:@""];
    clear.target = self;
    _moreButton.menu = menu;
}

// MARK: - Actions

- (void)toggleShuffle:(id)sender
{
    VLCPlayQueueController * const queue = self.playQueue;
    queue.playbackOrder = queue.playbackOrder == VLC_PLAYLIST_PLAYBACK_ORDER_RANDOM
        ? VLC_PLAYLIST_PLAYBACK_ORDER_NORMAL : VLC_PLAYLIST_PLAYBACK_ORDER_RANDOM;
    [self rebuildMoreMenu];
}

- (void)setRepeat:(NSMenuItem *)sender
{
    self.playQueue.playbackRepeat = (enum vlc_playlist_playback_repeat)sender.tag;
    [self rebuildMoreMenu];
}

- (void)saveAsPlaylist:(id)sender
{
    [VLCMain.sharedInstance.libraryController showCreatePlaylistDialogForPlayQueue];
}

- (void)clearQueue:(id)sender
{
    [self.playQueue clearPlayQueue];
}

- (void)doubleClicked:(id)sender
{
    [self playRow:_tableView.clickedRow];
}

- (void)playRow:(NSInteger)row
{
    if (row >= 0 && row < (NSInteger)_items.count) {
        [self.playQueue playItemAtIndex:(size_t)row];
    }
}

- (void)removeSelection:(id)sender
{
    NSIndexSet * const rows = _tableView.selectedRowIndexes;
    if (rows.count > 0) {
        [self.playQueue removeItemsAtIndexes:rows];
    }
}

- (void)playSelection:(id)sender
{
    [self playRow:_tableView.selectedRow];
}

- (void)showSelectionInFinder:(id)sender
{
    NSMutableArray<NSURL *> * const urls = [NSMutableArray array];
    [_tableView.selectedRowIndexes enumerateIndexesUsingBlock:^(NSUInteger row, BOOL * const stop) {
        NSString * const path = row < self->_items.count ? self->_items[row].path : nil;
        if (path.length > 0) {
            [urls addObject:[NSURL fileURLWithPath:path]];
        }
    }];
    if (urls.count > 0) {
        [NSWorkspace.sharedWorkspace activateFileViewerSelectingURLs:urls];
    }
}

- (void)showSelectionInfo:(id)sender
{
    const NSInteger row = _tableView.selectedRow;
    VLCMediaLibraryMediaItem * const media = row >= 0 && row < (NSInteger)_items.count
        ? _items[(NSUInteger)row].mediaLibraryItem : nil;
    if (media != nil) {
        [MacLCLibraryActions showInfoForItem:media];
    }
}

- (NSMenu *)contextMenu
{
    NSMenu * const menu = [[NSMenu alloc] initWithTitle:@""];
    NSMenuItem * const play = [menu addItemWithTitle:_NS("Play") action:@selector(playSelection:) keyEquivalent:@""];
    play.target = self;
    NSMenuItem * const remove = [menu addItemWithTitle:_NS("Remove from Up Next") action:@selector(removeSelection:) keyEquivalent:@""];
    remove.target = self;
    [menu addItem:NSMenuItem.separatorItem];
    NSMenuItem * const finder = [menu addItemWithTitle:_NS("Show in Finder") action:@selector(showSelectionInFinder:) keyEquivalent:@""];
    finder.target = self;
    NSMenuItem * const info = [menu addItemWithTitle:_NS("Get Info") action:@selector(showSelectionInfo:) keyEquivalent:@""];
    info.target = self;
    return menu;
}

// MARK: - NSTableViewDataSource

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
    return (NSInteger)_items.count;
}

- (id<NSPasteboardWriting>)tableView:(NSTableView *)tableView pasteboardWriterForRow:(NSInteger)row
{
    NSPasteboardItem * const item = [[NSPasteboardItem alloc] init];
    [item setString:[NSString stringWithFormat:@"%ld", (long)row] forType:MacLCUpNextRowPasteboardType];
    return item;
}

- (NSDragOperation)tableView:(NSTableView *)tableView
                validateDrop:(id<NSDraggingInfo>)info
                 proposedRow:(NSInteger)row
       proposedDropOperation:(NSTableViewDropOperation)dropOperation
{
    [tableView setDropRow:row dropOperation:NSTableViewDropAbove];
    return info.draggingSource == tableView ? NSDragOperationMove : NSDragOperationCopy;
}

- (BOOL)tableView:(NSTableView *)tableView
       acceptDrop:(id<NSDraggingInfo>)info
              row:(NSInteger)row
    dropOperation:(NSTableViewDropOperation)dropOperation
{
    NSPasteboard * const pasteboard = info.draggingPasteboard;
    VLCPlayQueueController * const queue = self.playQueue;

    if (info.draggingSource == tableView) {
        NSMutableIndexSet * const sourceRows = [NSMutableIndexSet indexSet];
        for (NSPasteboardItem * const item in pasteboard.pasteboardItems) {
            NSString * const str = [item stringForType:MacLCUpNextRowPasteboardType];
            if (str != nil) {
                const NSInteger source = str.integerValue;
                if (source >= 0 && source < (NSInteger)_items.count) {
                    [sourceRows addIndex:(NSUInteger)source];
                }
            }
        }
        if (sourceRows.count == 0) {
            return NO;
        }

        NSMutableArray<VLCPlayQueueItem *> * const draggedItems = [NSMutableArray arrayWithCapacity:sourceRows.count];
        [sourceRows enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL * const stop) {
            [draggedItems addObject:self->_items[idx]];
        }];

        const NSInteger clampedRow = MAX(0, MIN(row, (NSInteger)_items.count));

        // Count how many dragged items were originally above the drop row
        NSUInteger countAbove = 0;
        for (VLCPlayQueueItem * const item in draggedItems) {
            const NSUInteger origIdx = [_items indexOfObject:item];
            if (origIdx < (NSUInteger)clampedRow) {
                countAbove++;
            }
        }

        const size_t insertionIndex = (size_t)clampedRow - countAbove;

        // Construct desired final ordering
        NSMutableArray<VLCPlayQueueItem *> * const desired = [_items mutableCopy];
        [desired removeObjectsInArray:draggedItems];
        [desired insertObjects:draggedItems
                     atIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(insertionIndex, draggedItems.count)]];

        NSMutableArray<VLCPlayQueueItem *> * const currentList = [_items mutableCopy];

        // Items coming from above the drop row move down: process in reverse order
        NSMutableArray<VLCPlayQueueItem *> * const itemsFromAbove = [NSMutableArray array];
        NSMutableArray<VLCPlayQueueItem *> * const itemsFromBelow = [NSMutableArray array];
        for (VLCPlayQueueItem * const item in draggedItems) {
            const NSUInteger origIdx = [_items indexOfObject:item];
            if (origIdx < (NSUInteger)clampedRow) {
                [itemsFromAbove addObject:item];
            } else {
                [itemsFromBelow addObject:item];
            }
        }

        for (VLCPlayQueueItem * const item in itemsFromAbove.reverseObjectEnumerator) {
            const size_t targetPos = (size_t)[desired indexOfObject:item];
            const NSUInteger curPos = [currentList indexOfObject:item];
            if (curPos != NSNotFound && curPos != targetPos) {
                [queue moveItemWithID:(int64_t)item.uniqueID toPosition:targetPos];
                [currentList removeObjectAtIndex:curPos];
                [currentList insertObject:item atIndex:targetPos];
            }
        }

        for (VLCPlayQueueItem * const item in itemsFromBelow) {
            const size_t targetPos = (size_t)[desired indexOfObject:item];
            const NSUInteger curPos = [currentList indexOfObject:item];
            if (curPos != NSNotFound && curPos != targetPos) {
                [queue moveItemWithID:(int64_t)item.uniqueID toPosition:targetPos];
                [currentList removeObjectAtIndex:curPos];
                [currentList insertObject:item atIndex:targetPos];
            }
        }

        return YES;
    }

    NSMutableArray<VLCMediaLibraryMediaItem *> * const allMediaItems = [NSMutableArray array];
    for (NSPasteboardItem * const pboardItem in pasteboard.pasteboardItems) {
        NSData *itemData = [pboardItem dataForType:VLCMediaLibraryMediaItemPasteboardType];
        if (!itemData) {
            itemData = [pboardItem dataForType:VLCMediaLibraryMediaItemUTI];
        }
        if (itemData) {
            NSArray<VLCMediaLibraryMediaItem *> * const items = [VLCMediaLibraryMediaItem mediaItemsFromPasteboardData:itemData];
            if (items) {
                [allMediaItems addObjectsFromArray:items];
            }
        }
    }
    if (allMediaItems.count == 0) {
        NSData *itemData = [pasteboard dataForType:VLCMediaLibraryMediaItemPasteboardType];
        if (!itemData) {
            itemData = [pasteboard dataForType:VLCMediaLibraryMediaItemUTI];
        }
        if (itemData) {
            NSArray<VLCMediaLibraryMediaItem *> * const items = [VLCMediaLibraryMediaItem mediaItemsFromPasteboardData:itemData];
            if (items) {
                [allMediaItems addObjectsFromArray:items];
            }
        }
    }
    if (allMediaItems.count > 0) {
        size_t insertionIndex = (size_t)MAX(0, MIN(row, (NSInteger)_items.count));
        for (VLCMediaLibraryMediaItem * const mediaItem in allMediaItems) {
            input_item_t * const p_input = mediaItem.inputItem.vlcInputItem;
            if (p_input != NULL) {
                [queue addInputItem:p_input atPosition:insertionIndex startPlayback:NO];
                insertionIndex++;
            }
        }
        return YES;
    }

    NSArray<NSURL *> * const urls = [pasteboard readObjectsForClasses:@[NSURL.class]
                                                              options:@{NSPasteboardURLReadingFileURLsOnlyKey: @YES}];
    NSMutableArray<VLCOpenInputMetadata *> * const inputs = [NSMutableArray array];
    for (NSURL * const url in urls) {
        VLCOpenInputMetadata * const metadata = [[VLCOpenInputMetadata alloc] initWithPath:url.path];
        if (metadata != nil) {
            [inputs addObject:metadata];
        }
    }
    if (inputs.count > 0) {
        const size_t insertionIndex = (size_t)MAX(0, MIN(row, (NSInteger)_items.count));
        [queue addPlayQueueItems:inputs atPosition:insertionIndex startPlayback:NO];
        return YES;
    }
    return NO;
}

// MARK: - NSTableViewDelegate

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
    if (row < 0 || row >= (NSInteger)_items.count) {
        return nil;
    }
    MacLCUpNextCellView *cell = [tableView makeViewWithIdentifier:MacLCUpNextCellIdentifier owner:self];
    if (cell == nil) {
        cell = [[MacLCUpNextCellView alloc] initWithFrame:NSMakeRect(0, 0, 300, 52)];
    }
    VLCPlayQueueItem * const item = _items[(NSUInteger)row];
    const size_t currentIndex = self.playQueue.currentPlayQueueIndex;
    const BOOL playing = (size_t)row == currentIndex;
    const BOOL played = currentIndex != (size_t)-1 && (size_t)row < currentIndex;

    cell.representedID = item.uniqueID;
    /* The tagged title first: the item's name is often its file name. */
    NSString *title = item.inputItem.title;
    if (title.length == 0) {
        title = item.title ?: @"";
    }
    cell.titleField.stringValue = title;
    cell.titleField.font = playing
        ? [NSFont systemFontOfSize:MacLCDesign.body.pointSize weight:NSFontWeightSemibold] : MacLCDesign.body;
    cell.titleField.textColor = played ? NSColor.secondaryLabelColor : NSColor.labelColor;
    cell.subtitleField.stringValue = item.artistName.length > 0 ? item.artistName : (item.albumName ?: @"");
    cell.subtitleField.hidden = cell.subtitleField.stringValue.length == 0;
    /* A clock reading, like a track list: "Less than a minute" crowded out
     * the title. */
    cell.durationField.stringValue =
        item.duration > 0 ? [MacLCTrackListController stringForDuration:MS_FROM_VLC_TICK(item.duration)] : @"";
    cell.playingView.hidden = !playing;

    cell.artworkView.image = nil;
    const uint64_t representedID = item.uniqueID;
    [VLCLibraryImageCache thumbnailForPlayQueueItem:item withCompletion:^(const NSImage * const image) {
        if (cell.representedID == representedID) {
            cell.artworkView.image = (NSImage *)image;
        }
    }];
    cell.accessibilityLabel = [NSString stringWithFormat:@"%@%@", playing ? [_NS("Now Playing") stringByAppendingString:@", "] : @"",
                               title];
    return cell;
}

@end
