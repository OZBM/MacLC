/*****************************************************************************
 * atmos_prime.h: one-shot registration of Apple's Atmos decoder
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

#ifndef VLC_ATMOS_PRIME_H
#define VLC_ATMOS_PRIME_H

#include <stdbool.h>

/**
 * Starts the Atmos decoder registration, if it has not started yet.
 *
 * AVSampleBufferAudioRenderer decodes compressed E-AC-3 as Atmos only when
 * the process has registered Apple's Atmos decoder. On macOS creating an
 * AVPlayer for an E-AC-3 JOC item is enough; nothing has to play and the
 * registration persists for the process. This creates that player with a
 * generated silent Atmos stream, so it is inaudible and needs no media file.
 *
 * Safe to call from any thread and more than once.
 */
void
atmos_prime_Begin(void);

#endif
