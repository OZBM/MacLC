/*****************************************************************************
 * MacLCMetalDovi.h: Metal Dolby Vision RPU decoding pipeline
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

#ifndef MACLC_METAL_DOVI_H
#define MACLC_METAL_DOVI_H

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <CoreVideo/CoreVideo.h>

#ifdef HAVE_CONFIG_H
# include "config.h"
#endif

#include <vlc_common.h>
#include <vlc_ancillary.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * Metal Dolby Vision decoding engine.
 * Converts base-layer pictures with their RPU metadata into linear BT.2020 light
 * in RGBA16Float (1.0 = 100 cd/m², MACLC_HDR_REFERENCE_WHITE).
 */
@interface MacLCMetalDovi : NSObject

- (nullable instancetype)initWithDevice:(id<MTLDevice>)device;

/* Decodes one base-layer picture (P010 'x420' or 420v/420f 8-bit CVPixelBuffer)
 * with its RPU into linear BT.2020 light, RGBA16Float, 1.0 = 100 cd/m2
 * (MACLC_HDR_REFERENCE_WHITE), encoded into `commandBuffer` (not committed).
 * The texture is reused between calls; returns nil on failure. */
- (nullable id<MTLTexture>)decodePixelBuffer:(CVPixelBufferRef)pixelBuffer
                                    metadata:(const vlc_video_dovi_metadata_t *)rpu
                               commandBuffer:(id<MTLCommandBuffer>)commandBuffer
                                textureCache:(CVMetalTextureCacheRef)cache;

/* Peak of the current scene in cd/m2 (source_max_pq), for the tone mapper. */
@property (nonatomic, readonly) float sourcePeakNits;

@end

NS_ASSUME_NONNULL_END

#endif /* MACLC_METAL_DOVI_H */
