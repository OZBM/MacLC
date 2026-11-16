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

#import "MacLCTorrentSwarmView.h"

#import <QuartzCore/QuartzCore.h>

#import "extensions/NSString+Helpers.h"
#import "theme/MacLCDesign.h"

/* The picture shows the order of magnitude; the exact numbers are written in
 * the text below it. */
enum { kPeerSlots = 24, kInnerSlots = 10, kSwarmDots = 64, kTrackerPins = 8, kMaxPieces = 40 };
static const CGFloat kStripBand = 92.0;
static const CGFloat kLegendLine = 18.0;
static const CGFloat kPeerRadius = 6.5;
static const NSTimeInterval kTick = 0.25;

typedef NS_ENUM(NSInteger, SWPeerKind) {
    SWPeerHidden,
    SWPeerPending,  // connection opening
    SWPeerPartial,  // has part of the film
    SWPeerSeed,     // has all of it
};

static double SWHash(NSInteger i, double salt)
{
    const double v = sin((double)i * 12.9898 + salt * 78.233) * 43758.5453;
    return v - floor(v);
}

static NSAppearance *SWDark(void)
{
    return [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
}

/* Dynamic colours resolved for the dark appearance this view always has. */
static CGColorRef SWColor(NSColor *color)
{
    __block CGColorRef resolved = NULL;
    [SWDark() performAsCurrentDrawingAppearance:^{
        resolved = CGColorRetain(color.CGColor);
    }];
    return resolved ? (CGColorRef)CFAutorelease(resolved) : NULL;
}

static CGColorRef SWWhite(CGFloat alpha)
{
    return [NSColor colorWithWhite:1.0 alpha:alpha].CGColor;
}

static CGColorRef SWAccent(CGFloat alpha)
{
    return SWColor([MacLCDesign.accent colorWithAlphaComponent:alpha]);
}

static CAShapeLayer *SWShape(void)
{
    CAShapeLayer * const layer = [CAShapeLayer layer];
    layer.fillColor = NSColor.clearColor.CGColor;
    layer.strokeColor = NSColor.clearColor.CGColor;
    return layer;
}

static CATextLayer *SWText(CGFloat size, NSFontWeight weight, CGFloat alpha)
{
    CATextLayer * const text = [CATextLayer layer];
    text.font = (__bridge CFTypeRef)[NSFont systemFontOfSize:size weight:weight];
    text.fontSize = size;
    text.foregroundColor = SWWhite(alpha);
    text.alignmentMode = kCAAlignmentCenter;
    text.truncationMode = kCATruncationEnd;
    return text;
}

static CGSize SWTextSize(CATextLayer *layer)
{
    NSSize size;
    if ([layer.string isKindOfClass:NSAttributedString.class]) {
        size = [(NSAttributedString *)layer.string size];
    } else {
        NSString * const string = [layer.string isKindOfClass:NSString.class] ? layer.string : @"";
        NSFont * const font = [NSFont systemFontOfSize:layer.fontSize];
        size = [string sizeWithAttributes:@{NSFontAttributeName: (__bridge NSFont *)layer.font ?: font}];
    }
    return CGSizeMake(ceil(size.width) + 2.0, ceil(size.height));
}

/* An SF Symbol drawn once into a bitmap, for a CALayer. */
static void SWSetGlyph(CALayer *layer, NSString *name, CGFloat pointSize, NSColor *color, CGFloat scale)
{
    NSImageSymbolConfiguration *config =
        [NSImageSymbolConfiguration configurationWithPointSize:pointSize weight:NSFontWeightRegular];
    config = [config configurationByApplyingConfiguration:
              [NSImageSymbolConfiguration configurationWithPaletteColors:@[color]]];
    NSImage * const image = [[NSImage imageWithSystemSymbolName:name accessibilityDescription:nil]
                             imageWithSymbolConfiguration:config];
    if (image == nil)
        return;
    const NSSize size = image.size;
    const NSRect rect = NSMakeRect(0, 0, size.width, size.height);
    NSBitmapImageRep * const rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
                                                                           pixelsWide:(NSInteger)ceil(size.width * scale)
                                                                           pixelsHigh:(NSInteger)ceil(size.height * scale)
                                                                        bitsPerSample:8
                                                                      samplesPerPixel:4
                                                                             hasAlpha:YES
                                                                             isPlanar:NO
                                                                       colorSpaceName:NSDeviceRGBColorSpace
                                                                          bytesPerRow:0
                                                                         bitsPerPixel:0];
    rep.size = size;
    [NSGraphicsContext saveGraphicsState];
    NSGraphicsContext.currentContext = [NSGraphicsContext graphicsContextWithBitmapImageRep:rep];
    [image drawInRect:rect];
    [NSGraphicsContext restoreGraphicsState];
    layer.contents = (__bridge id)rep.CGImage;
    layer.contentsScale = scale;
    layer.bounds = CGRectMake(0, 0, size.width, size.height);
}

@implementation MacLCTorrentSwarmView
{
    /* swarm */
    CAShapeLayer *_swarmDots;
    CAShapeLayer *_links;
    CAShapeLayer *_pendingLinks;
    CAShapeLayer *_radar;
    CALayer *_peerLayers[kPeerSlots];
    CALayer *_peerCores[kPeerSlots];
    CALayer *_pins[kTrackerPins];
    CALayer *_pieces;
    CALayer *_macTile;
    CALayer *_macGlyph;
    CATextLayer *_macLabel;
    CATextLayer *_rateLabel;
    CATextLayer *_moreLabel;
    CATextLayer *_legend;

    /* film strip */
    CAShapeLayer *_track;
    CAShapeLayer *_have;
    CAShapeLayer *_haveMask;
    CAShapeLayer *_need;
    CAShapeLayer *_window;
    CALayer *_playhead;
    CATextLayer *_stripTitle;
    CATextLayer *_startLabel;
    CATextLayer *_endLabel;
    CAShapeLayer *_zoomTrack;
    CALayer *_zoomFill;
    CAShapeLayer *_wedge;
    CGRect _zoomRect;

    /* geometry */
    CGPoint _slot[kPeerSlots];
    NSInteger _slotOrder[kPeerSlots];
    CGPoint _swarmPoint[kSwarmDots];
    CGPoint _pinPoint[kTrackerPins];
    CGPoint _macCenter;
    CGRect _trackRect;
    CGFloat _scale;

    /* state */
    MacLCTorrentStage _stage;
    NSInteger _connected;
    NSInteger _seeds;
    NSInteger _sending;
    NSInteger _opening;
    NSInteger _swarmTotal;
    NSInteger _dht;
    int64_t _rate;
    NSArray<MacLCTorrentTrackerInfo *> *_trackers;
    BOOL _hasReader;
    NSArray<NSNumber *> *_ranges;
    double _position;
    double _needEnd;
    double _windowEnd;
    double _head;
    double _bufferProgress;
    BOOL _indexArrived;
    NSTimeInterval _aheadSeconds;

    NSTimer *_timer;
    double _pieceDebt;
    NSUInteger _tickCount;
}

- (instancetype)initWithFrame:(NSRect)frame
{
    self = [super initWithFrame:frame];
    if (self == nil)
        return nil;
    self.wantsLayer = YES;
    self.appearance = SWDark();
    self.translatesAutoresizingMaskIntoConstraints = NO;
    self.accessibilityElement = NO;
    _scale = 2.0;
    _stage = MacLCTorrentStageUnknown;

    /* Spread the first peers over both arcs rather than filling one side. */
    for (NSInteger i = 0; i < kPeerSlots; i++)
        _slotOrder[i] = i;
    for (NSInteger i = kPeerSlots - 1; i > 0; i--) {
        const NSInteger j = (NSInteger)(SWHash(i, 3.1) * (double)(i + 1)) % (i + 1);
        const NSInteger t = _slotOrder[i];
        _slotOrder[i] = _slotOrder[j];
        _slotOrder[j] = t;
    }
    [self build];
    return self;
}

- (void)dealloc
{
    [_timer invalidate];
}

- (BOOL)isFlipped { return NO; }

- (void)build
{
    CALayer * const root = self.layer;

    _swarmDots = SWShape();
    _swarmDots.fillColor = SWWhite(0.22);
    [root addSublayer:_swarmDots];

    _radar = SWShape();
    _radar.strokeColor = SWAccent(0.55);
    _radar.lineWidth = 1.5;
    _radar.opacity = 0.0;
    [root addSublayer:_radar];

    _pendingLinks = SWShape();
    _pendingLinks.strokeColor = SWWhite(0.22);
    _pendingLinks.lineWidth = 1.0;
    _pendingLinks.lineDashPattern = @[@3, @4];
    [root addSublayer:_pendingLinks];

    _links = SWShape();
    _links.strokeColor = SWAccent(0.55);
    _links.lineWidth = 1.5;
    [root addSublayer:_links];

    for (NSInteger i = 0; i < kTrackerPins; i++) {
        CALayer * const pin = [CALayer layer];
        pin.opacity = 0.0;
        _pins[i] = pin;
        [root addSublayer:pin];
    }

    for (NSInteger i = 0; i < kPeerSlots; i++) {
        CAShapeLayer * const peer = SWShape();
        CGPathRef const circle = CGPathCreateWithEllipseInRect(CGRectMake(-kPeerRadius, -kPeerRadius, 2 * kPeerRadius, 2 * kPeerRadius), NULL);
        peer.path = circle;
        CGPathRelease(circle);
        peer.lineWidth = 1.5;
        peer.opacity = 0.0;
        peer.shadowColor = SWAccent(1.0);
        peer.shadowOffset = CGSizeZero;
        peer.shadowRadius = 6.0;
        peer.shadowOpacity = 0.0;
        CALayer * const core = [CALayer layer];
        core.bounds = CGRectMake(0, 0, 5, 5);
        core.cornerRadius = 2.5;
        core.backgroundColor = SWAccent(1.0);
        core.position = CGPointZero;
        [peer addSublayer:core];
        _peerLayers[i] = peer;
        _peerCores[i] = core;
        [root addSublayer:peer];
    }

    _pieces = [CALayer layer];
    [root addSublayer:_pieces];

    _macTile = [CALayer layer];
    _macTile.bounds = CGRectMake(0, 0, 64, 46);
    _macTile.cornerRadius = 12.0;
    _macTile.backgroundColor = SWWhite(0.10);
    _macTile.borderColor = SWWhite(0.22);
    _macTile.borderWidth = 1.0;
    [root addSublayer:_macTile];
    _macGlyph = [CALayer layer];
    [_macTile addSublayer:_macGlyph];

    _macLabel = SWText(11.0, NSFontWeightSemibold, 0.85);
    _macLabel.string = _NS("This Mac");
    [root addSublayer:_macLabel];
    _rateLabel = SWText(11.0, NSFontWeightMedium, 0.6);
    [root addSublayer:_rateLabel];
    _moreLabel = SWText(10.0, NSFontWeightMedium, 0.55);
    [root addSublayer:_moreLabel];
    _legend = SWText(10.0, NSFontWeightRegular, 0.5);
    {
        NSDictionary * const words = @{NSFontAttributeName: [NSFont systemFontOfSize:10.0],
                                       NSForegroundColorAttributeName: [NSColor colorWithWhite:1.0 alpha:0.55]};
        NSDictionary * const marks = @{NSFontAttributeName: [NSFont systemFontOfSize:10.0 weight:NSFontWeightBold],
                                       NSForegroundColorAttributeName: [NSColor colorWithCGColor:SWAccent(1.0)]};
        NSMutableAttributedString * const legend = [[NSMutableAttributedString alloc] init];
        NSArray<NSArray<NSString *> *> * const items = @[@[@"●", _NS("has the whole film")],
                                                          @[@"◉", _NS("has part of it")],
                                                          @[@"━", _NS("sending to you")]];
        for (NSArray<NSString *> * const item in items) {
            if (legend.length > 0)
                [legend appendAttributedString:[[NSAttributedString alloc] initWithString:@"      " attributes:words]];
            [legend appendAttributedString:[[NSAttributedString alloc] initWithString:item[0] attributes:marks]];
            [legend appendAttributedString:[[NSAttributedString alloc] initWithString:[@"  " stringByAppendingString:item[1]] attributes:words]];
        }
        _legend.string = legend;
    }
    _legend.opacity = 0.0;
    [root addSublayer:_legend];

    _track = SWShape();
    _track.fillColor = SWWhite(0.08);
    _track.strokeColor = SWWhite(0.20);
    _track.lineWidth = 1.0;
    [root addSublayer:_track];
    _have = SWShape();
    _have.fillColor = SWAccent(0.9);
    _haveMask = SWShape();
    _haveMask.fillColor = NSColor.blackColor.CGColor;
    _have.mask = _haveMask;
    [root addSublayer:_have];
    _window = SWShape();
    _window.strokeColor = SWWhite(0.35);
    _window.lineWidth = 1.0;
    [root addSublayer:_window];
    _need = SWShape();
    _need.strokeColor = SWWhite(0.85);
    _need.lineWidth = 1.25;
    _need.lineDashPattern = @[@3, @2];
    [root addSublayer:_need];
    _playhead = [CALayer layer];
    _playhead.backgroundColor = SWWhite(0.95);
    _playhead.cornerRadius = 1.0;
    [root addSublayer:_playhead];

    _stripTitle = SWText(11.0, NSFontWeightMedium, 0.75);
    [root addSublayer:_stripTitle];
    _startLabel = SWText(10.0, NSFontWeightRegular, 0.45);
    _startLabel.string = _NS("Start");
    _startLabel.alignmentMode = kCAAlignmentLeft;
    [root addSublayer:_startLabel];
    _endLabel = SWText(10.0, NSFontWeightRegular, 0.45);
    _endLabel.string = _NS("End");
    _endLabel.alignmentMode = kCAAlignmentRight;
    [root addSublayer:_endLabel];
    _wedge = SWShape();
    _wedge.fillColor = SWWhite(0.05);
    _wedge.strokeColor = SWWhite(0.16);
    _wedge.lineWidth = 1.0;
    [root addSublayer:_wedge];
    _zoomTrack = SWShape();
    _zoomTrack.fillColor = SWWhite(0.10);
    _zoomTrack.strokeColor = SWWhite(0.30);
    _zoomTrack.lineWidth = 1.0;
    [root addSublayer:_zoomTrack];
    _zoomFill = [CALayer layer];
    _zoomFill.backgroundColor = SWAccent(1.0);
    _zoomFill.anchorPoint = CGPointMake(0.0, 0.5);
    _zoomFill.cornerRadius = 4.0;
    [root addSublayer:_zoomFill];

    [self refreshScale];
}

#pragma mark Geometry

- (void)viewDidChangeBackingProperties
{
    [super viewDidChangeBackingProperties];
    [self refreshScale];
}

- (void)viewDidMoveToWindow
{
    [super viewDidMoveToWindow];
    [self refreshScale];
    [self updateTimer];
}

- (void)refreshScale
{
    _scale = self.window.backingScaleFactor ?: (NSScreen.mainScreen.backingScaleFactor ?: 2.0);
    for (CATextLayer * const text in @[_macLabel, _rateLabel, _moreLabel, _legend, _stripTitle,
                                        _startLabel, _endLabel])
        text.contentsScale = _scale;
    SWSetGlyph(_macGlyph, @"laptopcomputer", 24.0, NSColor.whiteColor, _scale);
    [self styleTrackerPins];
    [self setNeedsLayout:YES];
}

- (void)layout
{
    [super layout];
    const CGFloat W = NSWidth(self.bounds);
    const CGFloat H = NSHeight(self.bounds);
    if (W < 40.0 || H < 40.0)
        return;

    /* Zones, bottom up, so that no two words ever share a place: the strip
     * band (Start and End, the film, the start-buffer zoom and its title),
     * the Mac with its name and rate, two arcs of peers, the wider swarm,
     * the legend on the top line. */
    const CGFloat band = kStripBand;
    const CGFloat top = H - kLegendLine;
    _macCenter = CGPointMake(round(W / 2.0), round(band + 58.0));
    const CGFloat r2 = MAX(36.0, MIN(W * 0.40, (top - (_macCenter.y + 10.0) - 30.0) / 0.92));
    const CGFloat r1 = r2 * 0.58;

    for (NSInteger i = 0; i < kPeerSlots; i++) {
        const BOOL inner = i < kInnerSlots;
        const NSInteger n = inner ? i : i - kInnerSlots;
        const NSInteger count = inner ? kInnerSlots : kPeerSlots - kInnerSlots;
        const double from = inner ? 30.0 : 16.0, to = inner ? 150.0 : 164.0;
        const double angle = (from + (to - from) * (double)n / (double)(count - 1)) * M_PI / 180.0;
        const CGFloat r = inner ? r1 : r2;
        _slot[i] = CGPointMake(_macCenter.x + r * cos(angle), _macCenter.y + 10.0 + r * sin(angle) * 0.92);
    }
    for (NSInteger i = 0; i < kTrackerPins; i++) {
        const double angle = (24.0 + 132.0 * (double)i / (double)(kTrackerPins - 1)) * M_PI / 180.0;
        _pinPoint[i] = CGPointMake(_macCenter.x + (r2 + 6.0) * cos(angle),
                                   _macCenter.y + 10.0 + (r2 + 6.0) * sin(angle) * 0.92);
    }
    const CGFloat outerRoom = MAX(6.0, MIN(46.0, top - (_macCenter.y + 10.0 + r2 * 0.92) - 6.0));
    for (NSInteger i = 0; i < kSwarmDots; i++) {
        const double angle = (6.0 + 168.0 * SWHash(i, 1.7)) * M_PI / 180.0;
        const CGFloat r = r2 + 14.0 + outerRoom * SWHash(i, 5.3);
        CGFloat x = _macCenter.x + (r + 30.0 * SWHash(i, 9.1)) * cos(angle);
        CGFloat y = _macCenter.y + 10.0 + r * sin(angle) * 0.92;
        x = MIN(MAX(x, 6.0), W - 6.0);
        y = MIN(MAX(y, _macCenter.y + 30.0), top - 4.0);
        _swarmPoint[i] = CGPointMake(x, y);
    }

    const CGFloat trackWidth = MIN(W - 40.0, 560.0);
    _trackRect = CGRectMake(round((W - trackWidth) / 2.0), 24.0, trackWidth, 12.0);
    const CGFloat zoomWidth = MIN(240.0, round(trackWidth * 0.5));
    _zoomRect = CGRectMake(round((W - zoomWidth) / 2.0), 62.0, zoomWidth, 8.0);

    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _macTile.position = _macCenter;
    _macGlyph.position = CGPointMake(32.0, 23.0);
    CGPathRef const radar = CGPathCreateWithEllipseInRect(CGRectMake(-r2, -r2 * 0.92, 2 * r2, 2 * r2 * 0.92), NULL);
    _radar.path = radar;
    CGPathRelease(radar);
    _radar.position = CGPointMake(_macCenter.x, _macCenter.y + 10.0);
    for (NSInteger i = 0; i < kPeerSlots; i++)
        _peerLayers[i].position = _slot[_slotOrder[i]];
    for (NSInteger i = 0; i < kTrackerPins; i++)
        _pins[i].position = _pinPoint[i];
    CGPathRef const track = CGPathCreateWithRoundedRect(_trackRect, 6.0, 6.0, NULL);
    _track.path = track;
    _haveMask.path = track;
    CGPathRelease(track);
    CGPathRef const zoom = CGPathCreateWithRoundedRect(_zoomRect, 4.0, 4.0, NULL);
    _zoomTrack.path = zoom;
    CGPathRelease(zoom);
    _zoomFill.position = CGPointMake(CGRectGetMinX(_zoomRect), CGRectGetMidY(_zoomRect));
    [CATransaction commit];
    [self refreshLayersAnimated:NO];
}

#pragma mark State

- (void)applyStage:(MacLCTorrentStage)stage
           torrent:(MacLCTorrentInfo *)torrent
            reader:(MacLCTorrentReaderInfo *)reader
          dhtNodes:(NSInteger)dhtNodes
{
    _stage = stage;
    _connected = MAX(0, torrent.peers);
    _seeds = MIN(_connected, MAX(0, torrent.seeds));
    _sending = MIN(_connected, MAX(0, torrent.peersUnchoked));
    _opening = MAX(0, torrent.peersConnecting) + MAX(0, torrent.peersHandshaking);
    _swarmTotal = MAX(0, torrent.swarmSeeds) + MAX(0, torrent.swarmLeechers);
    _dht = dhtNodes;
    _rate = MAX(0, torrent.downloadRate);
    _trackers = torrent.trackers ?: @[];

    _hasReader = reader != nil && reader.size > 0;
    if (_hasReader) {
        const double size = (double)reader.size;
        _ranges = reader.rangeFractions;
        _position = reader.positionFraction;
        _needEnd = reader.need > 0 ? MIN(1.0, ((double)reader.position + (double)reader.need) / size) : _position;
        _windowEnd = reader.windowEnd > 0 ? MIN(1.0, (double)reader.windowEnd / size) : _position;
        _head = reader.headFraction;
        _bufferProgress = reader.bufferProgress;
        _aheadSeconds = reader.aheadSeconds;
        _indexArrived = NO;
        for (NSArray<NSNumber *> * const range in reader.ranges) {
            if (range.count == 2 && range[1].doubleValue >= size * 0.995 && range[0].doubleValue > size * 0.5)
                _indexArrived = YES;
        }
    } else {
        _ranges = @[];
        _position = _needEnd = _windowEnd = _head = 0.0;
        _bufferProgress = 0.0;
        _indexArrived = NO;
    }
    [self refreshLayersAnimated:YES];
    [self updateTimer];
}

- (NSInteger)shownConnected { return MIN(_connected, kPeerSlots); }

- (BOOL)isDiscovering
{
    return _connected == 0 && (_stage == MacLCTorrentStageUnknown || _stage == MacLCTorrentStageTrackers ||
                               _stage == MacLCTorrentStageMetadata || _stage == MacLCTorrentStageConnecting);
}

- (SWPeerKind)kindForIndex:(NSInteger)n
{
    const NSInteger shown = [self shownConnected];
    if (n < shown)
        return n < MIN(_seeds, shown) ? SWPeerSeed : SWPeerPartial;
    if (n < MIN(kPeerSlots, shown + MIN(_opening, 8)))
        return SWPeerPending;
    return SWPeerHidden;
}

/* Seeds send first: the first `sending` connected peers carry the lines. */
- (BOOL)isSendingIndex:(NSInteger)n
{
    return n < MIN(_sending, [self shownConnected]);
}

- (void)styleTrackerPins
{
    for (NSInteger i = 0; i < kTrackerPins; i++) {
        MacLCTorrentTrackerInfo * const tracker = i < (NSInteger)_trackers.count ? _trackers[i] : nil;
        NSColor *color = [NSColor colorWithWhite:1.0 alpha:0.35];
        if (tracker.state == MacLCTorrentTrackerStateOK)
            color = NSColor.systemGreenColor;
        else if (tracker.state == MacLCTorrentTrackerStateError)
            color = NSColor.systemRedColor;
        else if (tracker.state == MacLCTorrentTrackerStateUpdating)
            color = [NSColor colorWithWhite:1.0 alpha:0.8];
        SWSetGlyph(_pins[i], @"antenna.radiowaves.left.and.right", 11.0, color, _scale);
    }
}

- (void)refreshLayersAnimated:(BOOL)animated
{
    const BOOL reduced = MacLCDesign.reducedMotion;
    [CATransaction begin];
    [CATransaction setAnimationDuration:animated ? (reduced ? 0.25 : 0.45) : 0.0];
    [CATransaction setDisableActions:!animated];
    [CATransaction setAnimationTimingFunction:
     [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut]];

    const BOOL failed = _stage == MacLCTorrentStageFailed;
    const BOOL discovering = [self isDiscovering];

    /* The wider swarm, or the DHT network while it is searched. */
    NSInteger dots = 0;
    if (_swarmTotal > 0)
        dots = MIN(kSwarmDots, _swarmTotal);
    else if (_dht > 0)
        dots = MIN(kSwarmDots, 10 + _dht / 12);
    CGMutablePathRef const swarm = CGPathCreateMutable();
    for (NSInteger i = 0; i < dots; i++)
        CGPathAddEllipseInRect(swarm, NULL, CGRectMake(_swarmPoint[i].x - 1.6, _swarmPoint[i].y - 1.6, 3.2, 3.2));
    _swarmDots.path = swarm;
    CGPathRelease(swarm);
    _swarmDots.opacity = failed ? 0.3 : 1.0;

    /* Trackers: shown while nobody answered yet. */
    [self styleTrackerPins];
    for (NSInteger i = 0; i < kTrackerPins; i++)
        _pins[i].opacity = (discovering && i < (NSInteger)_trackers.count) ? 1.0 : 0.0;

    /* Peers and the lines to the ones sending. */
    CGMutablePathRef const links = CGPathCreateMutable();
    CGMutablePathRef const pending = CGPathCreateMutable();
    for (NSInteger n = 0; n < kPeerSlots; n++) {
        CAShapeLayer * const peer = (CAShapeLayer *)_peerLayers[n];
        CALayer * const core = _peerCores[n];
        const SWPeerKind kind = [self kindForIndex:n];
        const BOOL sending = [self isSendingIndex:n] && !failed;
        const CGPoint p = _slot[_slotOrder[n]];
        switch (kind) {
            case SWPeerSeed:
                peer.fillColor = SWAccent(1.0);
                peer.strokeColor = SWAccent(1.0);
                peer.lineDashPattern = nil;
                core.opacity = 0.0;
                break;
            case SWPeerPartial:
                peer.fillColor = SWAccent(0.12);
                peer.strokeColor = SWAccent(1.0);
                peer.lineDashPattern = nil;
                core.opacity = 1.0;
                break;
            case SWPeerPending:
                peer.fillColor = NSColor.clearColor.CGColor;
                peer.strokeColor = SWWhite(0.45);
                peer.lineDashPattern = @[@2, @2];
                core.opacity = 0.0;
                break;
            case SWPeerHidden:
                break;
        }
        peer.opacity = kind == SWPeerHidden ? 0.0 : (failed ? 0.35 : 1.0);
        peer.shadowOpacity = sending ? 0.9 : 0.0;
        if (kind == SWPeerHidden)
            continue;
        /* Lines stop at the peer's edge and at the Mac tile. */
        const CGFloat dx = _macCenter.x - p.x, dy = _macCenter.y - p.y;
        const CGFloat len = MAX(1.0, hypot(dx, dy));
        const CGPoint a = CGPointMake(p.x + dx / len * (kPeerRadius + 2.0), p.y + dy / len * (kPeerRadius + 2.0));
        const CGPoint b = CGPointMake(_macCenter.x - dx / len * 30.0, _macCenter.y - dy / len * 26.0);
        if (sending) {
            CGPathMoveToPoint(links, NULL, a.x, a.y);
            CGPathAddLineToPoint(links, NULL, b.x, b.y);
        } else if (kind == SWPeerPending) {
            CGPathMoveToPoint(pending, NULL, a.x, a.y);
            CGPathAddLineToPoint(pending, NULL, b.x, b.y);
        }
    }
    _links.path = links;
    _pendingLinks.path = pending;
    CGPathRelease(links);
    CGPathRelease(pending);

    const BOOL more = _connected > kPeerSlots;
    _moreLabel.string = more ? [NSString stringWithFormat:_NS("+%ld more"), (long)(_connected - kPeerSlots)] : @"";
    _moreLabel.opacity = more ? 1.0 : 0.0;
    _legend.opacity = _connected > 0 && !failed ? 1.0 : 0.0;

    _rateLabel.string = _rate > 0 ? [NSString stringWithFormat:@"↓ %@", [MacLCTorrentFormat rateString:_rate]] : @"";
    _macTile.borderColor = failed ? SWColor(NSColor.systemRedColor) : (_rate > 0 ? SWAccent(0.8) : SWWhite(0.22));

    [self refreshStrip];
    [self placeLabels];
    [CATransaction commit];

    [self updateRadar];
}

- (CGFloat)xForFraction:(double)fraction
{
    return CGRectGetMinX(_trackRect) + CGRectGetWidth(_trackRect) * MIN(1.0, MAX(0.0, fraction));
}

- (void)refreshStrip
{
    const CGRect t = _trackRect;
    CGMutablePathRef const have = CGPathCreateMutable();
    for (NSUInteger i = 0; i + 1 < _ranges.count; i += 2) {
        const CGFloat x0 = [self xForFraction:_ranges[i].doubleValue];
        const CGFloat x1 = MAX(x0 + 1.5, [self xForFraction:_ranges[i + 1].doubleValue]);
        CGPathAddRect(have, NULL, CGRectMake(x0, CGRectGetMinY(t), x1 - x0, CGRectGetHeight(t)));
    }
    _have.path = have;
    CGPathRelease(have);

    const BOOL buffering = _hasReader && _needEnd > _position &&
                           _stage != MacLCTorrentStagePlaying && _stage != MacLCTorrentStageFailed;
    if (buffering) {
        const CGFloat x0 = [self xForFraction:_position];
        const CGFloat x1 = MAX(x0 + 6.0, [self xForFraction:_needEnd]);
        CGPathRef const need = CGPathCreateWithRoundedRect(CGRectInset(CGRectMake(x0, CGRectGetMinY(t), x1 - x0, CGRectGetHeight(t)), -2.0, -3.0), 4.0, 4.0, NULL);
        _need.path = need;
        CGPathRelease(need);
        _need.opacity = 1.0;
    } else {
        _need.opacity = 0.0;
    }

    CGMutablePathRef const window = CGPathCreateMutable();
    if (_hasReader && _windowEnd > _position) {
        const CGFloat y = CGRectGetMinY(t) - 5.0;
        CGPathMoveToPoint(window, NULL, [self xForFraction:_position], y + 2.0);
        CGPathAddLineToPoint(window, NULL, [self xForFraction:_position], y);
        CGPathAddLineToPoint(window, NULL, [self xForFraction:_windowEnd], y);
        CGPathAddLineToPoint(window, NULL, [self xForFraction:_windowEnd], y + 2.0);
    }
    _window.path = window;
    CGPathRelease(window);

    _playhead.bounds = CGRectMake(0, 0, 2.0, CGRectGetHeight(t) + 8.0);
    _playhead.position = CGPointMake([self xForFraction:_position], CGRectGetMidY(t));
    _playhead.opacity = _hasReader ? 1.0 : 0.0;
    _track.opacity = _hasReader ? 1.0 : 0.45;

    NSString *title;
    if (!_hasReader)
        title = _NS("The film, in pieces: they can arrive in any order");
    else if (_stage == MacLCTorrentStagePlaying)
        title = [NSString stringWithFormat:_NS("Playing · %@ ready ahead"), [MacLCTorrentFormat durationString:_aheadSeconds]];
    else if (_stage == MacLCTorrentStageReady || _bufferProgress >= 0.999)
        title = _NS("Start of the film ready");
    else
        title = [NSString stringWithFormat:_NS("Needed to start: %ld %%"), (long)lround(_bufferProgress * 100.0)];
    _stripTitle.string = title;
    _endLabel.string = _hasReader && _indexArrived ? _NS("Index ✓   End") : _NS("End");

    /* The start buffer is a sliver of a whole film: a zoom above the strip
     * shows it filling, joined to its place by a wedge. */
    _zoomTrack.opacity = buffering ? 1.0 : 0.0;
    _zoomFill.opacity = buffering ? 1.0 : 0.0;
    _wedge.opacity = buffering ? 1.0 : 0.0;
    _zoomFill.bounds = CGRectMake(0, 0, MAX(buffering ? 8.0 : 0.0, CGRectGetWidth(_zoomRect) * MIN(1.0, MAX(0.0, _bufferProgress))),
                                  CGRectGetHeight(_zoomRect));
    if (buffering) {
        const CGFloat x0 = [self xForFraction:_position];
        const CGFloat x1 = MAX(x0 + 6.0, [self xForFraction:_needEnd]);
        CGMutablePathRef const wedge = CGPathCreateMutable();
        CGPathMoveToPoint(wedge, NULL, x0 - 2.0, CGRectGetMaxY(t) + 3.0);
        CGPathAddLineToPoint(wedge, NULL, CGRectGetMinX(_zoomRect), CGRectGetMinY(_zoomRect) - 2.0);
        CGPathAddLineToPoint(wedge, NULL, CGRectGetMaxX(_zoomRect), CGRectGetMinY(_zoomRect) - 2.0);
        CGPathAddLineToPoint(wedge, NULL, x1 + 2.0, CGRectGetMaxY(t) + 3.0);
        CGPathCloseSubpath(wedge);
        _wedge.path = wedge;
        CGPathRelease(wedge);
    }
}

- (void)placeLabels
{
    const CGRect t = _trackRect;
    const CGFloat W = NSWidth(self.bounds);

    CGSize s = SWTextSize(_macLabel);
    _macLabel.bounds = CGRectMake(0, 0, s.width, s.height);
    _macLabel.position = CGPointMake(_macCenter.x, _macCenter.y - 23.0 - 10.0);
    s = SWTextSize(_rateLabel);
    _rateLabel.bounds = CGRectMake(0, 0, MAX(s.width, 1.0), s.height);
    _rateLabel.position = CGPointMake(_macCenter.x, _macCenter.y - 23.0 - 24.0);

    s = SWTextSize(_moreLabel);
    _moreLabel.bounds = CGRectMake(0, 0, MAX(s.width, 1.0), s.height);
    const CGPoint last = _slot[kPeerSlots - 1];
    _moreLabel.position = CGPointMake(MIN(W - s.width / 2.0 - 4.0, last.x + 4.0), last.y + 16.0);

    s = SWTextSize(_legend);
    _legend.bounds = CGRectMake(0, 0, MIN(s.width, W - 16.0), s.height);
    _legend.position = CGPointMake(W / 2.0, NSHeight(self.bounds) - kLegendLine / 2.0);

    /* Strip words: the title above the strip, Start and End under it, the
     * index chip above its end; nothing shares a line, nothing collides. */
    s = SWTextSize(_stripTitle);
    _stripTitle.bounds = CGRectMake(0, 0, MIN(s.width, CGRectGetWidth(t)), s.height);
    const BOOL zoomed = _zoomTrack.opacity > 0.5;
    _stripTitle.position = CGPointMake(CGRectGetMidX(t), (zoomed ? CGRectGetMaxY(_zoomRect) : CGRectGetMaxY(t)) + 5.0 + s.height / 2.0);
    s = SWTextSize(_startLabel);
    _startLabel.bounds = CGRectMake(0, 0, s.width, s.height);
    _startLabel.position = CGPointMake(CGRectGetMinX(t) + s.width / 2.0, CGRectGetMinY(t) - 4.0 - s.height / 2.0);
    s = SWTextSize(_endLabel);
    _endLabel.bounds = CGRectMake(0, 0, s.width, s.height);
    _endLabel.position = CGPointMake(CGRectGetMaxX(t) - s.width / 2.0, CGRectGetMinY(t) - 4.0 - s.height / 2.0);
}

#pragma mark Motion

- (void)setAnimating:(BOOL)animating
{
    if (_animating == animating)
        return;
    _animating = animating;
    [self updateTimer];
    [self updateRadar];
}

- (void)updateTimer
{
    const BOOL run = _animating && self.window != nil && !MacLCDesign.reducedMotion;
    if (run && _timer == nil) {
        __weak typeof(self) weakSelf = self;
        _timer = [NSTimer timerWithTimeInterval:kTick repeats:YES block:^(NSTimer * __unused timer) {
            [weakSelf tick];
        }];
        [NSRunLoop.mainRunLoop addTimer:_timer forMode:NSRunLoopCommonModes];
    } else if (!run && _timer != nil) {
        [_timer invalidate];
        _timer = nil;
        [_pieces.sublayers makeObjectsPerformSelector:@selector(removeFromSuperlayer)];
    }
}

- (void)updateRadar
{
    const BOOL show = [self isDiscovering] && _animating && !MacLCDesign.reducedMotion &&
                      _stage != MacLCTorrentStageFailed;
    if (show && [_radar animationForKey:@"sw.radar"] == nil) {
        CABasicAnimation * const scale = [CABasicAnimation animationWithKeyPath:@"transform.scale"];
        scale.fromValue = @0.15;
        scale.toValue = @1.0;
        CABasicAnimation * const fade = [CABasicAnimation animationWithKeyPath:@"opacity"];
        fade.fromValue = @0.9;
        fade.toValue = @0.0;
        CAAnimationGroup * const group = [CAAnimationGroup animation];
        group.animations = @[scale, fade];
        group.duration = 2.2;
        group.repeatCount = HUGE_VALF;
        group.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
        [_radar addAnimation:group forKey:@"sw.radar"];
    } else if (!show) {
        [_radar removeAnimationForKey:@"sw.radar"];
    }
}

- (void)tick
{
    _tickCount++;
    const NSInteger sendingShown = MIN(_sending, [self shownConnected]);
    const BOOL flowing = _rate > 0 && sendingShown > 0 && _stage != MacLCTorrentStageFailed;
    if (flowing) {
        /* One visible piece per ~256 KB, between 2 and 20 a second. */
        const double perSecond = MIN(20.0, MAX(2.0, (double)_rate / 262144.0));
        _pieceDebt += perSecond * kTick;
        while (_pieceDebt >= 1.0) {
            _pieceDebt -= 1.0;
            if (_pieces.sublayers.count >= kMaxPieces)
                break;
            const NSInteger n = (NSInteger)arc4random_uniform((uint32_t)sendingShown);
            [self sendPieceFrom:_slot[_slotOrder[n]] color:SWAccent(1.0) size:5.0 land:_hasReader];
        }
    } else if (_stage == MacLCTorrentStageMetadata && _connected > 0 && _tickCount % 3 == 0) {
        /* The file list travels from a peer as one white sheet. */
        const NSInteger n = (NSInteger)arc4random_uniform((uint32_t)[self shownConnected]);
        [self sendPieceFrom:_slot[_slotOrder[n]] color:SWWhite(0.9) size:7.0 land:NO];
    } else if ([self isDiscovering] && _tickCount % 2 == 0) {
        /* Trackers that answered hand over addresses of peers. */
        NSMutableArray<NSNumber *> * const answered = [NSMutableArray array];
        for (NSInteger i = 0; i < MIN(kTrackerPins, (NSInteger)_trackers.count); i++)
            if (_trackers[i].state == MacLCTorrentTrackerStateOK)
                [answered addObject:@(i)];
        if (answered.count > 0) {
            const NSInteger i = answered[arc4random_uniform((uint32_t)answered.count)].integerValue;
            [self sendPieceFrom:_pinPoint[i] color:SWColor(NSColor.systemGreenColor) size:3.5 land:NO];
        }
    }
}

- (void)sendPieceFrom:(CGPoint)from color:(CGColorRef)color size:(CGFloat)size land:(BOOL)land
{
    CALayer * const piece = [CALayer layer];
    piece.bounds = CGRectMake(0, 0, size, size);
    piece.cornerRadius = size * 0.3;
    piece.backgroundColor = color;
    piece.shadowColor = color;
    piece.shadowOpacity = 0.8;
    piece.shadowRadius = 3.0;
    piece.shadowOffset = CGSizeZero;
    const CGPoint to = _macCenter;
    piece.position = to;
    [_pieces addSublayer:piece];

    /* A slight arc, different for every piece, so the flow looks alive. */
    CGMutablePathRef const path = CGPathCreateMutable();
    const CGFloat bend = ((CGFloat)arc4random_uniform(1000) / 1000.0 - 0.5) * 40.0;
    const CGPoint mid = CGPointMake((from.x + to.x) / 2.0 - (to.y - from.y) / 200.0 * bend,
                                    (from.y + to.y) / 2.0 + (to.x - from.x) / 200.0 * bend);
    CGPathMoveToPoint(path, NULL, from.x, from.y);
    CGPathAddQuadCurveToPoint(path, NULL, mid.x, mid.y, to.x, to.y);
    CAKeyframeAnimation * const travel = [CAKeyframeAnimation animationWithKeyPath:@"position"];
    travel.path = path;
    CGPathRelease(path);
    travel.duration = 0.85;
    travel.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseIn];

    __weak typeof(self) weakSelf = self;
    [CATransaction begin];
    [CATransaction setCompletionBlock:^{
        [piece removeFromSuperlayer];
        if (land)
            [weakSelf dropPieceIntoStripWithColor:color];
    }];
    [piece addAnimation:travel forKey:@"sw.travel"];
    [CATransaction commit];
}

/* From the Mac into the film, at the download head: a piece takes its place. */
- (void)dropPieceIntoStripWithColor:(CGColorRef)color
{
    if (!_animating || _pieces.sublayers.count >= kMaxPieces)
        return;
    CALayer * const piece = [CALayer layer];
    piece.bounds = CGRectMake(0, 0, 4.0, 4.0);
    piece.cornerRadius = 1.0;
    piece.backgroundColor = color;
    const double target = _needEnd > _position && _bufferProgress < 1.0
        ? _position + (_needEnd - _position) * MIN(1.0, _bufferProgress + 0.02)
        : _head;
    const CGPoint to = CGPointMake([self xForFraction:target], CGRectGetMidY(_trackRect));
    piece.position = to;
    piece.opacity = 0.0;
    [_pieces addSublayer:piece];

    CABasicAnimation * const fall = [CABasicAnimation animationWithKeyPath:@"position"];
    fall.fromValue = [NSValue valueWithPoint:NSPointFromCGPoint(CGPointMake(_macCenter.x, _macCenter.y - 24.0))];
    fall.toValue = [NSValue valueWithPoint:NSPointFromCGPoint(to)];
    CABasicAnimation * const fade = [CABasicAnimation animationWithKeyPath:@"opacity"];
    fade.fromValue = @1.0;
    fade.toValue = @0.0;
    fade.beginTime = 0.35;
    fade.duration = 0.15;
    CAAnimationGroup * const group = [CAAnimationGroup animation];
    group.animations = @[fall, fade];
    group.duration = 0.5;
    group.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseIn];
    [CATransaction begin];
    [CATransaction setCompletionBlock:^{ [piece removeFromSuperlayer]; }];
    [piece addAnimation:group forKey:@"sw.drop"];
    [CATransaction commit];
}

@end
