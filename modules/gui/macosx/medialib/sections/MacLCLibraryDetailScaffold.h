/*****************************************************************************
 * MacLCLibraryDetailScaffold.h: layout shared by the library detail screens
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

@class MacLCDetailHeaderView;

NS_ASSUME_NONNULL_BEGIN

/// Base of the detail screens (album, artist, show, genre, playlist): the
/// header stays in place under the toolbar with the Play button always in
/// reach, an optional choice row (season pop-up, Albums/Songs switch) sits
/// under it, and the body (a grid or a track list) scrolls below.
@interface MacLCLibraryDetailScaffold : NSViewController

- (instancetype)initWithArtworkShape:(MacLCArtworkShape)shape NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithNibName:(nullable NSNibName)nibNameOrNil
                         bundle:(nullable NSBundle *)nibBundleOrNil NS_UNAVAILABLE;
- (nullable instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;

@property (readonly) MacLCDetailHeaderView *headerView;

/// A row of controls under the header (nil removes it).
@property (nonatomic, nullable) NSView *choiceView;

/// Replaces the body: a scroll view or any view filling the remaining space.
- (void)setBodyView:(NSView *)bodyView;

/// Subclasses reload their contents here; called at load and after every
/// library change.
- (void)reloadContents;

/// Forwarded from the section's search field.
- (void)applySearchString:(NSString *)searchString;

@end

NS_ASSUME_NONNULL_END
