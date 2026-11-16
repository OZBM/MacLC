/*****************************************************************************
 * MacLCTorrentLoadingView.m: the animated "your torrent is opening" screen
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
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston MA 02110-1301, USA.
 *****************************************************************************/

#import "torrent/MacLCTorrentLoadingView.h"
#import "torrent/MacLCTorrentSwarmView.h"

#import <QuartzCore/QuartzCore.h>

#import "addons/MacLCAddons.h"
#import "addons/watch/MacLCWatchComponents.h"
#import "addons/watch/MacLCWatchPlayback.h"
#import "extensions/NSString+Helpers.h"
#import "library/VLCLibraryWindow.h"
#import "main/VLCMain.h"
#import "playqueue/VLCPlayQueueController.h"
#import "playqueue/VLCPlayerController.h"
#import "theme/MacLCDesign.h"
#import "theme/MacLCGlassView.h"
#import "torrent/MacLCTorrentMonitor.h"

#pragma mark - Small helpers

/* The story's five steps; the stage → step map is the one place that knows. */
static NSInteger MLCStepForStage(MacLCTorrentStage stage)
{
    switch (stage) {
        case MacLCTorrentStageMetadata:    return 1;
        case MacLCTorrentStageConnecting:  return 2;
        case MacLCTorrentStageDownloading:
        case MacLCTorrentStageBuffering:
        case MacLCTorrentStageStalled:     return 3;
        case MacLCTorrentStageReady:       return 4;
        case MacLCTorrentStagePlaying:     return 5;
        default:                           return 0;
    }
}

static NSAppearance *MLCDark(void)
{
    return [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
}

/* Dynamic colours are resolved here, for the dark appearance this screen
 * always has, at the moment a layer needs them. */
static CGColorRef MLCResolved(NSColor *color)
{
    __block CGColorRef resolved = NULL;
    [MLCDark() performAsCurrentDrawingAppearance:^{
        resolved = CGColorRetain(color.CGColor);
    }];
    return resolved ? (CGColorRef)CFAutorelease(resolved) : NULL;
}

static CGColorRef MLCAccent(void)      { return MLCResolved(MacLCDesign.accent); }
static CGColorRef MLCWhite(CGFloat a)  { return [NSColor colorWithWhite:1.0 alpha:a].CGColor; }
static CGColorRef MLCClear(void)       { return NSColor.clearColor.CGColor; }

static CAShapeLayer *MLCShape(void)
{
    CAShapeLayer * const layer = [CAShapeLayer layer];
    layer.fillColor = MLCClear();
    layer.strokeColor = MLCClear();
    return layer;
}

static CGPathRef MLCCirclePath(CGFloat radius)
{
    return (CGPathRef)CFAutorelease(CGPathCreateWithEllipseInRect(
        CGRectMake(-radius, -radius, 2 * radius, 2 * radius), NULL));
}

static void MLCNoActions(void (^block)(void))
{
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    block();
    [CATransaction commit];
}

static void MLCAnimated(NSTimeInterval duration, void (^block)(void))
{
    [CATransaction begin];
    [CATransaction setAnimationDuration:duration];
    [CATransaction setAnimationTimingFunction:
     [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut]];
    block();
    [CATransaction commit];
}

static NSTextField *MLCLabel(NSFont *font, CGFloat alpha, NSTextAlignment alignment)
{
    NSTextField * const label = [NSTextField labelWithString:@""];
    label.font = font;
    label.textColor = [NSColor colorWithWhite:1.0 alpha:alpha];
    label.alignment = alignment;
    label.lineBreakMode = NSLineBreakByTruncatingTail;
    label.wantsLayer = YES;
    label.translatesAutoresizingMaskIntoConstraints = NO;
    /* A long title must truncate, never widen the view (or the window). */
    [label setContentCompressionResistancePriority:100 forOrientation:NSLayoutConstraintOrientationHorizontal];
    [label setAccessibilityElement:NO];
    return label;
}

/* Numbers and words change with a 0.25 s cross-fade (also under Reduce
 * Motion: a cross-fade is not movement). */
static void MLCSetText(NSTextField *label, NSString *text)
{
    if (text == nil)
        text = @"";
    if ([label.stringValue isEqualToString:text])
        return;
    if (label.window != nil && !label.hiddenOrHasHiddenAncestor) {
        CATransition * const fade = [CATransition animation];
        fade.type = kCATransitionFade;
        fade.duration = 0.25;
        [label.layer addAnimation:fade forKey:@"mlc.text"];
    }
    label.stringValue = text;
}

static NSString *MLCCount(NSInteger n, NSString *one, NSString *many)
{
    return [NSString stringWithFormat:@"%ld %@", (long)n, n == 1 ? one : many];
}

#pragma mark - Gradient helper

@interface MacLCTorrentGradientView : NSView
@property (readonly) CAGradientLayer *gradient;
@end

@implementation MacLCTorrentGradientView
- (CALayer *)makeBackingLayer { return [CAGradientLayer layer]; }
- (CAGradientLayer *)gradient { return (CAGradientLayer *)self.layer; }
- (instancetype)initWithFrame:(NSRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        self.wantsLayer = YES;
        self.translatesAutoresizingMaskIntoConstraints = NO;
    }
    return self;
}
- (NSView *)hitTest:(NSPoint)point { return nil; }
@end

#pragma mark - Step indicator

@interface MacLCTorrentSteps : NSView
@property (nonatomic) BOOL animating;
- (void)setStep:(NSInteger)step failed:(BOOL)failed;
@end

@implementation MacLCTorrentSteps
{
    NSArray<CAShapeLayer *> *_nodes;
    NSArray<CAShapeLayer *> *_connectors;
    NSArray<CAShapeLayer *> *_checks;
    NSArray<CATextLayer *> *_labels;
    CAShapeLayer *_halo;
    NSInteger _step;
    BOOL _failed;
    CGFloat _scale;
}

- (instancetype)initWithFrame:(NSRect)frame
{
    self = [super initWithFrame:frame];
    if (self == nil)
        return nil;
    self.wantsLayer = YES;
    self.translatesAutoresizingMaskIntoConstraints = NO;
    _scale = 2.0;
    _step = -1;
    NSArray *titles = @[_NS("Find peers"), _NS("File list"), _NS("Connect"), _NS("Download"), _NS("Start")];
    NSMutableArray *nodes = [NSMutableArray array], *connectors = [NSMutableArray array],
                   *checks = [NSMutableArray array], *labels = [NSMutableArray array];
    for (NSInteger i = 0; i < 5; i++) {
        if (i > 0) {
            CAShapeLayer * const connector = MLCShape();
            connector.lineWidth = 2.0;
            connector.lineCap = kCALineCapRound;
            [self.layer addSublayer:connector];
            [connectors addObject:connector];
        }
        CAShapeLayer * const node = MLCShape();
        node.path = MLCCirclePath(1.0);
        [self.layer addSublayer:node];
        [nodes addObject:node];
        CAShapeLayer * const check = MLCShape();
        check.lineWidth = 1.8;
        check.lineCap = kCALineCapRound;
        check.lineJoin = kCALineJoinRound;
        check.strokeColor = MLCWhite(1.0);
        CGMutablePathRef p = CGPathCreateMutable();
        CGPathMoveToPoint(p, NULL, -3.2, 0.0);
        CGPathAddLineToPoint(p, NULL, -1.0, -2.4);
        CGPathAddLineToPoint(p, NULL, 3.2, 2.6);
        check.path = p;
        CGPathRelease(p);
        check.opacity = 0.0;
        [self.layer addSublayer:check];
        [checks addObject:check];
        CATextLayer * const label = [CATextLayer layer];
        label.string = titles[i];
        label.fontSize = 11.0;
        label.font = (__bridge CFTypeRef)[NSFont systemFontOfSize:11.0 weight:NSFontWeightMedium];
        label.alignmentMode = kCAAlignmentCenter;
        label.truncationMode = kCATruncationEnd;
        [self.layer addSublayer:label];
        [labels addObject:label];
    }
    _nodes = nodes; _connectors = connectors; _checks = checks; _labels = labels;
    _halo = MLCShape();
    _halo.lineWidth = 1.5;
    _halo.strokeColor = MLCAccent();
    _halo.path = MLCCirclePath(7.0);
    _halo.opacity = 0.0;
    [self.layer addSublayer:_halo];
    return self;
}

- (BOOL)isFlipped { return NO; }
- (NSView *)hitTest:(NSPoint)point { return nil; }

- (void)viewDidMoveToWindow
{
    [super viewDidMoveToWindow];
    [self viewDidChangeBackingProperties];
}

- (void)viewDidChangeBackingProperties
{
    [super viewDidChangeBackingProperties];
    _scale = self.window.backingScaleFactor ?: 2.0;
    MLCNoActions(^{
        for (CATextLayer *label in self->_labels)
            label.contentsScale = self->_scale;
    });
}

- (CGFloat)xForNode:(NSInteger)i
{
    const CGFloat w = NSWidth(self.bounds);
    const CGFloat inset = MIN(48.0, w / 10.0);
    return inset + (w - 2 * inset) * i / 4.0;
}

- (void)layout
{
    [super layout];
    const CGFloat y = NSHeight(self.bounds) - 12.0;
    MLCNoActions(^{
        for (NSInteger i = 0; i < 5; i++) {
            const CGFloat x = [self xForNode:i];
            self->_nodes[i].position = CGPointMake(x, y);
            self->_checks[i].position = CGPointMake(x, y);
            self->_labels[i].frame = CGRectMake(x - 44, y - 30, 88, 14);
            if (i > 0) {
                CGMutablePathRef p = CGPathCreateMutable();
                CGPathMoveToPoint(p, NULL, [self xForNode:i - 1] + 12, y);
                CGPathAddLineToPoint(p, NULL, x - 12, y);
                self->_connectors[i - 1].path = p;
                CGPathRelease(p);
            }
        }
        if (self->_step >= 0 && self->_step < 5)
            self->_halo.position = CGPointMake([self xForNode:self->_step], y);
    });
    [self installHalo];
}

- (void)setAnimating:(BOOL)animating
{
    if (_animating == animating)
        return;
    _animating = animating;
    [self installHalo];
}

- (void)installHalo
{
    [_halo removeAnimationForKey:@"mlc.loop"];
    if (!_animating || self.window == nil || _failed || _step < 0 || _step > 4)
        return;
    CABasicAnimation * const scale = [CABasicAnimation animationWithKeyPath:@"transform.scale"];
    scale.fromValue = @0.6;
    scale.toValue = @1.9;
    CABasicAnimation * const fade = [CABasicAnimation animationWithKeyPath:@"opacity"];
    fade.fromValue = @0.8;
    fade.toValue = @0.0;
    CAAnimationGroup * const group = [CAAnimationGroup animation];
    group.animations = @[scale, fade];
    group.duration = 1.8;
    group.repeatCount = HUGE_VALF;
    group.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
    [_halo addAnimation:group forKey:@"mlc.loop"];
}

/* step 5 (playing) means every step is done. */
- (void)setStep:(NSInteger)step failed:(BOOL)failed
{
    if (step == _step && failed == _failed)
        return;
    _step = step;
    _failed = failed;
    CGColorRef accent = MLCAccent();
    CGColorRef danger = MLCResolved(MacLCDesign.destructive);
    const CGFloat y = NSHeight(self.bounds) - 12.0;
    MLCAnimated(0.35, ^{
        for (NSInteger i = 0; i < 5; i++) {
            const BOOL done = i < step;
            const BOOL current = i == step;
            const CGFloat r = done ? 7.0 : (current ? 5.5 : 4.0);
            self->_nodes[i].transform = CATransform3DMakeScale(r, r, 1.0);
            self->_nodes[i].fillColor = done ? accent : (current ? (failed ? danger : accent) : MLCWhite(0.22));
            self->_checks[i].opacity = done ? 1.0 : 0.0;
            self->_labels[i].foregroundColor = current ? MLCWhite(0.95) : (done ? MLCWhite(0.7) : MLCWhite(0.38));
            if (i > 0)
                self->_connectors[i - 1].strokeColor = (i <= step) ? accent : MLCWhite(0.16);
        }
        self->_halo.position = CGPointMake([self xForNode:MAX(0, MIN(4, step))], y);
        self->_halo.strokeColor = failed ? danger : accent;
    });
    [self installHalo];
}

@end

#pragma mark - Progress ring

@interface MacLCTorrentRing : NSView
@property (nonatomic) double progress;
@end

@implementation MacLCTorrentRing
{
    CAShapeLayer *_track;
    CAShapeLayer *_arc;
}

- (instancetype)initWithFrame:(NSRect)frame
{
    self = [super initWithFrame:frame];
    if (self == nil)
        return nil;
    self.wantsLayer = YES;
    self.translatesAutoresizingMaskIntoConstraints = NO;
    _track = MLCShape();
    _track.lineWidth = 2.5;
    _track.strokeColor = MLCWhite(0.22);
    _arc = MLCShape();
    _arc.lineWidth = 2.5;
    _arc.lineCap = kCALineCapRound;
    _arc.strokeColor = MLCWhite(0.95);
    _arc.strokeEnd = 0.0;
    [self.layer addSublayer:_track];
    [self.layer addSublayer:_arc];
    return self;
}

- (void)layout
{
    [super layout];
    const CGFloat r = MIN(NSWidth(self.bounds), NSHeight(self.bounds)) / 2.0 - 2.0;
    const CGPoint c = CGPointMake(NSMidX(self.bounds), NSMidY(self.bounds));
    CGMutablePathRef p = CGPathCreateMutable();
    CGPathAddArc(p, NULL, c.x, c.y, r, M_PI_2, M_PI_2 - 2 * M_PI, YES);
    MLCNoActions(^{
        self->_track.frame = self.bounds;
        self->_arc.frame = self.bounds;
        self->_track.path = p;
        self->_arc.path = p;
    });
    CGPathRelease(p);
}

- (void)setProgress:(double)progress
{
    _progress = MAX(0.0, MIN(1.0, progress));
    MLCAnimated(0.25, ^{ self->_arc.strokeEnd = MAX(0.03, self->_progress); });
}

@end

#pragma mark - Stall capsule

@interface MacLCTorrentStallCapsule : NSView
- (void)updateText:(NSString *)text progress:(double)progress;
@end

@implementation MacLCTorrentStallCapsule
{
    MacLCGlassView *_glass;
    MacLCTorrentRing *_ring;
    NSTextField *_label;
}

- (instancetype)initWithFrame:(NSRect)frame
{
    self = [super initWithFrame:frame];
    if (self == nil)
        return nil;
    _glass = [[MacLCGlassView alloc] initWithFrame:self.bounds];
    _glass.forcesDarkAppearance = YES;
    _glass.cornerRadius = MacLCDesign.cornerRadiusCapsule;
    _glass.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [self addSubview:_glass];

    _ring = [[MacLCTorrentRing alloc] initWithFrame:NSZeroRect];
    _label = MLCLabel([MacLCDesign monospacedDigitFontForTextStyle:NSFontTextStyleCallout
                                                            weight:NSFontWeightMedium],
                      0.95, NSTextAlignmentLeft);
    [_glass.contentView addSubview:_ring];
    [_glass.contentView addSubview:_label];
    [NSLayoutConstraint activateConstraints:@[
        [_ring.leadingAnchor constraintEqualToAnchor:_glass.contentView.leadingAnchor constant:14],
        [_ring.centerYAnchor constraintEqualToAnchor:_glass.contentView.centerYAnchor],
        [_ring.widthAnchor constraintEqualToConstant:20],
        [_ring.heightAnchor constraintEqualToConstant:20],
        [_label.leadingAnchor constraintEqualToAnchor:_ring.trailingAnchor constant:10],
        [_label.trailingAnchor constraintEqualToAnchor:_glass.contentView.trailingAnchor constant:-18],
        [_label.centerYAnchor constraintEqualToAnchor:_glass.contentView.centerYAnchor],
    ]];
    self.accessibilityElement = YES;
    self.accessibilityRole = NSAccessibilityStaticTextRole;
    return self;
}

- (NSSize)fittingCapsuleSize
{
    return NSMakeSize(ceil(14 + 20 + 10 + _label.intrinsicContentSize.width + 18), 40);
}

- (void)updateText:(NSString *)text progress:(double)progress
{
    MLCSetText(_label, text);
    _ring.progress = progress;
    self.accessibilityLabel = text;
}

@end

#pragma mark - The overlay

@interface MacLCTorrentLoadingView ()
{
    MacLCTorrentGradientView *_base;
    NSView *_imageHost;
    NSVisualEffectView *_blur;
    MacLCTorrentGradientView *_scrim;

    NSView *_fullContainer;
    NSStackView *_titleBlock;
    NSTextField *_title;
    NSTextField *_episode;
    NSStackView *_stack;
    MacLCTorrentSwarmView *_swarm;
    NSTextField *_stageLabel;
    NSTextField *_explanation;
    NSTextField *_counters;
    MacLCTorrentSteps *_steps;
    MacLCGlassView *_cancelGlass;
    NSButton *_cancel;
    MacLCTorrentStallCapsule *_stall;

    int _mode;               /* 0 hidden, 1 full, 2 compact */
    NSUInteger _fadeToken;
    BOOL _showsFailure;
    MacLCTorrentStage _lastStage;
    NSInteger _lastStep;
    NSInteger _lastAnnouncedStep;
    NSString *_lastExplanation;
    NSURL *_loadedBackdropURL;
    MacLCWatchImageRequest *_imageRequest;
    BOOL _compactLayout;
}
@end

@implementation MacLCTorrentLoadingView

- (instancetype)initWithFrame:(NSRect)frame
{
    self = [super initWithFrame:frame];
    if (self == nil)
        return nil;
    self.wantsLayer = YES;
    self.appearance = MLCDark();
    self.hidden = YES;
    self.alphaValue = 0.0;
    _lastStep = -1;
    _lastAnnouncedStep = -1;
    _lastStage = MacLCTorrentStageUnknown;
    [self build];
    [self accessibilityOptionsChanged:nil];
    [NSWorkspace.sharedWorkspace.notificationCenter
        addObserver:self
           selector:@selector(accessibilityOptionsChanged:)
               name:NSWorkspaceAccessibilityDisplayOptionsDidChangeNotification
             object:nil];
    return self;
}

- (void)dealloc
{
    [_imageRequest cancel];
    [NSWorkspace.sharedWorkspace.notificationCenter removeObserver:self];
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (BOOL)isFlipped { return NO; }

- (void)build
{
    _fullContainer = [[NSView alloc] initWithFrame:NSZeroRect];
    _fullContainer.translatesAutoresizingMaskIntoConstraints = NO;
    _fullContainer.wantsLayer = YES;
    [self addSubview:_fullContainer];

    _base = [[MacLCTorrentGradientView alloc] initWithFrame:NSZeroRect];
    _base.gradient.colors = @[(__bridge id)[NSColor colorWithRed:0.10 green:0.11 blue:0.16 alpha:1].CGColor,
                              (__bridge id)[NSColor colorWithRed:0.02 green:0.02 blue:0.04 alpha:1].CGColor];
    _base.gradient.startPoint = CGPointMake(0.2, 1.0);
    _base.gradient.endPoint = CGPointMake(0.8, 0.0);
    _imageHost = [[NSView alloc] initWithFrame:NSZeroRect];
    _imageHost.wantsLayer = YES;
    _imageHost.translatesAutoresizingMaskIntoConstraints = NO;
    _imageHost.layer.contentsGravity = kCAGravityResizeAspectFill;
    _imageHost.layer.masksToBounds = YES;
    _imageHost.layer.opacity = 0.0;
    _blur = [[NSVisualEffectView alloc] initWithFrame:NSZeroRect];
    _blur.translatesAutoresizingMaskIntoConstraints = NO;
    _blur.material = NSVisualEffectMaterialHUDWindow;
    _blur.blendingMode = NSVisualEffectBlendingModeWithinWindow;
    _blur.state = NSVisualEffectStateActive;
    _blur.appearance = MLCDark();
    _scrim = [[MacLCTorrentGradientView alloc] initWithFrame:NSZeroRect];
    _scrim.gradient.colors = @[(__bridge id)MLCWhite(0.0), (__bridge id)MLCWhite(0.0)];
    _scrim.gradient.colors = @[(__bridge id)[NSColor colorWithWhite:0 alpha:0.30].CGColor,
                               (__bridge id)[NSColor colorWithWhite:0 alpha:0.72].CGColor];
    for (NSView *view in @[_base, _imageHost, _blur, _scrim]) {
        [_fullContainer addSubview:view];
        [NSLayoutConstraint activateConstraints:@[
            [view.leadingAnchor constraintEqualToAnchor:_fullContainer.leadingAnchor],
            [view.trailingAnchor constraintEqualToAnchor:_fullContainer.trailingAnchor],
            [view.topAnchor constraintEqualToAnchor:_fullContainer.topAnchor],
            [view.bottomAnchor constraintEqualToAnchor:_fullContainer.bottomAnchor],
        ]];
    }

    _title = MLCLabel(MacLCDesign.title2, 1.0, NSTextAlignmentCenter);
    _episode = MLCLabel(MacLCDesign.callout, 0.7, NSTextAlignmentCenter);
    _titleBlock = [NSStackView stackViewWithViews:@[_title, _episode]];
    _titleBlock.orientation = NSUserInterfaceLayoutOrientationVertical;
    _titleBlock.alignment = NSLayoutAttributeCenterX;
    _titleBlock.spacing = 2;
    _titleBlock.translatesAutoresizingMaskIntoConstraints = NO;

    _swarm = [[MacLCTorrentSwarmView alloc] initWithFrame:NSZeroRect];
    _stageLabel = MLCLabel(MacLCDesign.title3, 1.0, NSTextAlignmentCenter);
    _explanation = MLCLabel(MacLCDesign.body, 0.72, NSTextAlignmentCenter);
    _explanation.lineBreakMode = NSLineBreakByWordWrapping;
    _explanation.maximumNumberOfLines = 3;
    _counters = MLCLabel([MacLCDesign monospacedDigitFontForTextStyle:NSFontTextStyleFootnote],
                         0.6, NSTextAlignmentCenter);
    _steps = [[MacLCTorrentSteps alloc] initWithFrame:NSZeroRect];

    _cancelGlass = [[MacLCGlassView alloc] initWithFrame:NSZeroRect];
    _cancelGlass.translatesAutoresizingMaskIntoConstraints = NO;
    _cancelGlass.forcesDarkAppearance = YES;
    _cancelGlass.cornerRadius = MacLCDesign.cornerRadiusCapsule;
    _cancel = [NSButton buttonWithTitle:_NS("Cancel") target:self action:@selector(cancelPressed:)];
    _cancel.bordered = NO;
    _cancel.translatesAutoresizingMaskIntoConstraints = NO;
    _cancel.font = MacLCDesign.bodyEmphasized;
    _cancel.contentTintColor = NSColor.whiteColor;
    _cancel.toolTip = _NS("Stop and go back");
    [_cancelGlass.contentView addSubview:_cancel];
    [NSLayoutConstraint activateConstraints:@[
        [_cancel.leadingAnchor constraintEqualToAnchor:_cancelGlass.contentView.leadingAnchor constant:22],
        [_cancel.trailingAnchor constraintEqualToAnchor:_cancelGlass.contentView.trailingAnchor constant:-22],
        [_cancel.centerYAnchor constraintEqualToAnchor:_cancelGlass.contentView.centerYAnchor],
        [_cancelGlass.heightAnchor constraintEqualToConstant:32],
    ]];

    _stack = [NSStackView stackViewWithViews:@[_swarm, _stageLabel, _explanation, _counters,
                                               _steps, _cancelGlass]];
    _stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    _stack.alignment = NSLayoutAttributeCenterX;
    _stack.distribution = NSStackViewDistributionFill;
    _stack.spacing = 8;
    _stack.translatesAutoresizingMaskIntoConstraints = NO;
    [_stack setCustomSpacing:14 afterView:_swarm];
    [_stack setCustomSpacing:14 afterView:_counters];
    [_stack setCustomSpacing:14 afterView:_steps];
    [_fullContainer addSubview:_titleBlock];
    [_fullContainer addSubview:_stack];

    /* Everything that sizes or places the content is weak (<= 250): inside
     * the library window a constraint above 500 resizes the window itself, and
     * the overlay is pinned by autoresizing, not by constraints. Content is
     * centred in the safe area: the library's floating sidebar covers the left
     * of the window, and the backdrop alone extends under it. */
    NSLayoutGuide * const safe = self.safeAreaLayoutGuide;
    NSLayoutConstraint * const stackWidth = [_stack.widthAnchor constraintEqualToAnchor:safe.widthAnchor
                                                                              constant:-48];
    stackWidth.priority = 250;
    NSLayoutConstraint * const sceneHeight = [_swarm.heightAnchor constraintEqualToConstant:440];
    sceneHeight.priority = 100;
    NSLayoutConstraint * const bottom = [_stack.bottomAnchor constraintLessThanOrEqualToAnchor:safe.bottomAnchor
                                                                                       constant:-112];
    bottom.priority = 250;
    NSLayoutConstraint * const center = [_stack.centerYAnchor constraintEqualToAnchor:safe.centerYAnchor
                                                                              constant:36];
    center.priority = 200;
    NSLayoutConstraint * const titleTop = [_titleBlock.topAnchor constraintEqualToAnchor:safe.topAnchor constant:56];
    titleTop.priority = 250;
    NSLayoutConstraint * const titleWidth = [_titleBlock.widthAnchor constraintLessThanOrEqualToAnchor:safe.widthAnchor
                                                                                              constant:-96];
    titleWidth.priority = 250;
    NSLayoutConstraint * const stackTop = [_stack.topAnchor constraintGreaterThanOrEqualToAnchor:_titleBlock.bottomAnchor
                                                                                        constant:10];
    stackTop.priority = 250;
    NSLayoutConstraint * const sceneMin = [_swarm.heightAnchor constraintGreaterThanOrEqualToConstant:200];
    sceneMin.priority = 250;
    [_swarm setContentHuggingPriority:100 forOrientation:NSLayoutConstraintOrientationVertical];
    [_swarm setContentCompressionResistancePriority:100 forOrientation:NSLayoutConstraintOrientationVertical];
    [NSLayoutConstraint activateConstraints:@[
        titleTop, titleWidth,
        [_titleBlock.centerXAnchor constraintEqualToAnchor:safe.centerXAnchor],

        [_stack.centerXAnchor constraintEqualToAnchor:safe.centerXAnchor],
        [_stack.widthAnchor constraintLessThanOrEqualToConstant:640],
        stackWidth, sceneHeight, bottom, center, stackTop, sceneMin,

        [_swarm.widthAnchor constraintEqualToAnchor:_stack.widthAnchor],
        [_swarm.heightAnchor constraintLessThanOrEqualToConstant:400],
        [_explanation.widthAnchor constraintLessThanOrEqualToConstant:520],
        [_explanation.widthAnchor constraintLessThanOrEqualToAnchor:_stack.widthAnchor],
        [_steps.widthAnchor constraintEqualToAnchor:_stack.widthAnchor],
        [_steps.widthAnchor constraintLessThanOrEqualToConstant:520],
        [_steps.heightAnchor constraintEqualToConstant:44],
    ]];

    NSLayoutConstraint * const fullLeading = [_fullContainer.leadingAnchor constraintEqualToAnchor:self.leadingAnchor];
    [NSLayoutConstraint activateConstraints:@[
        fullLeading,
        [_fullContainer.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [_fullContainer.topAnchor constraintEqualToAnchor:self.topAnchor],
        [_fullContainer.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
    ]];

    _stall = [[MacLCTorrentStallCapsule alloc] initWithFrame:NSMakeRect(0, 0, 100, 40)];
    _stall.alphaValue = 0.0;
    _stall.hidden = YES;
    [self addSubview:_stall];

    self.accessibilityElement = YES;
    self.accessibilityRole = NSAccessibilityGroupRole;
    self.accessibilityLabel = _NS("Getting your video ready");
}

#pragma mark Hit testing, layout

/* The picture below is not interactive while the full screen covers it, the
 * compact capsule leaves everything but itself to the video. */
- (NSView *)hitTest:(NSPoint)point
{
    if (_mode == 0)
        return nil;
    NSView * const hit = [super hitTest:point];
    if (_mode == 2)
        return hit == _stall || [hit isDescendantOf:_stall] ? hit : nil;
    return hit ?: self;
}

- (void)mouseDown:(NSEvent *)event {}

- (void)setFrameSize:(NSSize)size
{
    [super setFrameSize:size];
    const BOOL compact = size.height > 0 && size.height < 620;
    if (compact != _compactLayout) {
        _compactLayout = compact;
        _counters.hidden = compact;
        _episode.hidden = compact || _episode.stringValue.length == 0;
        _stack.spacing = compact ? 6 : 8;
    }
}

- (void)layout
{
    [super layout];
    NSSize size = _stall.fittingCapsuleSize;
    CGFloat inset = 24.0;
    NSView * const avoided = self.avoidedView;
    if (avoided != nil && avoided.window == self.window && self.window != nil) {
        const NSRect r = [self convertRect:avoided.bounds fromView:avoided];
        inset = MAX(inset, NSMaxY(r) + 16.0);
    }
    const CGFloat wrap = MIN(520.0, NSWidth(_stack.bounds));
    if (wrap > 40 && fabs(_explanation.preferredMaxLayoutWidth - wrap) > 1.0)
        _explanation.preferredMaxLayoutWidth = wrap;
    size.width = MIN(size.width, NSWidth(self.bounds) - 32);
    _stall.frame = NSMakeRect(round((NSWidth(self.bounds) - size.width) / 2.0), round(inset),
                              size.width, size.height);
}

#pragma mark Motion, visibility

- (void)viewDidMoveToWindow
{
    [super viewDidMoveToWindow];
    [NSNotificationCenter.defaultCenter removeObserver:self
                                                  name:NSWindowDidChangeOcclusionStateNotification
                                                object:nil];
    if (self.window != nil) {
        [NSNotificationCenter.defaultCenter addObserver:self
                                               selector:@selector(occlusionChanged:)
                                                   name:NSWindowDidChangeOcclusionStateNotification
                                                 object:self.window];
        [self loadBackdropIfNeeded];
    }
    [self refreshRunning];
}

- (void)viewDidHide { [super viewDidHide]; [self refreshRunning]; }
- (void)viewDidUnhide { [super viewDidUnhide]; [self refreshRunning]; }

- (void)occlusionChanged:(NSNotification *)note
{
    [self refreshRunning];
}

- (void)accessibilityOptionsChanged:(NSNotification *)note
{
    const BOOL opaque = MacLCDesign.reduceTransparency;
    _blur.hidden = opaque;
    _imageHost.hidden = opaque;
    _scrim.gradient.colors = opaque
        ? @[(__bridge id)[NSColor colorWithWhite:0.05 alpha:1.0].CGColor,
            (__bridge id)[NSColor colorWithWhite:0.02 alpha:1.0].CGColor]
        : @[(__bridge id)[NSColor colorWithWhite:0 alpha:0.30].CGColor,
            (__bridge id)[NSColor colorWithWhite:0 alpha:0.72].CGColor];
    [self refreshRunning];
}

- (void)refreshRunning
{
    const BOOL visible = _mode == 1 && !self.hiddenOrHasHiddenAncestor && self.window != nil &&
                         (self.window.occlusionState & NSWindowOcclusionStateVisible);
    const BOOL running = visible && !MacLCDesign.reducedMotion;
    _swarm.animating = running;
    _steps.animating = running;
}

#pragma mark Backdrop

- (void)setBackdropURL:(NSURL *)backdropURL
{
    if ((_backdropURL == backdropURL) || [_backdropURL isEqual:backdropURL])
        return;
    _backdropURL = backdropURL;
    [self loadBackdropIfNeeded];
}

- (void)loadBackdropIfNeeded
{
    NSURL * const url = _backdropURL;
    if (url == nil) {
        [_imageRequest cancel];
        _imageRequest = nil;
        _loadedBackdropURL = nil;
        _imageHost.layer.contents = nil;
        _imageHost.layer.opacity = 0.0;
        return;
    }
    if ([_loadedBackdropURL isEqual:url] || self.window == nil)
        return;
    _loadedBackdropURL = url;
    [_imageRequest cancel];
    _imageRequest = nil;
    __weak MacLCTorrentLoadingView * const weakSelf = self;
    MacLCWatchImageRequest *request = nil;
    NSImage * const cached = [MacLCWatchImageCache.sharedCache
        imageForURL:url
          pointSize:NSMakeSize(960, 540)
              scale:self.window.backingScaleFactor
            request:&request
         completion:^(NSImage *image) {
        [weakSelf backdropLoaded:image forURL:url];
    }];
    _imageRequest = request;
    if (cached != nil)
        [self backdropLoaded:cached forURL:url];
}

- (void)backdropLoaded:(NSImage *)image forURL:(NSURL *)url
{
    if (image == nil || ![url isEqual:_backdropURL])
        return;
    CGImageRef cg = [image CGImageForProposedRect:NULL context:nil hints:nil];
    if (cg == NULL)
        return;
    _imageHost.layer.contents = (__bridge id)cg;
    CABasicAnimation * const fade = [CABasicAnimation animationWithKeyPath:@"opacity"];
    fade.fromValue = @(_imageHost.layer.presentationLayer.opacity);
    fade.toValue = @0.85;
    fade.duration = 0.6;
    _imageHost.layer.opacity = 0.85;
    [_imageHost.layer addAnimation:fade forKey:@"mlc.fadeIn"];
}

#pragma mark API

- (BOOL)isPresenting { return _mode != 0; }
- (BOOL)showsFailure { return _showsFailure; }

- (void)cancelPressed:(id)sender
{
    if (self.cancelHandler != nil)
        self.cancelHandler();
}

- (void)setTitleText:(NSString *)titleText
{
    _titleText = [titleText copy];
    MLCSetText(_title, titleText ?: @"");
    _title.hidden = titleText.length == 0;
}

- (void)setEpisodeText:(NSString *)episodeText
{
    _episodeText = [episodeText copy];
    MLCSetText(_episode, episodeText ?: @"");
    _episode.hidden = episodeText.length == 0 || _compactLayout;
}

- (void)fadeInIfNeeded
{
    if (!self.hidden && self.alphaValue > 0.99)
        return;
    const NSUInteger token = ++_fadeToken;
    (void)token;
    self.hidden = NO;
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        context.duration = MacLCDesign.reducedMotion ? 0.2 : 0.3;
        self.animator.alphaValue = 1.0;
    }];
}

- (void)showFullWithStage:(MacLCTorrentStage)stage
                  torrent:(MacLCTorrentInfo *)torrent
                   reader:(MacLCTorrentReaderInfo *)reader
                 dhtNodes:(NSInteger)dhtNodes
{
    if (_mode != 1) {
        _mode = 1;
        _stall.hidden = YES;
        _stall.alphaValue = 0.0;
        _fullContainer.hidden = NO;
        _lastStep = -1;
        _lastAnnouncedStep = -1;
        [self fadeInIfNeeded];
        [self loadBackdropIfNeeded];
    }
    _lastStage = stage;
    const BOOL failed = stage == MacLCTorrentStageFailed;
    _showsFailure = failed;
    const NSInteger step = MLCStepForStage(stage);

    const MacLCTorrentStage shown = stage == MacLCTorrentStageUnknown ? MacLCTorrentStageTrackers : stage;
    NSString *stageTitle = [MacLCTorrentFormat titleForStage:shown];
    NSString *explanation = torrent != nil
        ? [MacLCTorrentFormat explanationForTorrent:torrent reader:reader]
        : _NS("Asking the trackers and the network who has this.");
    MLCSetText(_stageLabel, stageTitle);
    MLCSetText(_explanation, explanation);
    MLCSetText(_counters, [self counterTextForStep:step torrent:torrent dht:dhtNodes failed:failed]);
    if (!failed)
        _cancel.title = _NS("Cancel");
    else
        _cancel.title = _NS("Close");

    [_swarm applyStage:stage torrent:torrent reader:reader dhtNodes:dhtNodes];
    [_steps setStep:step failed:failed];

    /* VoiceOver: one element, the step and its words as the value. */
    NSString * const value = [NSString stringWithFormat:@"%@. %@", stageTitle, explanation];
    self.accessibilityValue = value;
    if (step != _lastAnnouncedStep) {
        _lastAnnouncedStep = step;
        NSAccessibilityPostNotificationWithUserInfo(
            self, NSAccessibilityAnnouncementRequestedNotification,
            @{ NSAccessibilityAnnouncementKey: value,
               NSAccessibilityPriorityKey: @(NSAccessibilityPriorityMedium) });
    }
    [self refreshRunning];
}

- (NSString *)counterTextForStep:(NSInteger)step
                         torrent:(MacLCTorrentInfo *)torrent
                             dht:(NSInteger)dht
                          failed:(BOOL)failed
{
    if (failed)
        return @"";
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    if (step <= 0) {
        if (dht >= 0)
            [parts addObject:MLCCount(dht, _NS("DHT node"), _NS("DHT nodes"))];
        NSInteger answered = 0;
        for (MacLCTorrentTrackerInfo *tracker in torrent.trackers)
            if (tracker.state == MacLCTorrentTrackerStateOK)
                answered++;
        if (torrent.trackers.count > 0)
            [parts addObject:[NSString stringWithFormat:_NS("%ld of %ld trackers answered"),
                              (long)answered, (long)torrent.trackers.count]];
        return [parts componentsJoinedByString:@" · "];
    }
    if (torrent != nil && step <= 2) {
        [parts addObject:[MacLCTorrentFormat peersString:torrent]];
        if (step == 2) {
            if (torrent.peersConnecting > 0)
                [parts addObject:[NSString stringWithFormat:_NS("%ld connecting"), (long)torrent.peersConnecting]];
            if (torrent.peersUnchoked > 0)
                [parts addObject:[NSString stringWithFormat:_NS("%ld sending data"), (long)torrent.peersUnchoked]];
        }
    }
    return [parts componentsJoinedByString:@" · "];
}

- (void)showStallWithTorrent:(MacLCTorrentInfo *)torrent reader:(MacLCTorrentReaderInfo *)reader
{
    NSMutableArray<NSString *> *parts =
        [NSMutableArray arrayWithObject:[MacLCTorrentFormat titleForStage:MacLCTorrentStageStalled]];
    if (torrent != nil && torrent.peersUnchoked > 0)
        [parts addObject:[NSString stringWithFormat:_NS("%@ sending"),
                          MLCCount(torrent.peersUnchoked, _NS("peer"), _NS("peers"))]];
    else
        [parts addObject:_NS("Looking for peers")];
    if (torrent != nil && torrent.downloadRate > 0)
        [parts addObject:[MacLCTorrentFormat rateString:torrent.downloadRate]];
    NSString * const text = [parts componentsJoinedByString:@" · "];
    const double progress = reader != nil ? MIN(1.0, MAX(0.0, reader.aheadSeconds / 10.0)) : 0.0;
    [_stall updateText:text progress:progress];

    if (_mode != 2) {
        const BOOL wasFull = _mode == 1;
        _mode = 2;
        _showsFailure = NO;
        self.hidden = NO;
        self.alphaValue = 1.0;
        [self setNeedsLayout:YES];
        [self layoutSubtreeIfNeeded];
        _stall.hidden = NO;
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
            context.duration = MacLCDesign.reducedMotion ? 0.2 : 0.3;
            self->_fullContainer.animator.alphaValue = 0.0;
            self->_stall.animator.alphaValue = 1.0;
        } completionHandler:^{
            if (self->_mode == 2)
                self->_fullContainer.hidden = YES;
        }];
        (void)wasFull;
        NSAccessibilityPostNotificationWithUserInfo(
            _stall, NSAccessibilityAnnouncementRequestedNotification,
            @{ NSAccessibilityAnnouncementKey: text,
               NSAccessibilityPriorityKey: @(NSAccessibilityPriorityLow) });
    }
    [self setNeedsLayout:YES];
    [self refreshRunning];
}

- (void)hideAnimated:(BOOL)animated
{
    if (_mode == 0 && self.hidden)
        return;
    _mode = 0;
    _showsFailure = NO;
    const NSUInteger token = ++_fadeToken;
    [self refreshRunning];
    void (^finish)(void) = ^{
        if (self->_fadeToken != token)
            return;
        self.hidden = YES;
        self->_stall.hidden = YES;
        self->_fullContainer.hidden = NO;
        self->_fullContainer.alphaValue = 1.0;
        [self refreshRunning];
    };
    if (!animated || self.window == nil) {
        self.alphaValue = 0.0;
        finish();
        return;
    }
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        context.duration = 0.3;
        self.animator.alphaValue = 0.0;
    } completionHandler:finish];
}

@end

#pragma mark - The controller

@implementation MacLCTorrentLoadingController
{
    __weak NSView *_hostView;
    __weak NSView *_controlsView;
    __weak NSView *_avoidedView;
    MacLCTorrentLoadingView *_overlay;
    BOOL _dismissed;
    BOOL _hasPlayed;
    BOOL _failureLatched;
    NSTimeInterval _stalledSince;
    BOOL _debugOverlay;
    BOOL _stopped;
}

- (instancetype)initWithHostView:(NSView *)hostView
                    controlsView:(NSView *)controlsView
                     avoidedView:(NSView *)avoidedView
{
    self = [super init];
    if (self == nil)
        return nil;
    _hostView = hostView;
    _controlsView = controlsView;
    _avoidedView = avoidedView;
    _debugOverlay = [NSProcessInfo.processInfo.environment[@"MACLC_DEBUG_TORRENT_OVERLAY"] isEqualToString:@"1"];

    _overlay = [[MacLCTorrentLoadingView alloc] initWithFrame:NSZeroRect];
    /* Pinned by autoresizing (frame = bounds of the target), never by constraints. */
    _overlay.translatesAutoresizingMaskIntoConstraints = YES;
    _overlay.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    __weak MacLCTorrentLoadingController * const weakSelf = self;
    _overlay.cancelHandler = ^{ [weakSelf cancel]; };

    NSNotificationCenter * const center = NSNotificationCenter.defaultCenter;
    [center addObserver:self selector:@selector(refresh:)
                   name:MacLCTorrentMonitorDidUpdateNotification object:nil];
    [center addObserver:self selector:@selector(playerStateChanged:)
                   name:VLCPlayerStateChanged object:nil];
    [center addObserver:self selector:@selector(mediaChanged:)
                   name:VLCPlayerCurrentMediaItemChanged object:nil];
    [center addObserver:self selector:@selector(interfaceWillClose:)
                   name:NSApplicationWillTerminateNotification object:nil];
    [MacLCTorrentMonitor.sharedMonitor start];
    return self;
}

- (instancetype)initWithHostView:(NSView *)hostView controlsView:(NSView *)controlsView
{
    return [self initWithHostView:hostView controlsView:controlsView avoidedView:nil];
}

- (void)dealloc
{
    [NSNotificationCenter.defaultCenter removeObserver:self];
    [_overlay removeFromSuperview];
}

/* Nothing here may reach the player or the monitor once the interface is
 * closing: getIntf() is NULL from then on. */
- (BOOL)interfaceAlive
{
    return !_stopped && getIntf() != NULL;
}

- (void)interfaceWillClose:(NSNotification *)note
{
    _stopped = YES;
    [_overlay hideAnimated:NO];
    [_overlay removeFromSuperview];
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)cancel
{
    if (![self interfaceAlive])
        return;
    _dismissed = YES;
    if (!_overlay.showsFailure) {
        [VLCMain.sharedInstance.playQueueController.playerController stop];
    }
    _failureLatched = NO;
    [_overlay hideAnimated:YES];
}

- (void)playerStateChanged:(NSNotification *)note
{
    [self refresh:nil];
}

- (void)mediaChanged:(NSNotification *)note
{
    _dismissed = NO;
    _hasPlayed = NO;
    _failureLatched = NO;
    _stalledSince = 0;
    [self refresh:nil];
}

#pragma mark Placement

/* Over the video when that view is on screen; else over the library
 * window's content area (it shows its video only once the tracks exist). */
- (void)placeOverlay
{
    NSView * const host = _hostView;
    NSView *target = nil;
    NSView *relative = nil;
    BOOL inHost = NO;
    if (host != nil && host.window != nil && !host.hiddenOrHasHiddenAncestor) {
        target = host;
        relative = _controlsView.superview == host ? _controlsView : nil;
        inHost = YES;
    } else {
        for (NSWindow * const window in NSApp.windows) {
            if ([window isKindOfClass:VLCLibraryWindow.class] && window.isVisible) {
                target = ((VLCLibraryWindow *)window).libraryTargetView;
                break;
            }
        }
    }
    if (target == nil || target.window == nil) {
        if (_overlay.superview != nil)
            [_overlay removeFromSuperview];
        return;
    }
    NSView * const current = _overlay.superview;
    BOOL ordered = current == target;
    if (ordered) {
        NSArray<NSView *> * const subviews = target.subviews;
        const NSUInteger own = [subviews indexOfObject:_overlay];
        if (relative != nil)
            ordered = own + 1 == [subviews indexOfObject:relative];
        else
            ordered = own == subviews.count - 1;
    }
    _overlay.avoidedView = inHost ? _avoidedView : nil;
    if (ordered)
        return;
    [_overlay removeFromSuperview];
    _overlay.frame = target.bounds;
    if (relative != nil)
        [target addSubview:_overlay positioned:NSWindowBelow relativeTo:relative];
    else
        [target addSubview:_overlay positioned:NSWindowAbove relativeTo:nil];
}

#pragma mark Following the monitor

- (void)updateTitle
{
    MacLCWatchPlayback * const playback = MacLCWatchPlayback.sharedPlayback;
    MacLCAddonItem * const item = playback.currentItem;
    MacLCTorrentInfo * const torrent = MacLCTorrentMonitor.sharedMonitor.torrent;
    NSString *title = item.name;
    if (title.length == 0 && torrent.name.length > 0) {
        title = torrent.name;
        if (![title containsString:@" "])
            title = [title stringByReplacingOccurrencesOfString:@"." withString:@" "];
    }
    _overlay.titleText = title;
    _overlay.episodeText = playback.currentEpisodeText;
    _overlay.backdropURL = item.backgroundURL ?: item.posterURL;
}

- (void)refresh:(NSNotification *)note
{
    if (![self interfaceAlive])
        return;
    MacLCTorrentMonitor * const monitor = MacLCTorrentMonitor.sharedMonitor;
    const BOOL fixture = monitor.fixturePath.length > 0;
    const BOOL active = monitor.active;

    if (!active) {
        _dismissed = NO;
        _hasPlayed = NO;
        _stalledSince = 0;
        if (_failureLatched && _overlay.isPresenting)
            return;
        [_overlay hideAnimated:YES];
        return;
    }

    MacLCTorrentStage stage = monitor.stage;
    MacLCTorrentInfo * const torrent = monitor.torrent;
    MacLCTorrentReaderInfo * const reader = monitor.reader;
    if (stage == MacLCTorrentStagePlaying)
        _hasPlayed = YES;

    BOOL playerStopped = NO;
    if (!fixture) {
        VLCPlayerController * const player = VLCMain.sharedInstance.playQueueController.playerController;
        const enum vlc_player_state state = player.playerState;
        playerStopped = state == VLC_PLAYER_STATE_STOPPED || state == VLC_PLAYER_STATE_STOPPING;
    }

    if (stage == MacLCTorrentStageFailed) {
        _failureLatched = !_dismissed;
    } else if (playerStopped && !_failureLatched) {
        [_overlay hideAnimated:YES];
        return;
    }
    if (_dismissed) {
        [_overlay hideAnimated:YES];
        return;
    }

    /* The debug overlay lets a fixture show the screen with no input open. */
    (void)_debugOverlay;

    if (stage == MacLCTorrentStagePlaying) {
        [_overlay hideAnimated:YES];
        return;
    }

    /* After the first picture, trouble is a small capsule, never the full
     * screen again (a seek, a stall). */
    const BOOL trouble = stage == MacLCTorrentStageStalled || _hasPlayed;
    if (trouble && stage != MacLCTorrentStageFailed) {
        const NSTimeInterval now = CACurrentMediaTime();
        if (_stalledSince == 0)
            _stalledSince = now;
        const NSTimeInterval waited = MAX(now - _stalledSince, reader.stallDuration);
        if (waited > 1.0) {
            [self placeOverlay];
            [_overlay showStallWithTorrent:torrent reader:reader];
        } else if (!_overlay.isPresenting) {
            [_overlay hideAnimated:NO];
        }
        return;
    }
    _stalledSince = 0;

    [self placeOverlay];
    [self updateTitle];
    [_overlay showFullWithStage:stage torrent:torrent reader:reader
                       dhtNodes:monitor.snapshot.dhtNodes];
}

@end
