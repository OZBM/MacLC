/*****************************************************************************
 * MacLCTorrentMonitor.h: asks the BitTorrent module what it is doing, while a
 * torrent plays, and tells the views
 *****************************************************************************
 * Copyright (C) 2026 Hazen Studio
 *
 * This program is free software; you can redistribute it and/or modify it
 * under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation; either version 2.1 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin Street, Fifth Floor, Boston MA 02110-1301, USA.
 *****************************************************************************/

/* Main thread only. Lives in the interface process (libvlc, the player
 * controller); not part of the unit tests (MacLCTorrentStats is).
 *
 * How it talks to the module. The module (a plugin of this process) creates
 * a variable of type address named "maclc-bt-snapshot" on the libvlc instance
 * object, holding a function `char *(*)(void)` that returns a malloc'd UTF-8
 * JSON snapshot (see the spec); the caller frees it with free(). The monitor
 * reads it with var_Type() / var_GetAddress() on vlc_object_instance(getIntf())
 * every 250 ms while a torrent is active, never otherwise (a stopped player
 * costs nothing). Before the module ever opened a torrent the variable does
 * not exist: nothing active.
 *
 * It also tells the module that an interface draws the progress itself, so
 * the module stops showing its own progress dialogs: on first -start it
 * creates the boolean variable "maclc-bt-gui" on the libvlc instance and sets
 * it true (var_Create is idempotent for the same type); on -stop or
 * termination it sets it false.
 *
 * "A torrent is active" means: the player's current media (or the media being
 * opened) has an MRL that starts with "magnet:" or "magnet://", or contains
 * ".torrent", or has an info hash that the snapshot lists as a torrent of
 * the active key; evaluated on VLCPlayerCurrentMediaItemChanged and
 * VLCPlayerStateChanged. When the player stops and the snapshot has no reader
 * left, the monitor goes inactive after 2 s and stops polling.
 *
 * The torrent and reader it exposes are the ones of the current media:
 *  - torrent: the snapshot's torrent whose key is in the MRL (hex info hash
 *    after "btih:"; a 32-character base32 hash is converted), else the
 *    snapshot's activeTorrent;
 *  - reader: among that torrent's readers, the one whose fileName's last path
 *    component equals the MRL's fragment after "#!/" (percent-decoded), else
 *    snapshot.primaryReader. */
#import <Foundation/Foundation.h>

#import "torrent/MacLCTorrentStats.h"

NS_ASSUME_NONNULL_BEGIN

/// Posted on the main queue each time a new snapshot was read while a torrent
/// is active (about 4 per second), and once more when it becomes inactive.
/// object: the monitor.
extern NSNotificationName const MacLCTorrentMonitorDidUpdateNotification;

@interface MacLCTorrentMonitor : NSObject

@property (class, readonly) MacLCTorrentMonitor *sharedMonitor;

/// Idempotent. Starts listening to the player and creates "maclc-bt-gui".
/// The first view that wants torrent data calls it (the controls bar does so
/// when it loads).
- (void)start;

/// YES from the moment the current media is a torrent until 2 s after it ends.
@property (readonly, getter=isActive) BOOL active;
@property (readonly, nullable) MacLCTorrentSnapshot *snapshot;
@property (readonly, nullable) MacLCTorrentInfo *torrent;
@property (readonly, nullable) MacLCTorrentReaderInfo *reader;
/// Download rate of the torrent, bytes/s, one sample per second, oldest first,
/// at most 60: for a sparkline.
@property (readonly, copy) NSArray<NSNumber *> *rateHistory;
/// The stage to show now: the reader's when there is one, else the torrent's.
@property (readonly) MacLCTorrentStage stage;

/// Reads one snapshot now, whatever the timer (used by the debug hook and
/// by tests of the views). Posts the notification. Returns the snapshot.
- (nullable MacLCTorrentSnapshot *)pollNow;

/// Developer hook for tests of the views without a network: while set, polling
/// returns this JSON instead of asking the module (MACLC_DEBUG_TORRENT_FIXTURE
/// = path of a file holding a snapshot, re-read on every poll, so a script can
/// rewrite it to animate the stages). Read once at -start.
@property (readonly, copy, nullable) NSString *fixturePath;

@end

NS_ASSUME_NONNULL_END
