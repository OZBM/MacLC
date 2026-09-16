/*****************************************************************************
 * maclc_tonemap.h: HDR picture-mode tone curves (BT.2390 Hermite spline)
 *****************************************************************************
 * Copyright (C) 2026 Hazen Studio
 *
 * This program is free software; you can redistribute it and/or modify it
 * under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin Street, Fifth Floor, Boston MA 02110-1301, USA.
 *****************************************************************************/

#ifndef MACLC_TONEMAP_H
#define MACLC_TONEMAP_H

#include <math.h>
#include <stdbool.h>
#include <stddef.h>

/*
 * SMPTE ST 2084:2014 (PQ - Perceptual Quantizer) constants
 *
 * m1 = 2610 / 16384          = 0.1593017578125
 * m2 = (2523 / 4096) * 128   = 78.84375
 * c1 = 3424 / 4096           = 0.8359375
 * c2 = (2413 / 4096) * 32    = 18.8515625
 * c3 = (2392 / 4096) * 32    = 18.6875
 */
#define MACLC_PQ_M1 (2610.0f / 16384.0f)
#define MACLC_PQ_M2 ((2523.0f / 4096.0f) * 128.0f)
#define MACLC_PQ_C1 (3424.0f / 4096.0f)
#define MACLC_PQ_C2 ((2413.0f / 4096.0f) * 32.0f)
#define MACLC_PQ_C3 ((2392.0f / 4096.0f) * 32.0f)

/**
 * SMPTE ST 2084 EOTF: maps normalised PQ code value e in [0, 1] to
 * optical luminance in cd/m² (nits) in [0, 10000].
 */
static inline float maclc_pq_to_nits(float e)
{
    if (e <= 0.0f)
        return 0.0f;
    if (e >= 1.0f)
        return 10000.0f;

    float em2 = powf(e, 1.0f / MACLC_PQ_M2);
    float num = em2 - MACLC_PQ_C1;
    if (num < 0.0f)
        num = 0.0f;

    float den = MACLC_PQ_C2 - MACLC_PQ_C3 * em2;
    if (den <= 0.0f)
        return 10000.0f;

    float y = powf(num / den, 1.0f / MACLC_PQ_M1);
    float nits = y * 10000.0f;
    if (nits < 0.0f)
        nits = 0.0f;
    else if (nits > 10000.0f)
        nits = 10000.0f;
    return nits;
}

/**
 * SMPTE ST 2084 inverse EOTF: maps optical luminance in cd/m² (nits)
 * in [0, 10000] to normalised PQ code value in [0, 1].
 */
static inline float maclc_nits_to_pq(float nits)
{
    if (nits <= 0.0f)
        return 0.0f;
    if (nits >= 10000.0f)
        return 1.0f;

    float y = nits / 10000.0f;
    float ym1 = powf(y, MACLC_PQ_M1);
    float num = MACLC_PQ_C1 + MACLC_PQ_C2 * ym1;
    float den = 1.0f + MACLC_PQ_C3 * ym1;
    float p = powf(num / den, MACLC_PQ_M2);
    if (p < 0.0f)
        p = 0.0f;
    else if (p > 1.0f)
        p = 1.0f;
    return p;
}

/**
 * Picture tone mapping modes:
 * - MACLC_TONE_ACCURATE: faithful to the master, late knee at 90 % of display peak
 *   with soft exponential shoulder in PQ space, gain 1.0.
 * - MACLC_TONE_BALANCED: standard BT.2390 EETF knee, balanced highlights/mid-tones, gain 1.0.
 * - MACLC_TONE_BRIGHT: mid-tone lift via luminance gain, standard BT.2390 knee.
 */
typedef enum {
    MACLC_TONE_ACCURATE = 1,
    MACLC_TONE_BALANCED = 2,
    MACLC_TONE_BRIGHT   = 3
} maclc_tone_mode;

/**
 * Pre-computed tone mapping parameters for a video presentation on a target display.
 */
typedef struct {
    maclc_tone_mode mode;
    float content_peak;     /* Content peak luminance (cd/m²), >= 100.0 */
    float display_peak;     /* Target display peak luminance (cd/m²), clamped to [100, 10000] */
    float reference_white;  /* Luminance shown at SDR white (cd/m², default 100, MACLC_HDR_REFERENCE_WHITE) */
    float gain;             /* Input luminance gain: 1.0 for ACCURATE/BALANCED, 1.0..1.6 for BRIGHT */
    float knee_pq;          /* Knee start in PQ: eK for ACCURATE, normalized KS for BALANCED/BRIGHT */
    float src_peak_pq;      /* Effective source peak luminance in PQ [0, 1] (after gain) */
    float dst_peak_pq;      /* Target display peak luminance in PQ [0, 1] */
    bool identity;          /* True if display covers content and gain == 1: 1:1 pass-through */
} maclc_tone_params;

/**
 * Initializes tone mapping parameters according to the requested picture mode,
 * content mastering peak, display peak, and reference diffuse white.
 *
 * Curve definitions:
 * - ACCURATE mode: A late knee with a soft exponential shoulder in PQ space.
 *   The ITU-R BT.2390 Hermite spline cannot support knees above KS = 1.5*maxLum - 0.5
 *   without its derivative turning negative mid-segment (causing non-monotonic
 *   dips and overshoot above display peak). ACCURATE therefore uses an exponential
 *   shoulder with knee anchored at 90 % of the target display peak:
 *     eK = maclc_nits_to_pq(0.9f * display_peak)
 *     eD = dst_peak_pq = maclc_nits_to_pq(display_peak)
 *   stored in knee_pq as eK. For e <= eK, output is e; for e > eK, output is
 *   eK + (eD - eK) * (1 - expf(-(e - eK) / (eD - eK))).
 *
 * - BALANCED and BRIGHT modes: Standard ITU-R BT.2390-10 section 5.4.1 Hermite spline.
 *   maxLum = dst_peak_pq / src_peak_pq
 *   KS = 1.5 * maxLum - 0.5
 *   stored in knee_pq as KS.
 */
static inline void maclc_tone_params_init(maclc_tone_params *p,
                                          maclc_tone_mode mode,
                                          float content_peak_nits,
                                          float display_peak_nits,
                                          float reference_white_nits)
{
    if (p == NULL)
        return;

    /* content_peak <= 0 means unknown: assume 1000 cd/m² */
    if (content_peak_nits <= 0.0f)
        content_peak_nits = 1000.0f;
    else if (content_peak_nits > 10000.0f)
        content_peak_nits = 10000.0f;

    /* reference_white <= 0: MacLC's anchor, 100 cd/m² at SDR white
     * (MACLC_HDR_REFERENCE_WHITE in maclc_hdr_vars.h) */
    if (reference_white_nits <= 0.0f)
        reference_white_nits = 100.0f;

    /* display_peak clamps to [100, 10000] cd/m² */
    if (display_peak_nits < 100.0f)
        display_peak_nits = 100.0f;
    else if (display_peak_nits > 10000.0f)
        display_peak_nits = 10000.0f;

    p->mode = mode;
    p->content_peak = content_peak_nits;
    p->display_peak = display_peak_nits;
    p->reference_white = reference_white_nits;

    /*
     * Mid-tone lift (gain):
     * ACCURATE and BALANCED use gain 1.0.
     * BRIGHT uses gain = clamp(0.55 * display_peak / reference_white, 1.0, 1.6).
     */
    if (mode == MACLC_TONE_BRIGHT) {
        float g = 0.55f * display_peak_nits / reference_white_nits;
        if (g < 1.0f)
            g = 1.0f;
        else if (g > 1.6f)
            g = 1.6f;
        p->gain = g;
    } else {
        p->gain = 1.0f;
    }

    /*
     * Identity case: if gain == 1 and content_peak <= display_peak,
     * the display can show the master as graded without roll-off.
     */
    if (p->gain == 1.0f && content_peak_nits <= display_peak_nits)
        p->identity = true;
    else
        p->identity = false;

    /* Source peak luminance with gain applied, clamped to PQ limit (10000 cd/m²) */
    float gained_content_peak = content_peak_nits * p->gain;
    if (gained_content_peak > 10000.0f)
        gained_content_peak = 10000.0f;

    p->src_peak_pq = maclc_nits_to_pq(gained_content_peak);
    p->dst_peak_pq = maclc_nits_to_pq(display_peak_nits);

    if (mode == MACLC_TONE_ACCURATE) {
        /*
         * ACCURATE mode: soft exponential shoulder in PQ space.
         * Knee is at 90 % of display peak:
         *   eK = maclc_nits_to_pq(0.9f * display_peak)
         */
        float eK = maclc_nits_to_pq(0.9f * display_peak_nits);
        p->knee_pq = eK;
    } else {
        /*
         * BALANCED and BRIGHT modes: ITU-R BT.2390-10 EETF Hermite spline.
         * maxLum: target display peak normalised by source peak in PQ space.
         * KS = 1.5 * maxLum - 0.5 (standard BT.2390 knee).
         */
        float maxLum = (p->src_peak_pq > 0.0f) ? (p->dst_peak_pq / p->src_peak_pq) : 1.0f;
        float standard_ks = 1.5f * maxLum - 0.5f;
        float ks = standard_ks;

        if (ks < 0.0f)
            ks = 0.0f;
        else if (ks > maxLum)
            ks = maxLum;

        p->knee_pq = ks;
    }
}

/**
 * Evaluates the ITU-R BT.2390-10 section 5.4.1 Hermite spline in normalised PQ space.
 *
 * Variables:
 * - E_1: normalised PQ coordinate in [0, 1]
 * - KS: knee start point in [0, maxLum]
 * - maxLum: target peak in normalised PQ [0, 1]
 *
 * Spline definition:
 * For E_1 <= KS:
 *   E_2 = E_1 (1:1 reproduction)
 * For KS < E_1 <= 1:
 *   T = (E_1 - KS) / (1 - KS)
 *   h00 = 2*T^3 - 3*T^2 + 1
 *   h10 = T^3 - 2*T^2 + T
 *   h01 = -2*T^3 + 3*T^2
 *   P[E_1] = h00 * KS + h10 * (1 - KS) + h01 * maxLum
 *   E_2 = min(P[E_1], maxLum)
 * For E_1 > 1:
 *   E_2 = maxLum
 */
static inline float maclc_bt2390_hermite(float E1, float ks, float maxLum)
{
    if (E1 <= ks)
        return E1;
    if (E1 >= 1.0f)
        return maxLum;

    float denom = 1.0f - ks;
    if (denom <= 0.0f)
        return maxLum;

    float T = (E1 - ks) / denom;
    float T2 = T * T;
    float T3 = T2 * T;

    /* Cubic Hermite basis functions */
    float h00 = 2.0f * T3 - 3.0f * T2 + 1.0f;
    float h10 = T3 - 2.0f * T2 + T;
    float h01 = -2.0f * T3 + 3.0f * T2;

    float E2 = h00 * ks + h10 * denom + h01 * maxLum;

    /* Ensure monotonic non-decreasing behavior and never exceed maxLum */
    if (E2 > maxLum)
        E2 = maxLum;
    else if (E2 < ks)
        E2 = ks;

    return E2;
}

/**
 * Maps content optical luminance in cd/m² (nits) to displayed luminance in cd/m².
 */
static inline float maclc_tone_map_nits(const maclc_tone_params *p, float nits)
{
    if (nits <= 0.0f)
        return 0.0f;

    /*
     * When identity is set, the display can show the full content range
     * as graded without roll-off.
     */
    if (p->identity)
        return (nits > p->display_peak) ? p->display_peak : nits;

    /*
     * ACCURATE mode:
     * - for nits <= 0.9 * display_peak: exact 1:1 luminance reproduction
     * - for nits > 0.9 * display_peak: soft exponential shoulder in PQ space
     *   e_out = eK + (eD - eK) * (1 - expf(-(e - eK) / (eD - eK)))
     */
    if (p->mode == MACLC_TONE_ACCURATE) {
        float knee_nits = 0.9f * p->display_peak;
        if (nits <= knee_nits)
            return nits;

        float e = maclc_nits_to_pq(nits);
        float eK = p->knee_pq;
        float eD = p->dst_peak_pq;
        float delta = eD - eK;
        if (delta <= 0.0f)
            return p->display_peak;

        float e_out = eK + delta * (1.0f - expf(-(e - eK) / delta));
        if (e_out >= eD)
            return p->display_peak;
        if (e_out < 0.0f)
            return 0.0f;

        float out_nits = maclc_pq_to_nits(e_out);
        if (out_nits > p->display_peak)
            out_nits = p->display_peak;
        else if (out_nits < 0.0f)
            out_nits = 0.0f;

        return out_nits;
    }

    /*
     * BALANCED and BRIGHT modes:
     * When KS >= 1 (or gained source peak <= display peak), the display can show
     * the full (gained) content range without compression.
     * The mapping is exactly min(gain * nits, display_peak) with no spline roll-off.
     */
    if (p->knee_pq >= 1.0f || (p->content_peak * p->gain) <= p->display_peak) {
        float out = p->gain * nits;
        return (out > p->display_peak) ? p->display_peak : out;
    }

    /* Apply mid-tone lift in luminance first */
    float gained_nits = nits * p->gain;

    /* Input at or above gained content peak maps to target display peak */
    if (gained_nits >= p->content_peak * p->gain || gained_nits >= 10000.0f)
        return p->display_peak;

    if (p->src_peak_pq <= 0.0f)
        return 0.0f;

    /* Convert gained luminance to PQ space */
    float E = maclc_nits_to_pq(gained_nits);

    /* Normalise by gained content peak in PQ space (BT.2390 E_1) */
    float E1 = E / p->src_peak_pq;
    float ks = p->knee_pq;

    /* Exact reproduction below the knee */
    if (E1 <= ks)
        return (gained_nits > p->display_peak) ? p->display_peak : gained_nits;

    if (E1 >= 1.0f)
        return p->display_peak;

    float maxLum = (p->src_peak_pq > 0.0f) ? (p->dst_peak_pq / p->src_peak_pq) : 1.0f;
    float E2 = maclc_bt2390_hermite(E1, ks, maxLum);

    /* Denormalise back to PQ space */
    float E_out = E2 * p->src_peak_pq;
    if (E_out >= p->dst_peak_pq)
        return p->display_peak;
    if (E_out < 0.0f)
        return 0.0f;

    float out_nits = maclc_pq_to_nits(E_out);
    if (out_nits > p->display_peak)
        out_nits = p->display_peak;
    else if (out_nits < 0.0f)
        out_nits = 0.0f;

    return out_nits;
}

/**
 * Maps content PQ code value [0, 1] to displayed PQ code value [0, 1].
 * Called per pixel on max(R, G, B) in the GPU rendering pass.
 */
static inline float maclc_tone_map_pq(const maclc_tone_params *p, float pq)
{
    if (pq <= 0.0f)
        return 0.0f;

    /*
     * When identity is set, the display can show the full content range
     * as graded without roll-off.
     */
    if (p->identity)
        return (pq > p->dst_peak_pq) ? p->dst_peak_pq : pq;

    /*
     * ACCURATE mode:
     * - for e <= eK: output e
     * - for e > eK: output eK + (eD - eK) * (1 - expf(-(e - eK) / (eD - eK)))
     */
    if (p->mode == MACLC_TONE_ACCURATE) {
        float e = (pq > 1.0f) ? 1.0f : pq;
        float eK = p->knee_pq;
        float eD = p->dst_peak_pq;

        if (e <= eK)
            return (e > eD) ? eD : e;

        float delta = eD - eK;
        if (delta <= 0.0f)
            return eD;

        float out = eK + delta * (1.0f - expf(-(e - eK) / delta));
        if (out >= eD)
            return eD;
        if (out < 0.0f)
            return 0.0f;

        return out;
    }

    /*
     * BALANCED and BRIGHT modes:
     * When KS >= 1 (or gained source peak <= display peak), the display can show
     * the full (gained) content range without compression.
     * The mapping is exactly min(gain * nits, display_peak) in PQ with no spline roll-off.
     */
    if (p->knee_pq >= 1.0f || (p->content_peak * p->gain) <= p->display_peak) {
        if (p->gain == 1.0f)
            return (pq > p->dst_peak_pq) ? p->dst_peak_pq : pq;

        float nits = maclc_pq_to_nits(pq);
        float gained_nits = nits * p->gain;
        if (gained_nits >= p->display_peak)
            return p->dst_peak_pq;
        float out_pq = maclc_nits_to_pq(gained_nits);
        return (out_pq > p->dst_peak_pq) ? p->dst_peak_pq : out_pq;
    }

    if (p->src_peak_pq <= 0.0f)
        return 0.0f;

    /*
     * Mid-tone lift: applied to luminance first.
     * When gain == 1.0, PQ signal is used directly without conversion round-trip.
     */
    float E;
    if (p->gain == 1.0f) {
        E = (pq > 1.0f) ? 1.0f : pq;
    } else {
        float nits = maclc_pq_to_nits(pq);
        float gained_nits = nits * p->gain;
        if (gained_nits >= p->content_peak * p->gain || gained_nits >= 10000.0f)
            return p->dst_peak_pq;
        E = maclc_nits_to_pq(gained_nits);
    }

    /* Normalise by gained content peak in PQ space (BT.2390 E_1) */
    float E1 = E / p->src_peak_pq;
    float ks = p->knee_pq;

    /* Exact reproduction below the knee */
    if (E1 <= ks) {
        if (p->gain == 1.0f)
            return (pq > p->dst_peak_pq) ? p->dst_peak_pq : pq;
        return (E > p->dst_peak_pq) ? p->dst_peak_pq : E;
    }

    if (E1 >= 1.0f)
        return p->dst_peak_pq;

    float maxLum = (p->src_peak_pq > 0.0f) ? (p->dst_peak_pq / p->src_peak_pq) : 1.0f;
    float E2 = maclc_bt2390_hermite(E1, ks, maxLum);

    /* Denormalise back to PQ space */
    float E_out = E2 * p->src_peak_pq;
    if (E_out >= p->dst_peak_pq)
        return p->dst_peak_pq;
    if (E_out < 0.0f)
        return 0.0f;

    return E_out;
}

#endif /* MACLC_TONEMAP_H */
