/*****************************************************************************
 * VLCPlaybackProgressSliderCell.m
 *****************************************************************************
 * Copyright (C) 2017 VLC authors and VideoLAN
 *
 * Authors: Marvin Scholz <epirat07 at gmail dot com>
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

#import "VLCPlaybackProgressSliderCell.h"

#import <QuartzCore/QuartzCore.h>

#import "extensions/NSColor+VLCAdditions.h"

#import "main/CompatibilityFixes.h"
#import "main/VLCMain.h"

#import "playqueue/VLCPlayerController.h"
#import "playqueue/VLCPlayQueueController.h"

#import "theme/MacLCDesign.h"

#import "views/VLCUIUnits.h"

/* A display link keeps its target until it is invalidated. It reaches the
 * cell through this box, which holds the cell weakly, so the link never keeps
 * the cell alive. */
@interface VLCPlaybackProgressSliderCellTarget : NSObject
@property (weak) VLCPlaybackProgressSliderCell *cell;
- (void)displayLinkDidFire:(CADisplayLink *)displayLink;
@end

@interface VLCPlaybackProgressSliderCell ()
{
    VLCPlaybackProgressSliderCellTarget *_displayLinkTarget;
    NSInteger _animationWidth;
    NSInteger _animationPosition;
    CFTimeInterval _lastTime;
    double _deltaToLastFrame;
    CADisplayLink *_displayLink;

    NSColor *_emptySliderBackgroundColor;

    enum vlc_player_abloop _abLoopState;
    CGFloat _aToBLoopAMarkPosition; // Position of the A loop mark as a fraction of slider width
    CGFloat _aToBLoopBMarkPosition; // Position of the B loop mark as a fraction of slider width
}

- (void)displayLinkDidFire:(CADisplayLink *)displayLink;

@end

@implementation VLCPlaybackProgressSliderCellTarget

- (void)displayLinkDidFire:(CADisplayLink *)displayLink
{
    [self.cell displayLinkDidFire:displayLink];
}

@end

@implementation VLCPlaybackProgressSliderCell

- (instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];
    if (self) {
        _animationWidth = self.controlView.bounds.size.width;

        [self setSliderStyleLight];
        [self updateAtoBLoopState];

        NSNotificationCenter * const notificationCenter = NSNotificationCenter.defaultCenter;
        [notificationCenter addObserver:self
                               selector:@selector(abLoopStateChanged:)
                                   name:VLCPlayerABLoopStateChanged
                                 object:nil];
    }
    return self;
}

- (void)dealloc
{
    [_displayLink invalidate];
}

/* The link comes from the slider view, and only while the animation runs.
 * AppKit keeps it in step with the display that shows the slider and stops
 * calling it while no display does (controls hidden, display asleep, lid
 * closed, headless Mac), where a link of the active displays cannot even be
 * created. Without ticks, the cell draws the same state, only still. */
- (void)startDisplayLink
{
    NSView * const controlView = self.controlView;
    if (_displayLink != nil || controlView == nil) {
        return;
    }

    if (_displayLinkTarget == nil) {
        _displayLinkTarget = [[VLCPlaybackProgressSliderCellTarget alloc] init];
        _displayLinkTarget.cell = self;
    }
    _displayLink = [controlView displayLinkWithTarget:_displayLinkTarget
                                             selector:@selector(displayLinkDidFire:)];
    [_displayLink addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
}

- (void)stopDisplayLink
{
    [_displayLink invalidate];
    _displayLink = nil;
}

/* One display link serves the indefinite animation and the download head's
 * pulse and shimmer: it runs only while one of them is on screen. */
- (BOOL)downloadAnimationWanted
{
    return _downloading && _downloadHead >= 0.0 && _downloadHead < 0.999 && !MacLCDesign.reducedMotion;
}

- (void)updateDisplayLink
{
    if (_indefinite || [self downloadAnimationWanted]) {
        [self startDisplayLink];
    } else {
        [self stopDisplayLink];
    }
}

- (void)setDownloadedRanges:(NSArray<NSNumber *> *)downloadedRanges
{
    if (_downloadedRanges == downloadedRanges || [_downloadedRanges isEqualToArray:downloadedRanges]) {
        return;
    }
    _downloadedRanges = [downloadedRanges copy];
    self.controlView.needsDisplay = YES;
}

- (void)setDownloadHead:(double)downloadHead
{
    _downloadHead = downloadHead;
    [self updateDisplayLink];
    self.controlView.needsDisplay = YES;
}

- (void)setDownloading:(BOOL)downloading
{
    _downloading = downloading;
    [self updateDisplayLink];
    self.controlView.needsDisplay = YES;
}

- (void)setSliderStyleLight
{
    _emptySliderBackgroundColor = NSColor.VLCSliderLightBackgroundColor;
}

- (void)setSliderStyleDark
{
    _emptySliderBackgroundColor = NSColor.VLCSliderDarkBackgroundColor;
}

- (void)abLoopStateChanged:(NSNotification *)notification
{
    [self updateAtoBLoopState];
}

- (void)updateAtoBLoopState
{
    VLCPlayerController * const playerController =
        VLCMain.sharedInstance.playQueueController.playerController;

    _abLoopState = playerController.abLoopState;
    _aToBLoopAMarkPosition = playerController.aLoopPosition;
    _aToBLoopBMarkPosition = playerController.bLoopPosition;
}

- (void)displayLinkDidFire:(CADisplayLink *)displayLink
{
    if (_lastTime == 0) {
        _deltaToLastFrame = 0;
    } else {
        _deltaToLastFrame = displayLink.timestamp - _lastTime;
    }
    _lastTime = displayLink.timestamp;

    self.controlView.needsDisplay = YES;
}

#pragma mark -
#pragma mark Normal slider drawing

/* Apple TV-style scrubber: a thin rounded track that thickens under the
 * pointer, filled in the label colour, with a round knob that only appears
 * while the pointer is over it (or the knob is being dragged). */
static const CGFloat kTrackThickness = 4.0;
static const CGFloat kTrackThicknessHovered = 8.0;
static const CGFloat kKnobDiameter = 14.0;

- (NSRect)trackRectForBarRect:(NSRect)rect
{
    const CGFloat thickness = _hovered ? kTrackThicknessHovered : kTrackThickness;
    return NSMakeRect(NSMinX(rect), NSMidY(rect) - thickness / 2.0,
                      NSWidth(rect), thickness);
}

- (void)drawKnob:(NSRect)knobRect
{
    if (self.knobHidden || !(_hovered || self.isHighlighted)) {
        return;
    }

    const NSRect circle = NSMakeRect(NSMidX(knobRect) - kKnobDiameter / 2.0,
                                     NSMidY(knobRect) - kKnobDiameter / 2.0,
                                     kKnobDiameter, kKnobDiameter);
    [NSGraphicsContext saveGraphicsState];
    NSShadow * const shadow = [[NSShadow alloc] init];
    shadow.shadowBlurRadius = 3.0;
    shadow.shadowOffset = NSMakeSize(0, -1);
    shadow.shadowColor = [NSColor colorWithWhite:0.0 alpha:0.35];
    [shadow set];
    [NSColor.whiteColor setFill];
    [[NSBezierPath bezierPathWithOvalInRect:circle] fill];
    [NSGraphicsContext restoreGraphicsState];
}

- (void)drawBarInside:(NSRect)rect flipped:(BOOL)flipped
{
    const NSRect track = [self trackRectForBarRect:rect];
    const CGFloat radius = NSHeight(track) / 2.0;

    // Empty track
    NSBezierPath * const emptyTrackPath =
        [NSBezierPath bezierPathWithRoundedRect:track xRadius:radius yRadius:radius];
    [_emptySliderBackgroundColor setFill];
    [emptyTrackPath fill];

    // What a torrent has already downloaded, between the empty track and the played fill
    [self drawDownloadedRangesInTrack:track radius:radius];

    if (!self.knobHidden) {
        // Filled track, up to the knob centre
        NSRect filledTrackRect = track;
        const NSRect knobRect = [self knobRectFlipped:NO];
        filledTrackRect.size.width = MAX(NSMidX(knobRect) - NSMinX(track), 0.0);

        NSBezierPath * const filledTrackPath =
            [NSBezierPath bezierPathWithRoundedRect:filledTrackRect xRadius:radius yRadius:radius];
        [NSColor.labelColor setFill];
        [filledTrackPath fill];
    }

    [self drawDownloadHeadInTrack:track];
}

#pragma mark -
#pragma mark Download drawing

/* labelColor at 45 % over the empty track (about 20 %) and under the played
 * fill (100 %): three states that read at a glance, as on a streaming player. Colours are set here, at draw time, so they follow the appearance. */
- (void)drawDownloadedRangesInTrack:(NSRect)track radius:(CGFloat)radius
{
    NSArray<NSNumber *> * const ranges = _downloadedRanges;
    if (ranges.count < 2 || NSWidth(track) <= 0.0) {
        return;
    }

    [[NSColor.labelColor colorWithAlphaComponent:0.45] setFill];
    for (NSUInteger i = 0; i + 1 < ranges.count; i += 2) {
        const double start = MIN(MAX(ranges[i].doubleValue, 0.0), 1.0);
        const double end = MIN(MAX(ranges[i + 1].doubleValue, 0.0), 1.0);
        if (end <= start) {
            continue;
        }
        NSRect piece = NSMakeRect(NSMinX(track) + start * NSWidth(track), NSMinY(track),
                                  MAX((end - start) * NSWidth(track), 1.0), NSHeight(track));
        const CGFloat pieceRadius = MIN(radius, NSWidth(piece) / 2.0);
        [[NSBezierPath bezierPathWithRoundedRect:piece xRadius:pieceRadius yRadius:pieceRadius] fill];
    }
}

/* A 4 pt capsule of the accent colour that glows and pulses (opacity 0.5 to 1
 * in 1.2 s), and every 2 s a soft sweep that travels from the playhead to it
 * inside the downloaded range. Reduce Motion: still, no sweep. */
- (void)drawDownloadHeadInTrack:(NSRect)track
{
    if (!_downloading || _downloadHead < 0.0 || _downloadHead >= 0.999 || NSWidth(track) <= 0.0) {
        return;
    }

    const BOOL animated = !MacLCDesign.reducedMotion && !_indefinite;
    const CFTimeInterval now = CACurrentMediaTime();
    const CGFloat headX = NSMinX(track) + MIN(_downloadHead, 1.0) * NSWidth(track);
    NSColor * const accent = NSColor.controlAccentColor;

    if (animated) {
        const CGFloat playX = self.knobHidden ? NSMinX(track) : NSMidX([self knobRectFlipped:NO]);
        const CGFloat span = headX - playX;
        const double phase = fmod(now, 2.0) / 0.9;
        if (span > 8.0 && phase < 1.0) {
            const double eased = phase * phase * (3.0 - 2.0 * phase);
            const CGFloat bandWidth = MIN(48.0, span);
            const CGFloat bandX = playX + (span + bandWidth) * (CGFloat)eased - bandWidth;
            const CGFloat radius = NSHeight(track) / 2.0;

            [NSGraphicsContext saveGraphicsState];
            [[NSBezierPath bezierPathWithRoundedRect:track xRadius:radius yRadius:radius] addClip];
            NSRectClip(NSMakeRect(playX, NSMinY(track), span, NSHeight(track)));
            NSGradient * const sweep = [[NSGradient alloc] initWithColors:@[
                [accent colorWithAlphaComponent:0.0],
                [accent colorWithAlphaComponent:0.55],
                [accent colorWithAlphaComponent:0.0],
            ]];
            [sweep drawInRect:NSMakeRect(bandX, NSMinY(track), bandWidth, NSHeight(track)) angle:0.0];
            [NSGraphicsContext restoreGraphicsState];
        }
    }

    const CGFloat opacity = animated ? 0.75 + 0.25 * cos(2.0 * M_PI * now / 1.2) : 1.0;
    const CGFloat headHeight = NSHeight(track) + 6.0;
    const NSRect head = NSMakeRect(headX - 2.0, NSMidY(track) - headHeight / 2.0, 4.0, headHeight);

    [NSGraphicsContext saveGraphicsState];
    NSShadow * const glow = [[NSShadow alloc] init];
    glow.shadowBlurRadius = 5.0;
    glow.shadowOffset = NSZeroSize;
    glow.shadowColor = [accent colorWithAlphaComponent:0.8 * opacity];
    [glow set];
    [[accent colorWithAlphaComponent:opacity] setFill];
    [[NSBezierPath bezierPathWithRoundedRect:head xRadius:2.0 yRadius:2.0] fill];
    [NSGraphicsContext restoreGraphicsState];
}

#pragma mark -
#pragma mark Hover

- (void)setHovered:(BOOL)hovered
{
    if (_hovered == hovered)
        return;
    _hovered = hovered;
    self.controlView.needsDisplay = YES;
}

#pragma mark -
#pragma mark Indefinite slider drawing

- (void)drawAnimationInRect:(NSRect)rect
{
    [NSGraphicsContext saveGraphicsState];
    rect = NSInsetRect(rect, 1.0, 1.0);
    NSBezierPath * const fullPath =
        [NSBezierPath bezierPathWithRoundedRect:rect xRadius:2.0 yRadius:2.0];
    [fullPath setClip];

    // Use previously calculated position
    rect.origin.x = _animationPosition;

    // Calculate new position for next Frame
    if (_animationPosition < (rect.size.width + _animationWidth)) {
        _animationPosition += (rect.size.width + _animationWidth) * _deltaToLastFrame;
    } else {
        _animationPosition = -(_animationWidth);
    }

    rect.size.width = _animationWidth;

    [NSGraphicsContext restoreGraphicsState];
    _deltaToLastFrame = 0;
}

- (void)drawCustomTickMarkAtPosition:(const CGFloat)position 
                         inCellFrame:(const NSRect)cellFrame
                           withColor:(NSColor * const)color
{
    const CGFloat tickThickness = VLCUIUnits.sliderTickThickness;
    const CGSize cellSize = cellFrame.size;
    NSRect tickFrame;

    if (self.isVertical) {
        const CGFloat tickY = cellSize.height * position;
        tickFrame = NSMakeRect(cellFrame.origin.x, tickY, cellSize.width, tickThickness);
    } else {
        const CGFloat tickX = cellSize.width * position;
        tickFrame = NSMakeRect(tickX, cellFrame.origin.y, tickThickness, cellSize.height);
    }

    const NSAlignmentOptions alignOpts =
        NSAlignMinXOutward | NSAlignMinYOutward | NSAlignWidthOutward | NSAlignMaxYOutward;
    const NSRect finalTickRect =
        [self.controlView backingAlignedRect:tickFrame options:alignOpts];

    [color setFill];
    NSRectFill(finalTickRect);
}

- (void)drawWithFrame:(NSRect)cellFrame inView:(NSView *)controlView
{
    if (self.indefinite) {
        return [self drawAnimationInRect:cellFrame];
    } else {
        [super drawWithFrame:cellFrame inView:controlView];
    }

    if (_abLoopState == VLC_PLAYER_ABLOOP_NONE) {
        return;
    }

    if (_aToBLoopAMarkPosition >= 0) {
        [self drawCustomTickMarkAtPosition:_aToBLoopAMarkPosition
                               inCellFrame:cellFrame
                                 withColor:_emptySliderBackgroundColor];
    }
    if (_aToBLoopBMarkPosition >= 0) {
        [self drawCustomTickMarkAtPosition:_aToBLoopBMarkPosition
                               inCellFrame:cellFrame
                                 withColor:_emptySliderBackgroundColor];
    }

    // Redraw knob
    [super drawKnob];
}

#pragma mark -
#pragma mark Animation handling

- (void)beginAnimating
{
    _animationPosition = -(_animationWidth);
    _lastTime = 0;
    [self updateDisplayLink];
    self.enabled = NO;
}

- (void)endAnimating
{
    [self updateDisplayLink];
    self.enabled = YES;
}

- (void)setIndefinite:(BOOL)indefinite
{
    if (self.indefinite == indefinite) {
        return;
    }

    _indefinite = indefinite;

    if (indefinite) {
        [self beginAnimating];
    } else {
        [self endAnimating];
    }
}

- (void)setKnobHidden:(BOOL)knobHidden
{
    _knobHidden = knobHidden;
    self.controlView.needsDisplay = YES;
}


@end
