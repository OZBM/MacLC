/*****************************************************************************
 * MacLCLibraryRouter.h: shows native library sections in the library window
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

#import "library/VLCLibraryAbstractSegmentViewController.h"
#import "library/VLCLibraryItemPresentingCapable.h"

@class VLCLibraryWindow;
@class VLCMediaLibraryPlaylist;
@class MacLCLibrarySectionViewController;

NS_ASSUME_NONNULL_BEGIN

/// Posted (object: the router) after the section on screen changed.
extern NSNotificationName const MacLCLibraryRouterSectionDidChangeNotification;

/// The bridge between the library window's segment machinery and the native
/// sections. VLCLibrarySegment's creator block returns
/// +routerForLibraryWindow: for every segment in +handlesSegmentType:, and its
/// presenter block calls -presentSegmentType:. The router keeps one section
/// view controller per segment type alive (so each keeps its scroll position
/// and navigation stack), shows its view with
/// -[VLCLibraryWindow displayLibraryView:], sets the window title and
/// subtitle from the section's chrome, and posts the change notification.
/// Browse is not a native section: it keeps VLCLibraryMediaSourceViewController.
@interface MacLCLibraryRouter : VLCLibraryAbstractSegmentViewController <VLCLibraryItemPresentingCapable>

/// One router per library window, created on first use.
+ (instancetype)routerForLibraryWindow:(VLCLibraryWindow *)libraryWindow;

/// Home, Favorites, Videos, Shows, Movies (shown as Videos), Music (shown as
/// Albums), Artists, Albums, Songs, Genres, Playlists and their subsegments.
+ (BOOL)handlesSegmentType:(NSInteger)segmentType;

- (void)presentSegmentType:(NSInteger)segmentType;

@property (readonly, nullable) MacLCLibrarySectionViewController *currentSection;

/// Selects the Playlists section and shows that playlist's detail.
- (void)showPlaylist:(VLCMediaLibraryPlaylist *)playlist;

@end

NS_ASSUME_NONNULL_END
