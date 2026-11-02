/*****************************************************************************
 * MacLCMetalHookShader.h: runs a 2x luma user shader on Metal
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

#ifndef MACLC_METAL_HOOK_SHADER_H
#define MACLC_METAL_HOOK_SHADER_H

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * Translates a user shader in the mpv hook format (fragment passes only:
 * HOOK MAIN or LUMA, BIND, SAVE, WIDTH, HEIGHT) to Metal and runs it on a
 * luma plane. The shader must end with one pass writing the hooked texture
 * at twice its size, as Anime4K and FSRCNNX x2 do. WHEN is ignored: the
 * caller decides when to upscale. The input is grey (luma in R, G and B).
 */
@interface MacLCMetalHookShader : NSObject

/** nil when the shader uses something unsupported or does not compile. */
- (nullable instancetype)initWithDevice:(id<MTLDevice>)device source:(NSString *)source;
- (instancetype)init NS_UNAVAILABLE;

/** Same contract as MacLCMetalArtCNN. */
- (BOOL)encodeLuma:(id<MTLTexture>)y
                to:(id<MTLTexture>)y2
        videoRange:(BOOL)videoRange
     commandBuffer:(id<MTLCommandBuffer>)commandBuffer;

@end

NS_ASSUME_NONNULL_END

#endif
