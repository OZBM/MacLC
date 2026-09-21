// SPDX-License-Identifier: LGPL-2.1-or-later
/*****************************************************************************
 * maclc_frc_geometry.h: arithmetic the frame interpolator relies on
 *****************************************************************************
 * Copyright © 2026 Hazen Studio
 *
 * Kept apart from the filter itself so it can be tested without a video
 * output, a GPU or a decoder.
 *****************************************************************************/

#ifndef MACLC_FRC_GEOMETRY_H
#define MACLC_FRC_GEOMETRY_H

#include <stddef.h>
#include <stdint.h>

/**
 * How many output frames to make out of each source frame.
 *
 * Only whole multiples are useful: showing 100 frames a second on a 120 Hz
 * panel puts the judder back. The answer is therefore the largest whole
 * multiple of the source that still fits in the target, capped by \p limit.
 *
 * @param source_fps frame rate of the video, rounded to the nearest integer;
 *                   0 when it is unknown
 * @param target_fps frame rate to aim for, usually the refresh rate of the
 *                   display
 * @param limit      never return more than this
 * @return the multiplier, at least 1; 1 means leave the video alone
 */
unsigned maclc_frc_factor(unsigned source_fps, unsigned target_fps,
                          unsigned limit);

/**
 * The refresh rate of the screen the video is most likely shown on.
 *
 * Both the filter and the interface ask here, so that the frame rate the
 * badge promises is the one the filter will actually aim for.
 *
 * @return whole frames per second; 120 when the panel declines to say, which
 *         is what the built-in displays of these machines do
 */
unsigned maclc_frc_display_refresh_rate(void);

/**
 * Interleaves two chroma planes into one, as 4:2:0 biplanar wants them.
 *
 * @param width  samples per row in each source plane
 * @param height rows
 */
void maclc_frc_interleave_chroma(uint8_t *dst, size_t dst_stride,
                                 const uint8_t *cb, size_t cb_stride,
                                 const uint8_t *cr, size_t cr_stride,
                                 size_t width, size_t height);

/** The reverse: splits an interleaved chroma plane back into two. */
void maclc_frc_deinterleave_chroma(const uint8_t *src, size_t src_stride,
                                   uint8_t *cb, size_t cb_stride,
                                   uint8_t *cr, size_t cr_stride,
                                   size_t width, size_t height);

#endif /* MACLC_FRC_GEOMETRY_H */
