/*****************************************************************************
 * MacLCMetalScaler.m: Metal video scaler implementing gl_scale presets
 *****************************************************************************
 * Copyright (C) 2026 Hazen Studio
 *
 * Filter definitions ported from libplacebo v7.351.0 (src/filters.c),
 * Copyright (C) 2017-2024 Niklas Haas and libplacebo contributors,
 * licensed under LGPL-2.1-or-later.
 *
 * Ported filter functions and presets:
 *  - Box / Nearest (pl_filter_box)
 *  - Triangle / Bilinear (pl_filter_triangle)
 *  - Gaussian (pl_filter_gaussian)
 *  - Sinc (pl_filter_sinc, unwindowed)
 *  - Lanczos (pl_filter_lanczos, sinc windowed with sinc)
 *  - Ginseng (pl_filter_ginseng, sinc windowed with jinc)
 *  - Jinc (Sombrero Bessel J1)
 *  - EWA Lanczos (pl_filter_ewa_lanczos, jinc windowed with jinc)
 *  - EWA Ginseng (pl_filter_ewa_ginseng, jinc windowed with sinc)
 *  - EWA Hann (pl_filter_ewa_hann, jinc windowed with hann)
 *  - EWA Jinc (pl_filter_ewa_jinc, unwindowed)
 *  - Cubic / BC-spline family:
 *      * Mitchell-Netravali (B=1/3, C=1/3)
 *      * Bicubic / Catmull-Rom (B=0, C=1/2)
 *      * Robidoux (B=0.3782157526, C=0.3108921237)
 *      * RobidouxSharp (B=0.2620145124, C=0.3689927438)
 *      * EWA Robidoux & EWA RobidouxSharp (polar variants)
 *  - Spline family:
 *      * Spline16 (2 taps natural cubic spline)
 *      * Spline36 (3 taps natural cubic spline)
 *      * Spline64 (4 taps natural cubic spline)
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

#include <vlc_common.h>
#import "MacLCMetalScaler.h"
#import <simd/simd.h>
#include <math.h>

#define LUT_ENTRIES 512

#pragma mark - Filter Configuration & Math Functions

typedef double (*filter_fn)(double x, const double *params, double radius);

static double filter_box(double x, const double *params, double radius)
{
    VLC_UNUSED(params);
    return (x <= radius) ? 1.0 : 0.0;
}

static double filter_triangle(double x, const double *params, double radius)
{
    VLC_UNUSED(params);
    return fmax(0.0, 1.0 - x / radius);
}

static double filter_gaussian(double x, const double *params, double radius)
{
    VLC_UNUSED(radius);
    double t = params ? params[0] : 2.0;
    return exp(-t * x * x);
}

static double filter_sinc(double x, const double *params, double radius)
{
    VLC_UNUSED(params); VLC_UNUSED(radius);
    if (x == 0.0)
        return 1.0;
    double px = x * M_PI;
    return sin(px) / px;
}

static double filter_jinc(double x, const double *params, double radius)
{
    VLC_UNUSED(params); VLC_UNUSED(radius);
    if (x == 0.0)
        return 1.0;
    double px = x * M_PI;
    return 2.0 * j1(px) / px;
}

static double filter_hann(double x, const double *params, double radius)
{
    VLC_UNUSED(params);
    return 0.5 + 0.5 * cos(M_PI * x / radius);
}

static double filter_cubic(double x, const double *params, double radius)
{
    VLC_UNUSED(radius);
    double b = params[0];
    double c = params[1];
    double p0 = (6.0 - 2.0 * b) / 6.0;
    double p2 = (-18.0 + 12.0 * b + 6.0 * c) / 6.0;
    double p3 = (12.0 - 9.0 * b - 6.0 * c) / 6.0;
    double q0 = (8.0 * b + 24.0 * c) / 6.0;
    double q1 = (-12.0 * b - 48.0 * c) / 6.0;
    double q2 = (6.0 * b + 30.0 * c) / 6.0;
    double q3 = (-b - 6.0 * c) / 6.0;

    if (x < 1.0)
        return p0 + x * x * (p2 + x * p3);
    if (x < 2.0)
        return q0 + x * (q1 + x * (q2 + x * q3));
    return 0.0;
}

static double filter_spline16(double x, const double *params, double radius)
{
    VLC_UNUSED(params); VLC_UNUSED(radius);
    if (x < 1.0) {
        return ((x - 9.0 / 5.0) * x - 1.0 / 5.0) * x + 1.0;
    } else if (x < 2.0) {
        double t = x - 1.0;
        return ((-1.0 / 3.0 * t + 4.0 / 5.0) * t - 7.0 / 15.0) * t;
    }
    return 0.0;
}

static double filter_spline36(double x, const double *params, double radius)
{
    VLC_UNUSED(params); VLC_UNUSED(radius);
    if (x < 1.0) {
        return ((13.0 / 11.0 * x - 453.0 / 209.0) * x - 3.0 / 209.0) * x + 1.0;
    } else if (x < 2.0) {
        double t = x - 1.0;
        return ((-6.0 / 11.0 * t + 270.0 / 209.0) * t - 156.0 / 209.0) * t;
    } else if (x < 3.0) {
        double t = x - 2.0;
        return ((1.0 / 11.0 * t - 45.0 / 209.0) * t + 26.0 / 209.0) * t;
    }
    return 0.0;
}

static double filter_spline64(double x, const double *params, double radius)
{
    VLC_UNUSED(params); VLC_UNUSED(radius);
    if (x < 1.0) {
        return ((49.0 / 41.0 * x - 6387.0 / 2911.0) * x - 3.0 / 2911.0) * x + 1.0;
    } else if (x < 2.0) {
        double t = x - 1.0;
        return ((-24.0 / 41.0 * t + 3918.0 / 2911.0) * t - 2256.0 / 2911.0) * t;
    } else if (x < 3.0) {
        double t = x - 2.0;
        return ((6.0 / 41.0 * t - 990.0 / 2911.0) * t + 570.0 / 2911.0) * t;
    } else if (x < 4.0) {
        double t = x - 3.0;
        return ((-1.0 / 41.0 * t + 165.0 / 2911.0) * t - 95.0 / 2911.0) * t;
    }
    return 0.0;
}

typedef struct {
    const char *name;
    float radius;
    bool polar;
    filter_fn kernel;
    filter_fn window;
    double params[2];
} FilterConfig;

static const FilterConfig kFilterPresets[] = {
    [VLC_GLSCALE_BUILTIN]           = { "builtin", 0.0f, false, NULL, NULL, {0} },
    [VLC_GLSCALE_SPLINE16]          = { "spline16", 2.0f, false, filter_spline16, NULL, {0} },
    [VLC_GLSCALE_SPLINE36]          = { "spline36", 3.0f, false, filter_spline36, NULL, {0} },
    [VLC_GLSCALE_SPLINE64]          = { "spline64", 4.0f, false, filter_spline64, NULL, {0} },
    [VLC_GLSCALE_MITCHELL]          = { "mitchell", 2.0f, false, filter_cubic, NULL, { 1.0 / 3.0, 1.0 / 3.0 } },
    [VLC_GLSCALE_BICUBIC]           = { "bicubic", 2.0f, false, filter_cubic, NULL, { 0.0, 0.5 } },
    [VLC_GLSCALE_EWA_LANCZOS]       = { "ewa_lanczos", 3.0f, true, filter_jinc, filter_jinc, {0} },
    [VLC_GLSCALE_NEAREST]           = { "nearest", 0.5f, false, filter_box, NULL, {0} },
    [VLC_GLSCALE_BILINEAR]          = { "bilinear", 1.0f, false, filter_triangle, NULL, {0} },
    [VLC_GLSCALE_GAUSSIAN]          = { "gaussian", 2.0f, false, filter_gaussian, NULL, { 2.0, 0.0 } },
    [VLC_GLSCALE_LANCZOS]           = { "lanczos", 3.0f, false, filter_sinc, filter_sinc, {0} },
    [VLC_GLSCALE_GINSENG]           = { "ginseng", 3.0f, false, filter_sinc, filter_jinc, {0} },
    [VLC_GLSCALE_EWA_GINSENG]       = { "ewa_ginseng", 3.0f, true, filter_jinc, filter_sinc, {0} },
    [VLC_GLSCALE_EWA_HANN]          = { "ewa_hann", 3.0f, true, filter_jinc, filter_hann, {0} },
    [VLC_GLSCALE_CATMULL_ROM]       = { "catmull_rom", 2.0f, false, filter_cubic, NULL, { 0.0, 0.5 } },
    [VLC_GLSCALE_ROBIDOUX]          = { "robidoux", 2.0f, false, filter_cubic, NULL,
                                        { 12.0 / (19.0 + 9.0 * 1.4142135623730951),
                                          (7.0 + 9.0 * 1.4142135623730951) / (2.0 * (19.0 + 9.0 * 1.4142135623730951)) } },
    [VLC_GLSCALE_ROBIDOUXSHARP]     = { "robidouxsharp", 2.0f, false, filter_cubic, NULL,
                                        { 6.0 / (13.0 + 7.0 * 1.4142135623730951),
                                          (7.0 + 7.0 * 1.4142135623730951) / (2.0 * (13.0 + 7.0 * 1.4142135623730951)) } },
    [VLC_GLSCALE_EWA_ROBIDOUX]      = { "ewa_robidoux", 2.0f, true, filter_cubic, NULL,
                                        { 12.0 / (19.0 + 9.0 * 1.4142135623730951),
                                          (7.0 + 9.0 * 1.4142135623730951) / (2.0 * (19.0 + 9.0 * 1.4142135623730951)) } },
    [VLC_GLSCALE_EWA_ROBIDOUXSHARP] = { "ewa_robidouxsharp", 2.0f, true, filter_cubic, NULL,
                                        { 6.0 / (13.0 + 7.0 * 1.4142135623730951),
                                          (7.0 + 7.0 * 1.4142135623730951) / (2.0 * (13.0 + 7.0 * 1.4142135623730951)) } },
    [VLC_GLSCALE_SINC]              = { "sinc", 3.0f, false, filter_sinc, NULL, {0} },
    [VLC_GLSCALE_EWA_JINC]          = { "ewa_jinc", 3.0f, true, filter_jinc, NULL, {0} },
};

static double SampleFilter(const FilterConfig *cfg, double x)
{
    if (x > cfg->radius)
        return 0.0;
    double w = cfg->kernel(x, cfg->params, cfg->radius);
    if (cfg->window != NULL)
        w *= cfg->window(x, NULL, cfg->radius);
    return w;
}

#pragma mark - Uniform Structs

typedef struct {
    float srcX0;
    float srcY0;
    float srcWidth;
    float srcHeight;
    float destWidth;
    float texWidth;
    float texHeight;
    float filterRadius;
    float filterScale;
    float _pad[3];
} ScaleHorizUniforms;

_Static_assert(sizeof(ScaleHorizUniforms) == 48,
               "ScaleHorizUniforms size must match 16-byte alignment");

typedef struct {
    float destX0;
    float destY0;
    float destWidth;
    float destHeight;
    float srcHeight;
    float intermediateWidth;
    float intermediateHeight;
    float filterRadius;
    float filterScale;
    float _pad[3];
} ScaleVertUniforms;

_Static_assert(sizeof(ScaleVertUniforms) == 48,
               "ScaleVertUniforms size must match 16-byte alignment");

typedef struct {
    float srcX0;
    float srcY0;
    float srcWidth;
    float srcHeight;
    float destX0;
    float destY0;
    float destWidth;
    float destHeight;
    float texWidth;
    float texHeight;
    float filterRadius;
    float filterScaleX;
    float filterScaleY;
    float _pad[3];
} ScalePolarUniforms;

_Static_assert(sizeof(ScalePolarUniforms) == 64,
               "ScalePolarUniforms size must match 16-byte alignment");

#pragma mark - Shaders Source

static NSString * const kScalerShaderSource =
    @"#include <metal_stdlib>\n"
    @"using namespace metal;\n"
    @"\n"
    @"struct VertexOut {\n"
    @"    float4 position [[position]];\n"
    @"    float2 uv;\n"
    @"};\n"
    @"\n"
    @"vertex VertexOut vlc_scale_vertex(uint vid [[vertex_id]])\n"
    @"{\n"
    @"    float2 pos = float2((vid >= 2) ? 1.0f : -1.0f,\n"
    @"                        (vid & 1) ? -1.0f : 1.0f);\n"
    @"    VertexOut out;\n"
    @"    out.position = float4(pos, 0.0f, 1.0f);\n"
    @"    out.uv = float2((pos.x + 1.0f) * 0.5f, (1.0f - pos.y) * 0.5f);\n"
    @"    return out;\n"
    @"}\n"
    @"\n"
    @"struct ScaleHorizUniforms {\n"
    @"    float srcX0;\n"
    @"    float srcY0;\n"
    @"    float srcWidth;\n"
    @"    float srcHeight;\n"
    @"    float destWidth;\n"
    @"    float texWidth;\n"
    @"    float texHeight;\n"
    @"    float filterRadius;\n"
    @"    float filterScale;\n"
    @"    float3 _pad;\n"
    @"};\n"
    @"\n"
    @"fragment float4 vlc_scale_horiz_fragment(\n"
    @"    VertexOut in [[stage_in]],\n"
    @"    texture2d<float, access::read> inTex     [[texture(0)]],\n"
    @"    texture2d<float, access::sample> lutTex  [[texture(1)]],\n"
    @"    sampler lutSampler                       [[sampler(0)]],\n"
    @"    constant ScaleHorizUniforms &u           [[buffer(0)]])\n"
    @"{\n"
    @"    int destX = int(in.position.x);\n"
    @"    float srcPos = u.srcX0 + (float(destX) + 0.5f) * (u.srcWidth / u.destWidth) - 0.5f;\n"
    @"    float rSrc = u.filterRadius * u.filterScale;\n"
    @"    int iMin = int(floor(srcPos - rSrc));\n"
    @"    int iMax = int(ceil(srcPos + rSrc));\n"
    @"    float4 colorSum = float4(0.0f);\n"
    @"    float weightSum = 0.0f;\n"
    @"    int yCoord = clamp(int(u.srcY0 + in.position.y), 0, int(u.texHeight - 1));\n"
    @"\n"
    @"    for (int i = iMin; i <= iMax; ++i) {\n"
    @"        int xCoord = clamp(i, 0, int(u.texWidth - 1));\n"
    @"        float dist = fabs(float(i) - srcPos) / u.filterScale;\n"
    @"        if (dist <= u.filterRadius) {\n"
    @"            float normCoord = dist / u.filterRadius;\n"
    @"            float w = lutTex.sample(lutSampler, float2(normCoord, 0.5f)).r;\n"
    @"            float4 c = inTex.read(uint2(xCoord, yCoord));\n"
    @"            colorSum += c * w;\n"
    @"            weightSum += w;\n"
    @"        }\n"
    @"    }\n"
    @"    float4 outColor = (weightSum > 0.0f) ? (colorSum / weightSum) :\n"
    @"                      inTex.read(uint2(clamp(int(srcPos), 0, int(u.texWidth - 1)), yCoord));\n"
    @"    return max(outColor, float4(0.0f));\n"
    @"}\n"
    @"\n"
    @"struct ScaleVertUniforms {\n"
    @"    float destX0;\n"
    @"    float destY0;\n"
    @"    float destWidth;\n"
    @"    float destHeight;\n"
    @"    float srcHeight;\n"
    @"    float intermediateWidth;\n"
    @"    float intermediateHeight;\n"
    @"    float filterRadius;\n"
    @"    float filterScale;\n"
    @"    float3 _pad;\n"
    @"};\n"
    @"\n"
    @"fragment float4 vlc_scale_vert_fragment(\n"
    @"    VertexOut in [[stage_in]],\n"
    @"    texture2d<float, access::read> intermediateTex [[texture(0)]],\n"
    @"    texture2d<float, access::sample> lutTex        [[texture(1)]],\n"
    @"    sampler lutSampler                             [[sampler(0)]],\n"
    @"    constant ScaleVertUniforms &u                  [[buffer(0)]])\n"
    @"{\n"
    @"    int destX = int(in.position.x - u.destX0);\n"
    @"    int destY = int(in.position.y - u.destY0);\n"
    @"    destX = clamp(destX, 0, int(u.intermediateWidth - 1));\n"
    @"    float srcPos = (float(destY) + 0.5f) * (u.srcHeight / u.destHeight) - 0.5f;\n"
    @"    float rSrc = u.filterRadius * u.filterScale;\n"
    @"    int jMin = int(floor(srcPos - rSrc));\n"
    @"    int jMax = int(ceil(srcPos + rSrc));\n"
    @"    float4 colorSum = float4(0.0f);\n"
    @"    float weightSum = 0.0f;\n"
    @"\n"
    @"    for (int j = jMin; j <= jMax; ++j) {\n"
    @"        int yCoord = clamp(j, 0, int(u.intermediateHeight - 1));\n"
    @"        float dist = fabs(float(j) - srcPos) / u.filterScale;\n"
    @"        if (dist <= u.filterRadius) {\n"
    @"            float normCoord = dist / u.filterRadius;\n"
    @"            float w = lutTex.sample(lutSampler, float2(normCoord, 0.5f)).r;\n"
    @"            float4 c = intermediateTex.read(uint2(destX, yCoord));\n"
    @"            colorSum += c * w;\n"
    @"            weightSum += w;\n"
    @"        }\n"
    @"    }\n"
    @"    float4 outColor = (weightSum > 0.0f) ? (colorSum / weightSum) :\n"
    @"                      intermediateTex.read(uint2(destX, clamp(int(srcPos), 0, int(u.intermediateHeight - 1))));\n"
    @"    return max(outColor, float4(0.0f));\n"
    @"}\n"
    @"\n"
    @"struct ScalePolarUniforms {\n"
    @"    float srcX0;\n"
    @"    float srcY0;\n"
    @"    float srcWidth;\n"
    @"    float srcHeight;\n"
    @"    float destX0;\n"
    @"    float destY0;\n"
    @"    float destWidth;\n"
    @"    float destHeight;\n"
    @"    float texWidth;\n"
    @"    float texHeight;\n"
    @"    float filterRadius;\n"
    @"    float filterScaleX;\n"
    @"    float filterScaleY;\n"
    @"    float3 _pad;\n"
    @"};\n"
    @"\n"
    @"fragment float4 vlc_scale_polar_fragment(\n"
    @"    VertexOut in [[stage_in]],\n"
    @"    texture2d<float, access::read> inTex     [[texture(0)]],\n"
    @"    texture2d<float, access::sample> lutTex  [[texture(1)]],\n"
    @"    sampler lutSampler                       [[sampler(0)]],\n"
    @"    constant ScalePolarUniforms &u           [[buffer(0)]])\n"
    @"{\n"
    @"    int destX = int(in.position.x - u.destX0);\n"
    @"    int destY = int(in.position.y - u.destY0);\n"
    @"    float srcPosX = u.srcX0 + (float(destX) + 0.5f) * (u.srcWidth / u.destWidth) - 0.5f;\n"
    @"    float srcPosY = u.srcY0 + (float(destY) + 0.5f) * (u.srcHeight / u.destHeight) - 0.5f;\n"
    @"    float rSrcX = u.filterRadius * u.filterScaleX;\n"
    @"    float rSrcY = u.filterRadius * u.filterScaleY;\n"
    @"    int iMin = int(floor(srcPosX - rSrcX));\n"
    @"    int iMax = int(ceil(srcPosX + rSrcX));\n"
    @"    int jMin = int(floor(srcPosY - rSrcY));\n"
    @"    int jMax = int(ceil(srcPosY + rSrcY));\n"
    @"    float4 colorSum = float4(0.0f);\n"
    @"    float weightSum = 0.0f;\n"
    @"\n"
    @"    for (int j = jMin; j <= jMax; ++j) {\n"
    @"        int yCoord = clamp(j, 0, int(u.texHeight - 1));\n"
    @"        float dy = (float(j) - srcPosY) / u.filterScaleY;\n"
    @"        for (int i = iMin; i <= iMax; ++i) {\n"
    @"            int xCoord = clamp(i, 0, int(u.texWidth - 1));\n"
    @"            float dx = (float(i) - srcPosX) / u.filterScaleX;\n"
    @"            float dist = sqrt(dx * dx + dy * dy);\n"
    @"            if (dist <= u.filterRadius) {\n"
    @"                float normCoord = dist / u.filterRadius;\n"
    @"                float w = lutTex.sample(lutSampler, float2(normCoord, 0.5f)).r;\n"
    @"                float4 c = inTex.read(uint2(xCoord, yCoord));\n"
    @"                colorSum += c * w;\n"
    @"                weightSum += w;\n"
    @"            }\n"
    @"        }\n"
    @"    }\n"
    @"    float4 outColor = (weightSum > 0.0f) ? (colorSum / weightSum) :\n"
    @"                      inTex.read(uint2(clamp(int(srcPosX), 0, int(u.texWidth - 1)),\n"
    @"                                       clamp(int(srcPosY), 0, int(u.texHeight - 1))));\n"
    @"    return max(outColor, float4(0.0f));\n"
    @"}\n";

#pragma mark - MacLCMetalScaler Implementation

/* The part of rect inside the target: a zoomed or cropped picture can start
 * left of or above the drawable, and a scissor rect must lie within it. */
static MTLScissorRect ScissorInside(CGRect rect, id<MTLTexture> target)
{
    const CGFloat x0 = fmax(0.0, floor(CGRectGetMinX(rect)));
    const CGFloat y0 = fmax(0.0, floor(CGRectGetMinY(rect)));
    const CGFloat x1 = fmin((CGFloat)target.width, ceil(CGRectGetMaxX(rect)));
    const CGFloat y1 = fmin((CGFloat)target.height, ceil(CGRectGetMaxY(rect)));
    MTLScissorRect sc = { (NSUInteger)x0, (NSUInteger)y0,
                          x1 > x0 ? (NSUInteger)(x1 - x0) : 0, y1 > y0 ? (NSUInteger)(y1 - y0) : 0 };
    return sc;
}

@implementation MacLCMetalScaler {
    id<MTLDevice> _device;
    id<MTLRenderPipelineState> _horizPSO;
    id<MTLRenderPipelineState> _vertPSO;
    id<MTLRenderPipelineState> _polarPSO;
    id<MTLSamplerState> _lutSampler;

    id<MTLTexture> _intermediateTexture;

    id<MTLTexture> _lutTextureUpscaler;
    int _cachedUpscalerPreset;

    id<MTLTexture> _lutTextureDownscaler;
    int _cachedDownscalerPreset;
}

@synthesize upscaler = _upscaler;
@synthesize downscaler = _downscaler;

- (nullable instancetype)initWithDevice:(id<MTLDevice>)device
{
    self = [super init];
    if (self == nil || device == nil)
        return nil;

    _device = device;
    _upscaler = VLC_GLSCALE_BUILTIN;
    _downscaler = VLC_GLSCALE_BUILTIN;
    _cachedUpscalerPreset = -1;
    _cachedDownscalerPreset = -1;

    NSError *error = nil;
    id<MTLLibrary> library = [_device newLibraryWithSource:kScalerShaderSource
                                                  options:nil
                                                    error:&error];
    if (library == nil) {
        NSLog(@"MacLCMetalScaler: shader compilation failed: %@", error.localizedDescription);
        return nil;
    }

    id<MTLFunction> vertFunc = [library newFunctionWithName:@"vlc_scale_vertex"];
    id<MTLFunction> horizFrag = [library newFunctionWithName:@"vlc_scale_horiz_fragment"];
    id<MTLFunction> vertFrag = [library newFunctionWithName:@"vlc_scale_vert_fragment"];
    id<MTLFunction> polarFrag = [library newFunctionWithName:@"vlc_scale_polar_fragment"];

    if (vertFunc == nil || horizFrag == nil || vertFrag == nil || polarFrag == nil)
        return nil;

    MTLRenderPipelineDescriptor *pDesc = [[MTLRenderPipelineDescriptor alloc] init];
    pDesc.vertexFunction = vertFunc;
    pDesc.fragmentFunction = horizFrag;
    pDesc.colorAttachments[0].pixelFormat = MTLPixelFormatRGBA16Float;
    _horizPSO = [_device newRenderPipelineStateWithDescriptor:pDesc error:&error];
    if (_horizPSO == nil)
        return nil;

    pDesc.fragmentFunction = vertFrag;
    _vertPSO = [_device newRenderPipelineStateWithDescriptor:pDesc error:&error];
    if (_vertPSO == nil)
        return nil;

    pDesc.fragmentFunction = polarFrag;
    _polarPSO = [_device newRenderPipelineStateWithDescriptor:pDesc error:&error];
    if (_polarPSO == nil)
        return nil;

    MTLSamplerDescriptor *sDesc = [[MTLSamplerDescriptor alloc] init];
    sDesc.minFilter = MTLSamplerMinMagFilterLinear;
    sDesc.magFilter = MTLSamplerMinMagFilterLinear;
    sDesc.sAddressMode = MTLSamplerAddressModeClampToEdge;
    sDesc.tAddressMode = MTLSamplerAddressModeClampToEdge;
    _lutSampler = [_device newSamplerStateWithDescriptor:sDesc];

    return self;
}

- (id<MTLTexture>)lutTextureForPreset:(int)preset
{
    if (preset < 0 || preset >= (int)(sizeof(kFilterPresets) / sizeof(kFilterPresets[0])))
        return nil;

    const FilterConfig *cfg = &kFilterPresets[preset];
    if (cfg->kernel == NULL)
        return nil;

    float weights[LUT_ENTRIES];
    for (int i = 0; i < LUT_ENTRIES; ++i) {
        double r = ((double)i / (double)(LUT_ENTRIES - 1)) * cfg->radius;
        weights[i] = (float)SampleFilter(cfg, r);
    }

    MTLTextureDescriptor *tDesc = [MTLTextureDescriptor
        texture2DDescriptorWithPixelFormat:MTLPixelFormatR32Float
                                     width:LUT_ENTRIES
                                    height:1
                                 mipmapped:NO];
    tDesc.usage = MTLTextureUsageShaderRead;
    tDesc.storageMode = MTLStorageModeManaged;
    id<MTLTexture> tex = [_device newTextureWithDescriptor:tDesc];
    if (tex != nil) {
        [tex replaceRegion:MTLRegionMake2D(0, 0, LUT_ENTRIES, 1)
               mipmapLevel:0
                 withBytes:weights
               bytesPerRow:LUT_ENTRIES * sizeof(float)];
    }
    return tex;
}

- (BOOL)encodeScaleFrom:(id<MTLTexture>)input
             sourceRect:(CGRect)sourceRect
                     to:(id<MTLTexture>)output
               destRect:(CGRect)destRect
          commandBuffer:(id<MTLCommandBuffer>)commandBuffer
{
    if (input == nil || output == nil || commandBuffer == nil)
        return NO;

    if (sourceRect.size.width <= 0.0 || sourceRect.size.height <= 0.0 ||
        destRect.size.width <= 0.0 || destRect.size.height <= 0.0)
        return NO;

    double scaleX = destRect.size.width / sourceRect.size.width;
    double scaleY = destRect.size.height / sourceRect.size.height;

    int presetX = (scaleX >= 1.0) ? _upscaler : _downscaler;
    int presetY = (scaleY >= 1.0) ? _upscaler : _downscaler;

    /* If both axes use Built-in / fixed-function, let caller handle bilinear path */
    if (presetX == VLC_GLSCALE_BUILTIN && presetY == VLC_GLSCALE_BUILTIN)
        return NO;

    /* Check if either active filter is polar (EWA) */
    const FilterConfig *cfgX = (presetX >= 0 && presetX < (int)(sizeof(kFilterPresets) / sizeof(kFilterPresets[0])))
                             ? &kFilterPresets[presetX] : NULL;
    const FilterConfig *cfgY = (presetY >= 0 && presetY < (int)(sizeof(kFilterPresets) / sizeof(kFilterPresets[0])))
                             ? &kFilterPresets[presetY] : NULL;

    bool isPolar = (cfgX && cfgX->polar) || (cfgY && cfgY->polar);
    int activePolarPreset = (cfgX && cfgX->polar) ? presetX : presetY;

    if (isPolar) {
        const FilterConfig *polarCfg = &kFilterPresets[activePolarPreset];
        id<MTLTexture> lutTex = [self lutTextureForPreset:activePolarPreset];
        if (lutTex == nil)
            return NO;

        ScalePolarUniforms u;
        memset(&u, 0, sizeof(u));
        u.srcX0 = (float)sourceRect.origin.x;
        u.srcY0 = (float)sourceRect.origin.y;
        u.srcWidth = (float)sourceRect.size.width;
        u.srcHeight = (float)sourceRect.size.height;
        u.destX0 = (float)destRect.origin.x;
        u.destY0 = (float)destRect.origin.y;
        u.destWidth = (float)destRect.size.width;
        u.destHeight = (float)destRect.size.height;
        u.texWidth = (float)input.width;
        u.texHeight = (float)input.height;
        u.filterRadius = polarCfg->radius;
        u.filterScaleX = (float)fmax(1.0, 1.0 / scaleX);
        u.filterScaleY = (float)fmax(1.0, 1.0 / scaleY);

        MTLRenderPassDescriptor *passDesc = [MTLRenderPassDescriptor renderPassDescriptor];
        passDesc.colorAttachments[0].texture = output;
        passDesc.colorAttachments[0].loadAction = MTLLoadActionLoad;
        passDesc.colorAttachments[0].storeAction = MTLStoreActionStore;

        id<MTLRenderCommandEncoder> enc = [commandBuffer renderCommandEncoderWithDescriptor:passDesc];
        if (enc == nil)
            return NO;

        /* Nothing of the picture is inside the drawable (panned or zoomed
         * away): an empty scissor rect is invalid, draw nothing. */
        const MTLScissorRect sc = ScissorInside(destRect, output);
        if (sc.width == 0 || sc.height == 0) {
            [enc endEncoding];
            return YES;
        }
        MTLViewport vp = { destRect.origin.x, destRect.origin.y, destRect.size.width, destRect.size.height, 0.0, 1.0 };
        [enc setViewport:vp];
        [enc setScissorRect:sc];

        [enc setRenderPipelineState:_polarPSO];
        [enc setFragmentTexture:input atIndex:0];
        [enc setFragmentTexture:lutTex atIndex:1];
        [enc setFragmentSamplerState:_lutSampler atIndex:0];
        [enc setFragmentBytes:&u length:sizeof(u) atIndex:0];

        [enc drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4];
        [enc endEncoding];

        return YES;
    }

    /* Separable 2-pass scaling (Horizontal into intermediate, then Vertical into output) */
    NSUInteger intermediateW = (NSUInteger)ceil(destRect.size.width);
    NSUInteger intermediateH = (NSUInteger)ceil(sourceRect.size.height);

    if (_intermediateTexture == nil ||
        _intermediateTexture.width != intermediateW ||
        _intermediateTexture.height != intermediateH) {
        MTLTextureDescriptor *iDesc = [MTLTextureDescriptor
            texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA16Float
                                         width:intermediateW
                                        height:intermediateH
                                     mipmapped:NO];
        iDesc.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead;
        iDesc.storageMode = MTLStorageModePrivate;
        _intermediateTexture = [_device newTextureWithDescriptor:iDesc];
    }
    if (_intermediateTexture == nil)
        return NO;

    int horizPreset = (presetX != VLC_GLSCALE_BUILTIN) ? presetX : VLC_GLSCALE_BILINEAR;
    int vertPreset = (presetY != VLC_GLSCALE_BUILTIN) ? presetY : VLC_GLSCALE_BILINEAR;

    const FilterConfig *hCfg = &kFilterPresets[horizPreset];
    const FilterConfig *vCfg = &kFilterPresets[vertPreset];

    id<MTLTexture> hLut = [self lutTextureForPreset:horizPreset];
    id<MTLTexture> vLut = [self lutTextureForPreset:vertPreset];
    if (hLut == nil || vLut == nil)
        return NO;

    /* Pass 1: Horizontal scale -> _intermediateTexture */
    {
        ScaleHorizUniforms uH;
        memset(&uH, 0, sizeof(uH));
        uH.srcX0 = (float)sourceRect.origin.x;
        uH.srcY0 = (float)sourceRect.origin.y;
        uH.srcWidth = (float)sourceRect.size.width;
        uH.srcHeight = (float)sourceRect.size.height;
        uH.destWidth = (float)intermediateW;
        uH.texWidth = (float)input.width;
        uH.texHeight = (float)input.height;
        uH.filterRadius = hCfg->radius;
        uH.filterScale = (float)fmax(1.0, 1.0 / scaleX);

        MTLRenderPassDescriptor *hPass = [MTLRenderPassDescriptor renderPassDescriptor];
        hPass.colorAttachments[0].texture = _intermediateTexture;
        hPass.colorAttachments[0].loadAction = MTLLoadActionDontCare;
        hPass.colorAttachments[0].storeAction = MTLStoreActionStore;

        id<MTLRenderCommandEncoder> hEnc = [commandBuffer renderCommandEncoderWithDescriptor:hPass];
        if (hEnc == nil)
            return NO;

        MTLViewport vp = { 0.0, 0.0, (double)intermediateW, (double)intermediateH, 0.0, 1.0 };
        [hEnc setViewport:vp];
        [hEnc setRenderPipelineState:_horizPSO];
        [hEnc setFragmentTexture:input atIndex:0];
        [hEnc setFragmentTexture:hLut atIndex:1];
        [hEnc setFragmentSamplerState:_lutSampler atIndex:0];
        [hEnc setFragmentBytes:&uH length:sizeof(uH) atIndex:0];

        [hEnc drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4];
        [hEnc endEncoding];
    }

    /* Pass 2: Vertical scale -> output (destRect region) */
    {
        ScaleVertUniforms uV;
        memset(&uV, 0, sizeof(uV));
        uV.destX0 = (float)destRect.origin.x;
        uV.destY0 = (float)destRect.origin.y;
        uV.destWidth = (float)destRect.size.width;
        uV.destHeight = (float)destRect.size.height;
        uV.srcHeight = (float)sourceRect.size.height;
        uV.intermediateWidth = (float)intermediateW;
        uV.intermediateHeight = (float)intermediateH;
        uV.filterRadius = vCfg->radius;
        uV.filterScale = (float)fmax(1.0, 1.0 / scaleY);

        MTLRenderPassDescriptor *vPass = [MTLRenderPassDescriptor renderPassDescriptor];
        vPass.colorAttachments[0].texture = output;
        vPass.colorAttachments[0].loadAction = MTLLoadActionLoad;
        vPass.colorAttachments[0].storeAction = MTLStoreActionStore;

        id<MTLRenderCommandEncoder> vEnc = [commandBuffer renderCommandEncoderWithDescriptor:vPass];
        if (vEnc == nil)
            return NO;

        const MTLScissorRect sc = ScissorInside(destRect, output);
        if (sc.width == 0 || sc.height == 0) {
            [vEnc endEncoding];
            return YES;
        }
        MTLViewport vp = { destRect.origin.x, destRect.origin.y, destRect.size.width, destRect.size.height, 0.0, 1.0 };
        [vEnc setViewport:vp];
        [vEnc setScissorRect:sc];

        [vEnc setRenderPipelineState:_vertPSO];
        [vEnc setFragmentTexture:_intermediateTexture atIndex:0];
        [vEnc setFragmentTexture:vLut atIndex:1];
        [vEnc setFragmentSamplerState:_lutSampler atIndex:0];
        [vEnc setFragmentBytes:&uV length:sizeof(uV) atIndex:0];

        [vEnc drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4];
        [vEnc endEncoding];
    }

    return YES;
}

@end
