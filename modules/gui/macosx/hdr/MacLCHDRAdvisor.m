/*****************************************************************************
 * MacLCHDRAdvisor.m: Pure logic HDR advisor and recommendation engine
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

#import "MacLCHDRAdvisor.h"

#include "../../video_output/apple/maclc_hdr_vars.h"

#if __has_include("extensions/NSString+Helpers.h")
#import "extensions/NSString+Helpers.h"
#elif __has_include("gui/macosx/extensions/NSString+Helpers.h")
#import "gui/macosx/extensions/NSString+Helpers.h"
#endif

#ifndef _NS
#define _NS(s) @(s)
#endif

@interface MacLCHDRRecommendation ()

@property (nonatomic, readonly, copy) NSArray<NSNumber *> *availablePresentations;
@property (nonatomic, readonly, copy) NSSet<NSNumber *> *processablePresentations;
@property (nonatomic, readwrite) BOOL brightnessAdviceSuggestsBright;

@end

@implementation MacLCHDRRecommendation

- (instancetype)initWithPresentation:(MacLCHDRPresentation)presentation
                         pictureMode:(MacLCHDRPictureMode)pictureMode
                            headline:(NSString *)headline
                              reason:(NSString *)reason
                    brightnessAdvice:(nullable NSString *)brightnessAdvice
                             warning:(nullable NSString *)warning
               availablePresentations:(NSArray<NSNumber *> *)availablePresentations
             processablePresentations:(NSSet<NSNumber *> *)processablePresentations
{
    self = [super init];
    if (self) {
        _presentation = presentation;
        _pictureMode = pictureMode;
        _headline = [headline copy];
        _reason = [reason copy];
        _brightnessAdvice = [brightnessAdvice copy];
        _warning = [warning copy];
        _availablePresentations = [availablePresentations copy];
        _processablePresentations = [processablePresentations copy];
    }
    return self;
}

- (BOOL)isPresentationSelectable:(MacLCHDRPresentation)p reason:(NSString * _Nullable * _Nullable)why
{
    if (![self.availablePresentations containsObject:@(p)]) {
        if (why != NULL) {
            *why = nil;
        }
        return NO;
    }

    if ([self.processablePresentations containsObject:@(p)]) {
        if (why != NULL) {
            *why = nil;
        }
        return YES;
    }

    if (why != NULL) {
        if (p == MacLCHDRPresentationDolbyVision) {
            *why = _NS("Needs Dolby Vision processing, which this video path can't do.");
        } else {
            *why = _NS("Not available with this decoder.");
        }
    }
    return NO;
}

@end

@implementation MacLCHDRAdvisor

+ (MacLCHDRRecommendation *)recommendationForStream:(MacLCHDRStreamInfo *)stream
                                            display:(MacLCDisplayInfo *)display
                                        processable:(NSSet<NSNumber *> *)processablePresentations
{
    MacLCHDRPresentation pickedPresentation = MacLCHDRPresentationSDR;
    MacLCHDRPictureMode pickedPictureMode = MacLCHDRPictureModeAuto;
    NSString *warning = nil;
    NSString *brightnessAdvice = nil;
    BOOL suggestsBright = NO;
    NSString *reason = @"";
    /* YES when the master is brighter than what the display can show right
     * now, i.e. some tone mapping has to happen (5 % tolerance so a 1,000-nit
     * master on a ~1,000-nit panel is not flagged). */
    const BOOL contentNeedsToneMapping =
        maclc_hdr_needs_tone_mapping((float)stream.contentPeakNits,
                                     (float)display.contentPeakNits);
    /* Set when Dolby Vision / HDR10+ are present but HDR10 was picked because
     * the master fits the display; the reason line then says why. */
    BOOL preferredNativeOverDynamic = NO;

    const NSArray<NSNumber *> *order = @[
        @(MacLCHDRPresentationDolbyVision),
        @(MacLCHDRPresentationHDR10Plus),
        @(MacLCHDRPresentationHDR10),
        @(MacLCHDRPresentationHLG)
    ];

    // Rule a: DV profile 5 has no standard or HDR10 fallback: pick DolbyVision.
    // If not processable, warn that colours may look wrong.
    if (stream.doviProfile == 5) {
        pickedPresentation = MacLCHDRPresentationDolbyVision;
        if (![processablePresentations containsObject:@(MacLCHDRPresentationDolbyVision)]) {
            warning = _NS("Dolby Vision processing isn't available here, so colours may look wrong.");
        }
    } else if (!display.supportsHDR) {
        // Rule b: standard-range display: first processable of DolbyVision, HDR10Plus, HDR10, HLG
        for (NSNumber *candidate in order) {
            if ([stream.availablePresentations containsObject:candidate] &&
                [processablePresentations containsObject:candidate]) {
                pickedPresentation = [candidate integerValue];
                break;
            }
        }
    } else {
        // Rule c: HDR display. Dynamic metadata (Dolby Vision, HDR10+) only
        // changes the picture when it has to be tone-mapped into the display.
        // When the whole master fits under the display's peak, all of them
        // render the same picture, and HDR10 is the one macOS shows through
        // its own HDR pipeline, which costs the least power.
        const BOOL fitsDisplay = !contentNeedsToneMapping;
        const BOOL hdr10Usable =
            [stream.availablePresentations containsObject:@(MacLCHDRPresentationHDR10)] &&
            [processablePresentations containsObject:@(MacLCHDRPresentationHDR10)];
        if (fitsDisplay && hdr10Usable) {
            pickedPresentation = MacLCHDRPresentationHDR10;
            preferredNativeOverDynamic =
                [stream.availablePresentations containsObject:@(MacLCHDRPresentationDolbyVision)] ||
                [stream.availablePresentations containsObject:@(MacLCHDRPresentationHDR10Plus)];
        } else {
            for (NSNumber *candidate in order) {
                if ([stream.availablePresentations containsObject:candidate] &&
                    [processablePresentations containsObject:candidate]) {
                    pickedPresentation = [candidate integerValue];
                    break;
                }
            }
        }
    }

    // Rule d: picture mode:
    // Accurate when the master fits under display.contentPeakNits, else Balanced; HLG/SDR -> Auto (not applicable).
    if (pickedPresentation == MacLCHDRPresentationHLG || pickedPresentation == MacLCHDRPresentationSDR) {
        pickedPictureMode = MacLCHDRPictureModeAuto;
    } else {
        if (!display.supportsHDR) {
            pickedPictureMode = MacLCHDRPictureModeBalanced;
        } else {
            if (!contentNeedsToneMapping) {
                pickedPictureMode = MacLCHDRPictureModeAccurate;
            } else {
                pickedPictureMode = MacLCHDRPictureModeBalanced;
            }
        }
    }

    // Rule e: headline "Playing in <DisplayName>"
    NSString *presentationName = MacLCHDRPresentationDisplayName(pickedPresentation);
    NSString *headline = [NSString stringWithFormat:_NS("Playing in %@"), presentationName];

    // Reason:
    if (!display.supportsHDR) {
        if (stream.isHDR) {
            if (pickedPresentation == MacLCHDRPresentationDolbyVision || pickedPresentation == MacLCHDRPresentationHDR10Plus) {
                reason = _NS("Your display shows standard range — scene-by-scene metadata converts HDR best.");
            } else {
                reason = _NS("MacLC converts HDR for your display.");
            }
        } else {
            reason = _NS("Standard range. Calmest picture, least power.");
        }
    } else {
        if (preferredNativeOverDynamic) {
            reason = [stream.availablePresentations containsObject:@(MacLCHDRPresentationDolbyVision)]
                ? _NS("Your display is brighter than this master, so Dolby Vision and HDR10 look the same here. HDR10 uses macOS's own HDR pipeline and less power.")
                : _NS("Your display is brighter than this master, so HDR10+ and HDR10 look the same here. HDR10 uses macOS's own HDR pipeline and less power.");
        } else if (pickedPictureMode == MacLCHDRPictureModeAccurate) {
            reason = _NS("Your display is brighter than the master, so you see exactly what the colourist saw.");
        } else if (pickedPresentation == MacLCHDRPresentationDolbyVision) {
            if (display.panelPeakNits > 0) {
                NSNumberFormatter *formatter = [[NSNumberFormatter alloc] init];
                formatter.numberStyle = NSNumberFormatterDecimalStyle;
                NSString *formatted = [formatter stringFromNumber:@(display.panelPeakNits)];
                NSString *peakStr = [NSString stringWithFormat:@"%@-nit", formatted];
                reason = [NSString stringWithFormat:_NS("Best for this display — adjusts every scene to its %@ peak."), peakStr];
            } else {
                reason = [NSString stringWithFormat:_NS("Best for this display — adjusts every scene to its %@ peak."), _NS("brightness")];
            }
        } else {
            reason = MacLCHDRPresentationSummary(pickedPresentation);
        }
    }

    // Rule f: brightnessAdvice (first that applies, else nil):
    // - onBattery && supportsHDR && currentHeadroom < potentialHeadroom*0.75 ->
    //   "HDR brightness is limited on battery. Connect power for full brightness."
    // - lowPowerMode -> "Low Power Mode limits HDR brightness."
    // - stream is PQ && picture != Bright && content peak > display peak ->
    //   "A brighter picture is available — it clips some highlight detail and uses more power."
    // - !stream.isHDR && supportsHDR -> "This display can play standard video in HDR for extra sparkle in highlights."
    if (display.onBattery && display.supportsHDR && (display.currentHeadroom < display.potentialHeadroom * 0.75)) {
        brightnessAdvice = _NS("HDR brightness is limited on battery. Connect power for full brightness.");
    } else if (display.lowPowerMode) {
        brightnessAdvice = _NS("Low Power Mode limits HDR brightness.");
    } else if (stream.transfer == TRANSFER_FUNC_SMPTE_ST2084 &&
               pickedPictureMode != MacLCHDRPictureModeBright &&
               contentNeedsToneMapping) {
        brightnessAdvice = _NS("A brighter picture is available — it clips some highlight detail and uses more power.");
        suggestsBright = YES;
    } else if (!stream.isHDR && display.supportsHDR) {
        brightnessAdvice = _NS("This display can play standard video in HDR for extra sparkle in highlights.");
    }

    // Rule g: referenceModeActive -> warning "Your display uses a reference mode; brightness is fixed by that preset." (only if no other warning).
    if (warning == nil && display.referenceModeActive) {
        warning = _NS("Your display uses a reference mode; brightness is fixed by that preset.");
    }

    MacLCHDRRecommendation *recommendation =
        [[MacLCHDRRecommendation alloc] initWithPresentation:pickedPresentation
                                                 pictureMode:pickedPictureMode
                                                    headline:headline
                                                      reason:reason
                                            brightnessAdvice:brightnessAdvice
                                                     warning:warning
                                       availablePresentations:stream.availablePresentations
                                     processablePresentations:processablePresentations];
    recommendation.brightnessAdviceSuggestsBright = suggestsBright;
    return recommendation;
}

@end
