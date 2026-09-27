/*****************************************************************************
 * MacLCLibraryMenus.m: menu bar commands of the media library
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

#import "menus/MacLCLibraryMenus.h"
#import "extensions/NSString+Helpers.h"

@interface MacLCLibrarySortMenuDelegate : NSObject <NSMenuDelegate>
@end

@implementation MacLCLibrarySortMenuDelegate

- (void)menuNeedsUpdate:(NSMenu *)menu
{
    [menu removeAllItems];

    id provider = [NSApp targetForAction:@selector(macLCLibrarySortMenu)];
    if ([provider conformsToProtocol:@protocol(MacLCLibraryMenuActions)]) {
        NSMenu *sortMenu = [(id<MacLCLibraryMenuActions>)provider macLCLibrarySortMenu];
        if (sortMenu != nil && sortMenu.numberOfItems > 0) {
            for (NSMenuItem *item in sortMenu.itemArray) {
                [menu addItem:[item copy]];
            }
            return;
        }
    }

    NSMenuItem *noSortItem = [[NSMenuItem alloc] initWithTitle:_NS("No Sort Options")
                                                        action:NULL
                                                 keyEquivalent:@""];
    noSortItem.target = nil;
    noSortItem.keyEquivalentModifierMask = 0;
    noSortItem.enabled = NO;
    [menu addItem:noSortItem];
}

@end

@implementation MacLCLibraryMenus

+ (NSMenu *)installInMainMenu:(NSMenu *)mainMenu
                     fileMenu:(NSMenu *)fileMenu
                     editMenu:(NSMenu *)editMenu
{
    // 1. File menu: insert a new group (separator before and after) right after
    // the group that holds the Open commands (the first separator of the File menu).
    if ([fileMenu indexOfItemWithTarget:nil andAction:@selector(newLibraryPlaylist:)] == -1) {
        NSMenuItem *newPlaylistItem = [[NSMenuItem alloc] initWithTitle:_NS("New Playlist…")
                                                                 action:@selector(newLibraryPlaylist:)
                                                          keyEquivalent:@"n"];
        newPlaylistItem.target = nil;
        newPlaylistItem.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift;

        NSMenuItem *addFolderItem = [[NSMenuItem alloc] initWithTitle:_NS("Add Folder to Library…")
                                                               action:@selector(addFolderToLibrary:)
                                                        keyEquivalent:@""];
        addFolderItem.target = nil;
        addFolderItem.keyEquivalentModifierMask = 0;

        NSMenuItem *libraryFoldersItem = [[NSMenuItem alloc] initWithTitle:_NS("Library Folders…")
                                                                    action:@selector(showLibraryFolders:)
                                                             keyEquivalent:@""];
        libraryFoldersItem.target = nil;
        libraryFoldersItem.keyEquivalentModifierMask = 0;

        NSInteger firstSeparatorIndex = -1;
        for (NSInteger i = 0; i < fileMenu.numberOfItems; i++) {
            if ([fileMenu itemAtIndex:i].isSeparatorItem) {
                firstSeparatorIndex = i;
                break;
            }
        }

        if (firstSeparatorIndex != -1) {
            NSInteger insertIndex = firstSeparatorIndex + 1;
            [fileMenu insertItem:newPlaylistItem atIndex:insertIndex++];
            [fileMenu insertItem:addFolderItem atIndex:insertIndex++];
            [fileMenu insertItem:libraryFoldersItem atIndex:insertIndex++];
            [fileMenu insertItem:[NSMenuItem separatorItem] atIndex:insertIndex++];
        } else {
            NSInteger insertIndex = 0;
            [fileMenu insertItem:[NSMenuItem separatorItem] atIndex:insertIndex++];
            [fileMenu insertItem:newPlaylistItem atIndex:insertIndex++];
            [fileMenu insertItem:addFolderItem atIndex:insertIndex++];
            [fileMenu insertItem:libraryFoldersItem atIndex:insertIndex++];
            [fileMenu insertItem:[NSMenuItem separatorItem] atIndex:insertIndex++];
        }
    }

    // Check if View menu is already installed in mainMenu
    for (NSMenuItem *item in mainMenu.itemArray) {
        if (item.submenu != nil && [item.submenu indexOfItemWithTarget:nil andAction:@selector(goBackInLibrary:)] != -1) {
            return item.submenu;
        }
    }

    // 2. View menu: create a new top-level menu titled "View"
    NSMenu *viewMenu = [[NSMenu alloc] initWithTitle:_NS("View")];
    viewMenu.autoenablesItems = YES;

    // Items in order:
    // - "Back" — goBackInLibrary: — Command-[
    NSMenuItem *backItem = [[NSMenuItem alloc] initWithTitle:_NS("Back")
                                                      action:@selector(goBackInLibrary:)
                                               keyEquivalent:@"["];
    backItem.target = nil;
    backItem.keyEquivalentModifierMask = NSEventModifierFlagCommand;
    [viewMenu addItem:backItem];

    // - "Forward" — goForwardInLibrary: — Command-]
    NSMenuItem *forwardItem = [[NSMenuItem alloc] initWithTitle:_NS("Forward")
                                                         action:@selector(goForwardInLibrary:)
                                                  keyEquivalent:@"]"];
    forwardItem.target = nil;
    forwardItem.keyEquivalentModifierMask = NSEventModifierFlagCommand;
    [viewMenu addItem:forwardItem];

    // - separator
    [viewMenu addItem:[NSMenuItem separatorItem]];

    // - "Show Sidebar" — toggleSidebar: — Control-Command-S
    NSMenuItem *sidebarItem = [[NSMenuItem alloc] initWithTitle:_NS("Show Sidebar")
                                                         action:@selector(toggleSidebar:)
                                                  keyEquivalent:@"s"];
    sidebarItem.target = nil;
    sidebarItem.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagControl;
    [viewMenu addItem:sidebarItem];

    // - "Show Up Next" — toggleUpNext: — Option-Command-U
    NSMenuItem *upNextItem = [[NSMenuItem alloc] initWithTitle:_NS("Show Up Next")
                                                        action:@selector(toggleUpNext:)
                                                 keyEquivalent:@"u"];
    upNextItem.target = nil;
    upNextItem.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagOption;
    [viewMenu addItem:upNextItem];

    // - "Hide Toolbar" — toggleToolbarShown: — Option-Command-T
    NSMenuItem *toolbarItem = [[NSMenuItem alloc] initWithTitle:_NS("Hide Toolbar")
                                                         action:@selector(toggleToolbarShown:)
                                                  keyEquivalent:@"t"];
    toolbarItem.target = nil;
    toolbarItem.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagOption;
    [viewMenu addItem:toolbarItem];

    // - separator
    [viewMenu addItem:[NSMenuItem separatorItem]];

    // - "as Grid" — showLibraryAsGrid: — Control-Command-1
    NSMenuItem *gridItem = [[NSMenuItem alloc] initWithTitle:_NS("as Grid")
                                                      action:@selector(showLibraryAsGrid:)
                                               keyEquivalent:@"1"];
    gridItem.target = nil;
    gridItem.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagControl;
    [viewMenu addItem:gridItem];

    // - "as List" — showLibraryAsList: — Control-Command-2
    NSMenuItem *listItem = [[NSMenuItem alloc] initWithTitle:_NS("as List")
                                                      action:@selector(showLibraryAsList:)
                                               keyEquivalent:@"2"];
    listItem.target = nil;
    listItem.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagControl;
    [viewMenu addItem:listItem];

    // - "Sort By" — item with an empty submenu titled "Sort By"
    NSMenuItem *sortItem = [[NSMenuItem alloc] initWithTitle:_NS("Sort By")
                                                      action:NULL
                                               keyEquivalent:@""];
    sortItem.target = nil;
    sortItem.keyEquivalentModifierMask = 0;
    if (@available(macOS 11.0, *)) {
        sortItem.image = [NSImage imageWithSystemSymbolName:@"arrow.up.arrow.down" accessibilityDescription:nil];
    }

    NSMenu *sortSubmenu = [[NSMenu alloc] initWithTitle:_NS("Sort By")];
    sortSubmenu.autoenablesItems = YES;

    static MacLCLibrarySortMenuDelegate *s_sortMenuDelegate = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        s_sortMenuDelegate = [[MacLCLibrarySortMenuDelegate alloc] init];
    });
    sortSubmenu.delegate = s_sortMenuDelegate;
    sortItem.submenu = sortSubmenu;

    [viewMenu addItem:sortItem];

    // Insert View menu in mainMenu immediately after editMenu
    NSInteger editIndex = [mainMenu indexOfItemWithSubmenu:editMenu];
    NSInteger insertIndex = (editIndex != -1) ? (editIndex + 1) : mainMenu.numberOfItems;

    NSMenuItem *viewMenuItem = [[NSMenuItem alloc] initWithTitle:_NS("View")
                                                          action:NULL
                                                   keyEquivalent:@""];
    viewMenuItem.submenu = viewMenu;
    [mainMenu insertItem:viewMenuItem atIndex:insertIndex];

    return viewMenu;
}

@end
