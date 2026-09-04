/*****************************************************************************
 * MacLCSettingsWindowController.h: Modern System Settings Window for MacLC
 *****************************************************************************
 * Copyright (C) 2026 VLC authors and VideoLAN
 *
 * Authors: MacLC Settings Team
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
#import <vlc_common.h>
#import <vlc_interface.h>

#import "settings/MacLCSettingsPane.h"

NS_ASSUME_NONNULL_BEGIN

@interface MacLCSettingsWindowController : NSWindowController

- (instancetype)initWithIntf:(intf_thread_t *)intf NS_DESIGNATED_INITIALIZER;
- (nullable instancetype)initWithCoder:(NSCoder *)coder NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithWindow:(nullable NSWindow *)window NS_UNAVAILABLE;

/**
 * Displays the settings window at the requested window level.
 */
- (void)showSettingsWindowWithLevel:(NSInteger)windowLevel;

/**
 * Selects a specific settings pane by its unique identifier.
 */
- (void)selectPaneWithIdentifier:(NSString *)identifier;

/**
 * Saves all modified settings across all registered panes.
 */
- (void)saveChangedSettings;

@end

NS_ASSUME_NONNULL_END
