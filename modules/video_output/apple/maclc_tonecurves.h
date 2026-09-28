/*****************************************************************************
 * maclc_tonecurves.h: HDR tone mapping curves reference and LUT generator
 *****************************************************************************
 * Copyright (C) 2026 Hazen Studio
 *
 * Ported from libplacebo v7.351.0 (src/tone_mapping.c, LGPL-2.1+).
 * Copyright (C) 2018-2024 Niklas Haas and libplacebo contributors.
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

#ifndef MACLC_TONECURVES_H
#define MACLC_TONECURVES_H

#ifdef HAVE_CONFIG_H
# include "config.h"
#endif

#include <math.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include <vlc_common.h>
#include <vlc_ancillary.h>

/* PQ constants and conversions (maclc_pq_to_nits, maclc_nits_to_pq) are
 * the ones every MacLC HDR path shares. */
#include "maclc_tonemap.h"

enum maclc_tonecurve {
    MACLC_TC_AUTO,
    MACLC_TC_CLIP,
    MACLC_TC_BT2390,
    MACLC_TC_REINHARD,
    MACLC_TC_MOBIUS,
    MACLC_TC_HABLE,
    MACLC_TC_GAMMA,
    MACLC_TC_LINEAR,
    MACLC_TC_BT2446A,
    MACLC_TC_SPLINE,
    MACLC_TC_ST2094_40,
};

struct maclc_tonecurve_params {
    enum maclc_tonecurve curve;
    float param;              /* 0 = default of the function (libplacebo semantics) */
    float input_min, input_max;   /* content black / peak, cd/m2 */
    float output_min, output_max; /* display black / peak, cd/m2 */
    const vlc_video_hdr_dynamic_metadata_t *hdr10plus; /* may be NULL */
};

/* Fills lut[n] with the curve sampled uniformly in PQ over [input_min, input_max]:
 * lut[i] is the output luminance in PQ (0..1). Same results as libplacebo's
 * pl_tone_map for the same parameters (document any deviation). */
void maclc_tonecurve_generate(const struct maclc_tonecurve_params *p, float *lut, int n);

/* Samples the tone curve at a single normalised PQ value x in [0, 1]. */
float maclc_tonecurve_sample(const struct maclc_tonecurve_params *p, float x_pq);

/* Deep-compares two maclc_tonecurve_params structs. */
bool maclc_tonecurve_params_equal(const struct maclc_tonecurve_params *a,
                                  const struct maclc_tonecurve_params *b);

#endif /* MACLC_TONECURVES_H */
