/*****************************************************************************
 * MacLCHDRStreamInfo.h: Immutable snapshot of video stream HDR metadata
 *****************************************************************************
 * Copyright (C) 2026 Hazen Studio
 *
 * Authors: MacLC Video Engineering Team
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston MA 02110-1301, USA.
 *****************************************************************************/

#import <Foundation/Foundation.h>

#include <vlc_common.h>
#include <vlc_es.h>

#import "MacLCHDRTypes.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * Immutable snapshot of video stream HDR properties and metadata.
 */
@interface MacLCHDRStreamInfo : NSObject

@property (nonatomic, readonly) video_transfer_func_t transfer;
@property (nonatomic, readonly) video_color_primaries_t primaries;
@property (nonatomic, readonly) NSUInteger bitDepth;
@property (nonatomic, readonly) NSSize pixelSize;
@property (nonatomic, readonly) float masteringPeakNits;
@property (nonatomic, readonly) float masteringMinNits;
@property (nonatomic, readonly) NSUInteger maxCLL;
@property (nonatomic, readonly) NSUInteger maxFALL;
@property (nonatomic, readonly) NSInteger doviProfile;
@property (nonatomic, readonly) NSInteger doviLevel;
@property (nonatomic, readonly) BOOL doviHasRPU;
@property (nonatomic, readonly) BOOL doviHasEL;
@property (nonatomic, readonly) BOOL doviHasBL;
@property (nonatomic, readonly) BOOL hdr10PlusSeen;

@property (nonatomic, readonly) BOOL isHDR;
@property (nonatomic, readonly) CGFloat contentPeakNits;
@property (nonatomic, readonly, copy) NSArray<NSNumber *> *availablePresentations;

+ (instancetype)streamInfoWithVideoFormat:(nullable const video_format_t *)fmt
                           hdr10PlusSeen:(BOOL)seen;

- (instancetype)initWithTransfer:(video_transfer_func_t)transfer
                       primaries:(video_color_primaries_t)primaries
                        bitDepth:(NSUInteger)bitDepth
                       pixelSize:(NSSize)pixelSize
                masteringPeakNits:(float)masteringPeakNits
                 masteringMinNits:(float)masteringMinNits
                          maxCLL:(NSUInteger)maxCLL
                         maxFALL:(NSUInteger)maxFALL
                     doviProfile:(NSInteger)doviProfile
                       doviLevel:(NSInteger)doviLevel
                      doviHasRPU:(BOOL)doviHasRPU
                       doviHasEL:(BOOL)doviHasEL
                       doviHasBL:(BOOL)doviHasBL
                   hdr10PlusSeen:(BOOL)hdr10PlusSeen NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
