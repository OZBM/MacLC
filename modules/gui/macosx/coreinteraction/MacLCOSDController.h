/*****************************************************************************
 * MacLCOSDController.h: what the glass capsule over the video says
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

/** Posted on the main thread for the visible video view to show. */
extern NSString * const MacLCOSDShouldShowNotification;
extern NSString * const MacLCOSDMessageKey;             /* NSString */
extern NSString * const MacLCOSDSymbolKey;              /* NSString, optional */
extern NSString * const MacLCOSDLevelKey;               /* NSNumber 0...1, negative: no bar */
/** NSNumber(BOOL): only worth showing when the playback controls, which
 *  already show the same thing, are hidden (volume, pause, seek). */
extern NSString * const MacLCOSDOnlyWithoutControlsKey;

/**
 * Turns player changes - volume, speed, tracks, delays, pausing, jumps - into
 * short messages for MacLCOSDView, whatever caused them: keyboard, menus,
 * remote, media keys. Replaces the text the playback core used to draw into
 * the picture, which it no longer does (its "osd" variable is turned off on
 * the player). The "osd" preference still turns the messages off altogether.
 */
@interface MacLCOSDController : NSObject

+ (instancetype)sharedController;

/** Shows a message now (actions the player does not report, e.g. snapshots). */
- (void)showMessage:(NSString *)message symbolName:(nullable NSString *)symbolName;

@end

NS_ASSUME_NONNULL_END
