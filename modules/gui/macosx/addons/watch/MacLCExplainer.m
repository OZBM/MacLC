/*****************************************************************************
 * MacLCExplainer.m: plain-language explanations of the words Watch uses
 * (peers, Dolby Vision, Remux...), shown as a tip when the pointer rests on
 * them
 *****************************************************************************
 * Copyright (C) 2026 Hazen Studio
 *
 * This program is free software; you can redistribute it and/or modify it
 * under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation; either version 2.1 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin Street, Fifth Floor, Boston MA 02110-1301, USA.
 *****************************************************************************/

#import "addons/watch/MacLCExplainer.h"

#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>

#import <vlc_common.h>

#import "extensions/NSString+Helpers.h"
#import "main/VLCMain.h"
#import "theme/MacLCDesign.h"

// Deliberate departure: Tips open when the pointer rests on a word (popovers normally open on click) because newcomers do not know there is anything to click on a word, and plain help tags cannot explain concepts with rich visuals.

#pragma mark - Topic Constants

MacLCExplainerTopic const MacLCExplainerTopicPeers = @"MacLCExplainerTopicPeers";
MacLCExplainerTopic const MacLCExplainerTopicHealth = @"MacLCExplainerTopicHealth";
MacLCExplainerTopic const MacLCExplainerTopicTorrent = @"MacLCExplainerTopicTorrent";
MacLCExplainerTopic const MacLCExplainerTopicDebrid = @"MacLCExplainerTopicDebrid";
MacLCExplainerTopic const MacLCExplainerTopicSize = @"MacLCExplainerTopicSize";
MacLCExplainerTopic const MacLCExplainerTopicPack = @"MacLCExplainerTopicPack";
MacLCExplainerTopic const MacLCExplainerTopicProvider = @"MacLCExplainerTopicProvider";

MacLCExplainerTopic const MacLCExplainerTopicResolution4K = @"MacLCExplainerTopicResolution4K";
MacLCExplainerTopic const MacLCExplainerTopicResolution1080p = @"MacLCExplainerTopicResolution1080p";
MacLCExplainerTopic const MacLCExplainerTopicResolution720p = @"MacLCExplainerTopicResolution720p";
MacLCExplainerTopic const MacLCExplainerTopicDolbyVision = @"MacLCExplainerTopicDolbyVision";
MacLCExplainerTopic const MacLCExplainerTopicHDR10Plus = @"MacLCExplainerTopicHDR10Plus";
MacLCExplainerTopic const MacLCExplainerTopicHDR10 = @"MacLCExplainerTopicHDR10";
MacLCExplainerTopic const MacLCExplainerTopicHLG = @"MacLCExplainerTopicHLG";
MacLCExplainerTopic const MacLCExplainerTopicSDR = @"MacLCExplainerTopicSDR";
MacLCExplainerTopic const MacLCExplainerTopicHEVC = @"MacLCExplainerTopicHEVC";
MacLCExplainerTopic const MacLCExplainerTopicUpscaled = @"MacLCExplainerTopicUpscaled";

MacLCExplainerTopic const MacLCExplainerTopicRemux = @"MacLCExplainerTopicRemux";
MacLCExplainerTopic const MacLCExplainerTopicBluRay = @"MacLCExplainerTopicBluRay";
MacLCExplainerTopic const MacLCExplainerTopicWebDL = @"MacLCExplainerTopicWebDL";
MacLCExplainerTopic const MacLCExplainerTopicWebRip = @"MacLCExplainerTopicWebRip";
MacLCExplainerTopic const MacLCExplainerTopicCam = @"MacLCExplainerTopicCam";

MacLCExplainerTopic const MacLCExplainerTopicAtmos = @"MacLCExplainerTopicAtmos";
MacLCExplainerTopic const MacLCExplainerTopicLosslessAudio = @"MacLCExplainerTopicLosslessAudio";
MacLCExplainerTopic const MacLCExplainerTopicSurround = @"MacLCExplainerTopicSurround";
MacLCExplainerTopic const MacLCExplainerTopicMultiAudio = @"MacLCExplainerTopicMultiAudio";
MacLCExplainerTopic const MacLCExplainerTopicSubtitles = @"MacLCExplainerTopicSubtitles";

MacLCExplainerTopic const MacLCExplainerTopicAddons = @"MacLCExplainerTopicAddons";
MacLCExplainerTopic const MacLCExplainerTopicServices = @"MacLCExplainerTopicServices";
MacLCExplainerTopic const MacLCExplainerTopicCollections = @"MacLCExplainerTopicCollections";
MacLCExplainerTopic const MacLCExplainerTopicBestMatch = @"MacLCExplainerTopicBestMatch";
MacLCExplainerTopic const MacLCExplainerTopicVerdict = @"MacLCExplainerTopicVerdict";

#pragma mark - Forward Declarations & Internal Protocols

@class MacLCExplainerIllustrationBaseView;
@class MacLCExplainerViewController;

@interface MacLCExplainerIllustrationBaseView : NSView
- (void)startAnimating;
- (void)stopAnimating;
@end

@implementation MacLCExplainerIllustrationBaseView
- (void)startAnimating {}
- (void)stopAnimating {}
@end

#pragma mark - Illustration 1: Peers

@interface MacLCPeersIllustrationView : MacLCExplainerIllustrationBaseView
@end

@implementation MacLCPeersIllustrationView {
    CALayer *_laptopLayer;
    NSMutableArray<CALayer *> *_dotLayers;
    NSMutableArray<CALayer *> *_pieceLayers;
    NSArray<NSValue *> *_dotPositions;
}

- (instancetype)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (self) {
        self.wantsLayer = YES;
        _dotLayers = [NSMutableArray array];
        _pieceLayers = [NSMutableArray array];

        const CGFloat w = 268.0;
        const CGFloat h = 76.0;
        const CGPoint center = CGPointMake(w / 2.0, h / 2.0);

        _laptopLayer = [CALayer layer];
        _laptopLayer.bounds = CGRectMake(0, 0, 26, 18);
        _laptopLayer.position = center;
        NSImage *laptopImg = [MacLCDesign symbolNamed:@"laptopcomputer" pointSize:18 weight:NSFontWeightRegular accessibilityLabel:nil];
        if (laptopImg) {
            _laptopLayer.contents = laptopImg;
            _laptopLayer.contentsGravity = kCAGravityResizeAspect;
        }
        [self.layer addSublayer:_laptopLayer];

        const CGFloat rx = 74.0;
        const CGFloat ry = 24.0;
        NSMutableArray<NSValue *> *positions = [NSMutableArray array];

        for (NSUInteger i = 0; i < 6; i++) {
            const CGFloat angle = (CGFloat)(i * (2.0 * M_PI / 6.0));
            const CGPoint pos = CGPointMake(center.x + rx * cos(angle), center.y + ry * sin(angle));
            [positions addObject:[NSValue valueWithPoint:NSPointFromCGPoint(pos)]];

            // 6 small person.fill dots
            CALayer *dot = [CALayer layer];
            dot.bounds = CGRectMake(0, 0, 10, 10);
            dot.position = pos;
            NSImage *personImg = [MacLCDesign symbolNamed:@"person.fill" pointSize:10 weight:NSFontWeightRegular accessibilityLabel:nil];
            if (personImg) {
                dot.contents = personImg;
                dot.contentsGravity = kCAGravityResizeAspect;
            } else {
                dot.cornerRadius = 5.0;
                dot.backgroundColor = [NSColor secondaryLabelColor].CGColor;
            }
            [self.layer addSublayer:dot];
            [_dotLayers addObject:dot];

            // Pieces: small accent squares traveling in turn
            CALayer *piece = [CALayer layer];
            piece.bounds = CGRectMake(0, 0, 5, 5);
            piece.position = pos;
            piece.cornerRadius = 1.0;
            piece.backgroundColor = [NSColor systemGreenColor].CGColor;
            piece.opacity = 0.0;
            [self.layer addSublayer:piece];
            [_pieceLayers addObject:piece];
        }

        _dotPositions = [positions copy];
    }
    return self;
}

- (NSSize)intrinsicContentSize
{
    return NSMakeSize(268.0, 76.0);
}

- (void)startAnimating
{
    if (MacLCDesign.reducedMotion) {
        for (CALayer *piece in _pieceLayers) {
            [piece removeAllAnimations];
            piece.opacity = 0.0;
        }
        return;
    }

    const CGPoint center = CGPointMake(268.0 / 2.0, 76.0 / 2.0);
    const NSTimeInterval totalDuration = 1.2;

    for (NSUInteger i = 0; i < _pieceLayers.count; i++) {
        CALayer *piece = _pieceLayers[i];
        CGPoint dotPos = NSPointToCGPoint([_dotPositions[i] pointValue]);

        CAKeyframeAnimation *posAnim = [CAKeyframeAnimation animationWithKeyPath:@"position"];
        posAnim.values = @[
            [NSValue valueWithPoint:NSPointFromCGPoint(dotPos)],
            [NSValue valueWithPoint:NSPointFromCGPoint(center)],
            [NSValue valueWithPoint:NSPointFromCGPoint(center)]
        ];
        posAnim.keyTimes = @[@0.0, @0.35, @1.0];
        posAnim.timingFunctions = @[
            [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseIn],
            [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear]
        ];

        CAKeyframeAnimation *opacityAnim = [CAKeyframeAnimation animationWithKeyPath:@"opacity"];
        opacityAnim.values = @[@0.0, @1.0, @1.0, @0.0, @0.0];
        opacityAnim.keyTimes = @[@0.0, @0.05, @0.30, @0.35, @1.0];

        CAAnimationGroup *group = [CAAnimationGroup animation];
        group.animations = @[posAnim, opacityAnim];
        group.duration = totalDuration;
        group.timeOffset = i * (totalDuration / 6.0);
        group.repeatCount = HUGE_VALF;
        group.removedOnCompletion = NO;

        [piece addAnimation:group forKey:@"travel"];
    }
}

- (void)stopAnimating
{
    for (CALayer *piece in _pieceLayers) {
        [piece removeAllAnimations];
        piece.opacity = 0.0;
    }
}

@end

#pragma mark - Illustration 2: Health

@interface MacLCHealthIllustrationView : MacLCExplainerIllustrationBaseView
@end

@implementation MacLCHealthIllustrationView {
    NSMutableArray<CALayer *> *_barFillLayers;
}

- (instancetype)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (self) {
        self.wantsLayer = YES;
        _barFillLayers = [NSMutableArray array];

        const CGFloat barW = 8.0;
        const CGFloat gap = 5.0;
        const CGFloat heights[4] = { 8.0, 14.0, 20.0, 26.0 };
        const CGFloat totalW = 4 * barW + 3 * gap;
        const CGFloat startX = (268.0 - totalW) / 2.0;
        const CGFloat baseY = 14.0;

        NSTextField *fewLabel = [NSTextField labelWithString:_NS("Few")];
        fewLabel.font = MacLCDesign.caption;
        fewLabel.textColor = MacLCDesign.secondaryLabel;
        fewLabel.alignment = NSTextAlignmentRight;
        fewLabel.frame = NSMakeRect(startX - 52.0, baseY + 4.0, 44.0, 16.0);
        [self addSubview:fewLabel];

        NSTextField *manyLabel = [NSTextField labelWithString:_NS("Many")];
        manyLabel.font = MacLCDesign.caption;
        manyLabel.textColor = MacLCDesign.secondaryLabel;
        manyLabel.frame = NSMakeRect(startX + totalW + 8.0, baseY + 4.0, 50.0, 16.0);
        [self addSubview:manyLabel];

        for (NSUInteger i = 0; i < 4; i++) {
            const CGFloat bx = startX + i * (barW + gap);
            const CGFloat bh = heights[i];

            CALayer *bgBar = [CALayer layer];
            bgBar.frame = CGRectMake(bx, baseY, barW, bh);
            bgBar.cornerRadius = 2.0;
            bgBar.backgroundColor = [[NSColor labelColor] colorWithAlphaComponent:0.12].CGColor;
            [self.layer addSublayer:bgBar];

            CALayer *fillBar = [CALayer layer];
            fillBar.frame = CGRectMake(bx, baseY, barW, bh);
            fillBar.cornerRadius = 2.0;
            fillBar.backgroundColor = [NSColor systemGreenColor].CGColor;
            fillBar.opacity = 1.0;
            [self.layer addSublayer:fillBar];
            [_barFillLayers addObject:fillBar];
        }
    }
    return self;
}

- (NSSize)intrinsicContentSize
{
    return NSMakeSize(268.0, 52.0);
}

- (void)startAnimating
{
    if (MacLCDesign.reducedMotion) {
        for (CALayer *fill in _barFillLayers) {
            [fill removeAllAnimations];
            fill.opacity = 1.0;
        }
        return;
    }

    const NSTimeInterval loopDuration = 2.2;
    for (NSUInteger i = 0; i < _barFillLayers.count; i++) {
        CALayer *fill = _barFillLayers[i];
        const CGFloat tFill = (CGFloat)(i * 0.25 / loopDuration);
        const CGFloat tHold = (CGFloat)(1.6 / loopDuration);
        const CGFloat tReset = (CGFloat)(1.9 / loopDuration);

        CAKeyframeAnimation *anim = [CAKeyframeAnimation animationWithKeyPath:@"opacity"];
        anim.keyTimes = @[ @0.0, @(tFill), @(tFill + 0.05), @(tHold), @(tReset), @1.0 ];
        anim.values = @[ @0.15, @0.15, @1.0, @1.0, @0.15, @0.15 ];
        anim.duration = loopDuration;
        anim.repeatCount = HUGE_VALF;
        anim.removedOnCompletion = NO;

        [fill addAnimation:anim forKey:@"healthPulse"];
    }
}

- (void)stopAnimating
{
    for (CALayer *fill in _barFillLayers) {
        [fill removeAllAnimations];
        fill.opacity = 1.0;
    }
}

@end

#pragma mark - Illustration 3: Dynamic Range

@interface MacLCDynamicRangeIllustrationView : MacLCExplainerIllustrationBaseView
@end

@implementation MacLCDynamicRangeIllustrationView {
    CAGradientLayer *_gradientLayer;
    CALayer *_glowLayer;
}

- (instancetype)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (self) {
        self.wantsLayer = YES;

        const CGFloat barW = 236.0;
        const CGFloat barH = 14.0;
        const CGFloat startX = (268.0 - barW) / 2.0;
        const CGFloat barY = 26.0;

        _gradientLayer = [CAGradientLayer layer];
        _gradientLayer.frame = CGRectMake(startX, barY, barW, barH);
        _gradientLayer.cornerRadius = 7.0;
        _gradientLayer.startPoint = CGPointMake(0.0, 0.5);
        _gradientLayer.endPoint = CGPointMake(1.0, 0.5);

        NSColor *c0 = [NSColor colorWithWhite:0.0 alpha:1.0];
        NSColor *c1 = [NSColor colorWithWhite:0.85 alpha:1.0];
        NSColor *c2 = [NSColor colorWithWhite:1.0 alpha:1.0];
        NSColor *c3 = [NSColor colorWithRed:1.0 green:0.92 blue:0.75 alpha:1.0];

        _gradientLayer.colors = @[ (id)c0.CGColor, (id)c1.CGColor, (id)c2.CGColor, (id)c3.CGColor ];
        _gradientLayer.locations = @[ @0.0, @0.42, @0.45, @1.0 ];
        [self.layer addSublayer:_gradientLayer];

        // Marker for "100 nits" at 0.45 mark
        const CGFloat markerX = startX + barW * 0.45;
        CALayer *tick = [CALayer layer];
        tick.frame = CGRectMake(markerX - 0.5, barY - 3.0, 1.0, barH + 6.0);
        tick.backgroundColor = [NSColor labelColor].CGColor;
        [self.layer addSublayer:tick];

        // Glow layer over HDR segment (0.45 to 1.0)
        _glowLayer = [CALayer layer];
        _glowLayer.frame = CGRectMake(markerX, barY, barW * 0.55, barH);
        _glowLayer.cornerRadius = 7.0;
        _glowLayer.shadowColor = [NSColor colorWithRed:1.0 green:0.85 blue:0.4 alpha:1.0].CGColor;
        _glowLayer.shadowRadius = 8.0;
        _glowLayer.shadowOpacity = 0.5;
        _glowLayer.shadowOffset = CGSizeZero;
        [self.layer addSublayer:_glowLayer];

        NSTextField *sdrLabel = [NSTextField labelWithString:_NS("SDR")];
        sdrLabel.font = MacLCDesign.caption;
        sdrLabel.textColor = MacLCDesign.secondaryLabel;
        sdrLabel.frame = NSMakeRect(startX, 6.0, 60.0, 16.0);
        [self addSubview:sdrLabel];

        NSTextField *nitsLabel = [NSTextField labelWithString:_NS("100 nits")];
        nitsLabel.font = MacLCDesign.caption;
        nitsLabel.textColor = MacLCDesign.secondaryLabel;
        nitsLabel.alignment = NSTextAlignmentCenter;
        nitsLabel.frame = NSMakeRect(markerX - 35.0, 6.0, 70.0, 16.0);
        [self addSubview:nitsLabel];

        NSTextField *hdrLabel = [NSTextField labelWithString:_NS("HDR")];
        hdrLabel.font = [NSFont systemFontOfSize:11.0 weight:NSFontWeightSemibold];
        hdrLabel.textColor = [NSColor systemPurpleColor];
        hdrLabel.alignment = NSTextAlignmentRight;
        hdrLabel.frame = NSMakeRect(startX + barW - 60.0, 6.0, 60.0, 16.0);
        [self addSubview:hdrLabel];
    }
    return self;
}

- (NSSize)intrinsicContentSize
{
    return NSMakeSize(268.0, 56.0);
}

- (void)startAnimating
{
    if (MacLCDesign.reducedMotion) {
        [_glowLayer removeAllAnimations];
        _glowLayer.shadowOpacity = 0.5;
        return;
    }

    CABasicAnimation *pulse = [CABasicAnimation animationWithKeyPath:@"shadowOpacity"];
    pulse.fromValue = @0.3;
    pulse.toValue = @0.95;
    pulse.duration = 1.3;
    pulse.autoreverses = YES;
    pulse.repeatCount = HUGE_VALF;
    pulse.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    [_glowLayer addAnimation:pulse forKey:@"hdrGlow"];
}

- (void)stopAnimating
{
    [_glowLayer removeAllAnimations];
    _glowLayer.shadowOpacity = 0.5;
}

@end

#pragma mark - Illustration 4: Resolution

@interface MacLCResolutionIllustrationView : MacLCExplainerIllustrationBaseView
@end

@implementation MacLCResolutionIllustrationView {
    CAShapeLayer *_layer4K;
    CAShapeLayer *_layer1080p;
    CAShapeLayer *_layer720p;
}

- (instancetype)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (self) {
        self.wantsLayer = YES;

        // Nested rectangles 720p ⊂ 1080p ⊂ 4K drawn to scale
        // 4K: 144 × 81, 1080p: 72 × 40.5, 720p: 48 × 27
        const CGFloat x0 = (268.0 - 144.0) / 2.0;
        const CGFloat y0 = 6.0;

        _layer4K = [self shapeLayerWithRect:CGRectMake(x0, y0, 144.0, 81.0) cornerRadius:4.0 alpha:0.06];
        [self.layer addSublayer:_layer4K];

        _layer1080p = [self shapeLayerWithRect:CGRectMake(x0, y0, 72.0, 40.5) cornerRadius:3.0 alpha:0.09];
        [self.layer addSublayer:_layer1080p];

        _layer720p = [self shapeLayerWithRect:CGRectMake(x0, y0, 48.0, 27.0) cornerRadius:2.0 alpha:0.14];
        [self.layer addSublayer:_layer720p];

        NSTextField *label720 = [NSTextField labelWithString:@"720p"];
        label720.font = [NSFont systemFontOfSize:9.0 weight:NSFontWeightMedium];
        label720.textColor = MacLCDesign.secondaryLabel;
        label720.frame = NSMakeRect(x0 + 4.0, y0 + 4.0, 40.0, 14.0);
        [self addSubview:label720];

        NSTextField *label1080 = [NSTextField labelWithString:@"1080p"];
        label1080.font = [NSFont systemFontOfSize:10.0 weight:NSFontWeightMedium];
        label1080.textColor = MacLCDesign.secondaryLabel;
        label1080.frame = NSMakeRect(x0 + 4.0, y0 + 40.5 - 16.0, 44.0, 14.0);
        [self addSubview:label1080];

        NSTextField *label4K = [NSTextField labelWithString:@"4K"];
        label4K.font = [NSFont systemFontOfSize:11.0 weight:NSFontWeightBold];
        label4K.textColor = [NSColor systemPurpleColor];
        label4K.alignment = NSTextAlignmentRight;
        label4K.frame = NSMakeRect(x0 + 144.0 - 40.0, y0 + 81.0 - 18.0, 36.0, 16.0);
        [self addSubview:label4K];
    }
    return self;
}

- (CAShapeLayer *)shapeLayerWithRect:(CGRect)rect cornerRadius:(CGFloat)radius alpha:(CGFloat)alpha
{
    CAShapeLayer *layer = [CAShapeLayer layer];
    CGPathRef cgPath = CGPathCreateWithRoundedRect(rect, radius, radius, NULL);
    layer.path = cgPath;
    CGPathRelease(cgPath);

    layer.strokeColor = [NSColor systemPurpleColor].CGColor;
    layer.fillColor = [[NSColor systemPurpleColor] colorWithAlphaComponent:alpha].CGColor;
    layer.lineWidth = 1.0;
    return layer;
}

- (NSSize)intrinsicContentSize
{
    return NSMakeSize(268.0, 94.0);
}

- (void)startAnimating
{
    if (MacLCDesign.reducedMotion) {
        [_layer720p removeAllAnimations];
        [_layer1080p removeAllAnimations];
        [_layer4K removeAllAnimations];
        _layer720p.lineWidth = 1.0;
        _layer1080p.lineWidth = 1.0;
        _layer4K.lineWidth = 1.0;
        return;
    }

    const NSTimeInterval cycle = 2.4;
    NSArray *layers = @[ _layer720p, _layer1080p, _layer4K ];

    for (NSUInteger i = 0; i < layers.count; i++) {
        CAShapeLayer *l = layers[i];
        CAKeyframeAnimation *anim = [CAKeyframeAnimation animationWithKeyPath:@"lineWidth"];
        const CGFloat tStart = (CGFloat)(i * 0.8 / cycle);
        const CGFloat tPeak = (CGFloat)((i * 0.8 + 0.3) / cycle);
        const CGFloat tEnd = (CGFloat)((i * 0.8 + 0.7) / cycle);

        anim.keyTimes = @[ @0.0, @(tStart), @(tPeak), @(tEnd), @1.0 ];
        anim.values = @[ @1.0, @1.0, @2.5, @1.0, @1.0 ];
        anim.duration = cycle;
        anim.repeatCount = HUGE_VALF;
        anim.removedOnCompletion = NO;

        [l addAnimation:anim forKey:@"strokePulse"];
    }
}

- (void)stopAnimating
{
    [_layer720p removeAllAnimations];
    [_layer1080p removeAllAnimations];
    [_layer4K removeAllAnimations];
    _layer720p.lineWidth = 1.0;
    _layer1080p.lineWidth = 1.0;
    _layer4K.lineWidth = 1.0;
}

@end

#pragma mark - Illustration 5: Surround

@interface MacLCSurroundIllustrationView : MacLCExplainerIllustrationBaseView
@end

@implementation MacLCSurroundIllustrationView {
    NSMutableArray<CAShapeLayer *> *_speakerLayers;
    NSMutableArray<CAShapeLayer *> *_pulseLayers;
}

- (instancetype)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (self) {
        self.wantsLayer = YES;
        _speakerLayers = [NSMutableArray array];
        _pulseLayers = [NSMutableArray array];

        const CGFloat cx = 268.0 / 2.0;
        const CGFloat cy = 40.0;

        // Couch in the center
        CALayer *couch = [CALayer layer];
        couch.bounds = CGRectMake(0, 0, 44.0, 22.0);
        couch.position = CGPointMake(cx, cy);
        couch.cornerRadius = 6.0;
        couch.backgroundColor = [[NSColor labelColor] colorWithAlphaComponent:0.18].CGColor;
        [self.layer addSublayer:couch];

        // Speaker positions: 5.1/7.1 surround + overhead Atmos speakers
        const CGPoint speakers[9] = {
            CGPointMake(cx - 56.0, cy + 28.0), // Front Left
            CGPointMake(cx,        cy + 34.0), // Center
            CGPointMake(cx + 56.0, cy + 28.0), // Front Right
            CGPointMake(cx + 66.0, cy - 2.0),  // Surround Right
            CGPointMake(cx + 46.0, cy - 28.0), // Rear Right
            CGPointMake(cx - 46.0, cy - 28.0), // Rear Left
            CGPointMake(cx - 66.0, cy - 2.0),  // Surround Left
            CGPointMake(cx - 24.0, cy + 12.0), // Height Left (Atmos)
            CGPointMake(cx + 24.0, cy + 12.0)  // Height Right (Atmos)
        };

        for (NSUInteger i = 0; i < 9; i++) {
            CGPoint pt = speakers[i];

            // Wave pulse layer
            CAShapeLayer *pulse = [CAShapeLayer layer];
            pulse.bounds = CGRectMake(0, 0, 24, 24);
            pulse.position = pt;
            CGMutablePathRef pulsePath = CGPathCreateMutable();
            CGPathAddEllipseInRect(pulsePath, NULL, CGRectMake(0, 0, 24, 24));
            pulse.path = pulsePath;
            CGPathRelease(pulsePath);
            pulse.strokeColor = [NSColor systemPinkColor].CGColor;
            pulse.fillColor = nil;
            pulse.lineWidth = 1.0;
            pulse.opacity = 0.0;
            [self.layer addSublayer:pulse];
            [_pulseLayers addObject:pulse];

            // Speaker dot
            CAShapeLayer *dot = [CAShapeLayer layer];
            dot.bounds = CGRectMake(0, 0, 8, 8);
            dot.position = pt;
            CGMutablePathRef dotPath = CGPathCreateMutable();
            CGPathAddEllipseInRect(dotPath, NULL, CGRectMake(0, 0, 8, 8));
            dot.path = dotPath;
            CGPathRelease(dotPath);
            dot.fillColor = [NSColor systemPinkColor].CGColor;
            [self.layer addSublayer:dot];
            [_speakerLayers addObject:dot];
        }
    }
    return self;
}

- (NSSize)intrinsicContentSize
{
    return NSMakeSize(268.0, 86.0);
}

- (void)startAnimating
{
    if (MacLCDesign.reducedMotion) {
        for (CAShapeLayer *p in _pulseLayers) {
            [p removeAllAnimations];
            p.opacity = 0.0;
        }
        return;
    }

    const NSTimeInterval cycle = 2.4;
    for (NSUInteger i = 0; i < _pulseLayers.count; i++) {
        CAShapeLayer *pulse = _pulseLayers[i];

        CABasicAnimation *scaleAnim = [CABasicAnimation animationWithKeyPath:@"transform.scale"];
        scaleAnim.fromValue = @0.3;
        scaleAnim.toValue = @1.4;

        CABasicAnimation *fadeAnim = [CABasicAnimation animationWithKeyPath:@"opacity"];
        fadeAnim.fromValue = @0.8;
        fadeAnim.toValue = @0.0;

        CAAnimationGroup *group = [CAAnimationGroup animation];
        group.animations = @[ scaleAnim, fadeAnim ];
        group.duration = 0.6;
        group.timeOffset = i * (cycle / 9.0);
        group.repeatCount = HUGE_VALF;
        group.removedOnCompletion = NO;

        [pulse addAnimation:group forKey:@"soundWave"];
    }
}

- (void)stopAnimating
{
    for (CAShapeLayer *p in _pulseLayers) {
        [p removeAllAnimations];
        p.opacity = 0.0;
    }
}

@end

#pragma mark - Popover Content View & View Controller

@interface MacLCExplainerViewController : NSViewController
@property (nonatomic, copy) MacLCExplainerTopic topic;
@property (nonatomic, strong, nullable) MacLCExplainerIllustrationBaseView *illustrationView;
@end

@implementation MacLCExplainerViewController

- (instancetype)initWithTopic:(MacLCExplainerTopic)topic
{
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _topic = [topic copy];
    }
    return self;
}

- (void)loadView
{
    NSView *rootView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 300, 200)];
    rootView.translatesAutoresizingMaskIntoConstraints = NO;

    NSStackView *stack = [[NSStackView alloc] initWithFrame:NSZeroRect];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 8.0;
    stack.edgeInsets = NSEdgeInsetsMake(16, 16, 16, 16);
    [rootView addSubview:stack];

    [NSLayoutConstraint activateConstraints:@[
        [rootView.widthAnchor constraintEqualToConstant:300.0],
        [stack.leadingAnchor constraintEqualToAnchor:rootView.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:rootView.trailingAnchor],
        [stack.topAnchor constraintEqualToAnchor:rootView.topAnchor],
        [stack.bottomAnchor constraintEqualToAnchor:rootView.bottomAnchor]
    ]];

    // 44 pt circle with 15% tint containing 28 pt filled SF symbol
    NSColor *tint = [MacLCExplainer tintForTopic:_topic];
    NSView *circleView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 44, 44)];
    circleView.translatesAutoresizingMaskIntoConstraints = NO;
    circleView.wantsLayer = YES;
    circleView.layer.cornerRadius = 22.0;
    circleView.layer.backgroundColor = [tint colorWithAlphaComponent:0.15].CGColor;

    [NSLayoutConstraint activateConstraints:@[
        [circleView.widthAnchor constraintEqualToConstant:44.0],
        [circleView.heightAnchor constraintEqualToConstant:44.0]
    ]];

    NSString *symbolName = [MacLCExplainer symbolNameForTopic:_topic];
    NSImage *symbolImg = [MacLCDesign symbolNamed:symbolName pointSize:28.0 weight:NSFontWeightMedium accessibilityLabel:nil];
    NSImageView *symbolImageView = [[NSImageView alloc] initWithFrame:NSMakeRect(0, 0, 28, 28)];
    symbolImageView.translatesAutoresizingMaskIntoConstraints = NO;
    symbolImageView.image = symbolImg;
    symbolImageView.contentTintColor = tint;

    [circleView addSubview:symbolImageView];
    [NSLayoutConstraint activateConstraints:@[
        [symbolImageView.centerXAnchor constraintEqualToAnchor:circleView.centerXAnchor],
        [symbolImageView.centerYAnchor constraintEqualToAnchor:circleView.centerYAnchor],
        [symbolImageView.widthAnchor constraintEqualToConstant:28.0],
        [symbolImageView.heightAnchor constraintEqualToConstant:28.0]
    ]];

    [stack addArrangedSubview:circleView];
    [stack setCustomSpacing:12.0 afterView:circleView];

    // Headline Title
    NSTextField *titleLabel = [NSTextField wrappingLabelWithString:[MacLCExplainer titleForTopic:_topic]];
    titleLabel.selectable = NO;
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    titleLabel.font = MacLCDesign.headline;
    titleLabel.textColor = MacLCDesign.primaryLabel;
    titleLabel.maximumNumberOfLines = 2;
    titleLabel.preferredMaxLayoutWidth = 268.0;
    [stack addArrangedSubview:titleLabel];
    [stack setCustomSpacing:6.0 afterView:titleLabel];

    // Body Explanation
    NSTextField *bodyLabel = [NSTextField wrappingLabelWithString:[MacLCExplainer explanationForTopic:_topic]];
    bodyLabel.selectable = NO;
    bodyLabel.translatesAutoresizingMaskIntoConstraints = NO;
    bodyLabel.font = MacLCDesign.body;
    bodyLabel.textColor = MacLCDesign.secondaryLabel;
    bodyLabel.maximumNumberOfLines = 0;
    bodyLabel.preferredMaxLayoutWidth = 268.0;
    [stack addArrangedSubview:bodyLabel];

    // Consequence line ("What this means for you")
    NSString *consequence = [MacLCExplainer consequenceForTopic:_topic];
    if (consequence.length > 0) {
        [stack setCustomSpacing:10.0 afterView:bodyLabel];
        NSTextField *consequenceLabel = [NSTextField wrappingLabelWithString:consequence];
    consequenceLabel.selectable = NO;
        consequenceLabel.translatesAutoresizingMaskIntoConstraints = NO;
        consequenceLabel.font = MacLCDesign.callout;
        consequenceLabel.textColor = MacLCDesign.primaryLabel;
        consequenceLabel.maximumNumberOfLines = 0;
        consequenceLabel.preferredMaxLayoutWidth = 268.0;
        [stack addArrangedSubview:consequenceLabel];
    }

    // Illustration View
    MacLCExplainerIllustration ill = [MacLCExplainer illustrationForTopic:_topic];
    if (ill != MacLCExplainerIllustrationNone) {
        _illustrationView = [self illustrationViewForType:ill];
        if (_illustrationView) {
            _illustrationView.translatesAutoresizingMaskIntoConstraints = NO;
            NSView *prev = stack.arrangedSubviews.lastObject;
            [stack setCustomSpacing:14.0 afterView:prev];
            [stack addArrangedSubview:_illustrationView];
        }
    }

    self.view = rootView;
}

- (nullable MacLCExplainerIllustrationBaseView *)illustrationViewForType:(MacLCExplainerIllustration)type
{
    switch (type) {
        case MacLCExplainerIllustrationPeers:
            return [[MacLCPeersIllustrationView alloc] initWithFrame:NSMakeRect(0, 0, 268, 76)];
        case MacLCExplainerIllustrationHealth:
            return [[MacLCHealthIllustrationView alloc] initWithFrame:NSMakeRect(0, 0, 268, 52)];
        case MacLCExplainerIllustrationDynamicRange:
            return [[MacLCDynamicRangeIllustrationView alloc] initWithFrame:NSMakeRect(0, 0, 268, 56)];
        case MacLCExplainerIllustrationResolution:
            return [[MacLCResolutionIllustrationView alloc] initWithFrame:NSMakeRect(0, 0, 268, 94)];
        case MacLCExplainerIllustrationSurround:
            return [[MacLCSurroundIllustrationView alloc] initWithFrame:NSMakeRect(0, 0, 268, 86)];
        case MacLCExplainerIllustrationNone:
        default:
            return nil;
    }
}

- (void)viewDidAppear
{
    [super viewDidAppear];
    [_illustrationView startAnimating];
}

- (void)viewWillDisappear
{
    [super viewWillDisappear];
    [_illustrationView stopAnimating];
}

@end

#pragma mark - Attachment Manager & Popover Delegate

@interface MacLCExplainerAttachment : NSObject
@property (nonatomic, weak) NSView *view;
@property (nonatomic, copy) MacLCExplainerTopic topic;
@property (nonatomic, strong, nullable) NSTrackingArea *trackingArea;
@property (nonatomic, strong, nullable) NSClickGestureRecognizer *clickRecognizer;

- (instancetype)initWithView:(NSView *)view topic:(MacLCExplainerTopic)topic;
- (void)detach;
@end

@interface MacLCExplainerManager : NSObject <NSPopoverDelegate>
@property (nonatomic, strong, nullable) NSPopover *popover;
@property (nonatomic, strong, nullable) MacLCExplainerViewController *viewController;
@property (nonatomic, strong, nullable) NSTimer *hoverTimer;
@property (nonatomic, strong, nullable) NSTimer *dismissTimer;
@property (nonatomic, weak, nullable) NSView *activeSourceView;
@property (nonatomic, copy, nullable) MacLCExplainerTopic activeTopic;
@property (nonatomic, assign) BOOL isMouseInSourceView;
@property (nonatomic, assign) BOOL isMouseInPopover;
@property (nonatomic, strong, nullable) id keyEventMonitor;

+ (instancetype)sharedManager;
- (void)scheduleHoverForTopic:(MacLCExplainerTopic)topic view:(NSView *)view;
- (void)cancelHover;
- (void)scheduleDismiss;
- (void)cancelDismiss;
- (void)showTopic:(MacLCExplainerTopic)topic relativeToView:(NSView *)view;
- (void)dismiss;
@end

static const char kMacLCExplainerAttachmentKey = 0;

@implementation MacLCExplainerAttachment

- (instancetype)initWithView:(NSView *)view topic:(MacLCExplainerTopic)topic
{
    self = [super init];
    if (self) {
        _view = view;
        _topic = [topic copy];

        NSTrackingAreaOptions options = (NSTrackingMouseEnteredAndExited |
                                         NSTrackingMouseMoved |
                                         NSTrackingActiveAlways |
                                         NSTrackingInVisibleRect);
        _trackingArea = [[NSTrackingArea alloc] initWithRect:view.bounds
                                                     options:options
                                                       owner:self
                                                    userInfo:nil];
        [view addTrackingArea:_trackingArea];

        // Accessibility Help & Action
        NSString *explanation = [MacLCExplainer explanationForTopic:topic];
        NSString *consequence = [MacLCExplainer consequenceForTopic:topic];
        NSString *help = explanation;
        if (consequence.length > 0) {
            help = [NSString stringWithFormat:@"%@ %@", explanation, consequence];
        }
        view.accessibilityHelp = help;

        NSAccessibilityCustomAction *explainAction =
            [[NSAccessibilityCustomAction alloc] initWithName:_NS("Explain")
                                                       target:self
                                                     selector:@selector(accessibilityExplainAction)];
        view.accessibilityCustomActions = @[ explainAction ];

        // Click on plain view (when not a control with its own action) opens the tip
        BOOL hasOwnAction = NO;
        if ([view isKindOfClass:[NSControl class]]) {
            NSControl *control = (NSControl *)view;
            if (control.target != nil && control.action != NULL) {
                hasOwnAction = YES;
            }
        }
        if (!hasOwnAction) {
            _clickRecognizer = [[NSClickGestureRecognizer alloc] initWithTarget:self action:@selector(viewClicked:)];
            [view addGestureRecognizer:_clickRecognizer];
        }
    }
    return self;
}

- (void)detach
{
    if (_view) {
        if (_trackingArea) {
            [_view removeTrackingArea:_trackingArea];
            _trackingArea = nil;
        }
        if (_clickRecognizer) {
            [_view removeGestureRecognizer:_clickRecognizer];
            _clickRecognizer = nil;
        }
        _view.accessibilityHelp = nil;
        _view.accessibilityCustomActions = nil;
    }
}

- (BOOL)accessibilityExplainAction
{
    if (_view && _topic) {
        [[MacLCExplainerManager sharedManager] showTopic:_topic relativeToView:_view];
        return YES;
    }
    return NO;
}

- (void)viewClicked:(NSClickGestureRecognizer *)recognizer
{
    if (_view && _topic) {
        [[MacLCExplainerManager sharedManager] showTopic:_topic relativeToView:_view];
    }
}

- (void)mouseEntered:(NSEvent *)event
{
    MacLCExplainerManager *mgr = [MacLCExplainerManager sharedManager];
    if (mgr.activeSourceView == _view) {
        mgr.isMouseInSourceView = YES;
        [mgr cancelDismiss];
    } else {
        [mgr scheduleHoverForTopic:_topic view:_view];
    }
}

- (void)mouseMoved:(NSEvent *)event
{
    MacLCExplainerManager *mgr = [MacLCExplainerManager sharedManager];
    if (mgr.activeSourceView != _view || mgr.popover == nil || !mgr.popover.isShown) {
        [mgr scheduleHoverForTopic:_topic view:_view];
    }
}

- (void)mouseExited:(NSEvent *)event
{
    MacLCExplainerManager *mgr = [MacLCExplainerManager sharedManager];
    [mgr cancelHover];
    if (mgr.activeSourceView == _view) {
        mgr.isMouseInSourceView = NO;
        if (!mgr.isMouseInPopover) {
            [mgr scheduleDismiss];
        }
    }
}

@end

#pragma mark - Explainer Manager

@implementation MacLCExplainerManager

+ (instancetype)sharedManager
{
    static MacLCExplainerManager *s_manager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        s_manager = [[MacLCExplainerManager alloc] init];
    });
    return s_manager;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        __weak typeof(self) weakSelf = self;
        _keyEventMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown
                                                                 handler:^NSEvent * _Nullable(NSEvent * _Nonnull event) {
            typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return event;

            // Escape closes the active tip
            if (event.keyCode == 53) {
                if (strongSelf.popover.isShown) {
                    [strongSelf dismiss];
                    return nil;
                }
            }

            // Space (keyCode 49) or Return (keyCode 36 or 76) while focused -> tip
            if (event.keyCode == 49 || event.keyCode == 36 || event.keyCode == 76) {
                NSResponder *responder = event.window.firstResponder;
                /* Only the focused explained view itself, never an ancestor of
                 * a text field or a control: their keys stay theirs. */
                if ([responder isKindOfClass:[NSView class]] && ![responder isKindOfClass:[NSText class]]) {
                    NSView *v = (NSView *)responder;
                    MacLCExplainerAttachment *attachment = objc_getAssociatedObject(v, &kMacLCExplainerAttachmentKey);
                    if (attachment && attachment.topic.length > 0) {
                        [strongSelf showTopic:attachment.topic relativeToView:v];
                        return nil;
                    }
                }
            }
            return event;
        }];
    }
    return self;
}

- (void)dealloc
{
    if (_keyEventMonitor) {
        [NSEvent removeMonitor:_keyEventMonitor];
        _keyEventMonitor = nil;
    }
    [_hoverTimer invalidate];
    [_dismissTimer invalidate];
}

- (void)scheduleHoverForTopic:(MacLCExplainerTopic)topic view:(NSView *)view
{
    [_hoverTimer invalidate];
    __weak typeof(self) weakSelf = self;
    _hoverTimer = [NSTimer scheduledTimerWithTimeInterval:0.6
                                                  repeats:NO
                                                    block:^(NSTimer * _Nonnull timer) {
        typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf && view.window != nil) {
            NSPoint mouseLoc = [NSEvent mouseLocation];
            NSRect screenRect = [view.window convertRectToScreen:[view convertRect:view.bounds toView:nil]];
            if (NSPointInRect(mouseLoc, screenRect)) {
                [strongSelf showTopic:topic relativeToView:view];
            }
        }
    }];
}

- (void)cancelHover
{
    [_hoverTimer invalidate];
    _hoverTimer = nil;
}

- (void)scheduleDismiss
{
    [_dismissTimer invalidate];
    __weak typeof(self) weakSelf = self;
    _dismissTimer = [NSTimer scheduledTimerWithTimeInterval:0.25
                                                    repeats:NO
                                                      block:^(NSTimer * _Nonnull timer) {
        typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf || !strongSelf.popover.isShown) return;

        NSPoint mouseLoc = [NSEvent mouseLocation];
        NSWindow *popoverWindow = strongSelf.popover.contentViewController.view.window;
        if (popoverWindow != nil && NSPointInRect(mouseLoc, popoverWindow.frame)) {
            strongSelf.isMouseInPopover = YES;
            return;
        }

        NSView *sourceView = strongSelf.activeSourceView;
        if (sourceView != nil && sourceView.window != nil) {
            NSRect screenRect = [sourceView.window convertRectToScreen:[sourceView convertRect:sourceView.bounds toView:nil]];
            if (NSPointInRect(mouseLoc, screenRect)) {
                strongSelf.isMouseInSourceView = YES;
                return;
            }
        }

        [strongSelf dismiss];
    }];
}

- (void)cancelDismiss
{
    [_dismissTimer invalidate];
    _dismissTimer = nil;
}

- (void)showTopic:(MacLCExplainerTopic)topic relativeToView:(NSView *)view
{
    [self cancelHover];
    [self cancelDismiss];

    if (_popover.isShown) {
        [_popover close];
    }

    if (!view || !view.window) {
        return;
    }

    _activeSourceView = view;
    _activeTopic = [topic copy];
    _isMouseInSourceView = YES;
    _isMouseInPopover = NO;

    _viewController = [[MacLCExplainerViewController alloc] initWithTopic:topic];
    NSView *contentView = _viewController.view;

    // Add mouse tracking to popover content view so hover does not close while over tip
    NSTrackingAreaOptions options = (NSTrackingMouseEnteredAndExited |
                                     NSTrackingActiveAlways |
                                     NSTrackingInVisibleRect);
    NSTrackingArea *popoverTracking = [[NSTrackingArea alloc] initWithRect:contentView.bounds
                                                                   options:options
                                                                     owner:self
                                                                  userInfo:nil];
    [contentView addTrackingArea:popoverTracking];

    _popover = [[NSPopover alloc] init];
    _popover.behavior = NSPopoverBehaviorTransient;
    _popover.animates = YES;
    _popover.contentViewController = _viewController;
    _popover.appearance = view.window.appearance;
    _popover.delegate = self;

    [contentView layoutSubtreeIfNeeded];
    NSSize fit = [contentView fittingSize];
    _popover.contentSize = NSMakeSize(300.0, fit.height);

    [_popover showRelativeToRect:view.bounds ofView:view preferredEdge:NSMaxYEdge];
}

- (void)dismiss
{
    [self cancelHover];
    [self cancelDismiss];
    if (_popover.isShown) {
        [_popover performClose:nil];
    }
}

- (void)mouseEntered:(NSEvent *)event
{
    _isMouseInPopover = YES;
    [self cancelDismiss];
}

- (void)mouseExited:(NSEvent *)event
{
    _isMouseInPopover = NO;
    if (!_isMouseInSourceView) {
        [self scheduleDismiss];
    }
}

#pragma mark - NSPopoverDelegate

- (void)popoverDidClose:(NSNotification *)notification
{
    [_viewController.illustrationView stopAnimating];
    _popover = nil;
    _viewController = nil;
    _activeSourceView = nil;
    _activeTopic = nil;
    _isMouseInSourceView = NO;
    _isMouseInPopover = NO;
    [self cancelHover];
    [self cancelDismiss];
}

@end

#pragma mark - Info Button

@interface MacLCExplainerInfoButton : NSButton
@property (nonatomic, copy) MacLCExplainerTopic topic;
@property (nonatomic, strong, nullable) NSTrackingArea *hoverArea;
@end

@implementation MacLCExplainerInfoButton

- (instancetype)initWithTopic:(MacLCExplainerTopic)topic
{
    self = [super initWithFrame:NSMakeRect(0, 0, 22, 22)];
    if (self) {
        _topic = [topic copy];
        self.bordered = NO;
        self.bezelStyle = NSBezelStyleInline;
        self.imagePosition = NSImageOnly;
        self.image = [MacLCDesign symbolNamed:@"info.circle" pointSize:16.0 weight:NSFontWeightRegular accessibilityLabel:nil];
        self.contentTintColor = MacLCDesign.secondaryLabel;
        self.target = self;
        self.action = @selector(buttonAction:);

        NSString *title = [MacLCExplainer titleForTopic:topic];
        self.accessibilityLabel = [NSString stringWithFormat:_NS("Explain %@"), title];
        /* No help tag: the tip itself opens on hover. */

        [MacLCExplainer attachToView:self topic:topic];
    }
    return self;
}

- (NSSize)intrinsicContentSize
{
    return NSMakeSize(22.0, 22.0);
}

- (void)updateTrackingAreas
{
    [super updateTrackingAreas];
    if (_hoverArea) {
        [self removeTrackingArea:_hoverArea];
    }
    NSTrackingAreaOptions options = (NSTrackingMouseEnteredAndExited |
                                     NSTrackingActiveAlways |
                                     NSTrackingInVisibleRect);
    _hoverArea = [[NSTrackingArea alloc] initWithRect:self.bounds options:options owner:self userInfo:nil];
    [self addTrackingArea:_hoverArea];
}

- (void)mouseEntered:(NSEvent *)event
{
    [super mouseEntered:event];
    self.contentTintColor = MacLCDesign.accent;
}

- (void)mouseExited:(NSEvent *)event
{
    [super mouseExited:event];
    self.contentTintColor = MacLCDesign.secondaryLabel;
}

- (void)buttonAction:(id)sender
{
    [MacLCExplainer showTopic:_topic relativeToView:self];
}

@end

#pragma mark - MacLCExplainer Implementation

@implementation MacLCExplainer

+ (NSString *)titleForTopic:(MacLCExplainerTopic)topic
{
    if ([topic isEqualToString:MacLCExplainerTopicPeers]) {
        return _NS("Peers");
    } else if ([topic isEqualToString:MacLCExplainerTopicHealth]) {
        return _NS("Connection Health");
    } else if ([topic isEqualToString:MacLCExplainerTopicTorrent]) {
        return _NS("Torrent");
    } else if ([topic isEqualToString:MacLCExplainerTopicDebrid]) {
        return _NS("Debrid Cloud");
    } else if ([topic isEqualToString:MacLCExplainerTopicSize]) {
        return _NS("File Size");
    } else if ([topic isEqualToString:MacLCExplainerTopicPack]) {
        return _NS("Season Pack");
    } else if ([topic isEqualToString:MacLCExplainerTopicProvider]) {
        return _NS("Provider");
    } else if ([topic isEqualToString:MacLCExplainerTopicResolution4K]) {
        return _NS("4K Ultra HD");
    } else if ([topic isEqualToString:MacLCExplainerTopicResolution1080p]) {
        return _NS("1080p Full HD");
    } else if ([topic isEqualToString:MacLCExplainerTopicResolution720p]) {
        return _NS("720p HD");
    } else if ([topic isEqualToString:MacLCExplainerTopicDolbyVision]) {
        return _NS("Dolby Vision");
    } else if ([topic isEqualToString:MacLCExplainerTopicHDR10Plus]) {
        return _NS("HDR10+");
    } else if ([topic isEqualToString:MacLCExplainerTopicHDR10]) {
        return _NS("HDR10");
    } else if ([topic isEqualToString:MacLCExplainerTopicHLG]) {
        return _NS("HLG");
    } else if ([topic isEqualToString:MacLCExplainerTopicSDR]) {
        return _NS("Standard Dynamic Range");
    } else if ([topic isEqualToString:MacLCExplainerTopicHEVC]) {
        return _NS("HEVC Video");
    } else if ([topic isEqualToString:MacLCExplainerTopicUpscaled]) {
        return _NS("Upscaled");
    } else if ([topic isEqualToString:MacLCExplainerTopicRemux]) {
        return _NS("Blu-ray Remux");
    } else if ([topic isEqualToString:MacLCExplainerTopicBluRay]) {
        return _NS("Blu-ray");
    } else if ([topic isEqualToString:MacLCExplainerTopicWebDL]) {
        return _NS("WEB-DL");
    } else if ([topic isEqualToString:MacLCExplainerTopicWebRip]) {
        return _NS("WEBRip");
    } else if ([topic isEqualToString:MacLCExplainerTopicCam]) {
        return _NS("Cam Recording");
    } else if ([topic isEqualToString:MacLCExplainerTopicAtmos]) {
        return _NS("Dolby Atmos");
    } else if ([topic isEqualToString:MacLCExplainerTopicLosslessAudio]) {
        return _NS("Lossless Audio");
    } else if ([topic isEqualToString:MacLCExplainerTopicSurround]) {
        return _NS("Surround Sound");
    } else if ([topic isEqualToString:MacLCExplainerTopicMultiAudio]) {
        return _NS("Multiple Audio Tracks");
    } else if ([topic isEqualToString:MacLCExplainerTopicSubtitles]) {
        return _NS("Subtitles");
    } else if ([topic isEqualToString:MacLCExplainerTopicAddons]) {
        return _NS("Add-ons");
    } else if ([topic isEqualToString:MacLCExplainerTopicServices]) {
        return _NS("Streaming Services");
    } else if ([topic isEqualToString:MacLCExplainerTopicCollections]) {
        return _NS("Collections");
    } else if ([topic isEqualToString:MacLCExplainerTopicBestMatch]) {
        return _NS("Best Match");
    } else if ([topic isEqualToString:MacLCExplainerTopicVerdict]) {
        return _NS("Version Verdict");
    }
    return topic ?: @"";
}

+ (NSString *)explanationForTopic:(MacLCExplainerTopic)topic
{
    if ([topic isEqualToString:MacLCExplainerTopicPeers]) {
        return _NS("People who have this video and are sending you pieces of it right now. MacLC gets the video from many of them at once.");
    } else if ([topic isEqualToString:MacLCExplainerTopicHealth]) {
        return _NS("How reliably this video can stream right now, based on how many people are currently sharing pieces of it.");
    } else if ([topic isEqualToString:MacLCExplainerTopicTorrent]) {
        return _NS("A way of streaming video directly between people across the internet, without a central company hosting the file.");
    } else if ([topic isEqualToString:MacLCExplainerTopicDebrid]) {
        return _NS("This version is stored on a paid download service you've connected, so it doesn't depend on other people sharing it.");
    } else if ([topic isEqualToString:MacLCExplainerTopicSize]) {
        return _NS("How much data plays through your connection. On a metered or mobile connection, smaller is kinder.");
    } else if ([topic isEqualToString:MacLCExplainerTopicPack]) {
        return _NS("A single collection containing every episode of a season together, rather than separate single-episode downloads.");
    } else if ([topic isEqualToString:MacLCExplainerTopicProvider]) {
        return _NS("The community catalog or indexing site where your installed add-on found this specific version.");
    } else if ([topic isEqualToString:MacLCExplainerTopicResolution4K]) {
        return _NS("An ultra-sharp picture with four times the detail of standard high definition, ideal for large screens and Retina displays.");
    } else if ([topic isEqualToString:MacLCExplainerTopicResolution1080p]) {
        return _NS("The crisp high-definition standard used by most modern streaming services and Blu-ray discs.");
    } else if ([topic isEqualToString:MacLCExplainerTopicResolution720p]) {
        return _NS("Standard high definition that delivers smooth video while using less internet data.");
    } else if ([topic isEqualToString:MacLCExplainerTopicDolbyVision]) {
        return _NS("A form of HDR that adjusts brightness scene by scene for richer highlights and deeper shadows. Your Mac shows it when its display supports HDR.");
    } else if ([topic isEqualToString:MacLCExplainerTopicHDR10Plus]) {
        return _NS("An enhanced high dynamic range format that tunes picture brightness dynamically throughout each scene.");
    } else if ([topic isEqualToString:MacLCExplainerTopicHDR10]) {
        return _NS("The universal high dynamic range standard, unlocking wider color range and brighter highlights than standard video.");
    } else if ([topic isEqualToString:MacLCExplainerTopicHLG]) {
        return _NS("Hybrid Log-Gamma, an HDR broadcast format that delivers vibrant color on HDR screens while staying compatible with regular displays.");
    } else if ([topic isEqualToString:MacLCExplainerTopicSDR]) {
        return _NS("Standard brightness and color designed for conventional computer monitors and televisions.");
    } else if ([topic isEqualToString:MacLCExplainerTopicHEVC]) {
        return _NS("A modern video format that halves the file size while keeping high picture quality.");
    } else if ([topic isEqualToString:MacLCExplainerTopicUpscaled]) {
        return _NS("A video that was digitally enlarged from a lower resolution rather than originally mastered in high definition.");
    } else if ([topic isEqualToString:MacLCExplainerTopicRemux]) {
        return _NS("An exact copy of the Blu-ray disc's picture and sound, not compressed again. The best quality there is, and the biggest file.");
    } else if ([topic isEqualToString:MacLCExplainerTopicBluRay]) {
        return _NS("A high-quality copy encoded from an official Blu-ray disc, balancing fine detail with manageable file size.");
    } else if ([topic isEqualToString:MacLCExplainerTopicWebDL]) {
        return _NS("A direct digital file downloaded from an official streaming service, without re-encoding.");
    } else if ([topic isEqualToString:MacLCExplainerTopicWebRip]) {
        return _NS("A video recorded from an online stream and compressed into a smaller file.");
    } else if ([topic isEqualToString:MacLCExplainerTopicCam]) {
        return _NS("Filmed with a camera in a cinema. Expect a blurry picture, muffled sound and audience noise.");
    } else if ([topic isEqualToString:MacLCExplainerTopicAtmos]) {
        return _NS("Immersive 3D audio that places sounds all around and above you, rather than just in front and behind.");
    } else if ([topic isEqualToString:MacLCExplainerTopicLosslessAudio]) {
        return _NS("Studio-master audio with no compression loss, exactly as heard in the mixing room.");
    } else if ([topic isEqualToString:MacLCExplainerTopicSurround]) {
        return _NS("Multi-channel sound (such as 5.1 or 7.1) that separates speech, music, and background effects into distinct speakers.");
    } else if ([topic isEqualToString:MacLCExplainerTopicMultiAudio]) {
        return _NS("Contains spoken soundtracks in multiple languages, allowing you to choose between original audio and dubs.");
    } else if ([topic isEqualToString:MacLCExplainerTopicSubtitles]) {
        return _NS("Built-in subtitle tracks offering translations, closed captions, and descriptive audio text.");
    } else if ([topic isEqualToString:MacLCExplainerTopicAddons]) {
        return _NS("Community extensions that connect MacLC to online catalogs, title details, and playable streams.");
    } else if ([topic isEqualToString:MacLCExplainerTopicServices]) {
        return _NS("Filters your recommendations to show only movies and series available on services you subscribe to.");
    } else if ([topic isEqualToString:MacLCExplainerTopicCollections]) {
        return _NS("Hand-picked collections from MacLC, renewed every two weeks so there is always something new to discover.");
    } else if ([topic isEqualToString:MacLCExplainerTopicBestMatch]) {
        return _NS("MacLC reads each version's picture, sound, language and how many people share it, and suggests the one most likely to look great and play without pausing.");
    } else if ([topic isEqualToString:MacLCExplainerTopicVerdict]) {
        return _NS("A rating (Great, Good, Okay, or Poor) computed from the stream's source, resolution, and current connection health.");
    }
    return @"";
}

+ (nullable NSString *)consequenceForTopic:(MacLCExplainerTopic)topic
{
    if ([topic isEqualToString:MacLCExplainerTopicPeers]) {
        return _NS("More people means it starts sooner and doesn't pause. Under 5 can be slow.");
    } else if ([topic isEqualToString:MacLCExplainerTopicHealth]) {
        return _NS("More bars mean smooth playback; one or two bars may pause or take time to begin.");
    } else if ([topic isEqualToString:MacLCExplainerTopicTorrent]) {
        return _NS("Playback speed depends on how many other people are sharing it at that moment.");
    } else if ([topic isEqualToString:MacLCExplainerTopicDebrid]) {
        return _NS("Starts instantly at full speed, even if nobody else is sharing the file right now.");
    } else if ([topic isEqualToString:MacLCExplainerTopicSize]) {
        return _NS("Larger files preserve more fine detail, but need a faster connection to avoid pausing.");
    } else if ([topic isEqualToString:MacLCExplainerTopicPack]) {
        return _NS("MacLC plays the chosen episode directly and moves to the next one automatically.");
    } else if ([topic isEqualToString:MacLCExplainerTopicProvider]) {
        return nil;
    } else if ([topic isEqualToString:MacLCExplainerTopicResolution4K]) {
        return _NS("Looks best on 4K or Retina displays, but uses the most internet data.");
    } else if ([topic isEqualToString:MacLCExplainerTopicResolution1080p]) {
        return _NS("A great balance between sharp picture quality and fast, dependable playback.");
    } else if ([topic isEqualToString:MacLCExplainerTopicResolution720p]) {
        return _NS("Great for slower connections or metered data, though softer on large screens.");
    } else if ([topic isEqualToString:MacLCExplainerTopicDolbyVision]) {
        return _NS("Gives the most lifelike contrast and vibrant color on supported Apple screens.");
    } else if ([topic isEqualToString:MacLCExplainerTopicHDR10Plus]) {
        return _NS("Provides deeper shadows and brighter highlights on compatible HDR screens.");
    } else if ([topic isEqualToString:MacLCExplainerTopicHDR10]) {
        return _NS("Shows rich, lifelike highlights on HDR displays, and adjusts cleanly for standard screens.");
    } else if ([topic isEqualToString:MacLCExplainerTopicHLG]) {
        return _NS("Plays naturally on both standard and HDR displays without requiring complex conversion.");
    } else if ([topic isEqualToString:MacLCExplainerTopicSDR]) {
        return _NS("Plays reliably with natural colors on every display, requiring no special screen hardware.");
    } else if ([topic isEqualToString:MacLCExplainerTopicHEVC]) {
        return _NS("Plays smoothly using hardware acceleration on your Mac, saving battery.");
    } else if ([topic isEqualToString:MacLCExplainerTopicUpscaled]) {
        return _NS("May appear slightly softer or smoothed compared to a true native high-resolution copy.");
    } else if ([topic isEqualToString:MacLCExplainerTopicRemux]) {
        return _NS("Flawless studio picture and master sound, but requires a fast connection.");
    } else if ([topic isEqualToString:MacLCExplainerTopicBluRay]) {
        return _NS("Excellent, dependable picture and sound that easily surpasses standard web streams.");
    } else if ([topic isEqualToString:MacLCExplainerTopicWebDL]) {
        return _NS("Very clean picture and reliable sound, identical to streaming directly from the source service.");
    } else if ([topic isEqualToString:MacLCExplainerTopicWebRip]) {
        return _NS("Downloads quickly and looks good, though fast motion or dark scenes may show light compression.");
    } else if ([topic isEqualToString:MacLCExplainerTopicCam]) {
        return _NS("We suggest waiting for an official digital or Blu-ray release instead.");
    } else if ([topic isEqualToString:MacLCExplainerTopicAtmos]) {
        return _NS("Incredible spatial realism on surround speaker systems, AirPods, and Mac speakers.");
    } else if ([topic isEqualToString:MacLCExplainerTopicLosslessAudio]) {
        return _NS("Pure dynamic impact and vocal clarity for home theater setups and quality headphones.");
    } else if ([topic isEqualToString:MacLCExplainerTopicSurround]) {
        return _NS("Puts you inside the movie when listening with multiple speakers or spatial headphones.");
    } else if ([topic isEqualToString:MacLCExplainerTopicMultiAudio]) {
        return _NS("You can switch spoken languages anytime during playback from the audio menu.");
    } else if ([topic isEqualToString:MacLCExplainerTopicSubtitles]) {
        return _NS("Turn them on or switch subtitle languages at any time from the subtitles menu.");
    } else if ([topic isEqualToString:MacLCExplainerTopicAddons]) {
        return _NS("MacLC only queries and streams from add-ons you choose to install.");
    } else if ([topic isEqualToString:MacLCExplainerTopicServices]) {
        return _NS("Hides titles from services you don't use, keeping your catalog relevant.");
    } else if ([topic isEqualToString:MacLCExplainerTopicCollections]) {
        return _NS("A curated way to explore films by theme, director, or awards without manual searching.");
    } else if ([topic isEqualToString:MacLCExplainerTopicBestMatch]) {
        return _NS("The quickest path to a high-quality stream without inspecting every release manually.");
    } else if ([topic isEqualToString:MacLCExplainerTopicVerdict]) {
        return _NS("Poor versions like cinema recordings or streams with no peers are hidden by default.");
    }
    return nil;
}

+ (NSString *)symbolNameForTopic:(MacLCExplainerTopic)topic
{
    if ([topic isEqualToString:MacLCExplainerTopicPeers]) {
        return @"person.2.fill";
    } else if ([topic isEqualToString:MacLCExplainerTopicHealth]) {
        return @"chart.bar.fill";
    } else if ([topic isEqualToString:MacLCExplainerTopicTorrent]) {
        return @"arrow.triangle.2.circlepath.circle.fill";
    } else if ([topic isEqualToString:MacLCExplainerTopicDebrid]) {
        return @"bolt.fill";
    } else if ([topic isEqualToString:MacLCExplainerTopicSize]) {
        return @"internaldrive.fill";
    } else if ([topic isEqualToString:MacLCExplainerTopicPack]) {
        return @"square.stack.3d.up.fill";
    } else if ([topic isEqualToString:MacLCExplainerTopicProvider]) {
        return @"gearshape.fill";
    } else if ([topic isEqualToString:MacLCExplainerTopicResolution4K]) {
        return @"tv.fill";
    } else if ([topic isEqualToString:MacLCExplainerTopicResolution1080p]) {
        return @"tv.fill";
    } else if ([topic isEqualToString:MacLCExplainerTopicResolution720p]) {
        return @"tv.fill";
    } else if ([topic isEqualToString:MacLCExplainerTopicDolbyVision]) {
        return @"sun.max.fill";
    } else if ([topic isEqualToString:MacLCExplainerTopicHDR10Plus]) {
        return @"sun.max.fill";
    } else if ([topic isEqualToString:MacLCExplainerTopicHDR10]) {
        return @"sun.max.fill";
    } else if ([topic isEqualToString:MacLCExplainerTopicHLG]) {
        return @"sun.max.fill";
    } else if ([topic isEqualToString:MacLCExplainerTopicSDR]) {
        return @"circle.lefthalf.filled";
    } else if ([topic isEqualToString:MacLCExplainerTopicHEVC]) {
        return @"film.fill";
    } else if ([topic isEqualToString:MacLCExplainerTopicUpscaled]) {
        return @"wand.and.stars";
    } else if ([topic isEqualToString:MacLCExplainerTopicRemux]) {
        return @"opticaldisc.fill";
    } else if ([topic isEqualToString:MacLCExplainerTopicBluRay]) {
        return @"opticaldisc.fill";
    } else if ([topic isEqualToString:MacLCExplainerTopicWebDL]) {
        return @"arrow.down.circle.fill";
    } else if ([topic isEqualToString:MacLCExplainerTopicWebRip]) {
        return @"play.rectangle.fill";
    } else if ([topic isEqualToString:MacLCExplainerTopicCam]) {
        return @"video.slash.fill";
    } else if ([topic isEqualToString:MacLCExplainerTopicAtmos]) {
        return @"speaker.wave.3.fill";
    } else if ([topic isEqualToString:MacLCExplainerTopicLosslessAudio]) {
        return @"waveform";
    } else if ([topic isEqualToString:MacLCExplainerTopicSurround]) {
        return @"speaker.wave.2.fill";
    } else if ([topic isEqualToString:MacLCExplainerTopicMultiAudio]) {
        return @"globe";
    } else if ([topic isEqualToString:MacLCExplainerTopicSubtitles]) {
        return @"captions.bubble.fill";
    } else if ([topic isEqualToString:MacLCExplainerTopicAddons]) {
        return @"puzzlepiece.fill";
    } else if ([topic isEqualToString:MacLCExplainerTopicServices]) {
        return @"play.tv.fill";
    } else if ([topic isEqualToString:MacLCExplainerTopicCollections]) {
        return @"sparkles.rectangle.stack.fill";
    } else if ([topic isEqualToString:MacLCExplainerTopicBestMatch]) {
        return @"star.fill";
    } else if ([topic isEqualToString:MacLCExplainerTopicVerdict]) {
        return @"checkmark.seal.fill";
    }
    return @"info.circle.fill";
}

+ (NSColor *)tintForTopic:(MacLCExplainerTopic)topic
{
    // Tints: peers systemGreen, picture systemPurple, sound systemPink,
    // language systemBlue, warnings systemOrange, discovery systemIndigo
    if ([topic isEqualToString:MacLCExplainerTopicPeers] ||
        [topic isEqualToString:MacLCExplainerTopicHealth] ||
        [topic isEqualToString:MacLCExplainerTopicTorrent] ||
        [topic isEqualToString:MacLCExplainerTopicDebrid] ||
        [topic isEqualToString:MacLCExplainerTopicSize] ||
        [topic isEqualToString:MacLCExplainerTopicPack] ||
        [topic isEqualToString:MacLCExplainerTopicProvider]) {
        return [NSColor systemGreenColor];
    } else if ([topic isEqualToString:MacLCExplainerTopicResolution4K] ||
               [topic isEqualToString:MacLCExplainerTopicResolution1080p] ||
               [topic isEqualToString:MacLCExplainerTopicResolution720p] ||
               [topic isEqualToString:MacLCExplainerTopicDolbyVision] ||
               [topic isEqualToString:MacLCExplainerTopicHDR10Plus] ||
               [topic isEqualToString:MacLCExplainerTopicHDR10] ||
               [topic isEqualToString:MacLCExplainerTopicHLG] ||
               [topic isEqualToString:MacLCExplainerTopicSDR] ||
               [topic isEqualToString:MacLCExplainerTopicHEVC] ||
               [topic isEqualToString:MacLCExplainerTopicUpscaled] ||
               [topic isEqualToString:MacLCExplainerTopicRemux] ||
               [topic isEqualToString:MacLCExplainerTopicBluRay] ||
               [topic isEqualToString:MacLCExplainerTopicWebDL] ||
               [topic isEqualToString:MacLCExplainerTopicWebRip]) {
        return [NSColor systemPurpleColor];
    } else if ([topic isEqualToString:MacLCExplainerTopicCam]) {
        return [NSColor systemOrangeColor];
    } else if ([topic isEqualToString:MacLCExplainerTopicAtmos] ||
               [topic isEqualToString:MacLCExplainerTopicLosslessAudio] ||
               [topic isEqualToString:MacLCExplainerTopicSurround]) {
        return [NSColor systemPinkColor];
    } else if ([topic isEqualToString:MacLCExplainerTopicMultiAudio] ||
               [topic isEqualToString:MacLCExplainerTopicSubtitles]) {
        return [NSColor systemBlueColor];
    } else if ([topic isEqualToString:MacLCExplainerTopicAddons] ||
               [topic isEqualToString:MacLCExplainerTopicServices] ||
               [topic isEqualToString:MacLCExplainerTopicCollections] ||
               [topic isEqualToString:MacLCExplainerTopicBestMatch] ||
               [topic isEqualToString:MacLCExplainerTopicVerdict]) {
        return [NSColor systemIndigoColor];
    }
    return [NSColor systemBlueColor];
}

+ (MacLCExplainerIllustration)illustrationForTopic:(MacLCExplainerTopic)topic
{
    if ([topic isEqualToString:MacLCExplainerTopicPeers]) {
        return MacLCExplainerIllustrationPeers;
    } else if ([topic isEqualToString:MacLCExplainerTopicHealth]) {
        return MacLCExplainerIllustrationHealth;
    } else if ([topic isEqualToString:MacLCExplainerTopicDolbyVision] ||
               [topic isEqualToString:MacLCExplainerTopicHDR10Plus] ||
               [topic isEqualToString:MacLCExplainerTopicHDR10] ||
               [topic isEqualToString:MacLCExplainerTopicHLG] ||
               [topic isEqualToString:MacLCExplainerTopicSDR]) {
        return MacLCExplainerIllustrationDynamicRange;
    } else if ([topic isEqualToString:MacLCExplainerTopicResolution4K] ||
               [topic isEqualToString:MacLCExplainerTopicResolution1080p] ||
               [topic isEqualToString:MacLCExplainerTopicResolution720p]) {
        return MacLCExplainerIllustrationResolution;
    } else if ([topic isEqualToString:MacLCExplainerTopicSurround] ||
               [topic isEqualToString:MacLCExplainerTopicAtmos]) {
        return MacLCExplainerIllustrationSurround;
    }
    return MacLCExplainerIllustrationNone;
}

+ (void)attachToView:(NSView *)view topic:(nullable MacLCExplainerTopic)topic
{
    if (!view) return;

    MacLCExplainerAttachment *existing = objc_getAssociatedObject(view, &kMacLCExplainerAttachmentKey);
    if (existing) {
        [existing detach];
        objc_setAssociatedObject(view, &kMacLCExplainerAttachmentKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    if (topic.length > 0) {
        MacLCExplainerAttachment *attachment = [[MacLCExplainerAttachment alloc] initWithView:view topic:topic];
        objc_setAssociatedObject(view, &kMacLCExplainerAttachmentKey, attachment, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

+ (void)showTopic:(MacLCExplainerTopic)topic relativeToView:(NSView *)view
{
    [[MacLCExplainerManager sharedManager] showTopic:topic relativeToView:view];
}

+ (void)dismiss
{
    [[MacLCExplainerManager sharedManager] dismiss];
}

+ (NSButton *)infoButtonForTopic:(MacLCExplainerTopic)topic
{
    return [[MacLCExplainerInfoButton alloc] initWithTopic:topic];
}

+ (NSTextField *)explainedLabelWithString:(NSString *)string
                                     font:(NSFont *)font
                                    color:(NSColor *)color
                                    topic:(MacLCExplainerTopic)topic
{
    NSTextField *label = [NSTextField labelWithString:@""];
    label.editable = NO;
    label.selectable = NO;
    label.drawsBackground = NO;
    label.bezeled = NO;

    NSDictionary *attributes = @{
        NSFontAttributeName: font ?: MacLCDesign.body,
        NSForegroundColorAttributeName: color ?: MacLCDesign.primaryLabel,
        NSUnderlineStyleAttributeName: @(NSUnderlineStylePatternDot | NSUnderlineStyleSingle),
        NSUnderlineColorAttributeName: MacLCDesign.tertiaryLabel
    };
    label.attributedStringValue = [[NSAttributedString alloc] initWithString:string ?: @"" attributes:attributes];

    [self attachToView:label topic:topic];
    return label;
}

@end
