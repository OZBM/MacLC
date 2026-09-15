/*****************************************************************************
 * MacLCHDRTypes.m: HDR presentation and picture mode types
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

#import "MacLCHDRTypes.h"

#if __has_include("extensions/NSString+Helpers.h")
#import "extensions/NSString+Helpers.h"
#elif __has_include("gui/macosx/extensions/NSString+Helpers.h")
#import "gui/macosx/extensions/NSString+Helpers.h"
#endif

#ifndef _NS
#define _NS(s) @(s)
#endif

NSString * const MacLCHDRStateDidChangeNotification = @"MacLCHDRStateDidChangeNotification";

MacLCHDRPresentation MacLCHDRPresentationFromString(NSString *string)
{
    if (string == nil) {
        return MacLCHDRPresentationAuto;
    }
    NSString *lower = [string lowercaseString];
    if ([lower isEqualToString:@"dolbyvision"]) {
        return MacLCHDRPresentationDolbyVision;
    }
    if ([lower isEqualToString:@"hdr10plus"]) {
        return MacLCHDRPresentationHDR10Plus;
    }
    if ([lower isEqualToString:@"hdr10"]) {
        return MacLCHDRPresentationHDR10;
    }
    if ([lower isEqualToString:@"hlg"]) {
        return MacLCHDRPresentationHLG;
    }
    if ([lower isEqualToString:@"sdr"]) {
        return MacLCHDRPresentationSDR;
    }
    return MacLCHDRPresentationAuto;
}

NSString *MacLCHDRPresentationToString(MacLCHDRPresentation presentation)
{
    switch (presentation) {
        case MacLCHDRPresentationDolbyVision:
            return @"dolbyvision";
        case MacLCHDRPresentationHDR10Plus:
            return @"hdr10plus";
        case MacLCHDRPresentationHDR10:
            return @"hdr10";
        case MacLCHDRPresentationHLG:
            return @"hlg";
        case MacLCHDRPresentationSDR:
            return @"sdr";
        case MacLCHDRPresentationAuto:
        default:
            return @"auto";
    }
}

MacLCHDRPictureMode MacLCHDRPictureModeFromString(NSString *string)
{
    if (string == nil) {
        return MacLCHDRPictureModeAuto;
    }
    NSString *lower = [string lowercaseString];
    if ([lower isEqualToString:@"accurate"]) {
        return MacLCHDRPictureModeAccurate;
    }
    if ([lower isEqualToString:@"balanced"]) {
        return MacLCHDRPictureModeBalanced;
    }
    if ([lower isEqualToString:@"bright"]) {
        return MacLCHDRPictureModeBright;
    }
    return MacLCHDRPictureModeAuto;
}

NSString *MacLCHDRPictureModeToString(MacLCHDRPictureMode pictureMode)
{
    switch (pictureMode) {
        case MacLCHDRPictureModeAccurate:
            return @"accurate";
        case MacLCHDRPictureModeBalanced:
            return @"balanced";
        case MacLCHDRPictureModeBright:
            return @"bright";
        case MacLCHDRPictureModeAuto:
        default:
            return @"auto";
    }
}

NSString *MacLCHDRPresentationDisplayName(MacLCHDRPresentation presentation)
{
    switch (presentation) {
        case MacLCHDRPresentationDolbyVision:
            return _NS("Dolby Vision");
        case MacLCHDRPresentationHDR10Plus:
            return _NS("HDR10+");
        case MacLCHDRPresentationHDR10:
            return _NS("HDR10");
        case MacLCHDRPresentationHLG:
            return _NS("HLG");
        case MacLCHDRPresentationSDR:
            return _NS("SDR");
        case MacLCHDRPresentationAuto:
        default:
            return _NS("Automatic");
    }
}

NSString *MacLCHDRPresentationBadgeTitle(MacLCHDRPresentation presentation)
{
    switch (presentation) {
        case MacLCHDRPresentationDolbyVision:
            return _NS("DOLBY VISION");
        case MacLCHDRPresentationHDR10Plus:
            return _NS("HDR10+");
        case MacLCHDRPresentationHDR10:
            return _NS("HDR10");
        case MacLCHDRPresentationHLG:
            return _NS("HLG");
        case MacLCHDRPresentationSDR:
            return _NS("SDR");
        case MacLCHDRPresentationAuto:
        default:
            return _NS("AUTO");
    }
}

NSString *MacLCHDRPresentationSummary(MacLCHDRPresentation presentation)
{
    switch (presentation) {
        case MacLCHDRPresentationDolbyVision:
            return _NS("Adjusts every scene to your display.");
        case MacLCHDRPresentationHDR10Plus:
            return _NS("Scene-by-scene brightness, open standard.");
        case MacLCHDRPresentationHDR10:
            return _NS("One tone curve for the whole video.");
        case MacLCHDRPresentationHLG:
            return _NS("Broadcast HDR that adapts to your display.");
        case MacLCHDRPresentationSDR:
            return _NS("Standard range. Calmest picture, least power.");
        case MacLCHDRPresentationAuto:
        default:
            return _NS("Selects the best presentation for your display.");
    }
}

NSString *MacLCHDRPictureModeSummary(MacLCHDRPictureMode pictureMode)
{
    switch (pictureMode) {
        case MacLCHDRPictureModeAccurate:
            return _NS("Faithful to the master. Can look dim in a bright room.");
        case MacLCHDRPictureModeBalanced:
            return _NS("Keeps highlights and mid-tones in proportion for this display.");
        case MacLCHDRPictureModeBright:
            return _NS("Lifts mid-tones and highlights. Bright details may clip, colours drift from the original grade, and it uses more power.");
        case MacLCHDRPictureModeAuto:
        default:
            return _NS("Selects the picture mode automatically based on display capabilities.");
    }
}
