/*****************************************************************************
 * NSWindow+VLCAdditions.m: MacOS X interface module
 *****************************************************************************
 * Copyright (C) 2023 VLC authors and VideoLAN
 *
 * Authors: Claudio Cambra <developer@claudiocambra.com>
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

#import "NSWindow+VLCAdditions.h"

@implementation NSWindow (Helpers)

- (CGFloat)titlebarHeight
{
    const NSView * const titlebarView = [self standardWindowButton:NSWindowCloseButton].superview;
    return titlebarView.frame.size.height;
}

static NSString * const VLCTouchContextMenuGestureName = @"MacLCTouchContextMenu";

- (void)installTouchContextMenuGesture
{
    NSView * const contentView = self.contentView;
    for (NSGestureRecognizer * const recognizer in contentView.gestureRecognizers) {
        if ([recognizer.name isEqualToString:VLCTouchContextMenuGestureName]) {
            return;
        }
    }
    NSPressGestureRecognizer * const press =
        [[NSPressGestureRecognizer alloc] initWithTarget:self action:@selector(vlc_touchContextMenu:)];
    press.name = VLCTouchContextMenuGestureName;
    [contentView addGestureRecognizer:press];
}

- (void)vlc_touchContextMenu:(NSPressGestureRecognizer *)recognizer
{
    if (recognizer.state != NSGestureRecognizerStateBegan) {
        return;
    }
    // A synthesized right click reaches the view under the finger the normal
    // way, so each view keeps its own menuForEvent: or rightMouseDown: menu.
    NSEvent * const rightClick =
        [NSEvent mouseEventWithType:NSEventTypeRightMouseDown
                           location:[recognizer locationInView:nil]
                      modifierFlags:0
                          timestamp:NSProcessInfo.processInfo.systemUptime
                       windowNumber:self.windowNumber
                            context:nil
                        eventNumber:0
                         clickCount:1
                           pressure:1.0];
    [self sendEvent:rightClick];
}

@end
