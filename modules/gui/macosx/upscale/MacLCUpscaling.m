/*****************************************************************************
 * MacLCUpscaling.m
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

#import "MacLCUpscaling.h"

#import "main/VLCMain.h"

#import <vlc_configuration.h>
#import <VideoToolbox/VideoToolbox.h>
#import <CommonCrypto/CommonDigest.h>

#import "extensions/NSString+Helpers.h"
#import "playqueue/VLCPlayQueueController.h"
#import "playqueue/VLCPlayerController.h"
#import "settings/MacLCConfigSafe.h"

#include "../../../video_output/apple/maclc_upscale_vars.h"

NSString * const MacLCUpscalingChangedNotification = @"MacLCUpscalingChangedNotification";

static NSTimer *gPoll;
static NSString *gLastState;
static BOOL gDownloading;
static NSString *gDownloadError;
static BOOL gFSRCNNXDownloading;
static NSString *gFSRCNNXError;

@implementation MacLCUpscaling

static VLCPlayerController *Player(void)
{
    return VLCMain.sharedInstance.playQueueController.playerController;
}

static void Changed(void)
{
    [NSNotificationCenter.defaultCenter
        postNotificationName:MacLCUpscalingChangedNotification object:nil];
}

static NSString *StateString(void)
{
    return [Player() mainVideoOutputString:MACLC_UPSCALE_VAR_STATE];
}

static struct maclc_upscale_state State(void)
{
    struct maclc_upscale_state st;
    maclc_upscale_parse_state(StateString().UTF8String, &st);
    return st;
}

static NSString *SizeLabel(unsigned w, unsigned h)
{
    char buf[16];
    maclc_upscale_size_label(w, h, buf, sizeof(buf));
    return toNSStr(buf);
}

+ (void)startWatching
{
    if (gPoll != nil)
        return;
    gPoll = [NSTimer scheduledTimerWithTimeInterval:1.0 repeats:YES block:^(NSTimer * __unused timer) {
        NSString * const state = StateString();
        if (state != gLastState && ![state isEqualToString:gLastState]) {
            gLastState = state;
            Changed();
        }
    }];
    gPoll.tolerance = 0.3;
}

#pragma mark - settings

+ (BOOL)isEnabled
{
    return MacLCConfigGetInt(MACLC_UPSCALE_VAR_ENABLED, 0) != 0;
}

+ (void)setEnabled:(BOOL)enabled
{
    MacLCConfigPutInt(MACLC_UPSCALE_VAR_ENABLED, enabled ? 1 : 0);
    config_SaveConfigFile(getIntf());

    VLCPlayerController * const player = Player();
    [player setVideoOutputBool:enabled forVariable:MACLC_UPSCALE_VAR_ENABLED];
    /* Only the Metal output upscales, and it publishes the state: without
     * one, the video is on the native output and has to be moved over. */
    if (enabled && player.selectedVideoTrack != nil && StateString() == nil)
        [player restartSelectedVideoTrack];
    Changed();
}

+ (NSInteger)method
{
    char * const method = MacLCConfigGetPsz(MACLC_UPSCALE_VAR_METHOD);
    const enum maclc_upscale_method m = maclc_upscale_parse_method(method);
    free(method);
    return m;
}

+ (void)setMethod:(NSInteger)method
{
    if (method < 0 || method >= MACLC_UPSCALE_METHOD_COUNT)
        return;
    NSString * const name = toNSStr(maclc_upscale_method_names[method]);
    MacLCConfigPutPsz(MACLC_UPSCALE_VAR_METHOD, name.UTF8String);
    config_SaveConfigFile(getIntf());
    [Player() setVideoOutputString:name forVariable:MACLC_UPSCALE_VAR_METHOD];
    Changed();
}

#pragma mark - Apple Neural 4x model

/* The model is one for every size; a 360p configuration asks about it. */
static VTSuperResolutionScalerConfiguration *ModelConfiguration(void)
{
    if (!VTSuperResolutionScalerConfiguration.isSupported
     || ![VTSuperResolutionScalerConfiguration.supportedScaleFactors containsObject:@4])
        return nil;
    return [[VTSuperResolutionScalerConfiguration alloc]
        initWithFrameWidth:640 frameHeight:360 scaleFactor:4
                 inputType:VTSuperResolutionScalerConfigurationInputTypeVideo
        usePrecomputedFlow:NO
     qualityPrioritization:VTSuperResolutionScalerConfigurationQualityPrioritizationNormal
                  revision:VTSuperResolutionScalerConfiguration.defaultRevision];
}

+ (MacLCUpscalingModelState)apple4xModelState
{
    VTSuperResolutionScalerConfiguration * const c = ModelConfiguration();
    if (c == nil)
        return MacLCUpscalingModelUnsupported;
    switch (c.configurationModelStatus) {
        case VTSuperResolutionScalerConfigurationModelStatusReady:
            return MacLCUpscalingModelReady;
        case VTSuperResolutionScalerConfigurationModelStatusDownloading:
            return MacLCUpscalingModelDownloading;
        default:
            return gDownloading ? MacLCUpscalingModelDownloading : MacLCUpscalingModelNotDownloaded;
    }
}

+ (double)apple4xModelProgress
{
    return ModelConfiguration().configurationModelPercentageAvailable;
}

+ (nullable NSString *)apple4xModelError
{
    return gDownloadError;
}

+ (void)downloadApple4xModel
{
    VTSuperResolutionScalerConfiguration * const c = ModelConfiguration();
    if (c == nil || gDownloading
     || c.configurationModelStatus == VTSuperResolutionScalerConfigurationModelStatusReady)
        return;
    gDownloading = YES;
    gDownloadError = nil;
    NSTimer * const progress = [NSTimer scheduledTimerWithTimeInterval:0.5 repeats:YES
                                                                block:^(NSTimer * __unused t) {
        Changed();
    }];
    [c downloadConfigurationModelWithCompletionHandler:^(NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [progress invalidate];
            gDownloading = NO;
            /* the handler can report an error with the model in place, so the
             * status decides */
            if (c.configurationModelStatus != VTSuperResolutionScalerConfigurationModelStatusReady)
                gDownloadError = error.localizedDescription ?: _NS("The download did not finish.");
            else {
                /* asked for to be used: use it */
                MacLCUpscaling.method = MACLC_UPSCALE_APPLE4X;
                MacLCUpscaling.enabled = YES;
            }
            Changed();
        });
    }];
    Changed();
}

#pragma mark - FSRCNNX

static NSURL *FSRCNNXFile(void)
{
    NSURL * const support = [NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory
                                                                 inDomains:NSUserDomainMask].firstObject;
    return [[support URLByAppendingPathComponent:@MACLC_UPSCALE_MODELS_DIR isDirectory:YES]
            URLByAppendingPathComponent:@MACLC_UPSCALE_FSRCNNX_FILE];
}

static NSString *SHA256Hex(NSData *data)
{
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
    NSMutableString * const hex = [NSMutableString stringWithCapacity:2 * sizeof(digest)];
    for (size_t i = 0; i < sizeof(digest); i++)
        [hex appendFormat:@"%02x", digest[i]];
    return hex;
}

+ (MacLCUpscalingModelState)fsrcnnxState
{
    if (gFSRCNNXDownloading)
        return MacLCUpscalingModelDownloading;
    return [FSRCNNXFile() checkResourceIsReachableAndReturnError:NULL]
        ? MacLCUpscalingModelReady : MacLCUpscalingModelNotDownloaded;
}

+ (nullable NSString *)fsrcnnxError
{
    return gFSRCNNXError;
}

+ (void)activateFSRCNNX
{
    if (gFSRCNNXDownloading || self.fsrcnnxState == MacLCUpscalingModelReady)
        return;
    gFSRCNNXDownloading = YES;
    gFSRCNNXError = nil;
    NSURL * const url = [NSURL URLWithString:@MACLC_UPSCALE_FSRCNNX_URL];
    [[NSURLSession.sharedSession dataTaskWithURL:url
                               completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSString *failure = error.localizedDescription;
        if (failure == nil && ((NSHTTPURLResponse *)response).statusCode != 200)
            failure = _NS("The download did not finish.");
        /* the file is code the GPU runs: only the reviewed version is kept */
        else if (failure == nil && ![SHA256Hex(data) isEqualToString:@MACLC_UPSCALE_FSRCNNX_SHA256])
            failure = _NS("The downloaded file is not the expected one, so it was not kept.");
        if (failure == nil) {
            NSURL * const file = FSRCNNXFile();
            NSError *writeError = nil;
            if (![NSFileManager.defaultManager createDirectoryAtURL:file.URLByDeletingLastPathComponent
                                        withIntermediateDirectories:YES attributes:nil error:&writeError]
             || ![data writeToURL:file options:NSDataWritingAtomic error:&writeError])
                failure = writeError.localizedDescription;
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            gFSRCNNXDownloading = NO;
            gFSRCNNXError = failure;
            if (failure == nil) {
                MacLCUpscaling.method = MACLC_UPSCALE_FSRCNNX;
                MacLCUpscaling.enabled = YES;
            }
            Changed();
        });
    }] resume];
    Changed();
}

#pragma mark - state

+ (BOOL)isActive
{
    return self.isEnabled && State().active;
}

+ (nullable NSString *)badgeTitle
{
    if (!self.isEnabled)
        return nil;
    const struct maclc_upscale_state st = State();
    return st.active ? SizeLabel(st.out_w, st.out_h) : nil;
}

+ (NSString *)statusText
{
    if (!self.isEnabled)
        return _NS("Off. The display scales videos smaller than the window.");

    NSString * const string = StateString();
    if (Player().selectedVideoTrack == nil || string == nil)
        return _NS("Upscales the next video that is smaller than its window.");

    const struct maclc_upscale_state st = State();
    if (!st.active)
        return _NS("This video is shown at its own size or smaller, so there is "
                   "nothing to upscale. Make the window larger to upscale it.");

    NSMutableArray<NSString *> * const passes = [NSMutableArray array];
    for (NSString *pass in [toNSStr(st.path) componentsSeparatedByString:@"+"]) {
        NSDictionary<NSString *, NSString *> * const names = @{
            @"neural": _NS("Neural super resolution"),
            @"neural4x": _NS("Apple Neural 4x"),
            @"anime": _NS("ArtCNN"),
            @"anime4k": _NS("Anime4K"),
            @"fsrcnnx": _NS("FSRCNNX"),
            @"sharp": _NS("FSR 1"),
            @"nis": _NS("NIS"),
            @"fast": _NS("MetalFX"),
            @"classic": _NS("EWA Lanczos"),
        };
        [passes addObject:names[pass] ?: pass];
    }
    NSString * const how = [passes componentsJoinedByString:@" + "];

    NSString * const playing =
        [NSString stringWithFormat:_NS("Playing %@ as %@ · %@."),
            SizeLabel(st.in_w, st.in_h), SizeLabel(st.out_w, st.out_h), how];

    NSString *why = nil;
    if (strcmp(st.why, "hdr") == 0)
        why = _NS("The first pass is for SDR video; HDR and SDR to HDR skip it.");
    else if (strcmp(st.why, "size") == 0)
        why = _NS("This video is too large for the first pass, or the window too small for it.");
    else if (strcmp(st.why, "power") == 0)
        why = _NS("On battery or in Low Power Mode, the neural pass is off to save energy.");
    else if (strcmp(st.why, "thermal") == 0)
        why = _NS("The Mac is running hot, so the neural pass is off.");
    else if (strcmp(st.why, "slow") == 0)
        why = _NS("The first pass could not keep up with this frame rate on this Mac.");
    else if (strcmp(st.why, "unsupported") == 0)
        why = _NS("Neural super resolution needs macOS 26 on Apple silicon.");
    else if (strcmp(st.why, "loading") == 0)
        why = _NS("The neural model is starting.");
    else if (strcmp(st.why, "model") == 0)
        why = self.method == MACLC_UPSCALE_FSRCNNX
            ? _NS("FSRCNNX is not installed: activate it in this panel.")
            : _NS("Apple Neural 4x needs its model: download it in this panel.");
    else if (strcmp(st.why, "format") == 0)
        why = _NS("This video's pixel format cannot go through the first pass.");

    return why != nil ? [NSString stringWithFormat:@"%@ %@", playing, why] : playing;
}

@end
