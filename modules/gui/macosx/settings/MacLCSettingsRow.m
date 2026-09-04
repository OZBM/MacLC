/*****************************************************************************
 * MacLCSettingsRow.m: MacLC reusable settings row builder
 *****************************************************************************
 * Copyright (C) 2026 VLC authors and VideoLAN
 *
 * Authors: MacLC Settings Team
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

#import "settings/MacLCSettingsRow.h"
#import "theme/MacLCDesign.h"
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wnullability-completeness"
#import "extensions/NSString+Helpers.h"
#pragma clang diagnostic pop

@interface MacLCSettingsRow () <NSTextFieldDelegate>

@property (nonatomic, strong) NSTextField *titleLabel;
@property (nonatomic, strong) NSTextField *explanationLabel;
@property (nonatomic, strong) NSView *controlView;
@property (nonatomic, strong) NSTextField *defaultHintLabel;
@property (nonatomic, strong) NSImageView *warningImageView;

@property (nonatomic, strong, nullable) NSButton *checkboxButton;
@property (nonatomic, strong, nullable) NSPopUpButton *popUpButton;
@property (nonatomic, strong, nullable) NSSlider *slider;
@property (nonatomic, strong, nullable) NSTextField *sliderReadoutLabel;
@property (nonatomic, copy, nullable) NSString *sliderFormat;
@property (nonatomic, strong, nullable) NSTextField *textField;
@property (nonatomic, strong, nullable) NSStepper *stepper;
@property (nonatomic, copy, nullable) NSString *stepperFormat;
@property (nonatomic, strong, nullable) NSArray<NSButton *> *radioButtons;

@property (nonatomic, strong) NSStackView *mainStackView;
@property (nonatomic, strong) NSStackView *headerStackView;

@end

@implementation MacLCSettingsRow

- (instancetype)initWithTitle:(NSString *)title
                  explanation:(NSString *)explanation
                      control:(NSView *)control
{
    self = [super initWithFrame:NSZeroRect];
    if (self) {
        _controlView = control;
        _enabled = YES;

        self.translatesAutoresizingMaskIntoConstraints = NO;

        // Warning glyph
        _warningImageView = [[NSImageView alloc] initWithFrame:NSZeroRect];
        _warningImageView.translatesAutoresizingMaskIntoConstraints = NO;
        NSImage *warnImg = [MacLCDesign symbolNamed:@"exclamationmark.triangle.fill"
                                 accessibilityLabel:_NS("Warning")];
        if (warnImg) {
            warnImg = [warnImg copy];
            [warnImg setTemplate:NO];
        }
        _warningImageView.image = warnImg;
        _warningImageView.contentTintColor = [MacLCDesign warning];
        _warningImageView.imageScaling = NSImageScaleProportionallyDown;
        _warningImageView.hidden = YES;
        [_warningImageView.widthAnchor constraintEqualToConstant:16].active = YES;
        [_warningImageView.heightAnchor constraintEqualToConstant:16].active = YES;

        // Title Label
        _titleLabel = [NSTextField labelWithString:title];
        _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _titleLabel.font = [MacLCDesign bodyEmphasized];
        _titleLabel.textColor = [MacLCDesign primaryLabel];
        _titleLabel.lineBreakMode = NSLineBreakByWordWrapping;
        [_titleLabel setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
        [_titleLabel setContentCompressionResistancePriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
        [_titleLabel setContentCompressionResistancePriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationVertical];

        // Flexible spacer between title and control
        NSView *spacer = [[NSView alloc] initWithFrame:NSZeroRect];
        spacer.translatesAutoresizingMaskIntoConstraints = NO;
        [spacer setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];

        // Ensure trailing control doesn't shrink
        [_controlView setContentHuggingPriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
        [_controlView setContentCompressionResistancePriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];

        // Header stack view (warning + title + spacer + control)
        _headerStackView = [[NSStackView alloc] init];
        _headerStackView.translatesAutoresizingMaskIntoConstraints = NO;
        _headerStackView.orientation = NSUserInterfaceLayoutOrientationHorizontal;
        _headerStackView.alignment = NSLayoutAttributeCenterY;
        _headerStackView.spacing = [MacLCDesign spacingS];
        [_headerStackView addArrangedSubview:_warningImageView];
        [_headerStackView addArrangedSubview:_titleLabel];
        [_headerStackView addArrangedSubview:spacer];
        [_headerStackView addArrangedSubview:_controlView];

        // Explanation Label
        _explanationLabel = [NSTextField wrappingLabelWithString:explanation];
        _explanationLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _explanationLabel.font = [MacLCDesign caption];
        _explanationLabel.textColor = [MacLCDesign secondaryLabel];
        _explanationLabel.maximumNumberOfLines = 0;
        [_explanationLabel setContentCompressionResistancePriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationVertical];
        [_explanationLabel setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];

        // Default Hint Label
        _defaultHintLabel = [NSTextField labelWithString:@""];
        _defaultHintLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _defaultHintLabel.font = [MacLCDesign footnote];
        _defaultHintLabel.textColor = [MacLCDesign tertiaryLabel];
        _defaultHintLabel.hidden = YES;

        // Main vertical stack view
        _mainStackView = [[NSStackView alloc] init];
        _mainStackView.translatesAutoresizingMaskIntoConstraints = NO;
        _mainStackView.orientation = NSUserInterfaceLayoutOrientationVertical;
        _mainStackView.alignment = NSLayoutAttributeLeading;
        _mainStackView.spacing = [MacLCDesign spacingXS];

        [_mainStackView addArrangedSubview:_headerStackView];
        [_mainStackView addArrangedSubview:_explanationLabel];
        [_mainStackView addArrangedSubview:_defaultHintLabel];

        [self addSubview:_mainStackView];

        [NSLayoutConstraint activateConstraints:@[
            [_mainStackView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [_mainStackView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [_mainStackView.topAnchor constraintEqualToAnchor:self.topAnchor],
            [_mainStackView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
            [_headerStackView.leadingAnchor constraintEqualToAnchor:_mainStackView.leadingAnchor],
            [_headerStackView.trailingAnchor constraintEqualToAnchor:_mainStackView.trailingAnchor],
            [_explanationLabel.leadingAnchor constraintEqualToAnchor:_mainStackView.leadingAnchor],
            [_explanationLabel.trailingAnchor constraintEqualToAnchor:_mainStackView.trailingAnchor],
        ]];

        // Minimum height from design system
        [self.heightAnchor constraintGreaterThanOrEqualToConstant:[MacLCDesign rowMinimumHeight]].active = YES;

        // Accessibility
        [self configureAccessibility];
    }
    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];
    return self;
}

- (void)configureAccessibility
{
    NSString *title = _titleLabel.stringValue;
    NSString *explanation = _explanationLabel.stringValue;

    _titleLabel.accessibilityLabel = title;
    _explanationLabel.accessibilityLabel = explanation;
    _explanationLabel.accessibilityRole = NSAccessibilityStaticTextRole;

    _controlView.accessibilityLabel = title;
    _controlView.accessibilityHelp = explanation;
}

#pragma mark - Setters

- (void)setWarning:(BOOL)warning
{
    _warning = warning;
    _warningImageView.hidden = !warning;
}

- (void)setDefaultHint:(NSString *)defaultHint
{
    _defaultHint = [defaultHint copy];
    if (_defaultHint.length > 0) {
        _defaultHintLabel.stringValue = _defaultHint;
        _defaultHintLabel.hidden = NO;
    } else {
        _defaultHintLabel.stringValue = @"";
        _defaultHintLabel.hidden = YES;
    }
}

- (void)setEnabled:(BOOL)enabled
{
    _enabled = enabled;
    _titleLabel.textColor = enabled ? [MacLCDesign primaryLabel] : [MacLCDesign tertiaryLabel];
    _explanationLabel.textColor = enabled ? [MacLCDesign secondaryLabel] : [MacLCDesign tertiaryLabel];
    if ([_controlView isKindOfClass:[NSControl class]]) {
        ((NSControl *)_controlView).enabled = enabled;
    }
    if (_checkboxButton) _checkboxButton.enabled = enabled;
    if (_popUpButton) _popUpButton.enabled = enabled;
    if (_slider) _slider.enabled = enabled;
    if (_textField) _textField.enabled = enabled;
    if (_stepper) _stepper.enabled = enabled;
    for (NSButton *btn in _radioButtons) {
        btn.enabled = enabled;
    }
}

#pragma mark - Factory Methods

+ (instancetype)rowWithTitle:(NSString *)title
                 explanation:(NSString *)explanation
                     control:(NSView *)control
{
    return [[self alloc] initWithTitle:title explanation:explanation control:control];
}

+ (instancetype)checkboxRowWithTitle:(NSString *)title
                         explanation:(NSString *)explanation
                               state:(BOOL)state
                              action:(nullable void (^)(BOOL checked))action
{
    NSButton *button = [[NSButton alloc] initWithFrame:NSZeroRect];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    [button setButtonType:NSButtonTypeSwitch];
    button.title = @"";
    button.state = state ? NSControlStateValueOn : NSControlStateValueOff;

    MacLCSettingsRow *row = [[self alloc] initWithTitle:title explanation:explanation control:button];
    row.checkboxButton = button;
    row.checkboxChangedHandler = action;

    button.target = row;
    button.action = @selector(checkboxFired:);

    return row;
}

- (void)checkboxFired:(id)sender
{
    BOOL checked = (self.checkboxButton.state == NSControlStateValueOn);
    if (self.checkboxChangedHandler) {
        self.checkboxChangedHandler(checked);
    }
}

+ (instancetype)popUpRowWithTitle:(NSString *)title
                      explanation:(NSString *)explanation
                            items:(NSArray<NSString *> *)items
                             tags:(nullable NSArray<NSNumber *> *)tags
                    selectedIndex:(NSInteger)selectedIndex
                           action:(nullable void (^)(NSInteger selectedIndex, NSInteger tag))action
{
    NSPopUpButton *popUp = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    popUp.translatesAutoresizingMaskIntoConstraints = NO;
    [popUp removeAllItems];
    for (NSUInteger i = 0; i < items.count; i++) {
        [popUp addItemWithTitle:items[i]];
        if (tags && i < tags.count) {
            popUp.lastItem.tag = tags[i].integerValue;
        } else {
            popUp.lastItem.tag = (NSInteger)i;
        }
    }
    if (selectedIndex >= 0 && selectedIndex < (NSInteger)popUp.numberOfItems) {
        [popUp selectItemAtIndex:selectedIndex];
    }

    MacLCSettingsRow *row = [[self alloc] initWithTitle:title explanation:explanation control:popUp];
    row.popUpButton = popUp;
    row.popUpChangedHandler = action;

    popUp.target = row;
    popUp.action = @selector(popUpFired:);

    return row;
}

- (void)popUpFired:(id)sender
{
    NSInteger index = self.popUpButton.indexOfSelectedItem;
    NSInteger tag = self.popUpButton.selectedTag;
    if (self.popUpChangedHandler) {
        self.popUpChangedHandler(index, tag);
    }
}

+ (instancetype)sliderRowWithTitle:(NSString *)title
                       explanation:(NSString *)explanation
                          minValue:(double)minValue
                          maxValue:(double)maxValue
                      initialValue:(double)initialValue
                       valueFormat:(NSString *)valueFormat
                            action:(nullable void (^)(double value))action
{
    NSSlider *slider = [[NSSlider alloc] initWithFrame:NSZeroRect];
    slider.translatesAutoresizingMaskIntoConstraints = NO;
    slider.minValue = minValue;
    slider.maxValue = maxValue;
    slider.doubleValue = initialValue;
    [slider.widthAnchor constraintEqualToConstant:140].active = YES;

    NSTextField *readout = [NSTextField labelWithString:@""];
    readout.translatesAutoresizingMaskIntoConstraints = NO;
    readout.font = [MacLCDesign monospacedDigitFontForTextStyle:NSFontTextStyleCaption1];
    readout.textColor = [MacLCDesign secondaryLabel];
    readout.alignment = NSTextAlignmentRight;
    [readout.widthAnchor constraintGreaterThanOrEqualToConstant:50].active = YES;

    NSString *fmt = valueFormat.length > 0 ? valueFormat : @"%.0f";
    readout.stringValue = [NSString stringWithFormat:fmt, initialValue];

    NSStackView *sliderStack = [[NSStackView alloc] init];
    sliderStack.translatesAutoresizingMaskIntoConstraints = NO;
    sliderStack.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    sliderStack.alignment = NSLayoutAttributeCenterY;
    sliderStack.spacing = [MacLCDesign spacingS];
    [sliderStack addArrangedSubview:slider];
    [sliderStack addArrangedSubview:readout];

    MacLCSettingsRow *row = [[self alloc] initWithTitle:title explanation:explanation control:sliderStack];
    row.slider = slider;
    row.sliderReadoutLabel = readout;
    row.sliderFormat = fmt;
    row.sliderChangedHandler = action;

    slider.target = row;
    slider.action = @selector(sliderFired:);

    return row;
}

- (void)sliderFired:(id)sender
{
    double val = self.slider.doubleValue;
    self.sliderReadoutLabel.stringValue = [NSString stringWithFormat:self.sliderFormat, val];
    if (self.sliderChangedHandler) {
        self.sliderChangedHandler(val);
    }
}

+ (instancetype)textFieldRowWithTitle:(NSString *)title
                          explanation:(NSString *)explanation
                                 text:(nullable NSString *)text
                          placeholder:(nullable NSString *)placeholder
                             isSecure:(BOOL)isSecure
                               action:(nullable void (^)(NSString *text))action
{
    NSTextField *field = isSecure ? [[NSSecureTextField alloc] initWithFrame:NSZeroRect]
                                  : [[NSTextField alloc] initWithFrame:NSZeroRect];
    field.translatesAutoresizingMaskIntoConstraints = NO;
    field.stringValue = text ?: @"";
    field.placeholderString = placeholder ?: @"";
    field.font = [MacLCDesign body];
    field.textColor = [MacLCDesign primaryLabel];
    [field.widthAnchor constraintEqualToConstant:180].active = YES;

    MacLCSettingsRow *row = [[self alloc] initWithTitle:title explanation:explanation control:field];
    row.textField = field;
    row.textChangedHandler = action;

    field.delegate = row;
    field.target = row;
    field.action = @selector(textFieldFired:);

    return row;
}

- (void)textFieldFired:(id)sender
{
    if (self.textChangedHandler) {
        self.textChangedHandler(self.textField.stringValue);
    }
}

- (void)controlTextDidChange:(NSNotification *)obj
{
    if (obj.object == self.textField && self.textChangedHandler) {
        self.textChangedHandler(self.textField.stringValue);
    }
}

+ (instancetype)pathPickerRowWithTitle:(NSString *)title
                           explanation:(NSString *)explanation
                                  path:(nullable NSString *)path
                           chooseTitle:(nullable NSString *)chooseTitle
                          chooseAction:(nullable void (^)(MacLCSettingsRow *row))chooseAction
{
    NSTextField *field = [[NSTextField alloc] initWithFrame:NSZeroRect];
    field.translatesAutoresizingMaskIntoConstraints = NO;
    field.stringValue = path ?: @"";
    field.font = [MacLCDesign body];
    field.textColor = [MacLCDesign primaryLabel];
    [field.widthAnchor constraintEqualToConstant:200].active = YES;

    NSButton *chooseBtn = [NSButton buttonWithTitle:chooseTitle ?: _NS("Choose…")
                                             target:nil
                                             action:nil];
    chooseBtn.translatesAutoresizingMaskIntoConstraints = NO;
    chooseBtn.bezelStyle = NSBezelStyleRounded;

    NSStackView *stack = [[NSStackView alloc] init];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    stack.alignment = NSLayoutAttributeCenterY;
    stack.spacing = [MacLCDesign spacingS];
    [stack addArrangedSubview:field];
    [stack addArrangedSubview:chooseBtn];

    MacLCSettingsRow *row = [[self alloc] initWithTitle:title explanation:explanation control:stack];
    row.textField = field;
    row.chooseButtonHandler = chooseAction;

    chooseBtn.target = row;
    chooseBtn.action = @selector(chooseButtonFired:);

    return row;
}

- (void)chooseButtonFired:(id)sender
{
    if (self.chooseButtonHandler) {
        self.chooseButtonHandler(self);
    }
}

+ (instancetype)stepperRowWithTitle:(NSString *)title
                        explanation:(NSString *)explanation
                           minValue:(double)minValue
                           maxValue:(double)maxValue
                       initialValue:(double)initialValue
                          stepValue:(double)stepValue
                        valueFormat:(NSString *)valueFormat
                             action:(nullable void (^)(double value))action
{
    NSTextField *readout = [NSTextField labelWithString:@""];
    readout.translatesAutoresizingMaskIntoConstraints = NO;
    readout.font = [MacLCDesign monospacedDigitFontForTextStyle:NSFontTextStyleCaption1];
    readout.textColor = [MacLCDesign secondaryLabel];
    readout.alignment = NSTextAlignmentRight;
    [readout.widthAnchor constraintGreaterThanOrEqualToConstant:50].active = YES;

    NSString *fmt = valueFormat.length > 0 ? valueFormat : @"%.0f";
    readout.stringValue = [NSString stringWithFormat:fmt, initialValue];

    NSStepper *stepper = [[NSStepper alloc] initWithFrame:NSZeroRect];
    stepper.translatesAutoresizingMaskIntoConstraints = NO;
    stepper.minValue = minValue;
    stepper.maxValue = maxValue;
    stepper.increment = stepValue;
    stepper.doubleValue = initialValue;

    NSStackView *stack = [[NSStackView alloc] init];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    stack.alignment = NSLayoutAttributeCenterY;
    stack.spacing = [MacLCDesign spacingXS];
    [stack addArrangedSubview:readout];
    [stack addArrangedSubview:stepper];

    MacLCSettingsRow *row = [[self alloc] initWithTitle:title explanation:explanation control:stack];
    row.stepper = stepper;
    row.sliderReadoutLabel = readout;
    row.stepperFormat = fmt;
    row.stepperChangedHandler = action;

    stepper.target = row;
    stepper.action = @selector(stepperFired:);

    return row;
}

- (void)stepperFired:(id)sender
{
    double val = self.stepper.doubleValue;
    self.sliderReadoutLabel.stringValue = [NSString stringWithFormat:self.stepperFormat, val];
    if (self.stepperChangedHandler) {
        self.stepperChangedHandler(val);
    }
}

+ (instancetype)radioGroupRowWithTitle:(NSString *)title
                           explanation:(NSString *)explanation
                               options:(NSArray<NSString *> *)options
                         selectedIndex:(NSInteger)selectedIndex
                                action:(nullable void (^)(NSInteger selectedIndex))action
{
    NSStackView *radioStack = [[NSStackView alloc] init];
    radioStack.translatesAutoresizingMaskIntoConstraints = NO;
    radioStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    radioStack.alignment = NSLayoutAttributeLeading;
    radioStack.spacing = [MacLCDesign spacingXS];

    NSMutableArray<NSButton *> *buttons = [NSMutableArray arrayWithCapacity:options.count];

    MacLCSettingsRow *row = [[self alloc] initWithTitle:title explanation:explanation control:radioStack];
    row.radioChangedHandler = action;

    for (NSUInteger i = 0; i < options.count; i++) {
        NSButton *radio = [NSButton radioButtonWithTitle:options[i] target:row action:@selector(radioFired:)];
        radio.translatesAutoresizingMaskIntoConstraints = NO;
        radio.tag = (NSInteger)i;
        radio.state = (i == (NSUInteger)selectedIndex) ? NSControlStateValueOn : NSControlStateValueOff;
        [radioStack addArrangedSubview:radio];
        [buttons addObject:radio];
    }
    row.radioButtons = [buttons copy];

    return row;
}

- (void)radioFired:(id)sender
{
    NSButton *selected = (NSButton *)sender;
    NSInteger selectedIdx = selected.tag;
    for (NSButton *btn in self.radioButtons) {
        btn.state = (btn == selected) ? NSControlStateValueOn : NSControlStateValueOff;
    }
    if (self.radioChangedHandler) {
        self.radioChangedHandler(selectedIdx);
    }
}

@end
