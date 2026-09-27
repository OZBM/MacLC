/*****************************************************************************
 * MacLCLibraryMenus.h: menu bar commands of the media library
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

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

/// Actions sent through the responder chain (nil target) by the library
/// commands of the menu bar. The library window implements them and
/// validates them (enabled state, check marks, Show/Hide titles).
@protocol MacLCLibraryMenuActions <NSObject>
- (IBAction)newLibraryPlaylist:(nullable id)sender;
- (IBAction)addFolderToLibrary:(nullable id)sender;
- (IBAction)showLibraryFolders:(nullable id)sender;
- (IBAction)goBackInLibrary:(nullable id)sender;
- (IBAction)goForwardInLibrary:(nullable id)sender;
- (IBAction)toggleUpNext:(nullable id)sender;
- (IBAction)showLibraryAsGrid:(nullable id)sender;
- (IBAction)showLibraryAsList:(nullable id)sender;
/// Returns the sort menu of the visible library section, or nil when the
/// visible section cannot be sorted. Its items carry their own target,
/// action and state; the Sort By submenu shows copies of them.
- (nullable NSMenu *)macLCLibrarySortMenu;
@end

@interface MacLCLibraryMenus : NSObject

/// Adds the library commands to the File menu and inserts a View menu
/// right after the Edit menu. Call once, from -[VLCMainMenu awakeFromNib].
/// Returns the View menu it created.
+ (NSMenu *)installInMainMenu:(NSMenu *)mainMenu
                     fileMenu:(NSMenu *)fileMenu
                     editMenu:(NSMenu *)editMenu;

@end

NS_ASSUME_NONNULL_END
