/*****************************************************************************
 * MacLCSoundMode.h
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

#import "sound/MacLCSoundPresets.h"

NS_ASSUME_NONNULL_BEGIN

extern NSString * const MacLCSoundModeDidChangeNotification;

@interface MacLCSoundMode : NSObject

@property (class, readonly) MacLCSoundMode *sharedMode;
@property (nonatomic, getter=isEnabled) BOOL enabled;          // master switch
@property (nonatomic, copy) NSString *presetIdentifier;        // one of the ids
@property (nonatomic) float intensity;                          // of the current preset, 0…1
@property (nonatomic, copy) NSArray<NSNumber *> *customBands;   // 10 values, −20…20
@property (readonly) NSArray<MacLCSoundPreset *> *presets;      // ordered as the table
@property (readonly) NSArray<NSNumber *> *effectiveBands;       // what the EQ is set to now

- (void)applyToAudioOutput;   // idempotent; Claude calls it at start-up and on media change
- (void)populateMenu:(NSMenu *)menu; // "Off" + one radio item per preset (checkmark on the
                                     // active one; "Off" checked when disabled); the items
                                     // target the model; menu validation keeps them current

@end

NS_ASSUME_NONNULL_END
