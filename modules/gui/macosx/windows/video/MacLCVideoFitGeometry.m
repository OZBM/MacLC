/*****************************************************************************
 * MacLCVideoFitGeometry.m: window geometry for fitting a window to a video
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

#import "MacLCVideoFitGeometry.h"

#include <math.h>

/* The smallest video the window ever shows, in points. */
static const CGFloat MacLCVideoFitMinContentWidth = 320.0;
static const CGFloat MacLCVideoFitMinContentHeight = 180.0;

BOOL MacLCVideoFitInputIsUsable(MacLCVideoFitInput input)
{
    if (!isfinite(input.nativeVideoSize.width) || !isfinite(input.nativeVideoSize.height) ||
        input.nativeVideoSize.width <= 0. || input.nativeVideoSize.height <= 0.) {
        return NO;
    }
    if (!isfinite(input.visibleFrame.size.width) || !isfinite(input.visibleFrame.size.height) ||
        input.visibleFrame.size.width <= 0. || input.visibleFrame.size.height <= 0.) {
        return NO;
    }
    if (!isfinite(input.chromeSize.width) || !isfinite(input.chromeSize.height) ||
        input.chromeSize.width < 0. || input.chromeSize.height < 0.) {
        return NO;
    }
    const CGFloat aspect = input.nativeVideoSize.width / input.nativeVideoSize.height;
    return isfinite(aspect) && aspect > 0.;
}

NSRect MacLCVideoFitTargetFrame(MacLCVideoFitInput input)
{
    if (!MacLCVideoFitInputIsUsable(input)) {
        return input.currentFrame;
    }

    const CGFloat scaleFactor = (isfinite(input.scaleFactor) && input.scaleFactor > 0.)
        ? input.scaleFactor : 1.0;
    const CGFloat aspect = input.nativeVideoSize.width / input.nativeVideoSize.height;
    const NSSize chromeSize = input.chromeSize;
    const NSRect visibleFrame = input.visibleFrame;

    CGFloat contentWidth = 0.0;
    CGFloat contentHeight = 0.0;

    switch (input.mode) {
        case MacLCVideoFitModeArranged: {
            CGFloat maxAvailableWidth = MAX(0.0, input.arrangedBounds.size.width - chromeSize.width);
            CGFloat maxAvailableHeight = MAX(0.0, input.arrangedBounds.size.height - chromeSize.height);
            if (maxAvailableWidth <= 0.0 || maxAvailableHeight <= 0.0) {
                contentWidth = input.nativeVideoSize.width / scaleFactor;
                contentHeight = contentWidth / aspect;
            } else if (maxAvailableWidth / aspect <= maxAvailableHeight) {
                contentWidth = maxAvailableWidth;
                contentHeight = contentWidth / aspect;
            } else {
                contentHeight = maxAvailableHeight;
                contentWidth = contentHeight * aspect;
            }
            break;
        }
        case MacLCVideoFitModeKeepWidth: {
            CGFloat currentContentWidth = MAX(0.0, input.currentFrame.size.width - chromeSize.width);
            if (currentContentWidth <= 0.0) {
                contentWidth = input.nativeVideoSize.width / scaleFactor;
            } else {
                contentWidth = currentContentWidth;
            }
            contentHeight = contentWidth / aspect;
            break;
        }
        case MacLCVideoFitModeNative:
        default: {
            contentWidth = input.nativeVideoSize.width / scaleFactor;
            contentHeight = input.nativeVideoSize.height / scaleFactor;
            break;
        }
    }

    const CGFloat maxContentW = MAX(0.0, visibleFrame.size.width - chromeSize.width);
    const CGFloat maxContentH = MAX(0.0, visibleFrame.size.height - chromeSize.height);

    if (contentWidth > maxContentW || contentHeight > maxContentH) {
        CGFloat scaleW = maxContentW > 0.0 ? (maxContentW / contentWidth) : 1.0;
        CGFloat scaleH = maxContentH > 0.0 ? (maxContentH / contentHeight) : 1.0;
        CGFloat downScale = MIN(scaleW, scaleH);
        contentWidth = contentWidth * downScale;
        contentHeight = contentWidth / aspect;
    }

    if (contentWidth < MacLCVideoFitMinContentWidth || contentHeight < MacLCVideoFitMinContentHeight) {
        CGFloat scaleW = contentWidth > 0.0 ? (MacLCVideoFitMinContentWidth / contentWidth) : 1.0;
        CGFloat scaleH = contentHeight > 0.0 ? (MacLCVideoFitMinContentHeight / contentHeight) : 1.0;
        CGFloat upScale = MAX(scaleW, scaleH);
        CGFloat maxAllowedScaleW = contentWidth > 0.0 ? (maxContentW / contentWidth) : upScale;
        CGFloat maxAllowedScaleH = contentHeight > 0.0 ? (maxContentH / contentHeight) : upScale;
        CGFloat maxAllowedScale = MIN(maxAllowedScaleW, maxAllowedScaleH);
        CGFloat effectiveScale = MIN(upScale, maxAllowedScale);
        if (effectiveScale > 1.0) {
            contentWidth = contentWidth * effectiveScale;
            contentHeight = contentWidth / aspect;
        }
    }

    const NSSize targetWindowSize = NSMakeSize(contentWidth + chromeSize.width,
                                               contentHeight + chromeSize.height);

    NSPoint centrePoint;
    if (input.mode == MacLCVideoFitModeArranged) {
        centrePoint = NSMakePoint(NSMidX(input.arrangedBounds), NSMidY(input.arrangedBounds));
    } else {
        centrePoint = NSMakePoint(NSMidX(input.currentFrame), NSMidY(input.currentFrame));
    }

    NSRect targetFrame = NSMakeRect(centrePoint.x - targetWindowSize.width / 2.0,
                                    centrePoint.y - targetWindowSize.height / 2.0,
                                    targetWindowSize.width,
                                    targetWindowSize.height);

    if (NSMinX(targetFrame) < NSMinX(visibleFrame)) {
        targetFrame.origin.x = NSMinX(visibleFrame);
    }
    if (NSMaxX(targetFrame) > NSMaxX(visibleFrame)) {
        targetFrame.origin.x = NSMaxX(visibleFrame) - targetFrame.size.width;
    }
    if (NSMinY(targetFrame) < NSMinY(visibleFrame)) {
        targetFrame.origin.y = NSMinY(visibleFrame);
    }
    if (NSMaxY(targetFrame) > NSMaxY(visibleFrame)) {
        targetFrame.origin.y = NSMaxY(visibleFrame) - targetFrame.size.height;
    }

    return targetFrame;
}
