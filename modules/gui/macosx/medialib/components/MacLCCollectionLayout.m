/*****************************************************************************
 * MacLCCollectionLayout.m: compositional layouts for library grids and shelves
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

#import "medialib/components/MacLCCollectionLayout.h"

#import "medialib/components/MacLCMediaCardItem.h"
#import "medialib/components/MacLCSectionHeaderView.h"

NSString * const MacLCSectionHeaderElementKind = @"MacLCSectionHeaderElementKind";

static const CGFloat MacLCLayoutHorizontalInset = 24.0;
static const CGFloat MacLCLayoutTopInset = 16.0;
static const CGFloat MacLCLayoutBottomInset = 32.0;
static const CGFloat MacLCLayoutColumnSpacing = 20.0;
static const CGFloat MacLCLayoutRowSpacing = 28.0;
static const CGFloat MacLCLayoutArtworkTextGap = 8.0;

typedef struct {
    CGFloat minimumWidth;
    CGFloat maximumWidth;
    CGFloat shelfWidth;
    CGFloat aspectRatio;
} MacLCShapeMetrics;

static MacLCShapeMetrics MacLCMetricsForShape(MacLCArtworkShape shape)
{
    switch (shape) {
        case MacLCArtworkShapeVideo:
            return (MacLCShapeMetrics){ 220.0, 300.0, 260.0, 16.0 / 9.0 };
        case MacLCArtworkShapeCircle:
            return (MacLCShapeMetrics){ 140.0, 180.0, 150.0, 1.0 };
        case MacLCArtworkShapeSquare:
        default:
            return (MacLCShapeMetrics){ 160.0, 220.0, 180.0, 1.0 };
    }
}

static CGFloat MacLCItemHeight(MacLCArtworkShape shape, CGFloat width, BOOL hasSubtitle)
{
    const MacLCShapeMetrics metrics = MacLCMetricsForShape(shape);
    return ceil(width / metrics.aspectRatio) + MacLCLayoutArtworkTextGap
        + [MacLCMediaCardItem textBlockHeightWithSubtitle:hasSubtitle];
}

@implementation MacLCCollectionLayout

+ (NSCollectionLayoutBoundarySupplementaryItem *)headerItemWithSubtitle:(BOOL)hasSubtitle
{
    NSCollectionLayoutSize * const size =
        [NSCollectionLayoutSize sizeWithWidthDimension:[NSCollectionLayoutDimension fractionalWidthDimension:1.0]
                                       heightDimension:[NSCollectionLayoutDimension absoluteDimension:
                                                        [MacLCSectionHeaderView heightWithSubtitle:hasSubtitle]]];
    return [NSCollectionLayoutBoundarySupplementaryItem
        boundarySupplementaryItemWithLayoutSize:size
                                    elementKind:MacLCSectionHeaderElementKind
                                      alignment:NSRectAlignmentTop];
}

+ (NSCollectionLayoutSection *)gridSectionWithShape:(MacLCArtworkShape)shape
                                        environment:(id<NSCollectionLayoutEnvironment>)environment
                                          hasHeader:(BOOL)hasHeader
                                        hasSubtitle:(BOOL)hasSubtitle
{
    const MacLCShapeMetrics metrics = MacLCMetricsForShape(shape);
    const CGFloat available = MAX(environment.container.effectiveContentSize.width - 2.0 * MacLCLayoutHorizontalInset,
                                  metrics.minimumWidth);

    /* As many columns as fit at the minimum width, then more while the items
     * would be wider than the maximum: the grid fills the width at any size. */
    NSInteger columns = MAX(1, (NSInteger)floor((available + MacLCLayoutColumnSpacing)
                                                / (metrics.minimumWidth + MacLCLayoutColumnSpacing)));
    CGFloat itemWidth = (available - (columns - 1) * MacLCLayoutColumnSpacing) / columns;
    while (itemWidth > metrics.maximumWidth) {
        columns += 1;
        itemWidth = (available - (columns - 1) * MacLCLayoutColumnSpacing) / columns;
    }
    itemWidth = floor(itemWidth);
    const CGFloat itemHeight = MacLCItemHeight(shape, itemWidth, hasSubtitle);

    NSCollectionLayoutSize * const itemSize =
        [NSCollectionLayoutSize sizeWithWidthDimension:[NSCollectionLayoutDimension absoluteDimension:itemWidth]
                                       heightDimension:[NSCollectionLayoutDimension absoluteDimension:itemHeight]];
    NSCollectionLayoutItem * const item = [NSCollectionLayoutItem itemWithLayoutSize:itemSize];

    NSCollectionLayoutSize * const groupSize =
        [NSCollectionLayoutSize sizeWithWidthDimension:[NSCollectionLayoutDimension fractionalWidthDimension:1.0]
                                       heightDimension:[NSCollectionLayoutDimension absoluteDimension:itemHeight]];
    NSCollectionLayoutGroup * const group =
        [NSCollectionLayoutGroup horizontalGroupWithLayoutSize:groupSize subitem:item count:columns];
    group.interItemSpacing = [NSCollectionLayoutSpacing fixedSpacing:MacLCLayoutColumnSpacing];

    NSCollectionLayoutSection * const section = [NSCollectionLayoutSection sectionWithGroup:group];
    section.interGroupSpacing = MacLCLayoutRowSpacing;
    section.contentInsets = NSDirectionalEdgeInsetsMake(MacLCLayoutTopInset, MacLCLayoutHorizontalInset,
                                                        MacLCLayoutBottomInset, MacLCLayoutHorizontalInset);
    if (hasHeader) {
        section.boundarySupplementaryItems = @[[self headerItemWithSubtitle:NO]];
    }
    return section;
}

+ (NSCollectionLayoutSection *)shelfSectionWithShape:(MacLCArtworkShape)shape
                                         environment:(id<NSCollectionLayoutEnvironment>)environment
                                         hasSubtitle:(BOOL)hasSubtitle
{
    const MacLCShapeMetrics metrics = MacLCMetricsForShape(shape);
    const CGFloat itemHeight = MacLCItemHeight(shape, metrics.shelfWidth, hasSubtitle);

    NSCollectionLayoutSize * const size =
        [NSCollectionLayoutSize sizeWithWidthDimension:[NSCollectionLayoutDimension absoluteDimension:metrics.shelfWidth]
                                       heightDimension:[NSCollectionLayoutDimension absoluteDimension:itemHeight]];
    NSCollectionLayoutItem * const item = [NSCollectionLayoutItem itemWithLayoutSize:size];
    NSCollectionLayoutGroup * const group = [NSCollectionLayoutGroup horizontalGroupWithLayoutSize:size
                                                                                         subitems:@[item]];

    NSCollectionLayoutSection * const section = [NSCollectionLayoutSection sectionWithGroup:group];
    section.orthogonalScrollingBehavior = NSCollectionLayoutSectionOrthogonalScrollingBehaviorContinuous;
    section.interGroupSpacing = MacLCLayoutColumnSpacing;
    section.contentInsets = NSDirectionalEdgeInsetsMake(8.0, MacLCLayoutHorizontalInset,
                                                        24.0, MacLCLayoutHorizontalInset);
    section.boundarySupplementaryItems = @[[self headerItemWithSubtitle:NO]];
    return section;
}

+ (NSCollectionLayoutSection *)fullWidthSectionWithHeight:(CGFloat)height
{
    NSCollectionLayoutSize * const size =
        [NSCollectionLayoutSize sizeWithWidthDimension:[NSCollectionLayoutDimension fractionalWidthDimension:1.0]
                                       heightDimension:[NSCollectionLayoutDimension absoluteDimension:height]];
    NSCollectionLayoutItem * const item = [NSCollectionLayoutItem itemWithLayoutSize:size];
    NSCollectionLayoutGroup * const group = [NSCollectionLayoutGroup horizontalGroupWithLayoutSize:size
                                                                                         subitems:@[item]];
    NSCollectionLayoutSection * const section = [NSCollectionLayoutSection sectionWithGroup:group];
    section.contentInsets = NSDirectionalEdgeInsetsMake(0.0, 0.0, 8.0, 0.0);
    return section;
}

+ (NSCollectionViewCompositionalLayout *)gridLayoutWithShape:(MacLCArtworkShape)shape
                                                 hasSubtitle:(BOOL)hasSubtitle
{
    return [[NSCollectionViewCompositionalLayout alloc] initWithSectionProvider:
        ^NSCollectionLayoutSection * _Nullable(NSInteger sectionIndex,
                                               id<NSCollectionLayoutEnvironment> environment) {
        return [MacLCCollectionLayout gridSectionWithShape:shape
                                               environment:environment
                                                 hasHeader:NO
                                               hasSubtitle:hasSubtitle];
    }];
}

@end
