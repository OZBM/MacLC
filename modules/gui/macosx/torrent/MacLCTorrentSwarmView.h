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

/* How a torrent reaches the screen, drawn from the module's live numbers:
 *   - the wider swarm: faint dots for everyone the trackers know about;
 *   - the peers this Mac is connected to, on two arcs: filled when they have
 *     the whole film (seeds), half filled when they have part of it, dashed
 *     while the connection opens; the ones sending data are joined to the Mac
 *     by a line that pieces travel along, as many as the download rate says;
 *   - before any peer: the trackers as pins coloured by their answer and the
 *     DHT search as a ring, without per-tracker text that could collide;
 *   - the film as a strip of pieces: what has arrived, where playback starts,
 *     the start buffer filling, the index at the end; arriving pieces drop
 *     from the Mac into the strip where they belong.
 * Always dark (it sits on video). Reduce Motion: no travelling pieces and no
 * radar, the same picture with cross-fades. Main thread only. */
@interface MacLCTorrentSwarmView : NSView

/// The latest numbers; call at about 4 Hz. Everything animates to them.
- (void)applyStage:(MacLCTorrentStage)stage
           torrent:(nullable MacLCTorrentInfo *)torrent
            reader:(nullable MacLCTorrentReaderInfo *)reader
          dhtNodes:(NSInteger)dhtNodes;

/// Continuous motion (travelling pieces, radar): off while hidden, occluded
/// or under Reduce Motion.
@property (nonatomic) BOOL animating;

@end

NS_ASSUME_NONNULL_END
