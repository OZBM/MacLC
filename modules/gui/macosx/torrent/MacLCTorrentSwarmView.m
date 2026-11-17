/*****************************************************************************
 * MacLCTorrentSwarmView.m: MacOS X interface module
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

#import "torrent/MacLCTorrentSwarmView.h"

#import <QuartzCore/QuartzCore.h>

#import "theme/MacLCDesign.h"

/* An enum: it sizes the per-slot arrays below. */
enum { kPeerSlots = 16 };
static const NSInteger kTicks = 60;
static const NSInteger kDustSlots = 40;
static const NSInteger kMaxFlights = 24;
static const NSTimeInterval kFlightTick = 0.1;
/* π (3 - √5): consecutive slots spread evenly round the orbit, however many. */
static const double kGoldenAngle = 2.39996322972865332;

typedef NS_ENUM(NSInteger, SWPeerKind) {
    SWPeerNone = 0,
    SWPeerConnecting,
    SWPeerPartial,
    SWPeerSeed,
};

#pragma mark - Helpers

/* A stable pseudo-random number in [0, 1) for slot i. */
static double SWHash(NSInteger i, double salt)
{
    const double x = sin((double)i * 12.9898 + salt * 78.233) * 43758.5453;
    return x - floor(x);
}

static double SWRandom(void)
{
    return (double)arc4random_uniform(1u << 24) / (double)(1u << 24);
}

static CGColorRef SWWhite(CGFloat alpha)
{
    return (CGColorRef)CFAutorelease(CGColorCreateSRGB(1.0, 1.0, 1.0, alpha));
}

/* A system colour as it looks on this always-dark screen. */
static CGColorRef SWDarkColor(NSColor *color, CGFloat alpha)
{
    __block CGColorRef resolved = NULL;
    [[NSAppearance appearanceNamed:NSAppearanceNameDarkAqua] performAsCurrentDrawingAppearance:^{
        resolved = CGColorCreateCopyWithAlpha(color.CGColor, alpha);
    }];
    return resolved != NULL ? (CGColorRef)CFAutorelease(resolved) : SWWhite(alpha);
}

static void SWNoActions(void (^block)(void))
{
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    block();
    [CATransaction commit];
}

static void SWAnimated(NSTimeInterval duration, void (^block)(void))
{
    [CATransaction begin];
    [CATransaction setAnimationDuration:duration];
    [CATransaction setAnimationTimingFunction:
     [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut]];
    block();
    [CATransaction commit];
}

static void SWSetScale(CALayer *layer, CGFloat scale)
{
    layer.contentsScale = scale;
    for (CALayer *sublayer in layer.sublayers)
        SWSetScale(sublayer, scale);
    if (layer.mask != nil)
        SWSetScale(layer.mask, scale);
}

static NSFont *SWRoundedFont(CGFloat size, NSFontWeight weight)
{
    NSFont * const base = [NSFont monospacedDigitSystemFontOfSize:size weight:weight];
    NSFontDescriptor * const rounded =
        [base.fontDescriptor fontDescriptorWithDesign:NSFontDescriptorSystemDesignRounded];
    NSFont * const font = rounded != nil ? [NSFont fontWithDescriptor:rounded size:size] : nil;
    return font ?: base;
}

/* The ticks of the start buffer, from `from` on, whose bytes are all verified. */
static NSIndexSet *SWVerifiedTicks(MacLCTorrentReaderInfo *reader, NSInteger from)
{
    NSMutableIndexSet * const ticks = [NSMutableIndexSet indexSet];
    const double start = (double)reader.position;
    const double need = (double)reader.need;
    if (need <= 0.0)
        return ticks;
    for (NSInteger i = MAX(0, from); i < kTicks; i++) {
        const double s = start + need * (double)i / kTicks;
        const double e = start + need * (double)(i + 1) / kTicks;
        for (NSArray<NSNumber *> *range in reader.ranges) {
            if (range.count >= 2 && range[0].doubleValue <= s && range[1].doubleValue >= e) {
                [ticks addIndex:(NSUInteger)i];
                break;
            }
        }
    }
    return ticks;
}

#pragma mark - The view

@implementation MacLCTorrentSwarmView
{
    NSView *_canvas;
    CALayer *_dustSpin;
    NSMutableArray<CALayer *> *_dust;
    CALayer *_orbitSpin;
    NSMutableArray<CAShapeLayer *> *_peers;
    SWPeerKind _kinds[kPeerSlots];
    BOOL _sending[kPeerSlots];
    BOOL _dimmed[kPeerSlots];
    CAShapeLayer *_track;
    CAShapeLayer *_received;
    CAShapeLayer *_filled;
    CALayer *_sweepHost;
    CAShapeLayer *_sweepMask;
    CAGradientLayer *_sweep;
    CALayer *_flashes;
    CALayer *_flights;
    NSMutableArray<CALayer *> *_piecePool;
    NSInteger _inFlight;

    NSStackView *_center;
    NSImageView *_symbol;
    NSTextField *_percent;
    NSTextField *_caption;

    /* Geometry, from the bounds. */
    CGPoint _c;
    CGFloat _R;          /* outer radius of the ticks */
    CGFloat _L;          /* tick length */
    CGFloat _W;          /* tick width */
    CGFloat _orbit;      /* radius of the peers' orbit */
    CGFloat _peerRadius;
    CGFloat _fontRadius; /* the _R the fonts were made for */
    CGFloat _symbolPointSize;

    /* What the numbers said last. */
    BOOL _failed;
    BOOL _ready;
    BOOL _gated;
    BOOL _waiting;
    BOOL _needsEntrance;
    NSInteger _filledCount;
    NSIndexSet *_receivedTicks;
    NSInteger _dustCount;
    NSInteger _senders;
    double _piecesPerSecond;
    double _owed;
    NSString *_symbolName;
    NSColor *_symbolColor;
    BOOL _symbolPulses;
    NSInteger _percentValue;
    NSTimer *_timer;
}

- (instancetype)initWithFrame:(NSRect)frame
{
    self = [super initWithFrame:frame];
    if (self == nil)
        return nil;
    self.translatesAutoresizingMaskIntoConstraints = NO;
    self.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
    [self setAccessibilityElement:NO];
    _receivedTicks = [NSIndexSet indexSet];
    _needsEntrance = YES;
    _percentValue = -1;
    [self build];
    return self;
}

- (void)dealloc
{
    [_timer invalidate];
}

- (BOOL)isFlipped { return NO; }
- (NSView *)hitTest:(NSPoint)point { return nil; }

- (CAShapeLayer *)tickLayerWithColor:(CGColorRef)color
{
    CAShapeLayer * const layer = [CAShapeLayer layer];
    layer.fillColor = NULL;
    layer.strokeColor = color;
    layer.lineCap = kCALineCapRound;
    return layer;
}

- (NSTextField *)centerLabel
{
    NSTextField * const label = [NSTextField labelWithString:@""];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.alignment = NSTextAlignmentCenter;
    label.textColor = NSColor.whiteColor;
    label.hidden = YES;
    [label setAccessibilityElement:NO];
    return label;
}

- (void)build
{
    /* Layer hosting: every sublayer of the canvas is ours to arrange. */
    _canvas = [[NSView alloc] initWithFrame:self.bounds];
    _canvas.layer = [CALayer layer];
    _canvas.wantsLayer = YES;
    _canvas.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [self addSubview:_canvas];
    CALayer * const root = _canvas.layer;

    _dustSpin = [CALayer layer];
    [root addSublayer:_dustSpin];
    _dust = [NSMutableArray arrayWithCapacity:kDustSlots];
    for (NSInteger j = 0; j < kDustSlots; j++) {
        CALayer * const mote = [CALayer layer];
        const CGFloat size = 1.4 + (CGFloat)SWHash(j, 4.0) * 1.4;
        mote.bounds = CGRectMake(0, 0, size, size);
        mote.cornerRadius = size / 2.0;
        mote.backgroundColor = SWWhite(0.12 + (CGFloat)SWHash(j, 5.0) * 0.18);
        mote.opacity = 0.0;
        [_dustSpin addSublayer:mote];
        [_dust addObject:mote];
    }

    _orbitSpin = [CALayer layer];
    [root addSublayer:_orbitSpin];
    _peers = [NSMutableArray arrayWithCapacity:kPeerSlots];
    for (NSInteger i = 0; i < kPeerSlots; i++) {
        CAShapeLayer * const peer = [CAShapeLayer layer];
        peer.opacity = 0.0;
        peer.shadowColor = SWWhite(1.0);
        peer.shadowOffset = CGSizeZero;
        peer.shadowOpacity = 0.0;
        [_orbitSpin addSublayer:peer];
        [_peers addObject:peer];
    }

    _track = [self tickLayerWithColor:SWWhite(0.16)];
    _received = [self tickLayerWithColor:SWWhite(0.42)];
    _filled = [self tickLayerWithColor:SWWhite(0.96)];
    [root addSublayer:_track];
    [root addSublayer:_received];
    [root addSublayer:_filled];

    /* While nothing arrives, a light runs round the ticks: a conic gradient
     * turning under a mask made of the ticks themselves. */
    _sweepHost = [CALayer layer];
    _sweepHost.opacity = 0.0;
    _sweepMask = [self tickLayerWithColor:SWWhite(1.0)];
    _sweepHost.mask = _sweepMask;
    _sweep = [CAGradientLayer layer];
    _sweep.type = kCAGradientLayerConic;
    _sweep.startPoint = CGPointMake(0.5, 0.5);
    _sweep.endPoint = CGPointMake(0.5, 1.0);
    /* Bright at the start angle, fading counter-clockwise: a tail behind a
     * head that turns clockwise, the way the ticks fill. */
    _sweep.colors = @[(__bridge id)SWWhite(0.9), (__bridge id)SWWhite(0.0), (__bridge id)SWWhite(0.0)];
    _sweep.locations = @[@0.0, @0.45, @1.0];
    [_sweepHost addSublayer:_sweep];
    [root addSublayer:_sweepHost];

    _flashes = [CALayer layer];
    _flights = [CALayer layer];
    [root addSublayer:_flashes];
    [root addSublayer:_flights];
    _piecePool = [NSMutableArray array];

    _symbol = [[NSImageView alloc] initWithFrame:NSZeroRect];
    _symbol.translatesAutoresizingMaskIntoConstraints = NO;
    _symbol.wantsLayer = YES;
    _symbol.imageScaling = NSImageScaleNone;
    [_symbol setAccessibilityElement:NO];
    _percent = [self centerLabel];
    _caption = [self centerLabel];
    _caption.textColor = [NSColor colorWithWhite:1.0 alpha:0.62];
    _center = [NSStackView stackViewWithViews:@[_symbol, _percent, _caption]];
    _center.orientation = NSUserInterfaceLayoutOrientationVertical;
    _center.alignment = NSLayoutAttributeCenterX;
    _center.spacing = 2.0;
    _center.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:_center];
    [NSLayoutConstraint activateConstraints:@[
        [_center.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        [_center.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
    ]];
}

#pragma mark Geometry

- (CGFloat)backingScale
{
    const CGFloat scale = self.window.backingScaleFactor;
    return scale > 0.0 ? scale : 2.0;
}

- (void)viewDidChangeBackingProperties
{
    [super viewDidChangeBackingProperties];
    SWNoActions(^{ SWSetScale(self->_canvas.layer, [self backingScale]); });
}

- (void)viewDidMoveToWindow
{
    [super viewDidMoveToWindow];
    SWNoActions(^{ SWSetScale(self->_canvas.layer, [self backingScale]); });
    [self updateTimer];
}

- (CGPathRef)newPathForTicks:(NSIndexSet *)ticks CF_RETURNS_RETAINED
{
    CGMutablePathRef path = CGPathCreateMutable();
    const CGFloat inner = _R - _L;
    const CGFloat outer = _R;
    const CGPoint c = _c;
    [ticks enumerateIndexesUsingBlock:^(NSUInteger i, BOOL * __unused stop) {
        /* Tick 0 at twelve o'clock, then clockwise (y points up). */
        const double a = M_PI_2 - (double)i * 2.0 * M_PI / kTicks;
        CGPathMoveToPoint(path, NULL, c.x + inner * cos(a), c.y + inner * sin(a));
        CGPathAddLineToPoint(path, NULL, c.x + outer * cos(a), c.y + outer * sin(a));
    }];
    return path;
}

- (CGPoint)offsetForPeer:(NSInteger)slot
{
    const double angle = M_PI_2 - (double)slot * kGoldenAngle;
    const CGFloat radius = _orbit + (CGFloat)(SWHash(slot, 1.0) - 0.5) * _R * 0.2;
    return CGPointMake(radius * cos(angle), radius * sin(angle));
}

- (void)layout
{
    [super layout];
    const NSRect bounds = self.bounds;
    const CGFloat side = MIN(NSWidth(bounds), NSHeight(bounds));
    if (side < 1.0)
        return;
    _c = CGPointMake(round(NSMidX(bounds)), round(NSMidY(bounds)));
    _R = MAX(40.0, MIN(96.0, floor(side * 0.25)));
    _L = MAX(6.0, round(_R * 0.17));
    _W = MAX(2.0, round(_R * 0.068) / 2.0);
    _orbit = _R * 1.46;
    _peerRadius = MAX(2.5, _R * 0.046);

    SWNoActions(^{
        for (CALayer *layer in @[self->_dustSpin, self->_orbitSpin, self->_track, self->_received,
                                 self->_filled, self->_sweepHost, self->_sweepMask, self->_flashes,
                                 self->_flights])
            layer.frame = bounds;
        const CGFloat sweepSide = 2.0 * (self->_R + 4.0);
        self->_sweep.frame = CGRectMake(self->_c.x - sweepSide / 2.0, self->_c.y - sweepSide / 2.0,
                                        sweepSide, sweepSide);
        for (CAShapeLayer *layer in @[self->_track, self->_received, self->_filled, self->_sweepMask])
            layer.lineWidth = self->_W;
        CGPathRef all = [self newPathForTicks:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, kTicks)]];
        self->_track.path = all;
        self->_sweepMask.path = all;
        CGPathRelease(all);
        [self refreshTickPaths];

        const CGFloat r = self->_peerRadius;
        CGPathRef dot = CGPathCreateWithEllipseInRect(CGRectMake(-r, -r, 2.0 * r, 2.0 * r), NULL);
        for (NSInteger i = 0; i < kPeerSlots; i++) {
            CAShapeLayer * const peer = self->_peers[i];
            const CGPoint offset = [self offsetForPeer:i];
            peer.bounds = CGRectMake(-r - 2.0, -r - 2.0, 2.0 * r + 4.0, 2.0 * r + 4.0);
            peer.path = dot;
            peer.position = CGPointMake(self->_c.x + offset.x, self->_c.y + offset.y);
            peer.shadowRadius = r * 1.2;
        }
        CGPathRelease(dot);

        for (NSInteger j = 0; j < kDustSlots; j++) {
            const double angle = SWHash(j, 2.0) * 2.0 * M_PI;
            const CGFloat radius = self->_R * (1.70 + (CGFloat)SWHash(j, 3.0) * 0.26);
            self->_dust[j].position = CGPointMake(self->_c.x + radius * cos(angle),
                                                  self->_c.y + radius * sin(angle));
        }
    });

    if (fabs(_fontRadius - _R) > 0.5) {
        _fontRadius = _R;
        _symbolPointSize = round(_R * 0.42);
        _caption.font = [NSFont monospacedDigitSystemFontOfSize:MAX(10.0, round(_R * 0.13))
                                                         weight:NSFontWeightMedium];
        if (_symbolName != nil)
            [self refreshSymbolImageAnimated:NO];
        [self refreshPercentText];
    }
}

- (void)refreshTickPaths
{
    const NSInteger filled = _ready ? kTicks : _filledCount;
    CGPathRef filledPath =
        [self newPathForTicks:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, (NSUInteger)filled)]];
    CGPathRef receivedPath = [self newPathForTicks:_ready ? [NSIndexSet indexSet] : _receivedTicks];
    _filled.path = filledPath;
    _received.path = receivedPath;
    CGPathRelease(filledPath);
    CGPathRelease(receivedPath);
}

#pragma mark Numbers

- (void)reset
{
    _needsEntrance = YES;
    _filledCount = 0;
    _receivedTicks = [NSIndexSet indexSet];
    _ready = NO;
    _failed = NO;
    _gated = NO;
    _senders = 0;
    _piecesPerSecond = 0.0;
    _owed = 0.0;
    _dustCount = 0;
    [self dropFlights];
    SWNoActions(^{
        for (NSInteger i = 0; i < kPeerSlots; i++) {
            self->_kinds[i] = SWPeerNone;
            self->_sending[i] = NO;
            self->_dimmed[i] = NO;
            [self->_peers[i] removeAllAnimations];
            self->_peers[i].opacity = 0.0;
        }
        for (CALayer *mote in self->_dust)
            mote.opacity = 0.0;
        for (CALayer *flash in [self->_flashes.sublayers copy])
            [flash removeFromSuperlayer];
        [self refreshTickPaths];
    });
}

- (void)applyStage:(MacLCTorrentStage)stage
           torrent:(MacLCTorrentInfo *)torrent
            reader:(MacLCTorrentReaderInfo *)reader
          dhtNodes:(NSInteger)dhtNodes
{
    (void)dhtNodes;
    if (stage == MacLCTorrentStageUnknown)
        stage = MacLCTorrentStageTrackers;
    const BOOL failed = stage == MacLCTorrentStageFailed;
    const BOOL ready = stage == MacLCTorrentStageReady;
    const BOOL gated = !failed && !ready && reader != nil && reader.need > 0;
    const BOOL wasReady = _ready;
    _failed = failed;
    _ready = ready;
    _gated = gated;
    _waiting = !failed && !ready && !gated;

    /* The dial: the bright run playback can use, the pieces ahead of it. */
    NSInteger filled = 0;
    NSIndexSet *received = [NSIndexSet indexSet];
    if (gated) {
        filled = MIN(kTicks, MAX(0, (NSInteger)floor(reader.bufferProgress * kTicks)));
        received = SWVerifiedTicks(reader, filled);
    }
    NSMutableIndexSet * const lit = [NSMutableIndexSet indexSet];
    for (NSInteger i = _filledCount; i < filled; i++)
        if (![_receivedTicks containsIndex:(NSUInteger)i])
            [lit addIndex:(NSUInteger)i];
    [received enumerateIndexesUsingBlock:^(NSUInteger i, BOOL * __unused stop) {
        if ((NSInteger)i >= self->_filledCount && ![self->_receivedTicks containsIndex:i])
            [lit addIndex:i];
    }];
    _filledCount = filled;
    _receivedTicks = received;
    SWNoActions(^{ [self refreshTickPaths]; });
    SWAnimated(0.4, ^{
        self->_track.strokeColor = failed ? SWDarkColor(MacLCDesign.warning, 0.55) : SWWhite(0.16);
        self->_filled.opacity = failed ? 0.0f : 1.0f;
        self->_received.opacity = failed ? 0.0f : 1.0f;
        self->_dustSpin.opacity = failed ? 0.35f : 1.0f;
    });
    NSIndexSet * const allTicks = [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, kTicks)];
    if (_needsEntrance) {
        _needsEntrance = NO;
        [self flashTicks:allTicks stagger:0.008];
    } else if (ready && !wasReady) {
        [self flashTicks:allTicks stagger:0.005];
    } else if (lit.count > 0) {
        [self flashTicks:lit stagger:0.03];
    }

    /* The peers: seeds first, then peers with part of the film, then the
     * connections still opening; the first ones send. */
    const NSInteger connected = MIN(MAX(torrent.peers, 0), kPeerSlots);
    const NSInteger seeds = MIN(MAX(torrent.seeds, 0), connected);
    const NSInteger opening = MIN(MAX(torrent.peersConnecting + torrent.peersHandshaking, 0),
                                  kPeerSlots - connected);
    NSInteger sending = MIN(MAX(torrent.peersUnchoked, 0), connected);
    if (sending == 0 && connected > 0 && torrent.downloadRate > 0)
        sending = 1;
    if (failed || ready)
        sending = 0;
    for (NSInteger i = 0; i < kPeerSlots; i++) {
        SWPeerKind kind = SWPeerNone;
        if (i < seeds)
            kind = SWPeerSeed;
        else if (i < connected)
            kind = SWPeerPartial;
        else if (i < connected + opening)
            kind = SWPeerConnecting;
        [self setPeer:i kind:kind sending:i < sending dim:failed];
    }
    _senders = sending;

    /* The swarm the trackers know about, as dust: more of it for a bigger
     * swarm, without drowning the picture (4 motes for 1 peer, 40 for 100). */
    NSInteger swarm = -1;
    if (torrent.swarmSeeds >= 0 && torrent.swarmLeechers >= 0)
        swarm = torrent.swarmSeeds + torrent.swarmLeechers;
    for (MacLCTorrentTrackerInfo *tracker in torrent.trackers)
        swarm = MAX(swarm, tracker.peers);
    swarm = MAX(swarm, torrent.peers + torrent.peersConnecting);
    const NSInteger dust = swarm > 0 ? MIN(kDustSlots, (NSInteger)ceil(sqrt((double)swarm) * 4.0)) : 0;
    if (dust != _dustCount) {
        _dustCount = dust;
        SWAnimated(0.8, ^{
            for (NSInteger j = 0; j < kDustSlots; j++)
                self->_dust[j].opacity = j < dust ? 1.0f : 0.0f;
        });
    }

    /* Pieces in flight: one for every 256 KB/s, 2 to 14 a second. */
    double perSecond = 0.0;
    if (sending > 0 && torrent.downloadRate > 0)
        perSecond = MAX(2.0, MIN(14.0, (double)torrent.downloadRate / 262144.0));
    _piecesPerSecond = perSecond;

    /* The middle. */
    NSString * const rate = torrent.downloadRate > 0 ? [MacLCTorrentFormat rateString:torrent.downloadRate] : nil;
    NSColor * const white = [NSColor colorWithWhite:1.0 alpha:0.92];
    if (failed) {
        [self showSymbol:@"exclamationmark.triangle" color:MacLCDesign.warning pulse:NO caption:nil];
    } else if (ready) {
        [self showSymbol:@"play.fill" color:white pulse:NO caption:nil];
    } else if (gated) {
        [self showPercent:(NSInteger)floor(reader.bufferProgress * 100.0) caption:rate];
    } else {
        NSString *name = @"dot.radiowaves.left.and.right";
        switch (stage) {
            case MacLCTorrentStageMetadata:
                name = @"doc.text.magnifyingglass";
                break;
            case MacLCTorrentStageConnecting:
                name = @"point.3.connected.trianglepath.dotted";
                break;
            case MacLCTorrentStageDownloading:
            case MacLCTorrentStageBuffering:
            case MacLCTorrentStageStalled:
            case MacLCTorrentStagePlaying:
                name = @"arrow.down";
                break;
            default:
                break;
        }
        [self showSymbol:name color:white pulse:YES caption:rate];
    }

    [self refreshMotion];
}

- (void)setPeer:(NSInteger)i kind:(SWPeerKind)kind sending:(BOOL)sending dim:(BOOL)dim
{
    CAShapeLayer * const peer = _peers[i];
    const SWPeerKind before = _kinds[i];
    /* Unchanged: leave the layer alone, or its implicit animations would
     * cut the connecting pulse every update. */
    if (kind == before && sending == _sending[i] && dim == _dimmed[i])
        return;
    _kinds[i] = kind;
    _sending[i] = sending;
    _dimmed[i] = dim;

    CGColorRef fill = SWWhite(0.0);
    CGColorRef stroke = SWWhite(0.0);
    NSArray<NSNumber *> *dash = nil;
    switch (kind) {
        case SWPeerSeed:
            fill = SWWhite(0.92);
            break;
        case SWPeerPartial:
            fill = SWWhite(0.14);
            stroke = SWWhite(0.82);
            break;
        case SWPeerConnecting:
            stroke = SWWhite(0.55);
            dash = @[@1.6, @1.6];
            break;
        case SWPeerNone:
            break;
    }
    const CGFloat scale = sending ? 1.2 : 1.0;
    SWAnimated(0.35, ^{
        peer.fillColor = fill;
        peer.strokeColor = stroke;
        peer.lineWidth = 1.2;
        peer.lineDashPattern = dash;
        peer.shadowOpacity = sending ? 0.7f : 0.0f;
        peer.opacity = kind == SWPeerNone ? 0.0f : (dim ? 0.35f : 1.0f);
        peer.transform = CATransform3DMakeScale(scale, scale, 1.0);
    });
    if (before == SWPeerNone && kind != SWPeerNone && self.window != nil && !MacLCDesign.reducedMotion) {
        CASpringAnimation * const grow = [MacLCDesign emphasizedSpringForKeyPath:@"transform.scale"];
        grow.fromValue = @0.2;
        grow.toValue = @(scale);
        [peer addAnimation:grow forKey:@"mlc.appear"];
    }
    [self refreshPulseForPeer:i];
}

#pragma mark The middle

- (void)showSymbol:(NSString *)name color:(NSColor *)color pulse:(BOOL)pulse caption:(NSString *)caption
{
    _percentValue = -1;
    _percent.hidden = YES;
    _symbol.hidden = NO;
    if (![name isEqualToString:_symbolName] || ![color isEqual:_symbolColor]) {
        _symbolName = [name copy];
        _symbolColor = color;
        [self refreshSymbolImageAnimated:YES];
    }
    _symbolPulses = pulse;
    [self refreshSymbolPulse];
    [self setCaption:caption];
}

- (void)showPercent:(NSInteger)percent caption:(NSString *)caption
{
    _symbolName = nil;
    _symbolPulses = NO;
    [self refreshSymbolPulse];
    _symbol.hidden = YES;
    _percent.hidden = NO;
    percent = MIN(100, MAX(0, percent));
    if (percent != _percentValue) {
        _percentValue = percent;
        [self refreshPercentText];
    }
    [self setCaption:caption];
}

- (void)setCaption:(NSString *)caption
{
    if (caption.length > 0 && ![_caption.stringValue isEqualToString:caption])
        _caption.stringValue = caption;
    _caption.hidden = caption.length == 0;
}

- (void)refreshPercentText
{
    if (_percentValue < 0 || _R <= 0.0)
        return;
    const CGFloat size = round(_R * 0.44);
    NSMutableAttributedString * const text = [[NSMutableAttributedString alloc]
        initWithString:[NSString stringWithFormat:@"%ld", (long)_percentValue]
            attributes:@{ NSFontAttributeName: SWRoundedFont(size, NSFontWeightSemibold),
                          NSForegroundColorAttributeName: NSColor.whiteColor }];
    [text appendAttributedString:[[NSAttributedString alloc]
        initWithString:@"%"
            attributes:@{ NSFontAttributeName: SWRoundedFont(round(size * 0.5), NSFontWeightMedium),
                          NSForegroundColorAttributeName: [NSColor colorWithWhite:1.0 alpha:0.7] }]];
    _percent.attributedStringValue = text;
}

/* A transform that scales a layer-backed view's layer about its centre
 * (AppKit anchors those layers at their bottom-left corner). */
static NSValue *SWScaleAboutCentre(CALayer *layer, CGFloat scale)
{
    const CGPoint c = CGPointMake(CGRectGetMidX(layer.bounds), CGRectGetMidY(layer.bounds));
    CATransform3D t = CATransform3DMakeTranslation(c.x, c.y, 0.0);
    t = CATransform3DScale(t, scale, scale, 1.0);
    t = CATransform3DTranslate(t, -c.x, -c.y, 0.0);
    return [NSValue valueWithCATransform3D:t];
}

- (void)refreshSymbolImageAnimated:(BOOL)animated
{
    if (_symbolName == nil || _symbolPointSize <= 0.0)
        return;
    /* Size and colour in one configuration: applying the colour on its own
     * would drop the size. */
    NSImageSymbolConfiguration * const configuration =
        [[NSImageSymbolConfiguration configurationWithPointSize:_symbolPointSize weight:NSFontWeightRegular]
         configurationByApplyingConfiguration:
             [NSImageSymbolConfiguration configurationWithHierarchicalColor:_symbolColor ?: NSColor.whiteColor]];
    NSImage * const image = [[MacLCDesign symbolNamed:_symbolName accessibilityLabel:nil]
                             imageWithSymbolConfiguration:configuration];
    CALayer * const layer = _symbol.layer;
    if (animated && _symbol.window != nil && layer != nil) {
        CATransition * const fade = [CATransition animation];
        fade.type = kCATransitionFade;
        fade.duration = 0.25;
        [layer addAnimation:fade forKey:@"mlc.swap"];
        if (!MacLCDesign.reducedMotion) {
            CASpringAnimation * const pop = [MacLCDesign emphasizedSpringForKeyPath:@"transform"];
            pop.fromValue = SWScaleAboutCentre(layer, 0.8);
            pop.toValue = [NSValue valueWithCATransform3D:CATransform3DIdentity];
            [layer addAnimation:pop forKey:@"mlc.pop"];
        }
    }
    _symbol.image = image;
}

- (void)refreshSymbolPulse
{
    CALayer * const layer = _symbol.layer;
    const BOOL want = _symbolPulses && _animating && !_symbol.hidden;
    if (want && [layer animationForKey:@"mlc.pulse"] == nil) {
        CABasicAnimation * const pulse = [CABasicAnimation animationWithKeyPath:@"opacity"];
        pulse.fromValue = @1.0;
        pulse.toValue = @0.45;
        pulse.duration = 1.1;
        pulse.autoreverses = YES;
        pulse.repeatCount = HUGE_VALF;
        pulse.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
        [layer addAnimation:pulse forKey:@"mlc.pulse"];
    } else if (!want) {
        [layer removeAnimationForKey:@"mlc.pulse"];
    }
}

#pragma mark Motion

- (void)setAnimating:(BOOL)animating
{
    if (_animating == animating)
        return;
    _animating = animating;
    [self refreshMotion];
}

/* Positive periods turn clockwise (y points up, so towards negative angles). */
static void SWSetSpin(CALayer *layer, NSString *key, NSTimeInterval period)
{
    if (period == 0.0) {
        [layer removeAnimationForKey:key];
        return;
    }
    if ([layer animationForKey:key] != nil)
        return;
    CABasicAnimation * const spin = [CABasicAnimation animationWithKeyPath:@"transform.rotation.z"];
    spin.fromValue = @0.0;
    spin.toValue = @(period > 0.0 ? -2.0 * M_PI : 2.0 * M_PI);
    spin.duration = fabs(period);
    spin.repeatCount = HUGE_VALF;
    [layer addAnimation:spin forKey:key];
}

- (void)refreshMotion
{
    const BOOL on = _animating;
    SWSetSpin(_orbitSpin, @"mlc.spin", on ? 170.0 : 0.0);
    SWSetSpin(_dustSpin, @"mlc.spin", on ? -260.0 : 0.0);
    SWSetSpin(_sweep, @"mlc.sweep", on && _waiting ? 1.8 : 0.0);
    SWAnimated(0.5, ^{ self->_sweepHost.opacity = on && self->_waiting ? 1.0f : 0.0f; });
    for (NSInteger i = 0; i < kPeerSlots; i++)
        [self refreshPulseForPeer:i];
    [self refreshSymbolPulse];
    if (!on)
        [self dropFlights];
    [self updateTimer];
}

- (void)refreshPulseForPeer:(NSInteger)i
{
    CAShapeLayer * const peer = _peers[i];
    const BOOL want = _animating && _kinds[i] == SWPeerConnecting;
    if (want && [peer animationForKey:@"mlc.pulse"] == nil) {
        CABasicAnimation * const pulse = [CABasicAnimation animationWithKeyPath:@"opacity"];
        pulse.fromValue = @1.0;
        pulse.toValue = @0.25;
        pulse.duration = 0.8 + SWHash(i, 6.0) * 0.4;
        pulse.autoreverses = YES;
        pulse.repeatCount = HUGE_VALF;
        [peer addAnimation:pulse forKey:@"mlc.pulse"];
    } else if (!want) {
        [peer removeAnimationForKey:@"mlc.pulse"];
    }
}

- (void)updateTimer
{
    const BOOL want = _animating && self.window != nil;
    if (want && _timer == nil) {
        __weak MacLCTorrentSwarmView * const weakSelf = self;
        _timer = [NSTimer timerWithTimeInterval:kFlightTick repeats:YES block:^(NSTimer * __unused timer) {
            [weakSelf tick];
        }];
        [NSRunLoop.mainRunLoop addTimer:_timer forMode:NSRunLoopCommonModes];
    } else if (!want && _timer != nil) {
        [_timer invalidate];
        _timer = nil;
    }
}

- (void)tick
{
    if (_piecesPerSecond <= 0.0 || _senders <= 0) {
        _owed = 0.0;
        return;
    }
    /* Irregular, like the network. */
    _owed += _piecesPerSecond * kFlightTick * (0.4 + 1.2 * SWRandom());
    while (_owed >= 1.0) {
        _owed -= 1.0;
        [self launchPiece];
    }
}

- (void)dropFlights
{
    _inFlight = 0;
    _owed = 0.0;
    for (CALayer *piece in [_flights.sublayers copy]) {
        [piece removeAllAnimations];
        [piece removeFromSuperlayer];
    }
}

/* Where a piece lands: just after the bright run mostly, sometimes further
 * (the part being fetched first), anywhere when there is no start buffer. */
- (NSInteger)landingTick
{
    if (!_gated)
        return (NSInteger)arc4random_uniform((uint32_t)kTicks);
    const NSInteger span = MIN(12, kTicks - _filledCount);
    if (span <= 0)
        return kTicks - 1;
    return MIN(kTicks - 1, _filledCount + (NSInteger)floor(pow(SWRandom(), 1.6) * span));
}

- (void)launchPiece
{
    if (_inFlight >= kMaxFlights || _senders <= 0 || _R <= 0.0)
        return;

    /* From one of the sending peers, where the turning orbit has it now. */
    const NSInteger slot = (NSInteger)arc4random_uniform((uint32_t)_senders);
    CALayer * const orbit = _orbitSpin.presentationLayer ?: _orbitSpin;
    const double spin = [[orbit valueForKeyPath:@"transform.rotation.z"] doubleValue];
    const CGPoint offset = [self offsetForPeer:slot];
    const CGPoint from = CGPointMake(_c.x + offset.x * cos(spin) - offset.y * sin(spin),
                                     _c.y + offset.x * sin(spin) + offset.y * cos(spin));
    const double a = M_PI_2 - (double)[self landingTick] * 2.0 * M_PI / kTicks;
    const CGFloat landing = _R - _L * 0.5;
    const CGPoint to = CGPointMake(_c.x + landing * cos(a), _c.y + landing * sin(a));
    const CGFloat bend = (CGFloat)(SWRandom() - 0.5) * 0.7;
    const CGPoint control = CGPointMake((from.x + to.x) / 2.0 - (to.y - from.y) * bend,
                                        (from.y + to.y) / 2.0 + (to.x - from.x) * bend);
    CGMutablePathRef path = CGPathCreateMutable();
    CGPathMoveToPoint(path, NULL, from.x, from.y);
    CGPathAddQuadCurveToPoint(path, NULL, control.x, control.y, to.x, to.y);

    CALayer *piece = _piecePool.lastObject;
    if (piece != nil) {
        [_piecePool removeLastObject];
    } else {
        piece = [CALayer layer];
        piece.backgroundColor = SWWhite(0.95);
    }
    const CGFloat size = MAX(2.5, round(_R * 0.042 * 2.0) / 2.0);
    SWNoActions(^{
        piece.contentsScale = [self backingScale];
        piece.bounds = CGRectMake(0, 0, size, size);
        piece.cornerRadius = size * 0.28;
        piece.position = to;
        piece.opacity = 0.0;
    });

    CAKeyframeAnimation * const move = [CAKeyframeAnimation animationWithKeyPath:@"position"];
    move.path = path;
    CGPathRelease(path);
    move.timingFunction = [CAMediaTimingFunction functionWithControlPoints:0.5f :0.0f :0.9f :0.7f];
    CAKeyframeAnimation * const fade = [CAKeyframeAnimation animationWithKeyPath:@"opacity"];
    fade.values = @[@0.0, @1.0, @1.0, @0.0];
    fade.keyTimes = @[@0.0, @0.15, @0.85, @1.0];
    CABasicAnimation * const shrink = [CABasicAnimation animationWithKeyPath:@"transform.scale"];
    shrink.fromValue = @1.0;
    shrink.toValue = @0.55;
    CAAnimationGroup * const group = [CAAnimationGroup animation];
    group.animations = @[move, fade, shrink];
    group.duration = 0.75 + 0.3 * SWRandom();

    _inFlight++;
    __weak MacLCTorrentSwarmView * const weakSelf = self;
    __weak CALayer * const flights = _flights;
    [CATransaction begin];
    [CATransaction setCompletionBlock:^{
        MacLCTorrentSwarmView * const strongSelf = weakSelf;
        if (strongSelf == nil || piece.superlayer != flights)
            return;
        [piece removeFromSuperlayer];
        strongSelf->_inFlight = MAX(0, strongSelf->_inFlight - 1);
        [strongSelf->_piecePool addObject:piece];
    }];
    [_flights addSublayer:piece];
    [piece addAnimation:group forKey:@"mlc.flight"];
    [CATransaction commit];
}

/* A tick that lights up flares and fades into its new shade; the flare
 * pushes outwards a little (a fade alone under Reduce Motion). */
- (void)flashTicks:(NSIndexSet *)ticks stagger:(NSTimeInterval)stagger
{
    if (ticks.count == 0 || self.window == nil || _R <= 0.0)
        return;
    const BOOL reduce = MacLCDesign.reducedMotion;
    if (reduce)
        stagger = 0.0;
    const CFTimeInterval now = [_flashes convertTime:CACurrentMediaTime() fromLayer:nil];
    const CGFloat scale = [self backingScale];
    __block NSInteger n = 0;
    [ticks enumerateIndexesUsingBlock:^(NSUInteger i, BOOL * __unused stop) {
        CAShapeLayer * const flash = [self tickLayerWithColor:SWWhite(1.0)];
        flash.frame = self->_flashes.bounds;
        flash.contentsScale = scale;
        flash.lineWidth = self->_W * 1.5;
        CGPathRef path = [self newPathForTicks:[NSIndexSet indexSetWithIndex:i]];
        flash.path = path;
        CGPathRelease(path);
        flash.opacity = 0.0;

        CABasicAnimation * const fade = [CABasicAnimation animationWithKeyPath:@"opacity"];
        fade.fromValue = @0.9;
        fade.toValue = @0.0;
        CAAnimationGroup * const group = [CAAnimationGroup animation];
        if (reduce) {
            group.animations = @[fade];
        } else {
            CABasicAnimation * const push = [CABasicAnimation animationWithKeyPath:@"transform.scale"];
            push.fromValue = @1.0;
            push.toValue = @1.08;
            group.animations = @[fade, push];
        }
        group.duration = 0.7;
        group.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
        group.beginTime = now + (double)n * stagger;

        [CATransaction begin];
        [CATransaction setCompletionBlock:^{ [flash removeFromSuperlayer]; }];
        [self->_flashes addSublayer:flash];
        [flash addAnimation:group forKey:@"mlc.flash"];
        [CATransaction commit];
        n++;
    }];
}

@end
