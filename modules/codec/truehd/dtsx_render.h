/*****************************************************************************
 * dtsx_render.h: render a DTS:X standard presentation to a 7.1 bed
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

#ifndef VLC_DTSX_RENDER_H
#define VLC_DTSX_RENDER_H

#include <stdbool.h>
#include <stdint.h>
#include "dtsx.h"
#include "atmos_render.h"

/**
 * Renders one decoded DTS:X block to an interleaved 7.1 bed.
 *
 * The 7.1 bed plays directly. The four fixed heights are folded onto the
 * ear-level speakers with the standard -3 dB gain, so the result matches a
 * plain 7.1 downmix in level while keeping the height content.
 *
 * \param block  a block from dtsx_decoder_pull()
 * \param out    frame_count * ATMOS_BED_CHANNELS_71 floats, interleaved in
 *               VLC's WG4 order (L R Ls Rs Lb Rb C LFE)
 * \return number of frames written, or 0 when the block cannot be rendered
 */
unsigned
dtsx_render_block_71(const DTSXBlock *block, float *out);

#endif