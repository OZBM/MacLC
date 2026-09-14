/*****************************************************************************
 * MacLCHDRSettingsViewController.h: HDR & Colour settings pane for MacLC
 *****************************************************************************
 * Copyright (C) 2026 VLC authors and VideoLAN
 *
 * Authors: MacLC Team
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
#import "settings/MacLCSettingsPane.h"

#include <vlc_common.h>
#include <vlc_interface.h>

NS_ASSUME_NONNULL_BEGIN

/// Posted whenever the SDR to HDR expansion is switched on or off, by this
/// pane or by the button on the video controls bar, so that both stay in step.
extern NSString * const MacLCHDRExpansionChangedNotification;

@interface MacLCHDRSettingsViewController : NSViewController <MacLCSettingsPane>

- (instancetype)initWithIntf:(intf_thread_t *)intf NS_DESIGNATED_INITIALIZER;
- (nullable instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;
- (instancetype)initWithNibName:(nullable NSNibName)nibNameOrNil bundle:(nullable NSBundle *)nibBundleOrNil NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
