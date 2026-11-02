/*****************************************************************************
 * MacLCMetalArtCNN.h: ArtCNN C4F16, a 2x luma doubler for anime, on Metal
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

#ifndef MACLC_METAL_ARTCNN_H
#define MACLC_METAL_ARTCNN_H

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * ArtCNN C4F16 (MIT, github.com/Artoriuz/ArtCNN): seven 3x3 convolutions of
 * 16 channels with a long skip, then depth-to-space, doubling an 8-bit luma
 * plane. Trained on anime line art.
 */
@interface MacLCMetalArtCNN : NSObject

- (nullable instancetype)initWithDevice:(id<MTLDevice>)device;
- (instancetype)init NS_UNAVAILABLE;

/** Encodes luma `y` (r8Unorm) doubled into `y2` (r8Unorm, twice the size,
 *  shader-write). videoRange: both planes are 16-235. */
- (BOOL)encodeLuma:(id<MTLTexture>)y
                to:(id<MTLTexture>)y2
        videoRange:(BOOL)videoRange
     commandBuffer:(id<MTLCommandBuffer>)commandBuffer;

@end

NS_ASSUME_NONNULL_END

#endif
