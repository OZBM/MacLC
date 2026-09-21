/****************************************************************************
 * MacLCVideoFitGeometryTest.m: window-to-video fit geometry tests
 ****************************************************************************
 * Copyright (C) 2026 Hazen Studio
 *
 * This program is free software; you can redistribute it and/or modify it
 * under the terms of the GNU General Public License as published by the
 * Free Software Foundation; either version 2 of the License, or (at your
 * option) any later version.
 *****************************************************************************/

#import <XCTest/XCTest.h>

#import "windows/video/MacLCVideoFitGeometry.h"

/* The machine the feature was measured on: a 2056x1290 pt screen at 2x, menu
 * bar excluded from the visible frame. */
static const CGFloat kScreenWidth = 2056.;
static const CGFloat kScreenHeight = 1290.;
static const CGFloat kMenuBarHeight = 39.;

@interface MacLCVideoFitGeometryTest : XCTestCase
@end

@implementation MacLCVideoFitGeometryTest

static NSRect visibleFrame(void)
{
    return NSMakeRect(0., 0., kScreenWidth, kScreenHeight - kMenuBarHeight);
}

static MacLCVideoFitInput baseInput(void)
{
    MacLCVideoFitInput input = {
        .nativeVideoSize = NSMakeSize(1920., 1080.),
        .chromeSize = NSZeroSize,
        /* The library window as it was measured: 1123x468 pt at 173,503. */
        .currentFrame = NSMakeRect(173., 503., 1123., 468.),
        .arrangedBounds = NSZeroRect,
        .visibleFrame = visibleFrame(),
        .scaleFactor = 2.,
        .mode = MacLCVideoFitModeNative,
    };
    return input;
}

static void assertRectEqual(NSRect got, NSRect expected, NSString *what)
{
    const CGFloat tolerance = 1.;
    XCTAssertEqualWithAccuracy(got.origin.x, expected.origin.x, tolerance, @"%@ x", what);
    XCTAssertEqualWithAccuracy(got.origin.y, expected.origin.y, tolerance, @"%@ y", what);
    XCTAssertEqualWithAccuracy(got.size.width, expected.size.width, tolerance, @"%@ width", what);
    XCTAssertEqualWithAccuracy(got.size.height, expected.size.height, tolerance, @"%@ height", what);
}

#pragma mark - Native mode

/* 1920x1080 px on a 2x screen is 960x540 pt, centred where the window was.
 * These are the numbers the running application logs as "video fit:". */
- (void)testNativeModeTakesTheVideoSizeInPointsAndKeepsTheCentre
{
    MacLCVideoFitInput input = baseInput();
    const NSRect frame = MacLCVideoFitTargetFrame(input);

    assertRectEqual(frame, NSMakeRect(254.5, 467., 960., 540.), @"16:9 native");
    XCTAssertEqualWithAccuracy(NSMidX(frame), NSMidX(input.currentFrame), 1.);
    XCTAssertEqualWithAccuracy(NSMidY(frame), NSMidY(input.currentFrame), 1.);
}

- (void)testNativeModeKeepsACinemaAspectRatio
{
    MacLCVideoFitInput input = baseInput();
    input.nativeVideoSize = NSMakeSize(1920., 804.);

    const NSRect frame = MacLCVideoFitTargetFrame(input);

    assertRectEqual(frame, NSMakeRect(254.5, 536., 960., 402.), @"2.39 native");
}

- (void)testChromeIsAddedAroundTheVideo
{
    MacLCVideoFitInput input = baseInput();
    /* A detached window carries a title bar: the video keeps its size and the
     * window grows by the chrome. */
    input.chromeSize = NSMakeSize(0., 28.);

    const NSRect frame = MacLCVideoFitTargetFrame(input);

    XCTAssertEqualWithAccuracy(frame.size.width, 960., 1.);
    XCTAssertEqualWithAccuracy(frame.size.height, 540. + 28., 1.);
}

- (void)testAOnePointScaleFactorMeansPixelsArePoints
{
    MacLCVideoFitInput input = baseInput();
    input.scaleFactor = 1.;
    input.nativeVideoSize = NSMakeSize(1280., 720.);

    const NSRect frame = MacLCVideoFitTargetFrame(input);

    XCTAssertEqualWithAccuracy(frame.size.width, 1280., 1.);
    XCTAssertEqualWithAccuracy(frame.size.height, 720., 1.);
}

#pragma mark - Arranged mode (tiled or zoomed windows)

/* Measured on the machine: the library window tiled to the left half is
 * 1028 pt wide, and the video fills that width. */
- (void)testArrangedModeFillsTheWidthOfATiledHalf
{
    MacLCVideoFitInput input = baseInput();
    input.mode = MacLCVideoFitModeArranged;
    input.arrangedBounds = NSMakeRect(0., 0., 1028., 1290.);
    input.currentFrame = input.arrangedBounds;

    const NSRect wide = MacLCVideoFitTargetFrame(input);
    XCTAssertEqualWithAccuracy(wide.size.width, 1028., 1.);
    XCTAssertEqualWithAccuracy(wide.size.height, 578., 1.);

    input.nativeVideoSize = NSMakeSize(1920., 804.);
    const NSRect cinema = MacLCVideoFitTargetFrame(input);
    XCTAssertEqualWithAccuracy(cinema.size.width, 1028., 1.);
    XCTAssertEqualWithAccuracy(cinema.size.height, 430., 1.);
}

- (void)testArrangedModeFitsTheHeightWhenTheBoundsAreWide
{
    MacLCVideoFitInput input = baseInput();
    input.mode = MacLCVideoFitModeArranged;
    /* A short, very wide tile: the height is what runs out first. */
    input.arrangedBounds = NSMakeRect(0., 0., 2000., 400.);
    input.currentFrame = input.arrangedBounds;

    const NSRect frame = MacLCVideoFitTargetFrame(input);

    XCTAssertEqualWithAccuracy(frame.size.height, 400., 1.);
    XCTAssertEqualWithAccuracy(frame.size.width, 400. * 16. / 9., 1.);
    XCTAssertEqualWithAccuracy(NSMidX(frame), NSMidX(input.arrangedBounds), 1.);
}

- (void)testArrangedModeCentresOnTheArrangedBoundsNotTheWindow
{
    MacLCVideoFitInput input = baseInput();
    input.mode = MacLCVideoFitModeArranged;
    input.arrangedBounds = NSMakeRect(1028., 0., 1028., 1251.);
    /* The window itself still sits on the other half. */
    input.currentFrame = NSMakeRect(0., 0., 1028., 1251.);

    const NSRect frame = MacLCVideoFitTargetFrame(input);

    XCTAssertEqualWithAccuracy(NSMidX(frame), NSMidX(input.arrangedBounds), 1.);
    XCTAssertEqualWithAccuracy(NSMidY(frame), NSMidY(input.arrangedBounds), 1.);
}

- (void)testArrangedModeFallsBackToTheNativeSizeWhenTheBoundsAreEmpty
{
    MacLCVideoFitInput input = baseInput();
    input.mode = MacLCVideoFitModeArranged;
    input.arrangedBounds = NSZeroRect;

    const NSRect frame = MacLCVideoFitTargetFrame(input);

    XCTAssertEqualWithAccuracy(frame.size.width, 960., 1.);
    XCTAssertEqualWithAccuracy(frame.size.height, 540., 1.);
}

#pragma mark - Keep-width mode (after the user resized)

- (void)testKeepWidthKeepsTheWidthAndDerivesTheHeight
{
    MacLCVideoFitInput input = baseInput();
    input.mode = MacLCVideoFitModeKeepWidth;
    input.currentFrame = NSMakeRect(100., 100., 800., 100.);

    const NSRect frame = MacLCVideoFitTargetFrame(input);

    XCTAssertEqualWithAccuracy(frame.size.width, 800., 1.);
    XCTAssertEqualWithAccuracy(frame.size.height, 450., 1.);
}

- (void)testKeepWidthSubtractsTheChromeFromTheWidthItKeeps
{
    MacLCVideoFitInput input = baseInput();
    input.mode = MacLCVideoFitModeKeepWidth;
    input.chromeSize = NSMakeSize(0., 28.);
    input.currentFrame = NSMakeRect(100., 100., 800., 100.);

    const NSRect frame = MacLCVideoFitTargetFrame(input);

    XCTAssertEqualWithAccuracy(frame.size.width, 800., 1.);
    XCTAssertEqualWithAccuracy(frame.size.height, 450. + 28., 1.);
}

#pragma mark - Clamping

- (void)testAVideoLargerThanTheScreenIsScaledDownKeepingItsRatio
{
    MacLCVideoFitInput input = baseInput();
    input.nativeVideoSize = NSMakeSize(7680., 4320.);
    input.scaleFactor = 1.;

    const NSRect frame = MacLCVideoFitTargetFrame(input);

    XCTAssertLessThanOrEqual(frame.size.width, input.visibleFrame.size.width + 1.);
    XCTAssertLessThanOrEqual(frame.size.height, input.visibleFrame.size.height + 1.);
    XCTAssertEqualWithAccuracy(frame.size.width / frame.size.height, 16. / 9., 0.01);
}

- (void)testATinyVideoIsRaisedToTheMinimumSize
{
    MacLCVideoFitInput input = baseInput();
    input.nativeVideoSize = NSMakeSize(160., 90.);
    input.scaleFactor = 1.;

    const NSRect frame = MacLCVideoFitTargetFrame(input);

    XCTAssertGreaterThanOrEqual(frame.size.width, 320.);
    XCTAssertGreaterThanOrEqual(frame.size.height, 180.);
    XCTAssertEqualWithAccuracy(frame.size.width / frame.size.height, 16. / 9., 0.01);
}

- (void)testTheFrameStaysInsideTheVisibleFrame
{
    MacLCVideoFitInput input = baseInput();
    /* A window hugging the bottom left corner: centring a larger video on it
     * would put the frame off screen. */
    input.currentFrame = NSMakeRect(0., 0., 340., 200.);
    input.nativeVideoSize = NSMakeSize(3840., 2160.);
    input.scaleFactor = 1.;

    const NSRect frame = MacLCVideoFitTargetFrame(input);

    XCTAssertGreaterThanOrEqual(NSMinX(frame), NSMinX(input.visibleFrame) - 1.);
    XCTAssertGreaterThanOrEqual(NSMinY(frame), NSMinY(input.visibleFrame) - 1.);
    XCTAssertLessThanOrEqual(NSMaxX(frame), NSMaxX(input.visibleFrame) + 1.);
    XCTAssertLessThanOrEqual(NSMaxY(frame), NSMaxY(input.visibleFrame) + 1.);
}

- (void)testTheVisibleFrameOriginIsRespected
{
    MacLCVideoFitInput input = baseInput();
    /* A second screen to the right of the main one. */
    input.visibleFrame = NSMakeRect(2056., 0., 1920., 1080.);
    input.currentFrame = NSMakeRect(2056., 0., 400., 300.);
    input.nativeVideoSize = NSMakeSize(3840., 2160.);
    input.scaleFactor = 1.;

    const NSRect frame = MacLCVideoFitTargetFrame(input);

    XCTAssertGreaterThanOrEqual(NSMinX(frame), 2056. - 1.);
    XCTAssertLessThanOrEqual(NSMaxX(frame), 2056. + 1920. + 1.);
}

#pragma mark - Inputs that cannot produce a fit

- (void)testAVideoWithoutASizeIsRejected
{
    MacLCVideoFitInput input = baseInput();

    input.nativeVideoSize = NSZeroSize;
    XCTAssertFalse(MacLCVideoFitInputIsUsable(input));
    assertRectEqual(MacLCVideoFitTargetFrame(input), input.currentFrame, @"zero size");

    input.nativeVideoSize = NSMakeSize(1920., 0.);
    XCTAssertFalse(MacLCVideoFitInputIsUsable(input));

    input.nativeVideoSize = NSMakeSize(-1920., 1080.);
    XCTAssertFalse(MacLCVideoFitInputIsUsable(input));
}

/* A broken sample aspect ratio can make the core report a size that is not a
 * number; feeding that to -setFrame: throws or loses the window. */
- (void)testANonFiniteVideoSizeIsRejected
{
    MacLCVideoFitInput input = baseInput();

    input.nativeVideoSize = NSMakeSize(NAN, 1080.);
    XCTAssertFalse(MacLCVideoFitInputIsUsable(input));
    assertRectEqual(MacLCVideoFitTargetFrame(input), input.currentFrame, @"NaN width");

    input.nativeVideoSize = NSMakeSize(1920., INFINITY);
    XCTAssertFalse(MacLCVideoFitInputIsUsable(input));
    assertRectEqual(MacLCVideoFitTargetFrame(input), input.currentFrame, @"infinite height");
}

- (void)testAScreenWithoutAVisibleAreaIsRejected
{
    MacLCVideoFitInput input = baseInput();
    input.visibleFrame = NSZeroRect;

    XCTAssertFalse(MacLCVideoFitInputIsUsable(input));
    assertRectEqual(MacLCVideoFitTargetFrame(input), input.currentFrame, @"empty screen");
}

- (void)testANegativeChromeIsRejected
{
    MacLCVideoFitInput input = baseInput();
    input.chromeSize = NSMakeSize(0., -28.);

    XCTAssertFalse(MacLCVideoFitInputIsUsable(input));
}

- (void)testAZeroScaleFactorIsTreatedAsOne
{
    MacLCVideoFitInput input = baseInput();
    input.scaleFactor = 0.;
    input.nativeVideoSize = NSMakeSize(1280., 720.);

    XCTAssertTrue(MacLCVideoFitInputIsUsable(input));
    const NSRect frame = MacLCVideoFitTargetFrame(input);
    XCTAssertEqualWithAccuracy(frame.size.width, 1280., 1.);
}

/* Every accepted input must produce a frame the window server can take. */
- (void)testEveryAcceptedInputProducesAFiniteFrame
{
    const NSSize sizes[] = {
        {1920., 1080.}, {1920., 804.}, {640., 480.}, {1., 1.},
        {3840., 2160.}, {16000., 9.}, {9., 16000.},
    };
    const MacLCVideoFitMode modes[] = {
        MacLCVideoFitModeNative, MacLCVideoFitModeArranged, MacLCVideoFitModeKeepWidth,
    };

    for (size_t i = 0; i < sizeof(sizes) / sizeof(sizes[0]); i++) {
        for (size_t m = 0; m < sizeof(modes) / sizeof(modes[0]); m++) {
            MacLCVideoFitInput input = baseInput();
            input.nativeVideoSize = sizes[i];
            input.mode = modes[m];
            input.arrangedBounds = NSMakeRect(0., 0., 1028., 1251.);

            XCTAssertTrue(MacLCVideoFitInputIsUsable(input));
            const NSRect frame = MacLCVideoFitTargetFrame(input);
            XCTAssertTrue(isfinite(frame.origin.x) && isfinite(frame.origin.y) &&
                          isfinite(frame.size.width) && isfinite(frame.size.height),
                          @"%.0fx%.0f mode %zu gave a non-finite frame",
                          sizes[i].width, sizes[i].height, m);
            XCTAssertGreaterThan(frame.size.width, 0.);
            XCTAssertGreaterThan(frame.size.height, 0.);
        }
    }
}

@end
