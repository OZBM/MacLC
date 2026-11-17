/*****************************************************************************
 * VLCImageButton.m
 *****************************************************************************
 * Copyright (C) 2017 VLC authors and VideoLAN
 *
 * Authors: Cameron Mozie <camsw0rld14@gmail.com>
 *          Marvin Scholz <epirat07 at gmail dot com>
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

#import "VLCImageButton.h"
#import "theme/MacLCDesign.h"

@implementation VLCImageButton

@synthesize toggle = _toggle;

- (instancetype)initWithCoder:(NSCoder *)coder
{
    self =  [super initWithCoder:coder];
    if (self) {
        _toggle = NO;
    }
    return self;
}

- (void)awakeFromNib
{
    [(NSButtonCell*)[self cell] setHighlightsBy:NSPushInCellMask];
    [(NSButtonCell*)[self cell] setShowsStateBy:(_toggle) ? NSContentsCellMask : NSNoCellMask];
}

/* A press sinks the button a little and lets it spring back: every control on
 * the player bar answers the click, not only the action behind it. The
 * tracking loop runs inside super, so the sink lasts as long as the press. */
- (void)mouseDown:(NSEvent *)event
{
    [self animatePressed:YES];
    [super mouseDown:event];
    [self animatePressed:NO];
}

- (void)animatePressed:(BOOL)pressed
{
    if (MacLCDesign.reducedMotion || !self.enabled)
        return;
    self.wantsLayer = YES;
    CALayer * const layer = self.layer;
    const CATransform3D target = pressed ? [MacLCDesign centeredScale:0.88 forLayer:layer] : CATransform3DIdentity;
    CASpringAnimation * const spring = [CASpringAnimation animationWithKeyPath:@"transform"];
    spring.fromValue = [NSValue valueWithCATransform3D:((CALayer *)layer.presentationLayer ?: layer).transform];
    spring.toValue = [NSValue valueWithCATransform3D:target];
    spring.damping = pressed ? 30.0 : 11.0;
    spring.stiffness = 420.0;
    spring.duration = spring.settlingDuration;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    layer.transform = target;
    [CATransaction commit];
    [layer addAnimation:spring forKey:@"VLCImageButtonPress"];
}

- (void)setToggle:(BOOL)toggle
{
    _toggle = toggle;
    [(NSButtonCell*)[self cell] setShowsStateBy:(_toggle) ? NSContentsCellMask : NSNoCellMask];
}

@end
