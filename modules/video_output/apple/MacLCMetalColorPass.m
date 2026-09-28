/*****************************************************************************
 * MacLCMetalColorPass.m: tone mapping of linear light for the Metal output
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

#ifdef HAVE_CONFIG_H
# include "config.h"
#endif

#import "MacLCMetalColorPass.h"

#include <string.h>

#include "maclc_hdr_vars.h"

/* Table size: 512 floats go to the kernel through setBytes (2 KiB, under
 * Metal's 4 KiB limit for inline data), so a new table never races a frame
 * still in flight. The curves are smooth in PQ: linear interpolation over
 * 512 points stays within 1e-4 PQ of the exact curve. */
#define MACLC_COLOR_PASS_LUT_SIZE 512

typedef struct
{
    float lutMinPQ;       /* the table's input range, in PQ */
    float lutMaxPQ;
    float referenceWhite; /* cd/m2 at 1.0 */
    uint32_t lutSize;
    uint32_t width;
    uint32_t height;
    uint32_t _pad[2];
} MacLCColorPassUniforms;

_Static_assert(sizeof(MacLCColorPassUniforms) == 32,
               "MacLCColorPassUniforms must match the shader's layout");

static NSString * const kMacLCColorPassShaderSource =
    @"#include <metal_stdlib>\n"
    @"using namespace metal;\n"
    @"\n"
    @"struct MacLCColorPassUniforms {\n"
    @"    float lutMinPQ;\n"
    @"    float lutMaxPQ;\n"
    @"    float referenceWhite;\n"
    @"    uint  lutSize;\n"
    @"    uint  width;\n"
    @"    uint  height;\n"
    @"    uint  _pad[2];\n"
    @"};\n"
    @"\n"
    @"constant float PQ_M1 = 2610.0f / 16384.0f;\n"
    @"constant float PQ_M2 = (2523.0f / 4096.0f) * 128.0f;\n"
    @"constant float PQ_C1 = 3424.0f / 4096.0f;\n"
    @"constant float PQ_C2 = (2413.0f / 4096.0f) * 32.0f;\n"
    @"constant float PQ_C3 = (2392.0f / 4096.0f) * 32.0f;\n"
    @"\n"
    @"static inline float pq_to_nits(float e)\n"
    @"{\n"
    @"    e = clamp(e, 0.0f, 1.0f);\n"
    @"    float em2 = pow(e, 1.0f / PQ_M2);\n"
    @"    float num = max(em2 - PQ_C1, 0.0f);\n"
    @"    float den = max(PQ_C2 - PQ_C3 * em2, 1e-6f);\n"
    @"    return 10000.0f * pow(num / den, 1.0f / PQ_M1);\n"
    @"}\n"
    @"\n"
    @"static inline float nits_to_pq(float nits)\n"
    @"{\n"
    @"    float y = pow(clamp(nits / 10000.0f, 0.0f, 1.0f), PQ_M1);\n"
    @"    return pow((PQ_C1 + PQ_C2 * y) / (1.0f + PQ_C3 * y), PQ_M2);\n"
    @"}\n"
    @"\n"
    @"/* The curve on max(R, G, B) in PQ, colours scaled by the same ratio, as\n"
    @" * MacLCHDRToneMapper.m does: hue and saturation are kept. */\n"
    @"kernel void maclc_color_pass(\n"
    @"    texture2d<float, access::read>   inTexture  [[texture(0)]],\n"
    @"    texture2d<float, access::write>  outTexture [[texture(1)]],\n"
    @"    constant MacLCColorPassUniforms &u          [[buffer(0)]],\n"
    @"    constant float                  *lut        [[buffer(1)]],\n"
    @"    uint2 gid [[thread_position_in_grid]])\n"
    @"{\n"
    @"    if (gid.x >= u.width || gid.y >= u.height)\n"
    @"        return;\n"
    @"\n"
    @"    float3 rgb = max(inTexture.read(gid).rgb, 0.0f);\n"
    @"    float m = max(max(rgb.r, rgb.g), rgb.b);\n"
    @"    float3 mapped = float3(0.0f);\n"
    @"    if (m > 0.0f) {\n"
    @"        float nits = m * u.referenceWhite;\n"
    @"        float range = max(u.lutMaxPQ - u.lutMinPQ, 1e-6f);\n"
    @"        float t = clamp((nits_to_pq(nits) - u.lutMinPQ) / range, 0.0f, 1.0f)\n"
    @"                * float(u.lutSize - 1u);\n"
    @"        uint i = min(uint(t), u.lutSize - 2u);\n"
    @"        float pq = mix(lut[i], lut[i + 1u], t - float(i));\n"
    @"        mapped = rgb * (pq_to_nits(pq) / nits);\n"
    @"    }\n"
    @"    outTexture.write(float4(mapped, 1.0f), gid);\n"
    @"}\n";

static bool ToneParamsEqual(const maclc_tone_params *a, const maclc_tone_params *b)
{
    return a->mode == b->mode && a->content_peak == b->content_peak
        && a->display_peak == b->display_peak
        && a->reference_white == b->reference_white && a->gain == b->gain
        && a->knee_pq == b->knee_pq && a->src_peak_pq == b->src_peak_pq
        && a->dst_peak_pq == b->dst_peak_pq && a->identity == b->identity;
}

@implementation MacLCMetalColorPass
{
    id<MTLDevice> _device;
    id<MTLComputePipelineState> _pipeline;
    id<MTLTexture> _output;

    float _lut[MACLC_COLOR_PASS_LUT_SIZE];
    float _lutMinPQ;
    float _lutMaxPQ;

    /* What the table holds now, to rebuild it only on change. */
    enum { MACLC_LUT_NONE, MACLC_LUT_PICTURE, MACLC_LUT_CURVE } _lutKind;
    maclc_tone_params _toneParams;
    struct maclc_tonecurve_params _curveParams;
    vlc_video_hdr_dynamic_metadata_t _hdr10plus;
}

- (nullable instancetype)initWithDevice:(id<MTLDevice>)device
{
    if (device == nil)
        return nil;
    self = [super init];
    if (self == nil)
        return nil;

    _device = device;
    NSError *error = nil;
    id<MTLLibrary> library = [device newLibraryWithSource:kMacLCColorPassShaderSource
                                                  options:nil
                                                    error:&error];
    id<MTLFunction> function = [library newFunctionWithName:@"maclc_color_pass"];
    if (function == nil) {
        NSLog(@"MacLCMetalColorPass: shader compilation failed: %@", error);
        return nil;
    }
    _pipeline = [device newComputePipelineStateWithFunction:function error:&error];
    if (_pipeline == nil)
        return nil;

    /* Until told otherwise: identity up to 10000 cd/m2. */
    for (int i = 0; i < MACLC_COLOR_PASS_LUT_SIZE; i++)
        _lut[i] = (float)i / (MACLC_COLOR_PASS_LUT_SIZE - 1);
    _lutMinPQ = 0.0f;
    _lutMaxPQ = 1.0f;
    _lutKind = MACLC_LUT_NONE;
    return self;
}

- (void)setToneParams:(const maclc_tone_params *)params
{
    if (params == NULL)
        return;
    if (_lutKind == MACLC_LUT_PICTURE && ToneParamsEqual(params, &_toneParams))
        return;

    _toneParams = *params;
    _lutKind = MACLC_LUT_PICTURE;
    _lutMinPQ = 0.0f;
    _lutMaxPQ = 1.0f;
    for (int i = 0; i < MACLC_COLOR_PASS_LUT_SIZE; i++)
        _lut[i] = maclc_tone_map_pq(params, (float)i / (MACLC_COLOR_PASS_LUT_SIZE - 1));
}

- (void)setToneCurve:(const struct maclc_tonecurve_params *)params
{
    if (params == NULL)
        return;
    if (_lutKind == MACLC_LUT_CURVE && maclc_tonecurve_params_equal(params, &_curveParams))
        return;

    /* Keep our own copy of the dynamic metadata: the caller's belongs to a
     * picture that goes away. */
    _curveParams = *params;
    if (params->hdr10plus != NULL) {
        _hdr10plus = *params->hdr10plus;
        _curveParams.hdr10plus = &_hdr10plus;
    }
    _lutKind = MACLC_LUT_CURVE;

    /* maclc_tonecurve_generate() samples [input_min, input_max] in PQ, with
     * the same defaults and HDR10+ peak it applies. */
    float in_min = params->input_min > 0.0f ? params->input_min : 0.0f;
    float in_max = params->input_max > 0.0f ? params->input_max : 1000.0f;
    if (params->hdr10plus != NULL) {
        const vlc_video_hdr_dynamic_metadata_t *h = params->hdr10plus;
        float scene_max = fmaxf(fmaxf(h->maxscl[0], h->maxscl[1]), h->maxscl[2]);
        if (scene_max > 0.0f)
            in_max = scene_max <= 1.5f ? scene_max * 10000.0f : scene_max;
    }
    _lutMinPQ = maclc_nits_to_pq(in_min);
    _lutMaxPQ = maclc_nits_to_pq(in_max);
    maclc_tonecurve_generate(&_curveParams, _lut, MACLC_COLOR_PASS_LUT_SIZE);
}

- (nullable id<MTLTexture>)encodeFrom:(id<MTLTexture>)input
                        commandBuffer:(id<MTLCommandBuffer>)commandBuffer
{
    if (input == nil || commandBuffer == nil)
        return nil;

    const NSUInteger width = input.width, height = input.height;
    if (_output == nil || _output.width != width || _output.height != height) {
        MTLTextureDescriptor *desc =
            [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA16Float
                                                               width:width
                                                              height:height
                                                           mipmapped:NO];
        desc.usage = MTLTextureUsageShaderRead | MTLTextureUsageShaderWrite;
        desc.storageMode = MTLStorageModePrivate;
        _output = [_device newTextureWithDescriptor:desc];
        if (_output == nil)
            return nil;
    }

    id<MTLComputeCommandEncoder> encoder = [commandBuffer computeCommandEncoder];
    if (encoder == nil)
        return nil;

    const MacLCColorPassUniforms uniforms = {
        .lutMinPQ = _lutMinPQ,
        .lutMaxPQ = _lutMaxPQ,
        .referenceWhite = MACLC_HDR_REFERENCE_WHITE,
        .lutSize = MACLC_COLOR_PASS_LUT_SIZE,
        .width = (uint32_t)width,
        .height = (uint32_t)height,
    };
    [encoder setComputePipelineState:_pipeline];
    [encoder setTexture:input atIndex:0];
    [encoder setTexture:_output atIndex:1];
    [encoder setBytes:&uniforms length:sizeof(uniforms) atIndex:0];
    [encoder setBytes:_lut length:sizeof(_lut) atIndex:1];

    NSUInteger w = 16, h = 16;
    while (w * h > _pipeline.maxTotalThreadsPerThreadgroup && h > 1)
        h /= 2;
    [encoder dispatchThreadgroups:MTLSizeMake((width + w - 1) / w, (height + h - 1) / h, 1)
            threadsPerThreadgroup:MTLSizeMake(w, h, 1)];
    [encoder endEncoding];
    return _output;
}

@end
