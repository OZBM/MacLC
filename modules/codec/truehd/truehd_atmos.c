/*****************************************************************************
 * truehd_atmos.c: Dolby TrueHD Atmos decoder (LibTrueHD + 7.1 object render)
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

#include <string.h>

#include <vlc_common.h>
#include <vlc_plugin.h>
#include <vlc_codec.h>
#include <vlc_aout.h>

#include "truehd_atmos.h"
#include "atmos_render.h"

static int  OpenDecoder(vlc_object_t *);
static void CloseDecoder(vlc_object_t *);

vlc_module_begin()
    set_description(N_("Dolby TrueHD Atmos decoder"))
    set_capability("audio decoder", 130)
    set_callbacks(OpenDecoder, CloseDecoder)
    set_subcategory(SUBCAT_INPUT_ACODEC)
vlc_module_end()

typedef struct
{
    TrueHDAtmosDecoder *handle;
    date_t end_date;
    bool have_date;
    bool forced;
} decoder_sys_t;

#define TRUEHD_ATMOS_UNSUPPORTED_VAR "truehd-atmos-unsupported"

static int
DecodeBlock(decoder_t *dec, block_t *block)
{
    decoder_sys_t *sys = dec->p_sys;
    bool refuse = false;

    if (block == NULL) /* drain */
        goto drain;

    if (decoder_UpdateAudioFormat(dec))
    {
        block_Release(block);
        return VLCDEC_SUCCESS;
    }

    if (block->i_flags & BLOCK_FLAG_CORRUPTED)
    {
        truehd_atmos_decoder_reset(sys->handle);
        sys->have_date = false;
    }
    if (block->i_flags & BLOCK_FLAG_DISCONTINUITY)
    {
        truehd_atmos_decoder_reset(sys->handle);
        sys->have_date = false;
    }

    if (block->i_pts != VLC_TICK_INVALID)
    {
        date_Set(&sys->end_date, block->i_pts);
        sys->have_date = true;
    }

    if (sys->have_date)
    {
        TrueHDAtmosStatus status =
            truehd_atmos_decoder_push(sys->handle, block->p_buffer,
                                      block->i_buffer, block->i_pts);
        if (status != TRUEHD_ATMOS_OK
         && status != TRUEHD_ATMOS_ERR_BUFFER_FULL)
            msg_Warn(dec, "LibTrueHD push failed: %s",
                     truehd_atmos_decoder_last_error(sys->handle));

        /* A plain (non-Atmos) TrueHD stream has no object presentation; this
         * decoder would render silence. Let VLC reload with avcodec instead. */
        TrueHDAtmosStreamInfo info;
        if (truehd_atmos_decoder_get_stream_info(sys->handle, &info) == TRUEHD_ATMOS_OK
         && !info.has_objects)
        {
            msg_Warn(dec, "TrueHD stream has no Atmos objects");
            refuse = true;
        }
    }

drain:
    for (;;)
    {
        TrueHDAtmosBlock out;
        if (refuse)
            break;
        TrueHDAtmosStatus status = truehd_atmos_decoder_pull(sys->handle, &out);
        if (status == TRUEHD_ATMOS_NEED_MORE_DATA)
            break;
        if (status != TRUEHD_ATMOS_OK)
        {
            msg_Warn(dec, "LibTrueHD pull failed: %s",
                     truehd_atmos_decoder_last_error(sys->handle));
            break;
        }

        unsigned samples = out.frame_count;
        if (samples == 0)
            continue;
        if (dec->fmt_out.audio.i_rate != out.sample_rate)
        {
            if (out.sample_rate == 0)
                continue;
            dec->fmt_out.audio.i_rate = out.sample_rate;
            date_Change(&sys->end_date, out.sample_rate, 1);
            if (decoder_UpdateAudioFormat(dec))
                continue;
        }

        block_t *pcm = decoder_NewAudioBuffer(dec, samples);
        if (pcm == NULL)
            continue;
        memset(pcm->p_buffer, 0, pcm->i_buffer);

#ifdef ATMOS_714
        atmos_render_block(&out, (float *) pcm->p_buffer);
#else
        atmos_render_block_71(&out, (float *) pcm->p_buffer);
#endif
        pcm->i_pts = date_Get(&sys->end_date);
        date_Increment(&sys->end_date, samples);
        pcm->i_length = date_Get(&sys->end_date) - pcm->i_pts;
        decoder_QueueAudio(dec, pcm);
    }

    if (refuse && !sys->forced)
    {
        var_SetBool(dec, TRUEHD_ATMOS_UNSUPPORTED_VAR, true);
        msg_Warn(dec, "reloading with a different TrueHD decoder");
        return VLCDEC_RELOAD; /* frame ownership stays with the core */
    }
    if (block != NULL)
        block_Release(block);

    return VLCDEC_SUCCESS;
}

static void
FlushDecoder(decoder_t *dec)
{
    decoder_sys_t *sys = dec->p_sys;
    truehd_atmos_decoder_reset(sys->handle);
    sys->have_date = false;
}

static int
OpenDecoder(vlc_object_t *obj)
{
    decoder_t *dec = (decoder_t *) obj;

    if (dec->fmt_in->i_codec != VLC_CODEC_TRUEHD)
        return VLC_EGENERIC;

    /* On reload after a non-Atmos stream was detected, decline so avcodec is
     * selected instead of looping back here. */
    if (var_Create(obj, TRUEHD_ATMOS_UNSUPPORTED_VAR, VLC_VAR_BOOL) != VLC_SUCCESS)
        return VLC_EGENERIC;
    if (var_GetBool(obj, TRUEHD_ATMOS_UNSUPPORTED_VAR))
        return VLC_EGENERIC;

    TrueHDAtmosDecoder *handle =
        truehd_atmos_decoder_create(TRUEHD_ATMOS_PRESENTATION_HIGHEST);
    if (handle == NULL)
        return VLC_EGENERIC;

    truehd_atmos_decoder_set_bed_companion(handle, true);
    truehd_atmos_decoder_set_ignore_interpolation(handle, true);

    decoder_sys_t *sys = malloc(sizeof(*sys));
    if (sys == NULL)
    {
        truehd_atmos_decoder_destroy(handle);
        return VLC_ENOMEM;
    }
    sys->handle = handle;
    sys->have_date = false;
    sys->forced = dec->obj.force;
    date_Init(&sys->end_date, 48000, 1);

    dec->fmt_out.i_codec = VLC_CODEC_FL32;
    dec->fmt_out.audio.i_format = VLC_CODEC_FL32;
    dec->fmt_out.audio.i_rate = 48000;
#ifdef ATMOS_714
    dec->fmt_out.audio.i_physical_channels = AOUT_CHANS_7_1_4;
#else
    dec->fmt_out.audio.i_physical_channels = AOUT_CHANS_7_1;
#endif
    dec->fmt_out.audio.channel_type = AUDIO_CHANNEL_TYPE_BITMAP;
    dec->fmt_out.audio.i_chan_mode = 0;
    dec->fmt_out.audio.i_bitspersample = 32;
    aout_FormatPrepare(&dec->fmt_out.audio);
#ifdef ATMOS_714
    dec->fmt_out.audio.i_channels = ATMOS_BED_CHANNELS;
    dec->fmt_out.audio.i_bytes_per_frame = ATMOS_BED_CHANNELS * sizeof(float);
    dec->fmt_out.audio.i_frame_length = 1;
#endif

    dec->pf_decode = DecodeBlock;
    dec->pf_flush = FlushDecoder;
    dec->p_sys = sys;
    return VLC_SUCCESS;
}

static void
CloseDecoder(vlc_object_t *obj)
{
    decoder_t *dec = (decoder_t *) obj;
    decoder_sys_t *sys = dec->p_sys;

    truehd_atmos_decoder_destroy(sys->handle);
    free(sys);
}