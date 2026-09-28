/*****************************************************************************
 * MacLCMetalColorPass.h: tone mapping of linear light for the Metal output
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

#ifndef MACLC_METAL_COLOR_PASS_H
#define MACLC_METAL_COLOR_PASS_H

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

#include "maclc_tonemap.h"
#include "maclc_tonecurves.h"

NS_ASSUME_NONNULL_BEGIN

/*
 * Tone maps a picture that is already linear light: the Dolby Vision decoder's
 * output, or HDR10 decoded without a curve when the user picked one of the
 * OpenGL engine's curves. The curve runs on max(R, G, B) in PQ, like MacLC's
 * own tone mapper (MacLCHDRToneMapper.m), through a 512-entry table the
 * kernel interpolates. Gamut mapping is done by the renderer's final pass.
 */
@interface MacLCMetalColorPass : NSObject

- (nullable instancetype)initWithDevice:(id<MTLDevice>)device;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

/* MacLC's picture modes (maclc_tonemap.h): the curve every engine uses by
 * default, which the interface draws. Cheap to call every picture: the table
 * is only rebuilt when the parameters change. */
- (void)setToneParams:(const maclc_tone_params *)params;

/* One of libplacebo's curves (gl-tone-mapping-function), ported in
 * maclc_tonecurves.c. Same caching as above. */
- (void)setToneCurve:(const struct maclc_tonecurve_params *)params;

/* In: linear BT.2020 light, RGBA16Float, 1.0 = MACLC_HDR_REFERENCE_WHITE.
 * Out: the same light, tone mapped, in a texture this object reuses.
 * Encoded into commandBuffer (not committed); nil on failure. */
- (nullable id<MTLTexture>)encodeFrom:(id<MTLTexture>)input
                        commandBuffer:(id<MTLCommandBuffer>)commandBuffer;

@end

NS_ASSUME_NONNULL_END

#endif
