/*****************************************************************************
 * MacLCTradeoffMeterView.h: what an HDR picture mode gives and costs
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

NS_ASSUME_NONNULL_BEGIN

/**
 * Four labelled three-dot meters - Brightness, Highlight detail, Faithful to
 * master, Battery - that make the consequence of a picture mode visible at a
 * glance. The dots animate when the mode changes.
 */
@interface MacLCTradeoffMeterView : NSView

/** Updates the meters for a picture mode. `needsToneMapping` is whether the
 *  video is brighter than the display (when it is not, every mode keeps full
 *  highlight detail and accuracy, except Bright). */
- (void)showPictureMode:(MacLCHDRPictureMode)mode
       needsToneMapping:(BOOL)needsToneMapping
               animated:(BOOL)animated;

@end

NS_ASSUME_NONNULL_END
