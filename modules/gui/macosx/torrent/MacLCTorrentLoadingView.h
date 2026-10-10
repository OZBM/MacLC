/*****************************************************************************
 * MacLCTorrentLoadingView.h: the animated "your torrent is opening" screen
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
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston MA 02110-1301, USA.
 *****************************************************************************/

/* Main thread only.
 *
 * While a torrent opens, the picture area tells the story of what happens, in
 * the order it happens, with the numbers the BitTorrent module reports:
 *   1. Finding peers      a radar: trackers and DHT nodes answer
 *   2. Getting the files  peers fly in, the list of files fills
 *   3. Connecting         lines to the peers; data flows along the ones
 *                         that send
 *   4. Receiving / Filling the buffer
 *                         the film as a strip, the start buffer filling
 *   5. Starting           everything converges and fades into the picture
 * Once playback has started, a stall shows a small capsule instead.
 *
 * Everything sits on video, so the view is always dark. Reduce Motion: the
 * same drawings without pulses, particles or flights (cross-fades only);
 * Reduce Transparency: an opaque dark backdrop; VoiceOver: one element whose
 * value is the step and its explanation, with Cancel as its only child. */
#import <Cocoa/Cocoa.h>

#import "torrent/MacLCTorrentStats.h"

NS_ASSUME_NONNULL_BEGIN

@interface MacLCTorrentLoadingView : NSView

/// Called by the Cancel button (the controller stops the player).
@property (copy, nullable) void (^cancelHandler)(void);
/// The controls the compact capsule must stay clear of: it sits 16 pt above
/// this view's top edge, whatever the layout.
@property (weak, nullable) NSView *avoidedView;
/// "Night of the Living Dead" and "S1, E2 · Pilot".
@property (nonatomic, copy, nullable) NSString *titleText;
@property (nonatomic, copy, nullable) NSString *episodeText;
/// Blurred behind the animation; nil for a dark gradient.
@property (nonatomic, nullable, strong) NSURL *backdropURL;
/// Cancel reads "Close" once the download failed.
@property (readonly) BOOL showsFailure;

/// The full screen (steps 1-5) or the stall capsule, with the data to show.
/// Both take the latest values and animate to them; call at about 4 Hz.
- (void)showFullWithStage:(MacLCTorrentStage)stage
                  torrent:(nullable MacLCTorrentInfo *)torrent
                   reader:(nullable MacLCTorrentReaderInfo *)reader
                 dhtNodes:(NSInteger)dhtNodes;
- (void)showStallWithTorrent:(nullable MacLCTorrentInfo *)torrent
                      reader:(nullable MacLCTorrentReaderInfo *)reader;
/// Nothing visible (no animation runs).
- (void)hideAnimated:(BOOL)animated;
@property (readonly, getter=isPresenting) BOOL presenting;

@end

/// Follows MacLCTorrentMonitor and the player, and shows the right thing in
/// the right place: over the video view (above the video, below the controls)
/// when that view is on screen, else - the library window shows its video only
/// once the tracks exist - over the library window's content area.
/// MACLC_DEBUG_TORRENT_OVERLAY=1 together with MACLC_DEBUG_TORRENT_FIXTURE
/// shows it without a playing input.
@interface MacLCTorrentLoadingController : NSObject

/// hostView: the video controller's view; controlsView: its controls
/// (the overlay goes just below it); avoidedView: the bar the compact
/// capsule stays above.
- (instancetype)initWithHostView:(NSView *)hostView
                    controlsView:(nullable NSView *)controlsView
                     avoidedView:(nullable NSView *)avoidedView NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithHostView:(NSView *)hostView controlsView:(nullable NSView *)controlsView;
- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
