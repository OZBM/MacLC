/*****************************************************************************
 * MacLCBrowseTableCellView.m: Folder contents table cell view
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

#import "MacLCBrowseTableCellView.h"

#import "theme/MacLCDesign.h"

NSString * const MacLCBrowseTableCellViewIdentifier = @"MacLCBrowseTableCellViewIdentifier";
NSString * const MacLCBrowseTableTextCellViewIdentifier = @"MacLCBrowseTableTextCellViewIdentifier";

@implementation MacLCBrowseTableCellView

- (instancetype)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (self) {
        self.identifier = MacLCBrowseTableCellViewIdentifier;

        _iconImageView = [[NSImageView alloc] initWithFrame:NSZeroRect];
        _iconImageView.translatesAutoresizingMaskIntoConstraints = NO;
        _iconImageView.imageScaling = NSImageScaleProportionallyUpOrDown;
        [self addSubview:_iconImageView];
        self.imageView = _iconImageView;

        _titleTextField = [NSTextField labelWithString:@""];
        _titleTextField.translatesAutoresizingMaskIntoConstraints = NO;
        _titleTextField.font = MacLCDesign.body;
        _titleTextField.textColor = MacLCDesign.primaryLabel;
        _titleTextField.lineBreakMode = NSLineBreakByTruncatingMiddle;
        _titleTextField.maximumNumberOfLines = 1;
        _titleTextField.drawsBackground = NO;
        [self addSubview:_titleTextField];
        self.textField = _titleTextField;

        [NSLayoutConstraint activateConstraints:@[
            [_iconImageView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:8.0],
            [_iconImageView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_iconImageView.widthAnchor constraintEqualToConstant:20.0],
            [_iconImageView.heightAnchor constraintEqualToConstant:20.0],

            [_titleTextField.leadingAnchor constraintEqualToAnchor:_iconImageView.trailingAnchor constant:8.0],
            [_titleTextField.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-8.0],
            [_titleTextField.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        ]];
    }
    return self;
}

- (void)setIconImage:(nullable NSImage *)image title:(NSString *)title
{
    _iconImageView.image = image;
    _titleTextField.stringValue = title ?: @"";
}

- (void)setBackgroundStyle:(NSBackgroundStyle)backgroundStyle
{
    [super setBackgroundStyle:backgroundStyle];
    if (backgroundStyle == NSBackgroundStyleEmphasized) {
        _titleTextField.textColor = MacLCDesign.selectionLabel;
    } else {
        _titleTextField.textColor = MacLCDesign.primaryLabel;
    }
}

- (NSMenu *)menuForEvent:(NSEvent *)event
{
    return [self.superview menuForEvent:event];
}

@end


@implementation MacLCBrowseTableTextCellView

- (instancetype)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (self) {
        self.identifier = MacLCBrowseTableTextCellViewIdentifier;

        _label = [NSTextField labelWithString:@""];
        _label.translatesAutoresizingMaskIntoConstraints = NO;
        _label.font = [MacLCDesign monospacedDigitFontForTextStyle:NSFontTextStyleFootnote];
        _label.textColor = MacLCDesign.secondaryLabel;
        _label.lineBreakMode = NSLineBreakByTruncatingTail;
        _label.maximumNumberOfLines = 1;
        _label.drawsBackground = NO;
        [self addSubview:_label];
        self.textField = _label;

        [NSLayoutConstraint activateConstraints:@[
            [_label.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:6.0],
            [_label.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-6.0],
            [_label.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        ]];
    }
    return self;
}

- (void)setStringValue:(NSString *)stringValue alignment:(NSTextAlignment)alignment
{
    _label.stringValue = stringValue ?: @"";
    _label.alignment = alignment;
}

- (void)setBackgroundStyle:(NSBackgroundStyle)backgroundStyle
{
    [super setBackgroundStyle:backgroundStyle];
    if (backgroundStyle == NSBackgroundStyleEmphasized) {
        _label.textColor = MacLCDesign.selectionLabel;
    } else {
        _label.textColor = MacLCDesign.secondaryLabel;
    }
}

- (NSMenu *)menuForEvent:(NSEvent *)event
{
    return [self.superview menuForEvent:event];
}

@end


@interface MacLCBrowseTableRowView ()
{
    NSTrackingArea *_trackingArea;
    BOOL _isHovered;
}
@end

@implementation MacLCBrowseTableRowView

- (instancetype)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (self) {
        self.wantsLayer = YES;
    }
    return self;
}

- (void)updateTrackingAreas
{
    [super updateTrackingAreas];
    if (_trackingArea != nil) {
        [self removeTrackingArea:_trackingArea];
    }
    _trackingArea = [[NSTrackingArea alloc] initWithRect:self.bounds
                                                 options:NSTrackingMouseEnteredAndExited |
                                                         NSTrackingActiveInActiveApp |
                                                         NSTrackingInVisibleRect
                                                   owner:self
                                                userInfo:nil];
    [self addTrackingArea:_trackingArea];
}

- (void)mouseEntered:(NSEvent *)event
{
    _isHovered = YES;
    [self setNeedsDisplay:YES];
}

- (void)mouseExited:(NSEvent *)event
{
    _isHovered = NO;
    [self setNeedsDisplay:YES];
}

- (void)drawBackgroundInRect:(NSRect)dirtyRect
{
    if (self.isSelected) {
        [super drawBackgroundInRect:dirtyRect];
        return;
    }

    if (_isHovered) {
        [[NSColor.quaternaryLabelColor colorWithAlphaComponent:0.06] setFill];
        NSRectFillUsingOperation(dirtyRect, NSCompositingOperationSourceOver);
    }
}

- (NSMenu *)menuForEvent:(NSEvent *)event
{
    return [self.superview menuForEvent:event];
}

@end
