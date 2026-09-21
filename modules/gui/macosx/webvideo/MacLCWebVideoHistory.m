/*****************************************************************************
 * MacLCWebVideoHistory.m: open web video history
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

#import "MacLCWebVideoHistory.h"

static NSString * const MacLCWebVideoRecentsKey = @"MacLCWebVideoRecents";

@implementation MacLCWebVideoHistory

+ (instancetype)sharedHistory {
    static MacLCWebVideoHistory *shared;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[self alloc] init];
    });
    return shared;
}

- (NSArray<NSDictionary *> *)entries {
    NSArray *array = [[NSUserDefaults standardUserDefaults] arrayForKey:MacLCWebVideoRecentsKey];
    if ([array isKindOfClass:[NSArray class]]) {
        return array;
    }
    return @[];
}

- (void)recordAddress:(NSString *)address title:(nullable NSString *)title site:(nullable NSString *)site {
    if (!address) return;
    
    NSMutableArray<NSDictionary *> *mutableEntries = [self.entries mutableCopy];
    // De-duplicate by address
    [mutableEntries filterUsingPredicate:[NSPredicate predicateWithFormat:@"address != %@", address]];
    
    NSMutableDictionary *entry = [NSMutableDictionary dictionary];
    entry[@"address"] = address;
    if (title) entry[@"title"] = title;
    if (site) entry[@"site"] = site;
    entry[@"date"] = [NSDate date];
    
    [mutableEntries insertObject:entry atIndex:0];
    
    if (mutableEntries.count > 10) {
        [mutableEntries removeObjectsInRange:NSMakeRange(10, mutableEntries.count - 10)];
    }
    
    [[NSUserDefaults standardUserDefaults] setObject:mutableEntries forKey:MacLCWebVideoRecentsKey];
}

- (void)clear {
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:MacLCWebVideoRecentsKey];
}

@end
