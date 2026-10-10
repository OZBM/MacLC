/*****************************************************************************
 * MacLCStreamFactsTest.m: tests for MacLCStreamFacts, parsing, filter & ranking
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

#import "addons/MacLCStreamFacts.h"
#import "addons/MacLCAddons.h"

@interface MacLCAddonStream (TestInit)
- (instancetype)initWithAddon:(nullable MacLCAddon *)addon
                        label:(NSString *)label
                qualityTokens:(NSArray<NSString *> *)qualityTokens
                     headline:(NSString *)headline
                      details:(nullable NSString *)details
                     infoHash:(nullable NSString *)infoHash
                     filename:(nullable NSString *)filename
                     trackers:(NSArray<NSString *> *)trackers
                    directURL:(nullable NSURL *)directURL
            youTubeIdentifier:(nullable NSString *)youTubeIdentifier
                          MRL:(NSString *)MRL;
@end

@interface MacLCStreamFactsTest : XCTestCase
@end

@implementation MacLCStreamFactsTest

#pragma mark - 29 Fixture Streams from torrentio-tt0063350.json

- (void)testTorrentioFixtureStream00
{
    NSString *name = @"Torrentio\n4k HDR";
    NSString *title = @"Night Of The Living Dead 1968 Upscaled BluRay 2160p HDR10 HEVC LPCM 1.0 x265-E\n👤 3 💾 15.77 GB ⚙️ 1337x";
    NSString *filename = @"Night Of The Living Dead 1968.mkv";

    MacLCStreamFacts *facts = [MacLCStreamFacts factsForName:name title:title filename:filename];
    XCTAssertEqual(facts.resolution, MacLCStreamResolution4K);
    XCTAssertEqual(facts.dynamicRange, MacLCStreamDynamicRangeHDR10);
    XCTAssertEqual(facts.source, MacLCStreamSourceBluRay);
    XCTAssertNotNil(facts.audio);
    XCTAssertTrue(facts.audio.count > 0);
    XCTAssertEqualObjects(facts.audio.firstObject.format, @"PCM");
    XCTAssertEqualObjects(facts.audio.firstObject.channels, @"1.0");
    XCTAssertEqual(facts.languages.count, (NSUInteger)0);
    XCTAssertEqual(facts.seeders, (NSInteger)3);
    XCTAssertTrue(facts.sizeBytes > 15000000000ULL);
    XCTAssertEqualObjects(facts.provider, @"1337x");
    XCTAssertTrue([facts.editionNotes containsObject:@"UPSCALED"]);
}

- (void)testTorrentioFixtureStream01
{
    NSString *name = @"Torrentio\n4k";
    NSString *title = @"Night of the Living Dead 1968 2160p BluRay\n👤 39 💾 4.35 GB ⚙️ YTS";
    NSString *filename = @"Night.Of.The.Living.Dead.1968.2160p.4K.BluRay.x265.10bit.AAC5.1-[YTS.MX].mkv";

    MacLCStreamFacts *facts = [MacLCStreamFacts factsForName:name title:title filename:filename];
    XCTAssertEqual(facts.resolution, MacLCStreamResolution4K);
    XCTAssertEqual(facts.dynamicRange, MacLCStreamDynamicRangeUnknown);
    XCTAssertEqual(facts.source, MacLCStreamSourceBluRay);
    XCTAssertNotNil(facts.audio);
    XCTAssertTrue(facts.audio.count > 0);
    XCTAssertEqualObjects(facts.audio.firstObject.format, @"AAC");
    XCTAssertEqualObjects(facts.audio.firstObject.channels, @"5.1");
    XCTAssertEqual(facts.languages.count, (NSUInteger)0);
    XCTAssertEqual(facts.seeders, (NSInteger)39);
    XCTAssertTrue(facts.sizeBytes > 4000000000ULL);
    XCTAssertEqualObjects(facts.provider, @"YTS");
}

- (void)testTorrentioFixtureStream02
{
    NSString *name = @"Torrentio\n4k";
    NSString *title = @"Night.of.the.Living.Dead.1968.2160p.BluRay.REMUX.HEVC.SDR.LPCM.1.0-FGT\n👤 6 💾 55.47 GB ⚙️ RARBG";
    NSString *filename = @"Night.of.the.Living.Dead.1968.2160p.BluRay.REMUX.HEVC.SDR.LPCM.1.0-FGT.mkv";

    MacLCStreamFacts *facts = [MacLCStreamFacts factsForName:name title:title filename:filename];
    XCTAssertEqual(facts.resolution, MacLCStreamResolution4K);
    XCTAssertEqual(facts.dynamicRange, MacLCStreamDynamicRangeSDR);
    XCTAssertEqual(facts.source, MacLCStreamSourceRemux);
    XCTAssertNotNil(facts.audio);
    XCTAssertTrue(facts.audio.count > 0);
    XCTAssertEqualObjects(facts.audio.firstObject.format, @"PCM");
    XCTAssertEqualObjects(facts.audio.firstObject.channels, @"1.0");
    XCTAssertEqual(facts.languages.count, (NSUInteger)0);
    XCTAssertEqual(facts.seeders, (NSInteger)6);
    XCTAssertTrue(facts.sizeBytes > 50000000000ULL);
    XCTAssertEqualObjects(facts.provider, @"RARBG");
}

- (void)testTorrentioFixtureStream03
{
    NSString *name = @"Torrentio\n1080p";
    NSString *title = @"Night of the Living Dead 1968 1080p BluRay\n👤 100 💾 1.51 GB ⚙️ YTS";
    NSString *filename = @"Night.Of.The.Living.Dead.1968.1080p.BluRay.x264-[YTS.AM].mp4";

    MacLCStreamFacts *facts = [MacLCStreamFacts factsForName:name title:title filename:filename];
    XCTAssertEqual(facts.resolution, MacLCStreamResolution1080p);
    XCTAssertEqual(facts.source, MacLCStreamSourceBluRay);
    XCTAssertEqual(facts.languages.count, (NSUInteger)0);
    XCTAssertEqual(facts.seeders, (NSInteger)100);
    XCTAssertEqual(facts.health, MacLCStreamHealthExcellent);
    XCTAssertTrue(facts.sizeBytes > 1500000000ULL);
    XCTAssertEqualObjects(facts.provider, @"YTS");
}

- (void)testTorrentioFixtureStream04
{
    NSString *name = @"Torrentio\n1080p";
    NSString *title = @"Night.of.the.Living.Dead.1968.REMASTERED.1080p.BluRay.X264-AMIABLE\n👤 71 💾 9.85 GB ⚙️ RARBG";

    MacLCStreamFacts *facts = [MacLCStreamFacts factsForName:name title:title filename:nil];
    XCTAssertEqual(facts.resolution, MacLCStreamResolution1080p);
    XCTAssertEqual(facts.source, MacLCStreamSourceBluRay);
    XCTAssertEqual(facts.languages.count, (NSUInteger)0);
    XCTAssertEqual(facts.seeders, (NSInteger)71);
    XCTAssertTrue(facts.sizeBytes > 9000000000ULL);
    XCTAssertEqualObjects(facts.provider, @"RARBG");
    XCTAssertTrue([facts.editionNotes containsObject:@"REMASTERED"]);
}

- (void)testTorrentioFixtureStream05
{
    NSString *name = @"Torrentio\n1080p";
    NSString *title = @"Night Of The Living Dead Remastered Collection 1968 2009\nNight Of The Living Dead Remastered Collection - Horror 1968 2009 1080p/01 Night Of The Living Dead Remastered - Horror 1968 Eng Rus Multi Subs 1080p [H264-mp4].mp4\n👤 10 💾 7.34 GB ⚙️ TorrentGalaxy\nMulti Subs / 🇬🇧 / 🇷🇺";
    NSString *filename = @"01 Night Of The Living Dead Remastered - Horror 1968 Eng Rus Multi Subs 1080p [H264-mp4].mp4";

    MacLCStreamFacts *facts = [MacLCStreamFacts factsForName:name title:title filename:filename];
    XCTAssertEqual(facts.resolution, MacLCStreamResolution1080p);
    NSArray<NSString *> *expectedLangs = @[@"en", @"ru"];
    XCTAssertEqualObjects(facts.languages, expectedLangs);
    XCTAssertTrue(facts.isPack);
    XCTAssertEqual(facts.seeders, (NSInteger)10);
    XCTAssertTrue(facts.sizeBytes > 7000000000ULL);
    XCTAssertEqualObjects(facts.provider, @"TorrentGalaxy");
    XCTAssertTrue(facts.hasMultipleSubtitles);
}

- (void)testTorrentioFixtureStream06
{
    NSString *name = @"Torrentio\n1080p";
    NSString *title = @"Night of the Living Dead 1968 1080p BluRay x264-OFT\n👤 8 💾 3.99 GB ⚙️ ThePirateBay";
    NSString *filename = @"Night of the Living Dead 1968 1080p BluRay x264-OFT.mkv";

    MacLCStreamFacts *facts = [MacLCStreamFacts factsForName:name title:title filename:filename];
    XCTAssertEqual(facts.resolution, MacLCStreamResolution1080p);
    XCTAssertEqual(facts.source, MacLCStreamSourceBluRay);
    XCTAssertEqual(facts.languages.count, (NSUInteger)0);
    XCTAssertEqual(facts.seeders, (NSInteger)8);
    XCTAssertTrue(facts.sizeBytes > 3500000000ULL);
    XCTAssertEqualObjects(facts.provider, @"ThePirateBay");
}

- (void)testTorrentioFixtureStream07
{
    NSString *name = @"Torrentio\n1080p";
    NSString *title = @"George A. Romero's Dead Trilogy REMASTERED 1080p BluRay HEVC x265-SUBS\nNight Of The Living Dead 1968 CRITERION REMASTERED 1080p BluRay x265-RARBG.mp4\n👤 7 💾 1.51 GB ⚙️ ThePirateBay";
    NSString *filename = @"Night Of The Living Dead 1968 CRITERION REMASTERED 1080p BluRay x265-RARBG.mp4";

    MacLCStreamFacts *facts = [MacLCStreamFacts factsForName:name title:title filename:filename];
    XCTAssertEqual(facts.resolution, MacLCStreamResolution1080p);
    XCTAssertEqual(facts.source, MacLCStreamSourceBluRay);
    XCTAssertTrue(facts.isPack);
    XCTAssertEqual(facts.seeders, (NSInteger)7);
    XCTAssertTrue(facts.sizeBytes > 1500000000ULL);
    XCTAssertEqualObjects(facts.provider, @"ThePirateBay");
    XCTAssertTrue([facts.editionNotes containsObject:@"REMASTERED"]);
    XCTAssertTrue([facts.editionNotes containsObject:@"CRITERION"]);
}

- (void)testTorrentioFixtureStream08
{
    NSString *name = @"Torrentio\n1080p";
    NSString *title = @"Night of the Living Dead (1968) Remastered 1080p Bluray x264 Amiab\nNight.of.the.Living.Dead.1968.REMASTERED.1080p.BluRay.X264-AMIABLE.mp4\n👤 5 💾 531.52 MB ⚙️ EXT";
    NSString *filename = @"Night.of.the.Living.Dead.1968.REMASTERED.1080p.BluRay.X264-AMIABLE.mp4";

    MacLCStreamFacts *facts = [MacLCStreamFacts factsForName:name title:title filename:filename];
    XCTAssertEqual(facts.resolution, MacLCStreamResolution1080p);
    XCTAssertEqual(facts.source, MacLCStreamSourceBluRay);
    XCTAssertTrue(facts.isPack);
    XCTAssertEqual(facts.seeders, (NSInteger)5);
    XCTAssertTrue(facts.sizeBytes > 500000000ULL);
    XCTAssertEqualObjects(facts.provider, @"EXT");
    XCTAssertTrue([facts.editionNotes containsObject:@"REMASTERED"]);
}

- (void)testTorrentioFixtureStream09
{
    NSString *name = @"Torrentio\n1080p";
    NSString *title = @"Night of the Living Dead (1968) Remastered 1080p Bluray x264 Amiab\nNight.of.the.Living.Dead.1968.REMASTERED.1080p.BluRay.X264-AMIABLE.mkv\n👤 5 💾 9.84 GB ⚙️ EXT";
    NSString *filename = @"Night.of.the.Living.Dead.1968.REMASTERED.1080p.BluRay.X264-AMIABLE.mkv";

    MacLCStreamFacts *facts = [MacLCStreamFacts factsForName:name title:title filename:filename];
    XCTAssertEqual(facts.resolution, MacLCStreamResolution1080p);
    XCTAssertEqual(facts.source, MacLCStreamSourceBluRay);
    XCTAssertTrue(facts.isPack);
    XCTAssertEqual(facts.seeders, (NSInteger)5);
    XCTAssertTrue(facts.sizeBytes > 9000000000ULL);
    XCTAssertEqualObjects(facts.provider, @"EXT");
}

- (void)testTorrentioFixtureStream10
{
    NSString *name = @"Torrentio\n1080p";
    NSString *title = @"Night of the Living Dead (1968) 1080p Ita Eng MIRCrew\n👤 4 💾 2.02 GB ⚙️ ThePirateBay\n🇬🇧 / 🇮🇹";
    NSString *filename = @"La notte dei morti viventi - Night of the Living Dead (1968) 1080p h264 Ac3 Ita Eng Sub Ita Eng-MIRCrew.mkv";

    MacLCStreamFacts *facts = [MacLCStreamFacts factsForName:name title:title filename:filename];
    XCTAssertEqual(facts.resolution, MacLCStreamResolution1080p);
    NSArray<NSString *> *expectedLangs = @[@"en", @"it"];
    XCTAssertEqualObjects(facts.languages, expectedLangs);
    XCTAssertEqual(facts.seeders, (NSInteger)4);
    XCTAssertTrue(facts.sizeBytes > 2000000000ULL);
    XCTAssertEqualObjects(facts.provider, @"ThePirateBay");
}

- (void)testTorrentioFixtureStream11
{
    NSString *name = @"Torrentio\n1080p";
    NSString *title = @"Night of the Living Dead (1968) Criterion (1080p BluRay x265 HEVC 10bit AAC 1.0 Tigole) [QxR]\n👤 4 💾 5.8 GB ⚙️ 1337x";

    MacLCStreamFacts *facts = [MacLCStreamFacts factsForName:name title:title filename:nil];
    XCTAssertEqual(facts.resolution, MacLCStreamResolution1080p);
    XCTAssertEqual(facts.source, MacLCStreamSourceBluRay);
    XCTAssertNotNil(facts.audio);
    XCTAssertTrue(facts.audio.count > 0);
    XCTAssertEqualObjects(facts.audio.firstObject.format, @"AAC");
    XCTAssertEqualObjects(facts.audio.firstObject.channels, @"1.0");
    XCTAssertEqual(facts.seeders, (NSInteger)4);
    XCTAssertTrue(facts.sizeBytes > 5000000000ULL);
    XCTAssertEqualObjects(facts.provider, @"1337x");
    XCTAssertTrue([facts.editionNotes containsObject:@"CRITERION"]);
}

- (void)testTorrentioFixtureStream12
{
    NSString *name = @"Torrentio\n1080p";
    NSString *title = @"Night Of The Living Dead (1968) [1080p.BluRay.x264.AAC-YTS.AM] [Napisy PL]\n👤 1 💾 1.51 GB ⚙️ BestTorrents\n🇵🇱";
    NSString *filename = @"Night.Of.The.Living.Dead.1968.1080p.BluRay.x264-[YTS.AM].mp4";

    MacLCStreamFacts *facts = [MacLCStreamFacts factsForName:name title:title filename:filename];
    XCTAssertEqual(facts.resolution, MacLCStreamResolution1080p);
    XCTAssertEqual(facts.source, MacLCStreamSourceBluRay);
    NSArray<NSString *> *expectedLangs = @[@"pl"];
    XCTAssertEqualObjects(facts.languages, expectedLangs);
    XCTAssertTrue([facts.subtitleLanguages containsObject:@"pl"]);
    XCTAssertEqual(facts.seeders, (NSInteger)1);
    XCTAssertTrue(facts.sizeBytes > 1500000000ULL);
    XCTAssertEqualObjects(facts.provider, @"BestTorrents");
}

- (void)testTorrentioFixtureStream13
{
    NSString *name = @"Torrentio\n1080p";
    NSString *title = @"Zombies Movies Collection 1080p AV1 AC3/Opus ITA/ENG Multisub\n(1968) La Notte Dei Morti Viventi - Night Of The Living Dead.mkv\n👤 1 💾 924.45 MB ⚙️ ilCorSaRoNeRo\nMulti Subs / 🇬🇧 / 🇮🇹";
    NSString *filename = @"(1968) La Notte Dei Morti Viventi - Night Of The Living Dead.mkv";

    MacLCStreamFacts *facts = [MacLCStreamFacts factsForName:name title:title filename:filename];
    XCTAssertEqual(facts.resolution, MacLCStreamResolution1080p);
    XCTAssertEqual(facts.videoCodec, MacLCStreamVideoCodecAV1);
    XCTAssertTrue(facts.isPack);
    NSArray<NSString *> *expectedLangs = @[@"en", @"it"];
    XCTAssertEqualObjects(facts.languages, expectedLangs);
    XCTAssertEqual(facts.seeders, (NSInteger)1);
    XCTAssertTrue(facts.sizeBytes > 900000000ULL);
    XCTAssertEqualObjects(facts.provider, @"ilCorSaRoNeRo");
    XCTAssertTrue(facts.hasMultipleSubtitles);
}

- (void)testTorrentioFixtureStream14
{
    NSString *name = @"Torrentio\n1080p";
    NSString *title = @"La noche de los muertos vivientes 1968 [BluRay 1080p][AC3 2.0 Castellano AC3 5.1-Ingles+Subs][ES-EN]\n👤 1 💾 10.77 GB ⚙️ Wolfmax4k\n🇬🇧 / 🇪🇸";
    NSString *filename = @"La noche de los muertos vivientes 1968 BD1080.www.pctnew.org.mkv";

    MacLCStreamFacts *facts = [MacLCStreamFacts factsForName:name title:title filename:filename];
    XCTAssertEqual(facts.resolution, MacLCStreamResolution1080p);
    XCTAssertEqual(facts.source, MacLCStreamSourceBluRay);
    NSArray<NSString *> *expectedLangs = @[@"en", @"es"];
    XCTAssertEqualObjects(facts.languages, expectedLangs);
    XCTAssertEqual(facts.seeders, (NSInteger)1);
    XCTAssertTrue(facts.sizeBytes > 10000000000ULL);
    XCTAssertEqualObjects(facts.provider, @"Wolfmax4k");
}

- (void)testTorrentioFixtureStream15
{
    NSString *name = @"Torrentio\n1080p";
    NSString *title = @"Night Of The Living Dead 1968 Remastered BDRip 1080p Ita Eng X265-NAHOM\n👤 1 💾 2.61 GB ⚙️ MagnetDL\n🇬🇧 / 🇮🇹";
    NSString *filename = @"Night of the Living Dead 1968 Remastered BDRip 1080p Ita Eng x265-NAHOM.mkv";

    MacLCStreamFacts *facts = [MacLCStreamFacts factsForName:name title:title filename:filename];
    XCTAssertEqual(facts.resolution, MacLCStreamResolution1080p);
    XCTAssertEqual(facts.source, MacLCStreamSourceBluRay);
    NSArray<NSString *> *expectedLangs = @[@"en", @"it"];
    XCTAssertEqualObjects(facts.languages, expectedLangs);
    XCTAssertEqual(facts.seeders, (NSInteger)1);
    XCTAssertTrue(facts.sizeBytes > 2500000000ULL);
    XCTAssertEqualObjects(facts.provider, @"MagnetDL");
    XCTAssertTrue([facts.editionNotes containsObject:@"REMASTERED"]);
}

- (void)testTorrentioFixtureStream16
{
    NSString *name = @"Torrentio\n720p";
    NSString *title = @"Night of the Living Dead 1968 Remastered 720p BluRay x264 DuaL-TURKO\n👤 46 💾 925.34 MB ⚙️ ThePirateBay\nDual Audio / 🇹🇷";
    NSString *filename = @"Night of the Living Dead 1968 Remastered 720p BluRay x264 DuaL-TURKO.mkv";

    MacLCStreamFacts *facts = [MacLCStreamFacts factsForName:name title:title filename:filename];
    XCTAssertEqual(facts.resolution, MacLCStreamResolution720p);
    XCTAssertEqual(facts.source, MacLCStreamSourceBluRay);
    NSArray<NSString *> *expectedLangs = @[@"tr"];
    XCTAssertEqualObjects(facts.languages, expectedLangs);
    XCTAssertTrue(facts.isMultiLanguage);
    XCTAssertEqual(facts.seeders, (NSInteger)46);
    XCTAssertTrue(facts.sizeBytes > 900000000ULL);
    XCTAssertEqualObjects(facts.provider, @"ThePirateBay");
    XCTAssertTrue([facts.editionNotes containsObject:@"REMASTERED"]);
}

- (void)testTorrentioFixtureStream17
{
    NSString *name = @"Torrentio\n720p";
    NSString *title = @"La noche de los muertos vivientes Estallido zombi (2026) [Bluray 720p][Esp]\n👤 30 💾 2.43 GB ⚙️ Wolfmax4k\n🇪🇸";
    NSString *filename = @"La noche de los muertos vivientes Estallido zombi (2026) [Bluray 720p][Esp].mkv";

    MacLCStreamFacts *facts = [MacLCStreamFacts factsForName:name title:title filename:filename];
    XCTAssertEqual(facts.resolution, MacLCStreamResolution720p);
    XCTAssertEqual(facts.source, MacLCStreamSourceBluRay);
    NSArray<NSString *> *expectedLangs = @[@"es"];
    XCTAssertEqualObjects(facts.languages, expectedLangs);
    XCTAssertEqual(facts.seeders, (NSInteger)30);
    XCTAssertTrue(facts.sizeBytes > 2000000000ULL);
    XCTAssertEqualObjects(facts.provider, @"Wolfmax4k");
}

- (void)testTorrentioFixtureStream18
{
    NSString *name = @"Torrentio\n720p";
    NSString *title = @"Night of the Living Dead 1968 720p BluRay\n👤 28 💾 790.37 MB ⚙️ YTS";
    NSString *filename = @"Night.Of.The.Living.Dead.1968.720p.BluRay.x264-[YTS.AM].mp4";

    MacLCStreamFacts *facts = [MacLCStreamFacts factsForName:name title:title filename:filename];
    XCTAssertEqual(facts.resolution, MacLCStreamResolution720p);
    XCTAssertEqual(facts.source, MacLCStreamSourceBluRay);
    XCTAssertEqual(facts.languages.count, (NSUInteger)0);
    XCTAssertEqual(facts.seeders, (NSInteger)28);
    XCTAssertTrue(facts.sizeBytes > 700000000ULL);
    XCTAssertEqualObjects(facts.provider, @"YTS");
}

- (void)testTorrentioFixtureStream19
{
    NSString *name = @"Torrentio\n720p";
    NSString *title = @"Night Of The Living Dead 1968 720p BRRip x264-x0r\n👤 28 💾 1.62 GB ⚙️ ThePirateBay";

    MacLCStreamFacts *facts = [MacLCStreamFacts factsForName:name title:title filename:nil];
    XCTAssertEqual(facts.resolution, MacLCStreamResolution720p);
    XCTAssertEqual(facts.source, MacLCStreamSourceBluRay);
    XCTAssertEqual(facts.languages.count, (NSUInteger)0);
    XCTAssertEqual(facts.seeders, (NSInteger)28);
    XCTAssertTrue(facts.sizeBytes > 1500000000ULL);
    XCTAssertEqualObjects(facts.provider, @"ThePirateBay");
}

- (void)testTorrentioFixtureStream20
{
    NSString *name = @"Torrentio";
    NSString *title = @"101 Horror Movies Mega Pack Mixed x264 [i c]\nNight of the Living Dead 1968.mkv\n👤 12 💾 2.22 GB ⚙️ TorrentGalaxy";
    NSString *filename = @"Night of the Living Dead 1968.mkv";

    MacLCStreamFacts *facts = [MacLCStreamFacts factsForName:name title:title filename:filename];
    XCTAssertTrue(facts.isPack);
    XCTAssertEqual(facts.seeders, (NSInteger)12);
    XCTAssertTrue(facts.sizeBytes > 2000000000ULL);
    XCTAssertEqualObjects(facts.provider, @"TorrentGalaxy");
}

- (void)testTorrentioFixtureStream21
{
    NSString *name = @"Torrentio";
    NSString *title = @"Adam Curtis Collection (Century of the Self The Trap etc.)\nThe Living Dead (1995)/The Living Dead - 02 - You Have Used Me as a Fish Long Enough.avi\n👤 11 💾 474.51 MB ⚙️ ThePirateBay";
    NSString *filename = @"The Living Dead - 02 - You Have Used Me as a Fish Long Enough.avi";

    MacLCStreamFacts *facts = [MacLCStreamFacts factsForName:name title:title filename:filename];
    XCTAssertTrue(facts.isPack);
    XCTAssertEqual(facts.seeders, (NSInteger)11);
    XCTAssertTrue(facts.sizeBytes > 400000000ULL);
    XCTAssertEqualObjects(facts.provider, @"ThePirateBay");
}

- (void)testTorrentioFixtureStream22
{
    NSString *name = @"Torrentio";
    NSString *title = @"Adam Curtis Collection (Century of the Self The Trap etc.)\nThe Living Dead (1995)/The Living Dead - 03 - The Attic.avi\n👤 11 💾 476.94 MB ⚙️ ThePirateBay";
    NSString *filename = @"The Living Dead - 03 - The Attic.avi";

    MacLCStreamFacts *facts = [MacLCStreamFacts factsForName:name title:title filename:filename];
    XCTAssertTrue(facts.isPack);
    XCTAssertEqual(facts.seeders, (NSInteger)11);
    XCTAssertTrue(facts.sizeBytes > 400000000ULL);
    XCTAssertEqualObjects(facts.provider, @"ThePirateBay");
}

- (void)testTorrentioFixtureStream23
{
    NSString *name = @"Torrentio";
    NSString *title = @"Adam Curtis Collection (Century of the Self The Trap etc.)\nThe Living Dead (1995)/The Living Dead - 01 - On the Desperate Edge of Now.avi\n👤 11 💾 470.56 MB ⚙️ ThePirateBay";
    NSString *filename = @"The Living Dead - 01 - On the Desperate Edge of Now.avi";

    MacLCStreamFacts *facts = [MacLCStreamFacts factsForName:name title:title filename:filename];
    XCTAssertTrue(facts.isPack);
    XCTAssertEqual(facts.seeders, (NSInteger)11);
    XCTAssertTrue(facts.sizeBytes > 400000000ULL);
    XCTAssertEqualObjects(facts.provider, @"ThePirateBay");
}

- (void)testTorrentioFixtureStream24
{
    NSString *name = @"Torrentio";
    NSString *title = @"horor\nzombies/George A. Romero's Dead Series/Originals/1) Night of the Living Dead (1968).avi\n👤 6 💾 700.23 MB ⚙️ Wolfmax4k\n🇪🇸";
    NSString *filename = @"1) Night of the Living Dead (1968).avi";

    MacLCStreamFacts *facts = [MacLCStreamFacts factsForName:name title:title filename:filename];
    XCTAssertTrue(facts.isPack);
    NSArray<NSString *> *expectedLangs = @[@"es"];
    XCTAssertEqualObjects(facts.languages, expectedLangs);
    XCTAssertEqual(facts.seeders, (NSInteger)6);
    XCTAssertTrue(facts.sizeBytes > 700000000ULL);
    XCTAssertEqualObjects(facts.provider, @"Wolfmax4k");
}

- (void)testTorrentioFixtureStream25
{
    NSString *name = @"Torrentio";
    NSString *title = @"101 Horror Movies Mega Pack Vol 6 Mixed x264 [i c]\nNight of the Living Dead (In Color) (1968).mkv\n👤 5 💾 991.01 MB ⚙️ TorrentGalaxy";
    NSString *filename = @"Night of the Living Dead (In Color) (1968).mkv";

    MacLCStreamFacts *facts = [MacLCStreamFacts factsForName:name title:title filename:filename];
    XCTAssertTrue(facts.isPack);
    XCTAssertEqual(facts.seeders, (NSInteger)5);
    XCTAssertTrue(facts.sizeBytes > 900000000ULL);
    XCTAssertEqualObjects(facts.provider, @"TorrentGalaxy");
}

- (void)testTorrentioFixtureStream26
{
    NSString *name = @"Torrentio";
    NSString *title = @"101 Horror Movies Mega Pack Vol 6 Mixed x264 [i c]\nNight of the Living Dead (40th Anniversary Edition).mkv\n👤 5 💾 1.31 GB ⚙️ TorrentGalaxy";
    NSString *filename = @"Night of the Living Dead (40th Anniversary Edition).mkv";

    MacLCStreamFacts *facts = [MacLCStreamFacts factsForName:name title:title filename:filename];
    XCTAssertTrue(facts.isPack);
    XCTAssertEqual(facts.seeders, (NSInteger)5);
    XCTAssertTrue(facts.sizeBytes > 1000000000ULL);
    XCTAssertEqualObjects(facts.provider, @"TorrentGalaxy");
}

- (void)testTorrentioFixtureStream27
{
    NSString *name = @"Torrentio";
    NSString *title = @"101 Horror Movies Mega Pack Vol 6 Mixed x264 [i c]\nNight of the Living Dead (1968).mkv\n👤 5 💾 1.64 GB ⚙️ TorrentGalaxy";
    NSString *filename = @"Night of the Living Dead (1968).mkv";

    MacLCStreamFacts *facts = [MacLCStreamFacts factsForName:name title:title filename:filename];
    XCTAssertTrue(facts.isPack);
    XCTAssertEqual(facts.seeders, (NSInteger)5);
    XCTAssertTrue(facts.sizeBytes > 1500000000ULL);
    XCTAssertEqualObjects(facts.provider, @"TorrentGalaxy");
}

- (void)testTorrentioFixtureStream28
{
    NSString *name = @"Torrentio";
    NSString *title = @"Night Of The Living Dead 30th Aniversary Edition\n👤 1 💾 4.37 GB ⚙️ ThePirateBay";

    MacLCStreamFacts *facts = [MacLCStreamFacts factsForName:name title:title filename:nil];
    XCTAssertFalse(facts.isPack);
    XCTAssertEqual(facts.seeders, (NSInteger)1);
    XCTAssertTrue(facts.sizeBytes > 4000000000ULL);
    XCTAssertEqualObjects(facts.provider, @"ThePirateBay");
}

#pragma mark - Specific Releases Required by Specification

- (void)testDuneRelease
{
    NSString *title = @"Dune.Part.Two.2024.2160p.UHD.BluRay.x265.TrueHD.Atmos.7.1.DV.HDR10-FraMeSToR";
    MacLCStreamFacts *facts = [MacLCStreamFacts factsForName:nil title:title filename:nil];

    XCTAssertEqual(facts.resolution, MacLCStreamResolution4K);
    XCTAssertEqual(facts.dynamicRange, MacLCStreamDynamicRangeDolbyVision);
    NSArray<NSString *> *expectedHDR = @[@"Dolby Vision", @"HDR10"];
    XCTAssertEqualObjects(facts.hdrFormats, expectedHDR);
    XCTAssertEqual(facts.source, MacLCStreamSourceBluRay);
    XCTAssertNotNil(facts.audio);
    XCTAssertTrue(facts.audio.count > 0);
    MacLCStreamAudio *firstAud = facts.audio.firstObject;
    XCTAssertEqualObjects(firstAud.format, @"Dolby Atmos");
    XCTAssertEqualObjects(firstAud.channels, @"7.1");
    XCTAssertTrue(firstAud.isLossless);
    XCTAssertTrue(firstAud.isImmersive);
}

- (void)testHDCAMMovie
{
    NSString *title = @"Movie.2025.HDCAM.x264-XYZ";
    MacLCStreamFacts *facts = [MacLCStreamFacts factsForName:nil title:title filename:nil];

    XCTAssertEqual(facts.source, MacLCStreamSourceCam);
    XCTAssertEqual(facts.verdict, MacLCStreamVerdictPoor);
    XCTAssertTrue([facts.cautions containsObject:@"Recorded in a cinema"]);
}

- (void)testDebridStream
{
    NSString *name = @"[RD+] Torrentio\n1080p";
    MacLCStreamFacts *facts = [MacLCStreamFacts factsForName:name title:nil filename:nil];

    XCTAssertEqualObjects(facts.debridService, @"Real-Debrid");
    XCTAssertEqual(facts.health, MacLCStreamHealthExcellent);
    XCTAssertEqual(facts.resolution, MacLCStreamResolution1080p);
}

- (void)testShowSeasonNoFileLine
{
    NSString *title = @"Show.S01.1080p.WEB-DL.DDP5.1.H.264-GRP";
    MacLCStreamFacts *facts = [MacLCStreamFacts factsForName:nil title:title filename:nil];

    XCTAssertEqual(facts.resolution, MacLCStreamResolution1080p);
    XCTAssertEqual(facts.source, MacLCStreamSourceWebDL);
    XCTAssertNotNil(facts.audio);
    XCTAssertTrue(facts.audio.count > 0);
    XCTAssertEqualObjects(facts.audio.firstObject.format, @"Dolby Digital Plus");
    XCTAssertEqualObjects(facts.audio.firstObject.channels, @"5.1");
    XCTAssertFalse(facts.isPack);
}

- (void)testFrenchRelease
{
    NSString *title = @"Le.Film.2020.FRENCH.1080p.BluRay.x264";
    MacLCStreamFacts *facts = [MacLCStreamFacts factsForName:nil title:title filename:nil];

    NSArray<NSString *> *expected = @[@"fr"];
    XCTAssertEqualObjects(facts.languages, expected);
}

- (void)testVOSTFRSubtitlesOnly
{
    NSString *title = @"Film.2021.VOSTFR.1080p.WEB";
    MacLCStreamFacts *facts = [MacLCStreamFacts factsForName:nil title:title filename:nil];

    NSArray<NSString *> *expectedSubs = @[@"fr"];
    XCTAssertEqualObjects(facts.subtitleLanguages, expectedSubs);
    XCTAssertEqual(facts.languages.count, (NSUInteger)0);
}

- (void)testMultiVFFHDR10Plus
{
    NSString *title = @"Title.2019.MULTi.VFF.2160p.WEB-DL.HDR10Plus";
    MacLCStreamFacts *facts = [MacLCStreamFacts factsForName:nil title:title filename:nil];

    XCTAssertTrue(facts.isMultiLanguage);
    NSArray<NSString *> *expectedLangs = @[@"fr"];
    XCTAssertEqualObjects(facts.languages, expectedLangs);
    XCTAssertEqual(facts.resolution, MacLCStreamResolution4K);
    XCTAssertEqual(facts.dynamicRange, MacLCStreamDynamicRangeHDR10Plus);
    NSArray<NSString *> *expectedHDR = @[@"HDR10+"];
    XCTAssertEqualObjects(facts.hdrFormats, expectedHDR);
}

- (void)testTheSpanishPrisoner
{
    NSString *title = @"The.Spanish.Prisoner.1997.1080p.BluRay";
    MacLCStreamFacts *facts = [MacLCStreamFacts factsForName:nil title:title filename:nil];

    XCTAssertFalse([facts.languages containsObject:@"es"]);
}

- (void)testSizeParsingFormats
{
    MacLCStreamFacts *f1 = [MacLCStreamFacts factsForName:nil title:@"Film 2024\n15.77 GB" filename:nil];
    XCTAssertTrue(f1.sizeBytes > 15000000000ULL);

    MacLCStreamFacts *f2 = [MacLCStreamFacts factsForName:nil title:@"Film 2024\n531.52 MB" filename:nil];
    XCTAssertTrue(f2.sizeBytes > 500000000ULL);

    MacLCStreamFacts *f3 = [MacLCStreamFacts factsForName:nil title:@"Film 2024\n1,2 GB" filename:nil];
    XCTAssertTrue(f3.sizeBytes > 1200000000ULL);
}

#pragma mark - Filter & Ranking Tests

- (void)testFilterLanguageKeepsMultiAfterNamed
{
    MacLCStreamFacts *namedFacts = [MacLCStreamFacts factsForName:@"Torrentio\n1080p"
                                                           title:@"Film.2024.FRENCH.1080p.BluRay\n👤 50"
                                                        filename:nil];
    MacLCStreamFacts *multiFacts = [MacLCStreamFacts factsForName:@"Torrentio\n1080p"
                                                           title:@"Film.2024.MULTi.1080p.BluRay\n👤 50"
                                                        filename:nil];
    MacLCStreamFacts *otherFacts = [MacLCStreamFacts factsForName:@"Torrentio\n1080p"
                                                           title:@"Film.2024.GERMAN.1080p.BluRay\n👤 50"
                                                        filename:nil];

    MacLCStreamChoice *choiceNamed = [[MacLCStreamChoice alloc] initWithFacts:namedFacts identifier:@"id-french"];
    MacLCStreamChoice *choiceMulti = [[MacLCStreamChoice alloc] initWithFacts:multiFacts identifier:@"id-multi"];
    MacLCStreamChoice *choiceOther = [[MacLCStreamChoice alloc] initWithFacts:otherFacts identifier:@"id-german"];

    MacLCStreamFilter *filter = [[MacLCStreamFilter alloc] init];
    filter.language = @"fr";

    NSArray<MacLCStreamChoice *> *input = @[choiceMulti, choiceNamed, choiceOther];
    NSArray<MacLCStreamChoice *> *result = [filter apply:input];

    XCTAssertEqual(result.count, (NSUInteger)2);
    XCTAssertEqualObjects(result[0].identifier, @"id-french");
    XCTAssertEqualObjects(result[1].identifier, @"id-multi");
}

- (void)testFilterHidePoorCount
{
    MacLCStreamFacts *goodFacts = [MacLCStreamFacts factsForName:@"Torrentio\n1080p"
                                                          title:@"Film.2024.1080p.BluRay\n👤 50"
                                                       filename:nil];
    MacLCStreamFacts *poorFacts1 = [MacLCStreamFacts factsForName:@"Torrentio\nCam"
                                                           title:@"Film.2024.HDCAM.x264\n👤 10"
                                                        filename:nil];
    MacLCStreamFacts *poorFacts2 = [MacLCStreamFacts factsForName:@"Torrentio\nTS"
                                                           title:@"Film.2024.HDTS.x264\n👤 0"
                                                        filename:nil];

    MacLCStreamChoice *cGood = [[MacLCStreamChoice alloc] initWithFacts:goodFacts identifier:@"good"];
    MacLCStreamChoice *cPoor1 = [[MacLCStreamChoice alloc] initWithFacts:poorFacts1 identifier:@"poor1"];
    MacLCStreamChoice *cPoor2 = [[MacLCStreamChoice alloc] initWithFacts:poorFacts2 identifier:@"poor2"];

    NSArray<MacLCStreamChoice *> *choices = @[cGood, cPoor1, cPoor2];
    MacLCStreamFilter *filter = [[MacLCStreamFilter alloc] init];
    filter.hidePoor = YES;

    XCTAssertEqual([filter hiddenCountIn:choices], (NSUInteger)2);
    NSArray<MacLCStreamChoice *> *applied = [filter apply:choices];
    XCTAssertEqual(applied.count, (NSUInteger)1);
    XCTAssertEqualObjects(applied[0].identifier, @"good");
}

- (void)testFilterSortOrders
{
    MacLCStreamFacts *f4k = [MacLCStreamFacts factsForName:@"Torrentio\n4k"
                                                    title:@"Film.2024.2160p.BluRay.REMUX\n👤 50 💾 40.0 GB"
                                                 filename:nil];
    MacLCStreamFacts *f1080p = [MacLCStreamFacts factsForName:@"Torrentio\n1080p"
                                                       title:@"Film.2024.1080p.BluRay\n👤 100 💾 2.0 GB"
                                                    filename:nil];
    MacLCStreamFacts *fDebrid = [MacLCStreamFacts factsForName:@"[RD+] Torrentio\n1080p"
                                                        title:@"Film.2024.1080p.BluRay\n💾 10.0 GB"
                                                     filename:nil];

    MacLCStreamChoice *c4k = [[MacLCStreamChoice alloc] initWithFacts:f4k identifier:@"c4k"];
    MacLCStreamChoice *c1080p = [[MacLCStreamChoice alloc] initWithFacts:f1080p identifier:@"c1080p"];
    MacLCStreamChoice *cDebrid = [[MacLCStreamChoice alloc] initWithFacts:fDebrid identifier:@"cDebrid"];

    NSArray<MacLCStreamChoice *> *choices = @[c4k, c1080p, cDebrid];
    MacLCStreamFilter *filter = [[MacLCStreamFilter alloc] init];

    // 1. MostShared: debrid first, then highest seeds
    filter.sortOrder = MacLCStreamSortMostShared;
    NSArray<MacLCStreamChoice *> *sharedOrder = [filter apply:choices];
    XCTAssertEqualObjects(sharedOrder[0].identifier, @"cDebrid");
    XCTAssertEqualObjects(sharedOrder[1].identifier, @"c1080p");
    XCTAssertEqualObjects(sharedOrder[2].identifier, @"c4k");

    // 2. HighestQuality: 4K first
    filter.sortOrder = MacLCStreamSortHighestQuality;
    NSArray<MacLCStreamChoice *> *qualityOrder = [filter apply:choices];
    XCTAssertEqualObjects(qualityOrder[0].identifier, @"c4k");

    // 3. Smallest: 2.0 GB first, then 10.0 GB, then 40.0 GB
    filter.sortOrder = MacLCStreamSortSmallest;
    NSArray<MacLCStreamChoice *> *sizeOrder = [filter apply:choices];
    XCTAssertEqualObjects(sizeOrder[0].identifier, @"c1080p");
    XCTAssertEqualObjects(sizeOrder[1].identifier, @"cDebrid");
    XCTAssertEqualObjects(sizeOrder[2].identifier, @"c4k");

    // 4. Recommended: score order
    filter.sortOrder = MacLCStreamSortRecommended;
    NSArray<MacLCStreamChoice *> *recOrder = [filter apply:choices];
    XCTAssertTrue(recOrder.count == 3);
    XCTAssertTrue(recOrder[0].facts.score >= recOrder[1].facts.score);
    XCTAssertTrue(recOrder[1].facts.score >= recOrder[2].facts.score);
}

- (void)testBestMatchRequirements
{
    MacLCStreamFacts *poorFacts = [MacLCStreamFacts factsForName:@"Torrentio\nCam"
                                                          title:@"Film.2025.HDCAM\n👤 5"
                                                       filename:nil];
    MacLCStreamFacts *okayFacts = [MacLCStreamFacts factsForName:@"Torrentio\n720p"
                                                          title:@"Film.2024.720p.HDTV\n👤 10"
                                                       filename:nil];
    MacLCStreamFacts *greatFacts = [MacLCStreamFacts factsForName:@"Torrentio\n1080p"
                                                           title:@"Film.2024.1080p.BluRay\n👤 80"
                                                        filename:nil];

    MacLCStreamChoice *cPoor = [[MacLCStreamChoice alloc] initWithFacts:poorFacts identifier:@"poor"];
    MacLCStreamChoice *cOkay = [[MacLCStreamChoice alloc] initWithFacts:okayFacts identifier:@"okay"];
    MacLCStreamChoice *cGreat = [[MacLCStreamChoice alloc] initWithFacts:greatFacts identifier:@"great"];

    // 0 choices -> nil
    XCTAssertNil([MacLCStreamFilter bestMatchIn:@[]]);

    // 1 choice -> nil
    NSArray *oneChoice = @[cGreat];
    XCTAssertNil([MacLCStreamFilter bestMatchIn:oneChoice]);

    // 2 Poor choices -> nil
    NSArray *twoPoor = @[cPoor, cPoor];
    XCTAssertNil([MacLCStreamFilter bestMatchIn:twoPoor]);

    // 2 choices: 1 Okay, 1 Poor -> returns Okay
    NSArray *okayAndPoor = @[cOkay, cPoor];
    MacLCStreamChoice *bm2 = [MacLCStreamFilter bestMatchIn:okayAndPoor];
    XCTAssertNotNil(bm2);
    XCTAssertEqualObjects(bm2.identifier, @"okay");

    // 3 choices: Okay, Good/Great, Poor -> returns Great
    NSArray *threeChoices = @[cOkay, cGreat, cPoor];
    MacLCStreamChoice *bm3 = [MacLCStreamFilter bestMatchIn:threeChoices];
    XCTAssertNotNil(bm3);
    XCTAssertEqualObjects(bm3.identifier, @"great");
}

- (void)testLanguagesInCountsOrdering
{
    MacLCStreamFacts *fEn1 = [MacLCStreamFacts factsForName:nil title:@"Film.2024.ENG.1080p" filename:nil];
    MacLCStreamFacts *fEn2 = [MacLCStreamFacts factsForName:nil title:@"Film.2024.ENG.720p" filename:nil];
    MacLCStreamFacts *fFr1 = [MacLCStreamFacts factsForName:nil title:@"Film.2024.FRENCH.1080p" filename:nil];
    MacLCStreamFacts *fMulti = [MacLCStreamFacts factsForName:nil title:@"Film.2024.MULTi.1080p" filename:nil];

    MacLCStreamChoice *c1 = [[MacLCStreamChoice alloc] initWithFacts:fEn1 identifier:@"en1"];
    MacLCStreamChoice *c2 = [[MacLCStreamChoice alloc] initWithFacts:fEn2 identifier:@"en2"];
    MacLCStreamChoice *c3 = [[MacLCStreamChoice alloc] initWithFacts:fFr1 identifier:@"fr1"];
    MacLCStreamChoice *c4 = [[MacLCStreamChoice alloc] initWithFacts:fMulti identifier:@"m1"];

    NSDictionary<NSString *, NSNumber *> *counts = nil;
    NSArray<NSString *> *langs = [MacLCStreamFilter languagesIn:@[c1, c2, c3, c4] counts:&counts];

    XCTAssertNotNil(counts);
    XCTAssertEqualObjects(counts[@"en"], @2);
    XCTAssertEqualObjects(counts[@"fr"], @1);
    XCTAssertNil(counts[@"multi"]);

    XCTAssertEqual(langs.count, (NSUInteger)2);
    XCTAssertEqualObjects(langs[0], @"en");
    XCTAssertEqualObjects(langs[1], @"fr");
}

- (void)testFactsForStream
{
    MacLCAddonStream *stream = [[MacLCAddonStream alloc] initWithAddon:nil
                                                                 label:@"Torrentio"
                                                         qualityTokens:@[@"1080p", @"HDR"]
                                                              headline:@"Night of the Living Dead 1968 1080p BluRay"
                                                               details:@"👤 39 · 💾 4.35 GB · ⚙️ YTS"
                                                              infoHash:@"abcdef1234567890"
                                                              filename:@"Night.Living.Dead.1968.mkv"
                                                              trackers:@[]
                                                             directURL:nil
                                                     youTubeIdentifier:nil
                                                                   MRL:@"magnet:?xt=urn:btih:abcdef1234567890"];

    MacLCStreamFacts *facts = [MacLCStreamFacts factsForStream:stream];
    XCTAssertTrue(facts.isTorrent);
    XCTAssertEqual(facts.resolution, MacLCStreamResolution1080p);
    XCTAssertEqual(facts.seeders, (NSInteger)39);
    XCTAssertEqualObjects(facts.provider, @"YTS");
    XCTAssertTrue(facts.sizeBytes > 4000000000ULL);
}

- (void)testDisplayFormattersAndNames
{
    XCTAssertEqualObjects([MacLCStreamFacts nameForResolution:MacLCStreamResolution4K], @"4K");
    XCTAssertEqualObjects([MacLCStreamFacts nameForResolution:MacLCStreamResolution1080p], @"1080p");
    XCTAssertEqualObjects([MacLCStreamFacts nameForResolution:MacLCStreamResolution720p], @"720p");
    XCTAssertEqualObjects([MacLCStreamFacts nameForResolution:MacLCStreamResolutionSD], @"SD");

    XCTAssertEqualObjects([MacLCStreamFacts nameForDynamicRange:MacLCStreamDynamicRangeDolbyVision], @"Dolby Vision");
    XCTAssertEqualObjects([MacLCStreamFacts nameForDynamicRange:MacLCStreamDynamicRangeHDR10Plus], @"HDR10+");
    XCTAssertEqualObjects([MacLCStreamFacts nameForDynamicRange:MacLCStreamDynamicRangeHDR10], @"HDR10");
    XCTAssertEqualObjects([MacLCStreamFacts nameForDynamicRange:MacLCStreamDynamicRangeSDR], @"SDR");

    XCTAssertEqualObjects([MacLCStreamFacts nameForSource:MacLCStreamSourceRemux], @"Blu-ray Remux");
    XCTAssertEqualObjects([MacLCStreamFacts nameForSource:MacLCStreamSourceBluRay], @"Blu-ray");
    XCTAssertEqualObjects([MacLCStreamFacts nameForSource:MacLCStreamSourceWebDL], @"Web Download");
    XCTAssertEqualObjects([MacLCStreamFacts nameForSource:MacLCStreamSourceCam], @"Cinema Recording");

    XCTAssertEqualObjects([MacLCStreamFacts nameForVideoCodec:MacLCStreamVideoCodecH264], @"H.264");
    XCTAssertEqualObjects([MacLCStreamFacts nameForVideoCodec:MacLCStreamVideoCodecHEVC], @"HEVC");
    XCTAssertEqualObjects([MacLCStreamFacts nameForVideoCodec:MacLCStreamVideoCodecAV1], @"AV1");

    XCTAssertEqualObjects([MacLCStreamFacts nameForVerdict:MacLCStreamVerdictGreat], @"Great");
    XCTAssertEqualObjects([MacLCStreamFacts nameForVerdict:MacLCStreamVerdictPoor], @"Poor");

    XCTAssertEqualObjects([MacLCStreamFacts nameForHealth:MacLCStreamHealthExcellent], @"Excellent connection");
    XCTAssertEqualObjects([MacLCStreamFacts nameForHealth:MacLCStreamHealthWeak], @"Weak connection");

    NSString *display = [MacLCStreamFacts displaySize:4670732370ULL];
    XCTAssertTrue(display.length > 0);
}

@end
