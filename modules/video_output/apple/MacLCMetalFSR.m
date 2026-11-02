/*****************************************************************************
 * MacLCMetalFSR.m: AMD FidelityFX Super Resolution 1 on the Metal output
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
 * The EASU and RCAS kernels are ported from ffx_fsr1.h and ffx_a.h of AMD
 * FidelityFX Super Resolution 1.0 (github.com/GPUOpen-Effects/FidelityFX-FSR),
 * distributed under the following licence:
 *
 * Copyright (c) 2021 Advanced Micro Devices, Inc. All rights reserved.
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.  IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 *****************************************************************************/

#import "MacLCMetalFSR.h"

#include <math.h>
#include <simd/simd.h>

/* FSR expects perceptual 0..1 values. The picture here is linear light that
 * may exceed 1.0, so edge and noise detection, and RCAS as a whole, work on
 * x / (1 + x), which keeps highlights in range; RCAS maps its result back. */
static NSString * const kFSRSource = @R"(
#include <metal_stdlib>
using namespace metal;

static inline float PrxLoRcp(float a) { return as_type<float>(0x7ef07ebbu - as_type<uint>(a)); }
static inline float PrxLoRsq(float a) { return as_type<float>(0x5f347d74u - (as_type<uint>(a) >> 1)); }
static inline float PrxMedRcp(float a)
{
    float b = as_type<float>(0x7ef19fffu - as_type<uint>(a));
    return b * (-b * a + 2.0f);
}
static inline float4 Compress(float4 x) { return x / (1.0f + x); }
static inline float3 Compress(float3 x) { return x / (1.0f + x); }

struct EasuCon { float4 con0, con1, con2, con3; };

static inline void EasuSet(thread float2 &dir, thread float &len, float2 pp,
                           bool biS, bool biT, bool biU, bool biV,
                           float lA, float lB, float lC, float lD, float lE)
{
    float w = 0.0f;
    if (biS) w = (1.0f - pp.x) * (1.0f - pp.y);
    if (biT) w = pp.x * (1.0f - pp.y);
    if (biU) w = (1.0f - pp.x) * pp.y;
    if (biV) w = pp.x * pp.y;
    float dc = lD - lC;
    float cb = lC - lB;
    float lenX = max(abs(dc), abs(cb));
    lenX = PrxLoRcp(lenX);
    float dirX = lD - lB;
    dir.x += dirX * w;
    lenX = saturate(abs(dirX) * lenX);
    lenX *= lenX;
    len += lenX * w;
    float ec = lE - lC;
    float ca = lC - lA;
    float lenY = max(abs(ec), abs(ca));
    lenY = PrxLoRcp(lenY);
    float dirY = lE - lA;
    dir.y += dirY * w;
    lenY = saturate(abs(dirY) * lenY);
    lenY *= lenY;
    len += lenY * w;
}

static inline void EasuTap(thread float3 &aC, thread float &aW, float2 off, float2 dir,
                           float2 len, float lob, float clp, float3 c)
{
    float2 v;
    v.x = (off.x * ( dir.x)) + (off.y * dir.y);
    v.y = (off.x * (-dir.y)) + (off.y * dir.x);
    v *= len;
    float d2 = v.x * v.x + v.y * v.y;
    d2 = min(d2, clp);
    float wB = (2.0f / 5.0f) * d2 - 1.0f;
    float wA = lob * d2 - 1.0f;
    wB *= wB;
    wA *= wA;
    wB = (25.0f / 16.0f) * wB - (25.0f / 16.0f - 1.0f);
    float w = wB * wA;
    aC += c * w;
    aW += w;
}

kernel void maclc_fsr_easu(texture2d<float, access::sample> src [[texture(0)]],
                           texture2d<float, access::write> dst [[texture(1)]],
                           constant EasuCon &k [[buffer(0)]],
                           uint2 ip [[thread_position_in_grid]])
{
    if (ip.x >= dst.get_width() || ip.y >= dst.get_height())
        return;
    constexpr sampler s(coord::normalized, address::clamp_to_edge, filter::linear);

    float2 pp = float2(ip) * k.con0.xy + k.con0.zw;
    float2 fp = floor(pp);
    pp -= fp;
    float2 p0 = fp * k.con1.xy + k.con1.zw;
    float2 p1 = p0 + k.con2.xy;
    float2 p2 = p0 + k.con2.zw;
    float2 p3 = p0 + k.con3.xy;
    float4 bczzR = src.gather(s, p0, int2(0), component::x);
    float4 bczzG = src.gather(s, p0, int2(0), component::y);
    float4 bczzB = src.gather(s, p0, int2(0), component::z);
    float4 ijfeR = src.gather(s, p1, int2(0), component::x);
    float4 ijfeG = src.gather(s, p1, int2(0), component::y);
    float4 ijfeB = src.gather(s, p1, int2(0), component::z);
    float4 klhgR = src.gather(s, p2, int2(0), component::x);
    float4 klhgG = src.gather(s, p2, int2(0), component::y);
    float4 klhgB = src.gather(s, p2, int2(0), component::z);
    float4 zzonR = src.gather(s, p3, int2(0), component::x);
    float4 zzonG = src.gather(s, p3, int2(0), component::y);
    float4 zzonB = src.gather(s, p3, int2(0), component::z);

    /* luma times two, on the compressed values */
    float4 bczzL = Compress(bczzB) * 0.5f + (Compress(bczzR) * 0.5f + Compress(bczzG));
    float4 ijfeL = Compress(ijfeB) * 0.5f + (Compress(ijfeR) * 0.5f + Compress(ijfeG));
    float4 klhgL = Compress(klhgB) * 0.5f + (Compress(klhgR) * 0.5f + Compress(klhgG));
    float4 zzonL = Compress(zzonB) * 0.5f + (Compress(zzonR) * 0.5f + Compress(zzonG));
    float bL = bczzL.x, cL = bczzL.y;
    float iL = ijfeL.x, jL = ijfeL.y, fL = ijfeL.z, eL = ijfeL.w;
    float kL = klhgL.x, lL = klhgL.y, hL = klhgL.z, gL = klhgL.w;
    float oL = zzonL.z, nL = zzonL.w;

    float2 dir = 0.0f;
    float len = 0.0f;
    EasuSet(dir, len, pp, true, false, false, false, bL, eL, fL, gL, jL);
    EasuSet(dir, len, pp, false, true, false, false, cL, fL, gL, hL, kL);
    EasuSet(dir, len, pp, false, false, true, false, fL, iL, jL, kL, nL);
    EasuSet(dir, len, pp, false, false, false, true, gL, jL, kL, lL, oL);

    float2 dir2 = dir * dir;
    float dirR = dir2.x + dir2.y;
    bool zro = dirR < (1.0f / 32768.0f);
    dirR = PrxLoRsq(dirR);
    dirR = zro ? 1.0f : dirR;
    dir.x = zro ? 1.0f : dir.x;
    dir *= dirR;
    len = len * 0.5f;
    len *= len;
    float stretch = (dir.x * dir.x + dir.y * dir.y) * PrxLoRcp(max(abs(dir.x), abs(dir.y)));
    float2 len2 = float2(1.0f + (stretch - 1.0f) * len, 1.0f - 0.5f * len);
    float lob = 0.5f + ((1.0f / 4.0f - 0.04f) - 0.5f) * len;
    float clp = PrxLoRcp(lob);

    float3 b = float3(bczzR.x, bczzG.x, bczzB.x), c = float3(bczzR.y, bczzG.y, bczzB.y);
    float3 i = float3(ijfeR.x, ijfeG.x, ijfeB.x), j = float3(ijfeR.y, ijfeG.y, ijfeB.y);
    float3 f = float3(ijfeR.z, ijfeG.z, ijfeB.z), e = float3(ijfeR.w, ijfeG.w, ijfeB.w);
    float3 kk = float3(klhgR.x, klhgG.x, klhgB.x), l = float3(klhgR.y, klhgG.y, klhgB.y);
    float3 h = float3(klhgR.z, klhgG.z, klhgB.z), g = float3(klhgR.w, klhgG.w, klhgB.w);
    float3 o = float3(zzonR.z, zzonG.z, zzonB.z), n = float3(zzonR.w, zzonG.w, zzonB.w);

    float3 min4 = min(min3(f, g, j), kk);
    float3 max4 = max(max3(f, g, j), kk);
    float3 aC = 0.0f;
    float aW = 0.0f;
    EasuTap(aC, aW, float2( 0.0f, -1.0f) - pp, dir, len2, lob, clp, b);
    EasuTap(aC, aW, float2( 1.0f, -1.0f) - pp, dir, len2, lob, clp, c);
    EasuTap(aC, aW, float2(-1.0f,  1.0f) - pp, dir, len2, lob, clp, i);
    EasuTap(aC, aW, float2( 0.0f,  1.0f) - pp, dir, len2, lob, clp, j);
    EasuTap(aC, aW, float2( 0.0f,  0.0f) - pp, dir, len2, lob, clp, f);
    EasuTap(aC, aW, float2(-1.0f,  0.0f) - pp, dir, len2, lob, clp, e);
    EasuTap(aC, aW, float2( 1.0f,  1.0f) - pp, dir, len2, lob, clp, kk);
    EasuTap(aC, aW, float2( 2.0f,  1.0f) - pp, dir, len2, lob, clp, l);
    EasuTap(aC, aW, float2( 2.0f,  0.0f) - pp, dir, len2, lob, clp, h);
    EasuTap(aC, aW, float2( 1.0f,  0.0f) - pp, dir, len2, lob, clp, g);
    EasuTap(aC, aW, float2( 1.0f,  2.0f) - pp, dir, len2, lob, clp, o);
    EasuTap(aC, aW, float2( 0.0f,  2.0f) - pp, dir, len2, lob, clp, n);
    /* dering: stay within the four nearest */
    float3 pix = min(max4, max(min4, aC * (1.0f / aW)));
    dst.write(float4(max(pix, 0.0f), 1.0f), ip);
}

#define FSR_RCAS_LIMIT (0.25f - (1.0f / 16.0f))

kernel void maclc_fsr_rcas(texture2d<float, access::read> src [[texture(0)]],
                           texture2d<float, access::write> dst [[texture(1)]],
                           constant float &sharp [[buffer(0)]],
                           uint2 ip [[thread_position_in_grid]])
{
    const uint w = src.get_width(), hgt = src.get_height();
    if (ip.x >= w || ip.y >= hgt)
        return;
    const int2 p = int2(ip), last = int2(w - 1, hgt - 1);
    /*  b
     * d e f
     *  h   */
    float3 b = Compress(src.read(uint2(clamp(p + int2( 0, -1), int2(0), last))).rgb);
    float3 d = Compress(src.read(uint2(clamp(p + int2(-1,  0), int2(0), last))).rgb);
    float3 e = Compress(src.read(ip).rgb);
    float3 f = Compress(src.read(uint2(clamp(p + int2( 1,  0), int2(0), last))).rgb);
    float3 h = Compress(src.read(uint2(clamp(p + int2( 0,  1), int2(0), last))).rgb);

    float bL = b.b * 0.5f + (b.r * 0.5f + b.g);
    float dL = d.b * 0.5f + (d.r * 0.5f + d.g);
    float eL = e.b * 0.5f + (e.r * 0.5f + e.g);
    float fL = f.b * 0.5f + (f.r * 0.5f + f.g);
    float hL = h.b * 0.5f + (h.r * 0.5f + h.g);
    /* noise detection (FSR_RCAS_DENOISE) */
    float nz = 0.25f * bL + 0.25f * dL + 0.25f * fL + 0.25f * hL - eL;
    nz = saturate(abs(nz) * PrxMedRcp(max3(max3(bL, dL, eL), fL, hL) - min3(min3(bL, dL, eL), fL, hL)));
    nz = -0.5f * nz + 1.0f;

    float3 mn4 = min(min3(b, d, f), h);
    float3 mx4 = max(max3(b, d, f), h);
    const float2 peakC = float2(1.0f, -1.0f * 4.0f);
    float3 hitMin = min(mn4, e) * (1.0f / (4.0f * mx4));
    float3 hitMax = (peakC.x - max(mx4, e)) * (1.0f / (4.0f * mn4 + peakC.y));
    float3 lobeRGB = max(-hitMin, hitMax);
    float lobe = max(-FSR_RCAS_LIMIT, min(max3(lobeRGB.r, lobeRGB.g, lobeRGB.b), 0.0f)) * sharp;
    lobe *= nz;
    float rcpL = PrxMedRcp(4.0f * lobe + 1.0f);
    float3 pix = (lobe * b + lobe * d + lobe * h + lobe * f + e) * rcpL;
    /* back to linear light */
    pix = clamp(pix, 0.0f, 0.9999f);
    dst.write(float4(pix / (1.0f - pix), 1.0f), ip);
}
)";

typedef struct { simd_float4 con0, con1, con2, con3; } EasuCon;

@implementation MacLCMetalFSR {
    id<MTLDevice> _device;
    id<MTLComputePipelineState> _easu, _rcas;
    id<MTLTexture> _mid, _out[2];
    NSUInteger _next;
}

- (instancetype)initWithDevice:(id<MTLDevice>)device
{
    self = [super init];
    if (self == nil)
        return nil;
    NSError *error = nil;
    id<MTLLibrary> library = [device newLibraryWithSource:kFSRSource options:nil error:&error];
    if (library == nil) {
        NSLog(@"FSR: %@", error);
        return nil;
    }
    _easu = [device newComputePipelineStateWithFunction:[library newFunctionWithName:@"maclc_fsr_easu"]
                                                  error:&error];
    _rcas = [device newComputePipelineStateWithFunction:[library newFunctionWithName:@"maclc_fsr_rcas"]
                                                  error:&error];
    if (_easu == nil || _rcas == nil) {
        NSLog(@"FSR: %@", error);
        return nil;
    }
    _device = device;
    _sharpness = 0.25f;
    return self;
}

static id<MTLTexture> Texture(id<MTLDevice> device, NSUInteger w, NSUInteger h)
{
    MTLTextureDescriptor *td =
        [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA16Float
                                                           width:w height:h mipmapped:NO];
    td.usage = MTLTextureUsageShaderRead | MTLTextureUsageShaderWrite;
    td.storageMode = MTLStorageModePrivate;
    return [device newTextureWithDescriptor:td];
}

static void Dispatch(id<MTLComputeCommandEncoder> enc, id<MTLComputePipelineState> pipe,
                     NSUInteger w, NSUInteger h)
{
    [enc setComputePipelineState:pipe];
    [enc dispatchThreadgroups:MTLSizeMake((w + 7) / 8, (h + 7) / 8, 1)
        threadsPerThreadgroup:MTLSizeMake(8, 8, 1)];
}

- (nullable id<MTLTexture>)encodeFrom:(id<MTLTexture>)texture
                                width:(NSUInteger)width
                               height:(NSUInteger)height
                        commandBuffer:(id<MTLCommandBuffer>)commandBuffer
{
    if (width < texture.width || height < texture.height)
        return nil;
    if (_mid == nil || _mid.width != width || _mid.height != height) {
        _mid = Texture(_device, width, height);
        _out[0] = Texture(_device, width, height);
        _out[1] = Texture(_device, width, height);
        if (_mid == nil || _out[0] == nil || _out[1] == nil) {
            _mid = nil;
            return nil;
        }
    }
    id<MTLTexture> out = _out[_next];
    _next ^= 1;

    /* FsrEasuCon, with the whole input as the viewport */
    const float inW = texture.width, inH = texture.height;
    const EasuCon con = {
        { inW / width, inH / height, 0.5f * inW / width - 0.5f, 0.5f * inH / height - 0.5f },
        { 1.0f / inW, 1.0f / inH, 1.0f / inW, -1.0f / inH },
        { -1.0f / inW, 2.0f / inH, 1.0f / inW, 2.0f / inH },
        { 0.0f / inW, 4.0f / inH, 0.0f, 0.0f },
    };
    /* FsrRcasCon */
    const float sharp = exp2f(-_sharpness);

    id<MTLComputeCommandEncoder> enc = [commandBuffer computeCommandEncoder];
    if (enc == nil)
        return nil;
    [enc setTexture:texture atIndex:0];
    [enc setTexture:_mid atIndex:1];
    [enc setBytes:&con length:sizeof(con) atIndex:0];
    Dispatch(enc, _easu, width, height);
    [enc setTexture:_mid atIndex:0];
    [enc setTexture:out atIndex:1];
    [enc setBytes:&sharp length:sizeof(sharp) atIndex:0];
    Dispatch(enc, _rcas, width, height);
    [enc endEncoding];
    return out;
}

@end
