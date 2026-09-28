/*****************************************************************************
 * maclc_sdr2hdr.h: names, parameters and curves of MacLC's SDR to HDR
 *                  conversion and its quality levels
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

#ifndef MACLC_SDR2HDR_H
#define MACLC_SDR2HDR_H

#include <math.h>
#include <stdbool.h>
#include <string.h>

#include "maclc_hdr_vars.h"

/*
 * Contract between the macOS GUI and the Apple video outputs for the SDR to
 * HDR conversion.
 *
 * The conversion works in linear light with SDR white at 1.0, which is what
 * the compositor shows at the display's SDR white (EDR). Luminances given in
 * cd/m2 are reference luminances: MACLC_HDR_REFERENCE_WHITE (100 cd/m2) at
 * SDR white, the anchor MacLC uses for PQ video, so "highlights up to
 * 400 cd/m2" looks like an HDR master graded to 400 cd/m2 does in MacLC.
 *
 * The C functions below are the reference for the Metal kernels, which port
 * them line by line, and for the interface, which plots them.
 */

/* Options: config options of the GUI and of the video output, and live
 * variables of the vout (VLC_VAR_DOINHERIT) so changes apply to the picture
 * that is playing. */
#define MACLC_SDR2HDR_VAR_ENABLED     "macosx-sdr-to-hdr"            /* bool */
#define MACLC_SDR2HDR_VAR_BOOST       "macosx-sdr-to-hdr-boost"      /* float */
#define MACLC_SDR2HDR_VAR_QUALITY     "macosx-sdr-to-hdr-quality"    /* string */
#define MACLC_SDR2HDR_VAR_MIDTONES    "macosx-sdr-to-hdr-midtones"   /* float */
#define MACLC_SDR2HDR_VAR_SATURATION  "macosx-sdr-to-hdr-saturation" /* float */
#define MACLC_SDR2HDR_VAR_DEBAND      "macosx-sdr-to-hdr-deband"     /* string */
#define MACLC_SDR2HDR_VAR_PROTECT     "macosx-sdr-to-hdr-protect"    /* bool */

/* Live variable only, never saved: while true the video output shows the
 * untouched SDR picture (hold-to-compare). Created by the vout. */
#define MACLC_SDR2HDR_VAR_COMPARE     "macosx-sdr-to-hdr-compare"    /* bool */

/* Published by the video output on the vout, read by the GUI. */
#define MACLC_SDR2HDR_VAR_ACTIVE      "macosx-sdr-to-hdr-active"     /* string: quality name, or "off" */
#define MACLC_SDR2HDR_VAR_REASON      "macosx-sdr-to-hdr-reason"     /* string: maclc_sdr2hdr_reason_name() */
#define MACLC_SDR2HDR_VAR_PEAK        "macosx-sdr-to-hdr-peak"       /* float: cd/m2 (reference) in use */

/* Highlight peak ("boost"): a multiple of SDR white. */
#define MACLC_SDR2HDR_BOOST_DEFAULT       4.0f
#define MACLC_SDR2HDR_BOOST_MIN           1.0f
#define MACLC_SDR2HDR_BOOST_MAX           16.0f
/* Mid-tones: 0 keeps SDR white where SDR video has it, 1 lifts it to
 * MACLC_SDR2HDR_LIFTED_WHITE. */
#define MACLC_SDR2HDR_MIDTONES_DEFAULT    0.0f
/* How colourful expanded highlights are, 1 = as in the SDR picture. */
#define MACLC_SDR2HDR_SATURATION_DEFAULT  1.0f
#define MACLC_SDR2HDR_SATURATION_MIN      0.5f
#define MACLC_SDR2HDR_SATURATION_MAX      1.5f

/* ITU-R BT.2408 puts the HDR reference white at 203 cd/m2; relative to
 * MacLC's 100 cd/m2 anchor that is 2.03 times SDR white. */
#define MACLC_SDR2HDR_LIFTED_WHITE        2.03f
/* Lifting mid-tones always leaves the highlights at least this much room. */
#define MACLC_SDR2HDR_MIN_HIGHLIGHT_ROOM  1.5f

/* Diffuse white of a graded SDR picture: about 90 % of the video signal
 * (ITU-R BT.2408), 0.9^1.961 in linear light. Anything at or below it is left
 * as graded by Balanced and above. */
#define MACLC_SDR2HDR_DIFFUSE_WHITE       0.8134f
/* Highlight weight h = smoothstep(DIFFUSE_WHITE, H_FULL, drive): the share of
 * a pixel that counts as highlight in the area statistics. 0.97 is about
 * 98.5 % of the signal. */
#define MACLC_SDR2HDR_H_FULL              0.97f
/* Saturated colours drive the expansion by max(Y, CHROMA_DRIVE * maxRGB):
 * a full-scale primary is expanded, but less than white. */
#define MACLC_SDR2HDR_CHROMA_DRIVE        0.85f
/* Fast: the knee of the per-pixel curve (linear light). */
#define MACLC_SDR2HDR_FAST_KNEE           0.5f
/* Area limiter: up to AREA_LOW of the picture in highlights gets the full
 * budget; from AREA_HIGH on, only AREA_FLOOR of it (large bright areas are
 * diffuse surfaces: glare and power). */
#define MACLC_SDR2HDR_AREA_LOW            0.02f
#define MACLC_SDR2HDR_AREA_HIGH           0.30f
#define MACLC_SDR2HDR_AREA_FLOOR          0.3f
/* Roll-off: values above ROLLOFF_START times the display's headroom are
 * compressed smoothly, so nothing reaches the compositor's hard clip. */
#define MACLC_SDR2HDR_ROLLOFF_START       0.8f
/* Log-intensity floor (natural log of 1/4096) and the range the learned
 * models' grids cover along the intensity axis. */
#define MACLC_SDR2HDR_LOG_FLOOR           (-8.3178f)
#define MACLC_SDR2HDR_GRID_LOG_MIN        (-3.0f)
#define MACLC_SDR2HDR_GRID_LOG_MAX        (0.0f)
/* The peak, in multiples of SDR white, the learned models' training pairs
 * were rendered to: a grid value is a gain as a share of its logarithm. */
#define MACLC_SDR2HDR_P_TRAIN             10.0f
/* Learned levels predict one gain per channel, which restores the colour of
 * clipped highlights (on held-out scenes: 2.2 degrees from the true colour,
 * against 4.0 with one gain per pixel). Each channel's log gain stays within
 * this distance of the pixel's luminance-weighted log gain: 0.2 costs 0.06
 * degree on average and keeps a failure, like a yellow street lamp pushed to
 * salmon, from rotating the hue. */
#define MACLC_SDR2HDR_HUE_SPREAD          0.2f

enum maclc_sdr2hdr_quality
{
    MACLC_SDR2HDR_AUTO = 0,
    MACLC_SDR2HDR_FAST,
    MACLC_SDR2HDR_BALANCED,
    MACLC_SDR2HDR_HIGH,
    MACLC_SDR2HDR_MAXIMUM,
};

enum maclc_sdr2hdr_deband
{
    MACLC_SDR2HDR_DEBAND_OFF = 0,
    MACLC_SDR2HDR_DEBAND_NORMAL,
    MACLC_SDR2HDR_DEBAND_STRONG,
};

/* Why a level is running (published with it, shown by the interface). */
enum maclc_sdr2hdr_reason
{
    MACLC_SDR2HDR_REASON_NONE = 0,   /* nothing to explain */
    MACLC_SDR2HDR_REASON_CHOSEN,     /* the level the user picked */
    MACLC_SDR2HDR_REASON_AC_POWER,   /* Automatic, on power: the best this Mac sustains */
    MACLC_SDR2HDR_REASON_BATTERY,    /* Automatic, on battery */
    MACLC_SDR2HDR_REASON_LOW_POWER,  /* Automatic, Low Power Mode */
    MACLC_SDR2HDR_REASON_THERMAL,    /* Automatic, the Mac is hot */
    MACLC_SDR2HDR_REASON_LOAD,       /* Automatic, the video is too demanding (size, frame rate, interpolation) */
    MACLC_SDR2HDR_REASON_SLOW,       /* Automatic, measured GPU time too high: stepped down */
    MACLC_SDR2HDR_REASON_MODEL_MISSING, /* High or Maximum asked for, no model: Balanced instead */
    MACLC_SDR2HDR_REASON_NO_HEADROOM,   /* the display has no extended range right now */
};

static inline enum maclc_sdr2hdr_quality
maclc_sdr2hdr_quality_parse(const char *s)
{
    if (s == NULL)                return MACLC_SDR2HDR_AUTO;
    if (!strcmp(s, "fast"))       return MACLC_SDR2HDR_FAST;
    if (!strcmp(s, "balanced"))   return MACLC_SDR2HDR_BALANCED;
    if (!strcmp(s, "high"))       return MACLC_SDR2HDR_HIGH;
    if (!strcmp(s, "maximum"))    return MACLC_SDR2HDR_MAXIMUM;
    return MACLC_SDR2HDR_AUTO;
}

static inline const char *
maclc_sdr2hdr_quality_name(enum maclc_sdr2hdr_quality q)
{
    switch (q)
    {
        case MACLC_SDR2HDR_FAST:     return "fast";
        case MACLC_SDR2HDR_BALANCED: return "balanced";
        case MACLC_SDR2HDR_HIGH:     return "high";
        case MACLC_SDR2HDR_MAXIMUM:  return "maximum";
        default:                     return "auto";
    }
}

static inline enum maclc_sdr2hdr_deband
maclc_sdr2hdr_deband_parse(const char *s)
{
    if (s != NULL && !strcmp(s, "off"))    return MACLC_SDR2HDR_DEBAND_OFF;
    if (s != NULL && !strcmp(s, "strong")) return MACLC_SDR2HDR_DEBAND_STRONG;
    return MACLC_SDR2HDR_DEBAND_NORMAL;
}

static inline const char *
maclc_sdr2hdr_deband_name(enum maclc_sdr2hdr_deband d)
{
    switch (d)
    {
        case MACLC_SDR2HDR_DEBAND_OFF:    return "off";
        case MACLC_SDR2HDR_DEBAND_STRONG: return "strong";
        default:                          return "normal";
    }
}

static inline const char *
maclc_sdr2hdr_reason_name(enum maclc_sdr2hdr_reason r)
{
    switch (r)
    {
        case MACLC_SDR2HDR_REASON_CHOSEN:        return "chosen";
        case MACLC_SDR2HDR_REASON_AC_POWER:      return "ac-power";
        case MACLC_SDR2HDR_REASON_BATTERY:       return "battery";
        case MACLC_SDR2HDR_REASON_LOW_POWER:     return "low-power";
        case MACLC_SDR2HDR_REASON_THERMAL:       return "thermal";
        case MACLC_SDR2HDR_REASON_LOAD:          return "load";
        case MACLC_SDR2HDR_REASON_SLOW:          return "slow";
        case MACLC_SDR2HDR_REASON_MODEL_MISSING: return "model-missing";
        case MACLC_SDR2HDR_REASON_NO_HEADROOM:   return "no-headroom";
        default:                                 return "none";
    }
}

static inline enum maclc_sdr2hdr_reason
maclc_sdr2hdr_reason_parse(const char *s)
{
    for (int r = MACLC_SDR2HDR_REASON_CHOSEN;
         r <= MACLC_SDR2HDR_REASON_NO_HEADROOM; r++)
        if (s != NULL && !strcmp(s, maclc_sdr2hdr_reason_name((enum maclc_sdr2hdr_reason)r)))
            return (enum maclc_sdr2hdr_reason)r;
    return MACLC_SDR2HDR_REASON_NONE;
}

/* Reference luminance of a boost, and back. */
static inline float
maclc_sdr2hdr_boost_to_nits(float boost)
{
    return MACLC_HDR_REFERENCE_WHITE * boost;
}

static inline float
maclc_sdr2hdr_nits_to_boost(float nits)
{
    float b = nits / MACLC_HDR_REFERENCE_WHITE;
    if (b < MACLC_SDR2HDR_BOOST_MIN) b = MACLC_SDR2HDR_BOOST_MIN;
    if (b > MACLC_SDR2HDR_BOOST_MAX) b = MACLC_SDR2HDR_BOOST_MAX;
    return b;
}

/* ------------------------------------------------------------------------
 * Curves (reference implementation of the Metal kernels)
 * ------------------------------------------------------------------------ */

static inline float
maclc_sdr2hdr_clamp(float x, float lo, float hi)
{
    return x < lo ? lo : (x > hi ? hi : x);
}

static inline float
maclc_sdr2hdr_smoothstep(float e0, float e1, float x)
{
    float t = maclc_sdr2hdr_clamp((x - e0) / (e1 - e0), 0.0f, 1.0f);
    return t * t * (3.0f - 2.0f * t);
}

/* The value that drives the expansion of a linear RGB triplet: luminance for
 * neutral and dark colours, a share of the largest component for saturated
 * ones. kr, kb: luma coefficients of the source matrix. */
static inline float
maclc_sdr2hdr_drive(float r, float g, float b, float kr, float kb)
{
    float y = kr * r + (1.0f - kr - kb) * g + kb * b;
    float m = fmaxf(fmaxf(r, g), b);
    return fmaxf(y, MACLC_SDR2HDR_CHROMA_DRIVE * m);
}

/* Highlight weight of a pixel for the area statistics. */
static inline float
maclc_sdr2hdr_highlight_weight(float drive)
{
    return maclc_sdr2hdr_smoothstep(MACLC_SDR2HDR_DIFFUSE_WHITE,
                                    MACLC_SDR2HDR_H_FULL, drive);
}

/* Fast: the per-pixel curve. Identity below the knee, then a quadratic whose
 * value and slope match the identity at the knee and which takes full-scale
 * white to `peak`; beyond white it carries on with its slope there. Returns
 * the expanded drive value; the triplet is scaled by e / d. */
static inline float
maclc_sdr2hdr_fast_curve(float d, float knee, float peak)
{
    if (peak <= 1.0f || d <= knee || d <= 0.0f)
        return d;
    float span = fmaxf(1.0f - knee, 1e-4f);
    if (d <= 1.0f)
    {
        float t = (d - knee) / span;
        return d + (peak - 1.0f) * t * t;
    }
    return peak + (d - 1.0f) * (1.0f + 2.0f * (peak - 1.0f) / span);
}

/* Share of the expansion budget a picture gets, from the filtered fraction of
 * its area that is highlight (mean highlight weight). */
static inline float
maclc_sdr2hdr_area_factor(float area)
{
    return 1.0f - (1.0f - MACLC_SDR2HDR_AREA_FLOOR)
                * maclc_sdr2hdr_smoothstep(MACLC_SDR2HDR_AREA_LOW,
                                           MACLC_SDR2HDR_AREA_HIGH, area);
}

/* Where SDR white goes once mid-tones are lifted (1 = as graded), for a
 * highlight peak (multiple of SDR white): never so high that highlights keep
 * less than MIN_HIGHLIGHT_ROOM above it. */
static inline float
maclc_sdr2hdr_white_level(float midtones, float peak)
{
    float w = 1.0f + maclc_sdr2hdr_clamp(midtones, 0.0f, 1.0f)
                   * (MACLC_SDR2HDR_LIFTED_WHITE - 1.0f);
    float cap = peak / MACLC_SDR2HDR_MIN_HIGHLIGHT_ROOM;
    if (cap < 1.0f)
        cap = 1.0f;
    return w < cap ? w : cap;
}

/* The expansion budget of a picture: how far above (lifted) white its
 * brightest highlights go, as a multiple. peak_rel = peak / white level. */
static inline float
maclc_sdr2hdr_budget(float peak_rel, float area)
{
    if (peak_rel <= 1.0f)
        return 1.0f;
    return 1.0f + (peak_rel - 1.0f) * maclc_sdr2hdr_area_factor(area);
}

/* Balanced: natural-log gain from the base log-intensity u of a pixel (its
 * edge-aware local average, see the guided filter in VLCHDRExpander.m). Zero
 * up to diffuse white, the whole budget at SDR white and above. */
static inline float
maclc_sdr2hdr_balanced_log_gain(float u, float budget)
{
    if (budget <= 1.0f)
        return 0.0f;
    const float u0 = logf(MACLC_SDR2HDR_DIFFUSE_WHITE);
    float s = maclc_sdr2hdr_smoothstep(u0, 0.0f, u);
    return logf(budget) * s;
}

/* Smooth shoulder under the display's ceiling (its current headroom):
 * identity up to ROLLOFF_START * ceiling, then an exponential approach to the
 * ceiling. Applied to the largest component, the triplet scaled with it. */
static inline float
maclc_sdr2hdr_rolloff(float x, float ceiling)
{
    if (ceiling <= 1.0f)
        return x;
    float k = MACLC_SDR2HDR_ROLLOFF_START * ceiling;
    if (x <= k)
        return x;
    float span = ceiling - k;
    return k + span * (1.0f - expf(-(x - k) / span));
}

/* Highlight saturation: moves an expanded colour towards (s < 1) or away
 * from (s > 1) its luminance, in proportion to how much it was expanded
 * (w in [0, 1]); unexpanded colours are left alone. In place. */
static inline void
maclc_sdr2hdr_saturate(float rgb[3], float y, float s, float w)
{
    float k = 1.0f + (s - 1.0f) * maclc_sdr2hdr_clamp(w, 0.0f, 1.0f);
    for (int i = 0; i < 3; i++)
    {
        rgb[i] = y + (rgb[i] - y) * k;
        if (rgb[i] < 0.0f)
            rgb[i] = 0.0f;
    }
}

/* Where the peak the conversion aims for is heading: the user's peak, never
 * above what the display can show now. */
static inline float
maclc_sdr2hdr_target_peak(float boost, float headroom)
{
    float h = headroom > 1.0f ? headroom : 1.0f;
    float b = maclc_sdr2hdr_clamp(boost, MACLC_SDR2HDR_BOOST_MIN,
                                  MACLC_SDR2HDR_BOOST_MAX);
    return b < h ? b : h;
}

/* One step of the peak's smoothing: follows a drop at once (never ask for
 * more than the display shows), rises with a one-second time constant. */
static inline float
maclc_sdr2hdr_smooth_peak(float current, float target, float dt)
{
    if (current <= 0.0f || target <= current)
        return target;
    float a = 1.0f - expf(-maclc_sdr2hdr_clamp(dt, 0.0f, 1.0f) / 1.0f);
    return current + (target - current) * a;
}

/*
 * Learned levels: what a grid value (a share in [0, 1]) is a share of, in
 * natural log. The share is read back as the gain the network predicts,
 * MACLC_SDR2HDR_P_TRAIN^share, so a highlight keeps the brightness the model
 * believes it had, and the result is then rolled off under the budget. Read
 * as a share of the budget instead, every gain shrank with the display's
 * headroom (at 4.4 a highlight the model put at 3x white showed at 2x). On a
 * display with more room than P_TRAIN, the share stretches to the budget.
 */
static inline float
maclc_sdr2hdr_grid_log_scale(float budget)
{
    return logf(fmaxf(budget, MACLC_SDR2HDR_P_TRAIN));
}

/*
 * What a neutral grey at `signal` (0..1 of the video signal, BT.709 video
 * gamma 1.961) becomes, in multiples of SDR white, for the interface's curve.
 * Fast is exact. For the other levels the result depends on the picture; this
 * is the curve for a flat area (base = the pixel itself) whose picture has
 * `area` of highlights: 0 for a small highlight, MACLC_SDR2HDR_AREA_HIGH for
 * a large bright area. High and Maximum are shown with the Balanced curve,
 * which their models refine per scene.
 */
static inline float
maclc_sdr2hdr_curve_point(enum maclc_sdr2hdr_quality q, float signal,
                          float boost, float midtones, float headroom,
                          float area)
{
    float lin = powf(maclc_sdr2hdr_clamp(signal, 0.0f, 1.0f), 1.961f);
    float peak = maclc_sdr2hdr_target_peak(boost, headroom);
    float white = maclc_sdr2hdr_white_level(midtones, peak);
    float peak_rel = peak / white;
    float out;

    if (q == MACLC_SDR2HDR_FAST)
        out = maclc_sdr2hdr_fast_curve(lin, MACLC_SDR2HDR_FAST_KNEE, peak_rel);
    else
    {
        float u = logf(fmaxf(lin, 1.0f / 4096.0f));
        float budget = maclc_sdr2hdr_budget(peak_rel, area);
        out = lin * expf(maclc_sdr2hdr_balanced_log_gain(u, budget));
    }
    return maclc_sdr2hdr_rolloff(out * white, headroom);
}

/* ------------------------------------------------------------------------
 * Automatic
 * ------------------------------------------------------------------------ */

/* GPU classes, from the Metal device name. */
enum maclc_sdr2hdr_gpu_class
{
    MACLC_SDR2HDR_GPU_UNKNOWN = 0,
    MACLC_SDR2HDR_GPU_BASE,   /* Apple M-series */
    MACLC_SDR2HDR_GPU_PRO,    /* "Pro" */
    MACLC_SDR2HDR_GPU_MAX,    /* "Max" or "Ultra" */
};

static inline enum maclc_sdr2hdr_gpu_class
maclc_sdr2hdr_gpu_class_from_name(const char *name)
{
    if (name == NULL)
        return MACLC_SDR2HDR_GPU_UNKNOWN;
    if (strstr(name, "Max") != NULL || strstr(name, "Ultra") != NULL)
        return MACLC_SDR2HDR_GPU_MAX;
    if (strstr(name, "Pro") != NULL)
        return MACLC_SDR2HDR_GPU_PRO;
    if (strstr(name, "Apple") != NULL)
        return MACLC_SDR2HDR_GPU_BASE;
    return MACLC_SDR2HDR_GPU_UNKNOWN;
}

struct maclc_sdr2hdr_env
{
    bool model_available;       /* the High/Maximum model is loaded or loadable */
    bool max_model_available;   /* Maximum's own network is there too */
    enum maclc_sdr2hdr_gpu_class gpu;
    bool on_battery;
    bool low_power_mode;
    int thermal_state;          /* NSProcessInfoThermalState: 0 nominal .. 3 critical */
    double pixel_rate;          /* width * height * frames per second of the video */
    bool frame_interpolation;   /* MacLC's frame interpolation is running too */
};

/* 3840 x 2160 at 30 frames per second */
#define MACLC_SDR2HDR_PIXEL_RATE_4K30 (3840.0 * 2160.0 * 30.0)

/*
 * The level Automatic runs. Maximum on a Pro or Max GPU on mains power when
 * its network is installed: measured on an M3 Max it costs 0.53 ms a frame
 * against 0.45 ms for High, and it is closer to the true light on every
 * held-out scene. High otherwise. `reason` (may be NULL) receives why.
 */
static inline enum maclc_sdr2hdr_quality
maclc_sdr2hdr_auto_quality(const struct maclc_sdr2hdr_env *env,
                           enum maclc_sdr2hdr_reason *reason)
{
    enum maclc_sdr2hdr_reason why;
    enum maclc_sdr2hdr_quality q;

    double load = env->pixel_rate > 0.0
                ? env->pixel_rate / MACLC_SDR2HDR_PIXEL_RATE_4K30 : 1.0;
    if (env->frame_interpolation)
        load *= 2.0;

    double high_limit;
    switch (env->gpu)
    {
        case MACLC_SDR2HDR_GPU_MAX:  high_limit = 4.0; break;  /* 4K120, 8K30 */
        case MACLC_SDR2HDR_GPU_PRO:  high_limit = 2.0; break;  /* 4K60 */
        case MACLC_SDR2HDR_GPU_BASE: high_limit = 0.5; break;  /* 1080p60, 1440p30 */
        default:                     high_limit = 0.0; break;
    }

    if (env->low_power_mode)
    {
        q = MACLC_SDR2HDR_FAST;
        why = MACLC_SDR2HDR_REASON_LOW_POWER;
    }
    else if (env->thermal_state >= 3)
    {
        q = MACLC_SDR2HDR_FAST;
        why = MACLC_SDR2HDR_REASON_THERMAL;
    }
    else if (env->thermal_state == 2)
    {
        q = MACLC_SDR2HDR_BALANCED;
        why = MACLC_SDR2HDR_REASON_THERMAL;
    }
    else if (env->on_battery)
    {
        q = MACLC_SDR2HDR_BALANCED;
        why = MACLC_SDR2HDR_REASON_BATTERY;
    }
    else if (!env->model_available)
    {
        q = MACLC_SDR2HDR_BALANCED;
        why = MACLC_SDR2HDR_REASON_MODEL_MISSING;
    }
    else if (load > high_limit)
    {
        q = MACLC_SDR2HDR_BALANCED;
        why = MACLC_SDR2HDR_REASON_LOAD;
    }
    else
    {
        q = env->max_model_available
            && (env->gpu == MACLC_SDR2HDR_GPU_MAX || env->gpu == MACLC_SDR2HDR_GPU_PRO)
          ? MACLC_SDR2HDR_MAXIMUM : MACLC_SDR2HDR_HIGH;
        why = MACLC_SDR2HDR_REASON_AC_POWER;
    }

    if (reason != NULL)
        *reason = why;
    return q;
}

/* The level that runs for a request: Automatic resolved, and High or Maximum
 * fall back to Balanced when there is no model. */
static inline enum maclc_sdr2hdr_quality
maclc_sdr2hdr_resolve_quality(enum maclc_sdr2hdr_quality requested,
                              const struct maclc_sdr2hdr_env *env,
                              enum maclc_sdr2hdr_reason *reason)
{
    if (requested == MACLC_SDR2HDR_AUTO)
        return maclc_sdr2hdr_auto_quality(env, reason);

    if ((requested == MACLC_SDR2HDR_HIGH || requested == MACLC_SDR2HDR_MAXIMUM)
        && !env->model_available)
    {
        if (reason != NULL)
            *reason = MACLC_SDR2HDR_REASON_MODEL_MISSING;
        return MACLC_SDR2HDR_BALANCED;
    }

    if (reason != NULL)
        *reason = MACLC_SDR2HDR_REASON_CHOSEN;
    return requested;
}

/* One level down, for Automatic's GPU-time guard (Fast stays Fast). */
static inline enum maclc_sdr2hdr_quality
maclc_sdr2hdr_step_down(enum maclc_sdr2hdr_quality q)
{
    switch (q)
    {
        case MACLC_SDR2HDR_MAXIMUM:  return MACLC_SDR2HDR_HIGH;
        case MACLC_SDR2HDR_HIGH:     return MACLC_SDR2HDR_BALANCED;
        default:                     return MACLC_SDR2HDR_FAST;
    }
}

#endif /* MACLC_SDR2HDR_H */
