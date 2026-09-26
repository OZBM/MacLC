/*****************************************************************************
 * MacLCUpNextViewController.h: the play queue, as the window's inspector
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

/// Content of the split view's inspector item (NSSplitViewItem
/// inspectorWithViewController:, floating glass on macOS 26), width 280–420.
/// Top: a header row "Up Next" (headline) with, trailing, a segmented control
/// "Queue | Chapters" (only when the current media has chapters; Chapters
/// hosts the existing VLCLibraryWindowChaptersSidebarViewController view) and
/// a "···" pull-down: Shuffle (checkmark), Repeat ▸ (Off, All, One),
/// separator, Save as Playlist…, Clear Up Next.
/// Queue: NSTableView (style inset, row height 52) of the play queue: artwork
/// 40 × 40 (16:9 poster for video, radius 5), title (body, 1 line), subtitle
/// (artist or duration, subheadline, secondaryLabel); the current item shows
/// speaker.wave.2.fill (accent) and bold title; played items above it use
/// secondaryLabel. Double-click plays; drag to reorder; Delete removes;
/// files dropped from Finder are appended; context menu: Play, Remove from
/// Up Next, Show in Finder, Get Info.
/// Empty queue: MacLCEmptyStateView (list.bullet, "Nothing Up Next",
/// "Add songs and videos with Play Next or Add to Up Next.").
@interface MacLCUpNextViewController : NSViewController

- (instancetype)initWithLibraryWindow:(VLCLibraryWindow *)libraryWindow;

@end

NS_ASSUME_NONNULL_END
