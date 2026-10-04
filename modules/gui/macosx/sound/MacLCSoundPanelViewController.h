/*****************************************************************************
 * MacLCSoundPanelViewController.h
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

@interface MacLCSoundPanelViewController : NSViewController

/* Toggles the popover under (or above) the given Sound button. */
+ (void)showRelativeToView:(NSView *)view preferredEdge:(NSRectEdge)edge;
/* The same controls in a floating panel titled "Sound" (frame autosaved). */
+ (void)showPanel;
/* Sound buttons of the control bars register here (weakly) so that the menu
 * command can open the popover from the visible one, or the panel otherwise. */
+ (void)registerAnchorView:(NSView *)view;
+ (void)showFromMenu;

@end

NS_ASSUME_NONNULL_END
