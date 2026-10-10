/*****************************************************************************
 * MacLCWatchLibrary.h: what the person watched, how far, and what they saved
 * for later (history, resume points, favorites) for movies and shows
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

/* Foundation only (plus MacLCAddons.h, also Foundation only): the unit tests
 * link this file on its own. Nothing here touches the player or any view.
 *
 * Storage: one JSON file, written atomically, in
 *   <Application Support>/org.maclc.MacLC/Watch/library.json
 * or, when the environment variable MACLC_WATCH_DATA_DIR is set, in
 *   $MACLC_WATCH_DATA_DIR/library.json
 * (tests and throwaway-profile runs must never touch the real file).
 * Shape (version 1):
 *   { "version": 1,
 *     "titles": [ { "id": "tt0063350", "type": "movie",
 *                   "addon": "<transportUrl>", "meta": { ...catalog entry as the
 *                   add-on sent it (MacLCAddonItem.rawMeta)... },
 *                   "favorite": 1760000000.0 | absent,
 *                   "episodes": [ { "id": "tt1:1:1", "s": 1, "e": 1, "n": "Pilot",
 *                                   "released": 1700000000.0 | absent } ] | absent,
 *                   "progress": [ { "video": "tt1:1:2", "s": 1, "e": 2, "n": "Name",
 *                                   "pos": 123.4, "dur": 2700.0, "watched": true|false,
 *                                   "last": 1760000000.0, "mrl": "...", "label": "..." } ] } ] }
 * Unknown keys are kept when the file is rewritten by this version, a file with
 * a higher "version" is left untouched (the library then works in memory only).
 *
 * Threading: every method is main-thread only, except -flush, which may be
 * called from any thread. Writes are coalesced (at most one per 1.5 s, on a
 * background queue) and -flush writes synchronously. */
#import <Foundation/Foundation.h>

@class MacLCAddonItem;
@class MacLCAddonVideo;

NS_ASSUME_NONNULL_BEGIN

/// Posted on the main queue, at most once per 2 s, after history or favorites
/// changed. object: the library. userInfo[MacLCWatchLibraryChangedTitlesKey]:
/// NSSet<NSString *> of the title identifiers that changed, absent when
/// "everything" (clear, load).
extern NSNotificationName const MacLCWatchLibraryDidChangeNotification;
extern NSString * const MacLCWatchLibraryChangedTitlesKey;

/// A video counts as watched from this fraction of its duration on (0.92):
/// the credits are unknown, 8 % of a film is about 8 minutes of them.
FOUNDATION_EXPORT const double MacLCWatchedFraction;
/// Shorter than this (seconds) is a mis-click, not worth remembering (15).
FOUNDATION_EXPORT const NSTimeInterval MacLCWatchMinimumPosition;

#pragma mark - Progress

/// How far one video (a movie, or one episode) was watched. Immutable snapshot.
@interface MacLCWatchProgress : NSObject
@property (readonly, copy) NSString *titleIdentifier;
/// The add-on's video id: the title id for a movie, "tt0944947:1:2" for an episode.
@property (readonly, copy) NSString *videoIdentifier;
/// 0 for a movie.
@property (readonly) NSInteger season;
@property (readonly) NSInteger episode;
@property (readonly, copy, nullable) NSString *episodeName;
/// Seconds.
@property (readonly) NSTimeInterval position;
/// Seconds; 0 when it was never known.
@property (readonly) NSTimeInterval duration;
/// position / duration clamped to 0...1; 0 when the duration is unknown;
/// 1 when watched.
@property (readonly) double fraction;
/// Seconds left; 0 when the duration is unknown.
@property (readonly) NSTimeInterval remaining;
@property (readonly, getter=isWatched) BOOL watched;
@property (readonly) NSDate *lastPlayed;
/// What was playing (a magnet link, an address): resuming plays it again
/// without choosing a version. nil for progress made by hand (marked watched).
@property (readonly, copy, nullable) NSString *streamMRL;
/// "1080p · Torrentio", shown on the resume card; nil when unknown.
@property (readonly, copy, nullable) NSString *streamLabel;
/// Not watched, at least MacLCWatchMinimumPosition in, and (duration unknown or
/// at least 30 s left).
@property (readonly) BOOL canResume;
@end

#pragma mark - Resume target

typedef NS_ENUM(NSInteger, MacLCWatchResumeKind) {
    /// Pick up a video where it stopped.
    MacLCWatchResumeKindResume,
    /// A show's next episode, the last one being watched.
    MacLCWatchResumeKindNextUp,
};

/// What a "Continue Watching" card plays.
@interface MacLCWatchResumeTarget : NSObject
@property (readonly) MacLCWatchResumeKind kind;
@property (readonly, copy) NSString *videoIdentifier;
@property (readonly) NSInteger season;
@property (readonly) NSInteger episode;
@property (readonly, copy, nullable) NSString *episodeName;
/// Set for MacLCWatchResumeKindResume; nil for next up.
@property (readonly, nullable) MacLCWatchProgress *progress;
/// "S1, E3 · 23 min left", "Next: S1, E4 · Pilot", "1 h 12 min left" (movie),
/// "Resume" when the duration is unknown. English, short, one line.
@property (readonly, copy) NSString *detailText;
@end

#pragma mark - Entry

/// One title the person watched or saved. Immutable snapshot, rebuilt after
/// each change; hold the identifier, not the entry.
@interface MacLCWatchEntry : NSObject
/// Rebuilt from the stored catalog entry: feed it to MacLCWatchPosterItem.
@property (readonly) MacLCAddonItem *item;
@property (readonly, copy) NSString *identifier;
/// "movie" or "series" (what the add-on calls it).
@property (readonly, copy) NSString *type;
@property (readonly, getter=isFavorite) BOOL favorite;
/// When it was added to Favorites.
@property (readonly, nullable) NSDate *favoriteDate;
/// The last time any video of it played; nil when only a favorite.
@property (readonly, nullable) NSDate *lastPlayed;
/// Newest first.
@property (readonly, copy) NSArray<MacLCWatchProgress *> *allProgress;
/// The most recently played video; nil when none.
@property (readonly, nullable) MacLCWatchProgress *latestProgress;
/// Movie: its progress is watched. Show: the episode list is known (see
/// -updateEpisodes:forItem:) and every released episode of a numbered season
/// (season 1 and up) is watched.
@property (readonly, getter=isWatched) BOOL watched;
/// Movie in progress: its fraction. Otherwise 0.
@property (readonly) double fraction;
/// Episodes (numbered seasons) marked watched.
@property (readonly) NSUInteger watchedEpisodeCount;
/// Nil when there is nothing to continue.
@property (readonly, nullable) MacLCWatchResumeTarget *resumeTarget;
@end

#pragma mark - Library

@interface MacLCWatchLibrary : NSObject

@property (class, readonly) MacLCWatchLibrary *sharedLibrary;

/// The file is created on the first change. A missing, empty or unreadable
/// file is an empty library (the unreadable one is renamed library.json.bad
/// first, once, so nothing is lost silently).
- (instancetype)initWithFileURL:(NSURL *)fileURL NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

#pragma mark Lookup

- (nullable MacLCWatchEntry *)entryForTitle:(NSString *)titleIdentifier;
/// videoIdentifier nil: the title's most recent video (a movie's only one).
- (nullable MacLCWatchProgress *)progressForTitle:(NSString *)titleIdentifier
                                            video:(nullable NSString *)videoIdentifier;

#pragma mark Recording

/// Called every few seconds while a video plays. Creates the title when new
/// (item is stored in full), updates the video's progress, and marks it
/// watched from MacLCWatchedFraction on. Ignored while position <
/// MacLCWatchMinimumPosition and the video has no progress yet. Does not
/// resurrect a video the person marked unwatched until it plays again from 0.
/// A watched video stays watched (only lastPlayed, stream and label update)
/// unless the save is below MacLCWatchMinimumPosition: a restart from the
/// beginning clears "watched" and the video is tracked normally again (resume
/// point, Continue Watching, watched again from MacLCWatchedFraction).
/// Show-wide data (season, episode, name) is taken from video when given.
- (void)recordPosition:(NSTimeInterval)position
              duration:(NSTimeInterval)duration
               forItem:(MacLCAddonItem *)item
       videoIdentifier:(nullable NSString *)videoIdentifier
                season:(NSInteger)season
               episode:(NSInteger)episode
           episodeName:(nullable NSString *)episodeName
             streamMRL:(nullable NSString *)streamMRL
           streamLabel:(nullable NSString *)streamLabel;
/// Convenience: season, episode, name and identifier from `video` (nil: a movie).
- (void)recordPosition:(NSTimeInterval)position
              duration:(NSTimeInterval)duration
               forItem:(MacLCAddonItem *)item
                 video:(nullable MacLCAddonVideo *)video
             streamMRL:(nullable NSString *)streamMRL
           streamLabel:(nullable NSString *)streamLabel;

/// YES: watched through (position = duration when known), NO: forgotten
/// (progress removed; the title leaves the history when it has no other
/// progress). video nil: the movie.
- (void)markWatched:(BOOL)watched forItem:(MacLCAddonItem *)item video:(nullable MacLCAddonVideo *)video;
/// Same for several episodes at once (a whole season).
- (void)markWatched:(BOOL)watched forItem:(MacLCAddonItem *)item videos:(NSArray<MacLCAddonVideo *> *)videos;

/// Remembers a show's episodes (from its meta) so that completeness and "next
/// up" can be computed offline. Call whenever the title page loads them.
/// Ignored for movies and empty lists.
- (void)updateEpisodes:(NSArray<MacLCAddonVideo *> *)videos forItem:(MacLCAddonItem *)item;

/// Forgets every progress of the title; a favorite stays one.
- (void)removeFromHistory:(NSString *)titleIdentifier;
- (void)clearHistory;

#pragma mark Lists

/// Titles with progress, most recently played first.
@property (readonly, copy) NSArray<MacLCWatchEntry *> *historyEntries;
/// Titles with a resume target, most recently played first, at most 30.
@property (readonly, copy) NSArray<MacLCWatchEntry *> *continueWatchingEntries;
/// Favorites, most recently added first.
@property (readonly, copy) NSArray<MacLCWatchEntry *> *favoriteEntries;

#pragma mark Favorites

- (BOOL)isFavorite:(NSString *)titleIdentifier;
/// Adds the title (item stored in full) or removes the flag; a title with no
/// progress and no flag is dropped from the file.
- (void)setFavorite:(BOOL)favorite forItem:(MacLCAddonItem *)item;
- (void)clearFavorites;

#pragma mark Persistence

/// Writes now, synchronously, if anything is pending. Any thread.
- (void)flush;

@end

NS_ASSUME_NONNULL_END
