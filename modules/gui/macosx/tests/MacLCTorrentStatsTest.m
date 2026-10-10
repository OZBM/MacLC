/*****************************************************************************
 * MacLCTorrentStatsTest.m: tests for the torrent snapshot model, derived
 * values, wording and the helpers that match a media address to a torrent
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

#if __has_include(<XCTest/XCTest.h>)
#import <XCTest/XCTest.h>
#else
#import <Foundation/Foundation.h>
@interface XCTestCase : NSObject
@end
@implementation XCTestCase
@end
#define XCTAssertEqual(a, b, ...) do { (void)(a); (void)(b); } while (0)
#define XCTAssertEqualObjects(a, b, ...) do { (void)(a); (void)(b); } while (0)
#define XCTAssertEqualWithAccuracy(a, b, acc, ...) do { (void)(a); (void)(b); (void)(acc); } while (0)
#define XCTAssertNotNil(a, ...) do { (void)(a); } while (0)
#define XCTAssertNil(a, ...) do { (void)(a); } while (0)
#define XCTAssertTrue(a, ...) do { (void)(a); } while (0)
#define XCTAssertFalse(a, ...) do { (void)(a); } while (0)
#endif

#import "torrent/MacLCTorrentStats.h"

/* Defined in MacLCTorrentStats.m (the monitor uses them to match the media). */
NSString * _Nullable MacLCTorrentHexFromBase32(NSString * _Nullable base32);
NSString * _Nullable MacLCTorrentKeyFromMRL(NSString * _Nullable mrl);
NSString * _Nullable MacLCTorrentFileNameFromMRL(NSString * _Nullable mrl);

static NSString * const kKey = @"11ea0258c7f1d9b4e6a3520b8d94f0c1a77e3b62";
static NSString * const kKeyBase32 = @"CHVAEWGH6HM3JZVDKIFY3FHQYGTX4O3C";

static MacLCTorrentSnapshot *Parse(NSString *json)
{
    NSError *error = nil;
    return [MacLCTorrentSnapshot snapshotFromJSONData:[json dataUsingEncoding:NSUTF8StringEncoding] error:&error];
}

/// A snapshot with one torrent (key kKey, active) whose fields are the given
/// JSON members, and optionally one reader of it.
static MacLCTorrentSnapshot *Snap(NSString *torrentMembers, NSString *readerMembers)
{
    NSString *json = [NSString stringWithFormat:
        @"{\"v\":1,\"active\":\"%@\",\"torrents\":[{\"key\":\"%@\"%@%@}],\"readers\":[%@]}",
        kKey, kKey, torrentMembers.length ? @"," : @"", torrentMembers ?: @"",
        readerMembers ? [NSString stringWithFormat:@"{\"torrent\":\"%@\",%@}", kKey, readerMembers] : @""];
    return Parse(json);
}

@interface MacLCTorrentStatsTest : XCTestCase
@end

@implementation MacLCTorrentStatsTest

#pragma mark - Stages

- (void)testStageStrings
{
    XCTAssertEqual(MacLCTorrentStageFromString(@"trackers"), MacLCTorrentStageTrackers);
    XCTAssertEqual(MacLCTorrentStageFromString(@"metadata"), MacLCTorrentStageMetadata);
    XCTAssertEqual(MacLCTorrentStageFromString(@"connecting"), MacLCTorrentStageConnecting);
    XCTAssertEqual(MacLCTorrentStageFromString(@"downloading"), MacLCTorrentStageDownloading);
    XCTAssertEqual(MacLCTorrentStageFromString(@"buffering"), MacLCTorrentStageBuffering);
    XCTAssertEqual(MacLCTorrentStageFromString(@"ready"), MacLCTorrentStageReady);
    XCTAssertEqual(MacLCTorrentStageFromString(@"playing"), MacLCTorrentStagePlaying);
    XCTAssertEqual(MacLCTorrentStageFromString(@"stalled"), MacLCTorrentStageStalled);
    XCTAssertEqual(MacLCTorrentStageFromString(@"error"), MacLCTorrentStageFailed);
    XCTAssertEqual(MacLCTorrentStageFromString(nil), MacLCTorrentStageUnknown);
    XCTAssertEqual(MacLCTorrentStageFromString(@""), MacLCTorrentStageUnknown);
    XCTAssertEqual(MacLCTorrentStageFromString(@"flying"), MacLCTorrentStageUnknown);
    XCTAssertEqual(MacLCTorrentStageFromString(@"PLAYING"), MacLCTorrentStageUnknown);
    id notAString = @42;
    XCTAssertEqual(MacLCTorrentStageFromString(notAString), MacLCTorrentStageUnknown);
}

- (void)testStageStringsInSnapshot
{
    NSArray<NSString *> *names = @[@"trackers", @"metadata", @"connecting", @"downloading", @"buffering",
                                   @"ready", @"playing", @"stalled", @"error"];
    MacLCTorrentStage expected[] = {
        MacLCTorrentStageTrackers, MacLCTorrentStageMetadata, MacLCTorrentStageConnecting,
        MacLCTorrentStageDownloading, MacLCTorrentStageBuffering, MacLCTorrentStageReady,
        MacLCTorrentStagePlaying, MacLCTorrentStageStalled, MacLCTorrentStageFailed,
    };
    for (NSUInteger i = 0; i < names.count; i++) {
        MacLCTorrentSnapshot *snapshot = Snap([NSString stringWithFormat:@"\"stage\":\"%@\"", names[i]],
                                              [NSString stringWithFormat:@"\"file\":\"a.mkv\",\"stage\":\"%@\"", names[i]]);
        XCTAssertNotNil(snapshot);
        XCTAssertEqual(snapshot.torrents.firstObject.stage, expected[i]);
        XCTAssertEqual(snapshot.readers.firstObject.stage, expected[i]);
    }
    MacLCTorrentSnapshot *odd = Snap(@"\"stage\":\"warp\"", @"\"stage\":7");
    XCTAssertEqual(odd.torrents.firstObject.stage, MacLCTorrentStageUnknown);
    XCTAssertEqual(odd.readers.firstObject.stage, MacLCTorrentStageUnknown);
}

#pragma mark - Parsing

- (void)testFullSnapshot
{
    NSString *json =
        @"{\"v\":1,\"now_ms\":123456789,\"dht_nodes\":87,\"active\":\"11EA0258C7F1D9B4E6A3520B8D94F0C1A77E3B62\","
        @"\"unknown_top\":[1,2],"
        @"\"torrents\":[{\"key\":\"11ea0258c7f1d9b4e6a3520b8d94f0c1a77e3b62\",\"name\":\"Night.of.the.Living.Dead.1968.1080p\","
        @"\"stage\":\"buffering\",\"error\":\"\",\"size\":4300000000,\"pieces\":2048,\"piece_size\":2097152,"
        @"\"peers\":14,\"seeds\":6,\"peers_connecting\":5,\"peers_handshaking\":2,\"peers_unchoked\":4,"
        @"\"swarm_seeds\":312,\"swarm_leechers\":54,"
        @"\"sources\":{\"tracker\":9,\"dht\":4,\"pex\":1,\"lsd\":2,\"incoming\":3},"
        @"\"trackers\":[{\"url\":\"udp://tracker.opentrackr.org:1337/announce\",\"state\":\"ok\",\"peers\":12,\"message\":\"\"},"
        @"{\"url\":\"http://t.example.org/announce\",\"state\":\"error\",\"peers\":-1,\"message\":\"timed out\"}],"
        @"\"down\":4200000,\"up\":120000,\"downloaded\":123456789,\"uploaded\":99,"
        @"\"uptime_ms\":15000,\"first_data_ms\":6200}],"
        @"\"readers\":[{\"torrent\":\"11ea0258c7f1d9b4e6a3520b8d94f0c1a77e3b62\",\"file\":\"dir/Night.mp4\",\"size\":3900000000,"
        @"\"pos\":123456,\"ahead\":83886080,\"ranges\":[[0,20971520],[3880000000,3900000000]],"
        @"\"window_end\":223456789,\"stage\":\"buffering\",\"need\":25165824,\"rate_in\":1100000,\"stall_ms\":1500}]}";
    MacLCTorrentSnapshot *snapshot = Parse(json);
    XCTAssertNotNil(snapshot);
    XCTAssertEqual(snapshot.dhtNodes, 87);
    XCTAssertEqualObjects(snapshot.activeKey, kKey);
    XCTAssertEqualWithAccuracy(snapshot.moduleTime, 123456.789, 1e-6);
    XCTAssertEqual(snapshot.torrents.count, 1);
    XCTAssertEqual(snapshot.readers.count, 1);

    MacLCTorrentInfo *t = snapshot.torrents.firstObject;
    XCTAssertEqualObjects(t.key, kKey);
    XCTAssertEqualObjects(t.name, @"Night.of.the.Living.Dead.1968.1080p");
    XCTAssertEqual(t.stage, MacLCTorrentStageBuffering);
    XCTAssertEqualObjects(t.error, @"");
    XCTAssertEqual(t.size, 4300000000ULL);
    XCTAssertEqual(t.pieceCount, 2048);
    XCTAssertEqual(t.pieceSize, 2097152ULL);
    XCTAssertEqual(t.peers, 14);
    XCTAssertEqual(t.seeds, 6);
    XCTAssertEqual(t.peersConnecting, 5);
    XCTAssertEqual(t.peersHandshaking, 2);
    XCTAssertEqual(t.peersUnchoked, 4);
    XCTAssertEqual(t.swarmSeeds, 312);
    XCTAssertEqual(t.swarmLeechers, 54);
    XCTAssertEqual(t.peersFromTrackers, 9);
    XCTAssertEqual(t.peersFromDHT, 4);
    XCTAssertEqual(t.peersFromPeerExchange, 1);
    XCTAssertEqual(t.peersFromLocalNetwork, 2);
    XCTAssertEqual(t.peersIncoming, 3);
    XCTAssertEqual(t.downloadRate, 4200000);
    XCTAssertEqual(t.uploadRate, 120000);
    XCTAssertEqual(t.downloaded, 123456789ULL);
    XCTAssertEqual(t.uploaded, 99ULL);
    XCTAssertEqualWithAccuracy(t.uptime, 15.0, 1e-9);
    XCTAssertEqualWithAccuracy(t.firstDataInterval, 6.2, 1e-9);
    XCTAssertEqual(t.trackers.count, 2);
    XCTAssertEqualObjects(t.trackers[0].host, @"tracker.opentrackr.org");
    XCTAssertEqual(t.trackers[0].state, MacLCTorrentTrackerStateOK);
    XCTAssertEqual(t.trackers[0].peers, 12);
    XCTAssertEqual(t.trackers[1].state, MacLCTorrentTrackerStateError);
    XCTAssertEqual(t.trackers[1].peers, -1);
    XCTAssertEqualObjects(t.trackers[1].message, @"timed out");

    MacLCTorrentReaderInfo *r = snapshot.readers.firstObject;
    XCTAssertEqualObjects(r.torrentKey, kKey);
    XCTAssertEqualObjects(r.fileName, @"dir/Night.mp4");
    XCTAssertEqual(r.size, 3900000000ULL);
    XCTAssertEqual(r.position, 123456ULL);
    XCTAssertEqual(r.ahead, 83886080ULL);
    XCTAssertEqual(r.ranges.count, 2);
    XCTAssertEqual(r.ranges[1][0].unsignedLongLongValue, 3880000000ULL);
    XCTAssertEqual(r.windowEnd, 223456789ULL);
    XCTAssertEqual(r.stage, MacLCTorrentStageBuffering);
    XCTAssertEqual(r.need, 25165824ULL);
    XCTAssertEqual(r.consumeRate, 1100000);
    XCTAssertEqualWithAccuracy(r.stallDuration, 1.5, 1e-9);

    XCTAssertEqual(snapshot.activeTorrent, t);
    XCTAssertEqual(snapshot.primaryReader, r);
}

- (void)testVersionAndShape
{
    NSError *error = nil;
    XCTAssertNil([MacLCTorrentSnapshot snapshotFromJSONData:[@"{\"v\":2,\"torrents\":[]}" dataUsingEncoding:NSUTF8StringEncoding] error:&error]);
    XCTAssertNotNil(error);
    XCTAssertNil(Parse(@"{\"torrents\":[]}"));
    XCTAssertNil(Parse(@"{\"v\":\"1\"}"));
    XCTAssertNil(Parse(@"{\"v\":true}"));
    XCTAssertNil(Parse(@"{\"v\":null}"));
    XCTAssertNil(Parse(@"{\"v\":1.5}"));
    XCTAssertNil(Parse(@"{\"v\":0}"));
    XCTAssertNil(Parse(@"[1]"));
    XCTAssertNil(Parse(@"\"v\""));
    XCTAssertNil(Parse(@"not json"));
    XCTAssertNil(Parse(@"{\"v\":1"));
    XCTAssertNil(Parse(@""));
    XCTAssertNotNil(Parse(@"{\"v\":1}"));
    XCTAssertNotNil(Parse(@"{\"v\":1.0}"));
    /* A NULL error pointer and a nil buffer must not crash. */
    XCTAssertNil([MacLCTorrentSnapshot snapshotFromJSONData:[NSData data] error:NULL]);
    NSData *none = nil;
    XCTAssertNil([MacLCTorrentSnapshot snapshotFromJSONData:none error:NULL]);
}

- (void)testMissingKeysGetDefaults
{
    MacLCTorrentSnapshot *snapshot = Parse(@"{\"v\":1}");
    XCTAssertEqual(snapshot.dhtNodes, -1);
    XCTAssertEqualObjects(snapshot.activeKey, @"");
    XCTAssertEqual(snapshot.torrents.count, 0);
    XCTAssertEqual(snapshot.readers.count, 0);
    XCTAssertNil(snapshot.activeTorrent);
    XCTAssertNil(snapshot.primaryReader);

    MacLCTorrentSnapshot *bare = Parse(@"{\"v\":1,\"torrents\":[{}],\"readers\":[{}]}");
    MacLCTorrentInfo *t = bare.torrents.firstObject;
    XCTAssertNotNil(t);
    XCTAssertEqualObjects(t.key, @"");
    XCTAssertEqualObjects(t.name, @"");
    XCTAssertEqual(t.stage, MacLCTorrentStageUnknown);
    XCTAssertEqual(t.size, 0ULL);
    XCTAssertEqual(t.peers, 0);
    XCTAssertEqual(t.swarmSeeds, -1);
    XCTAssertEqual(t.swarmLeechers, -1);
    XCTAssertEqual(t.downloadRate, 0);
    XCTAssertEqual(t.trackers.count, 0);
    XCTAssertEqualWithAccuracy(t.firstDataInterval, -1.0, 1e-9);
    XCTAssertEqualWithAccuracy(t.uptime, 0.0, 1e-9);
    MacLCTorrentReaderInfo *r = bare.readers.firstObject;
    XCTAssertNotNil(r);
    XCTAssertEqual(r.size, 0ULL);
    XCTAssertEqual(r.ranges.count, 0);
    XCTAssertEqual(r.rangeFractions.count, 0);
    XCTAssertEqualWithAccuracy(r.headFraction, 0.0, 1e-12);
    XCTAssertEqualWithAccuracy(r.aheadSeconds, 0.0, 1e-12);
    XCTAssertEqualWithAccuracy(r.bufferProgress, 1.0, 1e-12);
}

- (void)testWrongTypesAreMissing
{
    NSString *json =
        @"{\"v\":1,\"dht_nodes\":\"many\",\"active\":5,\"now_ms\":null,"
        @"\"torrents\":[null,7,\"x\",[1],"
        @"{\"key\":12,\"name\":null,\"stage\":3,\"error\":false,\"size\":\"big\",\"pieces\":[1],\"peers\":true,"
        @"\"seeds\":\"6\",\"swarm_seeds\":null,\"sources\":[1],\"trackers\":{\"a\":1},\"down\":-5,\"up\":{},"
        @"\"uptime_ms\":-3,\"first_data_ms\":\"soon\"},"
        @"{\"key\":\"abc\",\"trackers\":[7,null,{\"url\":9,\"state\":3,\"peers\":\"x\"},{\"url\":\"udp://h.example:1/a\"}]}],"
        @"\"readers\":[7,{\"ranges\":[[1],[\"a\",\"b\"],[5,3],[0,10],null,7,[1,2,3],[2,2],[-4,8]],\"pos\":\"x\","
        @"\"size\":[1],\"ahead\":false,\"need\":null,\"rate_in\":-9,\"stall_ms\":-1}]}";
    MacLCTorrentSnapshot *snapshot = Parse(json);
    XCTAssertNotNil(snapshot);
    XCTAssertEqual(snapshot.dhtNodes, -1);
    XCTAssertEqualObjects(snapshot.activeKey, @"");
    XCTAssertEqualWithAccuracy(snapshot.moduleTime, 0.0, 1e-12);
    XCTAssertEqual(snapshot.torrents.count, 2);
    MacLCTorrentInfo *t = snapshot.torrents[0];
    XCTAssertEqualObjects(t.key, @"");
    XCTAssertEqualObjects(t.name, @"");
    XCTAssertEqual(t.stage, MacLCTorrentStageUnknown);
    XCTAssertEqualObjects(t.error, @"");
    XCTAssertEqual(t.size, 0ULL);
    XCTAssertEqual(t.pieceCount, 0);
    XCTAssertEqual(t.peers, 0);
    XCTAssertEqual(t.seeds, 0);
    XCTAssertEqual(t.swarmSeeds, -1);
    XCTAssertEqual(t.peersFromDHT, 0);
    XCTAssertEqual(t.trackers.count, 0);
    XCTAssertEqual(t.downloadRate, 0);
    XCTAssertEqual(t.uploadRate, 0);
    XCTAssertEqualWithAccuracy(t.uptime, 0.0, 1e-12);
    XCTAssertEqualWithAccuracy(t.firstDataInterval, -1.0, 1e-12);

    MacLCTorrentInfo *u = snapshot.torrents[1];
    XCTAssertEqual(u.trackers.count, 2);   /* the two dictionaries, defaults for the first */
    XCTAssertEqualObjects(u.trackers[0].URL, @"");
    XCTAssertEqual(u.trackers[0].state, MacLCTorrentTrackerStateIdle);
    XCTAssertEqual(u.trackers[0].peers, -1);
    XCTAssertEqualObjects(u.trackers[1].host, @"h.example");

    XCTAssertEqual(snapshot.readers.count, 1);
    MacLCTorrentReaderInfo *r = snapshot.readers[0];
    XCTAssertEqual(r.position, 0ULL);
    XCTAssertEqual(r.size, 0ULL);
    XCTAssertEqual(r.ahead, 0ULL);
    XCTAssertEqual(r.need, 0ULL);
    XCTAssertEqual(r.consumeRate, 0);
    XCTAssertEqualWithAccuracy(r.stallDuration, 0.0, 1e-12);
    /* only [0,10] is a valid pair; [-4,8], [2,2], [5,3] and the rest are dropped */
    XCTAssertEqual(r.ranges.count, 1);
    XCTAssertEqual(r.ranges[0][1].integerValue, 10);
}

- (void)testHugeAndNegativeNumbers
{
    MacLCTorrentSnapshot *snapshot = Snap(@"\"size\":1e30,\"downloaded\":-7,\"peers\":1e30,\"down\":1e30,\"uptime_ms\":1e300",
                                          @"\"size\":1e30,\"pos\":-1,\"ahead\":1e30,\"need\":1e40");
    XCTAssertNotNil(snapshot);
    MacLCTorrentInfo *t = snapshot.torrents.firstObject;
    XCTAssertEqual(t.size, UINT64_MAX);
    XCTAssertEqual(t.downloaded, 0ULL);
    XCTAssertEqual(t.peers, NSIntegerMax);
    XCTAssertEqual(t.downloadRate, INT64_MAX);
    MacLCTorrentReaderInfo *r = snapshot.readers.firstObject;
    XCTAssertEqual(r.position, 0ULL);
    XCTAssertEqual(r.ahead, UINT64_MAX);
    XCTAssertEqual(r.need, UINT64_MAX);
    XCTAssertTrue(r.headFraction <= 1.0 && r.headFraction >= 0.0);
    XCTAssertTrue(r.bufferProgress <= 1.0);
    /* Formatting the extremes must not crash either. */
    XCTAssertNotNil([MacLCTorrentFormat sizeString:UINT64_MAX]);
    XCTAssertNotNil([MacLCTorrentFormat rateString:INT64_MAX]);
    XCTAssertNotNil([MacLCTorrentFormat explanationForTorrent:t reader:r]);
}

- (void)testUnknownKeysAreIgnored
{
    MacLCTorrentSnapshot *snapshot = Snap(@"\"stage\":\"playing\",\"from_the_future\":{\"a\":[1,2,3]}", @"\"extra\":1,\"stage\":\"playing\"");
    XCTAssertEqual(snapshot.torrents.firstObject.stage, MacLCTorrentStagePlaying);
    XCTAssertEqual(snapshot.readers.firstObject.stage, MacLCTorrentStagePlaying);
}

- (void)testTrackerHosts
{
    NSArray<NSString *> *urls = @[@"udp://tracker.opentrackr.org:1337/announce", @"http://user:pw@host.example:80/a?x=1#f",
                                  @"udp://[2001:db8::1]:6969/announce", @"tracker.example.org:80",
                                  @"wss://t.example.com", @"", @"udp://:1337/a"];
    NSArray<NSString *> *hosts = @[@"tracker.opentrackr.org", @"host.example", @"2001:db8::1",
                                   @"tracker.example.org", @"t.example.com", @"", @""];
    for (NSUInteger i = 0; i < urls.count; i++) {
        MacLCTorrentSnapshot *snapshot = Snap([NSString stringWithFormat:@"\"trackers\":[{\"url\":\"%@\"}]", urls[i]], nil);
        XCTAssertEqualObjects(snapshot.torrents.firstObject.trackers.firstObject.host, hosts[i]);
        XCTAssertEqualObjects(snapshot.torrents.firstObject.trackers.firstObject.URL, urls[i]);
    }
    /* At most 8 trackers, whatever the module sends. */
    NSMutableString *many = [NSMutableString stringWithString:@"\"trackers\":["];
    for (int i = 0; i < 12; i++)
        [many appendFormat:@"%@{\"url\":\"udp://t%d.example:1/a\",\"state\":\"updating\"}", i ? @"," : @"", i];
    [many appendString:@"]"];
    MacLCTorrentSnapshot *snapshot = Snap(many, nil);
    XCTAssertEqual(snapshot.torrents.firstObject.trackers.count, 8);
    XCTAssertEqual(snapshot.torrents.firstObject.trackers[0].state, MacLCTorrentTrackerStateUpdating);
}

- (void)testRangeCountIsCapped
{
    NSMutableString *ranges = [NSMutableString stringWithString:@"\"size\":1000000,\"ranges\":["];
    for (int i = 0; i < 300; i++)
        [ranges appendFormat:@"%@[%d,%d]", i ? @"," : @"", i * 10, i * 10 + 5];
    [ranges appendString:@"]"];
    MacLCTorrentSnapshot *snapshot = Snap(@"", ranges);
    XCTAssertEqual(snapshot.readers.firstObject.ranges.count, 128);
    XCTAssertEqual(snapshot.readers.firstObject.rangeFractions.count, 256);
}

- (void)testEmptySnapshot
{
    MacLCTorrentSnapshot *snapshot = [MacLCTorrentSnapshot emptySnapshot];
    XCTAssertNotNil(snapshot);
    XCTAssertEqual(snapshot.dhtNodes, -1);
    XCTAssertEqualObjects(snapshot.activeKey, @"");
    XCTAssertEqual(snapshot.torrents.count, 0);
    XCTAssertEqual(snapshot.readers.count, 0);
    XCTAssertNil(snapshot.activeTorrent);
    XCTAssertNil(snapshot.primaryReader);
    XCTAssertNil([snapshot torrentForKey:kKey]);
}

#pragma mark - Lookup

- (void)testTorrentLookup
{
    MacLCTorrentSnapshot *snapshot = Parse(@"{\"v\":1,\"active\":\"bbbb\",\"torrents\":[{\"key\":\"aaaa\"},{\"key\":\"bbbb\"},{\"key\":\"cccc\"}]}");
    XCTAssertEqualObjects([snapshot torrentForKey:@"aaaa"].key, @"aaaa");
    XCTAssertEqualObjects([snapshot torrentForKey:@"AAAA"].key, @"aaaa");
    XCTAssertNil([snapshot torrentForKey:@"dddd"]);
    XCTAssertNil([snapshot torrentForKey:@""]);
    XCTAssertEqualObjects(snapshot.activeTorrent.key, @"bbbb");

    /* No (or an unknown) active key: the last torrent. */
    MacLCTorrentSnapshot *noActive = Parse(@"{\"v\":1,\"active\":\"\",\"torrents\":[{\"key\":\"aaaa\"},{\"key\":\"cccc\"}]}");
    XCTAssertEqualObjects(noActive.activeTorrent.key, @"cccc");
    MacLCTorrentSnapshot *gone = Parse(@"{\"v\":1,\"active\":\"zzzz\",\"torrents\":[{\"key\":\"aaaa\"}]}");
    XCTAssertEqualObjects(gone.activeTorrent.key, @"aaaa");
}

- (void)testPrimaryReaderIsLargestFileOfActiveTorrent
{
    NSString *json =
        @"{\"v\":1,\"active\":\"aaaa\",\"torrents\":[{\"key\":\"aaaa\"},{\"key\":\"bbbb\"}],\"readers\":["
        @"{\"torrent\":\"aaaa\",\"file\":\"movie.mkv\",\"size\":4000000000},"
        @"{\"torrent\":\"bbbb\",\"file\":\"other-torrent-huge.mkv\",\"size\":9000000000},"
        @"{\"torrent\":\"aaaa\",\"file\":\"movie.en.srt\",\"size\":40000},"
        @"{\"torrent\":\"aaaa\",\"file\":\"movie.flac\",\"size\":50000000}]}";
    MacLCTorrentSnapshot *snapshot = Parse(json);
    XCTAssertEqualObjects(snapshot.primaryReader.fileName, @"movie.mkv");

    /* Tie: the first one wins. */
    MacLCTorrentSnapshot *tie = Parse(@"{\"v\":1,\"active\":\"aaaa\",\"torrents\":[{\"key\":\"aaaa\"}],\"readers\":["
                                      @"{\"torrent\":\"aaaa\",\"file\":\"one\",\"size\":10},{\"torrent\":\"aaaa\",\"file\":\"two\",\"size\":10}]}");
    XCTAssertEqualObjects(tie.primaryReader.fileName, @"one");

    /* The active torrent has no reader (the other one does): none. */
    MacLCTorrentSnapshot *none = Parse(@"{\"v\":1,\"active\":\"aaaa\",\"torrents\":[{\"key\":\"aaaa\"},{\"key\":\"bbbb\"}],\"readers\":["
                                       @"{\"torrent\":\"bbbb\",\"file\":\"x\",\"size\":10}]}");
    XCTAssertNil(none.primaryReader);

    /* No active key: the last torrent's readers are considered. */
    MacLCTorrentSnapshot *last = Parse(@"{\"v\":1,\"active\":\"\",\"torrents\":[{\"key\":\"aaaa\"},{\"key\":\"bbbb\"}],\"readers\":["
                                       @"{\"torrent\":\"aaaa\",\"file\":\"a\",\"size\":99},{\"torrent\":\"bbbb\",\"file\":\"b\",\"size\":1}]}");
    XCTAssertEqualObjects(last.primaryReader.fileName, @"b");
}

#pragma mark - Derived values

- (void)testDerivedValues
{
    MacLCTorrentSnapshot *snapshot = Snap(@"", @"\"size\":1000,\"pos\":100,\"ahead\":200,\"ranges\":[[0,100],[900,1000]],\"need\":400");
    MacLCTorrentReaderInfo *r = snapshot.readers.firstObject;
    XCTAssertEqualWithAccuracy(r.headFraction, 0.3, 1e-12);
    XCTAssertEqualWithAccuracy(r.positionFraction, 0.1, 1e-12);
    NSArray<NSNumber *> *f = r.rangeFractions;
    XCTAssertEqual(f.count, 4);
    XCTAssertEqualWithAccuracy(f[0].doubleValue, 0.0, 1e-12);
    XCTAssertEqualWithAccuracy(f[1].doubleValue, 0.1, 1e-12);
    XCTAssertEqualWithAccuracy(f[2].doubleValue, 0.9, 1e-12);
    XCTAssertEqualWithAccuracy(f[3].doubleValue, 1.0, 1e-12);
    XCTAssertEqualWithAccuracy(r.bufferProgress, 0.5, 1e-12);

    /* Without the player's rate: ahead / (size / 6000 s) = 200 / (1000/6000). */
    XCTAssertEqualWithAccuracy(r.aheadSeconds, 1200.0, 1e-6);

    /* With it: ahead / rate. */
    MacLCTorrentReaderInfo *rated = [Snap(@"", @"\"size\":1000,\"ahead\":200,\"rate_in\":50") readers].firstObject;
    XCTAssertEqualWithAccuracy(rated.aheadSeconds, 4.0, 1e-9);

    /* Seconds to fill: (need - ahead) / download rate. */
    XCTAssertEqualWithAccuracy([r secondsToFillWithDownloadRate:100], 2.0, 1e-9);
    XCTAssertTrue([r secondsToFillWithDownloadRate:0] < 0);
    XCTAssertTrue([r secondsToFillWithDownloadRate:-5] < 0);
    MacLCTorrentReaderInfo *full = [Snap(@"", @"\"size\":1000,\"ahead\":400,\"need\":400") readers].firstObject;
    XCTAssertTrue([full secondsToFillWithDownloadRate:100] < 0);
    XCTAssertEqualWithAccuracy(full.bufferProgress, 1.0, 1e-12);
    MacLCTorrentReaderInfo *over = [Snap(@"", @"\"size\":1000,\"ahead\":900,\"need\":400") readers].firstObject;
    XCTAssertEqualWithAccuracy(over.bufferProgress, 1.0, 1e-12);
    MacLCTorrentReaderInfo *noGate = [Snap(@"", @"\"size\":1000,\"ahead\":0,\"need\":0") readers].firstObject;
    XCTAssertEqualWithAccuracy(noGate.bufferProgress, 1.0, 1e-12);
    XCTAssertTrue([noGate secondsToFillWithDownloadRate:100] < 0);
}

- (void)testDerivedValuesAreClamped
{
    /* A module that is slightly off (ranges or head past the end) never gives > 1. */
    MacLCTorrentReaderInfo *r = [Snap(@"", @"\"size\":1000,\"pos\":900,\"ahead\":500,\"ranges\":[[500,1500]]") readers].firstObject;
    XCTAssertEqualWithAccuracy(r.headFraction, 1.0, 1e-12);
    XCTAssertEqualWithAccuracy(r.rangeFractions[0].doubleValue, 0.5, 1e-12);
    XCTAssertEqualWithAccuracy(r.rangeFractions[1].doubleValue, 1.0, 1e-12);
    /* Unknown size: no fractions, no division by zero. */
    MacLCTorrentReaderInfo *s = [Snap(@"", @"\"size\":0,\"pos\":5,\"ahead\":5,\"ranges\":[[0,5]],\"need\":10") readers].firstObject;
    XCTAssertEqualWithAccuracy(s.headFraction, 0.0, 1e-12);
    XCTAssertEqualWithAccuracy(s.positionFraction, 0.0, 1e-12);
    XCTAssertEqual(s.rangeFractions.count, 0);
    XCTAssertEqualWithAccuracy(s.aheadSeconds, 0.0, 1e-12);
    XCTAssertEqualWithAccuracy(s.bufferProgress, 0.5, 1e-12);
}

#pragma mark - Formatter

- (void)testRateString
{
    XCTAssertEqualObjects([MacLCTorrentFormat rateString:0], @"0 KB/s");
    XCTAssertEqualObjects([MacLCTorrentFormat rateString:-5], @"0 KB/s");
    XCTAssertEqualObjects([MacLCTorrentFormat rateString:500], @"0.5 KB/s");
    XCTAssertEqualObjects([MacLCTorrentFormat rateString:4200], @"4.2 KB/s");
    XCTAssertEqualObjects([MacLCTorrentFormat rateString:9960], @"10 KB/s");
    XCTAssertEqualObjects([MacLCTorrentFormat rateString:820000], @"820 KB/s");
    XCTAssertEqualObjects([MacLCTorrentFormat rateString:999600], @"1.0 MB/s");
    XCTAssertEqualObjects([MacLCTorrentFormat rateString:4200000], @"4.2 MB/s");
    XCTAssertEqualObjects([MacLCTorrentFormat rateString:12345678], @"12 MB/s");
    XCTAssertEqualObjects([MacLCTorrentFormat rateString:1500000000], @"1.5 GB/s");
}

- (void)testSizeString
{
    XCTAssertEqualObjects([MacLCTorrentFormat sizeString:0], @"0 KB");
    XCTAssertEqualObjects([MacLCTorrentFormat sizeString:40000], @"40 KB");
    XCTAssertEqualObjects([MacLCTorrentFormat sizeString:3200000], @"3.2 MB");
    XCTAssertEqualObjects([MacLCTorrentFormat sizeString:512000000], @"512 MB");
    XCTAssertEqualObjects([MacLCTorrentFormat sizeString:1400000000], @"1.4 GB");
    XCTAssertEqualObjects([MacLCTorrentFormat sizeString:25165824], @"25 MB");
    XCTAssertEqualObjects([MacLCTorrentFormat sizeString:4300000000ULL], @"4.3 GB");
    XCTAssertEqualObjects([MacLCTorrentFormat sizeString:2500000000000ULL], @"2.5 TB");
}

- (void)testDurationString
{
    XCTAssertEqualObjects([MacLCTorrentFormat durationString:0], @"0 s");
    XCTAssertEqualObjects([MacLCTorrentFormat durationString:45], @"45 s");
    XCTAssertEqualObjects([MacLCTorrentFormat durationString:44.6], @"45 s");
    XCTAssertEqualObjects([MacLCTorrentFormat durationString:60], @"1 min");
    XCTAssertEqualObjects([MacLCTorrentFormat durationString:125], @"2 min 5 s");
    XCTAssertEqualObjects([MacLCTorrentFormat durationString:3599], @"59 min 59 s");
    XCTAssertEqualObjects([MacLCTorrentFormat durationString:3600], @"1 h");
    XCTAssertEqualObjects([MacLCTorrentFormat durationString:3780], @"1 h 3 min");
    XCTAssertEqualObjects([MacLCTorrentFormat durationString:-1], @"");
    XCTAssertEqualObjects([MacLCTorrentFormat durationString:NAN], @"");
    XCTAssertNotNil([MacLCTorrentFormat durationString:INFINITY]);
}

- (void)testRemainingString
{
    XCTAssertEqualObjects([MacLCTorrentFormat remainingString:40], @"About 40 s left");
    XCTAssertEqualObjects([MacLCTorrentFormat remainingString:42], @"About 40 s left");
    XCTAssertEqualObjects([MacLCTorrentFormat remainingString:8], @"About 10 s left");
    XCTAssertEqualObjects([MacLCTorrentFormat remainingString:5], @"About 5 s left");
    XCTAssertEqualObjects([MacLCTorrentFormat remainingString:0], @"Less than a minute left");
    XCTAssertEqualObjects([MacLCTorrentFormat remainingString:4.9], @"Less than a minute left");
    XCTAssertEqualObjects([MacLCTorrentFormat remainingString:58], @"About 1 min left");
    XCTAssertEqualObjects([MacLCTorrentFormat remainingString:125], @"About 2 min left");
    XCTAssertEqualObjects([MacLCTorrentFormat remainingString:3780], @"About 1 h 3 min left");
    XCTAssertEqualObjects([MacLCTorrentFormat remainingString:-1], @"");
    XCTAssertEqualObjects([MacLCTorrentFormat remainingString:NAN], @"");
}

- (void)testStageTitles
{
    XCTAssertEqualObjects([MacLCTorrentFormat titleForStage:MacLCTorrentStageTrackers], @"Finding peers");
    XCTAssertEqualObjects([MacLCTorrentFormat titleForStage:MacLCTorrentStageMetadata], @"Getting the file list");
    XCTAssertEqualObjects([MacLCTorrentFormat titleForStage:MacLCTorrentStageConnecting], @"Connecting to peers");
    XCTAssertEqualObjects([MacLCTorrentFormat titleForStage:MacLCTorrentStageDownloading], @"Receiving data");
    XCTAssertEqualObjects([MacLCTorrentFormat titleForStage:MacLCTorrentStageBuffering], @"Filling the buffer");
    XCTAssertEqualObjects([MacLCTorrentFormat titleForStage:MacLCTorrentStageReady], @"Starting");
    XCTAssertEqualObjects([MacLCTorrentFormat titleForStage:MacLCTorrentStagePlaying], @"Playing");
    XCTAssertEqualObjects([MacLCTorrentFormat titleForStage:MacLCTorrentStageStalled], @"Buffering");
    XCTAssertEqualObjects([MacLCTorrentFormat titleForStage:MacLCTorrentStageFailed], @"Can't download");
    XCTAssertEqualObjects([MacLCTorrentFormat titleForStage:MacLCTorrentStageUnknown], @"");
}

- (void)testPeersString
{
    XCTAssertEqualObjects([MacLCTorrentFormat peersString:Snap(@"\"peers\":14,\"seeds\":6", nil).torrents.firstObject],
                          @"14 peers · 6 seeds");
    XCTAssertEqualObjects([MacLCTorrentFormat peersString:Snap(@"\"peers\":1,\"seeds\":1", nil).torrents.firstObject],
                          @"1 peer · 1 seed");
    XCTAssertEqualObjects([MacLCTorrentFormat peersString:Snap(@"", nil).torrents.firstObject],
                          @"0 peers · 0 seeds");
    XCTAssertEqualObjects([MacLCTorrentFormat peersString:Snap(@"\"peers\":2,\"seeds\":0", nil).torrents.firstObject],
                          @"2 peers · 0 seeds");
}

- (void)testExplanations
{
    MacLCTorrentSnapshot *s;

    s = Snap(@"\"stage\":\"trackers\"", nil);
    XCTAssertEqualObjects([MacLCTorrentFormat explanationForTorrent:s.activeTorrent reader:nil],
                          @"Asking the trackers and the network who has this.");

    s = Snap(@"\"stage\":\"metadata\",\"peers\":5", nil);
    XCTAssertEqualObjects([MacLCTorrentFormat explanationForTorrent:s.activeTorrent reader:nil],
                          @"5 peers answered. Asking them for the list of files.");
    s = Snap(@"\"stage\":\"metadata\",\"peers\":1", nil);
    XCTAssertEqualObjects([MacLCTorrentFormat explanationForTorrent:s.activeTorrent reader:nil],
                          @"1 peer answered. Asking them for the list of files.");

    s = Snap(@"\"stage\":\"connecting\",\"peers\":9,\"peers_connecting\":3,\"swarm_seeds\":312,\"swarm_leechers\":54", nil);
    XCTAssertEqualObjects([MacLCTorrentFormat explanationForTorrent:s.activeTorrent reader:nil],
                          @"Found the files. Connecting to 12 of 366 peers.");
    s = Snap(@"\"stage\":\"connecting\",\"peers\":1", nil);
    XCTAssertEqualObjects([MacLCTorrentFormat explanationForTorrent:s.activeTorrent reader:nil],
                          @"Found the files. Connecting to 1 peer.");
    s = Snap(@"\"stage\":\"connecting\"", nil);
    XCTAssertEqualObjects([MacLCTorrentFormat explanationForTorrent:s.activeTorrent reader:nil],
                          @"Found the files. Looking for peers that send data.");

    s = Snap(@"\"stage\":\"downloading\",\"peers\":9,\"peers_unchoked\":4,\"down\":4200000", nil);
    XCTAssertEqualObjects([MacLCTorrentFormat explanationForTorrent:s.activeTorrent reader:nil],
                          @"Receiving data from 4 peers at 4.2 MB/s.");
    s = Snap(@"\"stage\":\"downloading\",\"peers\":1", nil);
    XCTAssertEqualObjects([MacLCTorrentFormat explanationForTorrent:s.activeTorrent reader:nil],
                          @"Receiving data from 1 peer.");
    s = Snap(@"\"stage\":\"downloading\"", nil);
    XCTAssertEqualObjects([MacLCTorrentFormat explanationForTorrent:s.activeTorrent reader:nil],
                          @"Waiting for peers to send data.");

    /* Buffering: 15.25 MB of 25 MB = 61 %, 9.75 MB to go at 1 MB/s. */
    s = Snap(@"\"stage\":\"buffering\",\"down\":1000000", @"\"stage\":\"buffering\",\"size\":4000000000,\"ahead\":15250000,\"need\":25000000");
    XCTAssertEqualObjects([MacLCTorrentFormat explanationForTorrent:s.activeTorrent reader:s.primaryReader],
                          @"Downloading the first 25 MB so playback won't stop: 61 % there, about 10 s left.");
    s = Snap(@"\"stage\":\"buffering\"", @"\"stage\":\"buffering\",\"size\":4000000000,\"ahead\":15250000,\"need\":25000000");
    XCTAssertEqualObjects([MacLCTorrentFormat explanationForTorrent:s.activeTorrent reader:s.primaryReader],
                          @"Downloading the first 25 MB so playback won't stop: 61 % there.");
    s = Snap(@"\"stage\":\"buffering\"", nil);
    XCTAssertEqualObjects([MacLCTorrentFormat explanationForTorrent:s.activeTorrent reader:nil],
                          @"Downloading the first part so playback won't stop.");

    s = Snap(@"\"stage\":\"playing\"", @"\"stage\":\"ready\",\"size\":1000");
    XCTAssertEqualObjects([MacLCTorrentFormat explanationForTorrent:s.activeTorrent reader:s.primaryReader],
                          @"The start buffer is full. Starting playback.");

    /* Playing: 180 MB at 1.1 MB/s consumed = 164 s ahead. */
    s = Snap(@"\"stage\":\"playing\",\"down\":4200000", @"\"stage\":\"playing\",\"size\":4000000000,\"ahead\":180000000,\"rate_in\":1100000");
    XCTAssertEqualObjects([MacLCTorrentFormat explanationForTorrent:s.activeTorrent reader:s.primaryReader],
                          @"2 min 44 s of video is downloaded ahead of you, and more arrives at 4.2 MB/s.");
    s = Snap(@"\"stage\":\"playing\"", @"\"stage\":\"playing\",\"size\":4000000000,\"ahead\":180000000,\"rate_in\":1100000");
    XCTAssertEqualObjects([MacLCTorrentFormat explanationForTorrent:s.activeTorrent reader:s.primaryReader],
                          @"2 min 44 s of video is downloaded ahead of you.");

    s = Snap(@"\"stage\":\"playing\",\"peers_unchoked\":3", @"\"stage\":\"stalled\",\"size\":100");
    XCTAssertEqualObjects([MacLCTorrentFormat explanationForTorrent:s.activeTorrent reader:s.primaryReader],
                          @"Waiting for the next part: 3 peers are sending data.");
    s = Snap(@"\"stage\":\"stalled\",\"peers_unchoked\":1", nil);
    XCTAssertEqualObjects([MacLCTorrentFormat explanationForTorrent:s.activeTorrent reader:nil],
                          @"Waiting for the next part: 1 peer is sending data.");
    s = Snap(@"\"stage\":\"stalled\"", nil);
    XCTAssertEqualObjects([MacLCTorrentFormat explanationForTorrent:s.activeTorrent reader:nil],
                          @"Waiting for the next part: no peer is sending data right now.");

    s = Snap(@"\"stage\":\"error\",\"error\":\"No peer could be reached\"", nil);
    XCTAssertEqualObjects([MacLCTorrentFormat explanationForTorrent:s.activeTorrent reader:nil], @"No peer could be reached");
    s = Snap(@"\"stage\":\"error\"", nil);
    XCTAssertEqualObjects([MacLCTorrentFormat explanationForTorrent:s.activeTorrent reader:nil],
                          @"Something went wrong while downloading.");
    /* The torrent's error beats a reader that last said "playing". */
    s = Snap(@"\"stage\":\"error\",\"error\":\"disk full\"", @"\"stage\":\"playing\",\"size\":100");
    XCTAssertEqualObjects([MacLCTorrentFormat explanationForTorrent:s.activeTorrent reader:s.primaryReader], @"disk full");

    s = Snap(@"", nil);
    XCTAssertEqualObjects([MacLCTorrentFormat explanationForTorrent:s.activeTorrent reader:nil], @"");
    MacLCTorrentInfo *nothing = nil;
    XCTAssertEqualObjects([MacLCTorrentFormat explanationForTorrent:nothing reader:nil], @"");
    XCTAssertEqualObjects([MacLCTorrentFormat peersString:nothing], @"");
}

#pragma mark - Matching the current media

- (void)testBase32ToHex
{
    XCTAssertEqualObjects(MacLCTorrentHexFromBase32(kKeyBase32), kKey);
    XCTAssertEqualObjects(MacLCTorrentHexFromBase32(kKeyBase32.lowercaseString), kKey);
    XCTAssertEqualObjects(MacLCTorrentHexFromBase32(@"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"), @"0000000000000000000000000000000000000000");
    XCTAssertEqualObjects(MacLCTorrentHexFromBase32(@"77777777777777777777777777777777"), @"ffffffffffffffffffffffffffffffffffffffff");
    XCTAssertNil(MacLCTorrentHexFromBase32(nil));
    XCTAssertNil(MacLCTorrentHexFromBase32(@""));
    XCTAssertNil(MacLCTorrentHexFromBase32(@"CHVAEWGH6HM3JZVDKIFY3FHQYGTX4O3"));    /* 31 */
    XCTAssertNil(MacLCTorrentHexFromBase32(@"CHVAEWGH6HM3JZVDKIFY3FHQYGTX4O3CA"));  /* 33 */
    XCTAssertNil(MacLCTorrentHexFromBase32(@"CHVAEWGH6HM3JZVDKIFY3FHQYGTX4O31"));   /* '1' is not base32 */
    XCTAssertNil(MacLCTorrentHexFromBase32(@"CHVAEWGH6HM3JZVDKIFY3FHQYGTX4O3="));
    id notAString = @42;
    XCTAssertNil(MacLCTorrentHexFromBase32(notAString));
}

- (void)testKeyFromMRL
{
    XCTAssertEqualObjects(MacLCTorrentKeyFromMRL([@"magnet://?xt=urn:btih:" stringByAppendingString:kKey]), kKey);
    XCTAssertEqualObjects(MacLCTorrentKeyFromMRL([@"magnet:?xt=urn:btih:" stringByAppendingString:kKey.uppercaseString]), kKey);
    XCTAssertEqualObjects(MacLCTorrentKeyFromMRL([NSString stringWithFormat:@"magnet://?dn=x&xt=urn:btih:%@&tr=udp%%3A%%2F%%2Ft.example%%3A1%%2Fa#!/clip.mkv", kKey]), kKey);
    XCTAssertEqualObjects(MacLCTorrentKeyFromMRL([@"magnet://?xt=urn:btih:" stringByAppendingString:kKeyBase32]), kKey);
    XCTAssertEqualObjects(MacLCTorrentKeyFromMRL([@"magnet://?xt=urn:btih:" stringByAppendingString:kKeyBase32.lowercaseString]), kKey);
    XCTAssertEqualObjects(MacLCTorrentKeyFromMRL([@"magnet://?xt=urn%3Abtih%3A" stringByAppendingString:kKey]), kKey);
    XCTAssertEqualObjects(MacLCTorrentKeyFromMRL([@"MAGNET://?xt=URN:BTIH:" stringByAppendingString:kKey]), kKey);
    XCTAssertNil(MacLCTorrentKeyFromMRL([@"magnet://?xt=urn:btih:" stringByAppendingString:[kKey substringToIndex:39]]));
    XCTAssertNil(MacLCTorrentKeyFromMRL([@"magnet://?xt=urn:btih:" stringByAppendingString:[kKey stringByAppendingString:@"0"]]));
    XCTAssertNil(MacLCTorrentKeyFromMRL(@"magnet://?xt=urn:btmh:1220abcd"));
    XCTAssertNil(MacLCTorrentKeyFromMRL(@"file:///Users/me/Movies/x.torrent"));
    XCTAssertNil(MacLCTorrentKeyFromMRL(@"https://example.org/a.mkv"));
    XCTAssertNil(MacLCTorrentKeyFromMRL(@""));
    XCTAssertNil(MacLCTorrentKeyFromMRL(nil));
}

- (void)testFileNameFromMRL
{
    XCTAssertEqualObjects(MacLCTorrentFileNameFromMRL(@"magnet://?xt=urn:btih:aa#!/clip.mkv"), @"clip.mkv");
    XCTAssertEqualObjects(MacLCTorrentFileNameFromMRL(@"magnet://?xt=urn:btih:aa#!/Show%20S01E02%20%5B1080p%5D.mkv"), @"Show S01E02 [1080p].mkv");
    XCTAssertEqualObjects(MacLCTorrentFileNameFromMRL(@"magnet://?xt=urn:btih:aa#!/Show/Season%201/ep2.mkv"), @"ep2.mkv");
    XCTAssertEqualObjects(MacLCTorrentFileNameFromMRL(@"magnet://?xt=urn:btih:aa%23!/a.mkv"), @"a.mkv");
    XCTAssertEqualObjects(MacLCTorrentFileNameFromMRL(@"magnet://?xt=urn:btih:aa#!/50%zz.mkv"), @"50%zz.mkv");   /* undecodable: as is */
    XCTAssertEqualObjects(MacLCTorrentFileNameFromMRL(@"magnet://?xt=urn:btih:aa#!/caf%C3%A9.mkv"), @"café.mkv");
    XCTAssertNil(MacLCTorrentFileNameFromMRL(@"magnet://?xt=urn:btih:aa"));
    XCTAssertNil(MacLCTorrentFileNameFromMRL(@"magnet://?xt=urn:btih:aa#!/"));
    XCTAssertNil(MacLCTorrentFileNameFromMRL(@"magnet://?xt=urn:btih:aa#frag"));
    XCTAssertNil(MacLCTorrentFileNameFromMRL(@""));
    XCTAssertNil(MacLCTorrentFileNameFromMRL(nil));
}

@end
