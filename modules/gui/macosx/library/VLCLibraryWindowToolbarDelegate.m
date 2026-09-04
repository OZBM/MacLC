/*****************************************************************************
 * VLCLibraryWindowToolbarDelegate.m: MacOS X interface module
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

#import "VLCLibraryWindowToolbarDelegate.h"

#import "extensions/NSString+Helpers.h"

#import "library/VLCLibraryWindow.h"
#import "library/VLCLibraryWindowSidebarRootViewController.h"
#import "library/VLCLibraryWindowSplitViewController.h"

#import "main/VLCMain.h"

#import "menus/VLCMainMenu.h"
#import "menus/renderers/VLCRendererMenuController.h"

#import "theme/MacLCDesign.h"

NSString * const VLCLibraryWindowTrackingSeparatorToolbarItemIdentifier = 
    @"VLCLibraryWindowTrackingSeparatorToolbarItemIdentifier";

@implementation VLCLibraryWindowToolbarDelegate

#pragma mark - XIB handling

- (void)awakeFromNib
{
    self.toolbar.allowsUserCustomization = YES;
    self.toolbar.autosavesConfiguration = YES;
    
    if (@available(macOS 11.0, *)) {
        const NSInteger navSidebarToggleToolbarItemIndex = 
            [self.toolbar.items indexOfObject:self.toggleNavSidebarToolbarItem];

        NSAssert(navSidebarToggleToolbarItemIndex != NSNotFound,
                 @"Could not find navigation sidebar toggle toolbar item!");

        const NSInteger trackingSeparatorItemIndex = navSidebarToggleToolbarItemIndex + 1;
        [self.toolbar 
            insertItemWithItemIdentifier:VLCLibraryWindowTrackingSeparatorToolbarItemIdentifier
                                 atIndex:trackingSeparatorItemIndex];
        _trackingSeparatorToolbarItem =
            [self.toolbar.items objectAtIndex:trackingSeparatorItemIndex];
    }

    NSNotificationCenter * const notificationCenter = NSNotificationCenter.defaultCenter;
    [notificationCenter addObserver:self
                           selector:@selector(renderersChanged:)
                               name:VLCRendererAddedNotification
                             object:nil];
    [notificationCenter addObserver:self
                           selector:@selector(renderersChanged:)
                               name:VLCRendererRemovedNotification
                             object:nil];

    // Navigation sidebar toggle
    self.toggleNavSidebarToolbarItem.label = _NS("Sidebar");
    self.toggleNavSidebarToolbarItem.paletteLabel = _NS("Toggle Sidebar");
    self.toggleNavSidebarToolbarItem.toolTip = _NS("Toggle Sidebar");
    if (@available(macOS 11.0, *)) {
        NSImage *sidebarIcon = [MacLCDesign symbolNamed:@"sidebar.leading"
                                     accessibilityLabel:_NS("Toggle Sidebar")];
        if (!sidebarIcon) {
            sidebarIcon = [MacLCDesign symbolNamed:@"sidebar.left"
                                accessibilityLabel:_NS("Toggle Sidebar")];
        }
        if (sidebarIcon) {
            self.toggleNavSidebarToolbarItem.image = sidebarIcon;
        }
    }

    // Back / Forward navigation items
    self.backwardsToolbarItem.label = _NS("Back");
    self.backwardsToolbarItem.paletteLabel = _NS("Back");
    self.backwardsToolbarItem.toolTip = _NS("Navigate back");
    if (@available(macOS 11.0, *)) {
        NSImage *backIcon = [MacLCDesign symbolNamed:@"chevron.backward"
                                  accessibilityLabel:_NS("Back")];
        if (backIcon) {
            self.backwardsToolbarItem.image = backIcon;
        }
    }

    self.forwardsToolbarItem.label = _NS("Forward");
    self.forwardsToolbarItem.paletteLabel = _NS("Forward");
    self.forwardsToolbarItem.toolTip = _NS("Navigate forward");
    if (@available(macOS 11.0, *)) {
        NSImage *forwardIcon = [MacLCDesign symbolNamed:@"chevron.forward"
                                     accessibilityLabel:_NS("Forward")];
        if (forwardIcon) {
            self.forwardsToolbarItem.image = forwardIcon;
        }
    }

    // View mode segmented item
    self.libraryViewModeToolbarItem.label = _NS("View");
    self.libraryViewModeToolbarItem.paletteLabel = _NS("View Mode");
    self.libraryViewModeToolbarItem.toolTip = _NS("Grid View or List View");
    if (@available(macOS 11.0, *)) {
        NSImage *gridIcon = [MacLCDesign symbolNamed:@"square.grid.2x2"
                                  accessibilityLabel:_NS("Grid View")];
        NSImage *listIcon = [MacLCDesign symbolNamed:@"list.bullet"
                                  accessibilityLabel:_NS("List View")];
        if (gridIcon) {
            [self.libraryWindow.gridVsListSegmentedControl setImage:gridIcon forSegment:0];
        }
        if (listIcon) {
            [self.libraryWindow.gridVsListSegmentedControl setImage:listIcon forSegment:1];
        }
    }

    // Sort order item
    self.sortOrderToolbarItem.label = _NS("Sort");
    self.sortOrderToolbarItem.paletteLabel = _NS("Sort Order");
    self.sortOrderToolbarItem.toolTip = _NS("Select Sorting Mode");
    if (@available(macOS 11.0, *)) {
        NSImage *sortIcon = [MacLCDesign symbolNamed:@"arrow.up.arrow.down"
                                  accessibilityLabel:_NS("Sort Order")];
        if (sortIcon) {
            self.sortOrderToolbarItem.image = sortIcon;
        }
    }

    // Search toolbar item
    self.librarySearchToolbarItem.label = _NS("Search");
    self.librarySearchToolbarItem.paletteLabel = _NS("Search Library");
    self.librarySearchToolbarItem.toolTip = _NS("Search your media library");
    if (@available(macOS 11.0, *)) {
        if ([self.librarySearchToolbarItem isKindOfClass:[NSSearchToolbarItem class]]) {
            self.librarySearchToolbarItem.searchField = self.libraryWindow.librarySearchField;
            self.librarySearchToolbarItem.preferredWidthForSearchField = 220;
            self.librarySearchToolbarItem.resignsFirstResponderWithCancel = YES;
        }
    }

    // Toggle play queue item
    self.togglePlayQueueToolbarItem.label = _NS("Play Queue");
    self.togglePlayQueueToolbarItem.paletteLabel = _NS("Toggle Play Queue");
    self.togglePlayQueueToolbarItem.toolTip = _NS("Toggle Play Queue");
    if (@available(macOS 11.0, *)) {
        NSImage *pqIcon = [MacLCDesign symbolNamed:@"list.bullet.rectangle"
                                 accessibilityLabel:_NS("Play Queue")];
        if (!pqIcon) {
            pqIcon = [MacLCDesign symbolNamed:@"list.triangle"
                           accessibilityLabel:_NS("Play Queue")];
        }
        if (pqIcon) {
            self.togglePlayQueueToolbarItem.image = pqIcon;
        }
    }

    // Renderers / AirPlay item
    self.renderersToolbarItem.label = _NS("AirPlay");
    self.renderersToolbarItem.paletteLabel = _NS("Playback Destinations");
    self.renderersToolbarItem.toolTip = _NS("Choose playback destination");
    if (@available(macOS 11.0, *)) {
        NSImage *airplayIcon = [MacLCDesign symbolNamed:@"airplayvideo"
                                     accessibilityLabel:_NS("Playback Destinations")];
        if (!airplayIcon) {
            airplayIcon = [MacLCDesign symbolNamed:@"antenna.radiowaves.left.and.right"
                                accessibilityLabel:_NS("Playback Destinations")];
        }
        if (airplayIcon) {
            self.renderersToolbarItem.image = airplayIcon;
        }
    }

    self.vlcIconToolbarItem.minSize = NSMakeSize(18, 18);
    self.vlcIconToolbarItem.maxSize = NSMakeSize(18, 18);
    self.vlcIconToolbarItem.label = _NS("MacLC");
    self.vlcIconToolbarItem.paletteLabel = _NS("MacLC");

    NSImageView * const vlcIconImageView = [[NSImageView alloc] initWithFrame:NSZeroRect];
    vlcIconImageView.image = NSApp.applicationIconImage;
    self.vlcIconToolbarItem.view = vlcIconImageView;

    // Hide renderers toolbar item at first. Start discoveries and wait for notifications about
    // renderers being added or removed to keep hidden or show depending on outcome
    [self hideToolbarItem:self.renderersToolbarItem];
    [VLCMain.sharedInstance.mainMenu.rendererMenuController startRendererDiscoveries];

    [self updatePlayqueueToggleState];
}

#pragma mark - toolbar delegate methods

- (NSArray<NSToolbarItemIdentifier> *)toolbarDefaultItemIdentifiers:(NSToolbar *)toolbar
{
    NSMutableArray<NSToolbarItemIdentifier> *defaultItems = [NSMutableArray array];
    if (self.toggleNavSidebarToolbarItem.itemIdentifier) {
        [defaultItems addObject:self.toggleNavSidebarToolbarItem.itemIdentifier];
    }
    [defaultItems addObject:VLCLibraryWindowTrackingSeparatorToolbarItemIdentifier];
    if (self.backwardsToolbarItem.itemIdentifier) {
        [defaultItems addObject:self.backwardsToolbarItem.itemIdentifier];
    }
    if (self.forwardsToolbarItem.itemIdentifier) {
        [defaultItems addObject:self.forwardsToolbarItem.itemIdentifier];
    }
    if (self.libraryViewModeToolbarItem.itemIdentifier) {
        [defaultItems addObject:self.libraryViewModeToolbarItem.itemIdentifier];
    }
    if (self.sortOrderToolbarItem.itemIdentifier) {
        [defaultItems addObject:self.sortOrderToolbarItem.itemIdentifier];
    }
    [defaultItems addObject:NSToolbarFlexibleSpaceItemIdentifier];
    if (self.librarySearchToolbarItem.itemIdentifier) {
        [defaultItems addObject:self.librarySearchToolbarItem.itemIdentifier];
    }
    if (self.togglePlayQueueToolbarItem.itemIdentifier) {
        [defaultItems addObject:self.togglePlayQueueToolbarItem.itemIdentifier];
    }
    return [defaultItems copy];
}

- (NSArray<NSToolbarItemIdentifier> *)toolbarAllowedItemIdentifiers:(NSToolbar *)toolbar
{
    NSMutableArray<NSToolbarItemIdentifier> *allowedItems = [NSMutableArray array];
    if (self.toggleNavSidebarToolbarItem.itemIdentifier) {
        [allowedItems addObject:self.toggleNavSidebarToolbarItem.itemIdentifier];
    }
    [allowedItems addObject:VLCLibraryWindowTrackingSeparatorToolbarItemIdentifier];
    if (self.backwardsToolbarItem.itemIdentifier) {
        [allowedItems addObject:self.backwardsToolbarItem.itemIdentifier];
    }
    if (self.forwardsToolbarItem.itemIdentifier) {
        [allowedItems addObject:self.forwardsToolbarItem.itemIdentifier];
    }
    if (self.libraryViewModeToolbarItem.itemIdentifier) {
        [allowedItems addObject:self.libraryViewModeToolbarItem.itemIdentifier];
    }
    if (self.sortOrderToolbarItem.itemIdentifier) {
        [allowedItems addObject:self.sortOrderToolbarItem.itemIdentifier];
    }
    [allowedItems addObject:NSToolbarFlexibleSpaceItemIdentifier];
    [allowedItems addObject:NSToolbarSpaceItemIdentifier];
    if (self.librarySearchToolbarItem.itemIdentifier) {
        [allowedItems addObject:self.librarySearchToolbarItem.itemIdentifier];
    }
    if (self.renderersToolbarItem.itemIdentifier) {
        [allowedItems addObject:self.renderersToolbarItem.itemIdentifier];
    }
    if (self.togglePlayQueueToolbarItem.itemIdentifier) {
        [allowedItems addObject:self.togglePlayQueueToolbarItem.itemIdentifier];
    }
    return [allowedItems copy];
}

- (NSToolbarItem *)toolbar:(NSToolbar *)toolbar
     itemForItemIdentifier:(NSToolbarItemIdentifier)itemIdentifier
 willBeInsertedIntoToolbar:(BOOL)flag
{
    if ([itemIdentifier isEqualToString:VLCLibraryWindowTrackingSeparatorToolbarItemIdentifier]) {
        if (@available(macOS 11.0, *)) {
            return [NSTrackingSeparatorToolbarItem
                    trackingSeparatorToolbarItemWithIdentifier:itemIdentifier
                    splitView:self.libraryWindow.mainSplitView
                    dividerIndex:VLCLibraryWindowNavigationSidebarSplitViewDividerIndex];
        }
    } else if (self.toggleNavSidebarToolbarItem && [itemIdentifier isEqualToString:self.toggleNavSidebarToolbarItem.itemIdentifier]) {
        return self.toggleNavSidebarToolbarItem;
    } else if (self.backwardsToolbarItem && [itemIdentifier isEqualToString:self.backwardsToolbarItem.itemIdentifier]) {
        return self.backwardsToolbarItem;
    } else if (self.forwardsToolbarItem && [itemIdentifier isEqualToString:self.forwardsToolbarItem.itemIdentifier]) {
        return self.forwardsToolbarItem;
    } else if (self.libraryViewModeToolbarItem && [itemIdentifier isEqualToString:self.libraryViewModeToolbarItem.itemIdentifier]) {
        return self.libraryViewModeToolbarItem;
    } else if (self.sortOrderToolbarItem && [itemIdentifier isEqualToString:self.sortOrderToolbarItem.itemIdentifier]) {
        return self.sortOrderToolbarItem;
    } else if (self.librarySearchToolbarItem && [itemIdentifier isEqualToString:self.librarySearchToolbarItem.itemIdentifier]) {
        return self.librarySearchToolbarItem;
    } else if (self.togglePlayQueueToolbarItem && [itemIdentifier isEqualToString:self.togglePlayQueueToolbarItem.itemIdentifier]) {
        return self.togglePlayQueueToolbarItem;
    } else if (self.renderersToolbarItem && [itemIdentifier isEqualToString:self.renderersToolbarItem.itemIdentifier]) {
        return self.renderersToolbarItem;
    }

    return nil;
}

#pragma mark - renderers toolbar item handling

- (IBAction)rendererControlAction:(id)sender
{
    [NSMenu popUpContextMenu:VLCMain.sharedInstance.mainMenu.rendererMenu
                   withEvent:NSApp.currentEvent
                     forView:sender];
}

- (void)renderersChanged:(NSNotification *)notification
{
    const NSUInteger rendererCount =
        VLCMain.sharedInstance.mainMenu.rendererMenuController.rendererItems.count;
    const BOOL rendererToolbarItemVisible =
        [self.toolbar.items containsObject:self.renderersToolbarItem];

    if (rendererCount > 0 && !rendererToolbarItemVisible) {
        [self insertToolbarItem:self.renderersToolbarItem
                      inFrontOf:@[self.sortOrderToolbarItem,
                                  self.libraryViewModeToolbarItem,
                                  self.forwardsToolbarItem,
                                  self.backwardsToolbarItem,
                                  self.trackingSeparatorToolbarItem,
                                  self.toggleNavSidebarToolbarItem,
                                  self.vlcIconToolbarItem]];
    } else if (rendererCount == 0 && rendererToolbarItemVisible) {
        [self hideToolbarItem:self.renderersToolbarItem];
    }
}

#pragma mark - play queue toggle toolbar item handling

- (void)updatePlayqueueToggleState
{
    NSView * const multifunctionSidebar =
        self.libraryWindow.splitViewController.multifunctionSidebarViewController.view;
    NSSplitView * const sv = self.libraryWindow.mainSplitView;
    self.libraryWindow.playQueueToggle.state =
        ![sv.arrangedSubviews containsObject:multifunctionSidebar] ||
        [sv isSubviewCollapsed:multifunctionSidebar]
            ? NSControlStateValueOff
            : NSControlStateValueOn;
}

#pragma mark - item visibility handling

- (void)hideToolbarItem:(NSToolbarItem *)toolbarItem
{
    const NSInteger toolbarItemIndex = [self.toolbar.items indexOfObject:toolbarItem];
    if (toolbarItemIndex != NSNotFound) {
        [self.toolbar removeItemAtIndex:toolbarItemIndex];
    }
}

/*
 * Try to insert the toolbar item ahead of a group of possible toolbar items.
 * "items" should contain items sorted from the trailing edge of the toolbar to leading edge.
 * "toolbarItem" will be inserted as close to the trailing edge as possible.
 *
 * If you have: | item1 | item2 | item3 | item4 |
 * and the "items" parameter is an array containing @[item6, item5, item2, item1]
 * then the "toolbarItem" provided to this function will place toolbarItem thus:
 * | item1 | item2 | toolbarItem | item3 | item4 |
*/

- (void)insertToolbarItem:(NSToolbarItem *)toolbarItem inFrontOf:(NSArray<NSToolbarItem *> *)items
{
    NSParameterAssert(toolbarItem != nil);
    NSParameterAssert(items != nil);
    NSParameterAssert(toolbarItem.itemIdentifier.length > 0);

    // Build toolbar item index map once to avoid double iteration
    NSArray<NSToolbarItem *> * const toolbarItems = self.toolbar.items;
    NSMapTable * const itemIndexMap = [NSMapTable strongToStrongObjectsMapTable];
    for (NSUInteger i = 0; i < toolbarItems.count; i++) {
        [itemIndexMap setObject:@(i) forKey:toolbarItems[i]];
    }

    NSNumber * const toolbarItemIndexNumber = [itemIndexMap objectForKey:toolbarItem];
    if (toolbarItemIndexNumber != nil) {
        return;
    }

    for (NSToolbarItem * const item in items) {
        NSNumber * const itemIndexNumber = [itemIndexMap objectForKey:item];
        if (itemIndexNumber != nil) {
            const NSInteger itemIndex = itemIndexNumber.integerValue;
            [self.toolbar insertItemWithItemIdentifier:toolbarItem.itemIdentifier
                                               atIndex:itemIndex + 1];
            return;
        }
    }

    [self.toolbar insertItemWithItemIdentifier:toolbarItem.itemIdentifier atIndex:0];
}

#pragma mark - convenience methods for hiding/showing and positioning certain toolbar items

- (void)setForwardsBackwardsToolbarItemsVisible:(BOOL)visible
{
    if (!visible) {
        [self hideToolbarItem:self.forwardsToolbarItem];
        [self hideToolbarItem:self.backwardsToolbarItem];
        return;
    }

    [self insertToolbarItem:self.backwardsToolbarItem 
                  inFrontOf:@[self.trackingSeparatorToolbarItem,
                              self.toggleNavSidebarToolbarItem,
                              self.vlcIconToolbarItem]];

    [self insertToolbarItem:self.forwardsToolbarItem
                  inFrontOf:@[self.backwardsToolbarItem,
                              self.trackingSeparatorToolbarItem,
                              self.toggleNavSidebarToolbarItem,
                              self.vlcIconToolbarItem]];
}

- (void)setSortOrderToolbarItemVisible:(BOOL)visible
{
    if (!visible) {
        [self hideToolbarItem:self.sortOrderToolbarItem];
        return;
    }

    [self insertToolbarItem:self.sortOrderToolbarItem
                  inFrontOf:@[self.libraryViewModeToolbarItem,
                              self.forwardsToolbarItem,
                              self.backwardsToolbarItem,
                              self.trackingSeparatorToolbarItem,
                              self.toggleNavSidebarToolbarItem,
                              self.vlcIconToolbarItem]];
}

- (void)setLibrarySearchToolbarItemVisible:(BOOL)visible
{
    if (!visible) {
        [self hideToolbarItem:self.librarySearchToolbarItem];
        [self.libraryWindow clearFilterString];
        return;
    }

    // Display as far to the right as possible, but not in front of the multifunc bar toggle button
    NSMutableArray<NSToolbarItem *> * const currentToolbarItems = self.toolbar.items.mutableCopy;
    if (currentToolbarItems.lastObject == self.togglePlayQueueToolbarItem) {
        [currentToolbarItems removeLastObject];
    }

    NSArray * const reversedCurrentToolbarItems =
        currentToolbarItems.reverseObjectEnumerator.allObjects;
    [self insertToolbarItem:self.librarySearchToolbarItem
                  inFrontOf:reversedCurrentToolbarItems];
}

- (void)setViewModeToolbarItemVisible:(BOOL)visible
{
    if (!visible) {
        [self hideToolbarItem:self.libraryViewModeToolbarItem];
        return;
    }

    [self insertToolbarItem:self.libraryViewModeToolbarItem
                  inFrontOf:@[self.forwardsToolbarItem,
                              self.backwardsToolbarItem,
                              self.trackingSeparatorToolbarItem,
                              self.toggleNavSidebarToolbarItem,
                              self.vlcIconToolbarItem]];
}

- (void)applyVisiblityFlags:(VLCLibraryWindowToolbarDisplayFlags)flags
{
    [self setForwardsBackwardsToolbarItemsVisible:flags & VLCLibraryWindowToolbarDisplayFlagNavigationButtons];
    [self setSortOrderToolbarItemVisible:flags & VLCLibraryWindowToolbarDisplayFlagSortOrderButton];
    [self setLibrarySearchToolbarItemVisible:flags & VLCLibraryWindowToolbarDisplayFlagLibrarySearchBar];
    [self setViewModeToolbarItemVisible:flags & VLCLibraryWindowToolbarDisplayFlagToggleViewModeSegmentButton];
}

@end
