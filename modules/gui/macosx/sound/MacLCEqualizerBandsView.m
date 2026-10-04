/*****************************************************************************
 * MacLCEqualizerBandsView.m
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

#import "MacLCEqualizerBandsView.h"

#import "MacLCSoundMode.h"
#import "theme/MacLCDesign.h"

#import "extensions/NSString+Helpers.h"

@interface MacLCEqualizerSlider : NSSlider
@end

@implementation MacLCEqualizerSlider

- (void)mouseDown:(NSEvent *)event
{
    if (event.clickCount == 2) {
        self.floatValue = 0.0f;
        [self sendAction:self.action to:self.target];
        return;
    }
    [super mouseDown:event];
}

@end

@implementation MacLCEqualizerBandsView
{
    NSArray<MacLCEqualizerSlider *> *_sliders;
    NSArray<NSTextField *> *_valueLabels;
    NSArray<NSTextField *> *_freqLabels;
    NSButton *_resetButton;
    NSView *_referenceLine;
    NSArray<NSString *> *_freqStrings;
    NSArray<NSString *> *_accessibilityFreqStrings;
}

- (instancetype)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (self) {
        [self buildUI];
    }
    return self;
}

- (void)buildUI
{
    self.translatesAutoresizingMaskIntoConstraints = NO;

    _freqStrings = @[@"32", @"64", @"125", @"250", @"500", @"1K", @"2K", @"4K", @"8K", @"16K"];
    _accessibilityFreqStrings = @[
        _NS("32 hertz"),
        _NS("64 hertz"),
        _NS("125 hertz"),
        _NS("250 hertz"),
        _NS("500 hertz"),
        _NS("1 kilohertz"),
        _NS("2 kilohertz"),
        _NS("4 kilohertz"),
        _NS("8 kilohertz"),
        _NS("16 kilohertz"),
    ];

    // Reset button, trailing (the panel's disclosure row already says "Equalizer")

    _resetButton = [NSButton buttonWithTitle:_NS("Reset") target:self action:@selector(resetClicked:)];
    _resetButton.controlSize = NSControlSizeSmall;
    _resetButton.bezelStyle = NSBezelStyleRounded;
    _resetButton.font = [NSFont systemFontOfSize:11.0 weight:NSFontWeightRegular];
    _resetButton.accessibilityLabel = _NS("Reset Equalizer");
    _resetButton.toolTip = _NS("Reset all bands to 0 dB.");

    NSView *spacer = [[NSView alloc] initWithFrame:NSZeroRect];
    [spacer setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];

    NSStackView *headerRow = [NSStackView stackViewWithViews:@[spacer, _resetButton]];
    headerRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    headerRow.alignment = NSLayoutAttributeCenterY;
    headerRow.translatesAutoresizingMaskIntoConstraints = NO;

    // Sliders container
    NSView *slidersContainer = [[NSView alloc] initWithFrame:NSZeroRect];
    slidersContainer.translatesAutoresizingMaskIntoConstraints = NO;

    // 0 dB reference line behind sliders
    _referenceLine = [[NSView alloc] initWithFrame:NSZeroRect];
    _referenceLine.wantsLayer = YES;
    _referenceLine.layer.backgroundColor = MacLCDesign.separator.CGColor;
    _referenceLine.translatesAutoresizingMaskIntoConstraints = NO;
    [slidersContainer addSubview:_referenceLine positioned:NSWindowBelow relativeTo:nil];

    NSMutableArray<MacLCEqualizerSlider *> *sliders = [NSMutableArray arrayWithCapacity:10];
    NSMutableArray<NSTextField *> *valueLabels = [NSMutableArray arrayWithCapacity:10];
    NSMutableArray<NSTextField *> *freqLabels = [NSMutableArray arrayWithCapacity:10];
    NSMutableArray<NSStackView *> *columns = [NSMutableArray arrayWithCapacity:10];

    for (NSUInteger i = 0; i < 10; i++) {
        NSTextField *valLabel = [NSTextField labelWithString:@"0.0"];
        valLabel.alignment = NSTextAlignmentCenter;
        valLabel.font = [MacLCDesign monospacedDigitFontForTextStyle:NSFontTextStyleCaption2 weight:NSFontWeightRegular];
        valLabel.textColor = MacLCDesign.secondaryLabel;
        valLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [valueLabels addObject:valLabel];

        MacLCEqualizerSlider *slider = [[MacLCEqualizerSlider alloc] init];
        slider.vertical = YES;
        slider.minValue = -12.0;
        slider.maxValue = 12.0;
        slider.floatValue = 0.0f;
        slider.continuous = YES;
        if (@available(macOS 26.0, *))
            slider.neutralValue = 0.0; /* fill from 0 dB: a cut reads as a cut */
        slider.tag = (NSInteger)i;
        slider.target = self;
        slider.action = @selector(sliderMoved:);
        slider.accessibilityLabel = _accessibilityFreqStrings[i];
        slider.translatesAutoresizingMaskIntoConstraints = NO;
        [sliders addObject:slider];

        NSTextField *fLabel = [NSTextField labelWithString:_freqStrings[i]];
        fLabel.alignment = NSTextAlignmentCenter;
        fLabel.font = [NSFont systemFontOfSize:10.0 weight:NSFontWeightMedium];
        fLabel.textColor = MacLCDesign.secondaryLabel;
        fLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [freqLabels addObject:fLabel];

        NSStackView *col = [NSStackView stackViewWithViews:@[valLabel, slider, fLabel]];
        col.orientation = NSUserInterfaceLayoutOrientationVertical;
        col.alignment = NSLayoutAttributeCenterX;
        col.spacing = MacLCDesign.spacingXS;
        col.translatesAutoresizingMaskIntoConstraints = NO;
        [slidersContainer addSubview:col];
        [columns addObject:col];

        [NSLayoutConstraint activateConstraints:@[
            [slider.heightAnchor constraintEqualToConstant:100.0],
            [valLabel.widthAnchor constraintEqualToConstant:28.0],
            [fLabel.widthAnchor constraintEqualToConstant:28.0],
            [col.widthAnchor constraintEqualToConstant:28.0],
        ]];
    }

    _sliders = [sliders copy];
    _valueLabels = [valueLabels copy];
    _freqLabels = [freqLabels copy];

    // Reference line constraints
    MacLCEqualizerSlider *firstSlider = _sliders[0];
    [NSLayoutConstraint activateConstraints:@[
        [_referenceLine.leadingAnchor constraintEqualToAnchor:slidersContainer.leadingAnchor],
        [_referenceLine.trailingAnchor constraintEqualToAnchor:slidersContainer.trailingAnchor],
        [_referenceLine.centerYAnchor constraintEqualToAnchor:firstSlider.centerYAnchor],
        [_referenceLine.heightAnchor constraintEqualToConstant:1.0],
    ]];

    // Layout the 10 columns horizontally inside slidersContainer
    for (NSUInteger i = 0; i < columns.count; i++) {
        NSStackView *col = columns[i];
        [NSLayoutConstraint activateConstraints:@[
            [col.topAnchor constraintEqualToAnchor:slidersContainer.topAnchor],
            [col.bottomAnchor constraintEqualToAnchor:slidersContainer.bottomAnchor],
        ]];
        if (i == 0) {
            [col.leadingAnchor constraintEqualToAnchor:slidersContainer.leadingAnchor].active = YES;
        } else {
            NSStackView *prevCol = columns[i - 1];
            [col.leadingAnchor constraintEqualToAnchor:prevCol.trailingAnchor constant:2.0].active = YES;
        }
        if (i == columns.count - 1) {
            [col.trailingAnchor constraintEqualToAnchor:slidersContainer.trailingAnchor].active = YES;
        }
    }

    // Main vertical stack containing headerRow and slidersContainer
    NSStackView *mainStack = [NSStackView stackViewWithViews:@[headerRow, slidersContainer]];
    mainStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    mainStack.alignment = NSLayoutAttributeLeading;
    mainStack.spacing = MacLCDesign.spacingS;
    mainStack.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:mainStack];

    [NSLayoutConstraint activateConstraints:@[
        [mainStack.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [mainStack.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [mainStack.topAnchor constraintEqualToAnchor:self.topAnchor],
        [mainStack.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        [headerRow.widthAnchor constraintEqualToAnchor:mainStack.widthAnchor],
        [slidersContainer.widthAnchor constraintEqualToAnchor:mainStack.widthAnchor],
    ]];
}

- (void)updateBands:(NSArray<NSNumber *> *)effectiveBands
{
    for (NSUInteger i = 0; i < 10 && i < _sliders.count; i++) {
        float db = (i < effectiveBands.count) ? effectiveBands[i].floatValue : 0.0f;
        float clampedDisplay = fmaxf(-12.0f, fminf(12.0f, db));
        _sliders[i].floatValue = clampedDisplay;

        /* "+2.5", "-6", "0": whole values drop the decimal so "+12" fits the column. */
        const float rounded = roundf(db * 10.0f) / 10.0f;
        if (fabsf(rounded) < 0.05f) {
            _valueLabels[i].stringValue = @"0";
        } else if (fabsf(rounded - roundf(rounded)) < 0.05f) {
            _valueLabels[i].stringValue = [NSString stringWithFormat:@"%+.0f", rounded];
        } else {
            _valueLabels[i].stringValue = [NSString stringWithFormat:@"%+.1f", rounded];
        }

        _sliders[i].accessibilityValue = [NSString stringWithFormat:_NS("%.1f decibels"), db];
    }
}

- (void)sliderMoved:(MacLCEqualizerSlider *)slider
{
    NSInteger index = slider.tag;
    if (index < 0 || index >= 10) {
        return;
    }

    MacLCSoundMode *mode = MacLCSoundMode.sharedMode;
    NSMutableArray<NSNumber *> *bands = nil;

    if (![mode.presetIdentifier isEqualToString:@"custom"]) {
        // Moving a slider while non-custom is selected copies current effective bands
        bands = [mode.effectiveBands mutableCopy];
        if (bands.count < 10) {
            bands = [NSMutableArray arrayWithCapacity:10];
            for (NSUInteger i = 0; i < 10; i++) {
                [bands addObject:@0.0f];
            }
        }
        bands[index] = @(slider.floatValue);
        mode.customBands = bands;
        mode.presetIdentifier = @"custom";
    } else {
        bands = [mode.customBands mutableCopy];
        if (bands.count < 10) {
            bands = [NSMutableArray arrayWithCapacity:10];
            for (NSUInteger i = 0; i < 10; i++) {
                [bands addObject:@0.0f];
            }
        }
        bands[index] = @(slider.floatValue);
        mode.customBands = bands;
    }
    /* Editing the curve means wanting to hear it. */
    mode.enabled = YES;
}

- (void)resetClicked:(id)sender
{
    MacLCSoundMode *mode = MacLCSoundMode.sharedMode;
    mode.customBands = @[@0.0f, @0.0f, @0.0f, @0.0f, @0.0f, @0.0f, @0.0f, @0.0f, @0.0f, @0.0f];
    mode.presetIdentifier = @"custom";
    mode.enabled = YES;
}

@end
