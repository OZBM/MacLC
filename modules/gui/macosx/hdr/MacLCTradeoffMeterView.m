/*****************************************************************************
 * MacLCTradeoffMeterView.m: what an HDR picture mode gives and costs
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

#import "MacLCTradeoffMeterView.h"

#import "extensions/NSString+Helpers.h"
#import "theme/MacLCDesign.h"

#define kMeters 4
#define kDots 3
static const CGFloat kDotSize = 7.0;

@implementation MacLCTradeoffMeterView
{
    NSArray<NSTextField *> *_labels;
    NSArray<NSArray<NSView *> *> *_dots;
}

- (instancetype)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (self) {
        [self setUp];
    }
    return self;
}

- (void)setUp
{
    self.translatesAutoresizingMaskIntoConstraints = NO;

    NSArray<NSString *> *titles = @[
        _NS("Brightness"),
        _NS("Highlight detail"),
        _NS("Faithful to master"),
        _NS("Battery"),
    ];

    NSMutableArray<NSTextField *> *labels = [NSMutableArray array];
    NSMutableArray<NSArray<NSView *> *> *dots = [NSMutableArray array];
    NSMutableArray<NSView *> *columns = [NSMutableArray array];

    for (NSUInteger m = 0; m < kMeters; m++) {
        NSTextField *label = [NSTextField labelWithString:titles[m]];
        label.font = MacLCDesign.caption;
        label.textColor = MacLCDesign.secondaryLabel;
        label.alignment = NSTextAlignmentCenter;
        [labels addObject:label];

        NSMutableArray<NSView *> *row = [NSMutableArray array];
        for (NSUInteger d = 0; d < kDots; d++) {
            NSView *dot = [[NSView alloc] init];
            dot.wantsLayer = YES;
            dot.layer.cornerRadius = kDotSize / 2.0;
            dot.translatesAutoresizingMaskIntoConstraints = NO;
            [NSLayoutConstraint activateConstraints:@[
                [dot.widthAnchor constraintEqualToConstant:kDotSize],
                [dot.heightAnchor constraintEqualToConstant:kDotSize],
            ]];
            [row addObject:dot];
        }
        [dots addObject:row];

        NSStackView *dotRow = [NSStackView stackViewWithViews:row];
        dotRow.spacing = 4.0;
        NSStackView *column = [NSStackView stackViewWithViews:@[dotRow, label]];
        column.orientation = NSUserInterfaceLayoutOrientationVertical;
        column.alignment = NSLayoutAttributeCenterX;
        column.spacing = 4.0;
        [columns addObject:column];
    }
    _labels = labels;
    _dots = dots;

    NSStackView *stack = [NSStackView stackViewWithViews:columns];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.distribution = NSStackViewDistributionFillEqually;
    stack.spacing = MacLCDesign.spacingS;
    [self addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [stack.topAnchor constraintEqualToAnchor:self.topAnchor],
        [stack.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
    ]];

    [self showPictureMode:MacLCHDRPictureModeAccurate needsToneMapping:NO animated:NO];
}

- (void)showPictureMode:(MacLCHDRPictureMode)mode
       needsToneMapping:(BOOL)needsToneMapping
               animated:(BOOL)animated
{
    /* levels per meter: brightness, highlight detail, faithful, battery */
    NSUInteger levels[kMeters];
    switch (mode) {
        case MacLCHDRPictureModeBright:
            levels[0] = 3; levels[1] = needsToneMapping ? 1 : 2;
            levels[2] = 1; levels[3] = 1;
            break;
        case MacLCHDRPictureModeBalanced:
            levels[0] = 2; levels[1] = 3;
            levels[2] = needsToneMapping ? 2 : 3; levels[3] = 2;
            break;
        case MacLCHDRPictureModeAccurate:
        default:
            levels[0] = needsToneMapping ? 1 : 2; levels[1] = needsToneMapping ? 2 : 3;
            levels[2] = 3; levels[3] = 2;
            break;
    }

    NSMutableArray<NSString *> *spoken = [NSMutableArray array];
    for (NSUInteger m = 0; m < kMeters; m++) {
        for (NSUInteger d = 0; d < kDots; d++) {
            NSView *dot = _dots[m][d];
            const BOOL on = d < levels[m];
            [self.effectiveAppearance performAsCurrentDrawingAppearance:^{
                dot.layer.backgroundColor = (on ? MacLCDesign.primaryLabel
                                                : MacLCDesign.quaternaryLabel).CGColor;
            }];
            if (animated && !MacLCDesign.reducedMotion && on) {
                CABasicAnimation *pop = [CABasicAnimation animationWithKeyPath:@"opacity"];
                pop.fromValue = @(0.3);
                pop.toValue = @(1.0);
                pop.duration = MacLCDesign.motionStandardDuration;
                pop.beginTime = CACurrentMediaTime() + 0.03 * d;
                pop.fillMode = kCAFillModeBackwards;
                [dot.layer addAnimation:pop forKey:@"MacLCMeterPop"];
            }
        }
        [spoken addObject:[NSString stringWithFormat:@"%@ %lu/3",
                           _labels[m].stringValue, (unsigned long)levels[m]]];
    }
    self.accessibilityElement = YES;
    self.accessibilityRole = NSAccessibilityStaticTextRole;
    self.accessibilityLabel = [spoken componentsJoinedByString:@", "];
}

- (void)viewDidChangeEffectiveAppearance
{
    [super viewDidChangeEffectiveAppearance];
    /* Colours are resolved per appearance; redraw on the next update. */
    self.needsDisplay = YES;
}

@end
