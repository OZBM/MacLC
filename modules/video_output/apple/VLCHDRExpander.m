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

/* kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange, spelled as a literal for
 * the same reason codec/vt_utils.c does: it postdates our minimum SDK. */
#define VLC_CVPX_FORMAT_P010 ((OSType)'x420')

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
    VLC_HDR_TRANSFER_GAMMA = 0,
    VLC_HDR_TRANSFER_SRGB = 1,
};

/* Must stay byte-for-byte identical to the Metal struct of the same name. */
typedef struct
{
    float gamut[12];       /* three float4 rows, only .xyz is read */
    float boost;
    float knee;
    float sdrWhiteNits;
    float inputScale;
    float gamma;
    /* De-quantisation of the source: (sample - offset) * scale. The four-character
     * code of the buffer decides these, not the elementary stream metadata. */
    float lumaOffset;
    float lumaScale;
    float chromaOffset;
    float chromaScale;
    uint32_t matrix;
    uint32_t transferMode;
    uint32_t chromaW;
    uint32_t chromaH;
    uint32_t padding[3];
} VLCHDRExpandUniforms;

_Static_assert(sizeof(VLCHDRExpandUniforms) == 112,
               "the uniform block must keep the layout the Metal struct has");

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
 * The expansion kernels. They are compiled at run time rather than shipped as a
 * metallib so that the plugin stays a single object with no extra resource to
 * install; the cost is one compilation the first time HDR expansion is switched
 * on.
 */
static NSString * const kVLCHDRExpanderShaderSource =
    @"#include <metal_stdlib>\n"
    @"using namespace metal;\n"
    @"\n"
    @"struct VLCHDRExpandUniforms {\n"
    @"    float4 gamut[3];\n"
    @"    float  boost;\n"
    @"    float  knee;\n"
    @"    float  sdrWhiteNits;\n"
    @"    float  inputScale;\n"
    @"    float  gamma;\n"
    @"    float  lumaOffset;\n"
    @"    float  lumaScale;\n"
    @"    float  chromaOffset;\n"
    @"    float  chromaScale;\n"
    @"    uint   matrix;\n"
    @"    uint   transferMode;\n"
    @"    uint   chromaW;\n"
    @"    uint   chromaH;\n"
    @"    uint   padding[3];\n"
    @"};\n"
    @"\n"
    @"static inline uint2 clamp_read(uint2 c, uint w, uint h)\n"
    @"{\n"
    @"    return uint2(min(c.x, w - 1u), min(c.y, h - 1u));\n"
    @"}\n"
    @"\n"
    @"static inline float3 ycbcr_to_rgb(float3 ycc, constant VLCHDRExpandUniforms &u)\n"
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
    @"// Electro-optical transfer function of the source, normalised so that 1.0 is\n"
    @"// SDR diffuse white. The sign is carried through so that slightly negative,\n"
    @"// out-of-gamut values survive the gamut matrix that follows.\n"
    @"static inline float eotf_channel(float v, constant VLCHDRExpandUniforms &u)\n"
    @"{\n"
    @"    float a = fabs(v);\n"
    @"    float s = (v < 0.0f) ? -1.0f : 1.0f;\n"
    @"    if (u.transferMode == 1u)\n"
    @"        return s * ((a <= 0.04045f) ? (a / 12.92f)\n"
    @"                                    : pow((a + 0.055f) / 1.055f, 2.4f));\n"
    @"    return s * pow(a, u.gamma);\n"
    @"}\n"
    @"\n"
    @"// Expands highlights into the display's headroom.\n"
    @"//\n"
    @"// Everything at or below the knee comes back untouched, so shadows and\n"
    @"// mid-tones look exactly as they do in SDR. Above it a quadratic takes over,\n"
    @"// chosen so that its value and its slope match the identity at the knee and so\n"
    @"// that SDR white lands on `boost`. The curve is applied to the largest\n"
    @"// component and the triplet is scaled by the result, which leaves hue and\n"
    @"// saturation alone.\n"
    @"static inline float3 expand_highlights(float3 rgb, float boost, float knee)\n"
    @"{\n"
    @"    float m = max(max(rgb.r, rgb.g), rgb.b);\n"
    @"    if (boost <= 1.0f || m <= knee || m <= 0.0f)\n"
    @"        return rgb;\n"
    @"\n"
    @"    float span = max(1.0f - knee, 1e-4f);\n"
    @"    float e;\n"
    @"    if (m <= 1.0f) {\n"
    @"        float t = (m - knee) / span;\n"
    @"        e = m + (boost - 1.0f) * t * t;\n"
    @"    } else {\n"
    @"        // Carry on with the slope the curve has at SDR white so that\n"
    @"        // super-white excursions stay monotonic instead of flattening.\n"
    @"        e = boost + (m - 1.0f) * (1.0f + 2.0f * (boost - 1.0f) / span);\n"
    @"    }\n"
    @"    return rgb * (e / m);\n"
    @"}\n"
    @"\n"
    @"static inline float pq_encode(float nits)\n"
    @"{\n"
    @"    const float m1 = 0.1593017578125f;\n"
    @"    const float m2 = 78.84375f;\n"
    @"    const float c1 = 0.8359375f;\n"
    @"    const float c2 = 18.8515625f;\n"
    @"    const float c3 = 18.6875f;\n"
    @"\n"
    @"    float y  = clamp(nits * (1.0f / 10000.0f), 0.0f, 1.0f);\n"
    @"    float ym = pow(y, m1);\n"
    @"    return pow((c1 + c2 * ym) / (1.0f + c3 * ym), m2);\n"
    @"}\n"
    @"\n"
    @"static inline float3 sdr_to_pq2020(float3 nonLinear,\n"
    @"                                   constant VLCHDRExpandUniforms &u)\n"
    @"{\n"
    @"    float3 lin = float3(eotf_channel(nonLinear.r, u),\n"
    @"                        eotf_channel(nonLinear.g, u),\n"
    @"                        eotf_channel(nonLinear.b, u));\n"
    @"\n"
    @"    lin = expand_highlights(lin, u.boost, u.knee);\n"
    @"\n"
    @"    float3 wide = float3(dot(u.gamut[0].xyz, lin),\n"
    @"                         dot(u.gamut[1].xyz, lin),\n"
    @"                         dot(u.gamut[2].xyz, lin));\n"
    @"    wide = max(wide, 0.0f);\n"
    @"\n"
    @"    return float3(pq_encode(wide.r * u.sdrWhiteNits),\n"
    @"                  pq_encode(wide.g * u.sdrWhiteNits),\n"
    @"                  pq_encode(wide.b * u.sdrWhiteNits));\n"
    @"}\n"
    @"\n"
    @"// 10-bit limited-range codes. CoreVideo's x420 keeps them in the top ten bits\n"
    @"// of a 16-bit word, so the code is rounded first and then scaled by 64/65535,\n"
    @"// which lands exactly on that word and leaves the bottom six bits clear.\n"
    @"static inline float encode_luma10(float3 pq)\n"
    @"{\n"
    @"    float y = 0.2627f * pq.r + 0.6780f * pq.g + 0.0593f * pq.b;\n"
    @"    return round(clamp(y * 876.0f + 64.0f, 0.0f, 1023.0f)) * (64.0f / 65535.0f);\n"
    @"}\n"
    @"\n"
    @"static inline float2 encode_chroma10(float3 pq)\n"
    @"{\n"
    @"    float y  = 0.2627f * pq.r + 0.6780f * pq.g + 0.0593f * pq.b;\n"
    @"    float cb = (pq.b - y) / 1.8814f;\n"
    @"    float cr = (pq.r - y) / 1.4746f;\n"
    @"    return round(float2(clamp(cb * 896.0f + 512.0f, 0.0f, 1023.0f),\n"
    @"                        clamp(cr * 896.0f + 512.0f, 0.0f, 1023.0f)))\n"
    @"           * (64.0f / 65535.0f);\n"
    @"}\n"
    @"\n"
    @"kernel void vlc_hdr_expand_biplanar(\n"
    @"    texture2d<float, access::read>  inLuma    [[texture(0)]],\n"
    @"    texture2d<float, access::read>  inChroma  [[texture(1)]],\n"
    @"    texture2d<float, access::write> outLuma   [[texture(2)]],\n"
    @"    texture2d<float, access::write> outChroma [[texture(3)]],\n"
    @"    constant VLCHDRExpandUniforms&  u         [[buffer(0)]],\n"
    @"    uint2 gid [[thread_position_in_grid]])\n"
    @"{\n"
    @"    if (gid.x >= u.chromaW || gid.y >= u.chromaH)\n"
    @"        return;\n"
    @"\n"
    @"    float2 cc = inChroma.read(clamp_read(gid, inChroma.get_width(),\n"
    @"                                         inChroma.get_height())).rg;\n"
    @"    cc *= u.inputScale;\n"
    @"\n"
    @"    float3 sum = float3(0.0f);\n"
    @"    for (uint i = 0u; i < 4u; ++i) {\n"
    @"        uint2 lc = gid * 2u + uint2(i & 1u, i >> 1u);\n"
    @"        float y = inLuma.read(clamp_read(lc, inLuma.get_width(),\n"
    @"                                         inLuma.get_height())).r;\n"
    @"        y *= u.inputScale;\n"
    @"\n"
    @"        float3 pq = sdr_to_pq2020(ycbcr_to_rgb(float3(y, cc.x, cc.y), u), u);\n"
    @"        sum += pq;\n"
    @"\n"
    @"        if (lc.x < outLuma.get_width() && lc.y < outLuma.get_height())\n"
    @"            outLuma.write(float4(encode_luma10(pq), 0.0f, 0.0f, 1.0f), lc);\n"
    @"    }\n"
    @"\n"
    @"    float2 c = encode_chroma10(sum * 0.25f);\n"
    @"    if (gid.x < outChroma.get_width() && gid.y < outChroma.get_height())\n"
    @"        outChroma.write(float4(c.x, c.y, 0.0f, 1.0f), gid);\n"
    @"}\n"
    @"\n"
    @"kernel void vlc_hdr_expand_rgba(\n"
    @"    texture2d<float, access::read>  inRGBA    [[texture(0)]],\n"
    @"    texture2d<float, access::write> outLuma   [[texture(1)]],\n"
    @"    texture2d<float, access::write> outChroma [[texture(2)]],\n"
    @"    constant VLCHDRExpandUniforms&  u         [[buffer(0)]],\n"
    @"    uint2 gid [[thread_position_in_grid]])\n"
    @"{\n"
    @"    if (gid.x >= u.chromaW || gid.y >= u.chromaH)\n"
    @"        return;\n"
    @"\n"
    @"    float3 sum = float3(0.0f);\n"
    @"    for (uint i = 0u; i < 4u; ++i) {\n"
    @"        uint2 lc = gid * 2u + uint2(i & 1u, i >> 1u);\n"
    @"        float3 rgb = inRGBA.read(clamp_read(lc, inRGBA.get_width(),\n"
    @"                                            inRGBA.get_height())).rgb;\n"
    @"\n"
    @"        float3 pq = sdr_to_pq2020(rgb, u);\n"
    @"        sum += pq;\n"
    @"\n"
    @"        if (lc.x < outLuma.get_width() && lc.y < outLuma.get_height())\n"
    @"            outLuma.write(float4(encode_luma10(pq), 0.0f, 0.0f, 1.0f), lc);\n"
    @"    }\n"
    @"\n"
    @"    float2 c = encode_chroma10(sum * 0.25f);\n"
    @"    if (gid.x < outChroma.get_width() && gid.y < outChroma.get_height())\n"
    @"        outChroma.write(float4(c.x, c.y, 0.0f, 1.0f), gid);\n"
    @"}\n";

@interface VLCHDRExpander ()
- (nullable instancetype)initWithObject:(vlc_object_t *)obj;
@end

@implementation VLCHDRExpander
{
    vlc_object_t *_obj;

    id<MTLDevice> _device;
    id<MTLCommandQueue> _queue;
    id<MTLComputePipelineState> _biplanarPipeline;
    id<MTLComputePipelineState> _rgbaPipeline;
    MTLStorageMode _storageMode;

    CVPixelBufferPoolRef _pool;
    size_t _poolWidth;
    size_t _poolHeight;

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
    _boost = 4.0f;
    _knee = 0.5f;

    _device = MTLCreateSystemDefaultDevice();
    if (_device == nil) {
        msg_Warn(obj, "SDR to HDR: no Metal device, expansion unavailable");
        return nil;
    }

    /* Shared storage keeps the IOSurface and the texture pointing at the same
     * memory. Where it is not available the texture is managed and its writes
     * have to be flushed back explicitly, which -expandPixelBuffer: does. */
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

    id<MTLFunction> biplanar =
        [library newFunctionWithName:@"vlc_hdr_expand_biplanar"];
    id<MTLFunction> rgba = [library newFunctionWithName:@"vlc_hdr_expand_rgba"];
    if (biplanar == nil || rgba == nil) {
        msg_Err(obj, "SDR to HDR: expansion kernels missing from the library");
        return nil;
    }

    _biplanarPipeline = [_device newComputePipelineStateWithFunction:biplanar
                                                               error:&error];
    if (_biplanarPipeline == nil) {
        msg_Err(obj, "SDR to HDR: could not create the planar pipeline: %s",
                error.localizedDescription.UTF8String ?: "unknown error");
        return nil;
    }

    _rgbaPipeline = [_device newComputePipelineStateWithFunction:rgba
                                                           error:&error];
    if (_rgbaPipeline == nil) {
        msg_Err(obj, "SDR to HDR: could not create the packed pipeline: %s",
                error.localizedDescription.UTF8String ?: "unknown error");
        return nil;
    }

    _queue = [_device newCommandQueue];
    if (_queue == nil) {
        msg_Err(obj, "SDR to HDR: could not create a Metal command queue");
        return nil;
    }

    msg_Dbg(obj, "SDR to HDR: expansion ready on Metal device \"%s\"",
            _device.name.UTF8String ?: "unknown");
    return self;
}

- (void)dealloc
{
    CVPixelBufferPoolRelease(_pool);
}

- (void)setBoost:(float)boost
{
    _boost = (boost < 1.0f) ? 1.0f : ((boost > 16.0f) ? 16.0f : boost);
}

- (void)setKnee:(float)knee
{
    _knee = (knee < 0.0f) ? 0.0f : ((knee > 0.99f) ? 0.99f : knee);
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
            msg_Warn(_obj, "SDR to HDR: picture is not IOSurface-backed, "
                           "expansion skipped");
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
        msg_Warn(_obj, "SDR to HDR: could not wrap plane %zu of an IOSurface "
                       "as a Metal texture", plane);
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
            @(VLC_CVPX_FORMAT_P010),
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
        msg_Err(_obj, "SDR to HDR: could not create a %zux%zu 10-bit pool (%d)",
                width, height, (int)err);
        _pool = NULL;
        return NO;
    }

    _poolWidth = width;
    _poolHeight = height;
    return YES;
}

/* Fills in everything about the source the shader needs in order to undo its
 * encoding. Unknown or nonsensical colorimetry falls back to BT.709, which is
 * what an untagged SDR file is in practice. */
static void FillSourceColorimetry(VLCHDRExpandUniforms *uniforms,
                                  const video_format_t *fmt,
                                  BOOL isRGB)
{
    switch (fmt->space) {
    case COLOR_SPACE_BT601:  uniforms->matrix = VLC_HDR_MATRIX_BT601;  break;
    case COLOR_SPACE_BT2020: uniforms->matrix = VLC_HDR_MATRIX_BT2020; break;
    default:                 uniforms->matrix = VLC_HDR_MATRIX_BT709;  break;
    }

    switch (fmt->transfer) {
    case TRANSFER_FUNC_SRGB:
        uniforms->transferMode = VLC_HDR_TRANSFER_SRGB;
        uniforms->gamma = 2.2f;
        break;
    case TRANSFER_FUNC_BT470_M:
        uniforms->transferMode = VLC_HDR_TRANSFER_GAMMA;
        uniforms->gamma = 2.2f;
        break;
    case TRANSFER_FUNC_BT470_BG:
        uniforms->transferMode = VLC_HDR_TRANSFER_GAMMA;
        uniforms->gamma = 2.8f;
        break;
    case TRANSFER_FUNC_LINEAR:
        uniforms->transferMode = VLC_HDR_TRANSFER_GAMMA;
        uniforms->gamma = 1.0f;
        break;
    default:
        /* BT.1886, the display transfer function BT.709 video is graded on. */
        uniforms->transferMode = VLC_HDR_TRANSFER_GAMMA;
        uniforms->gamma = 2.4f;
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
        uniforms->gamut[row * 4 + 0] = gamut[row * 3 + 0];
        uniforms->gamut[row * 4 + 1] = gamut[row * 3 + 1];
        uniforms->gamut[row * 4 + 2] = gamut[row * 3 + 2];
        uniforms->gamut[row * 4 + 3] = 0.0f;
    }

    if (isRGB) {
        /* The converter has already taken the picture to full-range RGB, so
         * the matrix is never applied; keep it defined all the same. */
        uniforms->matrix = VLC_HDR_MATRIX_BT709;
    }
}

#pragma mark - Expansion

- (nullable CVPixelBufferRef)expandPixelBuffer:(CVPixelBufferRef)pixelBuffer
                                        format:(const video_format_t *)fmt
                                      headroom:(float)headroom
{
    if (pixelBuffer == NULL || fmt == NULL)
        return NULL;

    const OSType sourceFormat = CVPixelBufferGetPixelFormatType(pixelBuffer);
    if (![self canExpandPixelFormat:sourceFormat]) {
        if (!_warnedUnsupportedFormat) {
            const char name[5] = {
                (char)(sourceFormat >> 24), (char)(sourceFormat >> 16),
                (char)(sourceFormat >> 8), (char)sourceFormat, '\0'
            };
            msg_Warn(_obj, "SDR to HDR: pixel format %s cannot be expanded, "
                           "playing it as SDR", name);
            _warnedUnsupportedFormat = YES;
        }
        return NULL;
    }

    /* Never ask for more range than the screen can show: beyond its headroom
     * the compositor would only tone-map the expansion straight back down. */
    const float available = (headroom > 1.0f) ? headroom : 1.0f;
    const float boost = (self.boost < available) ? self.boost : available;
    if (boost <= 1.0f)
        return NULL;

    const size_t width = CVPixelBufferGetWidth(pixelBuffer);
    const size_t height = CVPixelBufferGetHeight(pixelBuffer);
    if (width < 2 || height < 2)
        return NULL;

    if (![self prepareOutputPoolForWidth:width height:height])
        return NULL;

    const BOOL isRGB = (sourceFormat == kCVPixelFormatType_32BGRA);
    const BOOL is10Bit = (sourceFormat == VLC_CVPX_FORMAT_P010);

    /* Everything ARC owns is declared before the first jump to `failure`. */
    id<MTLTexture> inLuma = nil;
    id<MTLTexture> inChroma = nil;
    id<MTLTexture> inRGBA = nil;
    id<MTLTexture> outLuma = nil;
    id<MTLTexture> outChroma = nil;
    id<MTLCommandBuffer> commandBuffer = nil;
    id<MTLComputeCommandEncoder> encoder = nil;
    id<MTLComputePipelineState> pipeline =
        isRGB ? _rgbaPipeline : _biplanarPipeline;

    CVPixelBufferRef output = NULL;
    CVReturn err = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault,
                                                      _pool, &output);
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

    outLuma = [self textureFromBuffer:output
                                plane:0
                          pixelFormat:MTLPixelFormatR16Unorm
                             writable:YES];
    outChroma = [self textureFromBuffer:output
                                  plane:1
                            pixelFormat:MTLPixelFormatRG16Unorm
                               writable:YES];
    if (outLuma == nil || outChroma == nil)
        goto failure;

    VLCHDRExpandUniforms uniforms;
    memset(&uniforms, 0, sizeof(uniforms));
    uniforms.boost = boost;
    uniforms.knee = self.knee;
    uniforms.sdrWhiteNits = VLC_HDR_EXPANDER_SDR_WHITE_NITS;
    uniforms.inputScale = is10Bit ? VLC_HDR_10BIT_READ_SCALE : 1.0f;

    /* Black, white and the neutral chroma point, in the normalised scale the
     * shader reads. Which one applies is decided by the buffer's four-character
     * code, which is what actually says how the samples are quantised. */
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
    default: /* kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange */
        uniforms.lumaOffset = 16.0f / 255.0f;
        uniforms.lumaScale = 255.0f / 219.0f;
        uniforms.chromaOffset = 128.0f / 255.0f;
        uniforms.chromaScale = 255.0f / 224.0f;
        break;
    }

    FillSourceColorimetry(&uniforms, fmt, isRGB);

    const uint32_t chromaW = (uint32_t)((width + 1) / 2);
    const uint32_t chromaH = (uint32_t)((height + 1) / 2);
    uniforms.chromaW = chromaW;
    uniforms.chromaH = chromaH;

    commandBuffer = [_queue commandBuffer];
    encoder = [commandBuffer computeCommandEncoder];
    if (commandBuffer == nil || encoder == nil)
        goto failure;

    [encoder setComputePipelineState:pipeline];
    if (isRGB) {
        [encoder setTexture:inRGBA atIndex:0];
        [encoder setTexture:outLuma atIndex:1];
        [encoder setTexture:outChroma atIndex:2];
    } else {
        [encoder setTexture:inLuma atIndex:0];
        [encoder setTexture:inChroma atIndex:1];
        [encoder setTexture:outLuma atIndex:2];
        [encoder setTexture:outChroma atIndex:3];
    }
    [encoder setBytes:&uniforms length:sizeof(uniforms) atIndex:0];

    NSUInteger groupWidth = 16;
    NSUInteger groupHeight = 16;
    while (groupWidth * groupHeight > pipeline.maxTotalThreadsPerThreadgroup
           && groupHeight > 1)
        groupHeight /= 2;

    [encoder dispatchThreadgroups:
                 MTLSizeMake((chromaW + groupWidth - 1) / groupWidth,
                             (chromaH + groupHeight - 1) / groupHeight, 1)
            threadsPerThreadgroup:MTLSizeMake(groupWidth, groupHeight, 1)];
    [encoder endEncoding];

#if TARGET_OS_OSX
    if (_storageMode == MTLStorageModeManaged) {
        id<MTLBlitCommandEncoder> blit = [commandBuffer blitCommandEncoder];
        [blit synchronizeResource:outLuma];
        [blit synchronizeResource:outChroma];
        [blit endEncoding];
    }
#endif

    [commandBuffer commit];
    [commandBuffer waitUntilCompleted];

    if (commandBuffer.error != nil) {
        msg_Warn(_obj, "SDR to HDR: GPU expansion failed: %s",
                 commandBuffer.error.localizedDescription.UTF8String
                     ?: "unknown error");
        goto failure;
    }

    _lastPeakNits = VLC_HDR_EXPANDER_SDR_WHITE_NITS * boost;
    return output;

failure:
    CVPixelBufferRelease(output);
    return NULL;
}

@end
