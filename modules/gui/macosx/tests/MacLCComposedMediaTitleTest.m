/****************************************************************************
 * MacLCComposedMediaTitleTest.m: window title composition tests
 ****************************************************************************
 * Copyright (C) 2026 Hazen Studio
 *
 * This program is free software; you can redistribute it and/or modify it
 * under the terms of the GNU General Public License as published by the
 * Free Software Foundation; either version 2 of the License, or (at your
 * option) any later version.
 *****************************************************************************/

#import <XCTest/XCTest.h>

#import "extensions/NSString+Helpers.h"

@interface MacLCComposedMediaTitleTest : XCTestCase
@end

@implementation MacLCComposedMediaTitleTest

- (void)testTitleAndNowPlayingAreJoined
{
    XCTAssertEqualObjects(MacLCComposedMediaTitle(@"Stream", @"Artist - Song"),
                          @"Stream — Artist - Song");
}

/* An item without now-playing metadata must not get a dangling separator:
 * the metadata getters return an empty string, never nil. */
- (void)testEmptyNowPlayingLeavesTheTitleAlone
{
    XCTAssertEqualObjects(MacLCComposedMediaTitle(@"clip.mp4", @""), @"clip.mp4");
    XCTAssertEqualObjects(MacLCComposedMediaTitle(@"clip.mp4", nil), @"clip.mp4");
}

- (void)testWhitespaceOnlyNowPlayingIsStillShown
{
    /* Only emptiness is special: a string of spaces is metadata the file
     * really carries, and the window shows what the file says. */
    XCTAssertEqualObjects(MacLCComposedMediaTitle(@"clip.mp4", @" "),
                          @"clip.mp4 —  ");
}

- (void)testWithoutATitleThereIsNothingToShow
{
    XCTAssertEqualObjects(MacLCComposedMediaTitle(nil, @"Artist - Song"), @"");
    XCTAssertEqualObjects(MacLCComposedMediaTitle(@"", @"Artist - Song"), @"");
    XCTAssertEqualObjects(MacLCComposedMediaTitle(nil, nil), @"");
}

- (void)testResultIsNeverNil
{
    XCTAssertNotNil(MacLCComposedMediaTitle(nil, nil));
    XCTAssertNotNil(MacLCComposedMediaTitle(@"", @""));
}

@end
