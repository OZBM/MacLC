/*****************************************************************************
 * MacLC-Bridging-Header.h: the Objective-C that the plugin's Swift sees
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

/* Swift imports these headers textually, without config.h: list only headers
 * that need nothing beyond the system frameworks (no vlc_*.h, which need the
 * build's config.h). Code that needs the core stays in Objective-C and hands
 * Swift what it needs (blocks, strings).
 * Used by MacLC.xcconfig (SWIFT_OBJC_BRIDGING_HEADER) and Makefile.am. */

#import <Cocoa/Cocoa.h>

#import "addons/MacLCAddons.h"
#import "addons/watch/MacLCWatchComponents.h"
