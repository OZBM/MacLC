/*****************************************************************************
 * MacLCHDRTypes.h: HDR presentation and picture mode types
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

NS_ASSUME_NONNULL_BEGIN

/**
 * HDR presentation formats supported by MacLC.
 */
typedef NS_ENUM(NSInteger, MacLCHDRPresentation) {
    MacLCHDRPresentationAuto = 0,
    MacLCHDRPresentationDolbyVision,
    MacLCHDRPresentationHDR10Plus,
    MacLCHDRPresentationHDR10,
    MacLCHDRPresentationHLG,
    MacLCHDRPresentationSDR,
};

/**
 * HDR picture rendering modes for PQ content.
 */
typedef NS_ENUM(NSInteger, MacLCHDRPictureMode) {
    MacLCHDRPictureModeAuto = 0,
    MacLCHDRPictureModeAccurate,
    MacLCHDRPictureModeBalanced,
    MacLCHDRPictureModeBright,
};

/**
 * Notification posted when the active HDR presentation, picture mode, stream, display, or recommendation changes.
 */
extern NSString * const MacLCHDRStateDidChangeNotification;

/**
 * Converts a string configuration value to MacLCHDRPresentation.
 * Vocabulary: "auto", "dolbyvision", "hdr10plus", "hdr10", "hlg", "sdr".
 */
MacLCHDRPresentation MacLCHDRPresentationFromString(NSString *string);

/**
 * Converts a MacLCHDRPresentation to its string configuration value.
 */
NSString *MacLCHDRPresentationToString(MacLCHDRPresentation presentation);

/**
 * Converts a string configuration value to MacLCHDRPictureMode.
 * Vocabulary: "auto", "accurate", "balanced", "bright".
 */
MacLCHDRPictureMode MacLCHDRPictureModeFromString(NSString *string);

/**
 * Converts a MacLCHDRPictureMode to its string configuration value.
 */
NSString *MacLCHDRPictureModeToString(MacLCHDRPictureMode pictureMode);

/**
 * Returns the localized user-visible presentation display name.
 * e.g. "Dolby Vision", "HDR10+", "HDR10", "HLG", "SDR", "Automatic".
 */
NSString *MacLCHDRPresentationDisplayName(MacLCHDRPresentation presentation);

/**
 * Returns the short badge title for the presentation.
 * e.g. "DOLBY VISION", "HDR10+", "HDR10", "HLG", "SDR".
 */
NSString *MacLCHDRPresentationBadgeTitle(MacLCHDRPresentation presentation);

/**
 * Returns the one-line description of the presentation (DESIGN_SPEC §10.4).
 */
NSString *MacLCHDRPresentationSummary(MacLCHDRPresentation presentation);

/**
 * Returns the one-line description of the picture mode (DESIGN_SPEC §10.4).
 */
NSString *MacLCHDRPictureModeSummary(MacLCHDRPictureMode pictureMode);

NS_ASSUME_NONNULL_END
