/*****************************************************************************
 * dtsx.c: DTS:X decoder (LibDTSX + 7.1 render)
 *****************************************************************************
 * Renders standard DTS:X presentations (7.1 bed + 4 fixed heights) to a 7.1
 * bed by folding heights at -3 dB. LibDTSX refuses alternate/object
 * presentations; in that case (and for plain DTS-HD without an X extension)
 * the decoder requests a reload so VLC falls back to avcodec automatically.
 * It scores above avcodec but below the S/PDIF passthrough decoder.
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

#include <vlc_common.h>
#include <vlc_plugin.h>
#include <vlc_codec.h>
#include <vlc_aout.h>

#include <string.h>

#include "dtsx.h"
#include "dtsx_render.h"

static int  OpenDecoder(vlc_object_t *);
static void CloseDecoder(vlc_object_t *);

vlc_module_begin()
    set_shortname("dtsx")
    set_description(N_("DTS:X decoder (standard presentation)"))
    /* Above avcodec (70), below S/PDIF passthrough (120). Unsupported streams
     * trigger a decoder reload with the "dtsx-unsupported" flag set, so the
     * next Open() declines and avcodec is selected instead. */
    set_capability("audio decoder", 80)
    set_callbacks(OpenDecoder, CloseDecoder)
    set_subcategory(SUBCAT_INPUT_ACODEC)
vlc_module_end()

typedef struct
{
    DTSXDecoder *handle;
    date_t end_date;
    bool have_date;
    bool dead;
    bool forced; /* --codec dtsx: do not reload, report the error instead */
} decoder_sys_t;

#define DTSX_UNSUPPORTED_VAR "dtsx-unsupported"

static int
DecodeBlock(decoder_t *dec, block_t *block)
{
    decoder_sys_t *sys = dec->p_sys;
    bool refuse = false;

    if (block == NULL) /* drain */
        goto drain;

    if (sys->dead)
    {
        block_Release(block);
        return VLCDEC_SUCCESS;
    }

    if (decoder_UpdateAudioFormat(dec))
    {
        block_Release(block);
        return VLCDEC_SUCCESS;
    }

    if (block->i_flags & (BLOCK_FLAG_CORRUPTED | BLOCK_FLAG_DISCONTINUITY))
        dtsx_decoder_reset(sys->handle);

    if (block->i_pts != VLC_TICK_INVALID)
    {
        date_Set(&sys->end_date, block->i_pts);
        sys->have_date = true;
    }

    if (sys->have_date)
    {
        DTSXStatus status = dtsx_decoder_push(sys->handle, block->p_buffer,
                                              block->i_buffer, block->i_pts);
        if (status == DTSX_ERR_UNSUPPORTED || status == DTSX_ERR_NOT_DTSX)
        {
            msg_Warn(dec, "DTS:X stream not supported by LibDTSX: %s",
                     dtsx_decoder_last_error(sys->handle));
            refuse = true;
        }
        else if (status != DTSX_OK && status != DTSX_ERR_BUFFER_FULL)
        {
            msg_Warn(dec, "LibDTSX push failed: %s",
                     dtsx_decoder_last_error(sys->handle));
        }
    }

drain:
    for (;;)
    {
        DTSXBlock out;
        DTSXStatus status = dtsx_decoder_pull(sys->handle, &out);
        if (status == DTSX_NEED_MORE_DATA)
            break;
        if (status == DTSX_ERR_UNSUPPORTED || status == DTSX_ERR_NOT_DTSX)
        {
            msg_Warn(dec, "DTS:X stream not supported by LibDTSX: %s",
                     dtsx_decoder_last_error(sys->handle));
            refuse = true;
            break;
        }
        if (status != DTSX_OK)
        {
            if (!refuse)
                msg_Dbg(dec, "LibDTSX pull: %s", dtsx_decoder_last_error(sys->handle));
            break;
        }

        unsigned samples = out.frame_count;
        if (samples == 0)
            continue;

        if (dec->fmt_out.audio.i_rate != out.sample_rate && out.sample_rate != 0)
        {
            dec->fmt_out.audio.i_rate = out.sample_rate;
            date_Change(&sys->end_date, out.sample_rate, 1);
            if (decoder_UpdateAudioFormat(dec))
                continue;
        }

        block_t *pcm = decoder_NewAudioBuffer(dec, samples);
        if (pcm == NULL)
            continue;
        memset(pcm->p_buffer, 0, pcm->i_buffer);

        dtsx_render_block_71(&out, (float *) pcm->p_buffer);
        if (sys->have_date)
        {
            pcm->i_pts = date_Get(&sys->end_date);
            date_Increment(&sys->end_date, samples);
            pcm->i_length = date_Get(&sys->end_date) - pcm->i_pts;
        }
        decoder_QueueAudio(dec, pcm);
    }

    if (refuse && !sys->forced)
    {
        var_SetBool(dec, DTSX_UNSUPPORTED_VAR, true);
        msg_Warn(dec, "reloading with a different DTS decoder");
        return VLCDEC_RELOAD; /* frame ownership stays with the core */
    }
    if (refuse)
        sys->dead = true; /* explicit --codec dtsx: keep the error local */
    if (block != NULL)
        block_Release(block);

    return VLCDEC_SUCCESS;
}

static void
FlushDecoder(decoder_t *dec)
{
    decoder_sys_t *sys = dec->p_sys;
    dtsx_decoder_reset(sys->handle);
    sys->have_date = false;
}

static int
OpenDecoder(vlc_object_t *obj)
{
    decoder_t *dec = (decoder_t *) obj;

    if (dec->fmt_in->i_codec != VLC_CODEC_DTS)
        return VLC_EGENERIC;

    /* A previous instance of this decoder refused the stream (no X extension,
     * or an unsupported presentation). On reload, decline so the next module
     * (avcodec) is selected instead of looping back here. */
    if (var_Create(obj, DTSX_UNSUPPORTED_VAR, VLC_VAR_BOOL) != VLC_SUCCESS)
        return VLC_EGENERIC;
    if (var_GetBool(obj, DTSX_UNSUPPORTED_VAR))
        return VLC_EGENERIC;

    /* DTS:X is carried in a DTS-HD extension (profile 1). A plain DTS core
     * or DTS Express cannot carry it; do not probe those at all unless the
     * user explicitly forced this decoder. */
    if (!dec->obj.force && dec->fmt_in->i_profile >= 0
     && dec->fmt_in->i_profile != 1)
        return VLC_EGENERIC;

    DTSXDecoder *handle = dtsx_decoder_create();
    if (handle == NULL)
        return VLC_EGENERIC;

    decoder_sys_t *sys = malloc(sizeof(*sys));
    if (sys == NULL)
    {
        dtsx_decoder_destroy(handle);
        return VLC_ENOMEM;
    }
    sys->handle = handle;
    sys->have_date = false;
    sys->dead = false;
    sys->forced = dec->obj.force;
    date_Init(&sys->end_date, 48000, 1);

    dec->fmt_out.i_codec = VLC_CODEC_FL32;
    dec->fmt_out.audio.i_format = VLC_CODEC_FL32;
    dec->fmt_out.audio.i_rate = 48000;
    dec->fmt_out.audio.i_physical_channels = AOUT_CHANS_7_1;
    dec->fmt_out.audio.channel_type = AUDIO_CHANNEL_TYPE_BITMAP;
    dec->fmt_out.audio.i_chan_mode = 0;
    dec->fmt_out.audio.i_bitspersample = 32;
    aout_FormatPrepare(&dec->fmt_out.audio);

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

    dtsx_decoder_destroy(sys->handle);
    free(sys);
}