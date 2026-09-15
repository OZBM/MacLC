/*****************************************************************************
 * MacLCOSDController.m: what the glass capsule over the video says
 *****************************************************************************
 * Copyright (C) 2026 Hazen Studio
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston MA 02110-1301, USA.
 *****************************************************************************/

#import "MacLCOSDController.h"

#import "extensions/NSString+Helpers.h"
#import "main/VLCMain.h"
#import "playqueue/VLCPlayQueueController.h"
#import "playqueue/VLCPlayerController.h"
#import "library/VLCInputItem.h"
#import "settings/MacLCConfigSafe.h"

#include <math.h>

NSString * const MacLCOSDShouldShowNotification = @"MacLCOSDShouldShowNotification";
NSString * const MacLCOSDMessageKey = @"MacLCOSDMessage";
NSString * const MacLCOSDSymbolKey = @"MacLCOSDSymbol";
NSString * const MacLCOSDLevelKey = @"MacLCOSDLevel";
NSString * const MacLCOSDOnlyWithoutControlsKey = @"MacLCOSDOnlyWithoutControls";

/* A new file brings its own speed, delays and resume position: none of that
 * is something the user just did. (Volume and mute are compared with what
 * was last shown instead, so a press right after opening still answers.) */
static const CFTimeInterval kSettleAfterMediaChange = 2.0;
/* Playback drifts by a frame or two between timer ticks; a jump is more. */
static const double kJumpThresholdSeconds = 2.5;

@implementation MacLCOSDController
{
    CFTimeInterval _mediaChangedAt;
    float _volume;
    BOOL _mute;
    float _rate;
    vlc_tick_t _audioDelay;
    vlc_tick_t _subtitlesDelay;
    enum vlc_player_state _state;
    vlc_tick_t _lastTime;
    CFTimeInterval _lastTimeAt;
    BOOL _hasLastTime;
    NSUInteger _mediaGeneration;
}

+ (instancetype)sharedController
{
    static MacLCOSDController *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        shared = [[MacLCOSDController alloc] init];
    });
    return shared;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        VLCPlayerController *player = self.playerController;
        /* The core draws its own messages into the picture; this controller
         * replaces them, so turn them off for every output, present and
         * future (the player object is the outputs' parent). */
        [player setVideoOutputBool:NO forVariable:"osd"];

        _volume = player.volume;
        _mute = player.mute;
        [self takeSnapshotOfPlayer:player];
        _mediaChangedAt = CACurrentMediaTime();

        NSDictionary<NSNotificationName, NSString *> *observed = @{
            VLCPlayerCurrentMediaItemChanged: NSStringFromSelector(@selector(mediaChanged:)),
            VLCPlayerVolumeChanged: NSStringFromSelector(@selector(volumeChanged:)),
            VLCPlayerMuteChanged: NSStringFromSelector(@selector(volumeChanged:)),
            VLCPlayerRateChanged: NSStringFromSelector(@selector(rateChanged:)),
            VLCPlayerAudioDelayChanged: NSStringFromSelector(@selector(delayChanged:)),
            VLCPlayerSubtitlesDelayChanged: NSStringFromSelector(@selector(delayChanged:)),
            VLCPlayerStateChanged: NSStringFromSelector(@selector(stateChanged:)),
            VLCPlayerTimeAndPositionChanged: NSStringFromSelector(@selector(timeChanged:)),
            VLCPlayerListOfVideoOutputThreadsChanged: NSStringFromSelector(@selector(videoOutputsChanged:)),
            VLCPlayerCoreOSDMessage: NSStringFromSelector(@selector(coreMessage:)),
        };
        NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
        [observed enumerateKeysAndObjectsUsingBlock:^(NSNotificationName name, NSString *selector, BOOL *stop) {
            [center addObserver:self selector:NSSelectorFromString(selector) name:name object:nil];
        }];
    }
    return self;
}

- (void)dealloc
{
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (VLCPlayerController *)playerController
{
    return VLCMain.sharedInstance.playQueueController.playerController;
}

#pragma mark - Posting

- (BOOL)enabled
{
    return MacLCConfigGetInt("osd", 1) != 0;
}

- (BOOL)settling
{
    return CACurrentMediaTime() - _mediaChangedAt < kSettleAfterMediaChange;
}

- (void)post:(NSString *)message
      symbol:(nullable NSString *)symbol
       level:(CGFloat)level
onlyWithoutControls:(BOOL)onlyWithoutControls
{
    if (![self enabled])
        return;
    msg_Dbg(getIntf(), "on-screen message: %s", message.UTF8String);
    NSMutableDictionary *info = [NSMutableDictionary dictionaryWithDictionary:@{
        MacLCOSDMessageKey: message,
        MacLCOSDLevelKey: @(level),
        MacLCOSDOnlyWithoutControlsKey: @(onlyWithoutControls),
    }];
    if (symbol != nil)
        info[MacLCOSDSymbolKey] = symbol;
    [NSNotificationCenter.defaultCenter postNotificationName:MacLCOSDShouldShowNotification
                                                      object:self
                                                    userInfo:info];
}

- (void)showMessage:(NSString *)message symbolName:(nullable NSString *)symbolName
{
    [self post:message symbol:symbolName level:-1.0 onlyWithoutControls:NO];
}

#pragma mark - State

/* What the file started with, so only later changes are announced. */
- (void)takeSnapshotOfPlayer:(VLCPlayerController *)player
{
    _rate = player.playbackRate;
    _audioDelay = player.audioDelay;
    _subtitlesDelay = player.subtitlesDelay;
    _state = player.playerState;
    _hasLastTime = NO;
}

- (void)mediaChanged:(NSNotification *)notification
{
    _mediaChangedAt = CACurrentMediaTime();
    _mediaGeneration++;
    [self takeSnapshotOfPlayer:self.playerController];
    [self scheduleTitle];
}

/* The media title, the way the core used to print it when a video starts
 * (the "video-title-show" preference). */
- (void)scheduleTitle
{
    if (!var_InheritBool(getIntf(), "video-title-show"))
        return;
    const NSUInteger generation = _mediaGeneration;
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        MacLCOSDController *strongSelf = weakSelf;
        if (strongSelf == nil || strongSelf->_mediaGeneration != generation)
            return;
        VLCPlayerController *player = strongSelf.playerController;
        VLCInputItem *media = player.currentMedia;
        NSString *title = media.title.length > 0 ? media.title : media.name;
        if (title.length == 0 || player.currentMediaIsAudioOnly)
            return;
        /* A file without a title in its metadata is named after the file:
         * "fight.mp4" reads "fight". */
        NSString *fileName = [NSURL URLWithString:media.MRL].lastPathComponent;
        if ([title isEqualToString:fileName] && title.pathExtension.length > 0)
            title = title.stringByDeletingPathExtension;
        [strongSelf post:title symbol:@"play.rectangle" level:-1.0 onlyWithoutControls:NO];
    });
}

/* A new output inherits "osd" from the player, but one opened before this
 * controller existed has its own value: turn it off there too. */
- (void)videoOutputsChanged:(NSNotification *)notification
{
    [self.playerController setVideoOutputBool:NO forVariable:"osd"];
}

#pragma mark - Messages

/* Compared with what was last shown: a new audio output reports the same
 * volume again (headphones plugged in, a new file), which says nothing. */
- (void)volumeChanged:(NSNotification *)notification
{
    VLCPlayerController *player = self.playerController;
    const float volume = player.volume;
    const BOOL mute = player.mute;
    if (fabsf(volume - _volume) < 0.001f && mute == _mute)
        return;
    _volume = volume;
    _mute = mute;

    if (mute) {
        [self post:_NS("Muted") symbol:@"speaker.slash.fill" level:0.0 onlyWithoutControls:YES];
        return;
    }
    NSString *symbol = volume <= 0.001f ? @"speaker.fill"
                     : volume < 0.34f   ? @"speaker.wave.1.fill"
                     : volume < 0.67f   ? @"speaker.wave.2.fill"
                                        : @"speaker.wave.3.fill";
    NSString *message = [NSString stringWithFormat:_NS("Volume %ld%%"), lroundf(volume * 100.0f)];
    [self post:message symbol:symbol level:MIN(volume, 1.0f) onlyWithoutControls:YES];
}

- (void)rateChanged:(NSNotification *)notification
{
    const float rate = self.playerController.playbackRate;
    if (fabsf(rate - _rate) < 0.001f)
        return;
    _rate = rate;
    _hasLastTime = NO; /* the last interval ran at the old speed */
    if ([self settling])
        return;

    NSString *message;
    if (fabsf(rate - 1.0f) < 0.001f) {
        message = _NS("Normal Speed");
    } else {
        NSNumberFormatter *formatter = [[NSNumberFormatter alloc] init];
        formatter.numberStyle = NSNumberFormatterDecimalStyle;
        formatter.minimumFractionDigits = 0;
        formatter.maximumFractionDigits = 2;
        message = [NSString stringWithFormat:_NS("Speed %@×"),
                   [formatter stringFromNumber:@(rate)]];
    }
    [self post:message symbol:@"gauge.with.dots.needle.67percent" level:-1.0 onlyWithoutControls:NO];
}

static NSString *SignedMilliseconds(vlc_tick_t delay)
{
    const long ms = lround((double)delay / 1000.0);
    return [NSString stringWithFormat:@"%@%ld ms", ms > 0 ? @"+" : @"−", labs(ms)];
}

- (void)delayChanged:(NSNotification *)notification
{
    VLCPlayerController *player = self.playerController;
    const vlc_tick_t audio = player.audioDelay;
    const vlc_tick_t subtitles = player.subtitlesDelay;
    const BOOL audioChanged = audio != _audioDelay;
    const BOOL subtitlesChanged = subtitles != _subtitlesDelay;
    _audioDelay = audio;
    _subtitlesDelay = subtitles;
    if ([self settling])
        return;

    if (audioChanged) {
        NSString *message = llabs(audio) < VLC_TICK_FROM_MS(1)
            ? _NS("Audio in Sync")
            : [NSString stringWithFormat:_NS("Audio Delay %@"), SignedMilliseconds(audio)];
        [self post:message symbol:@"waveform" level:-1.0 onlyWithoutControls:NO];
    } else if (subtitlesChanged) {
        NSString *message = llabs(subtitles) < VLC_TICK_FROM_MS(1)
            ? _NS("Subtitles in Sync")
            : [NSString stringWithFormat:_NS("Subtitle Delay %@"), SignedMilliseconds(subtitles)];
        [self post:message symbol:@"captions.bubble" level:-1.0 onlyWithoutControls:NO];
    }
}

- (void)stateChanged:(NSNotification *)notification
{
    const enum vlc_player_state state = self.playerController.playerState;
    const enum vlc_player_state previous = _state;
    _state = state;
    _hasLastTime = NO; /* time stood still while paused */
    if (state == previous)
        return;
    if (state == VLC_PLAYER_STATE_PAUSED && previous == VLC_PLAYER_STATE_PLAYING)
        [self post:_NS("Paused") symbol:@"pause.fill" level:-1.0 onlyWithoutControls:YES];
    else if (state == VLC_PLAYER_STATE_PLAYING && previous == VLC_PLAYER_STATE_PAUSED)
        [self post:_NS("Playing") symbol:@"play.fill" level:-1.0 onlyWithoutControls:YES];
}

/* What the core reports as "source<TAB>text": video settings (aspect ratio,
 * crop, zoom, deinterlacing, subtitle position), and the track, chapter,
 * title and program selections someone asked for - never the player's own
 * choices when a file opens. Worded the way the menus are. */
- (void)coreMessage:(NSNotification *)notification
{
    NSString *source = notification.userInfo[VLCPlayerCoreMessageSourceKey];
    NSString *text = notification.userInfo[VLCPlayerCoreMessageTextKey];
    if (text.length == 0)
        return;

    NSString *value = text;
    const NSRange colon = [text rangeOfString:@": "];
    if (colon.location != NSNotFound)
        value = [text substringFromIndex:NSMaxRange(colon)];
    const BOOL none = [value isEqualToString:@"N/A"];

    if ([source isEqualToString:@"subtitle-track"]) {
        [self post:none ? _NS("Subtitles Off") : [NSString stringWithFormat:_NS("Subtitles: %@"), value]
            symbol:@"captions.bubble" level:-1.0 onlyWithoutControls:NO];
        return;
    }
    if ([source isEqualToString:@"audio-track"]) {
        [self post:none ? _NS("Audio Off") : [NSString stringWithFormat:_NS("Audio: %@"), value]
            symbol:@"waveform" level:-1.0 onlyWithoutControls:NO];
        return;
    }
    if ([source isEqualToString:@"video-track"]) {
        [self post:none ? _NS("Video Off") : [NSString stringWithFormat:_NS("Video: %@"), value]
            symbol:@"film" level:-1.0 onlyWithoutControls:NO];
        return;
    }
    if ([source isEqualToString:@"chapter"] || [source isEqualToString:@"title"]) {
        /* "Next chapter" reads "Next Chapter", like a menu item. */
        [self post:text.capitalizedString
            symbol:[source isEqualToString:@"chapter"] ? @"bookmark" : @"film.stack"
             level:-1.0 onlyWithoutControls:NO];
        return;
    }
    if ([source isEqualToString:@"program"]) {
        [self post:text symbol:@"tv" level:-1.0 onlyWithoutControls:NO];
        return;
    }

    static NSDictionary<NSString *, NSArray<NSString *> *> *styles;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        /* variable: title for "title value" messages, symbol */
        styles = @{
            @"aspect-ratio": @[_NS("Aspect Ratio"), @"aspectratio"],
            @"crop": @[_NS("Crop"), @"crop"],
            @"zoom": @[_NS("Zoom"), @"plus.magnifyingglass"],
            @"autoscale": @[@"", @"arrow.up.left.and.arrow.down.right"],
            @"deinterlace": @[@"", @"rectangle.split.1x2"],
            @"deinterlace-mode": @[@"", @"rectangle.split.1x2"],
        };
    });
    NSArray<NSString *> *style = styles[source];
    NSString *symbol = style ? style[1]
                     : ([source hasPrefix:@"crop"] ? @"crop" : @"captions.bubble");

    /* "Aspect ratio: 16:9" reads "Aspect Ratio 16:9", like the menu. */
    NSString *message = text;
    if (style[0].length > 0 && colon.location != NSNotFound) {
        /* Zoom presets are named "2:1 Double" and the like: say "2×". */
        int num = 0, den = 0;
        if ([source isEqualToString:@"zoom"]
            && sscanf(value.UTF8String, "%d:%d", &num, &den) == 2 && den > 0) {
            NSNumberFormatter *formatter = [[NSNumberFormatter alloc] init];
            formatter.maximumFractionDigits = 2;
            value = [NSString stringWithFormat:@"%@×",
                     [formatter stringFromNumber:@((double)num / den)]];
        }
        message = [NSString stringWithFormat:@"%@ %@", style[0], value];
    }
    [self post:message symbol:symbol level:-1.0 onlyWithoutControls:NO];
}

/* The player does not say why the time changed: a jump is a change the
 * elapsed time and the speed cannot explain. Going back is a jump - unless an
 * A→B loop just went round; standing still is not (buffering); going forward
 * is when it outruns the clock. */
- (void)timeChanged:(NSNotification *)notification
{
    VLCPlayerController *player = self.playerController;
    const vlc_tick_t time = player.time;
    const CFTimeInterval now = CACurrentMediaTime();
    if (time == VLC_TICK_INVALID)
        return;

    if (_hasLastTime && ![self settling]) {
        const double elapsed = _state == VLC_PLAYER_STATE_PLAYING
                             ? (now - _lastTimeAt) * _rate : 0.0;
        const double moved = secf_from_vlc_tick(time - _lastTime);
        const BOOL looping = player.abLoopState == VLC_PLAYER_ABLOOP_B;
        const BOOL back = moved < -1.0 && !looping;
        const BOOL forward = moved > elapsed + kJumpThresholdSeconds;
        if (back || forward) {
            const vlc_tick_t length = player.length;
            NSString *symbol = forward ? @"goforward" : @"gobackward";
            if (length > 0)
                [self post:[NSString stringWithFormat:@"%@ / %@",
                            [NSString stringWithTimeFromTicks:time],
                            [NSString stringWithTimeFromTicks:length]]
                    symbol:symbol
                     level:(CGFloat)time / (CGFloat)length
       onlyWithoutControls:YES];
            else /* live streams: where we are, no bar */
                [self post:[NSString stringWithTimeFromTicks:time]
                    symbol:symbol level:-1.0 onlyWithoutControls:YES];
        }
    }
    _lastTime = time;
    _lastTimeAt = now;
    _hasLastTime = YES;
}

@end
