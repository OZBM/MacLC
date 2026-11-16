/*****************************************************************************
 * VLCLibraryCollectionViewDelegate.m: MacOS X interface module
 *****************************************************************************
 * Copyright (C) 2022 VLC authors and VideoLAN
 *
 * Authors: Claudio Cambra <developer@claudiocambra.com>
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

#import "VLCLibraryCollectionViewDelegate.h"

#import "VLCLibraryCollectionViewDataSource.h"
#import "VLCLibraryCollectionViewFlowLayout.h"
#import "VLCLibraryCollectionViewItem.h"
#import "VLCLibraryDataTypes.h"
#import "medialib/data/MacLCLibraryActions.h"

@implementation VLCLibraryCollectionViewDelegate

- (instancetype)init
{
    self = [super init];
    if (self) {
        _dynamicItemSizing = YES;
        _staticItemSize = VLCUIUnits.defaultMediaItemCollectionViewItemSize;
        _itemsAspectRatio = VLCLibraryCollectionViewItemAspectRatioDefaultItem;
    }
    return self;
}

- (void)collectionView:(NSCollectionView *)collectionView didSelectItemsAtIndexPaths:(NSSet<NSIndexPath *> *)indexPaths
{
    NSIndexPath *indexPath = indexPaths.anyObject;
    if (!indexPath) {
        return;
    }

    if (collectionView.selectionIndexPaths.count != 1) {
        return;
    }

    VLCLibraryCollectionViewFlowLayout *collectionViewFlowLayout = (VLCLibraryCollectionViewFlowLayout*)collectionView.collectionViewLayout;
    if(collectionViewFlowLayout) {
        [collectionViewFlowLayout expandDetailSectionAtIndex:indexPath];
    }
}

- (void)collectionView:(NSCollectionView *)collectionView didDeselectItemsAtIndexPaths:(NSSet<NSIndexPath *> *)indexPaths
{
    if (collectionView.selectionIndexPaths.count > 0) {
        return;
    }

    VLCLibraryCollectionViewFlowLayout * const collectionViewFlowLayout = 
        (VLCLibraryCollectionViewFlowLayout*)collectionView.collectionViewLayout;

    if (collectionViewFlowLayout) {
        for (NSIndexPath * const indexPath in indexPaths) {
            [collectionViewFlowLayout collapseDetailSectionAtIndex:indexPath];
        }
    }
}

- (NSSize)collectionView:(NSCollectionView *)collectionView
                  layout:(NSCollectionViewLayout *)collectionViewLayout
  sizeForItemAtIndexPath:(NSIndexPath *)indexPath
{
    if (!_dynamicItemSizing) {
        return _staticItemSize;
    }
    
    VLCLibraryCollectionViewFlowLayout * const collectionViewFlowLayout = (VLCLibraryCollectionViewFlowLayout *)collectionViewLayout;
    if (collectionViewLayout) {
        VLCLibraryCollectionViewItemAspectRatio aspectRatio = _itemsAspectRatio;
        
        if ([collectionView.dataSource conformsToProtocol:@protocol(VLCLibraryCollectionViewDataSource)]) {
            id<VLCLibraryCollectionViewDataSource> libraryDataSource =
                (id<VLCLibraryCollectionViewDataSource>)collectionView.dataSource;

            if ([libraryDataSource respondsToSelector:@selector(collectionView:aspectRatioForSection:)]) {
                aspectRatio = [libraryDataSource collectionView:collectionView
                                          aspectRatioForSection:indexPath.section];
            }
        }
        
        return [VLCUIUnits adjustedCollectionViewItemSizeForCollectionView:collectionView
                                                                withLayout:collectionViewFlowLayout
                                                      withItemsAspectRatio:aspectRatio];
    }

    return NSZeroSize;
}

- (BOOL)collectionView:(NSCollectionView *)collectionView
canDragItemsAtIndexPaths:(NSSet<NSIndexPath *> *)indexPaths
             withEvent:(NSEvent *)event
{
    return YES;
}

/* One writer per item (the media-library archive plus the file), the way the
 * library grid writes them; the play queue reads every pasteboard item. */
- (nullable id<NSPasteboardWriting>)collectionView:(NSCollectionView *)collectionView
                pasteboardWriterForItemAtIndexPath:(NSIndexPath *)indexPath
{
    if (![collectionView.dataSource conformsToProtocol:@protocol(VLCLibraryCollectionViewDataSource)]) {
        return nil;
    }
    NSObject<VLCLibraryCollectionViewDataSource> * const vlcDataSource =
        (NSObject<VLCLibraryCollectionViewDataSource> *)collectionView.dataSource;
    const id<VLCMediaLibraryItemProtocol> libraryItem =
        [vlcDataSource libraryItemAtIndexPath:indexPath forCollectionView:collectionView];
    return libraryItem != nil ? [MacLCLibraryActions pasteboardWriterForItem:libraryItem] : nil;
}

@end
