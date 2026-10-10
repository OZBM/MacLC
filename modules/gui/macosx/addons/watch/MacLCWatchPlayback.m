/*****************************************************************************
 * MacLCWatchPlayback.m: plays a title from Watch, remembers how far it got,
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

#import "addons/watch/MacLCWatchPlayback.h"

#import "addons/MacLCAddons.h"
#import "addons/MacLCStreamFacts.h"
#import "addons/watch/MacLCStreamPicker.h"
#import "addons/watch/MacLCWatchLibrary.h"
#import "library/VLCInputItem.h"
#import "library/VLCLibraryWindow.h"
#import "main/VLCMain.h"
#import "playqueue/VLCPlayQueueController.h"
#import "playqueue/VLCPlayerController.h"
#import "windows/VLCOpenInputMetadata.h"

#import <Cocoa/Cocoa.h>

/* getIntf() is NULL once the interface is closed: nothing below may talk to
 * the player or log through it after that. */
#define WATCH_DBG(...) \
    do { \
        intf_thread_t * const watch_intf__ = getIntf(); \
        if (watch_intf__ != NULL) \
            msg_Dbg(watch_intf__, __VA_ARGS__); \
    } while (0)

/// A resume that has not started playing within this many seconds failed.
static const NSTimeInterval MacLCWatchResumeTimeout = 45.0;
/// A resume whose seek never landed records anyway after this much playback.
static const NSTimeInterval MacLCWatchSeekGrace = 20.0;
/// A resume records once the player's time is within this of its start position.
static const NSTimeInterval MacLCWatchSeekWindow = 10.0;
/// A time sample this far from where playback should be is a seek.
static const NSTimeInterval MacLCWatchSeekDeviation = 3.0;
/// Playback time after a seek during which a position at the end is not trusted.
static const NSTimeInterval MacLCWatchSeekSettle = 10.0;
/// Playback time between two saves.
static const NSTimeInterval MacLCWatchSaveInterval = 5.0;
/// A position this close to the end of a stream that ended by itself is "watched".
static const double MacLCWatchEndedFraction = 0.8;
/// A pending title that no media change picked up after this long is dropped
/// when another media starts (younger ones may be racing a stale notification).
static const NSTimeInterval MacLCWatchPendingGrace = 3.0;

static inline NSTimeInterval WatchSeconds(vlc_tick_t tick)
{
    return (double)tick / (double)CLOCK_FREQ;
}

#pragma mark - Address key

/* 20 bytes as 40 lowercase hex digits from the 32 base32 characters of a
 * magnet link's info hash; nil when a character is not base32. */
static NSString *WatchHexFromBase32(NSString *string)
{
    NSMutableString * const hex = [NSMutableString stringWithCapacity:40];
    uint64_t buffer = 0;
    int bits = 0;
    for (NSUInteger i = 0; i < string.length; i++) {
        const unichar c = [string characterAtIndex:i];
        int value;
        if (c >= 'A' && c <= 'Z') {
            value = c - 'A';
        } else if (c >= 'a' && c <= 'z') {
            value = c - 'a';
        } else if (c >= '2' && c <= '7') {
            value = c - '2' + 26;
        } else {
            return nil;
        }
        buffer = (buffer << 5) | (uint64_t)value;
        bits += 5;
        if (bits >= 8) {
            bits -= 8;
            [hex appendFormat:@"%02x", (unsigned)((buffer >> bits) & 0xFF)];
            buffer &= ((uint64_t)1 << bits) - 1;
        }
    }
    return hex;
}

/* What two spellings of the same stream have in common: the info hash for a
 * magnet link ("magnet:?" becomes "magnet://?" in the core, the hash can be
 * hex or base32, upper or lower case, the "#!/file" fragment is not part of
 * the torrent), the whole address otherwise (percent-decoded). */
static NSString *WatchKeyForMRL(NSString *MRL)
{
    if (MRL.length == 0) {
        return nil;
    }
    static NSRegularExpression *btih;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        btih = [NSRegularExpression regularExpressionWithPattern:@"urn(?::|%3A)btih(?::|%3A)([A-Za-z0-9]{32,40})(?![A-Za-z0-9])"
                                                         options:NSRegularExpressionCaseInsensitive
                                                           error:NULL];
    });
    NSTextCheckingResult * const match = [btih firstMatchInString:MRL options:0 range:NSMakeRange(0, MRL.length)];
    if (match != nil) {
        NSString * const hash = [MRL substringWithRange:[match rangeAtIndex:1]];
        NSString * const hex = (hash.length == 32) ? WatchHexFromBase32(hash) : nil;
        return [@"btih:" stringByAppendingString:hex ?: hash.lowercaseString];
    }
    return MRL.stringByRemovingPercentEncoding ?: MRL;
}

#pragma mark - Context

/* One title being played (or about to be) and what is known of how it goes.
 * Main thread only. */
@interface MacLCWatchContext : NSObject
@property (nonatomic, strong) MacLCAddonItem *item;
@property (nonatomic, copy, nullable) NSString *videoIdentifier;
@property (nonatomic) NSInteger season;
@property (nonatomic) NSInteger episode;
@property (nonatomic, copy, nullable) NSString *episodeName;
@property (nonatomic, copy) NSString *MRL;
@property (nonatomic, copy) NSString *key;
@property (nonatomic, copy, nullable) NSString *streamLabel;
@property (nonatomic) NSTimeInterval startPosition;
/// Started by -resumeProgress:item: (a saved stream address): the failure fallback applies.
@property (nonatomic) BOOL isResume;
@property (nonatomic, strong) NSDate *startedAt;

/// The core's input item (compared as a number, never dereferenced): tells
/// the events of this media from those of the one it replaced.
@property (nonatomic) uintptr_t inputItemID;
/// The player's time when this context was bound or restarted: still the
/// previous media's until the first timer point of this one arrives.
@property (nonatomic) vlc_tick_t baselineTick;
/// A time sample of this media was seen.
@property (nonatomic) BOOL timeFresh;
/// Playback started (a fresh sample or the PLAYING state).
@property (nonatomic) BOOL playing;
/// The position is far enough to be recorded (see armThreshold).
@property (nonatomic) BOOL armed;
/// Stopped, ended or failed: samples are ignored until it plays again.
@property (nonatomic) BOOL stopped;
@property (nonatomic) BOOL fallbackDone;
@property (nonatomic) NSTimeInterval armThreshold;
/// Time of the first fresh sample.
@property (nonatomic) NSTimeInterval firstTime;
/// Seek detection: wall clock and play state of the previous sample, the
/// media time a detected seek landed on, and whether it is still recent.
@property (nonatomic) CFAbsoluteTime lastSampleWall;
@property (nonatomic) BOOL lastSampleWasPlaying;
@property (nonatomic) NSTimeInterval seekTime;
@property (nonatomic) BOOL afterSeek;
@property (nonatomic) NSTimeInterval lastTime;
@property (nonatomic) NSTimeInterval lastDuration;
@property (nonatomic) NSTimeInterval lastSavedTime;

- (void)resetTrackingWithBaseline:(vlc_tick_t)baseline;
@end

@implementation MacLCWatchContext

- (void)resetTrackingWithBaseline:(vlc_tick_t)baseline
{
    _baselineTick = baseline;
    _timeFresh = NO;
    _playing = NO;
    _stopped = NO;
    _lastTime = 0;
    _lastDuration = 0;
    _lastSavedTime = -1000.0;
    _lastSampleWall = 0;
    _afterSeek = NO;
    /* A new title waits for MacLCWatchMinimumPosition, so that a mis-click
     * never replaces a saved position. A resume waits until the seek to its
     * start position landed (the first samples may be at 0), so that it
     * never replaces the saved position with a smaller one (the library
     * updates an existing progress at any position); after
     * MacLCWatchSeekGrace of playback it records anyway, the person may
     * have gone back on purpose. */
    _armThreshold = _startPosition > 0 ? MAX(0.0, _startPosition - MacLCWatchSeekWindow) : MacLCWatchMinimumPosition;
    _armed = NO;
}

@end

@interface MacLCWatchPlayback ()
- (void)mediaStopping:(uintptr_t)identifier reason:(enum vlc_player_media_stopping_reason)reason;
@end

#pragma mark - Player callback

/* The player's reason for stopping a media (end of stream, the person, an
 * error) is not forwarded by VLCPlayerController: listen to it directly. It
 * is delivered before the state change it causes, and the main queue keeps
 * that order. */
static void WatchPlayerMediaStopping(vlc_player_t *player, input_item_t *media,
                                     enum vlc_player_media_stopping_reason reason, void *data)
{
    VLC_UNUSED(player);
    VLC_UNUSED(data);
    const uintptr_t identifier = (uintptr_t)media;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (getIntf() == NULL) {
            return;
        }
        [MacLCWatchPlayback.sharedPlayback mediaStopping:identifier reason:reason];
    });
}

static const struct vlc_player_cbs watch_player_callbacks = {
    .on_stopping_current_media = WatchPlayerMediaStopping,
};

#pragma mark - Playback

@implementation MacLCWatchPlayback
{
    MacLCWatchContext *_pending;
    MacLCWatchContext *_active;
    vlc_player_t *_vlcPlayer;
    vlc_player_listener_id *_listenerID;
    MacLCAddonRequest *_metaRequest;
    MacLCStreamPickerController *_fallbackPicker;
}

+ (MacLCWatchPlayback *)sharedPlayback
{
    static MacLCWatchPlayback *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        shared = [[MacLCWatchPlayback alloc] init];
    });
    return shared;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        NSNotificationCenter * const center = NSNotificationCenter.defaultCenter;
        [center addObserver:self selector:@selector(currentMediaChanged:) name:VLCPlayerCurrentMediaItemChanged object:nil];
        [center addObserver:self selector:@selector(stateChanged:) name:VLCPlayerStateChanged object:nil];
        [center addObserver:self selector:@selector(errorChanged:) name:VLCPlayerErrorChanged object:nil];
        [center addObserver:self selector:@selector(timeChanged:) name:VLCPlayerTimeAndPositionChanged object:nil];
        [center addObserver:self selector:@selector(applicationWillTerminate:) name:NSApplicationWillTerminateNotification object:nil];
    }
    return self;
}

#pragma mark Current title

- (MacLCAddonItem *)currentItem
{
    return _active.item;
}

- (NSString *)currentVideoIdentifier
{
    return _active.videoIdentifier;
}

- (NSString *)currentEpisodeText
{
    MacLCWatchContext * const ctx = _active;
    if (ctx == nil || (ctx.season <= 0 && ctx.episode <= 0)) {
        return nil;
    }
    NSString * const base = [NSString stringWithFormat:@"S%ld, E%ld", (long)ctx.season, (long)ctx.episode];
    return ctx.episodeName.length > 0 ? [NSString stringWithFormat:@"%@ · %@", base, ctx.episodeName] : base;
}

#pragma mark Starting

static NSString *WatchStreamLabel(MacLCAddonStream *stream)
{
    NSString * const resolution = [MacLCStreamFacts nameForResolution:[MacLCStreamFacts factsForStream:stream].resolution];
    NSString * const addon = stream.addon.name;
    if ([resolution isEqualToString:@"Unknown"] || resolution.length == 0) {
        return addon.length > 0 ? addon : nil;
    }
    return addon.length > 0 ? [NSString stringWithFormat:@"%@ · %@", resolution, addon] : resolution;
}

/* The name MacLCAddonStore gives, for an episode known by numbers only. */
static NSString *WatchItemName(MacLCAddonItem *item, NSInteger season, NSInteger episode, NSString *episodeName)
{
    if (season <= 0 && episode <= 0) {
        return [MacLCAddonStore itemNameForItem:item video:nil];
    }
    if (episodeName.length > 0) {
        return [NSString stringWithFormat:@"%@ — S%ldE%ld · %@", item.name, (long)season, (long)episode, episodeName];
    }
    return [NSString stringWithFormat:@"%@ — S%ldE%ld", item.name, (long)season, (long)episode];
}

- (void)playStream:(MacLCAddonStream *)stream
              item:(MacLCAddonItem *)item
             video:(MacLCAddonVideo *)video
     startPosition:(NSTimeInterval)startPosition
{
    MacLCWatchContext * const ctx = [[MacLCWatchContext alloc] init];
    ctx.item = item;
    ctx.videoIdentifier = video.identifier;
    ctx.season = video.season;
    ctx.episode = video.episode;
    ctx.episodeName = video.name;
    ctx.MRL = stream.MRL;
    ctx.streamLabel = WatchStreamLabel(stream);
    ctx.startPosition = startPosition;
    [self startContext:ctx displayName:[MacLCAddonStore itemNameForItem:item video:video]];
}

- (void)playMRL:(NSString *)MRL
    streamLabel:(NSString *)streamLabel
           item:(MacLCAddonItem *)item
videoIdentifier:(NSString *)videoIdentifier
         season:(NSInteger)season
        episode:(NSInteger)episode
    episodeName:(NSString *)episodeName
  startPosition:(NSTimeInterval)startPosition
{
    MacLCWatchContext * const ctx = [[MacLCWatchContext alloc] init];
    ctx.item = item;
    ctx.videoIdentifier = videoIdentifier;
    ctx.season = season;
    ctx.episode = episode;
    ctx.episodeName = episodeName;
    ctx.MRL = MRL;
    ctx.streamLabel = streamLabel;
    ctx.startPosition = startPosition;
    [self startContext:ctx displayName:WatchItemName(item, season, episode, episodeName)];
}

- (BOOL)resumeProgress:(MacLCWatchProgress *)progress item:(MacLCAddonItem *)item
{
    if (progress.streamMRL.length == 0 || getIntf() == NULL || VLCMain.sharedInstance.isTerminating) {
        return NO;
    }
    const BOOL movie = [progress.videoIdentifier isEqualToString:progress.titleIdentifier];
    MacLCWatchContext * const ctx = [[MacLCWatchContext alloc] init];
    ctx.item = item;
    ctx.videoIdentifier = movie ? nil : progress.videoIdentifier;
    ctx.season = progress.season;
    ctx.episode = progress.episode;
    ctx.episodeName = progress.episodeName;
    ctx.MRL = progress.streamMRL;
    ctx.streamLabel = progress.streamLabel;
    /* A watched video starts over; only a half-watched one resumes (and can fail). */
    ctx.startPosition = progress.canResume ? progress.position : 0;
    ctx.isResume = progress.canResume;
    [self startContext:ctx displayName:WatchItemName(item, progress.season, progress.episode, progress.episodeName)];
    return YES;
}

- (void)startContext:(MacLCWatchContext *)ctx displayName:(NSString *)displayName
{
    if (ctx.MRL.length == 0 || getIntf() == NULL || VLCMain.sharedInstance.isTerminating) {
        return;
    }
    [self ensureListening];

    ctx.key = WatchKeyForMRL(ctx.MRL);
    ctx.startedAt = [NSDate date];
    [ctx resetTrackingWithBaseline:VLC_TICK_INVALID];
    _pending = ctx;

    VLCOpenInputMetadata * const meta = [[VLCOpenInputMetadata alloc] init];
    meta.MRLString = ctx.MRL;
    meta.itemName = displayName;
    /* No "start-time" option: it makes the core clip the timeline (length and
     * times then start at 0). The seek is made once the media is current. */
    WATCH_DBG("watch: play \"%s\" (%s) key %s from %.0f s%s",
              ctx.item.name.UTF8String ?: "", ctx.videoIdentifier.UTF8String ?: "movie",
              ctx.key.UTF8String ?: "", ctx.startPosition, ctx.isResume ? " (resume)" : "");

    [VLCMain.sharedInstance.playQueueController addPlayQueueItems:@[meta]
                                                       atPosition:(size_t)-1
                                                    startPlayback:YES];

    if (ctx.isResume) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(MacLCWatchResumeTimeout * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [self resumeTimeoutForContext:ctx];
        });
    }
}

- (void)ensureListening
{
    if (_listenerID != NULL || getIntf() == NULL) {
        return;
    }
    vlc_player_t * const player = vlc_playlist_GetPlayer(VLCMain.sharedInstance.playQueueController.p_playlist);
    if (player == NULL) {
        return;
    }
    vlc_player_Lock(player);
    _listenerID = vlc_player_AddListener(player, &watch_player_callbacks, NULL);
    vlc_player_Unlock(player);
    _vlcPlayer = player;
}

#pragma mark Binding

- (void)currentMediaChanged:(NSNotification *)notification
{
    if (getIntf() == NULL || (_pending == nil && _active == nil)) {
        return;
    }
    VLCPlayerController * const player = notification.object;
    VLCInputItem * const media = player.currentMedia;
    NSString * const key = WatchKeyForMRL(media.MRL);

    MacLCWatchContext * const old = _active;
    MacLCWatchContext *next = nil;
    if (key != nil) {
        if (_pending != nil && [_pending.key isEqualToString:key]) {
            next = _pending;
            _pending = nil;
        } else if (old != nil && old.stopped && [old.key isEqualToString:key]) {
            /* The same stream played again from the queue: from the start. */
            next = old;
            next.startPosition = 0;
        }
    }
    if (old != nil && !old.stopped) {
        [self saveContext:old why:"media change"];
    }
    if (next == nil && _pending != nil && -[_pending.startedAt timeIntervalSinceNow] > MacLCWatchPendingGrace) {
        WATCH_DBG("watch: \"%s\" not played: current media %s does not match",
                  _pending.item.name.UTF8String ?: "", key.UTF8String ?: "(none)");
        _pending = nil;
    }

    _active = next;
    if (next != nil) {
        [next resetTrackingWithBaseline:player.time];
        next.inputItemID = (uintptr_t)media.vlcInputItem;
        if (next.startPosition > 0) {
            /* Precise: the person wants the exact spot. Queued on the input,
             * which runs it once it is open; absolute length and times. */
            [player setTimePrecise:(vlc_tick_t)(next.startPosition * CLOCK_FREQ)];
            WATCH_DBG("watch: seeking to %.0f s", next.startPosition);
        }
        WATCH_DBG("watch: bound \"%s\" (%s) to the player", next.item.name.UTF8String ?: "",
                  next.videoIdentifier.UTF8String ?: "movie");
    }
}

#pragma mark Recording

/* Reads the player's time and length into the context. NO while no time of
 * this media was seen (nothing started, or the time is still the previous
 * media's). */
- (BOOL)sampleContext:(MacLCWatchContext *)ctx fromPlayer:(VLCPlayerController *)player
{
    const enum vlc_player_state state = player.playerState;
    const vlc_tick_t tick = player.time;
    if ((state != VLC_PLAYER_STATE_PLAYING && state != VLC_PLAYER_STATE_PAUSED)
        || tick == VLC_TICK_INVALID || tick < 0) {
        return NO;
    }
    if (!ctx.timeFresh) {
        /* The same time as at binding is the previous media's; a time far
         * beyond the start is its tail, still ticking while it winds down. */
        if (tick == ctx.baselineTick || WatchSeconds(tick) > ctx.startPosition + 120.0) {
            return NO;
        }
        ctx.timeFresh = YES;
        ctx.playing = YES;
        ctx.firstTime = WatchSeconds(tick);
    }
    vlc_tick_t length = player.length;
    if (length <= 0) {
        length = player.durationOfCurrentMediaItem;
    }
    /* A sample far from previous sample + elapsed time x rate is a seek (a
     * scrub through the end must not look like having watched it). */
    const NSTimeInterval time = WatchSeconds(tick);
    const CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    if (ctx.lastSampleWall > 0) {
        const NSTimeInterval elapsed = ctx.lastSampleWasPlaying ? (now - ctx.lastSampleWall) * MAX(player.playbackRate, 0.0f) : 0.0;
        if (fabs(time - (ctx.lastTime + elapsed)) > MacLCWatchSeekDeviation) {
            ctx.seekTime = time;
            ctx.afterSeek = YES;
        }
    }
    if (ctx.afterSeek && time - ctx.seekTime >= MacLCWatchSeekSettle) {
        ctx.afterSeek = NO;
    }
    ctx.lastSampleWall = now;
    ctx.lastSampleWasPlaying = (state == VLC_PLAYER_STATE_PLAYING);
    ctx.lastTime = time;
    if (length > 0) {
        ctx.lastDuration = WatchSeconds(length);
    }
    if (!ctx.armed && (ctx.lastTime >= ctx.armThreshold
                       || (ctx.startPosition > 0 && ctx.lastTime - ctx.firstTime >= MacLCWatchSeekGrace))) {
        ctx.armed = YES;
    }
    return YES;
}

- (void)saveContext:(MacLCWatchContext *)ctx why:(const char *)why
{
    if (!ctx.armed || ctx.lastDuration <= 0 || ctx.lastTime == ctx.lastSavedTime) {
        return;
    }
    ctx.lastSavedTime = ctx.lastTime;
    const NSTimeInterval position = MIN(ctx.lastTime, ctx.lastDuration);
    if (ctx.afterSeek && position >= MacLCWatchedFraction * ctx.lastDuration) {
        /* Skipped, not retried at once: lastSavedTime moved on. */
        WATCH_DBG("watch: skip save after seek \"%s\" %.0f/%.0f s (%s)", ctx.item.name.UTF8String ?: "",
                  position, ctx.lastDuration, why);
        return;
    }
    WATCH_DBG("watch: save \"%s\" %s %.0f/%.0f s (%s)", ctx.item.name.UTF8String ?: "",
              ctx.videoIdentifier.UTF8String ?: "movie", position, ctx.lastDuration, why);
    [MacLCWatchLibrary.sharedLibrary recordPosition:position
                                           duration:ctx.lastDuration
                                            forItem:ctx.item
                                    videoIdentifier:ctx.videoIdentifier
                                             season:ctx.season
                                            episode:ctx.episode
                                        episodeName:ctx.episodeName
                                          streamMRL:ctx.MRL
                                        streamLabel:ctx.streamLabel];
}

- (void)timeChanged:(NSNotification *)notification
{
    MacLCWatchContext * const ctx = _active;
    if (ctx == nil || ctx.stopped || getIntf() == NULL) {
        return;
    }
    if ([self sampleContext:ctx fromPlayer:notification.object]
        && ctx.armed && fabs(ctx.lastTime - ctx.lastSavedTime) >= MacLCWatchSaveInterval) {
        [self saveContext:ctx why:"progress"];
    }
}

- (void)stateChanged:(NSNotification *)notification
{
    MacLCWatchContext * const ctx = _active;
    if (ctx == nil || getIntf() == NULL) {
        return;
    }
    VLCPlayerController * const player = notification.object;
    switch (player.playerState) {
        case VLC_PLAYER_STATE_PLAYING:
            if (ctx.stopped) {
                /* The same media started again after a stop. */
                [ctx resetTrackingWithBaseline:player.time];
            }
            ctx.playing = YES;
            break;
        case VLC_PLAYER_STATE_PAUSED:
            if (!ctx.stopped && [self sampleContext:ctx fromPlayer:player]) {
                [self saveContext:ctx why:"pause"];
            }
            break;
        case VLC_PLAYER_STATE_STOPPING:
        case VLC_PLAYER_STATE_STOPPED:
            if (!ctx.stopped) {
                ctx.stopped = YES;
                [self saveContext:ctx why:"stop"];
            }
            break;
        case VLC_PLAYER_STATE_STARTED:
            break;
    }
}

- (void)mediaStopping:(uintptr_t)identifier reason:(enum vlc_player_media_stopping_reason)reason
{
    MacLCWatchContext * const ctx = _active;
    if (ctx == nil || ctx.inputItemID != identifier || ctx.stopped || getIntf() == NULL) {
        return;
    }
    [self sampleContext:ctx fromPlayer:VLCMain.sharedInstance.playQueueController.playerController];
    ctx.stopped = YES;

    if (reason == VLC_PLAYER_MEDIA_STOPPING_EOS && ctx.timeFresh) {
        [self endedContext:ctx];
    } else {
        [self saveContext:ctx why:reason == VLC_PLAYER_MEDIA_STOPPING_USER ? "stop" : "error"];
    }
    if (reason != VLC_PLAYER_MEDIA_STOPPING_USER) {
        /* An end or an error before anything played. */
        [self failContext:ctx why:"stopped before playing"];
    }
}

/* The media reached its end by itself. A stream that gives up half-way (a
 * dropped connection) is not a watched film. */
- (void)endedContext:(MacLCWatchContext *)ctx
{
    if (ctx.lastDuration > 0 && ctx.lastTime < MacLCWatchEndedFraction * ctx.lastDuration) {
        [self saveContext:ctx why:"ended early"];
        return;
    }
    const NSTimeInterval end = ctx.lastDuration > 0 ? ctx.lastDuration : ctx.lastTime;
    ctx.lastTime = end;
    ctx.lastDuration = end;
    ctx.armed = YES;
    ctx.afterSeek = NO; /* the end of the stream is the end, whatever came before */
    WATCH_DBG("watch: watched \"%s\" %s (ended at %.0f s)", ctx.item.name.UTF8String ?: "",
              ctx.videoIdentifier.UTF8String ?: "movie", end);
    [self saveContext:ctx why:"ended"];
}

- (void)applicationWillTerminate:(NSNotification *)notification
{
    if (getIntf() != NULL) {
        MacLCWatchContext * const ctx = _active;
        if (ctx != nil && !ctx.stopped
            && [self sampleContext:ctx fromPlayer:VLCMain.sharedInstance.playQueueController.playerController]) {
            [self saveContext:ctx why:"quit"];
        }
        /* The player is still alive here; it is not once the interface closed. */
        if (_listenerID != NULL) {
            vlc_player_Lock(_vlcPlayer);
            vlc_player_RemoveListener(_vlcPlayer, _listenerID);
            vlc_player_Unlock(_vlcPlayer);
        }
    }
    _listenerID = NULL;
    _vlcPlayer = NULL;
    [MacLCWatchLibrary.sharedLibrary flush];
}

#pragma mark Failure

- (void)errorChanged:(NSNotification *)notification
{
    VLCPlayerController * const player = notification.object;
    if (_active != nil && getIntf() != NULL && player.error != VLC_PLAYER_ERROR_NONE) {
        [self failContext:_active why:"player error"];
    }
}

/* A saved stream that cannot be opened any more: choose another version. */
- (void)failContext:(MacLCWatchContext *)ctx why:(const char *)why
{
    if (!ctx.isResume || ctx.playing || ctx.fallbackDone
        || -[ctx.startedAt timeIntervalSinceNow] > MacLCWatchResumeTimeout) {
        return;
    }
    [self openFallbackForContext:ctx why:why];
}

- (void)resumeTimeoutForContext:(MacLCWatchContext *)ctx
{
    if (ctx.playing || ctx.fallbackDone || getIntf() == NULL) {
        return;
    }
    if (ctx == _pending) {
        /* Never picked up by a media change: nothing is known about the stream. */
        WATCH_DBG("watch: \"%s\" never reached the player", ctx.item.name.UTF8String ?: "");
        _pending = nil;
    } else if (ctx == _active) {
        [self openFallbackForContext:ctx why:"not playing after 45 s"];
    }
}

- (void)openFallbackForContext:(MacLCWatchContext *)ctx why:(const char *)why
{
    ctx.fallbackDone = YES;
    if (VLCMain.sharedInstance.isTerminating) {
        return;
    }
    WATCH_DBG("watch: resume of \"%s\" %s failed (%s), choosing another version", ctx.item.name.UTF8String ?: "",
              ctx.videoIdentifier.UTF8String ?: "movie", why);

    if (ctx.videoIdentifier == nil) {
        [self presentPickerForItem:ctx.item video:nil];
        return;
    }
    [_metaRequest cancel];
    __weak typeof(self) weakSelf = self;
    _metaRequest = [MacLCAddonStore.sharedStore fetchMetaForItem:ctx.item
                                                      completion:^(MacLCAddonMeta *meta, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf == nil || getIntf() == NULL) {
            return;
        }
        strongSelf->_metaRequest = nil;
        MacLCAddonVideo *video = nil;
        for (MacLCAddonVideo *candidate in meta.videos) {
            if ([candidate.identifier isEqualToString:ctx.videoIdentifier]) {
                video = candidate;
                break;
            }
        }
        if (video == nil) {
            WATCH_DBG("watch: episode %s of \"%s\" not found in its meta, no picker", ctx.videoIdentifier.UTF8String ?: "",
                      ctx.item.name.UTF8String ?: "");
            return;
        }
        [strongSelf presentPickerForItem:ctx.item video:video];
    }];
}

- (void)presentPickerForItem:(MacLCAddonItem *)item video:(MacLCAddonVideo *)video
{
    if (getIntf() == NULL || VLCMain.sharedInstance.isTerminating) {
        return;
    }
    NSWindow * const window = VLCMain.sharedInstance.libraryWindow;
    if (window == nil || window.attachedSheet != nil) {
        return;
    }
    [window makeKeyAndOrderFront:nil];

    MacLCStreamPickerController * const picker = [[MacLCStreamPickerController alloc] initWithItem:item video:video];
    _fallbackPicker = picker;
    __weak typeof(self) weakSelf = self;
    __weak MacLCStreamPickerController * const weakPicker = picker;
    picker.completionHandler = ^(BOOL played) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf != nil && strongSelf->_fallbackPicker == weakPicker) {
            strongSelf->_fallbackPicker = nil;
        }
    };
    [picker beginSheetModalForWindow:window];
}

@end
