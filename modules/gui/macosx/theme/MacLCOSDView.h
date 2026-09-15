/*****************************************************************************
 * MacLCOSDView.h: MacLC on-screen display capsule
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
 * The glass capsule that briefly confirms an action over the video: volume,
 * speed, subtitle track, seek, HDR format. One line: an SF Symbol, a short
 * message, and optionally a thin level bar.
 *
 * The view sizes itself (intrinsicContentSize); the host only positions it
 * (top centre of the video, overlay inset from the edge). It stays hidden
 * until the first message, appears with the emphasized entrance, lingers for
 * MacLCDesign.hudLinger after the last message and fades out.
 */
@interface MacLCOSDView : NSView

/**
 * Shows (or updates, if already visible) the capsule.
 * \param message short text, sentence case ("Speed 1.5×").
 * \param symbolName SF Symbol name, or nil for text only.
 * \param level 0...1 to show a level bar (volume), negative to hide it.
 */
- (void)showMessage:(NSString *)message
         symbolName:(nullable NSString *)symbolName
              level:(CGFloat)level;

/** Hides the capsule now (fade out). */
- (void)dismiss;

@end

NS_ASSUME_NONNULL_END
