/****************************************************************************
 * MacLCResumePositionTest.m: tests for the positions offered for resuming
 ****************************************************************************
 * Copyright (C) 2026 Hazen Studio
 *
 * This program is free software; you can redistribute it and/or modify it
 * under the terms of the GNU General Public License as published by the
 * Free Software Foundation; either version 2 of the License, or (at your
 * option) any later version.
 *****************************************************************************/

#import <XCTest/XCTest.h>

#import "playqueue/MacLCResumePosition.h"

#include <math.h>

static const int64_t kTwoHoursMs = 2 * 60 * 60 * 1000;
static const int64_t kFourMinutesMs = 4 * 60 * 1000;

@interface MacLCResumePositionTest : XCTestCase
@end

@implementation MacLCResumePositionTest

/* The case that showed "will continue at 1:39:15" for a 6 s clip: the media
 * library had kept the clip's last frame (it never learnt its duration), and
 * the clip's duration, in ticks, was read as milliseconds. */
- (void)testAShortClipPlayedToItsEndIsNeverOffered
{
    const int64_t duration = MacLCMediaDurationInMilliseconds(VLC_TICK_FROM_SEC(6), -1);
    XCTAssertEqual(duration, 6000);
    XCTAssertFalse(MacLCCanResumeAtPosition(0.9925773, duration));
    XCTAssertEqual(MacLCResumeTimeInSeconds(0.9925773, duration), -1);
}

- (void)testTheDurationIsTakenInMilliseconds
{
    XCTAssertEqual(MacLCMediaDurationInMilliseconds(VLC_TICK_FROM_MS(kFourMinutesMs), -1),
                   kFourMinutesMs);
    XCTAssertEqual(MacLCMediaDurationInMilliseconds(VLC_TICK_FROM_SEC(90 * 60), -1),
                   90 * 60 * 1000);
}

/* The input item does not always know its duration when the media starts;
 * the library's own figure, already in milliseconds, stands in for it. */
- (void)testTheLibraryDurationStandsInForAnUnknownInputDuration
{
    XCTAssertEqual(MacLCMediaDurationInMilliseconds(VLC_TICK_INVALID, kTwoHoursMs), kTwoHoursMs);
    XCTAssertEqual(MacLCMediaDurationInMilliseconds(-1, kTwoHoursMs), kTwoHoursMs);
    XCTAssertEqual(MacLCMediaDurationInMilliseconds(VLC_TICK_FROM_SEC(60), kTwoHoursMs),
                   60 * 1000);
    XCTAssertLessThanOrEqual(MacLCMediaDurationInMilliseconds(VLC_TICK_INVALID, -1), 0);
}

- (void)testTheResumeTimeIsInSecondsInsideTheMedia
{
    XCTAssertEqual(MacLCResumeTimeInSeconds(0.5, kFourMinutesMs), 120);
    XCTAssertEqual(MacLCResumeTimeInSeconds(0.25, kTwoHoursMs), 30 * 60);

    for (double position = 0.001; position < 1.; position += 0.001) {
        const int64_t seconds = MacLCResumeTimeInSeconds(position, kTwoHoursMs);
        XCTAssertLessThan(seconds, kTwoHoursMs / 1000);
    }
}

- (void)testAPositionAtOrPastTheEndIsNeverOffered
{
    XCTAssertFalse(MacLCCanResumeAtPosition(1., kTwoHoursMs));
    XCTAssertFalse(MacLCCanResumeAtPosition(1.5, kTwoHoursMs));
    XCTAssertFalse(MacLCCanResumeAtPosition(11., kFourMinutesMs));
    XCTAssertEqual(MacLCResumeTimeInSeconds(1., kTwoHoursMs), -1);
}

- (void)testNothingIsOfferedWithoutADuration
{
    XCTAssertFalse(MacLCCanResumeAtPosition(0.5, -1));
    XCTAssertFalse(MacLCCanResumeAtPosition(0.5, 0));
    XCTAssertEqual(MacLCResumeTimeInSeconds(0.5, -1), -1);
}

- (void)testOnlyMediaOfThreeMinutesOrMoreAreResumed
{
    XCTAssertFalse(MacLCCanResumeAtPosition(0.5, 3 * 60 * 1000 - 1));
    XCTAssertTrue(MacLCCanResumeAtPosition(0.5, 3 * 60 * 1000));
}

/* Nothing in the first or last minute or 5 %, whichever is shorter. */
- (void)testTheStartAndTheEndOfAMediaAreNotResumed
{
    const int64_t threeMinutes = 3 * 60 * 1000;
    XCTAssertFalse(MacLCCanResumeAtPosition(0.04, threeMinutes));
    XCTAssertTrue(MacLCCanResumeAtPosition(0.06, threeMinutes));
    XCTAssertTrue(MacLCCanResumeAtPosition(0.94, threeMinutes));
    XCTAssertFalse(MacLCCanResumeAtPosition(0.96, threeMinutes));

    XCTAssertFalse(MacLCCanResumeAtPosition(0.005, kTwoHoursMs));
    XCTAssertTrue(MacLCCanResumeAtPosition(0.01, kTwoHoursMs));
    XCTAssertTrue(MacLCCanResumeAtPosition(0.99, kTwoHoursMs));
    XCTAssertFalse(MacLCCanResumeAtPosition(0.995, kTwoHoursMs));
}

- (void)testPositionsOutsideTheMediaAreRefused
{
    XCTAssertFalse(MacLCCanResumeAtPosition(0., kTwoHoursMs));
    XCTAssertFalse(MacLCCanResumeAtPosition(-1., kTwoHoursMs));
    XCTAssertFalse(MacLCCanResumeAtPosition(NAN, kTwoHoursMs));
    XCTAssertEqual(MacLCResumeTimeInSeconds(NAN, kTwoHoursMs), -1);
}

@end
