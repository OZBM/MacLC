/*****************************************************************************
 * MacLCGlassContainerView.h: MacLC Liquid Glass container group view
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
 * MacLCGlassContainerView wraps macOS 26 NSGlassEffectContainerView to efficiently
 * batch-process and merge adjacent glass surfaces (such as clusters of glass controls or shapes).
 *
 * On older macOS releases or when Reduce Transparency is enabled, seamlessly falls back
 * to a standard NSView container. Consumers add child views to `contentView`.
 */
@interface MacLCGlassContainerView : NSView

/**
 * Initializes a glass effect container view with the specified frame.
 */
- (instancetype)initWithFrame:(NSRect)frameRect NS_DESIGNATED_INITIALIZER;

/**
 * Initializes a glass effect container view from an archive coder.
 */
- (nullable instancetype)initWithCoder:(NSCoder *)coder NS_DESIGNATED_INITIALIZER;

/**
 * The proximity spacing at which descendant glass effect views merge together.
 * Defaults to 0.0 (sufficient for batch rendering without distortion).
 */
@property (nonatomic) CGFloat spacing;

/**
 * The view hosting descendant glass elements.
 * Consumers add child glass views (e.g. MacLCGlassView) to this view.
 */
@property (nonatomic, strong, readonly) NSView *contentView;

@end

NS_ASSUME_NONNULL_END
