/*****************************************************************************
 * MacLCLibraryFormatting.h: counts and durations as the library writes them
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

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// "1 album", "38 albums" (localized through _NS, number grouped).
FOUNDATION_EXPORT NSString *MacLCCountString(NSUInteger count, NSString *singular, NSString *plural);

/// "1 hr 42 min", "32 min", "Less than a minute" (milliseconds in).
FOUNDATION_EXPORT NSString *MacLCDurationString(int64_t milliseconds);

/// Joins the non-empty parts with " · ".
FOUNDATION_EXPORT NSString *MacLCJoinedDetails(NSArray<NSString *> *parts);

NS_ASSUME_NONNULL_END
