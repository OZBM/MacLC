/*****************************************************************************
 * MacLCToneCurvesTest.m: tests of the tone curves ported from libplacebo
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

#include "../../video_output/apple/maclc_tonecurves.h"

@interface MacLCToneCurvesTest : XCTestCase
@end

@implementation MacLCToneCurvesTest

enum { N = 256 };

static struct maclc_tonecurve_params Params(enum maclc_tonecurve curve,
                                            float in_max, float out_max)
{
    struct maclc_tonecurve_params p = {
        .curve = curve,
        .param = 0.0f,
        .input_min = 0.0f,
        .input_max = in_max,
        .output_min = 0.0f,
        .output_max = out_max,
        .hdr10plus = NULL,
    };
    return p;
}

/* The input PQ value lut[i] was computed for. */
static float InputPQ(const struct maclc_tonecurve_params *p, int i)
{
    const float lo = maclc_nits_to_pq(p->input_min), hi = maclc_nits_to_pq(p->input_max);
    return lo + (hi - lo) * i / (N - 1);
}

static const enum maclc_tonecurve kCurves[] = {
    MACLC_TC_AUTO, MACLC_TC_CLIP, MACLC_TC_BT2390, MACLC_TC_REINHARD, MACLC_TC_MOBIUS,
    MACLC_TC_HABLE, MACLC_TC_GAMMA, MACLC_TC_LINEAR, MACLC_TC_BT2446A, MACLC_TC_SPLINE,
};

- (void)testEveryCurveIsMonotonicAndStaysUnderThePeak
{
    for (size_t c = 0; c < sizeof(kCurves) / sizeof(kCurves[0]); c++) {
        const struct maclc_tonecurve_params p = Params(kCurves[c], 1000.0f, 400.0f);
        float lut[N];
        maclc_tonecurve_generate(&p, lut, N);
        for (int i = 1; i < N; i++)
            XCTAssertGreaterThanOrEqual(lut[i] + 1e-5f, lut[i - 1], @"curve %d, entry %d", kCurves[c], i);
        XCTAssertLessThanOrEqual(lut[N - 1], maclc_nits_to_pq(400.0f) + 1e-5f, @"curve %d", kCurves[c]);
        XCTAssertLessThan(maclc_pq_to_nits(lut[0]), 0.01f, @"curve %d keeps black", kCurves[c]);
    }
}

- (void)testAutomaticIsSpline
{
    /* libplacebo 7's default (PL_COLOR_MAP_DEFAULTS), which VLC's Automatic
     * leaves in place. */
    const struct maclc_tonecurve_params a = Params(MACLC_TC_AUTO, 4000.0f, 600.0f);
    const struct maclc_tonecurve_params s = Params(MACLC_TC_SPLINE, 4000.0f, 600.0f);
    float la[N], ls[N];
    maclc_tonecurve_generate(&a, la, N);
    maclc_tonecurve_generate(&s, ls, N);
    for (int i = 0; i < N; i++)
        XCTAssertEqual(la[i], ls[i]);
}

- (void)testClipIsIdentityUnderThePeak
{
    const struct maclc_tonecurve_params p = Params(MACLC_TC_CLIP, 1000.0f, 400.0f);
    float lut[N];
    maclc_tonecurve_generate(&p, lut, N);
    const float peak = maclc_nits_to_pq(400.0f);
    for (int i = 0; i < N; i++)
        XCTAssertEqualWithAccuracy(lut[i], fminf(InputPQ(&p, i), peak), 1e-5f);
}

- (void)testBT2390KeepsShadowsAndReachesThePeak
{
    const struct maclc_tonecurve_params p = Params(MACLC_TC_BT2390, 1000.0f, 400.0f);
    float lut[N];
    maclc_tonecurve_generate(&p, lut, N);
    /* Below the knee (and above the black-point lift) the signal is kept. */
    for (int i = N / 4; i < N / 2; i++)
        XCTAssertEqualWithAccuracy(lut[i], InputPQ(&p, i), 1e-3f);
    XCTAssertEqualWithAccuracy(lut[N - 1], maclc_nits_to_pq(400.0f), 1e-4f);
}

- (void)testForwardCurvesDoNotExpand
{
    /* A master dimmer than the display is left alone by the curves that
     * cannot run backwards (libplacebo clamps the target to the source). */
    const struct maclc_tonecurve_params p = Params(MACLC_TC_BT2390, 300.0f, 1000.0f);
    float lut[N];
    maclc_tonecurve_generate(&p, lut, N);
    for (int i = 0; i < N; i++)
        XCTAssertEqualWithAccuracy(lut[i], InputPQ(&p, i), 1e-4f);
}

- (void)testST2094BezierIsMonotonicAndReachesTheTarget
{
    vlc_video_hdr_dynamic_metadata_t md;
    memset(&md, 0, sizeof(md));
    md.targeted_luminance = 400.0f;
    md.maxscl[0] = md.maxscl[1] = md.maxscl[2] = 0.1f; /* 1000 cd/m2 */
    md.average_maxrgb = 0.01f;
    md.tone_mapping_flag = 1;
    md.knee_point_x = 0.1f;
    md.knee_point_y = 0.3f;
    md.num_bezier_anchors = 9;
    const float anchors[9] = { 0.45f, 0.58f, 0.68f, 0.76f, 0.83f, 0.88f, 0.92f, 0.96f, 0.98f };
    memcpy(md.bezier_curve_anchors, anchors, sizeof(anchors));

    struct maclc_tonecurve_params p = Params(MACLC_TC_ST2094_40, 1000.0f, 400.0f);
    p.hdr10plus = &md;
    float lut[N];
    maclc_tonecurve_generate(&p, lut, N);
    for (int i = 1; i < N; i++)
        XCTAssertGreaterThanOrEqual(lut[i] + 1e-5f, lut[i - 1], @"entry %d", i);
    XCTAssertEqualWithAccuracy(maclc_pq_to_nits(lut[N - 1]), 400.0f, 4.0f);
    XCTAssertTrue(maclc_tonecurve_params_equal(&p, &p));
}

@end
