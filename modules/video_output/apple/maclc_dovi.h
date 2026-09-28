/*****************************************************************************
 * maclc_dovi.h: Dolby Vision reference math and parameter normalisation
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
 *****************************************************************************
 * Ported from libplacebo v7.351.0 (LGPL-2.1+):
 *   - src/include/libplacebo/colorspace.h: struct pl_dovi_metadata
 *   - src/shaders/colorspace.c: pl_shader_dovi_reshape (polynomial & MMR)
 *   - src/shaders/colorspace.c: pl_shader_decode_color (PL_COLOR_SYSTEM_DOLBYVISION)
 *   - src/colorspace.c: decoding matrix construction (dovi_lms2rgb * linear)
 *   - modules/video_output/libplacebo/utils.c: vlc_placebo_DoviMetadata normalisation
 *****************************************************************************/

#ifndef MACLC_DOVI_H
#define MACLC_DOVI_H

#ifdef HAVE_CONFIG_H
# include "config.h"
#endif

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include <string.h>
#include <math.h>

#include <vlc_common.h>
#include <vlc_ancillary.h>

#ifndef MACLC_HDR_REFERENCE_WHITE
# define MACLC_HDR_REFERENCE_WHITE 100.0f
#endif

/*
 * SMPTE ST 2084 (PQ - Perceptual Quantizer) constants
 */
#ifndef MACLC_PQ_M1
# define MACLC_PQ_M1 (2610.0f / 16384.0f)
# define MACLC_PQ_M2 ((2523.0f / 4096.0f) * 128.0f)
# define MACLC_PQ_C1 (3424.0f / 4096.0f)
# define MACLC_PQ_C2 ((2413.0f / 4096.0f) * 32.0f)
# define MACLC_PQ_C3 ((2392.0f / 4096.0f) * 32.0f)
#endif

/**
 * SMPTE ST 2084 EOTF: maps normalised PQ code value e in [0, 1] to
 * optical luminance in cd/m² (nits) in [0, 10000].
 */
static inline float maclc_dovi_pq_to_nits(float e)
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
 * Inverse Hunt-Pointer-Estevez LMS to BT.2020 RGB matrix (row-major).
 * Dolby Vision outputs BT.2020-referred HPE LMS; this matrix maps HPE LMS
 * back to linear BT.2020 RGB.
 * Ported from libplacebo src/shaders/colorspace.c (dovi_lms2rgb).
 */
static const float kMacLCDoviLms2Rgb[9] = {
     3.06441879f, -2.16597676f,  0.10155818f,
    -0.65612108f,  1.78554118f, -0.12943749f,
     0.01736321f, -0.04725154f,  1.03004253f,
};

static inline void maclc_dovi_mat3_mul(float out[9], const float a[9], const float b[9])
{
    for (int r = 0; r < 3; r++) {
        for (int c = 0; c < 3; c++) {
            out[r * 3 + c] = a[r * 3 + 0] * b[0 * 3 + c]
                           + a[r * 3 + 1] * b[1 * 3 + c]
                           + a[r * 3 + 2] * b[2 * 3 + c];
        }
    }
}

/*
 * Dolby Vision reshaping parameters per piece.
 * Kept strictly 16-byte aligned (112 bytes total) for MSL uniform compatibility.
 */
struct maclc_dovi_piece {
    uint32_t method;            /* 0 = polynomial, 1 = MMR */
    uint32_t mmr_order;         /* 1, 2, or 3 (if MMR) */
    float    poly_coef[3];      /* c0, c1, c2 */
    float    mmr_constant;
    float    mmr_coef[3][7];    /* [order 0..2][term 0..6] */
    float    _pad;              /* padding to 112 bytes (multiple of 16) */
};

/*
 * Dolby Vision reshaping parameters per component (Y, Cb, Cr).
 * Kept strictly 16-byte aligned (944 bytes total) for MSL uniform compatibility.
 */
struct maclc_dovi_comp {
    uint32_t num_pivots;
    float    pivots[9];
    float    _pad[2];           /* padding to 48 bytes */
    struct maclc_dovi_piece pieces[8]; /* 8 * 112 = 896 bytes */
};

/*
 * Everything the Dolby Vision shader needs, normalised like pl_dovi_metadata.
 * Total size: 2960 bytes (multiple of 16 bytes).
 */
struct maclc_dovi_params {
    struct maclc_dovi_comp comp[3];    /* 3 * 944 = 2832 bytes */
    float    nonlinear_offset[3];      /* input offset */
    float    _pad_offset;              /* padding to 16 bytes */
    float    nonlinear[9];             /* row-major ycc_to_rgb matrix */
    float    _pad_nl[3];               /* padding to 48 bytes */
    float    linear[9];                /* row-major linear BT.2020 decoding matrix */
    float    _pad_lin[3];              /* padding to 48 bytes */
    float    source_min_pq;            /* 12-bit PQ normalised to [0, 1] */
    float    source_max_pq;            /* 12-bit PQ normalised to [0, 1] */
    float    source_min_nits;          /* matching cd/m² */
    float    source_max_nits;          /* matching cd/m² */
};

#if defined(__STDC_VERSION__) && __STDC_VERSION__ >= 201112L
_Static_assert(sizeof(struct maclc_dovi_piece) == 112, "maclc_dovi_piece layout mismatch");
_Static_assert(sizeof(struct maclc_dovi_comp) == 944, "maclc_dovi_comp layout mismatch");
_Static_assert(sizeof(struct maclc_dovi_params) == 2960, "maclc_dovi_params layout mismatch");
#endif

/**
 * Normalise raw VLC Dolby Vision metadata into maclc_dovi_params.
 * Reproduces the normalisation performed in libplacebo's vlc_placebo_DoviMetadata
 * and colorspace decoding matrix construction.
 */
static inline void maclc_dovi_params_from_vlc(struct maclc_dovi_params *dst,
                                              const vlc_video_dovi_metadata_t *src)
{
    memset(dst, 0, sizeof(*dst));
    if (src == NULL)
        return;

    /* Input offset for neutral value */
    memcpy(dst->nonlinear_offset, src->nonlinear_offset, sizeof(dst->nonlinear_offset));

    /* Nonlinear (before PQ) transformation matrix */
    bool nl_non_zero = false;
    for (int i = 0; i < 9; i++) {
        if (src->nonlinear_matrix[i] != 0.0f) {
            nl_non_zero = true;
            break;
        }
    }
    if (nl_non_zero) {
        memcpy(dst->nonlinear, src->nonlinear_matrix, sizeof(dst->nonlinear));
    } else {
        dst->nonlinear[0] = 1.0f;
        dst->nonlinear[4] = 1.0f;
        dst->nonlinear[8] = 1.0f;
    }

    /*
     * Linear (after PQ) decoding matrix:
     * Dolby Vision RPU linear_matrix defines the transformation applied after PQ.
     * The linear LMS signal is mapped to BT.2020 RGB via kMacLCDoviLms2Rgb.
     * In libplacebo (src/shaders/colorspace.c):
     *   pl_matrix3x3_mul(&dovi_lms2rgb, &repr->dovi->linear);
     */
    bool lin_non_zero = false;
    for (int i = 0; i < 9; i++) {
        if (src->linear_matrix[i] != 0.0f) {
            lin_non_zero = true;
            break;
        }
    }
    if (lin_non_zero) {
        maclc_dovi_mat3_mul(dst->linear, kMacLCDoviLms2Rgb, src->linear_matrix);
    } else {
        memcpy(dst->linear, kMacLCDoviLms2Rgb, sizeof(dst->linear));
    }

    /* Reshaping curves for components 0 (Y), 1 (Cb), 2 (Cr) */
    const float bl_scale = (src->bl_bit_depth > 0)
        ? (1.0f / (float)((1 << src->bl_bit_depth) - 1))
        : (1.0f / 1023.0f);
    const float coef_scale = (src->coef_log2_denom < 31)
        ? (1.0f / (float)(1 << src->coef_log2_denom))
        : 1.0f;

    for (int c = 0; c < 3; c++) {
        const struct vlc_dovi_reshape_t *csrc = &src->curves[c];
        struct maclc_dovi_comp *cdst = &dst->comp[c];

        cdst->num_pivots = csrc->num_pivots;
        if (cdst->num_pivots > 9)
            cdst->num_pivots = 9;

        for (int i = 0; i < (int)cdst->num_pivots; i++) {
            cdst->pivots[i] = bl_scale * (float)csrc->pivots[i];
        }

        for (int i = 0; i < (int)cdst->num_pivots - 1; i++) {
            struct maclc_dovi_piece *p = &cdst->pieces[i];
            p->method = (uint32_t)csrc->mapping_idc[i];
            switch (csrc->mapping_idc[i]) {
            case VLC_DOVI_RESHAPE_POLYNOMIAL:
                for (int k = 0; k < 3; k++) {
                    p->poly_coef[k] = (k <= (int)csrc->poly_order[i])
                        ? (coef_scale * (float)csrc->poly_coef[i][k])
                        : 0.0f;
                }
                break;
            case VLC_DOVI_RESHAPE_MMR:
                p->mmr_order = csrc->mmr_order[i];
                p->mmr_constant = coef_scale * (float)csrc->mmr_constant[i];
                for (int j = 0; j < (int)csrc->mmr_order[i] && j < 3; j++) {
                    for (int k = 0; k < 7; k++) {
                        p->mmr_coef[j][k] = coef_scale * (float)csrc->mmr_coef[i][j][k];
                    }
                }
                break;
            }
        }
    }

    /* Source scene brightness in normalised PQ and cd/m² */
    const float pq_scale = 1.0f / 4095.0f;
    dst->source_min_pq = (float)src->source_min_pq * pq_scale;
    dst->source_max_pq = (float)src->source_max_pq * pq_scale;
    dst->source_min_nits = maclc_dovi_pq_to_nits(dst->source_min_pq);
    dst->source_max_nits = maclc_dovi_pq_to_nits(dst->source_max_pq);
}

/**
 * Pure reference per-pixel Dolby Vision decoding.
 * Line-by-line equivalent of the Metal compute kernel:
 *   1. Reshaping per component (polynomial or MMR, selected by pivot ranges)
 *   2. Nonlinear 3x3 matrix multiplication with input offset subtraction
 *   3. SMPTE ST 2084 PQ EOTF per component (yielding cd/m² in [0, 10000])
 *   4. Linear 3x3 matrix multiplication -> linear BT.2020 RGB in cd/m² (0..10000)
 *
 * @param params              Normalised Dolby Vision parameters
 * @param ycc                 Base-layer samples normalised to [0, 1] full scale
 * @param rgb_linear_nits     Output linear BT.2020 RGB in cd/m² (0..10000)
 */
static inline void maclc_dovi_decode_pixel(const struct maclc_dovi_params *params,
                                          const float ycc[3],
                                          float rgb_linear_nits[3])
{
    /* Step 1: Reshape each component using curves and pivots */
    float sig[3] = {
        fminf(fmaxf(ycc[0], 0.0f), 1.0f),
        fminf(fmaxf(ycc[1], 0.0f), 1.0f),
        fminf(fmaxf(ycc[2], 0.0f), 1.0f),
    };
    float reshaped[3];

    for (int c = 0; c < 3; c++) {
        const struct maclc_dovi_comp *comp = &params->comp[c];
        if (comp->num_pivots < 2) {
            reshaped[c] = sig[c];
            continue;
        }

        float s = sig[c];
        int piece = 0;
        while (piece < (int)comp->num_pivots - 2 && s >= comp->pivots[piece + 1]) {
            piece++;
        }

        const struct maclc_dovi_piece *p = &comp->pieces[piece];
        if (p->method == 0) {
            /* Polynomial: s = c0 + c1*s + c2*s^2 */
            s = (p->poly_coef[2] * s + p->poly_coef[1]) * s + p->poly_coef[0];
        } else {
            /* MMR (Multi-Method / Multiple Regression) */
            s = p->mmr_constant;
            float sigX[4];
            sigX[0] = sig[0] * sig[1];              /* y * u */
            sigX[1] = sig[0] * sig[2];              /* y * v */
            sigX[2] = sig[1] * sig[2];              /* u * v */
            sigX[3] = sigX[0] * sig[2];             /* y * u * v */

            /* Order 1 */
            s += p->mmr_coef[0][0] * sig[0] +
                 p->mmr_coef[0][1] * sig[1] +
                 p->mmr_coef[0][2] * sig[2];
            s += p->mmr_coef[0][3] * sigX[0] +
                 p->mmr_coef[0][4] * sigX[1] +
                 p->mmr_coef[0][5] * sigX[2] +
                 p->mmr_coef[0][6] * sigX[3];

            if (p->mmr_order >= 2) {
                float sig2[3] = { sig[0] * sig[0], sig[1] * sig[1], sig[2] * sig[2] };
                float sigX2[4] = { sigX[0] * sigX[0], sigX[1] * sigX[1], sigX[2] * sigX[2], sigX[3] * sigX[3] };
                s += p->mmr_coef[1][0] * sig2[0] +
                     p->mmr_coef[1][1] * sig2[1] +
                     p->mmr_coef[1][2] * sig2[2];
                s += p->mmr_coef[1][3] * sigX2[0] +
                     p->mmr_coef[1][4] * sigX2[1] +
                     p->mmr_coef[1][5] * sigX2[2] +
                     p->mmr_coef[1][6] * sigX2[3];

                if (p->mmr_order >= 3) {
                    s += p->mmr_coef[2][0] * (sig2[0] * sig[0]) +
                         p->mmr_coef[2][1] * (sig2[1] * sig[1]) +
                         p->mmr_coef[2][2] * (sig2[2] * sig[2]);
                    s += p->mmr_coef[2][3] * (sigX2[0] * sigX[0]) +
                         p->mmr_coef[2][4] * (sigX2[1] * sigX[1]) +
                         p->mmr_coef[2][5] * (sigX2[2] * sigX[2]) +
                         p->mmr_coef[2][6] * (sigX2[3] * sigX[3]);
                }
            }
        }

        /* Clamping: between first and last pivot */
        float lo = comp->pivots[0];
        float hi = comp->pivots[comp->num_pivots - 1];
        reshaped[c] = fminf(fmaxf(s, lo), hi);
    }

    /* Step 2: Nonlinear matrix with input offset subtraction */
    float v[3] = {
        reshaped[0] - params->nonlinear_offset[0],
        reshaped[1] - params->nonlinear_offset[1],
        reshaped[2] - params->nonlinear_offset[2],
    };

    float nonlin_rgb[3];
    for (int i = 0; i < 3; i++) {
        nonlin_rgb[i] = params->nonlinear[i * 3 + 0] * v[0] +
                        params->nonlinear[i * 3 + 1] * v[1] +
                        params->nonlinear[i * 3 + 2] * v[2];
    }

    /* Step 3: PQ EOTF per component (outputs optical cd/m² in [0, 10000]) */
    float pq_nits[3];
    pq_nits[0] = maclc_dovi_pq_to_nits(nonlin_rgb[0]);
    pq_nits[1] = maclc_dovi_pq_to_nits(nonlin_rgb[1]);
    pq_nits[2] = maclc_dovi_pq_to_nits(nonlin_rgb[2]);

    /* Step 4: Linear matrix -> linear BT.2020 RGB in cd/m² (0..10000) */
    for (int i = 0; i < 3; i++) {
        float val = params->linear[i * 3 + 0] * pq_nits[0] +
                    params->linear[i * 3 + 1] * pq_nits[1] +
                    params->linear[i * 3 + 2] * pq_nits[2];
        rgb_linear_nits[i] = fmaxf(val, 0.0f);
    }
}

#endif /* MACLC_DOVI_H */
