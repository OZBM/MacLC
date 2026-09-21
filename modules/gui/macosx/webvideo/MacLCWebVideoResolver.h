/*****************************************************************************
 * MacLCWebVideoResolver.h: resolve a web page address into playable media
 *****************************************************************************
 * Copyright (C) 2026 Hazen Studio
 *
 * This program is free software; you can redistribute it and/or modify it
 * under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation; either version 2.1 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin Street, Fifth Floor, Boston MA 02110-1301, USA.
 *****************************************************************************/

#import <Cocoa/Cocoa.h>

@class VLCOpenInputMetadata;

NS_ASSUME_NONNULL_BEGIN

extern NSErrorDomain const MacLCWebVideoErrorDomain;

typedef NS_ENUM(NSInteger, MacLCWebVideoErrorCode) {
    MacLCWebVideoErrorInvalidAddress = 1,
    MacLCWebVideoErrorExtractorMissing,
    MacLCWebVideoErrorExtractorOutdated,
    MacLCWebVideoErrorExtractorFailed,
    MacLCWebVideoErrorNoNetwork,
    MacLCWebVideoErrorNotAVideo,
    MacLCWebVideoErrorUnavailable,
    MacLCWebVideoErrorCancelled,
};

/**
 * One resolved web video, or one playlist of them.
 *
 * Every property is filled from the extractor's answer; anything the site did
 * not provide stays nil or zero.
 */
@interface MacLCWebVideoItem : NSObject

@property (readonly, copy) NSString *pageAddress;
@property (readonly, copy, nullable) NSString *title;
@property (readonly, copy, nullable) NSString *author;
@property (readonly, copy, nullable) NSString *siteName;
@property (readonly) NSTimeInterval duration;
@property (readonly, copy, nullable) NSString *thumbnailAddress;
@property (readonly, copy, nullable) NSString *formatDescription;
@property (readonly, getter=isLive) BOOL live;

/** Playlist entries, empty for a single video. */
@property (readonly, copy) NSArray<MacLCWebVideoItem *> *children;

/**
 * The item to hand to the play queue: media address, a display name and the
 * playback options the streams need (user agent, referer, separate audio
 * track). Returns nil for a playlist node, whose children carry their own.
 */
@property (readonly, nullable) VLCOpenInputMetadata *playQueueItem;

@end

/**
 * Turns a page address into a MacLCWebVideoItem by running the external
 * extractor. Every resolution runs off the main thread; every completion
 * block runs on the main thread.
 */
@interface MacLCWebVideoResolver : NSObject

@property (class, readonly) MacLCWebVideoResolver *sharedResolver;

/** Cheap syntax test, no input/output, for live validation while typing. */
+ (BOOL)looksLikeWebVideoAddress:(NSString *)string;

/** Trims, adds a scheme when missing, returns nil when it is not an address. */
+ (nullable NSString *)normalisedAddressFromString:(NSString *)string;

/** Absolute path of the discovered extractor, nil when none is installed. */
@property (readonly, copy, nullable) NSString *extractorPath;

/** Looks for the extractor again, after the user installed it. */
- (void)refreshExtractorPath;

/**
 * Starts a resolution. Returns a token for -cancelResolution:, or nil when
 * the address is not usable (the completion block still runs, with an error).
 */
- (nullable NSUUID *)resolveAddress:(NSString *)address
                         completion:(void (^)(MacLCWebVideoItem *_Nullable item,
                                              NSError *_Nullable error))completion;

- (void)cancelResolution:(NSUUID *)token;

@end

NS_ASSUME_NONNULL_END
