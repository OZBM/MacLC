/*****************************************************************************
 * channel_layout.h: Common Channel Layout code for iOS and macOS
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

typedef struct AudioChannelLayout AudioChannelLayout;

int
channel_layout_MapFromVLC(audio_output_t *p_aout, const audio_sample_format_t *fmt,
                          AudioChannelLayout **inlayoutp, size_t *inlayout_size);

/**
 * Maps a VLC format to a CoreAudio layout, preferring a standard layout tag.
 *
 * AVSampleBufferAudioRenderer only spatialises content whose format
 * description carries one of Apple's standard layouts; with
 * kAudioChannelLayoutTag_UseChannelDescriptions the stream plays as plain
 * multichannel audio and the system's spatial renderer is not engaged.
 *
 * \param order receives the VLC channel order the chosen layout expects
 *              (WG4 order when no standard tag matches). The samples must be
 *              reordered with aout_CheckChannelReorder() before being handed
 *              to the renderer when that order differs from the input.
 */
int
channel_layout_MapSpatialFromVLC(audio_output_t *p_aout,
                                 const audio_sample_format_t *fmt,
                                 AudioChannelLayout **inlayoutp,
                                 size_t *inlayout_size,
                                 uint32_t order[AOUT_CHAN_MAX]);
