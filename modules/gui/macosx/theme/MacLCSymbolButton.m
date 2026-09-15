/*****************************************************************************
 * MacLCSymbolButton.m: icon button for MacLC's glass surfaces
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

#import "MacLCSymbolButton.h"

#import "MacLCDesign.h"

@implementation MacLCSymbolButton
{
    NSTrackingArea *_trackingArea;
    CALayer *_highlightLayer;
    BOOL _hovered;
}

+ (instancetype)buttonWithSymbolName:(NSString *)symbolName
                               label:(NSString *)label
                           pointSize:(CGFloat)pointSize
                              target:(nullable id)target
                              action:(nullable SEL)action
{
    MacLCSymbolButton *button = [[self alloc] initWithFrame:NSZeroRect];
    button.pointSize = pointSize;
    button.symbolName = symbolName;
    button.label = label;
    button.target = target;
    button.action = action;
    return button;
}

- (instancetype)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (self) {
        [self setUp];
    }
    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];
    if (self) {
        [self setUp];
    }
    return self;
}

- (void)setUp
{
    _pointSize = 15.0;
    _weight = NSFontWeightMedium;
    _symbolName = @"";
    _label = @"";

    self.bordered = NO;
    self.buttonType = NSButtonTypeMomentaryChange;
    self.imagePosition = NSImageOnly;
    self.imageScaling = NSImageScaleNone;
    self.focusRingType = NSFocusRingTypeDefault;
    self.contentTintColor = MacLCDesign.primaryLabel;
    self.translatesAutoresizingMaskIntoConstraints = NO;
    self.wantsLayer = YES;

    _highlightLayer = [CALayer layer];
    _highlightLayer.opacity = 0.0;
    [self.layer insertSublayer:_highlightLayer atIndex:0];

    [NSLayoutConstraint activateConstraints:@[
        [self.widthAnchor constraintGreaterThanOrEqualToConstant:MacLCDesign.minimumHitTarget],
        [self.heightAnchor constraintGreaterThanOrEqualToConstant:MacLCDesign.minimumHitTarget],
    ]];
}

- (NSSize)intrinsicContentSize
{
    const CGFloat side = MAX(MacLCDesign.minimumHitTarget, ceil(_pointSize * 1.9));
    return NSMakeSize(side, side);
}

- (void)layout
{
    [super layout];
    const CGFloat side = MIN(NSWidth(self.bounds), NSHeight(self.bounds));
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _highlightLayer.frame = NSMakeRect((NSWidth(self.bounds) - side) / 2.0,
                                       (NSHeight(self.bounds) - side) / 2.0,
                                       side, side);
    _highlightLayer.cornerRadius = side / 2.0;
    [CATransaction commit];
}

- (void)updateImage
{
    if (_symbolName.length == 0)
        return;
    NSImage *image = [NSImage imageWithSystemSymbolName:_symbolName
                               accessibilityDescription:_label];
    NSImageSymbolConfiguration *configuration =
        [NSImageSymbolConfiguration configurationWithPointSize:_pointSize weight:_weight];
    configuration = [configuration configurationByApplyingConfiguration:
        [NSImageSymbolConfiguration configurationPreferringHierarchical]];
    self.image = [image imageWithSymbolConfiguration:configuration];
    [self invalidateIntrinsicContentSize];
}

- (void)setSymbolName:(NSString *)symbolName
{
    _symbolName = [symbolName copy];
    [self updateImage];
}

- (void)setSymbolName:(NSString *)symbolName animated:(BOOL)animated
{
    if ([symbolName isEqualToString:_symbolName])
        return;
    if (animated && !MacLCDesign.reducedMotion && self.layer != nil) {
        CATransition *transition = [CATransition animation];
        transition.type = kCATransitionFade;
        transition.duration = MacLCDesign.motionQuickDuration;
        [self.layer addAnimation:transition forKey:@"MacLCSymbolSwap"];
    }
    self.symbolName = symbolName;
}

- (void)setPointSize:(CGFloat)pointSize
{
    _pointSize = pointSize;
    [self updateImage];
}

- (void)setWeight:(NSFontWeight)weight
{
    _weight = weight;
    [self updateImage];
}

- (void)setLabel:(NSString *)label
{
    _label = [label copy];
    self.toolTip = _label;
    self.accessibilityLabel = _label;
    [self updateImage];
}

#pragma mark - Hover and press feedback

- (void)updateTrackingAreas
{
    [super updateTrackingAreas];
    if (_trackingArea != nil)
        [self removeTrackingArea:_trackingArea];
    _trackingArea = [[NSTrackingArea alloc] initWithRect:self.bounds
                                                 options:NSTrackingMouseEnteredAndExited
                                                       | NSTrackingActiveInKeyWindow
                                                       | NSTrackingInVisibleRect
                                                   owner:self
                                                userInfo:nil];
    [self addTrackingArea:_trackingArea];
}

- (void)mouseEntered:(NSEvent *)event
{
    [super mouseEntered:event];
    _hovered = YES;
    [self updateHighlightAnimated:YES];
}

- (void)mouseExited:(NSEvent *)event
{
    [super mouseExited:event];
    _hovered = NO;
    [self updateHighlightAnimated:YES];
}

- (void)setHighlighted:(BOOL)highlighted
{
    [super setHighlighted:highlighted];
    [self updateHighlightAnimated:NO];
}

- (void)viewDidChangeEffectiveAppearance
{
    [super viewDidChangeEffectiveAppearance];
    [self updateHighlightAnimated:NO];
}

- (void)updateHighlightAnimated:(BOOL)animated
{
    const float opacity = !self.enabled ? 0.0f
                        : (self.highlighted ? 0.20f : (_hovered ? 0.10f : 0.0f));
    [CATransaction begin];
    [CATransaction setAnimationDuration:(animated && !MacLCDesign.reducedMotion)
                                            ? MacLCDesign.motionQuickDuration : 0.0];
    [self.effectiveAppearance performAsCurrentDrawingAppearance:^{
        /* The layer retains the colour it is given. */
        self->_highlightLayer.backgroundColor = MacLCDesign.primaryLabel.CGColor;
    }];
    _highlightLayer.opacity = opacity;
    [CATransaction commit];
}

@end
