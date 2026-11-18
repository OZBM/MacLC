/*****************************************************************************
 * MacLCNestedScrollRouter.h: trackpad gestures over shelves inside a page
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

/// Gives each trackpad scroll gesture that starts over a horizontal shelf
/// inside a vertically scrolling page (collection view orthogonal sections,
/// the Watch services bar) to one scroll view for its whole length: the
/// shelf when the fingers move sideways, the page otherwise.
///
/// AppKit decides event by event instead: the shelf scrolls on the main
/// thread and hands on each event it cannot use, while the page tracks the
/// gestures it receives on a thread of its own. The first event of a
/// slanted swipe can go to the page and the rest to the shelf, so one
/// gesture ends up split between two scroll views.
@interface MacLCNestedScrollRouter : NSObject

/// Call from -[NSWindow sendEvent:] for scroll wheel events. YES when the
/// router delivered or holds the event: the window must not send it then.
- (BOOL)routeScrollEvent:(NSEvent *)event inWindow:(NSWindow *)window;

@end

NS_ASSUME_NONNULL_END
