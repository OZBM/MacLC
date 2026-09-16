/*****************************************************************************
 * maclc_tonemap.c: standalone unit test for HDR picture-mode tone curves
 *****************************************************************************
 * Copyright (C) 2026 Hazen Studio
 *
 * This program is free software; you can redistribute it and/or modify it
 * under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin Street, Fifth Floor, Boston MA 02110-1301, USA.
 *****************************************************************************/

#include <stdio.h>
#include <math.h>
#include <stdbool.h>

#include "../../../modules/video_output/apple/maclc_tonemap.h"
#include "../../../modules/video_output/apple/maclc_hdr_vars.h"

#define CHECK(cond) do { \
    if (!(cond)) { \
        fprintf(stderr, "FAIL: %s:%d: assertion '%s' failed\n", __FILE__, __LINE__, #cond); \
        return 1; \
    } \
} while (0)

struct test_pair {
    float content_peak;
    float display_peak;
};

static const struct test_pair k_pairs[] = {
    {  1000.0f, 1600.0f },
    {  4000.0f, 1600.0f },
    {  4000.0f,  500.0f },
    { 10000.0f, 1000.0f },
    {   600.0f, 1600.0f },
    {  1000.0f,  203.0f }
};

static const maclc_tone_mode k_modes[] = {
    MACLC_TONE_ACCURATE,
    MACLC_TONE_BALANCED,
    MACLC_TONE_BRIGHT
};

int main(void)
{
    /*
     * 1. PQ round trip within 0.5 % over 0.01..10000 nits
     */
    for (float log_n = -2.0f; log_n <= 4.0f; log_n += 0.02f) {
        float nits = powf(10.0f, log_n);
        float pq = maclc_nits_to_pq(nits);
        float rt_nits = maclc_pq_to_nits(pq);
        float rel_err = fabsf(rt_nits - nits) / nits;
        CHECK(rel_err <= 0.005f);
    }
    {
        float nits_min = 0.01f;
        float pq_min = maclc_nits_to_pq(nits_min);
        float rt_min = maclc_pq_to_nits(pq_min);
        CHECK(fabsf(rt_min - nits_min) / nits_min <= 0.005f);

        float nits_max = 10000.0f;
        float pq_max = maclc_nits_to_pq(nits_max);
        float rt_max = maclc_pq_to_nits(pq_max);
        CHECK(fabsf(rt_max - nits_max) / nits_max <= 0.005f);
    }

    /*
     * 2. f(0) = 0 for all modes and test pairs
     */
    for (size_t i = 0; i < sizeof(k_pairs) / sizeof(k_pairs[0]); i++) {
        for (size_t m = 0; m < sizeof(k_modes) / sizeof(k_modes[0]); m++) {
            maclc_tone_params p;
            maclc_tone_params_init(&p, k_modes[m], k_pairs[i].content_peak, k_pairs[i].display_peak, 203.0f);
            CHECK(maclc_tone_map_nits(&p, 0.0f) == 0.0f);
            CHECK(maclc_tone_map_pq(&p, 0.0f) == 0.0f);
        }
    }

    /*
     * 3. Monotonic on a 1000-point sweep for every mode and pair
     * 4. f(x) <= display_peak + 0.01
     */
    for (size_t i = 0; i < sizeof(k_pairs) / sizeof(k_pairs[0]); i++) {
        for (size_t m = 0; m < sizeof(k_modes) / sizeof(k_modes[0]); m++) {
            maclc_tone_params p;
            maclc_tone_params_init(&p, k_modes[m], k_pairs[i].content_peak, k_pairs[i].display_peak, 203.0f);

            /* 1000-point sweep in luminance space (0 to 10000 nits) */
            float prev_nits = -1.0f;
            for (int k = 0; k <= 1000; k++) {
                float in_nits = (float)k * 10.0f;
                float out_nits = maclc_tone_map_nits(&p, in_nits);
                CHECK(out_nits >= prev_nits);
                CHECK(out_nits <= p.display_peak + 0.01f);
                prev_nits = out_nits;
            }

            /* 1000-point sweep in PQ code values (0.0 to 1.0) */
            float prev_pq = -1.0f;
            for (int k = 0; k <= 1000; k++) {
                float in_pq = (float)k / 1000.0f;
                float out_pq = maclc_tone_map_pq(&p, in_pq);
                CHECK(out_pq >= prev_pq);
                CHECK(out_pq <= p.dst_peak_pq + 0.0001f);
                prev_pq = out_pq;
            }
        }
    }

    /*
     * 5. Identity case exact when gain == 1 and content_peak <= display_peak
     */
    {
        maclc_tone_params p1, p2;
        maclc_tone_params_init(&p1, MACLC_TONE_ACCURATE, 1000.0f, 1600.0f, 203.0f);
        maclc_tone_params_init(&p2, MACLC_TONE_BALANCED, 600.0f, 1600.0f, 203.0f);

        CHECK(p1.identity == true);
        CHECK(p2.identity == true);

        for (int k = 0; k <= 100; k++) {
            float in_nits = (float)k * 10.0f;
            CHECK(maclc_tone_map_nits(&p1, in_nits) == in_nits);
            float in_pq = maclc_nits_to_pq(in_nits);
            CHECK(maclc_tone_map_pq(&p1, in_pq) == in_pq);
        }

        for (int k = 0; k <= 60; k++) {
            float in_nits = (float)k * 10.0f;
            CHECK(maclc_tone_map_nits(&p2, in_nits) == in_nits);
            float in_pq = maclc_nits_to_pq(in_nits);
            CHECK(maclc_tone_map_pq(&p2, in_pq) == in_pq);
        }
    }

    /*
     * 6. BRIGHT >= BALANCED at 100 and 203 nits when gain > 1
     */
    for (size_t i = 0; i < sizeof(k_pairs) / sizeof(k_pairs[0]); i++) {
        maclc_tone_params p_bright, p_balanced;
        maclc_tone_params_init(&p_bright, MACLC_TONE_BRIGHT, k_pairs[i].content_peak, k_pairs[i].display_peak, 203.0f);
        maclc_tone_params_init(&p_balanced, MACLC_TONE_BALANCED, k_pairs[i].content_peak, k_pairs[i].display_peak, 203.0f);

        if (p_bright.gain > 1.0f) {
            float br100 = maclc_tone_map_nits(&p_bright, 100.0f);
            float bal100 = maclc_tone_map_nits(&p_balanced, 100.0f);
            CHECK(br100 >= bal100);

            float br203 = maclc_tone_map_nits(&p_bright, 203.0f);
            float bal203 = maclc_tone_map_nits(&p_balanced, 203.0f);
            CHECK(br203 >= bal203);
        }
    }

    /*
     * 7. ACCURATE maps 0.8 * display_peak to within 1 % of itself when content_peak > display_peak
     */
    {
        maclc_tone_params p_acc;
        maclc_tone_params_init(&p_acc, MACLC_TONE_ACCURATE, 4000.0f, 1600.0f, 203.0f);
        CHECK(p_acc.content_peak > p_acc.display_peak);
        float in_nits = 0.8f * p_acc.display_peak;
        float out_nits = maclc_tone_map_nits(&p_acc, in_nits);
        float rel_diff = fabsf(out_nits - in_nits) / in_nits;
        CHECK(rel_diff <= 0.01f);
    }

    /*
     * 8. Continuity at the knee (|f(k+eps) - f(k-eps)| small)
     */
    for (size_t i = 0; i < sizeof(k_pairs) / sizeof(k_pairs[0]); i++) {
        for (size_t m = 0; m < sizeof(k_modes) / sizeof(k_modes[0]); m++) {
            maclc_tone_params p;
            maclc_tone_params_init(&p, k_modes[m], k_pairs[i].content_peak, k_pairs[i].display_peak, 203.0f);

            if (!p.identity && p.knee_pq > 0.0f && p.knee_pq < (p.dst_peak_pq / p.src_peak_pq)) {
                float k_pq = p.knee_pq * p.src_peak_pq;
                float k_nits = maclc_pq_to_nits(k_pq) / p.gain;

                /* Luminance continuity */
                float eps_nits = 0.001f;
                float fn_plus = maclc_tone_map_nits(&p, k_nits + eps_nits);
                float fn_minus = maclc_tone_map_nits(&p, k_nits - eps_nits);
                CHECK(fabsf(fn_plus - fn_minus) < 0.05f);

                /* PQ continuity */
                float eps_pq = 0.00005f;
                float fpq_plus = maclc_tone_map_pq(&p, k_pq + eps_pq);
                float fpq_minus = maclc_tone_map_pq(&p, k_pq - eps_pq);
                CHECK(fabsf(fpq_plus - fpq_minus) < 0.001f);
            }
        }
    }

    /*
     * 9. Sweep 0..10000 nits for BRIGHT on (1000,1600) and (600,1600)
     */
    {
        static const struct test_pair bright_sweep_pairs[] = {
            { 1000.0f, 1600.0f },
            {  600.0f, 1600.0f }
        };
        for (size_t i = 0; i < sizeof(bright_sweep_pairs) / sizeof(bright_sweep_pairs[0]); i++) {
            maclc_tone_params p;
            maclc_tone_params_init(&p, MACLC_TONE_BRIGHT,
                                   bright_sweep_pairs[i].content_peak,
                                   bright_sweep_pairs[i].display_peak,
                                   203.0f);
            float prev_nits = -1.0f;
            for (float nits = 0.0f; nits <= 10000.0f; nits += 5.0f) {
                float out = maclc_tone_map_nits(&p, nits);
                CHECK(out >= prev_nits);
                CHECK(out <= p.display_peak);
                prev_nits = out;
            }
            float prev_pq = -1.0f;
            for (float pq = 0.0f; pq <= 1.0f; pq += 0.001f) {
                float out = maclc_tone_map_pq(&p, pq);
                CHECK(out >= prev_pq);
                CHECK(out <= p.dst_peak_pq);
                prev_pq = out;
            }
        }
    }

    /*
     * 10. MacLC's 100 cd/m2 anchor. An XDR panel (potential headroom 16) is a
     * 1,600-nit display; at full brightness (SDR white 600 cd/m2, headroom
     * 1600/600) a 1,000-nit master is mapped into 267 cd/m2 of video, which
     * the panel shows at 1,600 cd/m2.
     */
    {
        CHECK(maclc_hdr_peak_for_headroom(16.0f) == 1600.0f);
        CHECK(maclc_hdr_peak_for_headroom(0.5f) == MACLC_HDR_REFERENCE_WHITE);

        const float display_peak = maclc_hdr_peak_for_headroom(1600.0f / 600.0f);
        CHECK(fabsf(display_peak - 266.67f) < 0.1f);
        CHECK(maclc_hdr_needs_tone_mapping(1000.0f, display_peak));
        CHECK(!maclc_hdr_needs_tone_mapping(1000.0f, maclc_hdr_peak_for_headroom(16.0f)));

        maclc_tone_params bal, bright, acc;
        maclc_tone_params_init(&bal, MACLC_TONE_BALANCED, 1000.0f, display_peak,
                               MACLC_HDR_REFERENCE_WHITE);
        maclc_tone_params_init(&bright, MACLC_TONE_BRIGHT, 1000.0f, display_peak,
                               MACLC_HDR_REFERENCE_WHITE);
        maclc_tone_params_init(&acc, MACLC_TONE_ACCURATE, 1000.0f, display_peak,
                               MACLC_HDR_REFERENCE_WHITE);

        /* Same mid-tone lift as with the BT.2408 anchor: it only depends on
         * the headroom. */
        CHECK(fabsf(bright.gain - 0.55f * 1600.0f / 600.0f) < 0.001f);

        /* Faces and skies below the knee are left alone; highlights fold
         * into the display without ever reaching past it. */
        CHECK(fabsf(maclc_tone_map_nits(&bal, 50.0f) - 50.0f) < 0.05f);
        CHECK(fabsf(maclc_tone_map_nits(&acc, 200.0f) - 200.0f) < 0.05f);
        CHECK(maclc_tone_map_nits(&bright, 100.0f) > maclc_tone_map_nits(&bal, 100.0f));
        CHECK(maclc_tone_map_nits(&bal, 1000.0f) <= display_peak);
        CHECK(maclc_tone_map_nits(&bal, 1000.0f) > 0.95f * display_peak);

        float prev[3] = { -1.0f, -1.0f, -1.0f };
        for (float nits = 0.0f; nits <= 10000.0f; nits += 2.5f) {
            const maclc_tone_params *ps[3] = { &acc, &bal, &bright };
            for (int m = 0; m < 3; m++) {
                float out = maclc_tone_map_nits(ps[m], nits);
                CHECK(out >= prev[m]);
                CHECK(out <= display_peak + 0.01f);
                prev[m] = out;
            }
        }
    }

    printf("maclc_tonemap: all tests passed\n");
    return 0;
}
