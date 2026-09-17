/*****************************************************************************
 * MacLCBrowseEmptyView.m: Empty state view for Browse section
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

#import "MacLCBrowseEmptyView.h"

#import "extensions/NSString+Helpers.h"
#import "theme/MacLCDesign.h"

@interface MacLCBrowseEmptyView ()
{
    NSImageView *_iconImageView;
    NSTextField *_headlineLabel;
    NSTextField *_secondaryLabel;
}
@end

@implementation MacLCBrowseEmptyView

- (instancetype)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (self) {
        self.wantsLayer = YES;

        _iconImageView = [[NSImageView alloc] initWithFrame:NSZeroRect];
        _iconImageView.translatesAutoresizingMaskIntoConstraints = NO;
        _iconImageView.imageScaling = NSImageScaleProportionallyUpOrDown;
        _iconImageView.image = [MacLCDesign symbolNamed:@"folder"
                                              pointSize:40.0
                                                 weight:NSFontWeightRegular
                                     accessibilityLabel:_NS("Empty folder")];
        _iconImageView.contentTintColor = MacLCDesign.tertiaryLabel;
        [self addSubview:_iconImageView];

        _headlineLabel = [NSTextField labelWithString:_NS("This folder is empty")];
        _headlineLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _headlineLabel.font = MacLCDesign.headline;
        _headlineLabel.textColor = MacLCDesign.primaryLabel;
        _headlineLabel.alignment = NSTextAlignmentCenter;
        _headlineLabel.drawsBackground = NO;
        [self addSubview:_headlineLabel];

        _secondaryLabel = [NSTextField labelWithString:_NS("Drop videos or music here to play them.")];
        _secondaryLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _secondaryLabel.font = MacLCDesign.subheadline;
        _secondaryLabel.textColor = MacLCDesign.secondaryLabel;
        _secondaryLabel.alignment = NSTextAlignmentCenter;
        _secondaryLabel.drawsBackground = NO;
        [self addSubview:_secondaryLabel];

        [NSLayoutConstraint activateConstraints:@[
            [_iconImageView.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            [_iconImageView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor constant:-24.0],
            [_iconImageView.widthAnchor constraintEqualToConstant:48.0],
            [_iconImageView.heightAnchor constraintEqualToConstant:48.0],

            [_headlineLabel.topAnchor constraintEqualToAnchor:_iconImageView.bottomAnchor constant:16.0],
            [_headlineLabel.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            [_headlineLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.leadingAnchor constant:20.0],
            [_headlineLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.trailingAnchor constant:-20.0],

            [_secondaryLabel.topAnchor constraintEqualToAnchor:_headlineLabel.bottomAnchor constant:6.0],
            [_secondaryLabel.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            [_secondaryLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.leadingAnchor constant:20.0],
            [_secondaryLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.trailingAnchor constant:-20.0],
        ]];
    }
    return self;
}

- (NSSize)intrinsicContentSize
{
    return NSMakeSize(360.0, 160.0);
}

- (void)setHeadline:(NSString *)headline
{
    _headline = [headline copy];
    _headlineLabel.stringValue = headline ?: @"";
}

- (void)setSecondaryText:(NSString *)secondaryText
{
    _secondaryText = [secondaryText copy];
    _secondaryLabel.stringValue = secondaryText ?: @"";
}

@end
