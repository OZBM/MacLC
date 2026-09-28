/*****************************************************************************
 * VLCHDRExpander.h: GPU dynamic-range expansion (SDR -> HDR) for Apple
 * platforms
 *****************************************************************************
 * Copyright (C) 2026 VLC authors and VideoLAN
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

#ifndef VLC_HDR_EXPANDER_H
#define VLC_HDR_EXPANDER_H

#import <Foundation/Foundation.h>
#import <CoreVideo/CoreVideo.h>
#import <Metal/Metal.h>

#include <vlc_common.h>
#include <vlc_es.h>
#include <vlc_tick.h>
#include "maclc_sdr2hdr.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * What one picture asks of the expander. Built by the video output from the
 * options of maclc_sdr2hdr.h, with Automatic already resolved.
 */
typedef struct
{
    enum maclc_sdr2hdr_quality quality; /* resolved: FAST, BALANCED, HIGH or MAXIMUM */
    float boost;        /* user peak, multiple of SDR white, [1, 16] */
    float midtones;     /* [0, 1] */
    float saturation;   /* [0.5, 1.5] */
    enum maclc_sdr2hdr_deband deband;
    bool protect;       /* protect subtitles and logos */
    float headroom;     /* display's current EDR headroom (>= 1) */
    vlc_tick_t date;    /* picture date (for time constants); VLC_TICK_INVALID if unknown */
} VLCHDRExpandParams;

/**
 * Predicts, from a thumbnail of the SDR picture, the grid of gains High and
 * Maximum slice at every pixel (see VLCHDRNetwork.h for the trained one).
 */
@protocol VLCHDRGridProducer <NSObject>
/* Grid geometry the producer writes: gridWidth x gridHeight cells, gridDepth
 * intensity bins, 3 channels (R, G, B) of half floats in [0, 1], laid out as
 * [y][x][bin][channel] (NHWC with C = depth * 3). A value is a gain as a
 * share of log(MACLC_SDR2HDR_P_TRAIN): 0 leaves the pixel alone, 1 multiplies
 * it by P_TRAIN; the expander then rolls the result off under the picture's
 * budget (maclc_sdr2hdr_grid_log_scale()). */
@property (nonatomic, readonly) NSUInteger gridWidth, gridHeight, gridDepth;
/* Thumbnail the producer wants: thumbnailSize x thumbnailSize, RGBA16Float,
 * non-linear R'G'B' of the SDR picture in [0, 1] (alpha 1), area-averaged. */
@property (nonatomic, readonly) NSUInteger thumbnailSize;
/* Encode the prediction into `commandBuffer`. `grid` is a shared MTLBuffer
 * of gridWidth*gridHeight*gridDepth*3 halves. Returns the command buffer the
 * expander must carry on encoding into: `commandBuffer` itself, or the one an
 * MPSCommandBuffer continued with after committing it (MPSGraph may do that,
 * on the same queue, so order is kept). nil if nothing could be encoded (the
 * expander then falls back to Balanced for this picture). */
- (nullable id<MTLCommandBuffer>)encodeGridForThumbnail:(id<MTLTexture>)thumbnail
                                               intoGrid:(id<MTLBuffer>)grid
                                          commandBuffer:(id<MTLCommandBuffer>)commandBuffer;
/* Which levels it serves (High only, or High and Maximum). */
- (BOOL)supportsQuality:(enum maclc_sdr2hdr_quality)quality;
@optional
/* Set by the expander before it asks for the geometry and the prediction of
 * a picture, for producers that hold one network per level. */
@property (nonatomic) enum maclc_sdr2hdr_quality currentQuality;
@end

/**
 * Turns an SDR picture into an extended-range one by expanding its highlights
 * into the display's EDR headroom, on the GPU, at one of the quality levels of
 * maclc_sdr2hdr.h:
 *
 * - Fast: one per-pixel curve (knee at 0.5 in linear light);
 * - Balanced: statistics per 8x8 cell, filtered in time, an area limiter, an
 *   edge-aware base intensity (self-guided filter) driving the gain so 8-bit
 *   steps are not amplified, debanding and subtitle/logo protection;
 * - High and Maximum: Balanced's analysis with a grid of gains predicted by
 *   the grid producer instead of Balanced's curve.
 *
 * The result is linear light in half floats with SDR white at 1.0 (times the
 * mid-tone lift) and BT.2020 primaries. The compositor shows such a picture
 * untouched, with 1.0 at the display's SDR white, which is where it shows the
 * white of the SDR picture itself. The source is linearised with the curve the
 * compositor uses for it (for BT.709: a 1.961 power law for Y'CbCr, the
 * inverse OETF for RGB), so what is not expanded looks exactly as plain SDR
 * playback shows it.
 *
 * Every method is safe to call from the video output thread, but a single
 * instance must not be used from two threads at once.
 */
@interface VLCHDRExpander : NSObject

/**
 * Creates an expander, or returns nil if the system has no usable Metal device
 * or the shaders fail to compile. Failure is not fatal: the caller should carry
 * on displaying the untouched SDR picture.
 *
 * \param obj object used for logging; not retained.
 */
+ (nullable instancetype)expanderForObject:(vlc_object_t *)obj;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

/**
 * Whether a picture of that CoreVideo format can be expanded. Formats that
 * cannot are passed through unchanged.
 */
- (BOOL)canExpandPixelFormat:(OSType)pixelFormat;

/**
 * Expands one picture.
 *
 * \return a new 64RGBAHalf pixel buffer the caller owns, holding linear
 *         BT.2020 light with SDR white at 1.0 and tagged as such, or NULL if
 *         the picture could not (or need not) be expanded, in which case the
 *         source must be displayed as-is.
 */
- (nullable CVPixelBufferRef)expandPixelBuffer:(CVPixelBufferRef)pixelBuffer
                                        format:(const video_format_t *)fmt
                                        params:(const VLCHDRExpandParams *)params
    CF_RETURNS_RETAINED;

/** Forget temporal state (seek, new file, format change, compare released). */
- (void)resetTemporalState;

/** The network behind High and Maximum; nil: they run as Balanced. */
@property (nonatomic, nullable) id<VLCHDRGridProducer> gridProducer;

/* What the last expandPixelBuffer: call did. */
@property (nonatomic, readonly) enum maclc_sdr2hdr_quality lastQuality; /* may be lower than asked: see lastFallback */
@property (nonatomic, readonly) BOOL lastFallback;      /* High/Max asked, no grid producer: Balanced ran */
@property (nonatomic, readonly) float lastPeakNits;     /* 100 * white level * budget: reference cd/m2 reached by full white */
@property (nonatomic, readonly) double lastGPUTimeMs;   /* GPUEndTime - GPUStartTime of the last command buffer */

@end

NS_ASSUME_NONNULL_END

#endif /* VLC_HDR_EXPANDER_H */
