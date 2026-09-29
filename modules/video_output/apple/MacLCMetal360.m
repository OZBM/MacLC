/*****************************************************************************
 * MacLCMetal360.m: Metal 360 projection (equirectangular, cubemap) and stereo
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
#import "MacLCMetal360.h"
#import <simd/simd.h>
#include <math.h>

#define SPHERE_RADIUS 1.0f
#define SPHERE_LAT_BANDS 128
#define SPHERE_LON_BANDS 128

typedef struct {
    float position[3];
    float texCoord[2];
} Metal360Vertex;

_Static_assert(sizeof(Metal360Vertex) == 20,
               "Metal360Vertex must be 20 bytes (3 floats pos + 2 floats uv)");

typedef struct {
    simd_float4x4 mvp;
} Metal360Uniforms;

_Static_assert(sizeof(Metal360Uniforms) == 64,
               "Metal360Uniforms must be 64 bytes");

#pragma mark - Shaders Source

static NSString * const k360ShaderSource =
    @"#include <metal_stdlib>\n"
    @"using namespace metal;\n"
    @"\n"
    @"struct VertexIn {\n"
    @"    float3 position [[attribute(0)]];\n"
    @"    float2 texCoord [[attribute(1)]];\n"
    @"};\n"
    @"\n"
    @"struct VertexOut {\n"
    @"    float4 position [[position]];\n"
    @"    float2 texCoord;\n"
    @"};\n"
    @"\n"
    @"struct Uniforms360 {\n"
    @"    float4x4 mvp;\n"
    @"};\n"
    @"\n"
    @"vertex VertexOut vlc_metal_360_vertex(\n"
    @"    VertexIn in [[stage_in]],\n"
    @"    constant Uniforms360 &u [[buffer(1)]])\n"
    @"{\n"
    @"    VertexOut out;\n"
    @"    out.position = u.mvp * float4(in.position, 1.0f);\n"
    @"    out.texCoord = in.texCoord;\n"
    @"    return out;\n"
    @"}\n"
    @"\n"
    @"fragment float4 vlc_metal_360_fragment(\n"
    @"    VertexOut in [[stage_in]],\n"
    @"    texture2d<float, access::sample> tex [[texture(0)]],\n"
    @"    sampler s [[sampler(0)]])\n"
    @"{\n"
    @"    return tex.sample(s, in.texCoord);\n"
    @"}\n";

#pragma mark - MacLCMetal360 Implementation

@implementation MacLCMetal360 {
    id<MTLDevice> _device;
    id<MTLRenderPipelineState> _pipelineState;
    id<MTLSamplerState> _samplerLinear;

    video_projection_mode_t _projectionMode;
    vlc_viewpoint_t _viewpoint;

    id<MTLBuffer> _sphereVertexBuffer;
    id<MTLBuffer> _sphereIndexBuffer;
    NSUInteger _sphereIndexCount;

    id<MTLBuffer> _cubeVertexBuffer;
    id<MTLBuffer> _cubeIndexBuffer;
    NSUInteger _cubeIndexCount;
}

- (nullable instancetype)initWithDevice:(id<MTLDevice>)device
                            pixelFormat:(MTLPixelFormat)format
{
    self = [super init];
    if (self == nil || device == nil)
        return nil;

    _device = device;
    _projectionMode = PROJECTION_MODE_EQUIRECTANGULAR;
    vlc_viewpoint_init(&_viewpoint);

    NSError *error = nil;
    id<MTLLibrary> library = [_device newLibraryWithSource:k360ShaderSource options:nil error:&error];
    if (library == nil) {
        NSLog(@"MacLCMetal360: shader compile failed: %@", error.localizedDescription);
        return nil;
    }

    id<MTLFunction> vertFunc = [library newFunctionWithName:@"vlc_metal_360_vertex"];
    id<MTLFunction> fragFunc = [library newFunctionWithName:@"vlc_metal_360_fragment"];
    if (vertFunc == nil || fragFunc == nil)
        return nil;

    MTLVertexDescriptor *vDesc = [MTLVertexDescriptor vertexDescriptor];
    vDesc.attributes[0].format = MTLVertexFormatFloat3;
    vDesc.attributes[0].offset = offsetof(Metal360Vertex, position);
    vDesc.attributes[0].bufferIndex = 0;

    vDesc.attributes[1].format = MTLVertexFormatFloat2;
    vDesc.attributes[1].offset = offsetof(Metal360Vertex, texCoord);
    vDesc.attributes[1].bufferIndex = 0;

    vDesc.layouts[0].stride = sizeof(Metal360Vertex);
    vDesc.layouts[0].stepFunction = MTLVertexStepFunctionPerVertex;

    MTLRenderPipelineDescriptor *pDesc = [[MTLRenderPipelineDescriptor alloc] init];
    pDesc.vertexFunction = vertFunc;
    pDesc.fragmentFunction = fragFunc;
    pDesc.vertexDescriptor = vDesc;
    pDesc.colorAttachments[0].pixelFormat = format;

    _pipelineState = [_device newRenderPipelineStateWithDescriptor:pDesc error:&error];
    if (_pipelineState == nil) {
        NSLog(@"MacLCMetal360: pipeline state failed: %@", error.localizedDescription);
        return nil;
    }

    MTLSamplerDescriptor *sDesc = [[MTLSamplerDescriptor alloc] init];
    sDesc.minFilter = MTLSamplerMinMagFilterLinear;
    sDesc.magFilter = MTLSamplerMinMagFilterLinear;
    sDesc.sAddressMode = MTLSamplerAddressModeClampToEdge;
    sDesc.tAddressMode = MTLSamplerAddressModeClampToEdge;
    _samplerLinear = [_device newSamplerStateWithDescriptor:sDesc];

    [self buildSphereMesh];
    [self buildCubeMesh];

    return self;
}

- (void)buildSphereMesh
{
    const unsigned nbLat = SPHERE_LAT_BANDS;
    const unsigned nbLon = SPHERE_LON_BANDS;
    const NSUInteger nbVertices = (nbLat + 1) * (nbLon + 1);
    const NSUInteger nbIndices = nbLat * nbLon * 6;

    Metal360Vertex *vertices = malloc(nbVertices * sizeof(Metal360Vertex));
    uint16_t *indices = malloc(nbIndices * sizeof(uint16_t));
    if (vertices == NULL || indices == NULL) {
        free(vertices);
        free(indices);
        return;
    }

    for (unsigned lat = 0; lat <= nbLat; lat++) {
        float theta = (float)lat * (float)M_PI / (float)nbLat;
        float sinTheta = sinf(theta);
        float cosTheta = cosf(theta);

        for (unsigned lon = 0; lon <= nbLon; lon++) {
            float phi = 2.0f * (float)M_PI * (float)lon / (float)nbLon;
            float sinPhi = sinf(phi);
            float cosPhi = cosf(phi);

            float x = -sinPhi * sinTheta;
            float y = cosTheta;
            float z = cosPhi * sinTheta;

            float u = (float)lon / (float)nbLon;
            float v = (float)lat / (float)nbLat;

            unsigned idx = lat * (nbLon + 1) + lon;
            vertices[idx].position[0] = SPHERE_RADIUS * x;
            vertices[idx].position[1] = SPHERE_RADIUS * y;
            vertices[idx].position[2] = SPHERE_RADIUS * z;
            vertices[idx].texCoord[0] = u;
            vertices[idx].texCoord[1] = v;
        }
    }

    unsigned off = 0;
    for (unsigned lat = 0; lat < nbLat; lat++) {
        for (unsigned lon = 0; lon < nbLon; lon++) {
            uint16_t first = (uint16_t)((lat * (nbLon + 1)) + lon);
            uint16_t second = (uint16_t)(first + nbLon + 1);

            indices[off++] = first;
            indices[off++] = second;
            indices[off++] = (uint16_t)(first + 1);

            indices[off++] = second;
            indices[off++] = (uint16_t)(second + 1);
            indices[off++] = (uint16_t)(first + 1);
        }
    }

    _sphereVertexBuffer = [_device newBufferWithBytes:vertices
                                               length:nbVertices * sizeof(Metal360Vertex)
                                              options:MTLResourceStorageModeShared];
    _sphereIndexBuffer = [_device newBufferWithBytes:indices
                                              length:nbIndices * sizeof(uint16_t)
                                             options:MTLResourceStorageModeShared];
    _sphereIndexCount = nbIndices;

    free(vertices);
    free(indices);
}

- (void)buildCubeMesh
{
    const NSUInteger nbVertices = 4 * 6;
    const NSUInteger nbIndices = 6 * 6;

    Metal360Vertex vertices[24];
    static const float kPos[24][3] = {
        /* FRONT (Z = -1) */
        { -1.0f,  1.0f, -1.0f },
        { -1.0f, -1.0f, -1.0f },
        {  1.0f,  1.0f, -1.0f },
        {  1.0f, -1.0f, -1.0f },
        /* BACK (Z = +1) */
        { -1.0f,  1.0f,  1.0f },
        { -1.0f, -1.0f,  1.0f },
        {  1.0f,  1.0f,  1.0f },
        {  1.0f, -1.0f,  1.0f },
        /* LEFT (X = -1) */
        { -1.0f,  1.0f,  1.0f },
        { -1.0f, -1.0f,  1.0f },
        { -1.0f,  1.0f, -1.0f },
        { -1.0f, -1.0f, -1.0f },
        /* RIGHT (X = +1) */
        {  1.0f,  1.0f, -1.0f },
        {  1.0f, -1.0f, -1.0f },
        {  1.0f,  1.0f,  1.0f },
        {  1.0f, -1.0f,  1.0f },
        /* BOTTOM (Y = -1) */
        { -1.0f, -1.0f, -1.0f },
        { -1.0f, -1.0f,  1.0f },
        {  1.0f, -1.0f, -1.0f },
        {  1.0f, -1.0f,  1.0f },
        /* TOP (Y = +1) */
        { -1.0f,  1.0f,  1.0f },
        { -1.0f,  1.0f, -1.0f },
        {  1.0f,  1.0f,  1.0f },
        {  1.0f,  1.0f, -1.0f },
    };

    const float col[4] = { 0.0f, 1.0f / 3.0f, 2.0f / 3.0f, 1.0f };
    const float row[3] = { 0.0f, 0.5f, 1.0f };

    /* 3x2 standard cubemap texture coordinate layout (Metal V: 0 top, 1 bottom) */
    static const float kTex[24][2] = {
        /* FRONT */
        { 1.0f/3.0f, 0.5f }, { 1.0f/3.0f, 1.0f }, { 2.0f/3.0f, 0.5f }, { 2.0f/3.0f, 1.0f },
        /* BACK */
        { 1.0f,      0.5f }, { 1.0f,      1.0f }, { 2.0f/3.0f, 0.5f }, { 2.0f/3.0f, 1.0f },
        /* LEFT */
        { 2.0f/3.0f, 0.0f }, { 2.0f/3.0f, 0.5f }, { 1.0f/3.0f, 0.0f }, { 1.0f/3.0f, 0.5f },
        /* RIGHT */
        { 0.0f,      0.0f }, { 0.0f,      0.5f }, { 1.0f/3.0f, 0.0f }, { 1.0f/3.0f, 0.5f },
        /* BOTTOM */
        { 0.0f,      0.5f }, { 0.0f,      1.0f }, { 1.0f/3.0f, 0.5f }, { 1.0f/3.0f, 1.0f },
        /* TOP */
        { 2.0f/3.0f, 0.0f }, { 2.0f/3.0f, 0.5f }, { 1.0f,      0.0f }, { 1.0f,      0.5f },
    };
    VLC_UNUSED(col); VLC_UNUSED(row);

    for (int i = 0; i < 24; ++i) {
        vertices[i].position[0] = kPos[i][0];
        vertices[i].position[1] = kPos[i][1];
        vertices[i].position[2] = kPos[i][2];
        vertices[i].texCoord[0] = kTex[i][0];
        vertices[i].texCoord[1] = kTex[i][1];
    }

    static const uint16_t ind[36] = {
        0,  1,  2,      2,  1,  3,  /* front */
        6,  7,  4,      4,  7,  5,  /* back */
        10, 11, 8,      8,  11, 9,  /* left */
        12, 13, 14,     14, 13, 15, /* right */
        18, 19, 16,     16, 19, 17, /* bottom */
        20, 21, 22,     22, 21, 23, /* top */
    };

    _cubeVertexBuffer = [_device newBufferWithBytes:vertices
                                             length:nbVertices * sizeof(Metal360Vertex)
                                            options:MTLResourceStorageModeShared];
    _cubeIndexBuffer = [_device newBufferWithBytes:ind
                                            length:nbIndices * sizeof(uint16_t)
                                           options:MTLResourceStorageModeShared];
    _cubeIndexCount = nbIndices;
}

- (void)setProjection:(video_projection_mode_t)mode
{
    _projectionMode = mode;
}

- (void)setViewpoint:(const vlc_viewpoint_t *)viewpoint
{
    if (viewpoint != NULL)
        _viewpoint = *viewpoint;
}

- (CGRect)sourceRectForStereoMode:(vlc_stereoscopic_mode_t)stereoMode
                    multiviewMode:(video_multiview_mode_t)multiviewMode
{
    return MacLCStereoSourceRect(stereoMode, multiviewMode);
}

- (CGRect)sourceRectForStereoMode:(vlc_stereoscopic_mode_t)stereoMode
                    multiviewMode:(video_multiview_mode_t)multiviewMode
                     textureWidth:(size_t)width
                    textureHeight:(size_t)height
{
    CGRect norm = MacLCStereoSourceRect(stereoMode, multiviewMode);
    return CGRectMake(norm.origin.x * (double)width,
                      norm.origin.y * (double)height,
                      norm.size.width * (double)width,
                      norm.size.height * (double)height);
}

- (void)encodeFrom:(id<MTLTexture>)input
     renderEncoder:(id<MTLRenderCommandEncoder>)encoder
          destRect:(CGRect)destRect
      drawableSize:(CGSize)drawableSize
               sar:(float)sar
{
    if (input == nil || encoder == nil)
        return;

    if (destRect.size.width <= 0.0 || destRect.size.height <= 0.0)
        return;

    float effectiveSar = (sar > 0.001f) ? sar : ((float)destRect.size.width / (float)destRect.size.height);

    float fovxDeg = VLC_CLIP(_viewpoint.fov, FIELD_OF_VIEW_DEGREES_MIN, FIELD_OF_VIEW_DEGREES_MAX);
    float f_fovx = fovxDeg * (float)M_PI / 180.0f;
    float f_fovy = 2.0f * atanf(tanf(f_fovx * 0.5f) / effectiveSar);

    /* Zoom calculation based on FOV to prevent seeing black border corners */
    float tan_fovx_2 = tanf(f_fovx * 0.5f);
    float tan_fovy_2 = tanf(f_fovy * 0.5f);
    float z_min = -SPHERE_RADIUS / sinf(atanf(sqrtf(tan_fovx_2 * tan_fovx_2 + tan_fovy_2 * tan_fovy_2)));
    const float z_thresh = 90.0f * (float)M_PI / 180.0f;

    float f_z = 0.0f;
    if (f_fovx > z_thresh) {
        float f = z_min / ((FIELD_OF_VIEW_DEGREES_MAX * (float)M_PI / 180.0f) - z_thresh);
        f_z = f * f_fovx - f * z_thresh;
        if (f_z < z_min)
            f_z = z_min;
    }

    /* Projection matrix (perspective with Metal [0, 1] clip depth) */
    float zFar = 1000.0f;
    float zNear = 0.01f;
    float f = 1.0f / tanf(f_fovy * 0.5f);

    simd_float4x4 projMatrix = matrix_identity_float4x4;
    projMatrix.columns[0] = simd_make_float4(f / effectiveSar, 0.0f, 0.0f, 0.0f);
    projMatrix.columns[1] = simd_make_float4(0.0f, f, 0.0f, 0.0f);
    projMatrix.columns[2] = simd_make_float4(0.0f, 0.0f, zFar / (zNear - zFar), -1.0f);
    projMatrix.columns[3] = simd_make_float4(0.0f, 0.0f, (zNear * zFar) / (zNear - zFar), 0.0f);

    /* Zoom matrix: translation along Z */
    simd_float4x4 zoomMatrix = matrix_identity_float4x4;
    zoomMatrix.columns[3] = simd_make_float4(0.0f, 0.0f, f_z, 1.0f);

    /* View matrix from viewpoint */
    float rawView[16];
    vlc_viewpoint_to_4x4(&_viewpoint, rawView);
    simd_float4x4 viewMatrix;
    memcpy(&viewMatrix, rawView, sizeof(viewMatrix));

    /* Model-View-Projection matrix */
    simd_float4x4 mvp = matrix_multiply(projMatrix, matrix_multiply(zoomMatrix, viewMatrix));

    Metal360Uniforms uniforms;
    uniforms.mvp = mvp;

    MTLViewport vp = {
        .originX = destRect.origin.x,
        .originY = destRect.origin.y,
        .width   = destRect.size.width,
        .height  = destRect.size.height,
        .znear   = 0.0,
        .zfar    = 1.0
    };
    [encoder setViewport:vp];

    /* The scissor rect must lie within the drawable: a zoomed view starts
     * left of or above it. */
    const double x0 = fmax(0.0, floor(CGRectGetMinX(destRect)));
    const double y0 = fmax(0.0, floor(CGRectGetMinY(destRect)));
    const double x1 = fmin(drawableSize.width, ceil(CGRectGetMaxX(destRect)));
    const double y1 = fmin(drawableSize.height, ceil(CGRectGetMaxY(destRect)));
    if (x1 <= x0 || y1 <= y0)
        return;
    MTLScissorRect sc = {
        .x      = (NSUInteger)x0,
        .y      = (NSUInteger)y0,
        .width  = (NSUInteger)(x1 - x0),
        .height = (NSUInteger)(y1 - y0)
    };
    [encoder setScissorRect:sc];

    [encoder setRenderPipelineState:_pipelineState];
    [encoder setFragmentTexture:input atIndex:0];
    [encoder setFragmentSamplerState:_samplerLinear atIndex:0];
    [encoder setVertexBytes:&uniforms length:sizeof(uniforms) atIndex:1];

    if (_projectionMode == PROJECTION_MODE_CUBEMAP_LAYOUT_STANDARD) {
        if (_cubeVertexBuffer != nil && _cubeIndexBuffer != nil) {
            [encoder setVertexBuffer:_cubeVertexBuffer offset:0 atIndex:0];
            [encoder drawIndexedPrimitives:MTLPrimitiveTypeTriangle
                                indexCount:_cubeIndexCount
                                 indexType:MTLIndexTypeUInt16
                               indexBuffer:_cubeIndexBuffer
                         indexBufferOffset:0];
        }
    } else {
        if (_sphereVertexBuffer != nil && _sphereIndexBuffer != nil) {
            [encoder setVertexBuffer:_sphereVertexBuffer offset:0 atIndex:0];
            [encoder drawIndexedPrimitives:MTLPrimitiveTypeTriangle
                                indexCount:_sphereIndexCount
                                 indexType:MTLIndexTypeUInt16
                               indexBuffer:_sphereIndexBuffer
                         indexBufferOffset:0];
        }
    }
}

@end
