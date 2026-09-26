/*****************************************************************************
 * MacLCNowPlayingBar.h: floating Liquid Glass mini player of the library
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

@class VLCLibraryWindow;

NS_ASSUME_NONNULL_BEGIN

/// The one custom glass surface of the library window: a capsule
/// (MacLCGlassView, regular variant, corner radius = half height) floating
/// 16 pt above the bottom of the content area, centred, width
/// min(760, content width - 48), height 60. Content, leading to trailing:
///   artwork 40 × 40 (radius 6; a live-video poster for video) — click shows
///   the video / detached audio window ("Show Video" / "Show Player"),
///   title (headline, 1 line) over artist · album or "Video" (subheadline,
///   secondaryLabel), 8 pt,
///   backward.fill, play.fill/pause.fill (28 pt symbol, 36 × 36 target),
///   forward.fill, 12 pt,
///   elapsed (monospaced digits, footnote) · slider (flexible, min 160) ·
///   remaining, 12 pt,
///   speaker.wave.2.fill button opening a popover with a volume slider.
/// Symbols and text are labelColor/secondaryLabelColor only (no tint on
/// glass: liquid-glass.md › Color on glass). Every button has an
/// accessibilityLabel and an identical toolTip; hit targets ≥ 28 × 28.
/// Shown while the queue has a current item and the window is not showing
/// embedded video; hidden otherwise. Show/hide: fade + 8 pt slide
/// (MacLCDesign.animateEntranceOfView:/animateExitOfView:), fade only under
/// Reduce Motion. Reduce Transparency: MacLCGlassView's opaque fallback.
/// Content views scrolled beneath get an extra bottom inset equal to the
/// bar's height + 32 while it shows (additionalSafeAreaInsets on the
/// content view controller).
@interface MacLCNowPlayingBar : NSView

- (instancetype)initWithLibraryWindow:(VLCLibraryWindow *)libraryWindow;

- (void)setShown:(BOOL)shown animated:(BOOL)animated;
@property (readonly, getter=isShown) BOOL shown;

/// Height including the 16 pt gap under it, for content insets.
@property (class, readonly) CGFloat reservedHeight;

@end

NS_ASSUME_NONNULL_END
