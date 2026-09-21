/*****************************************************************************
 * MacLCFrameInterpolationTest.m
 *****************************************************************************
 * Copyright © 2026 Hazen Studio
 *
 * SPDX-License-Identifier: LGPL-2.1-or-later
 *****************************************************************************/

#import <XCTest/XCTest.h>

#include "../../../video_filter/maclc_frc_geometry.h"

@interface MacLCFrameInterpolationTest : XCTestCase
@end

@implementation MacLCFrameInterpolationTest

- (void)testFactorUsesTheLargestWholeMultiple
{
    /* 24 fps on a 120 Hz panel is the case the whole thing exists for. */
    XCTAssertEqual(maclc_frc_factor(24, 120, 5), 5u);
    XCTAssertEqual(maclc_frc_factor(30, 120, 5), 4u);
    XCTAssertEqual(maclc_frc_factor(60, 120, 5), 2u);
    XCTAssertEqual(maclc_frc_factor(24, 60, 5), 2u);
}

- (void)testFactorRoundsDownRatherThanOvershoot
{
    /* 25 x 5 would be 125 frames a second on a 120 Hz panel. */
    XCTAssertEqual(maclc_frc_factor(25, 120, 5), 4u);
    XCTAssertEqual(maclc_frc_factor(48, 120, 5), 2u);
}

- (void)testFactorLeavesTheVideoAloneWhenThereIsNothingToGain
{
    XCTAssertEqual(maclc_frc_factor(60, 60, 5), 1u);
    XCTAssertEqual(maclc_frc_factor(120, 120, 5), 1u);
    XCTAssertEqual(maclc_frc_factor(90, 60, 5), 1u);
}

- (void)testFactorIsOneWhenSomethingIsUnknownOrForbidden
{
    XCTAssertEqual(maclc_frc_factor(0, 120, 5), 1u);
    XCTAssertEqual(maclc_frc_factor(24, 0, 5), 1u);
    XCTAssertEqual(maclc_frc_factor(24, 120, 1), 1u);
    XCTAssertEqual(maclc_frc_factor(24, 120, 0), 1u);
}

- (void)testFactorHonoursTheCap
{
    XCTAssertEqual(maclc_frc_factor(24, 120, 3), 3u);
    XCTAssertEqual(maclc_frc_factor(24, 240, 8), 8u);
}

- (void)testChromaInterleavingIsReversible
{
    const size_t width = 5, height = 3;
    const size_t cb_stride = 8, cr_stride = 7, packed_stride = 20;
    uint8_t cb[8 * 3], cr[7 * 3], packed[20 * 3];
    uint8_t back_cb[8 * 3], back_cr[7 * 3];

    memset(cb, 0xAA, sizeof(cb));
    memset(cr, 0xBB, sizeof(cr));
    memset(packed, 0, sizeof(packed));
    memset(back_cb, 0, sizeof(back_cb));
    memset(back_cr, 0, sizeof(back_cr));

    for (size_t y = 0; y < height; y++)
        for (size_t x = 0; x < width; x++)
        {
            cb[y * cb_stride + x] = (uint8_t)(1 + y * width + x);
            cr[y * cr_stride + x] = (uint8_t)(100 + y * width + x);
        }

    maclc_frc_interleave_chroma(packed, packed_stride, cb, cb_stride,
                                cr, cr_stride, width, height);

    /* Cb first, then Cr, sample by sample. */
    XCTAssertEqual(packed[0], 1);
    XCTAssertEqual(packed[1], 100);
    XCTAssertEqual(packed[2], 2);
    XCTAssertEqual(packed[packed_stride], 6);
    XCTAssertEqual(packed[packed_stride + 1], 105);

    /* Nothing written past the samples that exist. */
    XCTAssertEqual(packed[width * 2], 0);

    maclc_frc_deinterleave_chroma(packed, packed_stride, back_cb, cb_stride,
                                  back_cr, cr_stride, width, height);

    for (size_t y = 0; y < height; y++)
        for (size_t x = 0; x < width; x++)
        {
            XCTAssertEqual(back_cb[y * cb_stride + x], cb[y * cb_stride + x]);
            XCTAssertEqual(back_cr[y * cr_stride + x], cr[y * cr_stride + x]);
        }
    XCTAssertEqual(back_cb[width], 0);
}

@end
