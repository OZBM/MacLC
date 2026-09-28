/*****************************************************************************
 * MacLCExpansionCurveView.m: live plot of MacLC's SDR to HDR expansion curve
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

#import "MacLCExpansionCurveView.h"

#import "theme/MacLCDesign.h"
#import "extensions/NSString+Helpers.h"

#include "../../video_output/apple/maclc_sdr2hdr.h"

#define kSamples 201

static inline CGFloat NormalizedXForSignal(float s)
{
    s = fmaxf(0.0f, fminf(1.0f, s));
    if (s <= 0.8f) {
        return (CGFloat)(0.5 * (s / 0.8f));
    } else {
        return (CGFloat)(0.5 + 0.5 * ((s - 0.8f) / 0.2f));
    }
}

@implementation MacLCExpansionCurveView
{
    double _from[kSamples];
    double _to[kSamples];
    double _shown[kSamples];

    double _fromHigh[kSamples];
    double _toHigh[kSamples];
    double _shownHigh[kSamples];

    NSTimer *_morphTimer;
    CFTimeInterval _morphStart;
}

- (instancetype)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (self) {
        _quality = MacLCSDRToHDRQualityAuto;
        _boost = MACLC_SDR2HDR_BOOST_DEFAULT;
        _midtones = MACLC_SDR2HDR_MIDTONES_DEFAULT;
        _headroom = 4.0f;
        _enabled = YES;

        [self computeSamplesTop:_to high:_toHigh];
        memcpy(_shown, _to, sizeof(_shown));
        memcpy(_shownHigh, _toHigh, sizeof(_shownHigh));

        self.accessibilityRole = NSAccessibilityImageRole;
        [self updateAccessibility];
    }
    return self;
}

- (void)dealloc
{
    [_morphTimer invalidate];
}

- (BOOL)isFlipped
{
    return NO;
}

- (NSSize)intrinsicContentSize
{
    return NSMakeSize(348.0, 110.0);
}

#pragma mark - Model

- (enum maclc_sdr2hdr_quality)resolvedQuality
{
    if (_quality == MacLCSDRToHDRQualityAuto) {
        MacLCSDRToHDRQuality active = [MacLCSDRToHDRState sharedState].activeQuality;
        if (active != MacLCSDRToHDRQualityAuto) {
            return (enum maclc_sdr2hdr_quality)active;
        }
        return MACLC_SDR2HDR_FAST;
    }
    return (enum maclc_sdr2hdr_quality)_quality;
}

- (void)computeSamplesTop:(double *)topSamples high:(double *)highSamples
{
    const enum maclc_sdr2hdr_quality q = [self resolvedQuality];
    const float headroom = _headroom > 1.0f ? _headroom : 1.0f;

    for (NSUInteger i = 0; i < kSamples; i++) {
        const float s = (float)i / (float)(kSamples - 1);
        if (!_enabled) {
            /* SDR as graded */
            const double sdrNits = 100.0 * pow((double)s, 1.961);
            topSamples[i] = fmax(10.0, sdrNits);
            highSamples[i] = topSamples[i];
        } else {
            const float ptTop = maclc_sdr2hdr_curve_point(q, s, _boost, _midtones, headroom, 0.0f);
            topSamples[i] = fmax(10.0, (double)(100.0f * ptTop));

            if (q == MACLC_SDR2HDR_FAST) {
                highSamples[i] = topSamples[i];
            } else {
                const float ptHigh = maclc_sdr2hdr_curve_point(q, s, _boost, _midtones, headroom, MACLC_SDR2HDR_AREA_HIGH);
                highSamples[i] = fmax(10.0, (double)(100.0f * ptHigh));
            }
        }
    }
}

- (void)setQuality:(MacLCSDRToHDRQuality)quality
{
    [self setQuality:quality boost:_boost midtones:_midtones headroom:_headroom enabled:_enabled animated:NO];
}

- (void)setBoost:(float)boost
{
    [self setQuality:_quality boost:boost midtones:_midtones headroom:_headroom enabled:_enabled animated:NO];
}

- (void)setMidtones:(float)midtones
{
    [self setQuality:_quality boost:_boost midtones:midtones headroom:_headroom enabled:_enabled animated:NO];
}

- (void)setHeadroom:(float)headroom
{
    [self setQuality:_quality boost:_boost midtones:_midtones headroom:headroom enabled:_enabled animated:NO];
}

- (void)setEnabled:(BOOL)enabled
{
    [self setQuality:_quality boost:_boost midtones:_midtones headroom:_headroom enabled:enabled animated:NO];
}

- (void)setQuality:(MacLCSDRToHDRQuality)quality
             boost:(float)boost
          midtones:(float)midtones
          headroom:(float)headroom
          animated:(BOOL)animated
{
    [self setQuality:quality boost:boost midtones:midtones headroom:headroom enabled:_enabled animated:animated];
}

- (void)setQuality:(MacLCSDRToHDRQuality)quality
             boost:(float)boost
          midtones:(float)midtones
          headroom:(float)headroom
           enabled:(BOOL)enabled
          animated:(BOOL)animated
{
    _quality = quality;
    _boost = boost > 0 ? boost : MACLC_SDR2HDR_BOOST_DEFAULT;
    _midtones = midtones >= 0 ? midtones : 0.0f;
    _headroom = headroom > 0 ? headroom : 1.0f;
    _enabled = enabled;

    memcpy(_from, _shown, sizeof(_from));
    memcpy(_fromHigh, _shownHigh, sizeof(_fromHigh));
    [self computeSamplesTop:_to high:_toHigh];
    [self updateAccessibility];

    [_morphTimer invalidate];
    _morphTimer = nil;

    if (!animated || MacLCDesign.reducedMotion || self.window == nil) {
        memcpy(_shown, _to, sizeof(_shown));
        memcpy(_shownHigh, _toHigh, sizeof(_shownHigh));
        self.needsDisplay = YES;
        return;
    }

    _morphStart = CACurrentMediaTime();
    __weak typeof(self) weakSelf = self;
    _morphTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 / 60.0
                                                  repeats:YES
                                                    block:^(NSTimer *timer) {
        [weakSelf morphStep:timer];
    }];
}

- (void)morphStep:(NSTimer *)timer
{
    const double duration = MacLCDesign.motionEmphasizedDuration;
    double t = (CACurrentMediaTime() - _morphStart) / duration;
    if (t >= 1.0) {
        t = 1.0;
        [timer invalidate];
        _morphTimer = nil;
    }
    const double e = 1.0 - pow(1.0 - t, 3.0);
    for (NSUInteger i = 0; i < kSamples; i++) {
        const double aTop = log10(_from[i]), bTop = log10(_to[i]);
        _shown[i] = pow(10.0, aTop + (bTop - aTop) * e);

        const double aHigh = log10(_fromHigh[i]), bHigh = log10(_toHigh[i]);
        _shownHigh[i] = pow(10.0, aHigh + (bHigh - aHigh) * e);
    }
    self.needsDisplay = YES;
}

- (void)updateAccessibility
{
    NSNumberFormatter *formatter = [[NSNumberFormatter alloc] init];
    formatter.numberStyle = NSNumberFormatterDecimalStyle;
    formatter.maximumFractionDigits = 0;

    const float targetPeakNits = maclc_sdr2hdr_boost_to_nits(_boost);
    self.accessibilityLabel = [NSString stringWithFormat:
        _NS("Highlights from 90 %% of the signal rise to %@ cd/m²"),
        [formatter stringFromNumber:@((NSInteger)roundf(targetPeakNits))]];
}

#pragma mark - Geometry & Drawing

- (NSRect)plotRect
{
    return NSMakeRect(NSMinX(self.bounds) + 26.0,
                      NSMinY(self.bounds) + 16.0,
                      NSWidth(self.bounds) - 34.0,
                      NSHeight(self.bounds) - 26.0);
}

- (CGFloat)xForSignal:(float)signal inRect:(NSRect)r
{
    return NSMinX(r) + NormalizedXForSignal(signal) * NSWidth(r);
}

- (CGFloat)yForNits:(double)nits inRect:(NSRect)r
{
    const double yMin = 10.0;
    const double yMax = fmax(400.0, 100.0 * fmax(1.0, (double)_headroom));
    const double t = (log10(fmax(nits, yMin)) - log10(yMin)) / (log10(yMax) - log10(yMin));
    return NSMinY(r) + (CGFloat)fmax(0.0, fmin(1.0, t)) * NSHeight(r);
}

- (void)drawRect:(NSRect)dirtyRect
{
    const NSRect r = [self plotRect];

    /* Background card */
    NSBezierPath *card = [NSBezierPath bezierPathWithRoundedRect:self.bounds
                                                         xRadius:MacLCDesign.cornerRadiusMedium
                                                         yRadius:MacLCDesign.cornerRadiusMedium];
    [[MacLCDesign.quaternaryLabel colorWithAlphaComponent:0.35] setFill];
    [card fill];

    NSDictionary *axisAttrs = @{
        NSFontAttributeName: MacLCDesign.caption,
        NSForegroundColorAttributeName: MacLCDesign.tertiaryLabel,
    };
    NSDictionary *legendAttrs = @{
        NSFontAttributeName: MacLCDesign.caption,
        NSForegroundColorAttributeName: MacLCDesign.secondaryLabel,
    };

    /* X axis ticks and labels at 0%, 50%, 80%, 90%, 100% */
    const float ticks[] = { 0.0f, 0.5f, 0.8f, 0.9f, 1.0f };
    const char *tickLabels[] = { "0%", "50%", "80%", "90%", "100%" };
    for (size_t i = 0; i < 5; i++) {
        const CGFloat x = [self xForSignal:ticks[i] inRect:r];
        NSBezierPath *tickPath = [NSBezierPath bezierPath];
        [tickPath moveToPoint:NSMakePoint(x, NSMinY(r))];
        [tickPath lineToPoint:NSMakePoint(x, NSMinY(r) - 3.0)];
        [MacLCDesign.tertiaryLabel setStroke];
        tickPath.lineWidth = 1.0;
        [tickPath stroke];

        NSString *lbl = [NSString stringWithUTF8String:tickLabels[i]];
        const NSSize sz = [lbl sizeWithAttributes:axisAttrs];
        CGFloat lx = x - sz.width / 2.0;
        if (i == 0) lx = x;
        if (i == 4) lx = x - sz.width;
        [lbl drawAtPoint:NSMakePoint(lx, NSMinY(r) - 13.0) withAttributes:axisAttrs];
    }

    /* Diffuse white line at 90% */
    const CGFloat xWhite = [self xForSignal:0.90f inRect:r];
    NSBezierPath *whiteLine = [NSBezierPath bezierPath];
    [whiteLine moveToPoint:NSMakePoint(xWhite, NSMinY(r))];
    [whiteLine lineToPoint:NSMakePoint(xWhite, NSMaxY(r))];
    const CGFloat whiteDash[] = { 2.0, 2.0 };
    [whiteLine setLineDash:whiteDash count:2 phase:0];
    whiteLine.lineWidth = 1.0;
    [[MacLCDesign.tertiaryLabel colorWithAlphaComponent:0.4] setStroke];
    [whiteLine stroke];

    [@"white" drawAtPoint:NSMakePoint(xWhite + 3.0, NSMinY(r) + 4.0) withAttributes:axisAttrs];

    /* Y axis reference at 100 nits */
    const CGFloat y100 = [self yForNits:100.0 inRect:r];
    [@"100" drawAtPoint:NSMakePoint(NSMinX(self.bounds) + 4.0, y100 - 5.0) withAttributes:axisAttrs];

    /* Display ceiling line */
    const double ceilingNits = 100.0 * fmax(1.0, (double)_headroom);
    const CGFloat yCeiling = [self yForNits:ceilingNits inRect:r];
    NSBezierPath *ceilingLine = [NSBezierPath bezierPath];
    [ceilingLine moveToPoint:NSMakePoint(NSMinX(r), yCeiling)];
    [ceilingLine lineToPoint:NSMakePoint(NSMaxX(r), yCeiling)];
    const CGFloat dashes[] = { 4.0, 3.0 };
    [ceilingLine setLineDash:dashes count:2 phase:0];
    ceilingLine.lineWidth = 1.0;
    [MacLCDesign.secondaryLabel setStroke];
    [ceilingLine stroke];

    NSString *displayLabel = _NS("This display");
    const NSSize dSize = [displayLabel sizeWithAttributes:legendAttrs];
    CGFloat dY = yCeiling + 2.0;
    if (dY + dSize.height > NSMaxY(self.bounds) - 2.0) {
        dY = yCeiling - dSize.height - 2.0;
    }
    [displayLabel drawAtPoint:NSMakePoint(NSMinX(r) + 4.0, dY) withAttributes:legendAttrs];

    /* Dotted line: SDR as graded (100 * signal^1.961) */
    NSBezierPath *graded = [NSBezierPath bezierPath];
    for (NSUInteger i = 0; i < kSamples; i++) {
        const float s = (float)i / (float)(kSamples - 1);
        const double nits = 100.0 * pow((double)s, 1.961);
        const NSPoint pt = NSMakePoint([self xForSignal:s inRect:r], [self yForNits:nits inRect:r]);
        if (i == 0) [graded moveToPoint:pt];
        else [graded lineToPoint:pt];
    }
    const CGFloat dots[] = { 1.0, 3.0 };
    [graded setLineDash:dots count:2 phase:0];
    graded.lineWidth = 1.0;
    [MacLCDesign.tertiaryLabel setStroke];
    [graded stroke];

    const enum maclc_sdr2hdr_quality q = [self resolvedQuality];
    const BOOL showBand = _enabled && (q == MACLC_SDR2HDR_BALANCED || q == MACLC_SDR2HDR_HIGH || q == MACLC_SDR2HDR_MAXIMUM);

    /* Shaded band between top curve and high curve */
    if (showBand) {
        NSBezierPath *band = [NSBezierPath bezierPath];
        for (NSUInteger i = 0; i < kSamples; i++) {
            const float s = (float)i / (float)(kSamples - 1);
            const NSPoint pt = NSMakePoint([self xForSignal:s inRect:r], [self yForNits:_shown[i] inRect:r]);
            if (i == 0) [band moveToPoint:pt];
            else [band lineToPoint:pt];
        }
        for (NSInteger i = (NSInteger)kSamples - 1; i >= 0; i--) {
            const float s = (float)i / (float)(kSamples - 1);
            const NSPoint pt = NSMakePoint([self xForSignal:s inRect:r], [self yForNits:_shownHigh[i] inRect:r]);
            [band lineToPoint:pt];
        }
        [band closePath];
        [[MacLCDesign.accent colorWithAlphaComponent:0.12] setFill];
        [band fill];

        /* Lower curve (large bright areas) */
        NSBezierPath *curveHigh = [NSBezierPath bezierPath];
        for (NSUInteger i = 0; i < kSamples; i++) {
            const float s = (float)i / (float)(kSamples - 1);
            const NSPoint pt = NSMakePoint([self xForSignal:s inRect:r], [self yForNits:_shownHigh[i] inRect:r]);
            if (i == 0) [curveHigh moveToPoint:pt];
            else [curveHigh lineToPoint:pt];
        }
        curveHigh.lineWidth = 1.0;
        [[MacLCDesign.accent colorWithAlphaComponent:0.5] setStroke];
        [curveHigh stroke];

        /* Labels at right edge */
        NSString *smallHighlights = _NS("small highlights");
        NSString *largeAreas = _NS("large bright areas");
        const NSSize shSize = [smallHighlights sizeWithAttributes:axisAttrs];
        const NSSize laSize = [largeAreas sizeWithAttributes:axisAttrs];

        CGFloat shY = [self yForNits:_shown[kSamples - 1] inRect:r] + 2.0;
        CGFloat laY = [self yForNits:_shownHigh[kSamples - 1] inRect:r] - laSize.height - 2.0;
        [smallHighlights drawAtPoint:NSMakePoint(NSMaxX(r) - shSize.width - 2.0, shY) withAttributes:axisAttrs];
        [largeAreas drawAtPoint:NSMakePoint(NSMaxX(r) - laSize.width - 2.0, laY) withAttributes:axisAttrs];
    }

    /* Solid accent curve (top curve) */
    NSBezierPath *curve = [NSBezierPath bezierPath];
    for (NSUInteger i = 0; i < kSamples; i++) {
        const float s = (float)i / (float)(kSamples - 1);
        const NSPoint pt = NSMakePoint([self xForSignal:s inRect:r], [self yForNits:_shown[i] inRect:r]);
        if (i == 0) [curve moveToPoint:pt];
        else [curve lineToPoint:pt];
    }
    curve.lineWidth = 2.0;
    curve.lineJoinStyle = NSLineJoinStyleRound;
    curve.lineCapStyle = NSLineCapStyleRound;
    if (_enabled) {
        [MacLCDesign.accent setStroke];
    } else {
        [MacLCDesign.tertiaryLabel setStroke];
    }
    [curve stroke];

    /* High/Maximum footnote caption inside the curve view if active */
    if (_enabled && (_quality == MacLCSDRToHDRQualityHigh || _quality == MacLCSDRToHDRQualityMaximum)) {
        NSString *caption = _NS("High and Maximum refine this curve for every scene.");
        [caption drawAtPoint:NSMakePoint(NSMinX(r) + 4.0, NSMaxY(r) - 12.0) withAttributes:axisAttrs];
    }
}

@end
