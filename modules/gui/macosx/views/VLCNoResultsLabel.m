/*****************************************************************************
 * VLCNoResultsLabel.m: MacOS X interface module
 *****************************************************************************
 * Copyright (C) 2024 VLC authors and VideoLAN
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

#import "VLCNoResultsLabel.h"

#import "extensions/NSString+Helpers.h"
#import "extensions/NSView+VLCAdditions.h"
#import "theme/MacLCDesign.h"
#import "views/VLCUIUnits.h"

@interface VLCNoResultsLabel ()
{
    __weak id _actionTarget;
    SEL _actionSelector;
}

@property (nonatomic, strong) NSImageView *symbolImageView;
@property (nonatomic, strong) NSTextField *titleLabel;
@property (nonatomic, strong) NSTextField *messageLabel;
@property (nonatomic, strong) NSButton *actionButton;
@property (nonatomic, strong) NSStackView *stackView;

@end

@implementation VLCNoResultsLabel

- (instancetype)init
{
    self = [super initWithFrame:NSZeroRect];
    if (self) {
        [self setup];
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];
    if (self) {
        [self setup];
    }
    return self;
}

- (instancetype)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (self) {
        [self setup];
    }
    return self;
}

- (void)setup
{
    _symbolImageView = [[NSImageView alloc] init];
    _symbolImageView.translatesAutoresizingMaskIntoConstraints = NO;
    _symbolImageView.imageScaling = NSImageScaleProportionallyDown;
    _symbolImageView.contentTintColor = MacLCDesign.secondaryLabel;
    _symbolImageView.image = [MacLCDesign symbolNamed:@"magnifyingglass"
                                            pointSize:48.
                                               weight:NSFontWeightRegular
                                   accessibilityLabel:_NS("No Results")];

    [NSLayoutConstraint activateConstraints:@[
        [_symbolImageView.widthAnchor constraintEqualToConstant:48.],
        [_symbolImageView.heightAnchor constraintEqualToConstant:48.]
    ]];

    _titleLabel = [NSTextField labelWithString:_NS("No Results Found")];
    _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _titleLabel.editable = NO;
    _titleLabel.selectable = NO;
    _titleLabel.bezeled = NO;
    _titleLabel.drawsBackground = NO;
    _titleLabel.alignment = NSTextAlignmentCenter;
    _titleLabel.font = MacLCDesign.title2;
    _titleLabel.textColor = MacLCDesign.primaryLabel;

    _messageLabel = [NSTextField labelWithString:_NS("Check the spelling or try a different search.")];
    _messageLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _messageLabel.editable = NO;
    _messageLabel.selectable = NO;
    _messageLabel.bezeled = NO;
    _messageLabel.drawsBackground = NO;
    _messageLabel.alignment = NSTextAlignmentCenter;
    _messageLabel.font = MacLCDesign.subheadline;
    _messageLabel.textColor = MacLCDesign.secondaryLabel;

    _actionButton = [NSButton buttonWithTitle:_NS("Clear Search")
                                      target:self
                                      action:@selector(actionButtonTapped:)];
    _actionButton.translatesAutoresizingMaskIntoConstraints = NO;
    _actionButton.bezelStyle = NSBezelStyleRounded;
    _actionButton.font = MacLCDesign.body;
    _actionButton.toolTip = _NS("Clear Search");
    [_actionButton.cell setAccessibilityLabel:_NS("Clear Search")];

    _stackView = [NSStackView stackViewWithViews:@[_symbolImageView, _titleLabel, _messageLabel, _actionButton]];
    _stackView.translatesAutoresizingMaskIntoConstraints = NO;
    _stackView.orientation = NSUserInterfaceLayoutOrientationVertical;
    _stackView.alignment = NSLayoutAttributeCenterX;
    _stackView.spacing = MacLCDesign.spacingM;
    [_stackView setCustomSpacing:MacLCDesign.spacingS afterView:_titleLabel];
    [_stackView setCustomSpacing:MacLCDesign.spacingL afterView:_messageLabel];

    [self addSubview:_stackView];
    [_stackView applyConstraintsToFillSuperview];
}

- (void)actionButtonTapped:(id)sender
{
    if (self.actionBlock) {
        self.actionBlock();
    }
    if (_actionTarget && _actionSelector && [_actionTarget respondsToSelector:_actionSelector]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        [_actionTarget performSelector:_actionSelector withObject:sender];
#pragma clang diagnostic pop
    }
}

- (void)setActionTarget:(nullable id)target action:(nullable SEL)action
{
    _actionTarget = target;
    _actionSelector = action;
}

- (NSString *)stringValue
{
    return self.titleLabel.stringValue;
}

- (void)setStringValue:(NSString *)stringValue
{
    self.titleLabel.stringValue = stringValue;
}

- (NSString *)titleString
{
    return self.titleLabel.stringValue;
}

- (void)setTitleString:(NSString *)titleString
{
    self.titleLabel.stringValue = titleString;
}

- (NSString *)messageString
{
    return self.messageLabel.stringValue;
}

- (void)setMessageString:(NSString *)messageString
{
    self.messageLabel.stringValue = messageString;
}

- (NSString *)actionTitle
{
    return self.actionButton.title;
}

- (void)setActionTitle:(NSString *)actionTitle
{
    self.actionButton.title = actionTitle;
    self.actionButton.toolTip = actionTitle;
    [self.actionButton.cell setAccessibilityLabel:actionTitle];
}

@end
