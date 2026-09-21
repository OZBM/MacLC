/*****************************************************************************
 * MacLCVideoFitGeometry.h: window geometry for fitting a window to a video
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

/**
 * How a window picks its size for the video it shows.
 *
 * - Native: the video's own pixel size, converted to points.
 * - Arranged: the largest fit inside bounds the window manager imposed
 *   (a tiled half, a tiled quarter, a zoomed window).
 * - KeepWidth: the width the user chose is kept and the height follows.
 */
typedef NS_ENUM(NSInteger, MacLCVideoFitMode) {
    MacLCVideoFitModeNative,
    MacLCVideoFitModeArranged,
    MacLCVideoFitModeKeepWidth
};

/** One fit decision's inputs. Sizes are in points, except the video size. */
typedef struct {
    NSSize nativeVideoSize;  /**< video size in pixels, SAR applied */
    NSSize chromeSize;       /**< window frame minus the video view */
    NSRect currentFrame;     /**< the window's frame right now */
    NSRect arrangedBounds;   /**< bounds to fit into, arranged mode only */
    NSRect visibleFrame;     /**< the screen's usable area */
    CGFloat scaleFactor;     /**< the screen's backing scale factor */
    MacLCVideoFitMode mode;
} MacLCVideoFitInput;

/**
 * Whether a fit can be computed at all: a video with a usable size, a finite
 * aspect ratio and a screen to put it on.
 */
BOOL MacLCVideoFitInputIsUsable(MacLCVideoFitInput input);

/**
 * The frame the window should take, aspect ratio preserved, never larger than
 * the visible frame, never smaller than 320x180 points of video, centred on
 * the current frame's centre (on the arranged bounds' centre in arranged
 * mode) and moved back inside the visible frame if it sticks out.
 *
 * An input that is not usable gives the current frame back unchanged.
 */
NSRect MacLCVideoFitTargetFrame(MacLCVideoFitInput input);

NS_ASSUME_NONNULL_END
