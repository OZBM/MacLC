/*****************************************************************************
 * MacLCArtworkLoader.m: asynchronous, size-exact artwork for library screens
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

#import "medialib/data/MacLCArtworkLoader.h"

#import <ImageIO/ImageIO.h>

#import <vlc_common.h>
#import <vlc_media_library.h>
#import <vlc_url.h>

#import "extensions/NSString+Helpers.h"
#import "library/VLCLibraryController.h"
#import "library/VLCLibraryDataTypes.h"
#import "main/VLCMain.h"
#import "medialib/data/MacLCLibraryStore.h"

NSNotificationName const MacLCArtworkLoaderArtworkDidChangeNotification = @"MacLCArtworkLoaderArtworkDidChangeNotification";

/* What the media library's thumbnailer is asked for: small thumbnails match
 * the largest card (300 pt at 2×), banners the hero at its widest. */
static const uint32_t MacLCSmallThumbnailWidth = 640;
static const uint32_t MacLCSmallThumbnailHeight = 360;
static const uint32_t MacLCBannerThumbnailWidth = 2560;
static const uint32_t MacLCBannerThumbnailHeight = 1440;
static const double MacLCThumbnailPosition = 0.15;
static const NSInteger MacLCMaximumThumbnailsInFlight = 2;
static const NSUInteger MacLCArtworkCacheCostLimit = 192 * 1024 * 1024;

@interface MacLCArtworkRequest ()
@property (readwrite, getter=isCancelled) BOOL cancelled;
@end

@implementation MacLCArtworkRequest

- (void)cancel
{
    self.cancelled = YES;
}

@end

@interface MacLCArtworkLoader ()
{
    vlc_medialibrary_t *_mediaLibrary;
    vlc_ml_event_callback_t *_eventCallback;
    NSCache<NSString *, NSImage *> *_cache;
    NSOperationQueue *_decodeQueue;
    dispatch_source_t _memoryPressureSource;

    /* Main thread only. */
    NSMutableArray<NSNumber *> *_thumbnailQueue;      // media ids, newest last
    NSMutableSet<NSNumber *> *_thumbnailsInFlight;
    NSMutableSet<NSNumber *> *_thumbnailsAttempted;
    NSMutableDictionary<NSNumber *, NSMutableArray *> *_bannerWaiters;
}

- (void)thumbnailGeneratedForMediaID:(int64_t)mediaID size:(vlc_ml_thumbnail_size_t)size success:(BOOL)success;

@end

static void MacLCArtworkLoaderEventCallback(void *data, const vlc_ml_event_t *event)
{
    if (event->i_type != VLC_ML_EVENT_MEDIA_THUMBNAIL_GENERATED
        || event->media_thumbnail_generated.p_media == NULL) {
        return;
    }
    MacLCArtworkLoader * const loader = (__bridge MacLCArtworkLoader *)data;
    const int64_t mediaID = event->media_thumbnail_generated.p_media->i_id;
    const vlc_ml_thumbnail_size_t size = event->media_thumbnail_generated.i_size;
    const BOOL success = event->media_thumbnail_generated.b_success;
    dispatch_async(dispatch_get_main_queue(), ^{
        [loader thumbnailGeneratedForMediaID:mediaID size:size success:success];
    });
}

@implementation MacLCArtworkLoader

+ (MacLCArtworkLoader *)sharedLoader
{
    static MacLCArtworkLoader *sharedLoader = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedLoader = [[MacLCArtworkLoader alloc] init];
    });
    return sharedLoader;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        _cache = [[NSCache alloc] init];
        _cache.totalCostLimit = MacLCArtworkCacheCostLimit;
        _decodeQueue = [[NSOperationQueue alloc] init];
        _decodeQueue.name = @"org.maclc.artwork-decode";
        _decodeQueue.maxConcurrentOperationCount = 4;
        _decodeQueue.qualityOfService = NSQualityOfServiceUserInitiated;
        _thumbnailQueue = [NSMutableArray array];
        _thumbnailsInFlight = [NSMutableSet set];
        _thumbnailsAttempted = [NSMutableSet set];
        _bannerWaiters = [NSMutableDictionary dictionary];

        if (VLCMain.sharedInstance.libraryController.shouldUseMediaLibrary) {
            _mediaLibrary = vlc_ml_instance_get(getIntf());
        }
        if (_mediaLibrary != NULL) {
            _eventCallback = vlc_ml_event_register_callback(_mediaLibrary,
                                                            MacLCArtworkLoaderEventCallback,
                                                            (__bridge void *)self);
        }

        __weak typeof(self) weakSelf = self;
        _memoryPressureSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_MEMORYPRESSURE, 0,
                                                       DISPATCH_MEMORYPRESSURE_WARN | DISPATCH_MEMORYPRESSURE_CRITICAL,
                                                       dispatch_get_main_queue());
        dispatch_source_set_event_handler(_memoryPressureSource, ^{
            [weakSelf purgeCache];
        });
        dispatch_resume(_memoryPressureSource);
    }
    return self;
}

- (void)dealloc
{
    if (_eventCallback != NULL) {
        vlc_ml_event_unregister_callback(_mediaLibrary, _eventCallback);
    }
    if (_memoryPressureSource != NULL) {
        dispatch_source_cancel(_memoryPressureSource);
    }
}

- (void)purgeCache
{
    [_cache removeAllObjects];
}

// MARK: - Small artwork

+ (NSString *)cacheKeyForIdentifier:(NSString *)identifier pixelSize:(NSSize)pixelSize
{
    return [NSString stringWithFormat:@"%@|%.0fx%.0f", identifier, pixelSize.width, pixelSize.height];
}

- (nullable NSImage *)artworkForItem:(id<VLCMediaLibraryItemProtocol>)item
                           pointSize:(NSSize)pointSize
                               scale:(CGFloat)scale
                             request:(MacLCArtworkRequest * _Nullable * _Nullable)outRequest
                          completion:(void (^)(NSImage * _Nullable image))completion
{
    const CGFloat backingScale = scale > 0.0 ? scale : 2.0;
    /* Round up to a 32 px step: resizing a column by a few points must not
     * miss the cache for every card. */
    const NSSize pixelSize = NSMakeSize(ceil(pointSize.width * backingScale / 32.0) * 32.0,
                                        ceil(pointSize.height * backingScale / 32.0) * 32.0);
    NSString * const identifier = MacLCLibraryItemIdentifier(item);
    NSString * const key = [MacLCArtworkLoader cacheKeyForIdentifier:identifier pixelSize:pixelSize];

    NSImage * const cached = [_cache objectForKey:key];
    if (cached != nil) {
        if (outRequest != NULL) {
            *outRequest = nil;
        }
        return cached;
    }

    MacLCArtworkRequest * const request = [[MacLCArtworkRequest alloc] init];
    if (outRequest != NULL) {
        *outRequest = request;
    }

    /* Everything that may touch the database (containers look up their first
     * media) runs on the decode queue. */
    __weak typeof(self) weakSelf = self;
    [_decodeQueue addOperationWithBlock:^{
        if (request.cancelled) {
            return;
        }
        NSString *path = [MacLCArtworkLoader artworkPathForItem:item];
        VLCMediaLibraryMediaItem *mediaNeedingThumbnail = nil;
        if (path == nil) {
            mediaNeedingThumbnail = [MacLCArtworkLoader mediaNeedingThumbnailForItem:item];
        }
        NSImage * const image = path != nil
            ? [MacLCArtworkLoader imageAtPath:path pixelSize:pixelSize pointSize:pointSize fill:YES]
            : nil;
        if (image != nil) {
            [weakSelf cacheImage:image forKey:key pixelSize:pixelSize];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            if (mediaNeedingThumbnail != nil) {
                [weakSelf enqueueThumbnailForMediaID:mediaNeedingThumbnail.libraryID];
            }
            if (!request.cancelled) {
                completion(image);
            }
        });
    }];
    return nil;
}

- (void)cacheImage:(NSImage *)image forKey:(NSString *)key pixelSize:(NSSize)pixelSize
{
    [_cache setObject:image forKey:key cost:(NSUInteger)(pixelSize.width * pixelSize.height * 4.0)];
}

/* Called on the decode queue. The file path of the item's own artwork, or of
 * the first media that has one for containers without artwork. */
+ (nullable NSString *)artworkPathForItem:(id<VLCMediaLibraryItemProtocol>)item
{
    NSString * const own = [self pathForArtworkMRL:item.smallArtworkGenerated ? item.smallArtworkMRL : nil];
    if (own != nil) {
        return own;
    }
    if ([item isKindOfClass:VLCMediaLibraryMediaItem.class]) {
        return nil;
    }
    if ([item isKindOfClass:VLCMediaLibraryArtist.class]) {
        for (VLCMediaLibraryAlbum * const album in ((VLCMediaLibraryArtist *)item).albums) {
            NSString * const albumPath =
                [self pathForArtworkMRL:album.smallArtworkGenerated ? album.smallArtworkMRL : nil];
            if (albumPath != nil) {
                return albumPath;
            }
        }
    }
    if ([item isKindOfClass:VLCMediaLibraryGenre.class]) {
        for (VLCMediaLibraryAlbum * const album in ((VLCMediaLibraryGenre *)item).albums) {
            NSString * const albumPath =
                [self pathForArtworkMRL:album.smallArtworkGenerated ? album.smallArtworkMRL : nil];
            if (albumPath != nil) {
                return albumPath;
            }
        }
    }
    VLCMediaLibraryMediaItem * const first = item.firstMediaItem;
    if (first != nil) {
        return [self pathForArtworkMRL:first.smallArtworkGenerated ? first.smallArtworkMRL : nil];
    }
    return nil;
}

/* Called on the decode queue: the video whose thumbnail would give this
 * item artwork, if generating one is worth asking for. */
+ (nullable VLCMediaLibraryMediaItem *)mediaNeedingThumbnailForItem:(id<VLCMediaLibraryItemProtocol>)item
{
    VLCMediaLibraryMediaItem *media = nil;
    if ([item isKindOfClass:VLCMediaLibraryMediaItem.class]) {
        media = (VLCMediaLibraryMediaItem *)item;
    } else if ([item isKindOfClass:VLCMediaLibraryShow.class] || [item isKindOfClass:VLCMediaLibraryPlaylist.class]) {
        media = item.firstMediaItem;
    }
    if (media != nil && media.mediaType == VLC_ML_MEDIA_TYPE_VIDEO && !media.smallArtworkGenerated) {
        return media;
    }
    return nil;
}

+ (nullable NSString *)pathForArtworkMRL:(nullable NSString *)mrl
{
    if (mrl.length == 0) {
        return nil;
    }
    char * const path = vlc_uri2path(mrl.UTF8String);
    if (path == NULL) {
        return nil;
    }
    NSString * const result = toNSStr(path);
    free(path);
    return [NSFileManager.defaultManager fileExistsAtPath:result] ? result : nil;
}

/* Decodes straight to the drawn size. With `fill`, the smaller side matches
 * the target (the view crops, aspect fill); otherwise the larger one. */
+ (nullable NSImage *)imageAtPath:(NSString *)path
                        pixelSize:(NSSize)pixelSize
                        pointSize:(NSSize)pointSize
                             fill:(BOOL)fill
{
    NSURL * const url = [NSURL fileURLWithPath:path];
    CGImageSourceRef const source = CGImageSourceCreateWithURL((__bridge CFURLRef)url, NULL);
    if (source == NULL) {
        return nil;
    }
    CGFloat maxPixelSize = MAX(pixelSize.width, pixelSize.height);
    NSDictionary * const properties =
        (__bridge_transfer NSDictionary *)CGImageSourceCopyPropertiesAtIndex(source, 0, NULL);
    const CGFloat sourceWidth = [properties[(NSString *)kCGImagePropertyPixelWidth] doubleValue];
    const CGFloat sourceHeight = [properties[(NSString *)kCGImagePropertyPixelHeight] doubleValue];
    if (fill && sourceWidth > 0.0 && sourceHeight > 0.0 && pixelSize.width > 0.0 && pixelSize.height > 0.0) {
        const CGFloat scale = MAX(pixelSize.width / sourceWidth, pixelSize.height / sourceHeight);
        maxPixelSize = ceil(MAX(sourceWidth, sourceHeight) * scale);
    }
    NSDictionary * const options = @{
        (NSString *)kCGImageSourceCreateThumbnailFromImageAlways: @YES,
        (NSString *)kCGImageSourceCreateThumbnailWithTransform: @YES,
        (NSString *)kCGImageSourceShouldCacheImmediately: @YES,
        (NSString *)kCGImageSourceThumbnailMaxPixelSize: @(MAX(maxPixelSize, 1.0)),
    };
    CGImageRef const cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, (__bridge CFDictionaryRef)options);
    CFRelease(source);
    if (cgImage == NULL) {
        return nil;
    }
    /* Point size keeps the pixel density: a 2× image draws sharp. */
    const CGFloat density = pixelSize.width > 0.0 && pointSize.width > 0.0 ? pixelSize.width / pointSize.width : 2.0;
    NSImage * const image = [[NSImage alloc] initWithCGImage:cgImage
                                                        size:NSMakeSize(CGImageGetWidth(cgImage) / density,
                                                                        CGImageGetHeight(cgImage) / density)];
    CGImageRelease(cgImage);
    return image;
}

// MARK: - Thumbnail generation (main thread)

- (void)enqueueThumbnailForMediaID:(int64_t)mediaID
{
    NSNumber * const key = @(mediaID);
    if (_mediaLibrary == NULL || [_thumbnailsAttempted containsObject:key]) {
        return;
    }
    /* Newest request first: what scrolled into view last is what people look at. */
    [_thumbnailQueue removeObject:key];
    [_thumbnailQueue addObject:key];
    [self startNextThumbnails];
}

- (void)startNextThumbnails
{
    while ((NSInteger)_thumbnailsInFlight.count < MacLCMaximumThumbnailsInFlight && _thumbnailQueue.count > 0) {
        NSNumber * const key = _thumbnailQueue.lastObject;
        [_thumbnailQueue removeLastObject];
        [_thumbnailsAttempted addObject:key];
        [_thumbnailsInFlight addObject:key];
        vlc_medialibrary_t * const ml = _mediaLibrary;
        const int64_t mediaID = key.longLongValue;
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
            const int ret = vlc_ml_media_generate_thumbnail(ml, mediaID, VLC_ML_THUMBNAIL_SMALL,
                                                            MacLCSmallThumbnailWidth,
                                                            MacLCSmallThumbnailHeight,
                                                            MacLCThumbnailPosition);
            if (ret != VLC_SUCCESS) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self thumbnailGeneratedForMediaID:mediaID size:VLC_ML_THUMBNAIL_SMALL success:NO];
                });
            }
        });
    }
}

- (void)thumbnailGeneratedForMediaID:(int64_t)mediaID size:(vlc_ml_thumbnail_size_t)size success:(BOOL)success
{
    NSNumber * const key = @(mediaID);
    if (size == VLC_ML_THUMBNAIL_BANNER) {
        NSArray * const waiters = _bannerWaiters[key];
        [_bannerWaiters removeObjectForKey:key];
        for (void (^waiter)(BOOL) in waiters) {
            waiter(success);
        }
        return;
    }

    [_thumbnailsInFlight removeObject:key];
    if (success) {
        NSString * const identifier = [NSString stringWithFormat:@"media:%lld", mediaID];
        [NSNotificationCenter.defaultCenter postNotificationName:MacLCArtworkLoaderArtworkDidChangeNotification
                                                          object:identifier];
    }
    [self startNextThumbnails];
}

// MARK: - Hero

- (MacLCArtworkRequest *)heroArtworkForItem:(id<VLCMediaLibraryItemProtocol>)item
                                  pointSize:(NSSize)pointSize
                                      scale:(CGFloat)scale
                                 completion:(void (^)(NSImage * _Nullable image))completion
{
    MacLCArtworkRequest * const request = [[MacLCArtworkRequest alloc] init];
    const CGFloat backingScale = scale > 0.0 ? scale : 2.0;
    const NSSize pixelSize = NSMakeSize(ceil(pointSize.width * backingScale), ceil(pointSize.height * backingScale));
    NSString * const key = [MacLCArtworkLoader cacheKeyForIdentifier:
        [MacLCLibraryItemIdentifier(item) stringByAppendingString:@"/hero"] pixelSize:pixelSize];

    NSImage * const cached = [_cache objectForKey:key];
    if (cached != nil) {
        completion(cached);
        return request;
    }

    VLCMediaLibraryMediaItem * const media = [item isKindOfClass:VLCMediaLibraryMediaItem.class]
        ? (VLCMediaLibraryMediaItem *)item : nil;
    vlc_medialibrary_t * const ml = _mediaLibrary;
    __weak typeof(self) weakSelf = self;

    void (^deliver)(NSString *, BOOL) = ^(NSString * const path, BOOL isBanner) {
        [weakSelf.decodeQueue addOperationWithBlock:^{
            NSImage * const image = path != nil
                ? [MacLCArtworkLoader imageAtPath:path pixelSize:pixelSize pointSize:pointSize fill:YES]
                : nil;
            if (image != nil && isBanner) {
                [weakSelf cacheImage:image forKey:key pixelSize:pixelSize];
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                if (!request.cancelled && (image != nil || isBanner)) {
                    completion(image);
                }
            });
        }];
    };

    [_decodeQueue addOperationWithBlock:^{
        if (request.cancelled) {
            return;
        }
        NSString *bannerPath = nil;
        BOOL canGenerate = NO;
        if (media != nil && ml != NULL) {
            vlc_ml_media_t * const p_media = vlc_ml_get_media(ml, media.libraryID);
            if (p_media != NULL) {
                const vlc_ml_thumbnail_t banner = p_media->thumbnails[VLC_ML_THUMBNAIL_BANNER];
                if (banner.i_status == VLC_ML_THUMBNAIL_STATUS_AVAILABLE && banner.psz_mrl != NULL) {
                    bannerPath = [MacLCArtworkLoader pathForArtworkMRL:toNSStr(banner.psz_mrl)];
                }
                canGenerate = banner.i_status == VLC_ML_THUMBNAIL_STATUS_MISSING
                    || banner.i_status == VLC_ML_THUMBNAIL_STATUS_FAILURE;
                vlc_ml_media_release(p_media);
            }
        }
        if (bannerPath != nil) {
            deliver(bannerPath, YES);
            return;
        }
        /* Show the small artwork scaled up right away, then the banner when
         * the thumbnailer is done. */
        deliver([MacLCArtworkLoader artworkPathForItem:item], NO);
        if (!canGenerate) {
            return;
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            MacLCArtworkLoader * const strongSelf = weakSelf;
            if (strongSelf == nil || request.cancelled) {
                return;
            }
            NSNumber * const waiterKey = @(media.libraryID);
            NSMutableArray * const waiters = strongSelf->_bannerWaiters[waiterKey] ?: [NSMutableArray array];
            const BOOL alreadyRequested = waiters.count > 0;
            [waiters addObject:^(BOOL success) {
                if (!success || request.cancelled) {
                    return;
                }
                dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
                    NSString *path = nil;
                    vlc_ml_media_t * const p_media = vlc_ml_get_media(ml, media.libraryID);
                    if (p_media != NULL) {
                        const vlc_ml_thumbnail_t banner = p_media->thumbnails[VLC_ML_THUMBNAIL_BANNER];
                        if (banner.i_status == VLC_ML_THUMBNAIL_STATUS_AVAILABLE && banner.psz_mrl != NULL) {
                            path = [MacLCArtworkLoader pathForArtworkMRL:toNSStr(banner.psz_mrl)];
                        }
                        vlc_ml_media_release(p_media);
                    }
                    if (path != nil) {
                        deliver(path, YES);
                    }
                });
            }];
            strongSelf->_bannerWaiters[waiterKey] = waiters;
            if (!alreadyRequested) {
                dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
                    vlc_ml_media_generate_thumbnail(ml, media.libraryID, VLC_ML_THUMBNAIL_BANNER,
                                                    MacLCBannerThumbnailWidth,
                                                    MacLCBannerThumbnailHeight,
                                                    MacLCThumbnailPosition);
                });
            }
        });
    }];
    return request;
}

- (NSOperationQueue *)decodeQueue
{
    return _decodeQueue;
}

@end
