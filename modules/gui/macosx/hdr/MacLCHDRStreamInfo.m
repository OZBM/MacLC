/*****************************************************************************
 * MacLCHDRStreamInfo.m: Immutable snapshot of video stream HDR metadata
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

#import "MacLCHDRStreamInfo.h"

#include <math.h>
#include <vlc_fourcc.h>

#include "../../video_output/apple/maclc_hdr_vars.h"

@implementation MacLCHDRStreamInfo

@synthesize availablePresentations = _availablePresentations;

+ (instancetype)streamInfoWithVideoFormat:(nullable const video_format_t *)fmt
                           hdr10PlusSeen:(BOOL)seen
{
    if (fmt == NULL) {
        return [[self alloc] initWithTransfer:TRANSFER_FUNC_UNDEF
                                    primaries:COLOR_PRIMARIES_UNDEF
                                     bitDepth:8
                                    pixelSize:NSZeroSize
                             masteringPeakNits:0.0f
                              masteringMinNits:0.0f
                                       maxCLL:0
                                      maxFALL:0
                                  doviProfile:-1
                                    doviLevel:0
                                   doviHasRPU:NO
                                    doviHasEL:NO
                                    doviHasBL:NO
                                hdr10PlusSeen:seen];
    }

    CGFloat width = fmt->i_visible_width > 0 ? (CGFloat)fmt->i_visible_width : (CGFloat)fmt->i_width;
    CGFloat height = fmt->i_visible_height > 0 ? (CGFloat)fmt->i_visible_height : (CGFloat)fmt->i_height;
    NSSize pixelSize = NSMakeSize(width, height);

    // Mastering max and min luminance in VLC core are in units of 0.0001 cd/m² (nits).
    float masteringPeakNits = fmt->mastering.max_luminance > 0 ? ((float)fmt->mastering.max_luminance / 10000.0f) : 0.0f;
    float masteringMinNits = fmt->mastering.min_luminance > 0 ? ((float)fmt->mastering.min_luminance / 10000.0f) : 0.0f;

    NSUInteger maxCLL = (NSUInteger)fmt->lighting.MaxCLL;
    NSUInteger maxFALL = (NSUInteger)fmt->lighting.MaxFALL;

    NSInteger doviProfile = -1;
    NSInteger doviLevel = 0;
    BOOL doviHasRPU = NO;
    BOOL doviHasEL = NO;
    BOOL doviHasBL = NO;

    if (fmt->dovi.version_major > 0 || fmt->dovi.rpu_present || fmt->dovi.profile > 0) {
        doviProfile = (NSInteger)fmt->dovi.profile;
        doviLevel = (NSInteger)fmt->dovi.level;
        doviHasRPU = fmt->dovi.rpu_present != 0;
        doviHasEL = fmt->dovi.el_present != 0;
        doviHasBL = fmt->dovi.bl_present != 0;
    }

    NSUInteger bitDepth = 8;
    const vlc_chroma_description_t *desc = vlc_fourcc_GetChromaDescription(fmt->i_chroma);
    if (desc != NULL && desc->pixel_bits > 0) {
        bitDepth = (desc->plane_count == 1 && desc->pixel_size > 0) ? (desc->pixel_bits / desc->pixel_size) : desc->pixel_bits;
    } else if (fmt->transfer == TRANSFER_FUNC_SMPTE_ST2084 || fmt->transfer == TRANSFER_FUNC_HLG || doviProfile >= 0) {
        bitDepth = 10;
    }

    return [[self alloc] initWithTransfer:fmt->transfer
                                primaries:fmt->primaries
                                 bitDepth:bitDepth
                                pixelSize:pixelSize
                         masteringPeakNits:masteringPeakNits
                          masteringMinNits:masteringMinNits
                                   maxCLL:maxCLL
                                  maxFALL:maxFALL
                              doviProfile:doviProfile
                                doviLevel:doviLevel
                               doviHasRPU:doviHasRPU
                                doviHasEL:doviHasEL
                                doviHasBL:doviHasBL
                            hdr10PlusSeen:seen];
}

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
                   hdr10PlusSeen:(BOOL)hdr10PlusSeen
{
    self = [super init];
    if (self) {
        _transfer = transfer;
        _primaries = primaries;
        _bitDepth = bitDepth;
        _pixelSize = pixelSize;
        _masteringPeakNits = masteringPeakNits;
        _masteringMinNits = masteringMinNits;
        _maxCLL = maxCLL;
        _maxFALL = maxFALL;
        _doviProfile = doviProfile;
        _doviLevel = doviLevel;
        _doviHasRPU = doviHasRPU;
        _doviHasEL = doviHasEL;
        _doviHasBL = doviHasBL;
        _hdr10PlusSeen = hdr10PlusSeen;

        NSMutableArray<NSNumber *> *presentations = [NSMutableArray array];
        BOOL isHDRStream = (transfer == TRANSFER_FUNC_SMPTE_ST2084 ||
                            transfer == TRANSFER_FUNC_HLG ||
                            doviProfile >= 0);

        if (isHDRStream) {
            if (doviProfile >= 0 && doviHasRPU) {
                [presentations addObject:@(MacLCHDRPresentationDolbyVision)];
            }
            if (hdr10PlusSeen && transfer == TRANSFER_FUNC_SMPTE_ST2084) {
                [presentations addObject:@(MacLCHDRPresentationHDR10Plus)];
            }
            if (transfer == TRANSFER_FUNC_SMPTE_ST2084 && doviProfile != 5) {
                [presentations addObject:@(MacLCHDRPresentationHDR10)];
            }
            if (transfer == TRANSFER_FUNC_HLG) {
                [presentations addObject:@(MacLCHDRPresentationHLG)];
            }
            [presentations addObject:@(MacLCHDRPresentationSDR)];
        } else {
            [presentations addObject:@(MacLCHDRPresentationSDR)];
        }
        _availablePresentations = [presentations copy];
    }
    return self;
}

- (BOOL)isHDR
{
    return (self.transfer == TRANSFER_FUNC_SMPTE_ST2084 ||
            self.transfer == TRANSFER_FUNC_HLG ||
            self.doviProfile >= 0);
}

- (CGFloat)contentPeakNits
{
    /* Same numbers as the video outputs use for "auto". */
    const bool isHDR = self.transfer == TRANSFER_FUNC_SMPTE_ST2084 ||
                       self.transfer == TRANSFER_FUNC_HLG ||
                       self.doviProfile >= 0;
    return (CGFloat)maclc_hdr_content_peak((unsigned)self.maxCLL,
                                           (unsigned)lroundf(self.masteringPeakNits * 10000.0f),
                                           isHDR);
}

- (BOOL)isEqual:(id)object
{
    if (self == object) {
        return YES;
    }
    if (![object isKindOfClass:[MacLCHDRStreamInfo class]]) {
        return NO;
    }
    MacLCHDRStreamInfo *other = (MacLCHDRStreamInfo *)object;
    return self.transfer == other.transfer &&
           self.primaries == other.primaries &&
           self.bitDepth == other.bitDepth &&
           NSEqualSizes(self.pixelSize, other.pixelSize) &&
           fabsf(self.masteringPeakNits - other.masteringPeakNits) < 0.001f &&
           fabsf(self.masteringMinNits - other.masteringMinNits) < 0.0001f &&
           self.maxCLL == other.maxCLL &&
           self.maxFALL == other.maxFALL &&
           self.doviProfile == other.doviProfile &&
           self.doviLevel == other.doviLevel &&
           self.doviHasRPU == other.doviHasRPU &&
           self.doviHasEL == other.doviHasEL &&
           self.doviHasBL == other.doviHasBL &&
           self.hdr10PlusSeen == other.hdr10PlusSeen;
}

- (NSUInteger)hash
{
    NSUInteger hash = (NSUInteger)self.transfer;
    hash = hash * 31 + (NSUInteger)self.primaries;
    hash = hash * 31 + self.bitDepth;
    hash = hash * 31 + (NSUInteger)self.pixelSize.width;
    hash = hash * 31 + (NSUInteger)self.pixelSize.height;
    hash = hash * 31 + (NSUInteger)self.maxCLL;
    hash = hash * 31 + (NSUInteger)(self.doviProfile + 1);
    hash = hash * 31 + (self.doviHasRPU ? 1 : 0);
    hash = hash * 31 + (self.hdr10PlusSeen ? 1 : 0);
    return hash;
}

@end
