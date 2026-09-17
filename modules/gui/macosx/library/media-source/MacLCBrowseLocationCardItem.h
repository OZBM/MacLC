/*****************************************************************************
 * MacLCBrowseLocationCardItem.h: Location card item for Browse home
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

extern NSString * const MacLCBrowseLocationCardItemIdentifier;

@interface MacLCBrowseLocationCardView : NSView

@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *subtitle;
@property (nonatomic, copy) NSString *symbolName;
@property (nonatomic, getter=isSelected) BOOL selected;

@end

@interface MacLCBrowseLocationCardItem : NSCollectionViewItem

@property (nonatomic, copy) NSString *subtitle;
@property (nonatomic, copy) NSString *symbolName;

@end

NS_ASSUME_NONNULL_END
