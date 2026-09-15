/*****************************************************************************
 * MacLCGlassView.h: MacLC Liquid Glass container view
 *****************************************************************************
 * Copyright (C) 2026 Hazen Studio
 *
 * Authors: MacLC Design System Team
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
 * MacLCGlassView is a surface view that hosts interface content on Liquid Glass
 * (macOS 26 NSGlassEffectView) with an automatic fallback to HUDWindow NSVisualEffectView
 * when running on earlier macOS releases or when Reduce Transparency is enabled.
 *
 * Consumers add subviews to `contentView` rather than directly to this view.
 */
@interface MacLCGlassView : NSView

/**
 * Initializes a glass surface view with the specified frame.
 */
- (instancetype)initWithFrame:(NSRect)frameRect NS_DESIGNATED_INITIALIZER;

/**
 * Initializes a glass surface view from an archive coder.
 */
- (nullable instancetype)initWithCoder:(NSCoder *)coder NS_DESIGNATED_INITIALIZER;

/**
 * The corner radius applied to the glass surface and its fallback visual effect layer.
 */
@property (nonatomic) CGFloat cornerRadius;

/**
 * The content view hosting glass surface subviews.
 * Always add content subviews to this view rather than directly to MacLCGlassView.
 */
@property (nonatomic, strong, readonly) NSView *contentView;

/**
 * Forces dark appearance (NSAppearanceNameDarkAqua) on the glass surface and its content.
 * Essential for video overlays, transport capsules, and HUDs to ensure legibility over any frame.
 */
@property (nonatomic) BOOL forcesDarkAppearance;

/**
 * An optional colour used to tint the glass surface background effect toward.
 */
@property (nonatomic, copy, nullable) NSColor *tintColor;

@end

NS_ASSUME_NONNULL_END
