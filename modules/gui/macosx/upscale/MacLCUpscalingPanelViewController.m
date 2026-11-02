/*****************************************************************************
 * MacLCUpscalingPanelViewController.m
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

#ifdef HAVE_CONFIG_H
# include "config.h"
#endif

#import "MacLCUpscalingPanelViewController.h"

#import "MacLCUpscaling.h"
#import "coreinteraction/MacLCOSDController.h"
#import "extensions/NSString+Helpers.h"
#import "hdr/MacLCTradeoffMeterView.h"
#import "theme/MacLCDesign.h"

#include "../../../video_output/apple/maclc_upscale_vars.h"

static const CGFloat kPanelWidth = 380.0;
static const CGFloat kPanelPadding = 16.0;

/* One method as the panel shows it. Levels: sharpness, fine detail, true to
 * source, battery; 0..3. */
typedef struct {
    const char *title, *summary, *good, *bad;
    int levels[4];
} MethodCopy;

static MethodCopy Copy(NSInteger method)
{
    switch (method) {
    case MACLC_UPSCALE_APPLE4X: return (MethodCopy){
        N_("Apple Neural 4x"), N_("Apple's largest model, for the most detail"),
        N_("The most detail of all: a large model rebuilds texture from several "
           "frames, for SDR videos up to 1080p."),
        N_("Very heavy: on most Macs it cannot keep up with the frame rate and "
           "falls back to the 2x pass. Needs a one-time model download."),
        {3, 3, 2, 0}};
    case MACLC_UPSCALE_ANIME: return (MethodCopy){
        N_("Anime"), N_("ArtCNN, a network trained on line art"),
        N_("Razor-sharp, clean lines with no halos in cartoons and anime."),
        N_("Smooths skin, film grain and fine texture like watercolor: not for "
           "live action. SDR 8-bit video only."),
        {3, 2, 2, 1}};
    case MACLC_UPSCALE_ANIME4K: return (MethodCopy){
        N_("Anime4K"), N_("Anime4K CNN x2 M, a real-time network for anime"),
        N_("Clean, sharp lines in anime with a lighter network than ArtCNN, so "
           "it keeps up on more Macs."),
        N_("Made for line art: flattens skin, grain and texture in live action. "
           "SDR 8-bit video only."),
        {3, 2, 2, 2}};
    case MACLC_UPSCALE_FSRCNNX: return (MethodCopy){
        N_("FSRCNNX"), N_("A small network for live action; downloaded on request"),
        N_("Restores edges and some texture in films and series without the "
           "drawn look of the anime networks."),
        N_("Not shipped with the app: you accept its LGPL-3.0 licence, then it is "
           "downloaded once. SDR 8-bit video only."),
        {2, 2, 3, 1}};
    case MACLC_UPSCALE_NIS: return (MethodCopy){
        N_("NIS"), N_("NVIDIA Image Scaling, directional with adaptive sharpening"),
        N_("Crisp, directional edges on any video including HDR, at very low "
           "energy cost."),
        N_("Rebuilds no detail, and its sharpening can make noise and bright "
           "HDR highlights stand out."),
        {3, 1, 2, 3}};
    case MACLC_UPSCALE_SHARP: return (MethodCopy){
        N_("Sharp"), N_("AMD FSR 1, edge-adaptive with sharpening"),
        N_("Crisp edges without ringing, on any video including HDR, at almost "
           "no energy cost."),
        N_("Cannot rebuild detail missing from the source, and sharpening makes "
           "compression noise in poor streams more visible."),
        {3, 1, 2, 3}};
    case MACLC_UPSCALE_FAST: return (MethodCopy){
        N_("Efficient"), N_("MetalFX alone"),
        N_("Apple's spatial scaler: clean edges at a fraction of the energy, the "
           "same for SDR and HDR."),
        N_("Softer than the neural methods, and rebuilds no texture."),
        {2, 1, 3, 3}};
    case MACLC_UPSCALE_CLASSIC: return (MethodCopy){
        N_("Classic"), N_("EWA Lanczos, no sharpening"),
        N_("Mathematically faithful scaling that adds nothing to the picture: "
           "what a purist expects."),
        N_("The softest look of all, with slight ringing on hard edges, and no "
           "detail rebuilt."),
        {1, 1, 3, 2}};
    default: return (MethodCopy){
        N_("Auto"), N_("Neural where it helps, MetalFX for the rest"),
        N_("Picks for each video: Apple's neural super resolution for SDR up to "
           "720p, then MetalFX to the window size."),
        N_("The neural pass uses the GPU and Neural Engine; on battery, when hot "
           "or for HDR, it steps down to MetalFX alone."),
        {3, 3, 2, 1}};
    }
}

static NSString * const kSymbols[MACLC_UPSCALE_METHOD_COUNT] = {
    [MACLC_UPSCALE_AUTO] = @"wand.and.stars",
    [MACLC_UPSCALE_APPLE4X] = @"sparkles",
    [MACLC_UPSCALE_ANIME] = @"paintbrush.pointed",
    [MACLC_UPSCALE_ANIME4K] = @"paintbrush",
    [MACLC_UPSCALE_FSRCNNX] = @"film",
    [MACLC_UPSCALE_SHARP] = @"scope",
    [MACLC_UPSCALE_NIS] = @"viewfinder",
    [MACLC_UPSCALE_FAST] = @"leaf",
    [MACLC_UPSCALE_CLASSIC] = @"square.grid.3x3",
};

static NSString * const kShowsDetailsKey = @"MacLCUpscalingPanelShowsDetails";
static const CGFloat kTileHeight = 60.0;
static const CGFloat kTileSpacing = 6.0;

/** A method tile, as in the Sound panel: a symbol over the method's name. */
@interface MacLCUpscaleTile : NSControl
@property (nonatomic) BOOL selected, available;
@property (copy) void (^hover)(BOOL inside);
@end

@implementation MacLCUpscaleTile
{
    NSImageView *_image;
    NSTextField *_title;
    BOOL _hovered;
}

- (instancetype)initWithMethod:(NSInteger)method width:(CGFloat)width
{
    self = [super initWithFrame:NSMakeRect(0, 0, width, kTileHeight)];
    if (self == nil)
        return nil;
    self.tag = method;
    self.translatesAutoresizingMaskIntoConstraints = NO;
    self.wantsLayer = YES;
    self.layer.cornerRadius = MacLCDesign.cornerRadiusMedium;
    self.focusRingType = NSFocusRingTypeExterior;
    _available = YES;

    _image = [NSImageView imageViewWithImage:
        [MacLCDesign symbolNamed:kSymbols[method] pointSize:18 weight:NSFontWeightMedium
              accessibilityLabel:nil]];
    _image.translatesAutoresizingMaskIntoConstraints = NO;
    _title = [NSTextField labelWithString:NSTR(Copy(method).title)];
    _title.alignment = NSTextAlignmentCenter;
    _title.lineBreakMode = NSLineBreakByTruncatingTail;
    _title.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:_image];
    [self addSubview:_title];
    [NSLayoutConstraint activateConstraints:@[
        [self.widthAnchor constraintEqualToConstant:width],
        [self.heightAnchor constraintEqualToConstant:kTileHeight],
        [_image.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        [_image.centerYAnchor constraintEqualToAnchor:self.topAnchor constant:22],
        [_title.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:4],
        [_title.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-4],
        [_title.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-7],
    ]];
    [self updateAppearance];
    return self;
}

- (void)setSelected:(BOOL)selected { _selected = selected; [self updateAppearance]; }
- (void)setAvailable:(BOOL)available { _available = available; [self updateAppearance]; }

- (void)updateAppearance
{
    const BOOL contrast = NSWorkspace.sharedWorkspace.accessibilityDisplayShouldIncreaseContrast;
    NSColor * const fill = _selected ? [MacLCDesign.accent colorWithAlphaComponent:0.20]
        : _hovered ? NSColor.tertiarySystemFillColor : NSColor.quaternarySystemFillColor;
    self.layer.backgroundColor = fill.CGColor;
    self.layer.borderWidth = _selected && contrast ? 1 : 0;
    self.layer.borderColor = MacLCDesign.accent.CGColor;
    /* a method that needs a download stays clickable: the click explains it */
    NSColor * const tint = _selected ? MacLCDesign.accent
        : _available ? MacLCDesign.secondaryLabel : MacLCDesign.tertiaryLabel;
    _image.contentTintColor = tint;
    _title.textColor = _selected ? MacLCDesign.accent
        : _available ? MacLCDesign.primaryLabel : MacLCDesign.secondaryLabel;
    _title.font = [NSFont systemFontOfSize:11
        weight:_selected ? NSFontWeightSemibold : NSFontWeightRegular];
}

- (void)updateTrackingAreas
{
    [super updateTrackingAreas];
    for (NSTrackingArea *area in self.trackingAreas)
        [self removeTrackingArea:area];
    [self addTrackingArea:[[NSTrackingArea alloc] initWithRect:self.bounds
        options:NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways | NSTrackingInVisibleRect
          owner:self userInfo:nil]];
}

- (void)mouseEntered:(NSEvent *)event { _hovered = YES; [self updateAppearance]; if (self.hover) self.hover(YES); }
- (void)mouseExited:(NSEvent *)event { _hovered = NO; [self updateAppearance]; if (self.hover) self.hover(NO); }
- (void)mouseDown:(NSEvent *)event { [self sendAction:self.action to:self.target]; }
- (BOOL)acceptsFirstResponder { return YES; }
- (BOOL)canBecomeKeyView { return YES; }

- (void)keyDown:(NSEvent *)event
{
    NSString * const chars = event.charactersIgnoringModifiers;
    const unichar c = chars.length ? [chars characterAtIndex:0] : 0;
    if (c == ' ' || c == '\r' || c == 3)
        [self sendAction:self.action to:self.target];
    else
        [super keyDown:event];
}

- (void)drawFocusRingMask
{
    [[NSBezierPath bezierPathWithRoundedRect:self.bounds xRadius:MacLCDesign.cornerRadiusMedium
                                     yRadius:MacLCDesign.cornerRadiusMedium] fill];
}
- (NSRect)focusRingMaskBounds { return self.bounds; }

- (BOOL)isAccessibilityElement { return YES; }
- (NSAccessibilityRole)accessibilityRole { return NSAccessibilityRadioButtonRole; }
- (id)accessibilityValue { return @(_selected); }
- (NSString *)accessibilityLabel { return NSTR(Copy(self.tag).title); }
- (NSString *)accessibilityHelp
{
    const MethodCopy c = Copy(self.tag);
    return [NSString stringWithFormat:@"%@. %@ %@ %@ %@", NSTR(c.summary),
        _NS("Good:"), NSTR(c.good), _NS("Bad:"), NSTR(c.bad)];
}
- (BOOL)accessibilityPerformPress { [self sendAction:self.action to:self.target]; return YES; }

@end

@implementation MacLCUpscalingPanelViewController
{
    NSSwitch *_switchControl;
    NSArray<MacLCUpscaleTile *> *_tiles;        /* indexed by method */
    NSTextField *_descriptionLabel;
    NSStackView *_actionStack;
    NSButton *_downloadButton, *_activateButton;
    NSProgressIndicator *_downloadProgress;
    NSSlider *_sharpnessSlider;
    NSTextField *_sharpnessLabel;
    NSPopUpButton *_targetPopup;
    NSButton *_disclosureButton;
    NSView *_details;
    NSTextField *_detailTitle, *_goodLabel, *_badLabel;
    MacLCTradeoffMeterView *_meterView;
    NSTextField *_statusLabel;
    NSInteger _hovered;                         /* -1: none */
    NSInteger _picked;                          /* last clicked tile */
    BOOL _sharpnessPending;
}

static NSPopover *gPopover;
static __weak NSView *gAnchor;

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
    popover.contentViewController = [[MacLCUpscalingPanelViewController alloc] init];
    gPopover = popover;
    gAnchor = view;
    [popover showRelativeToRect:view.bounds ofView:view preferredEdge:edge];
}

static NSTextField *Footnote(NSString *string, CGFloat width)
{
    NSTextField * const label = [NSTextField wrappingLabelWithString:string];
    label.font = MacLCDesign.footnote;
    label.textColor = MacLCDesign.secondaryLabel;
    label.preferredMaxLayoutWidth = width;
    return label;
}

static NSView *SymbolRow(NSString *symbol, NSColor *tint, NSTextField *label, NSString *name)
{
    NSImageView * const image = [NSImageView imageViewWithImage:
        [NSImage imageWithSystemSymbolName:symbol accessibilityDescription:name]];
    image.contentTintColor = tint;
    image.symbolConfiguration = [NSImageSymbolConfiguration configurationWithPointSize:11
                                                                                weight:NSFontWeightSemibold];
    [image setContentHuggingPriority:NSLayoutPriorityRequired
                      forOrientation:NSLayoutConstraintOrientationHorizontal];
    NSStackView * const row = [NSStackView stackViewWithViews:@[image, label]];
    row.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    row.alignment = NSLayoutAttributeFirstBaseline;
    row.spacing = MacLCDesign.spacingXS;
    return row;
}

static NSStackView *Row(NSArray<NSView *> *views)
{
    NSStackView * const row = [NSStackView stackViewWithViews:views];
    row.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    row.alignment = NSLayoutAttributeCenterY;
    row.spacing = MacLCDesign.spacingS;
    return row;
}

static NSBox *Separator(void)
{
    NSBox * const separator = [[NSBox alloc] init];
    separator.boxType = NSBoxSeparator;
    return separator;
}

- (void)loadView
{
    NSView * const root = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, kPanelWidth, 400)];
    root.translatesAutoresizingMaskIntoConstraints = NO;
    const CGFloat inner = kPanelWidth - 2 * kPanelPadding;
    _hovered = -1;
    _picked = MacLCUpscaling.method;

    /* header: title and master switch, as in the Sound panel */
    NSTextField * const title = [NSTextField labelWithString:_NS("Upscaling")];
    title.font = MacLCDesign.title3;
    _switchControl = [NSSwitch new];
    _switchControl.target = self;
    _switchControl.action = @selector(switchChanged:);
    _switchControl.accessibilityLabel = _NS("Upscale Video");
    NSStackView * const header = Row(@[title, [[NSView alloc] initWithFrame:NSZeroRect], _switchControl]);
    NSTextField * const subtitle = Footnote(
        _NS("Sharpens a video that is smaller than its window, so a DVD or a "
            "720p stream looks closer to the screen it is shown on."), inner);

    /* method tiles, three by three */
    const CGFloat tileWidth = floor((inner - 2 * kTileSpacing) / 3);
    NSMutableArray<MacLCUpscaleTile *> * const tiles = [NSMutableArray array];
    NSMutableArray<NSView *> * const gridRows = [NSMutableArray array];
    for (NSInteger m = 0; m < MACLC_UPSCALE_METHOD_COUNT; m++) {
        MacLCUpscaleTile * const tile = [[MacLCUpscaleTile alloc] initWithMethod:m width:tileWidth];
        tile.target = self;
        tile.action = @selector(tileClicked:);
        __weak typeof(self) weakSelf = self;
        tile.hover = ^(BOOL inside) {
            typeof(self) strongSelf = weakSelf;
            if (strongSelf == nil)
                return;
            if (inside)
                strongSelf->_hovered = m;
            else if (strongSelf->_hovered == m)
                strongSelf->_hovered = -1;
            [strongSelf showMethodDetailAnimated:YES];
        };
        [tiles addObject:tile];
        if (m % 3 == 2 || m == MACLC_UPSCALE_METHOD_COUNT - 1) {
            NSStackView * const gridRow = Row([tiles subarrayWithRange:NSMakeRange(m - m % 3, m % 3 + 1)]);
            gridRow.spacing = kTileSpacing;
            [gridRows addObject:gridRow];
        }
    }
    _tiles = tiles;
    NSStackView * const grid = [NSStackView stackViewWithViews:gridRows];
    grid.orientation = NSUserInterfaceLayoutOrientationVertical;
    grid.alignment = NSLayoutAttributeLeading;
    grid.spacing = kTileSpacing;
    grid.accessibilityRole = NSAccessibilityRadioGroupRole;
    grid.accessibilityLabel = _NS("Method");

    /* what the hovered or picked method does, with its download action */
    _descriptionLabel = [NSTextField wrappingLabelWithString:@""];
    _descriptionLabel.font = MacLCDesign.callout;
    _descriptionLabel.textColor = MacLCDesign.secondaryLabel;
    _descriptionLabel.maximumNumberOfLines = 2;
    [_descriptionLabel setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
                                                forOrientation:NSLayoutConstraintOrientationHorizontal];
    _downloadButton = [NSButton buttonWithTitle:_NS("Download") target:self
                                         action:@selector(downloadClicked:)];
    _downloadButton.controlSize = NSControlSizeSmall;
    _downloadButton.toolTip = _NS("Downloads Apple's model once, then this method can be used.");
    _downloadProgress = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(0, 0, 80, 12)];
    _downloadProgress.style = NSProgressIndicatorStyleBar;
    _downloadProgress.indeterminate = NO;
    _downloadProgress.minValue = 0;
    _downloadProgress.maxValue = 1;
    _downloadProgress.controlSize = NSControlSizeSmall;
    _downloadProgress.accessibilityLabel = _NS("Model download");
    [_downloadProgress.widthAnchor constraintEqualToConstant:80].active = YES;
    _activateButton = [NSButton buttonWithTitle:_NS("Activate…") target:self
                                         action:@selector(activateClicked:)];
    _activateButton.controlSize = NSControlSizeSmall;
    _activateButton.toolTip = _NS("Shows the model's licence; once you accept it, the model is downloaded.");
    _actionStack = Row(@[_downloadProgress, _downloadButton, _activateButton]);
    _actionStack.spacing = MacLCDesign.spacingXS;
    [_actionStack setContentHuggingPriority:NSLayoutPriorityRequired
                             forOrientation:NSLayoutConstraintOrientationHorizontal];
    NSStackView * const descriptionRow = Row(@[_descriptionLabel, _actionStack]);
    descriptionRow.alignment = NSLayoutAttributeTop;
    /* two lines are always reserved, so hovering never makes the popover jump */
    [descriptionRow.heightAnchor constraintGreaterThanOrEqualToConstant:
        ceil(2 * [[NSLayoutManager new] defaultLineHeightForFont:MacLCDesign.callout])].active = YES;

    /* sharpness and output size */
    _sharpnessLabel = [NSTextField labelWithString:_NS("Sharpness")];
    _sharpnessLabel.font = MacLCDesign.body;
    _sharpnessSlider = [NSSlider sliderWithValue:MacLCUpscaling.sharpness minValue:0 maxValue:100
                                          target:self action:@selector(sharpnessChanged:)];
    _sharpnessSlider.continuous = YES;
    _sharpnessSlider.accessibilityLabel = _NS("Sharpness");
    NSTextField * const targetLabel = [NSTextField labelWithString:_NS("Output Size")];
    targetLabel.font = MacLCDesign.body;
    _targetPopup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    _targetPopup.target = self;
    _targetPopup.action = @selector(targetChanged:);
    _targetPopup.accessibilityLabel = _NS("Output Size");
    _targetPopup.toolTip = _NS("Caps the upscaled picture: a smaller size saves energy on a large window.");
    const struct { const char *name; NSInteger tag; } targets[] = {
        {N_("Window Size"), 0}, {N_("Up to 1080p"), 1080}, {N_("Up to 1440p"), 1440}, {N_("Up to 4K"), 2160},
    };
    for (size_t i = 0; i < sizeof targets / sizeof *targets; i++) {
        [_targetPopup addItemWithTitle:NSTR(targets[i].name)];
        _targetPopup.lastItem.tag = targets[i].tag;
    }
    NSStackView * const sharpnessRow = Row(@[_sharpnessLabel, _sharpnessSlider]);
    NSStackView * const targetRow = Row(@[targetLabel, [[NSView alloc] initWithFrame:NSZeroRect], _targetPopup]);

    /* details: what the method is good and bad at, collapsed by default */
    _disclosureButton = [[NSButton alloc] initWithFrame:NSZeroRect];
    _disclosureButton.bordered = NO;
    _disclosureButton.target = self;
    _disclosureButton.action = @selector(toggleDetails:);
    _disclosureButton.imagePosition = NSImageLeading;
    _disclosureButton.alignment = NSTextAlignmentLeft;
    _disclosureButton.font = [NSFont systemFontOfSize:MacLCDesign.subheadline.pointSize
                                               weight:NSFontWeightSemibold];
    _disclosureButton.contentTintColor = MacLCDesign.primaryLabel;
    _disclosureButton.title = _NS("Strengths and Limits");

    _meterView = [[MacLCTradeoffMeterView alloc] initWithFrame:NSZeroRect];
    [_meterView setTitles:@[_NS("Sharpness"), _NS("Fine detail"),
                            _NS("True to source"), _NS("Battery")]];
    _detailTitle = [NSTextField labelWithString:@""];
    _detailTitle.font = [NSFont systemFontOfSize:MacLCDesign.footnote.pointSize
                                          weight:NSFontWeightSemibold];
    const CGFloat textWidth = inner - 18;
    _goodLabel = Footnote(@"", textWidth);
    _badLabel = Footnote(@"", textWidth);
    NSStackView * const details = [NSStackView stackViewWithViews:@[
        _meterView, _detailTitle,
        SymbolRow(@"plus.circle.fill", MacLCDesign.success, _goodLabel, _NS("Good")),
        SymbolRow(@"minus.circle.fill", MacLCDesign.warning, _badLabel, _NS("Bad")),
    ]];
    details.orientation = NSUserInterfaceLayoutOrientationVertical;
    details.alignment = NSLayoutAttributeLeading;
    details.spacing = MacLCDesign.spacingXS;
    [details setCustomSpacing:MacLCDesign.spacingS afterView:_meterView];
    _details = details;
    _details.hidden = ![NSUserDefaults.standardUserDefaults boolForKey:kShowsDetailsKey];
    [self updateDisclosureImage];

    NSBox * const separator1 = Separator(), * const separator2 = Separator();
    _statusLabel = Footnote(@"", inner);

    NSStackView * const stack = [NSStackView stackViewWithViews:@[
        header, subtitle, grid, descriptionRow, separator1, sharpnessRow, targetRow,
        separator2, _disclosureButton, _details, _statusLabel,
    ]];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = MacLCDesign.spacingS;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [stack setCustomSpacing:2.0 afterView:header];
    [stack setCustomSpacing:MacLCDesign.spacingM afterView:subtitle];
    [stack setCustomSpacing:MacLCDesign.spacingM afterView:separator2];

    [root addSubview:stack];
    NSMutableArray<NSLayoutConstraint *> * const constraints = [NSMutableArray arrayWithArray:@[
        [root.widthAnchor constraintEqualToConstant:kPanelWidth],
        [stack.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:kPanelPadding],
        [stack.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-kPanelPadding],
        [stack.topAnchor constraintEqualToAnchor:root.topAnchor constant:kPanelPadding],
        [stack.bottomAnchor constraintEqualToAnchor:root.bottomAnchor constant:-kPanelPadding],
        [_sharpnessLabel.widthAnchor constraintEqualToAnchor:targetLabel.widthAnchor],
    ]];
    for (NSView *view in @[header, descriptionRow, separator1, sharpnessRow, targetRow,
                           separator2, _disclosureButton, _meterView, details])
        [constraints addObject:[view.widthAnchor constraintEqualToConstant:inner]];
    [NSLayoutConstraint activateConstraints:constraints];

    /* the details keep the height of the longest method's, for the same reason */
    CGFloat tallest = 0;
    for (NSInteger m = 0; m < MACLC_UPSCALE_METHOD_COUNT; m++) {
        [self setDetailForMethod:m];
        tallest = MAX(tallest, details.fittingSize.height);
    }
    [details.heightAnchor constraintGreaterThanOrEqualToConstant:tallest].active = YES;
    [details setHuggingPriority:NSLayoutPriorityDefaultLow
                 forOrientation:NSLayoutConstraintOrientationVertical];

    self.view = root;
}

- (void)viewWillAppear
{
    [super viewWillAppear];
    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(stateDidChange:)
                                               name:MacLCUpscalingChangedNotification
                                             object:nil];
    [self updateAnimated:NO];
}

- (void)viewDidDisappear
{
    [super viewDidDisappear];
    [NSNotificationCenter.defaultCenter removeObserver:self
                                                  name:MacLCUpscalingChangedNotification
                                                object:nil];
}

- (void)stateDidChange:(NSNotification *)notification
{
    [self updateAnimated:YES];
}

- (void)updateDisclosureImage
{
    const BOOL shown = !_details.hidden;
    _disclosureButton.image = [NSImage imageWithSystemSymbolName:shown ? @"chevron.down" : @"chevron.right"
                                        accessibilityDescription:nil];
    _disclosureButton.accessibilityValue = shown ? _NS("Expanded") : _NS("Collapsed");
}

- (void)setDetailForMethod:(NSInteger)method
{
    const MethodCopy c = Copy(method);
    _detailTitle.stringValue = NSTR(c.title);
    _goodLabel.stringValue = NSTR(c.good);
    _badLabel.stringValue = NSTR(c.bad);
}

/* What a method does right now: its summary, or why it cannot be used yet. */
static NSString *Summary(NSInteger method)
{
    const MacLCUpscalingModelState model = MacLCUpscaling.apple4xModelState;
    const MacLCUpscalingModelState fsrcnnx = MacLCUpscaling.fsrcnnxState;
    if (method == MACLC_UPSCALE_APPLE4X) {
        if (model == MacLCUpscalingModelDownloading)
            return [NSString stringWithFormat:_NS("Downloading the model… %d%%"),
                (int)lround(MacLCUpscaling.apple4xModelProgress * 100)];
        if (model == MacLCUpscalingModelNotDownloaded)
            return MacLCUpscaling.apple4xModelError ?: _NS("Download Apple's model to use it.");
        if (model == MacLCUpscalingModelUnsupported)
            return _NS("Not available on this Mac.");
    }
    if (method == MACLC_UPSCALE_FSRCNNX) {
        if (fsrcnnx == MacLCUpscalingModelDownloading)
            return _NS("Downloading the model…");
        if (fsrcnnx == MacLCUpscalingModelNotDownloaded)
            return MacLCUpscaling.fsrcnnxError ?: _NS("Activate to download it (LGPL-3.0).");
    }
    return NSTR(Copy(method).summary);
}

static BOOL Available(NSInteger method)
{
    if (method == MACLC_UPSCALE_APPLE4X)
        return MacLCUpscaling.apple4xModelState == MacLCUpscalingModelReady;
    if (method == MACLC_UPSCALE_FSRCNNX)
        return MacLCUpscaling.fsrcnnxState == MacLCUpscalingModelReady;
    return YES;
}

/* The hovered method, or the last picked one: what it does, good and bad. */
- (void)showMethodDetailAnimated:(BOOL)animated
{
    const NSInteger method = _hovered >= 0 ? _hovered : _picked;
    [self setDetailForMethod:method];
    const MethodCopy c = Copy(method);
    [_meterView showLevels:@[@(c.levels[0]), @(c.levels[1]), @(c.levels[2]), @(c.levels[3])]
                  animated:animated];
    _descriptionLabel.stringValue = Summary(method);
    _descriptionLabel.toolTip = _descriptionLabel.stringValue;

    const MacLCUpscalingModelState model = MacLCUpscaling.apple4xModelState;
    const BOOL is4x = method == MACLC_UPSCALE_APPLE4X;
    _downloadButton.hidden = !is4x || model != MacLCUpscalingModelNotDownloaded;
    _downloadButton.title = MacLCUpscaling.apple4xModelError ? _NS("Retry") : _NS("Download");
    _downloadProgress.hidden = !is4x || model != MacLCUpscalingModelDownloading;
    _downloadProgress.doubleValue = MacLCUpscaling.apple4xModelProgress;
    _activateButton.hidden = method != MACLC_UPSCALE_FSRCNNX
        || MacLCUpscaling.fsrcnnxState != MacLCUpscalingModelNotDownloaded;
    _activateButton.title = MacLCUpscaling.fsrcnnxError ? _NS("Retry") : _NS("Activate…");
}

- (void)updateAnimated:(BOOL)animated
{
    const NSInteger method = MacLCUpscaling.method;
    _switchControl.state = MacLCUpscaling.isEnabled ? NSControlStateValueOn : NSControlStateValueOff;
    /* a picked method that became usable, or a change made elsewhere, follows the selection */
    if (Available(_picked))
        _picked = method;
    for (MacLCUpscaleTile *tile in _tiles) {
        tile.selected = tile.tag == method;
        tile.available = Available(tile.tag);
    }

    /* only FSR and NIS have a sharpening strength */
    const BOOL sharpens = method == MACLC_UPSCALE_SHARP || method == MACLC_UPSCALE_NIS;
    _sharpnessSlider.enabled = sharpens;
    _sharpnessLabel.textColor = sharpens ? MacLCDesign.primaryLabel : MacLCDesign.tertiaryLabel;
    _sharpnessSlider.toolTip = sharpens ? nil : _NS("Only Sharp and NIS have a sharpness setting.");
    if (!_sharpnessPending)
        _sharpnessSlider.integerValue = MacLCUpscaling.sharpness;
    _sharpnessSlider.accessibilityValueDescription =
        [NSString stringWithFormat:@"%ld%%", (long)_sharpnessSlider.integerValue];
    if (![_targetPopup selectItemWithTag:MacLCUpscaling.target])
        [_targetPopup selectItemWithTag:0];

    [self showMethodDetailAnimated:animated];
    _statusLabel.stringValue = MacLCUpscaling.statusText;
    self.preferredContentSize = self.view.fittingSize;
}

#pragma mark - actions

- (void)switchChanged:(id)sender
{
    const BOOL on = _switchControl.state == NSControlStateValueOn;
    MacLCUpscaling.enabled = on;
    [[MacLCOSDController sharedController]
        showMessage:on ? _NS("Upscaling On") : _NS("Upscaling Off")
         symbolName:@"arrow.up.left.and.arrow.down.right"];
}

- (void)tileClicked:(MacLCUpscaleTile *)sender
{
    _picked = sender.tag;
    if (!Available(sender.tag)) {
        /* the description now says how to get it, with its button */
        [self showMethodDetailAnimated:YES];
        return;
    }
    MacLCUpscaling.method = sender.tag;
    if (!MacLCUpscaling.isEnabled)
        MacLCUpscaling.enabled = YES;
    NSString * const message = [NSString stringWithFormat:_NS("Upscaling: %@"),
        NSTR(Copy(sender.tag).title)];
    NSAccessibilityPostNotificationWithUserInfo(self.view,
        NSAccessibilityAnnouncementRequestedNotification,
        @{ NSAccessibilityAnnouncementKey: message });
    [[MacLCOSDController sharedController]
        showMessage:message symbolName:@"arrow.up.left.and.arrow.down.right"];
}

/* The picture follows the slider live; the setting is saved once it rests,
 * not on every step of a drag. */
- (void)sharpnessChanged:(NSSlider *)sender
{
    _sharpnessPending = YES;
    [MacLCUpscaling previewSharpness:sender.integerValue];
    sender.accessibilityValueDescription = [NSString stringWithFormat:@"%ld%%", (long)sender.integerValue];
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(commitSharpness) object:nil];
    [self performSelector:@selector(commitSharpness) withObject:nil afterDelay:0.3];
}

- (void)commitSharpness
{
    _sharpnessPending = NO;
    MacLCUpscaling.sharpness = _sharpnessSlider.integerValue;
}

- (void)targetChanged:(NSPopUpButton *)sender
{
    MacLCUpscaling.target = sender.selectedTag;
}

- (void)toggleDetails:(id)sender
{
    _details.hidden = !_details.hidden;
    [NSUserDefaults.standardUserDefaults setBool:!_details.hidden forKey:kShowsDetailsKey];
    [self updateDisclosureImage];
    self.preferredContentSize = self.view.fittingSize;
}

- (void)downloadClicked:(id)sender
{
    [MacLCUpscaling downloadApple4xModel];
}

/* FSRCNNX is LGPL-3.0, so it is not shipped: the user accepts the licence
 * before the app downloads it. */
- (void)activateClicked:(id)sender
{
    NSAlert * const alert = [[NSAlert alloc] init];
    alert.messageText = _NS("Activate FSRCNNX?");
    alert.informativeText = _NS("FSRCNNX is by igv and is licensed under the GNU "
        "Lesser General Public License, version 3 or later. It is not part of "
        "MacLC: if you accept its licence, MacLC downloads it once from its "
        "author's GitHub release and checks it before use.");
    [alert addButtonWithTitle:_NS("Accept and Download")];
    [alert addButtonWithTitle:_NS("Cancel")];
    NSButton * const licence = [NSButton buttonWithTitle:_NS("Read the LGPL-3.0 Licence")
                                                  target:self
                                                  action:@selector(openLicence:)];
    licence.bezelStyle = NSBezelStylePush;
    alert.accessoryView = licence;
    [licence sizeToFit];
    if ([alert runModal] == NSAlertFirstButtonReturn)
        [MacLCUpscaling activateFSRCNNX];
}

- (void)openLicence:(id)sender
{
    [NSWorkspace.sharedWorkspace openURL:
        [NSURL URLWithString:@"https://www.gnu.org/licenses/lgpl-3.0.html"]];
}

@end
