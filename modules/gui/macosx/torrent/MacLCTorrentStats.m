/*****************************************************************************
 * MacLCTorrentStats.m: what the BitTorrent module says about a download, as
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

#import "torrent/MacLCTorrentStats.h"

#include <math.h>

static NSErrorDomain const MacLCTorrentStatsErrorDomain = @"MacLCTorrentStatsErrorDomain";

/* Helpers shared with MacLCTorrentMonitor.m and the tests (declared again
 * there: the test bundle links this file alone). */
NSString * _Nullable MacLCTorrentHexFromBase32(NSString * _Nullable base32);
NSString * _Nullable MacLCTorrentKeyFromMRL(NSString * _Nullable mrl);
NSString * _Nullable MacLCTorrentFileNameFromMRL(NSString * _Nullable mrl);

static const NSInteger kMaxRanges = 128;
static const NSInteger kMaxTrackers = 8;
/* An average film of 100 minutes, to turn bytes into seconds of media when
 * the player's own rate is not known yet. */
static const double kAverageFilmSeconds = 6000.0;

#pragma mark - Total JSON accessors (a wrong type is a missing key)

static BOOL IsBool(id value)
{
    return [value isKindOfClass:NSNumber.class]
        && CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID();
}

static NSDictionary *DictOf(id value)
{
    return [value isKindOfClass:NSDictionary.class] ? value : nil;
}

static NSArray *ArrayOf(id value)
{
    return [value isKindOfClass:NSArray.class] ? value : nil;
}

static NSNumber *NumberOf(id value)
{
    if (![value isKindOfClass:NSNumber.class] || IsBool(value))
        return nil;
    return isfinite([value doubleValue]) ? value : nil;
}

static NSString *StringIn(NSDictionary *dict, NSString *key)
{
    id value = dict[key];
    return [value isKindOfClass:NSString.class] ? value : @"";
}

static int64_t Int64In(NSDictionary *dict, NSString *key, int64_t fallback)
{
    NSNumber *number = NumberOf(dict[key]);
    if (number == nil)
        return fallback;
    double d = number.doubleValue;
    /* A double outside the range would be undefined behaviour to convert. */
    if (d >= 9.2e18)
        return INT64_MAX;
    if (d <= -9.2e18)
        return INT64_MIN;
    return (int64_t)d;
}

static uint64_t UInt64In(NSDictionary *dict, NSString *key)
{
    NSNumber *number = NumberOf(dict[key]);
    if (number == nil)
        return 0;
    double d = number.doubleValue;
    if (d <= 0)
        return 0;
    if (d >= 1.8e19)
        return UINT64_MAX;
    return (uint64_t)d;
}

static NSInteger IntegerIn(NSDictionary *dict, NSString *key, NSInteger fallback)
{
    int64_t value = Int64In(dict, key, fallback);
    if (value > NSIntegerMax)
        return NSIntegerMax;
    if (value < NSIntegerMin)
        return NSIntegerMin;
    return (NSInteger)value;
}

/// A duration in milliseconds as seconds; `fallback` when missing or negative.
static NSTimeInterval SecondsIn(NSDictionary *dict, NSString *key, NSTimeInterval fallback)
{
    NSNumber *number = NumberOf(dict[key]);
    if (number == nil || number.doubleValue < 0)
        return fallback;
    return number.doubleValue / 1000.0;
}

#pragma mark - Stage

MacLCTorrentStage MacLCTorrentStageFromString(NSString *string)
{
    if (![string isKindOfClass:NSString.class])
        return MacLCTorrentStageUnknown;
    static NSDictionary<NSString *, NSNumber *> *stages;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        stages = @{
            @"trackers": @(MacLCTorrentStageTrackers),
            @"metadata": @(MacLCTorrentStageMetadata),
            @"connecting": @(MacLCTorrentStageConnecting),
            @"downloading": @(MacLCTorrentStageDownloading),
            @"buffering": @(MacLCTorrentStageBuffering),
            @"ready": @(MacLCTorrentStageReady),
            @"playing": @(MacLCTorrentStagePlaying),
            @"stalled": @(MacLCTorrentStageStalled),
            @"error": @(MacLCTorrentStageFailed),
        };
    });
    NSNumber *stage = stages[string];
    return stage != nil ? (MacLCTorrentStage)stage.integerValue : MacLCTorrentStageUnknown;
}

#pragma mark - Tracker

@interface MacLCTorrentTrackerInfo ()
@property (readwrite, copy) NSString *URL;
@property (readwrite, copy) NSString *host;
@property (readwrite) MacLCTorrentTrackerState state;
@property (readwrite) NSInteger peers;
@property (readwrite, copy) NSString *message;
@end

@implementation MacLCTorrentTrackerInfo

- (instancetype)initWithDictionary:(NSDictionary *)dict
{
    self = [super init];
    if (self) {
        _URL = [StringIn(dict, @"url") copy];
        _host = [MacLCTorrentTrackerInfo hostFromURLString:_URL];
        NSString *state = StringIn(dict, @"state");
        if ([state isEqualToString:@"updating"])
            _state = MacLCTorrentTrackerStateUpdating;
        else if ([state isEqualToString:@"ok"])
            _state = MacLCTorrentTrackerStateOK;
        else if ([state isEqualToString:@"error"])
            _state = MacLCTorrentTrackerStateError;
        else
            _state = MacLCTorrentTrackerStateIdle;
        _peers = IntegerIn(dict, @"peers", -1);
        _message = [StringIn(dict, @"message") copy];
    }
    return self;
}

/// "udp://tracker.opentrackr.org:1337/announce" → "tracker.opentrackr.org".
/// NSURL refuses some addresses that trackers use (spaces, bare IPv6), so
/// the host is cut by hand.
+ (NSString *)hostFromURLString:(NSString *)URL
{
    NSString *rest = URL;
    NSRange scheme = [rest rangeOfString:@"://"];
    if (scheme.location != NSNotFound)
        rest = [rest substringFromIndex:NSMaxRange(scheme)];
    NSRange end = [rest rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"/?#"]];
    if (end.location != NSNotFound)
        rest = [rest substringToIndex:end.location];
    NSRange at = [rest rangeOfString:@"@" options:NSBackwardsSearch];
    if (at.location != NSNotFound)
        rest = [rest substringFromIndex:NSMaxRange(at)];
    if ([rest hasPrefix:@"["]) {
        NSRange close = [rest rangeOfString:@"]"];
        if (close.location != NSNotFound)
            return [rest substringWithRange:NSMakeRange(1, close.location - 1)];
        return rest;
    }
    NSRange colon = [rest rangeOfString:@":"];
    if (colon.location != NSNotFound)
        rest = [rest substringToIndex:colon.location];
    return rest;
}

@end

#pragma mark - Torrent

@interface MacLCTorrentInfo ()
@property (readwrite, copy) NSString *key;
@property (readwrite, copy) NSString *name;
@property (readwrite) MacLCTorrentStage stage;
@property (readwrite, copy) NSString *error;
@property (readwrite) uint64_t size;
@property (readwrite) NSInteger pieceCount;
@property (readwrite) uint64_t pieceSize;
@property (readwrite) NSInteger peers;
@property (readwrite) NSInteger seeds;
@property (readwrite) NSInteger peersConnecting;
@property (readwrite) NSInteger peersHandshaking;
@property (readwrite) NSInteger peersUnchoked;
@property (readwrite) NSInteger swarmSeeds;
@property (readwrite) NSInteger swarmLeechers;
@property (readwrite) NSInteger peersFromTrackers;
@property (readwrite) NSInteger peersFromDHT;
@property (readwrite) NSInteger peersFromPeerExchange;
@property (readwrite) NSInteger peersFromLocalNetwork;
@property (readwrite) NSInteger peersIncoming;
@property (readwrite, copy) NSArray<MacLCTorrentTrackerInfo *> *trackers;
@property (readwrite) int64_t downloadRate;
@property (readwrite) int64_t uploadRate;
@property (readwrite) uint64_t downloaded;
@property (readwrite) uint64_t uploaded;
@property (readwrite) NSTimeInterval uptime;
@property (readwrite) NSTimeInterval firstDataInterval;
@end

@implementation MacLCTorrentInfo

- (instancetype)initWithDictionary:(NSDictionary *)dict
{
    self = [super init];
    if (self) {
        _key = [StringIn(dict, @"key").lowercaseString copy];
        _name = [StringIn(dict, @"name") copy];
        _stage = MacLCTorrentStageFromString(dict[@"stage"]);
        _error = [StringIn(dict, @"error") copy];
        _size = UInt64In(dict, @"size");
        _pieceCount = MAX(IntegerIn(dict, @"pieces", 0), 0);
        _pieceSize = UInt64In(dict, @"piece_size");
        _peers = MAX(IntegerIn(dict, @"peers", 0), 0);
        _seeds = MAX(IntegerIn(dict, @"seeds", 0), 0);
        _peersConnecting = MAX(IntegerIn(dict, @"peers_connecting", 0), 0);
        _peersHandshaking = MAX(IntegerIn(dict, @"peers_handshaking", 0), 0);
        _peersUnchoked = MAX(IntegerIn(dict, @"peers_unchoked", 0), 0);
        _swarmSeeds = MAX(IntegerIn(dict, @"swarm_seeds", -1), -1);
        _swarmLeechers = MAX(IntegerIn(dict, @"swarm_leechers", -1), -1);

        NSDictionary *sources = DictOf(dict[@"sources"]);
        _peersFromTrackers = MAX(IntegerIn(sources, @"tracker", 0), 0);
        _peersFromDHT = MAX(IntegerIn(sources, @"dht", 0), 0);
        _peersFromPeerExchange = MAX(IntegerIn(sources, @"pex", 0), 0);
        _peersFromLocalNetwork = MAX(IntegerIn(sources, @"lsd", 0), 0);
        _peersIncoming = MAX(IntegerIn(sources, @"incoming", 0), 0);

        NSMutableArray *trackers = [NSMutableArray array];
        for (id entry in ArrayOf(dict[@"trackers"])) {
            NSDictionary *tracker = DictOf(entry);
            if (tracker == nil)
                continue;
            [trackers addObject:[[MacLCTorrentTrackerInfo alloc] initWithDictionary:tracker]];
            if ((NSInteger)trackers.count >= kMaxTrackers)
                break;
        }
        _trackers = trackers;

        _downloadRate = MAX(Int64In(dict, @"down", 0), 0);
        _uploadRate = MAX(Int64In(dict, @"up", 0), 0);
        _downloaded = UInt64In(dict, @"downloaded");
        _uploaded = UInt64In(dict, @"uploaded");
        _uptime = SecondsIn(dict, @"uptime_ms", 0);
        _firstDataInterval = SecondsIn(dict, @"first_data_ms", -1);
    }
    return self;
}

@end

#pragma mark - Reader

@interface MacLCTorrentReaderInfo ()
@property (readwrite, copy) NSString *torrentKey;
@property (readwrite, copy) NSString *fileName;
@property (readwrite) uint64_t size;
@property (readwrite) uint64_t position;
@property (readwrite) uint64_t ahead;
@property (readwrite, copy) NSArray<NSArray<NSNumber *> *> *ranges;
@property (readwrite) uint64_t windowEnd;
@property (readwrite) MacLCTorrentStage stage;
@property (readwrite) uint64_t need;
@property (readwrite) int64_t consumeRate;
@property (readwrite) NSTimeInterval stallDuration;
@end

@implementation MacLCTorrentReaderInfo

- (instancetype)initWithDictionary:(NSDictionary *)dict
{
    self = [super init];
    if (self) {
        _torrentKey = [StringIn(dict, @"torrent").lowercaseString copy];
        _fileName = [StringIn(dict, @"file") copy];
        _size = UInt64In(dict, @"size");
        _position = UInt64In(dict, @"pos");
        _ahead = UInt64In(dict, @"ahead");
        _windowEnd = UInt64In(dict, @"window_end");
        _stage = MacLCTorrentStageFromString(dict[@"stage"]);
        _need = UInt64In(dict, @"need");
        _consumeRate = MAX(Int64In(dict, @"rate_in", 0), 0);
        _stallDuration = SecondsIn(dict, @"stall_ms", 0);

        NSMutableArray *ranges = [NSMutableArray array];
        for (id entry in ArrayOf(dict[@"ranges"])) {
            NSArray *pair = ArrayOf(entry);
            if (pair.count != 2)
                continue;
            NSNumber *start = NumberOf(pair[0]);
            NSNumber *end = NumberOf(pair[1]);
            if (start == nil || end == nil || start.doubleValue < 0
             || end.doubleValue <= start.doubleValue)
                continue;
            [ranges addObject:@[start, end]];
            if ((NSInteger)ranges.count >= kMaxRanges)
                break;
        }
        _ranges = ranges;
    }
    return self;
}

static double Fraction(double value, double of)
{
    if (!(of > 0) || !(value > 0))
        return 0;
    return MIN(value / of, 1.0);
}

- (double)headFraction
{
    /* Sum in double: position + ahead cannot overflow there. */
    return Fraction((double)_position + (double)_ahead, (double)_size);
}

- (double)positionFraction
{
    return Fraction((double)_position, (double)_size);
}

- (NSArray<NSNumber *> *)rangeFractions
{
    NSMutableArray<NSNumber *> *fractions = [NSMutableArray arrayWithCapacity:_ranges.count * 2];
    if (_size == 0)
        return fractions;
    for (NSArray<NSNumber *> *range in _ranges) {
        [fractions addObject:@(Fraction(range[0].doubleValue, (double)_size))];
        [fractions addObject:@(Fraction(range[1].doubleValue, (double)_size))];
    }
    return fractions;
}

- (NSTimeInterval)aheadSeconds
{
    if (_consumeRate > 0)
        return (double)_ahead / (double)_consumeRate;
    if (_size == 0)
        return 0;
    return (double)_ahead / ((double)_size / kAverageFilmSeconds);
}

- (double)bufferProgress
{
    if (_need == 0)
        return 1.0;
    return MIN((double)_ahead / (double)_need, 1.0);
}

- (NSTimeInterval)secondsToFillWithDownloadRate:(int64_t)downloadRate
{
    if (_need == 0 || _ahead >= _need || downloadRate <= 0)
        return -1;
    return (double)(_need - _ahead) / (double)downloadRate;
}

@end

#pragma mark - Snapshot

@interface MacLCTorrentSnapshot ()
@property (readwrite) NSInteger dhtNodes;
@property (readwrite, copy) NSString *activeKey;
@property (readwrite, copy) NSArray<MacLCTorrentInfo *> *torrents;
@property (readwrite, copy) NSArray<MacLCTorrentReaderInfo *> *readers;
@property (readwrite) NSTimeInterval moduleTime;
@end

@implementation MacLCTorrentSnapshot

+ (instancetype)emptySnapshot
{
    MacLCTorrentSnapshot *snapshot = [[self alloc] init];
    snapshot.dhtNodes = -1;
    snapshot.activeKey = @"";
    snapshot.torrents = @[];
    snapshot.readers = @[];
    snapshot.moduleTime = 0;
    return snapshot;
}

+ (instancetype)snapshotFromJSONData:(NSData *)data error:(NSError **)error
{
    NSString *problem = nil;
    NSDictionary *root = nil;
    NSInteger code = 1;

    if (![data isKindOfClass:NSData.class] || data.length == 0) {
        problem = @"No data.";
    } else {
        @try {
            root = DictOf([NSJSONSerialization JSONObjectWithData:data options:0 error:NULL]);
        } @catch (NSException *exception) {
            root = nil;
        }
        if (root == nil)
            problem = @"Not a JSON object.";
        else if (NumberOf(root[@"v"]).doubleValue != 1.0) {
            problem = [NSString stringWithFormat:@"Unsupported snapshot version %@.", root[@"v"] ?: @"(none)"];
            code = 2;
        }
    }
    if (problem != nil) {
        if (error != NULL)
            *error = [NSError errorWithDomain:MacLCTorrentStatsErrorDomain
                                         code:code
                                     userInfo:@{NSLocalizedDescriptionKey: problem}];
        return nil;
    }

    MacLCTorrentSnapshot *snapshot = [[self alloc] init];
    snapshot.dhtNodes = MAX(IntegerIn(root, @"dht_nodes", -1), -1);
    snapshot.activeKey = [StringIn(root, @"active").lowercaseString copy];
    snapshot.moduleTime = SecondsIn(root, @"now_ms", 0);

    NSMutableArray *torrents = [NSMutableArray array];
    for (id entry in ArrayOf(root[@"torrents"])) {
        NSDictionary *dict = DictOf(entry);
        if (dict != nil)
            [torrents addObject:[[MacLCTorrentInfo alloc] initWithDictionary:dict]];
    }
    snapshot.torrents = torrents;

    NSMutableArray *readers = [NSMutableArray array];
    for (id entry in ArrayOf(root[@"readers"])) {
        NSDictionary *dict = DictOf(entry);
        if (dict != nil)
            [readers addObject:[[MacLCTorrentReaderInfo alloc] initWithDictionary:dict]];
    }
    snapshot.readers = readers;
    return snapshot;
}

- (MacLCTorrentInfo *)torrentForKey:(NSString *)key
{
    if (![key isKindOfClass:NSString.class] || key.length == 0)
        return nil;
    NSString *lower = key.lowercaseString;
    for (MacLCTorrentInfo *torrent in _torrents)
        if ([torrent.key isEqualToString:lower])
            return torrent;
    return nil;
}

- (MacLCTorrentInfo *)activeTorrent
{
    return [self torrentForKey:_activeKey] ?: _torrents.lastObject;
}

- (MacLCTorrentReaderInfo *)primaryReader
{
    MacLCTorrentInfo *torrent = self.activeTorrent;
    if (torrent == nil)
        return nil;
    MacLCTorrentReaderInfo *best = nil;
    for (MacLCTorrentReaderInfo *reader in _readers)
        if ([reader.torrentKey isEqualToString:torrent.key] && (best == nil || reader.size > best.size))
            best = reader;
    return best;
}

@end

#pragma mark - Wording

/// "1 peer", "14 peers".
static NSString *Counted(NSInteger count, NSString *singular, NSString *plural)
{
    return [NSString stringWithFormat:@"%ld %@", (long)count, count == 1 ? singular : plural];
}

/// Decimal units, as Finder does. One decimal under 10 ("4.2 MB"), none from
/// 10 ("820 KB"); a value that rounds up to 1000 moves to the next unit.
static NSString *DecimalString(double bytes, NSString *suffix)
{
    static NSString * const units[] = {@"KB", @"MB", @"GB", @"TB"};
    if (!(bytes > 0))
        return [NSString stringWithFormat:@"0 KB%@", suffix];
    double value = bytes / 1000.0;
    int unit = 0;
    for (;;) {
        double rounded = value < 10 ? round(value * 10) / 10 : round(value);
        if (rounded >= 1000 && unit < 3) {
            value /= 1000.0;
            unit++;
            continue;
        }
        return [NSString stringWithFormat:value < 10 && rounded < 10 ? @"%.1f %@%@" : @"%.0f %@%@",
                value, units[unit], suffix];
    }
}

@implementation MacLCTorrentFormat

+ (NSString *)rateString:(int64_t)bytesPerSecond
{
    return DecimalString((double)bytesPerSecond, @"/s");
}

+ (NSString *)sizeString:(uint64_t)bytes
{
    return DecimalString((double)bytes, @"");
}

+ (NSString *)durationString:(NSTimeInterval)seconds
{
    if (isnan(seconds) || seconds < 0)
        return @"";
    if (seconds > 1e9)
        seconds = 1e9;
    long long total = llround(seconds);
    if (total < 60)
        return [NSString stringWithFormat:@"%lld s", total];
    if (total < 3600) {
        long long minutes = total / 60, rest = total % 60;
        return rest > 0 ? [NSString stringWithFormat:@"%lld min %lld s", minutes, rest]
                        : [NSString stringWithFormat:@"%lld min", minutes];
    }
    long long hours = total / 3600, minutes = (total % 3600) / 60;
    return minutes > 0 ? [NSString stringWithFormat:@"%lld h %lld min", hours, minutes]
                       : [NSString stringWithFormat:@"%lld h", hours];
}

+ (NSString *)remainingString:(NSTimeInterval)seconds
{
    if (isnan(seconds) || seconds < 0)
        return @"";
    if (seconds < 5)
        return @"Less than a minute left";
    if (seconds < 57.5) {
        /* Tens of seconds, not the exact count: it moves every poll. */
        long long rounded = llround(seconds / 5.0) * 5;
        return [NSString stringWithFormat:@"About %lld s left", rounded];
    }
    /* From a minute up, whole minutes. */
    long long minutes = llround(MIN(seconds, 1e9) / 60.0);
    return [NSString stringWithFormat:@"About %@ left", [self durationString:(double)(minutes * 60)]];
}

+ (NSString *)titleForStage:(MacLCTorrentStage)stage
{
    switch (stage) {
        case MacLCTorrentStageTrackers:     return @"Finding peers";
        case MacLCTorrentStageMetadata:     return @"Getting the file list";
        case MacLCTorrentStageConnecting:   return @"Connecting to peers";
        case MacLCTorrentStageDownloading:  return @"Receiving data";
        case MacLCTorrentStageBuffering:    return @"Filling the buffer";
        case MacLCTorrentStageReady:        return @"Starting";
        case MacLCTorrentStagePlaying:      return @"Playing";
        case MacLCTorrentStageStalled:      return @"Buffering";
        case MacLCTorrentStageFailed:       return @"Can't download";
        case MacLCTorrentStageUnknown:      break;
    }
    return @"";
}

+ (NSString *)explanationForTorrent:(MacLCTorrentInfo *)torrent
                             reader:(MacLCTorrentReaderInfo *)reader
{
    if (torrent == nil)
        return @"";
    MacLCTorrentStage stage = reader != nil && reader.stage != MacLCTorrentStageUnknown
                            ? reader.stage : torrent.stage;
    /* An error on the torrent wins over the reader's last stage. */
    if (torrent.stage == MacLCTorrentStageFailed)
        stage = MacLCTorrentStageFailed;

    switch (stage) {
        case MacLCTorrentStageTrackers:
            return @"Asking the trackers and the network who has this.";

        case MacLCTorrentStageMetadata:
            if (torrent.peers <= 0)
                return @"Peers answered. Asking them for the list of files.";
            return [NSString stringWithFormat:@"%@ answered. Asking them for the list of files.",
                    Counted(torrent.peers, @"peer", @"peers")];

        case MacLCTorrentStageConnecting: {
            /* Peers we are talking to, plus those still being opened. */
            NSInteger reached = torrent.peers + torrent.peersConnecting;
            NSInteger swarm = torrent.swarmSeeds >= 0 && torrent.swarmLeechers >= 0
                            ? torrent.swarmSeeds + torrent.swarmLeechers : -1;
            if (reached <= 0)
                return @"Found the files. Looking for peers that send data.";
            if (swarm > reached)
                return [NSString stringWithFormat:@"Found the files. Connecting to %ld of %ld peers.",
                        (long)reached, (long)swarm];
            return [NSString stringWithFormat:@"Found the files. Connecting to %@.",
                    Counted(reached, @"peer", @"peers")];
        }

        case MacLCTorrentStageDownloading: {
            NSInteger senders = torrent.peersUnchoked > 0 ? torrent.peersUnchoked : torrent.peers;
            if (senders <= 0)
                return @"Waiting for peers to send data.";
            if (torrent.downloadRate > 0)
                return [NSString stringWithFormat:@"Receiving data from %@ at %@.",
                        Counted(senders, @"peer", @"peers"),
                        [self rateString:torrent.downloadRate]];
            return [NSString stringWithFormat:@"Receiving data from %@.", Counted(senders, @"peer", @"peers")];
        }

        case MacLCTorrentStageBuffering: {
            if (reader == nil || reader.need == 0)
                return @"Downloading the first part so playback won't stop.";
            NSString *head = [NSString stringWithFormat:@"Downloading the first %@ so playback won't stop: %d %% there",
                              [self sizeString:reader.need], (int)floor(reader.bufferProgress * 100.0)];
            NSString *left = [self remainingString:[reader secondsToFillWithDownloadRate:torrent.downloadRate]];
            if (left.length == 0)
                return [head stringByAppendingString:@"."];
            return [NSString stringWithFormat:@"%@, %@%@.", head,
                    [left substringToIndex:1].lowercaseString, [left substringFromIndex:1]];
        }

        case MacLCTorrentStageReady:
            return @"The start buffer is full. Starting playback.";

        case MacLCTorrentStagePlaying: {
            if (reader == nil)
                return @"Playing.";
            NSString *ahead = [self durationString:reader.aheadSeconds];
            NSString *sentence = [NSString stringWithFormat:@"%@ of video is downloaded ahead of you", ahead];
            if (torrent.downloadRate > 0)
                return [NSString stringWithFormat:@"%@, and more arrives at %@.", sentence,
                        [self rateString:torrent.downloadRate]];
            return [sentence stringByAppendingString:@"."];
        }

        case MacLCTorrentStageStalled:
            if (torrent.peersUnchoked <= 0)
                return @"Waiting for the next part: no peer is sending data right now.";
            return [NSString stringWithFormat:@"Waiting for the next part: %@ sending data.",
                    torrent.peersUnchoked == 1 ? @"1 peer is" : [NSString stringWithFormat:@"%ld peers are", (long)torrent.peersUnchoked]];

        case MacLCTorrentStageFailed:
            return torrent.error.length > 0 ? torrent.error : @"Something went wrong while downloading.";

        case MacLCTorrentStageUnknown:
            break;
    }
    return @"";
}

+ (NSString *)peersString:(MacLCTorrentInfo *)torrent
{
    if (torrent == nil)
        return @"";
    return [NSString stringWithFormat:@"%@ · %@",
            Counted(torrent.peers, @"peer", @"peers"), Counted(torrent.seeds, @"seed", @"seeds")];
}

@end

#pragma mark - Matching a media address to a torrent

/// A 32-character base32 info hash (RFC 4648, as magnet links use) → 40
/// lowercase hex characters. nil when it is not exactly that.
NSString *MacLCTorrentHexFromBase32(NSString *base32)
{
    if (![base32 isKindOfClass:NSString.class] || base32.length != 32)
        return nil;
    uint8_t bytes[20];
    uint32_t buffer = 0;
    int bits = 0;
    int count = 0;
    for (NSUInteger i = 0; i < 32; i++) {
        unichar c = [base32 characterAtIndex:i];
        int value;
        if (c >= 'A' && c <= 'Z')
            value = c - 'A';
        else if (c >= 'a' && c <= 'z')
            value = c - 'a';
        else if (c >= '2' && c <= '7')
            value = 26 + (c - '2');
        else
            return nil;
        buffer = (buffer << 5) | (uint32_t)value;
        bits += 5;
        if (bits >= 8) {
            bits -= 8;
            if (count < 20)
                bytes[count] = (uint8_t)((buffer >> bits) & 0xFF);
            count++;
            buffer &= (1u << bits) - 1;
        }
    }
    if (count != 20)
        return nil;
    NSMutableString *hex = [NSMutableString stringWithCapacity:40];
    for (int i = 0; i < 20; i++)
        [hex appendFormat:@"%02x", bytes[i]];
    return hex;
}

static BOOL IsHex40(NSString *string)
{
    if (string.length != 40)
        return NO;
    for (NSUInteger i = 0; i < 40; i++) {
        unichar c = [string characterAtIndex:i];
        if (!((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F')))
            return NO;
    }
    return YES;
}

static NSString *KeyFromPlainMRL(NSString *mrl)
{
    NSRange tag = [mrl rangeOfString:@"btih:" options:NSCaseInsensitiveSearch];
    if (tag.location == NSNotFound)
        return nil;
    NSUInteger start = NSMaxRange(tag), end = start;
    NSCharacterSet *alnum = NSCharacterSet.alphanumericCharacterSet;
    while (end < mrl.length && [alnum characterIsMember:[mrl characterAtIndex:end]])
        end++;
    NSString *hash = [mrl substringWithRange:NSMakeRange(start, end - start)];
    if (IsHex40(hash))
        return hash.lowercaseString;
    return MacLCTorrentHexFromBase32(hash);
}

/// The info hash a magnet address names ("…xt=urn:btih:<hash>…"), hex or
/// base32, as 40 lowercase hex characters; nil when the address has none.
/// Tries the address as given, then percent-decoded (":" may arrive as %3A).
NSString *MacLCTorrentKeyFromMRL(NSString *mrl)
{
    if (![mrl isKindOfClass:NSString.class])
        return nil;
    NSString *key = KeyFromPlainMRL(mrl);
    if (key == nil)
        key = KeyFromPlainMRL(mrl.stringByRemovingPercentEncoding ?: @"");
    return key;
}

/// The file a stream address asks for: the text after "#!/" (or "%23!/"),
/// percent-decoded, reduced to its last path component. nil without a fragment.
NSString *MacLCTorrentFileNameFromMRL(NSString *mrl)
{
    if (![mrl isKindOfClass:NSString.class])
        return nil;
    NSRange marker = [mrl rangeOfString:@"#!/"];
    if (marker.location == NSNotFound)
        marker = [mrl rangeOfString:@"%23!/" options:NSCaseInsensitiveSearch];
    if (marker.location == NSNotFound)
        return nil;
    NSString *fragment = [mrl substringFromIndex:NSMaxRange(marker)];
    NSString *decoded = fragment.stringByRemovingPercentEncoding ?: fragment;
    NSString *name = [decoded componentsSeparatedByString:@"/"].lastObject;
    return name.length > 0 ? name : nil;
}
