/*****************************************************************************
 * MacLCHDRToneMapper.h: GPU picture-mode tone mapping of PQ video
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

#ifndef MACLC_HDR_TONE_MAPPER_H
#define MACLC_HDR_TONE_MAPPER_H

#import <Foundation/Foundation.h>
#import <CoreVideo/CoreVideo.h>

#include <vlc_common.h>

#include "maclc_tonemap.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * Re-maps the luminance of a PQ / BT.2020 picture with one of MacLC's picture
 * modes (maclc_tonemap.h) before it is handed to the compositor, so that what
 * the display shows is decided by MacLC's curve rather than by whatever tone
 * mapping the system would apply on its own.
 *
 * The curve is evaluated on max(R, G, B) and the linear triplet is scaled by
 * the result, which keeps hue and saturation. The output is 10-bit PQ /
 * BT.2020 in the same bi-planar format the decoder produces.
 *
 * Safe to use from the video output thread; one instance must not be used by
 * two threads at once.
 */
@interface MacLCHDRToneMapper : NSObject

/**
 * Creates a tone mapper, or returns nil when there is no usable Metal device or
 * the kernel does not compile. Not fatal: the picture is then shown untouched.
 * \param obj object used for logging; not retained.
 */
+ (nullable instancetype)toneMapperForObject:(vlc_object_t *)obj;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

/** Whether pictures of that CoreVideo format can be tone-mapped. */
- (BOOL)canToneMapPixelFormat:(OSType)pixelFormat;

/**
 * Tone-maps one picture.
 * \param pixelBuffer a 10-bit limited-range PQ / BT.2020 bi-planar picture.
 * \param params curve parameters from maclc_tone_params_init(); callers
 *        should skip the call entirely when params->identity is true.
 * \return a new picture the caller owns, or NULL when it could not be
 *         processed, in which case the source is displayed as it is.
 */
- (nullable CVPixelBufferRef)toneMapPixelBuffer:(CVPixelBufferRef)pixelBuffer
                                         params:(const maclc_tone_params *)params
    CF_RETURNS_RETAINED;

@end

NS_ASSUME_NONNULL_END

#endif /* MACLC_HDR_TONE_MAPPER_H */
