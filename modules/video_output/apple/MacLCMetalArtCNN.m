/*****************************************************************************
 * MacLCMetalArtCNN.m: ArtCNN C4F16, a 2x luma doubler for anime, on Metal
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
 *
 * The network and its weights (maclc_artcnn_c4f16.h) are ArtCNN by João
 * Chrisóstomo, under the MIT licence quoted in that header.
 *****************************************************************************/

#import "MacLCMetalArtCNN.h"

#include "maclc_artcnn_c4f16.h"

/* The graph of ArtCNN_C4F16.onnx, every convolution 3x3 with zero padding:
 * conv0 1->16; conv1..4 16->16 + ReLU; conv5 16->16, plus conv0's output;
 * conv6 16->4; depth-to-space 2 (DCR); clip to [0, 1]. Sixteen channels are
 * held as a 4-slice RGBA16Float texture array. */
static NSString * const kArtCNNSource = @R"(
#include <metal_stdlib>
using namespace metal;

/* luma in [0, 1] from the plane value, and back */
struct Range { float scale; float offset; };

kernel void maclc_cnn_in(texture2d<half, access::read> y [[texture(0)]],
                         texture2d_array<half, access::write> out [[texture(1)]],
                         constant half4 *w [[buffer(0)]],     /* [tap*4 + outSlice] */
                         constant float4 *b [[buffer(1)]],
                         constant Range &range [[buffer(2)]],
                         uint2 gid [[thread_position_in_grid]])
{
    const int2 size = int2(y.get_width(), y.get_height());
    if (gid.x >= uint(size.x) || gid.y >= uint(size.y))
        return;
    float4 acc[4] = { b[0], b[1], b[2], b[3] };
    for (int t = 0; t < 9; t++) {
        const int2 p = int2(gid) + int2(t % 3 - 1, t / 3 - 1);
        if (any(p < 0) || any(p >= size))
            continue;
        const float v = float(y.read(uint2(p)).r) * range.scale + range.offset;
        for (int s = 0; s < 4; s++)
            acc[s] += float4(w[t * 4 + s]) * v;
    }
    for (int s = 0; s < 4; s++)
        out.write(half4(acc[s]), gid, s);
}

/* relu: conv1..4; otherwise conv5, which adds `skip` */
kernel void maclc_cnn_mid(texture2d_array<half, access::read> in [[texture(0)]],
                          texture2d_array<half, access::write> out [[texture(1)]],
                          texture2d_array<half, access::read> skip [[texture(2)]],
                          constant half4 *w [[buffer(0)]],    /* [(tap*4 + inSlice)*16 + out] */
                          constant float *b [[buffer(1)]],
                          constant uint &relu [[buffer(2)]],
                          uint2 gid [[thread_position_in_grid]])
{
    const int2 size = int2(in.get_width(), in.get_height());
    if (gid.x >= uint(size.x) || gid.y >= uint(size.y))
        return;
    float acc[16];
    for (int o = 0; o < 16; o++)
        acc[o] = b[o];
    for (int t = 0; t < 9; t++) {
        const int2 p = int2(gid) + int2(t % 3 - 1, t / 3 - 1);
        if (any(p < 0) || any(p >= size))
            continue;
        for (int s = 0; s < 4; s++) {
            const half4 v = in.read(uint2(p), s);
            constant half4 *ws = w + (t * 4 + s) * 16;
            for (int o = 0; o < 16; o++)
                acc[o] += float(dot(ws[o], v));
        }
    }
    for (int s = 0; s < 4; s++) {
        float4 r = float4(acc[4 * s], acc[4 * s + 1], acc[4 * s + 2], acc[4 * s + 3]);
        r = relu != 0 ? max(r, 0.0f) : r + float4(skip.read(gid, s));
        out.write(half4(r), gid, s);
    }
}

kernel void maclc_cnn_out(texture2d_array<half, access::read> in [[texture(0)]],
                          texture2d<half, access::write> y2 [[texture(1)]],
                          constant half4 *w [[buffer(0)]],    /* [(tap*4 + inSlice)*4 + out] */
                          constant float4 &b [[buffer(1)]],
                          constant Range &range [[buffer(2)]],
                          uint2 gid [[thread_position_in_grid]])
{
    const int2 size = int2(in.get_width(), in.get_height());
    if (gid.x >= uint(size.x) || gid.y >= uint(size.y))
        return;
    float4 acc = b;
    for (int t = 0; t < 9; t++) {
        const int2 p = int2(gid) + int2(t % 3 - 1, t / 3 - 1);
        if (any(p < 0) || any(p >= size))
            continue;
        for (int s = 0; s < 4; s++) {
            const half4 v = in.read(uint2(p), s);
            constant half4 *ws = w + (t * 4 + s) * 4;
            acc += float4(dot(ws[0], v), dot(ws[1], v), dot(ws[2], v), dot(ws[3], v));
        }
    }
    /* depth-to-space, DCR: channel i*2 + j goes to (2x + j, 2y + i) */
    const float4 v = clamp(acc, 0.0f, 1.0f) * range.scale + range.offset;
    y2.write(half4(v.x), uint2(gid.x * 2,     gid.y * 2));
    y2.write(half4(v.y), uint2(gid.x * 2 + 1, gid.y * 2));
    y2.write(half4(v.z), uint2(gid.x * 2,     gid.y * 2 + 1));
    y2.write(half4(v.w), uint2(gid.x * 2 + 1, gid.y * 2 + 1));
}
)";

struct Range { float scale, offset; };

/* Offsets of each layer in maclc_artcnn_c4f16: weights, then biases. */
static const struct { int offset, in, out; } kLayers[7] = {
    {     0,  1, 16 }, {   160, 16, 16 }, {  2480, 16, 16 }, {  4800, 16, 16 },
    {  7120, 16, 16 }, {  9440, 16, 16 }, { 11760, 16,  4 },
};

@implementation MacLCMetalArtCNN {
    id<MTLDevice> _device;
    id<MTLComputePipelineState> _in, _mid, _out;
    id<MTLBuffer> _weights[7], _biases[7];
    id<MTLTexture> _a, _b, _skip;
}

/* Repacks layer `l` as half4s over input channels (or, for conv0, over
 * outputs), in the order the kernels read them. */
static NSData *PackWeights(int l)
{
    const float *base = maclc_artcnn_c4f16 + kLayers[l].offset;
    const int in = kLayers[l].in, out = kLayers[l].out;
    NSMutableData *data = [NSMutableData dataWithLength:9 * 4 * (in == 1 ? 1 : out) * 4 * sizeof(__fp16)];
    __fp16 *dst = data.mutableBytes;
    for (int t = 0; t < 9; t++)
        for (int s = 0; s < 4; s++) {
            if (in == 1) {
                for (int k = 0; k < 4; k++)
                    *dst++ = (__fp16)base[(4 * s + k) * 9 + t];
                continue;
            }
            for (int o = 0; o < out; o++)
                for (int k = 0; k < 4; k++)
                    *dst++ = (__fp16)base[(o * in + 4 * s + k) * 9 + t];
        }
    return data;
}

- (instancetype)initWithDevice:(id<MTLDevice>)device
{
    _Static_assert(MACLC_ARTCNN_C4F16_COUNT == 11760 + 16 * 4 * 9 + 4, "weights layout");
    self = [super init];
    if (self == nil)
        return nil;
    _device = device;
    NSError *error = nil;
    id<MTLLibrary> library = [device newLibraryWithSource:kArtCNNSource options:nil error:&error];
    if (library == nil) {
        NSLog(@"ArtCNN: %@", error);
        return nil;
    }
    _in = [device newComputePipelineStateWithFunction:[library newFunctionWithName:@"maclc_cnn_in"] error:&error];
    _mid = [device newComputePipelineStateWithFunction:[library newFunctionWithName:@"maclc_cnn_mid"] error:&error];
    _out = [device newComputePipelineStateWithFunction:[library newFunctionWithName:@"maclc_cnn_out"] error:&error];
    if (_in == nil || _mid == nil || _out == nil)
        return nil;
    for (int l = 0; l < 7; l++) {
        NSData *w = PackWeights(l);
        _weights[l] = [device newBufferWithBytes:w.bytes length:w.length options:MTLResourceStorageModeShared];
        const float *bias = maclc_artcnn_c4f16 + kLayers[l].offset + kLayers[l].in * kLayers[l].out * 9;
        _biases[l] = [device newBufferWithBytes:bias length:kLayers[l].out * sizeof(float)
                                        options:MTLResourceStorageModeShared];
        if (_weights[l] == nil || _biases[l] == nil)
            return nil;
    }
    return self;
}

static void Dispatch(id<MTLComputeCommandEncoder> enc, id<MTLComputePipelineState> pipe,
                     NSUInteger w, NSUInteger h)
{
    [enc setComputePipelineState:pipe];
    const MTLSize group = MTLSizeMake(8, 8, 1);
    [enc dispatchThreadgroups:MTLSizeMake((w + 7) / 8, (h + 7) / 8, 1) threadsPerThreadgroup:group];
}

- (BOOL)encodeLuma:(id<MTLTexture>)y
                to:(id<MTLTexture>)y2
        videoRange:(BOOL)videoRange
     commandBuffer:(id<MTLCommandBuffer>)commandBuffer
{
    const NSUInteger w = y.width, h = y.height;
    if (y2.width < 2 * w || y2.height < 2 * h)
        return NO;
    if (_a == nil || _a.width != w || _a.height != h) {
        MTLTextureDescriptor *td = [MTLTextureDescriptor new];
        td.textureType = MTLTextureType2DArray;
        td.pixelFormat = MTLPixelFormatRGBA16Float;
        td.width = w;
        td.height = h;
        td.arrayLength = 4;
        td.usage = MTLTextureUsageShaderRead | MTLTextureUsageShaderWrite;
        td.storageMode = MTLStorageModePrivate;
        _a = [_device newTextureWithDescriptor:td];
        _b = [_device newTextureWithDescriptor:td];
        _skip = [_device newTextureWithDescriptor:td];
        if (_a == nil || _b == nil || _skip == nil) {
            _a = nil;
            return NO;
        }
    }

    const struct Range toUnit = videoRange ? (struct Range){ 255.0f / 219.0f, -16.0f / 219.0f }
                                           : (struct Range){ 1.0f, 0.0f };
    const struct Range toPlane = videoRange ? (struct Range){ 219.0f / 255.0f, 16.0f / 255.0f }
                                            : (struct Range){ 1.0f, 0.0f };

    id<MTLComputeCommandEncoder> enc = [commandBuffer computeCommandEncoder];
    if (enc == nil)
        return NO;
    [enc setTexture:y atIndex:0];
    [enc setTexture:_skip atIndex:1];
    [enc setBuffer:_weights[0] offset:0 atIndex:0];
    [enc setBuffer:_biases[0] offset:0 atIndex:1];
    [enc setBytes:&toUnit length:sizeof(toUnit) atIndex:2];
    Dispatch(enc, _in, w, h);

    /* conv1..5: skip -> a -> b -> a -> b -> a (conv5 adds skip) */
    id<MTLTexture> src = _skip, dst = _a;
    for (int l = 1; l <= 5; l++) {
        const uint32_t relu = l < 5;
        [enc setTexture:src atIndex:0];
        [enc setTexture:dst atIndex:1];
        [enc setTexture:_skip atIndex:2];
        [enc setBuffer:_weights[l] offset:0 atIndex:0];
        [enc setBuffer:_biases[l] offset:0 atIndex:1];
        [enc setBytes:&relu length:sizeof(relu) atIndex:2];
        Dispatch(enc, _mid, w, h);
        src = dst;
        dst = dst == _a ? _b : _a;
    }

    [enc setTexture:src atIndex:0];
    [enc setTexture:y2 atIndex:1];
    [enc setBuffer:_weights[6] offset:0 atIndex:0];
    [enc setBuffer:_biases[6] offset:0 atIndex:1];
    [enc setBytes:&toPlane length:sizeof(toPlane) atIndex:2];
    Dispatch(enc, _out, w, h);
    [enc endEncoding];
    return YES;
}

@end
