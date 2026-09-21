// SPDX-License-Identifier: LGPL-2.1-or-later
/*****************************************************************************
 * maclc_frc_geometry.c
 *****************************************************************************
 * Copyright © 2026 Hazen Studio
 *****************************************************************************/

#ifdef HAVE_CONFIG_H
# include "config.h"
#endif

#include "maclc_frc_geometry.h"

unsigned maclc_frc_factor(unsigned source_fps, unsigned target_fps,
                          unsigned limit)
{
    if (source_fps == 0 || target_fps == 0 || limit < 2)
        return 1;

    const unsigned factor = target_fps / source_fps;
    if (factor < 2)
        return 1;
    return factor > limit ? limit : factor;
}

void maclc_frc_interleave_chroma(uint8_t *dst, size_t dst_stride,
                                 const uint8_t *cb, size_t cb_stride,
                                 const uint8_t *cr, size_t cr_stride,
                                 size_t width, size_t height)
{
    for (size_t y = 0; y < height; y++)
    {
        uint8_t *out = dst + y * dst_stride;
        const uint8_t *blue = cb + y * cb_stride;
        const uint8_t *red = cr + y * cr_stride;
        for (size_t x = 0; x < width; x++)
        {
            out[x * 2] = blue[x];
            out[x * 2 + 1] = red[x];
        }
    }
}

void maclc_frc_deinterleave_chroma(const uint8_t *src, size_t src_stride,
                                   uint8_t *cb, size_t cb_stride,
                                   uint8_t *cr, size_t cr_stride,
                                   size_t width, size_t height)
{
    for (size_t y = 0; y < height; y++)
    {
        const uint8_t *in = src + y * src_stride;
        uint8_t *blue = cb + y * cb_stride;
        uint8_t *red = cr + y * cr_stride;
        for (size_t x = 0; x < width; x++)
        {
            blue[x] = in[x * 2];
            red[x] = in[x * 2 + 1];
        }
    }
}
