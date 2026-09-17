/*****************************************************************************
 * MacLCBrowseHeaderView.m: Floating Liquid Glass header & breadcrumb capsule
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

#import "MacLCBrowseHeaderView.h"

#import "extensions/NSString+Helpers.h"
#import "theme/MacLCDesign.h"
#import "theme/MacLCGlassView.h"

@interface MacLCBrowseHeaderView ()
{
    NSView *_homeTitleContainerView;
    NSTextField *_largeTitleLabel;
    NSTextField *_subtitleLabel;

    MacLCGlassView *_glassCapsuleView;
    NSButton *_homeButton;
    NSStackView *_breadcrumbStackView;
    NSScrollView *_breadcrumbScrollView;

    NSView *_loadingContainerView;
    NSProgressIndicator *_loadingSpinner;
    NSTextField *_loadingLabel;

    NSLayoutConstraint *_breadcrumbTrailingToLoadingConstraint;
    NSLayoutConstraint *_breadcrumbTrailingToCapsuleConstraint;

    NSArray<NSString *> *_currentSegments;
}
@end

@implementation MacLCBrowseHeaderView

- (instancetype)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (self) {
        self.wantsLayer = YES;
        _mode = MacLCBrowseHeaderModeHome;
        _currentSegments = @[];

        [self setupHomeTitleView];
        [self setupGlassCapsuleView];
        [self updateModeVisibilityAnimated:NO];
    }
    return self;
}

- (void)setupHomeTitleView
{
    _homeTitleContainerView = [[NSView alloc] initWithFrame:NSZeroRect];
    _homeTitleContainerView.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:_homeTitleContainerView];

    _largeTitleLabel = [NSTextField labelWithString:_NS("Browse")];
    _largeTitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _largeTitleLabel.font = [NSFont systemFontOfSize:MacLCDesign.title1.pointSize weight:NSFontWeightBold];
    _largeTitleLabel.textColor = MacLCDesign.primaryLabel;
    _largeTitleLabel.drawsBackground = NO;
    [_homeTitleContainerView addSubview:_largeTitleLabel];

    _subtitleLabel = [NSTextField labelWithString:_NS("Folders, drives and network shares")];
    _subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _subtitleLabel.font = MacLCDesign.subheadline;
    _subtitleLabel.textColor = MacLCDesign.secondaryLabel;
    _subtitleLabel.drawsBackground = NO;
    [_homeTitleContainerView addSubview:_subtitleLabel];

    [NSLayoutConstraint activateConstraints:@[
        [_homeTitleContainerView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [_homeTitleContainerView.trailingAnchor constraintLessThanOrEqualToAnchor:self.trailingAnchor],
        [_homeTitleContainerView.topAnchor constraintEqualToAnchor:self.topAnchor constant:4.0],
        [_homeTitleContainerView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],

        [_largeTitleLabel.topAnchor constraintEqualToAnchor:_homeTitleContainerView.topAnchor],
        [_largeTitleLabel.leadingAnchor constraintEqualToAnchor:_homeTitleContainerView.leadingAnchor],
        [_largeTitleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_homeTitleContainerView.trailingAnchor],

        [_subtitleLabel.topAnchor constraintEqualToAnchor:_largeTitleLabel.bottomAnchor constant:3.0],
        [_subtitleLabel.leadingAnchor constraintEqualToAnchor:_homeTitleContainerView.leadingAnchor],
        [_subtitleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_homeTitleContainerView.trailingAnchor],
        [_subtitleLabel.bottomAnchor constraintLessThanOrEqualToAnchor:_homeTitleContainerView.bottomAnchor],
    ]];
}

- (void)setupGlassCapsuleView
{
    _glassCapsuleView = [[MacLCGlassView alloc] initWithFrame:NSZeroRect];
    _glassCapsuleView.translatesAutoresizingMaskIntoConstraints = NO;
    _glassCapsuleView.cornerRadius = MacLCDesign.capsuleCornerRadius;
    [self addSubview:_glassCapsuleView];

    [NSLayoutConstraint activateConstraints:@[
        [_glassCapsuleView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [_glassCapsuleView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [_glassCapsuleView.topAnchor constraintEqualToAnchor:self.topAnchor],
        [_glassCapsuleView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
    ]];

    NSView * const capsuleContent = _glassCapsuleView.contentView;

    // Home button
    _homeButton = [[NSButton alloc] initWithFrame:NSMakeRect(0, 0, 28, 28)];
    _homeButton.translatesAutoresizingMaskIntoConstraints = NO;
    _homeButton.bordered = NO;
    _homeButton.image = [MacLCDesign symbolNamed:@"house"
                                       pointSize:14.0
                                          weight:NSFontWeightMedium
                              accessibilityLabel:_NS("Home")];
    _homeButton.imagePosition = NSImageOnly;
    _homeButton.toolTip = _NS("Home");
    _homeButton.target = self;
    _homeButton.action = @selector(homeButtonAction:);
    [capsuleContent addSubview:_homeButton];

    // Loading indicator on trailing side
    _loadingContainerView = [[NSView alloc] initWithFrame:NSZeroRect];
    _loadingContainerView.translatesAutoresizingMaskIntoConstraints = NO;
    _loadingContainerView.hidden = YES;
    [capsuleContent addSubview:_loadingContainerView];

    _loadingSpinner = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(0, 0, 16, 16)];
    _loadingSpinner.translatesAutoresizingMaskIntoConstraints = NO;
    _loadingSpinner.style = NSProgressIndicatorStyleSpinning;
    _loadingSpinner.controlSize = NSControlSizeSmall;
    [_loadingContainerView addSubview:_loadingSpinner];

    _loadingLabel = [NSTextField labelWithString:_NS("Loading…")];
    _loadingLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _loadingLabel.font = MacLCDesign.footnote;
    _loadingLabel.textColor = MacLCDesign.secondaryLabel;
    _loadingLabel.drawsBackground = NO;
    [_loadingContainerView addSubview:_loadingLabel];

    [NSLayoutConstraint activateConstraints:@[
        [_loadingContainerView.trailingAnchor constraintEqualToAnchor:capsuleContent.trailingAnchor constant:-14.0],
        [_loadingContainerView.centerYAnchor constraintEqualToAnchor:capsuleContent.centerYAnchor],

        [_loadingSpinner.leadingAnchor constraintEqualToAnchor:_loadingContainerView.leadingAnchor],
        [_loadingSpinner.centerYAnchor constraintEqualToAnchor:_loadingContainerView.centerYAnchor],
        [_loadingSpinner.widthAnchor constraintEqualToConstant:16.0],
        [_loadingSpinner.heightAnchor constraintEqualToConstant:16.0],

        [_loadingLabel.leadingAnchor constraintEqualToAnchor:_loadingSpinner.trailingAnchor constant:6.0],
        [_loadingLabel.trailingAnchor constraintEqualToAnchor:_loadingContainerView.trailingAnchor],
        [_loadingLabel.centerYAnchor constraintEqualToAnchor:_loadingContainerView.centerYAnchor],
    ]];

    // Breadcrumb scroll view and stack
    _breadcrumbScrollView = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    _breadcrumbScrollView.translatesAutoresizingMaskIntoConstraints = NO;
    _breadcrumbScrollView.drawsBackground = NO;
    _breadcrumbScrollView.hasHorizontalScroller = NO;
    _breadcrumbScrollView.hasVerticalScroller = NO;
    _breadcrumbScrollView.autohidesScrollers = YES;
    [capsuleContent addSubview:_breadcrumbScrollView];

    _breadcrumbStackView = [[NSStackView alloc] initWithFrame:NSZeroRect];
    _breadcrumbStackView.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    _breadcrumbStackView.alignment = NSLayoutAttributeCenterY;
    _breadcrumbStackView.spacing = 6.0;
    _breadcrumbStackView.translatesAutoresizingMaskIntoConstraints = NO;

    NSClipView * const clipView = [[NSClipView alloc] initWithFrame:NSZeroRect];
    clipView.drawsBackground = NO;
    clipView.documentView = _breadcrumbStackView;
    _breadcrumbScrollView.contentView = clipView;

    [NSLayoutConstraint activateConstraints:@[
        [_homeButton.leadingAnchor constraintEqualToAnchor:capsuleContent.leadingAnchor constant:12.0],
        [_homeButton.centerYAnchor constraintEqualToAnchor:capsuleContent.centerYAnchor],
        [_homeButton.widthAnchor constraintEqualToConstant:28.0],
        [_homeButton.heightAnchor constraintEqualToConstant:28.0],

        [_breadcrumbScrollView.leadingAnchor constraintEqualToAnchor:_homeButton.trailingAnchor constant:6.0],
        [_breadcrumbScrollView.topAnchor constraintEqualToAnchor:capsuleContent.topAnchor],
        [_breadcrumbScrollView.bottomAnchor constraintEqualToAnchor:capsuleContent.bottomAnchor],

        [_breadcrumbStackView.centerYAnchor constraintEqualToAnchor:clipView.centerYAnchor],
        [_breadcrumbStackView.heightAnchor constraintEqualToAnchor:clipView.heightAnchor],
    ]];

    _breadcrumbTrailingToLoadingConstraint =
        [_breadcrumbScrollView.trailingAnchor constraintEqualToAnchor:_loadingContainerView.leadingAnchor constant:-8.0];
    _breadcrumbTrailingToCapsuleConstraint =
        [_breadcrumbScrollView.trailingAnchor constraintEqualToAnchor:capsuleContent.trailingAnchor constant:-14.0];
    _breadcrumbTrailingToCapsuleConstraint.active = YES;
}

+ (CGFloat)preferredHeightForMode:(MacLCBrowseHeaderMode)mode
{
    return mode == MacLCBrowseHeaderModeHome ? 68.0 : 44.0;
}

- (void)setMode:(MacLCBrowseHeaderMode)mode
{
    if (_mode != mode) {
        _mode = mode;
        [self updateModeVisibilityAnimated:!MacLCDesign.reducedMotion];
        if ([self.delegate respondsToSelector:@selector(browseHeader:didChangeMode:)]) {
            [self.delegate browseHeader:self didChangeMode:mode];
        }
    }
}

- (void)updateModeVisibilityAnimated:(BOOL)animated
{
    const BOOL isHome = (_mode == MacLCBrowseHeaderModeHome);

    if (!animated) {
        _homeTitleContainerView.hidden = !isHome;
        _glassCapsuleView.hidden = isHome;
        _homeTitleContainerView.alphaValue = isHome ? 1.0 : 0.0;
        _glassCapsuleView.alphaValue = isHome ? 0.0 : 1.0;
        return;
    }

    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        context.duration = MacLCDesign.motionStandardDuration;
        if (isHome) {
            self->_homeTitleContainerView.hidden = NO;
            self->_homeTitleContainerView.animator.alphaValue = 1.0;
            self->_glassCapsuleView.animator.alphaValue = 0.0;
        } else {
            self->_glassCapsuleView.hidden = NO;
            self->_glassCapsuleView.animator.alphaValue = 1.0;
            self->_homeTitleContainerView.animator.alphaValue = 0.0;
        }
    } completionHandler:^{
        if (isHome) {
            self->_glassCapsuleView.hidden = YES;
        } else {
            self->_homeTitleContainerView.hidden = YES;
        }
    }];
}

- (void)setHomeTitle:(NSString *)title subtitle:(NSString *)subtitle
{
    _largeTitleLabel.stringValue = title ?: _NS("Browse");
    _subtitleLabel.stringValue = subtitle ?: _NS("Folders, drives and network shares");
}

- (void)setPathSegments:(NSArray<NSString *> *)segments
{
    _currentSegments = [segments copy];

    for (NSView * const subview in _breadcrumbStackView.arrangedSubviews.copy) {
        [_breadcrumbStackView removeArrangedSubview:subview];
        [subview removeFromSuperview];
    }

    const NSUInteger count = segments.count;
    for (NSUInteger i = 0; i < count; ++i) {
        if (i > 0) {
            NSImageView * const chevron = [[NSImageView alloc] initWithFrame:NSMakeRect(0, 0, 10, 10)];
            chevron.image = [MacLCDesign symbolNamed:@"chevron.right"
                                           pointSize:10.0
                                              weight:NSFontWeightMedium
                                  accessibilityLabel:nil];
            chevron.contentTintColor = MacLCDesign.tertiaryLabel;
            chevron.translatesAutoresizingMaskIntoConstraints = NO;
            [chevron.widthAnchor constraintEqualToConstant:10.0].active = YES;
            [chevron.heightAnchor constraintEqualToConstant:10.0].active = YES;
            [_breadcrumbStackView addArrangedSubview:chevron];
        }

        NSString * const segmentName = segments[i];
        const BOOL isLast = (i == count - 1);

        if (isLast) {
            NSTextField * const label = [NSTextField labelWithString:segmentName];
            label.font = [NSFont systemFontOfSize:13.0 weight:NSFontWeightSemibold];
            label.textColor = MacLCDesign.primaryLabel;
            label.drawsBackground = NO;
            label.lineBreakMode = NSLineBreakByTruncatingMiddle;
            [_breadcrumbStackView addArrangedSubview:label];
        } else {
            NSButton * const button = [[NSButton alloc] initWithFrame:NSZeroRect];
            button.title = segmentName;
            button.bordered = NO;
            button.font = [NSFont systemFontOfSize:13.0 weight:NSFontWeightRegular];
            button.contentTintColor = MacLCDesign.secondaryLabel;
            button.tag = (NSInteger)i;
            button.target = self;
            button.action = @selector(segmentButtonAction:);
            button.toolTip = segmentName;
            [button setButtonType:NSButtonTypeMomentaryChange];
            [_breadcrumbStackView addArrangedSubview:button];
        }
    }

    // Scroll to end of breadcrumb
    dispatch_async(dispatch_get_main_queue(), ^{
        NSPoint const endPoint = NSMakePoint(MAX(0.0, self->_breadcrumbStackView.frame.size.width - self->_breadcrumbScrollView.contentSize.width), 0.0);
        [self->_breadcrumbScrollView.contentView scrollToPoint:endPoint];
    });
}

- (void)startLoading
{
    _breadcrumbTrailingToCapsuleConstraint.active = NO;
    _breadcrumbTrailingToLoadingConstraint.active = YES;
    _loadingContainerView.hidden = NO;
    [_loadingSpinner startAnimation:self];
}

- (void)stopLoading
{
    [_loadingSpinner stopAnimation:self];
    _loadingContainerView.hidden = YES;
    _breadcrumbTrailingToLoadingConstraint.active = NO;
    _breadcrumbTrailingToCapsuleConstraint.active = YES;
}

- (void)homeButtonAction:(id)sender
{
    if ([self.delegate respondsToSelector:@selector(browseHeaderDidClickHome:)]) {
        [self.delegate browseHeaderDidClickHome:self];
    }
}

- (void)segmentButtonAction:(NSButton *)sender
{
    if ([self.delegate respondsToSelector:@selector(browseHeader:didClickSegmentAtIndex:)]) {
        [self.delegate browseHeader:self didClickSegmentAtIndex:sender.tag];
    }
}

@end
