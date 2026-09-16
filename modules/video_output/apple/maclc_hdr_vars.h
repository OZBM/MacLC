/*****************************************************************************
 * maclc_hdr_vars.h: shared names and helpers for MacLC's HDR presentation
 *                   and picture-mode controls
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

#ifndef MACLC_HDR_VARS_H
#define MACLC_HDR_VARS_H

#include <stdbool.h>
#include <string.h>

/*
 * Contract between the macOS GUI and the Apple video outputs
 * (see .agents/skills/maclc-hdr-domain/HDR_CONTRACT.md).
 *
 * The GUI writes the two request variables on the running vout (and the
 * options of the same name for defaults). The video output creates them with
 * VLC_VAR_STRING | VLC_VAR_DOINHERIT, adds callbacks so changes apply live,
 * and publishes the two state variables below.
 */

/* Requests (string options + live vout variables) */
#define MACLC_HDR_VAR_PRESENTATION "maclc-hdr-presentation"
#define MACLC_HDR_VAR_PICTURE      "maclc-hdr-picture"

/* Hint written by the GUI on the vout's parent before it restarts the video
 * track: the stream carries Dolby Vision even if its container did not say so
 * (bool). Lets the outputs route it to the one that can apply the RPUs. */
#define MACLC_HDR_VAR_DOVI_HINT    "maclc-hdr-dovi-hint"

/* Written by the GUI on the player: the peak luminance (cd/m2) its advice
 * assumes for the display showing the video, 0 when unknown (float). Lets an
 * output that opens before the GUI has decided apply the same rule to "auto". */
#define MACLC_HDR_VAR_DISPLAY_PEAK "maclc-hdr-display-peak"

/* State published by the vout (created by the vout, read by the GUI) */
#define MACLC_HDR_VAR_CAPS         "maclc-hdr-caps"   /* integer bitmask */
#define MACLC_HDR_VAR_ACTIVE       "maclc-hdr-active" /* string, presentation vocabulary */

/* Published by an OpenGL display on itself for its filters: true while the
 * surface shows extended-range linear light (EDR, 1.0 = SDR white =
 * MACLC_HDR_REFERENCE_WHITE), false in SDR mode. */
#define MACLC_HDR_VAR_EDR_LINEAR   "maclc-hdr-edr-linear" /* bool */

/* The luminance MacLC shows at the display's SDR white (EDR value 1.0) when it
 * presents PQ video. It is the anchor macOS itself uses for a PQ surface
 * (measured on macOS 26: a layer tagged ITU-R 2100 PQ shows 100 cd/m2 at 1.0,
 * and a 1,600-nit XDR panel reports a potential headroom of 16), so MacLC is
 * as bright as any player that hands PQ to the system, and PQ is shown
 * absolutely when SDR white is set to 100 cd/m2. */
#define MACLC_HDR_REFERENCE_WHITE  100.0f

/* The brightest PQ luminance, in cd/m2, a display can show without clipping
 * when it has this much EDR headroom. */
static inline float
maclc_hdr_peak_for_headroom(float headroom)
{
    return MACLC_HDR_REFERENCE_WHITE * (headroom > 1.0f ? headroom : 1.0f);
}

/* maclc-hdr-caps bits */
#define MACLC_HDR_CAP_DOVI_SEEN        0x1 /* a Dolby Vision RPU reached this vout */
#define MACLC_HDR_CAP_HDR10PLUS_SEEN   0x2 /* ST 2094-40 metadata reached this vout */
#define MACLC_HDR_CAP_CAN_DOVI         0x4 /* this vout applies Dolby Vision RPUs */
#define MACLC_HDR_CAP_CAN_HDR10PLUS    0x8 /* this vout applies HDR10+ dynamic metadata */

enum maclc_hdr_presentation
{
    MACLC_HDR_PRESENTATION_AUTO = 0,
    MACLC_HDR_PRESENTATION_DOLBYVISION,
    MACLC_HDR_PRESENTATION_HDR10PLUS,
    MACLC_HDR_PRESENTATION_HDR10,
    MACLC_HDR_PRESENTATION_HLG,
    MACLC_HDR_PRESENTATION_SDR,
};

enum maclc_hdr_picture
{
    MACLC_HDR_PICTURE_AUTO = 0,
    MACLC_HDR_PICTURE_ACCURATE,
    MACLC_HDR_PICTURE_BALANCED,
    MACLC_HDR_PICTURE_BRIGHT,
};

/* The brightest the video gets, in cd/m2: its content light level, else its
 * mastering display, else what HDR masters usually use.
 * mastering_max is in units of 0.0001 cd/m2, as in video_format_t. */
static inline float
maclc_hdr_content_peak(unsigned max_cll, unsigned mastering_max, bool is_hdr)
{
    if (max_cll > 0)
        return (float)max_cll;
    if (mastering_max > 0)
        return mastering_max / 10000.0f;
    return is_hdr ? 1000.0f : 100.0f;
}

/* The one rule behind "auto": a master brighter than the display (5 %
 * tolerance, so a 1,000-nit master on a ~1,000-nit panel fits) must be tone
 * mapped, which is when Dolby Vision or HDR10+ per-scene metadata changes the
 * picture. When it fits, every format shows the same image. */
static inline bool
maclc_hdr_needs_tone_mapping(float content_peak, float display_peak)
{
    return display_peak > 0.0f && content_peak > display_peak * 1.05f;
}

static inline enum maclc_hdr_presentation
maclc_hdr_presentation_parse(const char *s)
{
    if (s == NULL)                     return MACLC_HDR_PRESENTATION_AUTO;
    if (!strcmp(s, "dolbyvision"))     return MACLC_HDR_PRESENTATION_DOLBYVISION;
    if (!strcmp(s, "hdr10plus"))       return MACLC_HDR_PRESENTATION_HDR10PLUS;
    if (!strcmp(s, "hdr10"))           return MACLC_HDR_PRESENTATION_HDR10;
    if (!strcmp(s, "hlg"))             return MACLC_HDR_PRESENTATION_HLG;
    if (!strcmp(s, "sdr"))             return MACLC_HDR_PRESENTATION_SDR;
    return MACLC_HDR_PRESENTATION_AUTO;
}

static inline const char *
maclc_hdr_presentation_name(enum maclc_hdr_presentation p)
{
    switch (p)
    {
        case MACLC_HDR_PRESENTATION_DOLBYVISION: return "dolbyvision";
        case MACLC_HDR_PRESENTATION_HDR10PLUS:   return "hdr10plus";
        case MACLC_HDR_PRESENTATION_HDR10:       return "hdr10";
        case MACLC_HDR_PRESENTATION_HLG:         return "hlg";
        case MACLC_HDR_PRESENTATION_SDR:         return "sdr";
        default:                                 return "auto";
    }
}

static inline enum maclc_hdr_picture
maclc_hdr_picture_parse(const char *s)
{
    if (s == NULL)                  return MACLC_HDR_PICTURE_AUTO;
    if (!strcmp(s, "accurate"))     return MACLC_HDR_PICTURE_ACCURATE;
    if (!strcmp(s, "balanced"))     return MACLC_HDR_PICTURE_BALANCED;
    if (!strcmp(s, "bright"))       return MACLC_HDR_PICTURE_BRIGHT;
    return MACLC_HDR_PICTURE_AUTO;
}

static inline const char *
maclc_hdr_picture_name(enum maclc_hdr_picture m)
{
    switch (m)
    {
        case MACLC_HDR_PICTURE_ACCURATE: return "accurate";
        case MACLC_HDR_PICTURE_BALANCED: return "balanced";
        case MACLC_HDR_PICTURE_BRIGHT:   return "bright";
        default:                         return "auto";
    }
}

#endif /* MACLC_HDR_VARS_H */
