/*****************************************************************************
 * MacLCLibrarySongsViewController.m: every song, as a sortable list
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

@implementation MacLCLibrarySongsViewController

- (instancetype)init
{
    self = [super initWithSegmentType:VLCLibrarySongsMusicSubSegmentType
                                title:_NS("Songs")
                           collection:MacLCLibraryCollectionSongs
                                shape:MacLCArtworkShapeSquare
                        subtitleStyle:MacLCCardSubtitleStyleDefault];
    if (self) {
        [self setCountNounSingular:_NS("song") plural:_NS("songs")];
        [self setEmptyStateSymbolName:@"music.note"
                                title:_NS("No Songs")
                              message:_NS("Music in your library folders appears here.")];
        self.listColumns = MacLCTrackListColumnTitle | MacLCTrackListColumnArtist | MacLCTrackListColumnAlbum
            | MacLCTrackListColumnGenre | MacLCTrackListColumnDuration | MacLCTrackListColumnPlays;
        self.listOnly = YES;
    }
    return self;
}

@end
