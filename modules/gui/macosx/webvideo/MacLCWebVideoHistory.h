/*****************************************************************************
 * MacLCWebVideoHistory.h: open web video history
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

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface MacLCWebVideoHistory : NSObject

@property (class, readonly) MacLCWebVideoHistory *sharedHistory;
@property (readonly, copy) NSArray<NSDictionary *> *entries;

- (void)recordAddress:(NSString *)address title:(nullable NSString *)title site:(nullable NSString *)site;
- (void)clear;

@end

NS_ASSUME_NONNULL_END
