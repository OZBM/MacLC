/*****************************************************************************
 * MacLCSoundPanelViewController.m
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

#import "MacLCSoundPanelViewController.h"

#import "MacLCEqualizerBandsView.h"
#import "MacLCSoundMode.h"
#import "sound/MacLCSoundPresets.h"
#import "theme/MacLCDesign.h"

#import "extensions/NSString+Helpers.h"

static const CGFloat kPanelWidth = 340.0;
static const CGFloat kTileWidth = 96.0;
static const CGFloat kTileHeight = 64.0;
static NSString * const kMacLCSoundPanelShowsEqualizerKey = @"MacLCSoundPanelShowsEqualizer";

#pragma mark - MacLCSoundModeTileControl

@interface MacLCSoundModeTileControl : NSControl
@property (nonatomic, readonly) MacLCSoundPreset *preset;
@property (nonatomic, getter=isSelected) BOOL selected;
@property (nonatomic, getter=isHovered) BOOL hovered;
- (instancetype)initWithPreset:(MacLCSoundPreset *)preset;
- (void)updateAppearance;
@end

@implementation MacLCSoundModeTileControl
{
    NSImageView *_imageView;
    NSTextField *_titleLabel;
    NSTrackingArea *_trackingArea;
}

- (instancetype)initWithPreset:(MacLCSoundPreset *)preset
{
    self = [super initWithFrame:NSMakeRect(0, 0, kTileWidth, kTileHeight)];
    if (self) {
        _preset = preset;
        [self setupUI];
        [self updateAppearance];
    }
    return self;
}

- (void)setupUI
{
    self.translatesAutoresizingMaskIntoConstraints = NO;
    self.wantsLayer = YES;
    self.layer.cornerRadius = MacLCDesign.cornerRadiusMedium;
    self.layer.masksToBounds = YES;
    self.focusRingType = NSFocusRingTypeExterior;

    _imageView = [[NSImageView alloc] init];
    _imageView.translatesAutoresizingMaskIntoConstraints = NO;
    _imageView.imageScaling = NSImageScaleProportionallyDown;

    if (@available(macOS 11.0, *)) {
        NSImageSymbolConfiguration *config =
            [NSImageSymbolConfiguration configurationWithPointSize:20.0 weight:NSFontWeightMedium];
        NSImage *symbol = [NSImage imageWithSystemSymbolName:_preset.symbolName
                                    accessibilityDescription:nil];
        if (symbol) {
            _imageView.image = [symbol imageWithSymbolConfiguration:config];
        }
    }

    _titleLabel = [NSTextField labelWithString:_preset.title];
    _titleLabel.alignment = NSTextAlignmentCenter;
    _titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _titleLabel.toolTip = _preset.title;

    [self addSubview:_imageView];
    [self addSubview:_titleLabel];

    [NSLayoutConstraint activateConstraints:@[
        [self.widthAnchor constraintEqualToConstant:kTileWidth],
        [self.heightAnchor constraintEqualToConstant:kTileHeight],

        [_imageView.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        [_imageView.topAnchor constraintEqualToAnchor:self.topAnchor constant:10.0],
        [_imageView.widthAnchor constraintEqualToConstant:24.0],
        [_imageView.heightAnchor constraintEqualToConstant:24.0],

        [_titleLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:4.0],
        [_titleLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-4.0],
        [_titleLabel.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-8.0],
    ]];
}

- (void)updateAppearance
{
    const BOOL isSel = self.isSelected;
    const BOOL isHov = self.isHovered;
    const BOOL incContrast = NSWorkspace.sharedWorkspace.accessibilityDisplayShouldIncreaseContrast;

    if (isSel) {
        self.layer.backgroundColor = [MacLCDesign.accent colorWithAlphaComponent:0.20].CGColor;
        _imageView.contentTintColor = MacLCDesign.accent;
        _titleLabel.textColor = MacLCDesign.accent;
        _titleLabel.font = [NSFont systemFontOfSize:11.0 weight:NSFontWeightSemibold];
        if (incContrast) {
            self.layer.borderWidth = 1.0;
            self.layer.borderColor = MacLCDesign.accent.CGColor;
        } else {
            self.layer.borderWidth = 0.0;
        }
    } else {
        if (isHov) {
            self.layer.backgroundColor = NSColor.tertiarySystemFillColor.CGColor;
        } else {
            self.layer.backgroundColor = NSColor.quaternarySystemFillColor.CGColor;
        }
        _imageView.contentTintColor = MacLCDesign.secondaryLabel;
        _titleLabel.textColor = MacLCDesign.primaryLabel;
        _titleLabel.font = [NSFont systemFontOfSize:11.0 weight:NSFontWeightRegular];
        self.layer.borderWidth = 0.0;
    }
}

- (void)updateTrackingAreas
{
    [super updateTrackingAreas];
    if (_trackingArea != nil) {
        [self removeTrackingArea:_trackingArea];
    }
    _trackingArea = [[NSTrackingArea alloc] initWithRect:self.bounds
                                                 options:(NSTrackingMouseEnteredAndExited |
                                                          NSTrackingActiveInActiveApp |
                                                          NSTrackingInVisibleRect)
                                                   owner:self
                                                userInfo:nil];
    [self addTrackingArea:_trackingArea];
}

- (void)mouseEntered:(NSEvent *)event
{
    self.hovered = YES;
    [self updateAppearance];
}

- (void)mouseExited:(NSEvent *)event
{
    self.hovered = NO;
    [self updateAppearance];
}

- (void)mouseDown:(NSEvent *)event
{
    if (!self.isEnabled) {
        return;
    }
    [self.window makeFirstResponder:self];
    [self sendAction:self.action to:self.target];
}

- (BOOL)acceptsFirstResponder
{
    return YES;
}

- (BOOL)needsPanelToBecomeKey
{
    return YES;
}

- (void)keyDown:(NSEvent *)event
{
    NSString *chars = event.charactersIgnoringModifiers;
    if (chars.length > 0) {
        unichar c = [chars characterAtIndex:0];
        if (c == ' ' || c == '\r' || c == 3) {
            [self sendAction:self.action to:self.target];
            return;
        }
    }
    [super keyDown:event];
}

- (void)drawFocusRingMask
{
    NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:self.bounds
                                                        xRadius:MacLCDesign.cornerRadiusMedium
                                                        yRadius:MacLCDesign.cornerRadiusMedium];
    [path fill];
}

- (NSRect)focusRingMaskBounds
{
    return self.bounds;
}

#pragma mark - Accessibility

- (BOOL)isAccessibilityElement
{
    return YES;
}

- (NSAccessibilityRole)accessibilityRole
{
    return NSAccessibilityRadioButtonRole;
}

- (id)accessibilityValue
{
    return @(self.isSelected);
}

- (NSString *)accessibilityLabel
{
    return self.preset.title;
}

- (NSString *)accessibilityHelp
{
    return self.preset.presetDescription;
}

@end

#pragma mark - MacLCSoundPanelViewController

@interface MacLCSoundPanelViewController () <NSPopoverDelegate>
@end

@implementation MacLCSoundPanelViewController
{
    NSTextField *_titleLabel;
    NSSwitch *_masterSwitch;
    NSTextField *_statusLabel;

    NSView *_tilesContainer;
    NSMutableArray<MacLCSoundModeTileControl *> *_tiles;

    NSStackView *_intensityRow;
    NSTextField *_intensityLabel;
    NSSlider *_intensitySlider;

    NSTextField *_descriptionLabel;

    NSButton *_disclosureButton;
    MacLCEqualizerBandsView *_equalizerBandsView;

    BOOL _showsEqualizer;
}

static NSPopover *gPopover = nil;
static __weak NSView *gAnchor = nil;
static NSPanel *gSoundPanel = nil;
static NSHashTable<NSView *> *gAnchors = nil;

+ (void)registerAnchorView:(NSView *)view
{
    if (gAnchors == nil)
        gAnchors = [NSHashTable weakObjectsHashTable];
    [gAnchors addObject:view];
}

+ (void)showFromMenu
{
    /* Prefer the Sound button of the window in front, like a click on it would. */
    NSView *best = nil;
    for (NSView * const view in gAnchors) {
        NSWindow * const window = view.window;
        if (window == nil || !window.isVisible || view.isHiddenOrHasHiddenAncestor)
            continue;
        if (best == nil || window.isKeyWindow || (window.isMainWindow && !best.window.isKeyWindow))
            best = view;
    }
    if (best != nil) {
        if (!(gPopover.isShown && gAnchor == best))
            [self showRelativeToView:best preferredEdge:NSRectEdgeMaxY];
        return;
    }
    [self showPanel];
}

+ (void)showRelativeToView:(NSView *)view preferredEdge:(NSRectEdge)edge
{
    if (gPopover.isShown && gAnchor == view) {
        [gPopover performClose:nil];
        return;
    }
    [gPopover close];

    NSPopover * const popover = [[NSPopover alloc] init];
    popover.behavior = NSPopoverBehaviorTransient;
    popover.animates = !MacLCDesign.reducedMotion;
    MacLCSoundPanelViewController * const vc = [[MacLCSoundPanelViewController alloc] init];
    popover.contentViewController = vc;
    popover.delegate = vc;
    gPopover = popover;
    gAnchor = view;
    [popover showRelativeToRect:view.bounds ofView:view preferredEdge:edge];
}

+ (void)showPanel
{
    if (gPopover.isShown) {
        [gPopover close];
    }

    if (gSoundPanel == nil) {
        NSPanel *panel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, kPanelWidth, 400)
                                                    styleMask:(NSWindowStyleMaskTitled |
                                                               NSWindowStyleMaskClosable |
                                                               NSWindowStyleMaskUtilityWindow)
                                                      backing:NSBackingStoreBuffered
                                                        defer:YES];
        panel.title = _NS("Sound");
        [panel setFrameAutosaveName:@"MacLCSoundPanel"];
        panel.releasedWhenClosed = NO;
        MacLCSoundPanelViewController *vc = [[MacLCSoundPanelViewController alloc] init];
        panel.contentViewController = vc;
        gSoundPanel = panel;
    }

    [gSoundPanel makeKeyAndOrderFront:nil];
}

- (void)loadView
{
    const CGFloat padding = MacLCDesign.windowContentMargin; // 20 pt
    const CGFloat innerWidth = kPanelWidth - 2 * padding;    // 300 pt

    NSView * const root = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, kPanelWidth, 450)];
    root.translatesAutoresizingMaskIntoConstraints = NO;

    // 1. Header row
    _titleLabel = [NSTextField labelWithString:_NS("Sound")];
    _titleLabel.font = [NSFont systemFontOfSize:MacLCDesign.title3.pointSize weight:NSFontWeightSemibold];
    _titleLabel.textColor = MacLCDesign.primaryLabel;

    _masterSwitch = [[NSSwitch alloc] init];
    _masterSwitch.target = self;
    _masterSwitch.action = @selector(masterSwitchChanged:);
    _masterSwitch.accessibilityLabel = _NS("Sound Enhancements");
    _masterSwitch.translatesAutoresizingMaskIntoConstraints = NO;

    NSView *headerSpacer = [[NSView alloc] initWithFrame:NSZeroRect];
    [headerSpacer setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];

    NSStackView *headerRow = [NSStackView stackViewWithViews:@[_titleLabel, headerSpacer, _masterSwitch]];
    headerRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    headerRow.alignment = NSLayoutAttributeCenterY;
    headerRow.translatesAutoresizingMaskIntoConstraints = NO;

    _statusLabel = [NSTextField labelWithString:@""];
    _statusLabel.font = MacLCDesign.footnote;
    _statusLabel.textColor = MacLCDesign.secondaryLabel;
    _statusLabel.translatesAutoresizingMaskIntoConstraints = NO;

    // 2. Mode tiles container (3x3 grid)
    _tiles = [NSMutableArray arrayWithCapacity:9];
    NSArray<MacLCSoundPreset *> *presets = MacLCSoundMode.sharedMode.presets;

    NSMutableArray<NSStackView *> *gridRows = [NSMutableArray arrayWithCapacity:3];
    for (NSUInteger r = 0; r < 3; r++) {
        NSMutableArray<NSView *> *rowTiles = [NSMutableArray arrayWithCapacity:3];
        for (NSUInteger c = 0; c < 3; c++) {
            NSUInteger idx = r * 3 + c;
            if (idx < presets.count) {
                MacLCSoundModeTileControl *tile = [[MacLCSoundModeTileControl alloc] initWithPreset:presets[idx]];
                tile.target = self;
                tile.action = @selector(tileClicked:);
                [_tiles addObject:tile];
                [rowTiles addObject:tile];
            }
        }
        NSStackView *rowStack = [NSStackView stackViewWithViews:rowTiles];
        rowStack.orientation = NSUserInterfaceLayoutOrientationHorizontal;
        rowStack.spacing = 6.0;
        rowStack.alignment = NSLayoutAttributeCenterY;
        rowStack.translatesAutoresizingMaskIntoConstraints = NO;
        [gridRows addObject:rowStack];
    }

    NSStackView *tilesStack = [NSStackView stackViewWithViews:gridRows];
    tilesStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    tilesStack.spacing = MacLCDesign.spacingS;
    tilesStack.alignment = NSLayoutAttributeLeading;
    tilesStack.translatesAutoresizingMaskIntoConstraints = NO;
    tilesStack.accessibilityRole = NSAccessibilityRadioGroupRole;
    tilesStack.accessibilityLabel = _NS("Sound Mode");
    _tilesContainer = tilesStack;

    // 3. Intensity row
    _intensityLabel = [NSTextField labelWithString:_NS("Intensity:")];
    _intensityLabel.font = MacLCDesign.body;
    _intensityLabel.textColor = MacLCDesign.primaryLabel;

    NSImageView *speakerLow = [[NSImageView alloc] init];
    speakerLow.translatesAutoresizingMaskIntoConstraints = NO;
    speakerLow.accessibilityElement = NO; // decorative
    speakerLow.image = [MacLCDesign symbolNamed:@"speaker.wave.1" pointSize:12. weight:NSFontWeightRegular accessibilityLabel:nil];
    speakerLow.contentTintColor = MacLCDesign.secondaryLabel;

    _intensitySlider = [[NSSlider alloc] init];
    _intensitySlider.minValue = 0.0;
    _intensitySlider.maxValue = 100.0;
    _intensitySlider.continuous = YES;
    _intensitySlider.target = self;
    _intensitySlider.action = @selector(intensitySliderChanged:);
    _intensitySlider.accessibilityLabel = _NS("Intensity");
    _intensitySlider.translatesAutoresizingMaskIntoConstraints = NO;

    NSImageView *speakerHigh = [[NSImageView alloc] init];
    speakerHigh.translatesAutoresizingMaskIntoConstraints = NO;
    speakerHigh.accessibilityElement = NO; // decorative
    speakerHigh.image = [MacLCDesign symbolNamed:@"speaker.wave.3" pointSize:12. weight:NSFontWeightRegular accessibilityLabel:nil];
    speakerHigh.contentTintColor = MacLCDesign.secondaryLabel;

    _intensityRow = [NSStackView stackViewWithViews:@[_intensityLabel, speakerLow, _intensitySlider, speakerHigh]];
    _intensityRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    _intensityRow.alignment = NSLayoutAttributeCenterY;
    _intensityRow.spacing = MacLCDesign.spacingS;
    _intensityRow.translatesAutoresizingMaskIntoConstraints = NO;
    /* Symbols keep their own (wider than tall) size: a square box clipped them. */
    for (NSImageView * const icon in @[speakerLow, speakerHigh]) {
        [icon setContentHuggingPriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
        [icon setContentCompressionResistancePriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
    }

    // 4. Description label
    _descriptionLabel = [NSTextField wrappingLabelWithString:@""];
    _descriptionLabel.font = MacLCDesign.callout;
    _descriptionLabel.textColor = MacLCDesign.secondaryLabel;
    _descriptionLabel.maximumNumberOfLines = 2;
    _descriptionLabel.lineBreakMode = NSLineBreakByWordWrapping;
    _descriptionLabel.translatesAutoresizingMaskIntoConstraints = NO;

    // 5. Disclosure row for Equalizer
    _showsEqualizer = [[NSUserDefaults standardUserDefaults] boolForKey:kMacLCSoundPanelShowsEqualizerKey];

    _disclosureButton = [[NSButton alloc] initWithFrame:NSZeroRect];
    _disclosureButton.bordered = NO;
    _disclosureButton.target = self;
    _disclosureButton.action = @selector(toggleEqualizer:);
    _disclosureButton.imagePosition = NSImageLeading;
    _disclosureButton.alignment = NSTextAlignmentLeft;
    _disclosureButton.font = [NSFont systemFontOfSize:MacLCDesign.subheadline.pointSize weight:NSFontWeightSemibold];
    _disclosureButton.contentTintColor = MacLCDesign.primaryLabel;
    _disclosureButton.title = _NS("Equalizer");
    _disclosureButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self updateDisclosureImage];

    // 6. 10-band equalizer editor view
    _equalizerBandsView = [[MacLCEqualizerBandsView alloc] initWithFrame:NSZeroRect];
    _equalizerBandsView.hidden = !_showsEqualizer;

    // Separator line
    NSBox *separator = [[NSBox alloc] init];
    separator.boxType = NSBoxSeparator;
    separator.translatesAutoresizingMaskIntoConstraints = NO;

    // Main vertical stack
    NSStackView *mainStack = [NSStackView stackViewWithViews:@[
        headerRow,
        _statusLabel,
        _tilesContainer,
        _intensityRow,
        _descriptionLabel,
        separator,
        _disclosureButton,
        _equalizerBandsView,
    ]];
    mainStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    mainStack.alignment = NSLayoutAttributeLeading;
    mainStack.spacing = MacLCDesign.spacingS;
    mainStack.translatesAutoresizingMaskIntoConstraints = NO;

    [mainStack setCustomSpacing:MacLCDesign.spacingXXS afterView:headerRow];
    [mainStack setCustomSpacing:MacLCDesign.spacingM afterView:_statusLabel];
    [mainStack setCustomSpacing:MacLCDesign.spacingM afterView:_tilesContainer];
    [mainStack setCustomSpacing:MacLCDesign.spacingS afterView:_intensityRow];
    [mainStack setCustomSpacing:MacLCDesign.spacingM afterView:_descriptionLabel];
    [mainStack setCustomSpacing:MacLCDesign.spacingS afterView:separator];
    [mainStack setCustomSpacing:MacLCDesign.spacingS afterView:_disclosureButton];

    [root addSubview:mainStack];

    [NSLayoutConstraint activateConstraints:@[
        [root.widthAnchor constraintEqualToConstant:kPanelWidth],
        [mainStack.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:padding],
        [mainStack.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-padding],
        [mainStack.topAnchor constraintEqualToAnchor:root.topAnchor constant:padding],
        [mainStack.bottomAnchor constraintEqualToAnchor:root.bottomAnchor constant:-padding],

        [headerRow.widthAnchor constraintEqualToConstant:innerWidth],
        [_statusLabel.widthAnchor constraintEqualToConstant:innerWidth],
        [_tilesContainer.widthAnchor constraintEqualToConstant:innerWidth],
        [_intensityRow.widthAnchor constraintEqualToConstant:innerWidth],
        [_descriptionLabel.widthAnchor constraintEqualToConstant:innerWidth],
        [separator.widthAnchor constraintEqualToConstant:innerWidth],
        [_disclosureButton.widthAnchor constraintEqualToConstant:innerWidth],
        [_equalizerBandsView.widthAnchor constraintEqualToConstant:innerWidth],
    ]];

    _descriptionLabel.preferredMaxLayoutWidth = innerWidth;

    self.view = root;
}

- (void)updateDisclosureImage
{
    if (@available(macOS 11.0, *)) {
        NSString *symbolName = _showsEqualizer ? @"chevron.down" : @"chevron.right";
        NSString *desc = _showsEqualizer ? _NS("Collapse Equalizer") : _NS("Expand Equalizer");
        _disclosureButton.image = [NSImage imageWithSystemSymbolName:symbolName accessibilityDescription:desc];
    }
    _disclosureButton.toolTip = _showsEqualizer ? _NS("Collapse 10-band equalizer.") : _NS("Expand 10-band equalizer.");
}

- (void)viewWillAppear
{
    [super viewWillAppear];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(soundModeDidChange:)
                                                 name:MacLCSoundModeDidChangeNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(accessibilityDisplayOptionsDidChange:)
                                                 name:NSWorkspaceAccessibilityDisplayOptionsDidChangeNotification
                                               object:nil];
    [self updateUI];
}

- (void)viewDidDisappear
{
    [super viewDidDisappear];
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:MacLCSoundModeDidChangeNotification
                                                  object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:NSWorkspaceAccessibilityDisplayOptionsDidChangeNotification
                                                  object:nil];
}

- (void)soundModeDidChange:(NSNotification *)notification
{
    [self updateUI];
}

- (void)accessibilityDisplayOptionsDidChange:(NSNotification *)notification
{
    [self updateUI];
}

- (void)updateUI
{
    MacLCSoundMode *mode = MacLCSoundMode.sharedMode;
    MacLCSoundPreset *activePreset = [MacLCSoundPresets presetForIdentifier:mode.presetIdentifier];

    // Master switch
    _masterSwitch.state = mode.isEnabled ? NSControlStateValueOn : NSControlStateValueOff;

    // Status label
    if (mode.isEnabled) {
        NSString *title = activePreset ? activePreset.title : _NS("Sound");
        _statusLabel.stringValue = [NSString stringWithFormat:_NS("%@ is on"), title];
    } else {
        _statusLabel.stringValue = _NS("Off");
    }

    // Mode tiles
    for (MacLCSoundModeTileControl *tile in _tiles) {
        /* Off means no mode is active: no tile carries the accent colour. */
        tile.selected = mode.isEnabled && [tile.preset.identifier isEqualToString:mode.presetIdentifier];
        [tile updateAppearance];
    }

    // Intensity slider
    const BOOL isCustom = [mode.presetIdentifier isEqualToString:@"custom"];
    _intensityRow.hidden = isCustom;
    if (!isCustom) {
        float percent = mode.intensity * 100.0f;
        _intensitySlider.floatValue = percent;
        _intensitySlider.toolTip = [NSString stringWithFormat:@"%.0f%%", percent];
        _intensitySlider.accessibilityValue = [NSString stringWithFormat:@"%.0f%%", percent];
    }

    // Description
    _descriptionLabel.stringValue = activePreset ? activePreset.presetDescription : @"";

    // Equalizer bands view
    [_equalizerBandsView updateBands:mode.effectiveBands];

    self.preferredContentSize = self.view.fittingSize;
}

#pragma mark - Actions

- (void)masterSwitchChanged:(NSSwitch *)sender
{
    MacLCSoundMode.sharedMode.enabled = (sender.state == NSControlStateValueOn);
}

- (void)tileClicked:(MacLCSoundModeTileControl *)sender
{
    MacLCSoundMode *mode = MacLCSoundMode.sharedMode;
    mode.presetIdentifier = sender.preset.identifier;
    if (!mode.isEnabled) {
        mode.enabled = YES;
    }
}

- (void)intensitySliderChanged:(NSSlider *)sender
{
    float val = sender.floatValue / 100.0f;
    MacLCSoundMode.sharedMode.intensity = val;
    sender.toolTip = [NSString stringWithFormat:@"%.0f%%", sender.floatValue];
    sender.accessibilityValue = [NSString stringWithFormat:@"%.0f%%", sender.floatValue];
}

- (void)toggleEqualizer:(id)sender
{
    _showsEqualizer = !_showsEqualizer;
    [[NSUserDefaults standardUserDefaults] setBool:_showsEqualizer forKey:kMacLCSoundPanelShowsEqualizerKey];
    [self updateDisclosureImage];
    _equalizerBandsView.hidden = !_showsEqualizer;
    [self animateLayoutChange];
}

- (void)animateLayoutChange
{
    const BOOL animate = !MacLCDesign.reducedMotion;
    NSWindow * const window = self.view.window;
    if (window != nil && window == gSoundPanel) {
        /* Grow or shrink the panel downwards, keeping its title bar in place. */
        NSRect content = [window contentRectForFrameRect:window.frame];
        const NSSize fitting = self.view.fittingSize;
        content.origin.y += NSHeight(content) - fitting.height;
        content.size.height = fitting.height;
        [window setFrame:[window frameRectForContentRect:content] display:YES animate:animate];
        return;
    }
    if (!animate) {
        self.preferredContentSize = self.view.fittingSize;
        return;
    }
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        context.duration = MacLCDesign.motionStandardDuration;
        context.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
        self.preferredContentSize = self.view.fittingSize;
    }];
}

#pragma mark - NSPopoverDelegate

- (BOOL)popoverShouldDetach:(NSPopover *)popover
{
    return YES;
}

- (nullable NSWindow *)detachableWindowForPopover:(NSPopover *)popover
{
    return nil;
}

@end
