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

/** A method row: a radio button, a one-line summary, an optional accessory,
 *  and a hover callback so the panel can explain the method. */
@interface MacLCUpscaleMethodRow : NSView
@property (readonly) NSButton *radio;
@property (readonly) NSTextField *summary;
@property (copy) void (^hover)(BOOL inside);
@end

@implementation MacLCUpscaleMethodRow

- (instancetype)initWithTitle:(NSString *)title summary:(NSString *)summary
                    accessory:(nullable NSView *)accessory
{
    self = [super initWithFrame:NSZeroRect];
    if (self == nil)
        return nil;
    self.translatesAutoresizingMaskIntoConstraints = NO;
    _radio = [NSButton radioButtonWithTitle:title target:nil action:NULL];
    _radio.font = MacLCDesign.body;
    _summary = [NSTextField labelWithString:summary];
    _summary.font = MacLCDesign.caption;
    _summary.textColor = MacLCDesign.secondaryLabel;
    _summary.lineBreakMode = NSLineBreakByTruncatingTail;
    [_summary setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
                                       forOrientation:NSLayoutConstraintOrientationHorizontal];

    NSStackView * const text = [NSStackView stackViewWithViews:@[_radio, _summary]];
    text.orientation = NSUserInterfaceLayoutOrientationVertical;
    text.alignment = NSLayoutAttributeLeading;
    text.spacing = 0;
    NSView * const spacer = [[NSView alloc] initWithFrame:NSZeroRect];
    [spacer setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
    NSStackView * const row = [NSStackView stackViewWithViews:accessory
        ? @[text, spacer, accessory] : @[text, spacer]];
    row.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    row.alignment = NSLayoutAttributeCenterY;
    row.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:row];
    /* the summary lines up under the radio title, not under the circle */
    const CGFloat indent = _radio.intrinsicContentSize.width
        - [title sizeWithAttributes:@{NSFontAttributeName: _radio.font}].width;
    [NSLayoutConstraint activateConstraints:@[
        [row.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [row.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [row.topAnchor constraintEqualToAnchor:self.topAnchor constant:3],
        [row.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-3],
        [_summary.leadingAnchor constraintEqualToAnchor:text.leadingAnchor constant:MAX(indent, 0)],
    ]];
    [text setCustomSpacing:0 afterView:_radio];
    return self;
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

- (void)mouseEntered:(NSEvent *)event { if (self.hover) self.hover(YES); }
- (void)mouseExited:(NSEvent *)event { if (self.hover) self.hover(NO); }

/* the whole row is the hit target, not only the radio's title */
- (void)mouseUp:(NSEvent *)event
{
    if (_radio.enabled && NSPointInRect([self convertPoint:event.locationInWindow fromView:nil], self.bounds))
        [_radio performClick:nil];
}
- (void)mouseDown:(NSEvent *)event {}

@end

@implementation MacLCUpscalingPanelViewController
{
    NSSwitch *_switchControl;
    NSArray<MacLCUpscaleMethodRow *> *_rows;   /* indexed by method */
    NSButton *_downloadButton, *_activateButton;
    NSProgressIndicator *_downloadProgress;
    NSTextField *_detailTitle, *_goodLabel, *_badLabel;
    MacLCTradeoffMeterView *_meterView;
    NSTextField *_statusLabel;
    NSInteger _hovered;                         /* -1: none */
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

- (void)loadView
{
    NSView * const root = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, kPanelWidth, 400)];
    root.translatesAutoresizingMaskIntoConstraints = NO;
    const CGFloat inner = kPanelWidth - 2 * kPanelPadding;
    _hovered = -1;

    NSTextField * const title = [NSTextField labelWithString:_NS("Upscaling")];
    title.font = MacLCDesign.title3;
    NSTextField * const detail = Footnote(
        _NS("Sharpens a video that is smaller than its window, so a DVD or a "
            "720p stream looks closer to the screen it is shown on."), inner);

    NSTextField * const switchLabel = [NSTextField labelWithString:_NS("Upscale Video")];
    switchLabel.font = MacLCDesign.body;
    _switchControl = [NSSwitch new];
    _switchControl.target = self;
    _switchControl.action = @selector(switchChanged:);
    _switchControl.accessibilityLabel = _NS("Upscale Video");
    NSView * const spacer = [[NSView alloc] initWithFrame:NSZeroRect];
    NSStackView * const switchRow =
        [NSStackView stackViewWithViews:@[switchLabel, spacer, _switchControl]];
    switchRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    switchRow.alignment = NSLayoutAttributeCenterY;
    switchRow.spacing = MacLCDesign.spacingS;

    NSTextField * const methodHeader = [NSTextField labelWithString:_NS("Method")];
    methodHeader.font = [NSFont systemFontOfSize:MacLCDesign.subheadline.pointSize
                                          weight:NSFontWeightSemibold];
    methodHeader.textColor = MacLCDesign.secondaryLabel;

    _downloadButton = [NSButton buttonWithTitle:_NS("Download") target:self
                                         action:@selector(downloadClicked:)];
    _downloadButton.controlSize = NSControlSizeSmall;
    _downloadButton.font = [NSFont systemFontOfSize:NSFont.smallSystemFontSize];
    _downloadButton.toolTip = _NS("Downloads Apple's model once, then this method can be used.");
    _downloadProgress = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(0, 0, 80, 12)];
    _downloadProgress.style = NSProgressIndicatorStyleBar;
    _downloadProgress.indeterminate = NO;
    _downloadProgress.minValue = 0;
    _downloadProgress.maxValue = 1;
    _downloadProgress.controlSize = NSControlSizeSmall;
    _downloadProgress.accessibilityLabel = _NS("Model download");
    [_downloadProgress.widthAnchor constraintEqualToConstant:80].active = YES;
    NSStackView * const accessory =
        [NSStackView stackViewWithViews:@[_downloadProgress, _downloadButton]];
    accessory.spacing = MacLCDesign.spacingXS;
    _activateButton = [NSButton buttonWithTitle:_NS("Activate…") target:self
                                         action:@selector(activateClicked:)];
    _activateButton.controlSize = NSControlSizeSmall;
    _activateButton.font = _downloadButton.font;
    _activateButton.toolTip = _NS("Shows the model's licence; once you accept it, the model is downloaded.");

    NSMutableArray<MacLCUpscaleMethodRow *> * const rows = [NSMutableArray array];
    NSStackView * const list = [[NSStackView alloc] init];
    list.orientation = NSUserInterfaceLayoutOrientationVertical;
    list.alignment = NSLayoutAttributeLeading;
    list.spacing = 0;
    for (NSInteger m = 0; m < MACLC_UPSCALE_METHOD_COUNT; m++) {
        const MethodCopy c = Copy(m);
        MacLCUpscaleMethodRow * const row = [[MacLCUpscaleMethodRow alloc]
            initWithTitle:NSTR(c.title) summary:NSTR(c.summary)
                accessory:m == MACLC_UPSCALE_APPLE4X ? accessory
                         : m == MACLC_UPSCALE_FSRCNNX ? _activateButton : nil];
        row.radio.tag = m;
        row.radio.target = self;
        row.radio.action = @selector(methodChanged:);
        /* hovering shows good and bad below the list; VoiceOver reads it here */
        row.radio.accessibilityHelp = [NSString stringWithFormat:@"%@ %@ %@ %@",
            _NS("Good:"), NSTR(c.good), _NS("Bad:"), NSTR(c.bad)];
        __weak typeof(self) weakSelf = self;
        row.hover = ^(BOOL inside) {
            typeof(self) strongSelf = weakSelf;
            if (strongSelf == nil)
                return;
            if (inside)
                strongSelf->_hovered = m;
            else if (strongSelf->_hovered == m)
                strongSelf->_hovered = -1;
            [strongSelf showMethodDetailAnimated:YES];
        };
        [list addArrangedSubview:row];
        [row.widthAnchor constraintEqualToConstant:inner].active = YES;
        [rows addObject:row];
    }
    _rows = rows;

    _detailTitle = [NSTextField labelWithString:@""];
    _detailTitle.font = [NSFont systemFontOfSize:MacLCDesign.footnote.pointSize
                                          weight:NSFontWeightSemibold];
    const CGFloat textWidth = inner - 18;
    _goodLabel = Footnote(@"", textWidth);
    _badLabel = Footnote(@"", textWidth);
    NSView * const good = SymbolRow(@"plus.circle.fill", MacLCDesign.success, _goodLabel, _NS("Good"));
    NSView * const bad = SymbolRow(@"minus.circle.fill", MacLCDesign.warning, _badLabel, _NS("Bad"));
    NSStackView * const detailStack = [NSStackView stackViewWithViews:@[_detailTitle, good, bad]];
    detailStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    detailStack.alignment = NSLayoutAttributeLeading;
    detailStack.spacing = MacLCDesign.spacingXS;
    detailStack.translatesAutoresizingMaskIntoConstraints = NO;

    _meterView = [[MacLCTradeoffMeterView alloc] initWithFrame:NSZeroRect];
    [_meterView setTitles:@[_NS("Sharpness"), _NS("Fine detail"),
                            _NS("True to source"), _NS("Battery")]];

    NSBox * const separator = [[NSBox alloc] init];
    separator.boxType = NSBoxSeparator;
    separator.translatesAutoresizingMaskIntoConstraints = NO;
    _statusLabel = Footnote(@"", inner);

    NSStackView * const stack = [NSStackView stackViewWithViews:@[
        title, detail, switchRow, methodHeader, list, _meterView, detailStack,
        separator, _statusLabel,
    ]];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = MacLCDesign.spacingS;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [stack setCustomSpacing:2.0 afterView:title];
    [stack setCustomSpacing:MacLCDesign.spacingM afterView:detail];
    [stack setCustomSpacing:MacLCDesign.spacingM afterView:switchRow];
    [stack setCustomSpacing:MacLCDesign.spacingXS afterView:methodHeader];
    [stack setCustomSpacing:MacLCDesign.spacingM afterView:detailStack];

    [root addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [root.widthAnchor constraintEqualToConstant:kPanelWidth],
        [stack.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:kPanelPadding],
        [stack.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-kPanelPadding],
        [stack.topAnchor constraintEqualToAnchor:root.topAnchor constant:kPanelPadding],
        [stack.bottomAnchor constraintEqualToAnchor:root.bottomAnchor constant:-kPanelPadding],
        [switchRow.widthAnchor constraintEqualToConstant:inner],
        [_meterView.widthAnchor constraintEqualToConstant:inner],
        [detailStack.widthAnchor constraintEqualToConstant:inner],
        [separator.widthAnchor constraintEqualToConstant:inner],
    ]];

    /* The explanation keeps the height of the longest one, so hovering from
     * row to row never makes the popover jump. */
    CGFloat tallest = 0;
    for (NSInteger m = 0; m < MACLC_UPSCALE_METHOD_COUNT; m++) {
        [self setDetailForMethod:m];
        tallest = MAX(tallest, detailStack.fittingSize.height);
    }
    [detailStack.heightAnchor constraintGreaterThanOrEqualToConstant:tallest].active = YES;
    detailStack.alignment = NSLayoutAttributeLeading;
    [detailStack setHuggingPriority:NSLayoutPriorityDefaultLow
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

- (void)setDetailForMethod:(NSInteger)method
{
    const MethodCopy c = Copy(method);
    _detailTitle.stringValue = NSTR(c.title);
    _goodLabel.stringValue = NSTR(c.good);
    _badLabel.stringValue = NSTR(c.bad);
}

/* The hovered method, or the selected one: what it is good and bad at. */
- (void)showMethodDetailAnimated:(BOOL)animated
{
    const NSInteger method = _hovered >= 0 ? _hovered : MacLCUpscaling.method;
    [self setDetailForMethod:method];
    const MethodCopy c = Copy(method);
    [_meterView showLevels:@[@(c.levels[0]), @(c.levels[1]), @(c.levels[2]), @(c.levels[3])]
                  animated:animated];
}

- (void)updateAnimated:(BOOL)animated
{
    const BOOL enabled = MacLCUpscaling.isEnabled;
    const NSInteger method = MacLCUpscaling.method;
    const MacLCUpscalingModelState model = MacLCUpscaling.apple4xModelState;
    const MacLCUpscalingModelState fsrcnnx = MacLCUpscaling.fsrcnnxState;
    _switchControl.state = enabled ? NSControlStateValueOn : NSControlStateValueOff;

    for (MacLCUpscaleMethodRow *row in _rows) {
        const NSInteger m = row.radio.tag;
        row.radio.state = m == method ? NSControlStateValueOn : NSControlStateValueOff;
        /* picking a method while off turns upscaling on, so it is never greyed */
        row.radio.enabled = (m != MACLC_UPSCALE_APPLE4X || model == MacLCUpscalingModelReady)
            && (m != MACLC_UPSCALE_FSRCNNX || fsrcnnx == MacLCUpscalingModelReady);
    }

    /* FSRCNNX: usable once its licence is accepted and the file downloaded */
    MacLCUpscaleMethodRow * const rowFSRCNNX = _rows[MACLC_UPSCALE_FSRCNNX];
    _activateButton.hidden = fsrcnnx != MacLCUpscalingModelNotDownloaded;
    _activateButton.title = MacLCUpscaling.fsrcnnxError ? _NS("Retry") : _NS("Activate…");
    rowFSRCNNX.summary.stringValue =
        fsrcnnx == MacLCUpscalingModelDownloading ? _NS("Downloading the model…")
        : MacLCUpscaling.fsrcnnxError && fsrcnnx == MacLCUpscalingModelNotDownloaded
            ? MacLCUpscaling.fsrcnnxError
        : fsrcnnx == MacLCUpscalingModelNotDownloaded
            ? _NS("Activate to download it (LGPL-3.0)")
            : NSTR(Copy(MACLC_UPSCALE_FSRCNNX).summary);

    /* Apple Neural 4x: hidden where the Mac has no full super resolution,
     * otherwise usable once its model is downloaded. */
    MacLCUpscaleMethodRow * const row4x = _rows[MACLC_UPSCALE_APPLE4X];
    row4x.hidden = model == MacLCUpscalingModelUnsupported && method != MACLC_UPSCALE_APPLE4X;
    _downloadButton.hidden = model != MacLCUpscalingModelNotDownloaded;
    _downloadButton.title = MacLCUpscaling.apple4xModelError ? _NS("Retry") : _NS("Download");
    _downloadProgress.hidden = model != MacLCUpscalingModelDownloading;
    _downloadProgress.doubleValue = MacLCUpscaling.apple4xModelProgress;
    const MethodCopy c4x = Copy(MACLC_UPSCALE_APPLE4X);
    row4x.summary.stringValue =
        model == MacLCUpscalingModelDownloading
            ? [NSString stringWithFormat:_NS("Downloading the model… %d%%"),
                (int)lround(MacLCUpscaling.apple4xModelProgress * 100)]
        : MacLCUpscaling.apple4xModelError && model == MacLCUpscalingModelNotDownloaded
            ? MacLCUpscaling.apple4xModelError
        : model == MacLCUpscalingModelNotDownloaded
            ? _NS("Download Apple's model to use it")
        : model == MacLCUpscalingModelUnsupported
            ? _NS("Not available on this Mac")
            : NSTR(c4x.summary);

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

- (void)methodChanged:(NSButton *)sender
{
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
