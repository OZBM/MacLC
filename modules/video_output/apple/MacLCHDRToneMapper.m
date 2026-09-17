/*****************************************************************************
 * MacLCHDRToneMapper.m: GPU picture-mode tone mapping of PQ and HLG video
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

#import "MacLCHDRToneMapper.h"
#include "maclc_hdr_vars.h"

#import <Metal/Metal.h>
#import <IOSurface/IOSurface.h>

/* kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange, spelled as a literal like
 * VLCHDRExpander.m does. */
#define MACLC_CVPX_FORMAT_P010 ((OSType)'x420')
/* kCVPixelFormatType_64RGBAHalf */
#define MACLC_CVPX_FORMAT_RGBA_HALF ((OSType)'RGhA')

/* The ten bits of x420 sit at the top of a 16-bit word, so a normalised 16-bit
 * read yields code/65472 rather than code/1023. */
#define MACLC_10BIT_READ_SCALE (65535.0f / 65472.0f)

/* Must stay byte-for-byte identical to the Metal struct of the same name. */
typedef struct
{
    float contentPeak;
    float displayPeak;
    float gain;
    float kneePQ;
    float srcPeakPQ;
    float dstPeakPQ;
    float inputScale;
    float outputScale;
    uint32_t mode;
    uint32_t identity;
    uint32_t width;
    uint32_t height;
    uint32_t transfer;   /* MACLC_TONE_SOURCE_PQ or MACLC_TONE_SOURCE_HLG */
    float hlgPeak;
    float hlgGamma;
    uint32_t padding;
} MacLCToneMapUniforms;

_Static_assert(sizeof(MacLCToneMapUniforms) == 64,
               "the uniform block must keep the layout the Metal struct has");

enum
{
    MACLC_TONE_SOURCE_PQ = 0,
    MACLC_TONE_SOURCE_HLG = 1,
};

/*
 * The kernel. maclc_tone_map_pq() and the HLG functions below are
 * line-by-line ports of the functions of the same names in maclc_tonemap.h,
 * which is the tested reference: keep them in step when either changes.
 */
static NSString * const kMacLCToneMapperShaderSource =
    @"#include <metal_stdlib>\n"
    @"using namespace metal;\n"
    @"\n"
    @"struct MacLCToneMapUniforms {\n"
    @"    float contentPeak;\n"
    @"    float displayPeak;\n"
    @"    float gain;\n"
    @"    float kneePQ;\n"
    @"    float srcPeakPQ;\n"
    @"    float dstPeakPQ;\n"
    @"    float inputScale;\n"
    @"    float outputScale;\n"
    @"    uint  mode;\n"
    @"    uint  identity;\n"
    @"    uint  width;\n"
    @"    uint  height;\n"
    @"    uint  transfer;\n"
    @"    float hlgPeak;\n"
    @"    float hlgGamma;\n"
    @"    uint  padding;\n"
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
    @"    if (e <= 0.0f) return 0.0f;\n"
    @"    if (e >= 1.0f) return 10000.0f;\n"
    @"    float em2 = pow(e, 1.0f / PQ_M2);\n"
    @"    float num = max(em2 - PQ_C1, 0.0f);\n"
    @"    float den = PQ_C2 - PQ_C3 * em2;\n"
    @"    if (den <= 0.0f) return 10000.0f;\n"
    @"    return clamp(pow(num / den, 1.0f / PQ_M1) * 10000.0f, 0.0f, 10000.0f);\n"
    @"}\n"
    @"\n"
    @"static inline float nits_to_pq(float nits)\n"
    @"{\n"
    @"    if (nits <= 0.0f) return 0.0f;\n"
    @"    if (nits >= 10000.0f) return 1.0f;\n"
    @"    float ym1 = pow(nits / 10000.0f, PQ_M1);\n"
    @"    return clamp(pow((PQ_C1 + PQ_C2 * ym1) / (1.0f + PQ_C3 * ym1), PQ_M2), 0.0f, 1.0f);\n"
    @"}\n"
    @"\n"
    @"constant float HLG_A = 0.17883277f;\n"
    @"constant float HLG_B = 0.28466892f;\n"
    @"constant float HLG_C = 0.55991073f;\n"
    @"\n"
    @"static inline float hlg_to_scene(float e)\n"
    @"{\n"
    @"    if (e <= 0.0f) return 0.0f;\n"
    @"    e = min(e, 1.0f);\n"
    @"    if (e <= 0.5f) return e * e / 3.0f;\n"
    @"    return (exp((e - HLG_C) / HLG_A) + HLG_B) / 12.0f;\n"
    @"}\n"
    @"\n"
    @"/* BT.2100 HLG OOTF for a display of nominal peak hlgPeak and zero\n"
    @" * black level, in cd/m2. */\n"
    @"static inline float3 hlg_to_nits(float3 v, constant MacLCToneMapUniforms &u)\n"
    @"{\n"
    @"    float3 s = float3(hlg_to_scene(v.r), hlg_to_scene(v.g), hlg_to_scene(v.b));\n"
    @"    float ys = dot(s, float3(0.2627f, 0.6780f, 0.0593f));\n"
    @"    if (ys <= 0.0f) return float3(0.0f);\n"
    @"    return s * (u.hlgPeak * pow(ys, u.hlgGamma - 1.0f));\n"
    @"}\n"
    @"\n"
    @"static inline float bt2390_hermite(float E1, float ks, float maxLum)\n"
    @"{\n"
    @"    if (E1 <= ks) return E1;\n"
    @"    if (E1 >= 1.0f) return maxLum;\n"
    @"    float denom = 1.0f - ks;\n"
    @"    if (denom <= 0.0f) return maxLum;\n"
    @"    float T = (E1 - ks) / denom;\n"
    @"    float T2 = T * T;\n"
    @"    float T3 = T2 * T;\n"
    @"    float h00 = 2.0f * T3 - 3.0f * T2 + 1.0f;\n"
    @"    float h10 = T3 - 2.0f * T2 + T;\n"
    @"    float h01 = -2.0f * T3 + 3.0f * T2;\n"
    @"    return clamp(h00 * ks + h10 * denom + h01 * maxLum, ks, maxLum);\n"
    @"}\n"
    @"\n"
    @"static inline float maclc_tone_map_pq(constant MacLCToneMapUniforms &u, float pq)\n"
    @"{\n"
    @"    if (pq <= 0.0f) return 0.0f;\n"
    @"    if (u.identity != 0u) return min(pq, u.dstPeakPQ);\n"
    @"\n"
    @"    if (u.mode == 1u) { /* ACCURATE */\n"
    @"        float e = min(pq, 1.0f);\n"
    @"        float eK = u.kneePQ;\n"
    @"        float eD = u.dstPeakPQ;\n"
    @"        if (e <= eK) return min(e, eD);\n"
    @"        float delta = eD - eK;\n"
    @"        if (delta <= 0.0f) return eD;\n"
    @"        float o = eK + delta * (1.0f - exp(-(e - eK) / delta));\n"
    @"        return clamp(o, 0.0f, eD);\n"
    @"    }\n"
    @"\n"
    @"    /* BALANCED and BRIGHT */\n"
    @"    if (u.kneePQ >= 1.0f || u.contentPeak * u.gain <= u.displayPeak) {\n"
    @"        if (u.gain == 1.0f) return min(pq, u.dstPeakPQ);\n"
    @"        float g = pq_to_nits(pq) * u.gain;\n"
    @"        if (g >= u.displayPeak) return u.dstPeakPQ;\n"
    @"        return min(nits_to_pq(g), u.dstPeakPQ);\n"
    @"    }\n"
    @"    if (u.srcPeakPQ <= 0.0f) return 0.0f;\n"
    @"\n"
    @"    float E;\n"
    @"    if (u.gain == 1.0f) {\n"
    @"        E = min(pq, 1.0f);\n"
    @"    } else {\n"
    @"        float g = pq_to_nits(pq) * u.gain;\n"
    @"        if (g >= u.contentPeak * u.gain || g >= 10000.0f) return u.dstPeakPQ;\n"
    @"        E = nits_to_pq(g);\n"
    @"    }\n"
    @"\n"
    @"    float E1 = E / u.srcPeakPQ;\n"
    @"    float ks = u.kneePQ;\n"
    @"    if (E1 <= ks) {\n"
    @"        if (u.gain == 1.0f) return min(pq, u.dstPeakPQ);\n"
    @"        return min(E, u.dstPeakPQ);\n"
    @"    }\n"
    @"    if (E1 >= 1.0f) return u.dstPeakPQ;\n"
    @"\n"
    @"    float maxLum = u.dstPeakPQ / u.srcPeakPQ;\n"
    @"    float Eout = bt2390_hermite(E1, ks, maxLum) * u.srcPeakPQ;\n"
    @"    return clamp(Eout, 0.0f, u.dstPeakPQ);\n"
    @"}\n"
    @"\n"
    @"/* BT.2020 non-constant-luminance, 10-bit limited range. */\n"
    @"static inline float3 decode_ycc(float y, float2 c)\n"
    @"{\n"
    @"    float Y  = (y - 64.0f / 1023.0f) * (1023.0f / 876.0f);\n"
    @"    float Cb = (c.x - 512.0f / 1023.0f) * (1023.0f / 896.0f);\n"
    @"    float Cr = (c.y - 512.0f / 1023.0f) * (1023.0f / 896.0f);\n"
    @"    float r = Y + 1.4746f * Cr;\n"
    @"    float b = Y + 1.8814f * Cb;\n"
    @"    float g = (Y - 0.2627f * r - 0.0593f * b) / 0.6780f;\n"
    @"    return clamp(float3(r, g, b), 0.0f, 1.0f);\n"
    @"}\n"
    @"\n"
    @"/* Curve on the largest component (m, in PQ), linear triplet scaled by the\n"
    @" * result: brightness changes, hue and saturation do not. Takes and returns\n"
    @" * cd/m2. */\n"
    @"static inline float3 tone_map_nits(float3 nits, float m, constant MacLCToneMapUniforms &u)\n"
    @"{\n"
    @"    float inNits = max(max(nits.r, nits.g), nits.b);\n"
    @"    if (m <= 0.0f || inNits <= 0.0f) return float3(0.0f);\n"
    @"    return nits * (pq_to_nits(maclc_tone_map_pq(u, m)) / inNits);\n"
    @"}\n"
    @"\n"
    @"kernel void maclc_tone_map_to_linear(\n"
    @"    texture2d<float, access::read>   inLuma   [[texture(0)]],\n"
    @"    texture2d<float, access::sample> inChroma [[texture(1)]],\n"
    @"    texture2d<float, access::write>  outRGBA  [[texture(2)]],\n"
    @"    constant MacLCToneMapUniforms&   u        [[buffer(0)]],\n"
    @"    uint2 gid [[thread_position_in_grid]])\n"
    @"{\n"
    @"    if (gid.x >= u.width || gid.y >= u.height)\n"
    @"        return;\n"
    @"\n"
    @"    constexpr sampler bilinear(coord::normalized, address::clamp_to_edge,\n"
    @"                               filter::linear);\n"
    @"    float y = inLuma.read(gid).r * u.inputScale;\n"
    @"    /* 4:2:0 chroma, co-sited with the left luma sample and centred\n"
    @"     * between the two rows (the HEVC and BT.2020 default). */\n"
    @"    float2 pos = float2((float(gid.x) * 0.5f + 0.5f) / float(inChroma.get_width()),\n"
    @"                        (float(gid.y) * 0.5f + 0.25f) / float(inChroma.get_height()));\n"
    @"    float2 c = inChroma.sample(bilinear, pos).rg * u.inputScale;\n"
    @"\n"
    @"    float3 v = decode_ycc(y, c);\n"
    @"    float3 nits;\n"
    @"    float m;\n"
    @"    if (u.transfer == 1u) {\n"
    @"        nits = hlg_to_nits(v, u);\n"
    @"        m = nits_to_pq(max(max(nits.r, nits.g), nits.b));\n"
    @"    } else {\n"
    @"        nits = float3(pq_to_nits(v.r), pq_to_nits(v.g), pq_to_nits(v.b));\n"
    @"        m = max(max(v.r, v.g), v.b);\n"
    @"    }\n"
    @"    outRGBA.write(float4(tone_map_nits(nits, m, u) * u.outputScale, 1.0f), gid);\n"
    @"}\n";

@interface MacLCHDRToneMapper ()
- (nullable instancetype)initWithObject:(vlc_object_t *)obj;
@end

@implementation MacLCHDRToneMapper
{
    vlc_object_t *_obj;

    id<MTLDevice> _device;
    id<MTLCommandQueue> _queue;
    id<MTLComputePipelineState> _pipeline;
    MTLStorageMode _storageMode;

    CVPixelBufferPoolRef _pool;
    size_t _poolWidth;
    size_t _poolHeight;

    BOOL _warnedNoIOSurface;
    BOOL _warnedTextureFailure;
}

+ (nullable instancetype)toneMapperForObject:(vlc_object_t *)obj
{
    return [[MacLCHDRToneMapper alloc] initWithObject:obj];
}

- (nullable instancetype)initWithObject:(vlc_object_t *)obj
{
    self = [super init];
    if (self == nil)
        return nil;

    _obj = obj;

    _device = MTLCreateSystemDefaultDevice();
    if (_device == nil) {
        msg_Warn(obj, "HDR picture modes: no Metal device, tone mapping unavailable");
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
        [_device newLibraryWithSource:kMacLCToneMapperShaderSource
                              options:nil
                                error:&error];
    if (library == nil) {
        msg_Err(obj, "HDR picture modes: shader compilation failed: %s",
                error.localizedDescription.UTF8String ?: "unknown error");
        return nil;
    }

    id<MTLFunction> function =
        [library newFunctionWithName:@"maclc_tone_map_to_linear"];
    if (function == nil) {
        msg_Err(obj, "HDR picture modes: kernel missing from the library");
        return nil;
    }

    _pipeline = [_device newComputePipelineStateWithFunction:function
                                                       error:&error];
    if (_pipeline == nil) {
        msg_Err(obj, "HDR picture modes: could not create the pipeline: %s",
                error.localizedDescription.UTF8String ?: "unknown error");
        return nil;
    }

    _queue = [_device newCommandQueue];
    if (_queue == nil) {
        msg_Err(obj, "HDR picture modes: could not create a Metal command queue");
        return nil;
    }

    msg_Dbg(obj, "HDR picture modes: tone mapper ready on \"%s\"",
            _device.name.UTF8String ?: "unknown");
    return self;
}

- (void)dealloc
{
    CVPixelBufferPoolRelease(_pool);
}

- (BOOL)canToneMapPixelFormat:(OSType)pixelFormat
{
    return pixelFormat == MACLC_CVPX_FORMAT_P010;
}

- (nullable id<MTLTexture>)textureFromBuffer:(CVPixelBufferRef)buffer
                                       plane:(size_t)plane
                                 pixelFormat:(MTLPixelFormat)pixelFormat
                                    writable:(BOOL)writable
{
    IOSurfaceRef surface = CVPixelBufferGetIOSurface(buffer);
    if (surface == NULL) {
        if (!_warnedNoIOSurface) {
            msg_Warn(_obj, "HDR picture modes: picture is not IOSurface-backed, "
                           "shown without MacLC's tone mapping");
            _warnedNoIOSurface = YES;
        }
        return nil;
    }

    const bool planar = IOSurfaceGetPlaneCount(surface) > 0;
    const size_t width = planar ? IOSurfaceGetWidthOfPlane(surface, plane)
                                : IOSurfaceGetWidth(surface);
    const size_t height = planar ? IOSurfaceGetHeightOfPlane(surface, plane)
                                 : IOSurfaceGetHeight(surface);
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
        msg_Warn(_obj, "HDR picture modes: could not wrap plane %zu as a "
                       "Metal texture", plane);
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
        (__bridge NSString *)kCVPixelBufferPixelFormatTypeKey:
            @(MACLC_CVPX_FORMAT_RGBA_HALF),
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
        msg_Err(_obj, "HDR picture modes: could not create a %zux%zu pool (%d)",
                width, height, (int)err);
        _pool = NULL;
        return NO;
    }

    _poolWidth = width;
    _poolHeight = height;
    return YES;
}

- (nullable CVPixelBufferRef)toneMapPixelBuffer:(CVPixelBufferRef)pixelBuffer
                                       transfer:(video_transfer_func_t)transfer
                                        hlgPeak:(float)hlgPeak
                                         params:(const maclc_tone_params *)params
                                 referenceWhite:(float)referenceWhite
{
    if (pixelBuffer == NULL || params == NULL || referenceWhite <= 0.0f)
        return NULL;
    if (transfer != TRANSFER_FUNC_SMPTE_ST2084 && transfer != TRANSFER_FUNC_HLG)
        return NULL;
    if (![self canToneMapPixelFormat:CVPixelBufferGetPixelFormatType(pixelBuffer)])
        return NULL;

    const size_t width = CVPixelBufferGetWidth(pixelBuffer);
    const size_t height = CVPixelBufferGetHeight(pixelBuffer);
    if (width < 2 || height < 2)
        return NULL;
    if (![self prepareOutputPoolForWidth:width height:height])
        return NULL;

    /* Everything ARC owns is declared before the first jump to `failure`. */
    id<MTLTexture> inLuma = nil;
    id<MTLTexture> inChroma = nil;
    id<MTLTexture> outRGBA = nil;
    id<MTLCommandBuffer> commandBuffer = nil;
    id<MTLComputeCommandEncoder> encoder = nil;

    CVPixelBufferRef output = NULL;
    CVReturn err = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault,
                                                      _pool, &output);
    if (err != kCVReturnSuccess || output == NULL)
        return NULL;

    inLuma = [self textureFromBuffer:pixelBuffer plane:0
                         pixelFormat:MTLPixelFormatR16Unorm writable:NO];
    inChroma = [self textureFromBuffer:pixelBuffer plane:1
                           pixelFormat:MTLPixelFormatRG16Unorm writable:NO];
    outRGBA = [self textureFromBuffer:output plane:0
                          pixelFormat:MTLPixelFormatRGBA16Float writable:YES];
    if (inLuma == nil || inChroma == nil || outRGBA == nil)
        goto failure;

    MacLCToneMapUniforms uniforms;
    memset(&uniforms, 0, sizeof(uniforms));
    uniforms.contentPeak = params->content_peak;
    uniforms.displayPeak = params->display_peak;
    uniforms.gain = params->gain;
    uniforms.kneePQ = params->knee_pq;
    uniforms.srcPeakPQ = params->src_peak_pq;
    uniforms.dstPeakPQ = params->dst_peak_pq;
    uniforms.inputScale = MACLC_10BIT_READ_SCALE;
    uniforms.outputScale = 1.0f / referenceWhite;
    uniforms.mode = (uint32_t)params->mode;
    uniforms.identity = params->identity ? 1u : 0u;
    uniforms.width = (uint32_t)MIN(width, outRGBA.width);
    uniforms.height = (uint32_t)MIN(height, outRGBA.height);
    uniforms.transfer = (transfer == TRANSFER_FUNC_HLG) ? MACLC_TONE_SOURCE_HLG
                                                        : MACLC_TONE_SOURCE_PQ;
    uniforms.hlgPeak = (hlgPeak > 0.0f) ? hlgPeak : MACLC_HDR_HLG_PEAK;
    uniforms.hlgGamma = maclc_hlg_system_gamma(uniforms.hlgPeak);

    commandBuffer = [_queue commandBuffer];
    encoder = [commandBuffer computeCommandEncoder];
    if (commandBuffer == nil || encoder == nil)
        goto failure;

    [encoder setComputePipelineState:_pipeline];
    [encoder setTexture:inLuma atIndex:0];
    [encoder setTexture:inChroma atIndex:1];
    [encoder setTexture:outRGBA atIndex:2];
    [encoder setBytes:&uniforms length:sizeof(uniforms) atIndex:0];

    NSUInteger groupWidth = 16;
    NSUInteger groupHeight = 16;
    while (groupWidth * groupHeight > _pipeline.maxTotalThreadsPerThreadgroup
           && groupHeight > 1)
        groupHeight /= 2;

    [encoder dispatchThreadgroups:
                 MTLSizeMake((uniforms.width + groupWidth - 1) / groupWidth,
                             (uniforms.height + groupHeight - 1) / groupHeight, 1)
            threadsPerThreadgroup:MTLSizeMake(groupWidth, groupHeight, 1)];
    [encoder endEncoding];

#if TARGET_OS_OSX
    if (_storageMode == MTLStorageModeManaged) {
        id<MTLBlitCommandEncoder> blit = [commandBuffer blitCommandEncoder];
        [blit synchronizeResource:outRGBA];
        [blit endEncoding];
    }
#endif

    [commandBuffer commit];
    [commandBuffer waitUntilCompleted];

    if (commandBuffer.error != nil) {
        msg_Warn(_obj, "HDR picture modes: GPU pass failed: %s",
                 commandBuffer.error.localizedDescription.UTF8String
                     ?: "unknown error");
        goto failure;
    }

    /* Linear light keeps the source's BT.2020 primaries; the compositor
     * converts them to the display. */
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
