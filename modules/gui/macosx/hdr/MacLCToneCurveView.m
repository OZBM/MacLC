/*****************************************************************************
 * MacLCToneCurveView.m: live plot of MacLC's HDR picture-mode curve
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

#import "MacLCToneCurveView.h"

#import "extensions/NSString+Helpers.h"
#import "theme/MacLCDesign.h"

#include "../../video_output/apple/maclc_tonemap.h"
#include "../../video_output/apple/maclc_hdr_vars.h"

/* Plot range, in cd/m², on both axes (logarithmic). */
static const double kMinNits = 0.1;
static const double kMaxNits = 10000.0;
#define kSamples 96
static const CGFloat kInset = 6.0;

@implementation MacLCToneCurveView
{
    double _from[kSamples];
    double _to[kSamples];
    double _shown[kSamples];
    NSTimer *_morphTimer;
    CFTimeInterval _morphStart;
}

- (instancetype)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (self) {
        _pictureMode = MacLCHDRPictureModeAuto;
        _contentPeakNits = 1000.0;
        _displayPeakNits = 1000.0;
        _sdrWhiteNits = MACLC_HDR_REFERENCE_WHITE;
        [self computeSamplesInto:_to];
        memcpy(_shown, _to, sizeof(_shown));
        self.accessibilityRole = NSAccessibilityImageRole;
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
    return NSMakeSize(NSViewNoIntrinsicMetric, 112.0);
}

#pragma mark - Model

- (maclc_tone_mode)resolvedMode
{
    switch (_pictureMode) {
        case MacLCHDRPictureModeAccurate: return MACLC_TONE_ACCURATE;
        case MacLCHDRPictureModeBalanced: return MACLC_TONE_BALANCED;
        case MacLCHDRPictureModeBright:   return MACLC_TONE_BRIGHT;
        default:
            /* Same rule as the video outputs. */
            return maclc_hdr_needs_tone_mapping((float)_contentPeakNits,
                                                (float)_displayPeakNits)
                ? MACLC_TONE_BALANCED : MACLC_TONE_ACCURATE;
    }
}

/* Panel light per cd/m² of mapped video: the video output puts
 * MACLC_HDR_REFERENCE_WHITE at SDR white. */
- (double)lightScale
{
    return _sdrWhiteNits > 0 ? _sdrWhiteNits / MACLC_HDR_REFERENCE_WHITE : 1.0;
}

- (double)panelPeakNits
{
    return _displayPeakNits * [self lightScale];
}

static double NitsForSample(NSUInteger i)
{
    const double t = (double)i / (double)(kSamples - 1);
    return pow(10.0, log10(kMinNits) + t * (log10(kMaxNits) - log10(kMinNits)));
}

- (void)computeSamplesInto:(double *)samples
{
    maclc_tone_params params;
    maclc_tone_params_init(&params, [self resolvedMode], (float)_contentPeakNits,
                           (float)_displayPeakNits, MACLC_HDR_REFERENCE_WHITE);
    const double scale = [self lightScale];
    for (NSUInteger i = 0; i < kSamples; i++) {
        const double nits = NitsForSample(i);
        /* Past the video's own peak there is nothing to map: hold the last
         * value so the curve reads as "this is where the video stops". */
        const double input = MIN(nits, (double)params.content_peak);
        samples[i] = MAX(maclc_tone_map_nits(&params, (float)input) * scale, kMinNits);
    }
}

- (void)setPictureMode:(MacLCHDRPictureMode)pictureMode
{
    [self setPictureMode:pictureMode contentPeakNits:_contentPeakNits
         displayPeakNits:_displayPeakNits sdrWhiteNits:_sdrWhiteNits animated:NO];
}

- (void)setContentPeakNits:(CGFloat)contentPeakNits
{
    [self setPictureMode:_pictureMode contentPeakNits:contentPeakNits
         displayPeakNits:_displayPeakNits sdrWhiteNits:_sdrWhiteNits animated:NO];
}

- (void)setDisplayPeakNits:(CGFloat)displayPeakNits
{
    [self setPictureMode:_pictureMode contentPeakNits:_contentPeakNits
         displayPeakNits:displayPeakNits sdrWhiteNits:_sdrWhiteNits animated:NO];
}

- (void)setSdrWhiteNits:(CGFloat)sdrWhiteNits
{
    [self setPictureMode:_pictureMode contentPeakNits:_contentPeakNits
         displayPeakNits:_displayPeakNits sdrWhiteNits:sdrWhiteNits animated:NO];
}

- (void)setPictureMode:(MacLCHDRPictureMode)mode
       contentPeakNits:(CGFloat)contentPeak
       displayPeakNits:(CGFloat)displayPeak
          sdrWhiteNits:(CGFloat)sdrWhite
              animated:(BOOL)animated
{
    _pictureMode = mode;
    _contentPeakNits = contentPeak > 0 ? contentPeak : 1000.0;
    _displayPeakNits = displayPeak > 0 ? displayPeak : MACLC_HDR_REFERENCE_WHITE;
    _sdrWhiteNits = sdrWhite > 0 ? sdrWhite : 0.0;

    memcpy(_from, _shown, sizeof(_from));
    [self computeSamplesInto:_to];
    [self updateAccessibility];

    [_morphTimer invalidate];
    _morphTimer = nil;
    if (!animated || MacLCDesign.reducedMotion || self.window == nil) {
        memcpy(_shown, _to, sizeof(_shown));
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
    /* ease-out cubic: fast start, settles softly */
    const double e = 1.0 - pow(1.0 - t, 3.0);
    for (NSUInteger i = 0; i < kSamples; i++) {
        /* interpolate in log space so the motion reads evenly on the plot */
        const double a = log10(_from[i]), b = log10(_to[i]);
        _shown[i] = pow(10.0, a + (b - a) * e);
    }
    self.needsDisplay = YES;
}

- (void)updateAccessibility
{
    NSNumberFormatter *formatter = [[NSNumberFormatter alloc] init];
    formatter.numberStyle = NSNumberFormatterDecimalStyle;
    formatter.maximumFractionDigits = 0;
    self.accessibilityLabel = [NSString stringWithFormat:
        _NS("Tone curve: video up to %@ nits shown on a display that reaches %@ nits"),
        [formatter stringFromNumber:@(_contentPeakNits)],
        [formatter stringFromNumber:@([self panelPeakNits])]];
}

#pragma mark - Drawing

- (NSRect)plotRect
{
    return NSInsetRect(self.bounds, kInset, kInset);
}

- (CGFloat)xForNits:(double)nits inRect:(NSRect)r
{
    const double t = (log10(MAX(nits, kMinNits)) - log10(kMinNits))
                   / (log10(kMaxNits) - log10(kMinNits));
    return NSMinX(r) + (CGFloat)t * NSWidth(r);
}

- (CGFloat)yForNits:(double)nits inRect:(NSRect)r
{
    const double t = (log10(MAX(nits, kMinNits)) - log10(kMinNits))
                   / (log10(kMaxNits) - log10(kMinNits));
    return NSMinY(r) + (CGFloat)t * NSHeight(r);
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

    /* The range the video uses */
    const CGFloat contentX = [self xForNits:_contentPeakNits inRect:r];
    NSRect band = NSMakeRect(NSMinX(r), NSMinY(r), contentX - NSMinX(r), NSHeight(r));
    [[MacLCDesign.accent colorWithAlphaComponent:0.10] setFill];
    NSRectFillUsingOperation(band, NSCompositingOperationSourceOver);

    /* "Shown exactly as mastered" diagonal */
    NSBezierPath *diagonal = [NSBezierPath bezierPath];
    [diagonal moveToPoint:NSMakePoint(NSMinX(r), NSMinY(r))];
    [diagonal lineToPoint:NSMakePoint(NSMaxX(r), NSMaxY(r))];
    const CGFloat dots[] = { 1.0, 3.0 };
    [diagonal setLineDash:dots count:2 phase:0];
    diagonal.lineWidth = 1.0;
    [MacLCDesign.tertiaryLabel setStroke];
    [diagonal stroke];

    /* Display peak */
    const double panelPeak = [self panelPeakNits];
    const CGFloat peakY = [self yForNits:panelPeak inRect:r];
    NSBezierPath *peak = [NSBezierPath bezierPath];
    [peak moveToPoint:NSMakePoint(NSMinX(r), peakY)];
    [peak lineToPoint:NSMakePoint(NSMaxX(r), peakY)];
    const CGFloat dashes[] = { 4.0, 3.0 };
    [peak setLineDash:dashes count:2 phase:0];
    peak.lineWidth = 1.0;
    [MacLCDesign.secondaryLabel setStroke];
    [peak stroke];

    /* The curve */
    NSBezierPath *curve = [NSBezierPath bezierPath];
    for (NSUInteger i = 0; i < kSamples; i++) {
        const NSPoint p = NSMakePoint([self xForNits:NitsForSample(i) inRect:r],
                                      [self yForNits:_shown[i] inRect:r]);
        if (i == 0)
            [curve moveToPoint:p];
        else
            [curve lineToPoint:p];
    }
    curve.lineWidth = 2.0;
    curve.lineJoinStyle = NSLineJoinStyleRound;
    curve.lineCapStyle = NSLineCapStyleRound;
    [MacLCDesign.accent setStroke];
    [curve stroke];

    /* Labels */
    NSNumberFormatter *formatter = [[NSNumberFormatter alloc] init];
    formatter.numberStyle = NSNumberFormatterDecimalStyle;
    formatter.maximumFractionDigits = 0;
    NSDictionary *attributes = @{
        NSFontAttributeName: MacLCDesign.caption,
        NSForegroundColorAttributeName: MacLCDesign.secondaryLabel,
    };
    NSString *displayLabel = [NSString stringWithFormat:_NS("Display · %@ nits"),
                              [formatter stringFromNumber:@(panelPeak)]];
    const NSSize displaySize = [displayLabel sizeWithAttributes:attributes];
    CGFloat labelY = peakY + 2.0;
    if (labelY + displaySize.height > NSMaxY(r))
        labelY = peakY - displaySize.height - 2.0;
    [displayLabel drawAtPoint:NSMakePoint(NSMinX(r) + 4.0, labelY) withAttributes:attributes];

    NSString *videoLabel = [NSString stringWithFormat:_NS("Video · %@ nits"),
                            [formatter stringFromNumber:@(_contentPeakNits)]];
    const NSSize videoSize = [videoLabel sizeWithAttributes:attributes];
    CGFloat videoX = MIN(contentX - videoSize.width - 4.0, NSMaxX(r) - videoSize.width - 4.0);
    videoX = MAX(videoX, NSMinX(r) + 4.0);
    [videoLabel drawAtPoint:NSMakePoint(videoX, NSMinY(r) + 4.0) withAttributes:attributes];
}

@end
