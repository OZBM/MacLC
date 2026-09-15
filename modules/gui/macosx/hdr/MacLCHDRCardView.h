/*****************************************************************************
 * MacLCHDRCardView.h: the card MacLC shows when an HDR video starts
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
 * Glass card, top-right over the video (DESIGN_SPEC §10.1): the formats the
 * video carries (the active one filled), what MacLC is playing and why,
 * brightness advice when a boost is possible, and "Options…" to open the HDR
 * panel. Dismisses itself after MacLCDesign.hdrCardLinger unless the pointer
 * is over it.
 */
@interface MacLCHDRCardView : NSView

/** Adds the card to `hostView` (top-right, overlay inset) and animates it in.
 *  Replaces a card already shown in that view. */
+ (void)presentInView:(NSView *)hostView fullScreen:(BOOL)fullScreen;

/** Removes any card from `hostView`. */
+ (void)dismissFromView:(NSView *)hostView;

@end

NS_ASSUME_NONNULL_END
