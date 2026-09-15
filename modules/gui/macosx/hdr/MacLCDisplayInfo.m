/*****************************************************************************
 * MacLCDisplayInfo.m: Display EDR and power capabilities
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

#import "MacLCDisplayInfo.h"

#import <AppKit/NSScreen.h>
#import <IOKit/ps/IOPowerSources.h>
#include <math.h>

@implementation MacLCDisplayInfo

+ (instancetype)displayInfoForScreen:(nullable NSScreen *)screen
{
    NSString *localizedName = @"Display";
    CGFloat potentialHeadroom = 1.0;
    CGFloat currentHeadroom = 1.0;
    CGFloat referenceHeadroom = 0.0;

    if (screen != nil) {
        if (@available(macOS 10.15, *)) {
            if ([screen respondsToSelector:@selector(localizedName)] && screen.localizedName.length > 0) {
                localizedName = screen.localizedName;
            }
            if ([screen respondsToSelector:@selector(maximumPotentialExtendedDynamicRangeColorComponentValue)]) {
                potentialHeadroom = screen.maximumPotentialExtendedDynamicRangeColorComponentValue;
            }
            if ([screen respondsToSelector:@selector(maximumReferenceExtendedDynamicRangeColorComponentValue)]) {
                referenceHeadroom = screen.maximumReferenceExtendedDynamicRangeColorComponentValue;
            }
        }
        if (@available(macOS 10.11, *)) {
            if ([screen respondsToSelector:@selector(maximumExtendedDynamicRangeColorComponentValue)]) {
                currentHeadroom = screen.maximumExtendedDynamicRangeColorComponentValue;
            }
        }
    }

    BOOL onBattery = NO;
    CFTypeRef powerInfo = IOPSCopyPowerSourcesInfo();
    if (powerInfo != NULL) {
        CFStringRef powerSourceType = IOPSGetProvidingPowerSourceType(powerInfo);
        if (powerSourceType != NULL) {
            onBattery = (CFStringCompare(powerSourceType, CFSTR(kIOPMBatteryPowerKey), 0) == kCFCompareEqualTo);
        }
        CFRelease(powerInfo);
    }

    BOOL lowPowerMode = NO;
    if (@available(macOS 12.0, *)) {
        lowPowerMode = [NSProcessInfo processInfo].isLowPowerModeEnabled;
    }

    return [[self alloc] initWithLocalizedName:localizedName
                             potentialHeadroom:potentialHeadroom
                               currentHeadroom:currentHeadroom
                             referenceHeadroom:referenceHeadroom
                                     onBattery:onBattery
                                  lowPowerMode:lowPowerMode];
}

- (instancetype)initWithLocalizedName:(NSString *)localizedName
                    potentialHeadroom:(CGFloat)potentialHeadroom
                      currentHeadroom:(CGFloat)currentHeadroom
                    referenceHeadroom:(CGFloat)referenceHeadroom
                            onBattery:(BOOL)onBattery
                         lowPowerMode:(BOOL)lowPowerMode
{
    self = [super init];
    if (self) {
        _localizedName = [localizedName copy];
        _potentialHeadroom = potentialHeadroom;
        _currentHeadroom = currentHeadroom;
        _referenceHeadroom = referenceHeadroom;
        _onBattery = onBattery;
        _lowPowerMode = lowPowerMode;
    }
    return self;
}

- (BOOL)supportsHDR
{
    return self.potentialHeadroom > 1.0001;
}

- (BOOL)referenceModeActive
{
    return self.referenceHeadroom > 0.0;
}

- (CGFloat)contentPeakNits
{
    CGFloat targetHeadroom = self.supportsHDR ? MIN(self.potentialHeadroom, (CGFloat)4.0) : (CGFloat)1.0;
    CGFloat effectiveHeadroom = MAX(self.currentHeadroom, targetHeadroom);
    return effectiveHeadroom * (CGFloat)203.0;
}

- (NSUInteger)knownPanelPeakNits
{
    if (self.localizedName.length > 0 &&
        [self.localizedName rangeOfString:@"XDR" options:NSCaseInsensitiveSearch].location != NSNotFound) {
        return 1600;
    }
    return 0;
}

- (BOOL)isEqual:(id)object
{
    if (self == object) {
        return YES;
    }
    if (![object isKindOfClass:[MacLCDisplayInfo class]]) {
        return NO;
    }
    MacLCDisplayInfo *other = (MacLCDisplayInfo *)object;
    return [self.localizedName isEqualToString:other.localizedName] &&
           fabs(self.potentialHeadroom - other.potentialHeadroom) < 0.0001 &&
           fabs(self.currentHeadroom - other.currentHeadroom) < 0.0001 &&
           fabs(self.referenceHeadroom - other.referenceHeadroom) < 0.0001 &&
           self.onBattery == other.onBattery &&
           self.lowPowerMode == other.lowPowerMode;
}

- (NSUInteger)hash
{
    NSUInteger hash = self.localizedName.hash;
    hash = hash * 31 + (NSUInteger)(self.potentialHeadroom * 1000.0);
    hash = hash * 31 + (NSUInteger)(self.currentHeadroom * 1000.0);
    hash = hash * 31 + (NSUInteger)(self.referenceHeadroom * 1000.0);
    hash = hash * 31 + (self.onBattery ? 1 : 0);
    hash = hash * 31 + (self.lowPowerMode ? 1 : 0);
    return hash;
}

@end
