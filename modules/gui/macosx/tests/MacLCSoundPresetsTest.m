/*****************************************************************************
 * MacLCSoundPresetsTest.m
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

#if __has_include(<XCTest/XCTest.h>)
#import <XCTest/XCTest.h>
#else
#import <Foundation/Foundation.h>
@interface XCTestCase : NSObject
@end
@implementation XCTestCase
@end
#define XCTAssertEqual(a, b, ...) do { (void)(a); (void)(b); } while (0)
#define XCTAssertEqualObjects(a, b, ...) do { (void)(a); (void)(b); } while (0)
#define XCTAssertEqualWithAccuracy(a, b, acc, ...) do { (void)(a); (void)(b); (void)(acc); } while (0)
#define XCTAssertNotNil(a, ...) do { (void)(a); } while (0)
#define XCTAssertTrue(a, ...) do { (void)(a); } while (0)
#define XCTAssertFalse(a, ...) do { (void)(a); } while (0)
#endif

#import "sound/MacLCSoundPresets.h"

@interface MacLCSoundPresetsTest : XCTestCase
@end

@implementation MacLCSoundPresetsTest

- (void)testPresetTableOrderAndIdentifiers
{
    NSArray<MacLCSoundPreset *> *presets = [MacLCSoundPresets allPresets];
    XCTAssertEqual(presets.count, 9);

    NSArray<NSString *> *expectedIds = @[
        @"voice",
        @"night",
        @"cinema",
        @"music",
        @"bass",
        @"spoken",
        @"headphones",
        @"speakers",
        @"custom",
    ];

    for (NSUInteger i = 0; i < expectedIds.count; i++) {
        XCTAssertEqualObjects(presets[i].identifier, expectedIds[i]);
        XCTAssertNotNil([MacLCSoundPresets presetForIdentifier:expectedIds[i]]);
        XCTAssertEqual(presets[i].baseBands.count, 10);
    }
}

- (void)testScalingAtZero
{
    for (MacLCSoundPreset *preset in [MacLCSoundPresets allPresets]) {
        NSArray<NSNumber *> *scaled = [MacLCSoundPresets scaledBandsForPreset:preset intensity:0.0f];
        XCTAssertEqual(scaled.count, 10);
        if (![preset.identifier isEqualToString:@"custom"]) {
            for (NSNumber *val in scaled) {
                XCTAssertEqualWithAccuracy(val.floatValue, 0.0f, 1e-4f);
            }
            float dialogue = [MacLCSoundPresets scaledDialogueAmountForPreset:preset intensity:0.0f];
            XCTAssertEqualWithAccuracy(dialogue, 0.0f, 1e-4f);
        }
        if (preset.hasCompressor) {
            float ratio = [MacLCSoundPresets scaledCompressorRatioForPreset:preset intensity:0.0f];
            XCTAssertEqualWithAccuracy(ratio, 1.0f, 1e-4f);
            float makeup = [MacLCSoundPresets scaledCompressorMakeupForPreset:preset intensity:0.0f];
            XCTAssertEqualWithAccuracy(makeup, 0.0f, 1e-4f);
        }
    }
}

- (void)testScalingAtHalf
{
    MacLCSoundPreset *voice = [MacLCSoundPresets presetForIdentifier:@"voice"];
    XCTAssertNotNil(voice);

    NSArray<NSNumber *> *scaledBands = [MacLCSoundPresets scaledBandsForPreset:voice intensity:0.5f];
    XCTAssertEqual(scaledBands.count, 10);
    // Base bands: -6, -4, -1, -1, 0, 1, 2, 1.5, -1, -3
    NSArray<NSNumber *> *expected = @[@-3.0f, @-2.0f, @-0.5f, @-0.5f, @0.0f, @0.5f, @1.0f, @0.75f, @-0.5f, @-1.5f];
    for (NSUInteger i = 0; i < 10; i++) {
        XCTAssertEqualWithAccuracy(scaledBands[i].floatValue, expected[i].floatValue, 1e-4f);
    }

    float dialogue = [MacLCSoundPresets scaledDialogueAmountForPreset:voice intensity:0.5f];
    XCTAssertEqualWithAccuracy(dialogue, 0.5f, 1e-4f);

    MacLCSoundPreset *night = [MacLCSoundPresets presetForIdentifier:@"night"];
    XCTAssertNotNil(night);
    // Base compressor ratio: 6.0, makeup: 8.0
    // At s = 0.5: ratio = 1 + (6 - 1) * 0.5 = 3.5, makeup = 8 * 0.5 = 4.0
    float ratio = [MacLCSoundPresets scaledCompressorRatioForPreset:night intensity:0.5f];
    XCTAssertEqualWithAccuracy(ratio, 3.5f, 1e-4f);
    float makeup = [MacLCSoundPresets scaledCompressorMakeupForPreset:night intensity:0.5f];
    XCTAssertEqualWithAccuracy(makeup, 4.0f, 1e-4f);
}

- (void)testScalingAtOne
{
    for (MacLCSoundPreset *preset in [MacLCSoundPresets allPresets]) {
        NSArray<NSNumber *> *scaled = [MacLCSoundPresets scaledBandsForPreset:preset intensity:1.0f];
        for (NSUInteger i = 0; i < 10; i++) {
            XCTAssertEqualWithAccuracy(scaled[i].floatValue, preset.baseBands[i].floatValue, 1e-4f);
        }
        float dialogue = [MacLCSoundPresets scaledDialogueAmountForPreset:preset intensity:1.0f];
        XCTAssertEqualWithAccuracy(dialogue, preset.baseDialogueAmount, 1e-4f);
        if (preset.hasCompressor) {
            float ratio = [MacLCSoundPresets scaledCompressorRatioForPreset:preset intensity:1.0f];
            XCTAssertEqualWithAccuracy(ratio, preset.compressorRatio, 1e-4f);
            float makeup = [MacLCSoundPresets scaledCompressorMakeupForPreset:preset intensity:1.0f];
            XCTAssertEqualWithAccuracy(makeup, preset.compressorMakeupGain, 1e-4f);
        }
    }
}

- (void)testPreampFormula
{
    // Flat 0 dB
    NSArray<NSNumber *> *flat = @[@0.0f, @0.0f, @0.0f, @0.0f, @0.0f, @0.0f, @0.0f, @0.0f, @0.0f, @0.0f];
    XCTAssertEqualWithAccuracy([MacLCSoundPresets calculatePreampForBands:flat], 12.0f, 1e-4f);

    // Negative bands only -> max <= 0 -> 12.0
    NSArray<NSNumber *> *negative = @[@-6.0f, @-4.0f, @-1.0f, @-2.0f, @0.0f, @-1.0f, @-3.0f, @-4.0f, @-2.0f, @-5.0f];
    XCTAssertEqualWithAccuracy([MacLCSoundPresets calculatePreampForBands:negative], 12.0f, 1e-4f);

    // Isolated boost of 5.0 dB: max is 5.0, no adjacent boost -> 12 - 5 = 7.0 dB
    NSArray<NSNumber *> *isolated = @[@0.0f, @0.0f, @5.0f, @0.0f, @0.0f, @0.0f, @0.0f, @0.0f, @0.0f, @0.0f];
    XCTAssertEqualWithAccuracy([MacLCSoundPresets calculatePreampForBands:isolated], 7.0f, 1e-4f);

    // Adjacent boosts: band 0 = 6.0, band 1 = 5.5 -> max is 6.0, adjacent boost = YES (-1.0) -> 12 - 6 - 1 = 5.0 dB
    MacLCSoundPreset *bass = [MacLCSoundPresets presetForIdentifier:@"bass"];
    XCTAssertNotNil(bass);
    XCTAssertEqualWithAccuracy([MacLCSoundPresets calculatePreampForBands:bass.baseBands], 5.0f, 1e-4f);

    // Adjacent boosts: band 1 = 4.0, band 2 = 3.0, others 0 -> max is 4.0, adjacent boost = YES (-1.0) -> 12 - 4 - 1 = 7.0 dB
    NSArray<NSNumber *> *adj = @[@0.0f, @4.0f, @3.0f, @0.0f, @0.0f, @0.0f, @0.0f, @0.0f, @0.0f, @0.0f];
    XCTAssertEqualWithAccuracy([MacLCSoundPresets calculatePreampForBands:adj], 7.0f, 1e-4f);

    // Clamping lower bound: +35.0 dB -> 12 - 35 = -23.0 -> clamped to -20.0 dB
    NSArray<NSNumber *> *extreme = @[@35.0f, @0.0f, @0.0f, @0.0f, @0.0f, @0.0f, @0.0f, @0.0f, @0.0f, @0.0f];
    XCTAssertEqualWithAccuracy([MacLCSoundPresets calculatePreampForBands:extreme], -20.0f, 1e-4f);
}

- (void)testFilterListBuildingWhenOn
{
    MacLCSoundPreset *voice = [MacLCSoundPresets presetForIdentifier:@"voice"];
    XCTAssertNotNil(voice);

    NSArray<NSString *> *owned = nil;
    NSString *res1 = [MacLCSoundPresets filterStringForEnablingPreset:voice
                                                           intensity:0.7f
                                                 currentFilterString:@""
                                                        ownedFilters:&owned];
    XCTAssertEqualObjects(res1, @"equalizer:maclc_dialogue:limiter");
    XCTAssertEqualObjects(owned, (@[@"equalizer", @"maclc_dialogue", @"limiter"]));

    // Intensity 0 keeps the dialogue filter: dragging the slider through 0
    // must not rebuild the audio chain (gap, filter latency change).
    NSString *resZero = [MacLCSoundPresets filterStringForEnablingPreset:voice
                                                               intensity:0.0f
                                                     currentFilterString:@""
                                                            ownedFilters:NULL];
    XCTAssertEqualObjects(resZero, @"equalizer:maclc_dialogue:limiter");

    // A preset without dialogue boost never loads the filter.
    MacLCSoundPreset *bass = [MacLCSoundPresets presetForIdentifier:@"bass"];
    XCTAssertEqualObjects([MacLCSoundPresets filterStringForEnablingPreset:bass
                                                                 intensity:1.0f
                                                       currentFilterString:@""
                                                              ownedFilters:NULL],
                          @"equalizer:limiter");

    // Night preset (has compressor + dialogue)
    MacLCSoundPreset *night = [MacLCSoundPresets presetForIdentifier:@"night"];
    XCTAssertNotNil(night);
    NSString *res2 = [MacLCSoundPresets filterStringForEnablingPreset:night
                                                           intensity:0.7f
                                                 currentFilterString:@""
                                                        ownedFilters:&owned];
    XCTAssertEqualObjects(res2, @"equalizer:compressor:maclc_dialogue:limiter");
    XCTAssertEqualObjects(owned, (@[@"equalizer", @"compressor", @"maclc_dialogue", @"limiter"]));

    // Music preset (no compressor, dialogue is 0)
    MacLCSoundPreset *music = [MacLCSoundPresets presetForIdentifier:@"music"];
    XCTAssertNotNil(music);
    NSString *res3 = [MacLCSoundPresets filterStringForEnablingPreset:music
                                                           intensity:0.6f
                                                 currentFilterString:@""
                                                        ownedFilters:&owned];
    XCTAssertEqualObjects(res3, @"equalizer:limiter");
    XCTAssertEqualObjects(owned, (@[@"equalizer", @"limiter"]));

    // Preserving user filters and their order
    NSString *res4 = [MacLCSoundPresets filterStringForEnablingPreset:voice
                                                           intensity:0.7f
                                                 currentFilterString:@"normvol:headphone"
                                                        ownedFilters:&owned];
    XCTAssertEqualObjects(res4, @"equalizer:normvol:headphone:maclc_dialogue:limiter");

    // Switching presets strips previous owned filters cleanly
    NSString *res5 = [MacLCSoundPresets filterStringForEnablingPreset:night
                                                           intensity:0.7f
                                                 currentFilterString:res4
                                                        ownedFilters:&owned];
    XCTAssertEqualObjects(res5, @"equalizer:normvol:headphone:compressor:maclc_dialogue:limiter");
}

- (void)testFilterListBuildingWhenOff
{
    NSArray<NSString *> *owned = @[@"equalizer", @"compressor", @"maclc_dialogue", @"limiter"];
    NSString *current = @"equalizer:normvol:headphone:compressor:maclc_dialogue:limiter";

    NSString *disabled = [MacLCSoundPresets filterStringForDisablingCurrentFilterString:current
                                                                           ownedFilters:owned];
    XCTAssertEqualObjects(disabled, @"normvol:headphone");

    // All filters owned
    NSString *allOwned = @"equalizer:maclc_dialogue:limiter";
    NSArray<NSString *> *voiceOwned = @[@"equalizer", @"maclc_dialogue", @"limiter"];
    NSString *cleared = [MacLCSoundPresets filterStringForDisablingCurrentFilterString:allOwned
                                                                          ownedFilters:voiceOwned];
    XCTAssertEqualObjects(cleared, @"");
}

- (void)testBandsStringFormatting
{
    NSArray<NSNumber *> *bands = @[@-6.0f, @-4.0f, @-1.0f, @-1.0f, @0.0f, @1.0f, @2.0f, @1.5f, @-1.0f, @-3.0f];
    NSString *formatted = [MacLCSoundPresets formatBandsString:bands];
    XCTAssertEqualObjects(formatted, @"-6.0 -4.0 -1.0 -1.0 0.0 1.0 2.0 1.5 -1.0 -3.0");

    // Verify ASCII minus
    XCTAssertFalse([formatted containsString:@"−"]);
    XCTAssertTrue([formatted hasPrefix:@"-6.0"]);

    // Verify exactly 10 tokens
    NSArray<NSString *> *tokens = [formatted componentsSeparatedByString:@" "];
    XCTAssertEqual(tokens.count, 10);
    XCTAssertEqualObjects(tokens[0], @"-6.0");
    XCTAssertEqualObjects(tokens[4], @"0.0");
    XCTAssertEqualObjects(tokens[7], @"1.5");
}

@end
