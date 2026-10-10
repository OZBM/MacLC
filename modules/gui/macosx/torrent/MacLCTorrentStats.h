/*****************************************************************************
 * MacLCTorrentStats.h: what the BitTorrent module says about a download, as
 * objects the interface can draw (parsing, derived values, wording)
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

/* Foundation only: the unit tests link this file on its own
 * (tests/MacLCTorrentStatsTest.m, with fixture JSON).
 *
 * The module (modules/access/bittorrent) answers -[MacLCTorrentMonitor poll]
 * with a JSON snapshot; its shape is written in
 * .agents/reports/spec-torrent-engine.md, section "Snapshot". The keys map to
 * the properties below by their camelCase names ("peers_connecting" →
 * peersConnecting, "first_data_ms" → firstDataInterval in seconds...); each
 * property says which key it reads. Unknown keys are ignored, missing keys
 * leave zero / empty / -1 as documented, a value of the wrong type is treated
 * as missing, never an exception. Version: "v" must be 1; another version
 * parses to nil. */
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, MacLCTorrentStage) {
    MacLCTorrentStageUnknown = 0,
    /// "trackers": asking trackers and the DHT who has it; no peer yet.
    MacLCTorrentStageTrackers,
    /// "metadata": peers answered, the list of files is on its way.
    MacLCTorrentStageMetadata,
    /// "connecting": the files are known, finding peers that send data.
    MacLCTorrentStageConnecting,
    /// "downloading": data is arriving, nothing reads it yet.
    MacLCTorrentStageDownloading,
    /// "buffering": filling the start buffer (reader's `need`).
    MacLCTorrentStageBuffering,
    /// "ready": buffer full, the player is about to start.
    MacLCTorrentStageReady,
    /// "playing": the reader is reading, data ahead.
    MacLCTorrentStagePlaying,
    /// "stalled": a read has waited for a piece for a while.
    MacLCTorrentStageStalled,
    /// "error".
    MacLCTorrentStageFailed,
};

/// nil or an unknown word: MacLCTorrentStageUnknown.
MacLCTorrentStage MacLCTorrentStageFromString(NSString * _Nullable string);

#pragma mark - Pieces of a snapshot

typedef NS_ENUM(NSInteger, MacLCTorrentTrackerState) {
    MacLCTorrentTrackerStateIdle,      // "idle"
    MacLCTorrentTrackerStateUpdating,  // "updating"
    MacLCTorrentTrackerStateOK,        // "ok"
    MacLCTorrentTrackerStateError,     // "error"
};

@interface MacLCTorrentTrackerInfo : NSObject
@property (readonly, copy) NSString *URL;            // "url"
/// "tracker.opentrackr.org", from URL (the part a person recognises).
@property (readonly, copy) NSString *host;
@property (readonly) MacLCTorrentTrackerState state; // "state"
@property (readonly) NSInteger peers;                // "peers", -1 unknown
@property (readonly, copy) NSString *message;        // "message", "" when none
@end

/// One torrent of the session.
@interface MacLCTorrentInfo : NSObject
@property (readonly, copy) NSString *key;            // "key": lowercase hex of the info hash
@property (readonly, copy) NSString *name;           // "name", "" until known
@property (readonly) MacLCTorrentStage stage;        // "stage"
@property (readonly, copy) NSString *error;          // "error", "" when none
@property (readonly) uint64_t size;                  // "size" bytes, 0 until the metadata is known
@property (readonly) NSInteger pieceCount;           // "pieces"
@property (readonly) uint64_t pieceSize;             // "piece_size"
/// Connected peers, seeds included ("peers"), and the seeds among them ("seeds").
@property (readonly) NSInteger peers;
@property (readonly) NSInteger seeds;
@property (readonly) NSInteger peersConnecting;      // "peers_connecting": TCP/uTP being opened
@property (readonly) NSInteger peersHandshaking;     // "peers_handshaking"
@property (readonly) NSInteger peersUnchoked;        // "peers_unchoked": peers that send us data now
/// What the trackers say about the whole swarm ("swarm_seeds", "swarm_leechers"), -1 unknown.
@property (readonly) NSInteger swarmSeeds;
@property (readonly) NSInteger swarmLeechers;
/// Where the peers came from: "sources": {"tracker","dht","pex","lsd","incoming"}.
@property (readonly) NSInteger peersFromTrackers;
@property (readonly) NSInteger peersFromDHT;
@property (readonly) NSInteger peersFromPeerExchange;
@property (readonly) NSInteger peersFromLocalNetwork;
@property (readonly) NSInteger peersIncoming;
@property (readonly, copy) NSArray<MacLCTorrentTrackerInfo *> *trackers;   // "trackers", at most 8
@property (readonly) int64_t downloadRate;           // "down" bytes/s of payload
@property (readonly) int64_t uploadRate;             // "up"
@property (readonly) uint64_t downloaded;            // "downloaded" bytes since added
@property (readonly) uint64_t uploaded;              // "uploaded"
/// Seconds since the session got this torrent ("uptime_ms"), and until the
/// first verified piece ("first_data_ms"), -1 when none yet.
@property (readonly) NSTimeInterval uptime;
@property (readonly) NSTimeInterval firstDataInterval;
@end

/// One file being read (played) from a torrent.
@interface MacLCTorrentReaderInfo : NSObject
@property (readonly, copy) NSString *torrentKey;     // "torrent"
@property (readonly, copy) NSString *fileName;       // "file": path inside the torrent
@property (readonly) uint64_t size;                  // "size"
@property (readonly) uint64_t position;              // "pos": where the reader is
/// Verified bytes in a row from `position` ("ahead").
@property (readonly) uint64_t ahead;
/// Verified byte ranges of the file, merged and sorted, as [start, end)
/// pairs ("ranges"), at most 128.
@property (readonly, copy) NSArray<NSArray<NSNumber *> *> *ranges;
@property (readonly) uint64_t windowEnd;             // "window_end": end of the part being fetched first
@property (readonly) MacLCTorrentStage stage;        // "stage"
/// Bytes that must be ahead before playback may start ("need"); 0 when no gate.
@property (readonly) uint64_t need;
/// Bytes per second the player consumes, smoothed ("rate_in"); 0 unknown.
@property (readonly) int64_t consumeRate;
/// How long the read in progress has been waiting for data ("stall_ms"), seconds; 0 when it is not waiting.
@property (readonly) NSTimeInterval stallDuration;

/// (position + ahead) / size, 0...1: where the download head is on the seek bar.
@property (readonly) double headFraction;
/// position / size.
@property (readonly) double positionFraction;
/// ranges as fractions of size: [s0, e0, s1, e1, ...], each 0...1.
@property (readonly, copy) NSArray<NSNumber *> *rangeFractions;
/// Seconds of media ahead of the player: ahead / consumeRate when the rate is
/// known, else ahead / (size / 6000 s), i.e. an average film of 100 minutes.
@property (readonly) NSTimeInterval aheadSeconds;
/// Buffering progress, ahead / need clamped 0...1; 1 when need is 0.
@property (readonly) double bufferProgress;
/// Seconds until `need` bytes are ahead at the torrent's current download
/// rate; negative when unknown (no rate) or already there.
- (NSTimeInterval)secondsToFillWithDownloadRate:(int64_t)downloadRate;
@end

#pragma mark - Snapshot

@interface MacLCTorrentSnapshot : NSObject
/// nil, and *error, when data is not a snapshot of version 1.
+ (nullable instancetype)snapshotFromJSONData:(NSData *)data error:(NSError * _Nullable * _Nullable)error;
/// Empty snapshot (no torrent), for "nothing is happening".
+ (instancetype)emptySnapshot;

/// DHT nodes known ("dht_nodes"), -1 unknown.
@property (readonly) NSInteger dhtNodes;
/// The torrent that most recently got a user ("active"); "" none.
@property (readonly, copy) NSString *activeKey;
@property (readonly, copy) NSArray<MacLCTorrentInfo *> *torrents;
@property (readonly, copy) NSArray<MacLCTorrentReaderInfo *> *readers;
/// The module's clock when it built the snapshot ("now_ms", seconds).
@property (readonly) NSTimeInterval moduleTime;

- (nullable MacLCTorrentInfo *)torrentForKey:(NSString *)key;
/// The active torrent, else the last one; nil when none.
@property (readonly, nullable) MacLCTorrentInfo *activeTorrent;
/// The reader of the active torrent with the largest file (the video, not an
/// external audio track or a subtitle); nil when none.
@property (readonly, nullable) MacLCTorrentReaderInfo *primaryReader;
@end

#pragma mark - Wording

/// Wording shared by every view, so that the loading screen, the seek bar's
/// marker and the popover say the same thing. English; short; no jargon in the
/// titles (the explanations may name peers and seeds, and say what they are).
@interface MacLCTorrentFormat : NSObject
/// "4.2 MB/s", "820 KB/s", "0 KB/s" (decimal units, one decimal under 10).
+ (NSString *)rateString:(int64_t)bytesPerSecond;
/// "1.4 GB", "512 MB", "3.2 MB", "40 KB".
+ (NSString *)sizeString:(uint64_t)bytes;
/// "45 s", "2 min 5 s", "1 h 3 min"; "" for a negative value.
+ (NSString *)durationString:(NSTimeInterval)seconds;
/// "About 40 s left", "Less than a minute left", "" when unknown.
+ (NSString *)remainingString:(NSTimeInterval)seconds;

/// The step's name: Trackers "Finding peers", Metadata "Getting the file list",
/// Connecting "Connecting to peers", Downloading "Receiving data", Buffering
/// "Filling the buffer", Ready "Starting", Playing "Playing", Stalled "Buffering",
/// Failed "Can't download". Unknown: "".
+ (NSString *)titleForStage:(MacLCTorrentStage)stage;
/// One sentence saying what is happening and why it takes time, with the
/// numbers the torrent has now. Examples:
///   Trackers:    "Asking the trackers and the network who has this."
///   Metadata:    "5 peers answered. Asking them for the list of files."
///   Connecting:  "Found the files. Connecting to 12 of 38 peers."
///   Buffering:   "Downloading the first 24 MB so playback won't stop: 61 % there, about 8 s left."
///   Stalled:     "Waiting for the next part: 3 peers are sending data."
/// reader may be nil.
+ (NSString *)explanationForTorrent:(MacLCTorrentInfo *)torrent
                             reader:(nullable MacLCTorrentReaderInfo *)reader;
/// "14 peers · 6 seeds" (singular forms handled: "1 peer", "1 seed").
+ (NSString *)peersString:(MacLCTorrentInfo *)torrent;
@end

NS_ASSUME_NONNULL_END
