/*****************************************************************************
 * maclc_hdr_advisor_test.m: Unit tests for HDR stream, display, and advisor
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
#include <assert.h>
#include <stdio.h>
#include <vlc_common.h>
#include <vlc_es.h>

#if __has_include("gui/macosx/hdr/MacLCHDRTypes.h")
#import "gui/macosx/hdr/MacLCHDRTypes.h"
#import "gui/macosx/hdr/MacLCHDRStreamInfo.h"
#import "gui/macosx/hdr/MacLCDisplayInfo.h"
#import "gui/macosx/hdr/MacLCHDRAdvisor.h"
#else
#import "MacLCHDRTypes.h"
#import "MacLCHDRStreamInfo.h"
#import "MacLCDisplayInfo.h"
#import "MacLCHDRAdvisor.h"
#endif

static void test_types_and_helpers(void)
{
    // Test presentation strings roundtrip
    assert(MacLCHDRPresentationFromString(@"auto") == MacLCHDRPresentationAuto);
    assert(MacLCHDRPresentationFromString(@"dolbyvision") == MacLCHDRPresentationDolbyVision);
    assert(MacLCHDRPresentationFromString(@"hdr10plus") == MacLCHDRPresentationHDR10Plus);
    assert(MacLCHDRPresentationFromString(@"hdr10") == MacLCHDRPresentationHDR10);
    assert(MacLCHDRPresentationFromString(@"hlg") == MacLCHDRPresentationHLG);
    assert(MacLCHDRPresentationFromString(@"sdr") == MacLCHDRPresentationSDR);
    assert(MacLCHDRPresentationFromString(@"unknown") == MacLCHDRPresentationAuto);

    assert([MacLCHDRPresentationToString(MacLCHDRPresentationAuto) isEqualToString:@"auto"]);
    assert([MacLCHDRPresentationToString(MacLCHDRPresentationDolbyVision) isEqualToString:@"dolbyvision"]);
    assert([MacLCHDRPresentationToString(MacLCHDRPresentationHDR10Plus) isEqualToString:@"hdr10plus"]);
    assert([MacLCHDRPresentationToString(MacLCHDRPresentationHDR10) isEqualToString:@"hdr10"]);
    assert([MacLCHDRPresentationToString(MacLCHDRPresentationHLG) isEqualToString:@"hlg"]);
    assert([MacLCHDRPresentationToString(MacLCHDRPresentationSDR) isEqualToString:@"sdr"]);

    // Test picture mode strings roundtrip
    assert(MacLCHDRPictureModeFromString(@"auto") == MacLCHDRPictureModeAuto);
    assert(MacLCHDRPictureModeFromString(@"accurate") == MacLCHDRPictureModeAccurate);
    assert(MacLCHDRPictureModeFromString(@"balanced") == MacLCHDRPictureModeBalanced);
    assert(MacLCHDRPictureModeFromString(@"bright") == MacLCHDRPictureModeBright);
    assert(MacLCHDRPictureModeFromString(@"invalid") == MacLCHDRPictureModeAuto);

    assert([MacLCHDRPictureModeToString(MacLCHDRPictureModeAuto) isEqualToString:@"auto"]);
    assert([MacLCHDRPictureModeToString(MacLCHDRPictureModeAccurate) isEqualToString:@"accurate"]);
    assert([MacLCHDRPictureModeToString(MacLCHDRPictureModeBalanced) isEqualToString:@"balanced"]);
    assert([MacLCHDRPictureModeToString(MacLCHDRPictureModeBright) isEqualToString:@"bright"]);

    // Display names
    assert([MacLCHDRPresentationDisplayName(MacLCHDRPresentationDolbyVision) isEqualToString:@"Dolby Vision"]);
    assert([MacLCHDRPresentationDisplayName(MacLCHDRPresentationHDR10Plus) isEqualToString:@"HDR10+"]);
    assert([MacLCHDRPresentationDisplayName(MacLCHDRPresentationHDR10) isEqualToString:@"HDR10"]);
    assert([MacLCHDRPresentationDisplayName(MacLCHDRPresentationHLG) isEqualToString:@"HLG"]);
    assert([MacLCHDRPresentationDisplayName(MacLCHDRPresentationSDR) isEqualToString:@"SDR"]);

    // Badge titles
    assert([MacLCHDRPresentationBadgeTitle(MacLCHDRPresentationDolbyVision) isEqualToString:@"DOLBY VISION"]);
    assert([MacLCHDRPresentationBadgeTitle(MacLCHDRPresentationHDR10Plus) isEqualToString:@"HDR10+"]);
    assert([MacLCHDRPresentationBadgeTitle(MacLCHDRPresentationHDR10) isEqualToString:@"HDR10"]);
    assert([MacLCHDRPresentationBadgeTitle(MacLCHDRPresentationHLG) isEqualToString:@"HLG"]);
    assert([MacLCHDRPresentationBadgeTitle(MacLCHDRPresentationSDR) isEqualToString:@"SDR"]);

    // Summaries
    assert([MacLCHDRPresentationSummary(MacLCHDRPresentationDolbyVision) isEqualToString:@"Adjusts every scene to your display."]);
    assert([MacLCHDRPresentationSummary(MacLCHDRPresentationHDR10Plus) isEqualToString:@"Scene-by-scene brightness, open standard."]);
    assert([MacLCHDRPresentationSummary(MacLCHDRPresentationHDR10) isEqualToString:@"One tone curve for the whole video."]);
    assert([MacLCHDRPresentationSummary(MacLCHDRPresentationHLG) isEqualToString:@"Broadcast HDR that adapts to your display."]);
    assert([MacLCHDRPresentationSummary(MacLCHDRPresentationSDR) isEqualToString:@"Standard range. Calmest picture, least power."]);

    assert([MacLCHDRPictureModeSummary(MacLCHDRPictureModeAccurate) isEqualToString:@"Faithful to the master. Can look dim in a bright room."]);
    assert([MacLCHDRPictureModeSummary(MacLCHDRPictureModeBalanced) isEqualToString:@"Keeps highlights and mid-tones in proportion for this display."]);
    assert([MacLCHDRPictureModeSummary(MacLCHDRPictureModeBright) containsString:@"Lifts mid-tones and highlights."]);
}

static void test_stream_and_display_info(void)
{
    MacLCHDRStreamInfo *stream1 = [[MacLCHDRStreamInfo alloc]
        initWithTransfer:TRANSFER_FUNC_SMPTE_ST2084
               primaries:COLOR_PRIMARIES_BT2020
                bitDepth:10
               pixelSize:NSMakeSize(3840, 2160)
        masteringPeakNits:1000.0f
         masteringMinNits:0.005f
                  maxCLL:1000
                 maxFALL:400
             doviProfile:8
               doviLevel:6
              doviHasRPU:YES
               doviHasEL:NO
               doviHasBL:YES
           hdr10PlusSeen:YES];

    assert(stream1.isHDR);
    assert(stream1.contentPeakNits == 1000.0);
    NSArray<NSNumber *> *avail = stream1.availablePresentations;
    assert(avail.count == 4);
    assert([avail[0] integerValue] == MacLCHDRPresentationDolbyVision);
    assert([avail[1] integerValue] == MacLCHDRPresentationHDR10Plus);
    assert([avail[2] integerValue] == MacLCHDRPresentationHDR10);
    assert([avail[3] integerValue] == MacLCHDRPresentationSDR);

    MacLCHDRStreamInfo *stream2 = [[MacLCHDRStreamInfo alloc]
        initWithTransfer:TRANSFER_FUNC_SMPTE_ST2084
               primaries:COLOR_PRIMARIES_BT2020
                bitDepth:10
               pixelSize:NSMakeSize(3840, 2160)
        masteringPeakNits:1000.0f
         masteringMinNits:0.005f
                  maxCLL:1000
                 maxFALL:400
             doviProfile:8
               doviLevel:6
              doviHasRPU:YES
               doviHasEL:NO
               doviHasBL:YES
           hdr10PlusSeen:YES];

    assert([stream1 isEqual:stream2]);
    assert(stream1.hash == stream2.hash);

    MacLCDisplayInfo *disp1 = [[MacLCDisplayInfo alloc]
        initWithLocalizedName:@"Liquid Retina XDR"
            potentialHeadroom:16.0
              currentHeadroom:8.0
            referenceHeadroom:0.0
                    onBattery:NO
                 lowPowerMode:NO];

    assert(disp1.supportsHDR);
    assert(!disp1.referenceModeActive);
    assert(disp1.knownPanelPeakNits == 1600);
    assert(disp1.contentPeakNits == 8.0 * 203.0);

    MacLCDisplayInfo *disp2 = [[MacLCDisplayInfo alloc]
        initWithLocalizedName:@"Liquid Retina XDR"
            potentialHeadroom:16.0
              currentHeadroom:8.0
            referenceHeadroom:0.0
                    onBattery:NO
                 lowPowerMode:NO];

    assert([disp1 isEqual:disp2]);
    assert(disp1.hash == disp2.hash);
}

static void test_dv81_on_xdr(void)
{
    MacLCHDRStreamInfo *stream = [[MacLCHDRStreamInfo alloc]
        initWithTransfer:TRANSFER_FUNC_SMPTE_ST2084
               primaries:COLOR_PRIMARIES_BT2020
                bitDepth:10
               pixelSize:NSMakeSize(3840, 2160)
        masteringPeakNits:1000.0f
         masteringMinNits:0.005f
                  maxCLL:1000
                 maxFALL:400
             doviProfile:8
               doviLevel:6
              doviHasRPU:YES
               doviHasEL:NO
               doviHasBL:YES
           hdr10PlusSeen:NO];

    MacLCDisplayInfo *display = [[MacLCDisplayInfo alloc]
        initWithLocalizedName:@"Liquid Retina XDR"
            potentialHeadroom:16.0
              currentHeadroom:8.0
            referenceHeadroom:0.0
                    onBattery:NO
                 lowPowerMode:NO];

    NSSet<NSNumber *> *processable = [NSSet setWithObjects:
        @(MacLCHDRPresentationDolbyVision),
        @(MacLCHDRPresentationHDR10),
        @(MacLCHDRPresentationSDR),
        nil];

    MacLCHDRRecommendation *rec = [MacLCHDRAdvisor recommendationForStream:stream
                                                                   display:display
                                                               processable:processable];

    /* The 1,000-nit master fits under this display's 1,624 cd/m² of headroom:
     * Dolby Vision would render the same picture, so the native HDR10 path
     * (lighter on power) is recommended, and the reason says so. */
    assert(rec.presentation == MacLCHDRPresentationHDR10);
    assert(rec.pictureMode == MacLCHDRPictureModeAccurate);
    assert([rec.headline isEqualToString:@"Playing in HDR10"]);
    assert([rec.reason containsString:@"Dolby Vision and HDR10 look the same"]);
    assert(rec.warning == nil);

    /* Less headroom (4 x 203 = 812 cd/m²): the master must be tone-mapped,
     * which is where Dolby Vision's per-scene metadata pays off. */
    MacLCDisplayInfo *dimmerDisplay = [[MacLCDisplayInfo alloc]
        initWithLocalizedName:@"Liquid Retina XDR"
            potentialHeadroom:16.0
              currentHeadroom:4.0
            referenceHeadroom:0.0
                    onBattery:NO
                 lowPowerMode:NO];
    MacLCHDRRecommendation *dimmerRec = [MacLCHDRAdvisor recommendationForStream:stream
                                                                         display:dimmerDisplay
                                                                     processable:processable];
    assert(dimmerRec.presentation == MacLCHDRPresentationDolbyVision);
    assert(dimmerRec.pictureMode == MacLCHDRPictureModeBalanced);
    assert([dimmerRec.headline isEqualToString:@"Playing in Dolby Vision"]);

    NSString *why = nil;
    assert([rec isPresentationSelectable:MacLCHDRPresentationDolbyVision reason:&why]);
    assert(why == nil);
}

static void test_dv5_not_processable(void)
{
    MacLCHDRStreamInfo *stream = [[MacLCHDRStreamInfo alloc]
        initWithTransfer:TRANSFER_FUNC_SMPTE_ST2084
               primaries:COLOR_PRIMARIES_BT2020
                bitDepth:10
               pixelSize:NSMakeSize(3840, 2160)
        masteringPeakNits:1000.0f
         masteringMinNits:0.005f
                  maxCLL:1000
                 maxFALL:400
             doviProfile:5
               doviLevel:6
              doviHasRPU:YES
               doviHasEL:NO
               doviHasBL:YES
           hdr10PlusSeen:NO];

    // Profile 5 available presentations must NOT include HDR10
    assert([stream.availablePresentations containsObject:@(MacLCHDRPresentationDolbyVision)]);
    assert(![stream.availablePresentations containsObject:@(MacLCHDRPresentationHDR10)]);
    assert([stream.availablePresentations containsObject:@(MacLCHDRPresentationSDR)]);

    MacLCDisplayInfo *display = [[MacLCDisplayInfo alloc]
        initWithLocalizedName:@"Built-in Retina Display"
            potentialHeadroom:1.0
              currentHeadroom:1.0
            referenceHeadroom:0.0
                    onBattery:NO
                 lowPowerMode:NO];

    // Pipeline cannot process Dolby Vision
    NSSet<NSNumber *> *processable = [NSSet setWithObjects:
        @(MacLCHDRPresentationHDR10),
        @(MacLCHDRPresentationSDR),
        nil];

    MacLCHDRRecommendation *rec = [MacLCHDRAdvisor recommendationForStream:stream
                                                                   display:display
                                                               processable:processable];

    // Profile 5 must still pick DolbyVision and emit warning
    assert(rec.presentation == MacLCHDRPresentationDolbyVision);
    assert(rec.warning != nil);
    assert([rec.warning isEqualToString:@"Dolby Vision processing isn't available here, so colours may look wrong."]);

    NSString *why = nil;
    assert(![rec isPresentationSelectable:MacLCHDRPresentationDolbyVision reason:&why]);
    assert([why isEqualToString:@"Needs Dolby Vision processing, which this video path can't do."]);

    // HDR10 was not offered in available presentations for profile 5
    NSString *whyHDR10 = @"should_be_cleared";
    assert(![rec isPresentationSelectable:MacLCHDRPresentationHDR10 reason:&whyHDR10]);
    assert(whyHDR10 == nil);
}

static void test_hdr10_4000nit_on_sdr(void)
{
    MacLCHDRStreamInfo *stream = [[MacLCHDRStreamInfo alloc]
        initWithTransfer:TRANSFER_FUNC_SMPTE_ST2084
               primaries:COLOR_PRIMARIES_BT2020
                bitDepth:10
               pixelSize:NSMakeSize(3840, 2160)
        masteringPeakNits:4000.0f
         masteringMinNits:0.005f
                  maxCLL:4000
                 maxFALL:1000
             doviProfile:-1
               doviLevel:0
              doviHasRPU:NO
               doviHasEL:NO
               doviHasBL:NO
           hdr10PlusSeen:NO];

    MacLCDisplayInfo *display = [[MacLCDisplayInfo alloc]
        initWithLocalizedName:@"Standard Display"
            potentialHeadroom:1.0
              currentHeadroom:1.0
            referenceHeadroom:0.0
                    onBattery:NO
                 lowPowerMode:NO];

    NSSet<NSNumber *> *processable = [NSSet setWithObjects:
        @(MacLCHDRPresentationHDR10),
        @(MacLCHDRPresentationSDR),
        nil];

    MacLCHDRRecommendation *rec = [MacLCHDRAdvisor recommendationForStream:stream
                                                                   display:display
                                                               processable:processable];

    assert(rec.presentation == MacLCHDRPresentationHDR10);
    assert(rec.pictureMode == MacLCHDRPictureModeBalanced);
    assert([rec.reason isEqualToString:@"MacLC converts HDR for your display."]);
    assert([rec.headline isEqualToString:@"Playing in HDR10"]);
}

static void test_hlg(void)
{
    MacLCHDRStreamInfo *stream = [[MacLCHDRStreamInfo alloc]
        initWithTransfer:TRANSFER_FUNC_HLG
               primaries:COLOR_PRIMARIES_BT2020
                bitDepth:10
               pixelSize:NSMakeSize(3840, 2160)
        masteringPeakNits:0.0f
         masteringMinNits:0.0f
                  maxCLL:0
                 maxFALL:0
             doviProfile:-1
               doviLevel:0
              doviHasRPU:NO
               doviHasEL:NO
               doviHasBL:NO
           hdr10PlusSeen:NO];

    MacLCDisplayInfo *display = [[MacLCDisplayInfo alloc]
        initWithLocalizedName:@"Liquid Retina XDR"
            potentialHeadroom:16.0
              currentHeadroom:8.0
            referenceHeadroom:0.0
                    onBattery:NO
                 lowPowerMode:NO];

    NSSet<NSNumber *> *processable = [NSSet setWithObjects:
        @(MacLCHDRPresentationHLG),
        @(MacLCHDRPresentationSDR),
        nil];

    MacLCHDRRecommendation *rec = [MacLCHDRAdvisor recommendationForStream:stream
                                                                   display:display
                                                               processable:processable];

    assert(rec.presentation == MacLCHDRPresentationHLG);
    assert(rec.pictureMode == MacLCHDRPictureModeAuto);
    assert([rec.headline isEqualToString:@"Playing in HLG"]);
    assert([rec.reason isEqualToString:@"Broadcast HDR that adapts to your display."]);
}

static void test_hdr10plus(void)
{
    MacLCHDRStreamInfo *stream = [[MacLCHDRStreamInfo alloc]
        initWithTransfer:TRANSFER_FUNC_SMPTE_ST2084
               primaries:COLOR_PRIMARIES_BT2020
                bitDepth:10
               pixelSize:NSMakeSize(3840, 2160)
        masteringPeakNits:1000.0f
         masteringMinNits:0.005f
                  maxCLL:1000
                 maxFALL:400
             doviProfile:-1
               doviLevel:0
              doviHasRPU:NO
               doviHasEL:NO
               doviHasBL:NO
           hdr10PlusSeen:YES];

    MacLCDisplayInfo *display = [[MacLCDisplayInfo alloc]
        initWithLocalizedName:@"Pro Display XDR"
            potentialHeadroom:16.0
              currentHeadroom:8.0
            referenceHeadroom:0.0
                    onBattery:NO
                 lowPowerMode:NO];

    NSSet<NSNumber *> *processable = [NSSet setWithObjects:
        @(MacLCHDRPresentationHDR10Plus),
        @(MacLCHDRPresentationHDR10),
        @(MacLCHDRPresentationSDR),
        nil];

    MacLCHDRRecommendation *rec = [MacLCHDRAdvisor recommendationForStream:stream
                                                                   display:display
                                                               processable:processable];

    /* 1,000-nit master, 1,624 cd/m² of headroom: HDR10+ adds nothing here. */
    assert(rec.presentation == MacLCHDRPresentationHDR10);
    assert([rec.reason containsString:@"HDR10+ and HDR10 look the same"]);

    /* A 4,000-nit master has to be tone-mapped: HDR10+ is recommended. */
    MacLCHDRStreamInfo *brightStream = [[MacLCHDRStreamInfo alloc]
        initWithTransfer:TRANSFER_FUNC_SMPTE_ST2084
               primaries:COLOR_PRIMARIES_BT2020
                bitDepth:10
               pixelSize:NSMakeSize(3840, 2160)
        masteringPeakNits:4000.0f
         masteringMinNits:0.005f
                  maxCLL:4000
                 maxFALL:400
             doviProfile:-1
               doviLevel:0
              doviHasRPU:NO
               doviHasEL:NO
               doviHasBL:NO
           hdr10PlusSeen:YES];
    MacLCHDRRecommendation *brightRec = [MacLCHDRAdvisor recommendationForStream:brightStream
                                                                         display:display
                                                                     processable:processable];
    assert(brightRec.presentation == MacLCHDRPresentationHDR10Plus);
    assert(brightRec.pictureMode == MacLCHDRPictureModeBalanced);
    assert([brightRec.headline isEqualToString:@"Playing in HDR10+"]);
}

static void test_battery_advice(void)
{
    MacLCHDRStreamInfo *stream = [[MacLCHDRStreamInfo alloc]
        initWithTransfer:TRANSFER_FUNC_SMPTE_ST2084
               primaries:COLOR_PRIMARIES_BT2020
                bitDepth:10
               pixelSize:NSMakeSize(3840, 2160)
        masteringPeakNits:1000.0f
         masteringMinNits:0.005f
                  maxCLL:1000
                 maxFALL:400
             doviProfile:-1
               doviLevel:0
              doviHasRPU:NO
               doviHasEL:NO
               doviHasBL:NO
           hdr10PlusSeen:NO];

    // on battery with reduced headroom: 2.0 < 16.0 * 0.75
    MacLCDisplayInfo *display = [[MacLCDisplayInfo alloc]
        initWithLocalizedName:@"Liquid Retina XDR"
            potentialHeadroom:16.0
              currentHeadroom:2.0
            referenceHeadroom:0.0
                    onBattery:YES
                 lowPowerMode:NO];

    NSSet<NSNumber *> *processable = [NSSet setWithObjects:
        @(MacLCHDRPresentationHDR10),
        @(MacLCHDRPresentationSDR),
        nil];

    MacLCHDRRecommendation *rec = [MacLCHDRAdvisor recommendationForStream:stream
                                                                   display:display
                                                               processable:processable];

    assert(rec.brightnessAdvice != nil);
    assert([rec.brightnessAdvice isEqualToString:@"HDR brightness is limited on battery. Connect power for full brightness."]);
}

static void test_sdr_stream_on_edr(void)
{
    MacLCHDRStreamInfo *stream = [[MacLCHDRStreamInfo alloc]
        initWithTransfer:TRANSFER_FUNC_BT709
               primaries:COLOR_PRIMARIES_BT709
                bitDepth:8
               pixelSize:NSMakeSize(1920, 1080)
        masteringPeakNits:0.0f
         masteringMinNits:0.0f
                  maxCLL:0
                 maxFALL:0
             doviProfile:-1
               doviLevel:0
              doviHasRPU:NO
               doviHasEL:NO
               doviHasBL:NO
           hdr10PlusSeen:NO];

    assert(!stream.isHDR);

    MacLCDisplayInfo *display = [[MacLCDisplayInfo alloc]
        initWithLocalizedName:@"Liquid Retina XDR"
            potentialHeadroom:16.0
              currentHeadroom:8.0
            referenceHeadroom:0.0
                    onBattery:NO
                 lowPowerMode:NO];

    NSSet<NSNumber *> *processable = [NSSet setWithObjects:
        @(MacLCHDRPresentationSDR),
        nil];

    MacLCHDRRecommendation *rec = [MacLCHDRAdvisor recommendationForStream:stream
                                                                   display:display
                                                               processable:processable];

    assert(rec.presentation == MacLCHDRPresentationSDR);
    assert(rec.pictureMode == MacLCHDRPictureModeAuto);
    assert(rec.brightnessAdvice != nil);
    assert([rec.brightnessAdvice isEqualToString:@"This display can play standard video in HDR for extra sparkle in highlights."]);
}

static void test_additional_rules(void)
{
    // Low power mode advice
    MacLCHDRStreamInfo *stream = [[MacLCHDRStreamInfo alloc]
        initWithTransfer:TRANSFER_FUNC_SMPTE_ST2084
               primaries:COLOR_PRIMARIES_BT2020
                bitDepth:10
               pixelSize:NSMakeSize(3840, 2160)
        masteringPeakNits:1000.0f
         masteringMinNits:0.005f
                  maxCLL:1000
                 maxFALL:400
             doviProfile:-1
               doviLevel:0
              doviHasRPU:NO
               doviHasEL:NO
               doviHasBL:NO
           hdr10PlusSeen:NO];

    MacLCDisplayInfo *displayLPM = [[MacLCDisplayInfo alloc]
        initWithLocalizedName:@"Liquid Retina XDR"
            potentialHeadroom:16.0
              currentHeadroom:16.0
            referenceHeadroom:0.0
                    onBattery:NO
                 lowPowerMode:YES];

    NSSet<NSNumber *> *processable = [NSSet setWithObjects:
        @(MacLCHDRPresentationHDR10),
        @(MacLCHDRPresentationSDR),
        nil];

    MacLCHDRRecommendation *recLPM = [MacLCHDRAdvisor recommendationForStream:stream
                                                                      display:displayLPM
                                                                  processable:processable];
    assert(recLPM.brightnessAdvice != nil);
    assert([recLPM.brightnessAdvice isEqualToString:@"Low Power Mode limits HDR brightness."]);

    // Reference mode warning
    MacLCDisplayInfo *displayRef = [[MacLCDisplayInfo alloc]
        initWithLocalizedName:@"Pro Display XDR"
            potentialHeadroom:16.0
              currentHeadroom:16.0
            referenceHeadroom:2.5
                    onBattery:NO
                 lowPowerMode:NO];

    MacLCHDRRecommendation *recRef = [MacLCHDRAdvisor recommendationForStream:stream
                                                                      display:displayRef
                                                                  processable:processable];
    assert(recRef.warning != nil);
    assert([recRef.warning isEqualToString:@"Your display uses a reference mode; brightness is fixed by that preset."]);

    // Stream PQ && picture != Bright && content peak > display peak -> brighter picture available
    MacLCHDRStreamInfo *streamHighLuma = [[MacLCHDRStreamInfo alloc]
        initWithTransfer:TRANSFER_FUNC_SMPTE_ST2084
               primaries:COLOR_PRIMARIES_BT2020
                bitDepth:10
               pixelSize:NSMakeSize(3840, 2160)
        masteringPeakNits:4000.0f
         masteringMinNits:0.005f
                  maxCLL:4000
                 maxFALL:1000
             doviProfile:-1
               doviLevel:0
              doviHasRPU:NO
               doviHasEL:NO
               doviHasBL:NO
           hdr10PlusSeen:NO];

    MacLCDisplayInfo *displayLimited = [[MacLCDisplayInfo alloc]
        initWithLocalizedName:@"Studio Display"
            potentialHeadroom:2.0
              currentHeadroom:2.0
            referenceHeadroom:0.0
                    onBattery:NO
                 lowPowerMode:NO];

    MacLCHDRRecommendation *recBright = [MacLCHDRAdvisor recommendationForStream:streamHighLuma
                                                                         display:displayLimited
                                                                     processable:processable];
    assert(recBright.brightnessAdvice != nil);
    assert([recBright.brightnessAdvice isEqualToString:@"A brighter picture is available — it clips some highlight detail and uses more power."]);

    // DV reason with knownPanelPeakNits formatting
    MacLCHDRStreamInfo *streamDVHighLuma = [[MacLCHDRStreamInfo alloc]
        initWithTransfer:TRANSFER_FUNC_SMPTE_ST2084
               primaries:COLOR_PRIMARIES_BT2020
                bitDepth:10
               pixelSize:NSMakeSize(3840, 2160)
        masteringPeakNits:4000.0f
         masteringMinNits:0.005f
                  maxCLL:4000
                 maxFALL:1000
             doviProfile:8
               doviLevel:6
              doviHasRPU:YES
               doviHasEL:NO
               doviHasBL:YES
           hdr10PlusSeen:NO];

    MacLCDisplayInfo *displayXDRLowCurrent = [[MacLCDisplayInfo alloc]
        initWithLocalizedName:@"Liquid Retina XDR"
            potentialHeadroom:16.0
              currentHeadroom:4.0
            referenceHeadroom:0.0
                    onBattery:NO
                 lowPowerMode:NO];

    NSSet<NSNumber *> *dvProcessable = [NSSet setWithObjects:
        @(MacLCHDRPresentationDolbyVision),
        @(MacLCHDRPresentationHDR10),
        @(MacLCHDRPresentationSDR),
        nil];

    MacLCHDRRecommendation *recDVReason = [MacLCHDRAdvisor recommendationForStream:streamDVHighLuma
                                                                           display:displayXDRLowCurrent
                                                                       processable:dvProcessable];
    assert(recDVReason.presentation == MacLCHDRPresentationDolbyVision);
    assert(recDVReason.pictureMode == MacLCHDRPictureModeBalanced);
    /* The advisor formats numbers for the user's region (1,600 / 1 600 /
     * 1.600), so build the expectation the same way. */
    NSNumberFormatter *formatter = [[NSNumberFormatter alloc] init];
    formatter.numberStyle = NSNumberFormatterDecimalStyle;
    NSString *expectedPeak = [NSString stringWithFormat:@"%@-nit",
                              [formatter stringFromNumber:@1600]];
    assert([recDVReason.reason containsString:expectedPeak]);
}

int main(int argc, const char * argv[])
{
    @autoreleasepool {
        (void)argc;
        (void)argv;
        test_types_and_helpers();
        test_stream_and_display_info();
        test_dv81_on_xdr();
        test_dv5_not_processable();
        test_hdr10_4000nit_on_sdr();
        test_hlg();
        test_hdr10plus();
        test_battery_advice();
        test_sdr_stream_on_edr();
        test_additional_rules();
        printf("maclc_hdr_advisor: all tests passed\n");
    }
    return 0;
}
