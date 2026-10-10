/*****************************************************************************
 * MacLCWatchDiscoveryTest.m: tests for MacLCWatchDiscovery model
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
#import "addons/watch/MacLCWatchDiscovery.h"

__attribute__((weak)) NSData *MacLCWatchCollectionsPoolData(void)
{
    return [@"{\"version\":1,\"collections\":[]}" dataUsingEncoding:NSUTF8StringEncoding];
}

@interface MacLCWatchCollectionEntry (TestInit)
- (instancetype)initWithTitle:(NSString *)title year:(NSInteger)year type:(NSString *)type;
@end

@interface MacLCWatchCollection (TestInit)
- (instancetype)initWithIdentifier:(NSString *)identifier
                             title:(NSString *)title
                          subtitle:(NSString *)subtitle
                              kind:(NSString *)kind
                        symbolName:(NSString *)symbolName
                          tintName:(NSString *)tintName
                         sourceURL:(nullable NSURL *)sourceURL
                           entries:(NSArray<MacLCWatchCollectionEntry *> *)entries
                         mediaType:(nullable NSString *)mediaType;
@end

@interface MacLCWatchDiscovery (TestInit)
- (instancetype)initWithPool:(NSArray<MacLCWatchCollection *> *)pool;
@end

@interface MacLCWatchDiscoveryTest : XCTestCase
@end

@implementation MacLCWatchDiscoveryTest

- (void)testCollectionsFromData
{
    // Valid pool with 3 collections: movie, series, mixed
    NSString *json = @"{"
        "\"version\": 1,"
        "\"collections\": ["
            "{"
                "\"id\": \"c1\","
                "\"title\": \"All Movies\","
                "\"subtitle\": \"Collection 1\","
                "\"kind\": \"theme\","
                "\"symbol\": \"film.fill\","
                "\"tint\": \"red\","
                "\"source\": \"https://example.com/c1\","
                "\"entries\": ["
                    "{\"title\": \"Movie 1\", \"year\": 2020, \"type\": \"movie\"},"
                    "{\"title\": \"Movie 2\", \"year\": 2021, \"type\": \"movie\"}"
                "]"
            "},"
            "{"
                "\"id\": \"c2\","
                "\"title\": \"All Series\","
                "\"entries\": ["
                    "{\"title\": \"Show 1\", \"year\": 2022, \"type\": \"series\"},"
                    "{\"title\": \"Show 2\", \"year\": 2023, \"type\": \"series\"}"
                "]"
            "},"
            "{"
                "\"id\": \"c3\","
                "\"title\": \"Mixed\","
                "\"entries\": ["
                    "{\"title\": \"Movie 3\", \"year\": 2024, \"type\": \"movie\"},"
                    "{\"title\": \"Show 3\", \"year\": 2025, \"type\": \"series\"}"
                "]"
            "}"
        "]"
    "}";

    NSData *data = [json dataUsingEncoding:NSUTF8StringEncoding];
    NSArray<MacLCWatchCollection *> *collections = [MacLCWatchDiscovery collectionsFromData:data];
    XCTAssertNotNil(collections);
    XCTAssertEqual(collections.count, 3);

    MacLCWatchCollection *col1 = collections[0];
    XCTAssertEqualObjects(col1.identifier, @"c1");
    XCTAssertEqualObjects(col1.title, @"All Movies");
    XCTAssertEqualObjects(col1.subtitle, @"Collection 1");
    XCTAssertEqualObjects(col1.kind, @"theme");
    XCTAssertEqualObjects(col1.symbolName, @"film.fill");
    XCTAssertEqualObjects(col1.tintName, @"red");
    XCTAssertEqualObjects(col1.sourceURL.absoluteString, @"https://example.com/c1");
    XCTAssertEqual(col1.entries.count, 2);
    XCTAssertEqualObjects(col1.mediaType, @"movie");

    MacLCWatchCollection *col2 = collections[1];
    XCTAssertEqualObjects(col2.identifier, @"c2");
    XCTAssertEqualObjects(col2.title, @"All Series");
    XCTAssertEqual(col2.entries.count, 2);
    XCTAssertEqualObjects(col2.mediaType, @"series");

    MacLCWatchCollection *col3 = collections[2];
    XCTAssertEqualObjects(col3.identifier, @"c3");
    XCTAssertEqualObjects(col3.title, @"Mixed");
    XCTAssertEqual(col3.entries.count, 2);
    XCTAssertNil(col3.mediaType);

    // Invalid entries skipped
    NSString *invalidEntriesJSON = @"{"
        "\"version\": 1,"
        "\"collections\": ["
            "{"
                "\"id\": \"c4\","
                "\"title\": \"Collection with invalid entries\","
                "\"entries\": ["
                    "{\"title\": \"Valid Movie\", \"year\": 2020, \"type\": \"movie\"},"
                    "{\"year\": 2020, \"type\": \"movie\"},"
                    "{\"title\": \"Zero Year\", \"year\": 0, \"type\": \"movie\"},"
                    "{\"title\": \"Neg Year\", \"year\": -5, \"type\": \"movie\"},"
                    "{\"title\": \"Game\", \"year\": 2020, \"type\": \"game\"},"
                    "\"not a dictionary\","
                    "{\"title\": \"Valid Series\", \"year\": 2022, \"type\": \"series\"}"
                "]"
            "}"
        "]"
    "}";

    NSArray<MacLCWatchCollection *> *colWithSkips = [MacLCWatchDiscovery collectionsFromData:[invalidEntriesJSON dataUsingEncoding:NSUTF8StringEncoding]];
    XCTAssertNotNil(colWithSkips);
    XCTAssertEqual(colWithSkips.count, 1);
    XCTAssertEqual(colWithSkips[0].entries.count, 2);
    XCTAssertEqualObjects(colWithSkips[0].entries[0].title, @"Valid Movie");
    XCTAssertEqualObjects(colWithSkips[0].entries[1].title, @"Valid Series");
    XCTAssertNil(colWithSkips[0].mediaType);

    // Non-JSON data returns nil
    XCTAssertNil([MacLCWatchDiscovery collectionsFromData:[@"not json" dataUsingEncoding:NSUTF8StringEncoding]]);
    XCTAssertNil([MacLCWatchDiscovery collectionsFromData:[@"[]" dataUsingEncoding:NSUTF8StringEncoding]]);
    XCTAssertNil([MacLCWatchDiscovery collectionsFromData:[@"{}" dataUsingEncoding:NSUTF8StringEncoding]]);
    XCTAssertNil([MacLCWatchDiscovery collectionsFromData:[NSData data]]);
}

- (void)testEditForDateDeterministic
{
    NSMutableArray<MacLCWatchCollection *> *pool = [NSMutableArray array];
    for (NSUInteger i = 0; i < 12; i++) {
        NSString *cid = [NSString stringWithFormat:@"col_%lu", (unsigned long)i];
        MacLCWatchCollection *col = [[MacLCWatchCollection alloc] initWithIdentifier:cid
                                                                              title:cid
                                                                           subtitle:@""
                                                                               kind:@""
                                                                         symbolName:@"film.fill"
                                                                           tintName:@"blue"
                                                                          sourceURL:nil
                                                                            entries:@[]
                                                                          mediaType:nil];
        [pool addObject:col];
    }

    MacLCWatchDiscovery *discovery = [[MacLCWatchDiscovery alloc] initWithPool:pool];

    NSCalendar *calendar = [NSCalendar currentCalendar];
    NSDateComponents *comp = [[NSDateComponents alloc] init];
    comp.year = 2026;
    comp.month = 1;
    comp.day = 5;
    comp.hour = 10;
    NSDate *d1 = [calendar dateFromComponents:comp];

    comp.day = 12;
    comp.hour = 22;
    NSDate *d2 = [calendar dateFromComponents:comp];

    NSArray<MacLCWatchCollection *> *edit1 = [discovery editForDate:d1 mediaType:nil count:3];
    NSArray<MacLCWatchCollection *> *edit2 = [discovery editForDate:d2 mediaType:nil count:3];

    XCTAssertEqual(edit1.count, 3);
    XCTAssertEqual(edit2.count, 3);
    XCTAssertEqualObjects(edit1, edit2);
}

- (void)testEditForDateConsecutivePeriodsNonOverlappingWith12Pool
{
    NSMutableArray<MacLCWatchCollection *> *pool = [NSMutableArray array];
    for (NSUInteger i = 0; i < 12; i++) {
        NSString *cid = [NSString stringWithFormat:@"col_%lu", (unsigned long)i];
        MacLCWatchCollection *col = [[MacLCWatchCollection alloc] initWithIdentifier:cid
                                                                              title:cid
                                                                           subtitle:@""
                                                                               kind:@""
                                                                         symbolName:@"film.fill"
                                                                           tintName:@"blue"
                                                                          sourceURL:nil
                                                                            entries:@[]
                                                                          mediaType:nil];
        [pool addObject:col];
    }

    MacLCWatchDiscovery *discovery = [[MacLCWatchDiscovery alloc] initWithPool:pool];

    NSCalendar *calendar = [NSCalendar currentCalendar];
    NSDateComponents *comp = [[NSDateComponents alloc] init];
    comp.year = 2026;
    comp.month = 1;
    comp.day = 5; // Period 0 start
    comp.hour = 0;
    comp.minute = 0;
    comp.second = 0;
    NSDate *p0 = [calendar dateFromComponents:comp];

    comp.day = 19; // Period 1 start (+14 days)
    NSDate *p1 = [calendar dateFromComponents:comp];

    comp.month = 2;
    comp.day = 2; // Period 2 start (+28 days)
    NSDate *p2 = [calendar dateFromComponents:comp];

    NSArray<MacLCWatchCollection *> *edit0 = [discovery editForDate:p0 mediaType:nil count:3];
    NSArray<MacLCWatchCollection *> *edit1 = [discovery editForDate:p1 mediaType:nil count:3];
    NSArray<MacLCWatchCollection *> *edit2 = [discovery editForDate:p2 mediaType:nil count:3];

    XCTAssertEqual(edit0.count, 3);
    XCTAssertEqual(edit1.count, 3);
    XCTAssertEqual(edit2.count, 3);

    NSMutableSet<NSString *> *set0 = [NSMutableSet set];
    for (MacLCWatchCollection *c in edit0) [set0 addObject:c.identifier];

    NSMutableSet<NSString *> *set1 = [NSMutableSet set];
    for (MacLCWatchCollection *c in edit1) [set1 addObject:c.identifier];

    NSMutableSet<NSString *> *set2 = [NSMutableSet set];
    for (MacLCWatchCollection *c in edit2) [set2 addObject:c.identifier];

    // Consecutive periods share NO collection
    XCTAssertFalse([set0 intersectsSet:set1]);
    XCTAssertFalse([set1 intersectsSet:set2]);
}

- (void)testMediaTypeFiltering
{
    NSMutableArray<MacLCWatchCollection *> *pool = [NSMutableArray array];
    for (NSUInteger i = 0; i < 4; i++) {
        NSString *cid = [NSString stringWithFormat:@"movie_%lu", (unsigned long)i];
        MacLCWatchCollection *col = [[MacLCWatchCollection alloc] initWithIdentifier:cid
                                                                              title:cid
                                                                           subtitle:@""
                                                                               kind:@""
                                                                         symbolName:@"film.fill"
                                                                           tintName:@"blue"
                                                                          sourceURL:nil
                                                                            entries:@[]
                                                                          mediaType:@"movie"];
        [pool addObject:col];
    }
    for (NSUInteger i = 0; i < 4; i++) {
        NSString *cid = [NSString stringWithFormat:@"series_%lu", (unsigned long)i];
        MacLCWatchCollection *col = [[MacLCWatchCollection alloc] initWithIdentifier:cid
                                                                              title:cid
                                                                           subtitle:@""
                                                                               kind:@""
                                                                         symbolName:@"film.fill"
                                                                           tintName:@"blue"
                                                                          sourceURL:nil
                                                                            entries:@[]
                                                                          mediaType:@"series"];
        [pool addObject:col];
    }

    MacLCWatchDiscovery *discovery = [[MacLCWatchDiscovery alloc] initWithPool:pool];
    NSDate *now = [NSDate date];

    NSArray<MacLCWatchCollection *> *movies = [discovery editForDate:now mediaType:@"movie" count:2];
    XCTAssertEqual(movies.count, 2);
    for (MacLCWatchCollection *m in movies) {
        XCTAssertEqualObjects(m.mediaType, @"movie");
    }

    NSArray<MacLCWatchCollection *> *series = [discovery editForDate:now mediaType:@"series" count:2];
    XCTAssertEqual(series.count, 2);
    for (MacLCWatchCollection *s in series) {
        XCTAssertEqualObjects(s.mediaType, @"series");
    }
}

- (void)testNextEditDateAfter
{
    MacLCWatchDiscovery *discovery = [[MacLCWatchDiscovery alloc] initWithPool:@[]];
    NSCalendar *calendar = [NSCalendar currentCalendar];

    NSDateComponents *comp = [[NSDateComponents alloc] init];
    comp.year = 2026;
    comp.month = 1;
    comp.day = 5; // Monday
    comp.hour = 0;
    comp.minute = 0;
    comp.second = 0;
    NSDate *p0 = [calendar dateFromComponents:comp];

    NSDate *next0 = [discovery nextEditDateAfter:p0];
    XCTAssertNotNil(next0);

    // Weekday is Monday (2 in Gregorian calendar)
    NSInteger weekday = [calendar component:NSCalendarUnitWeekday fromDate:next0];
    XCTAssertEqual(weekday, 2);

    // 14 days after period start (2026-01-19 00:00:00)
    NSDateComponents *diff0 = [calendar components:NSCalendarUnitDay fromDate:p0 toDate:next0 options:0];
    XCTAssertEqual(diff0.day, 14);

    // Mid-period date gives same next edit date
    comp.day = 12;
    NSDate *mid0 = [calendar dateFromComponents:comp];
    NSDate *nextMid = [discovery nextEditDateAfter:mid0];
    XCTAssertEqualObjects(nextMid, next0);

    // Period 1 start gives next period (2026-02-02)
    comp.day = 19;
    NSDate *p1 = [calendar dateFromComponents:comp];
    NSDate *next1 = [discovery nextEditDateAfter:p1];
    NSInteger weekday1 = [calendar component:NSCalendarUnitWeekday fromDate:next1];
    XCTAssertEqual(weekday1, 2);
    NSDateComponents *diff1 = [calendar components:NSCalendarUnitDay fromDate:p1 toDate:next1 options:0];
    XCTAssertEqual(diff1.day, 14);
}

- (void)testServicesAddonAddressForCodes
{
    NSArray<NSString *> *codes = @[@"nfx", @"atp", @"dnp"];
    NSString *country = @"FR";
    NSString *address = [MacLCWatchDiscovery servicesAddonAddressForCodes:codes country:country];
    NSString *expected = @"https://7a82163c306e-stremio-netflix-catalog-addon.baby-beamup.club/bmZ4LGF0cCxkbnA6OkZS/manifest.json";
    XCTAssertEqualObjects(address, expected);
}

- (void)testServiceForCode
{
    MacLCWatchService *nfx = [MacLCWatchDiscovery serviceForCode:@"nfx"];
    XCTAssertNotNil(nfx);
    XCTAssertEqualObjects(nfx.code, @"nfx");
    XCTAssertEqualObjects(nfx.name, @"Netflix");
    NSArray<NSString *> *expectedNfxTypes = @[@"movie", @"series"];
    XCTAssertEqualObjects(nfx.types, expectedNfxTypes);

    MacLCWatchService *mbi = [MacLCWatchDiscovery serviceForCode:@"mbi"];
    XCTAssertNotNil(mbi);
    XCTAssertEqualObjects(mbi.code, @"mbi");
    XCTAssertEqualObjects(mbi.name, @"MUBI");
    NSArray<NSString *> *expectedMbiTypes = @[@"movie"];
    XCTAssertEqualObjects(mbi.types, expectedMbiTypes);

    MacLCWatchService *crc = [MacLCWatchDiscovery serviceForCode:@"crc"];
    XCTAssertNotNil(crc);
    XCTAssertEqualObjects(crc.code, @"crc");
    XCTAssertEqualObjects(crc.name, @"Criterion Channel");
    NSArray<NSString *> *expectedCrcTypes = @[@"movie"];
    XCTAssertEqualObjects(crc.types, expectedCrcTypes);

    XCTAssertNil([MacLCWatchDiscovery serviceForCode:@"unknown_service"]);
    XCTAssertEqual(MacLCWatchDiscovery.knownServices.count, 17);
}

- (void)testMatchEntryInItems
{
    NSString *addonJSON = @"{\"id\":\"test.addon\",\"name\":\"Test Addon\",\"version\":\"1.0.0\",\"resources\":[\"catalog\"],\"types\":[\"movie\",\"series\"]}";
    MacLCAddon *addon = [MacLCAddon addonWithTransportURL:@"https://example.com/manifest.json"
                                             manifestData:[addonJSON dataUsingEncoding:NSUTF8StringEncoding]
                                                    error:nil];
    XCTAssertNotNil(addon);

    NSString *catalogJSON = @"{\"metas\":["
        "{\"id\":\"tt1\",\"name\":\"Inception\",\"releaseInfo\":\"2010\",\"type\":\"movie\"},"
        "{\"id\":\"tt2\",\"name\":\"Amelie\",\"releaseInfo\":\"2001\",\"type\":\"movie\"},"
        "{\"id\":\"tt3\",\"name\":\"Matrix\",\"releaseInfo\":\"1999\",\"type\":\"movie\"},"
        "{\"id\":\"tt4\",\"name\":\"The Dark Knight\",\"releaseInfo\":\"2008\",\"type\":\"movie\"},"
        "{\"id\":\"tt5\",\"name\":\"Interstellar\",\"releaseInfo\":\"2015\",\"type\":\"movie\"},"
        "{\"id\":\"tt6\",\"name\":\"Fargo\",\"releaseInfo\":\"1996\",\"type\":\"series\"}"
    "]}";

    NSArray<MacLCAddonItem *> *items = [MacLCAddonStore itemsFromCatalogData:[catalogJSON dataUsingEncoding:NSUTF8StringEncoding]
                                                                      addon:addon
                                                                      error:nil];
    XCTAssertNotNil(items);
    XCTAssertEqual(items.count, 6);

    // 1. Exact title + year
    MacLCWatchCollectionEntry *e1 = [[MacLCWatchCollectionEntry alloc] initWithTitle:@"Inception" year:2010 type:@"movie"];
    MacLCAddonItem *m1 = [MacLCWatchDiscovery matchEntry:e1 inItems:items];
    XCTAssertNotNil(m1);
    XCTAssertEqualObjects(m1.identifier, @"tt1");

    // 2. Diacritics: 'Amelie' vs 'Amélie'
    MacLCWatchCollectionEntry *e2 = [[MacLCWatchCollectionEntry alloc] initWithTitle:@"Amélie" year:2001 type:@"movie"];
    MacLCAddonItem *m2 = [MacLCWatchDiscovery matchEntry:e2 inItems:items];
    XCTAssertNotNil(m2);
    XCTAssertEqualObjects(m2.identifier, @"tt2");

    // 3. 'The' prefix
    MacLCWatchCollectionEntry *e3 = [[MacLCWatchCollectionEntry alloc] initWithTitle:@"The Matrix" year:1999 type:@"movie"];
    MacLCAddonItem *m3 = [MacLCWatchDiscovery matchEntry:e3 inItems:items];
    XCTAssertNotNil(m3);
    XCTAssertEqualObjects(m3.identifier, @"tt3");

    MacLCWatchCollectionEntry *e4 = [[MacLCWatchCollectionEntry alloc] initWithTitle:@"Dark Knight" year:2008 type:@"movie"];
    MacLCAddonItem *m4 = [MacLCWatchDiscovery matchEntry:e4 inItems:items];
    XCTAssertNotNil(m4);
    XCTAssertEqualObjects(m4.identifier, @"tt4");

    // 4. Year ±1 fallback
    MacLCWatchCollectionEntry *e5 = [[MacLCWatchCollectionEntry alloc] initWithTitle:@"Interstellar" year:2014 type:@"movie"];
    MacLCAddonItem *m5 = [MacLCWatchDiscovery matchEntry:e5 inItems:items];
    XCTAssertNotNil(m5);
    XCTAssertEqualObjects(m5.identifier, @"tt5");

    // 5. Wrong type rejected
    MacLCWatchCollectionEntry *e6 = [[MacLCWatchCollectionEntry alloc] initWithTitle:@"Fargo" year:1996 type:@"movie"];
    MacLCAddonItem *m6 = [MacLCWatchDiscovery matchEntry:e6 inItems:items];
    XCTAssertNil(m6);
}

- (void)testItemsMatchingGenre
{
    NSString *addonJSON = @"{\"id\":\"test.addon\",\"name\":\"Test Addon\",\"version\":\"1.0.0\",\"resources\":[\"catalog\"],\"types\":[\"movie\"]}";
    MacLCAddon *addon = [MacLCAddon addonWithTransportURL:@"https://example.com/manifest.json"
                                             manifestData:[addonJSON dataUsingEncoding:NSUTF8StringEncoding]
                                                    error:nil];

    NSString *catalogJSON = @"{\"metas\":["
        "{\"id\":\"1\",\"name\":\"Movie A\",\"type\":\"movie\",\"genres\":[\"Action\",\"Sci-Fi\"]},"
        "{\"id\":\"2\",\"name\":\"Movie B\",\"type\":\"movie\",\"genres\":[\"Comedy\"]},"
        "{\"id\":\"3\",\"name\":\"Movie C\",\"type\":\"movie\",\"genres\":[\"action\",\"Drama\"]}"
    "]}";

    NSArray<MacLCAddonItem *> *items = [MacLCAddonStore itemsFromCatalogData:[catalogJSON dataUsingEncoding:NSUTF8StringEncoding]
                                                                      addon:addon
                                                                      error:nil];
    XCTAssertNotNil(items);
    XCTAssertEqual(items.count, 3);

    NSArray<MacLCAddonItem *> *actionItems = [MacLCWatchDiscovery items:items matchingGenre:@"Action"];
    XCTAssertEqual(actionItems.count, 2);
    XCTAssertEqualObjects(actionItems[0].identifier, @"1");
    XCTAssertEqualObjects(actionItems[1].identifier, @"3");

    NSArray<MacLCAddonItem *> *sciFiItems = [MacLCWatchDiscovery items:items matchingGenre:@"sci-fi"];
    XCTAssertEqual(sciFiItems.count, 1);
    XCTAssertEqualObjects(sciFiItems[0].identifier, @"1");

    NSArray<MacLCAddonItem *> *romanceItems = [MacLCWatchDiscovery items:items matchingGenre:@"Romance"];
    XCTAssertEqual(romanceItems.count, 0);
}

- (void)testGenreSymbolsAndTints
{
    XCTAssertEqualObjects([MacLCWatchDiscovery symbolNameForGenre:@"Action"], @"bolt.fill");
    XCTAssertEqualObjects([MacLCWatchDiscovery symbolNameForGenre:@"Crime"], @"magnifyingglass");
    XCTAssertEqualObjects([MacLCWatchDiscovery symbolNameForGenre:@"Documentary"], @"video.fill");
    XCTAssertEqualObjects([MacLCWatchDiscovery symbolNameForGenre:@"Nonexistent"], @"film.fill");

    XCTAssertEqualObjects([MacLCWatchDiscovery tintNameForGenre:@"Action"], @"orange");
    XCTAssertEqualObjects([MacLCWatchDiscovery tintNameForGenre:@"Comedy"], @"yellow");
    XCTAssertEqualObjects([MacLCWatchDiscovery tintNameForGenre:@"Horror"], @"indigo");
    XCTAssertEqualObjects([MacLCWatchDiscovery tintNameForGenre:@"Nonexistent"], @"blue");
}

@end
