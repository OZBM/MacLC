/*****************************************************************************
 * MacLCEmptyStateView.m: what a library screen shows when it has nothing
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

#import "medialib/components/MacLCEmptyStateView.h"

#import "theme/MacLCDesign.h"

static const CGFloat MacLCEmptyStateMaximumWidth = 420.0;

@interface MacLCEmptyStateView ()
{
    NSStackView *_stackView;
    NSStackView *_buttonRow;
    NSTextField *_titleField;
    NSTextField *_messageField;
    NSMutableArray<void (^)(void)> *_actions;
}
@end

@implementation MacLCEmptyStateView

+ (instancetype)emptyStateWithSymbolName:(NSString *)symbolName
                                   title:(NSString *)title
                                 message:(nullable NSString *)message
{
    MacLCEmptyStateView * const view = [[MacLCEmptyStateView alloc] initWithFrame:NSZeroRect];
    [view configureWithSymbolName:symbolName title:title message:message];
    return view;
}

- (void)configureWithSymbolName:(NSString *)symbolName title:(NSString *)title message:(nullable NSString *)message
{
    _actions = [NSMutableArray array];

    NSImageSymbolConfiguration * const symbolConfiguration =
        [[NSImageSymbolConfiguration configurationWithPointSize:48.0 weight:NSFontWeightLight]
            configurationByApplyingConfiguration:[NSImageSymbolConfiguration configurationPreferringHierarchical]];
    NSImage * const symbol = [[NSImage imageWithSystemSymbolName:symbolName accessibilityDescription:nil]
        imageWithSymbolConfiguration:symbolConfiguration];
    NSImageView * const imageView = [NSImageView imageViewWithImage:symbol ?: [[NSImage alloc] init]];
    imageView.contentTintColor = NSColor.tertiaryLabelColor;
    imageView.symbolConfiguration = symbolConfiguration;

    _titleField = [NSTextField wrappingLabelWithString:title];
    _titleField.font = [NSFont systemFontOfSize:MacLCDesign.title2.pointSize weight:NSFontWeightSemibold];
    _titleField.textColor = NSColor.labelColor;
    _titleField.alignment = NSTextAlignmentCenter;
    _titleField.selectable = NO;

    NSMutableArray<NSView *> * const views = [NSMutableArray arrayWithObjects:imageView, _titleField, nil];
    if (message.length > 0) {
        _messageField = [NSTextField wrappingLabelWithString:message];
        _messageField.font = MacLCDesign.body;
        _messageField.textColor = NSColor.secondaryLabelColor;
        _messageField.alignment = NSTextAlignmentCenter;
        _messageField.selectable = NO;
        [views addObject:_messageField];
    }

    _buttonRow = [NSStackView stackViewWithViews:@[]];
    _buttonRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    _buttonRow.spacing = 12.0;
    _buttonRow.hidden = YES;
    [views addObject:_buttonRow];

    _stackView = [NSStackView stackViewWithViews:views];
    _stackView.orientation = NSUserInterfaceLayoutOrientationVertical;
    _stackView.alignment = NSLayoutAttributeCenterX;
    _stackView.spacing = 6.0;
    [_stackView setCustomSpacing:16.0 afterView:imageView];
    [_stackView setCustomSpacing:20.0 afterView:_messageField ?: _titleField];
    _stackView.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:_stackView];

    [NSLayoutConstraint activateConstraints:@[
        [_stackView.topAnchor constraintEqualToAnchor:self.topAnchor],
        [_stackView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        [_stackView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [_stackView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [self.widthAnchor constraintLessThanOrEqualToConstant:MacLCEmptyStateMaximumWidth],
        [_titleField.widthAnchor constraintLessThanOrEqualToAnchor:_stackView.widthAnchor],
    ]];
    if (_messageField != nil) {
        [_messageField.widthAnchor constraintLessThanOrEqualToAnchor:_stackView.widthAnchor].active = YES;
    }
}

- (NSButton *)addButtonWithTitle:(NSString *)title prominent:(BOOL)prominent action:(void (^)(void))action
{
    NSButton * const button = [NSButton buttonWithTitle:title target:self action:@selector(buttonPressed:)];
    button.bezelStyle = NSBezelStyleGlass;
    button.controlSize = NSControlSizeLarge;
    if (prominent) {
        button.tintProminence = NSTintProminencePrimary;
        button.bezelColor = MacLCDesign.accent;
        button.keyEquivalent = @"\r";
    }
    button.tag = (NSInteger)_actions.count;
    [_actions addObject:[action copy]];
    [_buttonRow addArrangedSubview:button];
    _buttonRow.hidden = NO;
    return button;
}

- (void)buttonPressed:(NSButton *)sender
{
    if (sender.tag >= 0 && sender.tag < (NSInteger)_actions.count) {
        _actions[(NSUInteger)sender.tag]();
    }
}

// MARK: - Accessibility

- (BOOL)isAccessibilityElement
{
    return NO;
}

- (NSAccessibilityRole)accessibilityRole
{
    return NSAccessibilityGroupRole;
}

- (NSString *)accessibilityLabel
{
    NSString * const message = _messageField.stringValue;
    return message.length > 0
        ? [NSString stringWithFormat:@"%@. %@", _titleField.stringValue, message]
        : _titleField.stringValue;
}

@end
