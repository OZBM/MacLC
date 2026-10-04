/*****************************************************************************
 * MacLCSoundPresets.m
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

#import "MacLCSoundPresets.h"

#include <math.h>

#ifndef _NS
#define _NS(s) @(s)
#endif

@implementation MacLCSoundPreset

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
              compressorMakeupGain:(float)compressorMakeupGain
{
    self = [super init];
    if (self) {
        _identifier = [identifier copy];
        _title = [title copy];
        _symbolName = [symbolName copy];
        _presetDescription = [description copy];
        _baseBands = [baseBands copy];
        _defaultIntensity = defaultIntensity;
        _baseDialogueAmount = baseDialogueAmount;
        _hasCompressor = hasCompressor;
        _compressorRMSPeak = compressorRMSPeak;
        _compressorAttack = compressorAttack;
        _compressorRelease = compressorRelease;
        _compressorThreshold = compressorThreshold;
        _compressorRatio = compressorRatio;
        _compressorKnee = compressorKnee;
        _compressorMakeupGain = compressorMakeupGain;
    }
    return self;
}

@end

@implementation MacLCSoundPresets

+ (NSArray<MacLCSoundPreset *> *)allPresets
{
    static NSArray<MacLCSoundPreset *> *presets = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        presets = @[
            [[MacLCSoundPreset alloc] initWithIdentifier:@"voice"
                                                   title:_NS("Voice Boost")
                                              symbolName:@"person.wave.2.fill"
                                             description:_NS("Makes dialogue louder and clearer without raising music and effects.")
                                               baseBands:@[@-6.0f, @-4.0f, @-1.0f, @-1.0f, @0.0f, @1.0f, @2.0f, @1.5f, @-1.0f, @-3.0f]
                                        defaultIntensity:0.7f
                                      baseDialogueAmount:1.0f
                                           hasCompressor:NO
                                       compressorRMSPeak:0.0f
                                        compressorAttack:0.0f
                                       compressorRelease:0.0f
                                     compressorThreshold:0.0f
                                         compressorRatio:1.0f
                                          compressorKnee:0.0f
                                    compressorMakeupGain:0.0f],

            [[MacLCSoundPreset alloc] initWithIdentifier:@"night"
                                                   title:_NS("Night")
                                              symbolName:@"moon.fill"
                                             description:_NS("Evens out loud and quiet moments so you can keep the volume low.")
                                               baseBands:@[@-8.0f, @-5.0f, @-1.0f, @-1.0f, @0.0f, @1.0f, @2.0f, @1.5f, @-1.0f, @-4.0f]
                                        defaultIntensity:0.7f
                                      baseDialogueAmount:0.8f
                                           hasCompressor:YES
                                       compressorRMSPeak:0.2f
                                        compressorAttack:15.0f
                                       compressorRelease:150.0f
                                     compressorThreshold:-24.0f
                                         compressorRatio:6.0f
                                          compressorKnee:4.0f
                                    compressorMakeupGain:8.0f],

            [[MacLCSoundPreset alloc] initWithIdentifier:@"cinema"
                                                   title:_NS("Cinema")
                                              symbolName:@"film.fill"
                                             description:_NS("Fuller bass and crisper detail for movies and series.")
                                               baseBands:@[@3.0f, @3.0f, @1.5f, @0.0f, @-0.5f, @0.0f, @1.0f, @2.0f, @2.5f, @2.0f]
                                        defaultIntensity:0.6f
                                      baseDialogueAmount:0.3f
                                           hasCompressor:NO
                                       compressorRMSPeak:0.0f
                                        compressorAttack:0.0f
                                       compressorRelease:0.0f
                                     compressorThreshold:0.0f
                                         compressorRatio:1.0f
                                          compressorKnee:0.0f
                                    compressorMakeupGain:0.0f],

            [[MacLCSoundPreset alloc] initWithIdentifier:@"music"
                                                   title:_NS("Music")
                                              symbolName:@"music.note"
                                             description:_NS("Livelier bass and treble for songs and concerts.")
                                               baseBands:@[@4.0f, @3.5f, @2.0f, @-0.5f, @-1.5f, @-1.0f, @0.0f, @2.0f, @3.5f, @4.0f]
                                        defaultIntensity:0.6f
                                      baseDialogueAmount:0.0f
                                           hasCompressor:NO
                                       compressorRMSPeak:0.0f
                                        compressorAttack:0.0f
                                       compressorRelease:0.0f
                                     compressorThreshold:0.0f
                                         compressorRatio:1.0f
                                          compressorKnee:0.0f
                                    compressorMakeupGain:0.0f],

            [[MacLCSoundPreset alloc] initWithIdentifier:@"bass"
                                                   title:_NS("Bass Boost")
                                              symbolName:@"speaker.wave.3.fill"
                                             description:_NS("Adds weight to the low end.")
                                               baseBands:@[@6.0f, @5.5f, @3.5f, @1.5f, @0.0f, @0.0f, @0.0f, @0.0f, @0.0f, @0.0f]
                                        defaultIntensity:0.6f
                                      baseDialogueAmount:0.0f
                                           hasCompressor:NO
                                       compressorRMSPeak:0.0f
                                        compressorAttack:0.0f
                                       compressorRelease:0.0f
                                     compressorThreshold:0.0f
                                         compressorRatio:1.0f
                                          compressorKnee:0.0f
                                    compressorMakeupGain:0.0f],

            [[MacLCSoundPreset alloc] initWithIdentifier:@"spoken"
                                                   title:_NS("Spoken Word")
                                              symbolName:@"mic.fill"
                                             description:_NS("Focuses on voices for podcasts, audiobooks and lectures.")
                                               baseBands:@[@-10.0f, @-6.0f, @1.0f, @-1.0f, @1.0f, @2.5f, @3.5f, @2.5f, @-1.5f, @-6.0f]
                                        defaultIntensity:0.7f
                                      baseDialogueAmount:0.5f
                                           hasCompressor:YES
                                       compressorRMSPeak:0.2f
                                        compressorAttack:20.0f
                                       compressorRelease:200.0f
                                     compressorThreshold:-20.0f
                                         compressorRatio:3.0f
                                          compressorKnee:4.0f
                                    compressorMakeupGain:4.0f],

            [[MacLCSoundPreset alloc] initWithIdentifier:@"headphones"
                                                   title:_NS("Headphones")
                                              symbolName:@"headphones"
                                             description:_NS("A balanced curve tuned for headphones and earbuds.")
                                               baseBands:@[@3.0f, @2.0f, @0.0f, @-1.0f, @0.0f, @1.0f, @2.0f, @-1.5f, @-2.0f, @1.5f]
                                        defaultIntensity:0.6f
                                      baseDialogueAmount:0.0f
                                           hasCompressor:NO
                                       compressorRMSPeak:0.0f
                                        compressorAttack:0.0f
                                       compressorRelease:0.0f
                                     compressorThreshold:0.0f
                                         compressorRatio:1.0f
                                          compressorKnee:0.0f
                                    compressorMakeupGain:0.0f],

            [[MacLCSoundPreset alloc] initWithIdentifier:@"speakers"
                                                   title:_NS("Small Speakers")
                                              symbolName:@"laptopcomputer"
                                             description:_NS("Brings out detail on laptop and other small speakers.")
                                               baseBands:@[@-8.0f, @-3.0f, @3.0f, @1.5f, @0.0f, @-1.0f, @1.5f, @3.5f, @4.0f, @3.0f]
                                        defaultIntensity:0.6f
                                      baseDialogueAmount:0.2f
                                           hasCompressor:NO
                                       compressorRMSPeak:0.0f
                                        compressorAttack:0.0f
                                       compressorRelease:0.0f
                                     compressorThreshold:0.0f
                                         compressorRatio:1.0f
                                          compressorKnee:0.0f
                                    compressorMakeupGain:0.0f],

            [[MacLCSoundPreset alloc] initWithIdentifier:@"custom"
                                                   title:_NS("Custom")
                                              symbolName:@"slider.vertical.3"
                                             description:_NS("Your own equalizer settings.")
                                               baseBands:@[@0.0f, @0.0f, @0.0f, @0.0f, @0.0f, @0.0f, @0.0f, @0.0f, @0.0f, @0.0f]
                                        defaultIntensity:1.0f
                                      baseDialogueAmount:0.0f
                                           hasCompressor:NO
                                       compressorRMSPeak:0.0f
                                        compressorAttack:0.0f
                                       compressorRelease:0.0f
                                     compressorThreshold:0.0f
                                         compressorRatio:1.0f
                                          compressorKnee:0.0f
                                    compressorMakeupGain:0.0f],
        ];
    });
    return presets;
}

+ (nullable MacLCSoundPreset *)presetForIdentifier:(NSString *)identifier
{
    if (identifier == nil) {
        return nil;
    }
    for (MacLCSoundPreset *preset in [self allPresets]) {
        if ([preset.identifier isEqualToString:identifier]) {
            return preset;
        }
    }
    return nil;
}

+ (NSArray<NSNumber *> *)scaledBandsWithBands:(NSArray<NSNumber *> *)bands
                                    intensity:(float)intensity
{
    float s = fmaxf(0.0f, fminf(1.0f, intensity));
    NSMutableArray<NSNumber *> *scaled = [NSMutableArray arrayWithCapacity:10];
    for (NSUInteger i = 0; i < 10; i++) {
        float val = (i < bands.count) ? bands[i].floatValue : 0.0f;
        float result = val * s;
        if (fabsf(result) < 1e-5f) {
            result = 0.0f;
        }
        [scaled addObject:@(result)];
    }
    return [scaled copy];
}

+ (NSArray<NSNumber *> *)scaledBandsForPreset:(MacLCSoundPreset *)preset
                                    intensity:(float)intensity
{
    if ([preset.identifier isEqualToString:@"custom"]) {
        return [self scaledBandsWithBands:preset.baseBands intensity:1.0f];
    }
    return [self scaledBandsWithBands:preset.baseBands intensity:intensity];
}

+ (float)scaledDialogueAmountForPreset:(MacLCSoundPreset *)preset
                             intensity:(float)intensity
{
    float s = fmaxf(0.0f, fminf(1.0f, intensity));
    return preset.baseDialogueAmount * s;
}

+ (float)scaledCompressorRatioForPreset:(MacLCSoundPreset *)preset
                              intensity:(float)intensity
{
    if (!preset.hasCompressor) {
        return 1.0f;
    }
    float s = fmaxf(0.0f, fminf(1.0f, intensity));
    return 1.0f + (preset.compressorRatio - 1.0f) * s;
}

+ (float)scaledCompressorMakeupForPreset:(MacLCSoundPreset *)preset
                               intensity:(float)intensity
{
    if (!preset.hasCompressor) {
        return 0.0f;
    }
    float s = fmaxf(0.0f, fminf(1.0f, intensity));
    return preset.compressorMakeupGain * s;
}

+ (float)calculatePreampForBands:(NSArray<NSNumber *> *)bands
{
    float maxBand = 0.0f;
    BOOL hasValue = NO;
    for (NSUInteger i = 0; i < bands.count && i < 10; i++) {
        float b = bands[i].floatValue;
        if (!hasValue || b > maxBand) {
            maxBand = b;
            hasValue = YES;
        }
    }
    float peak = fmaxf(0.0f, maxBand);

    BOOL adjacentBoost = NO;
    for (NSUInteger i = 0; i + 1 < bands.count && i < 9; i++) {
        if (bands[i].floatValue > 0.0f && bands[i + 1].floatValue > 0.0f) {
            adjacentBoost = YES;
            break;
        }
    }

    float preamp = 12.0f - peak - (adjacentBoost ? 1.0f : 0.0f);
    if (preamp < -20.0f) {
        preamp = -20.0f;
    } else if (preamp > 20.0f) {
        preamp = 20.0f;
    }
    return preamp;
}

+ (NSString *)formatBandsString:(NSArray<NSNumber *> *)bands
{
    NSMutableArray<NSString *> *parts = [NSMutableArray arrayWithCapacity:10];
    for (NSUInteger i = 0; i < 10; i++) {
        float val = (i < bands.count) ? bands[i].floatValue : 0.0f;
        if (val < -20.0f) {
            val = -20.0f;
        } else if (val > 20.0f) {
            val = 20.0f;
        }
        if (fabsf(val) < 1e-5f) {
            val = 0.0f;
        }
        [parts addObject:[NSString stringWithFormat:@"%.1f", val]];
    }
    return [parts componentsJoinedByString:@" "];
}

+ (NSString *)filterStringForEnablingPreset:(MacLCSoundPreset *)preset
                                  intensity:(float)intensity
                        currentFilterString:(nullable NSString *)currentString
                               ownedFilters:(out NSArray<NSString *> * _Nullable * _Nullable)outOwnedFilters
{
    NSMutableArray<NSString *> *userFilters = [NSMutableArray array];
    if (currentString.length > 0) {
        NSArray<NSString *> *tokens = [currentString componentsSeparatedByString:@":"];
        for (NSString *token in tokens) {
            NSString *trimmed = [token stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            if (trimmed.length == 0) {
                continue;
            }
            if ([trimmed isEqualToString:@"equalizer"] ||
                [trimmed isEqualToString:@"compressor"] ||
                [trimmed isEqualToString:@"maclc_dialogue"] ||
                [trimmed isEqualToString:@"limiter"]) {
                continue;
            }
            [userFilters addObject:trimmed];
        }
    }

    NSMutableArray<NSString *> *owned = [NSMutableArray array];
    NSMutableArray<NSString *> *resultFilters = [NSMutableArray array];

    // 1. Equalizer is always first
    [resultFilters addObject:@"equalizer"];
    [owned addObject:@"equalizer"];

    // 2. User filters kept in their original order
    [resultFilters addObjectsFromArray:userFilters];

    // 3. Compressor (only if preset uses it)
    if (preset.hasCompressor) {
        [resultFilters addObject:@"compressor"];
        [owned addObject:@"compressor"];
    }

    // 4. maclc_dialogue whenever the preset uses it, even at intensity 0: changing
    //    the filter list rebuilds the chain (audible gap, latency change).
    if (preset.baseDialogueAmount > 0.0f) {
        [resultFilters addObject:@"maclc_dialogue"];
        [owned addObject:@"maclc_dialogue"];
    }

    // 5. Safety limiter
    [resultFilters addObject:@"limiter"];
    [owned addObject:@"limiter"];

    if (outOwnedFilters != NULL) {
        *outOwnedFilters = [owned copy];
    }
    return [resultFilters componentsJoinedByString:@":"];
}

+ (NSString *)filterStringForDisablingCurrentFilterString:(nullable NSString *)currentString
                                             ownedFilters:(nullable NSArray<NSString *> *)ownedFilters
{
    if (currentString.length == 0) {
        return @"";
    }
    NSSet<NSString *> *ownedSet = [NSSet setWithArray:ownedFilters ?: @[]];
    NSArray<NSString *> *tokens = [currentString componentsSeparatedByString:@":"];
    NSMutableArray<NSString *> *remaining = [NSMutableArray array];
    for (NSString *token in tokens) {
        NSString *trimmed = [token stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (trimmed.length == 0) {
            continue;
        }
        if ([ownedSet containsObject:trimmed]) {
            continue;
        }
        [remaining addObject:trimmed];
    }
    return [remaining componentsJoinedByString:@":"];
}

@end
