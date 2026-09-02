/*****************************************************************************
 * copy_neon.c: ARM64 NEON chroma conversion test suite
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
#include <stdint.h>
#include <stdbool.h>
#include <string.h>
#include <inttypes.h>

#include <vlc_common.h>
#include <vlc_picture.h>
#include "../../../modules/video_chroma/copy.h"

#if !defined(__aarch64__)

int main(void)
{
    printf("ARM64 NEON not supported on this architecture, skipping test.\n");
    return 0;
}

#else

/* Guard byte values and buffer initialization constants */
#define GUARD_SIZE 64
#define GUARD_HEAD_VAL 0x5A
#define GUARD_TAIL_VAL 0xA5
#define DST_INIT_VAL   0xCD

/* PRNG state for deterministic, reproducible pseudo-random numbers */
static uint64_t prng_state = 0xDEADBEEFCAFE1234ULL;

static inline uint32_t prng_next32(void)
{
    prng_state ^= prng_state >> 12;
    prng_state ^= prng_state << 25;
    prng_state ^= prng_state >> 27;
    return (uint32_t)((prng_state * 0x2545F4914F6CDD1DULL) >> 32);
}

static void prng_seed(uint64_t seed)
{
    prng_state = seed ? seed : 0xDEADBEEFCAFE1234ULL;
}

static void fill_random(uint8_t *buf, size_t size)
{
    size_t i = 0;
    for (; i + 3 < size; i += 4)
    {
        uint32_t r = prng_next32();
        buf[i + 0] = (uint8_t)(r & 0xFF);
        buf[i + 1] = (uint8_t)((r >> 8) & 0xFF);
        buf[i + 2] = (uint8_t)((r >> 16) & 0xFF);
        buf[i + 3] = (uint8_t)((r >> 24) & 0xFF);
    }
    for (; i < size; i++)
        buf[i] = (uint8_t)(prng_next32() & 0xFF);
}

/* Guarded buffer structure */
typedef struct {
    uint8_t *raw_alloc;
    uint8_t *data;
    size_t data_size;
} guarded_buf_t;

static guarded_buf_t alloc_guarded(size_t data_size, size_t unalign_offset)
{
    guarded_buf_t gb;
    gb.data_size = data_size;
    size_t total_size = GUARD_SIZE + data_size + GUARD_SIZE + 128;
    gb.raw_alloc = malloc(total_size);
    assert(gb.raw_alloc != NULL);

    uintptr_t p = (uintptr_t)(gb.raw_alloc + GUARD_SIZE);
    uintptr_t aligned_p = (p + 63) & ~63;
    gb.data = (uint8_t *)(aligned_p + unalign_offset);

    memset(gb.data - GUARD_SIZE, GUARD_HEAD_VAL, GUARD_SIZE);
    memset(gb.data + data_size, GUARD_TAIL_VAL, GUARD_SIZE);

    return gb;
}

static void free_guarded(guarded_buf_t *gb)
{
    if (gb && gb->raw_alloc)
    {
        free(gb->raw_alloc);
        gb->raw_alloc = NULL;
        gb->data = NULL;
        gb->data_size = 0;
    }
}

static bool check_guard(const guarded_buf_t *gb, const char *plane_name, char *violation_msg, size_t msg_max)
{
    const uint8_t *head = gb->data - GUARD_SIZE;
    for (size_t i = 0; i < GUARD_SIZE; i++)
    {
        if (head[i] != GUARD_HEAD_VAL)
        {
            snprintf(violation_msg, msg_max, "%s head guard corrupted at offset -%zu (got 0x%02X expected 0x%02X)",
                     plane_name, GUARD_SIZE - i, head[i], GUARD_HEAD_VAL);
            return false;
        }
    }
    const uint8_t *tail = gb->data + gb->data_size;
    for (size_t i = 0; i < GUARD_SIZE; i++)
    {
        if (tail[i] != GUARD_TAIL_VAL)
        {
            snprintf(violation_msg, msg_max, "%s tail guard corrupted at offset +%zu (got 0x%02X expected 0x%02X)",
                     plane_name, i, tail[i], GUARD_TAIL_VAL);
            return false;
        }
    }
    return true;
}

/* ========================================================================= */
/* INDEPENDENT REFERENCE IMPLEMENTATIONS DERIVED FROM FORMAT SPECIFICATIONS  */
/* ========================================================================= */

static inline uint16_t ref_apply_shift16(uint16_t val, int bitshift)
{
    if (bitshift == 0)
        return val;
    if (bitshift > 0)
        return (uint16_t)(val >> (bitshift & 0xf));
    return (uint16_t)((val << ((-bitshift) & 0xf)) & 0xFFFF);
}

static void ref_Copy420_SP_to_P(picture_t *dst,
                                const uint8_t *src[2],
                                const size_t src_pitch[2],
                                unsigned height)
{
    size_t copy_pitch_y = dst->p[0].i_pitch < (int)src_pitch[0] ? (size_t)dst->p[0].i_pitch : src_pitch[0];
    for (unsigned y = 0; y < height; y++)
    {
        const uint8_t *s = src[0] + y * src_pitch[0];
        uint8_t *d = dst->p[0].p_pixels + y * dst->p[0].i_pitch;
        for (size_t x = 0; x < copy_pitch_y; x++)
            d[x] = s[x];
    }

    unsigned chroma_h = (height + 1) / 2;
    size_t max_pairs = src_pitch[1] / 2;
    if ((size_t)dst->p[1].i_pitch < max_pairs)
        max_pairs = (size_t)dst->p[1].i_pitch;
    if ((size_t)dst->p[2].i_pitch < max_pairs)
        max_pairs = (size_t)dst->p[2].i_pitch;

    for (unsigned y = 0; y < chroma_h; y++)
    {
        const uint8_t *s_uv = src[1] + y * src_pitch[1];
        uint8_t *d_u = dst->p[1].p_pixels + y * dst->p[1].i_pitch;
        uint8_t *d_v = dst->p[2].p_pixels + y * dst->p[2].i_pitch;

        for (size_t x = 0; x < max_pairs; x++)
        {
            d_u[x] = s_uv[2 * x + 0];
            d_v[x] = s_uv[2 * x + 1];
        }
    }
}

static void ref_Copy420_P_to_SP(picture_t *dst,
                                const uint8_t *src[3],
                                const size_t src_pitch[3],
                                unsigned height)
{
    size_t copy_pitch_y = dst->p[0].i_pitch < (int)src_pitch[0] ? (size_t)dst->p[0].i_pitch : src_pitch[0];
    for (unsigned y = 0; y < height; y++)
    {
        const uint8_t *s = src[0] + y * src_pitch[0];
        uint8_t *d = dst->p[0].p_pixels + y * dst->p[0].i_pitch;
        for (size_t x = 0; x < copy_pitch_y; x++)
            d[x] = s[x];
    }

    unsigned chroma_h = (height + 1) / 2;
    size_t max_pairs = src_pitch[1] < src_pitch[2] ? src_pitch[1] : src_pitch[2];
    if ((size_t)dst->p[1].i_pitch / 2 < max_pairs)
        max_pairs = (size_t)dst->p[1].i_pitch / 2;

    for (unsigned y = 0; y < chroma_h; y++)
    {
        const uint8_t *s_u = src[1] + y * src_pitch[1];
        const uint8_t *s_v = src[2] + y * src_pitch[2];
        uint8_t *d_uv = dst->p[1].p_pixels + y * dst->p[1].i_pitch;

        for (size_t x = 0; x < max_pairs; x++)
        {
            d_uv[2 * x + 0] = s_u[x];
            d_uv[2 * x + 1] = s_v[x];
        }
    }
}

static void ref_Copy420_16_SP_to_P(picture_t *dst,
                                   const uint8_t *src[2],
                                   const size_t src_pitch[2],
                                   unsigned height,
                                   int bitshift)
{
    size_t copy_bytes_y = dst->p[0].i_pitch < (int)src_pitch[0] ? (size_t)dst->p[0].i_pitch : src_pitch[0];
    if (bitshift == 0)
    {
        for (unsigned y = 0; y < height; y++)
        {
            const uint8_t *s = src[0] + y * src_pitch[0];
            uint8_t *d = dst->p[0].p_pixels + y * dst->p[0].i_pitch;
            for (size_t x = 0; x < copy_bytes_y; x++)
                d[x] = s[x];
        }
    }
    else
    {
        size_t num_samples_y = copy_bytes_y / 2;
        for (unsigned y = 0; y < height; y++)
        {
            const uint16_t *s = (const uint16_t *)(src[0] + y * src_pitch[0]);
            uint16_t *d = (uint16_t *)(dst->p[0].p_pixels + y * dst->p[0].i_pitch);
            for (size_t x = 0; x < num_samples_y; x++)
                d[x] = ref_apply_shift16(s[x], bitshift);
        }
    }

    unsigned chroma_h = (height + 1) / 2;
    size_t max_pairs = src_pitch[1] / 4;
    if ((size_t)dst->p[1].i_pitch / 2 < max_pairs)
        max_pairs = (size_t)dst->p[1].i_pitch / 2;
    if ((size_t)dst->p[2].i_pitch / 2 < max_pairs)
        max_pairs = (size_t)dst->p[2].i_pitch / 2;

    for (unsigned y = 0; y < chroma_h; y++)
    {
        const uint16_t *s_uv = (const uint16_t *)(src[1] + y * src_pitch[1]);
        uint16_t *d_u = (uint16_t *)(dst->p[1].p_pixels + y * dst->p[1].i_pitch);
        uint16_t *d_v = (uint16_t *)(dst->p[2].p_pixels + y * dst->p[2].i_pitch);

        for (size_t x = 0; x < max_pairs; x++)
        {
            d_u[x] = ref_apply_shift16(s_uv[2 * x + 0], bitshift);
            d_v[x] = ref_apply_shift16(s_uv[2 * x + 1], bitshift);
        }
    }
}

static void ref_Copy420_16_P_to_SP(picture_t *dst,
                                   const uint8_t *src[3],
                                   const size_t src_pitch[3],
                                   unsigned height,
                                   int bitshift)
{
    size_t copy_bytes_y = dst->p[0].i_pitch < (int)src_pitch[0] ? (size_t)dst->p[0].i_pitch : src_pitch[0];
    if (bitshift == 0)
    {
        for (unsigned y = 0; y < height; y++)
        {
            const uint8_t *s = src[0] + y * src_pitch[0];
            uint8_t *d = dst->p[0].p_pixels + y * dst->p[0].i_pitch;
            for (size_t x = 0; x < copy_bytes_y; x++)
                d[x] = s[x];
        }
    }
    else
    {
        size_t num_samples_y = copy_bytes_y / 2;
        for (unsigned y = 0; y < height; y++)
        {
            const uint16_t *s = (const uint16_t *)(src[0] + y * src_pitch[0]);
            uint16_t *d = (uint16_t *)(dst->p[0].p_pixels + y * dst->p[0].i_pitch);
            for (size_t x = 0; x < num_samples_y; x++)
                d[x] = ref_apply_shift16(s[x], bitshift);
        }
    }

    unsigned chroma_h = (height + 1) / 2;
    size_t max_pairs = (src_pitch[1] / 2) < (src_pitch[2] / 2) ? (src_pitch[1] / 2) : (src_pitch[2] / 2);
    if ((size_t)dst->p[1].i_pitch / 4 < max_pairs)
        max_pairs = (size_t)dst->p[1].i_pitch / 4;

    for (unsigned y = 0; y < chroma_h; y++)
    {
        const uint16_t *s_u = (const uint16_t *)(src[1] + y * src_pitch[1]);
        const uint16_t *s_v = (const uint16_t *)(src[2] + y * src_pitch[2]);
        uint16_t *d_uv = (uint16_t *)(dst->p[1].p_pixels + y * dst->p[1].i_pitch);

        for (size_t x = 0; x < max_pairs; x++)
        {
            d_uv[2 * x + 0] = ref_apply_shift16(s_u[x], bitshift);
            d_uv[2 * x + 1] = ref_apply_shift16(s_v[x], bitshift);
        }
    }
}

/* ========================================================================= */
/* TEST HARNESS RUNNER                                                       */
/* ========================================================================= */

typedef enum {
    TEST_8_SP_TO_P,
    TEST_8_P_TO_SP,
    TEST_16_SP_TO_P,
    TEST_16_P_TO_SP,
} test_func_kind_t;

static const char *test_func_name(test_func_kind_t k)
{
    switch (k) {
        case TEST_8_SP_TO_P:   return "Copy420_SP_to_P";
        case TEST_8_P_TO_SP:   return "Copy420_P_to_SP";
        case TEST_16_SP_TO_P:  return "Copy420_16_SP_to_P";
        case TEST_16_P_TO_SP:  return "Copy420_16_P_to_SP";
    }
    return "unknown";
}

typedef enum {
    STRIDE_EXACT,
    STRIDE_PAD_64,
    STRIDE_PAD_128,
    STRIDE_ASYMM_SRC_BIG,
    STRIDE_ASYMM_DST_BIG,
    STRIDE_EXTRA_PIXELS,
} stride_mode_t;

static const char *stride_mode_name(stride_mode_t m)
{
    switch (m) {
        case STRIDE_EXACT:          return "exact";
        case STRIDE_PAD_64:         return "pad64";
        case STRIDE_PAD_128:        return "pad128";
        case STRIDE_ASYMM_SRC_BIG:  return "asymm_src_larger";
        case STRIDE_ASYMM_DST_BIG:  return "asymm_dst_larger";
        case STRIDE_EXTRA_PIXELS:   return "extra_pixels";
    }
    return "unknown";
}

static size_t compute_stride(size_t min_bytes, stride_mode_t mode, bool is_src, unsigned bpp)
{
    switch (mode) {
        case STRIDE_EXACT:
            return min_bytes;
        case STRIDE_PAD_64:
            return (min_bytes + 63) & ~63;
        case STRIDE_PAD_128:
            return (min_bytes + 127) & ~127;
        case STRIDE_ASYMM_SRC_BIG:
            return is_src ? ((min_bytes + 127) & ~127) : ((min_bytes + 31) & ~31);
        case STRIDE_ASYMM_DST_BIG:
            return is_src ? ((min_bytes + 31) & ~31) : ((min_bytes + 127) & ~127);
        case STRIDE_EXTRA_PIXELS:
            return min_bytes + (is_src ? 7 * bpp : 13 * bpp);
    }
    return min_bytes;
}

static uint64_t g_total_tests = 0;
static uint64_t g_total_mismatches = 0;
static uint64_t g_total_guard_violations = 0;

static void run_single_test(test_func_kind_t func_kind,
                            unsigned width,
                            unsigned height,
                            stride_mode_t stride_mode,
                            int bitshift,
                            size_t unalign_offset)
{
    g_total_tests++;
    bool is_16bit = (func_kind == TEST_16_SP_TO_P || func_kind == TEST_16_P_TO_SP);
    unsigned bpp = is_16bit ? 2 : 1;
    unsigned chroma_h = (height + 1) / 2;
    unsigned chroma_w = (width + 1) / 2;

    size_t min_src_stride[3] = {0, 0, 0};
    size_t min_dst_stride[3] = {0, 0, 0};
    unsigned src_planes_count = 0;
    unsigned dst_planes_count = 0;

    if (func_kind == TEST_8_SP_TO_P) {
        src_planes_count = 2;
        dst_planes_count = 3;
        min_src_stride[0] = width * 1;
        min_src_stride[1] = chroma_w * 2;
        min_dst_stride[0] = width * 1;
        min_dst_stride[1] = chroma_w * 1;
        min_dst_stride[2] = chroma_w * 1;
    } else if (func_kind == TEST_8_P_TO_SP) {
        src_planes_count = 3;
        dst_planes_count = 2;
        min_src_stride[0] = width * 1;
        min_src_stride[1] = chroma_w * 1;
        min_src_stride[2] = chroma_w * 1;
        min_dst_stride[0] = width * 1;
        min_dst_stride[1] = chroma_w * 2;
    } else if (func_kind == TEST_16_SP_TO_P) {
        src_planes_count = 2;
        dst_planes_count = 3;
        min_src_stride[0] = width * 2;
        min_src_stride[1] = chroma_w * 4;
        min_dst_stride[0] = width * 2;
        min_dst_stride[1] = chroma_w * 2;
        min_dst_stride[2] = chroma_w * 2;
    } else if (func_kind == TEST_16_P_TO_SP) {
        src_planes_count = 3;
        dst_planes_count = 2;
        min_src_stride[0] = width * 2;
        min_src_stride[1] = chroma_w * 2;
        min_src_stride[2] = chroma_w * 2;
        min_dst_stride[0] = width * 2;
        min_dst_stride[1] = chroma_w * 4;
    }

    size_t src_pitches[3] = {0, 0, 0};
    size_t dst_pitches[3] = {0, 0, 0};
    size_t src_lines[3] = {0, 0, 0};
    size_t dst_lines[3] = {0, 0, 0};

    src_lines[0] = height;
    src_pitches[0] = compute_stride(min_src_stride[0], stride_mode, true, bpp);
    for (unsigned i = 1; i < src_planes_count; i++) {
        src_lines[i] = chroma_h;
        src_pitches[i] = compute_stride(min_src_stride[i], stride_mode, true, bpp);
    }

    dst_lines[0] = height;
    dst_pitches[0] = compute_stride(min_dst_stride[0], stride_mode, false, bpp);
    for (unsigned i = 1; i < dst_planes_count; i++) {
        dst_lines[i] = chroma_h;
        dst_pitches[i] = compute_stride(min_dst_stride[i], stride_mode, false, bpp);
    }

    guarded_buf_t src_gb[3];
    guarded_buf_t dst_neon_gb[3];
    guarded_buf_t dst_ref_gb[3];

    for (unsigned i = 0; i < src_planes_count; i++) {
        src_gb[i] = alloc_guarded(src_pitches[i] * src_lines[i], unalign_offset);
        fill_random(src_gb[i].data, src_gb[i].data_size);
    }

    for (unsigned i = 0; i < dst_planes_count; i++) {
        size_t sz = dst_pitches[i] * dst_lines[i];
        dst_neon_gb[i] = alloc_guarded(sz, unalign_offset);
        dst_ref_gb[i] = alloc_guarded(sz, unalign_offset);
        memset(dst_neon_gb[i].data, DST_INIT_VAL, sz);
        memset(dst_ref_gb[i].data, DST_INIT_VAL, sz);
    }

    picture_t pic_neon;
    memset(&pic_neon, 0, sizeof(pic_neon));
    pic_neon.i_planes = dst_planes_count;
    for (unsigned i = 0; i < dst_planes_count; i++) {
        pic_neon.p[i].p_pixels = dst_neon_gb[i].data;
        pic_neon.p[i].i_pitch = (int)dst_pitches[i];
        pic_neon.p[i].i_lines = (int)dst_lines[i];
        pic_neon.p[i].i_visible_lines = (int)dst_lines[i];
        pic_neon.p[i].i_visible_pitch = (int)min_dst_stride[i];
    }

    picture_t pic_ref;
    memset(&pic_ref, 0, sizeof(pic_ref));
    pic_ref.i_planes = dst_planes_count;
    for (unsigned i = 0; i < dst_planes_count; i++) {
        pic_ref.p[i].p_pixels = dst_ref_gb[i].data;
        pic_ref.p[i].i_pitch = (int)dst_pitches[i];
        pic_ref.p[i].i_lines = (int)dst_lines[i];
        pic_ref.p[i].i_visible_lines = (int)dst_lines[i];
        pic_ref.p[i].i_visible_pitch = (int)min_dst_stride[i];
    }

    const uint8_t *src_ptrs[3] = { src_gb[0].data, src_gb[1].data, src_planes_count > 2 ? src_gb[2].data : NULL };

    copy_cache_t cache;
    int ret = CopyInitCache(&cache, width * bpp);
    assert(ret == VLC_SUCCESS);

    switch (func_kind) {
        case TEST_8_SP_TO_P:
            Copy420_SP_to_P(&pic_neon, src_ptrs, src_pitches, height, &cache);
            ref_Copy420_SP_to_P(&pic_ref, src_ptrs, src_pitches, height);
            break;
        case TEST_8_P_TO_SP:
            Copy420_P_to_SP(&pic_neon, src_ptrs, src_pitches, height, &cache);
            ref_Copy420_P_to_SP(&pic_ref, src_ptrs, src_pitches, height);
            break;
        case TEST_16_SP_TO_P:
            Copy420_16_SP_to_P(&pic_neon, src_ptrs, src_pitches, height, bitshift, &cache);
            ref_Copy420_16_SP_to_P(&pic_ref, src_ptrs, src_pitches, height, bitshift);
            break;
        case TEST_16_P_TO_SP:
            Copy420_16_P_to_SP(&pic_neon, src_ptrs, src_pitches, height, bitshift, &cache);
            ref_Copy420_16_P_to_SP(&pic_ref, src_ptrs, src_pitches, height, bitshift);
            break;
    }

    CopyCleanCache(&cache);

    /* 1. Verify guard bytes */
    for (unsigned i = 0; i < dst_planes_count; i++) {
        char msg[256];
        char pname[32];
        snprintf(pname, sizeof(pname), "Plane[%u]", i);
        if (!check_guard(&dst_neon_gb[i], pname, msg, sizeof(msg))) {
            g_total_guard_violations++;
            printf("GUARD VIOLATION: func=%s w=%u h=%u stride=%s shift=%d %s\n",
                   test_func_name(func_kind), width, height, stride_mode_name(stride_mode), bitshift, msg);
        }
    }

    /* 2. Verify bit-exactness against reference */
    for (unsigned i = 0; i < dst_planes_count; i++) {
        size_t total_bytes = dst_pitches[i] * dst_lines[i];
        if (memcmp(dst_neon_gb[i].data, dst_ref_gb[i].data, total_bytes) != 0) {
            g_total_mismatches++;

            if (is_16bit) {
                const uint16_t *act16 = (const uint16_t *)dst_neon_gb[i].data;
                const uint16_t *exp16 = (const uint16_t *)dst_ref_gb[i].data;
                size_t num_words = total_bytes / 2;
                for (size_t w = 0; w < num_words; w++) {
                    if (act16[w] != exp16[w]) {
                        size_t row = w / (dst_pitches[i] / 2);
                        size_t col = w % (dst_pitches[i] / 2);
                        printf("MISMATCH: func=%s w=%u h=%u stride=%s shift=%d plane=%u idx=%zu (row=%zu col=%zu) exp=0x%04X act=0x%04X\n",
                               test_func_name(func_kind), width, height, stride_mode_name(stride_mode), bitshift,
                               i, w, row, col, exp16[w], act16[w]);
                        break;
                    }
                }
            } else {
                const uint8_t *act8 = dst_neon_gb[i].data;
                const uint8_t *exp8 = dst_ref_gb[i].data;
                for (size_t b = 0; b < total_bytes; b++) {
                    if (act8[b] != exp8[b]) {
                        size_t row = b / dst_pitches[i];
                        size_t col = b % dst_pitches[i];
                        printf("MISMATCH: func=%s w=%u h=%u stride=%s shift=%d plane=%u idx=%zu (row=%zu col=%zu) exp=0x%02X act=0x%02X\n",
                               test_func_name(func_kind), width, height, stride_mode_name(stride_mode), bitshift,
                               i, b, row, col, exp8[b], act8[b]);
                        break;
                    }
                }
            }
        }
    }

    for (unsigned i = 0; i < src_planes_count; i++)
        free_guarded(&src_gb[i]);
    for (unsigned i = 0; i < dst_planes_count; i++) {
        free_guarded(&dst_neon_gb[i]);
        free_guarded(&dst_ref_gb[i]);
    }
}

int main(void)
{
    prng_seed(0x12345678ULL);

    printf("=================================================================\n");
    printf("ARM64 NEON Chroma Conversions Verification Suite\n");
    printf("=================================================================\n");

    static const unsigned test_widths[] = {
        16, 17, 31, 32, 33, 63, 65, 1920, 1921
    };
    static const size_t num_widths = sizeof(test_widths) / sizeof(test_widths[0]);

    static const unsigned test_heights[] = {
        2, 16, 1080
    };
    static const size_t num_heights = sizeof(test_heights) / sizeof(test_heights[0]);

    static const stride_mode_t test_strides[] = {
        STRIDE_EXACT,
        STRIDE_PAD_64,
        STRIDE_PAD_128,
        STRIDE_ASYMM_SRC_BIG,
        STRIDE_ASYMM_DST_BIG,
        STRIDE_EXTRA_PIXELS
    };
    static const size_t num_strides = sizeof(test_strides) / sizeof(test_strides[0]);

    static const int bitshifts_16[] = { 0, 6, -6 };
    static const size_t num_bitshifts_16 = sizeof(bitshifts_16) / sizeof(bitshifts_16[0]);

    static const size_t unalign_offsets[] = { 0, 1, 3 };
    static const size_t num_unalign = sizeof(unalign_offsets) / sizeof(unalign_offsets[0]);

    printf("Testing matrix:\n");
    printf("  Widths (%zu): ", num_widths);
    for (size_t i = 0; i < num_widths; i++) printf("%u%s", test_widths[i], i + 1 < num_widths ? ", " : "\n");
    printf("  Heights (%zu): ", num_heights);
    for (size_t i = 0; i < num_heights; i++) printf("%u%s", test_heights[i], i + 1 < num_heights ? ", " : "\n");
    printf("  Stride modes (%zu): exact, pad64, pad128, asymm_src_larger, asymm_dst_larger, extra_pixels\n", num_strides);
    printf("  Bitshifts for 16-bit (%zu): 0, 6, -6\n", num_bitshifts_16);
    printf("  Pointer alignments tested: 64-byte aligned and unaligned offsets (+0, +1, +3 bytes)\n");
    printf("  Functions tested: Copy420_SP_to_P, Copy420_P_to_SP, Copy420_16_SP_to_P, Copy420_16_P_to_SP\n\n");

    /* 1. Test 8-bit public functions */
    printf(">>> Running 8-bit conversions (Copy420_SP_to_P and Copy420_P_to_SP)...\n");
    for (size_t u = 0; u < num_unalign; u++) {
        for (size_t w = 0; w < num_widths; w++) {
            for (size_t h = 0; h < num_heights; h++) {
                for (size_t s = 0; s < num_strides; s++) {
                    run_single_test(TEST_8_SP_TO_P, test_widths[w], test_heights[h], test_strides[s], 0, unalign_offsets[u]);
                    run_single_test(TEST_8_P_TO_SP, test_widths[w], test_heights[h], test_strides[s], 0, unalign_offsets[u]);
                }
            }
        }
    }
    printf(">>> 8-bit tests completed.\n\n");

    /* 2. Test 16-bit public functions */
    printf(">>> Running 16-bit conversions (Copy420_16_SP_to_P and Copy420_16_P_to_SP)...\n");
    for (size_t u = 0; u < num_unalign; u++) {
        for (size_t w = 0; w < num_widths; w++) {
            for (size_t h = 0; h < num_heights; h++) {
                for (size_t s = 0; s < num_strides; s++) {
                    for (size_t bs = 0; bs < num_bitshifts_16; bs++) {
                        run_single_test(TEST_16_SP_TO_P, test_widths[w], test_heights[h], test_strides[s], bitshifts_16[bs], unalign_offsets[u]);
                        run_single_test(TEST_16_P_TO_SP, test_widths[w], test_heights[h], test_strides[s], bitshifts_16[bs], unalign_offsets[u]);
                    }
                }
            }
        }
    }
    printf(">>> 16-bit tests completed.\n\n");

    printf("=================================================================\n");
    printf("SUMMARY:\n");
    printf("  Total test configurations executed: %" PRIu64 "\n", g_total_tests);
    printf("  Total guard byte violations:        %" PRIu64 "\n", g_total_guard_violations);
    printf("  Total mismatching configurations:   %" PRIu64 "\n", g_total_mismatches);
    printf("=================================================================\n");

    if (g_total_mismatches == 0 && g_total_guard_violations == 0) {
        printf("RESULT: PASS\n");
        return 0;
    } else {
        printf("RESULT: FAIL %" PRIu64 " mismatches (guard violations: %" PRIu64 ")\n",
               g_total_mismatches, g_total_guard_violations);
        return 1;
    }
}

#endif /* defined(__aarch64__) */
