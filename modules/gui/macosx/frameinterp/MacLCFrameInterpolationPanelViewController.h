/*****************************************************************************
 * MacLCFrameInterpolationPanelViewController.h: the motion interpolation popover
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
 * Motion interpolation within reach of the playback bar: the switch, the
 * method, the frame rate to aim for, and a line saying what that comes to for
 * the video playing right now. Every change applies immediately.
 */
@interface MacLCFrameInterpolationPanelViewController : NSViewController

/** Shows the panel in a popover anchored to a view, usually the frame rate
 *  badge. Toggles it closed when already shown there. */
+ (void)showRelativeToView:(NSView *)view preferredEdge:(NSRectEdge)edge;

+ (void)closePanel;

@end

NS_ASSUME_NONNULL_END
