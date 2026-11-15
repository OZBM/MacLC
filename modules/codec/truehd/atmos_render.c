/*****************************************************************************
 * atmos_render.c: render a TrueHD Atmos object presentation to a 7.1.4 bed
 *****************************************************************************
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

#include "atmos_render.h"

#include <math.h>
#include <string.h>

#ifndef M_PI
# define M_PI 3.14159265358979323846
#endif

typedef struct
{
    float value;
    int channel;
} atmos_column_t;

typedef struct
{
    float y;
    const atmos_column_t *columns;
    unsigned column_count;
} atmos_row_t;

typedef struct
{
    float z;
    const atmos_row_t *rows;
    unsigned row_count;
} atmos_plane_t;

/* Ear-level speakers, in the CoreAudio Atmos_7_1_4 channel order. */
static const atmos_column_t ear_front[] = {
    { 0.00f, 0 },  /* L */
    { 0.50f, 2 },  /* C */
    { 1.00f, 1 },  /* R */
};
static const atmos_column_t ear_side[] = {
    { 0.00f, 4 },  /* Ls */
    { 1.00f, 5 },  /* Rs */
};
static const atmos_column_t ear_rear[] = {
    { 0.00f, 6 },  /* Lb */
    { 1.00f, 7 },  /* Rb */
};

static const atmos_row_t ear_rows[] = {
    { 0.00f, ear_front, 3 },
    { 0.50f, ear_side, 2 },
    { 1.00f, ear_rear, 2 },
};

/* Ceiling speakers sit a quarter of the room in from each wall (TS 103 448). */
static const atmos_column_t top_front[] = {
    { 0.25f, 8 },  /* TFL */
    { 0.75f, 9 },  /* TFR */
};
static const atmos_column_t top_rear[] = {
    { 0.25f, 10 }, /* TBL */
    { 0.75f, 11 }, /* TBR */
};

static const atmos_row_t top_rows[] = {
    { 0.25f, top_front, 2 },
    { 0.75f, top_rear, 2 },
};

static const atmos_plane_t planes[] = {
    { 0.0f, ear_rows, 3 },
    { 1.0f, top_rows, 2 },
};

static void
balance_columns(const atmos_column_t *columns, unsigned count, float value,
                float gain, float gains[ATMOS_BED_CHANNELS])
{
    if (count == 0)
        return;
    if (count == 1 || value <= columns[0].value)
    {
        gains[columns[0].channel] += gain;
        return;
    }
    if (value >= columns[count - 1].value)
    {
        gains[columns[count - 1].channel] += gain;
        return;
    }

    unsigned upper = 1;
    while (upper < count && columns[upper].value < value)
        ++upper;

    const float lo = columns[upper - 1].value;
    const float hi = columns[upper].value;
    const float t = hi > lo ? (value - lo) / (hi - lo) : 0.0f;
    const float angle = t * (float) (M_PI / 2.0);
    gains[columns[upper - 1].channel] += gain * cosf(angle);
    gains[columns[upper].channel] += gain * sinf(angle);
}

static void
render_row(const atmos_row_t *row, float x, float gain,
           float gains[ATMOS_BED_CHANNELS])
{
    balance_columns(row->columns, row->column_count, x, gain, gains);
}

static void
render_plane(const atmos_plane_t *plane, float y, float x, float gain,
             float gains[ATMOS_BED_CHANNELS])
{
    if (y <= plane->rows[0].y)
    {
        render_row(&plane->rows[0], x, gain, gains);
        return;
    }
    if (y >= plane->rows[plane->row_count - 1].y)
    {
        render_row(&plane->rows[plane->row_count - 1], x, gain, gains);
        return;
    }

    unsigned upper = 1;
    while (upper < plane->row_count && plane->rows[upper].y < y)
        ++upper;

    const float lo = plane->rows[upper - 1].y;
    const float hi = plane->rows[upper].y;
    const float t = (y - lo) / (hi - lo);
    const float angle = t * (float) (M_PI / 2.0);
    render_row(&plane->rows[upper - 1], x, gain * cosf(angle), gains);
    render_row(&plane->rows[upper], x, gain * sinf(angle), gains);
}

/* Dual-balance panning: plane, then row, then column, all constant-power. */
static void
atmos_pan(float x, float y, float z, float gains[ATMOS_BED_CHANNELS])
{
    memset(gains, 0, sizeof(*gains) * ATMOS_BED_CHANNELS);

    if (x < 0.0f) x = 0.0f; else if (x > 1.0f) x = 1.0f;
    if (y < 0.0f) y = 0.0f; else if (y > 1.0f) y = 1.0f;
    if (z < 0.0f) z = 0.0f; else if (z > 1.0f) z = 1.0f;

    const float angle = z * (float) (M_PI / 2.0);
    const float ear_gain = cosf(angle);
    const float top_gain = sinf(angle);

    if (ear_gain > 0.0f)
        render_plane(&planes[0], y, x, ear_gain, gains);
    if (top_gain > 0.0f)
        render_plane(&planes[1], y, x, top_gain, gains);
}

static int
atmos_speaker_channel(uint8_t speaker)
{
    switch (speaker)
    {
        case TRUEHD_ATMOS_SPEAKER_L:   return 0;
        case TRUEHD_ATMOS_SPEAKER_R:   return 1;
        case TRUEHD_ATMOS_SPEAKER_C:   return 2;
        case TRUEHD_ATMOS_SPEAKER_LFE: return 3;
        case TRUEHD_ATMOS_SPEAKER_LS:  return 4;
        case TRUEHD_ATMOS_SPEAKER_RS:  return 5;
        case TRUEHD_ATMOS_SPEAKER_LB:  return 6;
        case TRUEHD_ATMOS_SPEAKER_RB:  return 7;
        case TRUEHD_ATMOS_SPEAKER_TFL: return 8;
        case TRUEHD_ATMOS_SPEAKER_TFR: return 9;
        case TRUEHD_ATMOS_SPEAKER_TBL: return 10;
        case TRUEHD_ATMOS_SPEAKER_TBR: return 11;
        default:                       return -1;
    }
}

/* 7.1 bed, in VLC's WG4 channel order: L R Ls Rs Lb Rb C LFE. */
static const atmos_column_t p71_front[] = {
    { 0.00f, 0 }, /* L */
    { 0.50f, 6 }, /* C */
    { 1.00f, 1 }, /* R */
};
static const atmos_column_t p71_side[] = {
    { 0.00f, 2 }, /* Ls */
    { 1.00f, 3 }, /* Rs */
};
static const atmos_column_t p71_rear[] = {
    { 0.00f, 4 }, /* Lb */
    { 1.00f, 5 }, /* Rb */
};
static const atmos_row_t p71_rows[] = {
    { 0.00f, p71_front, 3 },
    { 0.50f, p71_side, 2 },
    { 1.00f, p71_rear, 2 },
};

/* Heights fold onto the ear-level plane: the 7.1 bed has no ceiling. */
static void
atmos_pan_71_impl(float x, float y, float gains[ATMOS_BED_CHANNELS_71])
{
    memset(gains, 0, sizeof(*gains) * ATMOS_BED_CHANNELS_71);
    if (x < 0.0f) x = 0.0f; else if (x > 1.0f) x = 1.0f;
    if (y < 0.0f) y = 0.0f; else if (y > 1.0f) y = 1.0f;
    render_plane(&(const atmos_plane_t){ 0.0f, p71_rows, 3 }, y, x, 1.0f,
                 gains);
}

void
atmos_pan_71(float x, float y, float gains[ATMOS_BED_CHANNELS_71])
{
    atmos_pan_71_impl(x, y, gains);
}

static int
atmos_speaker_channel_71(uint8_t speaker)
{
    switch (speaker)
    {
        case TRUEHD_ATMOS_SPEAKER_L:   return 0;
        case TRUEHD_ATMOS_SPEAKER_R:   return 1;
        case TRUEHD_ATMOS_SPEAKER_LS:  return 2;
        case TRUEHD_ATMOS_SPEAKER_RS:  return 3;
        case TRUEHD_ATMOS_SPEAKER_LB:  return 4;
        case TRUEHD_ATMOS_SPEAKER_RB:  return 5;
        case TRUEHD_ATMOS_SPEAKER_C:   return 6;
        case TRUEHD_ATMOS_SPEAKER_LFE: return 7;
        case TRUEHD_ATMOS_SPEAKER_TFL:
        case TRUEHD_ATMOS_SPEAKER_TBL: return 2; /* fold left heights */
        case TRUEHD_ATMOS_SPEAKER_TFR:
        case TRUEHD_ATMOS_SPEAKER_TBR: return 3; /* fold right heights */
        default:                       return -1;
    }
}

unsigned
atmos_render_block_71(const TrueHDAtmosBlock *block, float *out)
{
    if (block == NULL || out == NULL || block->channels == NULL
     || block->frame_count == 0)
        return 0;

    const unsigned frames = block->frame_count;
    memset(out, 0, sizeof(float) * frames * ATMOS_BED_CHANNELS_71);

    if (block->bed_channel_count > 0 && block->bed_channels != NULL
     && block->bed_speakers != NULL)
    {
        for (unsigned ch = 0; ch < block->bed_channel_count; ++ch)
        {
            const int out_ch = atmos_speaker_channel_71(block->bed_speakers[ch]);
            if (out_ch < 0)
                continue;
            const float *plane = block->bed_channels[ch];
            for (unsigned f = 0; f < frames; ++f)
                out[f * ATMOS_BED_CHANNELS_71 + out_ch] += plane[f];
        }
    }

    if (block->metadata != NULL)
    {
        const TrueHDAtmosMetadata *meta = block->metadata;
        const unsigned elements = meta->element_count;
        if (elements > block->channel_count)
            return frames;

        for (unsigned el = 0; el < elements; ++el)
        {
            const TrueHDAtmosElement *state = &meta->elements[el];
            if (state->kind != TRUEHD_ATMOS_ELEMENT_OBJECT
             || !(state->flags & TRUEHD_ATMOS_ELEMENT_ACTIVE))
                continue;
            if (state->gain <= 0.0f)
                continue;
            if (el >= block->channel_count || block->channels[el] == NULL)
                continue;

            float gains[ATMOS_BED_CHANNELS_71];
            atmos_pan_71(state->position[0], state->position[1], gains);

            const float *plane = block->channels[el];
            for (unsigned f = 0; f < frames; ++f)
            {
                const float sample = plane[f] * state->gain;
                for (unsigned ch = 0; ch < ATMOS_BED_CHANNELS_71; ++ch)
                    if (gains[ch] > 0.0f)
                        out[f * ATMOS_BED_CHANNELS_71 + ch] +=
                            sample * gains[ch];
            }
        }
    }

    return frames;
}

unsigned
atmos_render_block(const TrueHDAtmosBlock *block, float *out)
{
    if (block == NULL || out == NULL || block->channels == NULL
     || block->frame_count == 0)
        return 0;

    const unsigned frames = block->frame_count;

    memset(out, 0, sizeof(float) * frames * ATMOS_BED_CHANNELS);

    /* The channel-based presentation is Dolby's own 7.1 render of the mix. */
    if (block->bed_channel_count > 0 && block->bed_channels != NULL
     && block->bed_speakers != NULL)
    {
        for (unsigned ch = 0; ch < block->bed_channel_count; ++ch)
        {
            const int out_ch = atmos_speaker_channel(block->bed_speakers[ch]);
            if (out_ch < 0)
                continue;
            const float *plane = block->bed_channels[ch];
            for (unsigned f = 0; f < frames; ++f)
                out[f * ATMOS_BED_CHANNELS + out_ch] += plane[f];
        }
    }

    /* Objects are mixed from their own planes and their latest metadata. */
    if (block->metadata != NULL)
    {
        const TrueHDAtmosMetadata *meta = block->metadata;
        const unsigned elements = meta->element_count;
        if (elements > block->channel_count)
            return frames;

        for (unsigned el = 0; el < elements; ++el)
        {
            const TrueHDAtmosElement *state = &meta->elements[el];
            if (state->kind != TRUEHD_ATMOS_ELEMENT_OBJECT
             || !(state->flags & TRUEHD_ATMOS_ELEMENT_ACTIVE))
                continue;
            if (state->gain <= 0.0f)
                continue;
            if (el >= block->channel_count || block->channels[el] == NULL)
                continue;

            float gains[ATMOS_BED_CHANNELS];
            atmos_pan(state->position[0], state->position[1],
                      state->position[2], gains);

            const float *plane = block->channels[el];
            for (unsigned f = 0; f < frames; ++f)
            {
                const float sample = plane[f] * state->gain;
                for (unsigned ch = 0; ch < ATMOS_BED_CHANNELS; ++ch)
                    if (gains[ch] > 0.0f)
                        out[f * ATMOS_BED_CHANNELS + ch] += sample * gains[ch];
            }
        }
    }

    return frames;
}