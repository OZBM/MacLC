/*****************************************************************************
 * MacLCTorrentSwarmView.h: MacOS X interface module
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

#import "torrent/MacLCTorrentStats.h"

NS_ASSUME_NONNULL_BEGIN

/* The heart of the torrent loading screen, drawn from the module's live
 * numbers:
 *   - a dial of 60 ticks, the start buffer: ticks light up as its pieces are
 *     verified, in the order they really arrive (BitTorrent fetches pieces
 *     out of order, so a few light up ahead of the bright run that playback
 *     can already use);
 *   - before any data the dial waits: a light sweeps around it and the
 *     step's symbol sits in the middle;
 *   - the peers this Mac is connected to orbit the dial: seeds filled, peers
 *     with part of the film ringed, connections still opening dashed and
 *     pulsing; the ones sending data glow and send pieces into the dial, as
 *     many as the download rate says;
 *   - the rest of the swarm the trackers know about: faint dust further out;
 *   - in the middle: how full the start buffer is and the download rate, the
 *     play symbol once it is full, a warning when the download failed.
 * Always dark (it sits on video). Reduce Motion: no sweep, no travelling
 * pieces, no rotation, the same picture with cross-fades. Main thread only. */
@interface MacLCTorrentSwarmView : NSView

/// The latest numbers; call at about 4 Hz. Everything animates to them.
- (void)applyStage:(MacLCTorrentStage)stage
           torrent:(nullable MacLCTorrentInfo *)torrent
            reader:(nullable MacLCTorrentReaderInfo *)reader
          dhtNodes:(NSInteger)dhtNodes;

/// Forgets the previous torrent (no peer, an empty dial); the next
/// -applyStage... draws the dial on.
- (void)reset;

/// Continuous motion (sweep, orbit, travelling pieces, pulses): off while
/// hidden, occluded or under Reduce Motion.
@property (nonatomic) BOOL animating;

@end

NS_ASSUME_NONNULL_END
