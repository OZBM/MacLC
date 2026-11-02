/*****************************************************************************
 * MacLCUpscalingTest.m
 *****************************************************************************
 * Copyright © 2026 Hazen Studio
 *
 * SPDX-License-Identifier: LGPL-2.1-or-later
 *****************************************************************************/

#import <XCTest/XCTest.h>

#include "../../../video_output/apple/maclc_upscale_vars.h"

@interface MacLCUpscalingTest : XCTestCase
@end

@implementation MacLCUpscalingTest

- (void)testParsesAnActiveState
{
    struct maclc_upscale_state st;
    XCTAssertTrue(maclc_upscale_parse_state("neural+fast 720x480 3840x2160", &st));
    XCTAssertTrue(st.active);
    XCTAssertEqual(strcmp(st.path, "neural+fast"), 0);
    XCTAssertEqual(st.in_w, 720u);
    XCTAssertEqual(st.in_h, 480u);
    XCTAssertEqual(st.out_w, 3840u);
    XCTAssertEqual(st.out_h, 2160u);
    XCTAssertEqual(st.why[0], '\0');
}

- (void)testKeepsTheReasonTheNeuralPassWasSkipped
{
    struct maclc_upscale_state st;
    XCTAssertTrue(maclc_upscale_parse_state("fast 1920x1080 3840x2160 size", &st));
    XCTAssertEqual(strcmp(st.path, "fast"), 0);
    XCTAssertEqual(strcmp(st.why, "size"), 0);
}

- (void)testIdleStatesAreNotActive
{
    struct maclc_upscale_state st;
    XCTAssertTrue(maclc_upscale_parse_state("idle fits", &st));
    XCTAssertFalse(st.active);
    XCTAssertEqual(strcmp(st.why, "fits"), 0);
    XCTAssertFalse(maclc_upscale_parse_state(NULL, &st));
    XCTAssertFalse(maclc_upscale_parse_state("garbage", &st));
    XCTAssertFalse(st.active);
}

- (void)testSizeLabelsUseTheLongSide
{
    char buf[16];
    maclc_upscale_size_label(3840, 1600, buf, sizeof(buf));
    XCTAssertEqual(strcmp(buf, "4K"), 0);
    maclc_upscale_size_label(2560, 1440, buf, sizeof(buf));
    XCTAssertEqual(strcmp(buf, "1440p"), 0);
    maclc_upscale_size_label(1920, 800, buf, sizeof(buf));
    XCTAssertEqual(strcmp(buf, "1080p"), 0);
    maclc_upscale_size_label(1280, 720, buf, sizeof(buf));
    XCTAssertEqual(strcmp(buf, "720p"), 0);
    maclc_upscale_size_label(720, 480, buf, sizeof(buf));
    XCTAssertEqual(strcmp(buf, "480p"), 0);
    maclc_upscale_size_label(1080, 1920, buf, sizeof(buf));
    XCTAssertEqual(strcmp(buf, "1080p"), 0);
}

- (void)testMethodsRoundTripAndUnknownIsAuto
{
    for (int i = 0; i < MACLC_UPSCALE_METHOD_COUNT; i++)
        XCTAssertEqual((int)maclc_upscale_parse_method(maclc_upscale_method_names[i]), i);
    XCTAssertEqual(maclc_upscale_parse_method("apple4x"), MACLC_UPSCALE_APPLE4X);
    XCTAssertEqual(maclc_upscale_parse_method("anime4k"), MACLC_UPSCALE_ANIME4K);
    XCTAssertEqual(maclc_upscale_parse_method("fsrcnnx"), MACLC_UPSCALE_FSRCNNX);
    XCTAssertEqual(maclc_upscale_parse_method("nis"), MACLC_UPSCALE_NIS);
    XCTAssertEqual(maclc_upscale_parse_method(NULL), MACLC_UPSCALE_AUTO);
    XCTAssertEqual(maclc_upscale_parse_method("best"), MACLC_UPSCALE_AUTO);
}

- (void)testLongestPathFits
{
    struct maclc_upscale_state st;
    XCTAssertTrue(maclc_upscale_parse_state("neural4x+fast 640x360 3840x2160 loading", &st));
    XCTAssertEqual(strcmp(st.path, "neural4x+fast"), 0);
    XCTAssertEqual(strcmp(st.why, "loading"), 0);
}

@end
