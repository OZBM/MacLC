/*****************************************************************************
 * MacLCYouTubeService.h: YouTube lists and details through yt-dlp, with a
 * cache, and playback through MacLC's own player
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

/* The extractor is the one File ▸ Open Web Video uses
 * (MacLCWebVideoResolver.sharedResolver.extractorPath): yt-dlp, found by
 * absolute path because a Finder-launched app has no Homebrew PATH. Every
 * call runs `yt-dlp --ignore-config --no-warnings --no-progress
 * --socket-timeout 15 -J [--flat-playlist --playlist-end <limit>]
 * <MacLCYouTubeAccount extractorArguments> -- <target>` as an NSTask off the
 * main thread (at most 4 at a time, the rest queued, newest first), parses
 * stdout with MacLCYouTubeParser, and completes on the main queue.
 * Cancelling terminates the task; a cancelled request never completes.
 *
 * Errors (stderr's last "ERROR:" line decides):
 *   "Login details are needed", "Sign in to confirm", "This video is
 *   private", HTTP 401, and "The playlist does not exist" for WL/LL while
 *   signed out        -> MacLCYouTubeErrorSignInRequired
 *   "Unable to download", "timed out", "Temporary failure in name resolution",
 *   "nodename nor servname" -> MacLCYouTubeErrorNetwork
 *   anything else      -> MacLCYouTubeErrorExtractorFailed, with that line
 *                         (without "ERROR: [extractor] ") as the description.
 *
 * Cache: memory, and disk in <Caches>/org.maclc.MacLC/YouTube/<key hash>.json
 * (the raw yt-dlp JSON). Fresh for 15 min (home, feeds, search), 1 h
 * (channels, playlists), 24 h (video details). A fresh entry completes at
 * once (next run loop turn) without a task. -invalidateCache clears both;
 * MacLCYouTubeAccountDidChangeNotification invalidates by itself.
 *
 * Region and language: lists are asked in the person's first preferred
 * language (NSLocale.preferredLanguages, "fr" from "fr-FR") with
 * --extractor-args "youtube:lang=<code>".
 *
 * Developer hook: MACLC_DEBUG_YOUTUBE_FIXTURES=<dir> replaces every task by
 * reading <dir>/<request key>.json (keys below), with a 300 ms delay, so the
 * views can be checked without network or account; a missing file is a
 * MacLCYouTubeErrorNetwork error. Keys: "home-<category id>",
 * "feed-recommended", "feed-subscriptions", "feed-history", "feed-watchlater",
 * "feed-liked", "feed-playlists", "search-<filter>-<query, lowercased,
 * spaces as _>", "channel-<channel id or handle without @>-<tab>",
 * "playlist-<id>", "video-<id>". */
#import <Foundation/Foundation.h>

#import "youtube/MacLCYouTubeModel.h"

NS_ASSUME_NONNULL_BEGIN

extern NSErrorDomain const MacLCYouTubeErrorDomain;
typedef NS_ERROR_ENUM(MacLCYouTubeErrorDomain, MacLCYouTubeError) {
    /// No yt-dlp on this Mac.
    MacLCYouTubeErrorExtractorMissing = 1,
    MacLCYouTubeErrorExtractorFailed = 2,
    /// The list needs an account (signed out, or the account's cookies were refused).
    MacLCYouTubeErrorSignInRequired = 3,
    MacLCYouTubeErrorNetwork = 4,
    /// Not the JSON expected.
    MacLCYouTubeErrorBadResponse = 5,
    /// --cookies-from-browser could not read the browser's cookies (Safari
    /// without Full Disk Access, a Chromium Keychain refusal, no profile).
    MacLCYouTubeErrorBrowserCookies = 6,
};

/// The person's own lists. All of them need an account.
typedef NS_ENUM(NSInteger, MacLCYouTubeFeed) {
    MacLCYouTubeFeedRecommended,    // ":ytrec"
    MacLCYouTubeFeedSubscriptions,  // ":ytsubs"
    MacLCYouTubeFeedHistory,        // ":ythis"
    MacLCYouTubeFeedWatchLater,     // ":ytwatchlater"
    MacLCYouTubeFeedLiked,          // https://www.youtube.com/playlist?list=LL
    MacLCYouTubeFeedPlaylists,      // https://www.youtube.com/feed/playlists (results are playlists)
};

typedef NS_ENUM(NSInteger, MacLCYouTubeSearchFilter) {
    MacLCYouTubeSearchFilterAll,
    MacLCYouTubeSearchFilterVideos,
    MacLCYouTubeSearchFilterChannels,
    MacLCYouTubeSearchFilterPlaylists,
};

typedef NS_ENUM(NSInteger, MacLCYouTubeChannelTab) {
    MacLCYouTubeChannelTabVideos,     // <channel>/videos
    MacLCYouTubeChannelTabLive,       // <channel>/streams
    MacLCYouTubeChannelTabPlaylists,  // <channel>/playlists
};

/// A topic of Home (YouTube's "chips"). Signed out, each one is a search of
/// popular recent videos about it, worded in the person's language.
@interface MacLCYouTubeCategory : NSObject
/// "all", "music", "gaming", "news", "sports", "movies", "learning",
/// "technology", "cooking", "travel", "podcasts", "live".
@property (readonly, copy) NSString *identifier;
/// "All", "Music", "Gaming", "News", "Sports", "Movies & Trailers",
/// "Learning", "Technology", "Cooking", "Travel", "Podcasts", "Live".
@property (readonly, copy) NSString *title;
/// The categories, "All" first.
@property (class, readonly, copy) NSArray<MacLCYouTubeCategory *> *homeCategories;
@end

/// Cancels one call; a cancelled call's completion never runs.
@interface MacLCYouTubeRequest : NSObject
- (void)cancel;
@end

typedef void (^MacLCYouTubePageCompletion)(MacLCYouTubePage * _Nullable page, NSError * _Nullable error);

@interface MacLCYouTubeService : NSObject

@property (class, readonly) MacLCYouTubeService *sharedService;

/// yt-dlp was found (re-checked on each call, cheap).
@property (readonly, getter=isExtractorAvailable) BOOL extractorAvailable;

/// Home. category nil or "all": signed in, the account's recommendations
/// (feed Recommended); signed out, popular recent videos across several
/// topics (4 searches of 12 run together, interleaved, duplicates removed).
/// Another category: popular recent videos about it.
- (MacLCYouTubeRequest *)homeForCategory:(nullable MacLCYouTubeCategory *)category
                                   limit:(NSUInteger)limit
                              completion:(MacLCYouTubePageCompletion)completion;

- (MacLCYouTubeRequest *)feed:(MacLCYouTubeFeed)feed
                        limit:(NSUInteger)limit
                   completion:(MacLCYouTubePageCompletion)completion;

/// https://www.youtube.com/results?search_query=<q>[&sp=<filter>].
- (MacLCYouTubeRequest *)search:(NSString *)query
                         filter:(MacLCYouTubeSearchFilter)filter
                          limit:(NSUInteger)limit
                     completion:(MacLCYouTubePageCompletion)completion;

/// A channel's tab; page.channel describes the channel.
- (MacLCYouTubeRequest *)channel:(NSURL *)channelURL
                             tab:(MacLCYouTubeChannelTab)tab
                           limit:(NSUInteger)limit
                      completion:(MacLCYouTubePageCompletion)completion;

- (MacLCYouTubeRequest *)playlist:(NSURL *)playlistURL
                            limit:(NSUInteger)limit
                       completion:(MacLCYouTubePageCompletion)completion;

/// The full description of one video (no --flat-playlist).
- (MacLCYouTubeRequest *)detailsForVideo:(MacLCYouTubeVideo *)video
                              completion:(void (^)(MacLCYouTubeVideo * _Nullable video, NSError * _Nullable error))completion;

/// Plays now (enqueue NO: through MacLCWebVideoResolver, as Open Web Video
/// does, with the account's cookies, then the play queue starts it), or adds
/// to the end of the queue (enqueue YES: the watch address as MRL, which the
/// ytdl demuxer resolves when its turn comes). completion: nil error once
/// handed to the queue; the resolver's error otherwise. Main queue.
- (void)playVideo:(MacLCYouTubeVideo *)video
          enqueue:(BOOL)enqueue
       completion:(nullable void (^)(NSError * _Nullable error))completion;
/// Plays now from startTime seconds (a chapter): the resolved item gets the
/// playback option "start-time=<seconds>".
- (void)playVideo:(MacLCYouTubeVideo *)video
        startTime:(NSTimeInterval)startTime
       completion:(nullable void (^)(NSError * _Nullable error))completion;
/// "Play All": the first through the resolver, the rest queued after it.
- (void)playVideos:(NSArray<MacLCYouTubeVideo *> *)videos
   startingAtIndex:(NSUInteger)index
        completion:(nullable void (^)(NSError * _Nullable error))completion;

- (void)invalidateCache;

@end

NS_ASSUME_NONNULL_END
