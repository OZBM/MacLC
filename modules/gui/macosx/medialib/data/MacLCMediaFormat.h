/*****************************************************************************
 * MacLCMediaFormat.h: picture format facts of a library video, for badges
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

@class VLCMediaLibraryMediaItem;

NS_ASSUME_NONNULL_BEGIN

/// What a video's picture is, as far as the library knows it: resolution
/// class from the first video track, and dynamic range from the tag the
/// media library module writes in that track's description when it indexes
/// an HDR file ("Dolby Vision", "HDR10", "HLG"; see MetadataExtractor.cpp).
@interface MacLCMediaFormat : NSObject

+ (instancetype)formatForMediaItem:(VLCMediaLibraryMediaItem *)mediaItem;

/// "8K", "4K", "HD" or nil (below 720 lines, audio, or unknown).
@property (readonly, copy, nullable) NSString *resolutionBadge;
/// "DOLBY VISION", "HDR10", "HLG", "HDR" or nil for standard range/unknown.
@property (readonly, copy, nullable) NSString *dynamicRangeBadge;
/// The badges to draw, most significant first (dynamic range, then
/// resolution), already uppercase. Empty for audio.
@property (readonly, copy) NSArray<NSString *> *badges;
/// Spoken form for VoiceOver, e.g. "4K, Dolby Vision".
@property (readonly, copy) NSString *accessibilityDescription;

@end

NS_ASSUME_NONNULL_END
