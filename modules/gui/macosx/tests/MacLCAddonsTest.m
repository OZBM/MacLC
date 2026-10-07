/*****************************************************************************
 * MacLCAddonsTest.m: tests for MacLCAddons model, parsing and pure functions
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

#import "addons/MacLCAddons.h"

@interface MacLCAddonItem (TestInit)
- (instancetype)initWithAddon:(MacLCAddon *)addon
                   identifier:(NSString *)identifier
                         type:(NSString *)type
                         name:(NSString *)name
                  releaseInfo:(nullable NSString *)releaseInfo
                    posterURL:(nullable NSURL *)posterURL;
@end

@interface MacLCAddonVideo (TestInit)
- (instancetype)initWithIdentifier:(NSString *)identifier
                            season:(NSInteger)season
                           episode:(NSInteger)episode
                              name:(nullable NSString *)name
                          released:(nullable NSDate *)released;
@end

@interface MacLCAddonTitleCatalog (TestInit)
- (instancetype)initWithAddon:(MacLCAddon *)addon
                         type:(NSString *)type
                   identifier:(NSString *)identifier
                         name:(NSString *)name
                       genres:(NSArray<NSString *> *)genres
                requiresGenre:(BOOL)requiresGenre
                 supportsSkip:(BOOL)supportsSkip;
@end

@interface MacLCAddonsTest : XCTestCase
@end

@implementation MacLCAddonsTest

- (void)testTorrentioManifest
{
    NSString *json = @"{\"id\":\"com.stremio.torrentio.addon\",\"version\":\"0.0.15\",\"name\":\"Torrentio\",\"description\":\"Provides torrent streams from scraped torrent providers.\",\"catalogs\":[],\"resources\":[{\"name\":\"stream\",\"types\":[\"movie\",\"series\",\"anime\"],\"idPrefixes\":[\"tt\",\"kitsu\"]}],\"types\":[\"movie\",\"series\",\"anime\",\"other\"],\"behaviorHints\":{\"configurable\":true,\"configurationRequired\":false}}";
    NSData *data = [json dataUsingEncoding:NSUTF8StringEncoding];
    NSError *error = nil;
    MacLCAddon *addon = [MacLCAddon addonWithTransportURL:@"https://torrentio.strem.fun/manifest.json" manifestData:data error:&error];

    XCTAssertNotNil(addon);
    XCTAssertNil(error);
    XCTAssertEqualObjects(addon.identifier, @"com.stremio.torrentio.addon");
    XCTAssertEqualObjects(addon.name, @"Torrentio");
    XCTAssertEqualObjects(addon.version, @"0.0.15");
    XCTAssertEqualObjects(addon.addonDescription, @"Provides torrent streams from scraped torrent providers.");
    XCTAssertTrue(addon.providesStreams);
    XCTAssertTrue([addon providesResource:@"stream" forType:@"movie" identifier:@"tt0032599"]);
    XCTAssertTrue([addon providesResource:@"stream" forType:@"series" identifier:@"tt0043194:1:1"]);
    XCTAssertFalse([addon providesResource:@"stream" forType:@"movie" identifier:@"local:1"]);
    XCTAssertFalse([addon providesResource:@"stream" forType:@"channel" identifier:@"tt1"]);
    XCTAssertFalse(addon.providesSearch);
    XCTAssertNotNil(addon.configureURL);
    XCTAssertEqualObjects(addon.configureURL.absoluteString, @"https://torrentio.strem.fun/configure");
    XCTAssertTrue(addon.isRemovable);
}

- (void)testCinemetaManifest
{
    NSString *cinemetaJSON = @"{\"id\":\"com.linvo.cinemeta\",\"version\":\"3.0.14\",\"name\":\"Cinemeta\",\"description\":\"The official addon for movie and series catalogs\",\"resources\":[\"catalog\",\"meta\",\"addon_catalog\"],\"types\":[\"movie\",\"series\"],\"idPrefixes\":[\"tt\"],\"catalogs\":[{\"type\":\"movie\",\"id\":\"top\",\"name\":\"Popular\",\"extra\":[{\"name\":\"search\"}]},{\"type\":\"series\",\"id\":\"top\",\"name\":\"Popular\",\"extra\":[{\"name\":\"search\"}]}],\"addonCatalogs\":[{\"type\":\"all\",\"id\":\"official\",\"name\":\"Official\"},{\"type\":\"all\",\"id\":\"community\",\"name\":\"Community\"}]}";
    NSData *data = [cinemetaJSON dataUsingEncoding:NSUTF8StringEncoding];
    NSError *error = nil;
    MacLCAddon *addon = [MacLCAddon addonWithTransportURL:@"https://v3-cinemeta.strem.io/manifest.json" manifestData:data error:&error];

    XCTAssertNotNil(addon);
    XCTAssertNil(error);
    XCTAssertEqualObjects(addon.identifier, @"com.linvo.cinemeta");
    XCTAssertEqualObjects(addon.name, @"Cinemeta");
    XCTAssertEqualObjects(addon.version, @"3.0.14");
    XCTAssertTrue(addon.providesSearch);
    XCTAssertTrue([addon providesResource:@"meta" forType:@"series" identifier:@"tt0043194"]);
    XCTAssertTrue([addon.resourceNames containsObject:@"addon_catalog"]);
    XCTAssertFalse(addon.isRemovable);
}

- (void)testInvalidManifests
{
    NSError *error = nil;
    // Empty dictionary
    XCTAssertNil([MacLCAddon addonWithTransportURL:@"https://example.com/manifest.json"
                                      manifestData:[@"{}" dataUsingEncoding:NSUTF8StringEncoding]
                                             error:&error]);
    XCTAssertNotNil(error);
    XCTAssertEqualObjects(error.domain, MacLCAddonsErrorDomain);
    XCTAssertEqual(error.code, MacLCAddonsErrorNotAnAddon);

    // Array
    error = nil;
    XCTAssertNil([MacLCAddon addonWithTransportURL:@"https://example.com/manifest.json"
                                      manifestData:[@"[]" dataUsingEncoding:NSUTF8StringEncoding]
                                             error:&error]);
    XCTAssertNotNil(error);
    XCTAssertEqual(error.code, MacLCAddonsErrorNotAnAddon);

    // String JSON
    error = nil;
    XCTAssertNil([MacLCAddon addonWithTransportURL:@"https://example.com/manifest.json"
                                      manifestData:[@"\"x\"" dataUsingEncoding:NSUTF8StringEncoding]
                                             error:&error]);
    XCTAssertNotNil(error);
    XCTAssertEqual(error.code, MacLCAddonsErrorNotAnAddon);

    // Missing resources
    error = nil;
    NSString *noResources = @"{\"id\":\"test\",\"name\":\"Test\",\"version\":\"1.0.0\"}";
    XCTAssertNil([MacLCAddon addonWithTransportURL:@"https://example.com/manifest.json"
                                      manifestData:[noResources dataUsingEncoding:NSUTF8StringEncoding]
                                             error:&error]);
    XCTAssertNotNil(error);
    XCTAssertEqual(error.code, MacLCAddonsErrorNotAnAddon);

    // Non-JSON bytes
    error = nil;
    NSData *garbage = [@"this is not json" dataUsingEncoding:NSUTF8StringEncoding];
    XCTAssertNil([MacLCAddon addonWithTransportURL:@"https://example.com/manifest.json"
                                      manifestData:garbage
                                             error:&error]);
    XCTAssertNotNil(error);
    XCTAssertEqualObjects(error.domain, MacLCAddonsErrorDomain);
    XCTAssertEqual(error.code, MacLCAddonsErrorBadResponse);
}

- (void)testAddresses
{
    // Base address appends manifest.json
    XCTAssertEqualObjects([MacLCAddonStore transportURLForAddress:@"https://torrentio.strem.fun"],
                          @"https://torrentio.strem.fun/manifest.json");

    // Trailing slash handled
    XCTAssertEqualObjects([MacLCAddonStore transportURLForAddress:@"https://torrentio.strem.fun/"],
                          @"https://torrentio.strem.fun/manifest.json");

    // Trailing /configure replaced by /manifest.json
    XCTAssertEqualObjects([MacLCAddonStore transportURLForAddress:@"https://torrentio.strem.fun/configure"],
                          @"https://torrentio.strem.fun/manifest.json");
    XCTAssertEqualObjects([MacLCAddonStore transportURLForAddress:@"https://torrentio.strem.fun/configure/"],
                          @"https://torrentio.strem.fun/manifest.json");

    // stremio:// scheme converted to https, host kept, configuration segment preserved
    NSString *stremioAddress = @"stremio://torrentio.strem.fun/providers=yts,eztv|qualityfilter=480p/manifest.json";
    NSString *transport = [MacLCAddonStore transportURLForAddress:stremioAddress];
    XCTAssertNotNil(transport);
    XCTAssertTrue([transport hasPrefix:@"https://torrentio.strem.fun/"]);
    XCTAssertTrue([transport containsString:@"providers=yts,eztv"]);
    XCTAssertTrue([transport hasSuffix:@"/manifest.json"]);

    // Invalid addresses return nil
    XCTAssertNil([MacLCAddonStore transportURLForAddress:@"ftp://x"]);
    XCTAssertNil([MacLCAddonStore transportURLForAddress:@"not a url"]);
    XCTAssertNil([MacLCAddonStore transportURLForAddress:@"https://"]);
    XCTAssertNil([MacLCAddonStore transportURLForAddress:@""]);
    XCTAssertNil([MacLCAddonStore transportURLForAddress:@"   "]);
    NSString *nilAddress = nil;
    XCTAssertNil([MacLCAddonStore transportURLForAddress:nilAddress]);
}

- (void)testUnresolvedHost
{
    NSURL * const url = [NSURL URLWithString:@"https://torrentio.strem.fun/manifest.json"];
    NSDictionary * const info = @{NSURLErrorFailingURLErrorKey: url};
    XCTAssertEqualObjects(MacLCAddonsUnresolvedHost([NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorCannotFindHost userInfo:info]),
                          @"torrentio.strem.fun");
    XCTAssertEqualObjects(MacLCAddonsUnresolvedHost([NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorDNSLookupFailed userInfo:info]),
                          @"torrentio.strem.fun");
    XCTAssertNil(MacLCAddonsUnresolvedHost([NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorTimedOut userInfo:info]));
    XCTAssertNil(MacLCAddonsUnresolvedHost([NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorCannotFindHost userInfo:nil]));
    XCTAssertNil(MacLCAddonsUnresolvedHost([NSError errorWithDomain:MacLCAddonsErrorDomain code:NSURLErrorCannotFindHost userInfo:info]));
    XCTAssertNil(MacLCAddonsUnresolvedHost(nil));
}

- (void)testURLs
{
    NSString *torrentioJSON = @"{\"id\":\"com.stremio.torrentio.addon\",\"version\":\"0.0.15\",\"name\":\"Torrentio\",\"resources\":[\"stream\"],\"types\":[\"series\"]}";
    MacLCAddon *torrentio = [MacLCAddon addonWithTransportURL:@"https://torrentio.strem.fun/manifest.json"
                                                 manifestData:[torrentioJSON dataUsingEncoding:NSUTF8StringEncoding]
                                                        error:nil];
    XCTAssertNotNil(torrentio);

    // Stream URL keeps colons in identifier
    NSURL *streamURL = [MacLCAddonStore URLForResource:@"stream"
                                                 addon:torrentio
                                                  type:@"series"
                                            identifier:@"tt0043194:1:1"
                                                 extra:nil];
    XCTAssertEqualObjects(streamURL.absoluteString, @"https://torrentio.strem.fun/stream/series/tt0043194:1:1.json");

    NSString *cinemetaJSON = @"{\"id\":\"com.linvo.cinemeta\",\"version\":\"3.0.14\",\"name\":\"Cinemeta\",\"resources\":[\"catalog\"],\"types\":[\"movie\"]}";
    MacLCAddon *cinemeta = [MacLCAddon addonWithTransportURL:@"https://v3-cinemeta.strem.io/manifest.json"
                                                manifestData:[cinemetaJSON dataUsingEncoding:NSUTF8StringEncoding]
                                                       error:nil];
    XCTAssertNotNil(cinemeta);

    // Catalog search query percent-encoded except A-Za-z0-9-._~
    NSString *extra = @"search=night%20of%20the%20living%20dead";
    NSURL *searchURL = [MacLCAddonStore URLForResource:@"catalog"
                                                 addon:cinemeta
                                                  type:@"movie"
                                            identifier:@"top"
                                                 extra:extra];
    XCTAssertEqualObjects(searchURL.absoluteString,
                          @"https://v3-cinemeta.strem.io/catalog/movie/top/search=night%20of%20the%20living%20dead.json");
}

- (void)testStreamParsing
{
    NSString *torrentioJSON = @"{\"id\":\"com.stremio.torrentio.addon\",\"version\":\"0.0.15\",\"name\":\"Torrentio\",\"resources\":[\"stream\"],\"types\":[\"movie\"]}";
    MacLCAddon *torrentio = [MacLCAddon addonWithTransportURL:@"https://torrentio.strem.fun/manifest.json"
                                                 manifestData:[torrentioJSON dataUsingEncoding:NSUTF8StringEncoding]
                                                        error:nil];

    // Example 1: Cinephil 4K
    NSString *cinephilJSON = @"{\"streams\":[{"
        "\"name\":\"Torrentio\\n4k DV | HDR\","
        "\"title\":\"His.Girl.Friday.1940.REPACK.2160p.UHD.Bluray.Remux.DV.HDR.HEVC.FLAC2.0-CiNEPHiL\\n👤 6 💾 60.87 GB ⚙️ ThePirateBay\","
        "\"infoHash\":\"51631bc177e318ceaa7b6c61041eda1b5ff708f2\","
        "\"fileIdx\":0,"
        "\"behaviorHints\":{\"bingeGroup\":\"torrentio|4k|BluRay REMUX|hevc|DV|HDR\",\"filename\":\"His.Girl.Friday.1940.REPACK.2160p.UHD.Blu-ray.Remux.DV.HDR.HEVC.FLAC2.0-CiNEPHiLES.mkv\"}"
    "}]}";

    NSError *error = nil;
    NSArray<MacLCAddonStream *> *streams1 = [MacLCAddonStore streamsFromData:[cinephilJSON dataUsingEncoding:NSUTF8StringEncoding]
                                                                      addon:torrentio
                                                                      error:&error];
    XCTAssertNotNil(streams1);
    XCTAssertNil(error);
    XCTAssertEqual(streams1.count, 1);
    MacLCAddonStream *s1 = streams1[0];
    XCTAssertEqualObjects(s1.label, @"Torrentio");
    NSArray<NSString *> *expectedTokens1 = @[@"4k", @"DV", @"HDR"];
    XCTAssertEqualObjects(s1.qualityTokens, expectedTokens1);
    XCTAssertEqualObjects(s1.headline, @"His.Girl.Friday.1940.REPACK.2160p.UHD.Bluray.Remux.DV.HDR.HEVC.FLAC2.0-CiNEPHiL");
    XCTAssertEqualObjects(s1.details, @"👤 6 💾 60.87 GB ⚙️ ThePirateBay");
    XCTAssertEqualObjects(s1.infoHash, @"51631bc177e318ceaa7b6c61041eda1b5ff708f2");
    XCTAssertEqualObjects(s1.filename, @"His.Girl.Friday.1940.REPACK.2160p.UHD.Blu-ray.Remux.DV.HDR.HEVC.FLAC2.0-CiNEPHiLES.mkv");
    XCTAssertNil(s1.directURL);
    XCTAssertNil(s1.youTubeIdentifier);
    XCTAssertEqual(s1.trackers.count, 0);

    // Example 2: YTS 1080p
    NSString *ytsJSON = @"{\"streams\":[{"
        "\"name\":\"Torrentio\\n1080p\","
        "\"title\":\"His Girl Friday 1940 1080p BluRay\\n👤 63 💾 1.44 GB ⚙️ YTS\","
        "\"infoHash\":\"5d1cd67d7de2c2da4850203aa9e0bbcf8388e2d6\","
        "\"fileIdx\":0,"
        "\"behaviorHints\":{\"bingeGroup\":\"torrentio|1080p|BluRay|x264\",\"filename\":\"His.Girl.Friday.1940.1080p.BluRay.x264-[YTS.AM].mp4\"}"
    "}]}";

    NSArray<MacLCAddonStream *> *streams2 = [MacLCAddonStore streamsFromData:[ytsJSON dataUsingEncoding:NSUTF8StringEncoding]
                                                                      addon:torrentio
                                                                      error:&error];
    XCTAssertNotNil(streams2);
    XCTAssertNil(error);
    XCTAssertEqual(streams2.count, 1);
    MacLCAddonStream *s2 = streams2[0];
    XCTAssertEqualObjects(s2.label, @"Torrentio");
    NSArray<NSString *> *expectedTokens2 = @[@"1080p"];
    XCTAssertEqualObjects(s2.qualityTokens, expectedTokens2);
    XCTAssertEqualObjects(s2.headline, @"His Girl Friday 1940 1080p BluRay");
    XCTAssertEqualObjects(s2.details, @"👤 63 💾 1.44 GB ⚙️ YTS");
    XCTAssertEqualObjects(s2.infoHash, @"5d1cd67d7de2c2da4850203aa9e0bbcf8388e2d6");
    XCTAssertEqualObjects(s2.filename, @"His.Girl.Friday.1940.1080p.BluRay.x264-[YTS.AM].mp4");

    NSString *expectedYTSMRL = @"magnet:?xt=urn:btih:5d1cd67d7de2c2da4850203aa9e0bbcf8388e2d6"
        "&dn=His%20Girl%20Friday%201940%201080p%20BluRay"
        "&tr=udp%3A%2F%2Ftracker.opentrackr.org%3A1337%2Fannounce"
        "&tr=udp%3A%2F%2Fopen.stealth.si%3A80%2Fannounce"
        "&tr=udp%3A%2F%2Ftracker.torrent.eu.org%3A451%2Fannounce"
        "&tr=udp%3A%2F%2Fexodus.desync.com%3A6969%2Fannounce"
        "&tr=udp%3A%2F%2Fopen.demonii.com%3A1337%2Fannounce"
        "#!/His.Girl.Friday.1940.1080p.BluRay.x264-%5BYTS.AM%5D.mp4";
    XCTAssertEqualObjects(s2.MRL, expectedYTSMRL);

    // Example 3: Rutor BDRip
    NSString *rutorJSON = @"{\"streams\":[{"
        "\"name\":\"Torrentio\\nBDRip\","
        "\"title\":\"Его девушка Пятница / His Girl Friday (1940) BDRip-AVC от msltel | P P2\\n👤 1 💾 3.03 GB ⚙️ Rutor\\n🇬🇧 / 🇷🇺\","
        "\"infoHash\":\"3252960cfa8004428e66213fa944d39f156e95e0\","
        "\"fileIdx\":0,"
        "\"behaviorHints\":{\"bingeGroup\":\"torrentio|BDRip|avc\",\"filename\":\"Его девушка Пятница.1940.BDRip AVC msltel.mkv\"},"
        "\"sources\":["
            "\"tracker:udp://opentor.net:6969\","
            "\"tracker:http://retracker.local/announce\","
            "\"dht:3252960cfa8004428e66213fa944d39f156e95e0\","
            "\"tracker:udp://tracker.opentrackr.org:1337/announce\""
        "]"
    "}]}";

    NSArray<MacLCAddonStream *> *streams3 = [MacLCAddonStore streamsFromData:[rutorJSON dataUsingEncoding:NSUTF8StringEncoding]
                                                                      addon:torrentio
                                                                      error:&error];
    XCTAssertNotNil(streams3);
    XCTAssertNil(error);
    XCTAssertEqual(streams3.count, 1);
    MacLCAddonStream *s3 = streams3[0];
    XCTAssertEqualObjects(s3.label, @"Torrentio");
    NSArray<NSString *> *expectedTokens3 = @[@"BDRip"];
    XCTAssertEqualObjects(s3.qualityTokens, expectedTokens3);
    XCTAssertEqualObjects(s3.headline, @"Его девушка Пятница / His Girl Friday (1940) BDRip-AVC от msltel | P P2");
    XCTAssertEqualObjects(s3.details, @"👤 1 💾 3.03 GB ⚙️ Rutor · 🇬🇧 / 🇷🇺");
    XCTAssertEqual(s3.trackers.count, 3);
    XCTAssertEqualObjects(s3.trackers[0], @"udp://opentor.net:6969");
    XCTAssertEqualObjects(s3.trackers[1], @"http://retracker.local/announce");
    XCTAssertEqualObjects(s3.trackers[2], @"udp://tracker.opentrackr.org:1337/announce");

    // Public Domain Movies: single line name != addon name, headline = title, magnet without fragment
    NSString *pdmManifestJSON = @"{\"id\":\"com.pdm.addon\",\"version\":\"1.0.0\",\"name\":\"Public Domain Movies\",\"resources\":[\"stream\"],\"types\":[\"movie\"]}";
    MacLCAddon *pdmAddon = [MacLCAddon addonWithTransportURL:@"https://pdm.example.com/manifest.json"
                                                manifestData:[pdmManifestJSON dataUsingEncoding:NSUTF8StringEncoding]
                                                       error:nil];
    NSString *pdmJSON = @"{\"streams\":[{\"infoHash\":\"11ea02584fa6351956f35671962ab46354d99060\",\"title\":\"💾 1.51 GB\",\"fileIdx\":0,\"name\":\"1080p\"}]}";
    NSArray<MacLCAddonStream *> *pdmStreams = [MacLCAddonStore streamsFromData:[pdmJSON dataUsingEncoding:NSUTF8StringEncoding]
                                                                         addon:pdmAddon
                                                                         error:&error];
    XCTAssertNotNil(pdmStreams);
    XCTAssertEqual(pdmStreams.count, 1);
    MacLCAddonStream *pdm = pdmStreams[0];
    XCTAssertEqualObjects(pdm.label, @"1080p");
    NSArray<NSString *> *expectedPdmTokens = @[@"1080p"];
    XCTAssertEqualObjects(pdm.qualityTokens, expectedPdmTokens);
    XCTAssertEqualObjects(pdm.headline, @"💾 1.51 GB");
    XCTAssertNil(pdm.details);
    XCTAssertNil(pdm.filename);
    XCTAssertFalse([pdm.MRL containsString:@"#!/"]);
    XCTAssertTrue([pdm.MRL hasPrefix:@"magnet:?xt=urn:btih:11ea02584fa6351956f35671962ab46354d99060&dn=%F0%9F%92%BE%201.51%20GB"]);

    // URL stream
    NSString *urlJSON = @"{\"streams\":[{\"name\":\"Debrid\",\"title\":\"Direct Stream\",\"url\":\"https://example.com/stream.mp4\"}]}";
    NSArray<MacLCAddonStream *> *urlStreams = [MacLCAddonStore streamsFromData:[urlJSON dataUsingEncoding:NSUTF8StringEncoding]
                                                                        addon:torrentio
                                                                        error:&error];
    XCTAssertNotNil(urlStreams);
    XCTAssertEqual(urlStreams.count, 1);
    XCTAssertNotNil(urlStreams[0].directURL);
    XCTAssertEqualObjects(urlStreams[0].directURL.absoluteString, @"https://example.com/stream.mp4");
    XCTAssertEqualObjects(urlStreams[0].MRL, @"https://example.com/stream.mp4");

    // ytId stream
    NSString *ytJSON = @"{\"streams\":[{\"name\":\"YouTube\",\"title\":\"Trailer\",\"ytId\":\"dQw4w9WgXcQ\"}]}";
    NSArray<MacLCAddonStream *> *ytStreams = [MacLCAddonStore streamsFromData:[ytJSON dataUsingEncoding:NSUTF8StringEncoding]
                                                                       addon:torrentio
                                                                       error:&error];
    XCTAssertNotNil(ytStreams);
    XCTAssertEqual(ytStreams.count, 1);
    XCTAssertEqualObjects(ytStreams[0].youTubeIdentifier, @"dQw4w9WgXcQ");
    XCTAssertEqualObjects(ytStreams[0].MRL, @"https://www.youtube.com/watch?v=dQw4w9WgXcQ");

    // externalUrl-only stream is dropped
    NSString *extJSON = @"{\"streams\":[{\"name\":\"External\",\"title\":\"Web Link\",\"externalUrl\":\"https://example.com/watch\"}]}";
    NSArray<MacLCAddonStream *> *extStreams = [MacLCAddonStore streamsFromData:[extJSON dataUsingEncoding:NSUTF8StringEncoding]
                                                                        addon:torrentio
                                                                        error:&error];
    XCTAssertNotNil(extStreams);
    XCTAssertEqual(extStreams.count, 0);

    // Empty streams array
    NSString *emptyJSON = @"{\"streams\":[]}";
    NSArray<MacLCAddonStream *> *emptyStreams = [MacLCAddonStore streamsFromData:[emptyJSON dataUsingEncoding:NSUTF8StringEncoding]
                                                                          addon:torrentio
                                                                          error:&error];
    XCTAssertNotNil(emptyStreams);
    XCTAssertEqual(emptyStreams.count, 0);
    XCTAssertNil(error);
}

- (void)testAddonCatalogParsing
{
    NSString *cinemetaManifest = @"{\"id\":\"com.linvo.cinemeta\",\"version\":\"3.0.14\",\"name\":\"Cinemeta\",\"resources\":[\"catalog\",\"meta\"],\"types\":[\"movie\"]}";
    NSString *catalogJSON = [NSString stringWithFormat:@"{\"addons\":["
        "{\"transportUrl\":\"https://v3-cinemeta.strem.io/manifest.json\",\"manifest\":%@},"
        "{\"transportUrl\":\"https://subtitles.strem.fun/manifest.json\",\"manifest\":{\"id\":\"subs\",\"name\":\"Subs\",\"version\":\"1.0.0\",\"resources\":[\"subtitles\"],\"types\":[\"movie\"]}},"
        "{\"transportUrl\":\"http://127.0.0.1:11470/local-addon/manifest.json\",\"manifest\":{\"id\":\"local\",\"name\":\"Local\",\"version\":\"1.0.0\",\"resources\":[\"stream\"],\"types\":[\"movie\"]}},"
        "{\"transportUrl\":\"https://example.com/not-manifest\",\"manifest\":{\"id\":\"badurl\",\"name\":\"Bad\",\"version\":\"1.0.0\",\"resources\":[\"stream\"],\"types\":[\"movie\"]}}"
    "]}", cinemetaManifest];

    NSError *error = nil;
    NSArray<MacLCAddon *> *addons = [MacLCAddonStore addonsFromCatalogData:[catalogJSON dataUsingEncoding:NSUTF8StringEncoding]
                                                                     error:&error];
    XCTAssertNotNil(addons);
    XCTAssertNil(error);
    XCTAssertEqual(addons.count, 1);
    XCTAssertEqualObjects(addons[0].identifier, @"com.linvo.cinemeta");
}

- (void)testCommunityCatalogListsTorrentio
{
    NSString *catalogJSON = @"{\"addons\":[{\"transportUrl\":\"https://anime-kitsu.strem.fun/manifest.json\",\"manifest\":{\"id\":\"community.anime.kitsu\",\"name\":\"Anime Kitsu\",\"version\":\"0.0.10\",\"resources\":[\"catalog\",\"meta\"],\"types\":[\"anime\",\"movie\",\"series\"]}}]}";
    NSArray<MacLCAddon *> *listed = [MacLCAddonStore addonsFromCatalogData:[catalogJSON dataUsingEncoding:NSUTF8StringEncoding]
                                                                     error:nil];
    NSArray<MacLCAddon *> *addons = [MacLCAddonStore communityAddons:listed forType:@"all"];
    XCTAssertEqual(addons.count, 2);
    XCTAssertEqualObjects(addons[0].identifier, @"com.stremio.torrentio.addon");
    XCTAssertEqualObjects(addons[0].transportURL, @"https://torrentio.strem.fun/manifest.json");
    XCTAssertTrue(addons[0].providesStreams);
    XCTAssertTrue(addons[0].isRemovable);
    XCTAssertEqualObjects(addons[0].configureURL.absoluteString, @"https://torrentio.strem.fun/configure");
    XCTAssertEqualObjects(addons[1].identifier, @"community.anime.kitsu");

    /* Once when Stremio lists it again; not in a list of a type it does not serve. */
    XCTAssertEqual([MacLCAddonStore communityAddons:addons forType:@"all"].count, 2);
    XCTAssertEqual([MacLCAddonStore communityAddons:listed forType:@"series"].count, 2);
    XCTAssertEqual([MacLCAddonStore communityAddons:listed forType:@"channel"].count, 1);
}

- (void)testMetaParsing
{
    // Two seasons out of order, episode without episode but with number, behaviorHints.defaultVideoId
    NSString *metaJSON = @"{\"meta\":{\"id\":\"tt0043194\",\"behaviorHints\":{\"defaultVideoId\":\"tt0043194:default\"},\"videos\":["
        "{\"id\":\"tt0043194:2:1\",\"season\":2,\"episode\":1,\"name\":\"Season 2 Ep 1\",\"released\":\"1952-10-01\"},"
        "{\"id\":\"tt0043194:1:1\",\"season\":1,\"number\":1,\"title\":\"The Human Bomb\",\"released\":\"1951-12-16T00:00:00.000Z\"}"
    "]}}";

    NSError *error = nil;
    MacLCAddonMeta *meta = [MacLCAddonStore metaFromData:[metaJSON dataUsingEncoding:NSUTF8StringEncoding]
                                          itemIdentifier:@"tt0043194"
                                                   error:&error];
    XCTAssertNotNil(meta);
    XCTAssertNil(error);
    XCTAssertEqualObjects(meta.defaultVideoIdentifier, @"tt0043194:default");
    XCTAssertEqual(meta.videos.count, 2);

    // Sorted by season then episode: 1:1 before 2:1
    XCTAssertEqualObjects(meta.videos[0].identifier, @"tt0043194:1:1");
    XCTAssertEqual(meta.videos[0].season, 1);
    XCTAssertEqual(meta.videos[0].episode, 1);
    XCTAssertEqualObjects(meta.videos[0].name, @"The Human Bomb");
    XCTAssertNotNil(meta.videos[0].released);

    XCTAssertEqualObjects(meta.videos[1].identifier, @"tt0043194:2:1");
    XCTAssertEqual(meta.videos[1].season, 2);
    XCTAssertEqual(meta.videos[1].episode, 1);
    XCTAssertEqualObjects(meta.videos[1].name, @"Season 2 Ep 1");

    // Meta without videos
    NSString *emptyMetaJSON = @"{\"meta\":{\"id\":\"tt0032599\"}}";
    MacLCAddonMeta *emptyMeta = [MacLCAddonStore metaFromData:[emptyMetaJSON dataUsingEncoding:NSUTF8StringEncoding]
                                               itemIdentifier:@"tt0032599"
                                                        error:&error];
    XCTAssertNotNil(emptyMeta);
    XCTAssertNil(error);
    XCTAssertEqual(emptyMeta.videos.count, 0);
    XCTAssertEqualObjects(emptyMeta.defaultVideoIdentifier, @"tt0032599");
}

- (void)testItemNames
{
    NSString *manifestJSON = @"{\"id\":\"test\",\"name\":\"Test\",\"version\":\"1.0.0\",\"resources\":[\"meta\"],\"types\":[\"movie\",\"series\"]}";
    MacLCAddon *addon = [MacLCAddon addonWithTransportURL:@"https://example.com/manifest.json"
                                             manifestData:[manifestJSON dataUsingEncoding:NSUTF8StringEncoding]
                                                    error:nil];
    XCTAssertNotNil(addon);

    // Form 1: No video -> "Name (releaseInfo)" or "Name"
    MacLCAddonItem *movieWithYear = [[MacLCAddonItem alloc] initWithAddon:addon
                                                               identifier:@"tt0032599"
                                                                     type:@"movie"
                                                                     name:@"His Girl Friday"
                                                              releaseInfo:@"1940"
                                                                posterURL:nil];
    XCTAssertEqualObjects([MacLCAddonStore itemNameForItem:movieWithYear video:nil],
                          @"His Girl Friday (1940)");

    MacLCAddonItem *movieNoYear = [[MacLCAddonItem alloc] initWithAddon:addon
                                                             identifier:@"tt0032599"
                                                                   type:@"movie"
                                                                   name:@"His Girl Friday"
                                                            releaseInfo:nil
                                                              posterURL:nil];
    XCTAssertEqualObjects([MacLCAddonStore itemNameForItem:movieNoYear video:nil],
                          @"His Girl Friday");

    // Form 2: Video with season > 0 or episode > 0 -> "Name — S<season>E<episode> · <video name>" or "Name — S<season>E<episode>"
    MacLCAddonItem *seriesItem = [[MacLCAddonItem alloc] initWithAddon:addon
                                                            identifier:@"tt0043194"
                                                                  type:@"series"
                                                                  name:@"Dragnet"
                                                           releaseInfo:nil
                                                             posterURL:nil];

    MacLCAddonVideo *videoWithName = [[MacLCAddonVideo alloc] initWithIdentifier:@"tt0043194:1:2"
                                                                          season:1
                                                                         episode:2
                                                                            name:@"The Big Ruckus"
                                                                        released:nil];
    XCTAssertEqualObjects([MacLCAddonStore itemNameForItem:seriesItem video:videoWithName],
                          @"Dragnet — S1E2 · The Big Ruckus");

    MacLCAddonVideo *videoNoName = [[MacLCAddonVideo alloc] initWithIdentifier:@"tt0043194:1:2"
                                                                        season:1
                                                                       episode:2
                                                                          name:nil
                                                                      released:nil];
    XCTAssertEqualObjects([MacLCAddonStore itemNameForItem:seriesItem video:videoNoName],
                          @"Dragnet — S1E2");

    // Form 3: Another video (season 0, episode 0) -> "Name — <video name>" or "Name"
    MacLCAddonItem *channelItem = [[MacLCAddonItem alloc] initWithAddon:addon
                                                             identifier:@"ch1"
                                                                   type:@"channel"
                                                                   name:@"A Channel"
                                                            releaseInfo:nil
                                                              posterURL:nil];

    MacLCAddonVideo *chanVideoWithName = [[MacLCAddonVideo alloc] initWithIdentifier:@"vid1"
                                                                              season:0
                                                                             episode:0
                                                                                name:@"A Video"
                                                                            released:nil];
    XCTAssertEqualObjects([MacLCAddonStore itemNameForItem:channelItem video:chanVideoWithName],
                          @"A Channel — A Video");

    MacLCAddonVideo *chanVideoNoName = [[MacLCAddonVideo alloc] initWithIdentifier:@"vid2"
                                                                            season:0
                                                                           episode:0
                                                                              name:nil
                                                                          released:nil];
    XCTAssertEqualObjects([MacLCAddonStore itemNameForItem:channelItem video:chanVideoNoName],
                          @"A Channel");
}

- (void)testCatalogParsing
{
    NSString *manifestJSON = @"{\"id\":\"test\",\"name\":\"Test\",\"version\":\"1.0.0\",\"resources\":[\"catalog\"],\"types\":[\"movie\"]}";
    MacLCAddon *addon = [MacLCAddon addonWithTransportURL:@"https://example.com/manifest.json"
                                             manifestData:[manifestJSON dataUsingEncoding:NSUTF8StringEncoding]
                                                    error:nil];

    NSString *catalogJSON = @"{\"metas\":["
        "{\"id\":\"tt0032599\",\"type\":\"movie\",\"name\":\"His Girl Friday\",\"poster\":\"https://images.example.com/poster.jpg\",\"releaseInfo\":\"1940\"},"
        "{\"id\":\"invalid_no_name\",\"type\":\"movie\"},"
        "{\"name\":\"No ID\",\"type\":\"movie\"},"
        "{\"id\":\"tt0043194\",\"type\":\"series\",\"name\":\"Dragnet\"}"
    "]}";

    NSError *error = nil;
    NSArray<MacLCAddonItem *> *items = [MacLCAddonStore itemsFromCatalogData:[catalogJSON dataUsingEncoding:NSUTF8StringEncoding]
                                                                       addon:addon
                                                                       error:&error];
    XCTAssertNotNil(items);
    XCTAssertNil(error);
    XCTAssertEqual(items.count, 2);
    XCTAssertEqualObjects(items[0].identifier, @"tt0032599");
    XCTAssertEqualObjects(items[0].name, @"His Girl Friday");
    XCTAssertEqualObjects(items[0].type, @"movie");
    XCTAssertEqualObjects(items[0].releaseInfo, @"1940");
    XCTAssertEqualObjects(items[0].posterURL.absoluteString, @"https://images.example.com/poster.jpg");

    XCTAssertEqualObjects(items[1].identifier, @"tt0043194");
    XCTAssertEqualObjects(items[1].name, @"Dragnet");
    XCTAssertEqualObjects(items[1].type, @"series");
}

- (void)testCinemetaTitleCatalogs
{
    // Real Cinemeta manifest fixture with 8 catalogs:
    // movie/series top, movie/series year, movie/series imdbRating, series last-videos, series calendar-videos
    NSString *cinemetaJSON = @"{"
        "\"id\":\"com.linvo.cinemeta\","
        "\"version\":\"3.0.14\","
        "\"name\":\"Cinemeta\","
        "\"description\":\"The official addon for movie and series catalogs\","
        "\"resources\":[\"catalog\",\"meta\",\"addon_catalog\"],"
        "\"types\":[\"movie\",\"series\"],"
        "\"idPrefixes\":[\"tt\"],"
        "\"catalogs\":["
            "{\"type\":\"movie\",\"id\":\"top\",\"name\":\"Popular\",\"genres\":[\"Action\",\"Comedy\",\"Sci-Fi\"],"
             "\"extra\":[{\"name\":\"genre\",\"options\":[\"Action\",\"Comedy\",\"Sci-Fi\"]},{\"name\":\"search\"},{\"name\":\"skip\"}],"
             "\"extraSupported\":[\"search\",\"genre\",\"skip\"]},"
            "{\"type\":\"series\",\"id\":\"top\",\"name\":\"Popular\",\"genres\":[\"Action\",\"Drama\",\"Sci-Fi\"],"
             "\"extra\":[{\"name\":\"genre\",\"options\":[\"Action\",\"Drama\",\"Sci-Fi\"]},{\"name\":\"search\"},{\"name\":\"skip\"}],"
             "\"extraSupported\":[\"search\",\"genre\",\"skip\"]},"
            "{\"type\":\"movie\",\"id\":\"year\",\"name\":\"New\",\"genres\":[\"2026\",\"2025\",\"2024\"],"
             "\"extra\":[{\"name\":\"genre\",\"options\":[\"2026\",\"2025\",\"2024\"],\"isRequired\":true},{\"name\":\"skip\"}],"
             "\"extraSupported\":[\"genre\",\"skip\"],\"extraRequired\":[\"genre\"]},"
            "{\"type\":\"series\",\"id\":\"year\",\"name\":\"New\",\"genres\":[\"2026\",\"2025\",\"2024\"],"
             "\"extra\":[{\"name\":\"genre\",\"options\":[\"2026\",\"2025\",\"2024\"],\"isRequired\":true},{\"name\":\"skip\"}],"
             "\"extraSupported\":[\"genre\",\"skip\"],\"extraRequired\":[\"genre\"]},"
            "{\"type\":\"movie\",\"id\":\"imdbRating\",\"name\":\"Featured\",\"genres\":[\"Action\",\"Sci-Fi\"],"
             "\"extra\":[{\"name\":\"genre\",\"options\":[\"Action\",\"Sci-Fi\"]},{\"name\":\"skip\"}],"
             "\"extraSupported\":[\"genre\",\"skip\"]},"
            "{\"type\":\"series\",\"id\":\"imdbRating\",\"name\":\"Featured\",\"genres\":[\"Action\",\"Sci-Fi\"],"
             "\"extra\":[{\"name\":\"genre\",\"options\":[\"Action\",\"Sci-Fi\"]},{\"name\":\"skip\"}],"
             "\"extraSupported\":[\"genre\",\"skip\"]},"
            "{\"type\":\"series\",\"id\":\"last-videos\",\"name\":\"Last videos\","
             "\"extra\":[{\"name\":\"lastVideosIds\",\"isRequired\":true,\"optionsLimit\":100}],"
             "\"extraSupported\":[\"lastVideosIds\"],\"extraRequired\":[\"lastVideosIds\"]},"
            "{\"type\":\"series\",\"id\":\"calendar-videos\",\"name\":\"Calendar videos\","
             "\"extra\":[{\"name\":\"calendarVideosIds\",\"isRequired\":true,\"optionsLimit\":100}],"
             "\"extraSupported\":[\"calendarVideosIds\"],\"extraRequired\":[\"calendarVideosIds\"]}"
        "]}";

    NSError *error = nil;
    MacLCAddon *cinemeta = [MacLCAddon addonWithTransportURL:@"https://v3-cinemeta.strem.io/manifest.json"
                                                manifestData:[cinemetaJSON dataUsingEncoding:NSUTF8StringEncoding]
                                                       error:&error];
    XCTAssertNotNil(cinemeta);
    XCTAssertNil(error);

    NSArray<MacLCAddonTitleCatalog *> *catalogs = [MacLCAddonStore titleCatalogsOfAddon:cinemeta];
    XCTAssertNotNil(catalogs);
    XCTAssertEqual(catalogs.count, 6);

    // movie top
    XCTAssertEqualObjects(catalogs[0].type, @"movie");
    XCTAssertEqualObjects(catalogs[0].identifier, @"top");
    XCTAssertEqualObjects(catalogs[0].name, @"Popular");
    XCTAssertFalse(catalogs[0].requiresGenre);
    XCTAssertTrue(catalogs[0].supportsSkip);

    // series top
    XCTAssertEqualObjects(catalogs[1].type, @"series");
    XCTAssertEqualObjects(catalogs[1].identifier, @"top");
    XCTAssertEqualObjects(catalogs[1].name, @"Popular");
    XCTAssertFalse(catalogs[1].requiresGenre);
    XCTAssertTrue(catalogs[1].supportsSkip);

    // movie year (requiresGenre with first option "2026")
    XCTAssertEqualObjects(catalogs[2].type, @"movie");
    XCTAssertEqualObjects(catalogs[2].identifier, @"year");
    XCTAssertEqualObjects(catalogs[2].name, @"New");
    XCTAssertTrue(catalogs[2].requiresGenre);
    XCTAssertTrue(catalogs[2].supportsSkip);
    XCTAssertEqualObjects(catalogs[2].genres.firstObject, @"2026");

    // series year (requiresGenre with first option "2026")
    XCTAssertEqualObjects(catalogs[3].type, @"series");
    XCTAssertEqualObjects(catalogs[3].identifier, @"year");
    XCTAssertEqualObjects(catalogs[3].name, @"New");
    XCTAssertTrue(catalogs[3].requiresGenre);
    XCTAssertTrue(catalogs[3].supportsSkip);
    XCTAssertEqualObjects(catalogs[3].genres.firstObject, @"2026");

    // movie imdbRating
    XCTAssertEqualObjects(catalogs[4].type, @"movie");
    XCTAssertEqualObjects(catalogs[4].identifier, @"imdbRating");
    XCTAssertEqualObjects(catalogs[4].name, @"Featured");
    XCTAssertFalse(catalogs[4].requiresGenre);
    XCTAssertTrue(catalogs[4].supportsSkip);

    // series imdbRating
    XCTAssertEqualObjects(catalogs[5].type, @"series");
    XCTAssertEqualObjects(catalogs[5].identifier, @"imdbRating");
    XCTAssertEqualObjects(catalogs[5].name, @"Featured");
    XCTAssertFalse(catalogs[5].requiresGenre);
    XCTAssertTrue(catalogs[5].supportsSkip);

    // Neither last-videos nor calendar-videos included
    for (MacLCAddonTitleCatalog *cat in catalogs) {
        XCTAssertFalse([cat.identifier isEqualToString:@"last-videos"]);
        XCTAssertFalse([cat.identifier isEqualToString:@"calendar-videos"]);
    }
}

- (void)testExtraForTitleCatalog
{
    NSString *manifestJSON = @"{\"id\":\"test\",\"name\":\"Test\",\"version\":\"1.0.0\",\"resources\":[\"catalog\"],\"types\":[\"movie\"]}";
    MacLCAddon *addon = [MacLCAddon addonWithTransportURL:@"https://example.com/manifest.json"
                                             manifestData:[manifestJSON dataUsingEncoding:NSUTF8StringEncoding]
                                                    error:nil];

    MacLCAddonTitleCatalog *popular = [[MacLCAddonTitleCatalog alloc] initWithAddon:addon
                                                                               type:@"movie"
                                                                         identifier:@"top"
                                                                               name:@"Popular"
                                                                             genres:@[@"Action", @"Sci-Fi", @"Talk Show"]
                                                                      requiresGenre:NO
                                                                       supportsSkip:YES];

    MacLCAddonTitleCatalog *yearCat = [[MacLCAddonTitleCatalog alloc] initWithAddon:addon
                                                                              type:@"movie"
                                                                        identifier:@"year"
                                                                              name:@"New"
                                                                            genres:@[@"2026", @"2025"]
                                                                     requiresGenre:YES
                                                                      supportsSkip:YES];

    MacLCAddonTitleCatalog *noSkipCat = [[MacLCAddonTitleCatalog alloc] initWithAddon:addon
                                                                                type:@"movie"
                                                                          identifier:@"custom"
                                                                                name:@"Custom"
                                                                              genres:@[@"Drama"]
                                                                       requiresGenre:NO
                                                                        supportsSkip:NO];

    // genre+skip order
    NSString *extra1 = [MacLCAddonStore extraForTitleCatalog:popular genre:@"Action" skip:100];
    XCTAssertEqualObjects(extra1, @"genre=Action&skip=100");

    // encoding of "Sci-Fi"
    NSString *extraSciFi = [MacLCAddonStore extraForTitleCatalog:popular genre:@"Sci-Fi" skip:100];
    XCTAssertEqualObjects(extraSciFi, @"genre=Sci-Fi&skip=100");

    NSString *extraSciFiNoSkip = [MacLCAddonStore extraForTitleCatalog:popular genre:@"Sci-Fi" skip:0];
    XCTAssertEqualObjects(extraSciFiNoSkip, @"genre=Sci-Fi");

    // encoding of a space
    NSString *extraSpace = [MacLCAddonStore extraForTitleCatalog:popular genre:@"Talk Show" skip:50];
    XCTAssertEqualObjects(extraSpace, @"genre=Talk%20Show&skip=50");

    // skip 0 omitted
    NSString *extraSkipZero = [MacLCAddonStore extraForTitleCatalog:popular genre:@"Action" skip:0];
    XCTAssertEqualObjects(extraSkipZero, @"genre=Action");

    NSString *extraNoGenreNoSkip = [MacLCAddonStore extraForTitleCatalog:popular genre:nil skip:0];
    XCTAssertNil(extraNoGenreNoSkip);

    // skip only (when genre is nil and not required)
    NSString *extraSkipOnly = [MacLCAddonStore extraForTitleCatalog:popular genre:nil skip:100];
    XCTAssertEqualObjects(extraSkipOnly, @"skip=100");

    // required genre defaulted to first option ("2026")
    NSString *extraReqDefault = [MacLCAddonStore extraForTitleCatalog:yearCat genre:nil skip:0];
    XCTAssertEqualObjects(extraReqDefault, @"genre=2026");

    NSString *extraReqDefaultWithSkip = [MacLCAddonStore extraForTitleCatalog:yearCat genre:nil skip:100];
    XCTAssertEqualObjects(extraReqDefaultWithSkip, @"genre=2026&skip=100");

    // explicit genre on required catalog
    NSString *extraReqExplicit = [MacLCAddonStore extraForTitleCatalog:yearCat genre:@"2025" skip:20];
    XCTAssertEqualObjects(extraReqExplicit, @"genre=2025&skip=20");

    // skip unsupported: skip omitted
    NSString *extraNoSkip = [MacLCAddonStore extraForTitleCatalog:noSkipCat genre:@"Drama" skip:100];
    XCTAssertEqualObjects(extraNoSkip, @"genre=Drama");
}

- (void)testCatalogItemDetails
{
    NSString *manifestJSON = @"{\"id\":\"com.linvo.cinemeta\",\"name\":\"Cinemeta\",\"version\":\"3.0.14\",\"resources\":[\"catalog\"],\"types\":[\"movie\"]}";
    MacLCAddon *addon = [MacLCAddon addonWithTransportURL:@"https://v3-cinemeta.strem.io/manifest.json"
                                             manifestData:[manifestJSON dataUsingEncoding:NSUTF8StringEncoding]
                                                    error:nil];

    // Real excerpt from catalog-movie-top.json with Unabomber and Backrooms
    NSString *catalogJSON = @"{\"metas\":["
        "{"
            "\"id\":\"tt6933238\","
            "\"name\":\"Unabomber\","
            "\"type\":\"movie\","
            "\"releaseInfo\":\"2026\","
            "\"poster\":\"https://images.metahub.space/poster/small/tt6933238/img\","
            "\"description\":\"A Harvard student becomes the Unabomber after psychological experiments. Years later, an FBI agent's pursuit reveals how his past shaped his deadly campaign that killed 3 and injured 23 from 1978-1995.\","
            "\"background\":\"https://images.metahub.space/background/medium/tt6933238/img\","
            "\"logo\":\"https://images.metahub.space/logo/medium/tt6933238/img\","
            "\"genres\":[\"Biography\",\"Crime\",\"Drama\"],"
            "\"imdbRating\":\"\","
            "\"runtime\":\"101 min\""
        "},"
        "{"
            "\"id\":\"tt26657236\","
            "\"name\":\"Backrooms\","
            "\"type\":\"movie\","
            "\"releaseInfo\":\"2026\","
            "\"poster\":\"https://images.metahub.space/poster/small/tt26657236/img\","
            "\"description\":\"After a therapist's patient disappears into a dimension beyond reality, she must venture into the unknown to save him.\","
            "\"background\":\"https://images.metahub.space/background/medium/tt26657236/img\","
            "\"logo\":\"https://images.metahub.space/logo/medium/tt26657236/img\","
            "\"genre\":[\"Horror\",\"Sci-Fi\",\"Thriller\"],"
            "\"imdbRating\":\"6.8\","
            "\"runtime\":\"111 min\""
        "}"
    "]}";

    NSError *error = nil;
    NSArray<MacLCAddonItem *> *items = [MacLCAddonStore itemsFromCatalogData:[catalogJSON dataUsingEncoding:NSUTF8StringEncoding]
                                                                       addon:addon
                                                                       error:&error];
    XCTAssertNotNil(items);
    XCTAssertNil(error);
    XCTAssertEqual(items.count, 2);

    // Item 0: Unabomber
    MacLCAddonItem *item0 = items[0];
    XCTAssertEqualObjects(item0.identifier, @"tt6933238");
    XCTAssertEqualObjects(item0.name, @"Unabomber");
    XCTAssertEqualObjects(item0.type, @"movie");
    XCTAssertEqualObjects(item0.releaseInfo, @"2026");
    XCTAssertEqualObjects(item0.posterURL.absoluteString, @"https://images.metahub.space/poster/small/tt6933238/img");
    XCTAssertEqualObjects(item0.backgroundURL.absoluteString, @"https://images.metahub.space/background/medium/tt6933238/img");
    XCTAssertEqualObjects(item0.logoURL.absoluteString, @"https://images.metahub.space/logo/medium/tt6933238/img");
    XCTAssertTrue([item0.itemDescription hasPrefix:@"A Harvard student"]);
    NSArray<NSString *> *expectedGenres0 = @[@"Biography", @"Crime", @"Drama"];
    XCTAssertEqualObjects(item0.genres, expectedGenres0);
    // Empty imdbRating string in JSON is parsed as nil
    XCTAssertNil(item0.imdbRating);
    XCTAssertEqualObjects(item0.runtime, @"101 min");

    // Item 1: Backrooms
    MacLCAddonItem *item1 = items[1];
    XCTAssertEqualObjects(item1.identifier, @"tt26657236");
    XCTAssertEqualObjects(item1.name, @"Backrooms");
    XCTAssertEqualObjects(item1.type, @"movie");
    XCTAssertEqualObjects(item1.releaseInfo, @"2026");
    XCTAssertEqualObjects(item1.posterURL.absoluteString, @"https://images.metahub.space/poster/small/tt26657236/img");
    XCTAssertEqualObjects(item1.backgroundURL.absoluteString, @"https://images.metahub.space/background/medium/tt26657236/img");
    XCTAssertEqualObjects(item1.logoURL.absoluteString, @"https://images.metahub.space/logo/medium/tt26657236/img");
    XCTAssertTrue([item1.itemDescription hasPrefix:@"After a therapist's patient"]);
    NSArray<NSString *> *expectedGenres1 = @[@"Horror", @"Sci-Fi", @"Thriller"];
    XCTAssertEqualObjects(item1.genres, expectedGenres1);
    XCTAssertEqualObjects(item1.imdbRating, @"6.8");
    XCTAssertEqualObjects(item1.runtime, @"111 min");
}

- (void)testSeriesMetaDetailsAndEpisodes
{
    // Real excerpt from meta-series-silo.json
    NSString *siloJSON = @"{\"meta\":{"
        "\"id\":\"tt14688458\","
        "\"name\":\"Silo\","
        "\"type\":\"series\","
        "\"releaseInfo\":\"2023–\","
        "\"poster\":\"https://images.metahub.space/poster/small/tt14688458/img\","
        "\"background\":\"https://images.metahub.space/background/medium/tt14688458/img\","
        "\"logo\":\"https://images.metahub.space/logo/medium/tt14688458/img\","
        "\"description\":\"Men and women live in a giant silo underground with several regulations which they believe are in place to protect them from the toxic and ruined world on the surface.\","
        "\"genres\":[\"Drama\",\"Mystery\",\"Sci-Fi\"],"
        "\"imdbRating\":\"8.1\","
        "\"runtime\":\"51 min\","
        "\"cast\":[\"Rebecca Ferguson\",\"Common\",\"Chinaza Uche\"],"
        "\"director\":[],"
        "\"trailerStreams\":[{\"title\":\"Silo\",\"ytId\":\"8ZYhuvIv1pA\"}],"
        "\"trailers\":[{\"source\":\"8ZYhuvIv1pA\",\"type\":\"Trailer\"}],"
        "\"videos\":["
            "{"
                "\"id\":\"tt14688458:0:1\","
                "\"name\":\"Building a World\","
                "\"season\":0,"
                "\"episode\":1,"
                "\"number\":1,"
                "\"released\":\"2023-06-30T08:00:00.000Z\","
                "\"thumbnail\":\"https://episodes.metahub.space/tt14688458/0/1/w780.jpg\","
                "\"overview\":\"A brief, behind the scenes look into the making of Silo.\""
            "},"
            "{"
                "\"id\":\"tt14688458:1:1\","
                "\"name\":\"Freedom Day\","
                "\"season\":1,"
                "\"episode\":1,"
                "\"number\":1,"
                "\"released\":\"2023-05-05T08:00:00.000Z\","
                "\"thumbnail\":\"https://episodes.metahub.space/tt14688458/1/1/w780.jpg\","
                "\"overview\":\"Sheriff Becker’s plans for the future are thrown off course after his wife meets a hacker with information about the silo.\""
            "}"
        "]"
    "}}";

    NSError *error = nil;
    MacLCAddonMeta *meta = [MacLCAddonStore metaFromData:[siloJSON dataUsingEncoding:NSUTF8StringEncoding]
                                          itemIdentifier:@"tt14688458"
                                                   error:&error];
    XCTAssertNotNil(meta);
    XCTAssertNil(error);

    // Meta details
    XCTAssertEqualObjects(meta.name, @"Silo");
    XCTAssertEqualObjects(meta.releaseInfo, @"2023–");
    XCTAssertEqualObjects(meta.posterURL.absoluteString, @"https://images.metahub.space/poster/small/tt14688458/img");
    XCTAssertEqualObjects(meta.backgroundURL.absoluteString, @"https://images.metahub.space/background/medium/tt14688458/img");
    XCTAssertEqualObjects(meta.logoURL.absoluteString, @"https://images.metahub.space/logo/medium/tt14688458/img");
    XCTAssertTrue([meta.itemDescription hasPrefix:@"Men and women live"]);
    NSArray<NSString *> *expectedGenres = @[@"Drama", @"Mystery", @"Sci-Fi"];
    XCTAssertEqualObjects(meta.genres, expectedGenres);
    XCTAssertEqualObjects(meta.imdbRating, @"8.1");
    XCTAssertEqualObjects(meta.runtime, @"51 min");
    NSArray<NSString *> *expectedCast = @[@"Rebecca Ferguson", @"Common", @"Chinaza Uche"];
    XCTAssertEqualObjects(meta.cast, expectedCast);
    XCTAssertEqual(meta.directors.count, 0);
    XCTAssertEqualObjects(meta.trailerYouTubeIdentifier, @"8ZYhuvIv1pA");

    // Episode details and thumbnails
    XCTAssertEqual(meta.videos.count, 2);

    MacLCAddonVideo *ep0 = meta.videos[0];
    XCTAssertEqualObjects(ep0.identifier, @"tt14688458:0:1");
    XCTAssertEqual(ep0.season, 0);
    XCTAssertEqual(ep0.episode, 1);
    XCTAssertEqualObjects(ep0.name, @"Building a World");
    XCTAssertNotNil(ep0.released);
    XCTAssertEqualObjects(ep0.thumbnailURL.absoluteString, @"https://episodes.metahub.space/tt14688458/0/1/w780.jpg");
    XCTAssertEqualObjects(ep0.overview, @"A brief, behind the scenes look into the making of Silo.");

    MacLCAddonVideo *ep1 = meta.videos[1];
    XCTAssertEqualObjects(ep1.identifier, @"tt14688458:1:1");
    XCTAssertEqual(ep1.season, 1);
    XCTAssertEqual(ep1.episode, 1);
    XCTAssertEqualObjects(ep1.name, @"Freedom Day");
    XCTAssertNotNil(ep1.released);
    XCTAssertEqualObjects(ep1.thumbnailURL.absoluteString, @"https://episodes.metahub.space/tt14688458/1/1/w780.jpg");
    XCTAssertTrue([ep1.overview hasPrefix:@"Sheriff Becker’s plans"]);
}

- (void)testMovieMetaDetails
{
    // Real excerpt from meta-movie-notld.json
    NSString *notldJSON = @"{\"meta\":{"
        "\"id\":\"tt0063350\","
        "\"name\":\"Night of the Living Dead\","
        "\"type\":\"movie\","
        "\"releaseInfo\":\"1968\","
        "\"poster\":\"https://images.metahub.space/poster/small/tt0063350/img\","
        "\"background\":\"https://images.metahub.space/background/medium/tt0063350/img\","
        "\"logo\":\"https://images.metahub.space/logo/medium/tt0063350/img\","
        "\"description\":\"A ragtag group of Pennsylvanians barricade themselves in an old farmhouse to remain safe from a horde of flesh-eating ghouls that are ravaging the Northeast of the United States.\","
        "\"genre\":[\"Horror\",\"Thriller\"],"
        "\"imdbRating\":\"7.8\","
        "\"runtime\":\"96 min\","
        "\"cast\":[\"Duane Jones\",\"Judith O'Dea\",\"Karl Hardman\"],"
        "\"director\":[\"George A. Romero\"],"
        "\"trailerStreams\":[{\"title\":\"Night of the Living Dead\",\"ytId\":\"DIuI6T48Sj0\"}],"
        "\"videos\":[]"
    "}}";

    NSError *error = nil;
    MacLCAddonMeta *meta = [MacLCAddonStore metaFromData:[notldJSON dataUsingEncoding:NSUTF8StringEncoding]
                                          itemIdentifier:@"tt0063350"
                                                   error:&error];
    XCTAssertNotNil(meta);
    XCTAssertNil(error);
    XCTAssertEqualObjects(meta.name, @"Night of the Living Dead");
    XCTAssertEqualObjects(meta.releaseInfo, @"1968");
    XCTAssertEqualObjects(meta.imdbRating, @"7.8");
    XCTAssertEqualObjects(meta.runtime, @"96 min");
    NSArray<NSString *> *expectedGenres = @[@"Horror", @"Thriller"];
    XCTAssertEqualObjects(meta.genres, expectedGenres);
    NSArray<NSString *> *expectedCast = @[@"Duane Jones", @"Judith O'Dea", @"Karl Hardman"];
    XCTAssertEqualObjects(meta.cast, expectedCast);
    NSArray<NSString *> *expectedDirectors = @[@"George A. Romero"];
    XCTAssertEqualObjects(meta.directors, expectedDirectors);
    XCTAssertEqualObjects(meta.trailerYouTubeIdentifier, @"DIuI6T48Sj0");
    XCTAssertEqual(meta.videos.count, 0);
}

@end
