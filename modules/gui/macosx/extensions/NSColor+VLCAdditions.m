/*****************************************************************************
 * NSColor+VLCAdditions.m: MacOS X interface module
 *****************************************************************************
 * Copyright (C) 2019 VLC authors and VideoLAN
 *
 * Authors: Felix Paul Kühne <fkuehne # videolan -dot- org>
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

#import "NSColor+VLCAdditions.h"

#import "theme/MacLCDesign.h"

@implementation NSColor (VLCAdditions)

+ (NSColor *)VLCAccentColor
{
    return MacLCDesign.accent;
}

+ (NSColor *)VLCOrangeElementColor
{
    return MacLCDesign.accent;
}

+ (NSColor *)VLCSubtlerAccentColor
{
    return [MacLCDesign.accent colorWithAlphaComponent:0.8];
}

+ (NSColor *)VLClibrarySubtitleColor
{
    return MacLCDesign.secondaryLabel;
}

+ (NSColor *)VLClibraryAnnotationColor
{
    return MacLCDesign.primaryLabel;
}

+ (NSColor *)VLClibraryAnnotationBackgroundColor
{
    return [MacLCDesign.controlBackground colorWithAlphaComponent:0.2];
}

+ (NSColor *)VLClibrarySeparatorLightColor
{
    return MacLCDesign.separator;
}

+ (NSColor *)VLClibrarySeparatorDarkColor
{
    return MacLCDesign.separator;
}

+ (NSColor *)VLClibraryProgressIndicatorBackgroundColor
{
    return MacLCDesign.scrubberTrack;
}

+ (NSColor *)VLCSliderFillColor
{
    return MacLCDesign.scrubberFill;
}

+ (NSColor *)VLCSliderLightBackgroundColor
{
    return MacLCDesign.scrubberTrack;
}

+ (NSColor *)VLCSliderDarkBackgroundColor
{
    return MacLCDesign.scrubberTrack;
}

+ (NSColor *)VLCLightSubtleBorderColor
{
    return MacLCDesign.separator;
}

+ (NSColor *)VLCDarkSubtleBorderColor
{
    return MacLCDesign.separator;
}

+ (NSColor *)VLCSubtleBorderColor
{
    return MacLCDesign.separator;
}

@end
