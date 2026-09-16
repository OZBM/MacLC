/*****************************************************************************
 * MacLCHDRAdvisor.h: Pure logic HDR advisor and recommendation engine
 *****************************************************************************
 * Copyright (C) 2026 Hazen Studio
 *
 * Authors: MacLC Video Engineering Team
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

#import <Foundation/Foundation.h>

#import "MacLCHDRTypes.h"
#import "MacLCHDRStreamInfo.h"
#import "MacLCDisplayInfo.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * An HDR recommendation computed for a specific stream and display.
 */
@interface MacLCHDRRecommendation : NSObject

@property (nonatomic, readonly) MacLCHDRPresentation presentation;
@property (nonatomic, readonly) MacLCHDRPictureMode pictureMode;
@property (nonatomic, readonly, copy) NSString *headline;
@property (nonatomic, readonly, copy) NSString *reason;
@property (nonatomic, readonly, copy, nullable) NSString *brightnessAdvice;
/** YES when brightnessAdvice points at the Bright picture mode, so a surface
 *  showing Bright already can leave it out. */
@property (nonatomic, readonly) BOOL brightnessAdviceSuggestsBright;
@property (nonatomic, readonly, copy, nullable) NSString *warning;

- (BOOL)isPresentationSelectable:(MacLCHDRPresentation)p reason:(NSString * _Nullable * _Nullable)why;

- (instancetype)initWithPresentation:(MacLCHDRPresentation)presentation
                         pictureMode:(MacLCHDRPictureMode)pictureMode
                            headline:(NSString *)headline
                              reason:(NSString *)reason
                    brightnessAdvice:(nullable NSString *)brightnessAdvice
                             warning:(nullable NSString *)warning
               availablePresentations:(NSArray<NSNumber *> *)availablePresentations
             processablePresentations:(NSSet<NSNumber *> *)processablePresentations NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;

@end

/**
 * Recommendation advisor evaluating stream metadata, display headroom, and pipeline caps.
 */
@interface MacLCHDRAdvisor : NSObject

+ (MacLCHDRRecommendation *)recommendationForStream:(MacLCHDRStreamInfo *)stream
                                            display:(MacLCDisplayInfo *)display
                                        processable:(NSSet<NSNumber *> *)processablePresentations;

@end

NS_ASSUME_NONNULL_END
