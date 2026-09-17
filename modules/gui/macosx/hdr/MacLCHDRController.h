/*****************************************************************************
 * MacLCHDRController.h: MacLC's HDR state for the current video
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

#import <Cocoa/Cocoa.h>

#import "hdr/MacLCHDRTypes.h"
#import "hdr/MacLCHDRStreamInfo.h"
#import "hdr/MacLCDisplayInfo.h"
#import "hdr/MacLCHDRAdvisor.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * How often the on-open HDR card appears. Stored in the
 * "maclc-hdr-card" integer option (0 = always, 1 = only when the file offers
 * a choice, 2 = never).
 */
typedef NS_ENUM(NSInteger, MacLCHDRCardPolicy) {
    MacLCHDRCardPolicyAlways = 0,
    MacLCHDRCardPolicyWhenThereIsAChoice = 1,
    MacLCHDRCardPolicyNever = 2,
};

/**
 * Posted (main thread, object = the controller) when the HDR card should be
 * presented for the media that just started. UI code observes it and shows
 * MacLCHDRCardView over the video.
 */
extern NSString * const MacLCHDRCardShouldAppearNotification;

/**
 * MacLCHDRController is the single source of truth for everything HDR the UI
 * shows: what the selected video track contains, what the display under the
 * video window can do, what MacLC recommends, and what is being rendered.
 *
 * Main thread only. Every change of any property below is announced with
 * MacLCHDRStateDidChangeNotification (declared in MacLCHDRTypes.h), posted on
 * the main thread with the controller as object.
 */
@interface MacLCHDRController : NSObject

+ (instancetype)sharedController;

/** The selected video track, or nil when nothing with video is playing. */
@property (readonly, nullable) MacLCHDRStreamInfo *stream;

/** The display the video window is on (main screen when there is none). */
@property (readonly) MacLCDisplayInfo *display;

/** The advisor's pick for stream + display; nil when stream is nil. */
@property (readonly, nullable) MacLCHDRRecommendation *recommendation;

/** What the video output reports it renders ("maclc-hdr-active"), falling
 *  back to the requested presentation until it reports. */
@property (readonly) MacLCHDRPresentation activePresentation;

/** The picture mode in effect (never Auto once a PQ stream plays). */
@property (readonly) MacLCHDRPictureMode activePictureMode;

/** YES when the current file offers more than one valid presentation. */
@property (readonly) BOOL offersChoice;

/** Presentations the running video path can render for this stream. */
@property (readonly) NSSet<NSNumber *> *processablePresentations;

/** Card policy, read from and written to the "maclc-hdr-card" option. */
@property (nonatomic) MacLCHDRCardPolicy cardPolicy;

/** YES when HLG is rendered for the display's current brightness, NO when it
 *  is rendered like HDR10 (maclc-hdr-hlg, set in the HDR settings). */
@property (readonly) BOOL hlgFittedToDisplay;

/**
 * Render the current video with @p presentation. Writes the live
 * "maclc-hdr-presentation" variable on the video output(s) and, when the
 * running output cannot serve it, restarts the video track so a capable
 * output is chosen. No-op for presentations not in stream.availablePresentations.
 */
- (void)applyPresentation:(MacLCHDRPresentation)presentation;

/** Apply a picture mode ("maclc-hdr-picture") to the running output. */
- (void)applyPictureMode:(MacLCHDRPictureMode)pictureMode;

/** Persist the active presentation and picture mode as the defaults used for
 *  every HDR video ("maclc-hdr-presentation"/"maclc-hdr-picture" options). */
- (void)useCurrentChoiceAsDefault;

/** Re-read stream, display and output state now (normally automatic). */
- (void)refresh;

@end

NS_ASSUME_NONNULL_END
