/*****************************************************************************
 * MacLCMetalDovi.m: Metal Dolby Vision RPU decoding pipeline
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
 *****************************************************************************
 * Ported from libplacebo v7.351.0 (LGPL-2.1+):
 *   - src/shaders/colorspace.c: pl_shader_dovi_reshape
 *   - src/shaders/colorspace.c: pl_shader_decode_color (DOLBYVISION branch)
 *   - src/colorspace.c: decoding matrix construction (dovi_lms2rgb * linear)
 *   - src/include/libplacebo/colorspace.h: struct pl_dovi_metadata
 *****************************************************************************/

#ifdef HAVE_CONFIG_H
# include "config.h"
#endif

#import "MacLCMetalDovi.h"
#include "maclc_dovi.h"
#include "maclc_hdr_vars.h"

#define VLC_CVPX_FORMAT_P010 ((OSType)'x420')
#define VLC_CVPX_FORMAT_P010_FULL ((OSType)'xf20')
#define VLC_HDR_10BIT_READ_SCALE (65535.0f / 65472.0f)

/* Uniform block passed to the Metal shader buffer(0) */
typedef struct
{
    struct maclc_dovi_params params;
    uint32_t width;
    uint32_t height;
    float    inputScale;
    float    _pad;
} MacLCDoviUniforms;

_Static_assert(sizeof(struct maclc_dovi_piece) == 112,
               "maclc_dovi_piece must match the Metal struct layout");
_Static_assert(sizeof(struct maclc_dovi_comp) == 944,
               "maclc_dovi_comp must match the Metal struct layout");
_Static_assert(sizeof(struct maclc_dovi_params) == 2960,
               "maclc_dovi_params must match the Metal struct layout");
_Static_assert(sizeof(MacLCDoviUniforms) == 2976,
               "MacLCDoviUniforms must match the Metal struct layout");

/*
 * Metal shader source string for Dolby Vision decoding.
 * Line-by-line port of maclc_dovi_decode_pixel.
 */
static NSString * const kMacLCDoviShaderSource =
    @"#include <metal_stdlib>\n"
    @"using namespace metal;\n"
    @"\n"
    @"constant float PQ_M1 = 2610.0f / 16384.0f;\n"
    @"constant float PQ_M2 = (2523.0f / 4096.0f) * 128.0f;\n"
    @"constant float PQ_C1 = 3424.0f / 4096.0f;\n"
    @"constant float PQ_C2 = (2413.0f / 4096.0f) * 32.0f;\n"
    @"constant float PQ_C3 = (2392.0f / 4096.0f) * 32.0f;\n"
    @"\n"
    @"static inline float pq_to_nits(float e)\n"
    @"{\n"
    @"    if (e <= 0.0f)\n"
    @"        return 0.0f;\n"
    @"    if (e >= 1.0f)\n"
    @"        return 10000.0f;\n"
    @"    float em2 = pow(e, 1.0f / PQ_M2);\n"
    @"    float num = max(em2 - PQ_C1, 0.0f);\n"
    @"    float den = PQ_C2 - PQ_C3 * em2;\n"
    @"    if (den <= 0.0f)\n"
    @"        return 10000.0f;\n"
    @"    return clamp(pow(num / den, 1.0f / PQ_M1) * 10000.0f, 0.0f, 10000.0f);\n"
    @"}\n"
    @"\n"
    @"struct MacLCDoviPiece {\n"
    @"    uint   method;\n"
    @"    uint   mmr_order;\n"
    @"    float  poly_coef[3];\n"
    @"    float  mmr_constant;\n"
    @"    float  mmr_coef[3][7];\n"
    @"    float  _pad;\n"
    @"};\n"
    @"\n"
    @"struct MacLCDoviComp {\n"
    @"    uint   num_pivots;\n"
    @"    float  pivots[9];\n"
    @"    float  _pad[2];\n"
    @"    MacLCDoviPiece pieces[8];\n"
    @"};\n"
    @"\n"
    @"struct MacLCDoviParams {\n"
    @"    MacLCDoviComp comp[3];\n"
    @"    float  nonlinear_offset[3];\n"
    @"    float  _pad_offset;\n"
    @"    float  nonlinear[9];\n"
    @"    float  _pad_nl[3];\n"
    @"    float  linear[9];\n"
    @"    float  _pad_lin[3];\n"
    @"    float  source_min_pq;\n"
    @"    float  source_max_pq;\n"
    @"    float  source_min_nits;\n"
    @"    float  source_max_nits;\n"
    @"};\n"
    @"\n"
    @"struct MacLCDoviUniforms {\n"
    @"    MacLCDoviParams params;\n"
    @"    uint   width;\n"
    @"    uint   height;\n"
    @"    float  inputScale;\n"
    @"    float  _pad;\n"
    @"};\n"
    @"\n"
    @"kernel void maclc_dovi_decode_biplanar(\n"
    @"    texture2d<float, access::read>   inLuma   [[texture(0)]],\n"
    @"    texture2d<float, access::sample> inChroma [[texture(1)]],\n"
    @"    texture2d<float, access::write>  outRGBA  [[texture(2)]],\n"
    @"    constant MacLCDoviUniforms&      u        [[buffer(0)]],\n"
    @"    uint2 gid [[thread_position_in_grid]])\n"
    @"{\n"
    @"    if (gid.x >= u.width || gid.y >= u.height)\n"
    @"        return;\n"
    @"\n"
    @"    constexpr sampler bilinear(coord::normalized, address::clamp_to_edge, filter::linear);\n"
    @"\n"
    @"    float y = inLuma.read(gid).r * u.inputScale;\n"
    @"    float2 chromaCoord = float2((float(gid.x) * 0.5f + 0.5f) / float(inChroma.get_width()),\n"
    @"                                (float(gid.y) * 0.5f + 0.25f) / float(inChroma.get_height()));\n"
    @"    float2 cc = inChroma.sample(bilinear, chromaCoord).rg * u.inputScale;\n"
    @"\n"
    @"    float3 sig = clamp(float3(y, cc.x, cc.y), 0.0f, 1.0f);\n"
    @"    float reshaped[3];\n"
    @"\n"
    @"    for (int c = 0; c < 3; c++) {\n"
    @"        constant MacLCDoviComp &comp = u.params.comp[c];\n"
    @"        if (comp.num_pivots < 2) {\n"
    @"            reshaped[c] = sig[c];\n"
    @"            continue;\n"
    @"        }\n"
    @"\n"
    @"        float s = sig[c];\n"
    @"        int piece = 0;\n"
    @"        while (piece < int(comp.num_pivots) - 2 && s >= comp.pivots[piece + 1]) {\n"
    @"            piece++;\n"
    @"        }\n"
    @"\n"
    @"        constant MacLCDoviPiece &p = comp.pieces[piece];\n"
    @"        if (p.method == 0) {\n"
    @"            s = (p.poly_coef[2] * s + p.poly_coef[1]) * s + p.poly_coef[0];\n"
    @"        } else {\n"
    @"            s = p.mmr_constant;\n"
    @"            float4 sigX;\n"
    @"            sigX.xyz = sig.xxy * sig.yzz;\n"
    @"            sigX.w = sigX.x * sig.z;\n"
    @"\n"
    @"            s += p.mmr_coef[0][0] * sig.x +\n"
    @"                 p.mmr_coef[0][1] * sig.y +\n"
    @"                 p.mmr_coef[0][2] * sig.z;\n"
    @"            s += p.mmr_coef[0][3] * sigX.x +\n"
    @"                 p.mmr_coef[0][4] * sigX.y +\n"
    @"                 p.mmr_coef[0][5] * sigX.z +\n"
    @"                 p.mmr_coef[0][6] * sigX.w;\n"
    @"\n"
    @"            if (p.mmr_order >= 2) {\n"
    @"                float3 sig2 = sig * sig;\n"
    @"                float4 sigX2 = sigX * sigX;\n"
    @"                s += p.mmr_coef[1][0] * sig2.x +\n"
    @"                     p.mmr_coef[1][1] * sig2.y +\n"
    @"                     p.mmr_coef[1][2] * sig2.z;\n"
    @"                s += p.mmr_coef[1][3] * sigX2.x +\n"
    @"                     p.mmr_coef[1][4] * sigX2.y +\n"
    @"                     p.mmr_coef[1][5] * sigX2.z +\n"
    @"                     p.mmr_coef[1][6] * sigX2.w;\n"
    @"\n"
    @"                if (p.mmr_order >= 3) {\n"
    @"                    s += p.mmr_coef[2][0] * (sig2.x * sig.x) +\n"
    @"                         p.mmr_coef[2][1] * (sig2.y * sig.y) +\n"
    @"                         p.mmr_coef[2][2] * (sig2.z * sig.z);\n"
    @"                    s += p.mmr_coef[2][3] * (sigX2.x * sigX.x) +\n"
    @"                         p.mmr_coef[2][4] * (sigX2.y * sigX.y) +\n"
    @"                         p.mmr_coef[2][5] * (sigX2.z * sigX.z) +\n"
    @"                         p.mmr_coef[2][6] * (sigX2.w * sigX.w);\n"
    @"                }\n"
    @"            }\n"
    @"        }\n"
    @"\n"
    @"        float lo = comp.pivots[0];\n"
    @"        float hi = comp.pivots[comp.num_pivots - 1];\n"
    @"        reshaped[c] = clamp(s, lo, hi);\n"
    @"    }\n"
    @"\n"
    @"    float v[3];\n"
    @"    v[0] = reshaped[0] - u.params.nonlinear_offset[0];\n"
    @"    v[1] = reshaped[1] - u.params.nonlinear_offset[1];\n"
    @"    v[2] = reshaped[2] - u.params.nonlinear_offset[2];\n"
    @"\n"
    @"    float nonlin_rgb[3];\n"
    @"    for (int i = 0; i < 3; i++) {\n"
    @"        nonlin_rgb[i] = u.params.nonlinear[i * 3 + 0] * v[0] +\n"
    @"                        u.params.nonlinear[i * 3 + 1] * v[1] +\n"
    @"                        u.params.nonlinear[i * 3 + 2] * v[2];\n"
    @"    }\n"
    @"\n"
    @"    float pq_nits[3];\n"
    @"    pq_nits[0] = pq_to_nits(nonlin_rgb[0]);\n"
    @"    pq_nits[1] = pq_to_nits(nonlin_rgb[1]);\n"
    @"    pq_nits[2] = pq_to_nits(nonlin_rgb[2]);\n"
    @"\n"
    @"    float rgb_nits[3];\n"
    @"    for (int i = 0; i < 3; i++) {\n"
    @"        float val = u.params.linear[i * 3 + 0] * pq_nits[0] +\n"
    @"                    u.params.linear[i * 3 + 1] * pq_nits[1] +\n"
    @"                    u.params.linear[i * 3 + 2] * pq_nits[2];\n"
    @"        rgb_nits[i] = max(val, 0.0f);\n"
    @"    }\n"
    @"\n"
    @"    float3 outLight = float3(rgb_nits[0], rgb_nits[1], rgb_nits[2]) * (1.0f / 100.0f);\n"
    @"    outRGBA.write(float4(outLight, 1.0f), gid);\n"
    @"}\n";

@implementation MacLCMetalDovi {
    id<MTLDevice> _device;
    id<MTLComputePipelineState> _pipelineState;
    id<MTLTexture> _cachedOutputTexture;
    float _sourcePeakNits;
}

- (nullable instancetype)initWithDevice:(id<MTLDevice>)device
{
    self = [super init];
    if (self == nil || device == nil)
        return nil;

    _device = device;
    _sourcePeakNits = 0.0f;

    NSError *error = nil;
    id<MTLLibrary> library = [_device newLibraryWithSource:kMacLCDoviShaderSource
                                                   options:nil
                                                     error:&error];
    if (library == nil)
        return nil;

    id<MTLFunction> function = [library newFunctionWithName:@"maclc_dovi_decode_biplanar"];
    if (function == nil)
        return nil;

    _pipelineState = [_device newComputePipelineStateWithFunction:function error:&error];
    if (_pipelineState == nil)
        return nil;

    return self;
}

- (float)sourcePeakNits
{
    if (_sourcePeakNits > 0.0f)
        return _sourcePeakNits;
    return 1000.0f;
}

- (nullable id<MTLTexture>)textureFromPixelBuffer:(CVPixelBufferRef)pixelBuffer
                                            plane:(size_t)plane
                                      pixelFormat:(MTLPixelFormat)pixelFormat
                                            width:(size_t)width
                                           height:(size_t)height
                                    commandBuffer:(id<MTLCommandBuffer>)commandBuffer
                                     textureCache:(CVMetalTextureCacheRef)cache
{
    CVMetalTextureRef cvTexture = NULL;
    CVReturn err = CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault,
                                                            cache,
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
        (void)cb;
        CFRelease(cvTexture);
    }];
    return texture;
}

- (nullable id<MTLTexture>)decodePixelBuffer:(CVPixelBufferRef)pixelBuffer
                                    metadata:(const vlc_video_dovi_metadata_t *)rpu
                               commandBuffer:(id<MTLCommandBuffer>)commandBuffer
                                textureCache:(CVMetalTextureCacheRef)cache
{
    if (pixelBuffer == NULL || rpu == NULL || commandBuffer == nil || cache == NULL)
        return nil;

    const OSType sourceFormat = CVPixelBufferGetPixelFormatType(pixelBuffer);
    const BOOL is10Bit = (sourceFormat == VLC_CVPX_FORMAT_P010 ||
                          sourceFormat == VLC_CVPX_FORMAT_P010_FULL);
    const BOOL is8Bit = (sourceFormat == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange ||
                         sourceFormat == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange);

    if (!is10Bit && !is8Bit)
        return nil;

    const size_t width = CVPixelBufferGetWidth(pixelBuffer);
    const size_t height = CVPixelBufferGetHeight(pixelBuffer);
    if (width == 0 || height == 0)
        return nil;

    /* Allocate or reuse cached RGBA16Float output texture */
    if (_cachedOutputTexture == nil ||
        _cachedOutputTexture.width != width ||
        _cachedOutputTexture.height != height) {
        MTLTextureDescriptor *desc = [MTLTextureDescriptor
            texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA16Float
                                         width:width
                                        height:height
                                     mipmapped:NO];
        desc.usage = MTLTextureUsageShaderRead | MTLTextureUsageShaderWrite;
        desc.storageMode = MTLStorageModePrivate;
        _cachedOutputTexture = [_device newTextureWithDescriptor:desc];
    }
    if (_cachedOutputTexture == nil)
        return nil;

    /* Prepare Dolby Vision shader uniforms */
    MacLCDoviUniforms uniforms;
    memset(&uniforms, 0, sizeof(uniforms));
    maclc_dovi_params_from_vlc(&uniforms.params, rpu);
    uniforms.width = (uint32_t)width;
    uniforms.height = (uint32_t)height;
    uniforms.inputScale = is10Bit ? VLC_HDR_10BIT_READ_SCALE : 1.0f;

    _sourcePeakNits = uniforms.params.source_max_nits;

    /* Create input textures for luma (plane 0) and chroma (plane 1) */
    const MTLPixelFormat lumaFmt = is10Bit ? MTLPixelFormatR16Unorm : MTLPixelFormatR8Unorm;
    const MTLPixelFormat chromaFmt = is10Bit ? MTLPixelFormatRG16Unorm : MTLPixelFormatRG8Unorm;
    const size_t cWidth = CVPixelBufferGetWidthOfPlane(pixelBuffer, 1);
    const size_t cHeight = CVPixelBufferGetHeightOfPlane(pixelBuffer, 1);

    id<MTLTexture> lumaTex = [self textureFromPixelBuffer:pixelBuffer
                                                    plane:0
                                              pixelFormat:lumaFmt
                                                    width:width
                                                   height:height
                                            commandBuffer:commandBuffer
                                             textureCache:cache];
    id<MTLTexture> chromaTex = [self textureFromPixelBuffer:pixelBuffer
                                                      plane:1
                                                pixelFormat:chromaFmt
                                                      width:cWidth
                                                     height:cHeight
                                              commandBuffer:commandBuffer
                                               textureCache:cache];
    if (lumaTex == nil || chromaTex == nil)
        return nil;

    id<MTLComputeCommandEncoder> encoder = [commandBuffer computeCommandEncoder];
    if (encoder == nil)
        return nil;

    [encoder setComputePipelineState:_pipelineState];
    [encoder setTexture:lumaTex atIndex:0];
    [encoder setTexture:chromaTex atIndex:1];
    [encoder setTexture:_cachedOutputTexture atIndex:2];
    [encoder setBytes:&uniforms length:sizeof(uniforms) atIndex:0];

    MTLSize threadgroupSize = MTLSizeMake(16, 16, 1);
    MTLSize threadgroups = MTLSizeMake((width + 15) / 16, (height + 15) / 16, 1);
    [encoder dispatchThreadgroups:threadgroups threadsPerThreadgroup:threadgroupSize];
    [encoder endEncoding];

    return _cachedOutputTexture;
}

@end
