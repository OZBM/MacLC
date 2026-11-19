/*****************************************************************************
 * eac3_dec3.c: E-AC-3 header parsing and dec3 magic cookie generation
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
 * The dec3 box layout and the channel-map mapping follow FFmpeg's movenc.c
 * (LGPL-2.1+).
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin Street, Fifth Floor, Boston MA 02110-1301, USA.
 *****************************************************************************/

#ifdef HAVE_CONFIG_H
# include "config.h"
#endif

#include "eac3_dec3.h"

#include <string.h>

typedef struct
{
    const uint8_t *data;
    size_t size;
    size_t bit;
    int error;
} eac3_bs_t;

static void
eac3_bs_init(eac3_bs_t *bs, const uint8_t *data, size_t size)
{
    bs->data = data;
    bs->size = size;
    bs->bit = 0;
    bs->error = 0;
}

static unsigned
eac3_bs_read(eac3_bs_t *bs, unsigned count)
{
    unsigned value = 0;

    for (unsigned i = 0; i < count; ++i)
    {
        size_t byte = bs->bit >> 3;
        if (byte >= bs->size)
        {
            bs->error = 1;
            return 0;
        }

        value = (value << 1)
              | ((bs->data[byte] >> (7 - (bs->bit & 7))) & 1);
        ++bs->bit;
    }

    return value;
}

static void
eac3_bs_skip(eac3_bs_t *bs, unsigned count)
{
    if (bs->bit + count > bs->size * 8)
    {
        bs->error = 1;
        bs->bit = bs->size * 8;
        return;
    }
    bs->bit += count;
}

bool
eac3_ParseFrame(const uint8_t *data, size_t size, eac3_info_t *info)
{
    if (data == NULL || size < 7)
        return false;

    memset(info, 0, sizeof(*info));
    eac3_bs_t bs;
    eac3_bs_init(&bs, data, size);

    if (eac3_bs_read(&bs, 16) != 0x0B77)
        return false;

    /* The bitstream identification sits at bit 40 in both AC-3 and E-AC-3
     * headers; a value of 10 or less marks a plain AC-3 frame. E-AC-3
     * streams used for 7.1 material carry an AC-3 core as their independent
     * substream, followed by dependent E-AC-3 frames. */
    eac3_bs_t probe = bs;
    eac3_bs_skip(&probe, 24);
    const unsigned probe_bsid = eac3_bs_read(&probe, 5);

    if (probe_bsid <= 10)
    {
        eac3_bs_t b;
        eac3_bs_init(&b, data, size);
        eac3_bs_skip(&b, 16); /* sync */
        eac3_bs_skip(&b, 16); /* crc1 */

        const unsigned fscod = eac3_bs_read(&b, 2);
        const unsigned frmsizcod = eac3_bs_read(&b, 6);
        const unsigned bsid = eac3_bs_read(&b, 5);
        const unsigned bsmod = eac3_bs_read(&b, 3);
        const unsigned acmod = eac3_bs_read(&b, 3);
        if (fscod == 3 || frmsizcod >= 38)
            return false;

        if ((acmod & 1) && acmod != 1)
            eac3_bs_skip(&b, 2); /* cmixlev */
        if (acmod & 4)
            eac3_bs_skip(&b, 2); /* surmixlev */
        if (acmod == 2)
            eac3_bs_skip(&b, 2); /* dsurmod */
        const unsigned lfeon = eac3_bs_read(&b, 1);
        if (b.error)
            return false;

        static const uint16_t ac3_frame_words[38][3] = {
            {  96,  69,  64 }, {  96,  70,  64 },
            { 120,  87,  80 }, { 120,  88,  80 },
            { 144, 104,  96 }, { 144, 105,  96 },
            { 168, 121, 112 }, { 168, 122, 112 },
            { 192, 139, 128 }, { 192, 140, 128 },
            { 240, 174, 160 }, { 240, 175, 160 },
            { 288, 208, 192 }, { 288, 209, 192 },
            { 336, 243, 224 }, { 336, 244, 224 },
            { 384, 278, 256 }, { 384, 279, 256 },
            { 480, 348, 320 }, { 480, 349, 320 },
            { 576, 417, 384 }, { 576, 418, 384 },
            { 672, 487, 448 }, { 672, 488, 448 },
            { 768, 557, 512 }, { 768, 558, 512 },
            { 960, 696, 640 }, { 960, 697, 640 },
            { 1152, 835, 768 }, { 1152, 836, 768 },
            { 1344, 975, 896 }, { 1344, 976, 896 },
            { 1536, 1114, 1024 }, { 1536, 1115, 1024 },
            { 1728, 1253, 1152 }, { 1728, 1254, 1152 },
            { 1920, 1393, 1280 }, { 1920, 1394, 1280 },
        };
        static const unsigned rates[] = { 48000, 44100, 32000 };

        info->is_ac3 = true;
        /* AC-3 bsid 9/10 halves/quarters the sample rate (ETSI TS 102 366). */
        info->rate = rates[fscod] >> (bsid > 8 ? bsid - 8 : 0);
        info->channels = (acmod == 0 || acmod == 2 ? 2u :
                          acmod == 1 ? 1u :
                          acmod == 3 || acmod == 4 ? 3u :
                          acmod == 5 || acmod == 6 ? 4u : 5u)
                     + (lfeon ? 1u : 0u);
        info->frames_per_packet = 1536;
        info->fscod = fscod;
        info->bsid = bsid;
        info->bsmod = bsmod;
        info->acmod = acmod;
        info->lfeon = lfeon;
        info->frame_size = ac3_frame_words[frmsizcod][2 - fscod] * 2;
        return true;
    }

    const unsigned strmtyp = eac3_bs_read(&bs, 2);
    const unsigned substreamid = eac3_bs_read(&bs, 3);
    const unsigned frmsiz = eac3_bs_read(&bs, 11);
    const unsigned fscod = eac3_bs_read(&bs, 2);

    unsigned fscod2 = 0;
    unsigned numblkscod;
    if (fscod == 3)
    {
        fscod2 = eac3_bs_read(&bs, 2);
        numblkscod = 3;
    }
    else
        numblkscod = eac3_bs_read(&bs, 2);

    const unsigned acmod = eac3_bs_read(&bs, 3);
    const unsigned lfeon = eac3_bs_read(&bs, 1);
    const unsigned bsid = eac3_bs_read(&bs, 5);
    if (bsid <= 10) /* plain AC-3, no dec3 */
        return false;

    (void) eac3_bs_read(&bs, 5); /* dialnorm */
    if (eac3_bs_read(&bs, 1))    /* compre */
        eac3_bs_skip(&bs, 8);

    if (acmod == 0)
    {
        (void) eac3_bs_read(&bs, 5); /* dialnorm2 */
        if (eac3_bs_read(&bs, 1))    /* compr2e */
            eac3_bs_skip(&bs, 8);
    }

    unsigned chanmap = 0;
    bool has_chanmap = false;
    if (strmtyp == 1 && eac3_bs_read(&bs, 1)) /* chanmape */
    {
        chanmap = eac3_bs_read(&bs, 16);
        has_chanmap = true;
    }

    /* Mixing metadata (TS 102 366 E.1.3.1), parsed only to reach the
     * additional bitstream information. */
    if (eac3_bs_read(&bs, 1)) /* mixmdate */
    {
        if (acmod > 2)
        {
            (void) eac3_bs_read(&bs, 2); /* dmixmod */
            if (acmod & 1)
                eac3_bs_skip(&bs, 6); /* ltrtcmixlev + cmixlev */
            if (acmod & 4)
                eac3_bs_skip(&bs, 6); /* lorocmixlev + lrttsurcmixlev */
        }

        if (lfeon && eac3_bs_read(&bs, 1))
            (void) eac3_bs_read(&bs, 5); /* lfemixlevcod */

        if (strmtyp == 0)
        {
            const unsigned programs = acmod ? 1u : 2u;
            for (unsigned i = 0; i < programs; ++i)
                if (eac3_bs_read(&bs, 1))
                    eac3_bs_skip(&bs, 6); /* pgmscl */

            if (eac3_bs_read(&bs, 1))
                eac3_bs_skip(&bs, 6); /* extpgmscl */

            switch (eac3_bs_read(&bs, 2)) /* mixdef */
            {
                case 1:
                    eac3_bs_skip(&bs, 5); /* premixcmpsel, drcsrc, premixcmpscl */
                    break;
                case 2:
                    eac3_bs_skip(&bs, 12); /* mixdata */
                    break;
                case 3:
                    eac3_bs_skip(&bs, (eac3_bs_read(&bs, 5) + 2) * 8);
                    break;
                default:
                    break;
            }

            if (acmod < 2)
            {
                for (unsigned i = 0; i < programs; ++i)
                    if (eac3_bs_read(&bs, 1))
                        eac3_bs_skip(&bs, 14); /* panmean + paninfo */
            }

            if (eac3_bs_read(&bs, 1)) /* frmmixcfginfoe */
            {
                const unsigned num_blocks = numblkscod == 0 ? 1u :
                                            numblkscod == 1 ? 2u :
                                            numblkscod == 2 ? 3u : 6u;
                for (unsigned i = 0; i < num_blocks; ++i)
                    if (num_blocks == 1 || eac3_bs_read(&bs, 1))
                        eac3_bs_skip(&bs, 5); /* blkmixcfginfo */
            }
        }
    }

    unsigned bsmod = 0;
    if (eac3_bs_read(&bs, 1)) /* infomdate */
    {
        bsmod = eac3_bs_read(&bs, 3);
        eac3_bs_skip(&bs, 2); /* copyrightb, origbs */

        if (acmod == 2)
            eac3_bs_skip(&bs, 4); /* dsurmod, dheadphonmod */
        if (acmod >= 6)
            eac3_bs_skip(&bs, 2); /* dsurexmod */

        const unsigned programs = acmod ? 1u : 2u;
        for (unsigned i = 0; i < programs; ++i)
            if (eac3_bs_read(&bs, 1))
                eac3_bs_skip(&bs, 8); /* mixlevel, roomtyp, adconvtyp */

        if (fscod != 3)
            eac3_bs_skip(&bs, 1); /* sourcefscod */
    }

    if (strmtyp == 0 && numblkscod != 3)
        eac3_bs_skip(&bs, 1); /* convsync */

    if (strmtyp == 2)
    {
        if (numblkscod == 3)
            eac3_bs_skip(&bs, 6); /* frmsizecod */
        else if (eac3_bs_read(&bs, 1))
            eac3_bs_skip(&bs, 6);
    }

    /* Additional bitstream information (TS 103 420 8.3). The first byte's
     * least significant bit is flag_ec3_extension_type_a; the next byte is
     * complexity_index_type_a. This is what Apple reads as 'ec+3'. */
    if (eac3_bs_read(&bs, 1)) /* addbsie */
    {
        const unsigned addbsil = eac3_bs_read(&bs, 6);
        for (unsigned i = 0; i <= addbsil; ++i)
        {
            if (i == 0)
            {
                eac3_bs_skip(&bs, 7);
                if (eac3_bs_read(&bs, 1)) /* flag_ec3_extension_type_a */
                {
                    info->carries_joc = true;
                    info->complexity_index = eac3_bs_read(&bs, 8);
                    ++i;
                }
            }
            else
                eac3_bs_skip(&bs, 8);
        }
    }

    if (bs.error)
        return false;

    static const unsigned rates[] = { 48000, 44100, 32000 };
    unsigned rate;
    if (fscod == 3)
    {
        if (fscod2 >= 3)
            return false;
        rate = rates[fscod2] / 2;
    }
    else
        rate = rates[fscod];

    static const unsigned blocks[] = { 1, 2, 3, 6 };
    const unsigned num_blocks = blocks[numblkscod];
    const unsigned frame_size = 2 * (frmsiz + 1);
    unsigned channels;
    switch (acmod)
    {
        case 1: channels = 1; break;
        case 2: case 0: channels = 2; break;
        case 3: case 4: channels = 3; break;
        case 5: case 6: channels = 4; break;
        default: channels = 5; break;
    }
    if (lfeon)
        ++channels;

    info->rate = rate;
    info->channels = channels;
    info->frames_per_packet = num_blocks * 256;
    info->bitrate = 8 * frame_size * rate / info->frames_per_packet;
    info->fscod = fscod;
    info->strmtyp = strmtyp;
    info->has_chanmap = has_chanmap;
    info->bsid = bsid;
    info->bsmod = bsmod;
    info->acmod = acmod;
    info->lfeon = lfeon;
    info->frame_size = frame_size;
    info->chan_loc = (uint16_t) chanmap; /* overwritten by the caller when needed */
    (void) substreamid;
    return true;
}

typedef struct
{
    uint8_t bytes[64];
    size_t count; /* in bits */
} eac3_bw_t;

static void
eac3_bw_write(eac3_bw_t *bw, unsigned value, unsigned bits)
{
    for (int shift = (int) bits - 1; shift >= 0; --shift)
    {
        if (bw->count % 8 == 0)
            bw->bytes[bw->count / 8] = 0;
        bw->bytes[bw->count / 8] |=
            ((value >> shift) & 1u) << (7 - (bw->count % 8));
        ++bw->count;
    }
}

size_t
eac3_BuildDec3(const eac3_info_t *info, unsigned int bitrate,
               uint8_t *out, size_t out_size)
{
    if (info == NULL || out == NULL || out_size < 12)
        return 0;

    unsigned data_rate = bitrate ? (bitrate + 500u) / 1000u : 0;
    if (data_rate == 0)
        data_rate = 8 * info->frame_size * info->rate /
                    (info->frames_per_packet ? info->frames_per_packet : 1)
                    / 1000;
    if (data_rate > 8191)
        data_rate = 8191;

    eac3_bw_t bw = { .count = 0 };
    eac3_bw_write(&bw, data_rate, 13);
    eac3_bw_write(&bw, 0, 3); /* num_ind_sub: one independent substream */
    eac3_bw_write(&bw, info->fscod, 2);
    eac3_bw_write(&bw, info->bsid, 5);
    eac3_bw_write(&bw, 0, 1); /* reserved */
    eac3_bw_write(&bw, 0, 1); /* asvc */
    eac3_bw_write(&bw, info->bsmod, 3);
    eac3_bw_write(&bw, info->acmod, 3);
    eac3_bw_write(&bw, info->lfeon, 1);
    eac3_bw_write(&bw, 0, 3); /* reserved */
    eac3_bw_write(&bw, info->num_dep_sub, 4);
    if (info->num_dep_sub)
        eac3_bw_write(&bw, info->chan_loc, 9);
    else
        eac3_bw_write(&bw, 0, 1); /* reserved */

    if (info->carries_joc)
    {
        eac3_bw_write(&bw, 0, 7); /* reserved */
        eac3_bw_write(&bw, 1, 1); /* flag_eac3_extension_type_a */
        eac3_bw_write(&bw, info->complexity_index, 8);
    }

    const size_t payload_size = (bw.count + 7) / 8;
    const size_t box_size = 8 + payload_size;
    if (box_size > out_size)
        return 0;

    out[0] = (uint8_t) (box_size >> 24);
    out[1] = (uint8_t) (box_size >> 16);
    out[2] = (uint8_t) (box_size >> 8);
    out[3] = (uint8_t) box_size;
    memcpy(out + 4, "dec3", 4);
    memcpy(out + 8, bw.bytes, payload_size);
    return box_size;
}
