/*****************************************************************************
 * MacLCAddonSearchWindowController.h: search titles and play streams through
 * the installed add-ons
 *****************************************************************************
 * Copyright (C) 2026 Hazen Studio
 *
 * This program is free software; you can redistribute it and/or modify it
 * under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation; either version 2.1 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin Street, Fifth Floor, Boston MA 02110-1301, USA.
 *****************************************************************************/

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface MacLCAddonSearchWindowController : NSWindowController

@property (class, readonly) MacLCAddonSearchWindowController *sharedController;

/// Developer hook: searches query; autoplayType @"movie" or @"series" picks the
/// first result of that type (for a series, the first episode of the lowest
/// season >= 1) and plays its first stream; @"select-movie" or @"select-series"
/// stops once the streams are listed. nil only searches.
- (void)showWindowWithQuery:(NSString *)query autoplayType:(nullable NSString *)type;

@end

NS_ASSUME_NONNULL_END
