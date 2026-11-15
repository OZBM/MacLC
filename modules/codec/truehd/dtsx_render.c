/*****************************************************************************
 * dtsx_render.c: render a DTS:X standard presentation to a 7.1 bed
 *****************************************************************************
 * This is a proof of concept, not built into MacLC yet. LibDTSX refuses
 * alternate DTS:X presentations (the ones with objects), and a decoder module
 * that selects itself for every DTS-HD MA track would leave those silent. A
 * safe fallback to VLC's own DTS decoder is needed first. To build the
 * proof of concept, link DTSX.framework and compile this file with
 * dtsx_render_test.c.
 *
 * Copyright (C) 2026 VLC authors, VideoLAN and VideoLABS
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

#include "dtsx_render.h"

#include <math.h>
#include <string.h>

/* The standard DTS:X presentation: the 7.1 bed in DTS order, then the four
 * fixed heights. The bed has the standard -3 dB height fold removed, so the
 * heights are added back at the same gain when they are folded into a 7.1
 * bed; this keeps the level of a plain 7.1 downmix. */
#define DTSX_HEIGHT_FOLD_GAIN 0.70710678f

static int
dtsx_bed_channel(uint8_t speaker)
{
    switch (speaker)
    {
        case DTSX_SPEAKER_L:   return 0;
        case DTSX_SPEAKER_R:   return 1;
        case DTSX_SPEAKER_LS:  return 2;
        case DTSX_SPEAKER_RS:  return 3;
        case DTSX_SPEAKER_LB:  return 4;
        case DTSX_SPEAKER_RB:  return 5;
        case DTSX_SPEAKER_C:   return 6;
        case DTSX_SPEAKER_LFE: return 7;
        default:               return -1;
    }
}

static bool
dtsx_height_position(uint8_t speaker, float *x, float *y)
{
    switch (speaker)
    {
        case DTSX_SPEAKER_TFL: *x = 0.25f; *y = 0.25f; return true;
        case DTSX_SPEAKER_TFR: *x = 0.75f; *y = 0.25f; return true;
        case DTSX_SPEAKER_TBL: *x = 0.25f; *y = 0.75f; return true;
        case DTSX_SPEAKER_TBR: *x = 0.75f; *y = 0.75f; return true;
        default:               return false;
    }
}

unsigned
dtsx_render_block_71(const DTSXBlock *block, float *out)
{
    if (block == NULL || out == NULL || block->channels == NULL
     || block->frame_count == 0)
        return 0;

    const unsigned frames = block->frame_count;
    memset(out, 0, sizeof(float) * frames * ATMOS_BED_CHANNELS_71);

    for (uint32_t ch = 0; ch < block->channel_count; ++ch)
    {
        const float *plane = block->channels[ch];
        if (plane == NULL)
            continue;

        const int bed_ch = dtsx_bed_channel(block->speakers[ch]);
        if (bed_ch >= 0)
        {
            for (unsigned f = 0; f < frames; ++f)
                out[f * ATMOS_BED_CHANNELS_71 + bed_ch] += plane[f];
            continue;
        }

        float x, y;
        if (!dtsx_height_position(block->speakers[ch], &x, &y))
            continue;

        float gains[ATMOS_BED_CHANNELS_71];
        atmos_pan_71(x, y, gains);
        for (unsigned f = 0; f < frames; ++f)
        {
            const float sample = plane[f] * DTSX_HEIGHT_FOLD_GAIN;
            for (unsigned out_ch = 0; out_ch < ATMOS_BED_CHANNELS_71; ++out_ch)
                if (gains[out_ch] > 0.0f)
                    out[f * ATMOS_BED_CHANNELS_71 + out_ch] +=
                        sample * gains[out_ch];
        }
    }

    return frames;
}