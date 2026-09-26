/*****************************************************************************
 * MacLCCollectionLayout.h: compositional layouts for library grids and shelves
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

NS_ASSUME_NONNULL_BEGIN

/// Supplementary element kind of MacLCSectionHeaderView in library layouts.
extern NSString * const MacLCSectionHeaderElementKind;

/// Metrics (points), shared by every library screen:
/// - content insets: 24 leading/trailing, 16 top, 32 bottom per section;
/// - grid: columns = as many as fit with an item width between the shape's
///   minimum and maximum (video 220–300, square 160–220, circle 140–180);
///   20 between columns, 28 between rows;
/// - shelf: one row scrolling horizontally (orthogonal scrolling, group
///   paging off), fixed item width (video 260, square 180, circle 150),
///   20 between items;
/// - item height = artwork height (width / aspect) + 8 + text block height.
@interface MacLCCollectionLayout : NSObject

/// A vertical, adaptive grid section, with an optional pinned-free header.
+ (NSCollectionLayoutSection *)gridSectionWithShape:(MacLCArtworkShape)shape
                                        environment:(id<NSCollectionLayoutEnvironment>)environment
                                          hasHeader:(BOOL)hasHeader
                                        hasSubtitle:(BOOL)hasSubtitle;

/// A single-row, horizontally scrolling shelf section with a header.
+ (NSCollectionLayoutSection *)shelfSectionWithShape:(MacLCArtworkShape)shape
                                         environment:(id<NSCollectionLayoutEnvironment>)environment
                                         hasSubtitle:(BOOL)hasSubtitle;

/// A full-width section holding one item of the given absolute height
/// (the Home hero, a detail header).
+ (NSCollectionLayoutSection *)fullWidthSectionWithHeight:(CGFloat)height;

/// A whole layout made of one grid section.
+ (NSCollectionViewCompositionalLayout *)gridLayoutWithShape:(MacLCArtworkShape)shape
                                                 hasSubtitle:(BOOL)hasSubtitle;

@end

NS_ASSUME_NONNULL_END
