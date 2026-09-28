/*****************************************************************************
 * MacLCMetalRenderer.h: Metal GPU pipeline for video and subpictures
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

#ifndef MACLC_METAL_RENDERER_H
#define MACLC_METAL_RENDERER_H

#import <Foundation/Foundation.h>
#import <CoreVideo/CoreVideo.h>
#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>

#include <vlc_common.h>
#include <vlc_es.h>
#include <vlc_subpicture.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * Metal rendering engine handling stage-A decode, subpicture texture uploads,
 * bilinear scaling, orientation affine transforms, BT.2020 to Display P3 gamut mapping,
 * and presentation into a CAMetalDrawable.
 *
 * Contains NO vout_display_t references or dependencies.
 */
@class MacLCMetalScaler, MacLCMetal360, MacLCMetalLUT;

@interface MacLCMetalRenderer : NSObject

/* Optional stages (phase M3), owned by the display: the scaler replaces the
 * bilinear quad when a filter is chosen (upright pictures only), the
 * projector draws 360-degree video, the LUT is applied to the finished
 * picture (before subtitles). */
@property (nonatomic, nullable) MacLCMetalScaler *scaler;
@property (nonatomic, nullable) MacLCMetal360 *projector;
@property (nonatomic, nullable) MacLCMetalLUT *lut;
@property (nonatomic) float sampleAspectRatio; /* for the projector */
/* gl-gamut-mapping: how BT.2020 colours outside Display P3 are brought in,
 * in the final pass (0 = automatic, perceptual). Applied only while
 * sourceGamutIsWide: a BT.709 or P3 picture fits the display as it is, as
 * libplacebo leaves a source its target contains. */
@property (nonatomic) int gamutMapping;
@property (nonatomic) BOOL sourceGamutIsWide;

/* The Core Video texture cache the renderer wraps pixel buffers with, for
 * stages the display runs before it (Dolby Vision decoding). */
@property (nonatomic, readonly) CVMetalTextureCacheRef textureCache;

@property (nonatomic, readonly) id<MTLDevice> device;
@property (nonatomic, readonly) id<MTLCommandQueue> commandQueue;

/**
 * Initializes the Metal renderer with the given GPU device.
 */
- (nullable instancetype)initWithDevice:(id<MTLDevice>)device;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

/**
 * Creates a new command buffer for Stage A preparation.
 */
- (id<MTLCommandBuffer>)createCommandBuffer;

/**
 * Wraps an existing 64RGBAHalf CVPixelBuffer (produced by tone mapper or expander)
 * as an RGBA16Float Metal texture. Keeps the CVMetalTextureRef alive until the command
 * buffer completes.
 */
- (nullable id<MTLTexture>)textureFromRGBAHalfBuffer:(CVPixelBufferRef)pixelBuffer
                                      commandBuffer:(id<MTLCommandBuffer>)commandBuffer;

/**
 * Stage A: Decodes a raw hardware or software CVPixelBuffer (NV12 420v/420f, P010 x420, BGRA)
 * into an intermediate linear BT.2020 light RGBA16Float texture with SDR white at 1.0.
 */
- (nullable id<MTLTexture>)decodeSourceBuffer:(CVPixelBufferRef)pixelBuffer
                                       format:(const video_format_t *)fmt
                                commandBuffer:(id<MTLCommandBuffer>)commandBuffer;

/**
 * Updates subpicture regions, uploading RGBA region pixel data into recycled or new
 * Metal textures.
 */
- (void)updateSubpicture:(nullable const struct vlc_render_subpicture *)subpicture
             outputWidth:(unsigned)outWidth
            outputHeight:(unsigned)outHeight;

/**
 * Stage B: Renders the stage-A linear BT.2020 texture and any active subpictures into
 * the drawable's target texture in Display P3 linear light, presenting the drawable.
 *
 * \param stageATexture the linear BT.2020 intermediate texture from Stage A.
 * \param drawable the target CAMetalDrawable to draw into and present.
 * \param placement the picture placement rectangle in drawable pixel coordinates.
 * \param cropOrigin the top-left offset (i_x_offset, i_y_offset) in the source texture.
 * \param cropSize the visible dimensions (i_visible_width, i_visible_height).
 * \param orientation orientation transform of the video stream.
 * \param headroom current display EDR headroom.
 * \param isEDR whether extended dynamic range presentation is active.
 * \return YES if the render pass was successfully encoded and committed.
 */
- (BOOL)renderVideoTexture:(id<MTLTexture>)stageATexture
                toDrawable:(id<CAMetalDrawable>)drawable
                 placement:(CGRect)placement
                cropOrigin:(CGPoint)cropOrigin
                  cropSize:(CGSize)cropSize
               orientation:(video_orientation_t)orientation
                  headroom:(float)headroom
                     isEDR:(BOOL)isEDR;

/**
 * Scaling interface: encodes the video quad geometry and sampling from srcTexture
 * into the given render command encoder. In M1 this is bilinear; M3 replaces this.
 */
- (void)encodeScaleFrom:(id<MTLTexture>)srcTexture
          renderEncoder:(id<MTLRenderCommandEncoder>)encoder
              placement:(CGRect)placement
             cropOrigin:(CGPoint)cropOrigin
               cropSize:(CGSize)cropSize
            orientation:(video_orientation_t)orientation
               headroom:(float)headroom
                  isEDR:(BOOL)isEDR
           drawableSize:(CGSize)drawableSize;

/**
 * Subpicture rendering: encodes quads for each active subpicture region.
 */
- (void)renderSubpicturesWithEncoder:(id<MTLRenderCommandEncoder>)encoder
                        drawableSize:(CGSize)drawableSize;

/**
 * Waits for in-flight command buffers to complete on the GPU.
 */
- (void)waitUntilCompleted;

/**
 * Flushes texture caches and releases intermediate textures.
 */
- (void)releaseResources;

@end

NS_ASSUME_NONNULL_END

#endif /* MACLC_METAL_RENDERER_H */
