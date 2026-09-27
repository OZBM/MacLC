/*****************************************************************************
 * MacLCDetailHeaderView.m: header of album, artist, show, genre and playlist
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

#import "medialib/components/MacLCDetailHeaderView.h"

#import "extensions/NSString+Helpers.h"
#import "medialib/components/MacLCArtworkView.h"
#import "theme/MacLCDesign.h"

static const CGFloat MacLCDetailHeaderInset = 24.0;
static const CGFloat MacLCDetailHeaderCompactWidth = 640.0;

/* The subtitle as a link: label colour, underlined on hover, pointing hand. */
@interface MacLCDetailLinkField : NSTextField
@property (nonatomic, copy, nullable) void (^linkAction)(void);
@end

@implementation MacLCDetailLinkField
{
    NSTrackingArea *_trackingArea;
}

- (void)updateTrackingAreas
{
    [super updateTrackingAreas];
    if (_trackingArea != nil) {
        [self removeTrackingArea:_trackingArea];
    }
    _trackingArea = [[NSTrackingArea alloc] initWithRect:self.bounds
                                                 options:NSTrackingMouseEnteredAndExited
                                                         | NSTrackingActiveInKeyWindow | NSTrackingInVisibleRect
                                                   owner:self
                                                userInfo:nil];
    [self addTrackingArea:_trackingArea];
}

- (void)setUnderlined:(BOOL)underlined
{
    NSMutableAttributedString * const text = [self.attributedStringValue mutableCopy];
    [text addAttribute:NSUnderlineStyleAttributeName
                 value:@(underlined ? NSUnderlineStyleSingle : NSUnderlineStyleNone)
                 range:NSMakeRange(0, text.length)];
    self.attributedStringValue = text;
}

- (void)mouseEntered:(NSEvent *)event
{
    if (self.linkAction != nil) {
        [self setUnderlined:YES];
    }
}

- (void)mouseExited:(NSEvent *)event
{
    [self setUnderlined:NO];
}

- (void)resetCursorRects
{
    if (self.linkAction != nil) {
        [self addCursorRect:self.bounds cursor:NSCursor.pointingHandCursor];
    }
}

- (void)mouseUp:(NSEvent *)event
{
    if (self.linkAction != nil) {
        self.linkAction();
    }
}

- (BOOL)accessibilityPerformPress
{
    if (self.linkAction != nil) {
        self.linkAction();
        return YES;
    }
    return NO;
}

- (NSAccessibilityRole)accessibilityRole
{
    return self.linkAction != nil ? NSAccessibilityLinkRole : NSAccessibilityStaticTextRole;
}

@end

@interface MacLCDetailHeaderView ()
{
    MacLCArtworkShape _shape;
    NSTextField *_titleField;
    MacLCDetailLinkField *_subtitleField;
    NSTextField *_detailField;
    NSButton *_primaryButton;
    NSButton *_secondaryButton;
    NSPopUpButton *_moreButton;
    NSStackView *_buttonRow;
    NSLayoutConstraint *_artworkWidth;
    void (^_primaryAction)(void);
    void (^_secondaryAction)(void);
}
@end

@implementation MacLCDetailHeaderView

- (instancetype)initWithArtworkShape:(MacLCArtworkShape)shape
{
    self = [super initWithFrame:NSMakeRect(0, 0, 800, 260)];
    if (self) {
        _shape = shape;
        [self setUpViews];
    }
    return self;
}

- (void)setUpViews
{
    _artworkView = [[MacLCArtworkView alloc] initWithShape:_shape];
    _artworkView.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:_artworkView];

    _titleField = [NSTextField wrappingLabelWithString:@""];
    _titleField.font = [NSFont systemFontOfSize:MacLCDesign.title1.pointSize weight:NSFontWeightBold];
    _titleField.textColor = NSColor.labelColor;
    _titleField.maximumNumberOfLines = 2;
    _titleField.lineBreakMode = NSLineBreakByTruncatingTail;
    _titleField.selectable = NO;
    _titleField.accessibilityRole = NSAccessibilityStaticTextRole;

    _subtitleField = [[MacLCDetailLinkField alloc] initWithFrame:NSZeroRect];
    _subtitleField.bezeled = NO;
    _subtitleField.drawsBackground = NO;
    _subtitleField.editable = NO;
    _subtitleField.selectable = NO;
    _subtitleField.font = MacLCDesign.title3;
    _subtitleField.textColor = NSColor.labelColor;
    _subtitleField.lineBreakMode = NSLineBreakByTruncatingTail;

    _detailField = [NSTextField labelWithString:@""];
    _detailField.font = MacLCDesign.subheadline;
    _detailField.textColor = NSColor.secondaryLabelColor;
    _detailField.lineBreakMode = NSLineBreakByTruncatingTail;

    _primaryButton = [NSButton buttonWithTitle:@"" target:self action:@selector(primaryPressed:)];
    _primaryButton.bezelStyle = NSBezelStyleGlass;
    _primaryButton.controlSize = NSControlSizeLarge;
    _primaryButton.tintProminence = NSTintProminencePrimary;
    _primaryButton.bezelColor = MacLCDesign.accent;
    _primaryButton.imagePosition = NSImageLeading;
    _primaryButton.hidden = YES;

    _secondaryButton = [NSButton buttonWithTitle:@"" target:self action:@selector(secondaryPressed:)];
    _secondaryButton.bezelStyle = NSBezelStyleGlass;
    _secondaryButton.controlSize = NSControlSizeLarge;
    _secondaryButton.imagePosition = NSImageLeading;
    _secondaryButton.hidden = YES;

    _moreButton = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:YES];
    _moreButton.bezelStyle = NSBezelStyleGlass;
    _moreButton.controlSize = NSControlSizeLarge;
    _moreButton.imagePosition = NSImageOnly;
    ((NSPopUpButtonCell *)_moreButton.cell).arrowPosition = NSPopUpNoArrow;
    _moreButton.toolTip = _NS("More");
    /* A round button, like the system's glass "···" buttons. */
    _moreButton.translatesAutoresizingMaskIntoConstraints = NO;
    [_moreButton.widthAnchor constraintEqualToAnchor:_moreButton.heightAnchor].active = YES;
    _moreButton.accessibilityLabel = _NS("More");
    _moreButton.hidden = YES;

    _buttonRow = [NSStackView stackViewWithViews:@[_primaryButton, _secondaryButton, _moreButton]];
    _buttonRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    _buttonRow.spacing = 12.0;

    NSStackView * const column = [NSStackView stackViewWithViews:@[_titleField, _subtitleField, _detailField, _buttonRow]];
    column.orientation = NSUserInterfaceLayoutOrientationVertical;
    column.alignment = NSLayoutAttributeLeading;
    column.spacing = 4.0;
    [column setCustomSpacing:16.0 afterView:_detailField];
    column.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:column];

    const CGFloat artworkWidth = _shape == MacLCArtworkShapeVideo ? 320.0 : 200.0;
    _artworkWidth = [_artworkView.widthAnchor constraintEqualToConstant:artworkWidth];
    /* The header is as tall as its artwork (or its text, if taller): without
     * this it took every point the detail screen gave it, and the list below
     * got none. */
    NSLayoutConstraint * const hugArtwork =
        [_artworkView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-MacLCDetailHeaderInset];
    hugArtwork.priority = NSLayoutPriorityDefaultHigh;
    [NSLayoutConstraint activateConstraints:@[
        _artworkWidth,
        hugArtwork,
        [column.bottomAnchor constraintLessThanOrEqualToAnchor:self.bottomAnchor constant:-MacLCDetailHeaderInset],
        [_artworkView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:MacLCDetailHeaderInset],
        [_artworkView.topAnchor constraintEqualToAnchor:self.topAnchor constant:MacLCDetailHeaderInset],
        [_artworkView.bottomAnchor constraintLessThanOrEqualToAnchor:self.bottomAnchor constant:-MacLCDetailHeaderInset],
        [column.leadingAnchor constraintEqualToAnchor:_artworkView.trailingAnchor constant:MacLCDetailHeaderInset],
        [column.trailingAnchor constraintLessThanOrEqualToAnchor:self.trailingAnchor constant:-MacLCDetailHeaderInset],
        [column.centerYAnchor constraintEqualToAnchor:_artworkView.centerYAnchor],
        [column.topAnchor constraintGreaterThanOrEqualToAnchor:self.topAnchor constant:MacLCDetailHeaderInset],
        [_titleField.widthAnchor constraintLessThanOrEqualToConstant:560.0],
    ]];
}

- (void)layout
{
    [super layout];
    const BOOL compact = NSWidth(self.bounds) < MacLCDetailHeaderCompactWidth;
    const CGFloat width = _shape == MacLCArtworkShapeVideo ? (compact ? 224.0 : 320.0) : (compact ? 140.0 : 200.0);
    if (fabs(_artworkWidth.constant - width) > 0.5) {
        _artworkWidth.constant = width;
    }
}

// MARK: - Contents

- (void)setTitle:(NSString *)title
{
    _title = [title copy];
    _titleField.stringValue = title ?: @"";
}

- (void)setSubtitle:(nullable NSString *)subtitle
{
    _subtitle = [subtitle copy];
    _subtitleField.stringValue = subtitle ?: @"";
    _subtitleField.hidden = subtitle.length == 0;
}

- (void)setSubtitleAction:(nullable void (^)(void))subtitleAction
{
    _subtitleAction = [subtitleAction copy];
    _subtitleField.linkAction = _subtitleAction;
    [self.window invalidateCursorRectsForView:_subtitleField];
}

- (void)setDetail:(nullable NSString *)detail
{
    _detail = [detail copy];
    _detailField.stringValue = detail ?: @"";
    _detailField.hidden = detail.length == 0;
}

+ (void)configureButton:(NSButton *)button title:(nullable NSString *)title symbolName:(nullable NSString *)symbolName
{
    button.hidden = title.length == 0;
    button.title = title ?: @"";
    button.image = symbolName != nil ? [NSImage imageWithSystemSymbolName:symbolName accessibilityDescription:nil] : nil;
}

- (void)setPrimaryActionTitle:(nullable NSString *)title
                   symbolName:(nullable NSString *)symbolName
                       action:(nullable void (^)(void))action
{
    [MacLCDetailHeaderView configureButton:_primaryButton title:title symbolName:symbolName];
    _primaryAction = [action copy];
}

- (void)setSecondaryActionTitle:(nullable NSString *)title
                     symbolName:(nullable NSString *)symbolName
                         action:(nullable void (^)(void))action
{
    [MacLCDetailHeaderView configureButton:_secondaryButton title:title symbolName:symbolName];
    _secondaryAction = [action copy];
}

- (void)setMoreMenu:(nullable NSMenu *)moreMenu
{
    _moreMenu = moreMenu;
    _moreButton.hidden = moreMenu == nil;
    if (moreMenu == nil) {
        return;
    }
    /* A pull-down shows its first item as the button: an image-only title
     * item, then the actions. */
    NSMenu * const menu = [[NSMenu alloc] initWithTitle:@""];
    NSMenuItem * const titleItem = [[NSMenuItem alloc] initWithTitle:@"" action:nil keyEquivalent:@""];
    titleItem.image = [NSImage imageWithSystemSymbolName:@"ellipsis" accessibilityDescription:_NS("More")];
    [menu addItem:titleItem];
    for (NSMenuItem * const item in moreMenu.itemArray.copy) {
        [moreMenu removeItem:item];
        [menu addItem:item];
    }
    _moreButton.menu = menu;
}

- (void)primaryPressed:(id)sender
{
    if (_primaryAction != nil) {
        _primaryAction();
    }
}

- (void)secondaryPressed:(id)sender
{
    if (_secondaryAction != nil) {
        _secondaryAction();
    }
}

@end
