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

/* Slots for peers, dots for DHT nodes: the picture shows the order of
 * magnitude, the numbers are written next to it. */
static const NSInteger kSlots = 28;
static const NSInteger kDHTDots = 48;
static const NSInteger kMaxTrackers = 8;
static const CGFloat kTileSize = 64.0;

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

static double MLCHash(NSInteger i, double salt)
{
    const double v = sin((double)i * 12.9898 + salt * 78.233) * 43758.5453;
    return v - floor(v);
}

/* An SF Symbol drawn once into a bitmap (palette colour), for a CALayer. */
static CGImageRef MLCGlyph(NSString *name, CGFloat pointSize, NSFontWeight weight,
                           NSColor *color, CGFloat scale, NSSize *outSize)
{
    NSImageSymbolConfiguration *config =
        [NSImageSymbolConfiguration configurationWithPointSize:pointSize weight:weight];
    config = [config configurationByApplyingConfiguration:
              [NSImageSymbolConfiguration configurationWithPaletteColors:@[color]]];
    NSImage *image = [[NSImage imageWithSystemSymbolName:name accessibilityDescription:nil]
                      imageWithSymbolConfiguration:config];
    if (image == nil)
        return NULL;
    const NSSize size = image.size;
    const size_t w = MAX(1, (size_t)ceil(size.width * scale));
    const size_t h = MAX(1, (size_t)ceil(size.height * scale));
    CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGContextRef ctx = CGBitmapContextCreate(NULL, w, h, 8, 0, space, (CGBitmapInfo)kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(space);
    if (ctx == NULL)
        return NULL;
    NSGraphicsContext * const gc = [NSGraphicsContext graphicsContextWithCGContext:ctx flipped:NO];
    [NSGraphicsContext saveGraphicsState];
    NSGraphicsContext.currentContext = gc;
    CGContextScaleCTM(ctx, scale, scale);
    [image drawInRect:NSMakeRect(0, 0, size.width, size.height)];
    [NSGraphicsContext restoreGraphicsState];
    CGImageRef cg = CGBitmapContextCreateImage(ctx);
    CGContextRelease(ctx);
    if (outSize != NULL)
        *outSize = size;
    return cg ? (CGImageRef)CFAutorelease(cg) : NULL;
}

/* A layer showing a symbol, centred on `center`. */
static void MLCSetGlyph(CALayer *layer, NSString *name, CGFloat pt, NSFontWeight weight,
                        NSColor *color, CGFloat scale)
{
    NSSize size = NSZeroSize;
    CGImageRef image = MLCGlyph(name, pt, weight, color, scale, &size);
    layer.contents = (__bridge id)image;
    layer.contentsScale = scale;
    layer.bounds = CGRectMake(0, 0, size.width, size.height);
}

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

#pragma mark - The scene: radar, peers, document

@interface MacLCTorrentScene : NSView
/// YES while the screen is visible and Reduce Motion is off.
@property (nonatomic) BOOL animating;
- (void)applyStage:(MacLCTorrentStage)stage
           torrent:(nullable MacLCTorrentInfo *)torrent
          dhtNodes:(NSInteger)dht;
@end

@implementation MacLCTorrentScene
{
    MacLCTorrentStage _stage;
    BOOL _failed;
    BOOL _converged;
    BOOL _geometryDirty;
    CGFloat _scale;

    CALayer *_ghost;
    NSArray<CAShapeLayer *> *_ghostRings;
    NSArray<CAShapeLayer *> *_pulses;
    CALayer *_dhtGroup;
    CALayer *_trackerGroup;
    CALayer *_peerGroup;
    CALayer *_tile;
    CAShapeLayer *_tileOutline;
    CALayer *_deviceGlyph;
    CALayer *_docBadge;
    CAShapeLayer *_docOutline;
    NSArray<CAShapeLayer *> *_docLines;

    NSArray<CAShapeLayer *> *_dht;
    NSInteger _dhtShown;

    NSArray<CAShapeLayer *> *_trackerDots;
    NSArray<CAShapeLayer *> *_trackerBursts;
    NSArray<CALayer *> *_trackerGlyphs;
    NSArray<CATextLayer *> *_trackerLabels;
    NSInteger _trackerCount;
    MacLCTorrentTrackerState _trackerState[8];
    NSInteger _trackerPeers[8];
    BOOL _trackerStateKnown[8];

    NSArray<CAShapeLayer *> *_lines;
    NSArray<CAShapeLayer *> *_peerDots;
    NSArray<CAShapeLayer *> *_particlesA;
    NSArray<CAShapeLayer *> *_particlesB;
    int8_t _slotState[28];   /* -1 hidden, 0 connecting, 1 handshaking, 2 connected, 3 sending */
    BOOL _slotSeed[28];

    CGFloat _cx, _cy, _rx, _ry;
}

- (instancetype)initWithFrame:(NSRect)frame
{
    self = [super initWithFrame:frame];
    if (self == nil)
        return nil;
    self.wantsLayer = YES;
    self.translatesAutoresizingMaskIntoConstraints = NO;
    self.layer.masksToBounds = NO;
    _scale = 2.0;
    for (NSInteger i = 0; i < kSlots; i++)
        _slotState[i] = -1;
    _stage = MacLCTorrentStageUnknown;
    [self buildLayers];
    return self;
}

- (BOOL)isFlipped { return NO; }
- (NSView *)hitTest:(NSPoint)point { return nil; }

- (void)buildLayers
{
    CALayer * const root = self.layer;
    NSAppearance * const dark = MLCDark();
    (void)dark;

    _ghost = [CALayer layer];
    NSMutableArray *rings = [NSMutableArray array];
    for (NSInteger i = 0; i < 2; i++) {
        CAShapeLayer * const ring = MLCShape();
        ring.lineWidth = 1.0;
        ring.strokeColor = MLCWhite(i == 0 ? 0.05 : 0.09);
        [_ghost addSublayer:ring];
        [rings addObject:ring];
    }
    _ghostRings = rings;
    [root addSublayer:_ghost];

    NSMutableArray *pulses = [NSMutableArray array];
    for (NSInteger i = 0; i < 3; i++) {
        CAShapeLayer * const pulse = MLCShape();
        pulse.lineWidth = 1.5;
        pulse.strokeColor = MLCAccent();
        pulse.opacity = 0.0;
        [root addSublayer:pulse];
        [pulses addObject:pulse];
    }
    _pulses = pulses;

    _dhtGroup = [CALayer layer];
    NSMutableArray *dots = [NSMutableArray array];
    for (NSInteger i = 0; i < kDHTDots; i++) {
        CAShapeLayer * const dot = MLCShape();
        dot.fillColor = MLCWhite(0.7);
        dot.path = MLCCirclePath(1.8 + 1.1 * MLCHash(i, 3));
        dot.opacity = 0.45;
        dot.hidden = YES;
        [_dhtGroup addSublayer:dot];
        [dots addObject:dot];
    }
    _dht = dots;
    [root addSublayer:_dhtGroup];

    _trackerGroup = [CALayer layer];
    NSMutableArray *tDots = [NSMutableArray array], *tBursts = [NSMutableArray array],
                   *tGlyphs = [NSMutableArray array], *tLabels = [NSMutableArray array];
    for (NSInteger i = 0; i < kMaxTrackers; i++) {
        CAShapeLayer * const burst = MLCShape();
        burst.lineWidth = 1.5;
        burst.path = MLCCirclePath(8.0);
        burst.opacity = 0.0;
        CAShapeLayer * const dot = MLCShape();
        dot.lineWidth = 1.5;
        dot.path = MLCCirclePath(7.0);
        dot.hidden = YES;
        CALayer * const glyph = [CALayer layer];
        glyph.hidden = YES;
        CATextLayer * const label = [CATextLayer layer];
        label.fontSize = 11.0;
        label.font = (__bridge CFTypeRef)[NSFont systemFontOfSize:11.0 weight:NSFontWeightMedium];
        label.wrapped = YES;
        label.truncationMode = kCATruncationEnd;
        label.hidden = YES;
        [_trackerGroup addSublayer:burst];
        [_trackerGroup addSublayer:dot];
        [_trackerGroup addSublayer:glyph];
        [_trackerGroup addSublayer:label];
        [tBursts addObject:burst]; [tDots addObject:dot];
        [tGlyphs addObject:glyph]; [tLabels addObject:label];
    }
    _trackerBursts = tBursts; _trackerDots = tDots;
    _trackerGlyphs = tGlyphs; _trackerLabels = tLabels;
    [root addSublayer:_trackerGroup];

    _peerGroup = [CALayer layer];
    NSMutableArray *lines = [NSMutableArray array], *pDots = [NSMutableArray array],
                   *partA = [NSMutableArray array], *partB = [NSMutableArray array];
    for (NSInteger i = 0; i < kSlots; i++) {
        CAShapeLayer * const line = MLCShape();
        line.lineWidth = 1.2;
        line.lineCap = kCALineCapRound;
        line.opacity = 0.0;
        CAShapeLayer * const dot = MLCShape();
        dot.lineWidth = 1.8;
        dot.path = MLCCirclePath(6.0);
        dot.opacity = 0.0;
        CAShapeLayer * const a = MLCShape();
        a.fillColor = MLCWhite(0.95);
        a.path = MLCCirclePath(2.0);
        a.hidden = YES;
        CAShapeLayer * const b = MLCShape();
        b.fillColor = MLCWhite(0.95);
        b.path = MLCCirclePath(2.0);
        b.hidden = YES;
        [_peerGroup addSublayer:line];
        [_peerGroup addSublayer:a];
        [_peerGroup addSublayer:b];
        [_peerGroup addSublayer:dot];
        [lines addObject:line]; [pDots addObject:dot];
        [partA addObject:a]; [partB addObject:b];
    }
    _lines = lines; _peerDots = pDots; _particlesA = partA; _particlesB = partB;
    [root addSublayer:_peerGroup];

    _tile = [CALayer layer];
    _tile.backgroundColor = MLCWhite(0.10);
    _tile.cornerRadius = 18.0;
    _tile.cornerCurve = kCACornerCurveContinuous;
    _tile.borderColor = MLCWhite(0.22);
    _tile.borderWidth = 1.0;
    _tile.bounds = CGRectMake(0, 0, kTileSize, kTileSize);
    _deviceGlyph = [CALayer layer];
    [root addSublayer:_tile];
    [root addSublayer:_deviceGlyph];

    _docBadge = [CALayer layer];
    _docBadge.bounds = CGRectMake(0, 0, 24, 30);
    _docBadge.opacity = 0.0;
    _docOutline = MLCShape();
    _docOutline.lineWidth = 1.4;
    _docOutline.strokeColor = MLCWhite(0.85);
    _docOutline.fillColor = MLCWhite(0.14);
    _docOutline.path = (CGPathRef)CFAutorelease(CGPathCreateWithRoundedRect(
        CGRectMake(1, 1, 22, 28), 5, 5, NULL));
    [_docBadge addSublayer:_docOutline];
    NSMutableArray *docLines = [NSMutableArray array];
    for (NSInteger i = 0; i < 3; i++) {
        CAShapeLayer * const line = MLCShape();
        line.lineWidth = 2.4;
        line.lineCap = kCALineCapRound;
        line.strokeColor = MLCAccent();
        CGMutablePathRef p = CGPathCreateMutable();
        const CGFloat y = 21.0 - 6.0 * i;
        CGPathMoveToPoint(p, NULL, 6, y);
        CGPathAddLineToPoint(p, NULL, i == 2 ? 14 : 18, y);
        line.path = p;
        CGPathRelease(p);
        line.strokeEnd = 0.0;
        [_docBadge addSublayer:line];
        [docLines addObject:line];
    }
    _docLines = docLines;
    [root addSublayer:_docBadge];
}

#pragma mark Geometry

- (void)viewDidChangeBackingProperties
{
    [super viewDidChangeBackingProperties];
    _scale = self.window.backingScaleFactor ?: 2.0;
    [self refreshScaleDependentContent];
    self.needsLayout = YES;
}

- (void)viewDidMoveToWindow
{
    [super viewDidMoveToWindow];
    if (self.window != nil) {
        _scale = self.window.backingScaleFactor ?: 2.0;
        [self refreshScaleDependentContent];
    }
}

- (void)refreshScaleDependentContent
{
    MLCNoActions(^{
        for (CATextLayer *label in self->_trackerLabels)
            label.contentsScale = self->_scale;
        for (CALayer *glyph in self->_trackerGlyphs)
            glyph.contentsScale = self->_scale;
        NSString *symbol = self->_failed ? @"exclamationmark.triangle.fill" : @"laptopcomputer";
        NSColor *color = self->_failed ? [NSColor colorWithRed:1.0 green:0.45 blue:0.40 alpha:1.0]
                                       : [NSColor colorWithWhite:1.0 alpha:0.92];
        MLCSetGlyph(self->_deviceGlyph, symbol, 28.0, NSFontWeightRegular, color, self->_scale);
    });
    for (NSInteger i = 0; i < _trackerCount; i++)
        [self styleTracker:i animated:NO];
}

- (void)layout
{
    [super layout];
    const CGFloat w = NSWidth(self.bounds), h = NSHeight(self.bounds);
    _cx = w / 2.0;
    _cy = h / 2.0;
    _rx = MAX(60.0, MIN(w / 2.0 - 150.0, 270.0));
    _ry = MAX(40.0, h / 2.0 - 36.0);
    const CGPoint c = CGPointMake(_cx, _cy);
    const CGRect all = CGRectMake(0, 0, w, h);

    MLCNoActions(^{
        for (CALayer *group in @[self->_ghost, self->_dhtGroup, self->_trackerGroup, self->_peerGroup]) {
            group.bounds = all;
            group.position = c;
        }
        for (NSInteger i = 0; i < 2; i++) {
            const CGFloat s = i == 0 ? 0.55 : 1.0;
            CAShapeLayer * const ring = self->_ghostRings[i];
            ring.frame = all;
            ring.path = (CGPathRef)CFAutorelease(CGPathCreateWithEllipseInRect(
                CGRectMake(c.x - self->_rx * s, c.y - self->_ry * s, 2 * self->_rx * s, 2 * self->_ry * s), NULL));
        }
        for (CAShapeLayer *pulse in self->_pulses) {
            pulse.bounds = CGRectMake(0, 0, 2 * self->_rx, 2 * self->_ry);
            pulse.position = c;
            pulse.path = (CGPathRef)CFAutorelease(CGPathCreateWithEllipseInRect(pulse.bounds, NULL));
        }
        self->_tile.position = c;
        self->_deviceGlyph.position = c;
        self->_docBadge.position = CGPointMake(c.x + 34, c.y + 38);

        for (NSInteger i = 0; i < kDHTDots; i++) {
            const double angle = i * 2.399963 + 0.7;
            const double f = 0.30 + 0.66 * sqrt(fmod(i * 0.61803 + 0.21, 1.0));
            self->_dht[i].position = CGPointMake(c.x + self->_rx * f * cos(angle),
                                                 c.y + self->_ry * f * sin(angle));
        }
        for (NSInteger i = 0; i < kSlots; i++)
            [self layoutSlot:i];
        [self layoutTrackers];
    });
    [self installLoops];
}

- (CGPoint)slotPoint:(NSInteger)i
{
    const double angle = i * 2.399963 + 0.4;
    const double f = 0.40 + 0.46 * fmod(i * 0.381966 + 0.13, 1.0);
    double dx = _rx * f * cos(angle), dy = _ry * f * sin(angle);
    const double d = hypot(dx, dy), minD = 56.0;
    if (d < minD && d > 0.001) {
        dx *= minD / d;
        dy *= minD / d;
    }
    return CGPointMake(_cx + dx, _cy + dy);
}

- (void)layoutSlot:(NSInteger)i
{
    const CGPoint p = [self slotPoint:i];
    const CGPoint c = CGPointMake(_cx, _cy);
    const double d = hypot(p.x - c.x, p.y - c.y);
    const double ux = d > 0 ? (p.x - c.x) / d : 1, uy = d > 0 ? (p.y - c.y) / d : 0;
    CAShapeLayer * const line = _lines[i];
    line.frame = CGRectMake(0, 0, NSWidth(self.bounds), NSHeight(self.bounds));
    CGMutablePathRef path = CGPathCreateMutable();
    CGPathMoveToPoint(path, NULL, c.x + ux * 38, c.y + uy * 38);
    CGPathAddLineToPoint(path, NULL, p.x - ux * 8, p.y - uy * 8);
    line.path = path;
    CGPathRelease(path);
    _peerDots[i].position = p;
}

- (void)layoutTrackers
{
    const NSInteger n = _trackerCount;
    const CGPoint c = CGPointMake(_cx, _cy);
    for (NSInteger i = 0; i < kMaxTrackers; i++) {
        const BOOL on = i < n;
        _trackerDots[i].hidden = !on;
        _trackerGlyphs[i].hidden = !on;
        _trackerLabels[i].hidden = !on;
        if (!on)
            continue;
        const double theta = M_PI_2 - i * 2.0 * M_PI / n - (n > 1 ? M_PI / n : 0.0);
        const CGPoint p = CGPointMake(c.x + _rx * cos(theta), c.y + _ry * sin(theta));
        _trackerDots[i].position = p;
        _trackerBursts[i].position = p;
        _trackerGlyphs[i].position = p;
        [self positionLabel:i around:p cosine:cos(theta) sine:sin(theta)];
    }
}

- (void)positionLabel:(NSInteger)i around:(CGPoint)p cosine:(double)cs sine:(double)sn
{
    CATextLayer * const label = _trackerLabels[i];
    const NSInteger lines = [label.string isKindOfClass:NSString.class] &&
                            [(NSString *)label.string containsString:@"\n"] ? 2 : 1;
    const CGFloat width = 150.0, height = 14.0 * lines;
    CGRect frame;
    if (cs > 0.3) {
        label.alignmentMode = kCAAlignmentLeft;
        frame = CGRectMake(p.x + 16, p.y - height / 2.0, width, height);
    } else if (cs < -0.3) {
        label.alignmentMode = kCAAlignmentRight;
        frame = CGRectMake(p.x - 16 - width, p.y - height / 2.0, width, height);
    } else {
        label.alignmentMode = kCAAlignmentCenter;
        frame = sn > 0 ? CGRectMake(p.x - width / 2.0, p.y + 13, width, height)
                       : CGRectMake(p.x - width / 2.0, p.y - 13 - height, width, height);
    }
    label.frame = frame;
}

#pragma mark Continuous animations

- (void)setAnimating:(BOOL)animating
{
    if (_animating == animating)
        return;
    _animating = animating;
    [self installLoops];
}

/* Removes every looping animation, and puts them back when the screen is
 * visible and motion is allowed. They are state-free: what a loop shows
 * (colours, which layers exist) is driven by the model values, not by them. */
- (void)installLoops
{
    NSArray<CALayer *> *looping = [self loopingLayers];
    for (CALayer *layer in looping) {
        [layer removeAnimationForKey:@"mlc.loop"];
        [layer removeAnimationForKey:@"mlc.loop2"];
    }
    if (!_animating || self.window == nil || NSWidth(self.bounds) < 10)
        return;

    for (NSInteger i = 0; i < 3; i++) {
        CABasicAnimation * const scale = [CABasicAnimation animationWithKeyPath:@"transform.scale"];
        scale.fromValue = @0.14;
        scale.toValue = @1.0;
        CABasicAnimation * const fade = [CABasicAnimation animationWithKeyPath:@"opacity"];
        fade.fromValue = @0.55;
        fade.toValue = @0.0;
        CAAnimationGroup * const group = [CAAnimationGroup animation];
        group.animations = @[scale, fade];
        group.duration = 3.6;
        group.repeatCount = HUGE_VALF;
        group.timeOffset = i * 1.2;
        group.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
        [_pulses[i] addAnimation:group forKey:@"mlc.loop"];
    }

    for (NSInteger i = 0; i < kDHTDots; i++) {
        CABasicAnimation * const twinkle = [CABasicAnimation animationWithKeyPath:@"opacity"];
        twinkle.fromValue = @(0.25 + 0.15 * MLCHash(i, 5));
        twinkle.toValue = @(0.65 + 0.2 * MLCHash(i, 6));
        twinkle.duration = 1.4 + 2.2 * MLCHash(i, 7);
        twinkle.autoreverses = YES;
        twinkle.repeatCount = HUGE_VALF;
        twinkle.timeOffset = 2.0 * MLCHash(i, 8);
        [_dht[i] addAnimation:twinkle forKey:@"mlc.loop"];
    }

    for (NSInteger i = 0; i < kSlots; i++) {
        CABasicAnimation * const march = [CABasicAnimation animationWithKeyPath:@"lineDashPhase"];
        march.fromValue = @0;
        march.toValue = @-9;
        march.duration = 0.7;
        march.repeatCount = HUGE_VALF;
        [_lines[i] addAnimation:march forKey:@"mlc.loop"];

        const CGPoint p = [self slotPoint:i];
        const double d = hypot(p.x - _cx, p.y - _cy);
        const double ux = d > 0 ? (p.x - _cx) / d : 1, uy = d > 0 ? (p.y - _cy) / d : 0;
        const CGPoint start = CGPointMake(p.x - ux * 8, p.y - uy * 8);
        const CGPoint end = CGPointMake(_cx + ux * 38, _cy + uy * 38);
        for (NSInteger k = 0; k < 2; k++) {
            CABasicAnimation * const move = [CABasicAnimation animationWithKeyPath:@"position"];
            move.fromValue = [NSValue valueWithPoint:NSPointFromCGPoint(start)];
            move.toValue = [NSValue valueWithPoint:NSPointFromCGPoint(end)];
            CAKeyframeAnimation * const fade = [CAKeyframeAnimation animationWithKeyPath:@"opacity"];
            fade.values = @[@0.0, @1.0, @1.0, @0.0];
            fade.keyTimes = @[@0.0, @0.12, @0.85, @1.0];
            CAAnimationGroup * const group = [CAAnimationGroup animation];
            group.animations = @[move, fade];
            group.duration = 1.5;
            group.repeatCount = HUGE_VALF;
            group.timeOffset = k * 0.75 + 0.2 * MLCHash(i, 9);
            [(k == 0 ? _particlesA : _particlesB)[i] addAnimation:group forKey:@"mlc.loop"];
        }
    }

    for (NSInteger i = 0; i < kMaxTrackers; i++) {
        if (i < _trackerCount && _trackerState[i] == MacLCTorrentTrackerStateUpdating)
            [self addBreathe:_trackerDots[i]];
    }

    [self installDocLoops];
}

- (NSArray<CALayer *> *)loopingLayers
{
    NSMutableArray *all = [NSMutableArray array];
    [all addObjectsFromArray:_pulses];
    [all addObjectsFromArray:_dht];
    [all addObjectsFromArray:_lines];
    [all addObjectsFromArray:_particlesA];
    [all addObjectsFromArray:_particlesB];
    [all addObjectsFromArray:_trackerDots];
    [all addObjectsFromArray:_docLines];
    return all;
}

- (void)addBreathe:(CALayer *)layer
{
    if (!_animating || self.window == nil)
        return;
    CABasicAnimation * const breathe = [CABasicAnimation animationWithKeyPath:@"opacity"];
    breathe.fromValue = @0.45;
    breathe.toValue = @1.0;
    breathe.duration = 0.8;
    breathe.autoreverses = YES;
    breathe.repeatCount = HUGE_VALF;
    [layer addAnimation:breathe forKey:@"mlc.loop"];
}

/* The document's lines fill one after the other, over and over: no byte
 * count exists for the list of files, so the fill is indeterminate. */
- (void)installDocLoops
{
    if (_stage != MacLCTorrentStageMetadata)
        return;
    for (NSInteger i = 0; i < 3; i++) {
        CABasicAnimation * const fill = [CABasicAnimation animationWithKeyPath:@"strokeEnd"];
        fill.fromValue = @0.0;
        fill.toValue = @1.0;
        fill.duration = 1.0;
        fill.beginTime = 0;
        fill.fillMode = kCAFillModeForwards;
        CAAnimationGroup * const group = [CAAnimationGroup animation];
        group.animations = @[fill];
        group.duration = 2.1;
        group.repeatCount = HUGE_VALF;
        group.timeOffset = 2.1 - 0.35 * i;
        fill.beginTime = 0;
        [_docLines[i] addAnimation:group forKey:@"mlc.loop"];
    }
}

#pragma mark State

- (void)applyStage:(MacLCTorrentStage)stage
           torrent:(MacLCTorrentInfo *)torrent
          dhtNodes:(NSInteger)dht
{
    const BOOL stageChanged = stage != _stage;
    const MacLCTorrentStage previous = _stage;
    _stage = stage;
    const BOOL failed = stage == MacLCTorrentStageFailed;
    if (failed != _failed) {
        _failed = failed;
        [self refreshScaleDependentContent];
        MLCNoActions(^{
            self->_tile.borderColor = failed ? MLCResolved(MacLCDesign.destructive) : MLCWhite(0.22);
        });
    }

    const NSInteger step = MLCStepForStage(stage);
    const BOOL early = step <= 1;

    MLCAnimated(0.45, ^{
        const CGFloat pulses = failed ? 0.0 : (early ? 1.0 : (step == 2 ? 0.35 : 0.0));
        for (CAShapeLayer *layer in self->_ghostRings)
            layer.opacity = 1.0;
        /* The pulse layers' model opacity stays 0: the loop drives it; its
         * visibility is the group's. */
        (void)pulses;
        self->_dhtGroup.opacity = failed ? 0.2 : (step >= 3 ? 0.5 : 1.0);
        self->_trackerGroup.opacity = failed ? 0.3 : (step >= 3 ? 0.5 : 1.0);
        self->_peerGroup.opacity = failed ? 0.3 : 1.0;
    });
    MLCAnimated(0.45, ^{
        const CGFloat pulses = failed ? 0.0 : (early ? 1.0 : (step == 2 ? 0.35 : 0.0));
        for (CAShapeLayer *pulse in self->_pulses)
            pulse.strokeColor = MLCResolved([MacLCDesign.accent colorWithAlphaComponent:pulses]);
    });

    [self applyDocBadgeForStep:step previous:previous animated:stageChanged];

    /* Trackers. */
    NSArray<MacLCTorrentTrackerInfo *> *trackers = torrent.trackers ?: @[];
    const NSInteger count = MIN((NSInteger)trackers.count, kMaxTrackers);
    if (count != _trackerCount) {
        _trackerCount = count;
        for (NSInteger i = 0; i < kMaxTrackers; i++)
            _trackerStateKnown[i] = NO;
        MLCNoActions(^{ [self layoutTrackers]; });
    }
    for (NSInteger i = 0; i < count; i++) {
        MacLCTorrentTrackerInfo * const info = trackers[i];
        const BOOL changed = !_trackerStateKnown[i] || _trackerState[i] != info.state ||
                             _trackerPeers[i] != info.peers;
        if (!changed)
            continue;
        const BOOL becameOK = _trackerStateKnown[i] && _trackerState[i] != MacLCTorrentTrackerStateOK &&
                              info.state == MacLCTorrentTrackerStateOK;
        _trackerState[i] = info.state;
        _trackerPeers[i] = info.peers;
        const BOOL first = !_trackerStateKnown[i];
        _trackerStateKnown[i] = YES;
        [self styleTracker:i animated:YES];
        if (first)
            [self popIn:_trackerDots[i] delay:0.06 * i];
        if (becameOK)
            [self burst:i];
        [self->_trackerDots[i] removeAnimationForKey:@"mlc.loop"];
        if (info.state == MacLCTorrentTrackerStateUpdating)
            [self addBreathe:_trackerDots[i]];
    }

    [self applyDHT:dht];
    [self applyPeers:torrent stage:stage];
    [self setConverged:stage == MacLCTorrentStageReady];
}

- (void)styleTracker:(NSInteger)i animated:(BOOL)animated
{
    if (i >= _trackerCount)
        return;
    const MacLCTorrentTrackerState state = _trackerState[i];
    CAShapeLayer * const dot = _trackerDots[i];
    CATextLayer * const label = _trackerLabels[i];
    CALayer * const glyph = _trackerGlyphs[i];
    CGColorRef accent = MLCAccent();
    CGColorRef fill = MLCClear(), stroke = MLCWhite(0.3), text = MLCWhite(0.4);
    NSString *symbol = nil;
    switch (state) {
        case MacLCTorrentTrackerStateOK:
            fill = accent; stroke = accent; text = MLCWhite(0.92); symbol = @"checkmark";
            break;
        case MacLCTorrentTrackerStateError:
            fill = MLCWhite(0.16); stroke = MLCWhite(0.3); text = MLCWhite(0.4); symbol = @"exclamationmark";
            break;
        case MacLCTorrentTrackerStateUpdating:
            stroke = accent; text = MLCWhite(0.7);
            break;
        case MacLCTorrentTrackerStateIdle:
            break;
    }
    MacLCTorrentTrackerInfo * const info = nil;
    (void)info;
    MLCAnimated(animated ? 0.35 : 0.0, ^{
        dot.fillColor = fill;
        dot.strokeColor = stroke;
        label.foregroundColor = text;
    });
    MLCNoActions(^{
        if (symbol != nil) {
            MLCSetGlyph(glyph, symbol, 9.0, NSFontWeightBold,
                        [NSColor colorWithWhite:1.0 alpha:state == MacLCTorrentTrackerStateOK ? 1.0 : 0.75],
                        self->_scale);
            glyph.position = dot.position;
            glyph.hidden = NO;
        } else {
            glyph.hidden = YES;
        }
    });
}

- (void)setTrackerHosts:(NSArray<MacLCTorrentTrackerInfo *> *)trackers
{
    for (NSInteger i = 0; i < _trackerCount && i < (NSInteger)trackers.count; i++) {
        MacLCTorrentTrackerInfo * const info = trackers[i];
        NSString *text = info.host.length > 0 ? info.host : info.URL;
        if (info.state == MacLCTorrentTrackerStateOK && info.peers >= 0)
            text = [text stringByAppendingFormat:@"\n%@", MLCCount(info.peers, _NS("peer"), _NS("peers"))];
        CATextLayer * const label = _trackerLabels[i];
        if ([label.string isEqual:text])
            continue;
        MLCNoActions(^{
            label.string = text;
            const double theta = M_PI_2 - i * 2.0 * M_PI / self->_trackerCount -
                                 (self->_trackerCount > 1 ? M_PI / self->_trackerCount : 0.0);
            [self positionLabel:i around:self->_trackerDots[i].position
                         cosine:cos(theta) sine:sin(theta)];
        });
    }
}

- (void)popIn:(CALayer *)layer delay:(NSTimeInterval)delay
{
    if (MacLCDesign.reducedMotion || self.window == nil) {
        CABasicAnimation * const fade = [CABasicAnimation animationWithKeyPath:@"opacity"];
        fade.fromValue = @0.0;
        fade.toValue = @1.0;
        fade.duration = 0.2;
        [layer addAnimation:fade forKey:@"mlc.pop"];
        return;
    }
    CASpringAnimation * const spring = [MacLCDesign emphasizedSpringForKeyPath:@"transform.scale"];
    spring.fromValue = @0.0;
    spring.toValue = @1.0;
    spring.beginTime = CACurrentMediaTime() + delay;
    spring.fillMode = kCAFillModeBackwards;
    [layer addAnimation:spring forKey:@"mlc.pop"];
}

- (void)burst:(NSInteger)i
{
    if (MacLCDesign.reducedMotion || self.window == nil)
        return;
    CAShapeLayer * const burst = _trackerBursts[i];
    burst.strokeColor = MLCAccent();
    CABasicAnimation * const scale = [CABasicAnimation animationWithKeyPath:@"transform.scale"];
    scale.fromValue = @1.0;
    scale.toValue = @3.2;
    CABasicAnimation * const fade = [CABasicAnimation animationWithKeyPath:@"opacity"];
    fade.fromValue = @0.8;
    fade.toValue = @0.0;
    CAAnimationGroup * const group = [CAAnimationGroup animation];
    group.animations = @[scale, fade];
    group.duration = 0.8;
    group.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
    [burst addAnimation:group forKey:@"mlc.burst"];
}

- (void)applyDHT:(NSInteger)dht
{
    const NSInteger n = dht < 0 ? 0 : MIN(dht, kDHTDots);
    if (n == _dhtShown)
        return;
    const NSInteger old = _dhtShown;
    _dhtShown = n;
    /* hidden, not opacity: the twinkle loop would override an opacity of 0. */
    MLCNoActions(^{
        for (NSInteger i = 0; i < kDHTDots; i++)
            self->_dht[i].hidden = i >= n;
    });
    for (NSInteger i = old; i < n; i++) {
        if (i >= kDHTDots)
            break;
        [self popIn:_dht[i] delay:0.025 * (i - old)];
    }
}

- (void)applyPeers:(MacLCTorrentInfo *)torrent stage:(MacLCTorrentStage)stage
{
    int8_t states[28];
    BOOL seeds[28];
    for (NSInteger i = 0; i < kSlots; i++) {
        states[i] = -1;
        seeds[i] = NO;
    }
    NSInteger idx = 0;
    if (torrent != nil && !_failed) {
        const NSInteger sending = MAX(0, torrent.peersUnchoked);
        const NSInteger connected = MAX(0, torrent.peers - sending);
        const NSInteger runs[4] = { sending, connected, MAX(0, torrent.peersHandshaking),
                                    MAX(0, torrent.peersConnecting) };
        const int8_t kinds[4] = { 3, 2, 1, 0 };
        for (NSInteger r = 0; r < 4; r++)
            for (NSInteger k = 0; k < runs[r] && idx < kSlots; k++)
                states[idx++] = kinds[r];
        NSInteger remainingSeeds = MAX(0, torrent.seeds);
        for (NSInteger i = 0; i < idx && remainingSeeds > 0; i++) {
            if (states[i] >= 2) {
                seeds[i] = YES;
                remainingSeeds--;
            }
        }
    }

    const BOOL linesOn = MLCStepForStage(stage) >= 2 && !_failed;
    const BOOL reduced = MacLCDesign.reducedMotion;
    CGColorRef accent = MLCAccent();
    NSInteger arrivals = 0;

    for (NSInteger i = 0; i < kSlots; i++) {
        CAShapeLayer * const dot = _peerDots[i];
        CAShapeLayer * const line = _lines[i];
        const int8_t was = _slotState[i];
        const int8_t now = states[i];
        const BOOL wasSeed = _slotSeed[i];
        const BOOL on = now >= 0;

        if (now != was || seeds[i] != wasSeed) {
            CGColorRef color = MLCWhite(0.35);
            CGColorRef lineColor = MLCWhite(0.25);
            NSArray *dash = @[@4, @5];
            switch (now) {
                case 1: color = accent; lineColor = MLCResolved([MacLCDesign.accent colorWithAlphaComponent:0.6]); break;
                case 2: color = MLCWhite(0.88); lineColor = MLCWhite(0.35); dash = nil; break;
                case 3: color = accent; lineColor = MLCResolved([MacLCDesign.accent colorWithAlphaComponent:0.75]); dash = nil; break;
                default: break;
            }
            const BOOL isSeed = seeds[i];
            MLCAnimated(0.3, ^{
                dot.strokeColor = on ? color : MLCClear();
                dot.fillColor = on ? (isSeed ? color : MLCResolved([NSColor colorWithWhite:0.0 alpha:0.35])) : MLCClear();
                line.strokeColor = lineColor;
            });
            line.lineDashPattern = dash;
            _slotState[i] = now;
            _slotSeed[i] = seeds[i];
            if (on && was < 0) {
                arrivals++;
                [self flyIn:dot slot:i order:arrivals reduced:reduced];
            }
            /* Particles run only along lines that carry data. */
            const BOOL sending = now == 3;
            MLCNoActions(^{
                self->_particlesA[i].hidden = !sending;
                self->_particlesB[i].hidden = !sending;
            });
        }
        const float dotOpacity = on ? 1.0f : 0.0f;
        const float lineOpacity = (on && linesOn) ? 1.0f : 0.0f;
        if (dot.opacity != dotOpacity || line.opacity != lineOpacity) {
            MLCAnimated(0.35, ^{
                dot.opacity = dotOpacity;
                line.opacity = lineOpacity;
            });
        }
    }
}

/* A peer that answered flies in from outside the picture. */
- (void)flyIn:(CALayer *)dot slot:(NSInteger)slot order:(NSInteger)order reduced:(BOOL)reduced
{
    if (self.window == nil)
        return;
    if (reduced) {
        CABasicAnimation * const fade = [CABasicAnimation animationWithKeyPath:@"opacity"];
        fade.fromValue = @0.0;
        fade.toValue = @1.0;
        fade.duration = 0.25;
        [dot addAnimation:fade forKey:@"mlc.fly"];
        return;
    }
    const CGPoint p = [self slotPoint:slot];
    const double d = hypot(p.x - _cx, p.y - _cy);
    const double ux = d > 0 ? (p.x - _cx) / d : 1, uy = d > 0 ? (p.y - _cy) / d : 0;
    const CGPoint from = CGPointMake(p.x + ux * 90, p.y + uy * 70);
    CASpringAnimation * const move = [MacLCDesign emphasizedSpringForKeyPath:@"position"];
    move.fromValue = [NSValue valueWithPoint:NSPointFromCGPoint(from)];
    move.toValue = [NSValue valueWithPoint:NSPointFromCGPoint(p)];
    move.beginTime = CACurrentMediaTime() + MIN(0.6, 0.04 * order);
    move.fillMode = kCAFillModeBackwards;
    [dot addAnimation:move forKey:@"mlc.fly"];
}

- (void)applyDocBadgeForStep:(NSInteger)step previous:(MacLCTorrentStage)previous animated:(BOOL)animated
{
    const BOOL known = step >= 2;
    const CGFloat opacity = _failed ? 0.0 : (step == 1 ? 1.0 : (known ? 0.8 : 0.0));
    MLCAnimated(0.4, ^{
        self->_docBadge.opacity = opacity;
        for (CAShapeLayer *line in self->_docLines)
            line.strokeEnd = known ? 1.0 : 0.0;
    });
    if (animated) {
        for (CAShapeLayer *line in _docLines)
            [line removeAnimationForKey:@"mlc.loop"];
        [self installDocLoops];
    }
}

/* Ready: everything converges into the device and fades into the picture. */
- (void)setConverged:(BOOL)converged
{
    if (converged == _converged)
        return;
    _converged = converged;
    const BOOL reduced = MacLCDesign.reducedMotion;
    MLCAnimated(converged ? 0.4 : 0.3, ^{
        for (CALayer *group in @[self->_dhtGroup, self->_trackerGroup, self->_peerGroup]) {
            if (!reduced)
                group.transform = converged ? CATransform3DMakeScale(0.08, 0.08, 1.0) : CATransform3DIdentity;
            if (converged)
                group.opacity = 0.0;
        }
        self->_ghost.opacity = converged ? 0.0 : 1.0;
        self->_docBadge.opacity = converged ? 0.0 : self->_docBadge.opacity;
    });
    if (!converged) {
        MLCAnimated(0.3, ^{
            self->_dhtGroup.opacity = 1.0;
            self->_trackerGroup.opacity = 1.0;
            self->_peerGroup.opacity = 1.0;
        });
        return;
    }
    if (!reduced && self.window != nil) {
        CAKeyframeAnimation * const pulse = [CAKeyframeAnimation animationWithKeyPath:@"transform.scale"];
        pulse.values = @[@1.0, @1.1, @1.0];
        pulse.keyTimes = @[@0.0, @0.55, @1.0];
        pulse.duration = 0.5;
        [_tile addAnimation:pulse forKey:@"mlc.ready"];
        [_deviceGlyph addAnimation:pulse forKey:@"mlc.ready"];
    }
}

- (void)setTrackersLabelsFromTorrent:(MacLCTorrentInfo *)torrent
{
    [self setTrackerHosts:torrent.trackers ?: @[]];
}

@end

#pragma mark - The film strip: what has arrived, what the player waits for

@interface MacLCTorrentFilmStrip : NSView
@property (nonatomic) BOOL animating;
- (void)applyReader:(nullable MacLCTorrentReaderInfo *)reader
            torrent:(nullable MacLCTorrentInfo *)torrent;
@end

@implementation MacLCTorrentFilmStrip
{
    CAShapeLayer *_frame;
    NSArray<CALayer *> *_ranges;
    CAShapeLayer *_window;
    CAShapeLayer *_tail;
    CAShapeLayer *_callout;
    CALayer *_barTrack;
    CALayer *_glow;
    CALayer *_fill;
    CAGradientLayer *_shimmer;
    CALayer *_perforationsTop;
    CALayer *_perforationsBottom;
    CATextLayer *_startCaption;
    CATextLayer *_tailCaption;

    NSTextField *_percent;
    NSTextField *_detail;
    NSTextField *_remaining;

    CGFloat _scale;
    double _progress;
    double _windowFraction;
    double _tailFraction;
    BOOL _hasNeed;
    NSTimeInterval _tailSeenAt;
    BOOL _tailCaptionShown;
    NSArray<NSNumber *> *_rangeFractions;
    uint64_t _readerSize;
    BOOL _built;
}

- (instancetype)initWithFrame:(NSRect)frame
{
    self = [super initWithFrame:frame];
    if (self == nil)
        return nil;
    self.wantsLayer = YES;
    self.translatesAutoresizingMaskIntoConstraints = NO;
    _scale = 2.0;
    [self build];
    return self;
}

- (BOOL)isFlipped { return NO; }
- (NSView *)hitTest:(NSPoint)point { return nil; }

static CALayer *MLCPerforations(void)
{
    CAReplicatorLayer * const rep = [CAReplicatorLayer layer];
    CALayer * const hole = [CALayer layer];
    hole.backgroundColor = MLCWhite(0.2);
    hole.cornerRadius = 1.2;
    hole.bounds = CGRectMake(0, 0, 5, 3);
    hole.anchorPoint = CGPointMake(0, 0);
    [rep addSublayer:hole];
    rep.instanceTransform = CATransform3DMakeTranslation(11, 0, 0);
    return rep;
}

- (void)build
{
    CALayer * const root = self.layer;
    _frame = MLCShape();
    _frame.fillColor = MLCWhite(0.06);
    _frame.strokeColor = MLCWhite(0.14);
    _frame.lineWidth = 1.0;
    [root addSublayer:_frame];
    _perforationsTop = MLCPerforations();
    _perforationsBottom = MLCPerforations();
    [root addSublayer:_perforationsTop];
    [root addSublayer:_perforationsBottom];

    NSMutableArray *ranges = [NSMutableArray array];
    for (NSInteger i = 0; i < 64; i++) {
        CALayer * const r = [CALayer layer];
        r.backgroundColor = MLCWhite(0.42);
        r.cornerRadius = 3.0;
        r.hidden = YES;
        r.anchorPoint = CGPointMake(0, 0);
        [root addSublayer:r];
        [ranges addObject:r];
    }
    _ranges = ranges;

    _window = MLCShape();
    _window.lineWidth = 1.5;
    _window.strokeColor = MLCAccent();
    _window.fillColor = MLCResolved([MacLCDesign.accent colorWithAlphaComponent:0.18]);
    _tail = MLCShape();
    _tail.lineWidth = 1.2;
    _tail.lineDashPattern = @[@3, @3];
    _tail.strokeColor = MLCAccent();
    _tail.fillColor = MLCResolved([MacLCDesign.accent colorWithAlphaComponent:0.12]);
    _tail.opacity = 0.0;
    _callout = MLCShape();
    _callout.lineWidth = 1.0;
    _callout.strokeColor = MLCResolved([MacLCDesign.accent colorWithAlphaComponent:0.4]);
    _callout.fillColor = MLCResolved([MacLCDesign.accent colorWithAlphaComponent:0.07]);
    [root addSublayer:_callout];
    [root addSublayer:_window];
    [root addSublayer:_tail];

    _barTrack = [CALayer layer];
    _barTrack.backgroundColor = MLCWhite(0.12);
    _barTrack.cornerRadius = 5.0;
    _barTrack.anchorPoint = CGPointMake(0, 0);
    [root addSublayer:_barTrack];
    _glow = [CALayer layer];
    _glow.backgroundColor = MLCAccent();
    _glow.cornerRadius = 5.0;
    _glow.anchorPoint = CGPointMake(0, 0);
    _glow.shadowColor = MLCAccent();
    _glow.shadowOpacity = 0.9f;
    _glow.shadowRadius = 9.0;
    _glow.shadowOffset = CGSizeZero;
    [root addSublayer:_glow];
    _fill = [CALayer layer];
    _fill.backgroundColor = MLCAccent();
    _fill.cornerRadius = 5.0;
    _fill.masksToBounds = YES;
    _fill.anchorPoint = CGPointMake(0, 0);
    [root addSublayer:_fill];
    _shimmer = [CAGradientLayer layer];
    _shimmer.colors = @[(__bridge id)MLCWhite(0.0), (__bridge id)MLCWhite(0.45), (__bridge id)MLCWhite(0.0)];
    _shimmer.startPoint = CGPointMake(0, 0.5);
    _shimmer.endPoint = CGPointMake(1, 0.5);
    _shimmer.opacity = 0.0;
    [_fill addSublayer:_shimmer];

    _startCaption = [CATextLayer layer];
    _startCaption.string = _NS("Start buffer");
    _startCaption.fontSize = 10.0;
    _startCaption.font = (__bridge CFTypeRef)[NSFont systemFontOfSize:10.0 weight:NSFontWeightMedium];
    _startCaption.foregroundColor = MLCWhite(0.55);
    _startCaption.alignmentMode = kCAAlignmentLeft;
    [root addSublayer:_startCaption];
    _tailCaption = [CATextLayer layer];
    _tailCaption.string = _NS("Reading the film's index first");
    _tailCaption.fontSize = 10.0;
    _tailCaption.font = (__bridge CFTypeRef)[NSFont systemFontOfSize:10.0 weight:NSFontWeightMedium];
    _tailCaption.foregroundColor = MLCAccent();
    _tailCaption.alignmentMode = kCAAlignmentRight;
    _tailCaption.opacity = 0.0;
    [root addSublayer:_tailCaption];

    _percent = MLCLabel([MacLCDesign monospacedDigitFontForTextStyle:NSFontTextStyleLargeTitle
                                                              weight:NSFontWeightSemibold],
                        1.0, NSTextAlignmentLeft);
    _detail = MLCLabel([MacLCDesign monospacedDigitFontForTextStyle:NSFontTextStyleCallout
                                                             weight:NSFontWeightMedium],
                       0.9, NSTextAlignmentLeft);
    _remaining = MLCLabel([MacLCDesign monospacedDigitFontForTextStyle:NSFontTextStyleFootnote],
                          0.6, NSTextAlignmentLeft);
    for (NSTextField *field in @[_percent, _detail, _remaining]) {
        field.translatesAutoresizingMaskIntoConstraints = YES;
        [self addSubview:field];
    }
    _built = YES;
}

- (void)viewDidMoveToWindow
{
    [super viewDidMoveToWindow];
    if (self.window != nil)
        [self updateScale];
}

- (void)viewDidChangeBackingProperties
{
    [super viewDidChangeBackingProperties];
    [self updateScale];
}

- (void)updateScale
{
    _scale = self.window.backingScaleFactor ?: 2.0;
    MLCNoActions(^{
        self->_startCaption.contentsScale = self->_scale;
        self->_tailCaption.contentsScale = self->_scale;
    });
}

- (CGFloat)trackWidth { return NSWidth(self.bounds); }

- (void)layout
{
    [super layout];
    const CGFloat w = NSWidth(self.bounds), h = NSHeight(self.bounds);
    if (w < 10)
        return;
    MLCNoActions(^{
        /* From the bottom: metrics 0-46, start-buffer bar 54-64, callout
         * 64-80, the film 80-h. */
        const CGFloat filmY = 80.0, filmH = MAX(26.0, h - 80.0);
        self->_frame.path = (CGPathRef)CFAutorelease(CGPathCreateWithRoundedRect(
            CGRectMake(0.5, filmY, w - 1.0, filmH), 6, 6, NULL));
        const NSInteger holes = (NSInteger)floor((w - 12) / 11.0);
        for (CAReplicatorLayer *rep in @[self->_perforationsTop, self->_perforationsBottom]) {
            ((CAReplicatorLayer *)rep).instanceCount = MAX(1, holes);
        }
        self->_perforationsTop.frame = CGRectMake(8, filmY + filmH - 6, w, 3);
        self->_perforationsBottom.frame = CGRectMake(8, filmY + 3, w, 3);
        self->_barTrack.frame = CGRectMake(0, 54, w, 10);
        self->_glow.position = CGPointMake(0, 54);
        self->_fill.position = CGPointMake(0, 54);
        self->_startCaption.frame = CGRectMake(0, 66, 120, 13);
        self->_tailCaption.frame = CGRectMake(w - 220, 66, 220, 13);
        self->_percent.frame = NSMakeRect(0, 2, 124, 46);
        self->_detail.frame = NSMakeRect(130, 24, MAX(0, w - 130), 20);
        self->_remaining.frame = NSMakeRect(130, 6, MAX(0, w - 130), 16);
    });
    [self applyGeometry];
}

/* Positions that depend on the model: ranges, the start window, the callout
 * wedge, the bar's fill. */
- (void)applyGeometry
{
    const CGFloat w = NSWidth(self.bounds), h = NSHeight(self.bounds);
    if (w < 10)
        return;
    const CGFloat filmY = 80.0, filmH = MAX(26.0, h - 80.0);
    const CGFloat trackY = filmY + 10, trackH = filmH - 20;
    const CGFloat winW = MAX(8.0, _windowFraction * w);
    const CGFloat tailW = MAX(8.0, _tailFraction * w);

    MLCAnimated(0.45, ^{
        NSArray<NSNumber *> *fractions = self->_rangeFractions ?: @[];
        for (NSInteger i = 0; i < 64; i++) {
            CALayer * const layer = self->_ranges[i];
            if (i * 2 + 1 < (NSInteger)fractions.count) {
                const double s = fractions[i * 2].doubleValue, e = fractions[i * 2 + 1].doubleValue;
                layer.frame = CGRectMake(s * w, trackY, MAX(2.0, (e - s) * w), trackH);
                layer.hidden = NO;
            } else {
                layer.hidden = YES;
            }
        }
        self->_window.path = (CGPathRef)CFAutorelease(CGPathCreateWithRoundedRect(
            CGRectMake(0.5, trackY - 3, winW, trackH + 6), 3, 3, NULL));
        CGMutablePathRef wedge = CGPathCreateMutable();
        CGPathMoveToPoint(wedge, NULL, 0.5, trackY - 3);
        CGPathAddLineToPoint(wedge, NULL, winW, trackY - 3);
        CGPathAddLineToPoint(wedge, NULL, w, 64);
        CGPathAddLineToPoint(wedge, NULL, 0.5, 64);
        CGPathCloseSubpath(wedge);
        self->_callout.path = wedge;
        CGPathRelease(wedge);
        self->_tail.path = (CGPathRef)CFAutorelease(CGPathCreateWithRoundedRect(
            CGRectMake(w - tailW - 0.5, trackY - 3, tailW, trackH + 6), 3, 3, NULL));

        const CGFloat fillW = self->_hasNeed ? MAX(0.0, MIN(1.0, self->_progress)) * w : 0.0;
        self->_fill.bounds = CGRectMake(0, 0, fillW, 10);
        self->_glow.bounds = CGRectMake(0, 0, fillW, 10);
        self->_glow.opacity = fillW > 1 ? (self->_progress >= 1.0 ? 0.5f : 1.0f) : 0.0f;
        self->_shimmer.frame = CGRectMake(-80, 0, 80, 10);
    });
    [self installShimmer];
}

- (void)setAnimating:(BOOL)animating
{
    if (_animating == animating)
        return;
    _animating = animating;
    [self installShimmer];
}

- (void)installShimmer
{
    [_shimmer removeAnimationForKey:@"mlc.loop"];
    const CGFloat fillW = _fill.bounds.size.width;
    if (!_animating || fillW < 40 || _progress >= 1.0)
        return;
    MLCNoActions(^{ self->_shimmer.opacity = 1.0; });
    CABasicAnimation * const sweep = [CABasicAnimation animationWithKeyPath:@"position.x"];
    sweep.fromValue = @(-40);
    sweep.toValue = @(fillW + 40);
    sweep.duration = 1.8;
    sweep.repeatCount = HUGE_VALF;
    sweep.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    [_shimmer addAnimation:sweep forKey:@"mlc.loop"];
}

- (void)applyReader:(MacLCTorrentReaderInfo *)reader torrent:(MacLCTorrentInfo *)torrent
{
    _hasNeed = reader != nil && reader.need > 0;
    _progress = _hasNeed ? reader.bufferProgress : 0.0;
    _windowFraction = (reader != nil && reader.size > 0 && reader.need > 0)
        ? (double)reader.need / (double)reader.size : 0.0;
    _rangeFractions = reader.rangeFractions;
    _readerSize = reader.size;

    /* The index (mp4 moov, mkv cues) sits at the end of the file. */
    double tail = 0.0;
    NSArray<NSNumber *> *f = reader.rangeFractions ?: @[];
    if (reader != nil && reader.size > 0) {
        const double limit = 1.0 - (16.0 * 1024 * 1024) / (double)reader.size;
        for (NSUInteger i = 0; i + 1 < f.count; i += 2) {
            if (f[i + 1].doubleValue > 0.999 && f[i].doubleValue >= limit - 0.0001 && f[i].doubleValue > 0.5)
                tail = MAX(tail, f[i + 1].doubleValue - f[i].doubleValue);
        }
        _tailFraction = (16.0 * 1024 * 1024) / (double)reader.size;
    }
    const BOOL tailSeen = tail > 0.0;
    if (tailSeen && !_tailCaptionShown) {
        _tailCaptionShown = YES;
        _tailSeenAt = CACurrentMediaTime();
    }
    const BOOL showCaption = _tailCaptionShown && CACurrentMediaTime() - _tailSeenAt < 6.0 && _progress < 1.0;
    MLCAnimated(0.4, ^{
        self->_tail.opacity = tailSeen ? 1.0f : 0.0f;
        self->_tailCaption.opacity = showCaption ? 1.0f : 0.0f;
        self->_barTrack.opacity = self->_hasNeed ? 1.0f : 0.5f;
    });

    /* Words. */
    const int64_t rate = torrent != nil ? torrent.downloadRate : 0;
    if (_hasNeed) {
        MLCSetText(_percent, [NSString stringWithFormat:@"%ld %%", (long)lround(_progress * 100.0)]);
        const NSTimeInterval left = [reader secondsToFillWithDownloadRate:rate];
        MLCSetText(_remaining, _progress >= 1.0 ? @"" : [MacLCTorrentFormat remainingString:left]);
    } else {
        MLCSetText(_percent, [MacLCTorrentFormat rateString:rate]);
        MLCSetText(_remaining, @"");
    }
    NSString *detail = @"";
    if (torrent != nil) {
        detail = _hasNeed ? [MacLCTorrentFormat rateString:rate] : @"";
        NSString *peers = [MacLCTorrentFormat peersString:torrent];
        detail = detail.length > 0 ? [NSString stringWithFormat:@"%@ · %@", detail, peers] : peers;
    }
    MLCSetText(_detail, detail);
    _percent.hidden = NO;

    [self applyGeometry];
}

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
    MacLCTorrentScene *_scene;
    NSTextField *_stageLabel;
    NSTextField *_explanation;
    NSTextField *_counters;
    MacLCTorrentFilmStrip *_strip;
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
    BOOL _stripShown;
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

    _scene = [[MacLCTorrentScene alloc] initWithFrame:NSZeroRect];
    _stageLabel = MLCLabel(MacLCDesign.title3, 1.0, NSTextAlignmentCenter);
    _explanation = MLCLabel(MacLCDesign.body, 0.72, NSTextAlignmentCenter);
    _explanation.lineBreakMode = NSLineBreakByWordWrapping;
    _explanation.maximumNumberOfLines = 3;
    _counters = MLCLabel([MacLCDesign monospacedDigitFontForTextStyle:NSFontTextStyleFootnote],
                         0.6, NSTextAlignmentCenter);
    _strip = [[MacLCTorrentFilmStrip alloc] initWithFrame:NSZeroRect];
    _strip.alphaValue = 0.0;
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

    _stack = [NSStackView stackViewWithViews:@[_scene, _stageLabel, _explanation, _counters,
                                               _strip, _steps, _cancelGlass]];
    _stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    _stack.alignment = NSLayoutAttributeCenterX;
    _stack.distribution = NSStackViewDistributionFill;
    _stack.spacing = 8;
    _stack.translatesAutoresizingMaskIntoConstraints = NO;
    [_stack setCustomSpacing:14 afterView:_scene];
    [_stack setCustomSpacing:14 afterView:_counters];
    [_stack setCustomSpacing:10 afterView:_strip];
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
    NSLayoutConstraint * const sceneHeight = [_scene.heightAnchor constraintEqualToConstant:400];
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
    NSLayoutConstraint * const sceneMin = [_scene.heightAnchor constraintGreaterThanOrEqualToConstant:104];
    sceneMin.priority = 250;
    [_scene setContentHuggingPriority:100 forOrientation:NSLayoutConstraintOrientationVertical];
    [_scene setContentCompressionResistancePriority:100 forOrientation:NSLayoutConstraintOrientationVertical];
    [NSLayoutConstraint activateConstraints:@[
        titleTop, titleWidth,
        [_titleBlock.centerXAnchor constraintEqualToAnchor:safe.centerXAnchor],

        [_stack.centerXAnchor constraintEqualToAnchor:safe.centerXAnchor],
        [_stack.widthAnchor constraintLessThanOrEqualToConstant:640],
        stackWidth, sceneHeight, bottom, center, stackTop, sceneMin,

        [_scene.widthAnchor constraintEqualToAnchor:_stack.widthAnchor],
        [_scene.heightAnchor constraintLessThanOrEqualToConstant:300],
        [_explanation.widthAnchor constraintLessThanOrEqualToConstant:520],
        [_explanation.widthAnchor constraintLessThanOrEqualToAnchor:_stack.widthAnchor],
        [_strip.widthAnchor constraintEqualToAnchor:_stack.widthAnchor],
        [_strip.widthAnchor constraintLessThanOrEqualToConstant:560],
        [_strip.heightAnchor constraintEqualToConstant:112],
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
    _scene.animating = running;
    _strip.animating = running;
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

    [_scene applyStage:stage torrent:torrent dhtNodes:dhtNodes];
    [_scene setTrackersLabelsFromTorrent:torrent];
    [_steps setStep:step failed:failed];

    const BOOL showStrip = step >= 3 && step <= 4 && !failed;
    if (showStrip != _stripShown) {
        _stripShown = showStrip;
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
            context.duration = 0.4;
            self->_strip.animator.alphaValue = showStrip ? 1.0 : 0.0;
        }];
    }
    if (showStrip)
        [_strip applyReader:reader torrent:torrent];

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
        self->_strip.alphaValue = 0.0;
        self->_stripShown = NO;
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
