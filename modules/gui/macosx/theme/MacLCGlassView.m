/*****************************************************************************
 * MacLCGlassView.m: MacLC Liquid Glass container view
 *****************************************************************************
 * Copyright (C) 2026 Hazen Studio
 *
 * Authors: MacLC Design System Team
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

#import "MacLCGlassView.h"
#import "MacLCDesign.h"

@interface MacLCGlassView ()
{
    NSView *_glassEffectView;
    NSVisualEffectView *_fallbackVisualEffectView;
}

@end

@implementation MacLCGlassView

- (instancetype)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (self) {
        [self commonInit];
    }
    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];
    if (self) {
        [self commonInit];
    }
    return self;
}

- (void)dealloc
{
    [[NSWorkspace.sharedWorkspace notificationCenter] removeObserver:self];
}

- (void)commonInit
{
    self.wantsLayer = YES;
    _cornerRadius = 0.0;
    _forcesDarkAppearance = NO;

    _contentView = [[NSView alloc] initWithFrame:self.bounds];
    _contentView.translatesAutoresizingMaskIntoConstraints = NO;

    [self setupAccessibilityObserver];
    [self updateEffectView];
}

- (void)setupAccessibilityObserver
{
    [[NSWorkspace.sharedWorkspace notificationCenter] addObserver:self
                                                         selector:@selector(accessibilityOptionsDidChange:)
                                                             name:NSWorkspaceAccessibilityDisplayOptionsDidChangeNotification
                                                           object:nil];
}

- (void)accessibilityOptionsDidChange:(NSNotification *)notification
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self updateEffectView];
    });
}

- (void)viewDidChangeEffectiveAppearance
{
    [super viewDidChangeEffectiveAppearance];
    if (_fallbackVisualEffectView) {
        _fallbackVisualEffectView.layer.borderColor = MacLCDesign.separator.CGColor;
    }
}

/* A radius larger than half the smaller side means "capsule": clamp it so the
 * shape stays a capsule at any size. */
- (CGFloat)effectiveCornerRadius
{
    const CGFloat half = MIN(NSWidth(self.bounds), NSHeight(self.bounds)) / 2.0;
    return (half > 0.0) ? MIN(_cornerRadius, half) : _cornerRadius;
}

- (void)layout
{
    [super layout];
    const CGFloat radius = [self effectiveCornerRadius];
    if (fabs(self.layer.cornerRadius - radius) > 0.01)
        [self applyCornerRadius:radius];
}

- (void)setCornerRadius:(CGFloat)cornerRadius
{
    _cornerRadius = cornerRadius;
    [self applyCornerRadius:[self effectiveCornerRadius]];
}

- (void)applyCornerRadius:(CGFloat)cornerRadius
{
    self.layer.cornerRadius = cornerRadius;

    if (@available(macOS 26.0, *)) {
        if (_glassEffectView) {
            ((NSGlassEffectView *)_glassEffectView).cornerRadius = cornerRadius;
        }
    }

    if (_fallbackVisualEffectView) {
        _fallbackVisualEffectView.layer.cornerRadius = cornerRadius;
        _fallbackVisualEffectView.layer.masksToBounds = (cornerRadius > 0.0);
    }
}

- (void)setTintColor:(nullable NSColor *)tintColor
{
    _tintColor = [tintColor copy];

    if (@available(macOS 26.0, *)) {
        if (_glassEffectView) {
            ((NSGlassEffectView *)_glassEffectView).tintColor = _tintColor;
        }
    }
}

- (void)setForcesDarkAppearance:(BOOL)forcesDarkAppearance
{
    if (_forcesDarkAppearance != forcesDarkAppearance) {
        _forcesDarkAppearance = forcesDarkAppearance;
        self.appearance = _forcesDarkAppearance ? [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua] : nil;
    }
}

- (void)updateEffectView
{
    const BOOL reduceTransparency = MacLCDesign.reduceTransparency;
    BOOL canUseGlass = NO;
    if (@available(macOS 26.0, *)) {
        canUseGlass = !reduceTransparency;
    }

    if (canUseGlass) {
        if (_fallbackVisualEffectView) {
            [_contentView removeFromSuperview];
            [_fallbackVisualEffectView removeFromSuperview];
            _fallbackVisualEffectView = nil;
        }

        if (!_glassEffectView) {
            if (@available(macOS 26.0, *)) {
                NSGlassEffectView *glass = [[NSGlassEffectView alloc] initWithFrame:self.bounds];
                glass.translatesAutoresizingMaskIntoConstraints = NO;
                glass.style = NSGlassEffectViewStyleRegular;
                glass.cornerRadius = [self effectiveCornerRadius];
                glass.tintColor = _tintColor;
                _glassEffectView = glass;
            }
        }

        if (@available(macOS 26.0, *)) {
            NSGlassEffectView *glass = (NSGlassEffectView *)_glassEffectView;
            glass.cornerRadius = [self effectiveCornerRadius];
            glass.tintColor = _tintColor;

            if (glass.superview != self) {
                [self addSubview:glass positioned:NSWindowBelow relativeTo:nil];
                [NSLayoutConstraint activateConstraints:@[
                    [glass.topAnchor constraintEqualToAnchor:self.topAnchor],
                    [glass.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
                    [glass.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
                    [glass.bottomAnchor constraintEqualToAnchor:self.bottomAnchor]
                ]];
            }

            glass.contentView = _contentView;
            if (_contentView.superview) {
                [NSLayoutConstraint activateConstraints:@[
                    [_contentView.topAnchor constraintEqualToAnchor:_contentView.superview.topAnchor],
                    [_contentView.leadingAnchor constraintEqualToAnchor:_contentView.superview.leadingAnchor],
                    [_contentView.trailingAnchor constraintEqualToAnchor:_contentView.superview.trailingAnchor],
                    [_contentView.bottomAnchor constraintEqualToAnchor:_contentView.superview.bottomAnchor]
                ]];
            }
        }
    } else {
        if (@available(macOS 26.0, *)) {
            if (_glassEffectView) {
                ((NSGlassEffectView *)_glassEffectView).contentView = nil;
                [_glassEffectView removeFromSuperview];
                _glassEffectView = nil;
            }
        }

        if (!_fallbackVisualEffectView) {
            _fallbackVisualEffectView = [[NSVisualEffectView alloc] initWithFrame:self.bounds];
            _fallbackVisualEffectView.translatesAutoresizingMaskIntoConstraints = NO;
            _fallbackVisualEffectView.material = NSVisualEffectMaterialHUDWindow;
            _fallbackVisualEffectView.blendingMode = NSVisualEffectBlendingModeWithinWindow;
            _fallbackVisualEffectView.state = NSVisualEffectStateActive;
            _fallbackVisualEffectView.wantsLayer = YES;
        }

        _fallbackVisualEffectView.layer.cornerRadius = [self effectiveCornerRadius];
        _fallbackVisualEffectView.layer.masksToBounds = (_cornerRadius > 0.0);
        _fallbackVisualEffectView.layer.borderWidth = 0.5;
        _fallbackVisualEffectView.layer.borderColor = MacLCDesign.separator.CGColor;

        if (_fallbackVisualEffectView.superview != self) {
            [self addSubview:_fallbackVisualEffectView positioned:NSWindowBelow relativeTo:nil];
            [NSLayoutConstraint activateConstraints:@[
                [_fallbackVisualEffectView.topAnchor constraintEqualToAnchor:self.topAnchor],
                [_fallbackVisualEffectView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
                [_fallbackVisualEffectView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
                [_fallbackVisualEffectView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor]
            ]];
        }

        if (_contentView.superview != _fallbackVisualEffectView) {
            [_contentView removeFromSuperview];
            [_fallbackVisualEffectView addSubview:_contentView];
            [NSLayoutConstraint activateConstraints:@[
                [_contentView.topAnchor constraintEqualToAnchor:_fallbackVisualEffectView.topAnchor],
                [_contentView.leadingAnchor constraintEqualToAnchor:_fallbackVisualEffectView.leadingAnchor],
                [_contentView.trailingAnchor constraintEqualToAnchor:_fallbackVisualEffectView.trailingAnchor],
                [_contentView.bottomAnchor constraintEqualToAnchor:_fallbackVisualEffectView.bottomAnchor]
            ]];
        }
    }
}

@end
