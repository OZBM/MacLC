/*****************************************************************************
 * MacLCWatchPlayback.h: plays a title from Watch, remembers how far it got,
 * and picks it up again where it stopped
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

/* Every place that starts a title from Watch (the stream picker sheet, the
 * Search Add-ons window, the Continue Watching cards) goes through this
 * object instead of adding to the play queue itself, so that:
 *  - the player's time is saved into MacLCWatchLibrary while it plays;
 *  - a title that was left half-way starts there next time, even after the
 *    application was quit and opened again;
 *  - the end of a title marks it watched.
 *
 * It lives in the interface process (AppKit, VLCMain, the player controller),
 * so it is not part of the unit tests; MacLCWatchLibrary is.
 *
 * Binding. -playStream:... remembers a pending context (title, video, stream
 * address). When the player's current media changes to an item whose address
 * matches (compare a normalised key: the info hash after "btih:" for magnet
 * links, otherwise the whole address; MRLs are rewritten by the core, e.g.
 * "magnet:?" becomes "magnet://?"), the context becomes active; a current
 * media that does not match clears it. Only an active context is recorded.
 *
 * Recording. While active, on VLCPlayerTimeAndPositionChanged at most every
 * 5 s of playback time, and at once when the state becomes paused, stopping,
 * stopped or ended, when the current media changes, and when the application
 * terminates (NSApplicationWillTerminateNotification: record the player's
 * live time, then -[MacLCWatchLibrary flush]). The duration is the player's
 * length; while it is unknown nothing is recorded. When the player ends the
 * media by itself (not stopped by the person) the video is marked watched.
 *
 * Starting position. startPosition > 0 is a precise seek sent as soon as the
 * context is bound to the player's current media. Not the "start-time" playback
 * option: VLC 4 clips the timeline to it (length = total − start, times from
 * 0), measured on 2026-10-09. Nothing is recorded until the player's time is
 * within 10 s of startPosition (or 20 s of playback passed), so the seek never
 * overwrites the saved point with 0. The legacy resume dialog
 * (VLCPlaybackContinuityController) only handles file:// items.
 *
 * Failure. A saved stream can be gone (a debrid link expired, no seeder
 * left). If the player reports an error, or goes back to stopped without ever
 * reaching playing, within 45 s of a resume started by -resumeProgress:...,
 * the stream picker (MacLCStreamPickerController) opens for the same title and
 * episode, as a sheet on the library window, so a new version can be chosen;
 * the episode's MacLCAddonVideo is found in the title's meta
 * (MacLCAddonStore fetchMetaForItem:), nil for a movie. */
#import <Foundation/Foundation.h>

@class MacLCAddonItem;
@class MacLCAddonStream;
@class MacLCAddonVideo;
@class MacLCWatchProgress;

NS_ASSUME_NONNULL_BEGIN

@interface MacLCWatchPlayback : NSObject

@property (class, readonly) MacLCWatchPlayback *sharedPlayback;

/// Adds `stream` to the play queue and starts it, recording progress for
/// item/video as long as it plays. startPosition: seconds, 0 for the start.
/// The display name is +[MacLCAddonStore itemNameForItem:video:], as before.
- (void)playStream:(MacLCAddonStream *)stream
              item:(MacLCAddonItem *)item
             video:(nullable MacLCAddonVideo *)video
     startPosition:(NSTimeInterval)startPosition;

/// Same, without queueing a stream the add-on gave: for a saved address.
/// videoIdentifier nil: a movie (the title identifier is used).
- (void)playMRL:(NSString *)MRL
    streamLabel:(nullable NSString *)streamLabel
           item:(MacLCAddonItem *)item
videoIdentifier:(nullable NSString *)videoIdentifier
         season:(NSInteger)season
        episode:(NSInteger)episode
    episodeName:(nullable NSString *)episodeName
  startPosition:(NSTimeInterval)startPosition;

/// Plays again what `progress` was playing, from where it stopped, with the
/// failure fallback described above. NO, and nothing happens, when no stream
/// address was saved (the caller then opens the stream picker).
- (BOOL)resumeProgress:(MacLCWatchProgress *)progress item:(MacLCAddonItem *)item;

/// The Watch title that is playing now (the active context), else nil.
@property (readonly, nullable) MacLCAddonItem *currentItem;
@property (readonly, copy, nullable) NSString *currentVideoIdentifier;
/// "S1, E2 · Pilot" for an episode, nil for a movie or nothing.
@property (readonly, copy, nullable) NSString *currentEpisodeText;

@end

NS_ASSUME_NONNULL_END
