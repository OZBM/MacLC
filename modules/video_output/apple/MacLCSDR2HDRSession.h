/*****************************************************************************
 * MacLCSDR2HDRSession.h: shared SDR to HDR expansion session helper
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

#ifndef MACLC_SDR2HDR_SESSION_H
#define MACLC_SDR2HDR_SESSION_H

#import <Foundation/Foundation.h>
#import <CoreVideo/CoreVideo.h>

#include <vlc_common.h>
#include <vlc_es.h>
#include <vlc_vout_display.h>
#include "maclc_sdr2hdr.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * Encapsulates the SDR to HDR expansion session for a macOS video output display,
 * managing option variables, quality-level resolution, environment tracking,
 * GPU-time guarding, and state publishing.
 */
@interface MacLCSDR2HDRSession : NSObject

/**
 * Creates an SDR to HDR session for the given video output display.
 * Creates settings variables on vd and on the parent vout with callbacks,
 * the hold-to-compare variable, and published ACTIVE/REASON/PEAK variables.
 */
+ (nullable instancetype)sessionForDisplay:(vout_display_t *)vd;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

/**
 * Removes callbacks and destroys variables on vd and on the parent vout.
 */
- (void)close;

/**
 * Expands an SDR picture into the display's headroom if enabled and conditions allow.
 *
 * \param pb the source SDR pixel buffer.
 * \param fmt format of the picture; retagged to linear BT.2020 on expansion.
 * \param h the display's effective EDR headroom.
 * \param date presentation date of the picture (for time constants).
 * \param hdr whether the source stream is already HDR.
 * \param edr whether the display output is currently in EDR mode.
 * \return a retained 64RGBAHalf pixel buffer holding linear BT.2020 light, or NULL.
 */
- (nullable CVPixelBufferRef)expandIfNeeded:(CVPixelBufferRef)pb
                                     format:(video_format_t *)fmt
                                   headroom:(float)h
                                       date:(vlc_tick_t)date
                                sourceIsHDR:(BOOL)hdr
                                        edr:(BOOL)edr
    CF_RETURNS_RETAINED;

/**
 * Resets temporal filtering and scene state (called on seek, stream change, or compare release).
 */
- (void)resetTemporalState;

@property (nonatomic, readonly) enum maclc_sdr2hdr_quality activeQuality;
@property (nonatomic, readonly) enum maclc_sdr2hdr_reason activeReason;
@property (nonatomic, readonly) float activePeakNits;

@end

NS_ASSUME_NONNULL_END

#endif /* MACLC_SDR2HDR_SESSION_H */
