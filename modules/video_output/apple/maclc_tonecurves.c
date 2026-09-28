/*****************************************************************************
 * maclc_tonecurves.c: HDR tone mapping curves reference and LUT generator
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

#ifdef HAVE_CONFIG_H
# include "config.h"
#endif

#include "maclc_tonecurves.h"

#include <math.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <string.h>

#define PL_COLOR_SDR_WHITE 203.0f

#define fclampf(x, lo, hi) fminf(fmaxf(x, lo), hi)
#define PL_MIX(a, b, x) ((a) * (1.0f - (x)) + (b) * (x))

enum pl_hdr_scaling {
    PL_HDR_NORM = 0, /* 0.0 is black, 1.0 is PL_COLOR_SDR_WHITE (203 cd/m2) */
    PL_HDR_SQRT,
    PL_HDR_NITS,     /* absolute cd/m2 */
    PL_HDR_PQ,       /* PQ normalised [0, 1] */
};

struct pl_tone_map_constants {
    float knee_adaptation;
    float knee_minimum;
    float knee_maximum;
    float knee_default;
    float knee_offset;
    float slope_tuning;
    float slope_offset;
    float spline_contrast;
    float reinhard_contrast;
    float linear_knee;
    float exposure;
};

static const struct pl_tone_map_constants kDefaultConstants = {
    .knee_adaptation   = 0.4f,
    .knee_minimum      = 0.1f,
    .knee_maximum      = 0.8f,
    .knee_default      = 0.4f,
    .knee_offset       = 1.0f,
    .slope_tuning      = 1.5f,
    .slope_offset      = 0.2f,
    .spline_contrast   = 0.5f,
    .reinhard_contrast = 0.5f,
    .linear_knee       = 0.3f,
    .exposure          = 1.0f,
};

struct pl_hdr_bezier {
    float target_luma;
    float knee_x, knee_y;
    float anchors[15];
    uint8_t num_anchors;
};

struct pl_tone_map_params {
    const struct pl_tone_map_function *function;
    struct pl_tone_map_constants constants;
    enum pl_hdr_scaling input_scaling;
    enum pl_hdr_scaling output_scaling;
    size_t lut_size;
    float input_min;
    float input_max;
    float input_avg;
    float output_min;
    float output_max;
    struct {
        struct pl_hdr_bezier ootf;
    } hdr;
    float param;
};

struct pl_tone_map_function {
    const char *name;
    enum pl_hdr_scaling scaling;
    void (*map)(float *lut, const struct pl_tone_map_params *params);
    void (*map_inverse)(float *lut, const struct pl_tone_map_params *params);
};

static float pl_hdr_rescale(enum pl_hdr_scaling from, enum pl_hdr_scaling to, float x)
{
    if (from == to)
        return x;
    if (x <= 0.0f)
        return 0.0f;

    /* Step 1: to PL_HDR_NORM */
    switch (from) {
    case PL_HDR_PQ:
        x = maclc_pq_to_nits(x);
        /* fall through */
    case PL_HDR_NITS:
        x /= PL_COLOR_SDR_WHITE;
        /* fall through */
    case PL_HDR_NORM:
        break;
    case PL_HDR_SQRT:
        x *= x;
        break;
    }

    /* Step 2: from PL_HDR_NORM to destination */
    switch (to) {
    case PL_HDR_NORM:
        return x;
    case PL_HDR_SQRT:
        return sqrtf(fmaxf(x, 0.0f));
    case PL_HDR_NITS:
        return x * PL_COLOR_SDR_WHITE;
    case PL_HDR_PQ:
        return maclc_nits_to_pq(x * PL_COLOR_SDR_WHITE);
    }
    return x;
}

static void fix_constants(struct pl_tone_map_constants *c)
{
    const float eps = 1e-6f;
    c->knee_adaptation   = fclampf(c->knee_adaptation, 0.0f, 1.0f);
    c->knee_minimum      = fclampf(c->knee_minimum, eps, 0.5f - eps);
    c->knee_maximum      = fclampf(c->knee_maximum, 0.5f + eps, 1.0f - eps);
    c->knee_default      = fclampf(c->knee_default, c->knee_minimum, c->knee_maximum);
    c->knee_offset       = fclampf(c->knee_offset, 0.5f, 2.0f);
    c->slope_tuning      = fclampf(c->slope_tuning, 0.0f, 10.0f);
    c->slope_offset      = fclampf(c->slope_offset, 0.0f, 1.0f);
    c->spline_contrast   = fclampf(c->spline_contrast, 0.0f, 1.5f);
    c->reinhard_contrast = fclampf(c->reinhard_contrast, eps, 1.0f - eps);
    c->linear_knee       = fclampf(c->linear_knee, eps, 1.0f - eps);
    c->exposure          = fclampf(c->exposure, eps, 10.0f);
}

static inline float rescale_in(float x, const struct pl_tone_map_params *params)
{
    float denom = params->input_max - params->input_min;
    return (denom > 1e-6f) ? (x - params->input_min) / denom : 0.0f;
}

static inline float rescale(float x, const struct pl_tone_map_params *params)
{
    float denom = params->output_max - params->output_min;
    return (denom > 1e-6f) ? (x - params->input_min) / denom : 0.0f;
}

static inline float rescale_out(float x, const struct pl_tone_map_params *params)
{
    return x * (params->output_max - params->output_min) + params->output_min;
}

static inline float bt1886_eotf(float x, float min, float max)
{
    const float lb = powf(fmaxf(min, 0.0f), 1.0f / 2.4f);
    const float lw = powf(fmaxf(max, 0.0f), 1.0f / 2.4f);
    return powf(fmaxf((lw - lb) * x + lb, 0.0f), 2.4f);
}

static inline float bt1886_oetf(float x, float min, float max)
{
    const float lb = powf(fmaxf(min, 0.0f), 1.0f / 2.4f);
    const float lw = powf(fmaxf(max, 0.0f), 1.0f / 2.4f);
    const float denom = lw - lb;
    if (denom <= 1e-6f)
        return 0.0f;
    return (powf(fmaxf(x, 0.0f), 1.0f / 2.4f) - lb) / denom;
}

static inline float pl_smoothstep(float edge0, float edge1, float x)
{
    float denom = edge1 - edge0;
    if (fabsf(denom) < 1e-6f)
        return (x < edge0) ? 0.0f : 1.0f;
    x = fclampf((x - edge0) / denom, 0.0f, 1.0f);
    return x * x * (3.0f - 2.0f * x);
}

static void st2094_pick_knee(float *out_src_knee, float *out_dst_knee,
                             const struct pl_tone_map_params *params)
{
    const float src_min = pl_hdr_rescale(params->input_scaling,  PL_HDR_PQ, params->input_min);
    const float src_max = pl_hdr_rescale(params->input_scaling,  PL_HDR_PQ, params->input_max);
    const float src_avg = pl_hdr_rescale(params->input_scaling,  PL_HDR_PQ, params->input_avg);
    const float dst_min = pl_hdr_rescale(params->output_scaling, PL_HDR_PQ, params->output_min);
    const float dst_max = pl_hdr_rescale(params->output_scaling, PL_HDR_PQ, params->output_max);

    const float min_knee = params->constants.knee_minimum;
    const float max_knee = params->constants.knee_maximum;
    const float def_knee = params->constants.knee_default;
    const float src_knee_min = PL_MIX(src_min, src_max, min_knee);
    const float src_knee_max = PL_MIX(src_min, src_max, max_knee);
    const float dst_knee_min = PL_MIX(dst_min, dst_max, min_knee);
    const float dst_knee_max = PL_MIX(dst_min, dst_max, max_knee);

    float src_knee = (src_avg > 0.0f) ? src_avg : PL_MIX(src_min, src_max, def_knee);
    src_knee = fclampf(src_knee, src_knee_min, src_knee_max);

    float denom = src_max - src_min;
    float target = (denom > 1e-6f) ? (src_knee - src_min) / denom : 0.0f;
    float adapted = PL_MIX(dst_min, dst_max, target);

    float tuning = 1.0f - pl_smoothstep(max_knee, def_knee, target) *
                          pl_smoothstep(min_knee, def_knee, target);
    float adaptation = PL_MIX(params->constants.knee_adaptation, 1.0f, tuning);
    float dst_knee = PL_MIX(src_knee, adapted, adaptation);
    dst_knee = fclampf(dst_knee, dst_knee_min, dst_knee_max);

    *out_src_knee = pl_hdr_rescale(PL_HDR_PQ, params->input_scaling, src_knee);
    *out_dst_knee = pl_hdr_rescale(PL_HDR_PQ, params->output_scaling, dst_knee);
}

/* Pascal's triangle for Bezier curves */
static const uint16_t binom[17][17] = {
    {1},
    {1,1},
    {1,2,1},
    {1,3,3,1},
    {1,4,6,4,1},
    {1,5,10,10,5,1},
    {1,6,15,20,15,6,1},
    {1,7,21,35,35,21,7,1},
    {1,8,28,56,70,56,28,8,1},
    {1,9,36,84,126,126,84,36,9,1},
    {1,10,45,120,210,252,210,120,45,10,1},
    {1,11,55,165,330,462,462,330,165,55,11,1},
    {1,12,66,220,495,792,924,792,495,220,66,12,1},
    {1,13,78,286,715,1287,1716,1716,1287,715,286,78,13,1},
    {1,14,91,364,1001,2002,3003,3432,3003,2002,1001,364,91,14,1},
    {1,15,105,455,1365,3003,5005,6435,6435,5005,3003,1365,455,105,15,1},
    {1,16,120,560,1820,4368,8008,11440,12870,11440,8008,4368,1820,560,120,16,1},
};

static inline float st2094_intercept(uint8_t N, float Kx, float Ky)
{
    if (Kx <= 0.0f || Ky >= 1.0f)
        return (N > 0) ? (1.0f / N) : 1.0f;

    const float slope = Ky / Kx * (1.0f - Kx) / (1.0f - Ky);
    return fminf(slope / N, 1.0f);
}

/*
 * Tone mapping functions ported from libplacebo v7.351.0 (src/tone_mapping.c)
 */

/* 1. Clip */
static void clip_map(float *lut, const struct pl_tone_map_params *params)
{
    (void) lut;
    (void) params;
}

static const struct pl_tone_map_function fn_clip = {
    .name = "clip",
    .scaling = PL_HDR_PQ,
    .map = clip_map,
    .map_inverse = clip_map,
};

/* 2. ST 2094-40 */
static void st2094_40_map(float *lut, const struct pl_tone_map_params *params)
{
    const float D = params->output_max;
    float P[17], Kx, Ky, T;
    uint8_t N;

    if (params->hdr.ootf.num_anchors) {
        Kx = fclampf(params->hdr.ootf.knee_x, 0.0f, 1.0f);
        Ky = fclampf(params->hdr.ootf.knee_y, 0.0f, 1.0f);
        T = fclampf(params->hdr.ootf.target_luma, params->input_min, params->input_max);
        N = params->hdr.ootf.num_anchors + 1;
        if (N >= 17)
            N = 16;
        memcpy(P + 1, params->hdr.ootf.anchors, (N - 1) * sizeof(*P));
        P[0] = 0.0f;
        P[N] = 1.0f;
    } else {
        float src_knee, dst_knee;
        st2094_pick_knee(&src_knee, &dst_knee, params);
        Kx = (params->input_max > 0.0f) ? (src_knee / params->input_max) : 0.0f;
        Ky = (params->output_max > 0.0f) ? (dst_knee / params->output_max) : 0.0f;

        const float slope = (Kx > 0.0f && Ky < 1.0f) ? (Ky / Kx * (1.0f - Kx) / (1.0f - Ky)) : 1.0f;
        int n_calc = (int) ceilf(slope);
        N = (uint8_t) fclampf((float)n_calc, 2.0f, 16.0f);
        P[0] = 0.0f;
        P[1] = st2094_intercept(N, Kx, Ky);
        for (int i = 2; i <= N; i++)
            P[i] = 1.0f;
        T = D;
    }

    if (D < T) {
        const float Dmin = 0.0f;
        const float u = (T > Dmin) ? fmaxf(0.0f, (D - Dmin) / (T - Dmin)) : 0.0f;

        Kx *= u;
        Ky *= u;

        const float beta = (Kx < 1.0f) ? (N * Kx / (1.0f - Kx)) : 0.0f;
        const float Kxy = (D > 0.0f && beta >= 0.0f)
            ? fminf(Kx * params->input_max / D, beta / (beta + 1.0f))
            : 0.0f;
        Ky = PL_MIX(Kxy, Ky, u);

        for (int p = 2; p <= N; p++)
            P[p] = PL_MIX(1.0f, P[p], u);

        P[1] = PL_MIX(st2094_intercept(N, Kx, Ky), P[1], u);
    } else if (D > T) {
        const float denom = params->input_max - T;
        const float w = (denom > 1e-4f) ? powf(fmaxf(0.0f, 1.0f - (D - T) / denom), 1.4f) : 0.0f;

        if (D > 0.0f)
            Ky *= T / D;

        float Kxy = (params->input_max > 0.0f) ? (Kx * D / params->input_max) : 0.0f;
        Ky = PL_MIX(Kxy, Ky, w);

        for (int p = 2; p < N; p++) {
            float anchor_lin = (float) p / N;
            P[p] = PL_MIX(anchor_lin, P[p], w);
        }

        P[1] = PL_MIX(st2094_intercept(N, Kx, Ky), P[1], w);
    }

    Kx = fclampf(Kx, 0.0f, 1.0f);
    Ky = fclampf(Ky, 0.0f, 1.0f);

    for (size_t i = 0; i < params->lut_size; i++) {
        float x = lut[i];
        x = bt1886_oetf(x, params->input_min, params->input_max);
        x = bt1886_eotf(x, 0.0f, 1.0f);

        if (x <= Kx && Kx > 0.0f) {
            x *= Ky / Kx;
        } else if (Kx < 1.0f) {
            const float t = (x - Kx) / (1.0f - Kx);
            float bz = 0.0f;
            for (uint8_t p = 0; p <= N; p++)
                bz += (float)binom[N][p] * powf(t, p) * powf(1.0f - t, N - p) * P[p];
            x = Ky + (1.0f - Ky) * bz;
        } else {
            x = Ky;
        }

        x = bt1886_oetf(x, 0.0f, 1.0f);
        x = bt1886_eotf(x, params->output_min, params->output_max);
        lut[i] = x;
    }
}

static const struct pl_tone_map_function fn_st2094_40 = {
    .name = "st2094-40",
    .scaling = PL_HDR_NITS,
    .map = st2094_40_map,
    .map_inverse = NULL,
};

/* 3. BT.2390 */
static void bt2390_map(float *lut, const struct pl_tone_map_params *params)
{
    const float minLum = rescale_in(params->output_min, params);
    const float maxLum = rescale_in(params->output_max, params);
    const float offset = params->constants.knee_offset;
    const float ks = (1.0f + offset) * maxLum - offset;
    const float bp = (minLum > 0.0f) ? fminf(1.0f / minLum, 4.0f) : 4.0f;
    const float gain_inv = (maxLum > 0.0f)
        ? (1.0f + minLum / maxLum * powf(fmaxf(0.0f, 1.0f - maxLum), bp))
        : 1.0f;
    const float gain = (maxLum < 1.0f && gain_inv > 1e-6f) ? (1.0f / gain_inv) : 1.0f;

    for (size_t i = 0; i < params->lut_size; i++) {
        float x = rescale_in(lut[i], params);

        if (ks < 1.0f && x >= ks) {
            float denom = 1.0f - ks;
            if (denom > 1e-6f) {
                float tb = (x - ks) / denom;
                float tb2 = tb * tb;
                float tb3 = tb2 * tb;
                float pb = (2.0f * tb3 - 3.0f * tb2 + 1.0f) * ks +
                           (tb3 - 2.0f * tb2 + tb) * denom +
                           (-2.0f * tb3 + 3.0f * tb2) * maxLum;
                x = pb;
            } else {
                x = maxLum;
            }
        }

        if (x < 1.0f) {
            x += minLum * powf(fmaxf(0.0f, 1.0f - x), bp);
            x = gain * (x - minLum) + minLum;
        }

        lut[i] = x * (params->input_max - params->input_min) + params->input_min;
    }
}

static const struct pl_tone_map_function fn_bt2390 = {
    .name = "bt2390",
    .scaling = PL_HDR_PQ,
    .map = bt2390_map,
    .map_inverse = NULL,
};

/* 4. Reinhard */
static void reinhard_map(float *lut, const struct pl_tone_map_params *params)
{
    const float peak = rescale(params->input_max, params);
    const float contrast = params->constants.reinhard_contrast;
    const float offset = (1.0f - contrast) / contrast;
    const float scale = (peak > 0.0f) ? ((peak + offset) / peak) : 1.0f;

    for (size_t i = 0; i < params->lut_size; i++) {
        float x = rescale(lut[i], params);
        if (x + offset > 1e-6f)
            x = x / (x + offset) * scale;
        else
            x = 0.0f;
        lut[i] = rescale_out(x, params);
    }
}

static const struct pl_tone_map_function fn_reinhard = {
    .name = "reinhard",
    .scaling = PL_HDR_NORM,
    .map = reinhard_map,
    .map_inverse = NULL,
};

/* 5. Mobius */
static void mobius_map(float *lut, const struct pl_tone_map_params *params)
{
    const float peak = rescale(params->input_max, params);
    const float j = params->constants.linear_knee;

    const float denom_a = j * j - 2.0f * j + peak;
    const float a = (fabsf(denom_a) > 1e-6f)
        ? (-j * j * (peak - 1.0f) / denom_a)
        : 0.0f;
    const float b = (j * j - 2.0f * j * peak + peak) / fmaxf(1e-6f, peak - 1.0f);
    const float scale = (fabsf(b - a) > 1e-6f)
        ? ((b * b + 2.0f * b * j + j * j) / (b - a))
        : 1.0f;

    for (size_t i = 0; i < params->lut_size; i++) {
        float x = rescale(lut[i], params);
        if (x > j && (x + b > 1e-6f))
            x = scale * (x + a) / (x + b);
        lut[i] = rescale_out(x, params);
    }
}

static const struct pl_tone_map_function fn_mobius = {
    .name = "mobius",
    .scaling = PL_HDR_NORM,
    .map = mobius_map,
    .map_inverse = NULL,
};

/* 6. Hable */
static inline float hable_eval(float x)
{
    const float A = 0.15f, B = 0.50f, C = 0.10f, D = 0.20f, E = 0.02f, F = 0.30f;
    float denom = x * (A * x + B) + D * F;
    if (denom <= 1e-6f)
        return 0.0f;
    return ((x * (A * x + C * B) + D * E) / denom) - E / F;
}

static void hable_map(float *lut, const struct pl_tone_map_params *params)
{
    const float peak = (params->output_max > 0.0f) ? (params->input_max / params->output_max) : 1.0f;
    const float hable_peak = hable_eval(peak);
    const float scale = (hable_peak > 1e-6f) ? (1.0f / hable_peak) : 1.0f;

    for (size_t i = 0; i < params->lut_size; i++) {
        float x = bt1886_oetf(lut[i], params->input_min, params->input_max);
        x = bt1886_eotf(x, 0.0f, peak);
        x = scale * hable_eval(x);
        x = bt1886_oetf(x, 0.0f, 1.0f);
        lut[i] = bt1886_eotf(x, params->output_min, params->output_max);
    }
}

static const struct pl_tone_map_function fn_hable = {
    .name = "hable",
    .scaling = PL_HDR_NORM,
    .map = hable_map,
    .map_inverse = NULL,
};

/* 7. Gamma */
static void gamma_map(float *lut, const struct pl_tone_map_params *params)
{
    const float peak = rescale(params->input_max, params);
    const float cutoff = params->constants.linear_knee;
    const float denom = logf(fmaxf(cutoff / peak, 1e-6f));
    const float gamma = (fabsf(denom) > 1e-6f) ? (logf(fmaxf(cutoff, 1e-6f)) / denom) : 1.0f;

    for (size_t i = 0; i < params->lut_size; i++) {
        float x = rescale(lut[i], params);
        if (x > cutoff && peak > 0.0f)
            x = powf(fmaxf(x / peak, 0.0f), gamma);
        lut[i] = rescale_out(x, params);
    }
}

static const struct pl_tone_map_function fn_gamma = {
    .name = "gamma",
    .scaling = PL_HDR_NORM,
    .map = gamma_map,
    .map_inverse = NULL,
};

/* 8. Linear */
static void linear_map(float *lut, const struct pl_tone_map_params *params)
{
    const float gain = params->constants.exposure;

    for (size_t i = 0; i < params->lut_size; i++) {
        float x = rescale_in(lut[i], params);
        x *= gain;
        lut[i] = rescale_out(x, params);
    }
}

static const struct pl_tone_map_function fn_linear = {
    .name = "linear",
    .scaling = PL_HDR_PQ,
    .map = linear_map,
    .map_inverse = linear_map,
};

/* 9. BT.2446A */
static void bt2446a_map(float *lut, const struct pl_tone_map_params *params)
{
    const float phdr = 1.0f + 32.0f * powf(fmaxf(0.0f, params->input_max / 10000.0f), 1.0f / 2.4f);
    const float psdr = 1.0f + 32.0f * powf(fmaxf(0.0f, params->output_max / 10000.0f), 1.0f / 2.4f);
    const float log_phdr = logf(fmaxf(phdr, 1e-6f));

    for (size_t i = 0; i < params->lut_size; i++) {
        float x = powf(fmaxf(0.0f, rescale_in(lut[i], params)), 1.0f / 2.4f);
        x = (log_phdr > 1e-6f) ? (logf(fmaxf(1.0f + (phdr - 1.0f) * x, 1e-6f)) / log_phdr) : x;

        if (x <= 0.7399f) {
            x = 1.0770f * x;
        } else if (x < 0.9909f) {
            x = (-1.1510f * x + 2.7811f) * x - 0.6302f;
        } else {
            x = 0.5f * x + 0.5f;
        }

        x = (psdr > 1.0001f) ? ((powf(fmaxf(psdr, 1e-6f), x) - 1.0f) / (psdr - 1.0f)) : x;
        lut[i] = bt1886_eotf(x, params->output_min, params->output_max);
    }
}

static void bt2446a_inv_map(float *lut, const struct pl_tone_map_params *params)
{
    for (size_t i = 0; i < params->lut_size; i++) {
        float x = bt1886_oetf(lut[i], params->input_min, params->input_max);
        x *= 255.0f;
        if (x > 70.0f) {
            x = powf(fmaxf(x, 0.0f), (2.8305e-6f * x - 7.4622e-4f) * x + 1.2528f);
        } else {
            x = powf(fmaxf(x, 0.0f), (1.8712e-5f * x - 2.7334e-3f) * x + 1.3141f);
        }
        x = powf(fmaxf(x / 1000.0f, 0.0f), 2.4f);
        lut[i] = rescale_out(x, params);
    }
}

static const struct pl_tone_map_function fn_bt2446a = {
    .name = "bt2446a",
    .scaling = PL_HDR_NITS,
    .map = bt2446a_map,
    .map_inverse = bt2446a_inv_map,
};

/* 10. Spline */
static void spline_map(float *lut, const struct pl_tone_map_params *params)
{
    float src_pivot, dst_pivot;
    st2094_pick_knee(&src_pivot, &dst_pivot, params);

    float denom_slope = src_pivot - params->input_min;
    float slope = (fabsf(denom_slope) > 1e-6f)
        ? ((dst_pivot - params->output_min) / denom_slope)
        : 1.0f;

    float ratio = (params->output_max > 0.0f)
        ? (params->input_max / params->output_max - 1.0f)
        : 0.0f;
    ratio = fclampf(params->constants.slope_tuning * ratio,
                    params->constants.slope_offset,
                    1.0f + params->constants.slope_offset);
    if (slope > 0.0f)
        slope = powf(slope, (1.0f - params->constants.spline_contrast) * ratio);

    const float in_min = params->input_min - src_pivot;
    const float in_max = params->input_max - src_pivot;
    const float out_min = params->output_min - dst_pivot;
    const float out_max = params->output_max - dst_pivot;

    const float Pa = (fabsf(in_min) > 1e-6f)
        ? ((out_min - slope * in_min) / (in_min * in_min))
        : 0.0f;
    const float Pb = slope;

    const float t = 2.0f * in_max * in_max;
    const float Qa = (fabsf(in_max * t) > 1e-6f)
        ? ((slope * in_max - out_max) / (in_max * t))
        : 0.0f;
    const float Qb = (fabsf(t) > 1e-6f)
        ? (-3.0f * (slope * in_max - out_max) / t)
        : 0.0f;
    const float Qc = slope;

    for (size_t i = 0; i < params->lut_size; i++) {
        float x = lut[i] - src_pivot;
        x = (x > 0.0f) ? (((Qa * x + Qb) * x + Qc) * x) : ((Pa * x + Pb) * x);
        lut[i] = x + dst_pivot;
    }
}

static const struct pl_tone_map_function fn_spline = {
    .name = "spline",
    .scaling = PL_HDR_PQ,
    .map = spline_map,
    .map_inverse = spline_map,
};

static const struct pl_tone_map_function *pick_function(enum maclc_tonecurve curve)
{
    switch (curve) {
    case MACLC_TC_AUTO:
    case MACLC_TC_SPLINE:
        return &fn_spline;
    case MACLC_TC_CLIP:
        return &fn_clip;
    case MACLC_TC_BT2390:
        return &fn_bt2390;
    case MACLC_TC_REINHARD:
        return &fn_reinhard;
    case MACLC_TC_MOBIUS:
        return &fn_mobius;
    case MACLC_TC_HABLE:
        return &fn_hable;
    case MACLC_TC_GAMMA:
        return &fn_gamma;
    case MACLC_TC_LINEAR:
        return &fn_linear;
    case MACLC_TC_BT2446A:
        return &fn_bt2446a;
    case MACLC_TC_ST2094_40:
        return &fn_st2094_40;
    }
    return &fn_spline;
}

static void params_infer(struct pl_tone_map_params *par)
{
    if (par->param != 0.0f) {
        if (par->function == &fn_st2094_40)
            par->constants.knee_adaptation = par->param;
        if (par->function == &fn_bt2390)
            par->constants.knee_offset = par->param;
        if (par->function == &fn_spline)
            par->constants.spline_contrast = par->param;
        if (par->function == &fn_reinhard)
            par->constants.reinhard_contrast = par->param;
        if (par->function == &fn_mobius || par->function == &fn_gamma)
            par->constants.linear_knee = par->param;
        if (par->function == &fn_linear)
            par->constants.exposure = par->param;
    }

    fix_constants(&par->constants);

    /* Constrain the input peak to be no less than target SDR white */
    float sdr = pl_hdr_rescale(par->output_scaling, par->input_scaling, par->output_max);
    sdr = fminf(sdr, pl_hdr_rescale(PL_HDR_NITS, par->input_scaling, PL_COLOR_SDR_WHITE));
    par->input_max = fmaxf(par->input_max, sdr);

    if (!par->function->map_inverse)
        par->output_max = fminf(par->output_max, par->input_max);
}

static struct pl_tone_map_params fix_params(const struct pl_tone_map_params *params)
{
    struct pl_tone_map_params fixed = *params;
    params_infer(&fixed);

    const struct pl_tone_map_function *fun = params->function;
    fixed.input_scaling = fun->scaling;
    fixed.output_scaling = fun->scaling;
    fixed.input_min  = pl_hdr_rescale(params->input_scaling,  fun->scaling, fixed.input_min);
    fixed.input_max  = pl_hdr_rescale(params->input_scaling,  fun->scaling, fixed.input_max);
    fixed.input_avg  = pl_hdr_rescale(params->input_scaling,  fun->scaling, fixed.input_avg);
    fixed.output_min = pl_hdr_rescale(params->output_scaling, fun->scaling, fixed.output_min);
    fixed.output_max = pl_hdr_rescale(params->output_scaling, fun->scaling, fixed.output_max);

    return fixed;
}

static void map_lut(float *lut, const struct pl_tone_map_params *params)
{
    if (params->output_max > params->input_max + 1e-4f && params->function->map_inverse) {
        params->function->map_inverse(lut, params);
    } else {
        params->function->map(lut, params);
    }
}

void maclc_tonecurve_generate(const struct maclc_tonecurve_params *p, float *lut, int n)
{
    if (!p || !lut || n <= 0)
        return;

    const struct pl_tone_map_function *fun = pick_function(p->curve);

    float in_min = (p->input_min > 0.0f) ? p->input_min : 0.0f;
    float in_max = (p->input_max > 0.0f) ? p->input_max : 1000.0f;
    float in_avg = 0.0f;
    float out_min = (p->output_min > 0.0f) ? p->output_min : 0.0f;
    float out_max = (p->output_max > 0.0f) ? p->output_max : PL_COLOR_SDR_WHITE;

    struct pl_tone_map_params base = {
        .function       = fun,
        .constants      = kDefaultConstants,
        .input_scaling  = PL_HDR_PQ,
        .output_scaling = PL_HDR_PQ,
        .lut_size       = (size_t)n,
        .param          = p->param,
    };

    /* Dynamic HDR10+ metadata handling */
    if (p->hdr10plus) {
        const vlc_video_hdr_dynamic_metadata_t *hdm = p->hdr10plus;

        /* Per-scene peak from maxscl */
        float scene_max = fmaxf(fmaxf(hdm->maxscl[0], hdm->maxscl[1]), hdm->maxscl[2]);
        if (scene_max > 0.0f) {
            if (scene_max <= 1.5f)
                scene_max *= 10000.0f;
            in_max = scene_max;
        }

        /* Per-scene average from average_maxrgb */
        float scene_avg = hdm->average_maxrgb;
        if (scene_avg > 0.0f) {
            if (scene_avg <= 1.5f)
                scene_avg *= 10000.0f;
            in_avg = scene_avg;
        }

        if (p->curve == MACLC_TC_ST2094_40 && hdm->tone_mapping_flag && hdm->num_bezier_anchors > 0) {
            base.hdr.ootf.num_anchors = hdm->num_bezier_anchors;
            base.hdr.ootf.knee_x = hdm->knee_point_x;
            base.hdr.ootf.knee_y = hdm->knee_point_y;
            base.hdr.ootf.target_luma = hdm->targeted_luminance;
            uint8_t count = hdm->num_bezier_anchors;
            if (count > 15) count = 15;
            memcpy(base.hdr.ootf.anchors, hdm->bezier_curve_anchors, count * sizeof(float));
        }
    }

    base.input_min  = maclc_nits_to_pq(in_min);
    base.input_max  = maclc_nits_to_pq(in_max);
    base.input_avg  = (in_avg > 0.0f) ? maclc_nits_to_pq(in_avg) : 0.0f;
    base.output_min = maclc_nits_to_pq(out_min);
    base.output_max = maclc_nits_to_pq(out_max);

    struct pl_tone_map_params fixed = fix_params(&base);

    /* Generate input values evenly spaced in PQ over [base.input_min, base.input_max] */
    for (int i = 0; i < n; i++) {
        float x = (n > 1) ? ((float)i / (float)(n - 1)) : 0.0f;
        float x_pq = PL_MIX(base.input_min, base.input_max, x);
        lut[i] = pl_hdr_rescale(PL_HDR_PQ, fixed.function->scaling, x_pq);
    }

    map_lut(lut, &fixed);

    /* Sanitize outputs and adapt back to PQ */
    for (int i = 0; i < n; i++) {
        float x = fclampf(lut[i], fixed.output_min, fixed.output_max);
        lut[i] = fclampf(pl_hdr_rescale(fixed.function->scaling, PL_HDR_PQ, x), 0.0f, 1.0f);
    }
}

float maclc_tonecurve_sample(const struct maclc_tonecurve_params *p, float x_pq)
{
    float val = x_pq;
    if (!p)
        return val;

    const struct pl_tone_map_function *fun = pick_function(p->curve);

    float in_min = (p->input_min > 0.0f) ? p->input_min : 0.0f;
    float in_max = (p->input_max > 0.0f) ? p->input_max : 1000.0f;
    float in_avg = 0.0f;
    float out_min = (p->output_min > 0.0f) ? p->output_min : 0.0f;
    float out_max = (p->output_max > 0.0f) ? p->output_max : PL_COLOR_SDR_WHITE;

    struct pl_tone_map_params base = {
        .function       = fun,
        .constants      = kDefaultConstants,
        .input_scaling  = PL_HDR_PQ,
        .output_scaling = PL_HDR_PQ,
        .lut_size       = 1,
        .param          = p->param,
    };

    if (p->hdr10plus) {
        const vlc_video_hdr_dynamic_metadata_t *hdm = p->hdr10plus;
        float scene_max = fmaxf(fmaxf(hdm->maxscl[0], hdm->maxscl[1]), hdm->maxscl[2]);
        if (scene_max > 0.0f) {
            if (scene_max <= 1.5f)
                scene_max *= 10000.0f;
            in_max = scene_max;
        }

        float scene_avg = hdm->average_maxrgb;
        if (scene_avg > 0.0f) {
            if (scene_avg <= 1.5f)
                scene_avg *= 10000.0f;
            in_avg = scene_avg;
        }

        if (p->curve == MACLC_TC_ST2094_40 && hdm->tone_mapping_flag && hdm->num_bezier_anchors > 0) {
            base.hdr.ootf.num_anchors = hdm->num_bezier_anchors;
            base.hdr.ootf.knee_x = hdm->knee_point_x;
            base.hdr.ootf.knee_y = hdm->knee_point_y;
            base.hdr.ootf.target_luma = hdm->targeted_luminance;
            uint8_t count = hdm->num_bezier_anchors;
            if (count > 15) count = 15;
            memcpy(base.hdr.ootf.anchors, hdm->bezier_curve_anchors, count * sizeof(float));
        }
    }

    base.input_min  = maclc_nits_to_pq(in_min);
    base.input_max  = maclc_nits_to_pq(in_max);
    base.input_avg  = (in_avg > 0.0f) ? maclc_nits_to_pq(in_avg) : 0.0f;
    base.output_min = maclc_nits_to_pq(out_min);
    base.output_max = maclc_nits_to_pq(out_max);

    struct pl_tone_map_params fixed = fix_params(&base);

    val = fclampf(val, base.input_min, base.input_max);
    val = pl_hdr_rescale(PL_HDR_PQ, fixed.function->scaling, val);
    map_lut(&val, &fixed);
    val = fclampf(val, fixed.output_min, fixed.output_max);
    val = pl_hdr_rescale(fixed.function->scaling, PL_HDR_PQ, val);
    return fclampf(val, 0.0f, 1.0f);
}

bool maclc_tonecurve_params_equal(const struct maclc_tonecurve_params *a,
                                  const struct maclc_tonecurve_params *b)
{
    if (a == b)
        return true;
    if (!a || !b)
        return false;

    if (a->curve != b->curve ||
        a->param != b->param ||
        a->input_min != b->input_min ||
        a->input_max != b->input_max ||
        a->output_min != b->output_min ||
        a->output_max != b->output_max)
    {
        return false;
    }

    if (a->hdr10plus == b->hdr10plus)
        return true;
    if (!a->hdr10plus || !b->hdr10plus)
        return false;

    const vlc_video_hdr_dynamic_metadata_t *ha = a->hdr10plus;
    const vlc_video_hdr_dynamic_metadata_t *hb = b->hdr10plus;

    if (ha->tone_mapping_flag != hb->tone_mapping_flag ||
        ha->targeted_luminance != hb->targeted_luminance ||
        ha->average_maxrgb != hb->average_maxrgb ||
        ha->knee_point_x != hb->knee_point_x ||
        ha->knee_point_y != hb->knee_point_y ||
        ha->num_bezier_anchors != hb->num_bezier_anchors)
    {
        return false;
    }

    for (int i = 0; i < 3; i++) {
        if (ha->maxscl[i] != hb->maxscl[i])
            return false;
    }

    for (int i = 0; i < ha->num_bezier_anchors && i < 15; i++) {
        if (ha->bezier_curve_anchors[i] != hb->bezier_curve_anchors[i])
            return false;
    }

    return true;
}
