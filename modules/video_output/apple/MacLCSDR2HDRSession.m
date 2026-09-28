/*****************************************************************************
 * MacLCSDR2HDRSession.m: shared SDR to HDR expansion session helper
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

#import "MacLCSDR2HDRSession.h"
#import "VLCHDRNetwork.h"
#import "VLCHDRExpander.h"

#import <Metal/Metal.h>
#import <IOKit/ps/IOPowerSources.h>
#import <IOKit/ps/IOPSKeys.h>

#include <vlc_variables.h>
#include <vlc_tick.h>
#include <vlc_threads.h>

@implementation MacLCSDR2HDRSession {
    vout_display_t *_vd;
    vlc_object_t *_voutObj;
    VLCHDRExpander *_expander;
    BOOL _expanderFailed;
    BOOL _needsReset;       /* consumed by expandIfNeeded, on the vout thread */

    enum maclc_sdr2hdr_gpu_class _gpuClass;

    BOOL _enabled;
    float _boost;
    enum maclc_sdr2hdr_quality _requestedQuality;
    float _midtones;
    float _saturation;
    enum maclc_sdr2hdr_deband _deband;
    BOOL _protect;
    BOOL _compare;

    /* Environment evaluation and rate limiting */
    vlc_tick_t _lastEnvEvalTick;
    enum maclc_sdr2hdr_quality _resolvedQuality;
    enum maclc_sdr2hdr_reason _resolveReason;

    /* GPU-time guard state (Automatic only) */
    double _gpuTimeEMA;
    double _gpuOverloadDuration;
    BOOL _steppedDown;
    enum maclc_sdr2hdr_quality _steppedDownQuality;

    /* Video tracking */
    unsigned _lastWidth;
    unsigned _lastHeight;
    vlc_tick_t _lastDate;

    /* Rate-limited publishing state */
    vlc_tick_t _lastPublishTick;
    NSString *_publishedActive;
    NSString *_publishedReason;
    float _publishedPeak;

    NSLock *_lock;
}

#pragma mark - Callbacks

static int EnabledCallback(vlc_object_t *obj, char const *name,
                           vlc_value_t prev, vlc_value_t cur, void *data)
{
    VLC_UNUSED(obj); VLC_UNUSED(name); VLC_UNUSED(prev);
    MacLCSDR2HDRSession *session = (__bridge MacLCSDR2HDRSession *)data;
    [session setEnabled:cur.b_bool];
    return VLC_SUCCESS;
}

static int BoostCallback(vlc_object_t *obj, char const *name,
                         vlc_value_t prev, vlc_value_t cur, void *data)
{
    VLC_UNUSED(obj); VLC_UNUSED(name); VLC_UNUSED(prev);
    MacLCSDR2HDRSession *session = (__bridge MacLCSDR2HDRSession *)data;
    [session setBoost:cur.f_float];
    return VLC_SUCCESS;
}

static int QualityCallback(vlc_object_t *obj, char const *name,
                           vlc_value_t prev, vlc_value_t cur, void *data)
{
    VLC_UNUSED(obj); VLC_UNUSED(name); VLC_UNUSED(prev);
    MacLCSDR2HDRSession *session = (__bridge MacLCSDR2HDRSession *)data;
    [session setQuality:maclc_sdr2hdr_quality_parse(cur.psz_string)];
    return VLC_SUCCESS;
}

static int MidtonesCallback(vlc_object_t *obj, char const *name,
                            vlc_value_t prev, vlc_value_t cur, void *data)
{
    VLC_UNUSED(obj); VLC_UNUSED(name); VLC_UNUSED(prev);
    MacLCSDR2HDRSession *session = (__bridge MacLCSDR2HDRSession *)data;
    [session setMidtones:cur.f_float];
    return VLC_SUCCESS;
}

static int SaturationCallback(vlc_object_t *obj, char const *name,
                              vlc_value_t prev, vlc_value_t cur, void *data)
{
    VLC_UNUSED(obj); VLC_UNUSED(name); VLC_UNUSED(prev);
    MacLCSDR2HDRSession *session = (__bridge MacLCSDR2HDRSession *)data;
    [session setSaturation:cur.f_float];
    return VLC_SUCCESS;
}

static int DebandCallback(vlc_object_t *obj, char const *name,
                          vlc_value_t prev, vlc_value_t cur, void *data)
{
    VLC_UNUSED(obj); VLC_UNUSED(name); VLC_UNUSED(prev);
    MacLCSDR2HDRSession *session = (__bridge MacLCSDR2HDRSession *)data;
    [session setDeband:maclc_sdr2hdr_deband_parse(cur.psz_string)];
    return VLC_SUCCESS;
}

static int ProtectCallback(vlc_object_t *obj, char const *name,
                           vlc_value_t prev, vlc_value_t cur, void *data)
{
    VLC_UNUSED(obj); VLC_UNUSED(name); VLC_UNUSED(prev);
    MacLCSDR2HDRSession *session = (__bridge MacLCSDR2HDRSession *)data;
    [session setProtect:cur.b_bool];
    return VLC_SUCCESS;
}

static int CompareCallback(vlc_object_t *obj, char const *name,
                           vlc_value_t prev, vlc_value_t cur, void *data)
{
    VLC_UNUSED(obj); VLC_UNUSED(name); VLC_UNUSED(prev);
    MacLCSDR2HDRSession *session = (__bridge MacLCSDR2HDRSession *)data;
    [session setCompare:cur.b_bool];
    return VLC_SUCCESS;
}

#pragma mark - Property Setters

- (void)setEnabled:(BOOL)enabled
{
    [_lock lock];
    _enabled = enabled;
    [_lock unlock];
}

- (void)setBoost:(float)boost
{
    [_lock lock];
    _boost = maclc_sdr2hdr_clamp(boost, MACLC_SDR2HDR_BOOST_MIN, MACLC_SDR2HDR_BOOST_MAX);
    [_lock unlock];
}

- (void)setQuality:(enum maclc_sdr2hdr_quality)quality
{
    [_lock lock];
    _requestedQuality = quality;
    _lastEnvEvalTick = 0; /* force immediate re-evaluation */
    _steppedDown = NO;
    _gpuOverloadDuration = 0.0;
    _gpuTimeEMA = 0.0;
    [_lock unlock];
}

- (void)setMidtones:(float)midtones
{
    [_lock lock];
    _midtones = maclc_sdr2hdr_clamp(midtones, 0.0f, 1.0f);
    [_lock unlock];
}

- (void)setSaturation:(float)saturation
{
    [_lock lock];
    _saturation = maclc_sdr2hdr_clamp(saturation, MACLC_SDR2HDR_SATURATION_MIN,
                                      MACLC_SDR2HDR_SATURATION_MAX);
    [_lock unlock];
}

- (void)setDeband:(enum maclc_sdr2hdr_deband)deband
{
    [_lock lock];
    _deband = deband;
    [_lock unlock];
}

- (void)setProtect:(BOOL)protect
{
    [_lock lock];
    _protect = protect;
    [_lock unlock];
}

- (void)setCompare:(BOOL)compare
{
    [_lock lock];
    BOOL previous = _compare;
    _compare = compare;
    if (previous && !compare) {
        /* When hold-to-compare ends, forget temporal state so stale state is
         * not applied (done by the vout thread, the expander's only user). */
        _needsReset = YES;
        _steppedDown = NO;
        _gpuOverloadDuration = 0.0;
    }
    [_lock unlock];
}

#pragma mark - Lifecycle

+ (nullable instancetype)sessionForDisplay:(vout_display_t *)vd
{
    if (vd == NULL)
        return nil;

    MacLCSDR2HDRSession *session = [[MacLCSDR2HDRSession alloc] initWithDisplay:vd];
    return session;
}

- (nullable instancetype)initWithDisplay:(vout_display_t *)vd
{
    self = [super init];
    if (self == nil)
        return nil;

    _vd = vd;
    _voutObj = vlc_object_parent(vd);
    _lock = [[NSLock alloc] init];

    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    const char *deviceName = device ? [device.name UTF8String] : NULL;
    _gpuClass = maclc_sdr2hdr_gpu_class_from_name(deviceName);
    /* The expander and its networks are made with the first SDR picture that
     * needs them (-ensureExpander): an HDR video never pays for them. */

    /* Inherit initial values */
    _enabled = var_InheritBool(vd, MACLC_SDR2HDR_VAR_ENABLED);
    _boost = var_InheritFloat(vd, MACLC_SDR2HDR_VAR_BOOST);
    if (_boost < MACLC_SDR2HDR_BOOST_MIN || _boost > MACLC_SDR2HDR_BOOST_MAX)
        _boost = MACLC_SDR2HDR_BOOST_DEFAULT;

    char *qStr = var_InheritString(vd, MACLC_SDR2HDR_VAR_QUALITY);
    _requestedQuality = maclc_sdr2hdr_quality_parse(qStr);
    free(qStr);

    _midtones = var_InheritFloat(vd, MACLC_SDR2HDR_VAR_MIDTONES);
    _midtones = maclc_sdr2hdr_clamp(_midtones, 0.0f, 1.0f);

    _saturation = var_InheritFloat(vd, MACLC_SDR2HDR_VAR_SATURATION);
    if (_saturation < MACLC_SDR2HDR_SATURATION_MIN || _saturation > MACLC_SDR2HDR_SATURATION_MAX)
        _saturation = MACLC_SDR2HDR_SATURATION_DEFAULT;

    char *dStr = var_InheritString(vd, MACLC_SDR2HDR_VAR_DEBAND);
    _deband = maclc_sdr2hdr_deband_parse(dStr);
    free(dStr);

    _protect = var_InheritBool(vd, MACLC_SDR2HDR_VAR_PROTECT);
    _compare = NO;

    _resolvedQuality = MACLC_SDR2HDR_FAST;
    _resolveReason = MACLC_SDR2HDR_REASON_NONE;
    _lastDate = VLC_TICK_INVALID;
    _publishedPeak = -1.0f;

    /* Create variables and add callbacks on vd */
    var_Create(vd, MACLC_SDR2HDR_VAR_ENABLED, VLC_VAR_BOOL | VLC_VAR_DOINHERIT);
    var_AddCallback(vd, MACLC_SDR2HDR_VAR_ENABLED, EnabledCallback, (__bridge void *)self);

    var_Create(vd, MACLC_SDR2HDR_VAR_BOOST, VLC_VAR_FLOAT | VLC_VAR_DOINHERIT);
    var_AddCallback(vd, MACLC_SDR2HDR_VAR_BOOST, BoostCallback, (__bridge void *)self);

    var_Create(vd, MACLC_SDR2HDR_VAR_QUALITY, VLC_VAR_STRING | VLC_VAR_DOINHERIT);
    var_AddCallback(vd, MACLC_SDR2HDR_VAR_QUALITY, QualityCallback, (__bridge void *)self);

    var_Create(vd, MACLC_SDR2HDR_VAR_MIDTONES, VLC_VAR_FLOAT | VLC_VAR_DOINHERIT);
    var_AddCallback(vd, MACLC_SDR2HDR_VAR_MIDTONES, MidtonesCallback, (__bridge void *)self);

    var_Create(vd, MACLC_SDR2HDR_VAR_SATURATION, VLC_VAR_FLOAT | VLC_VAR_DOINHERIT);
    var_AddCallback(vd, MACLC_SDR2HDR_VAR_SATURATION, SaturationCallback, (__bridge void *)self);

    var_Create(vd, MACLC_SDR2HDR_VAR_DEBAND, VLC_VAR_STRING | VLC_VAR_DOINHERIT);
    var_AddCallback(vd, MACLC_SDR2HDR_VAR_DEBAND, DebandCallback, (__bridge void *)self);

    var_Create(vd, MACLC_SDR2HDR_VAR_PROTECT, VLC_VAR_BOOL | VLC_VAR_DOINHERIT);
    var_AddCallback(vd, MACLC_SDR2HDR_VAR_PROTECT, ProtectCallback, (__bridge void *)self);

    /* Create variables on parent vout */
    if (_voutObj != NULL) {
        var_Create(_voutObj, MACLC_SDR2HDR_VAR_ENABLED, VLC_VAR_BOOL | VLC_VAR_DOINHERIT);
        var_AddCallback(_voutObj, MACLC_SDR2HDR_VAR_ENABLED, EnabledCallback, (__bridge void *)self);

        var_Create(_voutObj, MACLC_SDR2HDR_VAR_BOOST, VLC_VAR_FLOAT | VLC_VAR_DOINHERIT);
        var_AddCallback(_voutObj, MACLC_SDR2HDR_VAR_BOOST, BoostCallback, (__bridge void *)self);

        var_Create(_voutObj, MACLC_SDR2HDR_VAR_QUALITY, VLC_VAR_STRING | VLC_VAR_DOINHERIT);
        var_AddCallback(_voutObj, MACLC_SDR2HDR_VAR_QUALITY, QualityCallback, (__bridge void *)self);

        var_Create(_voutObj, MACLC_SDR2HDR_VAR_MIDTONES, VLC_VAR_FLOAT | VLC_VAR_DOINHERIT);
        var_AddCallback(_voutObj, MACLC_SDR2HDR_VAR_MIDTONES, MidtonesCallback, (__bridge void *)self);

        var_Create(_voutObj, MACLC_SDR2HDR_VAR_SATURATION, VLC_VAR_FLOAT | VLC_VAR_DOINHERIT);
        var_AddCallback(_voutObj, MACLC_SDR2HDR_VAR_SATURATION, SaturationCallback, (__bridge void *)self);

        var_Create(_voutObj, MACLC_SDR2HDR_VAR_DEBAND, VLC_VAR_STRING | VLC_VAR_DOINHERIT);
        var_AddCallback(_voutObj, MACLC_SDR2HDR_VAR_DEBAND, DebandCallback, (__bridge void *)self);

        var_Create(_voutObj, MACLC_SDR2HDR_VAR_PROTECT, VLC_VAR_BOOL | VLC_VAR_DOINHERIT);
        var_AddCallback(_voutObj, MACLC_SDR2HDR_VAR_PROTECT, ProtectCallback, (__bridge void *)self);

        var_Create(_voutObj, MACLC_SDR2HDR_VAR_COMPARE, VLC_VAR_BOOL);
        var_SetBool(_voutObj, MACLC_SDR2HDR_VAR_COMPARE, false);
        var_AddCallback(_voutObj, MACLC_SDR2HDR_VAR_COMPARE, CompareCallback, (__bridge void *)self);

        var_Create(_voutObj, MACLC_SDR2HDR_VAR_ACTIVE, VLC_VAR_STRING);
        var_Create(_voutObj, MACLC_SDR2HDR_VAR_REASON, VLC_VAR_STRING);
        var_Create(_voutObj, MACLC_SDR2HDR_VAR_PEAK, VLC_VAR_FLOAT);

        [self publishActiveImmediate:@"off" reason:@"none" peak:0.0f];
    }

    return self;
}

- (void)close
{
    /* The callbacks take _lock, and var_DelCallback waits for one already
     * running: holding _lock here could deadlock with it. */
    [_lock lock];
    vout_display_t *vd = _vd;
    vlc_object_t *voutObj = _voutObj;
    [_lock unlock];

    if (vd != NULL) {
        var_DelCallback(vd, MACLC_SDR2HDR_VAR_ENABLED, EnabledCallback, (__bridge void *)self);
        var_DelCallback(vd, MACLC_SDR2HDR_VAR_BOOST, BoostCallback, (__bridge void *)self);
        var_DelCallback(vd, MACLC_SDR2HDR_VAR_QUALITY, QualityCallback, (__bridge void *)self);
        var_DelCallback(vd, MACLC_SDR2HDR_VAR_MIDTONES, MidtonesCallback, (__bridge void *)self);
        var_DelCallback(vd, MACLC_SDR2HDR_VAR_SATURATION, SaturationCallback, (__bridge void *)self);
        var_DelCallback(vd, MACLC_SDR2HDR_VAR_DEBAND, DebandCallback, (__bridge void *)self);
        var_DelCallback(vd, MACLC_SDR2HDR_VAR_PROTECT, ProtectCallback, (__bridge void *)self);

        var_Destroy(vd, MACLC_SDR2HDR_VAR_ENABLED);
        var_Destroy(vd, MACLC_SDR2HDR_VAR_BOOST);
        var_Destroy(vd, MACLC_SDR2HDR_VAR_QUALITY);
        var_Destroy(vd, MACLC_SDR2HDR_VAR_MIDTONES);
        var_Destroy(vd, MACLC_SDR2HDR_VAR_SATURATION);
        var_Destroy(vd, MACLC_SDR2HDR_VAR_DEBAND);
        var_Destroy(vd, MACLC_SDR2HDR_VAR_PROTECT);
    }

    if (voutObj != NULL) {
        var_DelCallback(voutObj, MACLC_SDR2HDR_VAR_ENABLED, EnabledCallback, (__bridge void *)self);
        var_DelCallback(voutObj, MACLC_SDR2HDR_VAR_BOOST, BoostCallback, (__bridge void *)self);
        var_DelCallback(voutObj, MACLC_SDR2HDR_VAR_QUALITY, QualityCallback, (__bridge void *)self);
        var_DelCallback(voutObj, MACLC_SDR2HDR_VAR_MIDTONES, MidtonesCallback, (__bridge void *)self);
        var_DelCallback(voutObj, MACLC_SDR2HDR_VAR_SATURATION, SaturationCallback, (__bridge void *)self);
        var_DelCallback(voutObj, MACLC_SDR2HDR_VAR_DEBAND, DebandCallback, (__bridge void *)self);
        var_DelCallback(voutObj, MACLC_SDR2HDR_VAR_PROTECT, ProtectCallback, (__bridge void *)self);
        var_DelCallback(voutObj, MACLC_SDR2HDR_VAR_COMPARE, CompareCallback, (__bridge void *)self);

        var_Destroy(voutObj, MACLC_SDR2HDR_VAR_ENABLED);
        var_Destroy(voutObj, MACLC_SDR2HDR_VAR_BOOST);
        var_Destroy(voutObj, MACLC_SDR2HDR_VAR_QUALITY);
        var_Destroy(voutObj, MACLC_SDR2HDR_VAR_MIDTONES);
        var_Destroy(voutObj, MACLC_SDR2HDR_VAR_SATURATION);
        var_Destroy(voutObj, MACLC_SDR2HDR_VAR_DEBAND);
        var_Destroy(voutObj, MACLC_SDR2HDR_VAR_PROTECT);
        var_Destroy(voutObj, MACLC_SDR2HDR_VAR_COMPARE);
        var_Destroy(voutObj, MACLC_SDR2HDR_VAR_ACTIVE);
        var_Destroy(voutObj, MACLC_SDR2HDR_VAR_REASON);
        var_Destroy(voutObj, MACLC_SDR2HDR_VAR_PEAK);
    }

    [_lock lock];
    _vd = NULL;
    _voutObj = NULL;
    _expander = nil;
    [_lock unlock];
}

- (void)resetTemporalState
{
    [_lock lock];
    _needsReset = YES;
    _steppedDown = NO;
    _gpuOverloadDuration = 0.0;
    _gpuTimeEMA = 0.0;
    _lastDate = VLC_TICK_INVALID;
    [_lock unlock];
}

#pragma mark - Publishing

- (void)publishActiveImmediate:(NSString *)active
                        reason:(NSString *)reason
                          peak:(float)peak
{
    if (_voutObj == NULL)
        return;

    _publishedActive = [active copy];
    _publishedReason = [reason copy];
    _publishedPeak = peak;
    _lastPublishTick = vlc_tick_now();

    var_SetString(_voutObj, MACLC_SDR2HDR_VAR_ACTIVE, [active UTF8String]);
    var_SetString(_voutObj, MACLC_SDR2HDR_VAR_REASON, [reason UTF8String]);
    var_SetFloat(_voutObj, MACLC_SDR2HDR_VAR_PEAK, peak);
}

- (void)publishActive:(NSString *)active
               reason:(NSString *)reason
                 peak:(float)peak
{
    if (_voutObj == NULL)
        return;

    vlc_tick_t now = vlc_tick_now();
    BOOL activeChanged = ![_publishedActive isEqualToString:active];
    BOOL reasonChanged = ![_publishedReason isEqualToString:reason];
    BOOL peakChanged = NO;

    if (_publishedPeak < 0.0f) {
        peakChanged = YES;
    } else {
        float diff = fabsf(peak - _publishedPeak);
        if (diff > 10.0f || (_publishedPeak > 0.0f && (diff / _publishedPeak) > 0.05f))
            peakChanged = YES;
    }

    if (!activeChanged && !reasonChanged && !peakChanged)
        return;

    /* Rate limit to ~4 updates per second (250 ms) */
    if ((now - _lastPublishTick) < VLC_TICK_FROM_MS(250) && _publishedPeak >= 0.0f)
        return;

    [self publishActiveImmediate:active reason:reason peak:peak];
}

#pragma mark - Environment Evaluation

- (void)evaluateEnvironmentForFormat:(const video_format_t *)fmt
{
    struct maclc_sdr2hdr_env env;
    memset(&env, 0, sizeof(env));

    env.gpu = _gpuClass;

    /* Model availability */
    id<VLCHDRGridProducer> producer = _expander.gridProducer;
    env.model_available = (producer != nil && [producer supportsQuality:MACLC_SDR2HDR_HIGH]);
    env.max_model_available = (producer != nil && [producer supportsQuality:MACLC_SDR2HDR_MAXIMUM]);
    if (_requestedQuality == MACLC_SDR2HDR_MAXIMUM) {
        if (![producer supportsQuality:MACLC_SDR2HDR_MAXIMUM])
            env.model_available = NO;
    }

    /* Power status */
    CFTypeRef powerInfo = IOPSCopyPowerSourcesInfo();
    if (powerInfo != NULL) {
        CFStringRef powerSource = IOPSGetProvidingPowerSourceType(powerInfo);
        if (powerSource != NULL && CFStringCompare(powerSource, CFSTR(kIOPMBatteryPowerKey), 0) == kCFCompareEqualTo)
            env.on_battery = true;
        CFRelease(powerInfo);
    }

    /* Low power mode */
    if (@available(macOS 12.0, *)) {
        env.low_power_mode = [NSProcessInfo processInfo].isLowPowerModeEnabled;
    }

    /* Thermal state */
    env.thermal_state = (int)[NSProcessInfo processInfo].thermalState;

    /* Pixel rate */
    double fps = 30.0;
    if (_vd != NULL && _vd->source != NULL &&
        _vd->source->i_frame_rate > 0 && _vd->source->i_frame_rate_base > 0) {
        fps = (double)_vd->source->i_frame_rate / (double)_vd->source->i_frame_rate_base;
    }
    double w = fmt->i_visible_width ? fmt->i_visible_width : fmt->i_width;
    double h = fmt->i_visible_height ? fmt->i_visible_height : fmt->i_height;
    env.pixel_rate = w * h * fps;

    /* Frame interpolation check */
    if (_voutObj != NULL) {
        char *vf = var_InheritString(_voutObj, "video-filter");
        if (vf != NULL) {
            if (strstr(vf, "maclc_frc") != NULL)
                env.frame_interpolation = true;
            free(vf);
        }
    }

    enum maclc_sdr2hdr_reason reason;
    _resolvedQuality = maclc_sdr2hdr_resolve_quality(_requestedQuality, &env, &reason);
    /* Maximum without its own network runs High when that one is here, as
     * the native output does. */
    if (_requestedQuality == MACLC_SDR2HDR_MAXIMUM && !env.model_available
        && producer != nil && [producer supportsQuality:MACLC_SDR2HDR_HIGH]) {
        _resolvedQuality = MACLC_SDR2HDR_HIGH;
        reason = MACLC_SDR2HDR_REASON_MODEL_MISSING;
    }
    _resolveReason = reason;
    _lastEnvEvalTick = vlc_tick_now();
}

#pragma mark - Expansion

/* Called with _lock held. */
- (void)ensureExpander
{
    if (_expander != nil || _expanderFailed)
        return;
    _expander = [VLCHDRExpander expanderForObject:VLC_OBJECT(_vd)];
    if (_expander == nil) {
        _expanderFailed = YES;
        return;
    }
    /* High and Maximum run the trained networks shipped in the app (or
     * installed in Application Support); without them they run as Balanced
     * and say so. */
    vout_display_t *vd = _vd;
    _expander.gridProducer =
        [VLCHDRNetworkSet networkSetWithDevice:MTLCreateSystemDefaultDevice()
                                 userDirectory:nil
                                           log:^(NSString *line) {
            msg_Dbg(vd, "SDR to HDR: %s", line.UTF8String);
        }];
}

- (nullable CVPixelBufferRef)expandIfNeeded:(CVPixelBufferRef)pb
                                     format:(video_format_t *)fmt
                                   headroom:(float)h
                                       date:(vlc_tick_t)date
                                sourceIsHDR:(BOOL)hdr
                                        edr:(BOOL)edr
{
    /* _lock guards the settings the callbacks change; the expander itself is
     * only used here, on the vout thread, and runs without the lock so that a
     * callback never waits for the GPU. */
    [_lock lock];

    if (_enabled && !hdr && edr && !_compare && h > 1.0f)
        [self ensureExpander];

    if (!_enabled || hdr || !edr || _compare || h <= 1.0f || _expander == nil) {
        const BOOL noHeadroom = h <= 1.0f && _enabled && !hdr && edr && !_compare;
        [_lock unlock];
        [self publishActive:@"off"
                     reason:noHeadroom
                         ? @(maclc_sdr2hdr_reason_name(MACLC_SDR2HDR_REASON_NO_HEADROOM))
                         : @"none"
                       peak:0.0f];
        return NULL;
    }

    VLCHDRExpander *expander = _expander;
    if (![expander canExpandPixelFormat:CVPixelBufferGetPixelFormatType(pb)]) {
        [_lock unlock];
        [self publishActive:@"off" reason:@"none" peak:0.0f];
        return NULL;
    }

    /* Video format or size change detection */
    if (fmt->i_visible_width != _lastWidth || fmt->i_visible_height != _lastHeight) {
        _lastWidth = fmt->i_visible_width;
        _lastHeight = fmt->i_visible_height;
        _needsReset = YES;
        _steppedDown = NO;
        _gpuOverloadDuration = 0.0;
        _gpuTimeEMA = 0.0;
        _lastEnvEvalTick = 0;
    }

    /* Re-evaluate environment periodically or when triggered */
    vlc_tick_t now = vlc_tick_now();
    if (_lastEnvEvalTick == 0 || (now - _lastEnvEvalTick) >= VLC_TICK_FROM_SEC(2)) {
        [self evaluateEnvironmentForFormat:fmt];
    }

    /* GPU-time guard for Automatic: one level down at a time, as far as
     * Fast, each step measured afresh. */
    if (_requestedQuality == MACLC_SDR2HDR_AUTO) {
        double fps = 30.0;
        if (_vd != NULL && _vd->source != NULL &&
            _vd->source->i_frame_rate > 0 && _vd->source->i_frame_rate_base > 0) {
            fps = (double)_vd->source->i_frame_rate / (double)_vd->source->i_frame_rate_base;
        }
        double frameIntervalMs = (fps > 0.0) ? (1000.0 / fps) : 33.33;
        double thresholdMs = 0.25 * frameIntervalMs;

        double dt = (date != VLC_TICK_INVALID && _lastDate != VLC_TICK_INVALID && date > _lastDate)
            ? secf_from_vlc_tick(date - _lastDate) : (1.0 / 30.0);
        if (dt > 0.25) dt = 0.25;

        const enum maclc_sdr2hdr_quality current = _steppedDown ? _steppedDownQuality : _resolvedQuality;
        double lastGpuMs = expander.lastGPUTimeMs;
        if (lastGpuMs > 0.0 && current != MACLC_SDR2HDR_FAST) {
            double alpha = 1.0 - exp(-dt / 1.0);
            _gpuTimeEMA = (_gpuTimeEMA <= 0.0) ? lastGpuMs : (_gpuTimeEMA + alpha * (lastGpuMs - _gpuTimeEMA));

            if (_gpuTimeEMA > thresholdMs) {
                _gpuOverloadDuration += dt;
                if (_gpuOverloadDuration >= 2.0) {
                    _steppedDown = YES;
                    _steppedDownQuality = maclc_sdr2hdr_step_down(current);
                    _gpuOverloadDuration = 0.0;
                    _gpuTimeEMA = 0.0;
                }
            } else {
                _gpuOverloadDuration = 0.0;
            }
        }

        if (_steppedDown) {
            _resolvedQuality = _steppedDownQuality;
            _resolveReason = MACLC_SDR2HDR_REASON_SLOW;
        }
    }
    _lastDate = date;

    /* This picture's parameters for the expander */
    VLCHDRExpandParams params;
    memset(&params, 0, sizeof(params));
    params.quality = _resolvedQuality;
    params.boost = _boost;
    params.midtones = _midtones;
    params.saturation = _saturation;
    params.deband = _deband;
    params.protect = _protect;
    params.headroom = h;
    params.date = date;
    const BOOL reset = _needsReset;
    _needsReset = NO;
    enum maclc_sdr2hdr_reason reason = _resolveReason;
    [_lock unlock];

    if (reset)
        [expander resetTemporalState];
    CVPixelBufferRef expanded = [expander expandPixelBuffer:pb format:fmt params:&params];
    if (expanded == NULL) {
        [self publishActive:@"off" reason:@"none" peak:0.0f];
        return NULL;
    }

    /* Retag the video format to linear BT.2020 light with SDR white 1.0 */
    fmt->transfer = TRANSFER_FUNC_LINEAR;
    fmt->primaries = COLOR_PRIMARIES_BT2020;
    fmt->space = COLOR_SPACE_BT2020;
    fmt->color_range = COLOR_RANGE_FULL;
    memset(&fmt->mastering, 0, sizeof(fmt->mastering));
    memset(&fmt->lighting, 0, sizeof(fmt->lighting));

    /* What actually ran: the expander falls back to Balanced when a level's
     * network cannot run. */
    if (expander.lastFallback)
        reason = MACLC_SDR2HDR_REASON_MODEL_MISSING;
    [self publishActive:@(maclc_sdr2hdr_quality_name(expander.lastQuality))
                 reason:@(maclc_sdr2hdr_reason_name(reason))
                   peak:expander.lastPeakNits];
    return expanded;
}

- (enum maclc_sdr2hdr_quality)activeQuality
{
    [_lock lock];
    enum maclc_sdr2hdr_quality q = _resolvedQuality;
    [_lock unlock];
    return q;
}

- (enum maclc_sdr2hdr_reason)activeReason
{
    [_lock lock];
    enum maclc_sdr2hdr_reason r = _resolveReason;
    [_lock unlock];
    return r;
}

- (float)activePeakNits
{
    [_lock lock];
    float p = _expander ? _expander.lastPeakNits : 0.0f;
    [_lock unlock];
    return p;
}

@end
