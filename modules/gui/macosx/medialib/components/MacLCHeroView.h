/*****************************************************************************
 * MacLCHeroView.h: the Home screen's featured video, under the glass
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

@class VLCMediaLibraryMediaItem;

NS_ASSUME_NONNULL_BEGIN

/// MacLC's signature element. A wide frame of the video people are most
/// likely to want next (the most recent unfinished one, else the most
/// recently added), filling the top of Home edge to edge.
///
/// - The picture fills the view (aspect fill) inside an
///   NSBackgroundExtensionView, so it extends under the floating glass
///   sidebar and the toolbar, and the glass has colour to refract
///   (sidebars.md: "Extend visually rich content beneath the sidebar").
/// - A bottom scrim (black 0 % → 60 % over the lower 55 %) keeps the text
///   legible on any frame; text is white regardless of appearance, in the
///   content layer (no glass on content).
/// - Text, bottom-leading, inset 32 pt from the safe area: eyebrow
///   ("CONTINUE WATCHING" or "RECENTLY ADDED", footnote, semibold, +0.6
///   tracking, white 75 %), title (MacLCDesign.largeTitle, bold, 2 lines),
///   detail ("23 min left · 4K · Dolby Vision", callout, white 85 %), then
///   the buttons: "Resume"/"Play" (play.fill; glass, prominent, accent) and
///   "Start Over" (arrow.counterclockwise; glass) for a started video.
/// - Height: 42 % of the window's content height, clamped to 280–460 pt.
/// - The hero fades in (MacLCDesign.motionStandardDuration) when its image
///   arrives; Reduce Motion keeps the fade (no movement anyway).
/// - VoiceOver: one group "Continue watching, <title>, 23 minutes left",
///   the buttons follow.
@interface MacLCHeroView : NSView

@property (nonatomic, nullable) VLCMediaLibraryMediaItem *mediaItem;
@property (nonatomic, copy, nullable) NSString *eyebrow;

@end

NS_ASSUME_NONNULL_END
