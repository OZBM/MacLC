/*****************************************************************************
 * MacLCCastController.h: Play on TV (Chromecast & AirPlay) controller
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
#import <AVFoundation/AVFoundation.h>
#import <AVKit/AVKit.h>

@class VLCRendererItem;

NS_ASSUME_NONNULL_BEGIN

extern NSString * const MacLCCastStateDidChangeNotification;

@interface MacLCCastController : NSObject

@property (class, readonly) MacLCCastController *sharedController;
- (void)start;   // Claude calls it once at app start-up (after the player exists)

// Chromecast & co. (VLC renderer discovery)
@property (readonly) NSArray<VLCRendererItem *> *rendererItems;  // discovered, sorted by name
@property (readonly) BOOL hasCastDevices;
- (void)playOnRendererItem:(nullable VLCRendererItem *)item;     // nil = This Mac
- (void)populateCastMenu:(NSMenu *)menu;   // "This Mac" + devices, radio-style checkmarks
- (NSButton *)makeCastButton;              // see Goal; menu pops up under the button on click

// AirPlay
@property (readonly) AVPlayer *airPlayPlayer;    // the ONE shared player
@property (readonly) BOOL hasAirPlayRoutes;      // AVRouteDetector.multipleRoutesDetected
- (NSView *)makeAirPlayButtonWithTint:(NSColor *)tint; // configured AVRoutePickerView

// State for status UI
@property (readonly, getter=isCasting) BOOL casting;
@property (readonly, nullable) NSString *destinationName; // "Living Room TV", nil when local
@property (readonly) BOOL destinationIsAirPlay;

@end

NS_ASSUME_NONNULL_END
