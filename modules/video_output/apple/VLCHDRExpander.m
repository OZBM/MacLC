/*****************************************************************************
 * VLCHDRExpander.m: GPU dynamic-range expansion (SDR -> HDR) for Apple
 * platforms
 *****************************************************************************
 * Copyright (C) 2026 VLC authors and VideoLAN
 *
 * This program is free software; you can redistribute it and/or modify it
 * under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation; either version 2.1 of the License, or
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
# include "config.h"
#endif

#import "VLCHDRExpander.h"

#import <Metal/Metal.h>
#import <IOSurface/IOSurface.h>
#include <math.h>
#include <vlc_tick.h>

/* kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange */
#define VLC_CVPX_FORMAT_P010 ((OSType)'x420')
/* kCVPixelFormatType_64RGBAHalf */
#define VLC_CVPX_FORMAT_RGBA_HALF ((OSType)'RGhA')

/* CoreVideo's 10-bit bi-planar formats are P010-style: the ten bits sit at the
 * top of a 16-bit word. Reading such a plane as a normalised 16-bit texture
 * therefore yields code/65472 rather than code/1023. */
#define VLC_HDR_10BIT_READ_SCALE (65535.0f / 65472.0f)

enum vlc_hdr_expander_matrix
{
    VLC_HDR_MATRIX_BT709 = 0,
    VLC_HDR_MATRIX_BT601 = 1,
    VLC_HDR_MATRIX_BT2020 = 2,
};

enum vlc_hdr_expander_transfer
{
    VLC_HDR_TRANSFER_POWER = 0,      /* pow(v, gamma) */
    VLC_HDR_TRANSFER_BT709_OETF = 1, /* inverse of the BT.709 OETF */
};

/* Must stay byte-for-byte identical to the Metal struct of the same name. */
typedef struct
{
    float gamut[12];       /* three float4 rows, only .xyz is read (48 bytes) */
    float inputScale;
    float gamma;
    float lumaOffset;
    float lumaScale;
    float chromaOffset;
    float chromaScale;
    uint32_t matrix;
    uint32_t transferMode;
    uint32_t width;
    uint32_t height;
    float P_rel;
    float W;
    float ceiling;
    float dt;
    float saturation;
    uint32_t reset;
    uint32_t quality;      /* 1: FAST, 2: BALANCED, 3: HIGH, 4: MAXIMUM */
    uint32_t deband;       /* 0: OFF, 1: NORMAL, 2: STRONG */
    uint32_t protect;      /* 0: OFF, 1: ON */
    uint32_t frameIndex;
    uint32_t cellWidth;
    uint32_t cellHeight;
    int32_t  guidedRadius;
    float    guidedEps;
    float    debandRadius;
    float    debandThreshold;
    uint32_t debandN;
    float    kr;
    float    kb;
    uint32_t gridWidth;
    uint32_t gridHeight;
    uint32_t gridDepth;
    uint32_t gridReset;    /* the grid texture holds nothing usable yet */
    uint32_t protectReset; /* the protect history holds nothing usable yet */
    uint32_t pad[2];       /* keeps the size a multiple of 16, like Metal's */
} VLCHDRExpandUniforms;

_Static_assert(sizeof(VLCHDRExpandUniforms) == 192,
               "the uniform block must keep the layout the Metal struct has");

typedef struct
{
    float A_prev;
    float Lg_prev;
    float A_f;
    float Lg_f;
    float budget;
    float M_f;
    uint32_t frames;
    uint32_t cut;
} VLCHDRExpandState;

_Static_assert(sizeof(VLCHDRExpandState) == 32,
               "the state block must keep the layout the Metal struct has");

/* Linear RGB -> linear BT.2020 RGB, derived from the CIE chromaticities of each
 * set of primaries against a D65 white point. */
static const float kGamutBT709ToBT2020[9] = {
     0.627404f,  0.329283f,  0.043313f,
     0.069097f,  0.919540f,  0.011362f,
     0.016391f,  0.088013f,  0.895595f,
};

static const float kGamutP3D65ToBT2020[9] = {
     0.753833f,  0.198597f,  0.047570f,
     0.045744f,  0.941777f,  0.012479f,
    -0.001210f,  0.017602f,  0.983609f,
};

static const float kGamutSMPTE170ToBT2020[9] = {
     0.595254f,  0.349314f,  0.055432f,
     0.081244f,  0.891503f,  0.027253f,
     0.015512f,  0.081912f,  0.902576f,
};

static const float kGamutEBU3213ToBT2020[9] = {
     0.655037f,  0.302161f,  0.042802f,
     0.072141f,  0.916631f,  0.011228f,
     0.017113f,  0.097853f,  0.885033f,
};

static const float kGamutIdentity[9] = {
     1.0f, 0.0f, 0.0f,
     0.0f, 1.0f, 0.0f,
     0.0f, 0.0f, 1.0f,
};

/*
 * Metal shader source string.
 */
static NSString * const kVLCHDRExpanderShaderSource =
    @"#include <metal_stdlib>\n"
    @"using namespace metal;\n"
    @"\n"
    @"struct VLCHDRExpandUniforms {\n"
    @"    float4 gamut[3];\n"
    @"    float  inputScale;\n"
    @"    float  gamma;\n"
    @"    float  lumaOffset;\n"
    @"    float  lumaScale;\n"
    @"    float  chromaOffset;\n"
    @"    float  chromaScale;\n"
    @"    uint   matrix;\n"
    @"    uint   transferMode;\n"
    @"    uint   width;\n"
    @"    uint   height;\n"
    @"    float  P_rel;\n"
    @"    float  W;\n"
    @"    float  ceiling;\n"
    @"    float  dt;\n"
    @"    float  saturation;\n"
    @"    uint   reset;\n"
    @"    uint   quality;\n"
    @"    uint   deband;\n"
    @"    uint   protect;\n"
    @"    uint   frameIndex;\n"
    @"    uint   cellWidth;\n"
    @"    uint   cellHeight;\n"
    @"    int    guidedRadius;\n"
    @"    float  guidedEps;\n"
    @"    float  debandRadius;\n"
    @"    float  debandThreshold;\n"
    @"    uint   debandN;\n"
    @"    float  kr;\n"
    @"    float  kb;\n"
    @"    uint   gridWidth;\n"
    @"    uint   gridHeight;\n"
    @"    uint   gridDepth;\n"
    @"    uint   gridReset;\n"
    @"    uint   protectReset;\n"
    @"    uint   pad1, pad2;\n"
    @"};\n"
    @"\n"
    @"struct VLCHDRExpandState {\n"
    @"    float A_prev;\n"
    @"    float Lg_prev;\n"
    @"    float A_f;\n"
    @"    float Lg_f;\n"
    @"    float budget;\n"
    @"    float M_f;\n"
    @"    uint  frames;\n"
    @"    uint  cut;\n"
    @"};\n"
    @"\n"
    @"static inline float3 ycbcr_to_rgb(float3 ycc, constant VLCHDRExpandUniforms &u)\n"
    @"{\n"
    @"    float y  = (ycc.x - u.lumaOffset) * u.lumaScale;\n"
    @"    float cb = (ycc.y - u.chromaOffset) * u.chromaScale;\n"
    @"    float cr = (ycc.z - u.chromaOffset) * u.chromaScale;\n"
    @"\n"
    @"    float kr = u.kr, kb = u.kb;\n"
    @"    float kg = 1.0f - kr - kb;\n"
    @"\n"
    @"    float r = y + 2.0f * (1.0f - kr) * cr;\n"
    @"    float b = y + 2.0f * (1.0f - kb) * cb;\n"
    @"    float g = (y - kr * r - kb * b) / kg;\n"
    @"    return float3(r, g, b);\n"
    @"}\n"
    @"\n"
    @"static inline float eotf_channel(float v, constant VLCHDRExpandUniforms &u)\n"
    @"{\n"
    @"    float a = fabs(v);\n"
    @"    float s = (v < 0.0f) ? -1.0f : 1.0f;\n"
    @"    if (u.transferMode == 1u)\n"
    @"        return s * ((a < 0.081f) ? (a / 4.5f)\n"
    @"                                 : pow((a + 0.099f) / 1.099f, 1.0f / 0.45f));\n"
    @"    return s * pow(a, u.gamma);\n"
    @"}\n"
    @"\n"
    @"static inline float maclc_sdr2hdr_drive(float r, float g, float b, float kr, float kb)\n"
    @"{\n"
    @"    float y = kr * r + (1.0f - kr - kb) * g + kb * b;\n"
    @"    float m = max(max(r, g), b);\n"
    @"    return max(y, 0.85f * m);\n"
    @"}\n"
    @"\n"
    @"static inline float maclc_sdr2hdr_highlight_weight(float d)\n"
    @"{\n"
    @"    return smoothstep(0.8134f, 0.97f, d);\n"
    @"}\n"
    @"\n"
    @"static inline float maclc_sdr2hdr_fast_curve(float d, float knee, float peak)\n"
    @"{\n"
    @"    if (peak <= 1.0f || d <= knee || d <= 0.0f)\n"
    @"        return d;\n"
    @"    float span = max(1.0f - knee, 1e-4f);\n"
    @"    if (d <= 1.0f) {\n"
    @"        float t = (d - knee) / span;\n"
    @"        return d + (peak - 1.0f) * t * t;\n"
    @"    }\n"
    @"    return peak + (d - 1.0f) * (1.0f + 2.0f * (peak - 1.0f) / span);\n"
    @"}\n"
    @"\n"
    @"static inline float maclc_sdr2hdr_area_factor(float area)\n"
    @"{\n"
    @"    return 1.0f - 0.7f * smoothstep(0.02f, 0.30f, area);\n"
    @"}\n"
    @"\n"
    @"static inline float maclc_sdr2hdr_budget(float peak_rel, float area)\n"
    @"{\n"
    @"    if (peak_rel <= 1.0f)\n"
    @"        return 1.0f;\n"
    @"    return 1.0f + (peak_rel - 1.0f) * maclc_sdr2hdr_area_factor(area);\n"
    @"}\n"
    @"\n"
    @"static inline float maclc_sdr2hdr_balanced_log_gain(float u, float budget)\n"
    @"{\n"
    @"    if (budget <= 1.0f)\n"
    @"        return 0.0f;\n"
    @"    const float u0 = log(0.8134f);\n"
    @"    float s = smoothstep(u0, 0.0f, u);\n"
    @"    return log(budget) * s;\n"
    @"}\n"
    @"\n"
    @"static inline float maclc_sdr2hdr_rolloff(float x, float ceiling)\n"
    @"{\n"
    @"    if (ceiling <= 1.0f)\n"
    @"        return x;\n"
    @"    float k = 0.8f * ceiling;\n"
    @"    if (x <= k)\n"
    @"        return x;\n"
    @"    float span = max(ceiling - k, 1e-4f);\n"
    @"    return k + span * (1.0f - exp(-(x - k) / span));\n"
    @"}\n"
    @"\n"
    @"static inline uint pcg_hash(uint input)\n"
    @"{\n"
    @"    uint state = input * 747796405u + 2891336453u;\n"
    @"    uint word = ((state >> ((state >> 28u) + 4u)) ^ state) * 277803737u;\n"
    @"    return (word >> 22u) ^ word;\n"
    @"}\n"
    @"\n"
    @"static inline float hash1(uint2 p, uint frameIndex, uint iter)\n"
    @"{\n"
    @"    uint h = pcg_hash(p.x + pcg_hash(p.y + pcg_hash(frameIndex * 17u + iter * 101u)));\n"
    @"    return float(h & 0x00FFFFFFu) / 16777216.0f;\n"
    @"}\n"
    @"\n"
    @"static inline float hash2(uint2 p, uint frameIndex, uint iter)\n"
    @"{\n"
    @"    uint h = pcg_hash((p.y ^ 0x5bf03635u) + pcg_hash(p.x + pcg_hash(frameIndex * 31u + iter * 223u)));\n"
    @"    return float(h & 0x00FFFFFFu) / 16777216.0f;\n"
    @"}\n"
    @"\n"
    @"static inline float3 sample_nonlinear_biplanar(\n"
    @"    float2 coord,\n"
    @"    texture2d<float, access::sample> inLuma,\n"
    @"    texture2d<float, access::sample> inChroma,\n"
    @"    constant VLCHDRExpandUniforms &u,\n"
    @"    sampler bilinear)\n"
    @"{\n"
    @"    float2 norm_luma = (coord + 0.5f) / float2(u.width, u.height);\n"
    @"    float y = inLuma.sample(bilinear, norm_luma).r * u.inputScale;\n"
    @"    float2 norm_chroma = float2((coord.x * 0.5f + 0.5f) / float(inChroma.get_width()),\n"
    @"                                (coord.y * 0.5f + 0.25f) / float(inChroma.get_height()));\n"
    @"    float2 cc = inChroma.sample(bilinear, norm_chroma).rg * u.inputScale;\n"
    @"    return ycbcr_to_rgb(float3(y, cc.x, cc.y), u);\n"
    @"}\n"
    @"\n"
    @"static inline float3 sample_nonlinear_rgba(\n"
    @"    float2 coord,\n"
    @"    texture2d<float, access::sample> inRGBA,\n"
    @"    constant VLCHDRExpandUniforms &u,\n"
    @"    sampler bilinear)\n"
    @"{\n"
    @"    float2 norm = (coord + 0.5f) / float2(u.width, u.height);\n"
    @"    return inRGBA.sample(bilinear, norm).rgb;\n"
    @"}\n"
    @"\n"
    @"/* Fast expansion kernels (single pass) */\n"
    @"kernel void vlc_hdr_expand_fast_biplanar(\n"
    @"    texture2d<float, access::sample> inLuma   [[texture(0)]],\n"
    @"    texture2d<float, access::sample> inChroma [[texture(1)]],\n"
    @"    texture2d<float, access::write>  outRGBA  [[texture(2)]],\n"
    @"    constant VLCHDRExpandUniforms&   u        [[buffer(0)]],\n"
    @"    uint2 gid [[thread_position_in_grid]])\n"
    @"{\n"
    @"    if (gid.x >= u.width || gid.y >= u.height)\n"
    @"        return;\n"
    @"\n"
    @"    constexpr sampler bilinear(coord::normalized, address::clamp_to_edge, filter::linear);\n"
    @"    float y = inLuma.read(gid).r * u.inputScale;\n"
    @"    float2 pos = float2((float(gid.x) * 0.5f + 0.5f) / float(inChroma.get_width()),\n"
    @"                        (float(gid.y) * 0.5f + 0.25f) / float(inChroma.get_height()));\n"
    @"    float2 cc = inChroma.sample(bilinear, pos).rg * u.inputScale;\n"
    @"    float3 nonLinear = ycbcr_to_rgb(float3(y, cc.x, cc.y), u);\n"
    @"    float3 rgb = float3(eotf_channel(nonLinear.r, u),\n"
    @"                        eotf_channel(nonLinear.g, u),\n"
    @"                        eotf_channel(nonLinear.b, u));\n"
    @"\n"
    @"    float d = maclc_sdr2hdr_drive(rgb.r, rgb.g, rgb.b, u.kr, u.kb);\n"
    @"    float e = maclc_sdr2hdr_fast_curve(d, 0.5f, u.P_rel);\n"
    @"    float g = (d > 0.0f) ? (e / d) : 1.0f;\n"
    @"    float3 out = rgb * g;\n"
    @"\n"
    @"    float w = clamp(log(max(g, 1e-6f)) / log(max(u.P_rel, 1.0001f)), 0.0f, 1.0f);\n"
    @"    float Yo = u.kr * out.r + (1.0f - u.kr - u.kb) * out.g + u.kb * out.b;\n"
    @"    float k_sat = 1.0f + (u.saturation - 1.0f) * w;\n"
    @"    out = max(Yo + (out - Yo) * k_sat, 0.0f);\n"
    @"    out *= u.W;\n"
    @"\n"
    @"    float m = max(max(out.r, out.g), out.b);\n"
    @"    if (m > 0.0f)\n"
    @"        out *= maclc_sdr2hdr_rolloff(m, u.ceiling) / m;\n"
    @"\n"
    @"    float3 wide = float3(dot(u.gamut[0].xyz, out),\n"
    @"                         dot(u.gamut[1].xyz, out),\n"
    @"                         dot(u.gamut[2].xyz, out));\n"
    @"    outRGBA.write(float4(max(wide, 0.0f), 1.0f), gid);\n"
    @"}\n"
    @"\n"
    @"kernel void vlc_hdr_expand_fast_rgba(\n"
    @"    texture2d<float, access::sample> inRGBA   [[texture(0)]],\n"
    @"    texture2d<float, access::write>  outRGBA  [[texture(1)]],\n"
    @"    constant VLCHDRExpandUniforms&   u        [[buffer(0)]],\n"
    @"    uint2 gid [[thread_position_in_grid]])\n"
    @"{\n"
    @"    if (gid.x >= u.width || gid.y >= u.height)\n"
    @"        return;\n"
    @"\n"
    @"    float3 nonLinear = inRGBA.read(gid).rgb;\n"
    @"    float3 rgb = float3(eotf_channel(nonLinear.r, u),\n"
    @"                        eotf_channel(nonLinear.g, u),\n"
    @"                        eotf_channel(nonLinear.b, u));\n"
    @"\n"
    @"    float d = maclc_sdr2hdr_drive(rgb.r, rgb.g, rgb.b, u.kr, u.kb);\n"
    @"    float e = maclc_sdr2hdr_fast_curve(d, 0.5f, u.P_rel);\n"
    @"    float g = (d > 0.0f) ? (e / d) : 1.0f;\n"
    @"    float3 out = rgb * g;\n"
    @"\n"
    @"    float w = clamp(log(max(g, 1e-6f)) / log(max(u.P_rel, 1.0001f)), 0.0f, 1.0f);\n"
    @"    float Yo = u.kr * out.r + (1.0f - u.kr - u.kb) * out.g + u.kb * out.b;\n"
    @"    float k_sat = 1.0f + (u.saturation - 1.0f) * w;\n"
    @"    out = max(Yo + (out - Yo) * k_sat, 0.0f);\n"
    @"    out *= u.W;\n"
    @"\n"
    @"    float m = max(max(out.r, out.g), out.b);\n"
    @"    if (m > 0.0f)\n"
    @"        out *= maclc_sdr2hdr_rolloff(m, u.ceiling) / m;\n"
    @"\n"
    @"    float3 wide = float3(dot(u.gamut[0].xyz, out),\n"
    @"                         dot(u.gamut[1].xyz, out),\n"
    @"                         dot(u.gamut[2].xyz, out));\n"
    @"    outRGBA.write(float4(max(wide, 0.0f), 1.0f), gid);\n"
    @"}\n"
    @"\n"
    @"/* Analysis pass (8x8 cells) */\n"
    @"kernel void sdr2hdr_analyze_biplanar(\n"
    @"    texture2d<float, access::sample> inLuma   [[texture(0)]],\n"
    @"    texture2d<float, access::sample> inChroma [[texture(1)]],\n"
    @"    texture2d<float, access::write>  statsA   [[texture(2)]],\n"
    @"    texture2d<float, access::write>  statsB   [[texture(3)]],\n"
    @"    constant VLCHDRExpandUniforms&   u        [[buffer(0)]],\n"
    @"    uint2 gid [[thread_position_in_grid]])\n"
    @"{\n"
    @"    if (gid.x >= u.cellWidth || gid.y >= u.cellHeight)\n"
    @"        return;\n"
    @"\n"
    @"    constexpr sampler bilinear(coord::normalized, address::clamp_to_edge, filter::linear);\n"
    @"    float sum_I = 0.0f, sum_II = 0.0f, sum_h = 0.0f, sum_Y = 0.0f;\n"
    @"    float max_d = 0.0f, min_d = 1e6f;\n"
    @"    uint count = 0u;\n"
    @"\n"
    @"    for (uint cy = 0u; cy < 8u; cy++) {\n"
    @"        uint y = gid.y * 8u + cy;\n"
    @"        if (y >= u.height) break;\n"
    @"        for (uint cx = 0u; cx < 8u; cx++) {\n"
    @"            uint x = gid.x * 8u + cx;\n"
    @"            if (x >= u.width) break;\n"
    @"\n"
    @"            float y_val = inLuma.read(uint2(x, y)).r * u.inputScale;\n"
    @"            float2 pos = float2((float(x) * 0.5f + 0.5f) / float(inChroma.get_width()),\n"
    @"                                (float(y) * 0.5f + 0.25f) / float(inChroma.get_height()));\n"
    @"            float2 cc = inChroma.sample(bilinear, pos).rg * u.inputScale;\n"
    @"            float3 nonLinear = ycbcr_to_rgb(float3(y_val, cc.x, cc.y), u);\n"
    @"            float3 rgb = float3(eotf_channel(nonLinear.r, u),\n"
    @"                                eotf_channel(nonLinear.g, u),\n"
    @"                                eotf_channel(nonLinear.b, u));\n"
    @"\n"
    @"            float Y = u.kr * rgb.r + (1.0f - u.kr - u.kb) * rgb.g + u.kb * rgb.b;\n"
    @"            float d = maclc_sdr2hdr_drive(rgb.r, rgb.g, rgb.b, u.kr, u.kb);\n"
    @"            float I = log(max(d, 1.0f / 4096.0f));\n"
    @"            float h = maclc_sdr2hdr_highlight_weight(d);\n"
    @"\n"
    @"            sum_I += I;\n"
    @"            sum_II += I * I;\n"
    @"            sum_h += h;\n"
    @"            sum_Y += Y;\n"
    @"            max_d = max(max_d, d);\n"
    @"            min_d = min(min_d, d);\n"
    @"            count++;\n"
    @"        }\n"
    @"    }\n"
    @"\n"
    @"    float fCount = max(float(count), 1.0f);\n"
    @"    statsA.write(float4(sum_I / fCount, sum_II / fCount, sum_h / fCount, max_d), gid);\n"
    @"    statsB.write(float4(sum_Y / fCount, max(max_d - min_d, 0.0f), 0.0f, 0.0f), gid);\n"
    @"}\n"
    @"\n"
    @"kernel void sdr2hdr_analyze_rgba(\n"
    @"    texture2d<float, access::sample> inRGBA   [[texture(0)]],\n"
    @"    texture2d<float, access::write>  statsA   [[texture(1)]],\n"
    @"    texture2d<float, access::write>  statsB   [[texture(2)]],\n"
    @"    constant VLCHDRExpandUniforms&   u        [[buffer(0)]],\n"
    @"    uint2 gid [[thread_position_in_grid]])\n"
    @"{\n"
    @"    if (gid.x >= u.cellWidth || gid.y >= u.cellHeight)\n"
    @"        return;\n"
    @"\n"
    @"    float sum_I = 0.0f, sum_II = 0.0f, sum_h = 0.0f, sum_Y = 0.0f;\n"
    @"    float max_d = 0.0f, min_d = 1e6f;\n"
    @"    uint count = 0u;\n"
    @"\n"
    @"    for (uint cy = 0u; cy < 8u; cy++) {\n"
    @"        uint y = gid.y * 8u + cy;\n"
    @"        if (y >= u.height) break;\n"
    @"        for (uint cx = 0u; cx < 8u; cx++) {\n"
    @"            uint x = gid.x * 8u + cx;\n"
    @"            if (x >= u.width) break;\n"
    @"\n"
    @"            float3 nonLinear = inRGBA.read(uint2(x, y)).rgb;\n"
    @"            float3 rgb = float3(eotf_channel(nonLinear.r, u),\n"
    @"                                eotf_channel(nonLinear.g, u),\n"
    @"                                eotf_channel(nonLinear.b, u));\n"
    @"\n"
    @"            float Y = u.kr * rgb.r + (1.0f - u.kr - u.kb) * rgb.g + u.kb * rgb.b;\n"
    @"            float d = maclc_sdr2hdr_drive(rgb.r, rgb.g, rgb.b, u.kr, u.kb);\n"
    @"            float I = log(max(d, 1.0f / 4096.0f));\n"
    @"            float h = maclc_sdr2hdr_highlight_weight(d);\n"
    @"\n"
    @"            sum_I += I;\n"
    @"            sum_II += I * I;\n"
    @"            sum_h += h;\n"
    @"            sum_Y += Y;\n"
    @"            max_d = max(max_d, d);\n"
    @"            min_d = min(min_d, d);\n"
    @"            count++;\n"
    @"        }\n"
    @"    }\n"
    @"\n"
    @"    float fCount = max(float(count), 1.0f);\n"
    @"    statsA.write(float4(sum_I / fCount, sum_II / fCount, sum_h / fCount, max_d), gid);\n"
    @"    statsB.write(float4(sum_Y / fCount, max(max_d - min_d, 0.0f), 0.0f, 0.0f), gid);\n"
    @"}\n"
    @"\n"
    @"/* Frame state reduction */\n"
    @"kernel void sdr2hdr_frame_state(\n"
    @"    texture2d<float, access::read> statsA    [[texture(0)]],\n"
    @"    texture2d<float, access::read> statsB    [[texture(1)]],\n"
    @"    texture2d<float, access::read> prevYTex  [[texture(2)]],\n"
    @"    device VLCHDRExpandState      *state     [[buffer(0)]],\n"
    @"    constant VLCHDRExpandUniforms &u         [[buffer(1)]],\n"
    @"    uint tid                                 [[thread_index_in_threadgroup]],\n"
    @"    uint tgSize                              [[threads_per_threadgroup]])\n"
    @"{\n"
    @"    threadgroup float shared_h[1024];\n"
    @"    threadgroup float shared_I[1024];\n"
    @"    threadgroup float shared_c[1024];\n"
    @"\n"
    @"    uint numCells = u.cellWidth * u.cellHeight;\n"
    @"    float sum_h = 0.0f, sum_I = 0.0f, sum_c = 0.0f;\n"
    @"\n"
    @"    for (uint idx = tid; idx < numCells; idx += tgSize) {\n"
    @"        uint cx = idx % u.cellWidth;\n"
    @"        uint cy = idx / u.cellWidth;\n"
    @"        float4 sA = statsA.read(uint2(cx, cy));\n"
    @"        sum_I += sA.x;\n"
    @"        sum_h += sA.z;\n"
    @"        if (u.protect != 0u && u.reset == 0u && u.protectReset == 0u && state->frames > 0u) {\n"
    @"            float meanY = statsB.read(uint2(cx, cy)).x;\n"
    @"            float prevY = prevYTex.read(uint2(cx, cy)).x;\n"
    @"            sum_c += abs(meanY - prevY);\n"
    @"        }\n"
    @"    }\n"
    @"\n"
    @"    shared_h[tid] = sum_h;\n"
    @"    shared_I[tid] = sum_I;\n"
    @"    shared_c[tid] = sum_c;\n"
    @"    threadgroup_barrier(mem_flags::mem_threadgroup);\n"
    @"\n"
    @"    // tgSize is a power of two (see the dispatch)\n"
    @"    for (uint s = tgSize >> 1u; s > 0u; s >>= 1u) {\n"
    @"        if (tid < s) {\n"
    @"            shared_h[tid] += shared_h[tid + s];\n"
    @"            shared_I[tid] += shared_I[tid + s];\n"
    @"            shared_c[tid] += shared_c[tid + s];\n"
    @"        }\n"
    @"        threadgroup_barrier(mem_flags::mem_threadgroup);\n"
    @"    }\n"
    @"\n"
    @"    if (tid == 0u) {\n"
    @"        float fNumCells = max(float(numCells), 1.0f);\n"
    @"        float A = shared_h[0] / fNumCells;\n"
    @"        float Lg = shared_I[0] / fNumCells;\n"
    @"        float M = shared_c[0] / fNumCells;\n"
    @"\n"
    @"        bool cut = (u.reset != 0u) || (state->frames == 0u) ||\n"
    @"                   (abs(Lg - state->Lg_prev) > 0.7f) ||\n"
    @"                   (abs(A - state->A_prev) > 0.15f);\n"
    @"\n"
    @"        float A_f = state->A_f;\n"
    @"        float Lg_f = state->Lg_f;\n"
    @"        float M_f = state->M_f;\n"
    @"\n"
    @"        if (cut) {\n"
    @"            A_f = A;\n"
    @"            Lg_f = Lg;\n"
    @"            M_f = M;\n"
    @"        } else {\n"
    @"            float a = 1.0f - exp(-u.dt / 0.5f);\n"
    @"            A_f += a * (A - A_f);\n"
    @"            Lg_f += a * (Lg - Lg_f);\n"
    @"            M_f += a * (M - M_f);\n"
    @"        }\n"
    @"\n"
    @"        float budget = maclc_sdr2hdr_budget(u.P_rel, A_f);\n"
    @"\n"
    @"        state->A_prev = A;\n"
    @"        state->Lg_prev = Lg;\n"
    @"        state->A_f = A_f;\n"
    @"        state->Lg_f = Lg_f;\n"
    @"        state->M_f = M_f;\n"
    @"        state->budget = budget;\n"
    @"        state->cut = cut ? 1u : 0u;\n"
    @"        state->frames++;\n"
    @"    }\n"
    @"}\n"
    @"\n"
    @"/* Guided filter box filters */\n"
    @"kernel void sdr2hdr_box_h(\n"
    @"    texture2d<float, access::read>  inTex  [[texture(0)]],\n"
    @"    texture2d<float, access::write> outTex [[texture(1)]],\n"
    @"    constant VLCHDRExpandUniforms   &u     [[buffer(0)]],\n"
    @"    uint2 gid [[thread_position_in_grid]])\n"
    @"{\n"
    @"    if (gid.x >= u.cellWidth || gid.y >= u.cellHeight)\n"
    @"        return;\n"
    @"\n"
    @"    int r = u.guidedRadius;\n"
    @"    int x0 = max(0, int(gid.x) - r);\n"
    @"    int x1 = min(int(u.cellWidth) - 1, int(gid.x) + r);\n"
    @"    float2 sum = float2(0.0f);\n"
    @"    for (int x = x0; x <= x1; x++) {\n"
    @"        sum += inTex.read(uint2(x, gid.y)).xy;\n"
    @"    }\n"
    @"    outTex.write(float4(sum / float(x1 - x0 + 1), 0.0f, 0.0f), gid);\n"
    @"}\n"
    @"\n"
    @"kernel void sdr2hdr_box_v_compute_ab(\n"
    @"    texture2d<float, access::read>  inTex  [[texture(0)]],\n"
    @"    texture2d<float, access::write> outTex [[texture(1)]],\n"
    @"    constant VLCHDRExpandUniforms   &u     [[buffer(0)]],\n"
    @"    uint2 gid [[thread_position_in_grid]])\n"
    @"{\n"
    @"    if (gid.x >= u.cellWidth || gid.y >= u.cellHeight)\n"
    @"        return;\n"
    @"\n"
    @"    int r = u.guidedRadius;\n"
    @"    int y0 = max(0, int(gid.y) - r);\n"
    @"    int y1 = min(int(u.cellHeight) - 1, int(gid.y) + r);\n"
    @"    float2 sum = float2(0.0f);\n"
    @"    for (int y = y0; y <= y1; y++) {\n"
    @"        sum += inTex.read(uint2(gid.x, y)).xy;\n"
    @"    }\n"
    @"    float2 m = sum / float(y1 - y0 + 1);\n"
    @"    float mI = m.x, mII = m.y;\n"
    @"    float var = max(mII - mI * mI, 0.0f);\n"
    @"    float a = var / (var + u.guidedEps);\n"
    @"    float b = (1.0f - a) * mI;\n"
    @"    outTex.write(float4(a, b, 0.0f, 0.0f), gid);\n"
    @"}\n"
    @"\n"
    @"kernel void sdr2hdr_box_v_ab(\n"
    @"    texture2d<float, access::read>  inTex  [[texture(0)]],\n"
    @"    texture2d<float, access::write> outTex [[texture(1)]],\n"
    @"    constant VLCHDRExpandUniforms   &u     [[buffer(0)]],\n"
    @"    uint2 gid [[thread_position_in_grid]])\n"
    @"{\n"
    @"    if (gid.x >= u.cellWidth || gid.y >= u.cellHeight)\n"
    @"        return;\n"
    @"\n"
    @"    int r = u.guidedRadius;\n"
    @"    int y0 = max(0, int(gid.y) - r);\n"
    @"    int y1 = min(int(u.cellHeight) - 1, int(gid.y) + r);\n"
    @"    float2 sum = float2(0.0f);\n"
    @"    for (int y = y0; y <= y1; y++) {\n"
    @"        sum += inTex.read(uint2(gid.x, y)).xy;\n"
    @"    }\n"
    @"    outTex.write(float4(sum / float(y1 - y0 + 1), 0.0f, 0.0f), gid);\n"
    @"}\n"
    @"\n"
    @"/* Protect subtitles and logos */\n"
    @"kernel void sdr2hdr_protect(\n"
    @"    texture2d<float, access::read>  statsA      [[texture(0)]],\n"
    @"    texture2d<float, access::read>  statsB      [[texture(1)]],\n"
    @"    texture2d<float, access::read>  prevYIn     [[texture(2)]],\n"
    @"    texture2d<float, access::read>  stillIn     [[texture(3)]],\n"
    @"    texture2d<float, access::read>  persistIn   [[texture(4)]],\n"
    @"    texture2d<float, access::write> prevYOut    [[texture(5)]],\n"
    @"    texture2d<float, access::write> stillOut    [[texture(6)]],\n"
    @"    texture2d<float, access::write> persistOut  [[texture(7)]],\n"
    @"    texture2d<float, access::write> protectRaw  [[texture(8)]],\n"
    @"    device VLCHDRExpandState       *state       [[buffer(0)]],\n"
    @"    constant VLCHDRExpandUniforms  &u           [[buffer(1)]],\n"
    @"    uint2 gid [[thread_position_in_grid]])\n"
    @"{\n"
    @"    if (gid.x >= u.cellWidth || gid.y >= u.cellHeight)\n"
    @"        return;\n"
    @"\n"
    @"    float maxd = statsA.read(gid).w;\n"
    @"    float meanY = statsB.read(gid).x;\n"
    @"    float contrast = statsB.read(gid).y;\n"
    @"\n"
    @"    /* No history yet (first frame, or protection just turned on). */\n"
    @"    bool fresh = u.reset != 0u || u.protectReset != 0u;\n"
    @"    float prevY = fresh ? meanY : prevYIn.read(gid).r;\n"
    @"    float still = fresh ? 0.0f : stillIn.read(gid).r;\n"
    @"    float persist = fresh ? 0.0f : persistIn.read(gid).r;\n"
    @"\n"
    @"    float c = abs(meanY - prevY);\n"
    @"    still = mix(still, c, 1.0f - exp(-u.dt / 0.5f));\n"
    @"    prevY = meanY;\n"
    @"\n"
    @"    float M_f = state->M_f;\n"
    @"    bool raw = (maxd >= 0.85f) && (contrast >= 0.45f) && (M_f > 0.002f) && (still < 0.2f * M_f);\n"
    @"    persist = clamp(persist + (raw ? (u.dt / 0.4f) : (-u.dt / 0.3f)), 0.0f, 1.0f);\n"
    @"    float p_raw = smoothstep(0.3f, 0.9f, persist);\n"
    @"\n"
    @"    prevYOut.write(float4(prevY, 0.0f, 0.0f, 0.0f), gid);\n"
    @"    stillOut.write(float4(still, 0.0f, 0.0f, 0.0f), gid);\n"
    @"    persistOut.write(float4(persist, 0.0f, 0.0f, 0.0f), gid);\n"
    @"    protectRaw.write(float4(p_raw, 0.0f, 0.0f, 0.0f), gid);\n"
    @"}\n"
    @"\n"
    @"kernel void sdr2hdr_protect_dilate(\n"
    @"    texture2d<float, access::read>  protectRaw  [[texture(0)]],\n"
    @"    texture2d<float, access::write> protectMask [[texture(1)]],\n"
    @"    constant VLCHDRExpandUniforms   &u          [[buffer(0)]],\n"
    @"    uint2 gid [[thread_position_in_grid]])\n"
    @"{\n"
    @"    if (gid.x >= u.cellWidth || gid.y >= u.cellHeight)\n"
    @"        return;\n"
    @"\n"
    @"    float max_v = 0.0f;\n"
    @"    for (int dy = -1; dy <= 1; dy++) {\n"
    @"        int y = clamp(int(gid.y) + dy, 0, int(u.cellHeight) - 1);\n"
    @"        for (int dx = -1; dx <= 1; dx++) {\n"
    @"            int x = clamp(int(gid.x) + dx, 0, int(u.cellWidth) - 1);\n"
    @"            max_v = max(max_v, protectRaw.read(uint2(x, y)).r);\n"
    @"        }\n"
    @"    }\n"
    @"    protectMask.write(float4(max_v, 0.0f, 0.0f, 0.0f), gid);\n"
    @"}\n"
    @"\n"
    @"/* Thumbnail generation for High/Maximum */\n"
    @"kernel void sdr2hdr_thumbnail_biplanar(\n"
    @"    texture2d<float, access::sample> inLuma    [[texture(0)]],\n"
    @"    texture2d<float, access::sample> inChroma  [[texture(1)]],\n"
    @"    texture2d<float, access::write>  thumbnail [[texture(2)]],\n"
    @"    constant VLCHDRExpandUniforms    &u         [[buffer(0)]],\n"
    @"    uint2 gid [[thread_position_in_grid]])\n"
    @"{\n"
    @"    uint thumbW = thumbnail.get_width();\n"
    @"    uint thumbH = thumbnail.get_height();\n"
    @"    if (gid.x >= thumbW || gid.y >= thumbH)\n"
    @"        return;\n"
    @"\n"
    @"    uint x_start = (gid.x * u.width) / thumbW;\n"
    @"    uint x_end   = ((gid.x + 1u) * u.width) / thumbW;\n"
    @"    uint y_start = (gid.y * u.height) / thumbH;\n"
    @"    uint y_end   = ((gid.y + 1u) * u.height) / thumbH;\n"
    @"\n"
    @"    if (x_end <= x_start) x_end = min(x_start + 1u, u.width);\n"
    @"    if (y_end <= y_start) y_end = min(y_start + 1u, u.height);\n"
    @"\n"
    @"    constexpr sampler bilinear(coord::normalized, address::clamp_to_edge, filter::linear);\n"
    @"    float3 sum = float3(0.0f);\n"
    @"    uint count = 0u;\n"
    @"\n"
    @"    for (uint y = y_start; y < y_end; y++) {\n"
    @"        for (uint x = x_start; x < x_end; x++) {\n"
    @"            float y_val = inLuma.read(uint2(x, y)).r * u.inputScale;\n"
    @"            float2 pos = float2((float(x) * 0.5f + 0.5f) / float(inChroma.get_width()),\n"
    @"                                (float(y) * 0.5f + 0.25f) / float(inChroma.get_height()));\n"
    @"            float2 cc = inChroma.sample(bilinear, pos).rg * u.inputScale;\n"
    @"            sum += ycbcr_to_rgb(float3(y_val, cc.x, cc.y), u);\n"
    @"            count++;\n"
    @"        }\n"
    @"    }\n"
    @"    float3 avg = sum / max(float(count), 1.0f);\n"
    @"    thumbnail.write(float4(avg, 1.0f), gid);\n"
    @"}\n"
    @"\n"
    @"kernel void sdr2hdr_thumbnail_rgba(\n"
    @"    texture2d<float, access::sample> inRGBA    [[texture(0)]],\n"
    @"    texture2d<float, access::write>  thumbnail [[texture(1)]],\n"
    @"    constant VLCHDRExpandUniforms    &u         [[buffer(0)]],\n"
    @"    uint2 gid [[thread_position_in_grid]])\n"
    @"{\n"
    @"    uint thumbW = thumbnail.get_width();\n"
    @"    uint thumbH = thumbnail.get_height();\n"
    @"    if (gid.x >= thumbW || gid.y >= thumbH)\n"
    @"        return;\n"
    @"\n"
    @"    uint x_start = (gid.x * u.width) / thumbW;\n"
    @"    uint x_end   = ((gid.x + 1u) * u.width) / thumbW;\n"
    @"    uint y_start = (gid.y * u.height) / thumbH;\n"
    @"    uint y_end   = ((gid.y + 1u) * u.height) / thumbH;\n"
    @"\n"
    @"    if (x_end <= x_start) x_end = min(x_start + 1u, u.width);\n"
    @"    if (y_end <= y_start) y_end = min(y_start + 1u, u.height);\n"
    @"\n"
    @"    float3 sum = float3(0.0f);\n"
    @"    uint count = 0u;\n"
    @"\n"
    @"    for (uint y = y_start; y < y_end; y++) {\n"
    @"        for (uint x = x_start; x < x_end; x++) {\n"
    @"            sum += inRGBA.read(uint2(x, y)).rgb;\n"
    @"            count++;\n"
    @"        }\n"
    @"    }\n"
    @"    float3 avg = sum / max(float(count), 1.0f);\n"
    @"    thumbnail.write(float4(avg, 1.0f), gid);\n"
    @"}\n"
    @"\n"
    @"/* Analytic grid generator (stand-in for test environment) */\n"
    @"kernel void sdr2hdr_analytic_grid(\n"
    @"    device half *grid [[buffer(0)]],\n"
    @"    uint3 gid [[thread_position_in_grid]])\n"
    @"{\n"
    @"    if (gid.x >= 16u || gid.y >= 16u || gid.z >= 8u)\n"
    @"        return;\n"
    @"\n"
    @"    float min_log = -3.0f;\n"
    @"    float max_log = 0.0f;\n"
    @"    float u_k = min_log + (float(gid.z) + 0.5f) * (max_log - min_log) / 8.0f;\n"
    @"    float u0 = log(0.8134f);\n"
    @"    float t = clamp((u_k - u0) / (0.0f - u0), 0.0f, 1.0f);\n"
    @"    half val = half(t * t * (3.0f - 2.0f * t));\n"
    @"\n"
    @"    uint idx = gid.y * (16u * 8u * 3u) + gid.x * (8u * 3u) + gid.z * 3u;\n"
    @"    grid[idx + 0u] = val;\n"
    @"    grid[idx + 1u] = val;\n"
    @"    grid[idx + 2u] = val;\n"
    @"}\n"
    @"\n"
    @"/* Grid EMA kernel */\n"
    @"kernel void sdr2hdr_grid_ema(\n"
    @"    device const half             *gridRaw [[buffer(0)]],\n"
    @"    texture3d<float, access::read>  gridIn  [[texture(0)]],\n"
    @"    texture3d<float, access::write> gridOut [[texture(1)]],\n"
    @"    device VLCHDRExpandState       *state   [[buffer(1)]],\n"
    @"    constant VLCHDRExpandUniforms  &u       [[buffer(2)]],\n"
    @"    uint3 gid [[thread_position_in_grid]])\n"
    @"{\n"
    @"    if (gid.x >= u.gridWidth || gid.y >= u.gridHeight || gid.z >= u.gridDepth)\n"
    @"        return;\n"
    @"\n"
    @"    bool fresh = u.reset != 0u || u.gridReset != 0u;\n"
    @"    float a = (fresh || state->cut != 0u) ? 1.0f : (1.0f - exp(-u.dt / 0.25f));\n"
    @"    uint idx = gid.y * (u.gridWidth * u.gridDepth * 3u) + gid.x * (u.gridDepth * 3u) + gid.z * 3u;\n"
    @"    float3 raw = float3(float(gridRaw[idx + 0u]), float(gridRaw[idx + 1u]), float(gridRaw[idx + 2u]));\n"
    @"    float3 prev = fresh ? raw : gridIn.read(gid).rgb;\n"
    @"    float3 blended = mix(prev, raw, a);\n"
    @"    gridOut.write(float4(blended, 1.0f), gid);\n"
    @"}\n"
    @"\n"
    @"/* Apply pass (Balanced, High, Maximum) */\n"
    @"kernel void sdr2hdr_apply_biplanar(\n"
    @"    texture2d<float, access::sample> inLuma      [[texture(0)]],\n"
    @"    texture2d<float, access::sample> inChroma    [[texture(1)]],\n"
    @"    texture2d<float, access::write>  outRGBA     [[texture(2)]],\n"
    @"    texture2d<float, access::sample> guidedAB    [[texture(3)]],\n"
    @"    texture2d<float, access::sample> protectMask [[texture(4)]],\n"
    @"    texture3d<float, access::sample> gridTexture [[texture(5)]],\n"
    @"    constant VLCHDRExpandUniforms    &u          [[buffer(0)]],\n"
    @"    device const VLCHDRExpandState   *state      [[buffer(1)]],\n"
    @"    uint2 gid [[thread_position_in_grid]])\n"
    @"{\n"
    @"    if (gid.x >= u.width || gid.y >= u.height)\n"
    @"        return;\n"
    @"\n"
    @"    constexpr sampler bilinear(coord::normalized, address::clamp_to_edge, filter::linear);\n"
    @"    constexpr sampler trilinear(coord::normalized, address::clamp_to_edge, filter::linear, mip_filter::none);\n"
    @"\n"
    @"    float y_raw = inLuma.read(gid).r * u.inputScale;\n"
    @"    float2 pos = float2((float(gid.x) * 0.5f + 0.5f) / float(inChroma.get_width()),\n"
    @"                        (float(gid.y) * 0.5f + 0.25f) / float(inChroma.get_height()));\n"
    @"    float2 cc = inChroma.sample(bilinear, pos).rg * u.inputScale;\n"
    @"    float3 nonLinear = ycbcr_to_rgb(float3(y_raw, cc.x, cc.y), u);\n"
    @"\n"
    @"    float3 rgb = float3(eotf_channel(nonLinear.r, u),\n"
    @"                        eotf_channel(nonLinear.g, u),\n"
    @"                        eotf_channel(nonLinear.b, u));\n"
    @"\n"
    @"    float d = maclc_sdr2hdr_drive(rgb.r, rgb.g, rgb.b, u.kr, u.kb);\n"
    @"    float I = log(max(d, 1.0f / 4096.0f));\n"
    @"\n"
    @"    float2 uv = float2((float(gid.x) + 0.5f) / (8.0f * float(u.cellWidth)),\n"
    @"                       (float(gid.y) + 0.5f) / (8.0f * float(u.cellHeight)));\n"
    @"    float2 ab = guidedAB.sample(bilinear, uv).rg;\n"
    @"    float u_val = ab.x * I + ab.y;\n"
    @"\n"
    @"    float budget = state->budget;\n"
    @"    float3 lg_c;\n"
    @"    float lg_max;\n"
    @"\n"
    @"    if (u.quality == 3u || u.quality == 4u) {\n"
    @"        float z = (clamp(u_val, -3.0f, 0.0f) - (-3.0f)) / 3.0f;\n"
    @"        float3 sampledGrid = gridTexture.sample(trilinear, float3((float(gid.x) + 0.5f) / float(u.width),\n"
    @"                                                                 (float(gid.y) + 0.5f) / float(u.height),\n"
    @"                                                                 z)).rgb;\n"
    @"        lg_c = sampledGrid * log(max(budget, 10.0f)); /* MACLC_SDR2HDR_P_TRAIN */\n"
    @"        /* MACLC_SDR2HDR_HUE_SPREAD around the luminance-weighted gain */\n"
    @"        float3 kw = float3(u.kr, 1.0f - u.kr - u.kb, u.kb) * rgb;\n"
    @"        float lg_y = dot(lg_c, kw) / max(kw.r + kw.g + kw.b, 1e-6f);\n"
    @"        lg_c = lg_y + clamp(lg_c - lg_y, -0.2f, 0.2f);\n"
    @"        if (u.protect != 0u) {\n"
    @"            float pm = protectMask.sample(bilinear, uv).r;\n"
    @"            lg_c *= (1.0f - pm);\n"
    @"        }\n"
    @"        lg_max = max(max(lg_c.r, lg_c.g), lg_c.b);\n"
    @"    } else {\n"
    @"        float lg = maclc_sdr2hdr_balanced_log_gain(u_val, budget);\n"
    @"        if (u.protect != 0u) {\n"
    @"            float pm = protectMask.sample(bilinear, uv).r;\n"
    @"            lg *= (1.0f - pm);\n"
    @"        }\n"
    @"        lg_c = float3(lg);\n"
    @"        lg_max = lg;\n"
    @"    }\n"
    @"\n"
    @"    if (u.deband != 0u && lg_max > log(1.05f)) {\n"
    @"        float3 ref = nonLinear;\n"
    @"        for (uint i = 1u; i <= u.debandN; i++) {\n"
    @"            float h1 = hash1(gid, u.frameIndex, i);\n"
    @"            float h2 = hash2(gid, u.frameIndex, i);\n"
    @"            float angle = 2.0f * M_PI_F * h1;\n"
    @"            float dist = u.debandRadius * float(i) * h2;\n"
    @"            float2 o = dist * float2(cos(angle), sin(angle));\n"
    @"            float2 o2 = float2(-o.y, o.x);\n"
    @"            float2 p = float2(gid);\n"
    @"            float3 s1 = sample_nonlinear_biplanar(p + o, inLuma, inChroma, u, bilinear);\n"
    @"            float3 s2 = sample_nonlinear_biplanar(p - o, inLuma, inChroma, u, bilinear);\n"
    @"            float3 s3 = sample_nonlinear_biplanar(p + o2, inLuma, inChroma, u, bilinear);\n"
    @"            float3 s4 = sample_nonlinear_biplanar(p - o2, inLuma, inChroma, u, bilinear);\n"
    @"            float3 avg = 0.25f * (s1 + s2 + s3 + s4);\n"
    @"            float th = u.debandThreshold / float(i);\n"
    @"            if (all(abs(avg - ref) < th)) {\n"
    @"                ref = avg;\n"
    @"            }\n"
    @"        }\n"
    @"        rgb = float3(eotf_channel(ref.r, u),\n"
    @"                     eotf_channel(ref.g, u),\n"
    @"                     eotf_channel(ref.b, u));\n"
    @"    }\n"
    @"\n"
    @"    float3 out = rgb * exp(lg_c);\n"
    @"    if (u.quality == 3u || u.quality == 4u) {\n"
    @"        /* Learned gains are absolute (maclc_sdr2hdr_grid_log_scale()):\n"
    @"         * roll them off under the budget, never below the SDR pixel. */\n"
    @"        float mx = max(max(out.r, out.g), out.b);\n"
    @"        float m0 = max(max(rgb.r, rgb.g), rgb.b);\n"
    @"        if (budget <= 1.0001f)\n"
    @"            out = rgb;\n"
    @"        else if (mx > 0.0f)\n"
    @"            out *= max(maclc_sdr2hdr_rolloff(mx, budget), m0) / mx;\n"
    @"    }\n"
    @"\n"
    @"    float w = clamp(lg_max / log(max(budget, 1.0001f)), 0.0f, 1.0f);\n"
    @"    float Yo = u.kr * out.r + (1.0f - u.kr - u.kb) * out.g + u.kb * out.b;\n"
    @"    float k_sat = 1.0f + (u.saturation - 1.0f) * w;\n"
    @"    out = max(Yo + (out - Yo) * k_sat, 0.0f);\n"
    @"    out *= u.W;\n"
    @"\n"
    @"    float m = max(max(out.r, out.g), out.b);\n"
    @"    if (m > 0.0f)\n"
    @"        out *= maclc_sdr2hdr_rolloff(m, u.ceiling) / m;\n"
    @"\n"
    @"    float3 wide = float3(dot(u.gamut[0].xyz, out),\n"
    @"                         dot(u.gamut[1].xyz, out),\n"
    @"                         dot(u.gamut[2].xyz, out));\n"
    @"    outRGBA.write(float4(max(wide, 0.0f), 1.0f), gid);\n"
    @"}\n"
    @"\n"
    @"kernel void sdr2hdr_apply_rgba(\n"
    @"    texture2d<float, access::sample> inRGBA      [[texture(0)]],\n"
    @"    texture2d<float, access::write>  outRGBA     [[texture(1)]],\n"
    @"    texture2d<float, access::sample> guidedAB    [[texture(2)]],\n"
    @"    texture2d<float, access::sample> protectMask [[texture(3)]],\n"
    @"    texture3d<float, access::sample> gridTexture [[texture(4)]],\n"
    @"    constant VLCHDRExpandUniforms    &u          [[buffer(0)]],\n"
    @"    device const VLCHDRExpandState   *state      [[buffer(1)]],\n"
    @"    uint2 gid [[thread_position_in_grid]])\n"
    @"{\n"
    @"    if (gid.x >= u.width || gid.y >= u.height)\n"
    @"        return;\n"
    @"\n"
    @"    constexpr sampler bilinear(coord::normalized, address::clamp_to_edge, filter::linear);\n"
    @"    constexpr sampler trilinear(coord::normalized, address::clamp_to_edge, filter::linear, mip_filter::none);\n"
    @"\n"
    @"    float3 nonLinear = inRGBA.read(gid).rgb;\n"
    @"    float3 rgb = float3(eotf_channel(nonLinear.r, u),\n"
    @"                        eotf_channel(nonLinear.g, u),\n"
    @"                        eotf_channel(nonLinear.b, u));\n"
    @"\n"
    @"    float d = maclc_sdr2hdr_drive(rgb.r, rgb.g, rgb.b, u.kr, u.kb);\n"
    @"    float I = log(max(d, 1.0f / 4096.0f));\n"
    @"\n"
    @"    float2 uv = float2((float(gid.x) + 0.5f) / (8.0f * float(u.cellWidth)),\n"
    @"                       (float(gid.y) + 0.5f) / (8.0f * float(u.cellHeight)));\n"
    @"    float2 ab = guidedAB.sample(bilinear, uv).rg;\n"
    @"    float u_val = ab.x * I + ab.y;\n"
    @"\n"
    @"    float budget = state->budget;\n"
    @"    float3 lg_c;\n"
    @"    float lg_max;\n"
    @"\n"
    @"    if (u.quality == 3u || u.quality == 4u) {\n"
    @"        float z = (clamp(u_val, -3.0f, 0.0f) - (-3.0f)) / 3.0f;\n"
    @"        float3 sampledGrid = gridTexture.sample(trilinear, float3((float(gid.x) + 0.5f) / float(u.width),\n"
    @"                                                                 (float(gid.y) + 0.5f) / float(u.height),\n"
    @"                                                                 z)).rgb;\n"
    @"        lg_c = sampledGrid * log(max(budget, 10.0f)); /* MACLC_SDR2HDR_P_TRAIN */\n"
    @"        /* MACLC_SDR2HDR_HUE_SPREAD around the luminance-weighted gain */\n"
    @"        float3 kw = float3(u.kr, 1.0f - u.kr - u.kb, u.kb) * rgb;\n"
    @"        float lg_y = dot(lg_c, kw) / max(kw.r + kw.g + kw.b, 1e-6f);\n"
    @"        lg_c = lg_y + clamp(lg_c - lg_y, -0.2f, 0.2f);\n"
    @"        if (u.protect != 0u) {\n"
    @"            float pm = protectMask.sample(bilinear, uv).r;\n"
    @"            lg_c *= (1.0f - pm);\n"
    @"        }\n"
    @"        lg_max = max(max(lg_c.r, lg_c.g), lg_c.b);\n"
    @"    } else {\n"
    @"        float lg = maclc_sdr2hdr_balanced_log_gain(u_val, budget);\n"
    @"        if (u.protect != 0u) {\n"
    @"            float pm = protectMask.sample(bilinear, uv).r;\n"
    @"            lg *= (1.0f - pm);\n"
    @"        }\n"
    @"        lg_c = float3(lg);\n"
    @"        lg_max = lg;\n"
    @"    }\n"
    @"\n"
    @"    if (u.deband != 0u && lg_max > log(1.05f)) {\n"
    @"        float3 ref = nonLinear;\n"
    @"        for (uint i = 1u; i <= u.debandN; i++) {\n"
    @"            float h1 = hash1(gid, u.frameIndex, i);\n"
    @"            float h2 = hash2(gid, u.frameIndex, i);\n"
    @"            float angle = 2.0f * M_PI_F * h1;\n"
    @"            float dist = u.debandRadius * float(i) * h2;\n"
    @"            float2 o = dist * float2(cos(angle), sin(angle));\n"
    @"            float2 o2 = float2(-o.y, o.x);\n"
    @"            float2 p = float2(gid);\n"
    @"            float3 s1 = sample_nonlinear_rgba(p + o, inRGBA, u, bilinear);\n"
    @"            float3 s2 = sample_nonlinear_rgba(p - o, inRGBA, u, bilinear);\n"
    @"            float3 s3 = sample_nonlinear_rgba(p + o2, inRGBA, u, bilinear);\n"
    @"            float3 s4 = sample_nonlinear_rgba(p - o2, inRGBA, u, bilinear);\n"
    @"            float3 avg = 0.25f * (s1 + s2 + s3 + s4);\n"
    @"            float th = u.debandThreshold / float(i);\n"
    @"            if (all(abs(avg - ref) < th)) {\n"
    @"                ref = avg;\n"
    @"            }\n"
    @"        }\n"
    @"        rgb = float3(eotf_channel(ref.r, u),\n"
    @"                     eotf_channel(ref.g, u),\n"
    @"                     eotf_channel(ref.b, u));\n"
    @"    }\n"
    @"\n"
    @"    float3 out = rgb * exp(lg_c);\n"
    @"    if (u.quality == 3u || u.quality == 4u) {\n"
    @"        /* Learned gains are absolute (maclc_sdr2hdr_grid_log_scale()):\n"
    @"         * roll them off under the budget, never below the SDR pixel. */\n"
    @"        float mx = max(max(out.r, out.g), out.b);\n"
    @"        float m0 = max(max(rgb.r, rgb.g), rgb.b);\n"
    @"        if (budget <= 1.0001f)\n"
    @"            out = rgb;\n"
    @"        else if (mx > 0.0f)\n"
    @"            out *= max(maclc_sdr2hdr_rolloff(mx, budget), m0) / mx;\n"
    @"    }\n"
    @"\n"
    @"    float w = clamp(lg_max / log(max(budget, 1.0001f)), 0.0f, 1.0f);\n"
    @"    float Yo = u.kr * out.r + (1.0f - u.kr - u.kb) * out.g + u.kb * out.b;\n"
    @"    float k_sat = 1.0f + (u.saturation - 1.0f) * w;\n"
    @"    out = max(Yo + (out - Yo) * k_sat, 0.0f);\n"
    @"    out *= u.W;\n"
    @"\n"
    @"    float m = max(max(out.r, out.g), out.b);\n"
    @"    if (m > 0.0f)\n"
    @"        out *= maclc_sdr2hdr_rolloff(m, u.ceiling) / m;\n"
    @"\n"
    @"    float3 wide = float3(dot(u.gamut[0].xyz, out),\n"
    @"                         dot(u.gamut[1].xyz, out),\n"
    @"                         dot(u.gamut[2].xyz, out));\n"
    @"    outRGBA.write(float4(max(wide, 0.0f), 1.0f), gid);\n"
    @"}\n";

/* Stand-in producer class used ONLY when MACLC_SDR2HDR_TEST_GRID=1 */
@interface VLCHDRAnalyticGridProducer : NSObject <VLCHDRGridProducer>
- (nullable instancetype)initWithDevice:(id<MTLDevice>)device library:(id<MTLLibrary>)library;
@end

@implementation VLCHDRAnalyticGridProducer {
    id<MTLDevice> _device;
    id<MTLComputePipelineState> _pipeline;
}

- (nullable instancetype)initWithDevice:(id<MTLDevice>)device library:(id<MTLLibrary>)library
{
    self = [super init];
    if (self == nil)
        return nil;
    _device = device;
    NSError *error = nil;
    id<MTLFunction> func = [library newFunctionWithName:@"sdr2hdr_analytic_grid"];
    if (func != nil) {
        _pipeline = [_device newComputePipelineStateWithFunction:func error:&error];
    }
    if (_pipeline == nil) {
        return nil;
    }
    return self;
}

- (NSUInteger)gridWidth { return 16; }
- (NSUInteger)gridHeight { return 16; }
- (NSUInteger)gridDepth { return 8; }
- (NSUInteger)thumbnailSize { return 256; }

- (BOOL)supportsQuality:(enum maclc_sdr2hdr_quality)quality
{
    return (quality == MACLC_SDR2HDR_HIGH || quality == MACLC_SDR2HDR_MAXIMUM);
}

- (nullable id<MTLCommandBuffer>)encodeGridForThumbnail:(id<MTLTexture>)thumbnail
                                               intoGrid:(id<MTLBuffer>)grid
                                          commandBuffer:(id<MTLCommandBuffer>)commandBuffer
{
    VLC_UNUSED(thumbnail);
    if (_pipeline == nil)
        return nil;
    id<MTLComputeCommandEncoder> enc = [commandBuffer computeCommandEncoder];
    if (enc == nil)
        return nil;
    [enc setComputePipelineState:_pipeline];
    [enc setBuffer:grid offset:0 atIndex:0];
    [enc dispatchThreadgroups:MTLSizeMake(2, 2, 2) threadsPerThreadgroup:MTLSizeMake(8, 8, 4)];
    [enc endEncoding];
    return commandBuffer;
}
@end

@interface VLCHDRExpander ()
- (nullable instancetype)initWithObject:(vlc_object_t *)obj;
@end

@implementation VLCHDRExpander
{
    vlc_object_t *_obj;

    id<MTLDevice> _device;
    id<MTLCommandQueue> _queue;

    id<MTLComputePipelineState> _fastBiplanarPipeline;
    id<MTLComputePipelineState> _fastRgbaPipeline;
    id<MTLComputePipelineState> _analyzeBiplanarPipeline;
    id<MTLComputePipelineState> _analyzeRgbaPipeline;
    id<MTLComputePipelineState> _frameStatePipeline;
    id<MTLComputePipelineState> _boxHPipeline;
    id<MTLComputePipelineState> _boxVComputeAbPipeline;
    id<MTLComputePipelineState> _boxVAbPipeline;
    id<MTLComputePipelineState> _protectPipeline;
    id<MTLComputePipelineState> _protectDilatePipeline;
    id<MTLComputePipelineState> _thumbnailBiplanarPipeline;
    id<MTLComputePipelineState> _thumbnailRgbaPipeline;
    id<MTLComputePipelineState> _gridEmaPipeline;
    id<MTLComputePipelineState> _applyBiplanarPipeline;
    id<MTLComputePipelineState> _applyRgbaPipeline;

    MTLStorageMode _storageMode;

    CVPixelBufferPoolRef _pool;
    size_t _poolWidth;
    size_t _poolHeight;

    /* Sized intermediate GPU resources */
    size_t _texWidth;
    size_t _texHeight;
    size_t _cw;
    size_t _ch;

    id<MTLTexture> _statsA;
    id<MTLTexture> _statsB;
    id<MTLTexture> _tempRG;
    id<MTLTexture> _guidedAB;

    id<MTLTexture> _prevYTex[2];
    id<MTLTexture> _stillTex[2];
    id<MTLTexture> _persistTex[2];
    id<MTLTexture> _protectRaw;
    id<MTLTexture> _protectMask;

    id<MTLBuffer> _stateBuffer;
    NSUInteger _pingPongIndex;

    /* High / Maximum resources */
    NSUInteger _gridRawWidth;
    NSUInteger _gridRawHeight;
    NSUInteger _gridRawDepth;
    NSUInteger _thumbnailSize;
    id<MTLBuffer> _gridRawBuffer;
    id<MTLTexture> _thumbnailTex;
    id<MTLTexture> _grid3D[2];
    NSUInteger _gridIndex;
    BOOL _gridNeedsReset;
    BOOL _protectNeedsReset;  /* the protect textures were not written last frame */

    id<MTLTexture> _dummy2DTex;
    id<MTLTexture> _dummy3DTex;

    /* Temporal CPU state */
    BOOL _reset;
    float _P_prev;
    vlc_tick_t _prevDate;
    uint32_t _frameIndex;

    enum maclc_sdr2hdr_quality _lastQuality;
    BOOL _lastFallback;
    float _lastPeakNits;
    double _lastGPUTimeMs;
    int _lastLoggedQuality;

    BOOL _warnedUnsupportedFormat;
    BOOL _warnedNoIOSurface;
    BOOL _warnedTextureFailure;
}

+ (nullable instancetype)expanderForObject:(vlc_object_t *)obj
{
    return [[VLCHDRExpander alloc] initWithObject:obj];
}

- (nullable instancetype)initWithObject:(vlc_object_t *)obj
{
    self = [super init];
    if (self == nil)
        return nil;

    _obj = obj;
    _reset = YES;
    _P_prev = 0.0f;
    _prevDate = VLC_TICK_INVALID;
    _frameIndex = 0;
    _lastQuality = MACLC_SDR2HDR_AUTO;
    _lastFallback = NO;
    _lastPeakNits = 0.0f;
    _lastGPUTimeMs = 0.0;
    _lastLoggedQuality = -1;

    _device = MTLCreateSystemDefaultDevice();
    if (_device == nil) {
        msg_Warn(obj, "SDR to HDR: no Metal device, expansion unavailable");
        return nil;
    }

    _storageMode = MTLStorageModeManaged;
#if TARGET_OS_OSX
    if (@available(macOS 10.15, *)) {
        if (_device.hasUnifiedMemory)
            _storageMode = MTLStorageModeShared;
    }
#else
    _storageMode = MTLStorageModeShared;
#endif

    NSError *error = nil;
    id<MTLLibrary> library =
        [_device newLibraryWithSource:kVLCHDRExpanderShaderSource
                              options:nil
                                error:&error];
    if (library == nil) {
        msg_Err(obj, "SDR to HDR: shader compilation failed: %s",
                error.localizedDescription.UTF8String ?: "unknown error");
        return nil;
    }

#define LOAD_PIPELINE(field, name) do { \
    id<MTLFunction> fn = [library newFunctionWithName:@(name)]; \
    if (fn == nil) { \
        msg_Err(obj, "SDR to HDR: kernel %s missing from library", name); \
        return nil; \
    } \
    field = [_device newComputePipelineStateWithFunction:fn error:&error]; \
    if (field == nil) { \
        msg_Err(obj, "SDR to HDR: could not create pipeline for %s: %s", \
                name, error.localizedDescription.UTF8String ?: "unknown"); \
        return nil; \
    } \
} while(0)

    LOAD_PIPELINE(_fastBiplanarPipeline, "vlc_hdr_expand_fast_biplanar");
    LOAD_PIPELINE(_fastRgbaPipeline, "vlc_hdr_expand_fast_rgba");
    LOAD_PIPELINE(_analyzeBiplanarPipeline, "sdr2hdr_analyze_biplanar");
    LOAD_PIPELINE(_analyzeRgbaPipeline, "sdr2hdr_analyze_rgba");
    LOAD_PIPELINE(_frameStatePipeline, "sdr2hdr_frame_state");
    LOAD_PIPELINE(_boxHPipeline, "sdr2hdr_box_h");
    LOAD_PIPELINE(_boxVComputeAbPipeline, "sdr2hdr_box_v_compute_ab");
    LOAD_PIPELINE(_boxVAbPipeline, "sdr2hdr_box_v_ab");
    LOAD_PIPELINE(_protectPipeline, "sdr2hdr_protect");
    LOAD_PIPELINE(_protectDilatePipeline, "sdr2hdr_protect_dilate");
    LOAD_PIPELINE(_thumbnailBiplanarPipeline, "sdr2hdr_thumbnail_biplanar");
    LOAD_PIPELINE(_thumbnailRgbaPipeline, "sdr2hdr_thumbnail_rgba");
    LOAD_PIPELINE(_gridEmaPipeline, "sdr2hdr_grid_ema");
    LOAD_PIPELINE(_applyBiplanarPipeline, "sdr2hdr_apply_biplanar");
    LOAD_PIPELINE(_applyRgbaPipeline, "sdr2hdr_apply_rgba");
#undef LOAD_PIPELINE

    _queue = [_device newCommandQueue];
    if (_queue == nil) {
        msg_Err(obj, "SDR to HDR: could not create a Metal command queue");
        return nil;
    }

    _stateBuffer = [_device newBufferWithLength:sizeof(VLCHDRExpandState)
                                        options:MTLResourceStorageModeShared];
    if (_stateBuffer != nil) {
        memset(_stateBuffer.contents, 0, sizeof(VLCHDRExpandState));
    }

    MTLTextureDescriptor *dummy2DDesc =
        [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatR16Float
                                                           width:1
                                                          height:1
                                                       mipmapped:NO];
    dummy2DDesc.usage = MTLTextureUsageShaderRead;
    _dummy2DTex = [_device newTextureWithDescriptor:dummy2DDesc];

    MTLTextureDescriptor *dummy3DDesc = [[MTLTextureDescriptor alloc] init];
    dummy3DDesc.textureType = MTLTextureType3D;
    dummy3DDesc.pixelFormat = MTLPixelFormatRGBA16Float;
    dummy3DDesc.width = 1;
    dummy3DDesc.height = 1;
    dummy3DDesc.depth = 1;
    dummy3DDesc.usage = MTLTextureUsageShaderRead;
    _dummy3DTex = [_device newTextureWithDescriptor:dummy3DDesc];

    const char *testGrid = getenv("MACLC_SDR2HDR_TEST_GRID");
    if (testGrid != NULL && strcmp(testGrid, "1") == 0) {
        _gridProducer = [[VLCHDRAnalyticGridProducer alloc] initWithDevice:_device library:library];
        msg_Dbg(obj, "SDR to HDR: test grid producer initialized (MACLC_SDR2HDR_TEST_GRID=1)");
    }

    msg_Dbg(obj, "SDR to HDR: pipeline ready on Metal device \"%s\"",
            _device.name.UTF8String ?: "unknown");
    return self;
}

- (void)dealloc
{
    CVPixelBufferPoolRelease(_pool);
}

- (void)resetTemporalState
{
    _reset = YES;
    _P_prev = 0.0f;
    _prevDate = VLC_TICK_INVALID;
    _pingPongIndex = 0;
    _gridIndex = 0;
    _gridNeedsReset = YES;
    _protectNeedsReset = YES;
    if (_stateBuffer != nil) {
        memset(_stateBuffer.contents, 0, sizeof(VLCHDRExpandState));
    }
}

- (BOOL)canExpandPixelFormat:(OSType)pixelFormat
{
    switch (pixelFormat) {
    case kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange:
    case kCVPixelFormatType_420YpCbCr8BiPlanarFullRange:
    case VLC_CVPX_FORMAT_P010:
    case kCVPixelFormatType_32BGRA:
        return YES;
    default:
        return NO;
    }
}

#pragma mark - Metal helpers

- (nullable id<MTLTexture>)textureFromBuffer:(CVPixelBufferRef)buffer
                                        plane:(size_t)plane
                                  pixelFormat:(MTLPixelFormat)pixelFormat
                                     writable:(BOOL)writable
{
    IOSurfaceRef surface = CVPixelBufferGetIOSurface(buffer);
    if (surface == NULL) {
        if (!_warnedNoIOSurface) {
            msg_Warn(_obj, "SDR to HDR: picture is not IOSurface-backed, expansion skipped");
            _warnedNoIOSurface = YES;
        }
        return nil;
    }

    size_t width, height;
    if (IOSurfaceGetPlaneCount(surface) > 0) {
        width = IOSurfaceGetWidthOfPlane(surface, plane);
        height = IOSurfaceGetHeightOfPlane(surface, plane);
    } else {
        width = IOSurfaceGetWidth(surface);
        height = IOSurfaceGetHeight(surface);
    }

    if (width == 0 || height == 0)
        return nil;

    MTLTextureDescriptor *descriptor = [MTLTextureDescriptor
        texture2DDescriptorWithPixelFormat:pixelFormat
                                     width:width
                                    height:height
                                 mipmapped:NO];
    descriptor.usage = writable ? MTLTextureUsageShaderWrite
                                : MTLTextureUsageShaderRead;
    descriptor.storageMode = _storageMode;

    id<MTLTexture> texture = [_device newTextureWithDescriptor:descriptor
                                                     iosurface:surface
                                                         plane:plane];
    if (texture == nil && !_warnedTextureFailure) {
        msg_Warn(_obj, "SDR to HDR: could not wrap plane %zu of an IOSurface as a Metal texture", plane);
        _warnedTextureFailure = YES;
    }
    return texture;
}

- (BOOL)prepareOutputPoolForWidth:(size_t)width height:(size_t)height
{
    if (_pool != NULL && _poolWidth == width && _poolHeight == height)
        return YES;

    CVPixelBufferPoolRelease(_pool);
    _pool = NULL;

    NSDictionary *attributes = @{
        (__bridge NSString *)kCVPixelBufferPixelFormatTypeKey: @(VLC_CVPX_FORMAT_RGBA_HALF),
        (__bridge NSString *)kCVPixelBufferWidthKey: @(width),
        (__bridge NSString *)kCVPixelBufferHeightKey: @(height),
        (__bridge NSString *)kCVPixelBufferIOSurfacePropertiesKey: @{},
        (__bridge NSString *)kCVPixelBufferMetalCompatibilityKey: @YES,
        (__bridge NSString *)kCVPixelBufferBytesPerRowAlignmentKey: @16,
    };
    NSDictionary *poolAttributes = @{
        (__bridge NSString *)kCVPixelBufferPoolMinimumBufferCountKey: @3,
        (__bridge NSString *)kCVPixelBufferPoolMaximumBufferAgeKey: @0,
    };

    CVReturn err =
        CVPixelBufferPoolCreate(kCFAllocatorDefault,
                                (__bridge CFDictionaryRef)poolAttributes,
                                (__bridge CFDictionaryRef)attributes,
                                &_pool);
    if (err != kCVReturnSuccess) {
        msg_Err(_obj, "SDR to HDR: could not create a %zux%zu half-float pool (%d)",
                width, height, (int)err);
        _pool = NULL;
        return NO;
    }

    _poolWidth = width;
    _poolHeight = height;
    return YES;
}

- (BOOL)prepareIntermediateTexturesForWidth:(size_t)width height:(size_t)height
{
    const size_t cw = (width + 7) / 8;
    const size_t ch = (height + 7) / 8;

    if (_texWidth == width && _texHeight == height && _statsA != nil)
        return YES;

    MTLTextureDescriptor *descRGBA32 = [MTLTextureDescriptor
        texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA32Float
                                     width:cw
                                    height:ch
                                 mipmapped:NO];
    descRGBA32.usage = MTLTextureUsageShaderRead | MTLTextureUsageShaderWrite;

    MTLTextureDescriptor *descRG32 = [MTLTextureDescriptor
        texture2DDescriptorWithPixelFormat:MTLPixelFormatRG32Float
                                     width:cw
                                    height:ch
                                 mipmapped:NO];
    descRG32.usage = MTLTextureUsageShaderRead | MTLTextureUsageShaderWrite;

    MTLTextureDescriptor *descR32 = [MTLTextureDescriptor
        texture2DDescriptorWithPixelFormat:MTLPixelFormatR32Float
                                     width:cw
                                    height:ch
                                 mipmapped:NO];
    descR32.usage = MTLTextureUsageShaderRead | MTLTextureUsageShaderWrite;

    MTLTextureDescriptor *descR16 = [MTLTextureDescriptor
        texture2DDescriptorWithPixelFormat:MTLPixelFormatR16Float
                                     width:cw
                                    height:ch
                                 mipmapped:NO];
    descR16.usage = MTLTextureUsageShaderRead | MTLTextureUsageShaderWrite;

    _statsA = [_device newTextureWithDescriptor:descRGBA32];
    _statsB = [_device newTextureWithDescriptor:descRGBA32];
    _tempRG = [_device newTextureWithDescriptor:descRG32];
    /* Sampled with a linear filter by the apply pass: half floats are
     * filterable on every GPU (32-bit floats are not), and b stays within
     * [-8.3, 0], where a half is precise to a few thousandths. */
    MTLTextureDescriptor *descRG16 = [MTLTextureDescriptor
        texture2DDescriptorWithPixelFormat:MTLPixelFormatRG16Float
                                     width:cw
                                    height:ch
                                 mipmapped:NO];
    descRG16.usage = MTLTextureUsageShaderRead | MTLTextureUsageShaderWrite;
    _guidedAB = [_device newTextureWithDescriptor:descRG16];

    _protectNeedsReset = YES; /* new textures: nothing written yet */
    _prevYTex[0] = [_device newTextureWithDescriptor:descR32];
    _prevYTex[1] = [_device newTextureWithDescriptor:descR32];
    _stillTex[0] = [_device newTextureWithDescriptor:descR32];
    _stillTex[1] = [_device newTextureWithDescriptor:descR32];
    _persistTex[0] = [_device newTextureWithDescriptor:descR32];
    _persistTex[1] = [_device newTextureWithDescriptor:descR32];

    _protectRaw = [_device newTextureWithDescriptor:descR16];
    _protectMask = [_device newTextureWithDescriptor:descR16];

    if (_statsA == nil || _statsB == nil || _tempRG == nil || _guidedAB == nil ||
        _prevYTex[0] == nil || _prevYTex[1] == nil || _stillTex[0] == nil || _stillTex[1] == nil ||
        _persistTex[0] == nil || _persistTex[1] == nil || _protectRaw == nil || _protectMask == nil) {
        msg_Err(_obj, "SDR to HDR: failed to allocate intermediate textures");
        /* Some textures may now be nil or of the new size: never reuse them. */
        _texWidth = _texHeight = 0;
        return NO;
    }

    _texWidth = width;
    _texHeight = height;
    _cw = cw;
    _ch = ch;
    [self resetTemporalState];
    return YES;
}

- (BOOL)prepareGridResourcesForProducer:(id<VLCHDRGridProducer>)producer
{
    if (producer == nil)
        return YES;

    NSUInteger gw = producer.gridWidth;
    NSUInteger gh = producer.gridHeight;
    NSUInteger gd = producer.gridDepth;
    NSUInteger ts = producer.thumbnailSize;

    if (_gridRawBuffer == nil || _gridRawWidth != gw || _gridRawHeight != gh || _gridRawDepth != gd) {
        NSUInteger bytes = gw * gh * gd * 3 * sizeof(uint16_t);
        _gridRawBuffer = [_device newBufferWithLength:bytes options:MTLResourceStorageModeShared];
        MTLTextureDescriptor *desc3D = [[MTLTextureDescriptor alloc] init];
        desc3D.textureType = MTLTextureType3D;
        desc3D.pixelFormat = MTLPixelFormatRGBA16Float;
        desc3D.width = gw;
        desc3D.height = gh;
        desc3D.depth = gd;
        desc3D.usage = MTLTextureUsageShaderRead | MTLTextureUsageShaderWrite;
        _grid3D[0] = [_device newTextureWithDescriptor:desc3D];
        _grid3D[1] = [_device newTextureWithDescriptor:desc3D];

        if (_gridRawBuffer == nil || _grid3D[0] == nil || _grid3D[1] == nil)
            return NO;

        _gridRawWidth = gw;
        _gridRawHeight = gh;
        _gridRawDepth = gd;
        _gridNeedsReset = YES;
    }

    if (_thumbnailTex == nil || _thumbnailSize != ts) {
        MTLTextureDescriptor *descThumb = [MTLTextureDescriptor
            texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA16Float
                                         width:ts
                                        height:ts
                                     mipmapped:NO];
        descThumb.usage = MTLTextureUsageShaderRead | MTLTextureUsageShaderWrite;
        _thumbnailTex = [_device newTextureWithDescriptor:descThumb];
        if (_thumbnailTex == nil)
            return NO;
        _thumbnailSize = ts;
    }

    return YES;
}

static void FillSourceColorimetry(VLCHDRExpandUniforms *uniforms,
                                  const video_format_t *fmt,
                                  BOOL isRGB)
{
    switch (fmt->space) {
    case COLOR_SPACE_BT601:  uniforms->matrix = VLC_HDR_MATRIX_BT601;  break;
    case COLOR_SPACE_BT2020: uniforms->matrix = VLC_HDR_MATRIX_BT2020; break;
    default:                 uniforms->matrix = VLC_HDR_MATRIX_BT709;  break;
    }

    switch (uniforms->matrix) {
    case VLC_HDR_MATRIX_BT601:
        uniforms->kr = 0.299f;
        uniforms->kb = 0.114f;
        break;
    case VLC_HDR_MATRIX_BT2020:
        uniforms->kr = 0.2627f;
        uniforms->kb = 0.0593f;
        break;
    default:
        uniforms->kr = 0.2126f;
        uniforms->kb = 0.0722f;
        break;
    }

    uniforms->transferMode = VLC_HDR_TRANSFER_POWER;
    switch (fmt->transfer) {
    case TRANSFER_FUNC_SRGB:
        uniforms->gamma = isRGB ? 2.2f : 2.0f;
        break;
    case TRANSFER_FUNC_BT470_M:
    case TRANSFER_FUNC_BT470_BG:
        uniforms->gamma = isRGB ? 1.961f : 1.8f;
        break;
    case TRANSFER_FUNC_LINEAR:
        uniforms->gamma = 1.0f;
        break;
    default:
        if (isRGB)
            uniforms->transferMode = VLC_HDR_TRANSFER_BT709_OETF;
        uniforms->gamma = 1.961f;
        break;
    }

    const float *gamut;
    switch (fmt->primaries) {
    case COLOR_PRIMARIES_BT2020:    gamut = kGamutIdentity;         break;
    case COLOR_PRIMARIES_DCI_P3:    gamut = kGamutP3D65ToBT2020;    break;
    case COLOR_PRIMARIES_BT601_525: gamut = kGamutSMPTE170ToBT2020; break;
    case COLOR_PRIMARIES_BT601_625: gamut = kGamutEBU3213ToBT2020;  break;
    default:                        gamut = kGamutBT709ToBT2020;    break;
    }

    for (int row = 0; row < 3; ++row) {
        const float sum = gamut[row * 3] + gamut[row * 3 + 1] + gamut[row * 3 + 2];
        uniforms->gamut[row * 4 + 0] = gamut[row * 3 + 0] / sum;
        uniforms->gamut[row * 4 + 1] = gamut[row * 3 + 1] / sum;
        uniforms->gamut[row * 4 + 2] = gamut[row * 3 + 2] / sum;
        uniforms->gamut[row * 4 + 3] = 0.0f;
    }

    if (isRGB) {
        uniforms->matrix = VLC_HDR_MATRIX_BT709;
        uniforms->kr = 0.2126f;
        uniforms->kb = 0.0722f;
    }
}

#pragma mark - Expansion

- (nullable CVPixelBufferRef)expandPixelBuffer:(CVPixelBufferRef)pixelBuffer
                                        format:(const video_format_t *)fmt
                                        params:(const VLCHDRExpandParams *)params
{
    if (pixelBuffer == NULL || fmt == NULL || params == NULL)
        return NULL;

    const OSType sourceFormat = CVPixelBufferGetPixelFormatType(pixelBuffer);
    if (![self canExpandPixelFormat:sourceFormat]) {
        if (!_warnedUnsupportedFormat) {
            const char name[5] = {
                (char)(sourceFormat >> 24), (char)(sourceFormat >> 16),
                (char)(sourceFormat >> 8), (char)sourceFormat, '\0'
            };
            msg_Warn(_obj, "SDR to HDR: pixel format %s cannot be expanded, playing it as SDR", name);
            _warnedUnsupportedFormat = YES;
        }
        return NULL;
    }

    const size_t width = CVPixelBufferGetWidth(pixelBuffer);
    const size_t height = CVPixelBufferGetHeight(pixelBuffer);
    if (width < 2 || height < 2)
        return NULL;

    /* 3.1 CPU side timing and peak calculation */
    float dt;
    uint32_t reset_flag = 0;
    if (_reset) {
        _reset = NO;
        reset_flag = 1;
        _P_prev = 0.0f;
        dt = (params->date != VLC_TICK_INVALID && _prevDate != VLC_TICK_INVALID && params->date > _prevDate)
            ? (float)(params->date - _prevDate) / (float)CLOCK_FREQ : (1.0f / 24.0f);
    } else {
        dt = (params->date != VLC_TICK_INVALID && _prevDate != VLC_TICK_INVALID && params->date > _prevDate)
            ? (float)(params->date - _prevDate) / (float)CLOCK_FREQ : (1.0f / 24.0f);
    }
    dt = maclc_sdr2hdr_clamp(dt, 0.0f, 0.25f);
    _prevDate = params->date;

    const float P_t = maclc_sdr2hdr_target_peak(params->boost, params->headroom);
    const float P = maclc_sdr2hdr_smooth_peak(_P_prev, P_t, dt);
    _P_prev = P;

    const float W = maclc_sdr2hdr_white_level(params->midtones, P);
    const float P_rel = fmaxf(1.0f, P / W);
    const float ceiling = fmaxf(1.0f, params->headroom);

    if (P_rel <= 1.0001f && fabsf(W - 1.0f) < 1e-4f)
        return NULL;

    if (![self prepareOutputPoolForWidth:width height:height])
        return NULL;

    const BOOL isRGB = (sourceFormat == kCVPixelFormatType_32BGRA);
    const BOOL is10Bit = (sourceFormat == VLC_CVPX_FORMAT_P010);

    enum maclc_sdr2hdr_quality resolvedQuality = params->quality;
    BOOL fallback = NO;
    BOOL gridReady = NO;

    if (resolvedQuality == MACLC_SDR2HDR_HIGH || resolvedQuality == MACLC_SDR2HDR_MAXIMUM) {
        if (_gridProducer != nil && [_gridProducer supportsQuality:resolvedQuality]) {
            if ([_gridProducer respondsToSelector:@selector(setCurrentQuality:)])
                _gridProducer.currentQuality = resolvedQuality;
            if ([self prepareGridResourcesForProducer:_gridProducer])
                gridReady = YES;
        }
        if (!gridReady) {
            resolvedQuality = MACLC_SDR2HDR_BALANCED;
            fallback = YES;
        }
    }

    if (resolvedQuality != MACLC_SDR2HDR_FAST) {
        if (![self prepareIntermediateTexturesForWidth:width height:height])
            return NULL;
    }

    /* Wrap input buffers as Metal textures */
    id<MTLTexture> inLuma = nil;
    id<MTLTexture> inChroma = nil;
    id<MTLTexture> inRGBA = nil;
    id<MTLTexture> outRGBA = nil;
    id<MTLCommandBuffer> commandBuffer = nil;
    id<MTLCommandBuffer> committedEarlier = nil;
    CVPixelBufferRef output = NULL;

    CVReturn err = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, _pool, &output);
    if (err != kCVReturnSuccess || output == NULL)
        return NULL;

    if (isRGB) {
        inRGBA = [self textureFromBuffer:pixelBuffer
                                   plane:0
                             pixelFormat:MTLPixelFormatBGRA8Unorm
                                writable:NO];
        if (inRGBA == nil)
            goto failure;
    } else {
        inLuma = [self textureFromBuffer:pixelBuffer
                                   plane:0
                             pixelFormat:is10Bit ? MTLPixelFormatR16Unorm
                                                 : MTLPixelFormatR8Unorm
                                writable:NO];
        inChroma = [self textureFromBuffer:pixelBuffer
                                     plane:1
                               pixelFormat:is10Bit ? MTLPixelFormatRG16Unorm
                                                   : MTLPixelFormatRG8Unorm
                                  writable:NO];
        if (inLuma == nil || inChroma == nil)
            goto failure;
    }

    outRGBA = [self textureFromBuffer:output
                                plane:0
                          pixelFormat:MTLPixelFormatRGBA16Float
                             writable:YES];
    if (outRGBA == nil)
        goto failure;

    VLCHDRExpandUniforms uniforms;
    memset(&uniforms, 0, sizeof(uniforms));
    uniforms.inputScale = is10Bit ? VLC_HDR_10BIT_READ_SCALE : 1.0f;

    switch (sourceFormat) {
    case kCVPixelFormatType_420YpCbCr8BiPlanarFullRange:
        uniforms.lumaOffset = 0.0f;
        uniforms.lumaScale = 1.0f;
        uniforms.chromaOffset = 128.0f / 255.0f;
        uniforms.chromaScale = 1.0f;
        break;
    case VLC_CVPX_FORMAT_P010:
        uniforms.lumaOffset = 64.0f / 1023.0f;
        uniforms.lumaScale = 1023.0f / 876.0f;
        uniforms.chromaOffset = 512.0f / 1023.0f;
        uniforms.chromaScale = 1023.0f / 896.0f;
        break;
    case kCVPixelFormatType_32BGRA:
        uniforms.lumaOffset = 0.0f;
        uniforms.lumaScale = 1.0f;
        uniforms.chromaOffset = 0.0f;
        uniforms.chromaScale = 1.0f;
        break;
    default:
        uniforms.lumaOffset = 16.0f / 255.0f;
        uniforms.lumaScale = 255.0f / 219.0f;
        uniforms.chromaOffset = 128.0f / 255.0f;
        uniforms.chromaScale = 255.0f / 224.0f;
        break;
    }

    FillSourceColorimetry(&uniforms, fmt, isRGB);

    uniforms.width = (uint32_t)MIN(width, outRGBA.width);
    uniforms.height = (uint32_t)MIN(height, outRGBA.height);
    uniforms.P_rel = P_rel;
    uniforms.W = W;
    uniforms.ceiling = ceiling;
    uniforms.dt = dt;
    uniforms.saturation = params->saturation;
    uniforms.reset = reset_flag;
    uniforms.quality = (uint32_t)resolvedQuality;
    uniforms.deband = (uint32_t)params->deband;
    uniforms.protect = params->protect ? 1u : 0u;
    /* Protection off leaves its history unwritten: start it over when it
     * comes back rather than read stale or never-written textures. */
    if (!params->protect)
        _protectNeedsReset = YES;
    uniforms.protectReset = _protectNeedsReset ? 1u : 0u;
    uniforms.frameIndex = _frameIndex++;
    uniforms.cellWidth = (uint32_t)_cw;
    uniforms.cellHeight = (uint32_t)_ch;
    uniforms.guidedRadius = (int32_t)fmaxf(2.0f, roundf((float)_ch / 34.0f));
    uniforms.guidedEps = 0.05f;
    uniforms.debandRadius = (params->deband == MACLC_SDR2HDR_DEBAND_STRONG)
        ? (20.0f * (float)height / 1080.0f) : (16.0f * (float)height / 1080.0f);
    uniforms.debandThreshold = (params->deband == MACLC_SDR2HDR_DEBAND_STRONG)
        ? (4.0f / 255.0f) : (2.0f / 255.0f);
    uniforms.debandN = (params->deband == MACLC_SDR2HDR_DEBAND_STRONG) ? 2u : 1u;
    if (gridReady) {
        uniforms.gridWidth = (uint32_t)_gridRawWidth;
        uniforms.gridHeight = (uint32_t)_gridRawHeight;
        uniforms.gridDepth = (uint32_t)_gridRawDepth;
        /* Coming from another level, the grid texture holds an old scene (or
         * nothing at all): start from this picture's prediction. */
        if (_lastQuality != MACLC_SDR2HDR_HIGH && _lastQuality != MACLC_SDR2HDR_MAXIMUM)
            _gridNeedsReset = YES;
        uniforms.gridReset = _gridNeedsReset ? 1u : 0u;
    }

    commandBuffer = [_queue commandBuffer];
    if (commandBuffer == nil)
        goto failure;

    if (resolvedQuality == MACLC_SDR2HDR_FAST) {
        id<MTLComputeCommandEncoder> enc = [commandBuffer computeCommandEncoder];
        if (enc == nil)
            goto failure;
        id<MTLComputePipelineState> pipeline = isRGB ? _fastRgbaPipeline : _fastBiplanarPipeline;
        [enc setComputePipelineState:pipeline];
        if (isRGB) {
            [enc setTexture:inRGBA atIndex:0];
            [enc setTexture:outRGBA atIndex:1];
        } else {
            [enc setTexture:inLuma atIndex:0];
            [enc setTexture:inChroma atIndex:1];
            [enc setTexture:outRGBA atIndex:2];
        }
        [enc setBytes:&uniforms length:sizeof(uniforms) atIndex:0];

        NSUInteger gw = 16, gh = 16;
        while (gw * gh > pipeline.maxTotalThreadsPerThreadgroup && gh > 1)
            gh /= 2;
        [enc dispatchThreadgroups:MTLSizeMake((uniforms.width + gw - 1) / gw,
                                             (uniforms.height + gh - 1) / gh, 1)
            threadsPerThreadgroup:MTLSizeMake(gw, gh, 1)];
        [enc endEncoding];
    } else {
        const NSUInteger cellGw = 16, cellGh = 16;
        const MTLSize cellGroups = MTLSizeMake((_cw + cellGw - 1) / cellGw,
                                             (_ch + cellGh - 1) / cellGh, 1);
        const MTLSize cellThreads = MTLSizeMake(cellGw, cellGh, 1);

        /* Pass 1: Analysis */
        {
            id<MTLComputeCommandEncoder> enc = [commandBuffer computeCommandEncoder];
            if (enc == nil) goto failure;
            id<MTLComputePipelineState> p = isRGB ? _analyzeRgbaPipeline : _analyzeBiplanarPipeline;
            [enc setComputePipelineState:p];
            if (isRGB) {
                [enc setTexture:inRGBA atIndex:0];
                [enc setTexture:_statsA atIndex:1];
                [enc setTexture:_statsB atIndex:2];
            } else {
                [enc setTexture:inLuma atIndex:0];
                [enc setTexture:inChroma atIndex:1];
                [enc setTexture:_statsA atIndex:2];
                [enc setTexture:_statsB atIndex:3];
            }
            [enc setBytes:&uniforms length:sizeof(uniforms) atIndex:0];
            [enc dispatchThreadgroups:cellGroups threadsPerThreadgroup:cellThreads];
            [enc endEncoding];
        }

        /* Pass 2: Frame state reduction */
        {
            id<MTLComputeCommandEncoder> enc = [commandBuffer computeCommandEncoder];
            if (enc == nil) goto failure;
            [enc setComputePipelineState:_frameStatePipeline];
            [enc setTexture:_statsA atIndex:0];
            [enc setTexture:_statsB atIndex:1];
            [enc setTexture:_prevYTex[_pingPongIndex] atIndex:2];
            [enc setBuffer:_stateBuffer offset:0 atIndex:0];
            [enc setBytes:&uniforms length:sizeof(uniforms) atIndex:1];
            /* A power of two the pipeline accepts: the reduction halves it. */
            NSUInteger tg = 1024;
            while (tg > _frameStatePipeline.maxTotalThreadsPerThreadgroup && tg > 32)
                tg >>= 1;
            [enc dispatchThreadgroups:MTLSizeMake(1, 1, 1)
                threadsPerThreadgroup:MTLSizeMake(tg, 1, 1)];
            [enc endEncoding];
        }

        /* Pass 3: Guided filter on cell resolution */
        {
            id<MTLComputeCommandEncoder> enc = [commandBuffer computeCommandEncoder];
            if (enc == nil) goto failure;

            /* 3a: Box filter statsA horizontally -> _tempRG */
            [enc setComputePipelineState:_boxHPipeline];
            [enc setTexture:_statsA atIndex:0];
            [enc setTexture:_tempRG atIndex:1];
            [enc setBytes:&uniforms length:sizeof(uniforms) atIndex:0];
            [enc dispatchThreadgroups:cellGroups threadsPerThreadgroup:cellThreads];

            /* 3b: Box filter vertically & compute a, b -> _guidedAB */
            [enc setComputePipelineState:_boxVComputeAbPipeline];
            [enc setTexture:_tempRG atIndex:0];
            [enc setTexture:_guidedAB atIndex:1];
            [enc setBytes:&uniforms length:sizeof(uniforms) atIndex:0];
            [enc dispatchThreadgroups:cellGroups threadsPerThreadgroup:cellThreads];

            /* 3c: Box filter a, b horizontally -> _tempRG */
            [enc setComputePipelineState:_boxHPipeline];
            [enc setTexture:_guidedAB atIndex:0];
            [enc setTexture:_tempRG atIndex:1];
            [enc setBytes:&uniforms length:sizeof(uniforms) atIndex:0];
            [enc dispatchThreadgroups:cellGroups threadsPerThreadgroup:cellThreads];

            /* 3d: Box filter a, b vertically -> _guidedAB */
            [enc setComputePipelineState:_boxVAbPipeline];
            [enc setTexture:_tempRG atIndex:0];
            [enc setTexture:_guidedAB atIndex:1];
            [enc setBytes:&uniforms length:sizeof(uniforms) atIndex:0];
            [enc dispatchThreadgroups:cellGroups threadsPerThreadgroup:cellThreads];

            [enc endEncoding];
        }

        /* Pass 4: Protect (subtitles and logos) */
        NSUInteger nextPingPong = 1 - _pingPongIndex;
        if (params->protect) {
            id<MTLComputeCommandEncoder> enc = [commandBuffer computeCommandEncoder];
            if (enc == nil) goto failure;

            [enc setComputePipelineState:_protectPipeline];
            [enc setTexture:_statsA atIndex:0];
            [enc setTexture:_statsB atIndex:1];
            [enc setTexture:_prevYTex[_pingPongIndex] atIndex:2];
            [enc setTexture:_stillTex[_pingPongIndex] atIndex:3];
            [enc setTexture:_persistTex[_pingPongIndex] atIndex:4];
            [enc setTexture:_prevYTex[nextPingPong] atIndex:5];
            [enc setTexture:_stillTex[nextPingPong] atIndex:6];
            [enc setTexture:_persistTex[nextPingPong] atIndex:7];
            [enc setTexture:_protectRaw atIndex:8];
            [enc setBuffer:_stateBuffer offset:0 atIndex:0];
            [enc setBytes:&uniforms length:sizeof(uniforms) atIndex:1];
            [enc dispatchThreadgroups:cellGroups threadsPerThreadgroup:cellThreads];

            /* 4b: Dilate by 1 cell */
            [enc setComputePipelineState:_protectDilatePipeline];
            [enc setTexture:_protectRaw atIndex:0];
            [enc setTexture:_protectMask atIndex:1];
            [enc setBytes:&uniforms length:sizeof(uniforms) atIndex:0];
            [enc dispatchThreadgroups:cellGroups threadsPerThreadgroup:cellThreads];

            [enc endEncoding];
            _pingPongIndex = nextPingPong;
            _protectNeedsReset = NO;
        }

        /* Pass 5: High / Maximum grid prediction */
        NSUInteger nextGrid = 1 - _gridIndex;
        if (gridReady) {
            /* 5a: Area-average non-linear R'G'B' into thumbnail */
            {
                id<MTLComputeCommandEncoder> enc = [commandBuffer computeCommandEncoder];
                if (enc == nil) goto failure;
                id<MTLComputePipelineState> p = isRGB ? _thumbnailRgbaPipeline : _thumbnailBiplanarPipeline;
                [enc setComputePipelineState:p];
                if (isRGB) {
                    [enc setTexture:inRGBA atIndex:0];
                    [enc setTexture:_thumbnailTex atIndex:1];
                } else {
                    [enc setTexture:inLuma atIndex:0];
                    [enc setTexture:inChroma atIndex:1];
                    [enc setTexture:_thumbnailTex atIndex:2];
                }
                [enc setBytes:&uniforms length:sizeof(uniforms) atIndex:0];
                MTLSize tGroups = MTLSizeMake((_thumbnailSize + 15) / 16, (_thumbnailSize + 15) / 16, 1);
                [enc dispatchThreadgroups:tGroups threadsPerThreadgroup:MTLSizeMake(16, 16, 1)];
                [enc endEncoding];
            }

            /* 5b: Producer prediction into gridRawBuffer */
            id<MTLCommandBuffer> continued = [_gridProducer encodeGridForThumbnail:_thumbnailTex
                                                                          intoGrid:_gridRawBuffer
                                                                     commandBuffer:commandBuffer];
            const BOOL producerOk = continued != nil;
            if (producerOk && continued != commandBuffer) {
                /* The producer's MPSCommandBuffer committed ours and went on in
                 * a new one on the same queue: carry on there. */
                committedEarlier = commandBuffer;
                commandBuffer = continued;
            }
            if (!producerOk) {
                fallback = YES;
                resolvedQuality = MACLC_SDR2HDR_BALANCED;
                uniforms.quality = (uint32_t)resolvedQuality;
            } else {
                /* 5c: Temporal EMA of 3D grid */
                id<MTLComputeCommandEncoder> enc = [commandBuffer computeCommandEncoder];
                if (enc == nil) goto failure;
                [enc setComputePipelineState:_gridEmaPipeline];
                [enc setBuffer:_gridRawBuffer offset:0 atIndex:0];
                [enc setTexture:_grid3D[_gridIndex] atIndex:0];
                [enc setTexture:_grid3D[nextGrid] atIndex:1];
                [enc setBuffer:_stateBuffer offset:0 atIndex:1];
                [enc setBytes:&uniforms length:sizeof(uniforms) atIndex:2];

                MTLSize gGroups = MTLSizeMake((_gridRawWidth + 7) / 8,
                                              (_gridRawHeight + 7) / 8,
                                              (_gridRawDepth + 3) / 4);
                [enc dispatchThreadgroups:gGroups threadsPerThreadgroup:MTLSizeMake(8, 8, 4)];
                [enc endEncoding];
                _gridIndex = nextGrid;
                _gridNeedsReset = NO;
            }
        }

        /* Pass 6: Apply pass */
        {
            id<MTLComputeCommandEncoder> enc = [commandBuffer computeCommandEncoder];
            if (enc == nil) goto failure;
            id<MTLComputePipelineState> p = isRGB ? _applyRgbaPipeline : _applyBiplanarPipeline;
            [enc setComputePipelineState:p];
            if (isRGB) {
                [enc setTexture:inRGBA atIndex:0];
                [enc setTexture:outRGBA atIndex:1];
                [enc setTexture:_guidedAB atIndex:2];
                [enc setTexture:(params->protect ? _protectMask : _dummy2DTex) atIndex:3];
                [enc setTexture:(gridReady && !fallback ? _grid3D[_gridIndex] : _dummy3DTex) atIndex:4];
            } else {
                [enc setTexture:inLuma atIndex:0];
                [enc setTexture:inChroma atIndex:1];
                [enc setTexture:outRGBA atIndex:2];
                [enc setTexture:_guidedAB atIndex:3];
                [enc setTexture:(params->protect ? _protectMask : _dummy2DTex) atIndex:4];
                [enc setTexture:(gridReady && !fallback ? _grid3D[_gridIndex] : _dummy3DTex) atIndex:5];
            }
            [enc setBytes:&uniforms length:sizeof(uniforms) atIndex:0];
            [enc setBuffer:_stateBuffer offset:0 atIndex:1];

            NSUInteger gw = 16, gh = 16;
            while (gw * gh > p.maxTotalThreadsPerThreadgroup && gh > 1)
                gh /= 2;
            [enc dispatchThreadgroups:MTLSizeMake((uniforms.width + gw - 1) / gw,
                                                 (uniforms.height + gh - 1) / gh, 1)
                threadsPerThreadgroup:MTLSizeMake(gw, gh, 1)];
            [enc endEncoding];
        }
    }

#if TARGET_OS_OSX
    if (_storageMode == MTLStorageModeManaged) {
        id<MTLBlitCommandEncoder> blit = [commandBuffer blitCommandEncoder];
        [blit synchronizeResource:outRGBA];
        [blit endEncoding];
    }
#endif

    [commandBuffer commit];
    [commandBuffer waitUntilCompleted];

    if (committedEarlier.error != nil) {
        msg_Warn(_obj, "SDR to HDR: GPU prediction failed: %s",
                 committedEarlier.error.localizedDescription.UTF8String ?: "unknown error");
        goto failure;
    }
    if (commandBuffer.error != nil) {
        msg_Warn(_obj, "SDR to HDR: GPU expansion failed: %s",
                 commandBuffer.error.localizedDescription.UTF8String ?: "unknown error");
        goto failure;
    }

    double gpuTime = (commandBuffer.GPUEndTime - commandBuffer.GPUStartTime) * 1000.0;
    if (committedEarlier != nil)
        gpuTime += (committedEarlier.GPUEndTime - committedEarlier.GPUStartTime) * 1000.0;
    if (gpuTime < 0.0) gpuTime = 0.0;
    _lastGPUTimeMs = gpuTime;

    float budget = 1.0f;
    float area = 0.0f;
    if (resolvedQuality == MACLC_SDR2HDR_FAST) {
        budget = P_rel;
        _lastPeakNits = 100.0f * P;
    } else {
        VLCHDRExpandState *st = (VLCHDRExpandState *)_stateBuffer.contents;
        budget = st->budget;
        area = st->A_f;
        _lastPeakNits = 100.0f * W * budget;
    }

    if (_lastLoggedQuality != (int)resolvedQuality) {
        msg_Dbg(_obj, "SDR to HDR: %s, white %.2f, budget %.2f (area %.3f), peak %.0f cd/m2, %.2f ms GPU",
                maclc_sdr2hdr_quality_name(resolvedQuality), W, budget, area, _lastPeakNits, _lastGPUTimeMs);
        _lastLoggedQuality = (int)resolvedQuality;
    }

    _lastQuality = resolvedQuality;
    _lastFallback = fallback;

    CVBufferSetAttachment(output, kCVImageBufferColorPrimariesKey,
                          kCVImageBufferColorPrimaries_ITU_R_2020,
                          kCVAttachmentMode_ShouldPropagate);
    CVBufferSetAttachment(output, kCVImageBufferTransferFunctionKey,
                          kCVImageBufferTransferFunction_Linear,
                          kCVAttachmentMode_ShouldPropagate);

    return output;

failure:
    CVPixelBufferRelease(output);
    return NULL;
}

@end
