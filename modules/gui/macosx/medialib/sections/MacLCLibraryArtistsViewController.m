/*****************************************************************************
 * MacLCLibraryArtistsViewController.m: artists
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

@implementation MacLCLibraryArtistsViewController

- (instancetype)init
{
    self = [super initWithSegmentType:VLCLibraryArtistsMusicSubSegmentType
                                title:_NS("Artists")
                           collection:MacLCLibraryCollectionArtists
                                shape:MacLCArtworkShapeCircle
                        subtitleStyle:MacLCCardSubtitleStyleDefault];
    if (self) {
        [self setCountNounSingular:_NS("artist") plural:_NS("artists")];
        [self setEmptyStateSymbolName:@"music.mic"
                                title:_NS("No Artists")
                              message:_NS("Music in your library folders appears here.")];
        self.detailFactory = ^NSViewController *(id<VLCMediaLibraryItemProtocol> const item) {
            return [item isKindOfClass:VLCMediaLibraryArtist.class]
                ? [[MacLCArtistDetailViewController alloc] initWithArtist:(VLCMediaLibraryArtist *)item] : nil;
        };
    }
    return self;
}

@end
