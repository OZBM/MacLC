/*****************************************************************************
 * MacLCHDRController.m: MacLC's HDR state for the current video
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

#import "MacLCHDRController.h"

#import "main/VLCMain.h"
#import "playqueue/VLCPlayQueueController.h"
#import "playqueue/VLCPlayerController.h"
#import "library/VLCInputItem.h"
#import "settings/MacLCConfigSafe.h"

#include <vlc_configuration.h>

#include "../../video_output/apple/maclc_hdr_vars.h"

NSString * const MacLCHDRCardShouldAppearNotification = @"MacLCHDRCardShouldAppearNotification";

/* How long after the video starts the card waits, so it lands on a picture
 * rather than on the black of the first frames. */
static const NSTimeInterval kCardDelay = 0.6;
/* The video output reports Dolby Vision / HDR10+ it finds while decoding;
 * read that state this often while a video plays. */
static const NSTimeInterval kPollInterval = 1.0;

@implementation MacLCHDRController
{
    MacLCHDRStreamInfo *_stream;
    MacLCDisplayInfo *_display;
    MacLCHDRRecommendation *_recommendation;
    NSSet<NSNumber *> *_processable;

    MacLCHDRPresentation _requestedPresentation;
    MacLCHDRPictureMode _requestedPicture;
    MacLCHDRPresentation _reportedActive;
    int64_t _caps;

    NSString *_mediaKey;
    BOOL _decidedForMedia;
    BOOL _cardPostedForMedia;
    BOOL _restartPending;
    BOOL _outputKnown;
    BOOL _outputCheckPending;
    NSUInteger _restartsForMedia;
    /* The user's default format when the file did not show it yet (HDR10+
     * and Dolby Vision can be found only while decoding). */
    MacLCHDRPresentation _awaitedDefault;
    CGFloat _publishedDisplayPeak;
    NSTimer *_pollTimer;
}

+ (instancetype)sharedController
{
    static MacLCHDRController *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        shared = [[MacLCHDRController alloc] initPrivate];
    });
    return shared;
}

- (instancetype)initPrivate
{
    self = [super init];
    if (self) {
        _display = [MacLCDisplayInfo displayInfoForScreen:[self videoScreen]];
        [self publishDisplayPeak:_display];
        _processable = [NSSet set];
        _requestedPresentation = [self defaultPresentation];
        _requestedPicture = [self defaultPicture];

        NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
        for (NSString *name in @[VLCPlayerCurrentMediaItemChanged,
                                 VLCPlayerTrackListChanged,
                                 VLCPlayerTrackSelectionChanged,
                                 VLCPlayerListOfVideoOutputThreadsChanged,
                                 VLCPlayerStateChanged]) {
            [center addObserver:self
                       selector:@selector(playerDidChange:)
                           name:name
                         object:nil];
        }
        [center addObserver:self
                   selector:@selector(environmentDidChange:)
                       name:NSApplicationDidChangeScreenParametersNotification
                     object:nil];
        [center addObserver:self
                   selector:@selector(environmentDidChange:)
                       name:NSWindowDidChangeScreenNotification
                     object:nil];
        if (@available(macOS 12.0, *)) {
            [center addObserver:self
                       selector:@selector(environmentDidChange:)
                           name:NSProcessInfoPowerStateDidChangeNotification
                         object:nil];
        }
    }
    return self;
}

- (void)dealloc
{
    [_pollTimer invalidate];
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

#pragma mark - Accessors

- (MacLCHDRStreamInfo *)stream { return _stream; }
- (MacLCDisplayInfo *)display { return _display; }
- (MacLCHDRRecommendation *)recommendation { return _recommendation; }
- (NSSet<NSNumber *> *)processablePresentations { return _processable; }

- (MacLCHDRPresentation)activePresentation
{
    if (_reportedActive != MacLCHDRPresentationAuto)
        return _reportedActive;
    if (_requestedPresentation != MacLCHDRPresentationAuto)
        return _requestedPresentation;
    return _recommendation ? _recommendation.presentation : MacLCHDRPresentationSDR;
}

- (MacLCHDRPictureMode)activePictureMode
{
    if (_requestedPicture != MacLCHDRPictureModeAuto)
        return _requestedPicture;
    return _recommendation ? _recommendation.pictureMode : MacLCHDRPictureModeAuto;
}

- (BOOL)offersChoice
{
    /* SDR is always there for HDR video; a choice means at least two HDR
     * presentations, or one HDR presentation plus picture modes. */
    NSUInteger hdrPresentations = 0;
    for (NSNumber *p in _stream.availablePresentations)
        if (p.integerValue != MacLCHDRPresentationSDR)
            hdrPresentations++;
    return hdrPresentations > 1;
}

- (MacLCHDRCardPolicy)cardPolicy
{
    return (MacLCHDRCardPolicy)MacLCConfigGetInt("maclc-hdr-card",
                                                 MacLCHDRCardPolicyWhenThereIsAChoice);
}

- (void)setCardPolicy:(MacLCHDRCardPolicy)cardPolicy
{
    MacLCConfigPutInt("maclc-hdr-card", cardPolicy);
    config_SaveConfigFile(getIntf());
}

#pragma mark - Defaults

/* Inherited rather than read from the configuration, so an option given on
 * the command line wins over the saved preference. */
- (MacLCHDRPresentation)defaultPresentation
{
    char *value = var_InheritString(getIntf(), MACLC_HDR_VAR_PRESENTATION);
    MacLCHDRPresentation p = value ? MacLCHDRPresentationFromString(@(value))
                                   : MacLCHDRPresentationAuto;
    free(value);
    return p;
}

- (MacLCHDRPictureMode)defaultPicture
{
    char *value = var_InheritString(getIntf(), MACLC_HDR_VAR_PICTURE);
    MacLCHDRPictureMode m = value ? MacLCHDRPictureModeFromString(@(value))
                                  : MacLCHDRPictureModeAuto;
    free(value);
    return m;
}

#pragma mark - Environment

- (VLCPlayerController *)playerController
{
    return VLCMain.sharedInstance.playQueueController.playerController;
}

/* The screen the video is on: a visible window showing video when there is
 * one, otherwise the key window's, otherwise the main screen. */
- (nullable NSScreen *)videoScreen
{
    for (NSWindow *window in NSApp.orderedWindows) {
        if (window.isVisible && [window respondsToSelector:@selector(videoViewController)])
            return window.screen;
    }
    return NSApp.keyWindow.screen ?: NSScreen.mainScreen;
}

- (void)environmentDidChange:(NSNotification *)notification
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self refresh];
    });
}

- (void)playerDidChange:(NSNotification *)notification
{
    dispatch_async(dispatch_get_main_queue(), ^{
        if ([notification.name isEqualToString:VLCPlayerCurrentMediaItemChanged])
            [self mediaDidChange];
        [self refresh];
    });
}

- (void)mediaDidChange
{
    VLCInputItem *media = self.playerController.currentMedia;
    NSString *key = media.MRL;
    if (key != nil && [key isEqualToString:_mediaKey])
        return;

    _mediaKey = [key copy];
    _decidedForMedia = NO;
    _cardPostedForMedia = NO;
    _restartPending = NO;
    _outputKnown = NO;
    _outputCheckPending = NO;
    _restartsForMedia = 0;
    _awaitedDefault = MacLCHDRPresentationAuto;
    _stream = nil;
    _recommendation = nil;
    _reportedActive = MacLCHDRPresentationAuto;
    _caps = 0;

    /* Every file starts from the user's defaults; a per-file choice never
     * leaks into the next file. */
    _requestedPresentation = [self defaultPresentation];
    _requestedPicture = [self defaultPicture];
    VLCPlayerController *player = self.playerController;
    [player setVideoOutputString:MacLCHDRPresentationToString(_requestedPresentation)
                     forVariable:MACLC_HDR_VAR_PRESENTATION];
    [player setVideoOutputString:MacLCHDRPictureModeToString(_requestedPicture)
                     forVariable:MACLC_HDR_VAR_PICTURE];
    [player setVideoOutputBool:NO forVariable:MACLC_HDR_VAR_DOVI_HINT];
}

#pragma mark - Refresh

/* Outputs that open before this controller has decided apply the same rule to
 * "auto" with this number, so they usually pick the right kind first. */
- (void)publishDisplayPeak:(MacLCDisplayInfo *)display
{
    const CGFloat peak = display.contentPeakNits;
    if (fabs(peak - _publishedDisplayPeak) < 1.0)
        return;
    _publishedDisplayPeak = peak;
    [self.playerController setVideoOutputFloat:(float)peak
                                   forVariable:MACLC_HDR_VAR_DISPLAY_PEAK];
}

- (void)refresh
{
    VLCPlayerController *player = self.playerController;

    MacLCDisplayInfo *display = [MacLCDisplayInfo displayInfoForScreen:[self videoScreen]];
    [self publishDisplayPeak:display];

    video_format_t fmt;
    const BOOL hasVideo = [player copySelectedVideoFormat:&fmt];

    _caps = hasVideo ? [player mainVideoOutputInteger:MACLC_HDR_VAR_CAPS fallback:0] : 0;
    NSString *active = hasVideo ? [player mainVideoOutputString:MACLC_HDR_VAR_ACTIVE] : nil;
    const MacLCHDRPresentation reported = active ? MacLCHDRPresentationFromString(active)
                                                 : MacLCHDRPresentationAuto;
    const BOOL reportedChanged = reported != _reportedActive;
    _reportedActive = reported;
    /* The libplacebo output announces itself when it opens, the native one
     * with its first picture. */
    _outputKnown = hasVideo && ((_caps & MACLC_HDR_CAP_CAN_DOVI) != 0 || active != nil);

    MacLCHDRStreamInfo *stream = nil;
    if (hasVideo) {
        /* Dolby Vision the container did not announce, found while decoding. */
        if ((_caps & MACLC_HDR_CAP_DOVI_SEEN) && !fmt.dovi.rpu_present) {
            fmt.dovi.rpu_present = 1;
            fmt.dovi.bl_present = 1;
        }
        stream = [MacLCHDRStreamInfo streamInfoWithVideoFormat:&fmt
                                                 hdr10PlusSeen:(_caps & MACLC_HDR_CAP_HDR10PLUS_SEEN) != 0];
    }

    /* Every presentation the file offers can be rendered: the native output
     * shows HDR10, HLG and SDR, the libplacebo output Dolby Vision and HDR10+,
     * and switching between them restarts the video track. */
    NSSet<NSNumber *> *processable =
        stream ? [NSSet setWithArray:stream.availablePresentations] : [NSSet set];

    MacLCHDRRecommendation *recommendation = stream
        ? [MacLCHDRAdvisor recommendationForStream:stream
                                           display:display
                                       processable:processable]
        : nil;

    const BOOL changed = (stream != _stream && ![stream isEqual:_stream])
                      || ![display isEqual:_display]
                      || reportedChanged
                      || recommendation.presentation != _recommendation.presentation
                      || recommendation.pictureMode != _recommendation.pictureMode
                      || ![recommendation.reason isEqualToString:_recommendation.reason ?: @""];
    _stream = stream;
    _display = display;
    _processable = processable;
    _recommendation = recommendation;

    [self updatePolling:hasVideo];

    if (stream != nil && stream.isHDR && !_decidedForMedia)
        [self decideForCurrentMedia];
    else if (_awaitedDefault != MacLCHDRPresentationAuto
             && [stream.availablePresentations containsObject:@(_awaitedDefault)]) {
        const MacLCHDRPresentation presentation = _awaitedDefault;
        _awaitedDefault = MacLCHDRPresentationAuto;
        [self requestPresentation:presentation userInitiated:NO];
    } else if (_outputCheckPending)
        [self reconcileOutput];

    if (stream != nil && stream.isHDR && !_cardPostedForMedia)
        [self scheduleCardIfNeeded];

    if (changed)
        [NSNotificationCenter.defaultCenter postNotificationName:MacLCHDRStateDidChangeNotification
                                                          object:self];
}

- (void)updatePolling:(BOOL)hasVideo
{
    if (hasVideo && _pollTimer == nil) {
        __weak typeof(self) weakSelf = self;
        _pollTimer = [NSTimer scheduledTimerWithTimeInterval:kPollInterval
                                                     repeats:YES
                                                       block:^(NSTimer *timer) {
            [weakSelf pollVideoOutput];
        }];
        _pollTimer.tolerance = 0.3;
    } else if (!hasVideo && _pollTimer != nil) {
        [_pollTimer invalidate];
        _pollTimer = nil;
    }
}

/* Cheap check of what the video output reports; a full refresh only when it
 * changed (dynamic metadata found, presentation switched). */
- (void)pollVideoOutput
{
    VLCPlayerController *player = self.playerController;
    const int64_t caps = [player mainVideoOutputInteger:MACLC_HDR_VAR_CAPS fallback:0];
    NSString *active = [player mainVideoOutputString:MACLC_HDR_VAR_ACTIVE];
    const MacLCHDRPresentation reported = active ? MacLCHDRPresentationFromString(active)
                                                 : MacLCHDRPresentationAuto;
    const CGFloat headroom = _display.currentHeadroom;
    MacLCDisplayInfo *display = [MacLCDisplayInfo displayInfoForScreen:[self videoScreen]];
    if (caps != _caps || reported != _reportedActive
        || fabs(display.currentHeadroom - headroom) > 0.25)
        [self refresh];
}

#pragma mark - Decisions

/* Once per file: apply the user's default, or MacLC's recommendation when the
 * default is Automatic. */
- (void)decideForCurrentMedia
{
    _decidedForMedia = YES;
    MacLCHDRPresentation target = _requestedPresentation;
    if (target == MacLCHDRPresentationAuto
        || ![_stream.availablePresentations containsObject:@(target)]) {
        /* A default the file may still reveal is applied when it does. */
        if (target == MacLCHDRPresentationHDR10Plus
            || target == MacLCHDRPresentationDolbyVision)
            _awaitedDefault = target;
        target = _recommendation.presentation;
    }
    if (target == MacLCHDRPresentationAuto)
        return;
    [self requestPresentation:target userInitiated:NO];
}

- (void)scheduleCardIfNeeded
{
    const MacLCHDRCardPolicy policy = self.cardPolicy;
    if (policy == MacLCHDRCardPolicyNever)
        return;
    if (policy == MacLCHDRCardPolicyWhenThereIsAChoice && !self.offersChoice)
        return;
    _cardPostedForMedia = YES;
    NSString *key = _mediaKey;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kCardDelay * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if (key == self->_mediaKey || [key isEqualToString:self->_mediaKey])
            [NSNotificationCenter.defaultCenter
                postNotificationName:MacLCHDRCardShouldAppearNotification object:self];
    });
}

- (BOOL)presentationNeedsLibplaceboOutput:(MacLCHDRPresentation)presentation
{
    return presentation == MacLCHDRPresentationDolbyVision
        || presentation == MacLCHDRPresentationHDR10Plus
        || _stream.doviProfile == 5;
}

- (void)requestPresentation:(MacLCHDRPresentation)presentation userInitiated:(BOOL)userInitiated
{
    if (_stream == nil || ![_stream.availablePresentations containsObject:@(presentation)])
        return;

    VLCPlayerController *player = self.playerController;
    _requestedPresentation = presentation;

    const BOOL wantsDoVi = presentation == MacLCHDRPresentationDolbyVision
                        || _stream.doviProfile == 5;
    [player setVideoOutputBool:wantsDoVi && _stream.doviProfile >= 0
                   forVariable:MACLC_HDR_VAR_DOVI_HINT];
    [player setVideoOutputString:MacLCHDRPresentationToString(presentation)
                     forVariable:MACLC_HDR_VAR_PRESENTATION];

    /* The restart budget guards against automatic ping-pong, not against
     * the user changing their mind - who also overrides an awaited default. */
    if (userInitiated) {
        _restartsForMedia = 0;
        _awaitedDefault = MacLCHDRPresentationAuto;
    }
    _outputCheckPending = YES;
    [self reconcileOutput];

    if (userInitiated)
        [NSNotificationCenter.defaultCenter postNotificationName:MacLCHDRStateDidChangeNotification
                                                          object:self];
}

/* Keeps each presentation on the output built for it: Dolby Vision and HDR10+
 * need the libplacebo output, the others are cheapest on the native one. A
 * running output of the wrong kind is replaced by restarting the video track;
 * SDR is served live by both. Until an output has said which kind it is there
 * is nothing to replace: the one being opened reads the request itself. */
- (void)reconcileOutput
{
    if (!_outputKnown || _restartPending || _stream == nil)
        return;
    _outputCheckPending = NO;

    const MacLCHDRPresentation presentation = _requestedPresentation;
    if (presentation == MacLCHDRPresentationAuto || presentation == MacLCHDRPresentationSDR)
        return;

    const BOOL runningLibplacebo = (_caps & MACLC_HDR_CAP_CAN_DOVI) != 0;
    if ([self presentationNeedsLibplaceboOutput:presentation] == runningLibplacebo)
        return;

    /* An output that keeps coming back as the wrong kind is not worth a
     * third interruption: keep playing with what it can do. */
    if (_restartsForMedia >= 2)
        return;
    _restartsForMedia++;
    _restartPending = YES;
    [self.playerController restartSelectedVideoTrack];
    NSString *key = _mediaKey;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if (key != self->_mediaKey && ![key isEqualToString:self->_mediaKey])
            return;
        self->_restartPending = NO;
        [self refresh];
    });
}

#pragma mark - Public actions

- (void)applyPresentation:(MacLCHDRPresentation)presentation
{
    [self requestPresentation:presentation userInitiated:YES];
    [self refresh];
}

- (void)applyPictureMode:(MacLCHDRPictureMode)pictureMode
{
    _requestedPicture = pictureMode;
    [self.playerController setVideoOutputString:MacLCHDRPictureModeToString(pictureMode)
                                    forVariable:MACLC_HDR_VAR_PICTURE];
    [NSNotificationCenter.defaultCenter postNotificationName:MacLCHDRStateDidChangeNotification
                                                      object:self];
}

- (void)useCurrentChoiceAsDefault
{
    MacLCConfigPutPsz(MACLC_HDR_VAR_PRESENTATION,
                      MacLCHDRPresentationToString(self.activePresentation).UTF8String);
    MacLCConfigPutPsz(MACLC_HDR_VAR_PICTURE,
                      MacLCHDRPictureModeToString(self.activePictureMode).UTF8String);
    config_SaveConfigFile(getIntf());
}

@end
