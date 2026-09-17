/*****************************************************************************
 * MacLCBrowseItemCollectionViewItem.h: Folder contents grid item
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

@class VLCInputItem;
@class VLCInputNode;
@class MacLCBrowseItemCollectionViewItem;

extern NSString * const MacLCBrowseItemCollectionViewItemIdentifier;

@protocol MacLCBrowseItemCollectionViewItemDelegate <NSObject>

- (void)browseItemDidDoubleClick:(MacLCBrowseItemCollectionViewItem *)item;
- (void)browseItemPlayInstantly:(MacLCBrowseItemCollectionViewItem *)item;
- (void)browseItemOpenContextMenu:(NSEvent *)event forItem:(MacLCBrowseItemCollectionViewItem *)item;

@end

@interface MacLCBrowseItemView : NSView

@property (nonatomic, strong, readonly) NSView *artworkBox;
@property (nonatomic, strong, readonly) NSImageView *thumbnailImageView;
@property (nonatomic, strong, readonly) NSTextField *titleLabel;
@property (nonatomic, strong, readonly) NSTextField *secondaryLabel;
@property (nonatomic, strong, readonly) NSView *durationBadgeView;
@property (nonatomic, strong, readonly) NSTextField *durationLabel;
@property (nonatomic, strong, readonly) NSButton *playButton;

@property (nonatomic, getter=isSelected) BOOL selected;
@property (nonatomic) BOOL isFolder;

/// Height of the two-line title block.
+ (CGFloat)titleHeight;
/// Height an item needs below its 16:9 artwork (title, secondary line, spacing).
+ (CGFloat)heightBelowArtwork;

@end

@interface MacLCBrowseItemCollectionViewItem : NSCollectionViewItem

@property (nonatomic, weak, nullable) id<MacLCBrowseItemCollectionViewItemDelegate> browseDelegate;
@property (nonatomic, strong, nullable) VLCInputItem *representedInputItem;
@property (nonatomic, strong, nullable) VLCInputNode *representedInputNode;
@property (nonatomic, copy, nullable) NSString *secondaryInfoString;

- (void)updateRepresentation;
- (void)openContextMenu:(NSEvent *)event;

@end

NS_ASSUME_NONNULL_END
