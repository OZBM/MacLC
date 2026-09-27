/*****************************************************************************
 * MacLCLibraryShowsViewController.m: shows, opened season by season
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

@implementation MacLCLibraryShowsViewController

- (instancetype)init
{
    self = [super initWithSegmentType:VLCLibraryShowsVideoSubSegmentType
                                title:_NS("Shows")
                           collection:MacLCLibraryCollectionShows
                                shape:MacLCArtworkShapeVideo
                        subtitleStyle:MacLCCardSubtitleStyleDefault];
    if (self) {
        [self setCountNounSingular:_NS("show") plural:_NS("shows")];
        [self setEmptyStateSymbolName:@"tv"
                                title:_NS("No Shows")
                              message:_NS("Name episodes like “Show Name S01E02” and they are grouped here.")];
        self.detailFactory = ^NSViewController *(id<VLCMediaLibraryItemProtocol> const item) {
            return [item isKindOfClass:VLCMediaLibraryShow.class]
                ? [[MacLCShowDetailViewController alloc] initWithShow:(VLCMediaLibraryShow *)item] : nil;
        };
    }
    return self;
}

@end
