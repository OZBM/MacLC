/*****************************************************************************
 * MacLCSDRToHDRState.m: single source of truth for MacLC's SDR to HDR GUI
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

#import "MacLCSDRToHDRState.h"

#import "main/VLCMain.h"
#import "playqueue/VLCPlayQueueController.h"
#import "playqueue/VLCPlayerController.h"
#import "settings/MacLCConfigSafe.h"
#import "settings/panes/MacLCHDRSettingsViewController.h"
#import "extensions/NSString+Helpers.h"

#include <vlc_common.h>
#include <vlc_configuration.h>
#include <vlc_variables.h>
#include <vlc_vout.h>

NSString * const MacLCSDRToHDRStateDidChangeNotification = @"MacLCSDRToHDRStateDidChangeNotification";

@implementation MacLCSDRToHDRState
{
    BOOL _enabled;
    MacLCSDRToHDRQuality _quality;
    float _boost;
    float _midtones;
    float _saturation;
    NSInteger _deband;
    BOOL _protect;

    NSString *_activeQualityName;
    MacLCSDRToHDRQuality _activeQuality;
    NSString *_reason;
    float _activePeakNits;
    BOOL _comparing;

    NSTimer *_pollTimer;
    NSInteger _pollingCount;
}

+ (instancetype)sharedState
{
    static MacLCSDRToHDRState *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        shared = [[MacLCSDRToHDRState alloc] initPrivate];
    });
    return shared;
}

- (instancetype)initPrivate
{
    self = [super init];
    if (self) {
        _enabled = MacLCConfigGetInt(MACLC_SDR2HDR_VAR_ENABLED, 0) != 0;

        char *psz_quality = MacLCConfigGetPsz(MACLC_SDR2HDR_VAR_QUALITY);
        _quality = (MacLCSDRToHDRQuality)maclc_sdr2hdr_quality_parse(psz_quality);
        free(psz_quality);

        _boost = MacLCConfigGetFloat(MACLC_SDR2HDR_VAR_BOOST, MACLC_SDR2HDR_BOOST_DEFAULT);
        if (_boost < MACLC_SDR2HDR_BOOST_MIN) _boost = MACLC_SDR2HDR_BOOST_MIN;
        if (_boost > MACLC_SDR2HDR_BOOST_MAX) _boost = MACLC_SDR2HDR_BOOST_MAX;

        _midtones = MacLCConfigGetFloat(MACLC_SDR2HDR_VAR_MIDTONES, MACLC_SDR2HDR_MIDTONES_DEFAULT);
        if (_midtones < 0.0f) _midtones = 0.0f;
        if (_midtones > 1.0f) _midtones = 1.0f;

        _saturation = MacLCConfigGetFloat(MACLC_SDR2HDR_VAR_SATURATION, MACLC_SDR2HDR_SATURATION_DEFAULT);
        if (_saturation < MACLC_SDR2HDR_SATURATION_MIN) _saturation = MACLC_SDR2HDR_SATURATION_MIN;
        if (_saturation > MACLC_SDR2HDR_SATURATION_MAX) _saturation = MACLC_SDR2HDR_SATURATION_MAX;

        char *psz_deband = MacLCConfigGetPsz(MACLC_SDR2HDR_VAR_DEBAND);
        _deband = maclc_sdr2hdr_deband_parse(psz_deband);
        free(psz_deband);

        _protect = MacLCConfigGetInt(MACLC_SDR2HDR_VAR_PROTECT, 1) != 0;

        _activeQuality = MacLCSDRToHDRQualityAuto;
        _activePeakNits = 0.0f;

        NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
        for (NSString *name in @[VLCPlayerCurrentMediaItemChanged,
                                 VLCPlayerTrackSelectionChanged,
                                 VLCPlayerListOfVideoOutputThreadsChanged,
                                 NSApplicationDidChangeScreenParametersNotification,
                                 NSWindowDidChangeScreenNotification]) {
            [center addObserver:self
                       selector:@selector(environmentDidChange:)
                           name:name
                         object:nil];
        }

        [self refresh];
    }
    return self;
}

- (void)dealloc
{
    [_pollTimer invalidate];
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)environmentDidChange:(NSNotification *)notification
{
    [self refresh];
}

#pragma mark - Properties

- (BOOL)enabled { return _enabled; }
- (MacLCSDRToHDRQuality)quality { return _quality; }
- (float)boost { return _boost; }
- (float)midtones { return _midtones; }
- (float)saturation { return _saturation; }
- (NSInteger)deband { return _deband; }
- (BOOL)protect { return _protect; }

- (NSString *)activeQualityName { return _activeQualityName; }
- (MacLCSDRToHDRQuality)activeQuality { return _activeQuality; }
- (NSString *)reason { return _reason; }
- (float)activePeakNits { return _activePeakNits; }
- (BOOL)isComparing { return _comparing; }

#pragma mark - Setters

/* Sliders call the setters continuously while they move: write the
 * configuration file once they have been still for half a second instead of
 * at every step. */
- (void)scheduleSave
{
    [NSObject cancelPreviousPerformRequestsWithTarget:self
                                             selector:@selector(saveNow)
                                               object:nil];
    [self performSelector:@selector(saveNow) withObject:nil afterDelay:0.5];
}

- (void)saveNow
{
    config_SaveConfigFile(getIntf());
}

- (void)pushToVoutWithBlock:(void (^)(vout_thread_t *vout))block
{
    VLCPlayerController *playerController = VLCMain.sharedInstance.playQueueController.playerController;
    vout_thread_t *vout = [playerController mainVideoOutputThread];
    if (vout != NULL) {
        if (block) {
            block(vout);
        }
        vout_Release(vout);
    }
}

- (void)notifyChanges
{
    [NSNotificationCenter.defaultCenter postNotificationName:MacLCHDRExpansionChangedNotification object:self];
    [NSNotificationCenter.defaultCenter postNotificationName:MacLCSDRToHDRStateDidChangeNotification object:self];
}

- (void)setEnabled:(BOOL)enabled
{
    if (_enabled == enabled)
        return;
    _enabled = enabled;
    MacLCConfigPutInt(MACLC_SDR2HDR_VAR_ENABLED, enabled ? 1 : 0);
    [self scheduleSave];

    [self pushToVoutWithBlock:^(vout_thread_t *vout) {
        if (var_Type(vout, MACLC_SDR2HDR_VAR_ENABLED) != 0) {
            var_SetBool(vout, MACLC_SDR2HDR_VAR_ENABLED, enabled);
        }
    }];
    [self refresh];
    [self notifyChanges];
}

- (void)setQuality:(MacLCSDRToHDRQuality)quality
{
    if (_quality == quality)
        return;
    _quality = quality;
    const char *qStr = maclc_sdr2hdr_quality_name((enum maclc_sdr2hdr_quality)quality);
    MacLCConfigPutPsz(MACLC_SDR2HDR_VAR_QUALITY, qStr);
    [self scheduleSave];

    [self pushToVoutWithBlock:^(vout_thread_t *vout) {
        if (var_Type(vout, MACLC_SDR2HDR_VAR_QUALITY) != 0) {
            var_SetString(vout, MACLC_SDR2HDR_VAR_QUALITY, qStr);
        }
    }];
    [self refresh];
    [self notifyChanges];
}

- (void)setBoost:(float)boost
{
    if (boost < MACLC_SDR2HDR_BOOST_MIN) boost = MACLC_SDR2HDR_BOOST_MIN;
    if (boost > MACLC_SDR2HDR_BOOST_MAX) boost = MACLC_SDR2HDR_BOOST_MAX;
    if (fabsf(_boost - boost) < 1e-4f)
        return;
    _boost = boost;
    MacLCConfigPutFloat(MACLC_SDR2HDR_VAR_BOOST, boost);
    [self scheduleSave];

    [self pushToVoutWithBlock:^(vout_thread_t *vout) {
        if (var_Type(vout, MACLC_SDR2HDR_VAR_BOOST) != 0) {
            var_SetFloat(vout, MACLC_SDR2HDR_VAR_BOOST, boost);
        }
    }];
    [self refresh];
    [self notifyChanges];
}

- (void)setMidtones:(float)midtones
{
    if (midtones < 0.0f) midtones = 0.0f;
    if (midtones > 1.0f) midtones = 1.0f;
    if (fabsf(_midtones - midtones) < 1e-4f)
        return;
    _midtones = midtones;
    MacLCConfigPutFloat(MACLC_SDR2HDR_VAR_MIDTONES, midtones);
    [self scheduleSave];

    [self pushToVoutWithBlock:^(vout_thread_t *vout) {
        if (var_Type(vout, MACLC_SDR2HDR_VAR_MIDTONES) != 0) {
            var_SetFloat(vout, MACLC_SDR2HDR_VAR_MIDTONES, midtones);
        }
    }];
    [self refresh];
    [self notifyChanges];
}

- (void)setSaturation:(float)saturation
{
    if (saturation < MACLC_SDR2HDR_SATURATION_MIN) saturation = MACLC_SDR2HDR_SATURATION_MIN;
    if (saturation > MACLC_SDR2HDR_SATURATION_MAX) saturation = MACLC_SDR2HDR_SATURATION_MAX;
    if (fabsf(_saturation - saturation) < 1e-4f)
        return;
    _saturation = saturation;
    MacLCConfigPutFloat(MACLC_SDR2HDR_VAR_SATURATION, saturation);
    [self scheduleSave];

    [self pushToVoutWithBlock:^(vout_thread_t *vout) {
        if (var_Type(vout, MACLC_SDR2HDR_VAR_SATURATION) != 0) {
            var_SetFloat(vout, MACLC_SDR2HDR_VAR_SATURATION, saturation);
        }
    }];
    [self refresh];
    [self notifyChanges];
}

- (void)setDeband:(NSInteger)deband
{
    if (_deband == deband)
        return;
    _deband = deband;
    const char *dStr = maclc_sdr2hdr_deband_name((enum maclc_sdr2hdr_deband)deband);
    MacLCConfigPutPsz(MACLC_SDR2HDR_VAR_DEBAND, dStr);
    [self scheduleSave];

    [self pushToVoutWithBlock:^(vout_thread_t *vout) {
        if (var_Type(vout, MACLC_SDR2HDR_VAR_DEBAND) != 0) {
            var_SetString(vout, MACLC_SDR2HDR_VAR_DEBAND, dStr);
        }
    }];
    [self refresh];
    [self notifyChanges];
}

- (void)setProtect:(BOOL)protect
{
    if (_protect == protect)
        return;
    _protect = protect;
    MacLCConfigPutInt(MACLC_SDR2HDR_VAR_PROTECT, protect ? 1 : 0);
    [self scheduleSave];

    [self pushToVoutWithBlock:^(vout_thread_t *vout) {
        if (var_Type(vout, MACLC_SDR2HDR_VAR_PROTECT) != 0) {
            var_SetBool(vout, MACLC_SDR2HDR_VAR_PROTECT, protect);
        }
    }];
    [self refresh];
    [self notifyChanges];
}

- (void)setComparing:(BOOL)on
{
    if (_comparing == on)
        return;
    _comparing = on;
    [self pushToVoutWithBlock:^(vout_thread_t *vout) {
        if (var_Type(vout, MACLC_SDR2HDR_VAR_COMPARE) != 0) {
            var_SetBool(vout, MACLC_SDR2HDR_VAR_COMPARE, on);
        }
    }];
    [NSNotificationCenter.defaultCenter postNotificationName:MacLCSDRToHDRStateDidChangeNotification object:self];
}

#pragma mark - Polling

- (void)startPolling
{
    _pollingCount++;
    if (_pollTimer == nil) {
        __weak typeof(self) weakSelf = self;
        _pollTimer = [NSTimer scheduledTimerWithTimeInterval:1.0
                                                     repeats:YES
                                                       block:^(NSTimer *timer) {
            [weakSelf refresh];
        }];
    }
}

- (void)stopPolling
{
    _pollingCount--;
    if (_pollingCount <= 0) {
        _pollingCount = 0;
        [_pollTimer invalidate];
        _pollTimer = nil;
    }
}

#pragma mark - Refresh

- (void)refresh
{
    BOOL changed = NO;

    const BOOL newEnabled = MacLCConfigGetInt(MACLC_SDR2HDR_VAR_ENABLED, 0) != 0;
    if (_enabled != newEnabled) {
        _enabled = newEnabled;
        changed = YES;
    }

    char *psz_quality = MacLCConfigGetPsz(MACLC_SDR2HDR_VAR_QUALITY);
    const MacLCSDRToHDRQuality newQuality = (MacLCSDRToHDRQuality)maclc_sdr2hdr_quality_parse(psz_quality);
    free(psz_quality);
    if (_quality != newQuality) {
        _quality = newQuality;
        changed = YES;
    }

    const float newBoost = MacLCConfigGetFloat(MACLC_SDR2HDR_VAR_BOOST, MACLC_SDR2HDR_BOOST_DEFAULT);
    if (fabsf(_boost - newBoost) > 1e-4f) {
        _boost = newBoost;
        changed = YES;
    }

    const float newMidtones = MacLCConfigGetFloat(MACLC_SDR2HDR_VAR_MIDTONES, MACLC_SDR2HDR_MIDTONES_DEFAULT);
    if (fabsf(_midtones - newMidtones) > 1e-4f) {
        _midtones = newMidtones;
        changed = YES;
    }

    const float newSaturation = MacLCConfigGetFloat(MACLC_SDR2HDR_VAR_SATURATION, MACLC_SDR2HDR_SATURATION_DEFAULT);
    if (fabsf(_saturation - newSaturation) > 1e-4f) {
        _saturation = newSaturation;
        changed = YES;
    }

    char *psz_deband = MacLCConfigGetPsz(MACLC_SDR2HDR_VAR_DEBAND);
    const NSInteger newDeband = maclc_sdr2hdr_deband_parse(psz_deband);
    free(psz_deband);
    if (_deband != newDeband) {
        _deband = newDeband;
        changed = YES;
    }

    const BOOL newProtect = MacLCConfigGetInt(MACLC_SDR2HDR_VAR_PROTECT, 1) != 0;
    if (_protect != newProtect) {
        _protect = newProtect;
        changed = YES;
    }

    /* Live vout variables */
    VLCPlayerController *playerController = VLCMain.sharedInstance.playQueueController.playerController;
    vout_thread_t *vout = [playerController mainVideoOutputThread];
    NSString *liveActive = nil;
    NSString *liveReason = nil;
    float livePeak = 0.0f;

    if (vout != NULL) {
        if (var_Type(vout, MACLC_SDR2HDR_VAR_ACTIVE) != 0) {
            char *s = var_GetString(vout, MACLC_SDR2HDR_VAR_ACTIVE);
            if (s) {
                liveActive = [NSString stringWithUTF8String:s];
                free(s);
            }
        }
        if (var_Type(vout, MACLC_SDR2HDR_VAR_REASON) != 0) {
            char *s = var_GetString(vout, MACLC_SDR2HDR_VAR_REASON);
            if (s) {
                liveReason = [NSString stringWithUTF8String:s];
                free(s);
            }
        }
        if (var_Type(vout, MACLC_SDR2HDR_VAR_PEAK) != 0) {
            livePeak = var_GetFloat(vout, MACLC_SDR2HDR_VAR_PEAK);
        }
        vout_Release(vout);
    }

    if ((_activeQualityName != liveActive) && ![_activeQualityName isEqualToString:liveActive]) {
        _activeQualityName = [liveActive copy];
        changed = YES;
    }
    if ((_reason != liveReason) && ![_reason isEqualToString:liveReason]) {
        _reason = [liveReason copy];
        changed = YES;
    }
    if (fabsf(_activePeakNits - livePeak) > 0.1f) {
        _activePeakNits = livePeak;
        changed = YES;
    }

    MacLCSDRToHDRQuality newActiveQ = MacLCSDRToHDRQualityAuto;
    if (liveActive.length > 0 && ![liveActive isEqualToString:@"off"]) {
        newActiveQ = (MacLCSDRToHDRQuality)maclc_sdr2hdr_quality_parse(liveActive.UTF8String);
    }
    if (_activeQuality != newActiveQ) {
        _activeQuality = newActiveQ;
        changed = YES;
    }

    if (changed) {
        [NSNotificationCenter.defaultCenter postNotificationName:MacLCSDRToHDRStateDidChangeNotification object:self];
    }
}

#pragma mark - String Helpers

+ (NSString *)displayNameForQuality:(MacLCSDRToHDRQuality)q
{
    switch (q) {
        case MacLCSDRToHDRQualityFast:
            return _NS("Fast");
        case MacLCSDRToHDRQualityBalanced:
            return _NS("Balanced");
        case MacLCSDRToHDRQualityHigh:
            return _NS("High");
        case MacLCSDRToHDRQualityMaximum:
            return _NS("Maximum");
        case MacLCSDRToHDRQualityAuto:
        default:
            return _NS("Automatic");
    }
}

+ (NSString *)summaryForQuality:(MacLCSDRToHDRQuality)q
{
    switch (q) {
        case MacLCSDRToHDRQualityFast:
            return _NS("One curve for the whole picture. Lightest on the battery.");
        case MacLCSDRToHDRQualityBalanced:
            return _NS("Adapts to each scene. Keeps whites natural and gradients smooth.");
        case MacLCSDRToHDRQualityHigh:
            return _NS("A trained model finds lights and reflections and lifts only those.");
        case MacLCSDRToHDRQualityMaximum:
            return _NS("The trained model at full detail, best around small lights.");
        case MacLCSDRToHDRQualityAuto:
        default:
            return _NS("Picks the best level this Mac can keep up right now.");
    }
}

+ (nullable NSString *)explanationForReason:(nullable NSString *)reason
{
    if (reason == nil || reason.length == 0)
        return nil;

    if ([reason isEqualToString:@"ac-power"])
        return _NS("on power adapter");
    if ([reason isEqualToString:@"battery"])
        return _NS("on battery power");
    if ([reason isEqualToString:@"low-power"])
        return _NS("Low Power Mode is on");
    if ([reason isEqualToString:@"thermal"])
        return _NS("the Mac is running hot");
    if ([reason isEqualToString:@"load"])
        return _NS("this video is demanding");
    if ([reason isEqualToString:@"slow"])
        return _NS("the graphics processor is busy");
    if ([reason isEqualToString:@"model-missing"])
        return _NS("the model for High isn't installed");
    if ([reason isEqualToString:@"no-headroom"])
        return _NS("the display has no extended range");

    return nil;
}

@end
