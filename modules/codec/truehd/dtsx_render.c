/*****************************************************************************
 * dtsx_render.c: render a DTS:X standard presentation to a 7.1 bed
 *****************************************************************************
 * Renders the standard DTS:X presentation (7.1 bed plus four fixed heights)
 * to a 7.1 FL32 bed for the Apple spatial-audio output. Heights are folded
 * back into the bed speaker LibDTSX removed them from. Used by dtsx.c.
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

/* LibDTSX removes each fixed height from exactly one bed speaker at -3 dB.
 * Fold it back into that same speaker to reproduce the compatible 7.1 mix. */
static int
dtsx_height_bed_channel(uint8_t speaker)
{
    switch (speaker)
    {
        case DTSX_SPEAKER_TFL: return 0; /* L  */
        case DTSX_SPEAKER_TFR: return 1; /* R  */
        case DTSX_SPEAKER_TBL: return 4; /* Lb */
        case DTSX_SPEAKER_TBR: return 5; /* Rb */
        default:               return -1;
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

        const int height_ch = dtsx_height_bed_channel(block->speakers[ch]);
        if (height_ch < 0)
            continue;

        for (unsigned f = 0; f < frames; ++f)
            out[f * ATMOS_BED_CHANNELS_71 + height_ch] +=
                plane[f] * DTSX_HEIGHT_FOLD_GAIN;
    }

    return frames;
}