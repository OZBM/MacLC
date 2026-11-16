/*****************************************************************************
 * MacLCGlassMenuPopover.h: MacOS X interface module
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
 * Shows an NSMenu as a Liquid Glass popover list: the same items, actions,
 * check marks, symbols and enabled states; submenus open inline. Items that
 * carry a custom view are reached through the last row, "All Options…",
 * which shows the classic menu. Clicking the same anchor again closes it.
 */
@interface MacLCGlassMenuPopover : NSViewController

+ (void)showMenu:(NSMenu *)menu relativeToView:(NSView *)view;

@end

NS_ASSUME_NONNULL_END
