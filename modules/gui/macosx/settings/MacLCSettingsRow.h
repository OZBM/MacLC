/*****************************************************************************
 * MacLCSettingsRow.h: MacLC reusable settings row builder
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

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * MacLCSettingsRow implements the canonical settings row idiom for MacLC:
 *
 * ┌──────────────────────────────────────────────────────────────────┐
 * │ [!] Label text                                   [ control ]     │
 * │ One sentence saying what changing this does, in terms of what    │
 * │ the user will see or hear.                                       │
 * │ Default: <built-in default>                                      │
 * └──────────────────────────────────────────────────────────────────┘
 *
 * Visual hierarchy:
 * - Label: primaryLabel, bodyEmphasized font.
 * - Explanation: secondaryLabel, caption font, wraps to as many lines as needed.
 * - Control: trailing-aligned, vertically centred with the label.
 * - Warning: optional exclamationmark.triangle.fill glyph preceding label.
 * - Default hint: optional tertiaryLabel caption showing default value.
 */
@interface MacLCSettingsRow : NSView

#pragma mark - Primary Views

/// The label displaying the setting name.
@property (nonatomic, readonly) NSTextField *titleLabel;

/// The multi-line label explaining what changing the setting does.
@property (nonatomic, readonly) NSTextField *explanationLabel;

/// The control view aligned to the trailing edge.
@property (nonatomic, readonly) NSView *controlView;

/// Optional default hint label.
@property (nonatomic, readonly) NSTextField *defaultHintLabel;

/// Warning icon displayed before the title when `warning` is YES.
@property (nonatomic, readonly) NSImageView *warningImageView;

#pragma mark - Configuration Properties

/// If YES, displays a warning symbol before the title.
@property (nonatomic, assign) BOOL warning;

/// Built-in default string (e.g. @"Default: English"). When nil, hint is hidden.
@property (nonatomic, copy, nullable) NSString *defaultHint;

/// Enables or disables the row and its interactive controls.
@property (nonatomic, assign) BOOL enabled;

#pragma mark - Typed Control Accessors

@property (nonatomic, readonly, nullable) NSButton *checkboxButton;
@property (nonatomic, readonly, nullable) NSPopUpButton *popUpButton;
@property (nonatomic, readonly, nullable) NSSlider *slider;
@property (nonatomic, readonly, nullable) NSTextField *sliderReadoutLabel;
@property (nonatomic, readonly, nullable) NSTextField *textField;
@property (nonatomic, readonly, nullable) NSStepper *stepper;
@property (nonatomic, readonly, nullable) NSArray<NSButton *> *radioButtons;

#pragma mark - Event Handlers

@property (nonatomic, copy, nullable) void (^checkboxChangedHandler)(BOOL checked);
@property (nonatomic, copy, nullable) void (^popUpChangedHandler)(NSInteger index, NSInteger tag);
@property (nonatomic, copy, nullable) void (^sliderChangedHandler)(double value);
@property (nonatomic, copy, nullable) void (^textChangedHandler)(NSString *text);
@property (nonatomic, copy, nullable) void (^stepperChangedHandler)(double value);
@property (nonatomic, copy, nullable) void (^radioChangedHandler)(NSInteger index);
@property (nonatomic, copy, nullable) void (^chooseButtonHandler)(MacLCSettingsRow *row);

#pragma mark - Initializers & Factory Methods

/**
 * Designated initializer building a row with arbitrary control.
 */
- (instancetype)initWithTitle:(NSString *)title
                  explanation:(NSString *)explanation
                      control:(NSView *)control NS_DESIGNATED_INITIALIZER;

- (nullable instancetype)initWithCoder:(NSCoder *)coder NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithFrame:(NSRect)frameRect NS_UNAVAILABLE;

+ (instancetype)rowWithTitle:(NSString *)title
                 explanation:(NSString *)explanation
                     control:(NSView *)control;

/**
 * Creates a toggle switch / checkbox row.
 */
+ (instancetype)checkboxRowWithTitle:(NSString *)title
                         explanation:(NSString *)explanation
                               state:(BOOL)state
                              action:(nullable void (^)(BOOL checked))action;

/**
 * Creates a popup menu row.
 */
+ (instancetype)popUpRowWithTitle:(NSString *)title
                      explanation:(NSString *)explanation
                            items:(NSArray<NSString *> *)items
                             tags:(nullable NSArray<NSNumber *> *)tags
                    selectedIndex:(NSInteger)selectedIndex
                           action:(nullable void (^)(NSInteger selectedIndex, NSInteger tag))action;

/**
 * Creates a slider row with an adjacent live monospaced readout label.
 */
+ (instancetype)sliderRowWithTitle:(NSString *)title
                       explanation:(NSString *)explanation
                          minValue:(double)minValue
                          maxValue:(double)maxValue
                      initialValue:(double)initialValue
                       valueFormat:(NSString *)valueFormat
                            action:(nullable void (^)(double value))action;

/**
 * Creates a text field row (optionally secure).
 */
+ (instancetype)textFieldRowWithTitle:(NSString *)title
                          explanation:(NSString *)explanation
                                 text:(nullable NSString *)text
                          placeholder:(nullable NSString *)placeholder
                             isSecure:(BOOL)isSecure
                               action:(nullable void (^)(NSString *text))action;

/**
 * Creates a path picker row with a path field and a "Choose…" button.
 */
+ (instancetype)pathPickerRowWithTitle:(NSString *)title
                           explanation:(NSString *)explanation
                                  path:(nullable NSString *)path
                           chooseTitle:(nullable NSString *)chooseTitle
                          chooseAction:(nullable void (^)(MacLCSettingsRow *row))chooseAction;

/**
 * Creates a stepper row with an adjacent live readout label.
 */
+ (instancetype)stepperRowWithTitle:(NSString *)title
                        explanation:(NSString *)explanation
                           minValue:(double)minValue
                           maxValue:(double)maxValue
                       initialValue:(double)initialValue
                          stepValue:(double)stepValue
                        valueFormat:(NSString *)valueFormat
                             action:(nullable void (^)(double value))action;

/**
 * Creates a radio group row.
 */
+ (instancetype)radioGroupRowWithTitle:(NSString *)title
                           explanation:(NSString *)explanation
                               options:(NSArray<NSString *> *)options
                         selectedIndex:(NSInteger)selectedIndex
                                action:(nullable void (^)(NSInteger selectedIndex))action;

@end

NS_ASSUME_NONNULL_END
