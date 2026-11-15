/*****************************************************************************
 * eac3_dec3.h: E-AC-3 header parsing and dec3 magic cookie generation
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

#ifndef VLC_EAC3_DEC3_H
#define VLC_EAC3_DEC3_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

typedef struct
{
    unsigned int rate;              /**< sample rate in Hz */
    unsigned int channels;          /**< channel count, LFE included */
    unsigned int frames_per_packet; /**< audio sample frames per E-AC-3 frame */
    unsigned int bitrate;           /**< bit rate in bit/s */
    unsigned int fscod;             /**< 2-bit sample rate code */
    unsigned int strmtyp;           /**< E-AC-3 frame type (0 independent, 1 dependent) */
    bool has_chanmap;               /**< dependent frame carried a channel map */
    bool is_ac3;                    /**< plain AC-3 frame (E-AC-3 stream core) */
    unsigned int bsid;              /**< bitstream identification */
    unsigned int bsmod;             /**< bitstream mode */
    unsigned int acmod;             /**< audio coding mode (3 bits) */
    unsigned int lfeon;             /**< LFE channel present */
    unsigned int num_dep_sub;       /**< dependent substreams following this frame */
    uint16_t chan_loc;              /**< dependent-frame chanmap, or the dec3 chan_loc */
    bool carries_joc;               /**< flag_ec3_extension_type_a */
    unsigned int complexity_index;  /**< complexity_index_type_a */
    unsigned int frame_size;        /**< size of this E-AC-3 frame in bytes */
} eac3_info_t;

/**
 * Parses the first E-AC-3 frame of a compressed audio block.
 *
 * Only the syncinfo and the additional bitstream information are decoded;
 * the audio payload is not touched. Returns false when the block is not a
 * well-formed E-AC-3 frame (or is plain AC-3, bsid <= 10).
 */
bool
eac3_ParseFrame(const uint8_t *data, size_t size, eac3_info_t *info);

/**
 * Builds the ISOBMFF dec3 box Apple's audio decoder reads as its magic
 * cookie, including the E-AC-3 extension that signals Atmos (ec+3).
 *
 * \param info       first frame as parsed by eac3_ParseFrame()
 * \param bitrate    bit rate in bit/s (0 lets the caller derive it)
 * \param out        destination buffer
 * \param out_size   size of out
 * \return number of bytes written, or 0 when the buffer is too small
 */
size_t
eac3_BuildDec3(const eac3_info_t *info, unsigned int bitrate,
               uint8_t *out, size_t out_size);

#endif