/*****************************************************************************
 * MacLCHDRToneMapper.h: GPU picture-mode tone mapping of PQ and HLG video
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
#include <vlc_es.h>

#include "maclc_tonemap.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * Re-maps the luminance of a PQ or HLG / BT.2020 picture with one of MacLC's
 * picture modes (maclc_tonemap.h) before it is handed to the compositor, so
 * that what the display shows is decided by MacLC's curve rather than by the
 * video tone curve the system applies to every PQ and HLG picture (which dims
 * mid-tones to make room for highlights).
 *
 * HLG is first turned into display light with the BT.2100 OOTF for a display
 * of the given nominal peak (MACLC_HDR_HLG_PEAK puts its reference white, 75 %,
 * at 203 cd/m2 like a PQ master's); from there both are handled alike.
 *
 * The curve is evaluated on max(R, G, B) and the linear triplet is scaled by
 * the result, which keeps hue and saturation. The output is extended-range
 * linear light in half floats with BT.2020 primaries, where 1.0 is the
 * reference white passed by the caller: the compositor shows such pictures
 * as they are, with 1.0 at the display's SDR white.
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
 * Tone-maps one picture into linear light.
 * \param pixelBuffer a 10-bit limited-range BT.2020 bi-planar picture.
 * \param transfer its transfer function: TRANSFER_FUNC_SMPTE_ST2084 or
 *        TRANSFER_FUNC_HLG; anything else is not processed.
 * \param hlgPeak for HLG, the nominal peak luminance in cd/m2 of the display
 *        it is rendered for (maclc_hdr_hlg_peak()); ignored for PQ.
 * \param params curve parameters from maclc_tone_params_init(); an identity
 *        curve still converts the picture to linear light.
 * \param referenceWhite the luminance, in cd/m2, written as 1.0.
 * \return a new 64RGBAHalf picture the caller owns, tagged BT.2020 / linear,
 *         or NULL when it could not be processed, in which case the source is
 *         displayed as it is.
 */
- (nullable CVPixelBufferRef)toneMapPixelBuffer:(CVPixelBufferRef)pixelBuffer
                                       transfer:(video_transfer_func_t)transfer
                                        hlgPeak:(float)hlgPeak
                                         params:(const maclc_tone_params *)params
                                 referenceWhite:(float)referenceWhite
    CF_RETURNS_RETAINED;

@end

NS_ASSUME_NONNULL_END

#endif /* MACLC_HDR_TONE_MAPPER_H */
