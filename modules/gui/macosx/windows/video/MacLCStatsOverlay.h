/*****************************************************************************
 * MacLCStatsOverlay.h: live playback figures and the Stats for Nerds panel
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

/// Posted on the main thread each time the figures below are measured again.
extern NSNotificationName const MacLCPlaybackMetricsDidChangeNotification;
/// Posted by the controls bar; the video view shows or hides the panel.
extern NSNotificationName const MacLCStatsOverlayToggleNotification;

/// Rates measured from the player's counters, about once a second. Unlike the
/// rate a file declares, these are what really happens: the frame rate of a
/// stream that declares none, and the pictures really shown once frames are
/// interpolated.
@interface MacLCPlaybackMetrics : NSObject

@property (class, readonly) MacLCPlaybackMetrics *sharedMetrics;

/// Frames decoded per second of media time; 0 until measured.
@property (readonly) double decodedFrameRate;
/// Pictures shown per second of wall time, interpolated ones included.
@property (readonly) double displayedFrameRate;
/// Late and lost pictures per second.
@property (readonly) double droppedFrameRate;
/// Bitrates in kbit/s.
@property (readonly) double inputBitrate;
@property (readonly) double demuxBitrate;

/// The declared frame rate rounded, or the measured one when the file
/// declares none; 0 while unknown.
@property (readonly) unsigned sourceFrameRate;
/// Same, unrounded where known (23.976).
@property (readonly) double exactSourceFrameRate;

/// Snaps a measured rate to the broadcast rate it is closest to (within 3 %).
+ (double)snappedFrameRate:(double)rate;

@end

/// A translucent panel of figures over the picture, like the one video sites
/// offer for the curious: source and shown frame rate, resolution, colour,
/// HDR, upscaling, audio and network.
@interface MacLCStatsOverlayView : NSView

/// Shows the panel in the top leading corner of host, or hides it.
+ (void)toggleInView:(NSView *)host topInset:(CGFloat)topInset;
+ (BOOL)isShown;

@end

NS_ASSUME_NONNULL_END
