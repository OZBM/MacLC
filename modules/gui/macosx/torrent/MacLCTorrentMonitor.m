/*****************************************************************************
 * MacLCTorrentMonitor.m: asks the BitTorrent module what it is doing, while a
 * torrent plays, and tells the views
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

#import "torrent/MacLCTorrentMonitor.h"

#import <Cocoa/Cocoa.h>

#import "library/VLCInputItem.h"
#import "main/VLCMain.h"
#import "playqueue/VLCPlayQueueController.h"
#import "playqueue/VLCPlayerController.h"

#include <vlc_common.h>
#include <vlc_objects.h>
#include <vlc_variables.h>

/* Defined in MacLCTorrentStats.m (Foundation only, so the unit tests reach them). */
NSString * _Nullable MacLCTorrentKeyFromMRL(NSString * _Nullable mrl);
NSString * _Nullable MacLCTorrentFileNameFromMRL(NSString * _Nullable mrl);

NSNotificationName const MacLCTorrentMonitorDidUpdateNotification = @"MacLCTorrentMonitorDidUpdateNotification";

/* The function the module publishes in "maclc-bt-snapshot". */
typedef char *(*MacLCBtSnapshotFunction)(void);

static const char kSnapshotVariable[] = "maclc-bt-snapshot";
static const char kGuiVariable[] = "maclc-bt-gui";

static const NSTimeInterval kPollInterval = 0.25;
/* After the media stops being a torrent: wait this long, then stop... */
static const NSTimeInterval kGrace = 2.0;
/* ...unless a reader is still open, which we wait for at most this long. */
static const NSTimeInterval kGraceLimit = 10.0;
static const NSTimeInterval kSampleInterval = 1.0;
static const NSUInteger kHistoryLimit = 60;

static const char *StageName(MacLCTorrentStage stage)
{
    switch (stage) {
        case MacLCTorrentStageTrackers:    return "trackers";
        case MacLCTorrentStageMetadata:    return "metadata";
        case MacLCTorrentStageConnecting:  return "connecting";
        case MacLCTorrentStageDownloading: return "downloading";
        case MacLCTorrentStageBuffering:   return "buffering";
        case MacLCTorrentStageReady:       return "ready";
        case MacLCTorrentStagePlaying:     return "playing";
        case MacLCTorrentStageStalled:     return "stalled";
        case MacLCTorrentStageFailed:      return "error";
        case MacLCTorrentStageUnknown:     break;
    }
    return "unknown";
}

@interface MacLCTorrentMonitor ()
{
    BOOL _started;
    BOOL _guiFlagSet;
    NSTimer *_timer;
    NSMutableArray<NSNumber *> *_history;
    NSTimeInterval _lastSampleTime;
    NSString *_historyKey;

    /* What the current media says (set by -mediaDidChange:). */
    BOOL _mediaWantsTorrent;
    NSString *_matchKey;
    NSString *_matchFile;
    /* When the media stopped being a torrent while we were active; 0 = not ending. */
    NSTimeInterval _endedAt;

    /* Last state written to the log. */
    NSString *_loggedKey;
    MacLCTorrentStage _loggedStage;
}
@property (readwrite, getter=isActive) BOOL active;
@property (readwrite, nullable) MacLCTorrentSnapshot *snapshot;
@property (readwrite, nullable) MacLCTorrentInfo *torrent;
@property (readwrite, nullable) MacLCTorrentReaderInfo *reader;
@property (readwrite, copy, nullable) NSString *fixturePath;
@end

@implementation MacLCTorrentMonitor

+ (MacLCTorrentMonitor *)sharedMonitor
{
    static MacLCTorrentMonitor *monitor;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        monitor = [[MacLCTorrentMonitor alloc] init];
    });
    return monitor;
}

- (instancetype)init
{
    self = [super init];
    if (self)
        _history = [NSMutableArray array];
    return self;
}

#pragma mark - Public

- (NSArray<NSNumber *> *)rateHistory
{
    return [_history copy];
}

- (MacLCTorrentStage)stage
{
    if (self.reader != nil && self.reader.stage != MacLCTorrentStageUnknown)
        return self.reader.stage;
    return self.torrent != nil ? self.torrent.stage : MacLCTorrentStageUnknown;
}

- (void)start
{
    if (_started)
        return;
    _started = YES;

    const char *fixture = getenv("MACLC_DEBUG_TORRENT_FIXTURE");
    if (fixture != NULL && fixture[0] != '\0')
        self.fixturePath = [NSString stringWithUTF8String:fixture];

    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    [center addObserver:self selector:@selector(mediaDidChange:)
                   name:VLCPlayerCurrentMediaItemChanged object:nil];
    [center addObserver:self selector:@selector(mediaDidChange:)
                   name:VLCPlayerStateChanged object:nil];
    [center addObserver:self selector:@selector(applicationWillTerminate:)
                   name:NSApplicationWillTerminateNotification object:nil];

    [self publishGuiFlag];

    /* Not inline: VLCMain.sharedInstance runs under dispatch_once, and the
     * first view that calls -start may itself be created by that init. */
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self->_fixturePath != nil) {
            [self startTimer];
            [self tick];
        } else {
            [self mediaDidChange:nil];
        }
    });
}

- (MacLCTorrentSnapshot *)pollNow
{
    MacLCTorrentSnapshot *snapshot = [self readSnapshot];
    if (snapshot != nil) {
        [self applySnapshot:snapshot now:NSProcessInfo.processInfo.systemUptime];
        [self postUpdate];
    }
    return snapshot;
}

#pragma mark - The module

/// Tells the module an interface draws the progress itself (it then keeps its
/// own dialogs away). Idempotent; retried later when the interface was not up yet.
- (void)publishGuiFlag
{
    if (_guiFlagSet)
        return;
    intf_thread_t *intf = getIntf();
    if (intf == NULL)
        return;
    libvlc_int_t *libvlc = vlc_object_instance(intf);
    if (var_Type(libvlc, kGuiVariable) == 0)
        var_Create(libvlc, kGuiVariable, VLC_VAR_BOOL);
    if (var_SetBool(libvlc, kGuiVariable, true) == VLC_SUCCESS) {
        _guiFlagSet = YES;
        msg_Dbg(intf, "torrent ui: the interface draws torrent progress");
    }
}

- (MacLCTorrentSnapshot *)readModuleSnapshot
{
    intf_thread_t *intf = getIntf();
    if (intf == NULL)
        return nil;
    libvlc_int_t *libvlc = vlc_object_instance(intf);
    if ((var_Type(libvlc, kSnapshotVariable) & VLC_VAR_CLASS) != VLC_VAR_ADDRESS)
        return nil;   /* no torrent was ever opened */
    MacLCBtSnapshotFunction function = (MacLCBtSnapshotFunction)var_GetAddress(libvlc, kSnapshotVariable);
    if (function == NULL)
        return nil;
    char *json = function();
    if (json == NULL)
        return nil;
    NSData *data = [NSData dataWithBytesNoCopy:json length:strlen(json) freeWhenDone:NO];
    MacLCTorrentSnapshot *snapshot = [MacLCTorrentSnapshot snapshotFromJSONData:data error:NULL];
    free(json);
    return snapshot;
}

- (MacLCTorrentSnapshot *)readFixture
{
    NSData *data = [NSData dataWithContentsOfFile:_fixturePath options:0 error:NULL];
    return data != nil ? [MacLCTorrentSnapshot snapshotFromJSONData:data error:NULL] : nil;
}

- (MacLCTorrentSnapshot *)readSnapshot
{
    return _fixturePath != nil ? [self readFixture] : [self readModuleSnapshot];
}

#pragma mark - The current media

- (void)mediaDidChange:(NSNotification *)notification
{
    if (_fixturePath != nil)
        return;   /* the file decides */
    if (getIntf() == NULL) {
        [self shutDown];
        return;
    }
    [self publishGuiFlag];

    VLCPlayerController *player = VLCMain.sharedInstance.playQueueController.playerController;
    VLCInputItem *media = player.currentMedia;
    const enum vlc_player_state state = player.playerState;
    const BOOL running = state == VLC_PLAYER_STATE_STARTED || state == VLC_PLAYER_STATE_PLAYING
                      || state == VLC_PLAYER_STATE_PAUSED;
    NSString *mrl = media.MRL;

    BOOL wants = NO;
    NSString *key = nil;
    NSString *file = nil;
    if (running && mrl.length > 0) {
        NSString *lower = mrl.lowercaseString;
        key = MacLCTorrentKeyFromMRL(mrl);
        wants = key != nil || [lower hasPrefix:@"magnet:"] || [lower containsString:@".torrent"];
        if (!wants) {
            /* An address of the module's own making: it carries the info hash
             * of a torrent the snapshot lists. */
            for (MacLCTorrentInfo *torrent in [self readModuleSnapshot].torrents) {
                if (torrent.key.length >= 32 && [lower containsString:torrent.key]) {
                    key = torrent.key;
                    wants = YES;
                    break;
                }
            }
        }
        if (wants)
            file = MacLCTorrentFileNameFromMRL(mrl);
    }

    _mediaWantsTorrent = wants;
    _matchKey = wants ? key : nil;
    _matchFile = wants ? file : nil;
    if (wants || self.active) {
        [self startTimer];
        [self tick];
    }
}

/// The torrent and the reader of the current media inside `snapshot`.
- (void)resolveInSnapshot:(MacLCTorrentSnapshot *)snapshot
{
    MacLCTorrentInfo *torrent = nil;
    if (_matchKey != nil)
        /* A key that the module does not list yet is a torrent still being
         * added: do not show another torrent's numbers meanwhile. */
        torrent = [snapshot torrentForKey:_matchKey];
    else
        torrent = snapshot.activeTorrent;

    /* The file named by the address' fragment, else the largest file (the
     * video, not an external audio track or subtitle) of that torrent. */
    MacLCTorrentReaderInfo *named = nil;
    MacLCTorrentReaderInfo *largest = nil;
    if (torrent != nil) {
        for (MacLCTorrentReaderInfo *candidate in snapshot.readers) {
            if (![candidate.torrentKey isEqualToString:torrent.key])
                continue;
            if (named == nil && _matchFile != nil
             && [candidate.fileName.lastPathComponent isEqualToString:_matchFile])
                named = candidate;
            if (largest == nil || candidate.size > largest.size)
                largest = candidate;
        }
    }
    MacLCTorrentReaderInfo *reader = named ?: largest;
    self.torrent = torrent;
    self.reader = reader;
}

#pragma mark - Polling

- (void)startTimer
{
    if (_timer != nil)
        return;
    NSTimer *timer = [NSTimer timerWithTimeInterval:kPollInterval target:self
                                           selector:@selector(timerFired:) userInfo:nil repeats:YES];
    timer.tolerance = 0.05;
    [NSRunLoop.mainRunLoop addTimer:timer forMode:NSRunLoopCommonModes];
    _timer = timer;
}

- (void)stopTimer
{
    [_timer invalidate];
    _timer = nil;
}

- (void)timerFired:(NSTimer *)timer
{
    [self tick];
}

- (void)tick
{
    const NSTimeInterval now = NSProcessInfo.processInfo.systemUptime;
    MacLCTorrentSnapshot *snapshot = nil;
    BOOL wants;

    if (_fixturePath != nil) {
        snapshot = [self readFixture];
        wants = snapshot != nil;
    } else {
        if (getIntf() == NULL) {
            [self shutDown];
            return;
        }
        wants = _mediaWantsTorrent;
        snapshot = [self readModuleSnapshot];
    }

    if (wants) {
        _endedAt = 0;
        if (!self.active)
            [self activate];
    } else if (self.active) {
        if (_endedAt == 0)
            _endedAt = now;
        const NSTimeInterval since = now - _endedAt;
        if (since >= kGrace && (snapshot.readers.count == 0 || since >= kGraceLimit)) {
            [self deactivate];
            return;
        }
    } else {
        if (_fixturePath == nil)
            [self stopTimer];
        return;
    }

    if (snapshot != nil)
        [self applySnapshot:snapshot now:now];
    [self postUpdate];
}

- (void)applySnapshot:(MacLCTorrentSnapshot *)snapshot now:(NSTimeInterval)now
{
    self.snapshot = snapshot;
    [self resolveInSnapshot:snapshot];

    MacLCTorrentInfo *torrent = self.torrent;
    if (torrent != nil) {
        if (![torrent.key isEqualToString:_historyKey ?: @""]) {
            [_history removeAllObjects];
            _lastSampleTime = 0;
            _historyKey = torrent.key;
        }
        if (_lastSampleTime == 0 || now - _lastSampleTime >= kSampleInterval) {
            _lastSampleTime = now;
            [_history addObject:@(torrent.downloadRate)];
            if (_history.count > kHistoryLimit)
                [_history removeObjectsInRange:NSMakeRange(0, _history.count - kHistoryLimit)];
        }
    }

    const MacLCTorrentStage stage = self.stage;
    if (![(torrent.key ?: @"") isEqualToString:_loggedKey ?: @""] || stage != _loggedStage) {
        _loggedKey = torrent.key;
        _loggedStage = stage;
        intf_thread_t *intf = getIntf();
        if (intf != NULL && torrent != nil)
            msg_Dbg(intf, "torrent ui: %s (peers %ld, unchoked %ld, down %lld B/s)",
                    StageName(stage), (long)torrent.peers, (long)torrent.peersUnchoked,
                    (long long)torrent.downloadRate);
    }
}

- (void)activate
{
    self.active = YES;
    [_history removeAllObjects];
    _lastSampleTime = 0;
    _historyKey = nil;
    _loggedKey = nil;
    _loggedStage = MacLCTorrentStageUnknown;
    intf_thread_t *intf = getIntf();
    if (intf != NULL)
        msg_Dbg(intf, "torrent ui: active%s", _fixturePath != nil ? " (fixture)" : "");
    [self startTimer];
}

- (void)clearState
{
    self.active = NO;
    _endedAt = 0;
    self.snapshot = nil;
    self.torrent = nil;
    self.reader = nil;
    [_history removeAllObjects];
    _lastSampleTime = 0;
    _historyKey = nil;
}

- (void)deactivate
{
    [self clearState];
    if (_fixturePath == nil)
        [self stopTimer];
    intf_thread_t *intf = getIntf();
    if (intf != NULL)
        msg_Dbg(intf, "torrent ui: inactive");
    [self postUpdate];
}

/// The interface is closing: no more calls into libvlc, no timer.
- (void)shutDown
{
    [self stopTimer];
    _mediaWantsTorrent = NO;
    const BOOL wasActive = self.active;
    [self clearState];
    if (wasActive)
        [self postUpdate];
}

- (void)postUpdate
{
    [NSNotificationCenter.defaultCenter postNotificationName:MacLCTorrentMonitorDidUpdateNotification
                                                      object:self];
}

- (void)applicationWillTerminate:(NSNotification *)notification
{
    [self stopTimer];
    [NSNotificationCenter.defaultCenter removeObserver:self];
    _started = NO;
    _mediaWantsTorrent = NO;
    intf_thread_t *intf = getIntf();
    if (intf != NULL && _guiFlagSet) {
        var_SetBool(vlc_object_instance(intf), kGuiVariable, false);
        msg_Dbg(intf, "torrent ui: stopped");
    }
    _guiFlagSet = NO;
}

@end
