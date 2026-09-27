/*****************************************************************************
 * MacLCLibraryFormatting.m: counts and durations as the library writes them
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

#import "medialib/MacLCLibraryFormatting.h"

#import <Cocoa/Cocoa.h>

#import "extensions/NSString+Helpers.h"

NSString *MacLCCountString(NSUInteger count, NSString *singular, NSString *plural)
{
    static NSNumberFormatter *formatter;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        formatter = [[NSNumberFormatter alloc] init];
        formatter.numberStyle = NSNumberFormatterDecimalStyle;
    });
    NSString * const number = [formatter stringFromNumber:@(count)] ?: [NSString stringWithFormat:@"%lu", (unsigned long)count];
    return [NSString stringWithFormat:@"%@ %@", number, count == 1 ? singular : plural];
}

NSString *MacLCDurationString(int64_t milliseconds)
{
    if (milliseconds <= 0) {
        return @"";
    }
    if (milliseconds < 60000) {
        return _NS("Less than a minute");
    }
    static NSDateComponentsFormatter *formatter;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        formatter = [[NSDateComponentsFormatter alloc] init];
        formatter.unitsStyle = NSDateComponentsFormatterUnitsStyleShort;
        formatter.allowedUnits = NSCalendarUnitHour | NSCalendarUnitMinute;
        formatter.zeroFormattingBehavior = NSDateComponentsFormatterZeroFormattingBehaviorDropAll;
    });
    return [formatter stringFromTimeInterval:(NSTimeInterval)(milliseconds / 1000)] ?: @"";
}

NSString *MacLCJoinedDetails(NSArray<NSString *> *parts)
{
    NSMutableArray<NSString *> * const kept = [NSMutableArray arrayWithCapacity:parts.count];
    for (NSString * const part in parts) {
        if (part.length > 0) {
            [kept addObject:part];
        }
    }
    return [kept componentsJoinedByString:@" · "];
}
