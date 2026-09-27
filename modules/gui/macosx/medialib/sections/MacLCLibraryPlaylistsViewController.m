/*****************************************************************************
 * MacLCLibraryPlaylistsViewController.m: playlists
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

#import "medialib/sections/MacLCLibrarySections.h"

#import "extensions/NSString+Helpers.h"
#import "library/VLCLibraryDataTypes.h"
#import "library/VLCLibrarySegment.h"

@implementation MacLCLibraryPlaylistsViewController

- (instancetype)init
{
    self = [super initWithSegmentType:VLCLibraryPlaylistsSegmentType
                                title:_NS("Playlists")
                           collection:MacLCLibraryCollectionPlaylists
                                shape:MacLCArtworkShapeSquare
                        subtitleStyle:MacLCCardSubtitleStyleDefault];
    if (self) {
        [self setCountNounSingular:_NS("playlist") plural:_NS("playlists")];
        [self setEmptyStateSymbolName:@"music.note.list"
                                title:_NS("No Playlists")
                              message:_NS("Create one with New Playlist in the File menu or the + next to Playlists.")];
        self.detailFactory = ^NSViewController *(id<VLCMediaLibraryItemProtocol> const item) {
            return [item isKindOfClass:VLCMediaLibraryPlaylist.class]
                ? [[MacLCPlaylistDetailViewController alloc] initWithPlaylist:(VLCMediaLibraryPlaylist *)item] : nil;
        };
    }
    return self;
}

@end
