/*****************************************************************************
 * MacLCLibraryVideosViewController.m: every video that is not an episode
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

@implementation MacLCLibraryVideosViewController

- (instancetype)init
{
    self = [super initWithSegmentType:VLCLibraryVideoSegmentType
                                title:_NS("Videos")
                           collection:MacLCLibraryCollectionVideos
                                shape:MacLCArtworkShapeVideo
                        subtitleStyle:MacLCCardSubtitleStyleDefault];
    if (self) {
        [self setCountNounSingular:_NS("video") plural:_NS("videos")];
        [self setEmptyStateSymbolName:@"film"
                                title:_NS("No Videos")
                              message:_NS("Videos in your library folders appear here.")];
        self.listColumns = MacLCTrackListColumnThumbnail | MacLCTrackListColumnTitle | MacLCTrackListColumnDuration
            | MacLCTrackListColumnFormat | MacLCTrackListColumnDateAdded | MacLCTrackListColumnPlays;
        self.sortOptions = @[MacLCSortKeyTitle, MacLCSortKeyDuration, MacLCSortKeyLastPlayed];
    }
    return self;
}

@end
