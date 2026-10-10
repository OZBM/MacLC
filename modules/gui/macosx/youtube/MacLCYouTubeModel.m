/*****************************************************************************
 * MacLCYouTubeModel.m: videos, channels and playlists as yt-dlp describes
 * them, and the wording YouTube people know ("1.2M views · 3 days ago")
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

#import "youtube/MacLCYouTubeModel.h"

/* Same string as MacLCYouTubeErrorDomain (MacLCYouTubeService.m): this file
 * links on its own in the unit tests. */
static NSString * const MacLCYouTubeModelErrorDomain = @"MacLCYouTubeErrorDomain";
enum { MacLCYouTubeModelBadResponse = 5 };

#pragma mark - JSON helpers (every field may be missing, null or of another type)

static NSString *MacLCYTString(id value)
{
    if (![value isKindOfClass:[NSString class]]) {
        return nil;
    }
    NSString * const s = (NSString *)value;
    return s.length > 0 ? s : nil;
}

static NSDictionary *MacLCYTDict(id value)
{
    return [value isKindOfClass:[NSDictionary class]] ? value : nil;
}

static NSArray *MacLCYTArray(id value)
{
    return [value isKindOfClass:[NSArray class]] ? value : nil;
}

/* -1 when absent. Floats (yt-dlp writes 15550.0) are accepted. */
static double MacLCYTNumber(id value, double fallback)
{
    if ([value isKindOfClass:[NSNumber class]]) {
        const double d = [(NSNumber *)value doubleValue];
        return (d == d && isfinite(d)) ? d : fallback;
    }
    return fallback;
}

static BOOL MacLCYTBool(id value)
{
    return [value isKindOfClass:[NSNumber class]] && [(NSNumber *)value boolValue];
}

/* yt-dlp writes "//yt3.googleusercontent.com/..." for avatars. */
static NSURL *MacLCYTURL(id value)
{
    NSString *s = MacLCYTString(value);
    if (s == nil) {
        return nil;
    }
    if ([s hasPrefix:@"//"]) {
        s = [@"https:" stringByAppendingString:s];
    }
    NSURL * const url = [NSURL URLWithString:s];
    return (url.scheme != nil && url.host != nil) ? url : nil;
}

static BOOL MacLCYTIsVideoIdentifier(NSString *s)
{
    if (s.length != 11) {
        return NO;
    }
    static NSCharacterSet *bad;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableCharacterSet * const ok = [NSMutableCharacterSet alphanumericCharacterSet];
        [ok formIntersectionWithCharacterSet:[NSCharacterSet characterSetWithRange:NSMakeRange(0, 128)]];
        [ok addCharactersInString:@"-_"];
        bad = ok.invertedSet;
    });
    return [s rangeOfCharacterFromSet:bad].location == NSNotFound;
}

static BOOL MacLCYTIsChannelIdentifier(NSString *s)
{
    return s.length == 24 && [s hasPrefix:@"UC"];
}

static BOOL MacLCYTIsPlaylistIdentifier(NSString *s)
{
    for (NSString *prefix in @[@"PL", @"UU", @"LL", @"WL", @"OL", @"RD", @"FL", @"VL"]) {
        if ([s hasPrefix:prefix] && (s.length > 2 || [s isEqualToString:@"LL"] || [s isEqualToString:@"WL"])) {
            return YES;
        }
    }
    return NO;
}

static NSDate *MacLCYTDateFrom(NSDictionary *d)
{
    double t = MacLCYTNumber(d[@"timestamp"], 0);
    if (t <= 0) {
        t = MacLCYTNumber(d[@"release_timestamp"], 0);
    }
    if (t > 0) {
        return [NSDate dateWithTimeIntervalSince1970:t];
    }
    NSString * const ymd = MacLCYTString(d[@"upload_date"]);
    if (ymd.length == 8) {
        NSDateComponents * const c = [[NSDateComponents alloc] init];
        c.year = [[ymd substringWithRange:NSMakeRange(0, 4)] integerValue];
        c.month = [[ymd substringWithRange:NSMakeRange(4, 2)] integerValue];
        c.day = [[ymd substringWithRange:NSMakeRange(6, 2)] integerValue];
        c.hour = 12;
        NSCalendar * const cal = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
        cal.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
        if (c.year > 1990 && c.month >= 1 && c.month <= 12 && c.day >= 1 && c.day <= 31) {
            return [cal dateFromComponents:c];
        }
    }
    return nil;
}

/* The picture for a 16:9 card: among the 16:9 pictures (width/height within
 * 0.05 of 16:9, or a name YouTube makes 16:9: maxresdefault, hq720,
 * mqdefault) the smallest at least 640 wide, else the widest. Without any
 * known 16:9 picture the same rule runs on every picture with a width.
 * At the same width a .jpg beats a .webp. Pictures with no width and no
 * known name (storyboards, "0.jpg", 4:3 "sddefault") are never chosen. */
static NSURL *MacLCYTBestThumbnail(NSArray *thumbnails)
{
    NSMutableArray<NSDictionary *> * const wide = [NSMutableArray array];
    NSMutableArray<NSDictionary *> * const all = [NSMutableArray array];
    for (id item in thumbnails) {
        NSDictionary * const t = MacLCYTDict(item);
        NSURL * const url = MacLCYTURL(t[@"url"]);
        if (url == nil) {
            continue;
        }
        NSString * const path = url.path;
        double w = MacLCYTNumber(t[@"width"], 0);
        const double h = MacLCYTNumber(t[@"height"], 0);
        const BOOL explicitWidth = w > 0;
        BOOL sixteenNine = explicitWidth && h > 0 && fabs(w / h - 16.0 / 9.0) < 0.05;
        if (!sixteenNine) {
            const double named = [path containsString:@"maxresdefault"] || [path containsString:@"hq720"] ? 1280
                : [path containsString:@"mqdefault"] ? 320 : 0;
            if (named > 0 && !(explicitWidth && h > 0)) {
                sixteenNine = YES;
                w = explicitWidth ? w : named;
            }
        }
        if (w <= 0) {
            continue;
        }
        NSDictionary * const entry = @{@"url": url, @"w": @(w), @"webp": @([path.pathExtension isEqualToString:@"webp"]),
                                       @"explicit": @(explicitWidth)};
        [all addObject:entry];
        if (sixteenNine) {
            [wide addObject:entry];
        }
    }
    NSArray<NSDictionary *> * const pool = wide.count > 0 ? wide : all;
    NSDictionary *best = nil;
    for (NSDictionary *e in pool) {
        if (best == nil) {
            best = e;
            continue;
        }
        const double w = [e[@"w"] doubleValue], bw = [best[@"w"] doubleValue];
        BOOL better;
        if (w == bw) {
            better = ([e[@"webp"] boolValue] < [best[@"webp"] boolValue])
                || ([e[@"webp"] boolValue] == [best[@"webp"] boolValue] && [e[@"explicit"] boolValue] && ![best[@"explicit"] boolValue]);
        } else if (w >= 640 && bw >= 640) {
            better = w < bw;
        } else {
            better = w >= 640 || (bw < 640 && w > bw);
        }
        if (better) {
            best = e;
        }
    }
    return best[@"url"];
}

#pragma mark - Model classes

@interface MacLCYouTubeChapter ()
@property (readwrite, copy) NSString *title;
@property (readwrite) NSTimeInterval start;
@property (readwrite) NSTimeInterval end;
@end
@implementation MacLCYouTubeChapter
@end

@interface MacLCYouTubeVideo ()
@property (readwrite, copy) NSString *identifier;
@property (readwrite, copy) NSString *title;
@property (readwrite, copy, nullable) NSString *channelName;
@property (readwrite, copy, nullable) NSString *channelIdentifier;
@property (readwrite, nullable) NSURL *channelURL;
@property (readwrite, getter=isChannelVerified) BOOL channelVerified;
@property (readwrite) NSURL *thumbnailURL;
@property (readwrite) NSTimeInterval duration;
@property (readwrite) int64_t viewCount;
@property (readwrite, nullable) NSDate *publishedDate;
@property (readwrite, getter=isLive) BOOL live;
@property (readwrite, getter=isUpcoming) BOOL upcoming;
@property (readwrite, getter=isShort) BOOL shortVideo;
@property (readwrite) NSURL *watchURL;
@property (readwrite, copy, nullable) NSString *descriptionText;
@property (readwrite) int64_t likeCount;
@property (readwrite) int64_t channelFollowerCount;
@property (readwrite, copy) NSArray<MacLCYouTubeChapter *> *chapters;
@property (readwrite, copy) NSArray<NSString *> *tags;
@property (readwrite, copy, nullable) NSString *category;
@end

@interface MacLCYouTubeChannel ()
@property (readwrite, copy) NSString *identifier;
@property (readwrite, copy) NSString *name;
@property (readwrite, copy, nullable) NSString *handle;
@property (readwrite) NSURL *URL;
@property (readwrite, nullable) NSURL *avatarURL;
@property (readwrite, nullable) NSURL *bannerURL;
@property (readwrite) int64_t subscriberCount;
@property (readwrite, copy, nullable) NSString *descriptionText;
@property (readwrite, getter=isVerified) BOOL verified;
@end

@interface MacLCYouTubePlaylist ()
@property (readwrite, copy) NSString *identifier;
@property (readwrite, copy) NSString *title;
@property (readwrite, copy, nullable) NSString *channelName;
@property (readwrite) NSInteger videoCount;
@property (readwrite, nullable) NSURL *thumbnailURL;
@property (readwrite) NSURL *URL;
@end

@interface MacLCYouTubeResult ()
@property (readwrite) MacLCYouTubeResultKind kind;
@property (readwrite, nullable) MacLCYouTubeVideo *video;
@property (readwrite, nullable) MacLCYouTubeChannel *channel;
@property (readwrite, nullable) MacLCYouTubePlaylist *playlist;
@end

@interface MacLCYouTubePage ()
@property (readwrite, copy) NSString *title;
@property (readwrite, nullable) MacLCYouTubeChannel *channel;
@property (readwrite, nullable) MacLCYouTubePlaylist *playlist;
@property (readwrite, copy) NSArray<MacLCYouTubeResult *> *results;
@property (readwrite, copy) NSArray<MacLCYouTubeVideo *> *videos;
@property (readwrite) BOOL mayHaveMore;
@end

@implementation MacLCYouTubeVideo
@end
@implementation MacLCYouTubeChannel
@end
@implementation MacLCYouTubePlaylist
@end
@implementation MacLCYouTubeResult
@end
@implementation MacLCYouTubePage
@end

#pragma mark - Builders

/* fallback: what a channel tab says about its owner, for entries (flat
 * channel-tab videos carry no channel of their own). */
static MacLCYouTubeVideo *MacLCYTVideoFrom(NSDictionary *d, MacLCYouTubeChannel *fallback)
{
    NSString *identifier = MacLCYTString(d[@"id"]);
    NSString * const urlString = MacLCYTString(d[@"url"]) ?: MacLCYTString(d[@"webpage_url"]);
    if (!MacLCYTIsVideoIdentifier(identifier)) {
        identifier = urlString != nil ? [MacLCYouTubeParser videoIdentifierFromURL:[NSURL URLWithString:urlString]] : nil;
    }
    NSString * const title = MacLCYTString(d[@"title"]) ?: MacLCYTString(d[@"fulltitle"]);
    if (identifier == nil || title == nil) {
        return nil;
    }

    MacLCYouTubeVideo * const v = [[MacLCYouTubeVideo alloc] init];
    v.identifier = identifier;
    v.title = title;
    v.channelName = MacLCYTString(d[@"channel"]) ?: MacLCYTString(d[@"uploader"]);
    v.channelIdentifier = MacLCYTString(d[@"channel_id"]);
    v.channelURL = MacLCYTURL(d[@"channel_url"]) ?: MacLCYTURL(d[@"uploader_url"]);
    v.channelVerified = MacLCYTBool(d[@"channel_is_verified"]);
    if (v.channelName == nil && v.channelIdentifier == nil && fallback != nil) {
        v.channelName = fallback.name;
        v.channelIdentifier = fallback.identifier.length > 0 ? fallback.identifier : nil;
        v.channelURL = fallback.URL;
        v.channelVerified = fallback.verified;
    }
    if (v.channelURL == nil) {
        NSString * const uploaderId = MacLCYTString(d[@"uploader_id"]);
        if (v.channelIdentifier != nil) {
            v.channelURL = [NSURL URLWithString:[@"https://www.youtube.com/channel/" stringByAppendingString:v.channelIdentifier]];
        } else if ([uploaderId hasPrefix:@"@"]) {
            v.channelURL = [NSURL URLWithString:[@"https://www.youtube.com/" stringByAppendingString:uploaderId]];
        }
    }
    v.thumbnailURL = MacLCYTBestThumbnail(MacLCYTArray(d[@"thumbnails"]))
        ?: ([MacLCYTURL(d[@"thumbnail"]).pathExtension isEqualToString:@"webp"] ? nil : MacLCYTURL(d[@"thumbnail"]))
        ?: [NSURL URLWithString:[NSString stringWithFormat:@"https://i.ytimg.com/vi/%@/hqdefault.jpg", identifier]];
    const double duration = MacLCYTNumber(d[@"duration"], 0);
    v.duration = duration > 0 ? duration : 0;
    const double views = MacLCYTNumber(d[@"view_count"], -1);
    v.viewCount = views >= 0 ? (int64_t)views : -1;
    v.publishedDate = MacLCYTDateFrom(d);
    NSString * const status = MacLCYTString(d[@"live_status"]);
    v.live = [status isEqualToString:@"is_live"] || (status == nil && MacLCYTBool(d[@"is_live"]));
    v.upcoming = [status isEqualToString:@"is_upcoming"];
    v.shortVideo = [urlString containsString:@"/shorts/"] || [MacLCYTString(d[@"webpage_url"]) containsString:@"/shorts/"];
    v.watchURL = [NSURL URLWithString:[@"https://www.youtube.com/watch?v=" stringByAppendingString:identifier]];

    v.descriptionText = MacLCYTString(d[@"description"]);
    const double likes = MacLCYTNumber(d[@"like_count"], -1);
    v.likeCount = likes >= 0 ? (int64_t)likes : -1;
    const double followers = MacLCYTNumber(d[@"channel_follower_count"], -1);
    v.channelFollowerCount = followers >= 0 ? (int64_t)followers : -1;

    NSMutableArray<MacLCYouTubeChapter *> * const chapters = [NSMutableArray array];
    for (id item in MacLCYTArray(d[@"chapters"])) {
        NSDictionary * const c = MacLCYTDict(item);
        const double start = MacLCYTNumber(c[@"start_time"], -1);
        if (c == nil || start < 0) {
            continue;
        }
        MacLCYouTubeChapter * const chapter = [[MacLCYouTubeChapter alloc] init];
        chapter.title = MacLCYTString(c[@"title"]) ?: @"";
        chapter.start = start;
        const double end = MacLCYTNumber(c[@"end_time"], start);
        chapter.end = end >= start ? end : start;
        [chapters addObject:chapter];
    }
    v.chapters = chapters;
    NSMutableArray<NSString *> * const tags = [NSMutableArray array];
    for (id tag in MacLCYTArray(d[@"tags"])) {
        if (MacLCYTString(tag) != nil) {
            [tags addObject:tag];
        }
    }
    v.tags = tags;
    v.category = MacLCYTString(MacLCYTArray(d[@"categories"]).firstObject);
    return v;
}

/* The picture that stands for the channel: a square one (avatar), the
 * "avatar_uncropped" original when there is one. */
static NSURL *MacLCYTAvatar(NSArray *thumbnails)
{
    NSURL *widest = nil;
    double widestWidth = 0;
    for (id item in thumbnails) {
        NSDictionary * const t = MacLCYTDict(item);
        NSURL * const url = MacLCYTURL(t[@"url"]);
        if (url == nil) {
            continue;
        }
        if ([t[@"id"] isEqual:@"avatar_uncropped"]) {
            return url;
        }
        const double w = MacLCYTNumber(t[@"width"], 0), h = MacLCYTNumber(t[@"height"], 0);
        if (w > 0 && fabs(w - h) <= 2 && w > widestWidth) {
            widest = url;
            widestWidth = w;
        }
    }
    return widest;
}

/* The widest wide-and-short picture (2560x424 "w2560-fcrop64"). The
 * "banner_uncropped" one is the 16:9 TV artwork, not the web banner. */
static NSURL *MacLCYTBanner(NSArray *thumbnails)
{
    NSURL *widest = nil;
    double widestWidth = 0;
    for (id item in thumbnails) {
        NSDictionary * const t = MacLCYTDict(item);
        NSURL * const url = MacLCYTURL(t[@"url"]);
        const double w = MacLCYTNumber(t[@"width"], 0), h = MacLCYTNumber(t[@"height"], 0);
        if (url != nil && h > 0 && w / h >= 2.5 && w > widestWidth) {
            widest = url;
            widestWidth = w;
        }
    }
    return widest;
}

/* A channel from a search entry or from the playlist-level fields of a
 * channel tab. */
static MacLCYouTubeChannel *MacLCYTChannelFrom(NSDictionary *d)
{
    NSString *identifier = MacLCYTString(d[@"channel_id"]);
    if (identifier == nil && MacLCYTIsChannelIdentifier(MacLCYTString(d[@"id"]))) {
        identifier = d[@"id"];
    }
    NSString *handle = MacLCYTString(d[@"uploader_id"]);
    if (![handle hasPrefix:@"@"]) {
        NSString * const last = MacLCYTURL(d[@"uploader_url"]).lastPathComponent;
        handle = [last hasPrefix:@"@"] ? last : nil;
    }
    NSString * const name = MacLCYTString(d[@"channel"]) ?: MacLCYTString(d[@"uploader"]) ?: MacLCYTString(d[@"title"]);
    if (name == nil || (identifier == nil && handle == nil)) {
        return nil;
    }
    MacLCYouTubeChannel * const c = [[MacLCYouTubeChannel alloc] init];
    c.identifier = identifier ?: @"";
    c.name = name;
    c.handle = handle;
    NSURL *url = MacLCYTURL(d[@"channel_url"]);
    if (url == nil && identifier != nil) {
        url = [NSURL URLWithString:[@"https://www.youtube.com/channel/" stringByAppendingString:identifier]];
    }
    if (url == nil && handle != nil) {
        url = [NSURL URLWithString:[@"https://www.youtube.com/" stringByAppendingString:handle]];
    }
    c.URL = url;
    NSArray * const thumbs = MacLCYTArray(d[@"thumbnails"]);
    c.avatarURL = MacLCYTAvatar(thumbs);
    c.bannerURL = MacLCYTBanner(thumbs);
    const double subs = MacLCYTNumber(d[@"channel_follower_count"], -1);
    c.subscriberCount = subs >= 0 ? (int64_t)subs : -1;
    c.descriptionText = MacLCYTString(d[@"description"]);
    c.verified = MacLCYTBool(d[@"channel_is_verified"]);
    return c.URL != nil ? c : nil;
}

static MacLCYouTubePlaylist *MacLCYTPlaylistFrom(NSDictionary *d)
{
    NSString *identifier = MacLCYTString(d[@"id"]);
    if (!MacLCYTIsPlaylistIdentifier(identifier)) {
        NSURLComponents * const comps = [NSURLComponents componentsWithString:MacLCYTString(d[@"url"]) ?: MacLCYTString(d[@"webpage_url"]) ?: @""];
        for (NSURLQueryItem *q in comps.queryItems) {
            if ([q.name isEqualToString:@"list"] && q.value.length > 0) {
                identifier = q.value;
            }
        }
    }
    NSString * const title = MacLCYTString(d[@"title"]);
    if (identifier.length == 0 || title == nil) {
        return nil;
    }
    MacLCYouTubePlaylist * const p = [[MacLCYouTubePlaylist alloc] init];
    p.identifier = identifier;
    p.title = title;
    p.channelName = MacLCYTString(d[@"channel"]) ?: MacLCYTString(d[@"uploader"]);
    const double count = MacLCYTNumber(d[@"playlist_count"], -1);
    p.videoCount = count >= 0 ? (NSInteger)count : -1;
    p.thumbnailURL = MacLCYTBestThumbnail(MacLCYTArray(d[@"thumbnails"]));
    p.URL = [NSURL URLWithString:[@"https://www.youtube.com/playlist?list=" stringByAppendingString:
                                  [identifier stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLQueryAllowedCharacterSet]]];
    return p;
}

static MacLCYouTubeResult *MacLCYTResult(MacLCYouTubeVideo *v, MacLCYouTubeChannel *c, MacLCYouTubePlaylist *p)
{
    MacLCYouTubeResult * const r = [[MacLCYouTubeResult alloc] init];
    if (v != nil) {
        r.kind = MacLCYouTubeResultKindVideo;
        r.video = v;
    } else if (c != nil) {
        r.kind = MacLCYouTubeResultKindChannel;
        r.channel = c;
    } else {
        r.kind = MacLCYouTubeResultKindPlaylist;
        r.playlist = p;
    }
    return r;
}

static NSError *MacLCYTBadResponse(NSString *why)
{
    return [NSError errorWithDomain:MacLCYouTubeModelErrorDomain
                               code:MacLCYouTubeModelBadResponse
                           userInfo:@{NSLocalizedDescriptionKey: why}];
}

static id MacLCYTJSON(NSData *data, NSError **error)
{
    if (data.length == 0) {
        if (error) *error = MacLCYTBadResponse(@"YouTube answered with nothing.");
        return nil;
    }
    id json = nil;
    @try {
        json = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
    } @catch (NSException *e) {
        json = nil;
    }
    if (![json isKindOfClass:[NSDictionary class]]) {
        if (error) *error = MacLCYTBadResponse(@"YouTube's answer could not be read.");
        return nil;
    }
    return json;
}

#pragma mark - Parser

@implementation MacLCYouTubeParser

+ (MacLCYouTubePage *)pageFromJSONData:(NSData *)data limit:(NSUInteger)limit error:(NSError **)error
{
    NSDictionary * const doc = MacLCYTJSON(data, error);
    if (doc == nil) {
        return nil;
    }
    NSArray * const entries = MacLCYTArray(doc[@"entries"]);
    if (entries == nil && ![doc[@"_type"] isEqual:@"playlist"]) {
        if (error) *error = MacLCYTBadResponse(@"This is not a list.");
        return nil;
    }

    NSString * const docId = MacLCYTString(doc[@"id"]);
    NSString * const docURL = MacLCYTString(doc[@"webpage_url"]);
    MacLCYouTubePage * const page = [[MacLCYouTubePage alloc] init];
    page.title = MacLCYTString(doc[@"title"]) ?: @"";

    /* A channel tab has a "UC…" id; a playlist, a playlist id or list=. */
    MacLCYouTubeChannel *tabChannel = nil;
    if (MacLCYTIsChannelIdentifier(docId)) {
        tabChannel = MacLCYTChannelFrom(doc);
        page.channel = tabChannel;
    } else if (MacLCYTIsPlaylistIdentifier(docId) || [docURL containsString:@"list="]) {
        page.playlist = MacLCYTPlaylistFrom(doc);
    }

    NSMutableArray<MacLCYouTubeResult *> * const results = [NSMutableArray array];
    NSMutableArray<MacLCYouTubeVideo *> * const videos = [NSMutableArray array];
    NSMutableSet<NSString *> * const seen = [NSMutableSet set];
    for (id item in entries) {
        NSDictionary * const e = MacLCYTDict(item);
        if (e == nil) {
            continue;
        }
        NSString * const eid = MacLCYTString(e[@"id"]);
        NSString * const url = MacLCYTString(e[@"url"]) ?: MacLCYTString(e[@"webpage_url"]);
        NSString * const key = MacLCYTString(e[@"ie_key"]);
        const BOOL isTab = [key isEqualToString:@"YoutubeTab"] || [e[@"_type"] isEqual:@"playlist"];
        if (isTab) {
            if (MacLCYTIsChannelIdentifier(eid) || [url containsString:@"/channel/"] || [url containsString:@"/@"]) {
                MacLCYouTubeChannel * const c = MacLCYTChannelFrom(e);
                NSString * const dedupe = c != nil ? [@"c:" stringByAppendingString:c.identifier.length ? c.identifier : c.URL.absoluteString] : nil;
                if (c != nil && ![seen containsObject:dedupe]) {
                    [seen addObject:dedupe];
                    [results addObject:MacLCYTResult(nil, c, nil)];
                }
            } else {
                MacLCYouTubePlaylist * const p = MacLCYTPlaylistFrom(e);
                NSString * const dedupe = [@"p:" stringByAppendingString:p.identifier ?: @""];
                if (p != nil && ![seen containsObject:dedupe]) {
                    [seen addObject:dedupe];
                    [results addObject:MacLCYTResult(nil, nil, p)];
                }
            }
            continue;
        }
        MacLCYouTubeVideo * const v = MacLCYTVideoFrom(e, tabChannel);
        NSString * const dedupe = [@"v:" stringByAppendingString:v.identifier ?: @""];
        if (v != nil && ![seen containsObject:dedupe]) {
            [seen addObject:dedupe];
            [results addObject:MacLCYTResult(v, nil, nil)];
            [videos addObject:v];
        }
    }
    page.results = results;
    page.videos = videos;

    /* The request got as many entries as it asked for. A playlist that says
     * how long it is settles it when everything has been received. */
    BOOL more = limit > 0 && entries.count >= limit;
    const double total = MacLCYTNumber(doc[@"playlist_count"], -1);
    if (more && total > 0 && (double)entries.count >= total) {
        more = NO;
    }
    page.mayHaveMore = more;
    return page;
}

+ (MacLCYouTubeVideo *)videoFromJSONData:(NSData *)data error:(NSError **)error
{
    NSDictionary * const doc = MacLCYTJSON(data, error);
    if (doc == nil) {
        return nil;
    }
    MacLCYouTubeVideo * const v = MacLCYTVideoFrom(doc, nil);
    if (v == nil) {
        if (error) *error = MacLCYTBadResponse(@"This is not a video.");
    }
    return v;
}

+ (NSString *)videoIdentifierFromURL:(NSURL *)URL
{
    NSString * const host = URL.host.lowercaseString;
    if (host.length == 0) {
        return nil;
    }
    NSString *candidate = nil;
    if ([host isEqualToString:@"youtu.be"] || [host isEqualToString:@"www.youtu.be"]) {
        NSArray * const parts = [URL.path componentsSeparatedByString:@"/"];
        candidate = parts.count > 1 ? parts[1] : nil;
    } else if ([host isEqualToString:@"youtube.com"] || [host hasSuffix:@".youtube.com"]
               || [host isEqualToString:@"youtube-nocookie.com"] || [host hasSuffix:@".youtube-nocookie.com"]) {
        NSArray<NSString *> * const parts = [URL.path componentsSeparatedByString:@"/"];
        if ([URL.path isEqualToString:@"/watch"]) {
            NSURLComponents * const comps = [NSURLComponents componentsWithURL:URL resolvingAgainstBaseURL:NO];
            for (NSURLQueryItem *q in comps.queryItems) {
                if ([q.name isEqualToString:@"v"]) {
                    candidate = q.value;
                    break;
                }
            }
        } else if (parts.count > 2 && [@[@"shorts", @"live", @"embed", @"v"] containsObject:parts[1]]) {
            candidate = parts[2];
        }
    }
    return MacLCYTIsVideoIdentifier(candidate) ? candidate : nil;
}

+ (NSInteger)resultKindForURL:(NSURL *)URL
{
    if ([self videoIdentifierFromURL:URL] != nil) {
        return MacLCYouTubeResultKindVideo;
    }
    NSString * const host = URL.host.lowercaseString;
    if (!([host isEqualToString:@"youtube.com"] || [host hasSuffix:@".youtube.com"])) {
        return NSNotFound;
    }
    NSURLComponents * const comps = [NSURLComponents componentsWithURL:URL resolvingAgainstBaseURL:NO];
    for (NSURLQueryItem *q in comps.queryItems) {
        if ([q.name isEqualToString:@"list"] && q.value.length > 0 && [URL.path isEqualToString:@"/playlist"]) {
            return MacLCYouTubeResultKindPlaylist;
        }
    }
    NSArray<NSString *> * const parts = [URL.path componentsSeparatedByString:@"/"];
    if (parts.count > 1) {
        NSString * const first = parts[1];
        if ([first hasPrefix:@"@"] && first.length > 1) {
            return MacLCYouTubeResultKindChannel;
        }
        if (parts.count > 2 && parts[2].length > 0 && [@[@"channel", @"c", @"user"] containsObject:first]) {
            return MacLCYouTubeResultKindChannel;
        }
    }
    return NSNotFound;
}

@end

#pragma mark - Wording

/* "1.2K", "12K", "1.2M": one decimal below 10, none from 10; a value that
 * rounds up to the next unit moves to it ("999,950" is "1M"). */
static NSString *MacLCYTShortCount(int64_t count)
{
    if (count < 1000) {
        return [NSString stringWithFormat:@"%lld", (long long)count];
    }
    static NSString * const units[] = {@"K", @"M", @"B"};
    double value = (double)count / 1000.0;
    for (int i = 0; i < 3; i++) {
        double rounded = value < 10 ? round(value * 10) / 10 : round(value);
        if (rounded >= 1000 && i < 2) {
            value = rounded / 1000.0;
            continue;
        }
        if (rounded < 10) {
            NSString * const s = [NSString stringWithFormat:@"%.1f", rounded];
            return [([s hasSuffix:@".0"] ? [s substringToIndex:s.length - 2] : s) stringByAppendingString:units[i]];
        }
        return [NSString stringWithFormat:@"%.0f%@", rounded, units[i]];
    }
    return [NSString stringWithFormat:@"%lldB", (long long)(count / 1000000000)];
}

@implementation MacLCYouTubeFormat

+ (NSString *)viewCountString:(int64_t)count live:(BOOL)live
{
    if (count < 0 || (live && count == 0)) {
        return @"";
    }
    if (live) {
        return [MacLCYTShortCount(count) stringByAppendingString:@" watching"];
    }
    if (count == 0) {
        return @"No views";
    }
    if (count == 1) {
        return @"1 view";
    }
    return [MacLCYTShortCount(count) stringByAppendingString:@" views"];
}

+ (NSString *)subscriberCountString:(int64_t)count
{
    if (count < 0) {
        return @"";
    }
    if (count == 1) {
        return @"1 subscriber";
    }
    return [MacLCYTShortCount(count) stringByAppendingString:@" subscribers"];
}

+ (NSString *)relativeDateString:(NSDate *)date now:(NSDate *)now
{
    const long long seconds = (long long)[now timeIntervalSinceDate:date];
    NSString *unit = nil;
    long long n = 0;
    if (seconds < 60) {
        return @"just now";
    } else if (seconds < 3600) {
        n = seconds / 60; unit = @"minute";
    } else if (seconds < 86400) {
        n = seconds / 3600; unit = @"hour";
    } else {
        const long long days = seconds / 86400;
        if (days < 7) {
            n = days; unit = @"day";
        } else if (days < 30) {
            n = days / 7; unit = @"week";
        } else if (days < 365) {
            n = days / 30; unit = @"month";
        } else {
            n = days / 365; unit = @"year";
        }
    }
    return [NSString stringWithFormat:@"%lld %@%@ ago", n, unit, n == 1 ? @"" : @"s"];
}

+ (NSString *)durationString:(NSTimeInterval)duration
{
    if (!(duration >= 1)) {
        return @"";
    }
    const long long total = (long long)duration;
    const long long h = total / 3600, m = (total / 60) % 60, s = total % 60;
    return h > 0 ? [NSString stringWithFormat:@"%lld:%02lld:%02lld", h, m, s]
                 : [NSString stringWithFormat:@"%lld:%02lld", m, s];
}

+ (NSString *)metadataLineForVideo:(MacLCYouTubeVideo *)video now:(NSDate *)now
{
    if (video.upcoming) {
        return @"Upcoming";
    }
    if (video.live) {
        NSString * const watching = [self viewCountString:video.viewCount live:YES];
        return watching.length > 0 ? [@"LIVE · " stringByAppendingString:watching] : @"LIVE";
    }
    NSMutableArray<NSString *> * const parts = [NSMutableArray array];
    NSString * const views = [self viewCountString:video.viewCount live:NO];
    if (views.length > 0) {
        [parts addObject:views];
    }
    if (video.publishedDate != nil) {
        [parts addObject:[self relativeDateString:video.publishedDate now:now]];
    }
    return [parts componentsJoinedByString:@" · "];
}

@end

#pragma mark - Shared with the service (not in the public header)

/* Several pages in one: round robin over the pages, the same video, channel or
 * playlist kept once. limit 0 keeps everything. */
MacLCYouTubePage *MacLCYouTubeMergedPage(NSString *title, NSArray<MacLCYouTubePage *> *pages, NSUInteger limit)
{
    NSMutableArray<MacLCYouTubeResult *> * const results = [NSMutableArray array];
    NSMutableArray<MacLCYouTubeVideo *> * const videos = [NSMutableArray array];
    NSMutableSet<NSString *> * const seen = [NSMutableSet set];
    NSUInteger longest = 0;
    BOOL more = NO;
    for (MacLCYouTubePage *p in pages) {
        longest = MAX(longest, p.results.count);
        more = more || p.mayHaveMore;
    }
    for (NSUInteger i = 0; i < longest; i++) {
        for (MacLCYouTubePage *p in pages) {
            if (i >= p.results.count) {
                continue;
            }
            MacLCYouTubeResult * const r = p.results[i];
            NSString * const key = r.kind == MacLCYouTubeResultKindVideo ? [@"v:" stringByAppendingString:r.video.identifier]
                : r.kind == MacLCYouTubeResultKindChannel ? [@"c:" stringByAppendingString:r.channel.URL.absoluteString]
                : [@"p:" stringByAppendingString:r.playlist.identifier];
            if ([seen containsObject:key]) {
                continue;
            }
            [seen addObject:key];
            [results addObject:r];
            if (r.video != nil) {
                [videos addObject:r.video];
            }
        }
    }
    if (limit > 0 && results.count > limit) {
        more = YES;
        while (results.count > limit) {
            MacLCYouTubeResult * const last = results.lastObject;
            [results removeLastObject];
            if (last.video != nil) {
                [videos removeObject:last.video];
            }
        }
    }
    MacLCYouTubePage * const page = [[MacLCYouTubePage alloc] init];
    page.title = title;
    page.results = results;
    page.videos = videos;
    page.mayHaveMore = more;
    return page;
}

/* Which MacLCYouTubeError (values of the enum in MacLCYouTubeService.h) the
 * stderr of a failed yt-dlp run means: 3 sign in required, 4 network,
 * 6 the browser's cookies could not be read, 2 anything else. The last "ERROR:" line decides. *message gets that line
 * without "ERROR: " and the "[extractor] " tag. */
NSInteger MacLCYouTubeClassifyExtractorError(NSString *stderrText, NSString **message)
{
    NSString *line = nil;
    NSString *lastLine = nil;
    for (NSString *l in [stderrText componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
        NSString * const t = [l stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        if (t.length == 0) {
            continue;
        }
        lastLine = t;
        if ([t hasPrefix:@"ERROR:"]) {
            line = t;
        }
    }
    line = line ?: lastLine ?: @"";
    NSString *text = [line hasPrefix:@"ERROR:"] ? [[line substringFromIndex:6] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet] : line;
    if ([text hasPrefix:@"["]) {
        const NSRange close = [text rangeOfString:@"] "];
        if (close.location != NSNotFound && close.location < 40) {
            text = [text substringFromIndex:NSMaxRange(close)];
        }
    }
    /* A traceback or a very long hint is no message for a person. */
    const NSRange hint = [text rangeOfString:@"; please report this issue"];
    if (hint.location != NSNotFound) {
        text = [text substringToIndex:hint.location];
    }
    if (message) {
        *message = text.length > 0 ? text : @"yt-dlp failed.";
    }

    NSString * const lower = line.lowercaseString;
    /* --cookies-from-browser that could not read the cookies. yt-dlp's wording
     * (yt_dlp/cookies.py): "failed to load cookies" (load_cookies wraps every
     * error in it), "could not find safari cookies database" /
     * "could not find <browser> cookies database", "unsupported browser",
     * PermissionError "[Errno 1] Operation not permitted: '…/Cookies.binarycookies'"
     * (Safari without Full Disk Access), "find-generic-password failed" (the
     * Chromium Keychain item), "Failed to decrypt". Any line of the output can
     * carry them: the last ERROR line is only the wrapper. */
    NSString * const everything = stderrText.lowercaseString ?: @"";
    if ([everything containsString:@"failed to load cookies"] || [everything containsString:@"binarycookies"]
        || [everything containsString:@"find-generic-password"] || [everything containsString:@"unsupported browser"]
        || ([everything containsString:@"cookies"] && ([everything containsString:@"operation not permitted"]
            || [everything containsString:@"permissionerror"] || [everything containsString:@"could not find"]
            || [everything containsString:@"failed to decrypt"] || [everything containsString:@"keychain"]))) {
        return 6;
    }
    /* The playlist error of Watch Later and Liked videos names the list. */
    const BOOL ownList = [lower containsString:@"] wl:"] || [lower containsString:@"] ll:"];
    if ([lower containsString:@"login details are needed"] || [lower containsString:@"sign in to confirm"]
        || [lower containsString:@"this video is private"] || [lower containsString:@"private video"]
        || [lower containsString:@"http error 401"] || [lower containsString:@"unauthorized"]
        || (ownList && [lower containsString:@"the playlist does not exist"])) {
        return 3;
    }
    if ([lower containsString:@"unable to download"] || [lower containsString:@"timed out"]
        || [lower containsString:@"temporary failure in name resolution"] || [lower containsString:@"nodename nor servname"]
        || [lower containsString:@"network is unreachable"] || [lower containsString:@"failed to resolve"]
        || [lower containsString:@"connection refused"] || [lower containsString:@"connection reset"]) {
        /* "HTTP Error 404/400" on an API page is a missing page, not a network. */
        if (![lower containsString:@"http error 404"] && ![lower containsString:@"http error 400"]) {
            return 4;
        }
    }
    return 2;
}
