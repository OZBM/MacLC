/*****************************************************************************
 * MacLCLibraryTypes.h: shared types of MacLC's native media library
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

/// The lists the library store keeps up to date. Every list is sorted by the
/// store's default order for that list (see MacLCLibraryStore.h).
typedef NS_ENUM(NSInteger, MacLCLibraryCollection) {
    /// Every video that is not a show episode. Items: VLCMediaLibraryMediaItem.
    MacLCLibraryCollectionVideos = 0,
    /// Items: VLCMediaLibraryShow.
    MacLCLibraryCollectionShows,
    /// Items: VLCMediaLibraryArtist.
    MacLCLibraryCollectionArtists,
    /// Items: VLCMediaLibraryAlbum.
    MacLCLibraryCollectionAlbums,
    /// Every audio track. Items: VLCMediaLibraryMediaItem.
    MacLCLibraryCollectionSongs,
    /// Items: VLCMediaLibraryGenre.
    MacLCLibraryCollectionGenres,
    /// User playlists (audio, video and mixed). Items: VLCMediaLibraryPlaylist.
    MacLCLibraryCollectionPlaylists,
    /// Videos (episodes included) started but not finished, most recent first.
    /// Items: VLCMediaLibraryMediaItem.
    MacLCLibraryCollectionContinueWatching,
    /// Videos (episodes included), most recently added first, at most 30.
    /// Items: VLCMediaLibraryMediaItem.
    MacLCLibraryCollectionRecentlyAddedVideos,
    /// Audio tracks, most recently played first, at most 30.
    /// Items: VLCMediaLibraryMediaItem.
    MacLCLibraryCollectionRecentlyPlayedMusic,
    /// Items: VLCMediaLibraryMediaItem (video).
    MacLCLibraryCollectionFavoriteVideos,
    /// Items: VLCMediaLibraryMediaItem (audio).
    MacLCLibraryCollectionFavoriteSongs,
    /// Items: VLCMediaLibraryAlbum.
    MacLCLibraryCollectionFavoriteAlbums,
    /// Items: VLCMediaLibraryArtist.
    MacLCLibraryCollectionFavoriteArtists,
    MacLCLibraryCollectionCount
};

/// Grid (artwork) or list (table) presentation of a section.
typedef NS_ENUM(NSInteger, MacLCLibraryViewMode) {
    MacLCLibraryViewModeGrid = 0,
    MacLCLibraryViewModeList = 1,
};

/// Shape of a piece of artwork. Drives aspect ratio, corner radius and the
/// placeholder symbol of MacLCArtworkView.
typedef NS_ENUM(NSInteger, MacLCArtworkShape) {
    /// 16:9, rounded rectangle: videos, episodes, shows.
    MacLCArtworkShapeVideo = 0,
    /// 1:1, rounded rectangle: albums, songs, playlists, genres.
    MacLCArtworkShapeSquare,
    /// 1:1, circle: artists.
    MacLCArtworkShapeCircle,
};

/// A stable identifier for a library object, usable as a diffable data
/// source item identifier across object types, e.g. @"media:42", @"album:7".
/// Build it with MacLCLibraryItemIdentifier() only.
typedef NSString * MacLCLibraryItemID;

NS_ASSUME_NONNULL_END
