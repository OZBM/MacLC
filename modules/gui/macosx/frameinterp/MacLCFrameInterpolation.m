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
#include <math.h>

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

+ (BOOL)isRIFEEnabled
{
    return MacLCConfigGetInt("maclc-frc-rife", 0) != 0;
}

+ (void)setRIFEEnabled:(BOOL)RIFEEnabled
{
    if (RIFEEnabled == self.isRIFEEnabled) {
        return;
    }
    MacLCConfigPutInt("maclc-frc-rife", RIFEEnabled ? 1 : 0);
    config_SaveConfigFile(getIntf());
    [self restartIfRunning];
    [NSNotificationCenter.defaultCenter
        postNotificationName:MacLCFrameInterpolationChangedNotification object:self];
}

+ (nullable NSString *)RIFEModelPath
{
    char * const val = MacLCConfigGetPsz("maclc-frc-rife-model");
    if (val == NULL) {
        return nil;
    }
    NSString * const path = toNSStr(val);
    free(val);
    return path.length > 0 ? path : nil;
}

+ (void)setRIFEModelPath:(nullable NSString *)RIFEModelPath
{
    NSString * const current = self.RIFEModelPath;
    if ([current isEqualToString:RIFEModelPath] || (current == nil && (RIFEModelPath == nil || RIFEModelPath.length == 0))) {
        return;
    }
    MacLCConfigPutPsz("maclc-frc-rife-model", RIFEModelPath.UTF8String ?: "");
    config_SaveConfigFile(getIntf());
    [self restartIfRunning];
    [NSNotificationCenter.defaultCenter
        postNotificationName:MacLCFrameInterpolationChangedNotification object:self];
}

+ (float)RIFEScale
{
    return MacLCConfigGetFloat("maclc-frc-rife-scale", 1.0f);
}

+ (void)setRIFEScale:(float)RIFEScale
{
    if (fabsf(RIFEScale - self.RIFEScale) < 0.001f) {
        return;
    }
    MacLCConfigPutFloat("maclc-frc-rife-scale", RIFEScale);
    config_SaveConfigFile(getIntf());
    [self restartIfRunning];
    [NSNotificationCenter.defaultCenter
        postNotificationName:MacLCFrameInterpolationChangedNotification object:self];
}

+ (nullable NSString *)SVPPath
{
    char * const val = MacLCConfigGetPsz("maclc-frc-svp-path");
    if (val == NULL) {
        return nil;
    }
    NSString * const path = toNSStr(val);
    free(val);
    return path.length > 0 ? path : nil;
}

+ (void)setSVPPath:(nullable NSString *)SVPPath
{
    NSString * const current = self.SVPPath;
    if ([current isEqualToString:SVPPath] || (current == nil && (SVPPath == nil || SVPPath.length == 0))) {
        return;
    }
    MacLCConfigPutPsz("maclc-frc-svp-path", SVPPath.UTF8String ?: "");
    config_SaveConfigFile(getIntf());
    [self restartIfRunning];
    [NSNotificationCenter.defaultCenter
        postNotificationName:MacLCFrameInterpolationChangedNotification object:self];
}

+ (nullable NSString *)unavailabilityReasonForEngine:(MacLCFrameInterpolationEngine)engine
{
    if (engine != MacLCFrameInterpolationEngineSVP && engine != MacLCFrameInterpolationEngineRIFE) {
        return nil;
    }

    NSFileManager * const fm = NSFileManager.defaultManager;

    if (engine == MacLCFrameInterpolationEngineSVP) {
        const BOOL vsInstalled = [fm fileExistsAtPath:@"/opt/homebrew/lib/libvapoursynth-script.dylib"]
                              || [fm fileExistsAtPath:@"/usr/local/lib/libvapoursynth-script.dylib"];
        if (!vsInstalled) {
            return _NS("VapourSynth is not installed; it was looked for in /opt/homebrew/lib/ and /usr/local/lib/.");
        }

        NSString * const svpConfig = self.SVPPath;
        NSString *svpBundlePath;
        if (svpConfig.length > 0) {
            if ([svpConfig.pathExtension isEqualToString:@"app"]) {
                svpBundlePath = svpConfig;
            } else {
                NSString * const candidate = [svpConfig stringByAppendingPathComponent:@"SVP 4 Mac.app"];
                svpBundlePath = [fm fileExistsAtPath:candidate] ? candidate : svpConfig;
            }
        } else {
            /* The engine looks in both places, so this has to as well, or an
             * SVP installed for one user alone shows up as missing. */
            NSString * const inHome =
                [NSHomeDirectory() stringByAppendingPathComponent:@"Applications/SVP 4 Mac.app"];
            svpBundlePath = [fm fileExistsAtPath:@"/Applications/SVP 4 Mac.app"]
                ? @"/Applications/SVP 4 Mac.app" : inHome;
        }

        if (![fm fileExistsAtPath:svpBundlePath]) {
            if (svpConfig.length > 0) {
                return [NSString stringWithFormat:
                    _NS("SVP 4 Mac is not installed; it was looked for at %@."), svpConfig];
            } else {
                return _NS("SVP 4 Mac is not installed; it was looked for at "
                           "/Applications/SVP 4 Mac.app and in your own Applications folder.");
            }
        }
        return nil;
    }

    if (engine == MacLCFrameInterpolationEngineRIFE) {
        /* The engine only takes a compiled model or a package, so a folder
         * that holds neither holds nothing, whatever else Finder left in it. */
        BOOL (^holdsAModel)(NSString *) = ^BOOL(NSString *folder) {
            for (NSString *item in [fm contentsOfDirectoryAtPath:folder error:nil]) {
                if ([item.pathExtension isEqualToString:@"mlmodelc"]
                 || [item.pathExtension isEqualToString:@"mlpackage"]) {
                    return YES;
                }
            }
            return NO;
        };
        NSString * const customModel = self.RIFEModelPath;
        if (customModel.length > 0 && [fm fileExistsAtPath:customModel]) {
            return nil;
        }

        NSString * const bundleModels = [NSBundle.mainBundle.resourcePath stringByAppendingPathComponent:@"models"];
        BOOL isDir = NO;
        if ([fm fileExistsAtPath:bundleModels isDirectory:&isDir]) {
            if (isDir) {
                if (holdsAModel(bundleModels)) {
                    return nil;
                }
            } else {
                return nil;
            }
        }

        NSString * const appSupportModels =
            [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/MacLC/models"];
        if ([fm fileExistsAtPath:appSupportModels isDirectory:&isDir]) {
            if (isDir) {
                if (holdsAModel(appSupportModels)) {
                    return nil;
                }
            } else {
                return nil;
            }
        }

        if (customModel.length > 0) {
            return [NSString stringWithFormat:
                _NS("No Core ML RIFE model was found; it was looked for at %@, in MacLC.app/Contents/Resources/models/, and in ~/Library/Application Support/MacLC/models/."), customModel];
        } else {
            return _NS("No Core ML RIFE model was found; it was looked for in MacLC.app/Contents/Resources/models/ and ~/Library/Application Support/MacLC/models/.");
        }
    }

    return nil;
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
        case MacLCFrameInterpolationEngineSVP:        return _NS("SmoothVideo Project");
        case MacLCFrameInterpolationEngineRIFE:       return _NS("RIFE neural network");
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
        case MacLCFrameInterpolationEngineSVP:
            return _NS("Uses the copy of SVP 4 Mac installed on this Mac, "
                       "with its motion vectors or neural network. Requires VapourSynth.");
        case MacLCFrameInterpolationEngineRIFE:
            return _NS("Neural network interpolation on Core ML. Doubles 1080p in "
                       "real time on this Mac, but cannot keep up with 4K.");
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
