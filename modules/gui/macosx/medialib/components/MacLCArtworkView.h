/*****************************************************************************
 * MacLCArtworkView.h: artwork with placeholder, badges, progress and hover
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

#import "medialib/MacLCLibraryTypes.h"

@protocol VLCMediaLibraryItemProtocol;

NS_ASSUME_NONNULL_BEGIN

/// The picture of a library item, in the content layer (never glass).
/// Layer-backed, clipped to its shape, drawn at its aspect ratio (the view's
/// width drives its height through an aspect constraint it installs itself).
@interface MacLCArtworkView : NSView

- (instancetype)initWithShape:(MacLCArtworkShape)shape NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithFrame:(NSRect)frameRect NS_UNAVAILABLE;
- (nullable instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;

@property (nonatomic) MacLCArtworkShape shape;

/// nil shows the placeholder: a tertiary-label SF Symbol centred on
/// quaternarySystemFill (film for video, music.note for square, person.fill
/// for circle, unless placeholderSymbolName says otherwise).
@property (nonatomic, nullable) NSImage *image;
@property (nonatomic, copy, nullable) NSString *placeholderSymbolName;

/// Picture badges ("DOLBY VISION", "4K"), drawn bottom-leading inside the
/// artwork on a dark translucent capsule (black 55 %) with white 10 pt
/// semibold text, 4 pt apart. Only for the video shape. Empty hides them.
@property (nonatomic, copy) NSArray<NSString *> *badges;

/// Playback progress in 0...1. Values outside (0, 1) hide the bar. The bar is
/// a 3 pt track (white 35 %) with an accent-colour fill, inset 8 pt from the
/// bottom and sides of the artwork.
@property (nonatomic) CGFloat progress;

/// When YES, hovering shows a centred play.circle.fill symbol (white,
/// 34 pt, drop shadow) over a 20 % black scrim. Clicking it calls playAction.
@property (nonatomic) BOOL showsPlayAffordance;
@property (nonatomic, copy, nullable) void (^playAction)(void);

/// Selection ring: 3 pt accent-colour ring drawn 3 pt outside the artwork
/// shape (so it never covers the picture).
@property (nonatomic, getter=isSelected) BOOL selected;

/// Loads the item's artwork through MacLCArtworkLoader at the view's current
/// size, cancelling any request still pending for a previous item, and
/// reloads when MacLCArtworkLoaderArtworkDidChangeNotification names the
/// item. Passing nil clears the image and cancels.
- (void)setArtworkFromItem:(nullable id<VLCMediaLibraryItemProtocol>)item;

@end

NS_ASSUME_NONNULL_END
