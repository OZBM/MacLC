/*****************************************************************************
 * MacLCArtworkLoader.h: asynchronous, size-exact artwork for library screens
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

/// Posted on the main thread when artwork that did not exist was generated
/// (a video thumbnail finished, for example). The object is the
/// MacLCLibraryItemID whose artwork changed; views showing it reload.
extern NSNotificationName const MacLCArtworkLoaderArtworkDidChangeNotification;

/// A pending request. Cancel it when the view that asked for it is reused.
@interface MacLCArtworkRequest : NSObject
- (void)cancel;
@property (readonly, getter=isCancelled) BOOL cancelled;
@end

/// Loads artwork decoded and downsampled off the main thread to the exact
/// pixel size it is drawn at, with an in-memory cache keyed by item and size.
/// Missing video thumbnails are generated through the media library (at most
/// two at a time, visible items first) and announced with
/// MacLCArtworkLoaderArtworkDidChangeNotification.
@interface MacLCArtworkLoader : NSObject

@property (class, readonly) MacLCArtworkLoader *sharedLoader;

/// Returns the cached image right away when there is one (and does not call
/// the completion), otherwise returns nil and calls the completion later on
/// the main thread, unless the request was cancelled. The completion gets nil
/// when the item has no artwork yet (the view keeps its placeholder).
/// `pointSize` is the drawn size in points; `scale` the backing scale factor.
- (nullable NSImage *)artworkForItem:(id<VLCMediaLibraryItemProtocol>)item
                           pointSize:(NSSize)pointSize
                               scale:(CGFloat)scale
                             request:(MacLCArtworkRequest * _Nullable * _Nullable)outRequest
                          completion:(void (^)(NSImage * _Nullable image))completion;

/// A wide, high-resolution frame of a video for the Home hero (generated on
/// demand, cached on disk by the media library).
- (MacLCArtworkRequest *)heroArtworkForItem:(id<VLCMediaLibraryItemProtocol>)item
                                  pointSize:(NSSize)pointSize
                                      scale:(CGFloat)scale
                                 completion:(void (^)(NSImage * _Nullable image))completion;

/// Drops every cached image (memory pressure, library reset).
- (void)purgeCache;

@end

NS_ASSUME_NONNULL_END
