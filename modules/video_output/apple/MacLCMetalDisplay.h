/*****************************************************************************
 * MacLCMetalDisplay.h: MacLC's Metal video output (a submodule of the
 *                      samplebufferdisplay plugin)
 *****************************************************************************
 * Copyright (C) 2026 Hazen Studio
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

#ifndef MACLC_METAL_DISPLAY_H
#define MACLC_METAL_DISPLAY_H

#include <vlc_common.h>
#include <vlc_vout_display.h>

/* The Metal output lives in the same plugin as the native sample-buffer one
 * because both run VLCHDRExpander, VLCHDRNetwork and MacLCHDRToneMapper: two
 * plugins would each carry a copy of those Objective-C classes, and the
 * runtime can only keep one of them (see VLCSampleBufferDisplay.m's module
 * descriptor for the submodule). */
int MacLCMetalOpen(vout_display_t *vd, video_format_t *fmt,
                   vlc_video_context *context);

#endif /* MACLC_METAL_DISPLAY_H */
