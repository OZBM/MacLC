/*****************************************************************************
 * MacLCHDRMenuController.h: the Video ▸ HDR submenu
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

/**
 * Builds the HDR submenu (DESIGN_SPEC §9): HDR Options… (⌥⌘H), the formats the
 * current video offers (unavailable ones disabled, the active one checked)
 * and the picture modes. Rebuilt every time the menu opens.
 */
@interface MacLCHDRMenuController : NSObject <NSMenuDelegate>

+ (instancetype)sharedMenuController;

/** Inserts the submenu at the top of `videoMenu` (once). */
- (void)installInVideoMenu:(NSMenu *)videoMenu;

/** The submenu, for other places that want it (the video context menu). */
@property (readonly) NSMenu *hdrMenu;

@end

NS_ASSUME_NONNULL_END
