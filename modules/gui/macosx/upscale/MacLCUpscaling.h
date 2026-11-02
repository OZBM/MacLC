/*****************************************************************************
 * MacLCUpscaling.h: the upscaling settings and state, in one place
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

NS_ASSUME_NONNULL_BEGIN

/** Posted when upscaling is switched, its method changes, or the video
 *  output reports a different state (another video, another window size). */
extern NSString * const MacLCUpscalingChangedNotification;

/**
 * Upscaling as the interface sees it. Settings are saved and pushed to the
 * running video output, so the picture changes under the click. The state is
 * what the Metal output publishes, polled once a second while video plays.
 */
@interface MacLCUpscaling : NSObject

@property (class, readwrite, getter=isEnabled) BOOL enabled;   /* maclc-upscale */
/** An enum maclc_upscale_method value. */
@property (class, readwrite) NSInteger method;                  /* maclc-upscale-method */

typedef NS_ENUM(NSInteger, MacLCUpscalingModelState) {
    MacLCUpscalingModelUnsupported,   /* no full super resolution on this Mac */
    MacLCUpscalingModelNotDownloaded,
    MacLCUpscalingModelDownloading,
    MacLCUpscalingModelReady,
};
/** The model Apple Neural 4x needs, downloaded once by the user. */
@property (class, readonly) MacLCUpscalingModelState apple4xModelState;
/** 0..1 while downloading. */
@property (class, readonly) double apple4xModelProgress;
/** Starts the download; changes are posted as MacLCUpscalingChangedNotification. */
+ (void)downloadApple4xModel;
/** The error of the last download that did not end with the model, or nil. */
@property (class, readonly, nullable) NSString *apple4xModelError;

/** FSRCNNX is not shipped (LGPL-3.0): the user accepts its licence, then it is
 *  downloaded once and checked against a pinned SHA-256. Never Unsupported. */
@property (class, readonly) MacLCUpscalingModelState fsrcnnxState;
/** Downloads FSRCNNX, then selects it; call only once the licence is accepted.
 *  Changes are posted as MacLCUpscalingChangedNotification. */
+ (void)activateFSRCNNX;
/** The error of the last FSRCNNX download that failed, or nil. */
@property (class, readonly, nullable) NSString *fsrcnnxError;

/** Starts the state poll; the control bar calls it once. */
+ (void)startWatching;

/** Whether the output is upscaling the picture right now. */
@property (class, readonly, getter=isActive) BOOL active;
/** Short output size for the badge ("4K", "1440p"), nil when not upscaling. */
@property (class, readonly, nullable) NSString *badgeTitle;
/** One or two sentences on what is happening to the video that is playing. */
@property (class, readonly) NSString *statusText;

@end

NS_ASSUME_NONNULL_END
