/*****************************************************************************
 * MacLCYouTubeModelTest.m: tests for the YouTube model, parsers and wording,
 * on real yt-dlp outputs (tests/fixtures/youtube, recorded 2026-10-09)
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
#define XCTAssertNotNil(a, ...) do { (void)(a); } while (0)
#define XCTAssertNil(a, ...) do { (void)(a); } while (0)
#define XCTAssertTrue(a, ...) do { (void)(a); } while (0)
#define XCTAssertFalse(a, ...) do { (void)(a); } while (0)
#endif

#import "youtube/MacLCYouTubeModel.h"

/* In MacLCYouTubeModel.m, shared with the service. */
extern MacLCYouTubePage *MacLCYouTubeMergedPage(NSString *title, NSArray<MacLCYouTubePage *> *pages, NSUInteger limit);
extern NSInteger MacLCYouTubeClassifyExtractorError(NSString *stderrText, NSString * _Nullable * _Nullable message);

@interface MacLCYouTubeModelTest : XCTestCase
@end

@implementation MacLCYouTubeModelTest

#pragma mark Fixtures

/* tests/fixtures/youtube next to this file; MACLC_YOUTUBE_FIXTURES overrides. */
static NSString *FixturePath(NSString *name)
{
    NSString * const override = NSProcessInfo.processInfo.environment[@"MACLC_YOUTUBE_FIXTURES"];
    NSString *dir = override;
    if (dir.length == 0) {
        NSString * const here = [NSString stringWithUTF8String:__FILE__];
        dir = [[here stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"fixtures/youtube"];
    }
    return [dir stringByAppendingPathComponent:name];
}

static NSData *Fixture(NSString *name)
{
    return [NSData dataWithContentsOfFile:FixturePath([name stringByAppendingPathExtension:@"json"])];
}

static NSString *Stderr(NSString *name)
{
    return [NSString stringWithContentsOfFile:FixturePath([@"stderr" stringByAppendingPathComponent:[name stringByAppendingPathExtension:@"txt"]])
                                     encoding:NSUTF8StringEncoding error:NULL];
}

static MacLCYouTubePage *PageNamed(NSString *name, NSUInteger limit)
{
    NSError *error = nil;
    MacLCYouTubePage * const page = [MacLCYouTubeParser pageFromJSONData:Fixture(name) ?: [NSData data] limit:limit error:&error];
    return page;
}

static MacLCYouTubePage *PageFromObject(id object, NSUInteger limit)
{
    NSData * const data = [NSJSONSerialization dataWithJSONObject:object options:0 error:NULL];
    return [MacLCYouTubeParser pageFromJSONData:data limit:limit error:NULL];
}

static NSDictionary *FlatVideo(NSString *identifier, NSString *title)
{
    return @{@"_type": @"url", @"ie_key": @"Youtube", @"id": identifier, @"title": title,
             @"url": [@"https://www.youtube.com/watch?v=" stringByAppendingString:identifier]};
}

#pragma mark Search

- (void)testSearchAllHasVideosChannelsAndPlaylistsInOrder
{
    MacLCYouTubePage * const page = PageNamed(@"search-all-blender", 24);
    XCTAssertNotNil(page);
    XCTAssertEqual(page.results.count, (NSUInteger)24);
    XCTAssertEqual(page.results[0].kind, MacLCYouTubeResultKindVideo);
    XCTAssertEqualObjects(page.results[0].video.identifier, @"z-Xl9tGqH14");
    XCTAssertEqualObjects(page.results[0].video.title, @"Beginner Blender Tutorial (2026)");
    XCTAssertEqualObjects(page.results[0].video.channelName, @"Blender Guru");
    XCTAssertEqualObjects(page.results[0].video.channelIdentifier, @"UCOKHwx1VCdgnxwbjyb9Iu1g");
    XCTAssertTrue(page.results[0].video.isChannelVerified);
    XCTAssertEqual(page.results[2].kind, MacLCYouTubeResultKindChannel);
    XCTAssertEqualObjects(page.results[2].channel.name, @"Blender");
    XCTAssertEqual(page.results[4].kind, MacLCYouTubeResultKindPlaylist);
    XCTAssertTrue([page.results[4].playlist.identifier hasPrefix:@"PL"]);
    /* videos is only the videos, same order */
    XCTAssertTrue(page.videos.count < page.results.count);
    XCTAssertEqualObjects(page.videos[0], page.results[0].video);
    XCTAssertEqualObjects(page.videos[1].identifier, page.results[1].video.identifier);
    XCTAssertNil(page.channel);
    XCTAssertNil(page.playlist);
}

- (void)testVideoCardFieldsFromFlatEntry
{
    MacLCYouTubeVideo * const v = PageNamed(@"search-videos-blender", 24).videos.firstObject;
    XCTAssertEqualObjects(v.identifier, @"z-Xl9tGqH14");
    XCTAssertEqual(v.duration, 15550.0);
    XCTAssertEqual(v.viewCount, (int64_t)2484900);
    XCTAssertNil(v.publishedDate);      /* flat lists carry no date */
    XCTAssertFalse(v.isLive);
    XCTAssertFalse(v.isUpcoming);
    XCTAssertFalse(v.isShort);
    XCTAssertEqualObjects(v.watchURL.absoluteString, @"https://www.youtube.com/watch?v=z-Xl9tGqH14");
    XCTAssertEqualObjects(v.channelURL.absoluteString, @"https://www.youtube.com/channel/UCOKHwx1VCdgnxwbjyb9Iu1g");
    XCTAssertEqual(v.chapters.count, (NSUInteger)0);
}

- (void)testThumbnailIsTheSmallestAtLeast640WideElseTheWidest
{
    /* 360 and 720 wide: the 720 one */
    MacLCYouTubeVideo * const v = PageNamed(@"search-videos-blender", 24).videos.firstObject;
    XCTAssertTrue([v.thumbnailURL.absoluteString containsString:@"hq720.jpg"]);
    XCTAssertTrue([v.thumbnailURL.absoluteString containsString:@"AOn4CLDZ7N3LvV_7KmhyBNLnoz7cKrSNPw"]);

    NSDictionary * const doc = @{@"_type": @"playlist", @"entries": @[@{
        @"id": @"aaaaaaaaaaa", @"title": @"t", @"ie_key": @"Youtube",
        @"thumbnails": @[@{@"url": @"https://x/small.jpg", @"width": @168}, @{@"url": @"https://x/w1280.jpg", @"width": @1280},
                         @{@"url": @"https://x/w640.jpg", @"width": @640}, @{@"url": @"https://x/nowidth.jpg"}]}]};
    XCTAssertEqualObjects(PageFromObject(doc, 0).videos[0].thumbnailURL.absoluteString, @"https://x/w640.jpg");

    /* only small ones: the widest (playlist entries are 336 wide) */
    NSDictionary * const small = @{@"entries": @[@{@"id": @"aaaaaaaaaaa", @"title": @"t", @"ie_key": @"Youtube",
        @"thumbnails": @[@{@"url": @"https://x/a.jpg", @"width": @168}, @{@"url": @"https://x/b.jpg", @"width": @336}]}]};
    XCTAssertEqualObjects(PageFromObject(small, 0).videos[0].thumbnailURL.absoluteString, @"https://x/b.jpg");

    /* full -J details: the 16:9 JPEG (maxresdefault), never the 4:3 sddefault, nor a storyboard */
    MacLCYouTubeVideo * const details = [MacLCYouTubeParser videoFromJSONData:Fixture(@"video-Q1fMMYyt0I4") error:NULL];
    XCTAssertEqualObjects(details.thumbnailURL.absoluteString, @"https://i.ytimg.com/vi/Q1fMMYyt0I4/maxresdefault.jpg");
    /* same width in .jpg and .webp: the .jpg */
    NSDictionary * const twin = @{@"entries": @[@{@"id": @"aaaaaaaaaaa", @"title": @"t", @"ie_key": @"Youtube",
        @"thumbnails": @[@{@"url": @"https://x/a.webp", @"width": @1280, @"height": @720}, @{@"url": @"https://x/a.jpg", @"width": @1280, @"height": @720},
                         @{@"url": @"https://x/sd.jpg", @"width": @640, @"height": @480}]}]};
    XCTAssertEqualObjects(PageFromObject(twin, 0).videos[0].thumbnailURL.absoluteString, @"https://x/a.jpg");

    /* none: i.ytimg.com hqdefault */
    NSDictionary * const none = @{@"entries": @[@{@"id": @"aaaaaaaaaaa", @"title": @"t", @"ie_key": @"Youtube"}]};
    XCTAssertEqualObjects(PageFromObject(none, 0).videos[0].thumbnailURL.absoluteString,
                          @"https://i.ytimg.com/vi/aaaaaaaaaaa/hqdefault.jpg");
}

- (void)testChannelResultsCarryHandleAvatarAndSubscribers
{
    MacLCYouTubePage * const page = PageNamed(@"search-channels-blender", 12);
    XCTAssertEqual(page.results.count, (NSUInteger)12);
    MacLCYouTubeChannel * const c = page.results[0].channel;
    XCTAssertEqual(page.results[0].kind, MacLCYouTubeResultKindChannel);
    XCTAssertEqualObjects(c.name, @"Blender");
    XCTAssertEqualObjects(c.handle, @"@BlenderOfficial");
    XCTAssertEqualObjects(c.identifier, @"UCSMOQeBJ2RAnuFungnQOxLg");
    XCTAssertEqualObjects(c.URL.absoluteString, @"https://www.youtube.com/channel/UCSMOQeBJ2RAnuFungnQOxLg");
    XCTAssertEqual(c.subscriberCount, (int64_t)1250000);
    XCTAssertTrue(c.isVerified);
    /* "//yt3.googleusercontent.com/..." gets its scheme; the 176 px one wins */
    XCTAssertTrue([c.avatarURL.absoluteString hasPrefix:@"https://yt3.googleusercontent.com/"]);
    XCTAssertTrue([c.avatarURL.absoluteString containsString:@"=s176-"]);
    XCTAssertNil(c.bannerURL);
}

- (void)testPlaylistResults
{
    MacLCYouTubePage * const page = PageNamed(@"search-playlists-blender", 12);
    XCTAssertEqual(page.results.count, (NSUInteger)12);
    MacLCYouTubePlaylist * const p = page.results[0].playlist;
    XCTAssertEqual(page.results[0].kind, MacLCYouTubeResultKindPlaylist);
    XCTAssertEqualObjects(p.identifier, @"PLjEaoINr3zgEPv5y--4MKpciLaoQYZB1Z");
    XCTAssertEqualObjects(p.title, @"Blender 4.0 Beginner Donut Tutorial (Old)");
    XCTAssertEqualObjects(p.URL.absoluteString, @"https://www.youtube.com/playlist?list=PLjEaoINr3zgEPv5y--4MKpciLaoQYZB1Z");
    XCTAssertEqual(p.videoCount, (NSInteger)-1);
    XCTAssertNotNil(p.thumbnailURL);
}

#pragma mark Channel tabs and playlists

- (void)testChannelTabDescribesTheChannelAndFillsMissingVideoChannel
{
    MacLCYouTubePage * const page = PageNamed(@"channel-BlenderStudio-videos", 24);
    XCTAssertEqual(page.results.count, (NSUInteger)24);
    XCTAssertNotNil(page.channel);
    XCTAssertNil(page.playlist);
    XCTAssertEqualObjects(page.channel.name, @"Blender Studio");
    XCTAssertEqualObjects(page.channel.identifier, @"UCz75RVbH8q2jdBJ4SnwuZZQ");
    XCTAssertEqualObjects(page.channel.handle, @"@BlenderStudio");
    XCTAssertEqual(page.channel.subscriberCount, (int64_t)577000);
    XCTAssertTrue([page.channel.descriptionText hasPrefix:@"Welcome to the official Blender Studio channel"]);
    XCTAssertTrue([page.channel.avatarURL.absoluteString hasSuffix:@"=s0"]);   /* avatar_uncropped */
    /* the 2560x424 web banner, not banner_uncropped (16:9 TV artwork, =s0) */
    XCTAssertTrue([page.channel.bannerURL.absoluteString containsString:@"=w2560-fcrop64"]);
    XCTAssertFalse([page.channel.avatarURL isEqual:page.channel.bannerURL]);
    /* flat channel-tab entries have no channel and no views: the tab's owner is filled in */
    MacLCYouTubeVideo * const v = page.videos[0];
    XCTAssertEqualObjects(v.identifier, @"Q1fMMYyt0I4");
    XCTAssertEqualObjects(v.channelName, @"Blender Studio");
    XCTAssertEqualObjects(v.channelIdentifier, @"UCz75RVbH8q2jdBJ4SnwuZZQ");
    XCTAssertEqual(v.viewCount, (int64_t)-1);
    XCTAssertTrue(page.mayHaveMore);   /* asked 24, got 24 */
    XCTAssertFalse(PageNamed(@"channel-BlenderStudio-videos", 25).mayHaveMore);
    XCTAssertFalse(PageNamed(@"channel-BlenderStudio-videos", 0).mayHaveMore);
}

- (void)testChannelPlaylistsTab
{
    MacLCYouTubePage * const page = PageNamed(@"channel-BlenderStudio-playlists", 24);
    XCTAssertEqualObjects(page.channel.name, @"Blender Studio");
    XCTAssertEqual(page.results.count, (NSUInteger)15);
    XCTAssertEqual(page.results[0].kind, MacLCYouTubeResultKindPlaylist);
    XCTAssertEqual(page.videos.count, (NSUInteger)0);
}

- (void)testLiveTabEntries
{
    MacLCYouTubePage * const page = PageNamed(@"channel-BlenderStudio-live", 24);
    XCTAssertNotNil(page.channel);
    XCTAssertTrue(page.videos.count > 0);
}

- (void)testPlaylistPage
{
    MacLCYouTubePage * const page = PageNamed(@"playlist-PLav47HAVZMjnTFVZL-aImCQIC0uLZtNCz", 24);
    XCTAssertNil(page.channel);
    XCTAssertNotNil(page.playlist);
    XCTAssertEqualObjects(page.playlist.identifier, @"PLav47HAVZMjnTFVZL-aImCQIC0uLZtNCz");
    XCTAssertEqualObjects(page.playlist.title, @"Blender Open Movies");
    XCTAssertEqualObjects(page.playlist.channelName, @"Blender Studio");
    XCTAssertEqual(page.playlist.videoCount, (NSInteger)18);
    XCTAssertEqual(page.videos.count, (NSUInteger)18);
    /* asked 24, got 18 of 18 */
    XCTAssertFalse(page.mayHaveMore);
}

#pragma mark Single video

- (void)testVideoDetailsWithChapters
{
    NSError *error = nil;
    MacLCYouTubeVideo * const v = [MacLCYouTubeParser videoFromJSONData:Fixture(@"video-6qKZw8oPoiE") error:&error];
    XCTAssertNotNil(v);
    XCTAssertNil(error);
    XCTAssertEqualObjects(v.title, @"The Making of SINGULARITY - Blender Open Movie");
    XCTAssertEqualObjects(v.channelName, @"Blender Studio");
    XCTAssertEqual(v.duration, 1019.0);
    XCTAssertEqual(v.viewCount, (int64_t)55201);
    XCTAssertEqual(v.likeCount, (int64_t)3276);
    XCTAssertEqual(v.channelFollowerCount, (int64_t)-1);   /* null in this document */
    XCTAssertEqualObjects(v.category, @"Entertainment");
    XCTAssertEqual(v.chapters.count, (NSUInteger)12);
    XCTAssertEqualObjects(v.chapters[0].title, @"Project concept and vision");
    XCTAssertEqual(v.chapters[0].start, 0.0);
    XCTAssertEqual(v.chapters[0].end, 24.0);
    XCTAssertEqual(v.chapters[1].start, 24.0);
    XCTAssertTrue(v.tags.count > 0);
    XCTAssertTrue([v.descriptionText hasPrefix:@"Join Blender Studio team"]);
    /* timestamp 1779462561 */
    XCTAssertEqual(v.publishedDate.timeIntervalSince1970, 1779462561.0);
    XCTAssertFalse(v.isLive);
    /* the thumbnails with a width, not the storyboard 0.jpg ones */
    XCTAssertTrue([v.thumbnailURL.absoluteString containsString:@"maxresdefault"] || [v.thumbnailURL.absoluteString containsString:@"hq720"]
                  || [v.thumbnailURL.absoluteString containsString:@"sddefault"] || [v.thumbnailURL.absoluteString containsString:@"hqdefault"]);
}

- (void)testVideoDetailsWithoutChaptersAndUploadDateFallback
{
    MacLCYouTubeVideo * const v = [MacLCYouTubeParser videoFromJSONData:Fixture(@"video-Q1fMMYyt0I4") error:NULL];
    XCTAssertNotNil(v);
    XCTAssertEqual(v.chapters.count, (NSUInteger)0);
    XCTAssertEqual(v.channelFollowerCount, (int64_t)577000);
    XCTAssertTrue(v.isChannelVerified);

    NSDictionary * const doc = @{@"id": @"aaaaaaaaaaa", @"title": @"t", @"upload_date": @"20260522"};
    MacLCYouTubeVideo * const d = [MacLCYouTubeParser videoFromJSONData:[NSJSONSerialization dataWithJSONObject:doc options:0 error:NULL] error:NULL];
    NSCalendar * const cal = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
    cal.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
    NSDateComponents * const c = [cal components:NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay | NSCalendarUnitHour fromDate:d.publishedDate];
    XCTAssertEqual(c.year, (NSInteger)2026);
    XCTAssertEqual(c.month, (NSInteger)5);
    XCTAssertEqual(c.day, (NSInteger)22);
    XCTAssertEqual(c.hour, (NSInteger)12);
}

#pragma mark Kinds: live, upcoming, shorts

- (void)testLiveUpcomingAndShortsAreDetectedInFlatEntries
{
    MacLCYouTubePage * const live = PageNamed(@"home-live", 24);
    XCTAssertEqual(live.videos.count, (NSUInteger)24);
    for (MacLCYouTubeVideo *v in live.videos) {
        XCTAssertTrue(v.isLive);
        XCTAssertEqual(v.duration, 0.0);
        XCTAssertEqual(v.viewCount, (int64_t)-1);
    }

    NSMutableDictionary * const upcoming = [FlatVideo(@"bbbbbbbbbbb", @"Soon") mutableCopy];
    upcoming[@"live_status"] = @"is_upcoming";
    NSMutableDictionary * const short1 = [FlatVideo(@"ccccccccccc", @"A short") mutableCopy];
    short1[@"url"] = @"https://www.youtube.com/shorts/ccccccccccc";
    MacLCYouTubePage * const page = PageFromObject(@{@"entries": @[upcoming, short1, FlatVideo(@"ddddddddddd", @"Plain")]}, 0);
    XCTAssertTrue(page.videos[0].isUpcoming);
    XCTAssertFalse(page.videos[0].isLive);
    XCTAssertTrue(page.videos[1].isShort);
    XCTAssertEqualObjects(page.videos[1].watchURL.absoluteString, @"https://www.youtube.com/watch?v=ccccccccccc");
    XCTAssertFalse(page.videos[2].isShort);
}

#pragma mark Totality, dedupe, paging

- (void)testParsersNeverThrowOnGarbage
{
    NSArray * const bad = @[
        [NSData data], [@"not json" dataUsingEncoding:NSUTF8StringEncoding], [@"[]" dataUsingEncoding:NSUTF8StringEncoding],
        [@"null" dataUsingEncoding:NSUTF8StringEncoding], [@"{}" dataUsingEncoding:NSUTF8StringEncoding],
        [@"{\"entries\": \"nope\"}" dataUsingEncoding:NSUTF8StringEncoding]];
    for (NSData *data in bad) {
        NSError *error = nil;
        MacLCYouTubePage * const page = [MacLCYouTubeParser pageFromJSONData:data limit:10 error:&error];
        XCTAssertNil(page);
        XCTAssertNotNil(error);
        XCTAssertEqualObjects(error.domain, @"MacLCYouTubeErrorDomain");
        XCTAssertEqual(error.code, (NSInteger)5);
        XCTAssertNil([MacLCYouTubeParser videoFromJSONData:data error:NULL]);
    }
    /* every field wrong-typed: dropped, no exception */
    NSDictionary * const weird = @{@"_type": @"playlist", @"id": @42, @"title": @[], @"entries": @[
        @1, @"x", [NSNull null], @{}, @{@"id": @5, @"title": @6, @"duration": @"long", @"thumbnails": @"none"},
        @{@"id": @"aaaaaaaaaaa", @"title": @"ok", @"ie_key": @"Youtube", @"view_count": @"many", @"duration": [NSNull null],
          @"thumbnails": @[@1, @{@"url": @2, @"width": @"wide"}], @"chapters": @[@"a"], @"channel_is_verified": @"yes"},
        @{@"ie_key": @"YoutubeTab", @"id": @"PLabc"}, @{@"ie_key": @"YoutubeTab", @"url": @"https://www.youtube.com/channel/"}]};
    MacLCYouTubePage * const page = PageFromObject(weird, 3);
    XCTAssertNotNil(page);
    XCTAssertEqual(page.videos.count, (NSUInteger)1);
    XCTAssertEqual(page.videos[0].viewCount, (int64_t)-1);
    XCTAssertFalse(page.videos[0].isChannelVerified);
    XCTAssertNotNil(page.videos[0].thumbnailURL);
}

- (void)testSameVideoTwiceKeepsTheFirstAndUnnamedEntriesAreDropped
{
    NSDictionary * const first = FlatVideo(@"aaaaaaaaaaa", @"First");
    NSDictionary * const again = FlatVideo(@"aaaaaaaaaaa", @"Second");
    NSDictionary * const unnamed = @{@"ie_key": @"Youtube", @"id": @"bbbbbbbbbbb", @"url": @"https://www.youtube.com/watch?v=bbbbbbbbbbb"};
    MacLCYouTubePage * const page = PageFromObject(@{@"entries": @[first, unnamed, again, FlatVideo(@"ccccccccccc", @"Third")]}, 0);
    XCTAssertEqual(page.results.count, (NSUInteger)2);
    XCTAssertEqualObjects(page.videos[0].title, @"First");
    XCTAssertEqualObjects(page.videos[1].identifier, @"ccccccccccc");
}

- (void)testMayHaveMore
{
    NSMutableArray * const entries = [NSMutableArray array];
    for (int i = 0; i < 12; i++) {
        [entries addObject:FlatVideo([NSString stringWithFormat:@"vid%08d", i], @"t")];
    }
    NSDictionary * const doc = @{@"entries": entries};
    XCTAssertTrue(PageFromObject(doc, 12).mayHaveMore);
    XCTAssertTrue(PageFromObject(doc, 10).mayHaveMore);
    XCTAssertFalse(PageFromObject(doc, 13).mayHaveMore);
    XCTAssertFalse(PageFromObject(doc, 0).mayHaveMore);
    /* duplicates and dropped entries still count as received */
    NSMutableArray * const withDup = [entries mutableCopy];
    [withDup replaceObjectAtIndex:1 withObject:entries[0]];
    XCTAssertTrue(PageFromObject(@{@"entries": withDup}, 12).mayHaveMore);
    /* a playlist that knows its length: everything received means no more */
    XCTAssertFalse(PageFromObject(@{@"entries": entries, @"playlist_count": @12}, 12).mayHaveMore);
    XCTAssertTrue(PageFromObject(@{@"entries": entries, @"playlist_count": @40}, 12).mayHaveMore);
}

- (void)testMergedPageInterleavesAndRemovesDuplicates
{
    MacLCYouTubePage * const a = PageFromObject(@{@"entries": @[FlatVideo(@"aaaaaaaaaa1", @"a1"), FlatVideo(@"aaaaaaaaaa2", @"a2"), FlatVideo(@"shared00000", @"s")]}, 3);
    MacLCYouTubePage * const b = PageFromObject(@{@"entries": @[FlatVideo(@"bbbbbbbbbb1", @"b1"), FlatVideo(@"shared00000", @"s"), FlatVideo(@"bbbbbbbbbb3", @"b3")]}, 3);
    MacLCYouTubePage * const merged = MacLCYouTubeMergedPage(@"Home", @[a, b], 0);
    NSMutableArray * const ids = [NSMutableArray array];
    for (MacLCYouTubeVideo *v in merged.videos) {
        [ids addObject:v.identifier];
    }
    NSArray * const expected = @[@"aaaaaaaaaa1", @"bbbbbbbbbb1", @"aaaaaaaaaa2", @"shared00000", @"bbbbbbbbbb3"];
    XCTAssertEqualObjects(ids, expected);
    XCTAssertEqualObjects(merged.title, @"Home");
    XCTAssertTrue(merged.mayHaveMore);
    MacLCYouTubePage * const cut = MacLCYouTubeMergedPage(@"Home", @[a, b], 3);
    XCTAssertEqual(cut.results.count, (NSUInteger)3);
    XCTAssertEqual(cut.videos.count, (NSUInteger)3);
    XCTAssertTrue(cut.mayHaveMore);
}

#pragma mark URLs

- (void)testVideoIdentifierFromURL
{
    NSString * const expected = @"dQw4w9WgXcQ";
    for (NSString *s in @[@"https://www.youtube.com/watch?v=dQw4w9WgXcQ", @"https://youtube.com/watch?v=dQw4w9WgXcQ&t=42s&list=PLabc",
                          @"https://m.youtube.com/watch?feature=share&v=dQw4w9WgXcQ", @"https://music.youtube.com/watch?v=dQw4w9WgXcQ",
                          @"https://youtu.be/dQw4w9WgXcQ", @"https://youtu.be/dQw4w9WgXcQ?si=abc",
                          @"https://www.youtube.com/shorts/dQw4w9WgXcQ", @"https://www.youtube.com/live/dQw4w9WgXcQ?feature=share",
                          @"https://www.youtube.com/embed/dQw4w9WgXcQ", @"https://www.youtube-nocookie.com/embed/dQw4w9WgXcQ"]) {
        XCTAssertEqualObjects([MacLCYouTubeParser videoIdentifierFromURL:[NSURL URLWithString:s]], expected);
    }
    for (NSString *s in @[@"https://www.youtube.com/", @"https://www.youtube.com/watch", @"https://www.youtube.com/watch?v=short",
                          @"https://www.youtube.com/playlist?list=PLabc", @"https://www.youtube.com/@BlenderStudio",
                          @"https://example.com/watch?v=dQw4w9WgXcQ", @"https://notyoutube.com/watch?v=dQw4w9WgXcQ",
                          @"https://youtu.be/", @"https://www.youtube.com/shorts/", @"https://www.youtube.com/watch?v=dQw4w9WgXcQ_toolong",
                          @"file:///watch?v=dQw4w9WgXcQ"]) {
        XCTAssertNil([MacLCYouTubeParser videoIdentifierFromURL:[NSURL URLWithString:s]]);
    }
}

- (void)testResultKindForURL
{
    XCTAssertEqual([MacLCYouTubeParser resultKindForURL:[NSURL URLWithString:@"https://www.youtube.com/watch?v=dQw4w9WgXcQ&list=PLabc"]], (NSInteger)MacLCYouTubeResultKindVideo);
    XCTAssertEqual([MacLCYouTubeParser resultKindForURL:[NSURL URLWithString:@"https://youtu.be/dQw4w9WgXcQ"]], (NSInteger)MacLCYouTubeResultKindVideo);
    XCTAssertEqual([MacLCYouTubeParser resultKindForURL:[NSURL URLWithString:@"https://www.youtube.com/playlist?list=PLav47HAVZMjnTFVZL-aImCQIC0uLZtNCz"]], (NSInteger)MacLCYouTubeResultKindPlaylist);
    for (NSString *s in @[@"https://www.youtube.com/channel/UCz75RVbH8q2jdBJ4SnwuZZQ", @"https://www.youtube.com/@BlenderStudio",
                          @"https://www.youtube.com/@BlenderStudio/videos", @"https://www.youtube.com/c/BlenderStudio", @"https://www.youtube.com/user/blender"]) {
        XCTAssertEqual([MacLCYouTubeParser resultKindForURL:[NSURL URLWithString:s]], (NSInteger)MacLCYouTubeResultKindChannel);
    }
    for (NSString *s in @[@"https://www.youtube.com/", @"https://www.youtube.com/feed/subscriptions", @"https://www.youtube.com/results?search_query=x",
                          @"https://example.com/@BlenderStudio", @"https://www.youtube.com/channel/", @"https://www.youtube.com/playlist"]) {
        XCTAssertEqual([MacLCYouTubeParser resultKindForURL:[NSURL URLWithString:s]], (NSInteger)NSNotFound);
    }
}

#pragma mark Wording

- (void)testViewCountString
{
    XCTAssertEqualObjects([MacLCYouTubeFormat viewCountString:0 live:NO], @"No views");
    XCTAssertEqualObjects([MacLCYouTubeFormat viewCountString:1 live:NO], @"1 view");
    XCTAssertEqualObjects([MacLCYouTubeFormat viewCountString:2 live:NO], @"2 views");
    XCTAssertEqualObjects([MacLCYouTubeFormat viewCountString:999 live:NO], @"999 views");
    XCTAssertEqualObjects([MacLCYouTubeFormat viewCountString:1000 live:NO], @"1K views");
    XCTAssertEqualObjects([MacLCYouTubeFormat viewCountString:1234 live:NO], @"1.2K views");
    XCTAssertEqualObjects([MacLCYouTubeFormat viewCountString:9949 live:NO], @"9.9K views");
    XCTAssertEqualObjects([MacLCYouTubeFormat viewCountString:9950 live:NO], @"10K views");
    XCTAssertEqualObjects([MacLCYouTubeFormat viewCountString:12345 live:NO], @"12K views");
    XCTAssertEqualObjects([MacLCYouTubeFormat viewCountString:999499 live:NO], @"999K views");
    XCTAssertEqualObjects([MacLCYouTubeFormat viewCountString:999500 live:NO], @"1M views");
    XCTAssertEqualObjects([MacLCYouTubeFormat viewCountString:1234567 live:NO], @"1.2M views");
    XCTAssertEqualObjects([MacLCYouTubeFormat viewCountString:2484865 live:NO], @"2.5M views");
    XCTAssertEqualObjects([MacLCYouTubeFormat viewCountString:3400000000LL live:NO], @"3.4B views");
    XCTAssertEqualObjects([MacLCYouTubeFormat viewCountString:-1 live:NO], @"");
    XCTAssertEqualObjects([MacLCYouTubeFormat viewCountString:1234 live:YES], @"1.2K watching");
    XCTAssertEqualObjects([MacLCYouTubeFormat viewCountString:57 live:YES], @"57 watching");
    XCTAssertEqualObjects([MacLCYouTubeFormat viewCountString:0 live:YES], @"");
}

- (void)testSubscriberCountString
{
    XCTAssertEqualObjects([MacLCYouTubeFormat subscriberCountString:-1], @"");
    XCTAssertEqualObjects([MacLCYouTubeFormat subscriberCountString:0], @"0 subscribers");
    XCTAssertEqualObjects([MacLCYouTubeFormat subscriberCountString:1], @"1 subscriber");
    XCTAssertEqualObjects([MacLCYouTubeFormat subscriberCountString:577000], @"577K subscribers");
    XCTAssertEqualObjects([MacLCYouTubeFormat subscriberCountString:1250000], @"1.3M subscribers");
}

- (void)testRelativeDateString
{
    NSDate * const now = [NSDate dateWithTimeIntervalSince1970:1800000000];
    NSString *(^ago)(NSTimeInterval) = ^NSString *(NSTimeInterval s) {
        return [MacLCYouTubeFormat relativeDateString:[now dateByAddingTimeInterval:-s] now:now];
    };
    XCTAssertEqualObjects(ago(0), @"just now");
    XCTAssertEqualObjects(ago(59), @"just now");
    XCTAssertEqualObjects(ago(60), @"1 minute ago");
    XCTAssertEqualObjects(ago(300), @"5 minutes ago");
    XCTAssertEqualObjects(ago(3600), @"1 hour ago");
    XCTAssertEqualObjects(ago(7200 + 59), @"2 hours ago");
    XCTAssertEqualObjects(ago(86400), @"1 day ago");
    XCTAssertEqualObjects(ago(3 * 86400), @"3 days ago");
    XCTAssertEqualObjects(ago(7 * 86400), @"1 week ago");
    XCTAssertEqualObjects(ago(15 * 86400), @"2 weeks ago");
    XCTAssertEqualObjects(ago(29 * 86400), @"4 weeks ago");
    XCTAssertEqualObjects(ago(30 * 86400), @"1 month ago");
    XCTAssertEqualObjects(ago(120 * 86400), @"4 months ago");
    XCTAssertEqualObjects(ago(364 * 86400), @"12 months ago");
    XCTAssertEqualObjects(ago(365 * 86400), @"1 year ago");
    XCTAssertEqualObjects(ago(800 * 86400), @"2 years ago");
    /* a date in the future (clock skew) */
    XCTAssertEqualObjects(ago(-3600), @"just now");
}

- (void)testDurationString
{
    XCTAssertEqualObjects([MacLCYouTubeFormat durationString:0], @"");
    XCTAssertEqualObjects([MacLCYouTubeFormat durationString:-5], @"");
    XCTAssertEqualObjects([MacLCYouTubeFormat durationString:5], @"0:05");
    XCTAssertEqualObjects([MacLCYouTubeFormat durationString:42], @"0:42");
    XCTAssertEqualObjects([MacLCYouTubeFormat durationString:725], @"12:05");
    XCTAssertEqualObjects([MacLCYouTubeFormat durationString:3723], @"1:02:03");
    XCTAssertEqualObjects([MacLCYouTubeFormat durationString:15550.0], @"4:19:10");
}

- (void)testMetadataLine
{
    NSDate * const now = [NSDate dateWithTimeIntervalSince1970:1800000000];
    NSMutableDictionary * const base = [FlatVideo(@"aaaaaaaaaaa", @"t") mutableCopy];
    base[@"view_count"] = @1234567;
    base[@"timestamp"] = @(1800000000 - 3 * 86400);
    MacLCYouTubeVideo * const full = PageFromObject(@{@"entries": @[base]}, 0).videos[0];
    XCTAssertEqualObjects([MacLCYouTubeFormat metadataLineForVideo:full now:now], @"1.2M views · 3 days ago");

    [base removeObjectForKey:@"timestamp"];
    XCTAssertEqualObjects([MacLCYouTubeFormat metadataLineForVideo:PageFromObject(@{@"entries": @[base]}, 0).videos[0] now:now], @"1.2M views");
    [base removeObjectForKey:@"view_count"];
    XCTAssertEqualObjects([MacLCYouTubeFormat metadataLineForVideo:PageFromObject(@{@"entries": @[base]}, 0).videos[0] now:now], @"");

    base[@"live_status"] = @"is_live";
    XCTAssertEqualObjects([MacLCYouTubeFormat metadataLineForVideo:PageFromObject(@{@"entries": @[base]}, 0).videos[0] now:now], @"LIVE");
    base[@"view_count"] = @1234;
    XCTAssertEqualObjects([MacLCYouTubeFormat metadataLineForVideo:PageFromObject(@{@"entries": @[base]}, 0).videos[0] now:now], @"LIVE · 1.2K watching");
    base[@"live_status"] = @"is_upcoming";
    XCTAssertEqualObjects([MacLCYouTubeFormat metadataLineForVideo:PageFromObject(@{@"entries": @[base]}, 0).videos[0] now:now], @"Upcoming");
}

#pragma mark Errors (real stderr of yt-dlp 2025.11.12)

- (NSInteger)codeFor:(NSString *)name message:(NSString **)message
{
    NSString * const text = Stderr(name);
    XCTAssertNotNil(text);
    return MacLCYouTubeClassifyExtractorError(text ?: @"", message);
}

- (void)testSignedOutFeedsNeedSignIn
{
    for (NSString *name in @[@"signed-out-ytsubs", @"signed-out-ythis", @"signed-out-ytwatchlater", @"signed-out-liked-LL", @"signed-out-feed-playlists"]) {
        XCTAssertEqual([self codeFor:name message:NULL], (NSInteger)3);
    }
}

- (void)testNetworkErrors
{
    XCTAssertEqual([self codeFor:@"offline-proxy-refused" message:NULL], (NSInteger)4);
    XCTAssertEqual([self codeFor:@"offline-timeout" message:NULL], (NSInteger)4);
    XCTAssertEqual(MacLCYouTubeClassifyExtractorError(@"ERROR: [youtube] x: Unable to download webpage: <urlopen error [Errno 8] nodename nor servname provided, or not known>", NULL), (NSInteger)4);
    XCTAssertEqual(MacLCYouTubeClassifyExtractorError(@"ERROR: [youtube] x: Unable to download webpage: <urlopen error [Errno 8] Temporary failure in name resolution>", NULL), (NSInteger)4);
    XCTAssertEqual(MacLCYouTubeClassifyExtractorError(@"ERROR: [youtube] x: The read operation timed out", NULL), (NSInteger)4);
}

- (void)testBrowserCookieFailuresAreTheirOwnError
{
    /* wording from yt_dlp/cookies.py (Safari without Full Disk Access, Keychain, missing database) */
    XCTAssertEqual(MacLCYouTubeClassifyExtractorError(@"ERROR: failed to load cookies", NULL), (NSInteger)6);
    XCTAssertEqual(MacLCYouTubeClassifyExtractorError(@"Traceback (most recent call last):\nPermissionError: [Errno 1] Operation not permitted: '/Users/x/Library/Containers/com.apple.Safari/Data/Library/Cookies/Cookies.binarycookies'\nERROR: failed to load cookies\n", NULL), (NSInteger)6);
    XCTAssertEqual(MacLCYouTubeClassifyExtractorError(@"ERROR: could not find safari cookies database", NULL), (NSInteger)6);
    XCTAssertEqual(MacLCYouTubeClassifyExtractorError(@"WARNING: find-generic-password failed\nERROR: could not find chrome cookies database in \"/Users/x/Library/Application Support/Google/Chrome\"", NULL), (NSInteger)6);
    XCTAssertEqual(MacLCYouTubeClassifyExtractorError(@"ERROR: unsupported browser: \"arc\"", NULL), (NSInteger)6);
    /* a plain network failure is still one */
    XCTAssertEqual([self codeFor:@"offline-timeout" message:NULL], (NSInteger)4);
}

- (void)testOtherErrorsKeepTheExtractorsWordsWithoutTheTag
{
    NSString *message = nil;
    XCTAssertEqual([self codeFor:@"unavailable-video" message:&message], (NSInteger)2);
    XCTAssertEqualObjects(message, @"aaaaaaaaaaa: This video is unavailable");
    XCTAssertEqual([self codeFor:@"missing-channel" message:&message], (NSInteger)2);
    XCTAssertTrue([message containsString:@"HTTP Error 404"]);
    XCTAssertFalse([message containsString:@"[youtube:tab]"]);
    XCTAssertEqual([self codeFor:@"missing-playlist" message:&message], (NSInteger)2);
    XCTAssertEqual([self codeFor:@"cookie-file-missing" message:&message], (NSInteger)2);
    XCTAssertTrue([message hasPrefix:@"FileNotFoundError"]);
    /* the playlist error only means "sign in" for Watch Later and Liked videos */
    XCTAssertEqual(MacLCYouTubeClassifyExtractorError(@"ERROR: [youtube:tab] PLabc: YouTube said: The playlist does not exist.", &message), (NSInteger)2);
    XCTAssertEqual(MacLCYouTubeClassifyExtractorError(@"ERROR: [youtube:tab] WL: YouTube said: The playlist does not exist.", NULL), (NSInteger)3);
    XCTAssertEqual(MacLCYouTubeClassifyExtractorError(@"ERROR: [youtube] abc: Sign in to confirm you’re not a bot.", NULL), (NSInteger)3);
    XCTAssertEqual(MacLCYouTubeClassifyExtractorError(@"ERROR: [youtube] abc: Private video. Sign in if you've been granted access", NULL), (NSInteger)3);
    /* the last ERROR line decides; nothing at all is still an error */
    XCTAssertEqual(MacLCYouTubeClassifyExtractorError(@"ERROR: [youtube] a: Unable to download webpage: timed out\nERROR: [youtube] b: This video is unavailable\n", &message), (NSInteger)2);
    XCTAssertEqual(MacLCYouTubeClassifyExtractorError(@"", &message), (NSInteger)2);
    XCTAssertEqualObjects(message, @"yt-dlp failed.");
}

@end
