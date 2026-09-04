/*****************************************************************************
 * MacLCSubtitlesSettingsViewController.m: Subtitles Settings Pane for MacLC
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

#import "settings/panes/MacLCSubtitlesSettingsViewController.h"
#import "settings/MacLCSettingsRow.h"
#import "theme/MacLCDesign.h"
#import "theme/MacLCCardView.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wnullability-completeness"
#import "extensions/NSString+Helpers.h"
#pragma clang diagnostic pop

#import <vlc_configuration.h>

@interface MacLCSubtitlesSettingsViewController ()

{
    intf_thread_t *_p_intf;
}

@property (nonatomic, assign) BOOL hasUnsavedChanges;

// Rows
@property (nonatomic, strong) MacLCSettingsRow *osdRow;
@property (nonatomic, strong) MacLCSettingsRow *subLangRow;
@property (nonatomic, strong) MacLCSettingsRow *encodingRow;
@property (nonatomic, strong) MacLCSettingsRow *autodetectRow;

@property (nonatomic, strong) MacLCSettingsRow *fontRow;
@property (nonatomic, strong) MacLCSettingsRow *fontSizeRow;
@property (nonatomic, strong) MacLCSettingsRow *fontColorRow;
@property (nonatomic, strong) MacLCSettingsRow *fontOpacityRow;
@property (nonatomic, strong) MacLCSettingsRow *fontBoldRow;

@property (nonatomic, strong) MacLCCardView *advancedCard;
@property (nonatomic, strong) NSButton *advancedDisclosureButton;
@property (nonatomic, strong) MacLCSettingsRow *outlineThicknessRow;
@property (nonatomic, strong) MacLCSettingsRow *outlineColorRow;
@property (nonatomic, strong) MacLCSettingsRow *shadowOpacityRow;

@end

@implementation MacLCSubtitlesSettingsViewController

- (instancetype)initWithIntf:(intf_thread_t *)intf
{
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _p_intf = intf;
    }
    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];
    return self;
}

#pragma mark - MacLCSettingsPane Protocol Properties

- (NSString *)paneTitle
{
    return _NS("Subtitles");
}

- (NSString *)paneSymbolName
{
    return @"captions.bubble";
}

- (NSString *)paneIdentifier
{
    return @"subtitles";
}

- (NSArray<NSString *> *)searchKeywords
{
    return @[
        @"subtitles", @"osd", @"font", @"color", @"size", @"encoding",
        @"language", @"autoload", @"autodetect", @"bold", @"outline",
        @"shadow", @"opacity", @"scale", @"caption",
        @"osd", @"sub-language", @"subsdec-encoding", @"sub-autodetect-file",
        @"freetype-font", @"sub-text-scale", @"freetype-color",
        @"freetype-opacity", @"freetype-bold", @"freetype-outline-thickness",
        @"freetype-outline-color", @"freetype-shadow-opacity"
    ];
}

#pragma mark - View Lifecycle & Layout

- (void)loadView
{
    NSView *container = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 600, 1050)];
    container.translatesAutoresizingMaskIntoConstraints = NO;
    self.view = container;

    NSStackView *rootStack = [[NSStackView alloc] init];
    rootStack.translatesAutoresizingMaskIntoConstraints = NO;
    rootStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    rootStack.alignment = NSLayoutAttributeLeading;
    rootStack.spacing = [MacLCDesign groupSpacing];

    [container addSubview:rootStack];

    [NSLayoutConstraint activateConstraints:@[
        [rootStack.leadingAnchor constraintEqualToAnchor:container.leadingAnchor
                                                constant:[MacLCDesign windowContentMargin]],
        [rootStack.trailingAnchor constraintEqualToAnchor:container.trailingAnchor
                                                 constant:-[MacLCDesign windowContentMargin]],
        [rootStack.topAnchor constraintEqualToAnchor:container.topAnchor
                                            constant:[MacLCDesign windowContentMargin]],
        [rootStack.bottomAnchor constraintEqualToAnchor:container.bottomAnchor
                                               constant:-[MacLCDesign windowContentMargin]],
        [container.widthAnchor constraintGreaterThanOrEqualToConstant:480]
    ]];

    __weak typeof(self) weakSelf = self;

    // Card 1: Subtitles & OSD
    MacLCCardView *generalCard = [MacLCCardView cardViewWithTitle:_NS("Subtitles & OSD")];
    generalCard.translatesAutoresizingMaskIntoConstraints = NO;
    [rootStack addArrangedSubview:generalCard];
    [generalCard.trailingAnchor constraintEqualToAnchor:rootStack.trailingAnchor].active = YES;

    _osdRow = [MacLCSettingsRow checkboxRowWithTitle:_NS("Enable On-Screen Display (OSD)")
                                         explanation:_NS("Show subtitles, volume adjustments, and playback state indicators over video.")
                                               state:YES
                                              action:^(BOOL checked) {
        weakSelf.hasUnsavedChanges = YES;
    }];
    _osdRow.defaultHint = _NS("Default: On");
    [generalCard.contentStackView addArrangedSubview:_osdRow];

    _subLangRow = [MacLCSettingsRow textFieldRowWithTitle:_NS("Preferred Subtitle Languages")
                                              explanation:_NS("Comma-separated two-letter codes (e.g. en, fr, de) for automatic subtitle track selection.")
                                                     text:@""
                                              placeholder:@"en, fr"
                                                 isSecure:NO
                                                   action:^(NSString *text) {
        weakSelf.hasUnsavedChanges = YES;
    }];
    _subLangRow.defaultHint = _NS("Default: Empty");
    [generalCard.contentStackView addArrangedSubview:_subLangRow];

    NSArray<NSString *> *encodings = @[
        _NS("Default (UTF-8)"), @"ISO-8859-1 (Latin 1)", @"Windows-1252",
        @"UTF-16", @"ISO-8859-15", @"Big5", @"GB18030", @"Shift-JIS"
    ];
    _encodingRow = [MacLCSettingsRow popUpRowWithTitle:_NS("Default Text Encoding")
                                           explanation:_NS("Character encoding used for subtitle files that do not declare their own format.")
                                                 items:encodings
                                                  tags:nil
                                         selectedIndex:0
                                                action:^(NSInteger selectedIndex, NSInteger tag) {
        weakSelf.hasUnsavedChanges = YES;
    }];
    _encodingRow.defaultHint = _NS("Default: UTF-8");
    [generalCard.contentStackView addArrangedSubview:_encodingRow];

    _autodetectRow = [MacLCSettingsRow checkboxRowWithTitle:_NS("Auto-Detect Subtitle Files")
                                                explanation:_NS("Automatically load external subtitle files (.srt, .vtt) located next to the video.")
                                                      state:YES
                                                     action:^(BOOL checked) {
        weakSelf.hasUnsavedChanges = YES;
    }];
    _autodetectRow.defaultHint = _NS("Default: On");
    [generalCard.contentStackView addArrangedSubview:_autodetectRow];

    // Card 2: Font & Styling
    MacLCCardView *fontCard = [MacLCCardView cardViewWithTitle:_NS("Font & Styling")];
    fontCard.translatesAutoresizingMaskIntoConstraints = NO;
    [rootStack addArrangedSubview:fontCard];
    [fontCard.trailingAnchor constraintEqualToAnchor:rootStack.trailingAnchor].active = YES;

    _fontRow = [MacLCSettingsRow textFieldRowWithTitle:_NS("Font Family")
                                           explanation:_NS("Typeface name used to render subtitle characters.")
                                                  text:@"Helvetica Neue"
                                           placeholder:@"Helvetica Neue"
                                              isSecure:NO
                                                action:^(NSString *text) {
        weakSelf.hasUnsavedChanges = YES;
    }];
    _fontRow.defaultHint = _NS("Default: Arial / Helvetica Neue");
    [fontCard.contentStackView addArrangedSubview:_fontRow];

    _fontSizeRow = [MacLCSettingsRow sliderRowWithTitle:_NS("Font Size Scale")
                                            explanation:_NS("Relative text size multiplier for subtitle readability.")
                                               minValue:50
                                               maxValue:200
                                           initialValue:100
                                            valueFormat:@"%.0f%%"
                                                 action:^(double value) {
        weakSelf.hasUnsavedChanges = YES;
    }];
    _fontSizeRow.defaultHint = _NS("Default: 100%");
    [fontCard.contentStackView addArrangedSubview:_fontSizeRow];

    NSArray<NSString *> *colors = @[
        _NS("White"), _NS("Yellow"), _NS("Cyan"), _NS("Green"),
        _NS("Magenta"), _NS("Red"), _NS("Blue"), _NS("Black")
    ];
    _fontColorRow = [MacLCSettingsRow popUpRowWithTitle:_NS("Text Color")
                                            explanation:_NS("Foreground color of subtitle characters.")
                                                  items:colors
                                                   tags:@[@0x00FFFFFF, @0x00FFFF00, @0x0000FFFF, @0x0000FF00,
                                                          @0x00FF00FF, @0x00FF0000, @0x000000FF, @0x00000000]
                                          selectedIndex:0
                                                 action:^(NSInteger selectedIndex, NSInteger tag) {
        weakSelf.hasUnsavedChanges = YES;
    }];
    _fontColorRow.defaultHint = _NS("Default: White");
    [fontCard.contentStackView addArrangedSubview:_fontColorRow];

    _fontOpacityRow = [MacLCSettingsRow sliderRowWithTitle:_NS("Text Opacity")
                                               explanation:_NS("Subtitle transparency level from transparent to solid.")
                                                  minValue:0
                                                  maxValue:100
                                              initialValue:100
                                               valueFormat:@"%.0f%%"
                                                    action:^(double value) {
        weakSelf.hasUnsavedChanges = YES;
    }];
    _fontOpacityRow.defaultHint = _NS("Default: 100%");
    [fontCard.contentStackView addArrangedSubview:_fontOpacityRow];

    _fontBoldRow = [MacLCSettingsRow checkboxRowWithTitle:_NS("Bold Text")
                                              explanation:_NS("Draw subtitle characters with heavier stroke weight for improved contrast.")
                                                    state:NO
                                                   action:^(BOOL checked) {
        weakSelf.hasUnsavedChanges = YES;
    }];
    _fontBoldRow.defaultHint = _NS("Default: Off");
    [fontCard.contentStackView addArrangedSubview:_fontBoldRow];

    // Card 3: Advanced Outline & Shadow (collapsed disclosure)
    _advancedDisclosureButton = [NSButton buttonWithTitle:_NS("Advanced Outline & Shadow ▶")
                                                   target:self
                                                   action:@selector(toggleAdvancedAction:)];
    _advancedDisclosureButton.bezelStyle = NSBezelStyleInline;
    [rootStack addArrangedSubview:_advancedDisclosureButton];

    _advancedCard = [MacLCCardView cardViewWithTitle:_NS("Outline & Shadow (Advanced)")];
    _advancedCard.translatesAutoresizingMaskIntoConstraints = NO;
    _advancedCard.hidden = YES;
    [rootStack addArrangedSubview:_advancedCard];
    [_advancedCard.trailingAnchor constraintEqualToAnchor:rootStack.trailingAnchor].active = YES;

    _outlineThicknessRow = [MacLCSettingsRow popUpRowWithTitle:_NS("Outline Thickness")
                                                   explanation:_NS("Width of the contrast border drawn around subtitle letters.")
                                                         items:@[_NS("None"), _NS("Thin"), _NS("Normal"), _NS("Thick")]
                                                          tags:@[@0, @1, @2, @3]
                                                 selectedIndex:2
                                                        action:^(NSInteger selectedIndex, NSInteger tag) {
        weakSelf.hasUnsavedChanges = YES;
    }];
    _outlineThicknessRow.defaultHint = _NS("Default: Normal");
    [_advancedCard.contentStackView addArrangedSubview:_outlineThicknessRow];

    _outlineColorRow = [MacLCSettingsRow popUpRowWithTitle:_NS("Outline Color")
                                               explanation:_NS("Color of the contrast outline drawn around subtitle characters.")
                                                     items:@[_NS("Black"), _NS("Dark Gray"), _NS("Light Gray"), _NS("White")]
                                                      tags:@[@0x00000000, @0x00808080, @0x00C0C0C0, @0x00FFFFFF]
                                             selectedIndex:0
                                                    action:^(NSInteger selectedIndex, NSInteger tag) {
        weakSelf.hasUnsavedChanges = YES;
    }];
    _outlineColorRow.defaultHint = _NS("Default: Black");
    [_advancedCard.contentStackView addArrangedSubview:_outlineColorRow];

    _shadowOpacityRow = [MacLCSettingsRow sliderRowWithTitle:_NS("Drop Shadow Opacity")
                                                 explanation:_NS("Intensity of the drop shadow rendered beneath subtitle characters.")
                                                    minValue:0
                                                    maxValue:100
                                                initialValue:50
                                                 valueFormat:@"%.0f%%"
                                                      action:^(double value) {
        weakSelf.hasUnsavedChanges = YES;
    }];
    _shadowOpacityRow.defaultHint = _NS("Default: 50%");
    [_advancedCard.contentStackView addArrangedSubview:_shadowOpacityRow];

    // Reset button
    NSButton *resetBtn = [NSButton buttonWithTitle:_NS("Reset Subtitle Settings…")
                                            target:self
                                            action:@selector(resetSectionAction:)];
    resetBtn.translatesAutoresizingMaskIntoConstraints = NO;
    resetBtn.bezelStyle = NSBezelStyleRounded;
    [rootStack addArrangedSubview:resetBtn];

    [self loadSettings];
}

- (void)toggleAdvancedAction:(id)sender
{
    BOOL isHidden = !_advancedCard.hidden;
    _advancedCard.hidden = isHidden;
    _advancedDisclosureButton.title = isHidden ? _NS("Advanced Outline & Shadow ▶")
                                               : _NS("Advanced Outline & Shadow ▼");
}

- (void)resetSectionAction:(id)sender
{
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = _NS("Reset Subtitle Settings");
    alert.informativeText = _NS("Are you sure you want to reset all Subtitle options to their default values?");
    [alert addButtonWithTitle:_NS("Reset")];
    [alert addButtonWithTitle:_NS("Cancel")];

    __weak typeof(self) weakSelf = self;
    [alert beginSheetModalForWindow:self.view.window completionHandler:^(NSModalResponse returnCode) {
        if (returnCode == NSAlertFirstButtonReturn) {
            [weakSelf resetToDefaults];
        }
    }];
}

#pragma mark - Settings Operations

- (void)loadSettings
{
    _osdRow.checkboxButton.state = config_GetInt("osd") ? NSControlStateValueOn : NSControlStateValueOff;

    char *subLang = config_GetPsz("sub-language");
    _subLangRow.textField.stringValue = subLang ? toNSStr(subLang) : @"";
    free(subLang);

    char *enc = config_GetPsz("subsdec-encoding");
    NSString *encStr = enc ? toNSStr(enc) : @"";
    free(enc);
    if (encStr.length == 0 || [encStr isEqualToString:@"UTF-8"]) {
        [_encodingRow.popUpButton selectItemAtIndex:0];
    } else {
        [_encodingRow.popUpButton selectItemWithTitle:encStr];
    }

    _autodetectRow.checkboxButton.state = config_GetInt("sub-autodetect-file") ? NSControlStateValueOn : NSControlStateValueOff;

    char *font = config_GetPsz("freetype-font");
    _fontRow.textField.stringValue = font ? toNSStr(font) : @"Helvetica Neue";
    free(font);

    int scale = (int)config_GetInt("sub-text-scale");
    if (scale <= 0) scale = 100;
    _fontSizeRow.slider.doubleValue = scale;
    _fontSizeRow.sliderReadoutLabel.stringValue = [NSString stringWithFormat:@"%d%%", scale];

    int colorVal = (int)config_GetInt("freetype-color");
    [_fontColorRow.popUpButton selectItemWithTag:colorVal];

    int opacity = (int)(config_GetInt("freetype-opacity") * 100.0 / 255.0 + 0.5);
    _fontOpacityRow.slider.doubleValue = opacity;
    _fontOpacityRow.sliderReadoutLabel.stringValue = [NSString stringWithFormat:@"%d%%", opacity];

    _fontBoldRow.checkboxButton.state = config_GetInt("freetype-bold") ? NSControlStateValueOn : NSControlStateValueOff;

    [_outlineThicknessRow.popUpButton selectItemWithTag:config_GetInt("freetype-outline-thickness")];
    [_outlineColorRow.popUpButton selectItemWithTag:config_GetInt("freetype-outline-color")];

    int shadow = (int)(config_GetInt("freetype-shadow-opacity") * 100.0 / 255.0 + 0.5);
    _shadowOpacityRow.slider.doubleValue = shadow;
    _shadowOpacityRow.sliderReadoutLabel.stringValue = [NSString stringWithFormat:@"%d%%", shadow];

    self.hasUnsavedChanges = NO;
}

- (void)applyChanges
{
    config_PutInt("osd", _osdRow.checkboxButton.state == NSControlStateValueOn);
    config_PutPsz("sub-language", [_subLangRow.textField.stringValue UTF8String]);

    NSString *enc = _encodingRow.popUpButton.titleOfSelectedItem;
    if ([enc hasPrefix:_NS("Default")]) {
        config_PutPsz("subsdec-encoding", "");
    } else {
        config_PutPsz("subsdec-encoding", [enc UTF8String]);
    }

    config_PutInt("sub-autodetect-file", _autodetectRow.checkboxButton.state == NSControlStateValueOn);
    config_PutPsz("freetype-font", [_fontRow.textField.stringValue UTF8String]);
    config_PutInt("sub-text-scale", (int)_fontSizeRow.slider.doubleValue);
    config_PutInt("freetype-color", (int)_fontColorRow.popUpButton.selectedTag);
    config_PutInt("freetype-opacity", (int)(_fontOpacityRow.slider.doubleValue * 255.0 / 100.0 + 0.5));
    config_PutInt("freetype-bold", _fontBoldRow.checkboxButton.state == NSControlStateValueOn);

    config_PutInt("freetype-outline-thickness", (int)_outlineThicknessRow.popUpButton.selectedTag);
    config_PutInt("freetype-outline-color", (int)_outlineColorRow.popUpButton.selectedTag);
    config_PutInt("freetype-shadow-opacity", (int)(_shadowOpacityRow.slider.doubleValue * 255.0 / 100.0 + 0.5));

    self.hasUnsavedChanges = NO;
}

- (void)resetToDefaults
{
    module_config_t *item;
    if ((item = config_FindConfig("osd"))) config_PutInt("osd", item->orig.i);
    if ((item = config_FindConfig("sub-language"))) config_PutPsz("sub-language", item->orig.psz ? item->orig.psz : "");
    if ((item = config_FindConfig("subsdec-encoding"))) config_PutPsz("subsdec-encoding", item->orig.psz ? item->orig.psz : "");
    if ((item = config_FindConfig("sub-autodetect-file"))) config_PutInt("sub-autodetect-file", item->orig.i);
    if ((item = config_FindConfig("freetype-font"))) config_PutPsz("freetype-font", item->orig.psz ? item->orig.psz : "");
    if ((item = config_FindConfig("sub-text-scale"))) config_PutInt("sub-text-scale", item->orig.i);
    if ((item = config_FindConfig("freetype-color"))) config_PutInt("freetype-color", item->orig.i);
    if ((item = config_FindConfig("freetype-opacity"))) config_PutInt("freetype-opacity", item->orig.i);
    if ((item = config_FindConfig("freetype-bold"))) config_PutInt("freetype-bold", item->orig.i);
    if ((item = config_FindConfig("freetype-outline-thickness"))) config_PutInt("freetype-outline-thickness", item->orig.i);
    if ((item = config_FindConfig("freetype-outline-color"))) config_PutInt("freetype-outline-color", item->orig.i);
    if ((item = config_FindConfig("freetype-shadow-opacity"))) config_PutInt("freetype-shadow-opacity", item->orig.i);

    [self loadSettings];
    self.hasUnsavedChanges = YES;
}

@end
