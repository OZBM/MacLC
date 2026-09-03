/*****************************************************************************
 * cvpx_hdr_metadata.c: CoreVideo HDR colour metadata roundtrip test
 *****************************************************************************
 * Copyright (C) 2024 VLC authors and VideoLAN
 *
 * This program is free software; you can redistribute it and/or modify it
 * under the terms of the GNU Lesser General Public License as published
 * by the Free Software Foundation; either version 2.1 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin Street, Fifth Floor, Boston MA 02110-1301, USA.
 *****************************************************************************/

#ifdef HAVE_CONFIG_H
# include <config.h>
#endif

#undef NDEBUG
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdbool.h>
#include <string.h>

#include <CoreVideo/CoreVideo.h>
#include <vlc_common.h>
#include <vlc_es.h>
#include <vlc_picture.h>

#include "../../../modules/codec/vt_utils.h"

static void test_cvpx_hdr_pq(void)
{
    printf("Testing CVPixelBuffer HDR metadata round-trip (PQ / ST 2084)...\n");

    CVPixelBufferRef cvpx = NULL;
    CVReturn err = CVPixelBufferCreate(kCFAllocatorDefault, 64, 64,
                                       kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange,
                                       NULL, &cvpx);
    assert(err == kCVReturnSuccess && cvpx != NULL);

    video_format_t fmt;
    video_format_Init(&fmt, VLC_CODEC_P010);
    fmt.i_width = fmt.i_visible_width = 3840;
    fmt.i_height = fmt.i_visible_height = 2160;
    fmt.space = COLOR_SPACE_BT2020;
    fmt.primaries = COLOR_PRIMARIES_BT2020;
    fmt.transfer = TRANSFER_FUNC_SMPTE_ST2084;

    /* SMPTE ST 2086 mastering display color volume */
    fmt.mastering.primaries[0] = 13250; /* G.x */
    fmt.mastering.primaries[1] = 34500; /* G.y */
    fmt.mastering.primaries[2] = 7500;  /* B.x */
    fmt.mastering.primaries[3] = 3000;  /* B.y */
    fmt.mastering.primaries[4] = 34000; /* R.x */
    fmt.mastering.primaries[5] = 16000; /* R.y */
    fmt.mastering.white_point[0] = 15635; /* D65.x */
    fmt.mastering.white_point[1] = 16450; /* D65.y */
    fmt.mastering.max_luminance = 10000000; /* 1000 nits (in 0.0001 nit units) */
    fmt.mastering.min_luminance = 50;       /* 0.0050 nits (in 0.0001 nit units) */

    /* CTA-861.3 content light level */
    fmt.lighting.MaxCLL = 1000;  /* 1000 nits */
    fmt.lighting.MaxFALL = 400;  /* 400 nits */

    /* Attach properties and HDR metadata */
    cvpx_attach_mapped_color_properties(cvpx, &fmt);

    /* Extract properties into a fresh video_format_t */
    video_format_t extracted;
    video_format_Init(&extracted, 0);
    cvpx_extract_color_properties(cvpx, &extracted);

    /* Assert exact round-trip */
    assert(extracted.space == COLOR_SPACE_BT2020);
    assert(extracted.primaries == COLOR_PRIMARIES_BT2020);
    assert(extracted.transfer == TRANSFER_FUNC_SMPTE_ST2084);

    for (size_t i = 0; i < 6; i++)
        assert(extracted.mastering.primaries[i] == fmt.mastering.primaries[i]);
    assert(extracted.mastering.white_point[0] == fmt.mastering.white_point[0]);
    assert(extracted.mastering.white_point[1] == fmt.mastering.white_point[1]);
    assert(extracted.mastering.max_luminance == fmt.mastering.max_luminance);
    assert(extracted.mastering.min_luminance == fmt.mastering.min_luminance);

    assert(extracted.lighting.MaxCLL == fmt.lighting.MaxCLL);
    assert(extracted.lighting.MaxFALL == fmt.lighting.MaxFALL);

    CFRelease(cvpx);
    printf("  -> PQ round-trip PASSED\n");
}

static void test_cvpx_hdr_hlg(void)
{
    printf("Testing CVPixelBuffer HDR metadata round-trip (HLG / BT.2100)...\n");

    CVPixelBufferRef cvpx = NULL;
    CVReturn err = CVPixelBufferCreate(kCFAllocatorDefault, 64, 64,
                                       kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange,
                                       NULL, &cvpx);
    assert(err == kCVReturnSuccess && cvpx != NULL);

    video_format_t fmt;
    video_format_Init(&fmt, VLC_CODEC_P010);
    fmt.i_width = fmt.i_visible_width = 3840;
    fmt.i_height = fmt.i_visible_height = 2160;
    fmt.space = COLOR_SPACE_BT2020;
    fmt.primaries = COLOR_PRIMARIES_BT2020;
    fmt.transfer = TRANSFER_FUNC_HLG;

    /* SMPTE ST 2086 mastering display color volume */
    fmt.mastering.primaries[0] = 13250;
    fmt.mastering.primaries[1] = 34500;
    fmt.mastering.primaries[2] = 7500;
    fmt.mastering.primaries[3] = 3000;
    fmt.mastering.primaries[4] = 34000;
    fmt.mastering.primaries[5] = 16000;
    fmt.mastering.white_point[0] = 15635;
    fmt.mastering.white_point[1] = 16450;
    fmt.mastering.max_luminance = 10000000;
    fmt.mastering.min_luminance = 50;

    /* CTA-861.3 content light level */
    fmt.lighting.MaxCLL = 1000;
    fmt.lighting.MaxFALL = 400;

    /* Attach properties and HDR metadata */
    cvpx_attach_mapped_color_properties(cvpx, &fmt);

    /* Extract properties into a fresh video_format_t */
    video_format_t extracted;
    video_format_Init(&extracted, 0);
    cvpx_extract_color_properties(cvpx, &extracted);

    /* Assert exact round-trip */
    assert(extracted.space == COLOR_SPACE_BT2020);
    assert(extracted.primaries == COLOR_PRIMARIES_BT2020);
    assert(extracted.transfer == TRANSFER_FUNC_HLG);

    for (size_t i = 0; i < 6; i++)
        assert(extracted.mastering.primaries[i] == fmt.mastering.primaries[i]);
    assert(extracted.mastering.white_point[0] == fmt.mastering.white_point[0]);
    assert(extracted.mastering.white_point[1] == fmt.mastering.white_point[1]);
    assert(extracted.mastering.max_luminance == fmt.mastering.max_luminance);
    assert(extracted.mastering.min_luminance == fmt.mastering.min_luminance);

    assert(extracted.lighting.MaxCLL == fmt.lighting.MaxCLL);
    assert(extracted.lighting.MaxFALL == fmt.lighting.MaxFALL);

    CFRelease(cvpx);
    printf("  -> HLG round-trip PASSED\n");
}

static void test_cvpx_hdr_negative(void)
{
    printf("Testing CVPixelBuffer HDR negative cases (unattached / SDR buffers)...\n");

    /* Case 1: Unattached clean buffer */
    CVPixelBufferRef cvpx_clean = NULL;
    CVReturn err = CVPixelBufferCreate(kCFAllocatorDefault, 64, 64,
                                       kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange,
                                       NULL, &cvpx_clean);
    assert(err == kCVReturnSuccess && cvpx_clean != NULL);

    video_format_t extracted_clean;
    video_format_Init(&extracted_clean, 0);
    cvpx_extract_color_properties(cvpx_clean, &extracted_clean);

    assert(extracted_clean.space == COLOR_SPACE_UNDEF);
    assert(extracted_clean.primaries == COLOR_PRIMARIES_UNDEF);
    assert(extracted_clean.transfer == TRANSFER_FUNC_UNDEF);
    for (size_t i = 0; i < 6; i++)
        assert(extracted_clean.mastering.primaries[i] == 0);
    assert(extracted_clean.mastering.white_point[0] == 0);
    assert(extracted_clean.mastering.white_point[1] == 0);
    assert(extracted_clean.mastering.max_luminance == 0);
    assert(extracted_clean.mastering.min_luminance == 0);
    assert(extracted_clean.lighting.MaxCLL == 0);
    assert(extracted_clean.lighting.MaxFALL == 0);

    CFRelease(cvpx_clean);

    /* Case 2: SDR BT.709 buffer with no HDR mastering/lighting */
    CVPixelBufferRef cvpx_sdr = NULL;
    err = CVPixelBufferCreate(kCFAllocatorDefault, 64, 64,
                              kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
                              NULL, &cvpx_sdr);
    assert(err == kCVReturnSuccess && cvpx_sdr != NULL);

    video_format_t fmt_sdr;
    video_format_Init(&fmt_sdr, VLC_CODEC_NV12);
    fmt_sdr.space = COLOR_SPACE_BT709;
    fmt_sdr.primaries = COLOR_PRIMARIES_BT709;
    fmt_sdr.transfer = TRANSFER_FUNC_BT709;

    cvpx_attach_mapped_color_properties(cvpx_sdr, &fmt_sdr);

    video_format_t extracted_sdr;
    video_format_Init(&extracted_sdr, 0);
    cvpx_extract_color_properties(cvpx_sdr, &extracted_sdr);

    assert(extracted_sdr.space == COLOR_SPACE_BT709);
    assert(extracted_sdr.primaries == COLOR_PRIMARIES_BT709);
    assert(extracted_sdr.transfer == TRANSFER_FUNC_BT709);
    for (size_t i = 0; i < 6; i++)
        assert(extracted_sdr.mastering.primaries[i] == 0);
    assert(extracted_sdr.mastering.white_point[0] == 0);
    assert(extracted_sdr.mastering.white_point[1] == 0);
    assert(extracted_sdr.mastering.max_luminance == 0);
    assert(extracted_sdr.mastering.min_luminance == 0);
    assert(extracted_sdr.lighting.MaxCLL == 0);
    assert(extracted_sdr.lighting.MaxFALL == 0);

    CFRelease(cvpx_sdr);

    printf("  -> Negative cases PASSED\n");
}

static void test_cvpx_hdr_hlg_bare(void)
{
    printf("Testing CVPixelBuffer HLG without mastering metadata (no synthesis)...\n");

    CVPixelBufferRef cvpx = NULL;
    CVReturn err = CVPixelBufferCreate(kCFAllocatorDefault, 64, 64,
                                       kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange,
                                       NULL, &cvpx);
    assert(err == kCVReturnSuccess && cvpx != NULL);

    /* A broadcast HLG stream is scene-referred: it carries no ST 2086
     * mastering display volume and no CTA-861.3 content light level. VLC must
     * not invent either of them, because the compositor would then tone map
     * against a mastering volume the stream never declared. */
    video_format_t fmt;
    video_format_Init(&fmt, VLC_CODEC_P010);
    fmt.i_width = fmt.i_visible_width = 3840;
    fmt.i_height = fmt.i_visible_height = 2160;
    fmt.space = COLOR_SPACE_BT2020;
    fmt.primaries = COLOR_PRIMARIES_BT2020;
    fmt.transfer = TRANSFER_FUNC_HLG;

    cvpx_attach_mapped_color_properties(cvpx, &fmt);

    video_format_t extracted;
    video_format_Init(&extracted, 0);
    cvpx_extract_color_properties(cvpx, &extracted);

    /* The colorimetry itself must still be tagged. */
    assert(extracted.space == COLOR_SPACE_BT2020);
    assert(extracted.primaries == COLOR_PRIMARIES_BT2020);
    assert(extracted.transfer == TRANSFER_FUNC_HLG);

    /* Nothing must have been synthesised. */
    for (size_t i = 0; i < 6; i++)
        assert(extracted.mastering.primaries[i] == 0);
    assert(extracted.mastering.white_point[0] == 0);
    assert(extracted.mastering.white_point[1] == 0);
    assert(extracted.mastering.max_luminance == 0);
    assert(extracted.mastering.min_luminance == 0);
    assert(extracted.lighting.MaxCLL == 0);
    assert(extracted.lighting.MaxFALL == 0);

    CFRelease(cvpx);
    printf("  -> Bare HLG PASSED\n");
}

static void test_cvpx_hdr_low_luminance(void)
{
    printf("Testing CVPixelBuffer PQ mastering luminance below 1 nit...\n");

    CVPixelBufferRef cvpx = NULL;
    CVReturn err = CVPixelBufferCreate(kCFAllocatorDefault, 64, 64,
                                       kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange,
                                       NULL, &cvpx);
    assert(err == kCVReturnSuccess && cvpx != NULL);

    video_format_t fmt;
    video_format_Init(&fmt, VLC_CODEC_P010);
    fmt.space = COLOR_SPACE_BT2020;
    fmt.primaries = COLOR_PRIMARIES_BT2020;
    fmt.transfer = TRANSFER_FUNC_SMPTE_ST2084;

    fmt.mastering.primaries[0] = 13250;
    fmt.mastering.primaries[1] = 34500;
    fmt.mastering.primaries[2] = 7500;
    fmt.mastering.primaries[3] = 3000;
    fmt.mastering.primaries[4] = 34000;
    fmt.mastering.primaries[5] = 16000;
    fmt.mastering.white_point[0] = 15635;
    fmt.mastering.white_point[1] = 16450;

    /* 0.5 cd/m^2 peak, expressed in the 0.0001 cd/m^2 units VLC and CoreVideo
     * both use. A value below 10000 must survive untouched: rescaling it would
     * turn a 0.5 nit mastering target into a 5000 nit one. */
    fmt.mastering.max_luminance = 5000;
    fmt.mastering.min_luminance = 1;

    cvpx_attach_mapped_color_properties(cvpx, &fmt);

    video_format_t extracted;
    video_format_Init(&extracted, 0);
    cvpx_extract_color_properties(cvpx, &extracted);

    assert(extracted.mastering.max_luminance == 5000);
    assert(extracted.mastering.min_luminance == 1);

    CFRelease(cvpx);
    printf("  -> Low mastering luminance PASSED\n");
}

int main(void)
{
    test_cvpx_hdr_pq();
    test_cvpx_hdr_hlg();
    test_cvpx_hdr_negative();
    test_cvpx_hdr_hlg_bare();
    test_cvpx_hdr_low_luminance();

    printf("All CoreVideo HDR metadata tests PASSED!\n");
    return 0;
}
