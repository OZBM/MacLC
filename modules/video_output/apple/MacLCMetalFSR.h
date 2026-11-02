/*****************************************************************************
 * MacLCMetalFSR.h: AMD FidelityFX Super Resolution 1 on the Metal output
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

#ifndef MACLC_METAL_FSR_H
#define MACLC_METAL_FSR_H

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

NS_ASSUME_NONNULL_BEGIN

/** AMD FSR 1: edge-adaptive upscale (EASU) then contrast-adaptive sharpening
 *  (RCAS), on a linear-light RGBA16Float texture that may exceed 1.0. */
@interface MacLCMetalFSR : NSObject

- (nullable instancetype)initWithDevice:(id<MTLDevice>)device;
- (instancetype)init NS_UNAVAILABLE;

/** RCAS sharpness in stops, 0 = sharpest; default 0.25. */
@property (nonatomic) float sharpness;

/** Encodes EASU from `texture` to width x height, then RCAS, into
 *  `commandBuffer`. Returns the result (RGBA16Float, private storage, one of
 *  two textures used in turn so the next frame never writes the one being
 *  drawn), or nil on failure. width/height are at least the input size. */
- (nullable id<MTLTexture>)encodeFrom:(id<MTLTexture>)texture
                                width:(NSUInteger)width
                               height:(NSUInteger)height
                        commandBuffer:(id<MTLCommandBuffer>)commandBuffer;

@end

NS_ASSUME_NONNULL_END

#endif
