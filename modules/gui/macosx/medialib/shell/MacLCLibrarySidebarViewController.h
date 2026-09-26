/*****************************************************************************
 * MacLCLibrarySidebarViewController.h: the library window's source list
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

@class VLCLibraryWindow;

NS_ASSUME_NONNULL_BEGIN

/// A standard source list (NSOutlineView, style NSTableViewStyleSourceList,
/// floating Liquid Glass on macOS 26 through the split view's sidebar item),
/// two levels at most (sidebars.md), system row size, SF Symbols in the
/// accent colour (sidebars.md: "By default, sidebar icons use your app's
/// accent color"):
///
///   Home                     house
///   Library ─────────────────────────────
///     Videos                 film
///     Shows                  tv
///     Artists                music.mic
///     Albums                 square.stack
///     Songs                  music.note
///     Genres                 guitars
///     Favorites              star
///   Playlists ───────────── [+ on hover]
///     <each playlist>        music.note.list
///   Locations ──────────────────────────
///     Browse                 folder
///     <bookmarked folders>   folder
///
/// Without a media library, only Locations shows. While indexing, the Library
/// header shows a small spinning NSProgressIndicator with the tooltip
/// "Adding media from <folder>" (no status bar at the bottom: sidebars.md,
/// "Avoid putting critical information or actions at the bottom").
/// Selecting a row sets the window's segment (playlists go through the
/// router's -showPlaylist:). Context menus: playlist rows get Play, Shuffle,
/// Rename…, Delete Playlist…; the Library header gets Library Folders…;
/// bookmarked folders get Remove from Sidebar.
@interface MacLCLibrarySidebarViewController : NSViewController

- (instancetype)initWithLibraryWindow:(VLCLibraryWindow *)libraryWindow;

/// Same contract as the old sidebar: select the row of a segment type.
- (void)selectSegment:(NSInteger)segmentType;

@end

NS_ASSUME_NONNULL_END
