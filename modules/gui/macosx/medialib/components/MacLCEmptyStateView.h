/*****************************************************************************
 * MacLCEmptyStateView.h: what a library screen shows when it has nothing
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

/// Centred vertically and horizontally in its superview, max 420 pt wide:
/// SF Symbol (48 pt, light weight, tertiaryLabel, hierarchical), 16 pt,
/// title (MacLCDesign.title2, semibold, labelColor, centred, title case),
/// 6 pt, message (MacLCDesign.body, secondaryLabel, centred, wraps,
/// sentence case), 20 pt, up to two buttons side by side 12 pt apart.
/// A prominent button uses NSBezelStyleGlass with tintProminence Primary
/// (bezelColor = accent) on macOS 26; the other is a standard push button.
/// Accessibility: the whole view is a group labelled "title. message".
@interface MacLCEmptyStateView : NSView

+ (instancetype)emptyStateWithSymbolName:(NSString *)symbolName
                                   title:(NSString *)title
                                 message:(nullable NSString *)message;

/// At most two buttons; the first prominent one should be the recommended
/// choice. Returns the button for further tweaks (key equivalent...).
- (NSButton *)addButtonWithTitle:(NSString *)title
                       prominent:(BOOL)prominent
                          action:(void (^)(void))action;

@end

NS_ASSUME_NONNULL_END
