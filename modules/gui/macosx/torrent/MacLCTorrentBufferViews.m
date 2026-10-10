/*****************************************************************************
 * MacLCTorrentBufferViews.m: the download head on the seek bar (marker and
 * details card), and the downloaded-ranges overlay of the Now Playing bar
 *****************************************************************************
 * Copyright (C) 2026 Hazen Studio
 *
 * This program is free software; you can redistribute it and/or modify it
 * under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin Street, Fifth Floor, Boston MA 02110-1301, USA.
 *****************************************************************************/

#import "MacLCTorrentBufferViews.h"

#import <QuartzCore/QuartzCore.h>

#import "extensions/NSString+Helpers.h"
#import "theme/MacLCDesign.h"
#import "torrent/MacLCTorrentMonitor.h"
#import "torrent/MacLCTorrentStats.h"

/* The marker sits 6 pt above the track, the card above the slider's hover
 * time capsule (which is 8 pt over the slider and about 24 pt high). */
static const CGFloat kMarkerGapAboveTrack = 6.0;
static const CGFloat kCardClearanceAboveSlider = 38.0;
static const CGFloat kNearHeadDistance = 40.0;
static const CGFloat kPillHeight = 24.0;
static const CGFloat kCardWidth = 252.0;
static const CGFloat kCardInset = 12.0;
static const CGFloat kGlyphSize = 12.0;
static const NSTimeInterval kCollapseDelay = 0.25;
/* The ring fills as the film in the buffer goes from 0 to this many seconds. */
static const NSTimeInterval kRingFullSeconds = 10.0;

static double Clamp01(double v)
{
    return v < 0.0 ? 0.0 : (v > 1.0 ? 1.0 : v);
}

/* The alpha the viewer sees for a view: the controls bar hides by fading an
 * ancestor of the slider, never the slider itself. */
static CGFloat EffectiveAlpha(NSView *view)
{
    CGFloat alpha = 1.0;
    for (NSView *v = view; v != nil; v = v.superview) {
        alpha *= v.alphaValue;
    }
    return alpha * (view.window != nil ? view.window.alphaValue : 1.0);
}

#pragma mark - Root view (clicks, pointer)

@protocol MacLCTorrentMarkerRootOwner <NSObject>
- (void)markerRootClicked;
- (void)markerRootPointerInside:(BOOL)inside;
@end

@interface MacLCTorrentMarkerRootView : NSView
@property (nonatomic, weak) id<MacLCTorrentMarkerRootOwner> owner;
@end

@implementation MacLCTorrentMarkerRootView

- (instancetype)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (self) {
        self.wantsLayer = YES;
        self.layer.cornerRadius = kPillHeight / 2.0;
        self.layer.masksToBounds = YES;
        NSTrackingArea * const area = [[NSTrackingArea alloc]
            initWithRect:NSZeroRect
                 options:NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways | NSTrackingInVisibleRect
                   owner:self
                userInfo:nil];
        [self addTrackingArea:area];
    }
    return self;
}

/* The panel never becomes key: the first click must act. */
- (BOOL)acceptsFirstMouse:(NSEvent *)event
{
    return YES;
}

- (void)mouseDown:(NSEvent *)event
{
    [self.owner markerRootClicked];
}

- (void)mouseEntered:(NSEvent *)event
{
    [self.owner markerRootPointerInside:YES];
}

- (void)mouseExited:(NSEvent *)event
{
    [self.owner markerRootPointerInside:NO];
}

- (BOOL)isAccessibilityElement
{
    return YES;
}

- (NSAccessibilityRole)accessibilityRole
{
    return NSAccessibilityButtonRole;
}

- (BOOL)accessibilityPerformPress
{
    [self.owner markerRootClicked];
    return YES;
}

@end

#pragma mark - Sparkline

/* Download rate history, drawn at draw time so the accent colour follows the
 * appearance. */
@interface MacLCTorrentSparklineView : NSView
@property (nonatomic, copy) NSArray<NSNumber *> *values;
@end

@implementation MacLCTorrentSparklineView

- (void)setValues:(NSArray<NSNumber *> *)values
{
    _values = [values copy];
    self.needsDisplay = YES;
}

- (BOOL)isAccessibilityElement
{
    return NO;
}

- (void)drawRect:(NSRect)dirtyRect
{
    NSArray<NSNumber *> * const values = _values;
    const NSUInteger count = values.count;
    if (count < 2) {
        return;
    }
    double peak = 1.0;
    for (NSNumber *value in values) {
        peak = MAX(peak, value.doubleValue);
    }

    const NSRect area = NSInsetRect(self.bounds, 1.0, 2.0);
    NSBezierPath * const line = [NSBezierPath bezierPath];
    for (NSUInteger i = 0; i < count; i++) {
        const CGFloat x = NSMinX(area) + NSWidth(area) * (CGFloat)i / (CGFloat)(count - 1);
        const CGFloat y = NSMinY(area) + NSHeight(area) * (CGFloat)(MAX(values[i].doubleValue, 0.0) / peak);
        if (i == 0) {
            [line moveToPoint:NSMakePoint(x, y)];
        } else {
            [line lineToPoint:NSMakePoint(x, y)];
        }
    }

    NSBezierPath * const fill = [line copy];
    [fill lineToPoint:NSMakePoint(NSMaxX(area), NSMinY(area))];
    [fill lineToPoint:NSMakePoint(NSMinX(area), NSMinY(area))];
    [fill closePath];
    [[MacLCDesign.accent colorWithAlphaComponent:0.28] setFill];
    [fill fill];

    line.lineWidth = 1.5;
    line.lineJoinStyle = NSLineJoinStyleRound;
    line.lineCapStyle = NSLineCapStyleRound;
    [MacLCDesign.accent setStroke];
    [line stroke];
}

@end

#pragma mark - Marker

@interface MacLCTorrentHeadMarker () <MacLCTorrentMarkerRootOwner>
{
    __weak NSSlider *_slider;
    NSPanel *_window;
    MacLCTorrentMarkerRootView *_root;

    /* Collapsed: arrow (or ring) and speed. */
    NSView *_pill;
    NSImageView *_arrowView;
    NSView *_ringHost;
    CAShapeLayer *_ringTrackLayer;
    CAShapeLayer *_ringLayer;
    NSTextField *_pillLabel;

    /* Expanded: the card. */
    NSView *_card;
    NSStackView *_cardStack;
    NSTextField *_stageLabel;
    NSTextField *_speedLabel;
    MacLCTorrentSparklineView *_sparkline;
    NSTextField *_peersLabel;
    NSTextField *_swarmLabel;
    NSTextField *_bufferLabel;
    NSTextField *_downloadedLabel;

    /* Latest data. */
    BOOL _active;
    BOOL _complete;
    BOOL _stalled;
    double _headFraction;
    NSString *_summary;

    /* Pointer and state. */
    BOOL _pointerOnSlider;
    BOOL _hoverVisible;
    CGFloat _pointerX;
    BOOL _pointerInWindow;
    BOOL _pinned;
    BOOL _shown;
    BOOL _expanded;
    BOOL _bouncing;
    BOOL _invalid;
    CFTimeInterval _collapseDeadline;
    NSRect _lastFrame;

    NSArray<NSView *> *_observedViews;
    NSPointerArray *_avoidViews;
    NSMutableArray *_notificationTokens;
}
@end

@implementation MacLCTorrentHeadMarker

- (instancetype)initWithSlider:(NSSlider *)slider
{
    self = [super init];
    if (self) {
        _slider = slider;
        _summary = @"";
        _notificationTokens = [NSMutableArray array];
        [self buildWindow];
        [self sliderDidMoveToWindow];
    }
    return self;
}

- (void)dealloc
{
    [self invalidate];
}

- (BOOL)shown
{
    return _shown;
}

- (NSArray<NSView *> *)avoidViews
{
    return _avoidViews.allObjects;
}

- (void)setAvoidViews:(NSArray<NSView *> *)avoidViews
{
    _avoidViews = [NSPointerArray weakObjectsPointerArray];
    for (NSView *view in avoidViews) {
        [_avoidViews addPointer:(__bridge void *)view];
    }
}

#pragma mark Building

static NSTextField *MakeLabel(NSFont *font, NSColor *color)
{
    NSTextField * const label = [NSTextField labelWithString:@""];
    label.font = font;
    label.textColor = color;
    label.lineBreakMode = NSLineBreakByTruncatingTail;
    label.maximumNumberOfLines = 1;
    [label setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
                                    forOrientation:NSLayoutConstraintOrientationHorizontal];
    return label;
}

- (NSStackView *)rowWithSymbol:(NSString *)symbolName label:(NSTextField *)label
{
    NSImageView * const icon = [[NSImageView alloc] init];
    icon.image = [MacLCDesign symbolNamed:symbolName pointSize:11.0 weight:NSFontWeightMedium accessibilityLabel:nil];
    icon.contentTintColor = MacLCDesign.secondaryLabel;
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    [icon.widthAnchor constraintEqualToConstant:16.0].active = YES;
    [icon setContentHuggingPriority:NSLayoutPriorityRequired
                     forOrientation:NSLayoutConstraintOrientationHorizontal];

    NSStackView * const row = [NSStackView stackViewWithViews:@[icon, label]];
    row.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    row.alignment = NSLayoutAttributeCenterY;
    row.spacing = MacLCDesign.spacingXS + 2.0;
    return row;
}

- (void)buildWindow
{
    _root = [[MacLCTorrentMarkerRootView alloc] initWithFrame:NSMakeRect(0, 0, 80.0, kPillHeight)];
    _root.owner = self;
    _root.accessibilityLabel = _NS("Download status");

    [self buildPill];
    [self buildCard];

    _window = [[NSPanel alloc] initWithContentRect:_root.frame
                                         styleMask:NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel
                                           backing:NSBackingStoreBuffered
                                             defer:NO];
    _window.contentView = _root;
    _window.opaque = NO;
    _window.backgroundColor = NSColor.clearColor;
    _window.hasShadow = YES;
    _window.releasedWhenClosed = NO;
    _window.hidesOnDeactivate = NO;
    /* Always dark: it floats over the picture. */
    _window.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
}

- (void)buildPill
{
    _pill = [[NSView alloc] initWithFrame:_root.bounds];
    _pill.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [_root addSubview:_pill];

    const CGFloat glyphY = (kPillHeight - kGlyphSize) / 2.0;
    _arrowView = [[NSImageView alloc] initWithFrame:NSMakeRect(9.0, glyphY, kGlyphSize, kGlyphSize)];
    _arrowView.image = [MacLCDesign symbolNamed:@"arrow.down" pointSize:11.0 weight:NSFontWeightBold accessibilityLabel:nil];
    _arrowView.contentTintColor = NSColor.whiteColor;
    _arrowView.imageScaling = NSImageScaleProportionallyDown;
    _arrowView.autoresizingMask = NSViewMinYMargin | NSViewMaxYMargin;
    _arrowView.wantsLayer = YES;
    [_pill addSubview:_arrowView];

    _ringHost = [[NSView alloc] initWithFrame:_arrowView.frame];
    _ringHost.autoresizingMask = NSViewMinYMargin | NSViewMaxYMargin;
    _ringHost.wantsLayer = YES;
    _ringHost.hidden = YES;
    const CGRect ringBounds = CGRectMake(0, 0, kGlyphSize, kGlyphSize);
    CGPathRef const circle = CGPathCreateWithEllipseInRect(CGRectInset(ringBounds, 1.4, 1.4), NULL);
    _ringTrackLayer = [CAShapeLayer layer];
    _ringLayer = [CAShapeLayer layer];
    for (CAShapeLayer *layer in @[_ringTrackLayer, _ringLayer]) {
        layer.bounds = ringBounds;
        layer.position = CGPointMake(kGlyphSize / 2.0, kGlyphSize / 2.0);
        layer.path = circle;
        layer.fillColor = NULL;
        layer.lineWidth = 1.8;
        layer.lineCap = kCALineCapRound;
        /* The arc starts at twelve o'clock. */
        layer.transform = CATransform3DMakeRotation((CGFloat)-M_PI_2, 0, 0, 1);
        [_ringHost.layer addSublayer:layer];
    }
    CGPathRelease(circle);
    _ringTrackLayer.strokeColor = [NSColor colorWithWhite:1.0 alpha:0.28].CGColor;
    _ringLayer.strokeColor = NSColor.whiteColor.CGColor;
    _ringLayer.strokeEnd = 0.0;
    [_pill addSubview:_ringHost];

    _pillLabel = MakeLabel([MacLCDesign monospacedDigitFontForTextStyle:NSFontTextStyleCaption1
                                                                  weight:NSFontWeightSemibold],
                           NSColor.whiteColor);
    _pillLabel.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin | NSViewMaxYMargin;
    [_pill addSubview:_pillLabel];
}

- (void)buildCard
{
    _card = [[NSView alloc] initWithFrame:_root.bounds];
    _card.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    _card.hidden = YES;
    [_root addSubview:_card];

    NSFont * const small = [MacLCDesign monospacedDigitFontForTextStyle:NSFontTextStyleCaption1];
    NSFont * const smallEmphasized = [MacLCDesign monospacedDigitFontForTextStyle:NSFontTextStyleCaption1
                                                                            weight:NSFontWeightMedium];

    _stageLabel = MakeLabel(smallEmphasized, MacLCDesign.secondaryLabel);

    _speedLabel = MakeLabel([MacLCDesign monospacedDigitFontForTextStyle:NSFontTextStyleTitle3
                                                                   weight:NSFontWeightSemibold],
                            MacLCDesign.primaryLabel);
    [_speedLabel setContentHuggingPriority:NSLayoutPriorityDefaultLow
                            forOrientation:NSLayoutConstraintOrientationHorizontal];
    _sparkline = [[MacLCTorrentSparklineView alloc] init];
    _sparkline.translatesAutoresizingMaskIntoConstraints = NO;
    [_sparkline.widthAnchor constraintEqualToConstant:92.0].active = YES;
    [_sparkline.heightAnchor constraintEqualToConstant:26.0].active = YES;
    NSStackView * const speedRow = [NSStackView stackViewWithViews:@[_speedLabel, _sparkline]];
    speedRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    speedRow.alignment = NSLayoutAttributeCenterY;
    speedRow.spacing = MacLCDesign.spacingS;

    _peersLabel = MakeLabel(small, MacLCDesign.primaryLabel);
    _swarmLabel = MakeLabel(small, MacLCDesign.secondaryLabel);
    _bufferLabel = MakeLabel(small, MacLCDesign.primaryLabel);
    _downloadedLabel = MakeLabel(small, MacLCDesign.primaryLabel);

    NSStackView * const peersRow = [self rowWithSymbol:@"person.2.fill" label:_peersLabel];
    NSStackView * const swarmRow = [self rowWithSymbol:@"network" label:_swarmLabel];
    NSStackView * const bufferRow = [self rowWithSymbol:@"clock" label:_bufferLabel];
    NSStackView * const downloadedRow = [self rowWithSymbol:@"internaldrive" label:_downloadedLabel];

    NSArray<NSView *> * const rows = @[_stageLabel, speedRow, peersRow, swarmRow, bufferRow, downloadedRow];
    _cardStack = [NSStackView stackViewWithViews:rows];
    _cardStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    _cardStack.alignment = NSLayoutAttributeLeading;
    _cardStack.spacing = MacLCDesign.spacingS - 2.0;
    _cardStack.edgeInsets = NSEdgeInsetsMake(10.0, kCardInset, 12.0, kCardInset);
    _cardStack.translatesAutoresizingMaskIntoConstraints = NO;
    [_cardStack setCustomSpacing:MacLCDesign.spacingS afterView:speedRow];
    [_card addSubview:_cardStack];

    const CGFloat rowWidth = kCardWidth - 2.0 * kCardInset;
    for (NSView *row in rows) {
        [row.widthAnchor constraintLessThanOrEqualToConstant:rowWidth].active = YES;
    }
    [speedRow.widthAnchor constraintEqualToConstant:rowWidth].active = YES;

    [NSLayoutConstraint activateConstraints:@[
        [_cardStack.widthAnchor constraintEqualToConstant:kCardWidth],
        [_cardStack.topAnchor constraintEqualToAnchor:_card.topAnchor],
        [_cardStack.leadingAnchor constraintEqualToAnchor:_card.leadingAnchor],
    ]];
}

#pragma mark Data

+ (NSString *)summaryForTorrent:(MacLCTorrentInfo *)torrent
{
    NSString * const peers = torrent.peers == 1
        ? _NS("1 peer")
        : [NSString stringWithFormat:_NS("%ld peers"), (long)torrent.peers];
    return [NSString stringWithFormat:@"%@ · %@ · %@", _NS("Downloading"),
            [MacLCTorrentFormat rateString:torrent.downloadRate], peers];
}

+ (NSString *)spokenRateString:(int64_t)bytesPerSecond
{
    if (bytesPerSecond >= 1000000) {
        return [NSString stringWithFormat:_NS("%.1f megabytes per second"), (double)bytesPerSecond / 1e6];
    }
    if (bytesPerSecond >= 1000) {
        return [NSString stringWithFormat:_NS("%lld kilobytes per second"), (long long)(bytesPerSecond / 1000)];
    }
    return [NSString stringWithFormat:_NS("%lld bytes per second"), (long long)MAX(bytesPerSecond, 0)];
}

- (void)updateWithMonitor:(MacLCTorrentMonitor *)monitor
{
    if (_invalid) {
        return;
    }
    MacLCTorrentReaderInfo * const reader = monitor.reader;
    MacLCTorrentInfo * const torrent = monitor.torrent;
    _active = monitor.active && reader != nil && torrent != nil && reader.size > 0;

    if (_active) {
        _headFraction = Clamp01(reader.headFraction);
        _complete = _headFraction >= 0.999;
        _stalled = monitor.stage == MacLCTorrentStageStalled;
        [self updateContentWithTorrent:torrent reader:reader monitor:monitor];
    } else {
        _pinned = NO;
    }
    [self refreshAnimated:YES];
}

- (void)updateContentWithTorrent:(MacLCTorrentInfo *)torrent
                          reader:(MacLCTorrentReaderInfo *)reader
                         monitor:(MacLCTorrentMonitor *)monitor
{
    NSString * const rate = [MacLCTorrentFormat rateString:torrent.downloadRate];
    _pillLabel.stringValue = rate;
    _speedLabel.stringValue = rate;
    _sparkline.values = monitor.rateHistory;

    const MacLCTorrentStage stage = monitor.stage;
    _stageLabel.hidden = stage == MacLCTorrentStagePlaying || stage == MacLCTorrentStageUnknown;
    _stageLabel.stringValue = [MacLCTorrentFormat titleForStage:stage];

    _peersLabel.stringValue = [MacLCTorrentFormat peersString:torrent];
    /* Trackers that know fewer seeds than we are connected to say nothing
     * useful ("0 seeds in the swarm" next to "1 seed"). */
    _swarmLabel.superview.hidden = torrent.swarmSeeds <= torrent.seeds;
    _swarmLabel.stringValue = torrent.swarmSeeds == 1
        ? _NS("1 seed in the swarm")
        : [NSString stringWithFormat:_NS("%ld seeds in the swarm"), (long)torrent.swarmSeeds];

    const NSTimeInterval ahead = reader.aheadSeconds;
    _bufferLabel.stringValue = ahead < 1.0
        ? _NS("Buffered: nothing ahead yet")
        : [NSString stringWithFormat:_NS("Buffered: %@ ahead"), [MacLCTorrentFormat durationString:ahead]];

    uint64_t onDisk = 0;
    for (NSArray<NSNumber *> *range in reader.ranges) {
        if (range.count == 2 && range[1].unsignedLongLongValue > range[0].unsignedLongLongValue) {
            onDisk += range[1].unsignedLongLongValue - range[0].unsignedLongLongValue;
        }
    }
    _downloadedLabel.stringValue = [NSString stringWithFormat:_NS("Downloaded: %@ of %@"),
        [MacLCTorrentFormat sizeString:MIN(onDisk, reader.size)],
        [MacLCTorrentFormat sizeString:reader.size]];

    _ringLayer.strokeEnd = (CGFloat)Clamp01(ahead / kRingFullSeconds);

    _summary = [MacLCTorrentHeadMarker summaryForTorrent:torrent];
    _root.accessibilityValue = [NSString stringWithFormat:@"%@, %@, %@",
        _summary, _bufferLabel.stringValue, _downloadedLabel.stringValue];
    _root.toolTip = _expanded ? nil : _summary;
}

#pragma mark Pointer from the slider

- (void)sliderPointerMovedToX:(CGFloat)x hoverVisible:(BOOL)hoverVisible
{
    _pointerOnSlider = YES;
    _pointerX = x;
    _hoverVisible = hoverVisible;
    [self refreshAnimated:YES];
}

- (void)sliderPointerExited
{
    _pointerOnSlider = NO;
    _hoverVisible = NO;
    [self refreshAnimated:YES];
}

- (void)markerRootClicked
{
    _pinned = !_pinned;
    [self refreshAnimated:YES];
}

- (void)markerRootPointerInside:(BOOL)inside
{
    _pointerInWindow = inside;
    [self refreshAnimated:YES];
}

#pragma mark Observing the slider's surroundings

- (void)stopObserving
{
    for (NSView *view in _observedViews) {
        [view removeObserver:self forKeyPath:@"alphaValue"];
    }
    _observedViews = nil;
    for (id token in _notificationTokens) {
        [NSNotificationCenter.defaultCenter removeObserver:token];
    }
    [_notificationTokens removeAllObjects];
}

- (void)sliderDidMoveToWindow
{
    if (_invalid) {
        return;
    }
    [self stopObserving];

    NSSlider * const slider = _slider;
    NSWindow * const window = slider.window;
    if (window == nil) {
        _pointerOnSlider = NO;
        _pointerInWindow = NO;
        [self hideAnimated:NO];
        return;
    }

    /* The controls bar fades one of the slider's ancestors. */
    NSMutableArray<NSView *> * const chain = [NSMutableArray array];
    for (NSView *view = slider; view != nil; view = view.superview) {
        [view addObserver:self forKeyPath:@"alphaValue" options:0 context:NULL];
        [chain addObject:view];
    }
    _observedViews = chain;

    __weak typeof(self) weakSelf = self;
    void (^refresh)(NSNotification *) = ^(NSNotification *note) {
        [weakSelf refreshAnimated:NO];
    };
    NSNotificationCenter * const center = NSNotificationCenter.defaultCenter;
    for (NSNotificationName name in @[NSWindowDidResizeNotification,
                                      NSWindowDidChangeOcclusionStateNotification,
                                      NSWindowDidMiniaturizeNotification,
                                      NSWindowDidDeminiaturizeNotification]) {
        [_notificationTokens addObject:[center addObserverForName:name object:window queue:NSOperationQueue.mainQueue usingBlock:refresh]];
    }
    [_notificationTokens addObject:
        [center addObserverForName:NSWindowWillCloseNotification
                            object:window
                             queue:NSOperationQueue.mainQueue
                        usingBlock:^(NSNotification *note) {
        [weakSelf windowWillClose];
    }]];
    [_notificationTokens addObject:
        [center addObserverForName:NSViewFrameDidChangeNotification
                            object:slider
                             queue:NSOperationQueue.mainQueue
                        usingBlock:refresh]];
    slider.postsFrameChangedNotifications = YES;

    [self refreshAnimated:NO];
}

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary<NSKeyValueChangeKey, id> *)change
                       context:(void *)context
{
    if ([keyPath isEqualToString:@"alphaValue"]) {
        [self refreshAnimated:YES];
    }
}

- (void)windowWillClose
{
    _pointerOnSlider = NO;
    _pointerInWindow = NO;
    _pinned = NO;
    [self stopObserving];
    [self hideAnimated:NO];
}

#pragma mark Layout

- (NSSize)pillSize
{
    return NSMakeSize(ceil(_pillLabel.fittingSize.width) + 9.0 + kGlyphSize + 5.0 + 11.0, kPillHeight);
}

- (NSSize)cardSize
{
    return NSMakeSize(kCardWidth, ceil(_cardStack.fittingSize.height));
}

/* Applies the chrome that depends on accessibility settings. */
- (void)applyChrome
{
    CALayer * const layer = _root.layer;
    NSColor * const background = MacLCDesign.reduceTransparency
        ? MacLCDesign.mediaBackground
        : MacLCDesign.mediaOverlayBackground;
    layer.backgroundColor = background.CGColor;
    layer.borderWidth = 0.5;
    layer.borderColor = [NSColor colorWithWhite:1.0 alpha:0.18].CGColor;
}

- (void)setBouncing:(BOOL)bouncing
{
    if (_bouncing == bouncing) {
        return;
    }
    _bouncing = bouncing;
    CALayer * const layer = _arrowView.layer;
    if (!bouncing) {
        [layer removeAnimationForKey:@"MacLCTorrentBounce"];
        return;
    }
    CABasicAnimation * const bounce = [CABasicAnimation animationWithKeyPath:@"transform.translation.y"];
    bounce.fromValue = @(1.0);
    bounce.toValue = @(-1.0);
    bounce.duration = 0.55;
    bounce.autoreverses = YES;
    bounce.repeatCount = HUGE_VALF;
    bounce.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    [layer addAnimation:bounce forKey:@"MacLCTorrentBounce"];
}

/* The glyph slot shows the arrow, or a ring while the player waits for data. */
- (void)updateGlyph
{
    _arrowView.hidden = _stalled;
    _ringHost.hidden = !_stalled;
    [self setBouncing:_shown && !_stalled && !MacLCDesign.reducedMotion];
}

- (void)refreshAnimated:(BOOL)animated
{
    if (_invalid) {
        return;
    }

    NSSlider * const slider = _slider;
    NSWindow * const parent = slider.window;
    BOOL canShow = _active && !_complete && slider != nil && parent != nil
        && parent.visible && !parent.miniaturized
        && (parent.occlusionState & NSWindowOcclusionStateVisible) != 0
        && !slider.hiddenOrHasHiddenAncestor
        && EffectiveAlpha(slider) > 0.05;

    NSRect sliderScreen = NSZeroRect;
    CGFloat headX = 0.0;
    if (canShow) {
        const NSRect bar = [(NSSliderCell *)slider.cell barRectFlipped:NO];
        if (NSWidth(bar) <= 0.0) {
            canShow = NO;
        } else {
            headX = NSMinX(bar) + (CGFloat)_headFraction * NSWidth(bar);
            sliderScreen = [parent convertRectToScreen:[slider convertRect:slider.bounds toView:nil]];
        }
    }

    const BOOL near = _pointerOnSlider && fabs(_pointerX - headX) <= kNearHeadDistance;
    const BOOL far = _pointerOnSlider && !near;
    if (!canShow || (far && !_pinned)) {
        if (!canShow) {
            _pointerInWindow = NO;
        }
        [self hideAnimated:animated];
        return;
    }

    /* Expanded under the pointer or on a click; leaving the card collapses it
     * after a short delay, so crossing from the bar to the card is smooth. */
    /* The pill sits below the bar and the card opens above it: the pointer on
     * the pill must not open the card (it would leave the pill at once); a
     * click does. Once the card is open, staying on it keeps it open. */
    BOOL expanded = _pinned || near || (_pointerInWindow && _expanded);
    if (!expanded && _expanded && _shown) {
        const CFTimeInterval now = CACurrentMediaTime();
        if (_collapseDeadline == 0.0) {
            _collapseDeadline = now + kCollapseDelay;
            [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(collapseTimerFired) object:nil];
            [self performSelector:@selector(collapseTimerFired) withObject:nil afterDelay:kCollapseDelay + 0.01];
        }
        if (now < _collapseDeadline) {
            expanded = YES;
        }
    }
    if (expanded || !_expanded) {
        _collapseDeadline = 0.0;
    }

    const NSSize size = expanded ? [self cardSize] : [self pillSize];
    const BOOL raised = expanded && _pointerOnSlider && _hoverVisible;

    const CGFloat headScreenX = NSMinX(sliderScreen) + headX;
    CGFloat originX = headScreenX - size.width / 2.0;
    originX = MAX(NSMinX(sliderScreen), MIN(originX, NSMaxX(sliderScreen) - size.width));
    const CGFloat trackHalf = _pointerOnSlider ? 4.0 : 2.0;
    NSRect frame = NSMakeRect(round(originX), 0.0, size.width, size.height);
    if (expanded) {
        /* The card is temporary: it may cover the buttons row above the bar. */
        frame.origin.y = round(raised
            ? NSMaxY(sliderScreen) + kCardClearanceAboveSlider
            : NSMidY(sliderScreen) + trackHalf + kMarkerGapAboveTrack);
    } else if (![self placePillBelowTrackInFrame:&frame
                                     sliderScreen:sliderScreen
                                      headScreenX:headScreenX
                                        trackHalf:trackHalf
                                           parent:parent]) {
        frame.origin.y = round(NSMidY(sliderScreen) + trackHalf + kMarkerGapAboveTrack);
    }

    [self presentFrame:frame expanded:expanded parent:parent animated:animated];
}

/* The compact pill goes under the track (the buttons row sits above it), 6 pt
 * from it, centred on the head and kept clear of the time labels. NO when
 * there is no room (the track is the bottom-most element, or the labels leave
 * no gap): the caller puts it above. */
- (BOOL)placePillBelowTrackInFrame:(NSRect *)frame
                      sliderScreen:(NSRect)sliderScreen
                       headScreenX:(CGFloat)headScreenX
                         trackHalf:(CGFloat)trackHalf
                            parent:(NSWindow *)parent
{
    NSRect pill = *frame;
    pill.origin.y = round(NSMidY(sliderScreen) - trackHalf - kMarkerGapAboveTrack - NSHeight(pill));

    if (NSMinY(pill) < NSMinY(parent.frame)) {
        return NO;
    }
    NSView * const container = _slider.superview;
    if (container != nil) {
        const NSRect bar = [parent convertRectToScreen:[container convertRect:container.bounds toView:nil]];
        if (NSMinY(pill) < NSMinY(bar)) {
            return NO;
        }
    }

    CGFloat low = NSMinX(sliderScreen);
    CGFloat high = NSMaxX(sliderScreen) - NSWidth(pill);
    for (NSView *view in _avoidViews.allObjects) {
        if (view.window != parent || view.hiddenOrHasHiddenAncestor) {
            continue;
        }
        const NSRect label = [parent convertRectToScreen:[view convertRect:view.bounds toView:nil]];
        if (NSMaxY(label) <= NSMinY(pill) || NSMinY(label) >= NSMaxY(pill)) {
            continue;
        }
        if (NSMidX(label) < headScreenX) {
            low = MAX(low, NSMaxX(label) + 4.0);
        } else {
            high = MIN(high, NSMinX(label) - NSWidth(pill) - 4.0);
        }
    }
    if (low > high) {
        return NO;
    }
    pill.origin.x = round(MAX(low, MIN(NSMinX(pill), high)));
    *frame = pill;
    return YES;
}

- (void)collapseTimerFired
{
    [self refreshAnimated:YES];
}

- (void)presentFrame:(NSRect)frame expanded:(BOOL)expanded parent:(NSWindow *)parent animated:(BOOL)animated
{
    const BOOL reduce = MacLCDesign.reducedMotion;
    const BOOL modeChanged = expanded != _expanded || !_shown;
    const BOOL wasShown = _shown;
    _expanded = expanded;
    _root.toolTip = expanded ? nil : _summary;

    if (!wasShown) {
        [self applyChrome];
        _window.alphaValue = 0.0;
    }
    if (_window.parentWindow != parent) {
        [_window.parentWindow removeChildWindow:_window];
        [parent addChildWindow:_window ordered:NSWindowAbove];
    }

    if (modeChanged) {
        /* The size jumps; the incoming content fades in. */
        [_window setFrame:frame display:YES];
        _pill.frame = _root.bounds;
        _card.frame = _root.bounds;
        _pill.hidden = expanded;
        _card.hidden = !expanded;
        NSView * const incoming = expanded ? _card : _pill;
        if (!reduce && animated && wasShown) {
            incoming.alphaValue = 0.0;
            [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
                context.duration = MacLCDesign.motionQuickDuration;
                [incoming.animator setAlphaValue:1.0];
            }];
        } else {
            incoming.alphaValue = 1.0;
        }
        [self layoutPillLabel];
    } else if (!NSEqualRects(frame, _lastFrame)) {
        if (animated && !reduce && wasShown) {
            [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
                context.duration = MacLCDesign.motionStandardDuration;
                context.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear];
                [self->_window.animator setFrame:frame display:YES];
            }];
        } else {
            [_window setFrame:frame display:YES];
        }
        [self layoutPillLabel];
    }
    _lastFrame = frame;

    _shown = YES;
    [self updateGlyph];
    if (!wasShown) {
        [_window orderFront:nil];
        if (animated && !reduce) {
            [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
                context.duration = MacLCDesign.motionQuickDuration;
                [self->_window.animator setAlphaValue:1.0];
            }];
        } else {
            _window.alphaValue = 1.0;
        }
    }
}

/* The label sits right of the glyph and fills the rest of the pill. */
- (void)layoutPillLabel
{
    const CGFloat x = 9.0 + kGlyphSize + 5.0;
    const NSSize label = _pillLabel.fittingSize;
    _pillLabel.frame = NSMakeRect(x, (kPillHeight - label.height) / 2.0,
                                  MAX(NSWidth(_pill.bounds) - x - 6.0, 0.0), label.height);
}

- (void)hideAnimated:(BOOL)animated
{
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(collapseTimerFired) object:nil];
    _collapseDeadline = 0.0;
    if (!_shown) {
        return;
    }
    _shown = NO;
    _expanded = NO;
    _lastFrame = NSZeroRect;
    _pointerInWindow = NO;
    [self setBouncing:NO];

    if (!animated || MacLCDesign.reducedMotion) {
        [self orderOutNow];
        return;
    }
    __weak typeof(self) weakSelf = self;
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        context.duration = MacLCDesign.motionQuickDuration;
        [self->_window.animator setAlphaValue:0.0];
    } completionHandler:^{
        typeof(self) strongSelf = weakSelf;
        if (strongSelf != nil && !strongSelf->_shown) {
            [strongSelf orderOutNow];
        }
    }];
}

- (void)orderOutNow
{
    [_window.parentWindow removeChildWindow:_window];
    [_window orderOut:nil];
}

- (void)invalidate
{
    if (_invalid) {
        return;
    }
    _invalid = YES;
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    [self stopObserving];
    _shown = NO;
    [self setBouncing:NO];
    [self orderOutNow];
    _root.owner = nil;
}

@end

#pragma mark - Now Playing bar overlay

@implementation MacLCTorrentTrackOverlay

- (instancetype)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (self) {
        _headFraction = -1.0;
    }
    return self;
}

- (NSView *)hitTest:(NSPoint)point
{
    return nil;
}

- (BOOL)isOpaque
{
    return NO;
}

- (BOOL)isAccessibilityElement
{
    return NO;
}

- (void)setRanges:(NSArray<NSNumber *> *)ranges
{
    if (_ranges == ranges || [_ranges isEqualToArray:ranges]) {
        return;
    }
    _ranges = [ranges copy];
    self.needsDisplay = YES;
}

- (void)setHeadFraction:(double)headFraction
{
    if (_headFraction == headFraction) {
        return;
    }
    _headFraction = headFraction;
    self.needsDisplay = YES;
}

- (void)drawRect:(NSRect)dirtyRect
{
    NSSlider * const slider = _slider;
    NSSliderCell * const cell = slider.cell;
    if (slider == nil || cell == nil || (_ranges.count < 2 && _headFraction < 0.0)) {
        return;
    }

    const NSRect bar = [cell barRectFlipped:NO];
    const NSRect knob = [cell knobRectFlipped:NO];
    if (NSWidth(bar) <= 0.0) {
        return;
    }
    /* The knob centre travels between the bar's ends inset by half a knob.
     * Calibrate the offset on the real knob position, so that the overlay
     * lines up with whatever the system draws. */
    const CGFloat travel = MAX(NSWidth(bar) - NSWidth(knob), 1.0);
    const double span = slider.maxValue - slider.minValue;
    const double played = span > 0.0 ? (slider.doubleValue - slider.minValue) / span : 0.0;
    const CGFloat zero = NSMidX(knob) - (CGFloat)played * travel;
    const CGFloat playX = NSMidX(knob);

    const CGFloat height = 3.0;
    const CGFloat y = NSMidY(bar) - height / 2.0;
    [[NSColor.labelColor colorWithAlphaComponent:0.45] setFill];
    for (NSUInteger i = 0; i + 1 < _ranges.count; i += 2) {
        const CGFloat from = MAX(zero + (CGFloat)Clamp01(_ranges[i].doubleValue) * travel, playX);
        const CGFloat to = zero + (CGFloat)Clamp01(_ranges[i + 1].doubleValue) * travel;
        if (to - from < 1.0) {
            continue;
        }
        [[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(from, y, to - from, height)
                                         xRadius:height / 2.0
                                         yRadius:height / 2.0] fill];
    }

    if (_headFraction >= 0.0 && _headFraction < 0.999) {
        const CGFloat diameter = 5.0;
        const CGFloat x = zero + (CGFloat)Clamp01(_headFraction) * travel;
        [MacLCDesign.accent setFill];
        [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(x - diameter / 2.0, NSMidY(bar) - diameter / 2.0,
                                                           diameter, diameter)] fill];
    }
}

@end
