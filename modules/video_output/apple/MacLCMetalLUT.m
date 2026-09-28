/*****************************************************************************
 * MacLCMetalLUT.m: Metal 3D LUT parser and application (.cube)
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

#include <vlc_common.h>
#import "MacLCMetalLUT.h"
#import <simd/simd.h>

typedef struct {
    float domainMin[4];
    float domainMax[4];
    float lutSize;
    uint32_t width;
    uint32_t height;
    float _pad;
} LUTUniforms;

_Static_assert(sizeof(LUTUniforms) == 48,
               "LUTUniforms must be 48 bytes (16-byte aligned)");

#pragma mark - Shaders Source

static NSString * const kLUTShaderSource =
    @"#include <metal_stdlib>\n"
    @"using namespace metal;\n"
    @"\n"
    @"struct LUTUniforms {\n"
    @"    float4 domainMin;\n"
    @"    float4 domainMax;\n"
    @"    float  lutSize;\n"
    @"    uint   width;\n"
    @"    uint   height;\n"
    @"    float  _pad;\n"
    @"};\n"
    @"\n"
    @"static inline float lin_to_srgb(float c) {\n"
    @"    return (c <= 0.0031308f) ? (c * 12.92f) : (1.055f * pow(c, 1.0f / 2.4f) - 0.055f);\n"
    @"}\n"
    @"\n"
    @"static inline float srgb_to_lin(float c) {\n"
    @"    return (c <= 0.04045f) ? (c / 12.92f) : pow((c + 0.055f) / 1.055f, 2.4f);\n"
    @"}\n"
    @"\n"
    @"kernel void vlc_metal_apply_lut(\n"
    @"    texture2d<float, access::read_write> tex   [[texture(0)]],\n"
    @"    texture3d<float, access::sample>     lut3D [[texture(1)]],\n"
    @"    sampler                              s     [[sampler(0)]],\n"
    @"    constant LUTUniforms&                u     [[buffer(0)]],\n"
    @"    uint2 gid [[thread_position_in_grid]])\n"
    @"{\n"
    @"    if (gid.x >= u.width || gid.y >= u.height)\n"
    @"        return;\n"
    @"\n"
    @"    float4 color = tex.read(gid);\n"
    @"    float3 lin = color.rgb;\n"
    @"\n"
    @"    /* EDR handling: pass values above 1.0 through scaled */\n"
    @"    float maxVal = max(lin.r, max(lin.g, lin.b));\n"
    @"    float edrScale = (maxVal > 1.0f) ? maxVal : 1.0f;\n"
    @"    float3 unitLin = lin / edrScale;\n"
    @"\n"
    @"    /* Convert linear Display P3 to non-linear domain (sRGB transfer curve) */\n"
    @"    float3 nonLin = float3(\n"
    @"        lin_to_srgb(clamp(unitLin.r, 0.0f, 1.0f)),\n"
    @"        lin_to_srgb(clamp(unitLin.g, 0.0f, 1.0f)),\n"
    @"        lin_to_srgb(clamp(unitLin.b, 0.0f, 1.0f))\n"
    @"    );\n"
    @"\n"
    @"    /* Normalize to LUT domain [DOMAIN_MIN, DOMAIN_MAX] */\n"
    @"    float3 span = u.domainMax.xyz - u.domainMin.xyz;\n"
    @"    if (span.x <= 0.0f) span.x = 1.0f;\n"
    @"    if (span.y <= 0.0f) span.y = 1.0f;\n"
    @"    if (span.z <= 0.0f) span.z = 1.0f;\n"
    @"    float3 normCoord = clamp((nonLin - u.domainMin.xyz) / span, 0.0f, 1.0f);\n"
    @"\n"
    @"    /* Hardware trilinear voxel sampling offset: center of 0 is 0.5/N, center of N-1 is (N-0.5)/N */\n"
    @"    float3 lutCoord = (normCoord * (u.lutSize - 1.0f) + 0.5f) / u.lutSize;\n"
    @"    float4 lutSample = lut3D.sample(s, lutCoord);\n"
    @"    float3 lutNonLin = lutSample.rgb;\n"
    @"\n"
    @"    /* Convert non-linear LUT result back to linear */\n"
    @"    float3 lutLin = float3(\n"
    @"        srgb_to_lin(clamp(lutNonLin.r, 0.0f, 1.0f)),\n"
    @"        srgb_to_lin(clamp(lutNonLin.g, 0.0f, 1.0f)),\n"
    @"        srgb_to_lin(clamp(lutNonLin.b, 0.0f, 1.0f))\n"
    @"    );\n"
    @"\n"
    @"    /* Rescale back to EDR luminance */\n"
    @"    float3 finalColor = lutLin * edrScale;\n"
    @"    tex.write(float4(finalColor, color.a), gid);\n"
    @"}\n";

#pragma mark - MacLCMetalLUT Implementation

@implementation MacLCMetalLUT {
    id<MTLDevice> _device;
    id<MTLTexture> _lut3DTexture;
    id<MTLComputePipelineState> _computePSO;
    id<MTLSamplerState> _trilinearSampler;

    simd_float3 _domainMin;
    simd_float3 _domainMax;
    NSUInteger _lutSize;
}

+ (nullable instancetype)lutWithCubeFile:(NSString *)path
                                  device:(id<MTLDevice>)device
                                   error:(NSError **)error
{
    if (path == nil || device == nil) {
        if (error) {
            *error = [NSError errorWithDomain:@"MacLCMetalLUT"
                                         code:-1
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid arguments"}];
        }
        return nil;
    }

    NSString *content = [NSString stringWithContentsOfFile:path
                                                  encoding:NSUTF8StringEncoding
                                                     error:error];
    if (content == nil)
        return nil;

    NSUInteger lutSize = 0;
    simd_float3 domainMin = simd_make_float3(0.0f, 0.0f, 0.0f);
    simd_float3 domainMax = simd_make_float3(1.0f, 1.0f, 1.0f);

    NSArray<NSString *> *lines = [content componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];

    /* 1. Parse header keywords */
    NSUInteger dataStartIndex = 0;
    for (NSUInteger lineIdx = 0; lineIdx < lines.count; ++lineIdx) {
        NSString *line = [lines[lineIdx] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (line.length == 0 || [line hasPrefix:@"#"])
            continue;

        if ([line hasPrefix:@"TITLE"]) {
            continue;
        } else if ([line hasPrefix:@"LUT_3D_SIZE"]) {
            NSArray<NSString *> *parts = [line componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            if (parts.count >= 2) {
                lutSize = (NSUInteger)[parts[1] integerValue];
            }
        } else if ([line hasPrefix:@"DOMAIN_MIN"]) {
            float r = 0.0f, g = 0.0f, b = 0.0f;
            if (sscanf(line.UTF8String, "DOMAIN_MIN %f %f %f", &r, &g, &b) == 3) {
                domainMin = simd_make_float3(r, g, b);
            }
        } else if ([line hasPrefix:@"DOMAIN_MAX"]) {
            float r = 1.0f, g = 1.0f, b = 1.0f;
            if (sscanf(line.UTF8String, "DOMAIN_MAX %f %f %f", &r, &g, &b) == 3) {
                domainMax = simd_make_float3(r, g, b);
            }
        } else {
            /* First line that is not a recognized keyword or comment is data */
            dataStartIndex = lineIdx;
            break;
        }
    }

    if (lutSize < 2 || lutSize > 256) {
        if (error) {
            *error = [NSError errorWithDomain:@"MacLCMetalLUT"
                                         code:-2
                                     userInfo:@{NSLocalizedDescriptionKey:
                                                    [NSString stringWithFormat:@"Invalid or missing LUT_3D_SIZE: %lu", (unsigned long)lutSize]}];
        }
        return nil;
    }

    NSUInteger totalEntries = lutSize * lutSize * lutSize;
    simd_float4 *lutData = malloc(totalEntries * sizeof(simd_float4));
    if (lutData == NULL) {
        if (error) {
            *error = [NSError errorWithDomain:@"MacLCMetalLUT"
                                         code:-3
                                     userInfo:@{NSLocalizedDescriptionKey: @"Out of memory allocating LUT buffer"}];
        }
        return nil;
    }

    /* 2. Parse data points (r, g, b in [0, 1]) */
    NSUInteger entryCount = 0;
    for (NSUInteger lineIdx = dataStartIndex; lineIdx < lines.count && entryCount < totalEntries; ++lineIdx) {
        NSString *line = [lines[lineIdx] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (line.length == 0 || [line hasPrefix:@"#"])
            continue;

        float r = 0.0f, g = 0.0f, b = 0.0f;
        if (sscanf(line.UTF8String, "%f %f %f", &r, &g, &b) == 3) {
            lutData[entryCount++] = simd_make_float4(r, g, b, 1.0f);
        }
    }

    if (entryCount != totalEntries) {
        free(lutData);
        if (error) {
            *error = [NSError errorWithDomain:@"MacLCMetalLUT"
                                         code:-4
                                     userInfo:@{NSLocalizedDescriptionKey:
                                                    [NSString stringWithFormat:@"Incomplete LUT data: expected %lu entries, found %lu",
                                                                               (unsigned long)totalEntries, (unsigned long)entryCount]}];
        }
        return nil;
    }

    /* 3. Upload 3D texture */
    MTLTextureDescriptor *tDesc = [[MTLTextureDescriptor alloc] init];
    tDesc.textureType = MTLTextureType3D;
    tDesc.pixelFormat = MTLPixelFormatRGBA32Float;
    tDesc.width = lutSize;
    tDesc.height = lutSize;
    tDesc.depth = lutSize;
    tDesc.mipmapLevelCount = 1;
    tDesc.usage = MTLTextureUsageShaderRead;
    tDesc.storageMode = MTLStorageModeManaged;

    id<MTLTexture> lut3DTex = [device newTextureWithDescriptor:tDesc];
    if (lut3DTex == nil) {
        free(lutData);
        if (error) {
            *error = [NSError errorWithDomain:@"MacLCMetalLUT"
                                         code:-5
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to create 3D Metal texture"}];
        }
        return nil;
    }

    [lut3DTex replaceRegion:MTLRegionMake3D(0, 0, 0, lutSize, lutSize, lutSize)
                mipmapLevel:0
                      slice:0
                  withBytes:lutData
                bytesPerRow:lutSize * sizeof(simd_float4)
              bytesPerImage:lutSize * lutSize * sizeof(simd_float4)];

    free(lutData);

    /* 4. Compile compute pipeline */
    id<MTLLibrary> library = [device newLibraryWithSource:kLUTShaderSource options:nil error:error];
    if (library == nil)
        return nil;

    id<MTLFunction> lutFunc = [library newFunctionWithName:@"vlc_metal_apply_lut"];
    if (lutFunc == nil) {
        if (error) {
            *error = [NSError errorWithDomain:@"MacLCMetalLUT"
                                         code:-6
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to find vlc_metal_apply_lut shader function"}];
        }
        return nil;
    }

    id<MTLComputePipelineState> computePSO = [device newComputePipelineStateWithFunction:lutFunc error:error];
    if (computePSO == nil)
        return nil;

    /* 5. Create trilinear sampler */
    MTLSamplerDescriptor *sDesc = [[MTLSamplerDescriptor alloc] init];
    sDesc.minFilter = MTLSamplerMinMagFilterLinear;
    sDesc.magFilter = MTLSamplerMinMagFilterLinear;
    sDesc.mipFilter = MTLSamplerMipFilterLinear;
    sDesc.sAddressMode = MTLSamplerAddressModeClampToEdge;
    sDesc.tAddressMode = MTLSamplerAddressModeClampToEdge;
    sDesc.rAddressMode = MTLSamplerAddressModeClampToEdge;
    id<MTLSamplerState> sampler = [device newSamplerStateWithDescriptor:sDesc];

    MacLCMetalLUT *lut = [[MacLCMetalLUT alloc] init];
    lut->_device = device;
    lut->_lut3DTexture = lut3DTex;
    lut->_computePSO = computePSO;
    lut->_trilinearSampler = sampler;
    lut->_domainMin = domainMin;
    lut->_domainMax = domainMax;
    lut->_lutSize = lutSize;

    return lut;
}

- (void)encodeApplyTo:(id<MTLTexture>)texture commandBuffer:(id<MTLCommandBuffer>)commandBuffer
{
    if (texture == nil || commandBuffer == nil)
        return;

    if (_lut3DTexture == nil || _computePSO == nil)
        return;

    const NSUInteger width = texture.width;
    const NSUInteger height = texture.height;
    if (width == 0 || height == 0)
        return;

    LUTUniforms u;
    memset(&u, 0, sizeof(u));
    u.domainMin[0] = _domainMin.x;
    u.domainMin[1] = _domainMin.y;
    u.domainMin[2] = _domainMin.z;
    u.domainMin[3] = 0.0f;

    u.domainMax[0] = _domainMax.x;
    u.domainMax[1] = _domainMax.y;
    u.domainMax[2] = _domainMax.z;
    u.domainMax[3] = 0.0f;

    u.lutSize = (float)_lutSize;
    u.width = (uint32_t)width;
    u.height = (uint32_t)height;

    id<MTLComputeCommandEncoder> encoder = [commandBuffer computeCommandEncoder];
    if (encoder == nil)
        return;

    [encoder setComputePipelineState:_computePSO];
    [encoder setTexture:texture atIndex:0];
    [encoder setTexture:_lut3DTexture atIndex:1];
    [encoder setSamplerState:_trilinearSampler atIndex:0];
    [encoder setBytes:&u length:sizeof(u) atIndex:0];

    MTLSize threadgroupSize = MTLSizeMake(16, 16, 1);
    MTLSize threadgroups = MTLSizeMake((width + 15) / 16, (height + 15) / 16, 1);
    [encoder dispatchThreadgroups:threadgroups threadsPerThreadgroup:threadgroupSize];
    [encoder endEncoding];
}

@end
