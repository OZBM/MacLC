/*****************************************************************************
 * MacLCLibrarySections.h: the sections of the native library
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

#import "medialib/sections/MacLCLibrarySectionViewController.h"
#import "medialib/sections/MacLCLibraryDetailScaffold.h"
#import "medialib/sections/MacLCLibraryGridSection.h"

@class VLCMediaLibraryShow;
@class VLCMediaLibraryAlbum;
@class VLCMediaLibraryArtist;
@class VLCMediaLibraryGenre;
@class VLCMediaLibraryPlaylist;

NS_ASSUME_NONNULL_BEGIN

// Every section is created with -init (its segment type is fixed by the
// class); each one's content is described on its interface below.

/// Hero + shelves: Continue Watching, Recently Added, Recently Played Music,
/// Albums; onboarding empty state when the library is empty.
@interface MacLCLibraryHomeViewController : MacLCLibrarySectionViewController
- (instancetype)init;
@end

/// Every video that is not an episode. Grid / list, sortable.
@interface MacLCLibraryVideosViewController : MacLCLibraryGridSection
- (instancetype)init;
@end

/// Shows grid; pushes MacLCShowDetailViewController.
@interface MacLCLibraryShowsViewController : MacLCLibraryGridSection
- (instancetype)init;
@end

/// Artists grid (circles) / list; pushes MacLCArtistDetailViewController.
@interface MacLCLibraryArtistsViewController : MacLCLibraryGridSection
- (instancetype)init;
@end

/// Albums grid / list; pushes MacLCAlbumDetailViewController.
@interface MacLCLibraryAlbumsViewController : MacLCLibraryGridSection
- (instancetype)init;
@end

/// Songs table (list only), sortable columns.
@interface MacLCLibrarySongsViewController : MacLCLibraryGridSection
- (instancetype)init;
@end

/// Genres grid; pushes MacLCGenreDetailViewController.
@interface MacLCLibraryGenresViewController : MacLCLibraryGridSection
- (instancetype)init;
@end

/// Playlists grid; pushes MacLCPlaylistDetailViewController. The sidebar
/// lists the playlists too and shows one through -showItem:.
@interface MacLCLibraryPlaylistsViewController : MacLCLibraryGridSection
- (instancetype)init;
@end

/// Shelves of favourite videos, songs, albums and artists.
@interface MacLCLibraryFavoritesViewController : MacLCLibrarySectionViewController
- (instancetype)init;
@end

// MARK: - Details (pushed on a section's stack)

@interface MacLCShowDetailViewController : MacLCLibraryDetailScaffold
- (instancetype)initWithShow:(VLCMediaLibraryShow *)show;
@end

@interface MacLCAlbumDetailViewController : MacLCLibraryDetailScaffold
- (instancetype)initWithAlbum:(VLCMediaLibraryAlbum *)album;
@end

@interface MacLCArtistDetailViewController : MacLCLibraryDetailScaffold
- (instancetype)initWithArtist:(VLCMediaLibraryArtist *)artist;
@end

@interface MacLCGenreDetailViewController : MacLCLibraryDetailScaffold
- (instancetype)initWithGenre:(VLCMediaLibraryGenre *)genre;
@end

@interface MacLCPlaylistDetailViewController : MacLCLibraryDetailScaffold
- (instancetype)initWithPlaylist:(VLCMediaLibraryPlaylist *)playlist;
@end

NS_ASSUME_NONNULL_END
