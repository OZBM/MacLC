/*****************************************************************************
 * MacLCSDRToHDRTest.m: tests of the SDR to HDR curves and of Automatic
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

#import <XCTest/XCTest.h>

#include "../../video_output/apple/maclc_sdr2hdr.h"

@interface MacLCSDRToHDRTest : XCTestCase
@end

@implementation MacLCSDRToHDRTest

static struct maclc_sdr2hdr_env Env(void)
{
    struct maclc_sdr2hdr_env e = {
        .model_available = true,
        .max_model_available = true,
        .gpu = MACLC_SDR2HDR_GPU_MAX,
        .on_battery = false,
        .low_power_mode = false,
        .thermal_state = 0,
        .pixel_rate = 1920.0 * 1080.0 * 24.0,
        .frame_interpolation = false,
    };
    return e;
}

- (void)testNamesRoundTrip
{
    for (int q = MACLC_SDR2HDR_AUTO; q <= MACLC_SDR2HDR_MAXIMUM; q++)
        XCTAssertEqual(maclc_sdr2hdr_quality_parse(maclc_sdr2hdr_quality_name(q)), q);
    for (int d = MACLC_SDR2HDR_DEBAND_OFF; d <= MACLC_SDR2HDR_DEBAND_STRONG; d++)
        XCTAssertEqual(maclc_sdr2hdr_deband_parse(maclc_sdr2hdr_deband_name(d)), d);
    for (int r = MACLC_SDR2HDR_REASON_CHOSEN; r <= MACLC_SDR2HDR_REASON_NO_HEADROOM; r++)
        XCTAssertEqual(maclc_sdr2hdr_reason_parse(maclc_sdr2hdr_reason_name(r)), r);
    /* unknown or missing values fall back to the defaults */
    XCTAssertEqual(maclc_sdr2hdr_quality_parse(NULL), MACLC_SDR2HDR_AUTO);
    XCTAssertEqual(maclc_sdr2hdr_quality_parse("ultra"), MACLC_SDR2HDR_AUTO);
    XCTAssertEqual(maclc_sdr2hdr_deband_parse(NULL), MACLC_SDR2HDR_DEBAND_NORMAL);
}

- (void)testBoostIsReferenceNits
{
    XCTAssertEqualWithAccuracy(maclc_sdr2hdr_boost_to_nits(4.0f), 400.0f, 1e-3);
    XCTAssertEqualWithAccuracy(maclc_sdr2hdr_nits_to_boost(1600.0f), 16.0f, 1e-3);
    XCTAssertEqualWithAccuracy(maclc_sdr2hdr_nits_to_boost(50.0f), 1.0f, 1e-6);
    XCTAssertEqualWithAccuracy(maclc_sdr2hdr_nits_to_boost(99999.0f), 16.0f, 1e-6);
}

- (void)testFastCurve
{
    const float knee = MACLC_SDR2HDR_FAST_KNEE, peak = 4.0f;
    /* untouched below the knee */
    XCTAssertEqual(maclc_sdr2hdr_fast_curve(0.3f, knee, peak), 0.3f);
    XCTAssertEqual(maclc_sdr2hdr_fast_curve(knee, knee, peak), knee);
    /* full-scale white lands on the peak */
    XCTAssertEqualWithAccuracy(maclc_sdr2hdr_fast_curve(1.0f, knee, peak), peak, 1e-5);
    /* value and slope continuous at the knee, and at white (a forward
     * difference over h overestimates the quadratic's slope by
     * (peak - 1) * h / span^2) */
    const float h = 1e-3f;
    XCTAssertEqualWithAccuracy((maclc_sdr2hdr_fast_curve(knee + h, knee, peak) - knee) / h,
                               1.0f + (peak - 1.0f) * h / ((1.0f - knee) * (1.0f - knee)), 2e-3);
    const float left = (maclc_sdr2hdr_fast_curve(1.0f, knee, peak) - maclc_sdr2hdr_fast_curve(1.0f - h, knee, peak)) / h;
    const float right = (maclc_sdr2hdr_fast_curve(1.0f + h, knee, peak) - maclc_sdr2hdr_fast_curve(1.0f, knee, peak)) / h;
    XCTAssertEqualWithAccuracy(left, right, 2e-2 * right);
    /* monotonic */
    float prev = 0.0f;
    for (float d = 0.0f; d <= 1.2f; d += 0.01f) {
        const float e = maclc_sdr2hdr_fast_curve(d, knee, peak);
        XCTAssertGreaterThanOrEqual(e, prev);
        prev = e;
    }
    /* no headroom, no change */
    XCTAssertEqual(maclc_sdr2hdr_fast_curve(0.9f, knee, 1.0f), 0.9f);
}

- (void)testBalancedLeavesDiffuseWhiteAlone
{
    const float budget = 4.0f;
    XCTAssertEqual(maclc_sdr2hdr_balanced_log_gain(logf(0.5f), budget), 0.0f);
    XCTAssertEqual(maclc_sdr2hdr_balanced_log_gain(logf(MACLC_SDR2HDR_DIFFUSE_WHITE), budget), 0.0f);
    XCTAssertEqualWithAccuracy(maclc_sdr2hdr_balanced_log_gain(0.0f, budget), logf(budget), 1e-6);
    XCTAssertEqualWithAccuracy(maclc_sdr2hdr_balanced_log_gain(0.1f, budget), logf(budget), 1e-6);
    XCTAssertEqual(maclc_sdr2hdr_balanced_log_gain(0.0f, 1.0f), 0.0f);
    float prev = -1.0f;
    for (float u = -1.0f; u <= 0.2f; u += 0.01f) {
        const float g = maclc_sdr2hdr_balanced_log_gain(u, budget);
        XCTAssertGreaterThanOrEqual(g, prev);
        prev = g;
    }
    /* 90 % of the signal (graded diffuse white) is shown as in SDR */
    XCTAssertEqualWithAccuracy(maclc_sdr2hdr_curve_point(MACLC_SDR2HDR_BALANCED, 0.9f, 4.0f, 0.0f, 16.0f, 0.0f),
                               powf(0.9f, 1.961f), 1e-3);
}

- (void)testAreaLimiter
{
    XCTAssertEqual(maclc_sdr2hdr_area_factor(0.0f), 1.0f);
    XCTAssertEqual(maclc_sdr2hdr_area_factor(MACLC_SDR2HDR_AREA_LOW), 1.0f);
    XCTAssertEqualWithAccuracy(maclc_sdr2hdr_area_factor(MACLC_SDR2HDR_AREA_HIGH), MACLC_SDR2HDR_AREA_FLOOR, 1e-6);
    XCTAssertEqualWithAccuracy(maclc_sdr2hdr_area_factor(1.0f), MACLC_SDR2HDR_AREA_FLOOR, 1e-6);
    /* the numbers measured on the bars clip: 17.7 % of highlights, peak 4 */
    XCTAssertEqualWithAccuracy(maclc_sdr2hdr_budget(4.0f, 0.177f), 2.76f, 0.01f);
    XCTAssertEqual(maclc_sdr2hdr_budget(1.0f, 0.0f), 1.0f);
}

- (void)testMidtonesKeepRoomForHighlights
{
    XCTAssertEqual(maclc_sdr2hdr_white_level(0.0f, 4.0f), 1.0f);
    XCTAssertEqualWithAccuracy(maclc_sdr2hdr_white_level(1.0f, 16.0f), MACLC_SDR2HDR_LIFTED_WHITE, 1e-6);
    /* peak 2.4: white may not go above 2.4 / 1.5 = 1.6 */
    XCTAssertEqualWithAccuracy(maclc_sdr2hdr_white_level(1.0f, 2.4f), 1.6f, 1e-6);
    /* never below SDR white */
    XCTAssertEqual(maclc_sdr2hdr_white_level(1.0f, 1.0f), 1.0f);
}

- (void)testRolloffStaysUnderTheCeiling
{
    const float ceiling = 4.44f;
    XCTAssertEqual(maclc_sdr2hdr_rolloff(1.0f, ceiling), 1.0f);
    XCTAssertEqual(maclc_sdr2hdr_rolloff(0.8f * ceiling, ceiling), 0.8f * ceiling);
    for (float x = 0.0f; x < 40.0f; x += 0.25f)
        XCTAssertLessThanOrEqual(maclc_sdr2hdr_rolloff(x, ceiling), ceiling);
    /* measured on the bars clip with Fast: 4.0 shown as 3.905 */
    XCTAssertEqualWithAccuracy(maclc_sdr2hdr_rolloff(4.0f, ceiling), 3.905f, 2e-3);
    /* no extended range: nothing to roll off into */
    XCTAssertEqual(maclc_sdr2hdr_rolloff(3.0f, 1.0f), 3.0f);
}

- (void)testLearnedGainsAreAbsolute
{
    /* Below the training peak a share is read as P_TRAIN^share whatever the
     * budget, so a highlight the model puts at 2x white stays at 2x... */
    const float share = logf(2.0f) / logf(MACLC_SDR2HDR_P_TRAIN);
    XCTAssertEqualWithAccuracy(expf(share * maclc_sdr2hdr_grid_log_scale(4.44f)), 2.0f, 1e-4);
    XCTAssertEqualWithAccuracy(expf(share * maclc_sdr2hdr_grid_log_scale(1.5f)), 2.0f, 1e-4);
    /* ...and the full share stretches to a budget above the training peak. */
    XCTAssertEqualWithAccuracy(expf(maclc_sdr2hdr_grid_log_scale(16.0f)), 16.0f, 1e-3);
    XCTAssertEqualWithAccuracy(expf(maclc_sdr2hdr_grid_log_scale(4.44f)), MACLC_SDR2HDR_P_TRAIN, 1e-3);
}

- (void)testSaturationOnlyTouchesExpandedColours
{
    float rgb[3] = { 0.8f, 0.2f, 0.1f };
    maclc_sdr2hdr_saturate(rgb, 0.4f, 1.5f, 0.0f);
    XCTAssertEqual(rgb[0], 0.8f);
    XCTAssertEqual(rgb[1], 0.2f);
    float rgb2[3] = { 0.8f, 0.2f, 0.1f };
    maclc_sdr2hdr_saturate(rgb2, 0.4f, 0.5f, 1.0f);
    XCTAssertEqualWithAccuracy(rgb2[0], 0.6f, 1e-6);
    XCTAssertEqualWithAccuracy(rgb2[1], 0.3f, 1e-6);
}

- (void)testPeakFollowsDropsAtOnceAndRisesSlowly
{
    XCTAssertEqual(maclc_sdr2hdr_smooth_peak(4.0f, 2.0f, 0.04f), 2.0f);
    const float up = maclc_sdr2hdr_smooth_peak(2.0f, 4.0f, 0.04f);
    XCTAssertGreaterThan(up, 2.0f);
    XCTAssertLessThan(up, 2.2f);
    XCTAssertEqual(maclc_sdr2hdr_target_peak(8.0f, 2.67f), 2.67f);
    XCTAssertEqual(maclc_sdr2hdr_target_peak(4.0f, 0.5f), 1.0f);
}

- (void)testAutomatic
{
    enum maclc_sdr2hdr_reason why;
    struct maclc_sdr2hdr_env e = Env();
    /* a Max GPU on mains power runs Maximum when its network is there */
    XCTAssertEqual(maclc_sdr2hdr_auto_quality(&e, &why), MACLC_SDR2HDR_MAXIMUM);
    XCTAssertEqual(why, MACLC_SDR2HDR_REASON_AC_POWER);
    e.max_model_available = false;
    XCTAssertEqual(maclc_sdr2hdr_auto_quality(&e, &why), MACLC_SDR2HDR_HIGH);

    e = Env(); e.on_battery = true;
    XCTAssertEqual(maclc_sdr2hdr_auto_quality(&e, &why), MACLC_SDR2HDR_BALANCED);
    XCTAssertEqual(why, MACLC_SDR2HDR_REASON_BATTERY);

    e = Env(); e.low_power_mode = true;
    XCTAssertEqual(maclc_sdr2hdr_auto_quality(&e, &why), MACLC_SDR2HDR_FAST);
    XCTAssertEqual(why, MACLC_SDR2HDR_REASON_LOW_POWER);

    e = Env(); e.thermal_state = 3;
    XCTAssertEqual(maclc_sdr2hdr_auto_quality(&e, &why), MACLC_SDR2HDR_FAST);
    e = Env(); e.thermal_state = 2;
    XCTAssertEqual(maclc_sdr2hdr_auto_quality(&e, &why), MACLC_SDR2HDR_BALANCED);
    XCTAssertEqual(why, MACLC_SDR2HDR_REASON_THERMAL);

    e = Env(); e.model_available = false;
    XCTAssertEqual(maclc_sdr2hdr_auto_quality(&e, &why), MACLC_SDR2HDR_BALANCED);
    XCTAssertEqual(why, MACLC_SDR2HDR_REASON_MODEL_MISSING);

    /* a base M chip keeps High (never Maximum) for 1080p, not for 4K */
    e = Env(); e.gpu = MACLC_SDR2HDR_GPU_BASE;
    XCTAssertEqual(maclc_sdr2hdr_auto_quality(&e, &why), MACLC_SDR2HDR_HIGH);
    e.pixel_rate = MACLC_SDR2HDR_PIXEL_RATE_4K30;
    XCTAssertEqual(maclc_sdr2hdr_auto_quality(&e, &why), MACLC_SDR2HDR_BALANCED);
    XCTAssertEqual(why, MACLC_SDR2HDR_REASON_LOAD);

    /* frame interpolation doubles the load: a Pro at 4K60 steps down */
    e = Env(); e.gpu = MACLC_SDR2HDR_GPU_PRO; e.pixel_rate = 3840.0 * 2160.0 * 60.0;
    XCTAssertEqual(maclc_sdr2hdr_auto_quality(&e, &why), MACLC_SDR2HDR_MAXIMUM);
    e.frame_interpolation = true;
    XCTAssertEqual(maclc_sdr2hdr_auto_quality(&e, &why), MACLC_SDR2HDR_BALANCED);

    /* on battery Automatic stays on Balanced whatever the GPU */
    e = Env(); e.pixel_rate = 640.0 * 360.0 * 24.0; e.on_battery = true;
    XCTAssertEqual(maclc_sdr2hdr_auto_quality(&e, &why), MACLC_SDR2HDR_BALANCED);
}

- (void)testResolve
{
    enum maclc_sdr2hdr_reason why;
    struct maclc_sdr2hdr_env e = Env();
    XCTAssertEqual(maclc_sdr2hdr_resolve_quality(MACLC_SDR2HDR_FAST, &e, &why), MACLC_SDR2HDR_FAST);
    XCTAssertEqual(why, MACLC_SDR2HDR_REASON_CHOSEN);
    XCTAssertEqual(maclc_sdr2hdr_resolve_quality(MACLC_SDR2HDR_MAXIMUM, &e, &why), MACLC_SDR2HDR_MAXIMUM);
    e.model_available = false;
    XCTAssertEqual(maclc_sdr2hdr_resolve_quality(MACLC_SDR2HDR_HIGH, &e, &why), MACLC_SDR2HDR_BALANCED);
    XCTAssertEqual(why, MACLC_SDR2HDR_REASON_MODEL_MISSING);
    XCTAssertEqual(maclc_sdr2hdr_step_down(MACLC_SDR2HDR_MAXIMUM), MACLC_SDR2HDR_HIGH);
    XCTAssertEqual(maclc_sdr2hdr_step_down(MACLC_SDR2HDR_HIGH), MACLC_SDR2HDR_BALANCED);
    XCTAssertEqual(maclc_sdr2hdr_step_down(MACLC_SDR2HDR_FAST), MACLC_SDR2HDR_FAST);
}

- (void)testGPUClassFromName
{
    XCTAssertEqual(maclc_sdr2hdr_gpu_class_from_name("Apple M3 Max"), MACLC_SDR2HDR_GPU_MAX);
    XCTAssertEqual(maclc_sdr2hdr_gpu_class_from_name("Apple M2 Ultra"), MACLC_SDR2HDR_GPU_MAX);
    XCTAssertEqual(maclc_sdr2hdr_gpu_class_from_name("Apple M4 Pro"), MACLC_SDR2HDR_GPU_PRO);
    XCTAssertEqual(maclc_sdr2hdr_gpu_class_from_name("Apple M1"), MACLC_SDR2HDR_GPU_BASE);
    XCTAssertEqual(maclc_sdr2hdr_gpu_class_from_name("AMD Radeon Pro 5500M"), MACLC_SDR2HDR_GPU_PRO);
    XCTAssertEqual(maclc_sdr2hdr_gpu_class_from_name(NULL), MACLC_SDR2HDR_GPU_UNKNOWN);
}

@end
