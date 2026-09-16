/*****************************************************************************
 * MacLCToneCurveView.h: live plot of MacLC's HDR picture-mode curve
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

#import "hdr/MacLCHDRTypes.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * Shows what a picture mode does to the video, the way a colourist would
 * look at it: content luminance on the horizontal axis, the light the panel
 * emits on the vertical one (both logarithmic, in cd/m²).
 *
 * - the shaded band is the range the video actually uses (up to its peak);
 * - the dashed line is the panel's peak;
 * - the dotted diagonal is "shown exactly as mastered";
 * - the solid curve is the selected mode, evaluated with the same
 *   maclc_tonemap.h code the video output runs and scaled by the current
 *   SDR white (MACLC_HDR_REFERENCE_WHITE is shown there), so the plot is
 *   the truth.
 *
 * Changing the mode or the peaks morphs the curve (emphasized motion, or an
 * instant change under Reduce Motion).
 */
@interface MacLCToneCurveView : NSView

@property (nonatomic) MacLCHDRPictureMode pictureMode;
/** The video's peak, in cd/m². */
@property (nonatomic) CGFloat contentPeakNits;
/** The brightest video luminance the display shows now (MacLCDisplayInfo). */
@property (nonatomic) CGFloat displayPeakNits;
/** SDR white at the current brightness, in cd/m²; 0 plots video luminance
 *  instead of panel light. */
@property (nonatomic) CGFloat sdrWhiteNits;

/** Updates everything at once with a single morph. */
- (void)setPictureMode:(MacLCHDRPictureMode)mode
       contentPeakNits:(CGFloat)contentPeak
       displayPeakNits:(CGFloat)displayPeak
          sdrWhiteNits:(CGFloat)sdrWhite
              animated:(BOOL)animated;

@end

NS_ASSUME_NONNULL_END
