/*****************************************************************************
 * maclc_upscale_vars.h: shared names for MacLC's upscaling control
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

#ifndef MACLC_UPSCALE_VARS_H
#define MACLC_UPSCALE_VARS_H

/*
 * Contract between the macOS GUI and the Metal video output.
 *
 * The GUI writes the two requests on the running vout (and the options of the
 * same name for defaults). The Metal output creates them with
 * VLC_VAR_DOINHERIT, adds callbacks so changes apply live, and publishes the
 * state below. The native output declines to open while upscaling is on, so
 * the Metal output takes the video.
 */

/* Requests */
#define MACLC_UPSCALE_VAR_ENABLED "maclc-upscale"        /* bool */
#define MACLC_UPSCALE_VAR_METHOD  "maclc-upscale-method" /* see the enum below */
/* integer 0..100, default 50: sharpening of "sharp" (FSR 1) and "nis" */
#define MACLC_UPSCALE_VAR_SHARPNESS "maclc-upscale-sharpness"
/* integer, lines of the short side the upscaler aims at at most:
 * 0 = the window's size (default), else 1080, 1440 or 2160 */
#define MACLC_UPSCALE_VAR_TARGET    "maclc-upscale-target"

/* State published by the Metal output (string):
 *   "idle off"      upscaling is switched off
 *   "idle fits"     the picture is shown at its own size or smaller
 *   "<path> <inW>x<inH> <outW>x<outH>[ <why>]"
 *       path: the passes, joined by '+': a first pass on the decoded picture
 *       (neural, neural4x, anime, anime4k or fsrcnnx), then the one that
 *       scales to the window (fast for MetalFX, sharp for FSR 1, nis for NVIDIA
 *       Image Scaling, classic for EWA Lanczos), e.g. "neural+fast",
 *       "neural4x", "sharp". When the method's first pass is
 *       not used, <why> says why: hdr (HDR source or SDR to HDR on), size (no
 *       neural factor for this size), power (battery or Low Power Mode),
 *       thermal, slow (too slow for the frame rate), unsupported (not on this
 *       Mac or this macOS), loading (the model is starting), model (the
 *       Apple 4x model is not downloaded, or the FSRCNNX file is missing),
 *       format (not 8-bit 4:2:0), rotated (classic cannot draw a rotated
 *       picture, MetalFX scales it instead). */
#define MACLC_UPSCALE_VAR_STATE   "maclc-upscale-state"

#include <stdbool.h>
#include <stdio.h>
#include <string.h>

/* maclc-upscale-method values, in the order the interface lists them. */
enum maclc_upscale_method {
    MACLC_UPSCALE_AUTO,    /* "auto": low-latency neural, then MetalFX */
    MACLC_UPSCALE_APPLE4X, /* "apple4x": Apple's full x4 neural model */
    MACLC_UPSCALE_ANIME,   /* "anime": ArtCNN x2 on luma, then MetalFX */
    MACLC_UPSCALE_ANIME4K, /* "anime4k": Anime4K CNN x2 M on luma, then MetalFX */
    MACLC_UPSCALE_FSRCNNX, /* "fsrcnnx": FSRCNNX x2 on luma, then MetalFX;
                              downloaded once its licence is accepted */
    MACLC_UPSCALE_SHARP,   /* "sharp": AMD FSR 1 (EASU + RCAS) */
    MACLC_UPSCALE_NIS,     /* "nis": NVIDIA Image Scaling */
    MACLC_UPSCALE_FAST,    /* "fast": MetalFX alone */
    MACLC_UPSCALE_CLASSIC, /* "classic": EWA Lanczos, no sharpening */
    MACLC_UPSCALE_METHOD_COUNT
};

static const char *const maclc_upscale_method_names[MACLC_UPSCALE_METHOD_COUNT] = {
    "auto", "apple4x", "anime", "anime4k", "fsrcnnx", "sharp", "nis", "fast",
    "classic",
};

/* FSRCNNX is LGPL-3.0, so it is not shipped: the GUI downloads it into
 * Application Support/<MACLC_UPSCALE_MODELS_DIR> after the user accepts its
 * licence, and the output reads it from there. */
#define MACLC_UPSCALE_MODELS_DIR      "org.maclc.MacLC/Upscalers"
#define MACLC_UPSCALE_FSRCNNX_FILE    "FSRCNNX_x2_8-0-4-1.glsl"
#define MACLC_UPSCALE_FSRCNNX_URL \
    "https://github.com/igv/FSRCNN-TensorFlow/releases/download/1.1/FSRCNNX_x2_8-0-4-1.glsl"
#define MACLC_UPSCALE_FSRCNNX_SHA256 \
    "e800dbc5c1c95185cc82216c597724533ff5f2880179f256eef600f03e8dc2ae"

/* Unknown or missing values read as "auto". */
static inline enum maclc_upscale_method maclc_upscale_parse_method(const char *s)
{
    for (int i = 0; s != NULL && i < MACLC_UPSCALE_METHOD_COUNT; i++)
        if (strcmp(s, maclc_upscale_method_names[i]) == 0)
            return (enum maclc_upscale_method)i;
    return MACLC_UPSCALE_AUTO;
}

/* The state string, read back. `active` is false for the idle states, whose
 * word ("off" or "fits") is then in `why`. */
struct maclc_upscale_state {
    bool active;
    char path[16];
    unsigned in_w, in_h, out_w, out_h;
    char why[16];
};

static inline bool maclc_upscale_parse_state(const char *s,
                                             struct maclc_upscale_state *st)
{
    memset(st, 0, sizeof(*st));
    if (s == NULL)
        return false;
    if (strncmp(s, "idle ", 5) == 0) {
        snprintf(st->why, sizeof(st->why), "%s", s + 5);
        return true;
    }
    const int n = sscanf(s, "%15s %ux%u %ux%u %15s", st->path,
                         &st->in_w, &st->in_h, &st->out_w, &st->out_h, st->why);
    st->active = n >= 5;
    return st->active;
}

/* The name people know a picture size by, from its long side, so that a
 * 3840x1600 film still reads 4K: "4K", "1440p", "1080p", "720p", else the
 * height ("480p"). */
static inline void maclc_upscale_size_label(unsigned w, unsigned h,
                                            char *buf, size_t size)
{
    const unsigned l = w > h ? w : h, s = w > h ? h : w;
    if (l >= 3200)      snprintf(buf, size, "4K");
    else if (l >= 2240) snprintf(buf, size, "1440p");
    else if (l >= 1700) snprintf(buf, size, "1080p");
    else if (l >= 1100) snprintf(buf, size, "720p");
    else                snprintf(buf, size, "%up", s);
}

#endif
