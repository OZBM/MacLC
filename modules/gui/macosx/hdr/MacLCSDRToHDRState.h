/*****************************************************************************
 * MacLCSDRToHDRState.h: single source of truth for MacLC's SDR to HDR GUI
 *****************************************************************************
 * Copyright (C) 2026 Hazen Studio
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

#import <Cocoa/Cocoa.h>

#include "../../video_output/apple/maclc_sdr2hdr.h"

NS_ASSUME_NONNULL_BEGIN

extern NSString * const MacLCSDRToHDRStateDidChangeNotification; // object = the state

typedef NS_ENUM(NSInteger, MacLCSDRToHDRQuality) {
    MacLCSDRToHDRQualityAuto = 0,
    MacLCSDRToHDRQualityFast = 1,
    MacLCSDRToHDRQualityBalanced = 2,
    MacLCSDRToHDRQualityHigh = 3,
    MacLCSDRToHDRQualityMaximum = 4,
};

@interface MacLCSDRToHDRState : NSObject

+ (instancetype)sharedState;

@property (nonatomic) BOOL enabled;                 // macosx-sdr-to-hdr
@property (nonatomic) MacLCSDRToHDRQuality quality; // macosx-sdr-to-hdr-quality
@property (nonatomic) float boost;                  // macosx-sdr-to-hdr-boost (1..16)
@property (nonatomic) float midtones;               // macosx-sdr-to-hdr-midtones (0..1)
@property (nonatomic) float saturation;             // macosx-sdr-to-hdr-saturation (0.5..1.5)
@property (nonatomic) NSInteger deband;             // macosx-sdr-to-hdr-deband (enum maclc_sdr2hdr_deband)
@property (nonatomic) BOOL protect;                 // macosx-sdr-to-hdr-protect

// Live, from the running vout (nil/0 when nothing plays):
@property (readonly, nullable) NSString *activeQualityName; // "fast", ..., "off"
@property (readonly) MacLCSDRToHDRQuality activeQuality;    // Auto if off/unknown
@property (readonly, nullable) NSString *reason;            // maclc_sdr2hdr_reason_name()
@property (readonly) float activePeakNits;
@property (readonly, getter=isComparing) BOOL comparing;

- (void)refresh;                  // re-read options and vout variables, post the notification if anything changed
- (void)setComparing:(BOOL)on;    // writes MACLC_SDR2HDR_VAR_COMPARE on the vout (never saved)

- (void)startPolling;
- (void)stopPolling;

+ (NSString *)displayNameForQuality:(MacLCSDRToHDRQuality)q;
+ (NSString *)summaryForQuality:(MacLCSDRToHDRQuality)q;
+ (nullable NSString *)explanationForReason:(nullable NSString *)reason; // A.4 phrases

@end

NS_ASSUME_NONNULL_END
