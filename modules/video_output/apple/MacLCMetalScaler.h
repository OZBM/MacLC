/*****************************************************************************
 * MacLCMetalScaler.h: Metal video scaler implementing gl_scale presets
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

#ifndef MACLC_METAL_SCALER_H
#define MACLC_METAL_SCALER_H

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <CoreGraphics/CoreGraphics.h>

#include "video_output/opengl/gl_scale.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * Metal video scaler implementing the 21 presets of gl_scale.h.
 *
 * Separable filters are executed in two passes (horizontal then vertical)
 * through an intermediate texture owned and managed by the scaler.
 * Polar (EWA) filters are executed in a single 2D pass directly from input
 * to the destination region of the output texture.
 *
 * Scaling operates directly in linear light (RGBA16Float). Negative lobes'
 * results are clamped at 0.0.
 */
@interface MacLCMetalScaler : NSObject

- (nullable instancetype)initWithDevice:(id<MTLDevice>)device;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

/* gl_scale.h values; 0 (VLC_GLSCALE_BUILTIN) keeps the hardware bilinear path
 * and returns NO from encodeScaleFrom:... */
@property (nonatomic) int upscaler, downscaler;

/**
 * Scales `input` (linear light RGBA16Float, may exceed 1.0) into `output`
 * (RGBA16Float, drawable size region `destRect`) with the configured filter.
 *
 * Separable filters run in two passes (horizontal then vertical, through an
 * intermediate texture owned by the scaler); polar (EWA) filters run in one pass.
 *
 * Encodes into commandBuffer. Returns NO if the configured filter is Built-in.
 *
 * \param input source linear light texture.
 * \param sourceRect crop rectangle in input pixels.
 * \param output destination texture.
 * \param destRect placement rectangle in output pixels.
 * \param commandBuffer Metal command buffer to encode render passes into.
 * \return YES if scaled successfully, NO if Built-in or on failure.
 */
- (BOOL)encodeScaleFrom:(id<MTLTexture>)input
             sourceRect:(CGRect)sourceRect
                     to:(id<MTLTexture>)output
               destRect:(CGRect)destRect
          commandBuffer:(id<MTLCommandBuffer>)commandBuffer;

@end

NS_ASSUME_NONNULL_END

#endif /* MACLC_METAL_SCALER_H */
