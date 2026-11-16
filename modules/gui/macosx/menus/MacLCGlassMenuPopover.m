/*****************************************************************************
 * MacLCGlassMenuPopover.m: MacOS X interface module
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

#import "MacLCGlassMenuPopover.h"

#import "extensions/NSString+Helpers.h"
#import "theme/MacLCDesign.h"

static const CGFloat kPopoverWidth = 290.0;
static const CGFloat kRowHeight = 28.0;
static const CGFloat kIndent = 14.0;
static const CGFloat kMaximumHeight = 520.0;

static NSPopover *gPopover;
static __weak NSView *gAnchor;

/* "⌥⌘S", the way a menu shows an item's shortcut; empty when there is none
 * or the key has no printable glyph. */
static NSString *MacLCShortcutText(NSMenuItem *item)
{
    NSString *key = item.keyEquivalent;
    if (key.length == 0)
        return @"";
    switch ([key characterAtIndex:0]) {
        case NSUpArrowFunctionKey: key = @"↑"; break;
        case NSDownArrowFunctionKey: key = @"↓"; break;
        case NSLeftArrowFunctionKey: key = @"←"; break;
        case NSRightArrowFunctionKey: key = @"→"; break;
        case ' ': key = _NS("Space"); break;
        case '\r': key = @"↩"; break;
        default:
            if ([key characterAtIndex:0] >= 0xF700)
                return @"";
            break;
    }
    const NSEventModifierFlags flags = item.keyEquivalentModifierMask;
    NSMutableString * const text = [NSMutableString string];
    if (flags & NSEventModifierFlagControl) [text appendString:@"⌃"];
    if (flags & NSEventModifierFlagOption) [text appendString:@"⌥"];
    if ((flags & NSEventModifierFlagShift) || ![key isEqualToString:key.lowercaseString])
        [text appendString:@"⇧"];
    if (flags & NSEventModifierFlagCommand) [text appendString:@"⌘"];
    [text appendString:key.uppercaseString];
    return text;
}

#pragma mark - Row

/* One menu line: symbol, title, shortcut and a trailing mark (check mark,
 * dash for mixed, chevron for a submenu). Highlights under the pointer and
 * answers Space and Return like a button. */
@interface MacLCGlassMenuRow : NSView
@property (nonatomic, copy) void (^handler)(void);
@property (nonatomic) BOOL enabled;
@end

@implementation MacLCGlassMenuRow
{
    BOOL _hovered;
    NSString *_title;
    NSString *_value;
}

- (instancetype)initWithTitle:(NSString *)title
                        image:(nullable NSImage *)image
                     shortcut:(NSString *)shortcut
                    markImage:(nullable NSImage *)mark
                       indent:(CGFloat)indent
                      enabled:(BOOL)enabled
                        value:(nullable NSString *)value
{
    self = [super initWithFrame:NSMakeRect(0, 0, kPopoverWidth, kRowHeight)];
    if (self == nil)
        return nil;
    _title = [title copy];
    _value = [value copy];
    _enabled = enabled;
    self.wantsLayer = YES;
    self.layer.cornerRadius = MacLCDesign.cornerRadiusSmall;
    self.translatesAutoresizingMaskIntoConstraints = NO;

    NSColor * const textColor = enabled ? NSColor.labelColor : NSColor.tertiaryLabelColor;

    NSImageView * const icon = [NSImageView imageViewWithImage:image ?: [[NSImage alloc] initWithSize:NSMakeSize(16, 16)]];
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    icon.symbolConfiguration = [NSImageSymbolConfiguration configurationWithPointSize:14.0 weight:NSFontWeightRegular];
    icon.contentTintColor = enabled ? NSColor.secondaryLabelColor : NSColor.tertiaryLabelColor;
    icon.hidden = (image == nil);

    NSTextField * const label = [NSTextField labelWithString:title];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.font = MacLCDesign.body;
    label.textColor = textColor;
    label.lineBreakMode = NSLineBreakByTruncatingTail;
    [label setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
                                    forOrientation:NSLayoutConstraintOrientationHorizontal];

    NSTextField * const keys = [NSTextField labelWithString:shortcut];
    keys.translatesAutoresizingMaskIntoConstraints = NO;
    keys.font = MacLCDesign.callout;
    keys.textColor = NSColor.tertiaryLabelColor;

    NSImageView * const markView = [NSImageView imageViewWithImage:mark ?: [[NSImage alloc] initWithSize:NSMakeSize(12, 12)]];
    markView.translatesAutoresizingMaskIntoConstraints = NO;
    markView.symbolConfiguration = [NSImageSymbolConfiguration configurationWithPointSize:12.0 weight:NSFontWeightSemibold];
    markView.contentTintColor = enabled ? NSColor.controlAccentColor : NSColor.tertiaryLabelColor;
    markView.hidden = (mark == nil);

    for (NSView * const v in @[icon, label, keys, markView])
        [self addSubview:v];
    [NSLayoutConstraint activateConstraints:@[
        [self.heightAnchor constraintEqualToConstant:kRowHeight],
        [icon.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:8.0 + indent],
        [icon.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [icon.widthAnchor constraintEqualToConstant:18.0],
        [label.leadingAnchor constraintEqualToAnchor:icon.trailingAnchor constant:8.0],
        [label.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [keys.leadingAnchor constraintGreaterThanOrEqualToAnchor:label.trailingAnchor constant:8.0],
        [keys.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [markView.leadingAnchor constraintEqualToAnchor:keys.trailingAnchor constant:6.0],
        [markView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-8.0],
        [markView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [markView.widthAnchor constraintEqualToConstant:14.0],
    ]];
    return self;
}

- (void)updateTrackingAreas
{
    [super updateTrackingAreas];
    for (NSTrackingArea * const area in self.trackingAreas)
        [self removeTrackingArea:area];
    [self addTrackingArea:[[NSTrackingArea alloc] initWithRect:NSZeroRect
                                                       options:NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways | NSTrackingInVisibleRect
                                                         owner:self
                                                      userInfo:nil]];
}

- (void)setHovered:(BOOL)hovered
{
    _hovered = hovered && _enabled;
    self.layer.backgroundColor = _hovered
        ? [NSColor.labelColor colorWithAlphaComponent:0.10].CGColor
        : NSColor.clearColor.CGColor;
}

- (void)mouseEntered:(NSEvent *)event { [self setHovered:YES]; }
- (void)mouseExited:(NSEvent *)event { [self setHovered:NO]; }
- (void)mouseDown:(NSEvent *)event { }

- (void)mouseUp:(NSEvent *)event
{
    const NSPoint p = [self convertPoint:event.locationInWindow fromView:nil];
    if (_enabled && NSPointInRect(p, self.bounds) && _handler)
        _handler();
}

- (BOOL)acceptsFirstResponder { return _enabled; }
- (BOOL)canBecomeKeyView { return _enabled; }

- (void)keyDown:(NSEvent *)event
{
    const unichar c = event.charactersIgnoringModifiers.length > 0 ? [event.charactersIgnoringModifiers characterAtIndex:0] : 0;
    if ((c == ' ' || c == '\r' || c == NSEnterCharacter) && _enabled && _handler)
        _handler();
    else
        [super keyDown:event];
}

- (NSRect)focusRingMaskBounds { return self.bounds; }

- (void)drawFocusRingMask
{
    [[NSBezierPath bezierPathWithRoundedRect:self.bounds
                                     xRadius:MacLCDesign.cornerRadiusSmall
                                     yRadius:MacLCDesign.cornerRadiusSmall] fill];
}

- (BOOL)isAccessibilityElement { return YES; }
- (NSAccessibilityRole)accessibilityRole { return NSAccessibilityButtonRole; }
- (NSString *)accessibilityLabel { return _title; }
- (id)accessibilityValue { return _value; }
- (BOOL)isAccessibilityEnabled { return _enabled; }

- (BOOL)accessibilityPerformPress
{
    if (!_enabled || !_handler)
        return NO;
    _handler();
    return YES;
}

@end

#pragma mark - Popover

@interface MacLCGlassMenuFlippedView : NSView
@end

@implementation MacLCGlassMenuFlippedView
- (BOOL)isFlipped { return YES; }
@end

@implementation MacLCGlassMenuPopover
{
    NSMenu *_menu;
    __weak NSView *_anchor;
    NSStackView *_stack;
    NSMutableSet<NSMenu *> *_expanded;
    NSLayoutConstraint *_heightConstraint;
}

+ (void)showMenu:(NSMenu *)menu relativeToView:(NSView *)view
{
    if (gPopover.isShown && gAnchor == view) {
        [gPopover performClose:nil];
        return;
    }
    [gPopover close];

    MacLCGlassMenuPopover * const controller = [[MacLCGlassMenuPopover alloc] init];
    controller->_menu = menu;
    controller->_anchor = view;

    NSPopover * const popover = [[NSPopover alloc] init];
    popover.behavior = NSPopoverBehaviorTransient;
    popover.animates = !MacLCDesign.reducedMotion;
    popover.appearance = view.effectiveAppearance;
    popover.contentViewController = controller;
    gPopover = popover;
    gAnchor = view;
    [popover showRelativeToRect:view.bounds ofView:view preferredEdge:NSRectEdgeMaxY];
}

- (void)loadView
{
    _expanded = [NSMutableSet set];

    _stack = [[NSStackView alloc] init];
    _stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    _stack.alignment = NSLayoutAttributeLeading;
    _stack.spacing = 0.0;
    _stack.edgeInsets = NSEdgeInsetsMake(6.0, 6.0, 6.0, 6.0);
    _stack.translatesAutoresizingMaskIntoConstraints = NO;

    NSView * const document = [[MacLCGlassMenuFlippedView alloc] init];
    document.translatesAutoresizingMaskIntoConstraints = NO;
    [document addSubview:_stack];

    NSScrollView * const scroll = [[NSScrollView alloc] init];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    scroll.drawsBackground = NO;
    scroll.hasVerticalScroller = YES;
    scroll.autohidesScrollers = YES;
    scroll.borderType = NSNoBorder;
    scroll.documentView = document;

    NSView * const root = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, kPopoverWidth + 12.0, 200)];
    [root addSubview:scroll];
    _heightConstraint = [root.heightAnchor constraintEqualToConstant:200.0];
    [NSLayoutConstraint activateConstraints:@[
        [root.widthAnchor constraintEqualToConstant:kPopoverWidth + 12.0],
        _heightConstraint,
        [scroll.leadingAnchor constraintEqualToAnchor:root.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:root.trailingAnchor],
        [scroll.topAnchor constraintEqualToAnchor:root.topAnchor],
        [scroll.bottomAnchor constraintEqualToAnchor:root.bottomAnchor],
        [document.leadingAnchor constraintEqualToAnchor:scroll.contentView.leadingAnchor],
        [document.trailingAnchor constraintEqualToAnchor:scroll.contentView.trailingAnchor],
        [document.topAnchor constraintEqualToAnchor:scroll.contentView.topAnchor],
        [_stack.leadingAnchor constraintEqualToAnchor:document.leadingAnchor],
        [_stack.trailingAnchor constraintEqualToAnchor:document.trailingAnchor],
        [_stack.topAnchor constraintEqualToAnchor:document.topAnchor],
        [_stack.bottomAnchor constraintEqualToAnchor:document.bottomAnchor],
    ]];
    self.view = root;
    [self rebuild];
}

/* Dynamic menus fill themselves when they open: ask them now, then let
 * autoenabling validate every item. */
static void MacLCPrepareMenu(NSMenu *menu)
{
    if ([menu.delegate respondsToSelector:@selector(menuNeedsUpdate:)])
        [menu.delegate menuNeedsUpdate:menu];
    [menu update];
}

- (void)rebuild
{
    for (NSView * const view in _stack.arrangedSubviews.copy) {
        [_stack removeArrangedSubview:view];
        [view removeFromSuperview];
    }
    MacLCPrepareMenu(_menu);
    [self addItemsOfMenu:_menu indent:0.0];

    [self addSeparator];
    __weak typeof(self) weakSelf = self;
    MacLCGlassMenuRow * const all =
        [[MacLCGlassMenuRow alloc] initWithTitle:_NS("All Options…")
                                           image:[NSImage imageWithSystemSymbolName:@"list.bullet" accessibilityDescription:nil]
                                        shortcut:@""
                                       markImage:nil
                                          indent:0.0
                                         enabled:YES
                                           value:nil];
    all.handler = ^{ [weakSelf showClassicMenu]; };
    [self addRow:all];

    [_stack layoutSubtreeIfNeeded];
    const CGFloat height = _stack.fittingSize.height;
    _heightConstraint.constant = MIN(height, kMaximumHeight);
    self.preferredContentSize = NSMakeSize(kPopoverWidth + 12.0, _heightConstraint.constant);
}

- (void)addRow:(NSView *)row
{
    [_stack addArrangedSubview:row];
    [row.widthAnchor constraintEqualToConstant:kPopoverWidth].active = YES;
}

- (void)addSeparator
{
    NSView * const last = _stack.arrangedSubviews.lastObject;
    if (last == nil || [last isKindOfClass:NSBox.class])
        return;
    NSBox * const line = [[NSBox alloc] init];
    line.boxType = NSBoxSeparator;
    line.translatesAutoresizingMaskIntoConstraints = NO;
    [_stack addArrangedSubview:line];
    [line.widthAnchor constraintEqualToConstant:kPopoverWidth - 16.0].active = YES;
    [_stack setCustomSpacing:5.0 afterView:_stack.arrangedSubviews[_stack.arrangedSubviews.count - 2]];
    [_stack setCustomSpacing:5.0 afterView:line];
}

- (void)addItemsOfMenu:(NSMenu *)menu indent:(CGFloat)indent
{
    __weak typeof(self) weakSelf = self;
    for (NSMenuItem * const item in menu.itemArray) {
        if (item.isHidden || item.isAlternate)
            continue;
        if (item.isSeparatorItem) {
            [self addSeparator];
            continue;
        }
        if (item.view != nil)
            continue; // custom controls: reached through All Options…
        if (item.isSectionHeader) {
            NSTextField * const header = [NSTextField labelWithString:item.title];
            header.font = [NSFont systemFontOfSize:MacLCDesign.footnote.pointSize weight:NSFontWeightSemibold];
            header.textColor = NSColor.secondaryLabelColor;
            NSView * const box = [[NSView alloc] init];
            box.translatesAutoresizingMaskIntoConstraints = NO;
            header.translatesAutoresizingMaskIntoConstraints = NO;
            [box addSubview:header];
            [NSLayoutConstraint activateConstraints:@[
                [box.heightAnchor constraintEqualToConstant:22.0],
                [header.leadingAnchor constraintEqualToAnchor:box.leadingAnchor constant:10.0 + indent],
                [header.bottomAnchor constraintEqualToAnchor:box.bottomAnchor constant:-3.0],
            ]];
            [self addRow:box];
            continue;
        }

        NSMenu * const submenu = item.submenu;
        const BOOL expanded = submenu != nil && [_expanded containsObject:submenu];
        NSImage *mark = nil;
        NSString *value = nil;
        if (submenu != nil) {
            mark = [NSImage imageWithSystemSymbolName:expanded ? @"chevron.down" : @"chevron.right"
                             accessibilityDescription:nil];
            value = expanded ? _NS("Expanded") : _NS("Collapsed");
        } else if (item.state == NSControlStateValueOn) {
            mark = [NSImage imageWithSystemSymbolName:@"checkmark" accessibilityDescription:nil];
            value = _NS("Selected");
        } else if (item.state == NSControlStateValueMixed) {
            mark = [NSImage imageWithSystemSymbolName:@"minus" accessibilityDescription:nil];
        }

        MacLCGlassMenuRow * const row =
            [[MacLCGlassMenuRow alloc] initWithTitle:item.title
                                               image:item.image
                                            shortcut:submenu ? @"" : MacLCShortcutText(item)
                                           markImage:mark
                                              indent:indent
                                             enabled:item.isEnabled
                                               value:value];
        if (submenu != nil) {
            row.handler = ^{ [weakSelf toggleSubmenu:submenu]; };
        } else {
            NSMenuItem * __weak weakItem = item;
            row.handler = ^{ [weakSelf performItem:weakItem]; };
        }
        [self addRow:row];

        if (expanded) {
            MacLCPrepareMenu(submenu);
            [self addItemsOfMenu:submenu indent:indent + kIndent];
        }
    }
}

- (void)toggleSubmenu:(NSMenu *)submenu
{
    if ([_expanded containsObject:submenu])
        [_expanded removeObject:submenu];
    else
        [_expanded addObject:submenu];
    [self rebuild];
}

- (void)performItem:(NSMenuItem *)item
{
    NSMenu * const menu = item.menu;
    const NSInteger index = menu != nil ? [menu indexOfItem:item] : -1;
    [gPopover performClose:nil];
    if (index < 0)
        return;
    /* After the popover is gone, so the action reaches the window's
     * responder chain the way a menu choice would. */
    dispatch_async(dispatch_get_main_queue(), ^{
        [menu performActionForItemAtIndex:index];
    });
}

- (void)showClassicMenu
{
    NSMenu * const menu = _menu;
    NSView * const anchor = _anchor;
    [gPopover performClose:nil];
    if (anchor == nil)
        return;
    dispatch_async(dispatch_get_main_queue(), ^{
        [menu popUpMenuPositioningItem:nil
                            atLocation:NSMakePoint(0.0, NSHeight(anchor.bounds))
                                inView:anchor];
    });
}

@end
