/*****************************************************************************
 * MacLCSymbolButton.h: icon button for MacLC's glass surfaces
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

/**
 * A borderless SF Symbol button for controls that sit on glass: hierarchical
 * rendering, a soft circular highlight under the pointer and while pressed,
 * and one `label` that drives both the tooltip and the accessibility label.
 */
@interface MacLCSymbolButton : NSButton

+ (instancetype)buttonWithSymbolName:(NSString *)symbolName
                               label:(NSString *)label
                           pointSize:(CGFloat)pointSize
                              target:(nullable id)target
                              action:(nullable SEL)action;

/** SF Symbol shown by the button. */
@property (nonatomic, copy) NSString *symbolName;

/** Symbol size in points (default 15). */
@property (nonatomic) CGFloat pointSize;

/** Symbol weight (default medium). */
@property (nonatomic) NSFontWeight weight;

/** Tooltip and accessibility label, in one place. */
@property (nonatomic, copy) NSString *label;

/** Changes the symbol, cross-fading unless Reduce Motion is on. */
- (void)setSymbolName:(NSString *)symbolName animated:(BOOL)animated;

@end

NS_ASSUME_NONNULL_END
