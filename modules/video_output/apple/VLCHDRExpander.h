/*****************************************************************************
 * VLCHDRExpander.h: GPU dynamic-range expansion (SDR -> HDR) for Apple
 * platforms
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

#ifndef VLC_HDR_EXPANDER_H
#define VLC_HDR_EXPANDER_H

#import <Foundation/Foundation.h>
#import <CoreVideo/CoreVideo.h>

#include <vlc_common.h>
#include <vlc_es.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * Luminance, in cd/m^2, that the expander assigns to SDR diffuse white when
 * encoding PQ. macOS maps PQ 100 cd/m^2 onto the display's SDR white level, so
 * using that value keeps everything below the expansion knee pixel-identical to
 * SDR playback: toggling the feature must not shift mid-tone brightness.
 */
#define VLC_HDR_EXPANDER_SDR_WHITE_NITS 100.0f

/**
 * Turns an SDR picture into a PQ / BT.2020 one by expanding its highlights into
 * the display's extended dynamic range, on the GPU.
 *
 * The transform is: Y'CbCr (or BGRA) -> R'G'B' -> linear (BT.1886 or sRGB) ->
 * highlight expansion -> BT.2020 primaries -> PQ -> 10-bit Y'CbCr. Only values
 * above the knee are altered; shadows and mid-tones round-trip exactly.
 *
 * Every method is safe to call from the video output thread, but a single
 * instance must not be used from two threads at once.
 */
@interface VLCHDRExpander : NSObject

/**
 * Creates an expander, or returns nil if the system has no usable Metal device
 * or the shaders fail to compile. Failure is not fatal: the caller should carry
 * on displaying the untouched SDR picture.
 *
 * \param obj object used for logging; not retained.
 */
+ (nullable instancetype)expanderForObject:(vlc_object_t *)obj;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

/**
 * How far above SDR white the brightest highlights are allowed to go, as a
 * multiple of SDR white. Clamped to [1.0, 16.0]. 1.0 disables the expansion.
 */
@property (nonatomic) float boost;

/**
 * Signal level, relative to SDR white, at which the expansion starts. Below it
 * the picture is untouched. Clamped to [0.0, 0.99].
 */
@property (nonatomic) float knee;

/**
 * Whether a picture of that CoreVideo format can be expanded. Formats that
 * cannot are passed through unchanged.
 */
- (BOOL)canExpandPixelFormat:(OSType)pixelFormat;

/**
 * Expands one picture.
 *
 * \param pixelBuffer the SDR source picture.
 * \param fmt colorimetry of the source picture.
 * \param headroom the display's current EDR headroom; the effective expansion
 *        is min(headroom, boost), so a picture is never brighter than the
 *        screen can show.
 * \return a new PQ / BT.2020 10-bit pixel buffer the caller owns, or NULL if
 *         the picture could not be expanded, in which case the source must be
 *         displayed as-is.
 */
- (nullable CVPixelBufferRef)expandPixelBuffer:(CVPixelBufferRef)pixelBuffer
                                        format:(const video_format_t *)fmt
                                      headroom:(float)headroom
    CF_RETURNS_RETAINED;

/**
 * Peak luminance, in cd/m^2, that the last expandPixelBuffer: call encoded for.
 * Meant for the mastering-display metadata attached to the result.
 */
@property (nonatomic, readonly) float lastPeakNits;

@end

NS_ASSUME_NONNULL_END

#endif /* VLC_HDR_EXPANDER_H */
