/*****************************************************************************
 * MacLCFrameInterpolation.m
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

#import "MacLCFrameInterpolation.h"

#import "main/VLCMain.h"

#import <vlc_configuration.h>

#import "coreinteraction/VLCVideoFilterHelper.h"
#import "playqueue/VLCPlayQueueController.h"
#import "playqueue/VLCPlayerController.h"
#import "extensions/NSString+Helpers.h"
#import "settings/MacLCConfigSafe.h"

#include "../../../video_filter/maclc_frc_geometry.h"

NSString * const MacLCFrameInterpolationChangedNotification =
    @"MacLCFrameInterpolationChangedNotification";

static NSString * const kFilterName = @"maclc_frc";

@implementation MacLCFrameInterpolation

#pragma mark - the filter chain

/* The chain is a colon-separated list of module names in one string. The video
 * output holds the one in force — which is not the saved setting when the
 * chain came from the command line, or when something changed it since. */
static NSMutableArray<NSString *> *FilterListOfString(const char *chain)
{
    NSString * const value = chain ? toNSStr(chain) : @"";

    NSMutableArray<NSString *> * const names = [NSMutableArray array];
    for (NSString * const part in [value componentsSeparatedByString:@":"]) {
        NSString * const trimmed =
            [part stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        if (trimmed.length > 0) {
            [names addObject:trimmed];
        }
    }
    return names;
}

static NSMutableArray<NSString *> *FilterList(void)
{
    char * const chain = MacLCConfigGetPsz("video-filter");
    NSMutableArray<NSString *> * const names = FilterListOfString(chain);
    free(chain);
    return names;
}

+ (BOOL)isEnabled
{
    VLCPlayerController * const player =
        VLCMain.sharedInstance.playQueueController.playerController;
    vout_thread_t * const vout = [player mainVideoOutputThread];
    if (vout != NULL) {
        char * const chain = var_InheritString(vout, "video-filter");
        const BOOL present = [FilterListOfString(chain) containsObject:kFilterName];
        free(chain);
        vout_Release(vout);
        return present;
    }
    return [FilterList() containsObject:kFilterName];
}

+ (void)setEnabled:(BOOL)enabled
{
    NSMutableArray<NSString *> * const names = FilterList();
    const BOOL present = [names containsObject:kFilterName];
    if (present != enabled) {
        if (enabled) {
            [names addObject:kFilterName];
        } else {
            [names removeObject:kFilterName];
        }
        MacLCConfigPutPsz("video-filter",
                          [names componentsJoinedByString:@":"].UTF8String);
        config_SaveConfigFile(getIntf());
    }

    /* And to whatever is playing, so the picture changes now. */
    [VLCVideoFilterHelper setVideoFilter:kFilterName.UTF8String on:enabled];

    [NSNotificationCenter.defaultCenter
        postNotificationName:MacLCFrameInterpolationChangedNotification object:self];
}

/* The filter reads its options when it opens, so a setting only reaches the
 * picture if the filter is taken out of the chain and put back. */
+ (void)restartIfRunning
{
    if (!self.isEnabled) {
        return;
    }
    [VLCVideoFilterHelper setVideoFilter:kFilterName.UTF8String on:NO];
    [VLCVideoFilterHelper setVideoFilter:kFilterName.UTF8String on:YES];
}

#pragma mark - settings

+ (MacLCFrameInterpolationEngine)engine
{
    return (MacLCFrameInterpolationEngine)MacLCConfigGetInt("maclc-frc-engine", 0);
}

+ (void)setEngine:(MacLCFrameInterpolationEngine)engine
{
    if (engine == self.engine) {
        return;
    }
    MacLCConfigPutInt("maclc-frc-engine", engine);
    config_SaveConfigFile(getIntf());
    [self restartIfRunning];
    [NSNotificationCenter.defaultCenter
        postNotificationName:MacLCFrameInterpolationChangedNotification object:self];
}

+ (MacLCFrameInterpolationTarget)target
{
    return (MacLCFrameInterpolationTarget)MacLCConfigGetInt("maclc-frc-target", 0);
}

+ (void)setTarget:(MacLCFrameInterpolationTarget)target
{
    if (target == self.target) {
        return;
    }
    MacLCConfigPutInt("maclc-frc-target", target);
    config_SaveConfigFile(getIntf());
    [self restartIfRunning];
    [NSNotificationCenter.defaultCenter
        postNotificationName:MacLCFrameInterpolationChangedNotification object:self];
}

#pragma mark - words and arithmetic

+ (NSString *)nameForEngine:(MacLCFrameInterpolationEngine)engine
{
    switch (engine) {
        case MacLCFrameInterpolationEngineQuality:    return _NS("Quality");
        case MacLCFrameInterpolationEngineBalanced:   return _NS("Balanced");
        case MacLCFrameInterpolationEngineLowLatency: return _NS("Low Latency");
        case MacLCFrameInterpolationEngineMotion:     return _NS("Motion Compensation");
        case MacLCFrameInterpolationEngineBlend:      return _NS("Blend");
        case MacLCFrameInterpolationEngineAutomatic:
        default:                                      return _NS("Automatic");
    }
}

+ (NSString *)summaryForEngine:(MacLCFrameInterpolationEngine)engine
{
    switch (engine) {
        case MacLCFrameInterpolationEngineQuality:
            return _NS("Optical flow at its most careful. Twice the cost of "
                       "Balanced and not measurably better.");
        case MacLCFrameInterpolationEngineBalanced:
            return _NS("Optical flow. The closest to the truth, but it only "
                       "keeps up at 1080p from a slow source.");
        case MacLCFrameInterpolationEngineLowLatency:
            return _NS("A tenth of the cost of optical flow and nearly as "
                       "convincing, up to 720p only.");
        case MacLCFrameInterpolationEngineMotion:
            return _NS("Motion vectors from the video hardware. The only "
                       "method fast enough for 4K or for 60 fps sources.");
        case MacLCFrameInterpolationEngineBlend:
            return _NS("A plain cross-fade. Costs almost nothing, and looks "
                       "like it on anything that moves quickly.");
        case MacLCFrameInterpolationEngineAutomatic:
        default:
            return _NS("Picks the best method that still runs in real time "
                       "for the video being played.");
    }
}

+ (NSString *)nameForTarget:(MacLCFrameInterpolationTarget)target
{
    switch (target) {
        case MacLCFrameInterpolationTargetSixty:          return _NS("60 fps");
        case MacLCFrameInterpolationTargetHundredTwenty:  return _NS("120 fps");
        case MacLCFrameInterpolationTargetDouble:         return _NS("Twice the Source");
        case MacLCFrameInterpolationTargetDisplay:
        default:                                          return _NS("Match the Display");
    }
}

+ (unsigned)outputFrameRateForSourceFrameRate:(unsigned)sourceFrameRate
{
    if (sourceFrameRate == 0) {
        return 0;
    }

    const unsigned limit = (unsigned)MacLCConfigGetInt("maclc-frc-max-factor", 5);
    unsigned factor;

    if (self.target == MacLCFrameInterpolationTargetDouble) {
        factor = limit < 2 ? 1 : 2;
    } else {
        unsigned wanted;
        switch (self.target) {
            case MacLCFrameInterpolationTargetSixty:         wanted = 60; break;
            case MacLCFrameInterpolationTargetHundredTwenty: wanted = 120; break;
            default: wanted = maclc_frc_display_refresh_rate(); break;
        }
        factor = maclc_frc_factor(sourceFrameRate, wanted, limit);
    }

    return factor < 2 ? 0 : sourceFrameRate * factor;
}

@end
