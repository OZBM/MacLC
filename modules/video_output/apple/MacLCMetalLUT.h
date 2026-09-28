/*****************************************************************************
 * MacLCMetalLUT.h: Metal 3D LUT parser and application (.cube)
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

#ifndef MACLC_METAL_LUT_H
#define MACLC_METAL_LUT_H

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * Metal 3D LUT component for parsing .cube files and applying 3D color transforms
 * to Display P3 linear light textures in place with hardware trilinear filtering.
 *
 * EDR values above 1.0 are passed through scaled.
 */
@interface MacLCMetalLUT : NSObject

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

/**
 * Parses an Adobe .cube file from `path` and creates a 3D texture on `device`.
 *
 * Supports TITLE, LUT_3D_SIZE, DOMAIN_MIN, DOMAIN_MAX, comments and whitespace.
 *
 * \param path filesystem path to the .cube file.
 * \param device Metal GPU device.
 * \param error optional pointer to receive parsing error if failed.
 * \return initialized MacLCMetalLUT or nil on error.
 */
+ (nullable instancetype)lutWithCubeFile:(NSString *)path
                                  device:(id<MTLDevice>)device
                                   error:(NSError **)error;

/**
 * Applies the 3D LUT in place to `texture` (linear Display P3 light).
 *
 * Encodes the compute or render pass into `commandBuffer`.
 *
 * \param texture linear Display P3 texture with read/write access.
 * \param commandBuffer Metal command buffer to encode into.
 */
- (void)encodeApplyTo:(id<MTLTexture>)texture
        commandBuffer:(id<MTLCommandBuffer>)commandBuffer;

@end

NS_ASSUME_NONNULL_END

#endif /* MACLC_METAL_LUT_H */
