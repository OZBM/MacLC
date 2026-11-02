/*****************************************************************************
 * MacLCMetalUpscaler.h: neural and MetalFX upscaling for the Metal output
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

#ifndef MACLC_METAL_UPSCALER_H
#define MACLC_METAL_UPSCALER_H

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <CoreVideo/CoreVideo.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * Upscaling passes, used one after the other:
 *
 * 1. A first pass on the decoded 8-bit SDR picture, before it is decoded to
 *    linear light, either
 *    - neural: VideoToolbox's low-latency super resolution (macOS 26, ×1.5
 *      and ×2 up to 1280×1280) or its full ×4 super resolution (a model the
 *      user downloads, up to 1920×1080), or
 *    - anime: a ×2 luma network, ArtCNN for line art (MacLCMetalArtCNN), or
 *      Anime4K or FSRCNNX run as hook shaders (MacLCMetalHookShader).
 * 2. Spatial: MetalFX's spatial scaler on the linear-light texture, for what
 *    is left up to the size the picture is shown at.
 *
 * VideoToolbox sessions start on a queue (the ×4 one takes seconds), so a
 * pass reports "loading" until its session is ready.
 */
@interface MacLCMetalUpscaler : NSObject

- (instancetype)initWithDevice:(id<MTLDevice>)device;
- (instancetype)init NS_UNAVAILABLE;

/** The low-latency neural factor for a picture of width×height shown
 *  maxRatio times larger: the largest offered that does not overshoot, 0 for
 *  none. */
+ (float)neuralFactorForWidth:(size_t)width height:(size_t)height
                     maxRatio:(float)maxRatio;

/**
 * Upscales `source` with a neural pass.
 *
 * @param apple4x in: try the full ×4 pass first; out: whether it was used
 * @param frameInterval seconds per frame, the budget the pass must fit in
 * @return a retained buffer, or NULL when no neural pass is used; `why` then
 *         names the reason in the maclc-upscale-state vocabulary. With a
 *         buffer, `why` may still name why the ×4 pass was not used.
 */
- (nullable CVPixelBufferRef)neuralUpscale:(CVPixelBufferRef)source
                                  maxRatio:(float)maxRatio
                                   apple4x:(BOOL *)apple4x
                             frameInterval:(double)frameInterval
                                       why:(const char *_Nullable *_Nonnull)why
    CF_RETURNS_RETAINED;

/** Doubles `source` (420v or 420f) with the luma network of `method`
 *  (MACLC_UPSCALE_ANIME, _ANIME4K or _FSRCNNX); chroma is scaled bilinearly.
 *  Same contract as neuralUpscale. */
- (nullable CVPixelBufferRef)animeUpscale:(CVPixelBufferRef)source
                                  network:(NSInteger)method
                                 maxRatio:(float)maxRatio
                            frameInterval:(double)frameInterval
                                      why:(const char *_Nullable *_Nonnull)why
    CF_RETURNS_RETAINED;

/** Encodes a MetalFX spatial upscale of `texture` to width×height into
 *  `commandBuffer`; nil when MetalFX cannot take it. */
- (nullable id<MTLTexture>)encodeSpatialFrom:(id<MTLTexture>)texture
                                       width:(NSUInteger)width
                                      height:(NSUInteger)height
                               commandBuffer:(id<MTLCommandBuffer>)commandBuffer;

@end

NS_ASSUME_NONNULL_END

#endif
