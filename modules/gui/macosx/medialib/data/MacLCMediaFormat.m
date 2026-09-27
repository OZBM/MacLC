/*****************************************************************************
 * MacLCMediaFormat.m: picture format facts of a library video, for badges
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

#import "medialib/data/MacLCMediaFormat.h"

#import <vlc_common.h>
#import <vlc_media_library.h>

#import "extensions/NSString+Helpers.h"
#import "library/VLCLibraryDataTypes.h"

@implementation MacLCMediaFormat

+ (instancetype)formatForMediaItem:(VLCMediaLibraryMediaItem *)mediaItem
{
    return [[self alloc] initWithMediaItem:mediaItem];
}

- (instancetype)initWithMediaItem:(VLCMediaLibraryMediaItem *)mediaItem
{
    self = [super init];
    if (self) {
        VLCMediaLibraryTrack * const track =
            mediaItem.mediaType == VLC_ML_MEDIA_TYPE_VIDEO ? mediaItem.firstVideoTrack : nil;
        if (track != nil) {
            _resolutionBadge = [MacLCMediaFormat resolutionBadgeForWidth:track.videoWidth
                                                                  height:track.videoHeight];
            _dynamicRangeBadge = [MacLCMediaFormat dynamicRangeBadgeForDescription:track.trackDescription];
        }

        NSMutableArray<NSString *> * const badges = [NSMutableArray arrayWithCapacity:2];
        NSMutableArray<NSString *> * const spoken = [NSMutableArray arrayWithCapacity:2];
        if (_dynamicRangeBadge != nil) {
            [badges addObject:_dynamicRangeBadge];
        }
        if (_resolutionBadge != nil) {
            [badges addObject:_resolutionBadge];
            [spoken addObject:_resolutionBadge];
        }
        if (_dynamicRangeBadge != nil) {
            [spoken addObject:[MacLCMediaFormat spokenDynamicRange:_dynamicRangeBadge]];
        }
        _badges = [badges copy];
        _accessibilityDescription = [spoken componentsJoinedByString:@", "];
    }
    return self;
}

/* Classes by the larger dimension too, so cropped (scope) and portrait
 * videos land where people expect: a 3840 × 1600 film is 4K. */
+ (nullable NSString *)resolutionBadgeForWidth:(uint32_t)width height:(uint32_t)height
{
    if (height >= 4000 || width >= 7600) {
        return @"8K";
    }
    if (height >= 2000 || width >= 3800) {
        return @"4K";
    }
    if (height >= 700 || width >= 1270) {
        return @"HD";
    }
    return nil;
}

/* The media library module names the dynamic range of HDR tracks in their
 * description (MetadataExtractor.cpp); anything else is standard or
 * unknown, and gets no badge. */
+ (nullable NSString *)dynamicRangeBadgeForDescription:(nullable NSString *)description
{
    static NSDictionary<NSString *, NSString *> *badges;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        badges = @{
            @"Dolby Vision": @"DOLBY VISION",
            @"HDR10+": @"HDR10+",
            @"HDR10": @"HDR10",
            @"HLG": @"HLG",
            @"HDR": @"HDR",
        };
    });
    return description != nil ? badges[description] : nil;
}

+ (NSString *)spokenDynamicRange:(NSString *)badge
{
    if ([badge isEqualToString:@"DOLBY VISION"]) {
        return _NS("Dolby Vision");
    }
    return badge;
}

@end
