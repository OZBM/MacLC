/*****************************************************************************
 * MacLCStatsOverlay.m: live playback figures and the Stats for Nerds panel
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

#import "MacLCStatsOverlay.h"

#import <vlc_common.h>
#import <vlc_es.h>
#import <vlc_input_item.h>

#import "extensions/NSString+Helpers.h"
#import "extensions/NSView+VLCAdditions.h"
#import "frameinterp/MacLCFrameInterpolation.h"
#import "hdr/MacLCHDRController.h"
#import "hdr/MacLCHDRStreamInfo.h"
#import "hdr/MacLCHDRTypes.h"
#import "hdr/MacLCSDRToHDRState.h"
#import "library/VLCInputItem.h"
#import "main/VLCMain.h"
#import "playqueue/VLCPlayQueueController.h"
#import "playqueue/VLCPlayerController.h"
#import "theme/MacLCDesign.h"
#import "theme/MacLCGlassView.h"
#import "torrent/MacLCTorrentMonitor.h"
#import "torrent/MacLCTorrentStats.h"
#import "upscale/MacLCUpscaling.h"

#include "../../../../video_filter/maclc_frc_geometry.h"

NSNotificationName const MacLCPlaybackMetricsDidChangeNotification = @"MacLCPlaybackMetricsDidChangeNotification";
NSNotificationName const MacLCStatsOverlayToggleNotification = @"MacLCStatsOverlayToggleNotification";

static VLCPlayerController *MetricsPlayer(void)
{
    return VLCMain.sharedInstance.playQueueController.playerController;
}

#pragma mark - metrics

@implementation MacLCPlaybackMetrics
{
    int64_t _lastDecoded, _lastDisplayed, _lastDropped;
    CFTimeInterval _lastTime;
    BOOL _primed;
}

+ (MacLCPlaybackMetrics *)sharedMetrics
{
    static MacLCPlaybackMetrics *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [[MacLCPlaybackMetrics alloc] init]; });
    return shared;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        NSNotificationCenter * const center = NSNotificationCenter.defaultCenter;
        [center addObserver:self selector:@selector(statisticsUpdated:)
                       name:VLCPlayerStatisticsUpdated object:nil];
        [center addObserver:self selector:@selector(mediaChanged:)
                       name:VLCPlayerCurrentMediaItemChanged object:nil];
    }
    return self;
}

- (void)mediaChanged:(NSNotification *)notification
{
    _primed = NO;
    _decodedFrameRate = _displayedFrameRate = _droppedFrameRate = 0.0;
    [NSNotificationCenter.defaultCenter postNotificationName:MacLCPlaybackMetricsDidChangeNotification object:self];
}

static double Smoothed(double previous, double sample)
{
    return previous <= 0.0 ? sample : previous * 0.6 + sample * 0.4;
}

- (void)statisticsUpdated:(NSNotification *)notification
{
    VLCPlayerController * const player = MetricsPlayer();
    VLCInputStats * const stats = player.statistics;
    if (stats == nil)
        return;

    const CFTimeInterval now = CACurrentMediaTime();
    const int64_t dropped = stats.latePictures + stats.lostPictures;
    const BOOL playing = player.playerState == VLC_PLAYER_STATE_PLAYING;
    if (_primed && playing && now - _lastTime > 0.2) {
        const double elapsed = now - _lastTime;
        const double rate = player.playbackRate > 0.0f ? player.playbackRate : 1.0;
        const int64_t decoded = stats.decodedVideo - _lastDecoded;
        const int64_t displayed = stats.displayedPictures - _lastDisplayed;
        /* The counters start again with each input: a step back is a reset. */
        if (decoded >= 0 && displayed >= 0 && dropped >= _lastDropped) {
            _decodedFrameRate = Smoothed(_decodedFrameRate, decoded / elapsed / rate);
            _displayedFrameRate = Smoothed(_displayedFrameRate, displayed / elapsed);
            _droppedFrameRate = Smoothed(_droppedFrameRate, (dropped - _lastDropped) / elapsed);
        }
    }
    _lastDecoded = stats.decodedVideo;
    _lastDisplayed = stats.displayedPictures;
    _lastDropped = dropped;
    _lastTime = now;
    _primed = YES;
    /* Bytes per microsecond. */
    _inputBitrate = stats.inputBitrate * 8000.0;
    _demuxBitrate = stats.demuxBitrate * 8000.0;

    [NSNotificationCenter.defaultCenter postNotificationName:MacLCPlaybackMetricsDidChangeNotification object:self];
}

+ (double)snappedFrameRate:(double)rate
{
    static const double known[] = { 23.976, 24.0, 25.0, 29.97, 30.0, 48.0, 50.0,
                                    59.94, 60.0, 100.0, 119.88, 120.0 };
    double best = rate, distance = DBL_MAX;
    for (size_t i = 0; i < ARRAY_SIZE(known); i++) {
        const double d = fabs(rate - known[i]) / known[i];
        if (d < 0.03 && d < distance) {
            distance = d;
            best = known[i];
        }
    }
    return best;
}

- (double)exactSourceFrameRate
{
    const unsigned declared = MetricsPlayer().selectedVideoTrack.videoFrameRate;
    if (declared > 0)
        return declared;
    return _decodedFrameRate > 1.0 ? [MacLCPlaybackMetrics snappedFrameRate:_decodedFrameRate] : 0.0;
}

- (unsigned)sourceFrameRate
{
    return (unsigned)lround(self.exactSourceFrameRate);
}

@end

#pragma mark - panel

static MacLCStatsOverlayView *gShownOverlay;

@implementation MacLCStatsOverlayView
{
    NSTextField *_textField;
    NSTimer *_timer;
}

+ (BOOL)isShown
{
    return gShownOverlay != nil;
}

+ (void)toggleInView:(NSView *)host topInset:(CGFloat)topInset
{
    if (gShownOverlay != nil) {
        MacLCStatsOverlayView * const overlay = gShownOverlay;
        gShownOverlay = nil;
        [overlay->_timer invalidate];
        [MacLCDesign animateExitOfView:overlay completion:^{ [overlay removeFromSuperview]; }];
        return;
    }
    (void)MacLCPlaybackMetrics.sharedMetrics;
    MacLCStatsOverlayView * const overlay = [[MacLCStatsOverlayView alloc] initWithFrame:NSZeroRect];
    overlay.translatesAutoresizingMaskIntoConstraints = NO;
    [host addSubview:overlay];
    [NSLayoutConstraint activateConstraints:@[
        [overlay.leadingAnchor constraintEqualToAnchor:host.leadingAnchor constant:16.0],
        [overlay.topAnchor constraintEqualToAnchor:host.topAnchor constant:topInset],
        [overlay.widthAnchor constraintEqualToConstant:500.0],
    ]];
    gShownOverlay = overlay;
    [overlay refresh];
    [MacLCDesign animateEntranceOfView:overlay];
}

- (instancetype)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (self) {
        self.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
        self.accessibilityLabel = _NS("Stats for Nerds");

        MacLCGlassView * const glass = [[MacLCGlassView alloc] initWithFrame:NSZeroRect];
        glass.translatesAutoresizingMaskIntoConstraints = NO;
        glass.cornerRadius = 16.0;
        glass.forcesDarkAppearance = YES;
        [self addSubview:glass];
        [glass applyConstraintsToFillSuperview];

        _textField = [NSTextField wrappingLabelWithString:@""];
        _textField.translatesAutoresizingMaskIntoConstraints = NO;
        _textField.selectable = YES;
        _textField.font = [NSFont monospacedSystemFontOfSize:11.0 weight:NSFontWeightRegular];
        [glass.contentView addSubview:_textField];

        NSButton * const close = [NSButton buttonWithImage:[MacLCDesign symbolNamed:@"xmark.circle.fill" accessibilityLabel:_NS("Close Stats for Nerds")]
                                                    target:self
                                                    action:@selector(close:)];
        close.translatesAutoresizingMaskIntoConstraints = NO;
        close.bordered = NO;
        close.contentTintColor = MacLCDesign.secondaryLabel;
        close.toolTip = _NS("Close");
        [glass.contentView addSubview:close];

        [NSLayoutConstraint activateConstraints:@[
            [_textField.leadingAnchor constraintEqualToAnchor:glass.contentView.leadingAnchor constant:14.0],
            [_textField.trailingAnchor constraintEqualToAnchor:close.leadingAnchor constant:-6.0],
            [_textField.topAnchor constraintEqualToAnchor:glass.contentView.topAnchor constant:12.0],
            [_textField.bottomAnchor constraintEqualToAnchor:glass.contentView.bottomAnchor constant:-12.0],
            [close.topAnchor constraintEqualToAnchor:glass.contentView.topAnchor constant:10.0],
            [close.trailingAnchor constraintEqualToAnchor:glass.contentView.trailingAnchor constant:-10.0],
        ]];

        _timer = [NSTimer timerWithTimeInterval:0.5 target:self selector:@selector(tick:) userInfo:nil repeats:YES];
        _timer.tolerance = 0.1;
        [NSRunLoop.mainRunLoop addTimer:_timer forMode:NSRunLoopCommonModes];
    }
    return self;
}

- (void)close:(id)sender
{
    if (gShownOverlay == self)
        [MacLCStatsOverlayView toggleInView:self.superview topInset:0.0];
}

- (void)tick:(NSTimer *)timer
{
    if (self.window == nil) {
        [timer invalidate];
        if (gShownOverlay == self)
            gShownOverlay = nil;
        return;
    }
    [self refresh];
}

static NSString *FormatRate(double kbps)
{
    return kbps >= 1000.0 ? [NSString stringWithFormat:@"%.1f Mb/s", kbps / 1000.0]
                          : [NSString stringWithFormat:@"%.0f kb/s", kbps];
}

/* Every line the core wrote about a stream ("Stream '1/video/0'"), as it wrote
 * them, codec and colour description included. */
static void AddTrackInfo(NSMutableArray<NSArray<NSString *> *> *rows, NSString *heading,
                         VLCTrackMetaData *track, input_item_t *item)
{
    if (track == nil || track.esID == NULL || item == NULL)
        return;
    const char * const strID = vlc_es_id_GetStrId(track.esID);
    NSString * const needle = [NSString stringWithFormat:@"'%s'", strID ?: ""];
    NSMutableArray<NSArray<NSString *> *> * const found = [NSMutableArray array];
    vlc_mutex_lock(&item->lock);
    info_category_t *cat;
    vlc_list_foreach(cat, &item->categories, node) {
        if (cat->psz_name == NULL || ![@(cat->psz_name) containsString:needle])
            continue;
        info_t *info;
        info_foreach(info, &cat->infos) {
            NSString * const name = info->psz_name ? @(info->psz_name) : @"";
            if ([name isEqualToString:@"Type"] || info->psz_value == NULL)
                continue;
            [found addObject:@[name, @(info->psz_value)]];
        }
    }
    vlc_mutex_unlock(&item->lock);
    if (found.count == 0)
        return;
    [rows addObject:@[heading, @""]];
    [rows addObjectsFromArray:found];
}

- (NSArray<NSArray<NSString *> *> *)rows
{
    VLCPlayerController * const player = MetricsPlayer();
    MacLCPlaybackMetrics * const metrics = MacLCPlaybackMetrics.sharedMetrics;
    NSMutableArray<NSArray<NSString *> *> * const rows = [NSMutableArray array];

    VLCInputItem * const media = player.currentMedia;
    if (media == nil) {
        [rows addObject:@[_NS("Playback"), _NS("Nothing is playing")]];
        return rows;
    }
    [rows addObject:@[_NS("Title"), media.name ?: @""]];

    /* Frames: what the file has, and what reaches the screen. */
    const double source = metrics.exactSourceFrameRate;
    const BOOL declared = player.selectedVideoTrack.videoFrameRate > 0;
    NSString * const sourceText = source > 0.0
        ? [NSString stringWithFormat:declared ? @"%.3g fps" : _NS("%.3g fps (measured)"), source]
        : _NS("unknown");
    [rows addObject:@[_NS("Source rate"), sourceText]];
    [rows addObject:@[_NS("Shown rate"), metrics.displayedFrameRate > 0.0
        ? [NSString stringWithFormat:@"%.1f fps", metrics.displayedFrameRate] : @"–"]];
    [rows addObject:@[_NS("Dropped"), [NSString stringWithFormat:_NS("%.1f per second"), metrics.droppedFrameRate]]];
    if (MacLCFrameInterpolation.isEnabled) {
        const unsigned output = [MacLCFrameInterpolation outputFrameRateForSourceFrameRate:metrics.sourceFrameRate];
        [rows addObject:@[_NS("Interpolation"),
            [NSString stringWithFormat:@"%@, %@%@",
                [MacLCFrameInterpolation nameForEngine:MacLCFrameInterpolation.engine],
                [MacLCFrameInterpolation nameForTarget:MacLCFrameInterpolation.target],
                output > 0 ? [NSString stringWithFormat:_NS(" (aims for %u fps)"), output] : @""]]];
    } else {
        [rows addObject:@[_NS("Interpolation"), _NS("Off")]];
    }

    /* Picture. */
    NSView * const host = self.superview;
    if (host != nil) {
        const CGFloat scale = host.window.backingScaleFactor ?: 1.0;
        [rows addObject:@[_NS("Viewport"), [NSString stringWithFormat:@"%.0f×%.0f px",
            NSWidth(host.bounds) * scale, NSHeight(host.bounds) * scale]]];
    }
    [rows addObject:@[_NS("Upscaling"), MacLCUpscaling.isEnabled
        ? (MacLCUpscaling.activeMethodName != nil
            ? [NSString stringWithFormat:@"%@ %@", MacLCUpscaling.activeMethodName, MacLCUpscaling.badgeTitle ?: @""]
            : MacLCUpscaling.statusText)
        : _NS("Off")]];

    MacLCHDRController * const hdr = MacLCHDRController.sharedController;
    NSString *dynamicRange;
    if (hdr.stream.isHDR) {
        dynamicRange = MacLCHDRPresentationDisplayName(hdr.activePresentation);
    } else {
        MacLCSDRToHDRState * const state = MacLCSDRToHDRState.sharedState;
        dynamicRange = state.enabled
            ? [NSString stringWithFormat:_NS("SDR shown in HDR (%@)"),
                [MacLCSDRToHDRState displayNameForQuality:state.activeQuality]]
            : _NS("SDR");
    }
    [rows addObject:@[_NS("Dynamic range"), dynamicRange]];

    NSScreen * const screen = self.window.screen ?: NSScreen.mainScreen;
    [rows addObject:@[_NS("Display"), [NSString stringWithFormat:_NS("%u Hz, headroom %.1f× now, %.1f× at most"),
        maclc_frc_display_refresh_rate(),
        screen.maximumExtendedDynamicRangeColorComponentValue,
        screen.maximumPotentialExtendedDynamicRangeColorComponentValue]]];

    /* Network. */
    [rows addObject:@[_NS("Input"), [NSString stringWithFormat:_NS("%@ read, %@ demuxed"),
        FormatRate(metrics.inputBitrate), FormatRate(metrics.demuxBitrate)]]];
    MacLCTorrentMonitor * const torrent = MacLCTorrentMonitor.sharedMonitor;
    if (torrent.isActive && torrent.torrent != nil) {
        MacLCTorrentInfo * const info = torrent.torrent;
        NSString * const ahead = torrent.reader != nil
            ? [NSByteCountFormatter stringFromByteCount:(long long)torrent.reader.ahead countStyle:NSByteCountFormatterCountStyleFile]
            : @"–";
        [rows addObject:@[_NS("Torrent"), [NSString stringWithFormat:_NS("%@/s from %ld peers, %@ ahead"),
            [NSByteCountFormatter stringFromByteCount:info.downloadRate countStyle:NSByteCountFormatterCountStyleFile],
            (long)info.peers, ahead]]];
    }

    input_item_t * const item = media.vlcInputItem;
    AddTrackInfo(rows, _NS("Video stream"), player.selectedVideoTrack, item);
    AddTrackInfo(rows, _NS("Audio stream"), player.selectedAudioTrack, item);
    return rows;
}

- (void)refresh
{
    NSMutableParagraphStyle * const paragraph = [[NSMutableParagraphStyle alloc] init];
    paragraph.tabStops = @[[[NSTextTab alloc] initWithTextAlignment:NSTextAlignmentLeft location:176.0 options:@{}]];
    paragraph.headIndent = 176.0;
    paragraph.lineBreakMode = NSLineBreakByTruncatingTail;
    NSFont * const font = [NSFont monospacedSystemFontOfSize:11.0 weight:NSFontWeightRegular];
    NSFont * const bold = [NSFont monospacedSystemFontOfSize:11.0 weight:NSFontWeightSemibold];
    NSDictionary * const labelAttributes = @{ NSFontAttributeName: font, NSForegroundColorAttributeName: MacLCDesign.secondaryLabel, NSParagraphStyleAttributeName: paragraph };
    NSDictionary * const valueAttributes = @{ NSFontAttributeName: font, NSForegroundColorAttributeName: MacLCDesign.primaryLabel, NSParagraphStyleAttributeName: paragraph };
    NSDictionary * const headingAttributes = @{ NSFontAttributeName: bold, NSForegroundColorAttributeName: MacLCDesign.primaryLabel, NSParagraphStyleAttributeName: paragraph };

    NSMutableAttributedString * const text = [[NSMutableAttributedString alloc] init];
    for (NSArray<NSString *> * const row in self.rows) {
        if (text.length > 0)
            [text appendAttributedString:[[NSAttributedString alloc] initWithString:@"\n" attributes:valueAttributes]];
        if (row[1].length == 0) {
            [text appendAttributedString:[[NSAttributedString alloc] initWithString:row[0] attributes:headingAttributes]];
            continue;
        }
        [text appendAttributedString:[[NSAttributedString alloc] initWithString:[row[0] stringByAppendingString:@"\t"] attributes:labelAttributes]];
        [text appendAttributedString:[[NSAttributedString alloc] initWithString:row[1] attributes:valueAttributes]];
    }
    /* Selection would be lost on every refresh: keep the text while selecting. */
    if (_textField.currentEditor == nil)
        _textField.attributedStringValue = text;
}

@end
