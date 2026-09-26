/*****************************************************************************
 * MacLCLibraryFoldersController.h: choose the folders the library watches
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

/// A sheet titled "Library Folders": one sentence ("MacLC adds the movies,
/// shows and music it finds in these folders. Nothing leaves your Mac."), a
/// bordered table of folders (folder icon from NSWorkspace, name, path in
/// secondaryLabel, a spinning indicator while that folder is being scanned),
/// "+" / "−" gradient buttons under it (+ opens an NSOpenPanel for
/// directories, − removes the selection after a confirmation alert when the
/// folder has media: "Remove “Movies” from the library? The files stay on
/// your Mac."), and "Rescan" + "Done" (default) at the bottom right.
@interface MacLCLibraryFoldersController : NSWindowController

+ (instancetype)sharedController;

- (void)beginSheetForWindow:(NSWindow *)window;
/// NSOpenPanel for one or more folders, added directly (File ▸ Add Folder to
/// Library…).
- (void)chooseFoldersToAddForWindow:(nullable NSWindow *)window;

@end

NS_ASSUME_NONNULL_END
