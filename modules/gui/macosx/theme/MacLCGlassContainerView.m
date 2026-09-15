/*****************************************************************************
 * MacLCGlassContainerView.m: MacLC Liquid Glass container group view
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

#import "MacLCGlassContainerView.h"
#import "MacLCDesign.h"

@interface MacLCGlassContainerView ()
{
    NSView *_containerView;
}

@end

@implementation MacLCGlassContainerView

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
    _spacing = 0.0;

    _contentView = [[NSView alloc] initWithFrame:self.bounds];
    _contentView.translatesAutoresizingMaskIntoConstraints = NO;

    [self setupAccessibilityObserver];
    [self updateContainerView];
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
        [self updateContainerView];
    });
}

- (void)setSpacing:(CGFloat)spacing
{
    _spacing = spacing;
    if (@available(macOS 26.0, *)) {
        if (_containerView) {
            ((NSGlassEffectContainerView *)_containerView).spacing = spacing;
        }
    }
}

- (void)updateContainerView
{
    const BOOL reduceTransparency = MacLCDesign.reduceTransparency;
    BOOL canUseGlass = NO;
    if (@available(macOS 26.0, *)) {
        canUseGlass = !reduceTransparency;
    }

    if (canUseGlass) {
        if (_contentView.superview == self) {
            [_contentView removeFromSuperview];
        }

        if (!_containerView) {
            if (@available(macOS 26.0, *)) {
                NSGlassEffectContainerView *effectContainer = [[NSGlassEffectContainerView alloc] initWithFrame:self.bounds];
                effectContainer.translatesAutoresizingMaskIntoConstraints = NO;
                effectContainer.spacing = _spacing;
                _containerView = effectContainer;
            }
        }

        if (@available(macOS 26.0, *)) {
            NSGlassEffectContainerView *effectContainer = (NSGlassEffectContainerView *)_containerView;
            effectContainer.spacing = _spacing;

            if (effectContainer.superview != self) {
                [self addSubview:effectContainer];
                [NSLayoutConstraint activateConstraints:@[
                    [effectContainer.topAnchor constraintEqualToAnchor:self.topAnchor],
                    [effectContainer.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
                    [effectContainer.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
                    [effectContainer.bottomAnchor constraintEqualToAnchor:self.bottomAnchor]
                ]];
            }

            effectContainer.contentView = _contentView;
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
            if (_containerView) {
                ((NSGlassEffectContainerView *)_containerView).contentView = nil;
                [_containerView removeFromSuperview];
                _containerView = nil;
            }
        }

        if (_contentView.superview != self) {
            [_contentView removeFromSuperview];
            [self addSubview:_contentView];
            [NSLayoutConstraint activateConstraints:@[
                [_contentView.topAnchor constraintEqualToAnchor:self.topAnchor],
                [_contentView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
                [_contentView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
                [_contentView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor]
            ]];
        }
    }
}

@end
