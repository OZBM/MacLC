/*****************************************************************************
 * VLCMediaSourceDataSource.m: MacOS X interface module
 *****************************************************************************
 * Copyright (C) 2019 VLC authors and VideoLAN
 *
 * Authors: Felix Paul Kühne <fkuehne # videolan -dot- org>
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

#import "VLCMediaSourceDataSource.h"

#import "VLCLibraryMediaSourceViewNavigationStack.h"
#import "VLCMediaSource.h"
#import "VLCMediaSourceBaseDataSource.h"

#import "extensions/MacLCVolumePath.h"

#import "extensions/NSPasteboardItem+VLCAdditions.h"
#import "extensions/NSString+Helpers.h"
#import "extensions/NSTableCellView+VLCAdditions.h"

#import "library/VLCInputItem.h"
#import "library/VLCInputNode.h"
#import "library/VLCInputNodePathControl.h"
#import "library/VLCInputNodePathControlItem.h"
#import "library/VLCLibraryImageCache.h"
#import "MacLCBrowseItemCollectionViewItem.h"
#import "MacLCBrowseTableCellView.h"
#import "theme/MacLCDesign.h"
#import "library/VLCLibraryMenuController.h"

#import "library/media-source/VLCMediaSourceCollectionViewItem.h"

#import "main/VLCMain.h"

#import "playqueue/VLCPlayQueueController.h"

#import "views/VLCFileDragRecognisingView.h"
#import "views/VLCImageView.h"
#import "views/VLCUIUnits.h"

#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

NSString * const VLCMediaSourceDataSourceNodeChanged = @"VLCMediaSourceDataSourceNodeChanged";
NSString * const VLCMediaSourceDataSourceLoadingStarted = @"VLCMediaSourceDataSourceLoadingStarted";
NSString * const VLCMediaSourceDataSourceLoadingEnded = @"VLCMediaSourceDataSourceLoadingEnded";

@interface VLCMediaSourceDataSource()
{
    VLCInputItem *_childRootInput;
    VLCLibraryMenuController *_menuController;
}

@property (readwrite) dispatch_source_t observedPathDispatchSource;
@property (readwrite, strong, nullable, nonatomic) id<VLCMediaSourceNodeObservation> nodeObservation;
@property (readwrite, strong) NSMutableSet<NSValue *> *preparingInputItemIdentifiers;
@property (readwrite, strong) NSMutableSet<NSValue *> *preparedInputItemIdentifiers;
@property (readwrite, strong) NSMutableSet<NSValue *> *unavailableInputItemIdentifiers;
@property (readwrite, strong) NSMutableDictionary<NSValue *, NSNumber *> *childCountsByInputItemIdentifier;
@property (readwrite) dispatch_queue_t childCountQueue;

@end

static NSValue * _Nullable inputItemIdentifier(VLCInputItem * _Nullable const inputItem)
{
    return inputItem.vlcInputItem == NULL
        ? nil
        : [NSValue valueWithPointer:inputItem.vlcInputItem];
}

static NSString *MacLCBrowseItemCountString(NSInteger count)
{
    if (count <= 0) {
        return _NS("Empty");
    } else if (count == 1) {
        return _NS("1 item");
    }
    return [NSString stringWithFormat:_NS("%ld items"), (long)count];
}

@implementation VLCMediaSourceDataSource

- (instancetype)initWithParentBaseDataSource:(VLCMediaSourceBaseDataSource *)parentBaseDataSource
{
    self = [super init];
    if (self) {
        self.parentBaseDataSource = parentBaseDataSource;
        self.preparingInputItemIdentifiers = NSMutableSet.set;
        self.preparedInputItemIdentifiers = NSMutableSet.set;
        self.unavailableInputItemIdentifiers = NSMutableSet.set;
        self.childCountsByInputItemIdentifier = NSMutableDictionary.dictionary;
        dispatch_queue_attr_t const childCountQueueAttributes =
            dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_UTILITY, 0);
        self.childCountQueue = dispatch_queue_create("org.maclc.media-source-child-count",
                                                     childCountQueueAttributes);
        NSNotificationCenter * const notificationCenter = NSNotificationCenter.defaultCenter;
        [notificationCenter addObserver:self
                               selector:@selector(mediaSourceChildrenChanged:)
                                   name:VLCMediaSourceChildrenReset
                                 object:nil];
        [notificationCenter addObserver:self
                               selector:@selector(mediaSourceChildrenChanged:)
                                   name:VLCMediaSourceChildrenAdded
                                 object:nil];
        [notificationCenter addObserver:self
                               selector:@selector(mediaSourceChildrenChanged:)
                                   name:VLCMediaSourceChildrenRemoved
                                 object:nil];
        [notificationCenter addObserver:self
                               selector:@selector(preparseStateChanged:)
                                   name:VLCMediaSourcePreparsingStarted
                                 object:nil];
        [notificationCenter addObserver:self
                               selector:@selector(preparseStateChanged:)
                                   name:VLCMediaSourcePreparsingEnded
                                 object:nil];
    }
    return self;
}

- (void)dealloc
{
    [self.nodeObservation cancel];
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)preparseStateChanged:(NSNotification *)notification
{
    if (notification.object != self.displayedMediaSource)
        return;

    VLCInputItem * const inputItem = notification.userInfo[VLCMediaSourcePreparseInputItemKey];
    NSValue * const identifier = inputItemIdentifier(inputItem);
    if (identifier == nil) {
        return;
    }

    const BOOL preparseStarted = [notification.name isEqualToString:VLCMediaSourcePreparsingStarted];
    if (preparseStarted) {
        [self.preparingInputItemIdentifiers addObject:identifier];
    } else {
        [self.preparingInputItemIdentifiers removeObject:identifier];

        NSNumber * const status = notification.userInfo[VLCMediaSourcePreparseStatusKey];
        if (status == nil || status.intValue == VLC_SUCCESS) {
            [self.preparedInputItemIdentifiers addObject:identifier];
            [self.unavailableInputItemIdentifiers removeObject:identifier];
        } else {
            [self.unavailableInputItemIdentifiers addObject:identifier];
            [self.preparedInputItemIdentifiers removeObject:identifier];
        }
    }

    NSValue * const displayedNodeIdentifier = inputItemIdentifier(self.nodeToDisplay.inputItem);
    if (![identifier isEqual:displayedNodeIdentifier]) {
        if (!preparseStarted) {
            [self reloadCountForInputItemIdentifier:identifier];
        }
        return;
    }

    if (!preparseStarted) {
        [self.nodeToDisplay clearChildrenCache];
        [self reloadData];
    }

    NSString * const loadingNotificationName = preparseStarted
        ? VLCMediaSourceDataSourceLoadingStarted
        : VLCMediaSourceDataSourceLoadingEnded;
    [NSNotificationCenter.defaultCenter postNotificationName:loadingNotificationName
                                                      object:self];
}

- (void)reloadCountForInputItemIdentifier:(NSValue *)identifier
{
    NSArray<VLCInputNode *> * const children = self.nodeToDisplay.children;
    const NSUInteger row = [children indexOfObjectPassingTest:^BOOL(VLCInputNode * const childNode,
                                                                    NSUInteger __unused idx,
                                                                    BOOL * const __unused stop) {
        return [inputItemIdentifier(childNode.inputItem) isEqual:identifier];
    }];
    if (row == NSNotFound) {
        return;
    }

    [children[row] clearChildrenCache];

    const NSInteger countColumn = [self.tableView columnWithIdentifier:@"VLCMediaSourceTableCountColumn"];
    if (self.tableView.hidden || countColumn == -1) {
        return;
    }

    [self.tableView reloadDataForRowIndexes:[NSIndexSet indexSetWithIndex:row]
                              columnIndexes:[NSIndexSet indexSetWithIndex:countColumn]];
}

- (void)clearDisplayedNodeChildrenCaches
{
    [self.nodeToDisplay clearChildrenCache];
    for (VLCInputNode * const childNode in self.nodeToDisplay.children) {
        [childNode clearChildrenCache];
    }
}

- (void)mediaSourceChildrenChanged:(NSNotification *)notification
{
    if (notification.object != self.displayedMediaSource)
        return;
    dispatch_async(dispatch_get_main_queue(), ^{
        [self clearDisplayedNodeChildrenCaches];
        [self reloadData];
    });
}

- (void)setNodeToDisplay:(nonnull VLCInputNode*)nodeToDisplay
{
    NSAssert(nodeToDisplay, @"Nil node to display, will not set");
    _nodeToDisplay = nodeToDisplay;

    NSParameterAssert(self.parentBaseDataSource);
    [self.nodeObservation cancel];

    const __weak typeof(self) weakSelf = self;
    self.nodeObservation = [self.displayedMediaSource observeInputNode:nodeToDisplay
                                                              onChange:^(VLCMediaSourceNodeChange change) {
        const typeof(self) strongSelf = weakSelf;
        if (strongSelf == nil) {
            return;
        }
        switch (change) {
            case VLCMediaSourceNodeChangeChildrenUpdated:
                [strongSelf reloadData];
                break;
            case VLCMediaSourceNodeChangeInvalidated:
                [strongSelf.parentBaseDataSource homeButtonAction:strongSelf];
                break;
        }
    }];

    [self reloadData];
    NSValue * const identifier = inputItemIdentifier(nodeToDisplay.inputItem);
    NSString * const loadingNotificationName =
        [self.preparingInputItemIdentifiers containsObject:identifier]
        ? VLCMediaSourceDataSourceLoadingStarted
        : VLCMediaSourceDataSourceLoadingEnded;
    [NSNotificationCenter.defaultCenter postNotificationName:loadingNotificationName
                                                      object:self];
}

- (BOOL)hasDisplayedItems
{
    return _nodeToDisplay.numberOfChildren > 0;
}

- (void)setupViews
{
    [self.collectionView registerClass:MacLCBrowseItemCollectionViewItem.class
                 forItemWithIdentifier:MacLCBrowseItemCollectionViewItemIdentifier];

    self.tableView.rowHeight = MacLCDesign.rowMinimumHeight;
    /* A click only selects; opening is the double click (and Return, handled
     * by the view controller). Sharing one selector between action and
     * doubleAction could open twice. */
    [self.tableView setAction:nil];
    [self.tableView setDoubleAction:@selector(tableViewAction:)];
    [self.tableView setTarget:self];
    [self.tableView registerForDraggedTypes:@[NSFilenamesPboardType]];
    [self.tableView setDraggingSourceOperationMask:NSDragOperationCopy forLocal:NO];
    [self.tableView setDraggingSourceOperationMask:NSDragOperationCopy forLocal:YES];
}

- (nullable VLCInputNode *)inputNodeForIndexPath:(NSIndexPath *)indexPath
{
    VLCInputNode * const rootNode = self.nodeToDisplay;
    NSArray * const nodeChildren = rootNode.children;
    return nodeChildren ? nodeChildren[indexPath.item] : nil;
}

- (NSArray<VLCInputItem *> *)mediaSourceInputItemsAtIndexPaths:(NSSet<NSIndexPath *> *const)indexPaths
{
    NSMutableArray<VLCInputItem *> * const inputItems =
        [NSMutableArray arrayWithCapacity:indexPaths.count];

    for (NSIndexPath * const indexPath in indexPaths) {
        VLCInputNode * const inputNode = [self inputNodeForIndexPath:indexPath];
        if (!inputNode) {
            continue;
        }
        VLCInputItem * const inputItem = inputNode.inputItem;
        [inputItems addObject:inputItem];
    }

    return inputItems.copy;
}

#pragma mark - collection view data source and delegation

- (NSInteger)numberOfSectionsInCollectionView:(NSCollectionView *)collectionView
{
    return 1;
}

- (NSInteger)collectionView:(NSCollectionView *)collectionView
     numberOfItemsInSection:(NSInteger)section
{
    if (_nodeToDisplay) {
        return _nodeToDisplay.numberOfChildren;
    }

    return 0;
}

- (NSCollectionViewItem *)collectionView:(NSCollectionView *)collectionView
     itemForRepresentedObjectAtIndexPath:(NSIndexPath *)indexPath
{
    MacLCBrowseItemCollectionViewItem * const viewItem =
        [collectionView makeItemWithIdentifier:MacLCBrowseItemCollectionViewItemIdentifier
                                       forIndexPath:indexPath];

    VLCInputNode * const rootNode = _nodeToDisplay;
    NSArray * const nodeChildren = rootNode.children;
    if (nodeChildren == nil || indexPath.item >= (NSInteger)nodeChildren.count) {
        NSLog(@"No children for node %@, cannot provide correctly setup viewItem", rootNode);
        return viewItem;
    }

    VLCInputNode * const childNode = nodeChildren[indexPath.item];
    VLCInputItem * const childRootInput = childNode.inputItem;

    viewItem.browseDelegate = self;
    viewItem.representedInputNode = childNode;
    viewItem.representedInputItem = childRootInput;

    if (childRootInput.inputType == ITEM_TYPE_DIRECTORY ||
        childRootInput.inputType == ITEM_TYPE_NODE ||
        childRootInput.inputType == ITEM_TYPE_PLAYLIST) {
        const int childCount = childNode.numberOfChildren;
        if (childCount > 0) {
            viewItem.secondaryInfoString = MacLCBrowseItemCountString(childCount);
        } else {
            viewItem.secondaryInfoString = _NS("Folder");
        }
    } else {
        NSString * const ext = childRootInput.MRL.pathExtension.uppercaseString;
        if (ext.length > 0) {
            viewItem.secondaryInfoString = ext;
        } else {
            viewItem.secondaryInfoString = _NS("Media file");
        }
    }

    [viewItem updateRepresentation];
    return viewItem;
}

- (void)collectionView:(NSCollectionView *)collectionView didSelectItemsAtIndexPaths:(NSSet<NSIndexPath *> *)indexPaths
{
    // Single-click selects only (consistent with Finder and MacLC design language).
    // Navigation and playback occur on double-click or play hover button.
}

- (NSSize)collectionView:(NSCollectionView *)collectionView
                  layout:(NSCollectionViewLayout *)collectionViewLayout
  sizeForItemAtIndexPath:(NSIndexPath *)indexPath
{
    const CGFloat availableWidth = MAX(180.0, collectionView.bounds.size.width - 40.0);
    const NSInteger columns = MAX(1, (NSInteger)floor((availableWidth + 16.0) / (180.0 + 16.0)));
    const CGFloat itemWidth = floor((availableWidth - (columns - 1) * 16.0) / columns);
    const CGFloat itemHeight = floor(itemWidth * 9.0 / 16.0) + ceil([MacLCBrowseItemView heightBelowArtwork]);
    return NSMakeSize(itemWidth, itemHeight);
}

- (NSEdgeInsets)collectionView:(NSCollectionView *)collectionView
                        layout:(NSCollectionViewLayout *)collectionViewLayout
        insetForSectionAtIndex:(NSInteger)section
{
    return NSEdgeInsetsMake(0.0, 20.0, 20.0, 20.0);
}

- (CGFloat)collectionView:(NSCollectionView *)collectionView
                   layout:(NSCollectionViewLayout *)collectionViewLayout
minimumLineSpacingForSectionAtIndex:(NSInteger)section
{
    return 16.0;
}

- (CGFloat)collectionView:(NSCollectionView *)collectionView
                   layout:(NSCollectionViewLayout *)collectionViewLayout
minimumInteritemSpacingForSectionAtIndex:(NSInteger)section
{
    return 16.0;
}

#pragma mark - MacLCBrowseItemCollectionViewItemDelegate

- (void)browseItemDidDoubleClick:(MacLCBrowseItemCollectionViewItem *)item
{
    VLCInputNode * const childNode = item.representedInputNode;
    if (childNode != nil) {
        [self performActionForNode:childNode allowPlayback:YES];
    }
}

- (void)browseItemPlayInstantly:(MacLCBrowseItemCollectionViewItem *)item
{
    VLCInputItem * const inputItem = item.representedInputItem;
    if (inputItem == nil) {
        return;
    }

    if (inputItem.inputType == ITEM_TYPE_DIRECTORY ||
        inputItem.inputType == ITEM_TYPE_NODE ||
        inputItem.inputType == ITEM_TYPE_PLAYLIST) {
        if (item.representedInputNode != nil) {
            [self performActionForNode:item.representedInputNode allowPlayback:YES];
        }
    } else {
        [VLCMain.sharedInstance.playQueueController addInputItem:inputItem.vlcInputItem
                                                      atPosition:-1
                                                   startPlayback:YES];
    }
}

- (void)browseItemOpenContextMenu:(NSEvent *)event forItem:(MacLCBrowseItemCollectionViewItem *)item
{
    if (item.representedInputItem == nil) {
        return;
    }

    if (_menuController == nil) {
        _menuController = [[VLCLibraryMenuController alloc] init];
    }

    NSCollectionView * const collectionView = self.collectionView;
    NSSet<NSIndexPath *> * const indexPaths = collectionView.selectionIndexPaths;
    NSArray<VLCInputItem *> * const selectedInputItems =
        [self mediaSourceInputItemsAtIndexPaths:indexPaths];

    const NSInteger representedItemIndex = [selectedInputItems indexOfObjectPassingTest:^BOOL(
        VLCInputItem * const inputItem, const NSUInteger __unused idx, BOOL * const __unused stop
    ) {
        return [inputItem.MRL isEqualToString:item.representedInputItem.MRL];
    }];

    NSArray<VLCInputItem *> *items = nil;
    if (representedItemIndex == NSNotFound) {
        items = @[item.representedInputItem];
    } else {
        items = selectedInputItems;
    }

    _menuController.representedInputItems = items;
    [_menuController popupMenuWithEvent:event forView:item.view];
}

- (void)openItemAtIndexPath:(NSIndexPath *)indexPath
{
    if (indexPath == nil) {
        return;
    }
    VLCInputNode * const node = [self mediaSourceInputNodeAtRow:indexPath.item];
    if (node != nil) {
        [self performActionForNode:node allowPlayback:YES];
    }
}

#pragma mark - table view data source and delegation

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
    if (_nodeToDisplay) {
        return _nodeToDisplay.numberOfChildren;
    }

    return 0;
}

- (NSView *)tableView:(NSTableView *)tableView
   viewForTableColumn:(NSTableColumn *)tableColumn
                  row:(NSInteger)row
{
    VLCInputNode * const inputNode = [self mediaSourceInputNodeAtRow:row];
    if (inputNode == nil) {
        return nil;
    }

    VLCInputItem * const inputItem = inputNode.inputItem;

    if ([tableColumn.identifier isEqualToString:@"VLCMediaSourceTableNameColumn"]) {
        MacLCBrowseTableCellView *cellView =
            [tableView makeViewWithIdentifier:MacLCBrowseTableCellViewIdentifier owner:self];
        if (cellView == nil) {
            cellView = [[MacLCBrowseTableCellView alloc] initWithFrame:NSMakeRect(0, 0, tableColumn.width, 32.0)];
        }

        NSImage *icon = nil;
        if (inputItem.inputType == ITEM_TYPE_DIRECTORY ||
            inputItem.inputType == ITEM_TYPE_NODE ||
            inputItem.inputType == ITEM_TYPE_PLAYLIST) {
            icon = [MacLCDesign symbolNamed:@"folder.fill"
                                  pointSize:15.0
                                     weight:NSFontWeightMedium
                         accessibilityLabel:_NS("Folder")];
        } else {
            NSString * const ext = inputItem.MRL.pathExtension.lowercaseString;
            static NSSet *audioExts = nil;
            if (!audioExts) {
                audioExts = [NSSet setWithObjects:@"mp3", @"flac", @"m4a", @"aac", @"wav", @"alac", @"aiff", @"ogg", @"opus", nil];
            }
            if ([audioExts containsObject:ext]) {
                icon = [MacLCDesign symbolNamed:@"music.note"
                                      pointSize:15.0
                                         weight:NSFontWeightMedium
                             accessibilityLabel:_NS("Audio file")];
            } else {
                icon = [MacLCDesign symbolNamed:@"film"
                                      pointSize:15.0
                                         weight:NSFontWeightMedium
                             accessibilityLabel:_NS("Video file")];
            }
        }
        [cellView setIconImage:icon title:inputItem.name ?: @""];
        return cellView;
    }

    if ([tableColumn.identifier isEqualToString:@"VLCMediaSourceTableCountColumn"]) {
        MacLCBrowseTableTextCellView *cellView =
            [tableView makeViewWithIdentifier:MacLCBrowseTableTextCellViewIdentifier owner:self];
        if (cellView == nil) {
            cellView = [[MacLCBrowseTableTextCellView alloc] initWithFrame:NSMakeRect(0, 0, tableColumn.width, 32.0)];
        }

        if (inputItem.inputType == ITEM_TYPE_DIRECTORY ||
            inputItem.inputType == ITEM_TYPE_NODE ||
            inputItem.inputType == ITEM_TYPE_PLAYLIST) {
            NSValue * const identifier = inputItemIdentifier(inputItem);
            const int numberOfChildren = inputNode.numberOfChildren;
            NSNumber * const cachedChildCount = self.childCountsByInputItemIdentifier[identifier];
            if ([self.unavailableInputItemIdentifiers containsObject:identifier]) {
                [cellView setStringValue:_NS("Unavailable") alignment:NSTextAlignmentRight];
            } else if (numberOfChildren > 0 || [self.preparedInputItemIdentifiers containsObject:identifier]) {
                [cellView setStringValue:MacLCBrowseItemCountString(numberOfChildren)
                               alignment:NSTextAlignmentRight];
            } else if (cachedChildCount != nil) {
                [cellView setStringValue:MacLCBrowseItemCountString(cachedChildCount.integerValue)
                               alignment:NSTextAlignmentRight];
            } else {
                [cellView setStringValue:_NS("Loading…") alignment:NSTextAlignmentRight];
                if (![self.preparingInputItemIdentifiers containsObject:identifier]) {
                    [self.preparingInputItemIdentifiers addObject:identifier];
                    VLCMediaSource * const mediaSource = self.displayedMediaSource;
                    /* Counting the children of an unreachable share takes as
                     * long as the mount needs to time out: the data source and
                     * its views must not be kept alive for that. */
                    __weak typeof(self) weakSelf = self;
                    dispatch_async(self.childCountQueue, ^{
                        NSError *error = nil;
                        NSNumber * const childCount = [mediaSource childCountForInputNode:inputNode error:&error];
                        if (childCount == nil && error == nil) {
                            [mediaSource preparseInputNodeWithinTree:inputNode];
                            return;
                        }
                        dispatch_async(dispatch_get_main_queue(), ^{
                            typeof(self) strongSelf = weakSelf;
                            if (strongSelf == nil) {
                                return;
                            }
                            [strongSelf.preparingInputItemIdentifiers removeObject:identifier];
                            if (error != nil) {
                                [strongSelf.unavailableInputItemIdentifiers addObject:identifier];
                            } else if (childCount != nil) {
                                [strongSelf.unavailableInputItemIdentifiers removeObject:identifier];
                                strongSelf.childCountsByInputItemIdentifier[identifier] = childCount;
                            }
                            [strongSelf reloadCountForInputItemIdentifier:identifier];
                        });
                    });
                }
            }
        } else {
            NSURL * const fileURL = [NSURL URLWithString:inputItem.MRL];
            /* Reading a size on a network volume could stall the interface. */
            if (fileURL.isFileURL && MacLCPathIsOnLocalVolume(fileURL.path)) {
                NSError *sizeError = nil;
                NSNumber *fileSizeNumber = nil;
                [fileURL getResourceValue:&fileSizeNumber forKey:NSURLFileSizeKey error:&sizeError];
                if (fileSizeNumber != nil) {
                    NSString * const sizeStr = [NSByteCountFormatter stringFromByteCount:fileSizeNumber.longLongValue
                                                                              countStyle:NSByteCountFormatterCountStyleFile];
                    [cellView setStringValue:sizeStr alignment:NSTextAlignmentRight];
                } else {
                    [cellView setStringValue:@"--" alignment:NSTextAlignmentRight];
                }
            } else {
                [cellView setStringValue:@"--" alignment:NSTextAlignmentRight];
            }
        }
        return cellView;
    }

    if ([tableColumn.identifier isEqualToString:@"VLCMediaSourceTableKindColumn"]) {
        MacLCBrowseTableTextCellView *cellView =
            [tableView makeViewWithIdentifier:MacLCBrowseTableTextCellViewIdentifier owner:self];
        if (cellView == nil) {
            cellView = [[MacLCBrowseTableTextCellView alloc] initWithFrame:NSMakeRect(0, 0, tableColumn.width, 32.0)];
        }

        NSString *typeName = _NS("Unknown");
        switch (inputItem.inputType) {
            case ITEM_TYPE_UNKNOWN:
                typeName = _NS("Unknown");
                break;
            case ITEM_TYPE_FILE:
            {
                NSString * const filePath = inputItem.MRL;
                NSString * const extension = filePath.pathExtension.lowercaseString;
                if (extension.length > 0) {
                    UTType * const type = [UTType typeWithFilenameExtension:extension];
                    if (type.localizedDescription.length > 0) {
                        typeName = type.localizedDescription;
                    } else {
                        typeName = [NSString stringWithFormat:_NS("%@ file"), extension.uppercaseString];
                    }
                } else {
                    typeName = _NS("File");
                }
                break;
            }
            case ITEM_TYPE_DIRECTORY:
                typeName = _NS("Folder");
                break;
            case ITEM_TYPE_DISC:
                typeName = _NS("Disc");
                break;
            case ITEM_TYPE_CARD:
                typeName = _NS("Card");
                break;
            case ITEM_TYPE_STREAM:
                typeName = _NS("Stream");
                break;
            case ITEM_TYPE_PLAYLIST:
                typeName = _NS("Playlist");
                break;
            case ITEM_TYPE_NODE:
                typeName = _NS("Node");
                break;
            case ITEM_TYPE_NUMBER:
                typeName = _NS("Undefined");
                break;
        }
        [cellView setStringValue:typeName alignment:NSTextAlignmentLeft];
        return cellView;
    }

    if ([tableColumn.identifier isEqualToString:@"VLCMediaSourceTableTagsColumn"]) {
        MacLCBrowseTableTextCellView *cellView =
            [tableView makeViewWithIdentifier:MacLCBrowseTableTextCellViewIdentifier owner:self];
        if (cellView == nil) {
            cellView = [[MacLCBrowseTableTextCellView alloc] initWithFrame:NSMakeRect(0, 0, tableColumn.width, 32.0)];
        }
        /* Reading tags on a network volume could stall the interface, just
         * like reading a size. */
        NSURL * const tagsURL = [NSURL URLWithString:inputItem.MRL];
        NSArray<NSString *> *tags = nil;
        if (tagsURL.isFileURL && MacLCPathIsOnLocalVolume(tagsURL.path)) {
            tags = inputItem.finderTags;
        }
        [cellView setStringValue:(tags.count > 0 ? [tags componentsJoinedByString:@", "] : @"")
                       alignment:NSTextAlignmentLeft];
        return cellView;
    }

    return nil;
}

- (nullable NSTableRowView *)tableView:(NSTableView *)tableView rowViewForRow:(NSInteger)row
{
    static NSString * const rowIdentifier = @"MacLCBrowseTableRowViewIdentifier";
    MacLCBrowseTableRowView *rowView = [tableView makeViewWithIdentifier:rowIdentifier owner:self];
    if (rowView == nil) {
        rowView = [[MacLCBrowseTableRowView alloc] initWithFrame:NSZeroRect];
        rowView.identifier = rowIdentifier;
    }
    return rowView;
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification
{
    // Single click selects only; opening is triggered via doubleAction (tableViewAction:)
}

- (void)tableViewAction:(id)sender
{
    NSEvent * const currentEvent = NSApp.currentEvent;
    if (currentEvent.type == NSEventTypeLeftMouseDown || currentEvent.type == NSEventTypeLeftMouseUp) {
        if (currentEvent.clickCount < 2) {
            return;
        }
    }

    NSInteger selectedIndex = self.tableView.selectedRow;
    if (selectedIndex < 0) {
        return;
    }

    VLCInputNode *childNode = [self mediaSourceInputNodeAtRow:selectedIndex];
    if (childNode) {
        [self performActionForNode:childNode allowPlayback:YES];
    }
}

- (id<NSPasteboardWriting>)tableView:(NSTableView *)tableView pasteboardWriterForRow:(NSInteger)row
{
    VLCInputItem * const inputItem = [self mediaSourceInputItemAtRow:row];
    return [self.parentBaseDataSource pasteboardWriterForInputItem:inputItem];
}

- (NSDragOperation)tableView:(NSTableView *)tableView
                validateDrop:(id<NSDraggingInfo>)info
                 proposedRow:(NSInteger)row
       proposedDropOperation:(NSTableViewDropOperation)dropOperation
{
    const id propertyList = [info.draggingPasteboard propertyListForType:NSFilenamesPboardType];
    if (propertyList == nil) {
        return NSDragOperationNone;
    }

    [tableView setDropRow:-1 dropOperation:NSTableViewDropOn];
    return NSDragOperationCopy;
}

- (BOOL)tableView:(NSTableView *)tableView
       acceptDrop:(id<NSDraggingInfo>)info
              row:(NSInteger)row
    dropOperation:(NSTableViewDropOperation)dropOperation
{
    return [VLCFileDragRecognisingView
        handlePasteboardFromDragSessionAsPlayQueueItems:info.draggingPasteboard];
}

- (nullable VLCInputNode *)mediaSourceInputNodeAtRow:(NSInteger)tableViewRow
{
    if (_nodeToDisplay == nil) {
        return nil;
    }

    VLCInputNode *rootNode = _nodeToDisplay;
    NSArray *nodeChildren = rootNode.children;

    /* A reload can shrink the model between the row count the view cached and
     * the moment it asks for a row, and clicked-row lookups hand out -1 for
     * an empty area. */
    if (tableViewRow < 0 || (NSUInteger)tableViewRow >= nodeChildren.count) {
        return nil;
    }

    return nodeChildren[tableViewRow];
}

- (VLCInputItem*)mediaSourceInputItemAtRow:(NSInteger)tableViewRow
{
    VLCInputNode *childNode = [self mediaSourceInputNodeAtRow:tableViewRow];

    if (childNode == nil) {
        return nil;
    }

    return childNode.inputItem;
}

#pragma mark - generic actions

- (void)performActionForNode:(VLCInputNode *)node allowPlayback:(BOOL)allowPlayback
{
    if(node == nil || node.inputItem == nil) {
        return;
    }

    VLCInputItem *childRootInput = node.inputItem;

    if (childRootInput.inputType == ITEM_TYPE_DIRECTORY || childRootInput.inputType == ITEM_TYPE_NODE || childRootInput.inputType == ITEM_TYPE_PLAYLIST) {
        VLCInputNodePathControlItem *nodePathItem = [[VLCInputNodePathControlItem alloc] initWithInputNode:node];
        [self.pathControl appendInputNodePathControlItem:nodePathItem];

        NSError * const error = [self.displayedMediaSource preparseInputNodeWithinTree:node];
        if (error) {
            NSAlert * const alert = [NSAlert alertWithError:error];
            alert.alertStyle = NSAlertStyleCritical;
            [alert runModal];
            return;
        }
        self.nodeToDisplay = node;

        [self.navigationStack appendCurrentLibraryState];
        [self.parentBaseDataSource updateHeaderPathBreadcrumbs];
    } else if (childRootInput.inputType == ITEM_TYPE_FILE && allowPlayback) {
        [VLCMain.sharedInstance.playQueueController addInputItem:childRootInput.vlcInputItem atPosition:-1 startPlayback:YES];
    }
}

- (void)reloadData
{
    if (!_collectionView.hidden) {
        [_collectionView reloadData];
    }

    if(!_tableView.hidden) {
        [_tableView reloadData];
    }

    [NSNotificationCenter.defaultCenter postNotificationName:VLCMediaSourceDataSourceNodeChanged
                                                      object:self];
}

@end
