/*****************************************************************************
 * MacLCYouTubeModel.h: videos, channels and playlists as yt-dlp describes
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

/* Foundation only: the unit tests link this file on its own
 * (tests/MacLCYouTubeModelTest.m, with real yt-dlp outputs recorded in
 * .agents/reports/youtube-fixtures/).
 *
 * MacLC has no YouTube API key and wants none: lists come from yt-dlp's
 * "-J --flat-playlist" output (search results, channel tabs, playlists, the
 * signed-in feeds), details from its "-J" output for one video. Flat entries
 * carry: id, url, title, duration, channel, channel_id, channel_url,
 * channel_is_verified, uploader_id, thumbnails [{url, width, height}],
 * view_count, live_status, timestamp / release_timestamp (often null);
 * playlist-level fields carry the channel of a channel tab (channel,
 * channel_id, uploader_id "@handle", channel_follower_count, description,
 * thumbnails with ids "avatar_uncropped" and "banner_uncropped").
 * Every field may be missing or null; nothing here throws. */
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface MacLCYouTubeChapter : NSObject
@property (readonly, copy) NSString *title;
@property (readonly) NSTimeInterval start;
@property (readonly) NSTimeInterval end;
@end

@interface MacLCYouTubeVideo : NSObject
/// The 11-character id.
@property (readonly, copy) NSString *identifier;
@property (readonly, copy) NSString *title;
@property (readonly, copy, nullable) NSString *channelName;
/// "UC…", nil when unknown.
@property (readonly, copy, nullable) NSString *channelIdentifier;
/// channel_url, else uploader_url, else built from the id / handle; nil when none.
@property (readonly, nullable) NSURL *channelURL;
@property (readonly, getter=isChannelVerified) BOOL channelVerified;
/// The best picture for a 16:9 card about 640 px wide: the smallest
/// thumbnail at least 640 wide, else the widest; else
/// https://i.ytimg.com/vi/<id>/hqdefault.jpg (4:3 with bars: draw it aspect
/// fill, the bars fall outside).
@property (readonly) NSURL *thumbnailURL;
/// Seconds; 0 when unknown (lives, premieres).
@property (readonly) NSTimeInterval duration;
/// -1 when unknown.
@property (readonly) int64_t viewCount;
/// timestamp, else release_timestamp, else upload_date (YYYYMMDD, noon UTC);
/// nil when unknown (common in flat lists).
@property (readonly, nullable) NSDate *publishedDate;
/// live_status "is_live".
@property (readonly, getter=isLive) BOOL live;
/// live_status "is_upcoming".
@property (readonly, getter=isUpcoming) BOOL upcoming;
/// Its url is a /shorts/ address.
@property (readonly, getter=isShort) BOOL shortVideo;
/// https://www.youtube.com/watch?v=<id>
@property (readonly) NSURL *watchURL;

/* Only from a single video's "-J" (MacLCYouTubeService detailsForVideo:). */
@property (readonly, copy, nullable) NSString *descriptionText;
/// -1 when unknown.
@property (readonly) int64_t likeCount;
/// -1 when unknown.
@property (readonly) int64_t channelFollowerCount;
@property (readonly, copy) NSArray<MacLCYouTubeChapter *> *chapters;
@property (readonly, copy) NSArray<NSString *> *tags;
/// "Music", "Gaming"... (categories[0]), nil when none.
@property (readonly, copy, nullable) NSString *category;
@end

@interface MacLCYouTubeChannel : NSObject
/// "UC…"; may be empty when only a handle is known.
@property (readonly, copy) NSString *identifier;
@property (readonly, copy) NSString *name;
/// "@BlenderStudio", nil when unknown.
@property (readonly, copy, nullable) NSString *handle;
/// https://www.youtube.com/channel/<id> or /@handle.
@property (readonly) NSURL *URL;
@property (readonly, nullable) NSURL *avatarURL;
@property (readonly, nullable) NSURL *bannerURL;
/// -1 when unknown.
@property (readonly) int64_t subscriberCount;
@property (readonly, copy, nullable) NSString *descriptionText;
@property (readonly, getter=isVerified) BOOL verified;
@end

@interface MacLCYouTubePlaylist : NSObject
/// "PL…", "WL", "LL"...
@property (readonly, copy) NSString *identifier;
@property (readonly, copy) NSString *title;
@property (readonly, copy, nullable) NSString *channelName;
/// -1 when unknown.
@property (readonly) NSInteger videoCount;
@property (readonly, nullable) NSURL *thumbnailURL;
/// https://www.youtube.com/playlist?list=<id>
@property (readonly) NSURL *URL;
@end

typedef NS_ENUM(NSInteger, MacLCYouTubeResultKind) {
    MacLCYouTubeResultKindVideo,
    MacLCYouTubeResultKindChannel,
    MacLCYouTubeResultKindPlaylist,
};

/// One entry of a list: exactly one of the three is set, as `kind` says.
@interface MacLCYouTubeResult : NSObject
@property (readonly) MacLCYouTubeResultKind kind;
@property (readonly, nullable) MacLCYouTubeVideo *video;
@property (readonly, nullable) MacLCYouTubeChannel *channel;
@property (readonly, nullable) MacLCYouTubePlaylist *playlist;
@end

/// One list: a search, a feed, a channel tab, a playlist.
@interface MacLCYouTubePage : NSObject
@property (readonly, copy) NSString *title;
/// The channel a channel tab belongs to (playlist-level fields), else nil.
@property (readonly, nullable) MacLCYouTubeChannel *channel;
/// The playlist itself when the page is one, else nil.
@property (readonly, nullable) MacLCYouTubePlaylist *playlist;
/// In the source's order; entries that are neither a video, a channel nor a
/// playlist (YouTube "shelves", ads, unavailable videos with no title) are
/// dropped; the same video twice keeps the first.
@property (readonly, copy) NSArray<MacLCYouTubeResult *> *results;
/// Only the videos of results, same order.
@property (readonly, copy) NSArray<MacLCYouTubeVideo *> *videos;
/// The request asked for `limit` entries and got that many: there may be more.
@property (readonly) BOOL mayHaveMore;
@end

@interface MacLCYouTubeParser : NSObject
/// A "-J --flat-playlist" document. limit: what was asked (for mayHaveMore);
/// 0 means "no limit asked". nil and *error when not such a document.
+ (nullable MacLCYouTubePage *)pageFromJSONData:(NSData *)data
                                          limit:(NSUInteger)limit
                                          error:(NSError * _Nullable * _Nullable)error;
/// A single video's "-J" document.
+ (nullable MacLCYouTubeVideo *)videoFromJSONData:(NSData *)data
                                            error:(NSError * _Nullable * _Nullable)error;
/// The video id in watch?v=, youtu.be/, /shorts/, /live/, /embed/ addresses;
/// nil otherwise.
+ (nullable NSString *)videoIdentifierFromURL:(NSURL *)URL;
/// Video, channel (/channel/, /@handle, /c/, /user/) or playlist (list=
/// without v=) address; NSNotFound for anything else.
+ (NSInteger)resultKindForURL:(NSURL *)URL;
@end

/// Wording, English, as YouTube writes it.
@interface MacLCYouTubeFormat : NSObject
/// "No views", "1 view", "999 views", "1.2K views", "12K views", "1.2M views",
/// "3.4B views" (one decimal below 10, none from 10; "watching" for lives:
/// "1.2K watching").
+ (NSString *)viewCountString:(int64_t)count live:(BOOL)live;
/// "577K subscribers", "1 subscriber", "" when unknown.
+ (NSString *)subscriberCountString:(int64_t)count;
/// "just now", "5 minutes ago", "1 hour ago", "3 days ago", "2 weeks ago",
/// "4 months ago", "1 year ago" (largest whole unit; weeks from 7 days,
/// months from 30 days, years from 365 days).
+ (NSString *)relativeDateString:(NSDate *)date now:(NSDate *)now;
/// "0:42", "12:05", "1:02:03"; "" for 0.
+ (NSString *)durationString:(NSTimeInterval)duration;
/// The line under a card's title: "1.2M views · 3 days ago", parts that are
/// unknown left out; "LIVE · 1.2K watching"; "Upcoming".
+ (NSString *)metadataLineForVideo:(MacLCYouTubeVideo *)video now:(NSDate *)now;
@end

NS_ASSUME_NONNULL_END
