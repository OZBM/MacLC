/*****************************************************************************
 * MacLCTorrentBufferViews.h: the download head on the seek bar (marker and
 * details card), and the downloaded-ranges overlay of the Now Playing bar
 *****************************************************************************
 * Copyright (C) 2026 Hazen Studio
 *
 * This program is free software; you can redistribute it and/or modify it
 * under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin Street, Fifth Floor, Boston MA 02110-1301, USA.
 *****************************************************************************/

/* Main thread only. The data comes from MacLCTorrentMonitor (torrent/); the
 * seek bar itself (ranges, glowing head) is drawn by
 * VLCPlaybackProgressSliderCell. */
#import <Cocoa/Cocoa.h>

@class MacLCTorrentMonitor;
@class MacLCTorrentInfo;

NS_ASSUME_NONNULL_BEGIN

/// A small dark capsule floating just below the seek bar (above it when
/// there is no room below) at the download head ("4.2 MB/s" and an arrow that bounces, or a ring that fills when the
/// player waits for data). With the pointer within 40 pt of the head on the
/// bar, or after a click on it, it grows into a card: speed with a sparkline,
/// peers and seeds, how far ahead the picture is buffered, how much of the
/// file is on disk, and the step's name while the film is not playing yet.
///
/// It lives in a borderless child window of the slider's window (like the
/// slider's hover time capsule) and shows only while the slider is on screen,
/// the controls bar is visible (it follows the alpha of the slider's
/// ancestors), the torrent is active and not fully downloaded. While the
/// pointer is on the bar far from the head it steps aside, so that it never
/// covers the hover time capsule; the expanded card sits above that capsule.
/// The owner (the controls bar) keeps it alive; it holds the slider weakly
/// and retains nothing of the owner. It never touches the player.
@interface MacLCTorrentHeadMarker : NSObject

/// The slider must be a VLCPlaybackProgressSlider-like control whose cell
/// answers -barRectFlipped: with the whole track (the marker maps the head
/// fraction on it, as the slider's hover time does).
- (instancetype)initWithSlider:(NSSlider *)slider;

/// Feed with the monitor on each MacLCTorrentMonitorDidUpdateNotification.
- (void)updateWithMonitor:(MacLCTorrentMonitor *)monitor;

/// Called by the slider. x is in the slider's own coordinates.
- (void)sliderPointerMovedToX:(CGFloat)x hoverVisible:(BOOL)hoverVisible;
- (void)sliderPointerExited;
/// The slider moved to another window or out of every window.
- (void)sliderDidMoveToWindow;

/// Hides the window and stops observing; the marker is inert afterwards.
- (void)invalidate;

@property (readonly) BOOL shown;

/// Views (the elapsed / remaining time labels) the compact pill keeps clear
/// of; held weakly. The pill sits below the track, between them.
@property (nonatomic, copy, nullable) NSArray<NSView *> *avoidViews;

/// "Downloading · 4.2 MB/s · 14 peers" (tooltips).
+ (NSString *)summaryForTorrent:(MacLCTorrentInfo *)torrent;
/// "4.2 megabytes per second" (VoiceOver).
+ (NSString *)spokenRateString:(int64_t)bytesPerSecond;

@end

/// Downloaded ranges and a static head dot, drawn over the plain NSSlider of
/// the Now Playing bar (the part not yet played only). Pass-through for mouse
/// events; give it the slider's frame.
@interface MacLCTorrentTrackOverlay : NSView

/// Flattened fractions [s0, e0, s1, e1, ...], 0...1.
@property (nonatomic, copy, nullable) NSArray<NSNumber *> *ranges;
/// 0...1, < 0 for none.
@property (nonatomic) double headFraction;
/// The slider this overlay sits on, for its geometry.
@property (nonatomic, weak, nullable) NSSlider *slider;

@end

NS_ASSUME_NONNULL_END
