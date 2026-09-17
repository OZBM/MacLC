/*****************************************************************************
 * MacLCBrowseSectionHeaderView.m: Section header for Browse home
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

#import "MacLCBrowseSectionHeaderView.h"

#import "theme/MacLCDesign.h"

NSString * const MacLCBrowseSectionHeaderViewIdentifier = @"MacLCBrowseSectionHeaderViewIdentifier";

@interface MacLCBrowseSectionHeaderView ()
{
    NSTextField *_titleLabel;
}
@end

@implementation MacLCBrowseSectionHeaderView

- (instancetype)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (self) {
        self.wantsLayer = YES;

        _titleLabel = [NSTextField labelWithString:@""];
        _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _titleLabel.font = [NSFont systemFontOfSize:MacLCDesign.title3.pointSize weight:NSFontWeightSemibold];
        _titleLabel.textColor = MacLCDesign.secondaryLabel;
        _titleLabel.drawsBackground = NO;
        _titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        _titleLabel.maximumNumberOfLines = 1;

        [self addSubview:_titleLabel];

        [NSLayoutConstraint activateConstraints:@[
            [_titleLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:20.0],
            [_titleLabel.topAnchor constraintEqualToAnchor:self.topAnchor constant:24.0],
            [_titleLabel.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-8.0],
            [_titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.trailingAnchor constant:-20.0]
        ]];
    }
    return self;
}

- (void)setTitle:(NSString *)title
{
    _title = [title copy];
    _titleLabel.stringValue = title ?: @"";
}

- (void)prepareForReuse
{
    [super prepareForReuse];
    self.title = @"";
}

@end
