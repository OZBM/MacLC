/*****************************************************************************
 * MacLCFrameInterpolation.h: the motion interpolation settings, in one place
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

NS_ASSUME_NONNULL_BEGIN

/** Posted whenever interpolation is switched, or its engine or target change. */
extern NSString * const MacLCFrameInterpolationChangedNotification;

/** The method that makes up the in-between frames. Matches maclc-frc-engine. */
typedef NS_ENUM(NSInteger, MacLCFrameInterpolationEngine) {
    MacLCFrameInterpolationEngineAutomatic = 0,
    MacLCFrameInterpolationEngineQuality,
    MacLCFrameInterpolationEngineBalanced,
    MacLCFrameInterpolationEngineLowLatency,
    MacLCFrameInterpolationEngineMotion,
    MacLCFrameInterpolationEngineBlend,
    MacLCFrameInterpolationEngineSVP = 6,
    MacLCFrameInterpolationEngineRIFE = 7,
};

/** What frame rate to aim for. Matches maclc-frc-target. */
typedef NS_ENUM(NSInteger, MacLCFrameInterpolationTarget) {
    MacLCFrameInterpolationTargetDisplay = 0,
    MacLCFrameInterpolationTargetSixty,
    MacLCFrameInterpolationTargetHundredTwenty,
    MacLCFrameInterpolationTargetDouble,
};

/**
 * Motion interpolation as the interface sees it: whether it is on, how it is
 * set up, and what it would do to the video that is playing.
 *
 * Switching it on and off means editing the video filter chain, which is why
 * this does not look like an ordinary preference. Every change here is written
 * to the configuration and pushed to the video output that is running, so the
 * picture changes under the click rather than on the next file.
 */
@interface MacLCFrameInterpolation : NSObject

/** Whether the interpolating filter is in the video filter chain. */
@property (class, readonly, getter=isEnabled) BOOL enabled;

@property (class, readwrite) MacLCFrameInterpolationEngine engine;
@property (class, readwrite) MacLCFrameInterpolationTarget target;

@property (class, readwrite, getter=isRIFEEnabled) BOOL RIFEEnabled;   /* maclc-frc-rife */
@property (class, readwrite, copy, nullable) NSString *RIFEModelPath;  /* maclc-frc-rife-model */
@property (class, readwrite) float RIFEScale;                          /* maclc-frc-rife-scale */
@property (class, readwrite, copy, nullable) NSString *SVPPath;        /* maclc-frc-svp-path */

/** Nil when the engine can run here; otherwise one sentence naming what is
 *  missing and where it was looked for. */
+ (nullable NSString *)unavailabilityReasonForEngine:(MacLCFrameInterpolationEngine)engine;

+ (void)setEnabled:(BOOL)enabled;

/** Rebuilds the filter chain so a running filter picks up changed options.
 *  Does nothing when interpolation is off. The filter reads its options once,
 *  when it opens, so anything changed underneath it needs this. */
+ (void)restartIfRunning;

/** Human name of an engine, for menus. */
+ (NSString *)nameForEngine:(MacLCFrameInterpolationEngine)engine;
/** One line on what an engine costs and what it is for. */
+ (NSString *)summaryForEngine:(MacLCFrameInterpolationEngine)engine;
/** Human name of a target, for menus. */
+ (NSString *)nameForTarget:(MacLCFrameInterpolationTarget)target;

/**
 * The frame rate the current settings would produce out of \p sourceFrameRate.
 *
 * @return whole frames per second, or 0 when there is nothing to gain — an
 *         unknown source rate, or one the display already matches
 */
+ (unsigned)outputFrameRateForSourceFrameRate:(unsigned)sourceFrameRate;

@end

NS_ASSUME_NONNULL_END
