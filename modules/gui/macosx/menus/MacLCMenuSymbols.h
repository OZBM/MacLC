/*****************************************************************************
 * MacLCMenuSymbols.h: MacOS X interface module
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

#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface MacLCMenuSymbols : NSObject

/**
 * Recursively applies SF Symbol icons to menu items following Apple HIG
 * rules for grouping, purpose, and visual consistency.
 *
 * @param menu The root menu to process.
 */
+ (void)applySymbolsToMenu:(NSMenu *)menu;

@end

NS_ASSUME_NONNULL_END
