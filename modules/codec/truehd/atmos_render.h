/*****************************************************************************
 * atmos_render.h: render a TrueHD Atmos object presentation to a 7.1.4 bed
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

#ifndef VLC_ATMOS_RENDER_H
#define VLC_ATMOS_RENDER_H

#include <stdint.h>
#include "truehd_atmos.h"

/* Channels in the CoreAudio Atmos_7_1_4 order:
 * L R C LFE Ls Rs Lb Rb TFL TFR TBL TBR. */
#define ATMOS_BED_CHANNELS 12

/* Channels in VLC's WG4 order for AOUT_CHANS_7_1:
 * L R Ls Rs Lb Rb C LFE. */
#define ATMOS_BED_CHANNELS_71 8

/**
 * Renders one decoded TrueHD Atmos block to an interleaved float bed.
 *
 * \param block  a block from truehd_atmos_decoder_pull()
 * \param out    frame_count * ATMOS_BED_CHANNELS floats, interleaved in the
 *               CoreAudio Atmos_7_1_4 order
 * \return number of frames written, or 0 when the block cannot be rendered
 */
unsigned
atmos_render_block(const TrueHDAtmosBlock *block, float *out);

/**
 * Renders one decoded TrueHD Atmos block to an interleaved 7.1 bed.
 *
 * Objects with height are folded onto the ear-level plane, so the result is
 * a proper object mix that the existing Apple spatial-audio path can render;
 * it carries no discrete height channels.
 *
 * \param block  a block from truehd_atmos_decoder_pull()
 * \param out    frame_count * ATMOS_BED_CHANNELS_71 floats, interleaved in
 *               VLC's WG4 order (L R Ls Rs Lb Rb C LFE)
 * \return number of frames written, or 0 when the block cannot be rendered
 */
unsigned
atmos_render_block_71(const TrueHDAtmosBlock *block, float *out);

/* Pan a point to the 7.1 WG4-order bed (L R Ls Rs Lb Rb C LFE), folding
 * height onto the ear-level plane. Exposed for the DTS:X renderer. */
void
atmos_pan_71(float x, float y, float gains[ATMOS_BED_CHANNELS_71]);

#endif