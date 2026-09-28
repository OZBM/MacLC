/*****************************************************************************
 * MacLCMetalRenderer.m: Metal GPU pipeline for video and subpictures
 *****************************************************************************
 * Copyright (C) 2026 Hazen Studio
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

#import "MacLCMetalRenderer.h"
#import "MacLCMetalScaler.h"
#import "MacLCMetal360.h"
#import "MacLCMetalLUT.h"
#import <CoreGraphics/CoreGraphics.h>

#define VLC_CVPX_FORMAT_P010 ((OSType)'x420')
#define VLC_CVPX_FORMAT_P010_FULL ((OSType)'xf20')
#define VLC_CVPX_FORMAT_RGBA_HALF ((OSType)'RGhA')
#define VLC_HDR_10BIT_READ_SCALE (65535.0f / 65472.0f)

enum vlc_metal_matrix
{
    VLC_METAL_MATRIX_BT709 = 0,
    VLC_METAL_MATRIX_BT601 = 1,
    VLC_METAL_MATRIX_BT2020 = 2,
};

enum vlc_metal_transfer
{
    VLC_METAL_TRANSFER_POWER = 0,
    VLC_METAL_TRANSFER_BT709_OETF = 1,
};

typedef struct
{
    float gamut[12];       /* three float4 rows, only .xyz is read */
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
    float _pad[2];         /* 16-byte alignment (96 bytes total) */
} MacLCDecodeUniforms;

_Static_assert(sizeof(MacLCDecodeUniforms) == 96,
               "MacLCDecodeUniforms must keep the layout of the Metal struct");

typedef struct
{
    float quadRect[4];     /* x, y, width, height in pixels (top-left origin) */
    float cropRect[4];     /* u_min, v_min, u_span, v_span */
    float viewportSize[4]; /* width, height, 0, 0 */
    float orientation[8];  /* two float4 rows for 2x3 affine matrix */
    float headroom;
    uint32_t isEDR;
    uint32_t gamutMode;    /* gl-gamut-mapping value, see maclc_gamut_map() */
    float _pad;
} VideoQuadUniforms;

_Static_assert(sizeof(VideoQuadUniforms) == 96,
               "VideoQuadUniforms must keep the layout of the Metal struct");

typedef struct
{
    float quadRect[4];     /* x, y, width, height in pixels */
    float texRect[4];      /* u_min, v_min, u_max, v_max */
    float viewportSize[4]; /* width, height, 0, 0 */
    float alpha;
    float _pad[3];
} SubpicUniforms;

_Static_assert(sizeof(SubpicUniforms) == 64,
               "SubpicUniforms must keep the layout of the Metal struct");

/* Linear RGB -> linear BT.2020 RGB tables */
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

static inline uint32_t NextPowerOfTwo(uint32_t v)
{
    if (v == 0) return 1;
    v--;
    v |= v >> 1;
    v |= v >> 2;
    v |= v >> 4;
    v |= v >> 8;
    v |= v >> 16;
    return v + 1;
}

static void InitOrientationMatrix(float out[8], video_orientation_t orientation)
{
    float c00 = 1.0f, c01 = 0.0f, c02 = 0.0f;
    float c10 = 0.0f, c11 = 1.0f, c12 = 0.0f;

    switch (orientation) {
        case ORIENT_ROTATED_90:
            c00 = 0.0f;  c01 = -1.0f; c02 = 1.0f;
            c10 = 1.0f;  c11 =  0.0f; c12 = 0.0f;
            break;
        case ORIENT_ROTATED_180:
            c00 = -1.0f; c01 =  0.0f; c02 = 1.0f;
            c10 =  0.0f; c11 = -1.0f; c12 = 1.0f;
            break;
        case ORIENT_ROTATED_270:
            c00 =  0.0f; c01 =  1.0f; c02 = 0.0f;
            c10 = -1.0f; c11 =  0.0f; c12 = 1.0f;
            break;
        case ORIENT_HFLIPPED:
            c00 = -1.0f; c01 =  0.0f; c02 = 1.0f;
            c10 =  0.0f; c11 =  1.0f; c12 = 0.0f;
            break;
        case ORIENT_VFLIPPED:
            c00 =  1.0f; c01 =  0.0f; c02 = 0.0f;
            c10 =  0.0f; c11 = -1.0f; c12 = 1.0f;
            break;
        case ORIENT_TRANSPOSED:
            c00 =  0.0f; c01 = -1.0f; c02 = 1.0f;
            c10 = -1.0f; c11 =  0.0f; c12 = 1.0f;
            break;
        case ORIENT_ANTI_TRANSPOSED:
            c00 = 0.0f;  c01 = 1.0f;  c02 = 0.0f;
            c10 = 1.0f;  c11 = 0.0f;  c12 = 0.0f;
            break;
        case ORIENT_NORMAL:
        default:
            c00 = 1.0f; c01 = 0.0f; c02 = 0.0f;
            c10 = 0.0f; c11 = 1.0f; c12 = 0.0f;
            break;
    }

    out[0] = c00; out[1] = c01; out[2] = c02; out[3] = 0.0f;
    out[4] = c10; out[5] = c11; out[6] = c12; out[7] = 0.0f;
}

static void FillSourceColorimetry(MacLCDecodeUniforms *uniforms,
                                  const video_format_t *fmt,
                                  BOOL isRGB)
{
    switch (fmt->space) {
        case COLOR_SPACE_BT601:  uniforms->matrix = VLC_METAL_MATRIX_BT601;  break;
        case COLOR_SPACE_BT2020: uniforms->matrix = VLC_METAL_MATRIX_BT2020; break;
        default:                 uniforms->matrix = VLC_METAL_MATRIX_BT709;  break;
    }

    uniforms->transferMode = VLC_METAL_TRANSFER_POWER;
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
                uniforms->transferMode = VLC_METAL_TRANSFER_BT709_OETF;
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

    if (isRGB)
        uniforms->matrix = VLC_METAL_MATRIX_BT709;
}

#pragma mark - Shaders Source

static NSString * const kMacLCMetalShaderSource =
    @"#include <metal_stdlib>\n"
    @"using namespace metal;\n"
    @"\n"
    @"struct MacLCDecodeUniforms {\n"
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
    @"    float2 _pad;\n"
    @"};\n"
    @"\n"
    @"static inline float3 ycbcr_to_rgb(float3 ycc, constant MacLCDecodeUniforms &u)\n"
    @"{\n"
    @"    float y  = (ycc.x - u.lumaOffset) * u.lumaScale;\n"
    @"    float cb = (ycc.y - u.chromaOffset) * u.chromaScale;\n"
    @"    float cr = (ycc.z - u.chromaOffset) * u.chromaScale;\n"
    @"\n"
    @"    float kr = 0.2126f, kb = 0.0722f;\n"
    @"    if (u.matrix == 1u) { kr = 0.299f;  kb = 0.114f;  }\n"
    @"    if (u.matrix == 2u) { kr = 0.2627f; kb = 0.0593f; }\n"
    @"    float kg = 1.0f - kr - kb;\n"
    @"\n"
    @"    float r = y + 2.0f * (1.0f - kr) * cr;\n"
    @"    float b = y + 2.0f * (1.0f - kb) * cb;\n"
    @"    float g = (y - kr * r - kb * b) / kg;\n"
    @"    return float3(r, g, b);\n"
    @"}\n"
    @"\n"
    @"static inline float eotf_channel(float v, constant MacLCDecodeUniforms &u)\n"
    @"{\n"
    @"    float a = fabs(v);\n"
    @"    float s = (v < 0.0f) ? -1.0f : 1.0f;\n"
    @"    if (u.transferMode == 1u)\n"
    @"        return s * ((a < 0.081f) ? (a / 4.5f)\n"
    @"                                 : pow((a + 0.099f) / 1.099f, 1.0f / 0.45f));\n"
    @"    return s * pow(a, u.gamma);\n"
    @"}\n"
    @"\n"
    @"kernel void vlc_metal_decode_biplanar(\n"
    @"    texture2d<float, access::read>   inLuma   [[texture(0)]],\n"
    @"    texture2d<float, access::sample> inChroma [[texture(1)]],\n"
    @"    texture2d<float, access::write>  outRGBA  [[texture(2)]],\n"
    @"    constant MacLCDecodeUniforms&    u        [[buffer(0)]],\n"
    @"    uint2 gid [[thread_position_in_grid]])\n"
    @"{\n"
    @"    if (gid.x >= u.width || gid.y >= u.height)\n"
    @"        return;\n"
    @"\n"
    @"    constexpr sampler bilinear(coord::normalized, address::clamp_to_edge,\n"
    @"                               filter::linear);\n"
    @"    float y = inLuma.read(gid).r * u.inputScale;\n"
    @"    float2 pos = float2((float(gid.x) * 0.5f + 0.5f) / float(inChroma.get_width()),\n"
    @"                        (float(gid.y) * 0.5f + 0.25f) / float(inChroma.get_height()));\n"
    @"    float2 cc = inChroma.sample(bilinear, pos).rg * u.inputScale;\n"
    @"\n"
    @"    float3 ycc = float3(y, cc.x, cc.y);\n"
    @"    float3 nonLinear = ycbcr_to_rgb(ycc, u);\n"
    @"    float3 lin = float3(eotf_channel(nonLinear.r, u),\n"
    @"                        eotf_channel(nonLinear.g, u),\n"
    @"                        eotf_channel(nonLinear.b, u));\n"
    @"    float3 wide = float3(dot(u.gamut[0].xyz, lin),\n"
    @"                         dot(u.gamut[1].xyz, lin),\n"
    @"                         dot(u.gamut[2].xyz, lin));\n"
    @"    outRGBA.write(float4(max(wide, 0.0f), 1.0f), gid);\n"
    @"}\n"
    @"\n"
    @"kernel void vlc_metal_decode_bgra(\n"
    @"    texture2d<float, access::read>  inRGBA  [[texture(0)]],\n"
    @"    texture2d<float, access::write> outRGBA [[texture(1)]],\n"
    @"    constant MacLCDecodeUniforms&   u       [[buffer(0)]],\n"
    @"    uint2 gid [[thread_position_in_grid]])\n"
    @"{\n"
    @"    if (gid.x >= u.width || gid.y >= u.height)\n"
    @"        return;\n"
    @"\n"
    @"    float4 c = inRGBA.read(gid);\n"
    @"    float3 nonLinear = c.rgb;\n"
    @"    float3 lin = float3(eotf_channel(nonLinear.r, u),\n"
    @"                        eotf_channel(nonLinear.g, u),\n"
    @"                        eotf_channel(nonLinear.b, u));\n"
    @"    float3 wide = float3(dot(u.gamut[0].xyz, lin),\n"
    @"                         dot(u.gamut[1].xyz, lin),\n"
    @"                         dot(u.gamut[2].xyz, lin));\n"
    @"    outRGBA.write(float4(max(wide, 0.0f), 1.0f), gid);\n"
    @"}\n"
    @"\n"
    @"struct VideoQuadUniforms {\n"
    @"    float4 quadRect;\n"
    @"    float4 cropRect;\n"
    @"    float4 viewportSize;\n"
    @"    float4 orientation[2];\n"
    @"    float  headroom;\n"
    @"    uint   isEDR;\n"
    @"    uint   gamutMode;\n"
    @"    float  _pad;\n"
    @"};\n"
    @"\n"
    @"struct VertexOut {\n"
    @"    float4 position [[position]];\n"
    @"    float2 texCoord;\n"
    @"};\n"
    @"\n"
    @"vertex VertexOut vlc_metal_video_quad_vertex(\n"
    @"    uint vid [[vertex_id]],\n"
    @"    constant VideoQuadUniforms &u [[buffer(0)]])\n"
    @"{\n"
    @"    float2 normCoord = float2((vid >= 2) ? 1.0f : 0.0f,\n"
    @"                              (vid & 1) ? 1.0f : 0.0f);\n"
    @"    float2 pixelPos = u.quadRect.xy + normCoord * u.quadRect.zw;\n"
    @"    float ndcX = (2.0f * pixelPos.x / u.viewportSize.x) - 1.0f;\n"
    @"    float ndcY = 1.0f - (2.0f * pixelPos.y / u.viewportSize.y);\n"
    @"\n"
    @"    float tx = u.orientation[0].x * normCoord.x + u.orientation[0].y * normCoord.y + u.orientation[0].z;\n"
    @"    float ty = u.orientation[1].x * normCoord.x + u.orientation[1].y * normCoord.y + u.orientation[1].z;\n"
    @"    float2 finalTexCoord = u.cropRect.xy + float2(tx, ty) * u.cropRect.zw;\n"
    @"\n"
    @"    VertexOut out;\n"
    @"    out.position = float4(ndcX, ndcY, 0.0f, 1.0f);\n"
    @"    out.texCoord = finalTexCoord;\n"
    @"    return out;\n"
    @"}\n"
    @"\n"
    @"/* Gamut mapping of BT.2020 light into Display P3 (gl-gamut-mapping), per\n"
    @" * pixel. libplacebo (gamut_mapping.c) works in ICh through a 3D table;\n"
    @" * here every mode moves colours along the line to the grey of the same\n"
    @" * luminance, which keeps luminance and dominant wavelength:\n"
    @" * 0 Auto and 2 Perceptual compress the outer fifth of the gamut and what\n"
    @" *   lies beyond it smoothly onto the boundary (libplacebo's default is\n"
    @" *   perceptual too);\n"
    @" * 1 Clip clamps each channel;\n"
    @" * 3 Relative, 5 Absolute (same D65 white) and 6 Desaturate desaturate\n"
    @" *   out-of-gamut colours onto the boundary (libplacebo's relative mode\n"
    @" *   also trades some lightness, not reproduced);\n"
    @" * 4 Saturation shows BT.2020 values as P3 values;\n"
    @" * 7 Darken scales by 1/1.3436 (the most any BT.2020 primary or secondary\n"
    @" *   exceeds P3), then desaturates;\n"
    @" * 8 Warn shows out-of-gamut pixels in their complementary colour;\n"
    @" * 9 Linear scales all chroma by 0.82, an estimate of libplacebo's\n"
    @" *   hue-independent gain for BT.2020 to P3 (computed there in ICh). */\n"
    @"constant float3 kP3Luma = float3(0.228975f, 0.691739f, 0.079287f);\n"
    @"\n"
    @"/* How far along the line from grey Y to c the gamut [0, peak]^3 reaches:\n"
    @" * > 1 inside, 1 on the boundary, < 1 outside. */\n"
    @"static inline float gamut_reach(float3 c, float Y, float peak)\n"
    @"{\n"
    @"    float t = 1e6f;\n"
    @"    for (int i = 0; i < 3; i++) {\n"
    @"        float d = c[i] - Y;\n"
    @"        if (d < -1e-7f) t = min(t, Y / -d);\n"
    @"        else if (d > 1e-7f) t = min(t, (peak - Y) / d);\n"
    @"    }\n"
    @"    return max(t, 0.0f);\n"
    @"}\n"
    @"\n"
    @"static inline float3 maclc_gamut_map(float3 c, uint mode, float peak)\n"
    @"{\n"
    @"    if (mode == 1u || mode == 4u)\n"
    @"        return clamp(c, 0.0f, peak);\n"
    @"    if (mode == 7u)\n"
    @"        c *= 0.7443f;\n"
    @"    float Y = clamp(dot(c, kP3Luma), 0.0f, peak);\n"
    @"    if (mode == 9u)\n"
    @"        c = Y + (c - Y) * 0.82f;\n"
    @"    float reach = gamut_reach(c, Y, peak);\n"
    @"    if (mode == 8u) {\n"
    @"        if (reach < 1.0f)\n"
    @"            c = Y + (Y - c) * 1.2f;\n"
    @"    } else if (mode == 0u || mode == 2u) {\n"
    @"        const float k = 0.8f;\n"
    @"        float s = 1.0f / max(reach, 1e-6f);\n"
    @"        if (s > k) {\n"
    @"            float sm = k + (1.0f - k) * (1.0f - exp(-(s - k) / (1.0f - k)));\n"
    @"            c = Y + (c - Y) * (sm / s);\n"
    @"        }\n"
    @"    } else if (reach < 1.0f) {\n"
    @"        c = Y + (c - Y) * reach;\n"
    @"    }\n"
    @"    return clamp(c, 0.0f, peak);\n"
    @"}\n"
    @"\n"
    @"fragment float4 vlc_metal_video_quad_fragment(\n"
    @"    VertexOut in [[stage_in]],\n"
    @"    texture2d<float, access::sample> videoTex [[texture(0)]],\n"
    @"    sampler s [[sampler(0)]],\n"
    @"    constant VideoQuadUniforms &u [[buffer(0)]])\n"
    @"{\n"
    @"    float4 rgb2020 = videoTex.sample(s, in.texCoord);\n"
    @"\n"
    @"    const float3x3 kBT2020ToDisplayP3 = float3x3(\n"
    @"        float3( 1.343585f, -0.065298f,  0.002822f),\n"
    @"        float3(-0.282180f,  1.075788f, -0.019597f),\n"
    @"        float3(-0.061405f, -0.010490f,  1.016775f)\n"
    @"    );\n"
    @"\n"
    @"    float3 p3 = (u.gamutMode == 4u) ? rgb2020.rgb : kBT2020ToDisplayP3 * rgb2020.rgb;\n"
    @"    float maxLimit = (u.isEDR != 0u) ? u.headroom : 1.0f;\n"
    @"    return float4(maclc_gamut_map(p3, u.gamutMode, maxLimit), 1.0f);\n"
    @"}\n"
    @"\n"
    @"fragment float4 vlc_metal_copy_fragment(\n"
    @"    VertexOut in [[stage_in]],\n"
    @"    texture2d<float, access::sample> tex [[texture(0)]],\n"
    @"    sampler s [[sampler(0)]])\n"
    @"{\n"
    @"    return tex.sample(s, in.texCoord);\n"
    @"}\n"
    @"\n"
    @"struct SubpicUniforms {\n"
    @"    float4 quadRect;\n"
    @"    float4 texRect;\n"
    @"    float4 viewportSize;\n"
    @"    float  alpha;\n"
    @"    float3 _pad;\n"
    @"};\n"
    @"\n"
    @"vertex VertexOut vlc_metal_subpic_vertex(\n"
    @"    uint vid [[vertex_id]],\n"
    @"    constant SubpicUniforms &u [[buffer(0)]])\n"
    @"{\n"
    @"    float2 normCoord = float2((vid >= 2) ? 1.0f : 0.0f,\n"
    @"                              (vid & 1) ? 1.0f : 0.0f);\n"
    @"    float2 pixelPos = u.quadRect.xy + normCoord * u.quadRect.zw;\n"
    @"    float ndcX = (2.0f * pixelPos.x / u.viewportSize.x) - 1.0f;\n"
    @"    float ndcY = 1.0f - (2.0f * pixelPos.y / u.viewportSize.y);\n"
    @"    float2 texCoord = u.texRect.xy + normCoord * (u.texRect.zw - u.texRect.xy);\n"
    @"\n"
    @"    VertexOut out;\n"
    @"    out.position = float4(ndcX, ndcY, 0.0f, 1.0f);\n"
    @"    out.texCoord = texCoord;\n"
    @"    return out;\n"
    @"}\n"
    @"\n"
    @"fragment float4 vlc_metal_subpic_fragment(\n"
    @"    VertexOut in [[stage_in]],\n"
    @"    texture2d<float, access::sample> subpicTex [[texture(0)]],\n"
    @"    sampler s [[sampler(0)]],\n"
    @"    constant SubpicUniforms &u [[buffer(0)]])\n"
    @"{\n"
    @"    float4 srgb = subpicTex.sample(s, in.texCoord);\n"
    @"\n"
    @"    const float3x3 kSRGBToDisplayP3 = float3x3(\n"
    @"        float3(0.822462f, 0.033194f, 0.017083f),\n"
    @"        float3(0.177538f, 0.966806f, 0.072397f),\n"
    @"        float3(0.000000f, 0.000000f, 0.910520f)\n"
    @"    );\n"
    @"\n"
    @"    float3 lin = float3(\n"
    @"        (srgb.r <= 0.04045f) ? (srgb.r / 12.92f) : pow((srgb.r + 0.055f) / 1.055f, 2.4f),\n"
    @"        (srgb.g <= 0.04045f) ? (srgb.g / 12.92f) : pow((srgb.g + 0.055f) / 1.055f, 2.4f),\n"
    @"        (srgb.b <= 0.04045f) ? (srgb.b / 12.92f) : pow((srgb.b + 0.055f) / 1.055f, 2.4f)\n"
    @"    );\n"
    @"\n"
    @"    float3 p3 = clamp(kSRGBToDisplayP3 * lin, 0.0f, 1.0f);\n"
    @"    float a = srgb.a * u.alpha;\n"
    @"    return float4(p3 * a, a);\n"
    @"}\n";

#pragma mark - Subpicture Region Container

@interface MetalSubpicRegion : NSObject
@property (nonatomic) CGRect place;
@property (nonatomic) float alpha;
@property (nonatomic) id<MTLTexture> texture;
@property (nonatomic) float uMax;
@property (nonatomic) float vMax;
@end

@implementation MetalSubpicRegion
@end

#pragma mark - Renderer Implementation

@implementation MacLCMetalRenderer {
    id<MTLDevice> _device;
    id<MTLCommandQueue> _queue;
    CVMetalTextureCacheRef _textureCache;

    id<MTLComputePipelineState> _biplanarDecodePSO;
    id<MTLComputePipelineState> _bgraDecodePSO;
    id<MTLRenderPipelineState> _videoQuadPSO;
    id<MTLRenderPipelineState> _subpicPSO;
    id<MTLRenderPipelineState> _copyPSO;
    /* Intermediates of the optional stages, drawable-sized, reused. */
    id<MTLTexture> _composeTexture;   /* scaled or projected picture, BT.2020 */
    id<MTLTexture> _outputTexture;    /* finished picture, for the LUT */
    id<MTLSamplerState> _samplerLinear;

    id<MTLTexture> _cachedStageATexture;

    NSMutableArray<MetalSubpicRegion *> *_activeSubpicRegions;
    NSMutableArray<id<MTLTexture>> *_subpicTexturePool;

    id<MTLCommandBuffer> _lastCommandBuffer;
    /* CVMetalTextures of pictures stage A wrapped for Display to draw */
    NSMutableArray *_displayHeldTextures;
}

@synthesize device = _device;
@synthesize commandQueue = _queue;
@synthesize textureCache = _textureCache;

- (nullable instancetype)initWithDevice:(id<MTLDevice>)device
{
    self = [super init];
    if (self == nil || device == nil)
        return nil;

    _device = device;
    _queue = [_device newCommandQueue];
    if (_queue == nil)
        return nil;

    _displayHeldTextures = [NSMutableArray array];
    CVReturn cvRet = CVMetalTextureCacheCreate(kCFAllocatorDefault, NULL, _device, NULL, &_textureCache);
    if (cvRet != kCVReturnSuccess || _textureCache == NULL)
        return nil;

    NSError *error = nil;
    id<MTLLibrary> library = [_device newLibraryWithSource:kMacLCMetalShaderSource options:nil error:&error];
    if (library == nil) {
        NSLog(@"MacLC Metal output: shader compilation failed: %@", error.localizedDescription);
        return nil;
    }

    id<MTLFunction> biplanarFunc = [library newFunctionWithName:@"vlc_metal_decode_biplanar"];
    id<MTLFunction> bgraFunc = [library newFunctionWithName:@"vlc_metal_decode_bgra"];
    if (biplanarFunc == nil || bgraFunc == nil)
        return nil;

    _biplanarDecodePSO = [_device newComputePipelineStateWithFunction:biplanarFunc error:&error];
    _bgraDecodePSO = [_device newComputePipelineStateWithFunction:bgraFunc error:&error];
    if (_biplanarDecodePSO == nil || _bgraDecodePSO == nil)
        return nil;

    id<MTLFunction> vqVertexFunc = [library newFunctionWithName:@"vlc_metal_video_quad_vertex"];
    id<MTLFunction> vqFragFunc = [library newFunctionWithName:@"vlc_metal_video_quad_fragment"];
    if (vqVertexFunc == nil || vqFragFunc == nil)
        return nil;

    MTLRenderPipelineDescriptor *vqDesc = [[MTLRenderPipelineDescriptor alloc] init];
    vqDesc.vertexFunction = vqVertexFunc;
    vqDesc.fragmentFunction = vqFragFunc;
    vqDesc.colorAttachments[0].pixelFormat = MTLPixelFormatRGBA16Float;
    _videoQuadPSO = [_device newRenderPipelineStateWithDescriptor:vqDesc error:&error];
    if (_videoQuadPSO == nil)
        return nil;

    id<MTLFunction> spVertexFunc = [library newFunctionWithName:@"vlc_metal_subpic_vertex"];
    id<MTLFunction> spFragFunc = [library newFunctionWithName:@"vlc_metal_subpic_fragment"];
    if (spVertexFunc == nil || spFragFunc == nil)
        return nil;

    MTLRenderPipelineDescriptor *spDesc = [[MTLRenderPipelineDescriptor alloc] init];
    spDesc.vertexFunction = spVertexFunc;
    spDesc.fragmentFunction = spFragFunc;
    spDesc.colorAttachments[0].pixelFormat = MTLPixelFormatRGBA16Float;
    spDesc.colorAttachments[0].blendingEnabled = YES;
    spDesc.colorAttachments[0].rgbBlendOperation = MTLBlendOperationAdd;
    spDesc.colorAttachments[0].alphaBlendOperation = MTLBlendOperationAdd;
    spDesc.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorOne;
    spDesc.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    spDesc.colorAttachments[0].sourceAlphaBlendFactor = MTLBlendFactorOne;
    spDesc.colorAttachments[0].destinationAlphaBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    _subpicPSO = [_device newRenderPipelineStateWithDescriptor:spDesc error:&error];
    if (_subpicPSO == nil)
        return nil;

    id<MTLFunction> copyFunc = [library newFunctionWithName:@"vlc_metal_copy_fragment"];
    if (copyFunc == nil)
        return nil;
    MTLRenderPipelineDescriptor *cpDesc = [[MTLRenderPipelineDescriptor alloc] init];
    cpDesc.vertexFunction = vqVertexFunc;
    cpDesc.fragmentFunction = copyFunc;
    cpDesc.colorAttachments[0].pixelFormat = MTLPixelFormatRGBA16Float;
    _copyPSO = [_device newRenderPipelineStateWithDescriptor:cpDesc error:&error];
    if (_copyPSO == nil)
        return nil;

    MTLSamplerDescriptor *sDesc = [[MTLSamplerDescriptor alloc] init];
    sDesc.minFilter = MTLSamplerMinMagFilterLinear;
    sDesc.magFilter = MTLSamplerMinMagFilterLinear;
    sDesc.sAddressMode = MTLSamplerAddressModeClampToEdge;
    sDesc.tAddressMode = MTLSamplerAddressModeClampToEdge;
    _samplerLinear = [_device newSamplerStateWithDescriptor:sDesc];

    _activeSubpicRegions = [[NSMutableArray alloc] init];
    _subpicTexturePool = [[NSMutableArray alloc] init];

    return self;
}

- (id<MTLCommandBuffer>)createCommandBuffer
{
    return [_queue commandBuffer];
}

- (nullable id<MTLTexture>)textureFromPixelBuffer:(CVPixelBufferRef)pixelBuffer
                                            plane:(size_t)plane
                                      pixelFormat:(MTLPixelFormat)pixelFormat
                                            width:(size_t)width
                                           height:(size_t)height
                                    commandBuffer:(id<MTLCommandBuffer>)commandBuffer
{
    CVMetalTextureRef cvTexture = NULL;
    CVReturn err = CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault,
                                                            _textureCache,
                                                            pixelBuffer,
                                                            NULL,
                                                            pixelFormat,
                                                            width,
                                                            height,
                                                            plane,
                                                            &cvTexture);
    if (err != kCVReturnSuccess || cvTexture == NULL)
        return nil;

    id<MTLTexture> texture = CVMetalTextureGetTexture(cvTexture);
    [commandBuffer addCompletedHandler:^(id<MTLCommandBuffer> cb) {
        VLC_UNUSED(cb);
        CFRelease(cvTexture);
    }];
    return texture;
}

- (nullable id<MTLTexture>)textureFromRGBAHalfBuffer:(CVPixelBufferRef)pixelBuffer
                                      commandBuffer:(id<MTLCommandBuffer>)commandBuffer
{
    VLC_UNUSED(commandBuffer);
    /* This texture is the picture Display draws, after stage A: its
     * CVMetalTexture must outlive the frame's render command buffer, not
     * just stage A's, or the cache may hand its binding to another buffer
     * while the GPU still reads it. Held until the next render completes. */
    CVMetalTextureRef cvTexture = NULL;
    CVReturn err = CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, _textureCache,
                                                             pixelBuffer, NULL,
                                                             MTLPixelFormatRGBA16Float,
                                                             CVPixelBufferGetWidth(pixelBuffer),
                                                             CVPixelBufferGetHeight(pixelBuffer),
                                                             0, &cvTexture);
    if (err != kCVReturnSuccess || cvTexture == NULL)
        return nil;
    [_displayHeldTextures addObject:(__bridge_transfer id)cvTexture];
    return CVMetalTextureGetTexture(cvTexture);
}

- (nullable id<MTLTexture>)decodeSourceBuffer:(CVPixelBufferRef)pixelBuffer
                                       format:(const video_format_t *)fmt
                                commandBuffer:(id<MTLCommandBuffer>)commandBuffer
{
    if (pixelBuffer == NULL || fmt == NULL || commandBuffer == nil)
        return nil;

    const OSType sourceFormat = CVPixelBufferGetPixelFormatType(pixelBuffer);
    const size_t width = CVPixelBufferGetWidth(pixelBuffer);
    const size_t height = CVPixelBufferGetHeight(pixelBuffer);
    if (width == 0 || height == 0)
        return nil;

    BOOL isRGB = (sourceFormat == kCVPixelFormatType_32BGRA);
    BOOL is10Bit = (sourceFormat == VLC_CVPX_FORMAT_P010 || sourceFormat == VLC_CVPX_FORMAT_P010_FULL);

    /* Allocate or reuse the intermediate RGBA16Float stage A texture */
    if (_cachedStageATexture == nil ||
        _cachedStageATexture.width != width ||
        _cachedStageATexture.height != height) {
        MTLTextureDescriptor *desc = [MTLTextureDescriptor
            texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA16Float
                                         width:width
                                        height:height
                                     mipmapped:NO];
        desc.usage = MTLTextureUsageShaderRead | MTLTextureUsageShaderWrite;
        desc.storageMode = MTLStorageModePrivate;
        _cachedStageATexture = [_device newTextureWithDescriptor:desc];
    }
    if (_cachedStageATexture == nil)
        return nil;

    MacLCDecodeUniforms uniforms;
    memset(&uniforms, 0, sizeof(uniforms));
    uniforms.inputScale = is10Bit ? VLC_HDR_10BIT_READ_SCALE : 1.0f;

    switch (sourceFormat) {
        case kCVPixelFormatType_420YpCbCr8BiPlanarFullRange:
            uniforms.lumaOffset = 0.0f;
            uniforms.lumaScale = 1.0f;
            uniforms.chromaOffset = 128.0f / 255.0f;
            uniforms.chromaScale = 1.0f;
            break;
        case VLC_CVPX_FORMAT_P010_FULL:
            uniforms.lumaOffset = 0.0f;
            uniforms.lumaScale = 1.0f;
            uniforms.chromaOffset = 512.0f / 1023.0f;
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
        default: /* kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange */
            uniforms.lumaOffset = 16.0f / 255.0f;
            uniforms.lumaScale = 255.0f / 219.0f;
            uniforms.chromaOffset = 128.0f / 255.0f;
            uniforms.chromaScale = 255.0f / 224.0f;
            break;
    }

    FillSourceColorimetry(&uniforms, fmt, isRGB);
    uniforms.width = (uint32_t)width;
    uniforms.height = (uint32_t)height;

    id<MTLComputeCommandEncoder> encoder = [commandBuffer computeCommandEncoder];
    if (encoder == nil)
        return nil;

    if (isRGB) {
        id<MTLTexture> inTexture = [self textureFromPixelBuffer:pixelBuffer
                                                         plane:0
                                                   pixelFormat:MTLPixelFormatBGRA8Unorm
                                                         width:width
                                                        height:height
                                                 commandBuffer:commandBuffer];
        if (inTexture == nil) {
            [encoder endEncoding];
            return nil;
        }

        [encoder setComputePipelineState:_bgraDecodePSO];
        [encoder setTexture:inTexture atIndex:0];
        [encoder setTexture:_cachedStageATexture atIndex:1];
        [encoder setBytes:&uniforms length:sizeof(uniforms) atIndex:0];
    } else {
        MTLPixelFormat lumaFmt = is10Bit ? MTLPixelFormatR16Unorm : MTLPixelFormatR8Unorm;
        MTLPixelFormat chromaFmt = is10Bit ? MTLPixelFormatRG16Unorm : MTLPixelFormatRG8Unorm;
        size_t cWidth = CVPixelBufferGetWidthOfPlane(pixelBuffer, 1);
        size_t cHeight = CVPixelBufferGetHeightOfPlane(pixelBuffer, 1);

        id<MTLTexture> lumaTex = [self textureFromPixelBuffer:pixelBuffer
                                                        plane:0
                                                  pixelFormat:lumaFmt
                                                        width:width
                                                       height:height
                                                commandBuffer:commandBuffer];
        id<MTLTexture> chromaTex = [self textureFromPixelBuffer:pixelBuffer
                                                          plane:1
                                                    pixelFormat:chromaFmt
                                                          width:cWidth
                                                         height:cHeight
                                                  commandBuffer:commandBuffer];
        if (lumaTex == nil || chromaTex == nil) {
            [encoder endEncoding];
            return nil;
        }

        [encoder setComputePipelineState:_biplanarDecodePSO];
        [encoder setTexture:lumaTex atIndex:0];
        [encoder setTexture:chromaTex atIndex:1];
        [encoder setTexture:_cachedStageATexture atIndex:2];
        [encoder setBytes:&uniforms length:sizeof(uniforms) atIndex:0];
    }

    MTLSize threadgroupSize = MTLSizeMake(16, 16, 1);
    MTLSize threadgroups = MTLSizeMake((width + 15) / 16, (height + 15) / 16, 1);
    [encoder dispatchThreadgroups:threadgroups threadsPerThreadgroup:threadgroupSize];
    [encoder endEncoding];

    return _cachedStageATexture;
}

#pragma mark - Subpictures

- (void)updateSubpicture:(nullable const struct vlc_render_subpicture *)subpicture
             outputWidth:(unsigned)outWidth
            outputHeight:(unsigned)outHeight
{
    VLC_UNUSED(outWidth); VLC_UNUSED(outHeight);

    /* Move existing active textures to the pool for reuse */
    for (MetalSubpicRegion *reg in _activeSubpicRegions) {
        if (reg.texture != nil)
            [_subpicTexturePool addObject:reg.texture];
    }
    [_activeSubpicRegions removeAllObjects];

    if (subpicture == NULL || subpicture->regions.size == 0)
        return;

    const struct subpicture_region_rendered *r;
    vlc_vector_foreach(r, &subpicture->regions) {
        if (r == NULL || r->p_picture == NULL)
            continue;

        unsigned visW = r->p_picture->format.i_visible_width;
        unsigned visH = r->p_picture->format.i_visible_height;
        if (visW == 0 || visH == 0)
            continue;

        uint32_t texW = NextPowerOfTwo(visW);
        uint32_t texH = NextPowerOfTwo(visH);

        id<MTLTexture> regionTex = nil;
        for (NSUInteger i = 0; i < _subpicTexturePool.count; ++i) {
            id<MTLTexture> t = _subpicTexturePool[i];
            if (t.width == texW && t.height == texH) {
                regionTex = t;
                [_subpicTexturePool removeObjectAtIndex:i];
                break;
            }
        }

        if (regionTex == nil) {
            MTLTextureDescriptor *tDesc = [MTLTextureDescriptor
                texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm
                                             width:texW
                                            height:texH
                                         mipmapped:NO];
            tDesc.usage = MTLTextureUsageShaderRead;
            tDesc.storageMode = MTLStorageModeManaged;
            regionTex = [_device newTextureWithDescriptor:tDesc];
        }

        if (regionTex == nil)
            continue;

        size_t pixelOffset = r->p_picture->format.i_y_offset * r->p_picture->p[0].i_pitch +
                             r->p_picture->format.i_x_offset * r->p_picture->p[0].i_pixel_pitch;
        const uint8_t *srcBytes = r->p_picture->p[0].p_pixels + pixelOffset;

        [regionTex replaceRegion:MTLRegionMake2D(0, 0, visW, visH)
                     mipmapLevel:0
                       withBytes:srcBytes
                     bytesPerRow:r->p_picture->p[0].i_pitch];

        MetalSubpicRegion *region = [[MetalSubpicRegion alloc] init];
        region.place = CGRectMake(r->place.x, r->place.y, r->place.width, r->place.height);
        region.alpha = (float)r->i_alpha / 255.0f;
        region.texture = regionTex;
        region.uMax = (float)visW / (float)texW;
        region.vMax = (float)visH / (float)texH;

        [_activeSubpicRegions addObject:region];
    }
}

#pragma mark - Stage B Render Pass

- (void)encodeScaleFrom:(id<MTLTexture>)srcTexture
          renderEncoder:(id<MTLRenderCommandEncoder>)encoder
              placement:(CGRect)placement
             cropOrigin:(CGPoint)cropOrigin
               cropSize:(CGSize)cropSize
            orientation:(video_orientation_t)orientation
               headroom:(float)headroom
                  isEDR:(BOOL)isEDR
           drawableSize:(CGSize)drawableSize
{
    float srcW = (float)srcTexture.width;
    float srcH = (float)srcTexture.height;
    if (srcW <= 0.0f || srcH <= 0.0f)
        return;

    VideoQuadUniforms uniforms;
    memset(&uniforms, 0, sizeof(uniforms));

    uniforms.quadRect[0] = (float)placement.origin.x;
    uniforms.quadRect[1] = (float)placement.origin.y;
    uniforms.quadRect[2] = (float)placement.size.width;
    uniforms.quadRect[3] = (float)placement.size.height;

    uniforms.cropRect[0] = (float)cropOrigin.x / srcW;
    uniforms.cropRect[1] = (float)cropOrigin.y / srcH;
    uniforms.cropRect[2] = (float)cropSize.width / srcW;
    uniforms.cropRect[3] = (float)cropSize.height / srcH;

    uniforms.viewportSize[0] = (float)drawableSize.width;
    uniforms.viewportSize[1] = (float)drawableSize.height;

    InitOrientationMatrix(uniforms.orientation, orientation);

    uniforms.headroom = headroom;
    uniforms.isEDR = isEDR ? 1u : 0u;
    /* Clip (1) keeps colours the display contains exactly as they are. */
    uniforms.gamutMode = self.sourceGamutIsWide ? (uint32_t)MAX(self.gamutMapping, 0) : 1u;

    [encoder setRenderPipelineState:_videoQuadPSO];
    [encoder setFragmentTexture:srcTexture atIndex:0];
    [encoder setFragmentSamplerState:_samplerLinear atIndex:0];
    [encoder setVertexBytes:&uniforms length:sizeof(uniforms) atIndex:0];
    [encoder setFragmentBytes:&uniforms length:sizeof(uniforms) atIndex:0];

    [encoder drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4];
}

- (void)renderSubpicturesWithEncoder:(id<MTLRenderCommandEncoder>)encoder
                        drawableSize:(CGSize)drawableSize
{
    if (_activeSubpicRegions.count == 0)
        return;

    [encoder setRenderPipelineState:_subpicPSO];
    [encoder setFragmentSamplerState:_samplerLinear atIndex:0];

    for (MetalSubpicRegion *reg in _activeSubpicRegions) {
        if (reg.texture == nil)
            continue;

        SubpicUniforms u;
        memset(&u, 0, sizeof(u));
        u.quadRect[0] = (float)reg.place.origin.x;
        u.quadRect[1] = (float)reg.place.origin.y;
        u.quadRect[2] = (float)reg.place.size.width;
        u.quadRect[3] = (float)reg.place.size.height;

        u.texRect[0] = 0.0f;
        u.texRect[1] = 0.0f;
        u.texRect[2] = reg.uMax;
        u.texRect[3] = reg.vMax;

        u.viewportSize[0] = (float)drawableSize.width;
        u.viewportSize[1] = (float)drawableSize.height;
        u.alpha = reg.alpha;

        [encoder setVertexBytes:&u length:sizeof(u) atIndex:0];
        [encoder setFragmentBytes:&u length:sizeof(u) atIndex:0];
        [encoder setFragmentTexture:reg.texture atIndex:0];

        [encoder drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4];
    }
}

- (id<MTLTexture>)intermediate:(id<MTLTexture>)current size:(CGSize)size usage:(MTLTextureUsage)usage
{
    if (current != nil && current.width == (NSUInteger)size.width
        && current.height == (NSUInteger)size.height)
        return current;
    MTLTextureDescriptor *desc = [MTLTextureDescriptor
        texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA16Float
                                     width:(NSUInteger)size.width
                                    height:(NSUInteger)size.height
                                 mipmapped:NO];
    desc.usage = usage;
    desc.storageMode = MTLStorageModePrivate;
    return [_device newTextureWithDescriptor:desc];
}

/* Draws `texture` over the whole target without conversion (identity quad). */
- (void)encodeCopyOf:(id<MTLTexture>)texture
       renderEncoder:(id<MTLRenderCommandEncoder>)encoder
        drawableSize:(CGSize)size
{
    VideoQuadUniforms u;
    memset(&u, 0, sizeof(u));
    u.quadRect[2] = (float)size.width;
    u.quadRect[3] = (float)size.height;
    u.cropRect[2] = 1.0f;
    u.cropRect[3] = 1.0f;
    u.viewportSize[0] = (float)size.width;
    u.viewportSize[1] = (float)size.height;
    InitOrientationMatrix(u.orientation, ORIENT_NORMAL);
    [encoder setRenderPipelineState:_copyPSO];
    [encoder setFragmentTexture:texture atIndex:0];
    [encoder setFragmentSamplerState:_samplerLinear atIndex:0];
    [encoder setVertexBytes:&u length:sizeof(u) atIndex:0];
    [encoder drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4];
}

- (BOOL)renderVideoTexture:(id<MTLTexture>)stageATexture
                toDrawable:(id<CAMetalDrawable>)drawable
                 placement:(CGRect)placement
                cropOrigin:(CGPoint)cropOrigin
                  cropSize:(CGSize)cropSize
               orientation:(video_orientation_t)orientation
                  headroom:(float)headroom
                     isEDR:(BOOL)isEDR
{
    if (stageATexture == nil || drawable == nil)
        return NO;

    id<MTLCommandBuffer> cmdBuf = [_queue commandBuffer];
    if (cmdBuf == nil)
        return NO;
    /* The wrapped pictures this frame reads go when it has been drawn. */
    NSArray *held = _displayHeldTextures;
    _displayHeldTextures = [NSMutableArray array];
    [cmdBuf addCompletedHandler:^(id<MTLCommandBuffer> cb) {
        VLC_UNUSED(cb);
        (void)held;
    }];

    const CGSize drawableSize = CGSizeMake(drawable.texture.width, drawable.texture.height);

    /* 1. Optional: a projected (360) or filter-scaled picture, composed at the
     * drawable's size in BT.2020 light; the final pass then only converts it. */
    id<MTLTexture> source = stageATexture;
    CGRect sourcePlacement = placement;
    CGPoint sourceCropOrigin = cropOrigin;
    CGSize sourceCropSize = cropSize;
    video_orientation_t sourceOrientation = orientation;
    BOOL composed = NO;

    if (_projector != nil || (_scaler != nil && orientation == ORIENT_NORMAL)) {
        _composeTexture = [self intermediate:_composeTexture size:drawableSize
                                       usage:MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead];
        MTLRenderPassDescriptor *clear = [MTLRenderPassDescriptor renderPassDescriptor];
        clear.colorAttachments[0].texture = _composeTexture;
        clear.colorAttachments[0].loadAction = MTLLoadActionClear;
        clear.colorAttachments[0].clearColor = MTLClearColorMake(0.0, 0.0, 0.0, 1.0);
        clear.colorAttachments[0].storeAction = MTLStoreActionStore;
        id<MTLRenderCommandEncoder> enc = [cmdBuf renderCommandEncoderWithDescriptor:clear];
        if (_projector != nil && enc != nil) {
            [_projector encodeFrom:stageATexture
                     renderEncoder:enc
                          destRect:placement
                      drawableSize:drawableSize
                               sar:_sampleAspectRatio > 0.0f ? _sampleAspectRatio : 1.0f];
            composed = YES;
        }
        [enc endEncoding];
        if (!composed && _scaler != nil) {
            composed = [_scaler encodeScaleFrom:stageATexture
                                     sourceRect:CGRectMake(cropOrigin.x, cropOrigin.y,
                                                           cropSize.width, cropSize.height)
                                             to:_composeTexture
                                       destRect:placement
                                  commandBuffer:cmdBuf];
        }
        if (composed) {
            source = _composeTexture;
            sourcePlacement = CGRectMake(0, 0, drawableSize.width, drawableSize.height);
            sourceCropOrigin = CGPointZero;
            sourceCropSize = drawableSize;
            sourceOrientation = ORIENT_NORMAL;
        }
    }

    /* 2. The picture in Display P3 light, into the drawable, or into an
     * intermediate the LUT can write when there is one. */
    id<MTLTexture> target = drawable.texture;
    if (_lut != nil) {
        _outputTexture = [self intermediate:_outputTexture size:drawableSize
                                      usage:MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead
                                            | MTLTextureUsageShaderWrite];
        if (_outputTexture != nil)
            target = _outputTexture;
    }

    MTLRenderPassDescriptor *passDesc = [MTLRenderPassDescriptor renderPassDescriptor];
    passDesc.colorAttachments[0].texture = target;
    passDesc.colorAttachments[0].loadAction = MTLLoadActionClear;
    passDesc.colorAttachments[0].clearColor = MTLClearColorMake(0.0, 0.0, 0.0, 1.0);
    passDesc.colorAttachments[0].storeAction = MTLStoreActionStore;

    id<MTLRenderCommandEncoder> encoder = [cmdBuf renderCommandEncoderWithDescriptor:passDesc];
    if (encoder == nil) {
        [cmdBuf commit]; /* runs the completion handler above */
        return NO;
    }
    [self encodeScaleFrom:source
            renderEncoder:encoder
                placement:sourcePlacement
               cropOrigin:sourceCropOrigin
                 cropSize:sourceCropSize
              orientation:sourceOrientation
                 headroom:headroom
                    isEDR:isEDR
             drawableSize:drawableSize];
    if (target == drawable.texture)
        [self renderSubpicturesWithEncoder:encoder drawableSize:drawableSize];
    [encoder endEncoding];

    /* 3. The LUT on the finished picture, then subtitles on top of it. */
    if (target != drawable.texture) {
        [_lut encodeApplyTo:target commandBuffer:cmdBuf];
        MTLRenderPassDescriptor *final = [MTLRenderPassDescriptor renderPassDescriptor];
        final.colorAttachments[0].texture = drawable.texture;
        final.colorAttachments[0].loadAction = MTLLoadActionDontCare;
        final.colorAttachments[0].storeAction = MTLStoreActionStore;
        id<MTLRenderCommandEncoder> fin = [cmdBuf renderCommandEncoderWithDescriptor:final];
        if (fin == nil) {
            [cmdBuf commit];
            return NO;
        }
        [self encodeCopyOf:target renderEncoder:fin drawableSize:drawableSize];
        [self renderSubpicturesWithEncoder:fin drawableSize:drawableSize];
        [fin endEncoding];
    }

    [cmdBuf presentDrawable:drawable];
    [cmdBuf commit];

    _lastCommandBuffer = cmdBuf;
    return YES;
}

- (void)waitUntilCompleted
{
    if (_lastCommandBuffer != nil) {
        [_lastCommandBuffer waitUntilCompleted];
        _lastCommandBuffer = nil;
    }
}

- (void)releaseResources
{
    [self waitUntilCompleted];
    [_displayHeldTextures removeAllObjects];
    if (_textureCache != NULL)
        CVMetalTextureCacheFlush(_textureCache, 0);
    _cachedStageATexture = nil;
    _composeTexture = nil;
    _outputTexture = nil;
    [_activeSubpicRegions removeAllObjects];
    [_subpicTexturePool removeAllObjects];
}

- (void)dealloc
{
    [self releaseResources];
    if (_textureCache != NULL) {
        CFRelease(_textureCache);
        _textureCache = NULL;
    }
}

@end
