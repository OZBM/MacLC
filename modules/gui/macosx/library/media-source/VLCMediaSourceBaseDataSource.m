/*****************************************************************************
 * VLCMediaSourceBaseDataSource.m: MacOS X interface module
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

#import "VLCMediaSourceBaseDataSource.h"

#import "VLCLibraryMediaSourceViewNavigationStack.h"
#import "VLCMediaSource.h"
#import "VLCLocalMediaSource.h"
#import "VLCMediaSourceDataSource.h"
#import "VLCMediaSourceDeviceCollectionViewItem.h"

#import "MacLCBrowseHeaderView.h"
#import "MacLCBrowseLocationCardItem.h"
#import "MacLCBrowseSectionHeaderView.h"
#import "MacLCBrowseTableCellView.h"

#import "theme/MacLCDesign.h"
#import "VLCMediaSourceProvider.h"

#import "extensions/NSImage+VLCAdditions.h"
#import "extensions/NSPasteboardItem+VLCAdditions.h"
#import "extensions/NSString+Helpers.h"
#import "extensions/NSTableCellView+VLCAdditions.h"
#import "extensions/NSWindow+VLCAdditions.h"

#import "library/VLCInputItem.h"
#import "library/VLCInputNode.h"
#import "library/VLCInputNodePathControl.h"
#import "library/VLCInputNodePathControlItem.h"
#import "library/VLCLibraryCollectionViewSupplementaryElementView.h"
#import "library/VLCLibraryImageCache.h"
#import "library/VLCLibrarySegment.h"
#import "library/VLCLibraryTableCellView.h"
#import "library/VLCLibraryWindow.h"
#import "library/VLCLibraryWindowPersistentPreferences.h"

#import "library/media-source/VLCMediaSourceCollectionViewItem.h"

#import "main/VLCMain.h"

#import "views/VLCFileDragRecognisingView.h"
#import "views/VLCImageView.h"
#import "views/VLCUIUnits.h"

#include <sys/mount.h>

NSString * const VLCMediaSourceBaseDataSourceNodeChanged = @"VLCMediaSourceBaseDataSourceNodeChanged";
NSString * const VLCMediaSourceTableTagsColumnIdentifier = @"VLCMediaSourceTableTagsColumn";

@interface VLCLANDeviceRecord : NSObject
@property (readonly) VLCMediaSource *mediaSource;
@property (readonly) VLCInputNode *inputNode;

- (instancetype)initWithMediaSource:(VLCMediaSource *)mediaSource
                          inputNode:(VLCInputNode *)inputNode;
@end

@implementation VLCLANDeviceRecord

- (instancetype)initWithMediaSource:(VLCMediaSource *)mediaSource
                          inputNode:(VLCInputNode *)inputNode
{
    self = [super init];
    if (self) {
        _mediaSource = mediaSource;
        _inputNode = inputNode;
    }
    return self;
}

@end

@interface MacLCBrowseHomeItem : NSObject
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *subtitle;
@property (nonatomic, copy) NSString *symbolName;
@property (nonatomic, strong, nullable) VLCInputNode *inputNode;
@property (nonatomic, strong, nullable) VLCMediaSource *mediaSource;
@property (nonatomic, copy, nullable) NSString *mrl;
@end

@implementation MacLCBrowseHomeItem
@end

@interface MacLCBrowseHomeSection : NSObject
@property (nonatomic, copy) NSString *title;
@property (nonatomic, strong) NSMutableArray<MacLCBrowseHomeItem *> *items;
@end

@implementation MacLCBrowseHomeSection
- (instancetype)init
{
    self = [super init];
    if (self) {
        _items = [NSMutableArray array];
    }
    return self;
}
@end

static NSString *MacLCBrowseStandardizedPath(NSURL *url)
{
    NSString * const path = url.URLByStandardizingPath.path;
    if (path.length > 1 && [path hasSuffix:@"/"]) {
        return [path substringToIndex:path.length - 1];
    }
    return path;
}

static BOOL MacLCBrowseMRLIsHomeFolder(NSString *mrl)
{
    if (mrl == nil) {
        return NO;
    }
    NSURL * const url = [NSURL URLWithString:mrl];
    if (url == nil || !url.isFileURL) {
        return NO;
    }
    NSString * const home = MacLCBrowseStandardizedPath([NSURL fileURLWithPath:NSHomeDirectory()]);
    return [MacLCBrowseStandardizedPath(url) isEqualToString:home];
}

/* Whether the path lives on a local file system, from the kernel's cached
 * mount table: MNT_NOWAIT never touches a (possibly unreachable) server. */
BOOL MacLCBrowsePathIsOnLocalVolume(NSString *path)
{
    struct statfs *mounts = NULL;
    const int count = getmntinfo(&mounts, MNT_NOWAIT);
    const char * const cPath = path.fileSystemRepresentation;
    if (count <= 0 || cPath == NULL) {
        return NO;
    }

    size_t bestLength = 0;
    BOOL isLocal = NO;
    for (int i = 0; i < count; i++) {
        const char * const mountPoint = mounts[i].f_mntonname;
        const size_t length = strlen(mountPoint);
        if (length < bestLength || strncmp(cPath, mountPoint, length) != 0) {
            continue;
        }
        /* Match whole path components only ("/Volumes/A" is not "/Volumes/AB"). */
        if (length > 1 && cPath[length] != '\0' && cPath[length] != '/') {
            continue;
        }
        bestLength = length;
        isLocal = (mounts[i].f_flags & MNT_LOCAL) != 0;
    }
    return isLocal;
}

static void MacLCBrowseConfigureVolumeItem(MacLCBrowseHomeItem *item, VLCInputItem *inputItem)
{
    item.symbolName = @"externaldrive.fill";
    item.subtitle = _NS("External drive");

    NSURL * const url = inputItem.MRL ? [NSURL URLWithString:inputItem.MRL] : nil;
    if (url == nil || !url.isFileURL) {
        return;
    }
    if (!MacLCBrowsePathIsOnLocalVolume(url.path)) {
        item.symbolName = @"server.rack";
        item.subtitle = _NS("Network volume");
        return;
    }

    NSDictionary<NSURLResourceKey, id> * const values =
        [url resourceValuesForKeys:@[NSURLVolumeIsInternalKey,
                                     NSURLVolumeIsEjectableKey,
                                     NSURLVolumeIsRemovableKey]
                             error:nil];
    const BOOL isInternal = [values[NSURLVolumeIsInternalKey] boolValue];
    const BOOL isEjectable = [values[NSURLVolumeIsEjectableKey] boolValue];
    const BOOL isRemovable = [values[NSURLVolumeIsRemovableKey] boolValue];
    if (isInternal && !isEjectable && !isRemovable) {
        item.symbolName = @"internaldrive.fill";
        item.subtitle = _NS("Internal drive");
    }
}

@interface VLCMediaSourceBaseDataSource () <NSCollectionViewDataSource, NSCollectionViewDelegate, NSTableViewDelegate, NSTableViewDataSource>
{
    NSArray<VLCMediaSource *> *_mediaSources;
    NSArray<NSString *> *_mediaSourceNotificationNames;
    NSMapTable<VLCMediaSource *, NSArray<VLCLANDeviceRecord *> *> *_sourceRecords;
    NSArray<VLCLANDeviceRecord *> *_lanDeviceSnapshot;
    NSArray<MacLCBrowseHomeSection *> *_homeSections;
    NSArray<MacLCBrowseHomeItem *> *_homeItems;
}
@end

@implementation VLCMediaSourceBaseDataSource

- (instancetype)init
{
    self = [super init];
    if (self) {
        _mediaSources = @[];
        _lanDeviceSnapshot = @[];
        _mediaSourceNotificationNames = @[
            VLCMediaSourceChildrenReset,
            VLCMediaSourceChildrenAdded,
            VLCMediaSourceChildrenRemoved,
            VLCMediaSourcePreparsingEnded
        ];
        _sourceRecords = [NSMapTable mapTableWithKeyOptions:NSPointerFunctionsWeakMemory |
                                                           NSPointerFunctionsObjectPointerPersonality
                                              valueOptions:NSPointerFunctionsStrongMemory |
                                                          NSPointerFunctionsObjectPersonality];
        _mediaSourceMode = VLCMediaSourceModeLAN;
        [self loadMediaSources];
        [self returnHome];
    }
    return self;
}

- (void)dealloc
{
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

#pragma mark - view and model state management

- (VLCLibraryViewModeSegment)viewMode
{
    VLCLibraryWindowPersistentPreferences * const libraryWindowPrefs =
        VLCLibraryWindowPersistentPreferences.sharedInstance;

    switch (_mediaSourceMode) {
        case VLCMediaSourceModeLAN:
            return libraryWindowPrefs.browseLibraryViewMode;
        case VLCMediaSourceModeInternet:
            return libraryWindowPrefs.streamLibraryViewMode;
        default:
            return VLCLibraryGridViewModeSegment;
    }
}

- (void)setupViews
{
    self.collectionView.dataSource = self;
    self.collectionView.delegate = self;
    [self.collectionView registerClass:[MacLCBrowseLocationCardItem class]
                 forItemWithIdentifier:MacLCBrowseLocationCardItemIdentifier];
    [self.collectionView registerClass:[VLCMediaSourceDeviceCollectionViewItem class]
                 forItemWithIdentifier:VLCMediaSourceDeviceCellIdentifier];
    [self.collectionView registerClass:VLCMediaSourceCollectionViewItem.class
                 forItemWithIdentifier:VLCMediaSourceCollectionViewItemIdentifier];
    [self.collectionView registerClass:[MacLCBrowseSectionHeaderView class]
            forSupplementaryViewOfKind:NSCollectionElementKindSectionHeader
                        withIdentifier:MacLCBrowseSectionHeaderViewIdentifier];
    [self.collectionView registerClass:[VLCLibraryCollectionViewSupplementaryElementView class]
            forSupplementaryViewOfKind:NSCollectionElementKindSectionHeader
                        withIdentifier:VLCLibrarySupplementaryElementViewIdentifier];

    self.homeButton.action = @selector(homeButtonAction:);
    self.homeButton.target = self;
    [self.pathControl clearInputNodePathControlItems];
    self.pathControl.action = @selector(pathControlAction:);
    self.pathControl.target = self;

    [self togglePathControlVisibility:NO];

    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.rowHeight = MacLCDesign.rowMinimumHeight;
    self.tableView.usesAlternatingRowBackgroundColors = NO;
    /* A click only selects; opening is the double click (and Return, handled
     * by the view controller). */
    [self.tableView setAction:nil];
    [self.tableView setDoubleAction:@selector(tableViewAction:)];
    [self.tableView setTarget:self];
    [self.tableView registerForDraggedTypes:@[NSFilenamesPboardType]];
    [self.tableView setDraggingSourceOperationMask:NSDragOperationCopy forLocal:NO];
    [self.tableView setDraggingSourceOperationMask:NSDragOperationCopy forLocal:YES];

    NSNib * const tableCellViewNib = [[NSNib alloc] initWithNibNamed:NSStringFromClass(VLCLibraryTableCellView.class) bundle:nil];
    [self.tableView registerNib:tableCellViewNib forIdentifier:VLCLibraryTableCellViewIdentifier];

    [self updateTableColumnVisibility];
    [self reloadViews];
}

- (void)updateTableColumnVisibility
{
    NSTableColumn * const tagsColumn =
        [self.tableView tableColumnWithIdentifier:VLCMediaSourceTableTagsColumnIdentifier];
    tagsColumn.hidden = self.mediaSourceMode == VLCMediaSourceModeInternet;

    /* The column shows file sizes and folder item counts. */
    NSTableColumn * const sizeColumn =
        [self.tableView tableColumnWithIdentifier:@"VLCMediaSourceTableCountColumn"];
    sizeColumn.title = _NS("Size");
}

- (void)reloadViews
{
    const VLCLibraryViewModeSegment viewModeSegment = self.viewMode;
    if (viewModeSegment == VLCLibraryGridViewModeSegment) {
        self.collectionViewScrollView.hidden = NO;
        self.tableViewScrollView.hidden = YES;
        [self.collectionView reloadData];
    } else if (viewModeSegment == VLCLibraryListViewModeSegment) {
        self.collectionViewScrollView.hidden = YES;
        self.tableViewScrollView.hidden = NO;
        [self.tableView reloadData];
    } else {
        NSAssert(false, @"View mode must be grid or list mode");
    }
    [self togglePathControlVisibility:self.childDataSource != nil];
}

- (void)loadMediaSources
{
    [self.pathControl clearInputNodePathControlItems];

    NSArray *mediaSources;
    if (self.mediaSourceMode == VLCMediaSourceModeLAN) {
        mediaSources = VLCMediaSourceProvider.listOfLocalMediaSources;
    } else {
        mediaSources = [VLCMediaSourceProvider listOfMediaSourcesForCategory:SD_CAT_INTERNET];
    }
    NSAssert(mediaSources != nil, @"Media sources array should not be nil");

    for (VLCMediaSource * const mediaSource in mediaSources) {
        VLCInputNode * const rootNode = [mediaSource rootNode];
        if (rootNode == nil)
            continue;
        NSError * const error = [mediaSource preparseInputNodeWithinTree:rootNode];
        if (error == nil)
            [self.navigationStack installHandlersOnMediaSource:mediaSource];
    }

    [self setMediaSources:mediaSources];
    _lanDeviceSnapshot = self.mediaSourceMode == VLCMediaSourceModeLAN ? [self buildMediaSourceSnapshot] : @[];
    [self rebuildHomeSections];
    [self updateHeaderPathBreadcrumbs];
    [self reloadData];
}

- (void)setMediaSources:(NSArray<VLCMediaSource *> *)mediaSources
{
    NSNotificationCenter * const nc = NSNotificationCenter.defaultCenter;

    for (VLCMediaSource * const source in _mediaSources) {
        for (NSString * const name in _mediaSourceNotificationNames) {
            [nc removeObserver:self name:name object:source];
        }
    }

    _mediaSources = mediaSources;

    for (VLCMediaSource * const source in _mediaSources) {
        [nc addObserver:self
               selector:@selector(mediaSourceChildrenReset:)
                   name:VLCMediaSourceChildrenReset
                 object:source];
        [nc addObserver:self
               selector:@selector(mediaSourceChildrenAdded:)
                   name:VLCMediaSourceChildrenAdded
                 object:source];
        [nc addObserver:self
               selector:@selector(mediaSourceChildrenRemoved:)
                   name:VLCMediaSourceChildrenRemoved
                 object:source];
        [nc addObserver:self
               selector:@selector(mediaSourcePreparingEnded:)
                   name:VLCMediaSourcePreparsingEnded
                 object:source];
    }
}

- (void)setMediaSourceMode:(VLCMediaSourceMode)mediaSourceMode
{
    if (mediaSourceMode == self.mediaSourceMode) {
        return;
    }
    _mediaSourceMode = mediaSourceMode;
    [self updateTableColumnVisibility];
    [self loadMediaSources];
    [self returnHome];
}

- (void)rebuildHomeSections
{
    NSMutableArray<MacLCBrowseHomeSection *> * const sections = [NSMutableArray array];
    NSMutableArray<MacLCBrowseHomeItem *> * const flatItems = [NSMutableArray array];

    if (self.mediaSourceMode == VLCMediaSourceModeLAN) {
        // Section 1: "Locations"
        MacLCBrowseHomeSection * const locationsSection = [[MacLCBrowseHomeSection alloc] init];
        locationsSection.title = _NS("Locations");

        VLCMediaSource *myFoldersSource = nil;
        VLCMediaSource *devicesSource = nil;

        for (VLCMediaSource * const source in _mediaSources) {
            NSString * const desc = source.mediaSourceDescription;
            if ([desc isEqualToString:@"My Folders"] || source.category == SD_CAT_MYCOMPUTER) {
                if (myFoldersSource == nil) {
                    myFoldersSource = source;
                }
            }
            if ([desc isEqualToString:@"My Machine"]) {
                devicesSource = source;
            }
        }
        if (myFoldersSource == nil && _mediaSources.count > 0) {
            myFoldersSource = _mediaSources.firstObject;
        }

        NSMutableSet<NSString *> * const addedMrls = [NSMutableSet set];

        /* The home folder comes with the machine's devices: show it first
         * among the locations instead. */
        if (devicesSource != nil) {
            for (VLCInputNode * const child in devicesSource.rootNode.children) {
                VLCInputItem * const inputItem = child.inputItem;
                if (inputItem == nil || !MacLCBrowseMRLIsHomeFolder(inputItem.MRL)) {
                    continue;
                }
                MacLCBrowseHomeItem * const item = [[MacLCBrowseHomeItem alloc] init];
                item.title = inputItem.name;
                item.subtitle = _NS("Home folder");
                item.symbolName = @"house.fill";
                item.inputNode = child;
                item.mediaSource = devicesSource;
                item.mrl = inputItem.MRL;
                [locationsSection.items addObject:item];
                [addedMrls addObject:inputItem.MRL];
                break;
            }
        }

        if (myFoldersSource != nil) {
            for (VLCInputNode * const child in myFoldersSource.rootNode.children) {
                VLCInputItem * const inputItem = child.inputItem;
                if (inputItem == nil) continue;
                if (inputItem.MRL != nil && [addedMrls containsObject:inputItem.MRL]) continue;

                MacLCBrowseHomeItem * const item = [[MacLCBrowseHomeItem alloc] init];
                item.title = inputItem.name;
                item.subtitle = _NS("Folder");
                item.inputNode = child;
                item.mediaSource = myFoldersSource;
                item.mrl = inputItem.MRL;

                NSString * const nameLower = inputItem.name.lowercaseString;
                if (MacLCBrowseMRLIsHomeFolder(inputItem.MRL)) {
                    item.symbolName = @"house.fill";
                    item.subtitle = _NS("Home folder");
                } else if ([nameLower containsString:@"desktop"]) {
                    item.symbolName = @"menubar.dock.rectangle";
                } else if ([nameLower containsString:@"document"]) {
                    item.symbolName = @"doc.fill";
                } else if ([nameLower containsString:@"download"]) {
                    item.symbolName = @"arrow.down.circle.fill";
                } else if ([nameLower containsString:@"movie"] || [nameLower containsString:@"video"]) {
                    item.symbolName = @"film.fill";
                } else if ([nameLower containsString:@"music"]) {
                    item.symbolName = @"music.note";
                } else if ([nameLower containsString:@"picture"] || [nameLower containsString:@"photo"]) {
                    item.symbolName = @"photo.fill";
                } else {
                    item.symbolName = @"folder.fill";
                }

                [locationsSection.items addObject:item];
                if (inputItem.MRL) {
                    [addedMrls addObject:inputItem.MRL];
                }
            }
        }

        // Bookmarked folders
        NSArray<NSString *> * const bookmarks =
            [NSUserDefaults.standardUserDefaults stringArrayForKey:VLCLibraryBookmarkedLocationsKey];
        for (NSString * const locationMrl in bookmarks) {
            if ([addedMrls containsObject:locationMrl]) continue;
            NSURL * const url = [NSURL URLWithString:locationMrl];
            if (url.path != nil && [NSFileManager.defaultManager fileExistsAtPath:url.path]) {
                MacLCBrowseHomeItem * const item = [[MacLCBrowseHomeItem alloc] init];
                item.title = url.lastPathComponent.length > 0 ? url.lastPathComponent : locationMrl;
                item.subtitle = _NS("Folder");
                item.symbolName = @"folder.fill";
                item.mrl = locationMrl;
                [locationsSection.items addObject:item];
                [addedMrls addObject:locationMrl];
            }
        }

        if (locationsSection.items.count > 0) {
            [sections addObject:locationsSection];
        }

        // Section 2: "Devices"
        MacLCBrowseHomeSection * const devicesSection = [[MacLCBrowseHomeSection alloc] init];
        devicesSection.title = _NS("Devices");

        if (devicesSource != nil) {
            for (VLCInputNode * const child in devicesSource.rootNode.children) {
                VLCInputItem * const inputItem = child.inputItem;
                if (inputItem == nil) continue;
                if (inputItem.MRL != nil && [addedMrls containsObject:inputItem.MRL]) continue;

                MacLCBrowseHomeItem * const item = [[MacLCBrowseHomeItem alloc] init];
                item.title = inputItem.name;
                item.inputNode = child;
                item.mediaSource = devicesSource;
                item.mrl = inputItem.MRL;
                MacLCBrowseConfigureVolumeItem(item, inputItem);

                [devicesSection.items addObject:item];
            }
        }

        if (devicesSection.items.count > 0) {
            [sections addObject:devicesSection];
        }

        // Section 3: "Network"
        MacLCBrowseHomeSection * const networkSection = [[MacLCBrowseHomeSection alloc] init];
        networkSection.title = _NS("Network");

        for (VLCMediaSource * const source in _mediaSources) {
            if (source.category != SD_CAT_LAN) continue;

            NSArray<VLCInputNode *> * const children = source.rootNode.children;
            if (children.count > 0) {
                for (VLCInputNode * const child in children) {
                    VLCInputItem * const inputItem = child.inputItem;
                    if (inputItem == nil) continue;

                    MacLCBrowseHomeItem * const item = [[MacLCBrowseHomeItem alloc] init];
                    item.title = inputItem.name;
                    item.inputNode = child;
                    item.mediaSource = source;
                    item.mrl = inputItem.MRL;

                    NSString * const descLower = [NSString stringWithFormat:@"%@ %@", inputItem.name, source.mediaSourceDescription].lowercaseString;
                    const BOOL isUPnP = [descLower containsString:@"upnp"] || [descLower containsString:@"dlna"];
                    item.symbolName = isUPnP ? @"tv.and.mediabox" : @"server.rack";
                    item.subtitle = isUPnP ? _NS("Media server") : _NS("Network share");

                    [networkSection.items addObject:item];
                }
            } else {
                /* A discovery service that has found nothing yet (Bonjour,
                 * SAP, ...): it is a service, not a share. */
                MacLCBrowseHomeItem * const item = [[MacLCBrowseHomeItem alloc] init];
                item.title = source.mediaSourceDescription;
                item.inputNode = source.rootNode;
                item.mediaSource = source;
                item.symbolName = @"network";
                item.subtitle = _NS("Network service");

                [networkSection.items addObject:item];
            }
        }

        if (networkSection.items.count > 0) {
            [sections addObject:networkSection];
        }

    } else {
        // Internet / Streams
        MacLCBrowseHomeSection * const streamsSection = [[MacLCBrowseHomeSection alloc] init];
        streamsSection.title = _NS("Streams");

        for (VLCMediaSource * const source in _mediaSources) {
            MacLCBrowseHomeItem * const item = [[MacLCBrowseHomeItem alloc] init];
            item.title = source.mediaSourceDescription;
            item.subtitle = _NS("Stream");
            item.symbolName = @"antenna.radiowaves.left.and.right";
            item.inputNode = source.rootNode;
            item.mediaSource = source;

            [streamsSection.items addObject:item];
        }

        if (streamsSection.items.count > 0) {
            [sections addObject:streamsSection];
        }
    }

    /* The list view shows the same items, in the same order. */
    for (MacLCBrowseHomeSection * const section in sections) {
        [flatItems addObjectsFromArray:section.items];
    }

    _homeSections = [sections copy];
    _homeItems = [flatItems copy];
}

- (BOOL)hasDisplayedItems
{
    if (_childDataSource != nil) {
        return _childDataSource.nodeToDisplay.numberOfChildren > 0;
    }

    return _homeSections.count > 0;
}

#pragma mark - collection view data source

- (NSInteger)numberOfSectionsInCollectionView:(NSCollectionView *)collectionView
{
    return _homeSections.count;
}

- (NSInteger)collectionView:(NSCollectionView *)collectionView
     numberOfItemsInSection:(NSInteger)section
{
    if (section < (NSInteger)_homeSections.count) {
        return _homeSections[section].items.count;
    }
    return 0;
}

- (NSCollectionViewItem *)collectionView:(NSCollectionView *)collectionView
     itemForRepresentedObjectAtIndexPath:(NSIndexPath *)indexPath
{
    MacLCBrowseLocationCardItem * const cardItem =
        [collectionView makeItemWithIdentifier:MacLCBrowseLocationCardItemIdentifier forIndexPath:indexPath];

    if (indexPath.section < (NSInteger)_homeSections.count &&
        indexPath.item < (NSInteger)_homeSections[indexPath.section].items.count) {
        MacLCBrowseHomeItem * const homeItem = _homeSections[indexPath.section].items[indexPath.item];
        cardItem.title = homeItem.title;
        cardItem.subtitle = homeItem.subtitle;
        cardItem.symbolName = homeItem.symbolName;
    }
    return cardItem;
}

- (void)openHomeItemAtIndexPath:(NSIndexPath *)indexPath
{
    if (!indexPath || indexPath.section >= (NSInteger)_homeSections.count ||
        indexPath.item >= (NSInteger)_homeSections[indexPath.section].items.count) {
        return;
    }

    MacLCBrowseHomeItem * const item = _homeSections[indexPath.section].items[indexPath.item];
    if (item.inputNode != nil && item.mediaSource != nil) {
        [self configureChildDataSourceWithNode:item.inputNode andMediaSource:item.mediaSource];
    } else if (item.mrl != nil) {
        [self browseFolderByMrl:item.mrl];
    }
    [self reloadData];
}

- (void)collectionView:(NSCollectionView *)collectionView didSelectItemsAtIndexPaths:(NSSet<NSIndexPath *> *)indexPaths
{
    [self openHomeItemAtIndexPath:indexPaths.anyObject];
}

- (NSView *)collectionView:(NSCollectionView *)collectionView
viewForSupplementaryElementOfKind:(NSCollectionViewSupplementaryElementKind)kind
               atIndexPath:(NSIndexPath *)indexPath
{
    MacLCBrowseSectionHeaderView * const headerView =
        [collectionView makeSupplementaryViewOfKind:kind
                                     withIdentifier:MacLCBrowseSectionHeaderViewIdentifier
                                       forIndexPath:indexPath];

    if (indexPath.section < (NSInteger)_homeSections.count) {
        headerView.title = _homeSections[indexPath.section].title;
    }

    return headerView;
}

- (CGSize)collectionView:(NSCollectionView *)collectionView
                  layout:(NSCollectionViewLayout *)collectionViewLayout
referenceSizeForHeaderInSection:(NSInteger)section
{
    if (section < (NSInteger)_homeSections.count && _homeSections[section].items.count > 0) {
        return CGSizeMake(collectionView.bounds.size.width, 54.0);
    }
    return CGSizeZero;
}

- (NSSize)collectionView:(NSCollectionView *)collectionView
                  layout:(NSCollectionViewLayout *)collectionViewLayout
  sizeForItemAtIndexPath:(NSIndexPath *)indexPath
{
    const CGFloat availableWidth = MAX(220.0, collectionView.bounds.size.width - 40.0);
    const NSInteger columns = MAX(1, (NSInteger)floor((availableWidth + 12.0) / (220.0 + 12.0)));
    const CGFloat itemWidth = floor((availableWidth - (columns - 1) * 12.0) / columns);
    return NSMakeSize(itemWidth, 64.0);
}

- (NSEdgeInsets)collectionView:(NSCollectionView *)collectionView
                        layout:(NSCollectionViewLayout *)collectionViewLayout
        insetForSectionAtIndex:(NSInteger)section
{
    return NSEdgeInsetsMake(0.0, 20.0, 16.0, 20.0);
}

- (CGFloat)collectionView:(NSCollectionView *)collectionView
                   layout:(NSCollectionViewLayout *)collectionViewLayout
minimumLineSpacingForSectionAtIndex:(NSInteger)section
{
    return 12.0;
}

- (CGFloat)collectionView:(NSCollectionView *)collectionView
                   layout:(NSCollectionViewLayout *)collectionViewLayout
minimumInteritemSpacingForSectionAtIndex:(NSInteger)section
{
    return 12.0;
}

#pragma mark - table view data source and delegation

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
    return _homeItems.count;
}

- (NSView *)tableView:(NSTableView *)tableView
   viewForTableColumn:(NSTableColumn *)tableColumn
                  row:(NSInteger)row
{
    if (row >= (NSInteger)_homeItems.count) {
        return nil;
    }

    MacLCBrowseHomeItem * const item = _homeItems[row];

    if ([tableColumn.identifier isEqualToString:@"VLCMediaSourceTableNameColumn"]) {
        MacLCBrowseTableCellView * const cellView =
            [tableView makeViewWithIdentifier:MacLCBrowseTableCellViewIdentifier owner:self];
        MacLCBrowseTableCellView *view = cellView;
        if (view == nil) {
            view = [[MacLCBrowseTableCellView alloc] initWithFrame:NSMakeRect(0, 0, tableColumn.width, 32.0)];
        }
        NSImage * const symbolImage = [MacLCDesign symbolNamed:item.symbolName
                                                     pointSize:16.0
                                                        weight:NSFontWeightMedium
                                            accessibilityLabel:item.title];
        [view setIconImage:symbolImage title:item.title];
        return view;
    } else if ([tableColumn.identifier isEqualToString:@"VLCMediaSourceTableKindColumn"]) {
        MacLCBrowseTableTextCellView * const cellView =
            [tableView makeViewWithIdentifier:MacLCBrowseTableTextCellViewIdentifier owner:self];
        MacLCBrowseTableTextCellView *view = cellView;
        if (view == nil) {
            view = [[MacLCBrowseTableTextCellView alloc] initWithFrame:NSMakeRect(0, 0, tableColumn.width, 32.0)];
        }
        [view setStringValue:item.subtitle alignment:NSTextAlignmentLeft];
        return view;
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
    // Single click selects only; navigation is invoked via doubleAction (tableViewAction:)
}

- (void)tableViewAction:(id)sender
{
    NSEvent * const currentEvent = NSApp.currentEvent;
    if (currentEvent.type == NSEventTypeLeftMouseDown || currentEvent.type == NSEventTypeLeftMouseUp) {
        if (currentEvent.clickCount < 2) {
            return;
        }
    }

    const NSInteger selectedRow = self.tableView.selectedRow;
    if (selectedRow < 0 || selectedRow >= (NSInteger)_homeItems.count) {
        return;
    }

    MacLCBrowseHomeItem * const item = _homeItems[selectedRow];
    if (item.inputNode != nil && item.mediaSource != nil) {
        [self configureChildDataSourceWithNode:item.inputNode andMediaSource:item.mediaSource];
    } else if (item.mrl != nil) {
        [self browseFolderByMrl:item.mrl];
    }
    [self reloadData];
}

- (id<NSPasteboardWriting>)tableView:(NSTableView *)tableView pasteboardWriterForRow:(NSInteger)row
{
    VLCInputItem * const inputItem = _mediaSourceMode == VLCMediaSourceModeLAN
        ? _lanDeviceSnapshot[row].inputNode.inputItem
        : _mediaSources[row].rootNode.inputItem;
    return [self pasteboardWriterForInputItem:inputItem];
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

- (nullable id<NSPasteboardWriting>)pasteboardWriterForInputItem:(nullable VLCInputItem *)inputItem
{
    if (inputItem == nil || inputItem.inputType == ITEM_TYPE_DIRECTORY) {
        return nil;
    }

    return [NSPasteboardItem pasteboardItemWithInputItem:inputItem];
}

#pragma mark - LAN device snapshot

- (NSArray<VLCLANDeviceRecord *> *)buildMediaSourceSnapshot
{
    [_sourceRecords removeAllObjects];
    NSMutableArray<VLCLANDeviceRecord *> * const flat = [NSMutableArray array];
    for (VLCMediaSource * const mediaSource in _mediaSources) {
        NSMutableArray<VLCLANDeviceRecord *> * const sourceRecs = [NSMutableArray array];
        for (VLCInputNode * const child in mediaSource.rootNode.children) {
            VLCLANDeviceRecord * const record = [[VLCLANDeviceRecord alloc] initWithMediaSource:mediaSource
                                                                                          inputNode:child];
            [sourceRecs addObject:record];
        }
        NSArray<VLCLANDeviceRecord *> * const frozen = [sourceRecs copy];
        [_sourceRecords setObject:frozen forKey:mediaSource];
        [flat addObjectsFromArray:frozen];
    }
    return [flat copy];
}

- (NSArray<VLCLANDeviceRecord *> *)snapshotByUpdatingSource:(VLCMediaSource *)mediaSource
{
    NSMutableArray<VLCLANDeviceRecord *> * const sourceRecs = [NSMutableArray array];
    for (VLCInputNode * const child in mediaSource.rootNode.children) {
        VLCLANDeviceRecord * const record = [[VLCLANDeviceRecord alloc] initWithMediaSource:mediaSource
                                                                                      inputNode:child];
        [sourceRecs addObject:record];
    }
    [_sourceRecords setObject:[sourceRecs copy] forKey:mediaSource];

    NSMutableArray<VLCLANDeviceRecord *> * const flat = [NSMutableArray array];
    for (VLCMediaSource * const source in _mediaSources) {
        NSArray<VLCLANDeviceRecord *> * const recs = [_sourceRecords objectForKey:source];
        if (recs) {
            [flat addObjectsFromArray:recs];
        }
    }
    return [flat copy];
}

#pragma mark - glue code

- (void)configureChildDataSourceWithNode:(VLCInputNode *)node andMediaSource:(VLCMediaSource *)mediaSource
{
    if (!node || !mediaSource) {
        NSLog(@"Received bad node or media source, could not configure child data media source");
        return;
    }

    NSError * const error = [mediaSource preparseInputNodeWithinTree:node];
    if (error) {
        NSAlert * const alert = [NSAlert alertWithError:error];
        alert.alertStyle = NSAlertStyleCritical;
        [alert runModal];
        return;
    }
    
    VLCMediaSourceDataSource * const newChildDataSource =
        [[VLCMediaSourceDataSource alloc] initWithParentBaseDataSource:self];
    
    newChildDataSource.displayedMediaSource = mediaSource;
    newChildDataSource.nodeToDisplay = node;
    newChildDataSource.collectionView = self.collectionView;
    newChildDataSource.pathControl = self.pathControl;
    newChildDataSource.tableView = self.tableView;
    newChildDataSource.navigationStack = self.navigationStack;

    [self setChildDataSource:newChildDataSource];
    [self.navigationStack appendCurrentLibraryState];

    [self togglePathControlVisibility:YES];
}

- (void)setChildDataSource:(VLCMediaSourceDataSource *)childDataSource
{
    if (!childDataSource) {
        NSLog(@"Received bad childDataSource, returning home");
        [self returnHome];
        return;
    } else if (childDataSource == _childDataSource) {
        NSLog(@"Received same childDataSource");
        return;
    }
    
    _childDataSource = childDataSource;

    VLCInputNode * const node = childDataSource.nodeToDisplay;
    VLCInputNodePathControlItem * const nodePathItem = 
        [[VLCInputNodePathControlItem alloc] initWithInputNode:node];

    [self.pathControl appendInputNodePathControlItem:nodePathItem];
    self.pathControl.hidden = YES;
    
    [_childDataSource setupViews];

    self.collectionView.dataSource = _childDataSource;
    self.collectionView.delegate = _childDataSource;

    self.tableView.dataSource = _childDataSource;
    self.tableView.delegate = _childDataSource;

    [self updateHeaderPathBreadcrumbs];
}

#pragma mark - user interaction with generic buttons

- (void)togglePathControlVisibility:(BOOL)visible
{
    // The legacy XIB path control container is kept hidden in favour of MacLCBrowseHeaderView
    _pathControlContainerView.hidden = YES;
}

- (void)returnHome
{
    self.collectionView.dataSource = self;
    self.collectionView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.target = self;
    self.tableView.action = nil;
    self.tableView.doubleAction = @selector(tableViewAction:);

    _childDataSource = nil;
    [self.pathControl clearInputNodePathControlItems];
    [self.navigationStack clear];

    [self reloadData];
    [self updateHeaderPathBreadcrumbs];
}

- (void)homeButtonAction:(id)sender
{
    [self returnHome];
}

- (void)pathControlAction:(id)sender
{
    if (self.pathControl.clickedPathItem == nil || self.childDataSource == nil) {
        return;
    }

    NSPathControlItem * const selectedItem = self.pathControl.clickedPathItem;
    VLCInputNode *targetNode = nil;
    if ([selectedItem isKindOfClass:VLCInputNodePathControlItem.class]) {
        targetNode = ((VLCInputNodePathControlItem *)selectedItem).inputNode;
    } else {
        NSString * const itemNodeMrl = selectedItem.image.accessibilityDescription;
        VLCInputNodePathControlItem * const matchingItem = [self.pathControl.inputNodePathControlItems objectForKey:itemNodeMrl];
        targetNode = matchingItem.inputNode;
    }

    if (targetNode != nil) {
        VLCInputNode * const currentNode = self.childDataSource.nodeToDisplay;
        if (currentNode != nil &&
            [targetNode.inputItem.MRL isEqualToString:currentNode.inputItem.MRL]) {
            return;
        }

        self.childDataSource.nodeToDisplay = targetNode;
        [self.pathControl clearPathControlItemsAheadOf:selectedItem];
        [self.navigationStack appendCurrentLibraryState];
        [self updateHeaderPathBreadcrumbs];
        [self reloadData];
    } else {
        NSLog(@"Could not find matching item for clicked path item: %@", selectedItem);
    }
}

- (void)navigateToBreadcrumbIndex:(NSInteger)index
{
    NSArray<NSPathControlItem *> * const pathItems = self.pathControl.pathItems;
    if (index < 0 || index >= (NSInteger)pathItems.count || self.childDataSource == nil) {
        return;
    }

    if (index == (NSInteger)pathItems.count - 1) {
        return;
    }

    NSPathControlItem * const selectedItem = pathItems[index];
    VLCInputNode *targetNode = nil;
    if ([selectedItem isKindOfClass:VLCInputNodePathControlItem.class]) {
        targetNode = ((VLCInputNodePathControlItem *)selectedItem).inputNode;
    } else {
        NSString * const itemNodeMrl = selectedItem.image.accessibilityDescription;
        VLCInputNodePathControlItem * const matchingItem = [self.pathControl.inputNodePathControlItems objectForKey:itemNodeMrl];
        targetNode = matchingItem.inputNode;
    }

    if (targetNode != nil) {
        VLCInputNode * const currentNode = self.childDataSource.nodeToDisplay;
        if (currentNode != nil &&
            [targetNode.inputItem.MRL isEqualToString:currentNode.inputItem.MRL]) {
            return;
        }

        self.childDataSource.nodeToDisplay = targetNode;
        [self.pathControl clearPathControlItemsAheadOf:selectedItem];
        [self.navigationStack appendCurrentLibraryState];
        [self updateHeaderPathBreadcrumbs];
        [self reloadData];
    }
}

- (void)updateHeaderPathBreadcrumbs
{
    if (self.browseHeaderView == nil) {
        return;
    }

    if (self.childDataSource == nil) {
        self.browseHeaderView.mode = MacLCBrowseHeaderModeHome;
        NSString * const title = (self.mediaSourceMode == VLCMediaSourceModeLAN) ? _NS("Browse") : _NS("Streams");
        NSString * const subtitle = (self.mediaSourceMode == VLCMediaSourceModeLAN)
            ? _NS("Folders, drives and network shares")
            : _NS("Internet radio, podcasts and streaming services");
        [self.browseHeaderView setHomeTitle:title subtitle:subtitle];
        [self.browseHeaderView setPathSegments:@[]];
    } else {
        self.browseHeaderView.mode = MacLCBrowseHeaderModePath;
        NSMutableArray<NSString *> * const titles = [NSMutableArray array];
        for (NSPathControlItem * const item in self.pathControl.pathItems) {
            NSString *title = item.title;
            if (title.length == 0) {
                title = item.image.accessibilityDescription ?: @"";
            }
            if (title.length > 0) {
                [titles addObject:title];
            }
        }
        [self.browseHeaderView setPathSegments:titles];
    }
}

#pragma mark - VLCMediaSource Delegation

- (void)mediaSourceChildrenReset:(NSNotification *)aNotification
{
    msg_Dbg(getIntf(), "Reset nodes: %s", [[aNotification.object description] UTF8String]);
    dispatch_async(dispatch_get_main_queue(), ^{
        [self reloadDataForNotification:aNotification];
    });
}

- (void)mediaSourceChildrenAdded:(NSNotification *)aNotification
{
    msg_Dbg(getIntf(), "Received new nodes: %s", [[aNotification.object description] UTF8String]);
    dispatch_async(dispatch_get_main_queue(), ^{
        [self reloadDataForNotification:aNotification];
    });
}

- (void)mediaSourceChildrenRemoved:(NSNotification *)aNotification
{
    msg_Dbg(getIntf(), "Removed nodes: %s", [[aNotification.object description] UTF8String]);
    dispatch_async(dispatch_get_main_queue(), ^{
        [self reloadDataForNotification:aNotification];
    });
}

- (void)mediaSourcePreparingEnded:(NSNotification *)aNotification
{
    msg_Dbg(getIntf(), "Preparsing ended: %s", [[aNotification.object description] UTF8String]);
    dispatch_async(dispatch_get_main_queue(), ^{
        [self reloadDataForNotification:aNotification];
    });
}

- (void)reloadDataForNotification:(NSNotification *)aNotification
{
    if (self.mediaSourceMode == VLCMediaSourceModeLAN) {
        VLCMediaSource * const source = aNotification.object;
        if ([aNotification.name isEqualToString:VLCMediaSourceChildrenReset]) {
            _lanDeviceSnapshot = [self buildMediaSourceSnapshot];
        } else {
            _lanDeviceSnapshot = [self snapshotByUpdatingSource:source];
        }
    }
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [self rebuildHomeSections];
        [self reloadData];
        [self updateHeaderPathBreadcrumbs];
    });
}

- (void)reloadData
{
    if (self.viewMode == VLCLibraryGridViewModeSegment) {
        [self.collectionView reloadData];
    } else {
        [self.tableView reloadData];
    }

    [NSNotificationCenter.defaultCenter postNotificationName:VLCMediaSourceBaseDataSourceNodeChanged
                                                      object:self];
}

- (void)browseFolderByMrl:(NSString *)mrl
{
    vlc_preparser_t *p_preparser = getNetworkPreparser();
    NSURL * const folderURL = [NSURL URLWithString:mrl];
    VLCMediaSource * const mediaSource = folderURL.isFileURL
        ? [[VLCLocalMediaSource alloc] initWithFolderMrl:mrl andPreparser:p_preparser]
        : [[VLCMediaSource alloc] initWithFolderMrl:mrl andPreparser:p_preparser];
    if (mediaSource == nil) {
        NSLog(@"Could not create valid media source for mrl: %@", mrl);
        return;
    }
    VLCInputNode * const entryNode = (mediaSource.category == SD_CAT_LAN && mediaSource.rootNode.children.firstObject != nil)
        ? mediaSource.rootNode.children.firstObject
        : mediaSource.rootNode;
    if (entryNode == nil) {
        NSLog(@"No entry node for mrl: %@", mrl);
        return;
    }
    [self configureChildDataSourceWithNode:entryNode andMediaSource:mediaSource];
    [self reloadData];
}

@end
