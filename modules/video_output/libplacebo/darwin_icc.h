/*****************************************************************************
 * darwin_icc.h: Darwin screen ICC profile resolver for libplacebo
 *****************************************************************************
 * Copyright (C) 2026 VLC authors and VideoLAN
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

#ifndef VLC_PLACEBO_DARWIN_ICC_H
#define VLC_PLACEBO_DARWIN_ICC_H 1

#include <CoreGraphics/CoreGraphics.h>
#include <stdatomic.h>

typedef struct vlc_placebo_darwin_icc vlc_placebo_darwin_icc;

/**
 * Creates a Darwin ICC watcher for the given window view handle.
 *
 * @param nsobject the window's handle.nsobject (expected to be an NSView)
 * @param dirty pointer to atomic_bool dirty flag in vout_display_sys_t
 * @return opaque watcher pointer, or NULL if handle is not an NSView or allocation fails
 */
vlc_placebo_darwin_icc *vlc_placebo_darwin_icc_create(void *nsobject,
                                                      atomic_bool *dirty);

/**
 * Destroys the Darwin ICC watcher and unregisters all screen observers.
 *
 * @param icc the watcher context (can be NULL)
 */
void vlc_placebo_darwin_icc_destroy(vlc_placebo_darwin_icc *icc);

/**
 * Returns the cached CGDirectDisplayID for the window's screen.
 * This is non-blocking and safe to call from any thread (including render thread).
 * If the screen cannot be resolved or icc is NULL, falls back to CGMainDisplayID().
 *
 * @param icc the watcher context (can be NULL)
 * @return CGDirectDisplayID for the window's screen, or CGMainDisplayID()
 */
CGDirectDisplayID vlc_placebo_darwin_icc_get_display_id(vlc_placebo_darwin_icc *icc);

/**
 * Requests an asynchronous re-evaluation of the window's screen on the main thread.
 * If the display ID has changed, the dirty flag is set.
 *
 * @param icc the watcher context (can be NULL)
 */
void vlc_placebo_darwin_icc_request_update(vlc_placebo_darwin_icc *icc);

#endif /* VLC_PLACEBO_DARWIN_ICC_H */
