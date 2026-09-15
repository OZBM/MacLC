/*****************************************************************************
 * MacLCHDRPanelViewController.h: MacLC's HDR options popover
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
 * The HDR panel (DESIGN_SPEC §10.2): which formats the video carries and
 * which one MacLC recommends, the picture mode with its tone curve and
 * trade-offs, what the display can do, and brightness advice. Every choice
 * applies immediately through MacLCHDRController.
 */
@interface MacLCHDRPanelViewController : NSViewController

/** Shows the panel in a popover anchored to a view (the HDR badge, the
 *  card's Options button...). Toggles it closed when already shown there. */
+ (void)showRelativeToView:(NSView *)view preferredEdge:(NSRectEdge)edge;

/** Shows the panel anchored to a rectangle of a view (e.g. where the HDR card
 *  was, as the card goes away). */
+ (void)showRelativeToRect:(NSRect)rect ofView:(NSView *)view preferredEdge:(NSRectEdge)edge;

/** Shows the panel anchored to the key window's content (menu command). */
+ (void)showForKeyWindow;

+ (void)closePanel;

@end

NS_ASSUME_NONNULL_END
