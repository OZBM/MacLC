/*****************************************************************************
 * airplay.m: AirPlay stream output (HLS + AVPlayer)
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
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin Street, Fifth Floor, Boston MA 02110-1301, USA.
 *****************************************************************************/

#ifdef HAVE_CONFIG_H
# include "config.h"
#endif

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>

#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <net/if.h>
#include <ifaddrs.h>
#include <unistd.h>

#include <vlc_common.h>
#include <vlc_plugin.h>
#include <vlc_sout.h>
#include <vlc_frame.h>
#include <vlc_configuration.h>
#include <vlc_memstream.h>
#include <vlc_threads.h>
#include <vlc_tick.h>
#include <vlc_interrupt.h>

#include "../stream_out/chromecast/chromecast_common.h"
#include "packetizer/h264_nal.h"
#include "packetizer/hevc_nal.h"

#ifndef PROFILE_H264_BASELINE
# define PROFILE_H264_BASELINE 66
# define PROFILE_H264_MAIN 77
# define PROFILE_H264_HIGH 100
# define PROFILE_H264_HIGH_10 110
# define PROFILE_H264_HIGH_422 122
# define PROFILE_H264_HIGH_444 144
# define PROFILE_H264_HIGH_444_PREDICTIVE 244
#endif

#ifndef HEVC_PROFILE_IDC_MAIN
# define HEVC_PROFILE_IDC_MAIN 1
# define HEVC_PROFILE_IDC_MAIN_10 2
#endif

#define SOUT_CFG_PREFIX "sout-airplay-"

static const char *const ppsz_sout_options[] = {
    "ip", "port", "device-name", NULL
};

static void *kAirPlayStatusContext = &kAirPlayStatusContext;
static void *kAirPlayTimeControlStatusContext = &kAirPlayTimeControlStatusContext;

@interface MacLCAirPlaySession : NSObject

@property (nonatomic, readonly) AVPlayer *player;
@property (nonatomic, readonly) BOOL isPrivatePlayer;

- (instancetype)initWithStream:(sout_stream_t *)p_stream
                        player:(AVPlayer *)player
               isPrivatePlayer:(BOOL)isPrivatePlayer;

- (void)startGenerationWithURL:(NSString *)urlString;
- (void)resetGeneration;
- (void)setVlcPaused:(BOOL)paused;
- (void)setDemuxCallback:(on_paused_changed_itf)cb data:(void *)data;
- (void)invalidate;
- (void)detachStream;

- (vlc_tick_t)cachedPlaybackTime;
- (BOOL)isItemFailed;
- (NSError *)itemError;
- (BOOL)didPlayToEnd;
- (BOOL)hasStartedPlayback;

@end

typedef struct sout_stream_id_sys_t sout_stream_id_sys_t;

struct sout_stream_id_sys_t
{
    es_format_t fmt;
    char *es_id;
    void *p_sub_id;
    bool b_dummy;
    vlc_frame_t *pending;         /* held until the chain starts, see Send() */
    vlc_frame_t **pending_last;
};

typedef struct
{
    vlc_mutex_t lock;
    vlc_cond_t pace_cond;        /* pace() sleeps on it; input controls wake it */
    bool b_pace_interrupted;
    vlc_tick_t last_cached_time; /* end detection: last playback time seen */
    vlc_tick_t last_progress;    /* and when it last changed */
    vlc_tick_t pending_first;    /* timestamp of the oldest held frame */
    sout_stream_t *p_stream;

    chromecast_common common;

    char *psz_ip;
    int i_port;
    char *psz_device_name;
    char psz_token[17];
    unsigned int generation_idx;

    char *generation_url;
    bool b_generation_needed;
    bool b_player_started_for_gen;
    bool b_input_eof;
    bool b_vlc_paused;

    vlc_tick_t first_pushed_pts;
    vlc_tick_t newest_pushed_pts;
    vlc_tick_t last_pace_log;

    sout_stream_id_sys_t *video_id;
    sout_stream_id_sys_t *audio_id;

    sout_stream_t *p_out;

    MacLCAirPlaySession *session;
} sout_stream_sys_t;

/* Main-queue code logs through the stream object, which Close may free at any
 * time: take the state lock and check that it is still attached. */
#define SESSION_LOG(level, ...) do { \
        vlc_mutex_lock(&self->_stateLock); \
        if (self->_p_stream != NULL) \
            msg_##level(self->_p_stream, __VA_ARGS__); \
        vlc_mutex_unlock(&self->_stateLock); \
    } while (0)

@implementation MacLCAirPlaySession {
    sout_stream_t *_p_stream;
    AVPlayer *_player;
    BOOL _isPrivatePlayer;
    AVPlayerItem *_createdPlayerItem;
    unsigned _createdGeneration;   /* generation _createdPlayerItem belongs to */
    id _timeObserver;
    BOOL _isObservingPlayer;
    BOOL _isObservingItem;
    BOOL _invalidated;
    BOOL _vlcPaused;
    BOOL _remotePaused;
    BOOL _playedThisGeneration;
    NSDate *_epochDate;

    on_paused_changed_itf _demux_cb;
    void *_demux_data;

    vlc_mutex_t _stateLock;
    unsigned _generation;   /* bumped synchronously by -resetGeneration */
    vlc_tick_t _cachedTime;
    BOOL _itemFailed;
    NSError *_lastError;
    BOOL _playToEnd;
    BOOL _startedPlayback;
}

- (instancetype)initWithStream:(sout_stream_t *)p_stream
                        player:(AVPlayer *)player
               isPrivatePlayer:(BOOL)isPrivatePlayer
{
    if ((self = [super init]))
    {
        _p_stream = p_stream;
        _player = player;
        _isPrivatePlayer = isPrivatePlayer;
        _epochDate = [NSDate dateWithTimeIntervalSince1970:946684800];
        _cachedTime = VLC_TICK_INVALID;
        vlc_mutex_init(&_stateLock);

        dispatch_async(dispatch_get_main_queue(), ^{
            if (!self->_invalidated)
            {
                [self->_player addObserver:self
                                forKeyPath:@"timeControlStatus"
                                   options:NSKeyValueObservingOptionNew
                                   context:kAirPlayTimeControlStatusContext];
                self->_isObservingPlayer = YES;
            }
        });
    }
    return self;
}

- (AVPlayer *)player
{
    return _player;
}

- (BOOL)isPrivatePlayer
{
    return _isPrivatePlayer;
}

- (void)updateCachedTimeFromDate:(NSDate *)currentDate generation:(unsigned)generation
{
    if (currentDate == nil)
        return;
    NSTimeInterval diff = [currentDate timeIntervalSinceDate:_epochDate];
    if (diff < 0.0)
        return;
    vlc_mutex_lock(&_stateLock);
    /* An observer of the previous item may still fire after a seek. */
    if (generation == _generation)
    {
        _cachedTime = vlc_tick_from_sec(diff);
        _startedPlayback = YES;
    }
    vlc_mutex_unlock(&_stateLock);
}

- (vlc_tick_t)cachedPlaybackTime
{
    vlc_mutex_lock(&_stateLock);
    vlc_tick_t t = _cachedTime;
    vlc_mutex_unlock(&_stateLock);
    return t;
}

- (BOOL)isItemFailed
{
    vlc_mutex_lock(&_stateLock);
    BOOL f = _itemFailed;
    vlc_mutex_unlock(&_stateLock);
    return f;
}

- (NSError *)itemError
{
    vlc_mutex_lock(&_stateLock);
    NSError *err = _lastError;
    vlc_mutex_unlock(&_stateLock);
    return err;
}

- (BOOL)didPlayToEnd
{
    vlc_mutex_lock(&_stateLock);
    BOOL e = _playToEnd;
    vlc_mutex_unlock(&_stateLock);
    return e;
}

- (BOOL)hasStartedPlayback
{
    vlc_mutex_lock(&_stateLock);
    BOOL s = _startedPlayback;
    vlc_mutex_unlock(&_stateLock);
    return s;
}

/* Main queue: does _createdPlayerItem still belong to the live generation?
 * After a seek the old item fails (its playlist is gone) or ends: none of that
 * may reach the new generation's state. */
- (BOOL)createdItemIsCurrent
{
    vlc_mutex_lock(&_stateLock);
    const BOOL current = _createdGeneration == _generation;
    vlc_mutex_unlock(&_stateLock);
    return current;
}

- (void)setDemuxCallback:(on_paused_changed_itf)cb data:(void *)data
{
    /* Synchronous: once the demux filter is disabled, the main queue must never
     * call into it again. */
    vlc_mutex_lock(&_stateLock);
    _demux_cb = cb;
    _demux_data = data;
    vlc_mutex_unlock(&_stateLock);
}

- (void)detachStream
{
    vlc_mutex_lock(&_stateLock);
    _p_stream = NULL;
    _demux_cb = NULL;
    _demux_data = NULL;
    vlc_mutex_unlock(&_stateLock);
}

- (void)notifyRemotePaused:(BOOL)paused
{
    vlc_mutex_lock(&_stateLock);
    if (_demux_cb != NULL)
        _demux_cb(_demux_data, paused);
    vlc_mutex_unlock(&_stateLock);
}

- (void)setVlcPaused:(BOOL)paused
{
    _vlcPaused = paused;
    if (!paused)
        _remotePaused = NO;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self->_invalidated)
            return;
        if (paused)
            [self->_player pause];
        else
            [self->_player play];
    });
}

- (void)itemDidPlayToEnd:(NSNotification *)note
{
    if (note.object == _createdPlayerItem && [self createdItemIsCurrent])
    {
        SESSION_LOG(Info, "AirPlay: AVPlayerItemDidPlayToEndTime");
        vlc_mutex_lock(&_stateLock);
        _playToEnd = YES;
        vlc_mutex_unlock(&_stateLock);
    }
}

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary<NSKeyValueChangeKey,id> *)change
                       context:(void *)context
{
    if (context == kAirPlayStatusContext)
    {
        if (object == _createdPlayerItem && [self createdItemIsCurrent])
        {
            AVPlayerItemStatus status = _createdPlayerItem.status;
            if (status == AVPlayerItemStatusReadyToPlay)
            {
                SESSION_LOG(Info, "AirPlay: AVPlayerItem status -> ReadyToPlay");

                __weak typeof(self) weakSelf = self;
                [_createdPlayerItem seekToDate:_epochDate completionHandler:^(BOOL finished) {
                    VLC_UNUSED(finished);
                    dispatch_async(dispatch_get_main_queue(), ^{
                        __strong typeof(weakSelf) strongSelf = weakSelf;
                        if (!strongSelf || strongSelf->_invalidated)
                            return;
                        if (!strongSelf->_vlcPaused)
                            [strongSelf->_player play];
                    });
                }];
                _player.muted = NO;
            }
            else if (status == AVPlayerItemStatusFailed)
            {
                NSError *error = _createdPlayerItem.error;
                SESSION_LOG(Err, "AirPlay: AVPlayerItem status -> Failed: %s",
                            error ? error.localizedDescription.UTF8String : "unknown error");
                vlc_mutex_lock(&_stateLock);
                _itemFailed = YES;
                _lastError = error;
                vlc_mutex_unlock(&_stateLock);
            }
        }
        return;
    }
    if (context == kAirPlayTimeControlStatusContext)
    {
        if (object == _player)
        {
            AVPlayerTimeControlStatus status = _player.timeControlStatus;
            SESSION_LOG(Dbg, "AirPlay: AVPlayer timeControlStatus -> %ld", (long)status);

            /* A pause counts as the TV remote's only once this generation has
             * played: a fresh item starts out paused, and an item that reached
             * its end pauses by itself. Anything else would cork the input
             * while the player waits for data, and both would wait forever. */
            if (status == AVPlayerTimeControlStatusPlaying)
            {
                _playedThisGeneration = YES;
                if (_remotePaused)
                {
                    _remotePaused = NO;
                    [self notifyRemotePaused:NO];
                }
            }
            else if (status == AVPlayerTimeControlStatusPaused)
            {
                if (_playedThisGeneration && !_vlcPaused && !_remotePaused && ![self didPlayToEnd])
                {
                    _remotePaused = YES;
                    [self notifyRemotePaused:YES];
                }
            }
        }
        return;
    }
    [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
}

- (void)startGenerationWithURL:(NSString *)urlString
{
    vlc_mutex_lock(&_stateLock);
    const unsigned generation = _generation;
    vlc_mutex_unlock(&_stateLock);

    dispatch_async(dispatch_get_main_queue(), ^{
        if (self->_invalidated)
            return;
        vlc_mutex_lock(&self->_stateLock);
        const bool stale = generation != self->_generation;
        vlc_mutex_unlock(&self->_stateLock);
        if (stale)
            return;

        if (self->_isObservingItem && self->_createdPlayerItem != nil)
        {
            [self->_createdPlayerItem removeObserver:self
                                         forKeyPath:@"status"
                                            context:kAirPlayStatusContext];
            [[NSNotificationCenter defaultCenter] removeObserver:self
                                                            name:AVPlayerItemDidPlayToEndTimeNotification
                                                          object:self->_createdPlayerItem];
            self->_isObservingItem = NO;
        }

        if (self->_timeObserver != nil)
        {
            [self->_player removeTimeObserver:self->_timeObserver];
            self->_timeObserver = nil;
        }

        self->_playedThisGeneration = NO;

        NSURL *url = [NSURL URLWithString:urlString];
        if (url == nil)
        {
            SESSION_LOG(Err, "AirPlay: invalid URL string %s", urlString.UTF8String);
            vlc_mutex_lock(&self->_stateLock);
            self->_itemFailed = YES;
            vlc_mutex_unlock(&self->_stateLock);
            return;
        }

        AVPlayerItem *item = [AVPlayerItem playerItemWithURL:url];
        self->_createdPlayerItem = item;
        self->_createdGeneration = generation;

        [item addObserver:self
               forKeyPath:@"status"
                  options:NSKeyValueObservingOptionNew
                  context:kAirPlayStatusContext];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(itemDidPlayToEnd:)
                                                     name:AVPlayerItemDidPlayToEndTimeNotification
                                                   object:item];
        self->_isObservingItem = YES;

        [self->_player replaceCurrentItemWithPlayerItem:item];

        __weak typeof(self) weakSelf = self;
        self->_timeObserver = [self->_player addPeriodicTimeObserverForInterval:CMTimeMake(250, 1000)
                                                                          queue:dispatch_get_main_queue()
                                                                     usingBlock:^(CMTime time) {
            VLC_UNUSED(time);
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf || strongSelf->_invalidated)
                return;
            AVPlayerItem *cur = strongSelf->_player.currentItem;
            if (cur != strongSelf->_createdPlayerItem)
                return;
            [strongSelf updateCachedTimeFromDate:cur.currentDate generation:generation];
        }];
    });
}

- (void)resetGeneration
{
    /* Synchronous: pace() and get_time() must never see the previous
     * generation's playback time once the input has been flushed. */
    vlc_mutex_lock(&_stateLock);
    _generation++;
    _cachedTime = VLC_TICK_INVALID;
    _itemFailed = NO;
    _lastError = nil;
    _playToEnd = NO;
    _startedPlayback = NO;
    vlc_mutex_unlock(&_stateLock);

    dispatch_async(dispatch_get_main_queue(), ^{
        if (self->_invalidated)
            return;

        if (self->_isObservingItem && self->_createdPlayerItem != nil)
        {
            [self->_createdPlayerItem removeObserver:self
                                         forKeyPath:@"status"
                                            context:kAirPlayStatusContext];
            [[NSNotificationCenter defaultCenter] removeObserver:self
                                                            name:AVPlayerItemDidPlayToEndTimeNotification
                                                          object:self->_createdPlayerItem];
            self->_isObservingItem = NO;
        }

        if (self->_timeObserver != nil)
        {
            [self->_player removeTimeObserver:self->_timeObserver];
            self->_timeObserver = nil;
        }

        self->_remotePaused = NO;
        self->_playedThisGeneration = NO;
        /* Keep the old item (an AirPlay session ends with the last item) but
         * stop it: its playlist is gone. The next generation replaces it. */
        if (self->_createdPlayerItem != nil && self->_player.currentItem == self->_createdPlayerItem)
            [self->_player pause];
    });
}

- (void)invalidate
{
    dispatch_async(dispatch_get_main_queue(), ^{
        self->_invalidated = YES;
        self->_p_stream = NULL;
        self->_remotePaused = NO;

        if (self->_timeObserver != nil)
        {
            [self->_player removeTimeObserver:self->_timeObserver];
            self->_timeObserver = nil;
        }

        if (self->_isObservingPlayer)
        {
            [self->_player removeObserver:self
                               forKeyPath:@"timeControlStatus"
                                  context:kAirPlayTimeControlStatusContext];
            self->_isObservingPlayer = NO;
        }

        if (self->_isObservingItem && self->_createdPlayerItem != nil)
        {
            [self->_createdPlayerItem removeObserver:self
                                         forKeyPath:@"status"
                                            context:kAirPlayStatusContext];
            self->_isObservingItem = NO;
        }
        [[NSNotificationCenter defaultCenter] removeObserver:self];

        if (self->_isPrivatePlayer || self->_player.currentItem == self->_createdPlayerItem)
        {
            [self->_player pause];
        }

        self->_createdPlayerItem = nil;
        self->_player = nil;
    });
}

@end

static char *GetLocalLANIP(sout_stream_t *p_stream)
{
    int fd = socket(AF_INET, SOCK_DGRAM, 0);
    if (fd >= 0)
    {
        struct sockaddr_in target;
        memset(&target, 0, sizeof(target));
        target.sin_family = AF_INET;
        target.sin_port = htons(9);
        inet_pton(AF_INET, "192.0.2.1", &target.sin_addr);
        if (connect(fd, (struct sockaddr *)&target, sizeof(target)) == 0)
        {
            struct sockaddr_in local;
            socklen_t len = sizeof(local);
            if (getsockname(fd, (struct sockaddr *)&local, &len) == 0)
            {
                char ip_buf[INET_ADDRSTRLEN];
                if (inet_ntop(AF_INET, &local.sin_addr, ip_buf, sizeof(ip_buf)) != NULL)
                {
                    if (strcmp(ip_buf, "0.0.0.0") != 0 && strncmp(ip_buf, "127.", 4) != 0)
                    {
                        close(fd);
                        return strdup(ip_buf);
                    }
                }
            }
        }
        close(fd);
    }

    struct ifaddrs *ifap = NULL;
    if (getifaddrs(&ifap) == 0)
    {
        char *found_en0 = NULL;
        char *found_any = NULL;
        for (struct ifaddrs *ifa = ifap; ifa != NULL; ifa = ifa->ifa_next)
        {
            if (ifa->ifa_addr == NULL || ifa->ifa_addr->sa_family != AF_INET)
                continue;
            if ((ifa->ifa_flags & IFF_LOOPBACK) || !(ifa->ifa_flags & IFF_UP) || !(ifa->ifa_flags & IFF_RUNNING))
                continue;

            struct sockaddr_in *sa = (struct sockaddr_in *)ifa->ifa_addr;
            char ip_buf[INET_ADDRSTRLEN];
            if (inet_ntop(AF_INET, &sa->sin_addr, ip_buf, sizeof(ip_buf)) == NULL)
                continue;
            if (strcmp(ip_buf, "0.0.0.0") == 0 || strncmp(ip_buf, "127.", 4) == 0)
                continue;

            if (strcmp(ifa->ifa_name, "en0") == 0 && found_en0 == NULL)
                found_en0 = strdup(ip_buf);
            else if (found_any == NULL)
                found_any = strdup(ip_buf);
        }
        freeifaddrs(ifap);
        if (found_en0 != NULL)
        {
            free(found_any);
            return found_en0;
        }
        if (found_any != NULL)
            return found_any;
    }

    msg_Warn(p_stream, "AirPlay: unable to determine LAN IPv4, falling back to 127.0.0.1");
    return strdup("127.0.0.1");
}

static void stopInnerChain(sout_stream_t *p_stream)
{
    sout_stream_sys_t *p_sys = (sout_stream_sys_t *)p_stream->p_sys;
    if (p_sys->p_out == NULL)
        return;

    if (p_sys->video_id && p_sys->video_id->p_sub_id)
    {
        sout_StreamIdDel(p_sys->p_out, p_sys->video_id->p_sub_id);
        p_sys->video_id->p_sub_id = NULL;
    }
    if (p_sys->audio_id && p_sys->audio_id->p_sub_id)
    {
        sout_StreamIdDel(p_sys->p_out, p_sys->audio_id->p_sub_id);
        p_sys->audio_id->p_sub_id = NULL;
    }

    sout_StreamChainDelete(p_sys->p_out, NULL);
    p_sys->p_out = NULL;
}

static bool startNewGeneration(sout_stream_t *p_stream)
{
    sout_stream_sys_t *p_sys = (sout_stream_sys_t *)p_stream->p_sys;

    stopInnerChain(p_stream);

    p_sys->generation_idx++;

    if (p_sys->psz_token[0] == '\0')
    {
        uint8_t rand_bytes[8];
        arc4random_buf(rand_bytes, sizeof(rand_bytes));
        snprintf(p_sys->psz_token, sizeof(p_sys->psz_token),
                 "%02x%02x%02x%02x%02x%02x%02x%02x",
                 rand_bytes[0], rand_bytes[1], rand_bytes[2], rand_bytes[3],
                 rand_bytes[4], rand_bytes[5], rand_bytes[6], rand_bytes[7]);
    }

    char path[128];
    snprintf(path, sizeof(path), "/maclc-airplay/%s/%u", p_sys->psz_token, p_sys->generation_idx);

    free(p_sys->generation_url);
    if (asprintf(&p_sys->generation_url, "http://%s:%d%s/stream.m3u8",
                 p_sys->psz_ip, p_sys->i_port, path) == -1)
    {
        p_sys->generation_url = NULL;
        return false;
    }

    msg_Info(p_stream, "AirPlay: generation %u URL: %s",
             p_sys->generation_idx, p_sys->generation_url);

    bool b_has_video = (p_sys->video_id != NULL);
    bool b_has_audio = (p_sys->audio_id != NULL);

    if (!b_has_video && !b_has_audio)
    {
        msg_Dbg(p_stream, "AirPlay: no active tracks to output");
        return true;
    }

    bool b_video_transcode = false;
    int video_vb = 8000;
    if (b_has_video)
    {
        const es_format_t *fmt = &p_sys->video_id->fmt;
        bool can_copy = false;
        if (fmt->i_codec == VLC_CODEC_H264)
        {
            if (fmt->i_profile <= 0 ||
                fmt->i_profile == PROFILE_H264_BASELINE ||
                fmt->i_profile == PROFILE_H264_MAIN ||
                fmt->i_profile == PROFILE_H264_HIGH)
            {
                can_copy = true;
            }
        }
        else if (fmt->i_codec == VLC_CODEC_HEVC)
        {
            if (fmt->i_profile <= 0 ||
                fmt->i_profile == HEVC_PROFILE_IDC_MAIN ||
                fmt->i_profile == HEVC_PROFILE_IDC_MAIN_10)
            {
                can_copy = true;
            }
        }

        if (can_copy)
        {
            msg_Info(p_stream, "AirPlay: video track %d (%.4s) profile=%d -> stream copy",
                     fmt->i_id, (const char *)&fmt->i_codec, fmt->i_profile);
        }
        else
        {
            b_video_transcode = true;
            if (fmt->video.i_height > 0 && fmt->video.i_height <= 720)
                video_vb = 4000;
            else
                video_vb = 8000;
            msg_Info(p_stream, "AirPlay: video track %d (%.4s) profile=%d -> transcode VideoToolbox H.264 (vb=%d kbps)",
                     fmt->i_id, (const char *)&fmt->i_codec, fmt->i_profile, video_vb);
        }
    }

    bool b_audio_transcode = false;
    int audio_ab = 192;
    unsigned audio_channels = 2;
    if (b_has_audio)
    {
        const es_format_t *fmt = &p_sys->audio_id->fmt;
        if (fmt->i_codec == VLC_CODEC_MP4A && fmt->audio.i_channels <= 6 && fmt->audio.i_channels > 0)
        {
            msg_Info(p_stream, "AirPlay: audio track %d (%.4s) -> stream copy (%u channels)",
                     fmt->i_id, (const char *)&fmt->i_codec, fmt->audio.i_channels);
        }
        else
        {
            b_audio_transcode = true;
            unsigned in_ch = fmt->audio.i_channels > 0 ? fmt->audio.i_channels : 2;
            audio_channels = in_ch > 6 ? 6 : in_ch;
            audio_ab = (audio_channels <= 2) ? 192 : 384;
            msg_Info(p_stream, "AirPlay: audio track %d (%.4s) -> transcode AAC (%u channels, %d kbps)",
                     fmt->i_id, (const char *)&fmt->i_codec, audio_channels, audio_ab);
        }
    }

    /* One track per fMP4 playlist: the audio becomes an alternative rendition
     * (EXT-X-MEDIA) of the video variant. AVFoundation rejects this muxer's
     * segments when they carry audio and video together. */
    const char *variants = b_has_video ? "{v}" : "{a}";

    struct vlc_memstream chain;
    vlc_memstream_open(&chain);
    if (b_video_transcode || b_audio_transcode)
    {
        vlc_memstream_puts(&chain, "transcode{");
        bool first_opt = true;
        if (b_video_transcode)
        {
            vlc_memstream_printf(&chain, "vcodec=h264,venc=avcodec{codec=h264_videotoolbox,options{realtime=1}},vb=%d,maxwidth=1920,maxheight=1080",
                                 video_vb);
            first_opt = false;
        }
        if (b_audio_transcode)
        {
            if (!first_opt)
                vlc_memstream_putc(&chain, ',');
            vlc_memstream_printf(&chain, "acodec=mp4a,ab=%d,channels=%u",
                                 audio_ab, audio_channels);
        }
        vlc_memstream_puts(&chain, "}:");
    }

    vlc_memstream_printf(&chain, "hls{seg-type=fmp4,host-http=true,base-url=%s,seg-len=4,max-seg-len=10,num-seg=10,max-memory=800000,program-date-time,variants=\"%s\"}",
                         path, variants);

    if (vlc_memstream_close(&chain) != 0)
        return false;

    msg_Dbg(p_stream, "AirPlay: building inner chain: %s", chain.ptr);

    var_Create(p_stream, "http-port", VLC_VAR_INTEGER);
    var_SetInteger(p_stream, "http-port", p_sys->i_port);
    /* cc_demux already paces the input: no extra muxer delay (as Chromecast). */
    var_Create(p_stream, "sout-mux-caching", VLC_VAR_INTEGER);
    var_SetInteger(p_stream, "sout-mux-caching", 0);

    p_sys->p_out = sout_StreamChainNew(VLC_OBJECT(p_stream), chain.ptr, NULL);
    free(chain.ptr);
    if (p_sys->p_out == NULL)
    {
        msg_Err(p_stream, "AirPlay: failed to create inner sout chain");
        return false;
    }

    if (b_has_video)
    {
        p_sys->video_id->p_sub_id = sout_StreamIdAdd(p_sys->p_out, &p_sys->video_id->fmt, "v");
        if (p_sys->video_id->p_sub_id == NULL)
            msg_Err(p_stream, "AirPlay: failed to add video ES to inner chain");
    }
    if (b_has_audio)
    {
        p_sys->audio_id->p_sub_id = sout_StreamIdAdd(p_sys->p_out, &p_sys->audio_id->fmt, "a");
        if (p_sys->audio_id->p_sub_id == NULL)
            msg_Err(p_stream, "AirPlay: failed to add audio ES to inner chain");
    }

    p_sys->first_pushed_pts = VLC_TICK_INVALID;
    p_sys->newest_pushed_pts = VLC_TICK_INVALID;
    p_sys->last_cached_time = VLC_TICK_INVALID;
    p_sys->last_progress = 0;
    p_sys->b_player_started_for_gen = false;
    p_sys->b_generation_needed = false;

    [p_sys->session resetGeneration];

    return true;
}

static void set_demux_enabled(void *p_opaque, bool enabled, on_paused_changed_itf cb, void *data)
{
    sout_stream_sys_t *p_sys = (sout_stream_sys_t *)p_opaque;
    if (p_sys == NULL)
        return;
    [p_sys->session setDemuxCallback:enabled ? cb : NULL data:enabled ? data : NULL];
}

static vlc_tick_t get_time(void *p_opaque)
{
    sout_stream_sys_t *p_sys = (sout_stream_sys_t *)p_opaque;
    if (p_sys == NULL)
        return VLC_TICK_INVALID;
    return [p_sys->session cachedPlaybackTime];
}

static void pace_interrupt(void *data)
{
    sout_stream_sys_t *p_sys = data;
    vlc_mutex_lock(&p_sys->lock);
    p_sys->b_pace_interrupted = true;
    vlc_cond_signal(&p_sys->pace_cond);
    vlc_mutex_unlock(&p_sys->lock);
}

/* Nothing to do for now: sleep a little instead of letting the input thread
 * spin, but wake up at once for its controls (seek, pause, stop), like the
 * Chromecast output does. The interrupt is (un)registered without the lock:
 * its callback takes the lock while the interrupt context holds its own. */
static void pace_wait(sout_stream_sys_t *p_sys)
{
    vlc_mutex_lock(&p_sys->lock);
    p_sys->b_pace_interrupted = false;
    vlc_mutex_unlock(&p_sys->lock);

    vlc_interrupt_register(pace_interrupt, p_sys);
    vlc_mutex_lock(&p_sys->lock);
    const vlc_tick_t deadline = vlc_tick_now() + VLC_TICK_FROM_MS(200);
    while (!p_sys->b_pace_interrupted
        && vlc_cond_timedwait(&p_sys->pace_cond, &p_sys->lock, deadline) == 0)
        ;
    vlc_mutex_unlock(&p_sys->lock);
    vlc_interrupt_unregister();
}

static int pace(void *p_opaque)
{
    sout_stream_sys_t *p_sys = (sout_stream_sys_t *)p_opaque;
    if (p_sys == NULL)
        return CC_PACE_ERR;

    if ([p_sys->session isItemFailed])
    {
        NSError *err = [p_sys->session itemError];
        msg_Err(p_sys->p_stream, "AirPlay: AVPlayerItem failed: %s",
                err ? err.localizedDescription.UTF8String : "unknown");
        return CC_PACE_ERR;
    }

    vlc_mutex_lock(&p_sys->lock);
    vlc_tick_t first_pts = p_sys->first_pushed_pts;
    vlc_tick_t newest_pts = p_sys->newest_pushed_pts;
    bool b_eof = p_sys->b_input_eof;
    vlc_mutex_unlock(&p_sys->lock);

    vlc_tick_t pushed_diff = 0;
    if (first_pts != VLC_TICK_INVALID && newest_pts != VLC_TICK_INVALID && newest_pts >= first_pts)
        pushed_diff = newest_pts - first_pts;

    vlc_tick_t cached_time = [p_sys->session cachedPlaybackTime];
    BOOL did_play_to_end = [p_sys->session didPlayToEnd];
    BOOL has_started = [p_sys->session hasStartedPlayback];

    if (b_eof)
    {
        /* Done when the player says so, or has played everything, or sits
         * near the end without moving (some streams never report the end). */
        const vlc_tick_t now = vlc_tick_now();
        if (cached_time != p_sys->last_cached_time)
        {
            p_sys->last_cached_time = cached_time;
            p_sys->last_progress = now;
        }
        const bool stalled_at_end = cached_time != VLC_TICK_INVALID
            && pushed_diff - cached_time <= VLC_TICK_FROM_SEC(1)
            && now - p_sys->last_progress >= VLC_TICK_FROM_SEC(5);
        if (did_play_to_end
         || (cached_time != VLC_TICK_INVALID && cached_time + VLC_TICK_FROM_MS(100) >= pushed_diff)
         || stalled_at_end)
        {
            msg_Dbg(p_sys->p_stream, "AirPlay: end of media (pushed %.2fs, played %.2fs, ended %d)",
                    secf_from_vlc_tick(pushed_diff),
                    cached_time != VLC_TICK_INVALID ? secf_from_vlc_tick(cached_time) : -1.0,
                    did_play_to_end);
            return CC_PACE_OK_ENDED;
        }
        /* Everything is pushed: wait for the receiver to play it. */
        pace_wait(p_sys);
        return CC_PACE_OK_WAIT;
    }

    if (!has_started || cached_time == VLC_TICK_INVALID)
    {
        if (pushed_diff > VLC_TICK_FROM_SEC(16))
        {
            vlc_tick_t now = vlc_tick_now();
            if (now - p_sys->last_pace_log > VLC_TICK_FROM_SEC(2))
            {
                msg_Dbg(p_sys->p_stream, "AirPlay: pacing wait before player started (pushed %.2fs > 16s)",
                        secf_from_vlc_tick(pushed_diff));
                p_sys->last_pace_log = now;
            }
            pace_wait(p_sys);
            return CC_PACE_OK_WAIT;
        }
    }
    else
    {
        if (pushed_diff > cached_time + VLC_TICK_FROM_SEC(20))
        {
            vlc_tick_t now = vlc_tick_now();
            if (now - p_sys->last_pace_log > VLC_TICK_FROM_SEC(2))
            {
                msg_Dbg(p_sys->p_stream, "AirPlay: pacing wait (pushed %.2fs > playback %.2fs + 20s)",
                        secf_from_vlc_tick(pushed_diff), secf_from_vlc_tick(cached_time));
                p_sys->last_pace_log = now;
            }
            pace_wait(p_sys);
            return CC_PACE_OK_WAIT;
        }
    }

    return CC_PACE_OK;
}

static void send_input_event(void *p_opaque, enum cc_input_event event, union cc_input_arg arg)
{
    sout_stream_sys_t *p_sys = (sout_stream_sys_t *)p_opaque;
    if (p_sys == NULL)
        return;

    switch (event)
    {
        case CC_INPUT_EVENT_EOF:
        {
            vlc_mutex_lock(&p_sys->lock);
            p_sys->b_input_eof = arg.eof;
            if (arg.eof && p_sys->p_out != NULL)
            {
                if (p_sys->video_id && p_sys->video_id->p_sub_id)
                {
                    sout_StreamIdDel(p_sys->p_out, p_sys->video_id->p_sub_id);
                    p_sys->video_id->p_sub_id = NULL;
                }
                if (p_sys->audio_id && p_sys->audio_id->p_sub_id)
                {
                    sout_StreamIdDel(p_sys->p_out, p_sys->audio_id->p_sub_id);
                    p_sys->audio_id->p_sub_id = NULL;
                }

                if (!p_sys->b_player_started_for_gen && p_sys->generation_url != NULL)
                {
                    p_sys->b_player_started_for_gen = true;
                    [p_sys->session startGenerationWithURL:[NSString stringWithUTF8String:p_sys->generation_url]];
                }
            }
            vlc_mutex_unlock(&p_sys->lock);
            break;
        }
        case CC_INPUT_EVENT_RETRY:
            msg_Dbg(p_sys->p_stream, "AirPlay: input event RETRY received");
            break;
    }
}

static void set_pause_state(void *p_opaque, bool paused)
{
    sout_stream_sys_t *p_sys = (sout_stream_sys_t *)p_opaque;
    if (p_sys == NULL)
        return;
    vlc_mutex_lock(&p_sys->lock);
    p_sys->b_vlc_paused = paused;
    vlc_mutex_unlock(&p_sys->lock);

    [p_sys->session setVlcPaused:paused];
}

static void set_meta(void *p_opaque, vlc_meta_t *p_meta)
{
    VLC_UNUSED(p_opaque);
    VLC_UNUSED(p_meta);
}

static void set_input_length(void *p_opaque, vlc_tick_t length)
{
    VLC_UNUSED(p_opaque);
    VLC_UNUSED(length);
}

static void *Add(sout_stream_t *p_stream, const es_format_t *p_fmt, const char *es_id)
{
    sout_stream_sys_t *p_sys = (sout_stream_sys_t *)p_stream->p_sys;
    vlc_mutex_lock(&p_sys->lock);

    sout_stream_id_sys_t *id = malloc(sizeof(*id));
    if (unlikely(id == NULL))
    {
        vlc_mutex_unlock(&p_sys->lock);
        return NULL;
    }

    es_format_Init(&id->fmt, p_fmt->i_cat, 0);
    es_format_Copy(&id->fmt, p_fmt);
    id->es_id = strdup(es_id ? es_id : "");
    id->p_sub_id = NULL;
    id->b_dummy = false;
    id->pending = NULL;
    id->pending_last = &id->pending;

    if (p_fmt->i_cat == VIDEO_ES && p_sys->video_id == NULL)
    {
        p_sys->video_id = id;
        p_sys->b_generation_needed = true;
        stopInnerChain(p_stream);
        msg_Dbg(p_stream, "AirPlay: selected video ES (track %d, %.4s)",
                p_fmt->i_id, (const char *)&p_fmt->i_codec);
    }
    else if (p_fmt->i_cat == AUDIO_ES && p_sys->audio_id == NULL)
    {
        p_sys->audio_id = id;
        p_sys->b_generation_needed = true;
        stopInnerChain(p_stream);
        msg_Dbg(p_stream, "AirPlay: selected audio ES (track %d, %.4s)",
                p_fmt->i_id, (const char *)&p_fmt->i_codec);
    }
    else
    {
        id->b_dummy = true;
        msg_Dbg(p_stream, "AirPlay: ignoring extra/unsupported ES (cat=%d, track %d, %.4s)",
                p_fmt->i_cat, p_fmt->i_id, (const char *)&p_fmt->i_codec);
    }

    vlc_mutex_unlock(&p_sys->lock);
    return id;
}

static void Del(sout_stream_t *p_stream, void *_id)
{
    sout_stream_sys_t *p_sys = (sout_stream_sys_t *)p_stream->p_sys;
    sout_stream_id_sys_t *id = (sout_stream_id_sys_t *)_id;

    vlc_mutex_lock(&p_sys->lock);
    if (id == p_sys->video_id)
    {
        p_sys->video_id = NULL;
        p_sys->b_generation_needed = true;
        stopInnerChain(p_stream);
        msg_Dbg(p_stream, "AirPlay: removed video ES");
    }
    else if (id == p_sys->audio_id)
    {
        p_sys->audio_id = NULL;
        p_sys->b_generation_needed = true;
        stopInnerChain(p_stream);
        msg_Dbg(p_stream, "AirPlay: removed audio ES");
    }
    vlc_mutex_unlock(&p_sys->lock);

    vlc_frame_ChainRelease(id->pending);
    es_format_Clean(&id->fmt);
    free(id->es_id);
    free(id);
}

static int Send(sout_stream_t *p_stream, void *_id, vlc_frame_t *p_frame)
{
    sout_stream_sys_t *p_sys = (sout_stream_sys_t *)p_stream->p_sys;
    sout_stream_id_sys_t *id = (sout_stream_id_sys_t *)_id;

    if (id->b_dummy)
    {
        vlc_frame_Release(p_frame);
        return VLC_SUCCESS;
    }

    vlc_mutex_lock(&p_sys->lock);

    if (p_sys->b_generation_needed || p_sys->p_out == NULL)
    {
        /* Hold the first frames until every track has shown up: an audio
         * track often starts after the first video frames, and restarting the
         * chain for it would throw away what the chain already received (the
         * TV would start late and the reported time would be off). */
        const vlc_tick_t t = p_frame->i_dts != VLC_TICK_INVALID ? p_frame->i_dts : p_frame->i_pts;
        vlc_frame_ChainLastAppend(&id->pending_last, p_frame);
        if (p_sys->pending_first == VLC_TICK_INVALID)
            p_sys->pending_first = t;
        const bool ready = (p_sys->video_id != NULL && p_sys->audio_id != NULL)
            || (t != VLC_TICK_INVALID && p_sys->pending_first != VLC_TICK_INVALID
                && t - p_sys->pending_first >= VLC_TICK_FROM_MS(1000));
        if (!ready)
        {
            vlc_mutex_unlock(&p_sys->lock);
            return VLC_SUCCESS;
        }
        p_sys->pending_first = VLC_TICK_INVALID;

        vlc_frame_t *held[2] = { NULL, NULL };
        void *held_sub[2] = { NULL, NULL };
        sout_stream_id_sys_t *const ids[2] = { p_sys->video_id, p_sys->audio_id };
        const bool started = startNewGeneration(p_stream);
        for (size_t i = 0; i < 2; ++i)
            if (ids[i] != NULL)
            {
                held[i] = ids[i]->pending;
                held_sub[i] = ids[i]->p_sub_id;
                ids[i]->pending = NULL;
                ids[i]->pending_last = &ids[i]->pending;
            }
        sout_stream_t *p_out = p_sys->p_out;
        for (size_t i = 0; i < 2; ++i)
            for (vlc_frame_t *f = held[i]; f != NULL; f = f->p_next)
            {
                const vlc_tick_t ft = f->i_pts != VLC_TICK_INVALID ? f->i_pts : f->i_dts;
                if (ft == VLC_TICK_INVALID)
                    continue;
                if (p_sys->first_pushed_pts == VLC_TICK_INVALID || ft < p_sys->first_pushed_pts)
                    p_sys->first_pushed_pts = ft;
                if (p_sys->newest_pushed_pts == VLC_TICK_INVALID || ft > p_sys->newest_pushed_pts)
                    p_sys->newest_pushed_pts = ft;
            }
        vlc_mutex_unlock(&p_sys->lock);

        for (size_t i = 0; i < 2; ++i)
        {
            if (!started || held_sub[i] == NULL || p_out == NULL)
            {
                vlc_frame_ChainRelease(held[i]);
                continue;
            }
            while (held[i] != NULL)
            {
                vlc_frame_t *f = held[i];
                held[i] = f->p_next;
                f->p_next = NULL;
                sout_StreamIdSend(p_out, held_sub[i], f);
            }
        }
        return started ? VLC_SUCCESS : VLC_EGENERIC;
    }

    vlc_tick_t pts = (p_frame->i_pts != VLC_TICK_INVALID) ? p_frame->i_pts : p_frame->i_dts;
    if (pts != VLC_TICK_INVALID)
    {
        if (p_sys->first_pushed_pts == VLC_TICK_INVALID)
            p_sys->first_pushed_pts = pts;
        p_sys->newest_pushed_pts = pts;

        vlc_tick_t pushed_diff = pts - p_sys->first_pushed_pts;
        if (pushed_diff >= VLC_TICK_FROM_SEC(9) && !p_sys->b_player_started_for_gen && p_sys->generation_url != NULL)
        {
            p_sys->b_player_started_for_gen = true;
            [p_sys->session startGenerationWithURL:[NSString stringWithUTF8String:p_sys->generation_url]];
        }
    }

    void *sub_id = id->p_sub_id;
    sout_stream_t *p_out = p_sys->p_out;
    vlc_mutex_unlock(&p_sys->lock);

    if (sub_id != NULL && p_out != NULL)
        return sout_StreamIdSend(p_out, sub_id, p_frame);

    vlc_frame_Release(p_frame);
    return VLC_SUCCESS;
}

static void Flush(sout_stream_t *p_stream, void *id)
{
    VLC_UNUSED(id);
    sout_stream_sys_t *p_sys = (sout_stream_sys_t *)p_stream->p_sys;
    msg_Dbg(p_stream, "AirPlay: Flush received, triggering new generation");

    vlc_mutex_lock(&p_sys->lock);
    p_sys->b_generation_needed = true;
    p_sys->first_pushed_pts = VLC_TICK_INVALID;
    p_sys->newest_pushed_pts = VLC_TICK_INVALID;
    p_sys->b_player_started_for_gen = false;
    p_sys->b_input_eof = false;
    p_sys->pending_first = VLC_TICK_INVALID;
    sout_stream_id_sys_t *const held[] = { p_sys->video_id, p_sys->audio_id };
    for (size_t i = 0; i < ARRAY_SIZE(held); ++i)
        if (held[i] != NULL)
        {
            vlc_frame_ChainRelease(held[i]->pending);
            held[i]->pending = NULL;
            held[i]->pending_last = &held[i]->pending;
        }
    stopInnerChain(p_stream);
    vlc_mutex_unlock(&p_sys->lock);

    [p_sys->session resetGeneration];
}

/* The HLS segmenter cuts on the clock: forward it, or no segment ever appears. */
static void SetPCR(sout_stream_t *p_stream, vlc_tick_t pcr)
{
    sout_stream_sys_t *p_sys = (sout_stream_sys_t *)p_stream->p_sys;
    vlc_mutex_lock(&p_sys->lock);
    sout_stream_t *p_out = p_sys->p_out;
    if (p_out != NULL)
        sout_StreamSetPCR(p_out, pcr);
    vlc_mutex_unlock(&p_sys->lock);
}

static int Control(sout_stream_t *p_stream, int i_query, va_list args)
{
    VLC_UNUSED(p_stream);
    switch (i_query)
    {
        case SOUT_STREAM_IS_SYNCHRONOUS:
            *va_arg(args, bool *) = false;
            return VLC_SUCCESS;
        default:
            return VLC_EGENERIC;
    }
}

static void Close(sout_stream_t *p_stream)
{
    sout_stream_sys_t *p_sys = (sout_stream_sys_t *)p_stream->p_sys;
    if (p_sys == NULL)
        return;
    p_stream->p_sys = NULL;

    msg_Dbg(p_stream, "AirPlay: closing stream output");

    vlc_object_t *parent1 = vlc_object_parent(p_stream);
    vlc_object_t *parent2 = parent1 ? vlc_object_parent(parent1) : NULL;
    if (parent2 != NULL)
    {
        var_SetAddress(parent2, CC_SHARED_VAR_NAME, NULL);
        var_Destroy(parent2, CC_SHARED_VAR_NAME);
    }

    vlc_mutex_lock(&p_sys->lock);
    stopInnerChain(p_stream);
    vlc_mutex_unlock(&p_sys->lock);

    [p_sys->session detachStream];
    [p_sys->session invalidate];
    p_sys->session = nil;

    free(p_sys->psz_ip);
    free(p_sys->psz_device_name);
    free(p_sys->generation_url);

    free(p_sys);
}

static const struct sout_stream_operations ops = {
    .add = Add,
    .del = Del,
    .send = Send,
    .flush = Flush,
    .set_pcr = SetPCR,
    .control = Control,
    .close = Close,
};

static int Open(vlc_object_t *p_this)
{
    sout_stream_t *p_stream = (sout_stream_t *)p_this;

    sout_stream_sys_t *p_sys = malloc(sizeof(*p_sys));
    if (unlikely(p_sys == NULL))
        return VLC_ENOMEM;

    vlc_mutex_init(&p_sys->lock);
    vlc_cond_init(&p_sys->pace_cond);
    p_sys->b_pace_interrupted = false;
    p_sys->pending_first = VLC_TICK_INVALID;
    p_sys->last_cached_time = VLC_TICK_INVALID;
    p_sys->last_progress = 0;
    p_sys->p_stream = p_stream;
    p_sys->psz_ip = NULL;
    p_sys->i_port = 8011;
    p_sys->psz_device_name = NULL;
    p_sys->psz_token[0] = '\0';
    p_sys->generation_idx = 0;
    p_sys->generation_url = NULL;
    p_sys->b_generation_needed = true;
    p_sys->b_player_started_for_gen = false;
    p_sys->b_input_eof = false;
    p_sys->b_vlc_paused = false;
    p_sys->first_pushed_pts = VLC_TICK_INVALID;
    p_sys->newest_pushed_pts = VLC_TICK_INVALID;
    p_sys->last_pace_log = 0;
    p_sys->video_id = NULL;
    p_sys->audio_id = NULL;
    p_sys->p_out = NULL;
    p_sys->session = nil;

    config_ChainParse(p_stream, SOUT_CFG_PREFIX, ppsz_sout_options, p_stream->p_cfg);

    char *psz_cfg_ip = var_GetNonEmptyString(p_stream, SOUT_CFG_PREFIX "ip");
    if (psz_cfg_ip != NULL && strcmp(psz_cfg_ip, "0.0.0.0") != 0)
        p_sys->psz_ip = psz_cfg_ip;
    else
    {
        free(psz_cfg_ip);
        p_sys->psz_ip = GetLocalLANIP(p_stream);
    }

    p_sys->i_port = var_InheritInteger(p_stream, SOUT_CFG_PREFIX "port");
    if (p_sys->i_port <= 0)
        p_sys->i_port = 8011;

    p_sys->psz_device_name = var_GetNonEmptyString(p_stream, SOUT_CFG_PREFIX "device-name");

    msg_Info(p_stream, "AirPlay: streaming to device='%s' via LAN IP %s:%d",
             p_sys->psz_device_name ? p_sys->psz_device_name : "(unknown)",
             p_sys->psz_ip, p_sys->i_port);

    void *player_addr = var_InheritAddress(p_stream, "maclc-airplay-player");
    AVPlayer *player = nil;
    BOOL is_private = NO;
    if (player_addr != NULL)
    {
        player = (__bridge AVPlayer *)player_addr;
        msg_Info(p_stream, "AirPlay: using GUI AVPlayer instance (%p)", player_addr);
    }
    else
    {
        player = [[AVPlayer alloc] init];
        is_private = YES;
        msg_Info(p_stream, "AirPlay: created private AVPlayer instance for local playback");
    }

    p_sys->session = [[MacLCAirPlaySession alloc] initWithStream:p_stream
                                                          player:player
                                                 isPrivatePlayer:is_private];
    if (p_sys->session == nil)
    {
        free(p_sys->psz_ip);
        free(p_sys->psz_device_name);
        free(p_sys);
        return VLC_ENOMEM;
    }

    p_sys->common.p_opaque = p_sys;
    p_sys->common.pf_set_demux_enabled = set_demux_enabled;
    p_sys->common.pf_get_time = get_time;
    p_sys->common.pf_pace = pace;
    p_sys->common.pf_send_input_event = send_input_event;
    p_sys->common.pf_set_pause_state = set_pause_state;
    p_sys->common.pf_set_meta = set_meta;
    p_sys->common.pf_set_input_length = set_input_length;

    vlc_object_t *parent1 = vlc_object_parent(p_stream);
    vlc_object_t *parent2 = parent1 ? vlc_object_parent(parent1) : NULL;
    if (parent2 != NULL)
    {
        var_Create(parent2, CC_SHARED_VAR_NAME, VLC_VAR_ADDRESS);
        var_SetAddress(parent2, CC_SHARED_VAR_NAME, &p_sys->common);
    }

    p_stream->ops = &ops;
    p_stream->p_sys = p_sys;

    return VLC_SUCCESS;
}

vlc_module_begin()
    set_shortname("AirPlay")
    set_description(N_("AirPlay stream output"))
    set_capability("sout output", 0)
    add_shortcut("airplay")
    set_subcategory(SUBCAT_SOUT_STREAM)
    add_string(SOUT_CFG_PREFIX "ip", NULL, NULL, NULL) change_private()
    add_integer(SOUT_CFG_PREFIX "port", 8011, N_("HTTP port"), N_("Port of the local HTTP server the TV reads from."))
    add_string(SOUT_CFG_PREFIX "device-name", NULL, NULL, NULL) change_private()
    set_callbacks(Open, Close)
vlc_module_end()
