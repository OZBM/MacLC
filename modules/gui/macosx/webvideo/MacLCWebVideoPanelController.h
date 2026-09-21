/*****************************************************************************
 * MacLCWebVideoPanelController.h: open web video panel
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

@interface MacLCWebVideoPanelController : NSWindowController

@property (class, readonly) MacLCWebVideoPanelController *sharedController;

- (void)showPanel;
- (void)showPanelWithAddress:(nullable NSString *)address;

/**
 * Same, but plays the address as soon as it resolves, without waiting for a
 * key. Used by the headless interface checks.
 */
- (void)showPanelWithAddress:(nullable NSString *)address
            playWhenResolved:(BOOL)playWhenResolved;

@end

NS_ASSUME_NONNULL_END
