/*****************************************************************************
 * MacLCWatchLibraryTest.m: tests for the watch history, resume points and favorites
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
#import "addons/watch/MacLCWatchLibrary.h"

@interface MacLCAddonVideo (WatchTestInit)
- (instancetype)initWithIdentifier:(NSString *)identifier
                            season:(NSInteger)season
                           episode:(NSInteger)episode
                              name:(nullable NSString *)name
                          released:(nullable NSDate *)released;
@end

/* Private to the library, for the tests. */
@interface MacLCWatchLibrary (WatchTest)
@property (copy) NSDate * (^now)(void);
@property (readonly) NSUInteger writeCount;
@end

static NSString * const kCinemeta = @"https://v3-cinemeta.strem.io/manifest.json";

/* A real Cinemeta catalog entry (Cinemeta "top" movie catalog, 2026-10-09),
 * trimmed of its popularity numbers. */
static NSString * const kUnabomberCatalog =
    @"{\"metas\":[{\"imdb_id\":\"tt6933238\",\"cast\":[\"Annabelle Wallis\",\"Shailene Woodley\"],"
    @"\"country\":\"United States\",\"description\":\"A Harvard student becomes the Unabomber.\","
    @"\"director\":[\"Janus Metz\"],\"genre\":[\"Biography\",\"Crime\",\"Drama\"],\"imdbRating\":\"\","
    @"\"name\":\"Unabomber\",\"released\":\"2026-09-25T00:00:00.000Z\",\"slug\":\"movie/unabomber-6933238\","
    @"\"type\":\"movie\",\"year\":\"2026\",\"moviedb_id\":1492640,\"popularity\":4.321546666666666,"
    @"\"background\":\"https://images.metahub.space/background/medium/tt6933238/img\","
    @"\"logo\":\"https://images.metahub.space/logo/medium/tt6933238/img\","
    @"\"poster\":\"https://images.metahub.space/poster/small/tt6933238/img\",\"runtime\":\"101 min\","
    @"\"id\":\"tt6933238\",\"genres\":[\"Biography\",\"Crime\",\"Drama\"],\"releaseInfo\":\"2026\"}]}";

@interface MacLCWatchLibraryTest : XCTestCase
@end

@implementation MacLCWatchLibraryTest

#pragma mark Helpers

- (NSURL *)freshFileURL
{
    NSString *directory = [NSTemporaryDirectory() stringByAppendingPathComponent:
                           [@"maclc-watch-test-" stringByAppendingString:NSUUID.UUID.UUIDString]];
    [NSFileManager.defaultManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil];
    return [NSURL fileURLWithPath:[directory stringByAppendingPathComponent:@"library.json"]];
}

- (MacLCAddonItem *)itemWithIdentifier:(NSString *)identifier type:(NSString *)type name:(NSString *)name
{
    NSDictionary *meta = @{@"id": identifier, @"type": type, @"name": name, @"releaseInfo": @"2026",
                           @"poster": @"https://example.com/poster.jpg", @"genres": @[@"Drama"],
                           @"customKey": @{@"nested": @[@1, @2]}};
    return [MacLCAddonItem itemFromRawMeta:meta addonTransportURL:kCinemeta];
}

- (MacLCAddonItem *)movie:(NSString *)identifier
{
    return [self itemWithIdentifier:identifier type:@"movie" name:[@"Movie " stringByAppendingString:identifier]];
}

- (MacLCAddonItem *)show
{
    return [self itemWithIdentifier:@"tt1" type:@"series" name:@"The Show"];
}

- (MacLCAddonVideo *)episode:(NSInteger)episode season:(NSInteger)season name:(NSString *)name released:(NSDate *)released
{
    return [[MacLCAddonVideo alloc] initWithIdentifier:[NSString stringWithFormat:@"tt1:%ld:%ld", (long)season, (long)episode]
                                                season:season
                                               episode:episode
                                                  name:name
                                              released:released];
}

/// S1E1 "Pilot" ... S1E4, a special (S0E1) and a season 2 episode that airs next year.
- (NSArray<MacLCAddonVideo *> *)episodeList
{
    NSDate *past = [NSDate dateWithTimeIntervalSince1970:1700000000];
    NSDate *future = [NSDate dateWithTimeIntervalSinceNow:365 * 86400];
    return @[[self episode:1 season:0 name:@"Making of" released:past],
             [self episode:1 season:1 name:@"Pilot" released:past],
             [self episode:2 season:1 name:@"Second" released:past],
             [self episode:3 season:1 name:@"Third" released:past],
             [self episode:4 season:1 name:@"Fourth" released:past],
             [self episode:1 season:2 name:@"Later" released:future]];
}

- (MacLCAddonVideo *)episodeNumber:(NSInteger)number
{
    for (MacLCAddonVideo *video in [self episodeList]) {
        if (video.season == 1 && video.episode == number) {
            return video;
        }
    }
    return nil;
}

- (MacLCWatchLibrary *)library
{
    return [[MacLCWatchLibrary alloc] initWithFileURL:[self freshFileURL]];
}

/// A library whose clock advances 10 s with every call.
- (MacLCWatchLibrary *)libraryWithClockAt:(NSURL *)url
{
    MacLCWatchLibrary *library = [[MacLCWatchLibrary alloc] initWithFileURL:url];
    __block NSTimeInterval t = 1760000000;
    library.now = ^NSDate * { t += 10; return [NSDate dateWithTimeIntervalSince1970:t]; };
    return library;
}

- (void)spinFor:(NSTimeInterval)seconds
{
    [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:seconds]];
}

- (NSDictionary *)readJSON:(NSURL *)url
{
    NSData *data = [NSData dataWithContentsOfURL:url];
    return data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
}

#pragma mark MacLCAddons additions

- (void)testItemFromRawMetaRoundTripsARealCinemetaEntry
{
    NSData *data = [kUnabomberCatalog dataUsingEncoding:NSUTF8StringEncoding];
    MacLCAddon *cinemeta = nil;
    for (MacLCAddon *addon in [MacLCAddonStore sharedStore].installedAddons) {
        if ([addon.identifier isEqualToString:@"com.linvo.cinemeta"]) {
            cinemeta = addon;
        }
    }
    XCTAssertNotNil(cinemeta);
    NSArray<MacLCAddonItem *> *items = [MacLCAddonStore itemsFromCatalogData:data addon:cinemeta error:nil];
    XCTAssertEqual(items.count, (NSUInteger)1);
    MacLCAddonItem *item = items.firstObject;
    XCTAssertNotNil(item.rawMeta);
    XCTAssertEqualObjects(item.rawMeta[@"slug"], @"movie/unabomber-6933238");

    /* Through JSON, as the library stores it. */
    NSData *stored = [NSJSONSerialization dataWithJSONObject:item.rawMeta options:0 error:nil];
    NSDictionary *meta = [NSJSONSerialization JSONObjectWithData:stored options:0 error:nil];
    MacLCAddonItem *rebuilt = [MacLCAddonItem itemFromRawMeta:meta addonTransportURL:kCinemeta];
    XCTAssertNotNil(rebuilt);
    XCTAssertEqualObjects(rebuilt.identifier, @"tt6933238");
    XCTAssertEqualObjects(rebuilt.type, @"movie");
    XCTAssertEqualObjects(rebuilt.name, @"Unabomber");
    XCTAssertEqualObjects(rebuilt.releaseInfo, @"2026");
    XCTAssertEqualObjects(rebuilt.posterURL, item.posterURL);
    XCTAssertEqualObjects(rebuilt.backgroundURL, item.backgroundURL);
    XCTAssertEqualObjects(rebuilt.genres, (@[@"Biography", @"Crime", @"Drama"]));
    XCTAssertEqualObjects(rebuilt.runtime, @"101 min");
    XCTAssertEqualObjects(rebuilt.rawMeta, item.rawMeta);
    XCTAssertEqualObjects(rebuilt.addon.identifier, @"com.linvo.cinemeta");
}

- (void)testItemFromRawMetaRejectsWhatIsNotATitle
{
    XCTAssertNil([MacLCAddonItem itemFromRawMeta:@{@"id": @"tt1"} addonTransportURL:kCinemeta]);
    XCTAssertNil([MacLCAddonItem itemFromRawMeta:@{@"name": @"No id"} addonTransportURL:kCinemeta]);
    XCTAssertNil([MacLCAddonItem itemFromRawMeta:@{} addonTransportURL:@"https://nowhere.example/manifest.json"]);
    /* An unknown add-on falls back to the default one. */
    MacLCAddonItem *item = [MacLCAddonItem itemFromRawMeta:@{@"id": @"tt1", @"name": @"X"}
                                         addonTransportURL:@"https://nowhere.example/manifest.json"];
    XCTAssertEqualObjects(item.addon.identifier, @"com.linvo.cinemeta");
}

#pragma mark Storage

- (void)testRoundTripThroughTheFile
{
    NSURL *url = [self freshFileURL];
    MacLCWatchLibrary *library = [self libraryWithClockAt:url];
    MacLCAddonItem *movie = [self movie:@"tt10"];
    [library recordPosition:600 duration:7200 forItem:movie video:nil streamMRL:@"magnet:?xt=urn:btih:abc" streamLabel:@"1080p · Test"];
    [library setFavorite:YES forItem:[self show]];
    [library flush];

    NSDictionary *json = [self readJSON:url];
    XCTAssertEqualObjects(json[@"version"], @1);
    XCTAssertEqual([json[@"titles"] count], (NSUInteger)2);

    MacLCWatchLibrary *reloaded = [[MacLCWatchLibrary alloc] initWithFileURL:url];
    MacLCWatchEntry *entry = [reloaded entryForTitle:@"tt10"];
    XCTAssertNotNil(entry);
    XCTAssertEqualObjects(entry.item.name, @"Movie tt10");
    XCTAssertEqualObjects(entry.item.rawMeta[@"customKey"], (@{@"nested": @[@1, @2]}));
    XCTAssertEqualObjects(entry.type, @"movie");
    XCTAssertFalse(entry.isFavorite);
    MacLCWatchProgress *p = [reloaded progressForTitle:@"tt10" video:nil];
    XCTAssertEqualWithAccuracy(p.position, 600.0, 0.001);
    XCTAssertEqualWithAccuracy(p.duration, 7200.0, 0.001);
    XCTAssertEqualObjects(p.videoIdentifier, @"tt10");
    XCTAssertEqualObjects(p.streamMRL, @"magnet:?xt=urn:btih:abc");
    XCTAssertEqualObjects(p.streamLabel, @"1080p · Test");
    XCTAssertTrue(p.canResume);
    XCTAssertTrue([reloaded isFavorite:@"tt1"]);
    XCTAssertEqual(reloaded.historyEntries.count, (NSUInteger)1);
    XCTAssertEqual(reloaded.favoriteEntries.count, (NSUInteger)1);
}

- (void)testWritesAreCoalescedAndFlushIsSynchronous
{
    NSURL *url = [self freshFileURL];
    MacLCWatchLibrary *library = [[MacLCWatchLibrary alloc] initWithFileURL:url];
    MacLCAddonItem *movie = [self movie:@"tt10"];
    for (int i = 0; i < 20; i++) {
        [library recordPosition:100 + i duration:7200 forItem:movie video:nil streamMRL:nil streamLabel:nil];
    }
    XCTAssertEqual(library.writeCount, (NSUInteger)0);
    XCTAssertFalse([NSFileManager.defaultManager fileExistsAtPath:url.path]);
    [library flush];
    XCTAssertEqual(library.writeCount, (NSUInteger)1);
    XCTAssertTrue([NSFileManager.defaultManager fileExistsAtPath:url.path]);
    [library flush];
    XCTAssertEqual(library.writeCount, (NSUInteger)1); // nothing pending

    /* Pending changes are written by themselves, once, after a moment. */
    for (int i = 0; i < 20; i++) {
        [library recordPosition:200 + i duration:7200 forItem:movie video:nil streamMRL:nil streamLabel:nil];
    }
    XCTAssertEqual(library.writeCount, (NSUInteger)1);
    [self spinFor:2.5];
    XCTAssertEqual(library.writeCount, (NSUInteger)2);
    NSDictionary *json = [self readJSON:url];
    XCTAssertEqualWithAccuracy([json[@"titles"][0][@"progress"][0][@"pos"] doubleValue], 219.0, 0.001);

    /* flush from another thread. */
    [library recordPosition:300 duration:7200 forItem:movie video:nil streamMRL:nil streamLabel:nil];
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        [library flush];
        dispatch_semaphore_signal(done);
    });
    dispatch_semaphore_wait(done, DISPATCH_TIME_FOREVER);
    XCTAssertEqualWithAccuracy([[self readJSON:url][@"titles"][0][@"progress"][0][@"pos"] doubleValue], 300.0, 0.001);
}

- (void)testUnknownKeysAreKept
{
    NSURL *url = [self freshFileURL];
    NSString *json = @"{\"version\":1,\"futureRoot\":{\"a\":1},\"titles\":[{\"id\":\"tt10\",\"type\":\"movie\","
        @"\"addon\":\"https://v3-cinemeta.strem.io/manifest.json\",\"meta\":{\"id\":\"tt10\",\"name\":\"Old\",\"type\":\"movie\"},"
        @"\"futureTitleKey\":[1,2],\"progress\":[{\"video\":\"tt10\",\"s\":0,\"e\":0,\"pos\":100,\"dur\":3000,"
        @"\"watched\":false,\"last\":1760000000,\"futureProgressKey\":\"x\"}]}]}";
    [[json dataUsingEncoding:NSUTF8StringEncoding] writeToURL:url atomically:YES];
    MacLCWatchLibrary *library = [[MacLCWatchLibrary alloc] initWithFileURL:url];
    XCTAssertEqualObjects([library entryForTitle:@"tt10"].item.name, @"Old");
    [library recordPosition:200 duration:3000 forItem:[self movie:@"tt10"] video:nil streamMRL:nil streamLabel:nil];
    [library flush];

    NSDictionary *saved = [self readJSON:url];
    XCTAssertEqualObjects(saved[@"futureRoot"], (@{@"a": @1}));
    NSDictionary *title = saved[@"titles"][0];
    XCTAssertEqualObjects(title[@"futureTitleKey"], (@[@1, @2]));
    XCTAssertEqualObjects(title[@"progress"][0][@"futureProgressKey"], @"x");
    XCTAssertEqualWithAccuracy([title[@"progress"][0][@"pos"] doubleValue], 200.0, 0.001);
}

- (void)testAFileWithAHigherVersionIsLeftUntouched
{
    NSURL *url = [self freshFileURL];
    NSString *json = @"{\"version\":2,\"titles\":[{\"id\":\"tt10\",\"type\":\"movie\",\"meta\":{\"id\":\"tt10\",\"name\":\"Newer\"}}],\"extra\":true}";
    NSData *original = [json dataUsingEncoding:NSUTF8StringEncoding];
    [original writeToURL:url atomically:YES];
    MacLCWatchLibrary *library = [[MacLCWatchLibrary alloc] initWithFileURL:url];
    [library recordPosition:600 duration:7200 forItem:[self movie:@"tt11"] video:nil streamMRL:nil streamLabel:nil];
    XCTAssertEqual([library historyEntries].count, (NSUInteger)1); // works in memory
    [library flush];
    [self spinFor:2.0];
    XCTAssertEqualObjects([NSData dataWithContentsOfURL:url], original);
    XCTAssertEqual(library.writeCount, (NSUInteger)0);
    XCTAssertFalse([NSFileManager.defaultManager fileExistsAtPath:[url.path stringByAppendingString:@".bad"]]);
}

- (void)testACorruptFileIsRenamedOnceAndTheLibraryStartsEmpty
{
    NSURL *url = [self freshFileURL];
    NSData *garbage = [@"{ not json at all" dataUsingEncoding:NSUTF8StringEncoding];
    [garbage writeToURL:url atomically:YES];
    MacLCWatchLibrary *library = [[MacLCWatchLibrary alloc] initWithFileURL:url];
    XCTAssertEqual(library.historyEntries.count, (NSUInteger)0);
    NSString *bad = [url.path stringByAppendingString:@".bad"];
    XCTAssertFalse([NSFileManager.defaultManager fileExistsAtPath:url.path]);
    XCTAssertEqualObjects([NSData dataWithContentsOfFile:bad], garbage);

    [library recordPosition:600 duration:7200 forItem:[self movie:@"tt10"] video:nil streamMRL:nil streamLabel:nil];
    [library flush];
    XCTAssertTrue([NSFileManager.defaultManager fileExistsAtPath:url.path]);
    /* Reopening a good file does not touch the .bad one. */
    (void)[[MacLCWatchLibrary alloc] initWithFileURL:url];
    XCTAssertEqualObjects([NSData dataWithContentsOfFile:bad], garbage);

    /* A missing or empty file is just an empty library, not a .bad. */
    NSURL *empty = [self freshFileURL];
    [NSData.data writeToURL:empty atomically:YES];
    XCTAssertEqual([[MacLCWatchLibrary alloc] initWithFileURL:empty].historyEntries.count, (NSUInteger)0);
    XCTAssertTrue([NSFileManager.defaultManager fileExistsAtPath:empty.path]);
}

#pragma mark Recording rules

- (void)testWatchedFromNinetyTwoPercent
{
    MacLCWatchLibrary *library = [self library];
    MacLCAddonItem *movie = [self movie:@"tt10"];
    [library recordPosition:6600 duration:7200 forItem:movie video:nil streamMRL:nil streamLabel:nil];
    XCTAssertFalse([library progressForTitle:@"tt10" video:nil].isWatched);
    XCTAssertFalse([library entryForTitle:@"tt10"].isWatched);
    XCTAssertEqualWithAccuracy([library entryForTitle:@"tt10"].fraction, 6600.0 / 7200.0, 0.0001);

    [library recordPosition:6624 duration:7200 forItem:movie video:nil streamMRL:nil streamLabel:nil]; // exactly 92 %
    MacLCWatchProgress *p = [library progressForTitle:@"tt10" video:nil];
    XCTAssertTrue(p.isWatched);
    XCTAssertEqualWithAccuracy(p.fraction, 1.0, 0.0001);
    XCTAssertFalse(p.canResume);
    XCTAssertTrue([library entryForTitle:@"tt10"].isWatched);
    XCTAssertNil([library entryForTitle:@"tt10"].resumeTarget);

    /* A later save mid-film keeps it watched and does not move the position. */
    [library recordPosition:3000 duration:7200 forItem:movie video:nil streamMRL:nil streamLabel:nil];
    p = [library progressForTitle:@"tt10" video:nil];
    XCTAssertTrue(p.isWatched);
    XCTAssertEqualWithAccuracy(p.position, 6624.0, 0.001);

    /* Starting over (a save under 15 s) tracks it normally again. */
    [library recordPosition:4 duration:7200 forItem:movie video:nil streamMRL:nil streamLabel:nil];
    XCTAssertFalse([library progressForTitle:@"tt10" video:nil].isWatched);
    XCTAssertNil([library entryForTitle:@"tt10"].resumeTarget);
    [library recordPosition:1800 duration:7200 forItem:movie video:nil streamMRL:nil streamLabel:nil];
    XCTAssertFalse([library entryForTitle:@"tt10"].isWatched);
    XCTAssertEqual(library.continueWatchingEntries.count, (NSUInteger)1);
    XCTAssertEqualWithAccuracy([library progressForTitle:@"tt10" video:nil].position, 1800.0, 0.001);
    [library recordPosition:6700 duration:7200 forItem:movie video:nil streamMRL:nil streamLabel:nil];
    XCTAssertTrue([library entryForTitle:@"tt10"].isWatched);
    XCTAssertEqual(library.continueWatchingEntries.count, (NSUInteger)0);
}

- (void)testShortPositionsAreIgnoredUnlessThereIsProgress
{
    MacLCWatchLibrary *library = [self library];
    MacLCAddonItem *movie = [self movie:@"tt10"];
    [library recordPosition:14.9 duration:7200 forItem:movie video:nil streamMRL:nil streamLabel:nil];
    XCTAssertNil([library entryForTitle:@"tt10"]);
    XCTAssertEqual(library.historyEntries.count, (NSUInteger)0);

    [library recordPosition:15 duration:7200 forItem:movie video:nil streamMRL:nil streamLabel:nil];
    XCTAssertNotNil([library entryForTitle:@"tt10"]);
    XCTAssertTrue([library progressForTitle:@"tt10" video:nil].canResume);

    /* Started over: the existing progress follows. */
    [library recordPosition:3 duration:7200 forItem:movie video:nil streamMRL:nil streamLabel:nil];
    MacLCWatchProgress *p = [library progressForTitle:@"tt10" video:nil];
    XCTAssertEqualWithAccuracy(p.position, 3.0, 0.001);
    XCTAssertFalse(p.canResume);
}

- (void)testCanResumeNeedsThirtySecondsLeft
{
    MacLCWatchLibrary *library = [self library];
    MacLCAddonItem *movie = [self movie:@"tt10"];
    [library recordPosition:250 duration:300 forItem:movie video:nil streamMRL:nil streamLabel:nil]; // 50 s left
    XCTAssertTrue([library progressForTitle:@"tt10" video:nil].canResume);
    [library recordPosition:271 duration:300 forItem:movie video:nil streamMRL:nil streamLabel:nil]; // 29 s left, 90 %
    MacLCWatchProgress *p = [library progressForTitle:@"tt10" video:nil];
    XCTAssertFalse(p.isWatched);
    XCTAssertFalse(p.canResume);
    XCTAssertNil([library entryForTitle:@"tt10"].resumeTarget);
}

- (void)testMarkingUnwatchedRemovesProgressAndLateSavesDoNotBringItBack
{
    MacLCWatchLibrary *library = [self library];
    MacLCAddonItem *movie = [self movie:@"tt10"];
    [library recordPosition:600 duration:7200 forItem:movie video:nil streamMRL:nil streamLabel:nil];
    [library markWatched:NO forItem:movie video:nil];
    XCTAssertNil([library progressForTitle:@"tt10" video:nil]);
    XCTAssertNil([library entryForTitle:@"tt10"]); // no other progress, not a favorite: gone
    XCTAssertEqual(library.historyEntries.count, (NSUInteger)0);

    /* The tracker of the playback that was running saves once more. */
    [library recordPosition:620 duration:7200 forItem:movie video:nil streamMRL:nil streamLabel:nil];
    XCTAssertNil([library entryForTitle:@"tt10"]);

    /* Playing it again from the start brings it back. */
    [library recordPosition:2 duration:7200 forItem:movie video:nil streamMRL:nil streamLabel:nil];
    [library recordPosition:30 duration:7200 forItem:movie video:nil streamMRL:nil streamLabel:nil];
    XCTAssertEqualWithAccuracy([library progressForTitle:@"tt10" video:nil].position, 30.0, 0.001);
}

- (void)testMarkWatchedByHandAndKeepFavoriteWhenForgotten
{
    MacLCWatchLibrary *library = [self libraryWithClockAt:[self freshFileURL]];
    MacLCAddonItem *movie = [self movie:@"tt10"];
    [library setFavorite:YES forItem:movie];
    [library markWatched:YES forItem:movie video:nil];
    MacLCWatchEntry *entry = [library entryForTitle:@"tt10"];
    XCTAssertTrue(entry.isWatched);
    XCTAssertTrue(entry.isFavorite);
    XCTAssertNil(entry.latestProgress.streamMRL);
    XCTAssertEqual(library.historyEntries.count, (NSUInteger)1);

    [library markWatched:NO forItem:movie video:nil];
    entry = [library entryForTitle:@"tt10"];
    XCTAssertNotNil(entry); // still a favorite
    XCTAssertFalse(entry.isWatched);
    XCTAssertNil(entry.latestProgress);
    XCTAssertEqual(library.historyEntries.count, (NSUInteger)0);

    [library recordPosition:2 duration:7200 forItem:movie video:nil streamMRL:nil streamLabel:nil];
    [library recordPosition:600 duration:7200 forItem:movie video:nil streamMRL:nil streamLabel:nil];
    XCTAssertEqual(library.historyEntries.count, (NSUInteger)1);
    [library removeFromHistory:@"tt10"];
    XCTAssertTrue([library entryForTitle:@"tt10"].isFavorite);
    XCTAssertNil([library entryForTitle:@"tt10"].latestProgress);
}

#pragma mark Lists

- (void)testFavoritesAreNewestFirstAndDroppedWhenUnused
{
    MacLCWatchLibrary *library = [self libraryWithClockAt:[self freshFileURL]];
    [library setFavorite:YES forItem:[self movie:@"tt1"]];
    [library setFavorite:YES forItem:[self movie:@"tt2"]];
    [library setFavorite:YES forItem:[self movie:@"tt3"]];
    [library setFavorite:YES forItem:[self movie:@"tt1"]]; // already one: keeps its date
    NSArray *ids = [library.favoriteEntries valueForKey:@"identifier"];
    XCTAssertEqualObjects(ids, (@[@"tt3", @"tt2", @"tt1"]));
    XCTAssertEqual(library.historyEntries.count, (NSUInteger)0);
    XCTAssertEqual(library.continueWatchingEntries.count, (NSUInteger)0);

    [library setFavorite:NO forItem:[self movie:@"tt2"]];
    XCTAssertNil([library entryForTitle:@"tt2"]);
    ids = [library.favoriteEntries valueForKey:@"identifier"];
    XCTAssertEqualObjects(ids, (@[@"tt3", @"tt1"]));
    [library clearFavorites];
    XCTAssertEqual(library.favoriteEntries.count, (NSUInteger)0);
    XCTAssertNil([library entryForTitle:@"tt3"]);
}

- (void)testHistoryIsMostRecentlyPlayedFirst
{
    MacLCWatchLibrary *library = [self libraryWithClockAt:[self freshFileURL]];
    for (NSString *identifier in @[@"tt1", @"tt2", @"tt3"]) {
        [library recordPosition:100 duration:7200 forItem:[self movie:identifier] video:nil streamMRL:nil streamLabel:nil];
    }
    [library recordPosition:200 duration:7200 forItem:[self movie:@"tt1"] video:nil streamMRL:nil streamLabel:nil];
    XCTAssertEqualObjects([library.historyEntries valueForKey:@"identifier"], (@[@"tt1", @"tt3", @"tt2"]));
    XCTAssertEqualObjects([library.continueWatchingEntries valueForKey:@"identifier"], (@[@"tt1", @"tt3", @"tt2"]));
    [library clearHistory];
    XCTAssertEqual(library.historyEntries.count, (NSUInteger)0);
}

- (void)testContinueWatchingIsLimitedToThirty
{
    MacLCWatchLibrary *library = [self libraryWithClockAt:[self freshFileURL]];
    for (int i = 0; i < 35; i++) {
        [library recordPosition:100 duration:7200 forItem:[self movie:[NSString stringWithFormat:@"tt%d", i]]
                          video:nil streamMRL:nil streamLabel:nil];
    }
    XCTAssertEqual(library.historyEntries.count, (NSUInteger)35);
    XCTAssertEqual(library.continueWatchingEntries.count, (NSUInteger)30);
    XCTAssertEqualObjects(library.continueWatchingEntries.firstObject.identifier, @"tt34");
}

#pragma mark Continue watching

- (void)testContinueWatchingAMovieInProgress
{
    MacLCWatchLibrary *library = [self library];
    MacLCAddonItem *movie = [self movie:@"tt10"];
    [library recordPosition:2880 duration:7200 forItem:movie video:nil streamMRL:@"magnet:x" streamLabel:nil];
    MacLCWatchResumeTarget *target = [library entryForTitle:@"tt10"].resumeTarget;
    XCTAssertNotNil(target);
    XCTAssertEqual(target.kind, MacLCWatchResumeKindResume);
    XCTAssertEqualObjects(target.videoIdentifier, @"tt10");
    XCTAssertEqualObjects(target.detailText, @"1 h 12 min left");
    XCTAssertEqualObjects(target.progress.streamMRL, @"magnet:x");
    XCTAssertEqual(library.continueWatchingEntries.count, (NSUInteger)1);
}

- (void)testResumeTextWhenTheDurationIsUnknownAndForShortMovies
{
    MacLCWatchLibrary *library = [self library];
    [library recordPosition:300 duration:0 forItem:[self movie:@"tt10"] video:nil streamMRL:nil streamLabel:nil];
    XCTAssertEqualObjects([library entryForTitle:@"tt10"].resumeTarget.detailText, @"Resume");
    [library recordPosition:1500 duration:5400 forItem:[self movie:@"tt11"] video:nil streamMRL:nil streamLabel:nil];
    XCTAssertEqualObjects([library entryForTitle:@"tt11"].resumeTarget.detailText, @"1 h 5 min left");
    [library recordPosition:1820 duration:2000 forItem:[self movie:@"tt12"] video:nil streamMRL:nil streamLabel:nil]; // 3 min left
    XCTAssertEqualObjects([library entryForTitle:@"tt12"].resumeTarget.detailText, @"3 min left");
    [library recordPosition:0.5 * 3600 duration:2 * 3600 forItem:[self movie:@"tt13"] video:nil streamMRL:nil streamLabel:nil];
    XCTAssertEqualObjects([library entryForTitle:@"tt13"].resumeTarget.detailText, @"1 h 30 min left");
    [library recordPosition:3600 duration:3 * 3600 forItem:[self movie:@"tt14"] video:nil streamMRL:nil streamLabel:nil];
    XCTAssertEqualObjects([library entryForTitle:@"tt14"].resumeTarget.detailText, @"2 h left");
}

- (void)testContinueWatchingAShowEpisodeInProgress
{
    MacLCWatchLibrary *library = [self libraryWithClockAt:[self freshFileURL]];
    MacLCAddonItem *show = [self show];
    [library updateEpisodes:[self episodeList] forItem:show];
    [library recordPosition:1320 duration:2700 forItem:show video:[self episodeNumber:3] streamMRL:nil streamLabel:nil];
    MacLCWatchEntry *entry = [library entryForTitle:@"tt1"];
    XCTAssertEqual(entry.resumeTarget.kind, MacLCWatchResumeKindResume);
    XCTAssertEqualObjects(entry.resumeTarget.videoIdentifier, @"tt1:1:3");
    XCTAssertEqual(entry.resumeTarget.season, (NSInteger)1);
    XCTAssertEqual(entry.resumeTarget.episode, (NSInteger)3);
    XCTAssertEqualObjects(entry.resumeTarget.detailText, @"S1, E3 · 23 min left");
    XCTAssertEqualObjects(entry.latestProgress.episodeName, @"Third");
    XCTAssertFalse(entry.isWatched);
    XCTAssertEqual(entry.watchedEpisodeCount, (NSUInteger)0);
}

- (void)testNextUpAfterAWatchedEpisodeNeedsTheEpisodeList
{
    MacLCWatchLibrary *library = [self libraryWithClockAt:[self freshFileURL]];
    MacLCAddonItem *show = [self show];
    [library markWatched:YES forItem:show video:[self episodeNumber:3]];
    XCTAssertNil([library entryForTitle:@"tt1"].resumeTarget); // list unknown

    /* The list arrives later (from the title page), also when the title was new. */
    [library updateEpisodes:[self episodeList] forItem:show];
    MacLCWatchResumeTarget *target = [library entryForTitle:@"tt1"].resumeTarget;
    XCTAssertEqual(target.kind, MacLCWatchResumeKindNextUp);
    XCTAssertEqualObjects(target.videoIdentifier, @"tt1:1:4");
    XCTAssertEqualObjects(target.detailText, @"Next: S1, E4 · Fourth");
    XCTAssertNil(target.progress);
    XCTAssertEqual(library.continueWatchingEntries.count, (NSUInteger)1);

    /* Episodes already watched are skipped; a half-watched one is resumed. */
    [library markWatched:YES forItem:show video:[self episodeNumber:4]];
    XCTAssertNil([library entryForTitle:@"tt1"].resumeTarget); // S2E1 is not out yet
    [library markWatched:NO forItem:show video:[self episodeNumber:4]];
    [library recordPosition:2 duration:2700 forItem:show video:[self episodeNumber:4] streamMRL:nil streamLabel:nil]; // plays again from the start
    [library recordPosition:600 duration:2700 forItem:show video:[self episodeNumber:4] streamMRL:nil streamLabel:nil];
    [library markWatched:YES forItem:show video:[self episodeNumber:2]];
    target = [library entryForTitle:@"tt1"].resumeTarget;
    XCTAssertEqual(target.kind, MacLCWatchResumeKindResume); // most recent is S1E2 -> next is S1E3 (watched) -> S1E4 half-watched
    XCTAssertEqualObjects(target.videoIdentifier, @"tt1:1:4");
}

- (void)testNextUpTextWithoutAnEpisodeName
{
    MacLCWatchLibrary *library = [self library];
    MacLCAddonItem *show = [self show];
    NSDate *past = [NSDate dateWithTimeIntervalSince1970:1700000000];
    [library updateEpisodes:@[[self episode:1 season:1 name:nil released:past], [self episode:2 season:1 name:nil released:nil]] forItem:show];
    [library markWatched:YES forItem:show video:[self episode:1 season:1 name:nil released:past]];
    XCTAssertEqualObjects([library entryForTitle:@"tt1"].resumeTarget.detailText, @"Next: S1, E2");
}

- (void)testNothingToContinueWhenEverythingIsWatched
{
    MacLCWatchLibrary *library = [self libraryWithClockAt:[self freshFileURL]];
    MacLCAddonItem *show = [self show];
    [library updateEpisodes:[self episodeList] forItem:show];
    [library markWatched:YES forItem:show videos:@[[self episodeNumber:1], [self episodeNumber:2], [self episodeNumber:3]]];
    XCTAssertFalse([library entryForTitle:@"tt1"].isWatched);
    XCTAssertEqual([library entryForTitle:@"tt1"].watchedEpisodeCount, (NSUInteger)3);
    XCTAssertNotNil([library entryForTitle:@"tt1"].resumeTarget);

    [library markWatched:YES forItem:show video:[self episodeNumber:4]];
    MacLCWatchEntry *entry = [library entryForTitle:@"tt1"];
    /* The special and the season 2 episode that airs next year do not count. */
    XCTAssertTrue(entry.isWatched);
    XCTAssertNil(entry.resumeTarget);
    XCTAssertEqual(entry.watchedEpisodeCount, (NSUInteger)4);
    XCTAssertEqual(library.continueWatchingEntries.count, (NSUInteger)0);
    XCTAssertEqual(library.historyEntries.count, (NSUInteger)1);

    /* Forget one episode: not watched anymore, and it is next up again. */
    [library markWatched:NO forItem:show video:[self episodeNumber:2]];
    XCTAssertFalse([library entryForTitle:@"tt1"].isWatched);
}

- (void)testUpdateEpisodesIgnoresMoviesAndEmptyLists
{
    NSURL *url = [self freshFileURL];
    MacLCWatchLibrary *library = [self libraryWithClockAt:url];
    [library updateEpisodes:[self episodeList] forItem:[self movie:@"tt10"]];
    [library recordPosition:600 duration:7200 forItem:[self movie:@"tt10"] video:nil streamMRL:nil streamLabel:nil];
    [library updateEpisodes:@[] forItem:[self show]];
    [library recordPosition:600 duration:2700 forItem:[self show] video:[self episodeNumber:1] streamMRL:nil streamLabel:nil];
    [library flush];
    NSArray *titles = [self readJSON:url][@"titles"];
    for (NSDictionary *title in titles) {
        XCTAssertNil(title[@"episodes"]);
    }
}

#pragma mark Notifications

- (void)testNotificationsAreThrottledAndNameTheChangedTitles
{
    MacLCWatchLibrary *library = [self library];
    NSMutableArray<NSNotification *> *received = [NSMutableArray array];
    id observer = [NSNotificationCenter.defaultCenter addObserverForName:MacLCWatchLibraryDidChangeNotification
                                                                  object:library
                                                                   queue:nil
                                                              usingBlock:^(NSNotification *note) { [received addObject:note]; }];
    [library recordPosition:100 duration:7200 forItem:[self movie:@"tt1"] video:nil streamMRL:nil streamLabel:nil];
    [library recordPosition:110 duration:7200 forItem:[self movie:@"tt1"] video:nil streamMRL:nil streamLabel:nil];
    XCTAssertEqual(received.count, (NSUInteger)0); // asynchronous, on the main queue
    [self spinFor:0.3];
    XCTAssertEqual(received.count, (NSUInteger)1);
    XCTAssertEqualObjects(received.firstObject.userInfo[MacLCWatchLibraryChangedTitlesKey], [NSSet setWithObject:@"tt1"]);

    [library recordPosition:100 duration:7200 forItem:[self movie:@"tt2"] video:nil streamMRL:nil streamLabel:nil];
    [library setFavorite:YES forItem:[self movie:@"tt3"]];
    [self spinFor:0.5];
    XCTAssertEqual(received.count, (NSUInteger)1); // within 2 s of the last one
    [self spinFor:2.0];
    XCTAssertEqual(received.count, (NSUInteger)2);
    NSSet *expected = [NSSet setWithObjects:@"tt2", @"tt3", nil];
    XCTAssertEqualObjects(received.lastObject.userInfo[MacLCWatchLibraryChangedTitlesKey], expected);

    [library clearHistory];
    [self spinFor:2.5];
    XCTAssertEqual(received.count, (NSUInteger)3);
    XCTAssertNil(received.lastObject.userInfo[MacLCWatchLibraryChangedTitlesKey]); // everything
    [NSNotificationCenter.defaultCenter removeObserver:observer];
}

#pragma mark Detail texts

- (void)testDetailTextWording
{
    MacLCWatchLibrary *library = [self libraryWithClockAt:[self freshFileURL]];
    MacLCAddonItem *show = [self show];
    [library updateEpisodes:[self episodeList] forItem:show];
    [library recordPosition:1320 duration:2700 forItem:show video:[self episodeNumber:3] streamMRL:nil streamLabel:nil];
    XCTAssertEqualObjects([library entryForTitle:@"tt1"].resumeTarget.detailText, @"S1, E3 · 23 min left");
    [library recordPosition:2600 duration:2700 forItem:show video:[self episodeNumber:3] streamMRL:nil streamLabel:nil];
    XCTAssertEqualObjects([library entryForTitle:@"tt1"].resumeTarget.detailText, @"Next: S1, E4 · Fourth");
    [library recordPosition:300 duration:0 forItem:show video:[self episodeNumber:4] streamMRL:nil streamLabel:nil];
    XCTAssertEqualObjects([library entryForTitle:@"tt1"].resumeTarget.detailText, @"S1, E4 · Resume");
}

@end
