/*****************************************************************************
 * channel_layout.c: Common Channel Layout code for iOS and macOS
 *****************************************************************************
 * Copyright (C) 2024 VLC authors and VideoLAN
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
#include <vlc_aout.h>
#include "channel_layout.h"

#include <stdckdint.h>
#include <CoreAudio/CoreAudioTypes.h>

static AudioChannelLabel
VlcChanToAudioChannelLabel(unsigned chan, bool swap_rear_surround)
{
    switch (chan)
    {
        case AOUT_CHAN_LEFT:
            return kAudioChannelLabel_Left;
        case AOUT_CHAN_RIGHT:
            return kAudioChannelLabel_Right;
        case AOUT_CHAN_CENTER:
            return kAudioChannelLabel_Center;
        case AOUT_CHAN_LFE:
            return kAudioChannelLabel_LFEScreen;
        case AOUT_CHAN_REARLEFT:
            return swap_rear_surround ? kAudioChannelLabel_RearSurroundLeft
                                      : kAudioChannelLabel_LeftSurround;
        case AOUT_CHAN_REARRIGHT:
            return swap_rear_surround ? kAudioChannelLabel_RearSurroundRight
                                      : kAudioChannelLabel_RightSurround;
        case AOUT_CHAN_MIDDLELEFT:
            return swap_rear_surround ? kAudioChannelLabel_LeftSurround
                                      : kAudioChannelLabel_RearSurroundLeft;
        case AOUT_CHAN_MIDDLERIGHT:
            return swap_rear_surround ? kAudioChannelLabel_RightSurround
                                      : kAudioChannelLabel_RearSurroundRight;
        case AOUT_CHAN_REARCENTER:
            return kAudioChannelLabel_CenterSurround;
        default:
            vlc_assert_unreachable();
    }
}

int
channel_layout_MapFromVLC(audio_output_t *p_aout, const audio_sample_format_t *fmt,
                          AudioChannelLayout **inlayoutp, size_t *inlayout_size)
{
    unsigned channels = aout_FormatNbChannels(fmt);
    size_t size;

    /* Stereo on xros via avsb doesn't work with the UseChannelDescriptions
     * tag, so use Mono and Stereo tags. */
    if (channels <= 2)
    {
        size = sizeof(AudioChannelLayout);
        AudioChannelLayout *inlayout = malloc(size);
        if (inlayout == NULL)
            return VLC_ENOMEM;
        *inlayoutp = inlayout;
        *inlayout_size = size;
        inlayout->mChannelBitmap = 0;
        inlayout->mNumberChannelDescriptions = 0;

        if (channels == 1)
            inlayout->mChannelLayoutTag = kAudioChannelLayoutTag_Mono;
        else
            inlayout->mChannelLayoutTag =
                p_aout->current_sink_info.headphones ?
                    kAudioChannelLayoutTag_StereoHeadphones :
                    kAudioChannelLayoutTag_Stereo;

        return VLC_SUCCESS;
    }

    if (ckd_mul(&size, channels, sizeof(AudioChannelDescription)) ||
        ckd_add(&size, size, sizeof(AudioChannelLayout)))
        return VLC_ENOMEM;
    AudioChannelLayout *inlayout = malloc(size);
    if (inlayout == NULL)
        return VLC_ENOMEM;

    *inlayoutp = inlayout;
    *inlayout_size = size;
    inlayout->mChannelLayoutTag = kAudioChannelLayoutTag_UseChannelDescriptions;
    inlayout->mNumberChannelDescriptions = aout_FormatNbChannels(fmt);

    bool swap_rear_surround = (fmt->i_physical_channels & AOUT_CHANS_7_0) == AOUT_CHANS_7_0;
    if (swap_rear_surround)
        msg_Dbg(p_aout, "swapping Surround and RearSurround channels "
                "for 7.1 Rear Surround");
    unsigned chan_idx = 0;
    for (unsigned i = 0; i < ARRAY_SIZE(pi_vlc_chan_order_wg4) - 1; ++i)
    {
        unsigned vlcchan = pi_vlc_chan_order_wg4[i];
        if ((vlcchan & fmt->i_physical_channels) == 0)
            continue;

        inlayout->mChannelDescriptions[chan_idx].mChannelLabel =
            VlcChanToAudioChannelLabel(vlcchan, swap_rear_surround);
        inlayout->mChannelDescriptions[chan_idx].mChannelFlags =
            kAudioChannelFlags_AllOff;
        chan_idx++;
    }

    msg_Dbg(p_aout, "VLC keeping the same input layout");

    return VLC_SUCCESS;
}

/* Layouts Apple recognises as spatial audio, with the channel order the tag
 * implies. Only the tags whose order is known here are used; anything else
 * keeps the descriptions. */
static bool
channel_layout_GetStandardTag(const audio_sample_format_t *fmt,
                              AudioChannelLayoutTag *tag,
                              uint32_t order[AOUT_CHAN_MAX])
{
    if (fmt->channel_type != AUDIO_CHANNEL_TYPE_BITMAP)
        return false;

    const uint32_t chans = fmt->i_physical_channels;

    if (chans == AOUT_CHANS_2_1)
    {
        /* DVD_4 is L R LFE, VLC's 2.1 order. */
        static const uint32_t o[AOUT_CHAN_MAX] = {
            AOUT_CHAN_LEFT, AOUT_CHAN_RIGHT, AOUT_CHAN_LFE, 0,
        };
        *tag = kAudioChannelLayoutTag_DVD_4;
        memcpy(order, o, sizeof(o));
        return true;
    }

    if (chans == AOUT_CHANS_3_1)
    {
        /* DVD_10 is L R C LFE, VLC's 3.1 order. */
        static const uint32_t o[AOUT_CHAN_MAX] = {
            AOUT_CHAN_LEFT, AOUT_CHAN_RIGHT, AOUT_CHAN_CENTER, AOUT_CHAN_LFE,
            0,
        };
        *tag = kAudioChannelLayoutTag_DVD_10;
        memcpy(order, o, sizeof(o));
        return true;
    }

    if (chans == AOUT_CHANS_4_0 || chans == AOUT_CHANS_4_0_MIDDLE)
    {
        /* Quadraphonic is L R Ls Rs, VLC's 4.0 order with either surround
         * pair. */
        static const uint32_t o_rear[AOUT_CHAN_MAX] = {
            AOUT_CHAN_LEFT, AOUT_CHAN_RIGHT, AOUT_CHAN_REARLEFT,
            AOUT_CHAN_REARRIGHT, 0,
        };
        static const uint32_t o_middle[AOUT_CHAN_MAX] = {
            AOUT_CHAN_LEFT, AOUT_CHAN_RIGHT, AOUT_CHAN_MIDDLELEFT,
            AOUT_CHAN_MIDDLERIGHT, 0,
        };
        *tag = kAudioChannelLayoutTag_Quadraphonic;
        memcpy(order, chans == AOUT_CHANS_4_0 ? o_rear : o_middle,
               sizeof(o_rear));
        return true;
    }

    if (chans == AOUT_CHANS_4_CENTER_REAR)
    {
        /* MPEG_4_0_A is L R C Cs, VLC's 4.0 with a rear centre. */
        static const uint32_t o[AOUT_CHAN_MAX] = {
            AOUT_CHAN_LEFT, AOUT_CHAN_RIGHT, AOUT_CHAN_CENTER,
            AOUT_CHAN_REARCENTER, 0,
        };
        *tag = kAudioChannelLayoutTag_MPEG_4_0_A;
        memcpy(order, o, sizeof(o));
        return true;
    }

    if (chans == AOUT_CHANS_3_0)
    {
        /* MPEG_3_0_A is L R C, VLC's 3.0 order. */
        static const uint32_t o[AOUT_CHAN_MAX] = {
            AOUT_CHAN_LEFT, AOUT_CHAN_RIGHT, AOUT_CHAN_CENTER, 0,
        };
        *tag = kAudioChannelLayoutTag_MPEG_3_0_A;
        memcpy(order, o, sizeof(o));
        return true;
    }

    if (chans == AOUT_CHANS_5_0 || chans == AOUT_CHANS_5_0_MIDDLE)
    {
        /* MPEG_5_0_B is L R Ls Rs C, VLC's 5.0 order with either surround
         * pair. */
        static const uint32_t o_rear[AOUT_CHAN_MAX] = {
            AOUT_CHAN_LEFT, AOUT_CHAN_RIGHT, AOUT_CHAN_REARLEFT,
            AOUT_CHAN_REARRIGHT, AOUT_CHAN_CENTER, 0,
        };
        static const uint32_t o_middle[AOUT_CHAN_MAX] = {
            AOUT_CHAN_LEFT, AOUT_CHAN_RIGHT, AOUT_CHAN_MIDDLELEFT,
            AOUT_CHAN_MIDDLERIGHT, AOUT_CHAN_CENTER, 0,
        };
        *tag = kAudioChannelLayoutTag_MPEG_5_0_B;
        memcpy(order, chans == AOUT_CHANS_5_0 ? o_rear : o_middle,
               sizeof(o_rear));
        return true;
    }

    if (chans == AOUT_CHANS_5_1
     || chans == (AOUT_CHANS_5_0_MIDDLE | AOUT_CHAN_LFE))
    {
        /* MPEG_5_1_B is L R Ls Rs C LFE. VLC's rear pair is the surround
         * pair, and its middle pair is the side pair. */
        static const uint32_t o_rear[AOUT_CHAN_MAX] = {
            AOUT_CHAN_LEFT, AOUT_CHAN_RIGHT, AOUT_CHAN_REARLEFT,
            AOUT_CHAN_REARRIGHT, AOUT_CHAN_CENTER, AOUT_CHAN_LFE, 0,
        };
        static const uint32_t o_middle[AOUT_CHAN_MAX] = {
            AOUT_CHAN_LEFT, AOUT_CHAN_RIGHT, AOUT_CHAN_MIDDLELEFT,
            AOUT_CHAN_MIDDLERIGHT, AOUT_CHAN_CENTER, AOUT_CHAN_LFE, 0,
        };
        *tag = kAudioChannelLayoutTag_MPEG_5_1_B;
        memcpy(order, chans == AOUT_CHANS_5_1 ? o_rear : o_middle,
               sizeof(o_rear));
        return true;
    }

    if (chans == (AOUT_CHANS_5_0_MIDDLE | AOUT_CHAN_REARCENTER))
    {
        /* AudioUnit_6_0 is L R Ls Rs C Cs, VLC's 6.0 with a rear centre. */
        static const uint32_t o[AOUT_CHAN_MAX] = {
            AOUT_CHAN_LEFT, AOUT_CHAN_RIGHT, AOUT_CHAN_MIDDLELEFT,
            AOUT_CHAN_MIDDLERIGHT, AOUT_CHAN_CENTER, AOUT_CHAN_REARCENTER, 0,
        };
        *tag = kAudioChannelLayoutTag_AudioUnit_6_0;
        memcpy(order, o, sizeof(o));
        return true;
    }

    if (chans == AOUT_CHANS_6_1_MIDDLE)
    {
        /* MPEG_6_1_A is L R C LFE Ls Rs Cs. */
        static const uint32_t o[AOUT_CHAN_MAX] = {
            AOUT_CHAN_LEFT, AOUT_CHAN_RIGHT, AOUT_CHAN_CENTER, AOUT_CHAN_LFE,
            AOUT_CHAN_MIDDLELEFT, AOUT_CHAN_MIDDLERIGHT,
            AOUT_CHAN_REARCENTER, 0,
        };
        *tag = kAudioChannelLayoutTag_MPEG_6_1_A;
        memcpy(order, o, sizeof(o));
        return true;
    }

    if (chans == AOUT_CHANS_7_0)
    {
        /* AudioUnit_7_0 is L R Ls Rs C Rls Rrs. */
        static const uint32_t o[AOUT_CHAN_MAX] = {
            AOUT_CHAN_LEFT, AOUT_CHAN_RIGHT, AOUT_CHAN_MIDDLELEFT,
            AOUT_CHAN_MIDDLERIGHT, AOUT_CHAN_CENTER, AOUT_CHAN_REARLEFT,
            AOUT_CHAN_REARRIGHT, 0,
        };
        *tag = kAudioChannelLayoutTag_AudioUnit_7_0;
        memcpy(order, o, sizeof(o));
        return true;
    }

    if (chans == AOUT_CHANS_7_1)
    {
        /* MPEG_7_1_C is L R C LFE Ls Rs Rls Rrs: VLC's middle pair is the
         * side pair and its rear pair the rear surround pair. */
        static const uint32_t o[AOUT_CHAN_MAX] = {
            AOUT_CHAN_LEFT, AOUT_CHAN_RIGHT, AOUT_CHAN_CENTER, AOUT_CHAN_LFE,
            AOUT_CHAN_MIDDLELEFT, AOUT_CHAN_MIDDLERIGHT,
            AOUT_CHAN_REARLEFT, AOUT_CHAN_REARRIGHT, 0,
        };
        *tag = kAudioChannelLayoutTag_MPEG_7_1_C;
        memcpy(order, o, sizeof(o));
        return true;
    }

    return false;
}

int
channel_layout_MapSpatialFromVLC(audio_output_t *p_aout,
                                 const audio_sample_format_t *fmt,
                                 AudioChannelLayout **inlayoutp,
                                 size_t *inlayout_size,
                                 uint32_t order[AOUT_CHAN_MAX])
{
    AudioChannelLayoutTag tag;

    unsigned dbg_channels = aout_FormatNbChannels(fmt);
    if (fmt->i_physical_channels == 0 && fmt->i_channels > 0)
        dbg_channels = fmt->i_channels;
    msg_Dbg(p_aout, "layout type %d, %u channel(s), physical mask 0x%x",
            (int) fmt->channel_type, dbg_channels,
            fmt->i_physical_channels);

    if (fmt->channel_type == AUDIO_CHANNEL_TYPE_BITMAP
     && (fmt->i_physical_channels == AOUT_CHANS_7_1_4
      || (fmt->i_physical_channels == AOUT_CHANS_7_1 && fmt->i_channels == 12)
      || (fmt->i_physical_channels == 0 && fmt->i_channels == 12)))
    {
        AudioChannelLayout *inlayout = malloc(sizeof(*inlayout));
        if (inlayout == NULL)
            return VLC_ENOMEM;

        inlayout->mChannelLayoutTag = kAudioChannelLayoutTag_Atmos_7_1_4;
        inlayout->mNumberChannelDescriptions = 0;
        *inlayoutp = inlayout;
        *inlayout_size = sizeof(*inlayout);

        /* Samples are emitted in CoreAudio's Atmos 7.1.4 order
         * (L R C LFE Ls Rs Lb Rb TFL TFR TBL TBR), so no reorder. */
        memset(order, 0, sizeof(*order) * AOUT_CHAN_MAX);
        order[0] = UINT32_MAX;

        msg_Dbg(p_aout, "using standard CoreAudio layout 0x%08x for spatial "
                "audio", (unsigned) kAudioChannelLayoutTag_Atmos_7_1_4);
        return VLC_SUCCESS;
    }

    if (channel_layout_GetStandardTag(fmt, &tag, order))
    {
        AudioChannelLayout *inlayout = malloc(sizeof(*inlayout));
        if (inlayout == NULL)
            return VLC_ENOMEM;

        inlayout->mChannelLayoutTag = tag;
        inlayout->mNumberChannelDescriptions = 0;
        *inlayoutp = inlayout;
        *inlayout_size = sizeof(*inlayout);

        msg_Dbg(p_aout, "using standard CoreAudio layout 0x%08x for spatial "
                "audio", (unsigned) tag);
        return VLC_SUCCESS;
    }

    /* No standard tag for this layout: keep the descriptions, which preserve
     * the channel map, but the system may not spatialise the stream. The
     * samples stay in VLC's order. */
    memcpy(order, pi_vlc_chan_order_wg4,
           AOUT_CHAN_MAX * sizeof(*order));
    return channel_layout_MapFromVLC(p_aout, fmt, inlayoutp, inlayout_size);
}
