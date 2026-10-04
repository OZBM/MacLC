/*****************************************************************************
 * MacLCSoundPresets.h
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

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface MacLCSoundPreset : NSObject

@property (nonatomic, readonly, copy) NSString *identifier;
@property (nonatomic, readonly, copy) NSString *title;
@property (nonatomic, readonly, copy) NSString *symbolName;
@property (nonatomic, readonly, copy) NSString *presetDescription;
@property (nonatomic, readonly, copy) NSArray<NSNumber *> *baseBands;
@property (nonatomic, readonly) float defaultIntensity;
@property (nonatomic, readonly) float baseDialogueAmount;
@property (nonatomic, readonly) BOOL hasCompressor;

@property (nonatomic, readonly) float compressorRMSPeak;
@property (nonatomic, readonly) float compressorAttack;
@property (nonatomic, readonly) float compressorRelease;
@property (nonatomic, readonly) float compressorThreshold;
@property (nonatomic, readonly) float compressorRatio;
@property (nonatomic, readonly) float compressorKnee;
@property (nonatomic, readonly) float compressorMakeupGain;

- (instancetype)initWithIdentifier:(NSString *)identifier
                             title:(NSString *)title
                        symbolName:(NSString *)symbolName
                       description:(NSString *)description
                         baseBands:(NSArray<NSNumber *> *)baseBands
                  defaultIntensity:(float)defaultIntensity
                baseDialogueAmount:(float)baseDialogueAmount
                     hasCompressor:(BOOL)hasCompressor
                 compressorRMSPeak:(float)compressorRMSPeak
                  compressorAttack:(float)compressorAttack
                 compressorRelease:(float)compressorRelease
               compressorThreshold:(float)compressorThreshold
                   compressorRatio:(float)compressorRatio
                    compressorKnee:(float)compressorKnee
              compressorMakeupGain:(float)compressorMakeupGain NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

@end

@interface MacLCSoundPresets : NSObject

@property (class, readonly) NSArray<MacLCSoundPreset *> *allPresets;

+ (nullable MacLCSoundPreset *)presetForIdentifier:(NSString *)identifier;

+ (NSArray<NSNumber *> *)scaledBandsForPreset:(MacLCSoundPreset *)preset
                                    intensity:(float)intensity;

+ (NSArray<NSNumber *> *)scaledBandsWithBands:(NSArray<NSNumber *> *)bands
                                    intensity:(float)intensity;

+ (float)scaledDialogueAmountForPreset:(MacLCSoundPreset *)preset
                             intensity:(float)intensity;

+ (float)scaledCompressorRatioForPreset:(MacLCSoundPreset *)preset
                              intensity:(float)intensity;

+ (float)scaledCompressorMakeupForPreset:(MacLCSoundPreset *)preset
                               intensity:(float)intensity;

+ (float)calculatePreampForBands:(NSArray<NSNumber *> *)bands;

+ (NSString *)formatBandsString:(NSArray<NSNumber *> *)bands;

+ (NSString *)filterStringForEnablingPreset:(MacLCSoundPreset *)preset
                                  intensity:(float)intensity
                        currentFilterString:(nullable NSString *)currentString
                               ownedFilters:(out NSArray<NSString *> * _Nullable * _Nullable)outOwnedFilters;

+ (NSString *)filterStringForDisablingCurrentFilterString:(nullable NSString *)currentString
                                             ownedFilters:(nullable NSArray<NSString *> *)ownedFilters;

@end

NS_ASSUME_NONNULL_END
