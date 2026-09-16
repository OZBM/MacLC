/*****************************************************************************
 * MacLCDisplayInfo.h: Display EDR and power capabilities
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

@class NSScreen;

NS_ASSUME_NONNULL_BEGIN

/**
 * Value object capturing display headroom, power state, and panel capabilities.
 */
@interface MacLCDisplayInfo : NSObject

@property (nonatomic, readonly, copy) NSString *localizedName;
@property (nonatomic, readonly) CGFloat potentialHeadroom;
@property (nonatomic, readonly) CGFloat currentHeadroom;
@property (nonatomic, readonly) CGFloat referenceHeadroom;
@property (nonatomic, readonly) BOOL onBattery;
@property (nonatomic, readonly) BOOL lowPowerMode;

@property (nonatomic, readonly) BOOL supportsHDR;
@property (nonatomic, readonly) BOOL referenceModeActive;

/** The EDR headroom video is mapped into: the current one once the screen
 *  shows extended range, the potential one before it does. */
@property (nonatomic, readonly) CGFloat effectiveHeadroom;

/** Brightest video luminance (cd/m², PQ) shown without clipping right now,
 *  with MACLC_HDR_REFERENCE_WHITE at SDR white. */
@property (nonatomic, readonly) CGFloat contentPeakNits;

/** The panel's peak luminance in cd/m² (1,600 on an XDR panel), 0 when the
 *  display has no extended range. macOS reports potential headroom relative
 *  to a 100 cd/m² white. */
@property (nonatomic, readonly) NSUInteger panelPeakNits;

/** Luminance of SDR white at the current brightness, in cd/m², 0 when the
 *  display has no extended range. */
@property (nonatomic, readonly) CGFloat sdrWhiteNits;

+ (instancetype)displayInfoForScreen:(nullable NSScreen *)screen;

- (instancetype)initWithLocalizedName:(NSString *)localizedName
                    potentialHeadroom:(CGFloat)potentialHeadroom
                      currentHeadroom:(CGFloat)currentHeadroom
                    referenceHeadroom:(CGFloat)referenceHeadroom
                            onBattery:(BOOL)onBattery
                         lowPowerMode:(BOOL)lowPowerMode NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
