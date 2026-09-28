/*****************************************************************************
 * MacLCMetal360.h: Metal 360 projection (equirectangular, cubemap) and stereo
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

#ifndef MACLC_METAL_360_H
#define MACLC_METAL_360_H

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <CoreGraphics/CoreGraphics.h>

#include <vlc_common.h>
#include <vlc_es.h>
#include <vlc_viewpoint.h>
#include <vlc_vout.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * Computes the normalized sub-rectangle [0, 1] of a stereoscopic input texture
 * to sample for the given output stereo mode (SBS/TB, Left/Right).
 */
static inline __attribute__((unused))
CGRect MacLCStereoSourceRect(vlc_stereoscopic_mode_t stereoMode,
                            video_multiview_mode_t multiviewMode)
{
    if (stereoMode == VIDEO_STEREO_OUTPUT_SIDE_BY_SIDE)
        return CGRectMake(0.0, 0.0, 1.0, 1.0);

    if (stereoMode != VIDEO_STEREO_OUTPUT_LEFT_ONLY &&
        stereoMode != VIDEO_STEREO_OUTPUT_RIGHT_ONLY)
        return CGRectMake(0.0, 0.0, 1.0, 1.0);

    switch (multiviewMode) {
        case MULTIVIEW_STEREO_SBS:
            if (stereoMode == VIDEO_STEREO_OUTPUT_RIGHT_ONLY)
                return CGRectMake(0.5, 0.0, 0.5, 1.0);
            return CGRectMake(0.0, 0.0, 0.5, 1.0);
        case MULTIVIEW_STEREO_TB:
            if (stereoMode == VIDEO_STEREO_OUTPUT_RIGHT_ONLY)
                return CGRectMake(0.0, 0.5, 1.0, 0.5);
            return CGRectMake(0.0, 0.0, 1.0, 0.5);
        default:
            return CGRectMake(0.0, 0.0, 1.0, 1.0);
    }
}

/**
 * Metal 360° video rendering component for PROJECTION_MODE_EQUIRECTANGULAR
 * and PROJECTION_MODE_CUBEMAP_LAYOUT_STANDARD, supporting viewpoint rotation
 * and stereoscopic selection.
 */
@interface MacLCMetal360 : NSObject

- (nullable instancetype)initWithDevice:(id<MTLDevice>)device
                            pixelFormat:(MTLPixelFormat)format;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

- (void)setProjection:(video_projection_mode_t)mode;

- (void)setViewpoint:(const vlc_viewpoint_t *)viewpoint;

/**
 * Returns normalized source rectangle for stereo SBS/TB and left/right.
 */
- (CGRect)sourceRectForStereoMode:(vlc_stereoscopic_mode_t)stereoMode
                    multiviewMode:(video_multiview_mode_t)multiviewMode;

/**
 * Returns pixel-coordinate source rectangle for stereo SBS/TB and left/right.
 */
- (CGRect)sourceRectForStereoMode:(vlc_stereoscopic_mode_t)stereoMode
                    multiviewMode:(video_multiview_mode_t)multiviewMode
                     textureWidth:(size_t)width
                    textureHeight:(size_t)height;

/**
 * Draws the equirectangular or cubemap texture on a sphere/cube seen from the
 * viewpoint into the current render encoder, filling `destRect` (aspect sar).
 * Uses the same 128x128 sphere and 6-face cube meshes and matrices as renderer.c.
 */
- (void)encodeFrom:(id<MTLTexture>)input
     renderEncoder:(id<MTLRenderCommandEncoder>)encoder
          destRect:(CGRect)destRect
      drawableSize:(CGSize)drawableSize
               sar:(float)sar;

@end

NS_ASSUME_NONNULL_END

#endif /* MACLC_METAL_360_H */
