/*****************************************************************************
 * MacLCBrowseHeaderView.h: Floating Liquid Glass header & breadcrumb capsule
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

typedef NS_ENUM(NSInteger, MacLCBrowseHeaderMode) {
    MacLCBrowseHeaderModeHome,
    MacLCBrowseHeaderModePath,
};

@class MacLCBrowseHeaderView;

@protocol MacLCBrowseHeaderViewDelegate <NSObject>

- (void)browseHeaderDidClickHome:(MacLCBrowseHeaderView *)headerView;
- (void)browseHeader:(MacLCBrowseHeaderView *)headerView didClickSegmentAtIndex:(NSInteger)index;

@optional
/// Called after the header switched between the home title and the path capsule,
/// which have different heights (see +preferredHeightForMode:).
- (void)browseHeader:(MacLCBrowseHeaderView *)headerView didChangeMode:(MacLCBrowseHeaderMode)mode;

@end

@interface MacLCBrowseHeaderView : NSView

@property (nonatomic, weak, nullable) id<MacLCBrowseHeaderViewDelegate> delegate;
@property (nonatomic) MacLCBrowseHeaderMode mode;

/// Height the header needs in a mode: the home title has a subtitle below it.
+ (CGFloat)preferredHeightForMode:(MacLCBrowseHeaderMode)mode;

- (void)setHomeTitle:(NSString *)title subtitle:(NSString *)subtitle;
- (void)setPathSegments:(NSArray<NSString *> *)segments;
- (void)startLoading;
- (void)stopLoading;

@end

NS_ASSUME_NONNULL_END
