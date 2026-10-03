/*****************************************************************************
 * VLCHDRNetwork.m: the trained grid predictors behind SDR to HDR's High and
 *                  Maximum levels, run with MPSGraph
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

#import "VLCHDRNetwork.h"

#import <MetalPerformanceShaders/MetalPerformanceShaders.h>
#import <MetalPerformanceShadersGraph/MetalPerformanceShadersGraph.h>

/* File layout (export.py): the 8-byte magic, a little-endian uint32 with the
 * length of a UTF-8 JSON header, the header, then every tensor as IEEE half
 * floats, in the order and with the shapes the header lists. */
static const char kMagic[8] = { 'M', 'L', 'C', 'N', 'N', '0', '0', '1' };

static NSString * const kErrorDomain = @"org.maclc.sdr2hdr.network";

/* Copies the thumbnail texture into the NCHW half buffer the graph reads. */
static NSString * const kThumbnailToBufferSource =
    @"#include <metal_stdlib>\n"
    @"using namespace metal;\n"
    @"kernel void sdr2hdr_thumbnail_to_nchw(\n"
    @"    texture2d<float, access::read> thumb [[texture(0)]],\n"
    @"    device half *out                     [[buffer(0)]],\n"
    @"    uint2 gid [[thread_position_in_grid]])\n"
    @"{\n"
    @"    uint w = thumb.get_width(), h = thumb.get_height();\n"
    @"    if (gid.x >= w || gid.y >= h)\n"
    @"        return;\n"
    @"    float3 v = clamp(thumb.read(gid).rgb, 0.0f, 1.0f);\n"
    @"    uint plane = w * h, i = gid.y * w + gid.x;\n"
    @"    out[i] = half(v.r);\n"
    @"    out[plane + i] = half(v.g);\n"
    @"    out[2u * plane + i] = half(v.b);\n"
    @"}\n";

static NSError *NetworkError(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);
static NSError *NetworkError(NSString *format, ...)
{
    va_list ap;
    va_start(ap, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:ap];
    va_end(ap);
    return [NSError errorWithDomain:kErrorDomain code:1
                           userInfo:@{ NSLocalizedDescriptionKey: message }];
}

@implementation VLCHDRNetwork
{
    id<MTLDevice> _device;
    MPSGraph *_graph;
    MPSGraphTensor *_input;
    MPSGraphTensor *_output;
    MPSGraphExecutable *_executable;
    id<MTLComputePipelineState> _toBuffer;
    id<MTLBuffer> _inputBuffer;

    NSUInteger _thumbnailSize;
    NSUInteger _gridWidth, _gridHeight, _gridDepth;

    /* name -> NSData of halves, and name -> shape */
    NSDictionary<NSString *, NSData *> *_tensors;
    NSDictionary<NSString *, NSArray<NSNumber *> *> *_shapes;
}

@synthesize thumbnailSize = _thumbnailSize;
@synthesize gridWidth = _gridWidth, gridHeight = _gridHeight, gridDepth = _gridDepth;

+ (nullable instancetype)networkWithContentsOfFile:(NSString *)path
                                            device:(id<MTLDevice>)device
                                             error:(NSError **)error
{
    return [[self alloc] initWithContentsOfFile:path device:device error:error];
}

- (nullable instancetype)initWithContentsOfFile:(NSString *)path
                                         device:(id<MTLDevice>)device
                                          error:(NSError **)error
{
    self = [super init];
    if (self == nil)
        return nil;
    _device = device;
    _path = [path copy];

    NSData *file = [NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:error];
    if (file == nil)
        return nil;

    NSDictionary *header = nil;
    if (![self parseFile:file header:&header error:error])
        return nil;
    if (![self buildGraphWithHeader:header error:error])
        return nil;
    if (![self buildCopyKernel:error])
        return nil;
    return self;
}

#pragma mark - File

- (BOOL)parseFile:(NSData *)file header:(NSDictionary **)outHeader error:(NSError **)error
{
    const uint8_t *bytes = file.bytes;
    const NSUInteger length = file.length;
    if (length < 12 || memcmp(bytes, kMagic, sizeof(kMagic)) != 0) {
        if (error) *error = NetworkError(@"%@ is not a MacLC network file", _path);
        return NO;
    }
    const uint32_t jsonLength = (uint32_t)bytes[8] | ((uint32_t)bytes[9] << 8)
                              | ((uint32_t)bytes[10] << 16) | ((uint32_t)bytes[11] << 24);
    if (12 + (NSUInteger)jsonLength > length) {
        if (error) *error = NetworkError(@"%@: truncated header", _path);
        return NO;
    }
    NSData *json = [file subdataWithRange:NSMakeRange(12, jsonLength)];
    NSDictionary *header = [NSJSONSerialization JSONObjectWithData:json options:0 error:error];
    if (![header isKindOfClass:[NSDictionary class]])
        return NO;

    NSArray *list = header[@"tensors"];
    if (![list isKindOfClass:[NSArray class]]) {
        if (error) *error = NetworkError(@"%@: no tensor list", _path);
        return NO;
    }

    NSMutableDictionary *tensors = [NSMutableDictionary dictionary];
    NSMutableDictionary *shapes = [NSMutableDictionary dictionary];
    NSUInteger offset = 12 + jsonLength;
    /* The file may come from Application Support, where anyone can put one:
     * check every type and every size before trusting it. */
    for (id item in list) {
        NSDictionary *entry = [item isKindOfClass:[NSDictionary class]] ? item : nil;
        NSString *name = entry[@"name"];
        NSArray *shape = entry[@"shape"];
        if (![name isKindOfClass:[NSString class]] || ![shape isKindOfClass:[NSArray class]]
            || shape.count == 0 || shape.count > 4) {
            if (error) *error = NetworkError(@"%@: malformed tensor entry", _path);
            return NO;
        }
        NSUInteger count = 1;
        for (id d in shape) {
            if (![d isKindOfClass:[NSNumber class]] || [d integerValue] <= 0
                || __builtin_mul_overflow(count, (NSUInteger)[d integerValue], &count)) {
                if (error) *error = NetworkError(@"%@: tensor %@ has a bad shape", _path, name);
                return NO;
            }
        }
        NSUInteger size, end;
        if (__builtin_mul_overflow(count, (NSUInteger)2, &size)
            || __builtin_add_overflow(offset, size, &end) || end > length) {
            if (error) *error = NetworkError(@"%@: tensor %@ runs past the end", _path, name);
            return NO;
        }
        tensors[name] = [file subdataWithRange:NSMakeRange(offset, size)];
        shapes[name] = shape;
        offset = end;
    }
    _tensors = tensors;
    _shapes = shapes;
    *outHeader = header;
    return YES;
}

#pragma mark - Graph

- (nullable MPSGraphTensor *)constantNamed:(NSString *)name
{
    NSData *data = _tensors[name];
    NSArray<NSNumber *> *shape = _shapes[name];
    if (data == nil)
        return nil;
    return [_graph constantWithData:data shape:shape dataType:MPSDataTypeFloat16];
}

/* conv (OIHW weights, NCHW data, symmetric padding: what nn.Conv2d with
 * padding=k/2 does, which TF_SAME does not for even inputs) + bias. */
- (nullable MPSGraphTensor *)conv:(MPSGraphTensor *)x
                            named:(NSString *)name
                           stride:(NSUInteger)stride
{
    MPSGraphTensor *w = [self constantNamed:[name stringByAppendingString:@".weight"]];
    MPSGraphTensor *b = [self constantNamed:[name stringByAppendingString:@".bias"]];
    NSArray<NSNumber *> *ws = _shapes[[name stringByAppendingString:@".weight"]];
    if (w == nil || b == nil || ws.count != 4)
        return nil;
    const NSUInteger pad = ws[2].unsignedIntegerValue / 2;
    MPSGraphConvolution2DOpDescriptor *d =
        [MPSGraphConvolution2DOpDescriptor descriptorWithStrideInX:stride
                                                        strideInY:stride
                                                  dilationRateInX:1
                                                  dilationRateInY:1
                                                           groups:1
                                                      paddingLeft:pad
                                                     paddingRight:pad
                                                       paddingTop:pad
                                                    paddingBottom:pad
                                                     paddingStyle:MPSGraphPaddingStyleExplicit
                                                       dataLayout:MPSGraphTensorNamedDataLayoutNCHW
                                                    weightsLayout:MPSGraphTensorNamedDataLayoutOIHW];
    MPSGraphTensor *y = [_graph convolution2DWithSourceTensor:x weightsTensor:w descriptor:d name:nil];
    MPSGraphTensor *bias = [_graph reshapeTensor:b withShape:@[@1, ws[0], @1, @1] name:nil];
    return [_graph additionWithPrimaryTensor:y secondaryTensor:bias name:nil];
}

/* nn.Linear: y = x W^T + b, W stored [out, in] as PyTorch keeps it. */
- (nullable MPSGraphTensor *)linear:(MPSGraphTensor *)x named:(NSString *)name
{
    MPSGraphTensor *w = [self constantNamed:[name stringByAppendingString:@".weight"]];
    MPSGraphTensor *b = [self constantNamed:[name stringByAppendingString:@".bias"]];
    if (w == nil || b == nil)
        return nil;
    MPSGraphTensor *wt = [_graph transposeTensor:w dimension:0 withDimension:1 name:nil];
    MPSGraphTensor *y = [_graph matrixMultiplicationWithPrimaryTensor:x secondaryTensor:wt name:nil];
    return [_graph additionWithPrimaryTensor:y secondaryTensor:b name:nil];
}

- (MPSGraphTensor *)act:(MPSGraphTensor *)x
{
    return [_graph leakyReLUWithTensor:x alpha:0.1 name:nil];
}

- (BOOL)buildGraphWithHeader:(NSDictionary *)header error:(NSError **)error
{
    NSDictionary *cfg = header[@"config"];
    NSString *name = header[@"name"];
    if (![cfg isKindOfClass:[NSDictionary class]] || ![name isKindOfClass:[NSString class]]) {
        if (error) *error = NetworkError(@"%@: no architecture description", _path);
        return NO;
    }
    _name = [name copy];
    _quality = [name hasPrefix:@"max"] ? MACLC_SDR2HDR_MAXIMUM : MACLC_SDR2HDR_HIGH;

    /* Numbers in a sane range, or 0 (refused below). */
    NSUInteger (^number)(NSString *, NSUInteger) = ^NSUInteger(NSString *key, NSUInteger max) {
        id v = cfg[key];
        if (![v isKindOfClass:[NSNumber class]] || [v integerValue] <= 0 || [v integerValue] > (NSInteger)max)
            return 0;
        return (NSUInteger)[v integerValue];
    };
    NSArray *channels = [cfg[@"ch"] isKindOfClass:[NSArray class]] ? cfg[@"ch"] : nil;
    const NSUInteger nGlobal = number(@"n_glob", 8);
    _thumbnailSize = number(@"thumb", 1024);
    _gridWidth = _gridHeight = number(@"grid", 256);
    _gridDepth = number(@"depth", 64);
    if (channels.count == 0 || channels.count > 8 || nGlobal == 0 || _thumbnailSize == 0
        || _gridWidth == 0 || _gridDepth == 0
        || (_thumbnailSize >> channels.count) != _gridWidth) {
        if (error) *error = NetworkError(@"%@: inconsistent architecture", _path);
        return NO;
    }

    _graph = [[MPSGraph alloc] init];
    _input = [_graph placeholderWithShape:@[@1, @3, @(_thumbnailSize), @(_thumbnailSize)]
                                 dataType:MPSDataTypeFloat16
                                     name:@"thumbnail"];
    _output = [self layersFrom:_input downsamples:channels.count globalDownsamples:nGlobal];
    if (_output == nil) {
        if (error) *error = NetworkError(@"%@: tensors missing for %@", _path, _name);
        return NO;
    }

    MPSGraphShapedType *inType =
        [[MPSGraphShapedType alloc] initWithShape:_input.shape dataType:MPSDataTypeFloat16];
    /* By default the compile returns early and MPSGraph goes on optimising on
     * its own queue (placement on the Neural Engine). Quitting during that
     * aborted the app in exit(), whose static destructors pulled MPSGraph's
     * mutexes from under it ("mutex lock failed"). Finish here, on the vout
     * thread, which is joined before exit: about 20 ms more, once. */
    MPSGraphCompilationDescriptor *compilation = [[MPSGraphCompilationDescriptor alloc] init];
    compilation.waitForCompilationCompletion = YES;
    _executable = [_graph compileWithDevice:[MPSGraphDevice deviceWithMTLDevice:_device]
                                      feeds:@{ _input: inType }
                              targetTensors:@[ _output ]
                           targetOperations:nil
                      compilationDescriptor:compilation];
    if (_executable == nil) {
        if (error) *error = NetworkError(@"%@: MPSGraph could not compile the network", _path);
        return NO;
    }

    _inputBuffer = [_device newBufferWithLength:3 * _thumbnailSize * _thumbnailSize * 2
                                        options:MTLResourceStorageModePrivate];
    if (_inputBuffer == nil) {
        if (error) *error = NetworkError(@"could not allocate the network's input");
        return NO;
    }
    return YES;
}

/* Output channels of layer `name` if its weight is [out, inputs, ...] with
 * `rank` dimensions and its bias [out]; 0 otherwise. */
- (NSUInteger)outputsOf:(NSString *)name inputs:(NSUInteger)inputs rank:(NSUInteger)rank
{
    NSArray<NSNumber *> *w = _shapes[[name stringByAppendingString:@".weight"]];
    NSArray<NSNumber *> *b = _shapes[[name stringByAppendingString:@".bias"]];
    if (w.count != rank || b.count != 1 || w[1].unsignedIntegerValue != inputs
        || b[0].unsignedIntegerValue != w[0].unsignedIntegerValue)
        return 0;
    return w[0].unsignedIntegerValue;
}

/* Every layer fits the one before it: MPSGraph aborts on mismatched shapes
 * instead of failing, so a malformed file is refused here. */
- (BOOL)checkChannelsWithDownsamples:(NSUInteger)downsamples global:(NSUInteger)nGlobal
{
    NSUInteger c = 3;
    for (NSUInteger i = 0; i < downsamples && c != 0; i++)
        c = [self outputsOf:[NSString stringWithFormat:@"down.%lu", (unsigned long)i] inputs:c rank:4];
    NSUInteger local = [self outputsOf:@"local1" inputs:c rank:4];
    local = [self outputsOf:@"local2" inputs:local rank:4];
    NSUInteger global = c;
    for (NSUInteger i = 0; i < nGlobal && global != 0; i++)
        global = [self outputsOf:[NSString stringWithFormat:@"gdown.%lu", (unsigned long)i] inputs:global rank:4];
    global = [self outputsOf:@"fc1" inputs:global rank:2];
    global = [self outputsOf:@"fc2" inputs:global rank:2];
    const NSUInteger out = [self outputsOf:@"out" inputs:local rank:4];
    return c != 0 && local != 0 && global == local && out == _gridDepth * 3;
}

/* The layers of model.py's GridNet, in the same order; nil when a tensor the
 * architecture needs is not in the file. */
- (nullable MPSGraphTensor *)layersFrom:(MPSGraphTensor *)input
                            downsamples:(NSUInteger)downsamples
                      globalDownsamples:(NSUInteger)nGlobal
{
    if (![self checkChannelsWithDownsamples:downsamples global:nGlobal])
        return nil;
    MPSGraphTensor *x = input;
    for (NSUInteger i = 0; i < downsamples; i++) {
        x = [self conv:x named:[NSString stringWithFormat:@"down.%lu", (unsigned long)i] stride:2];
        if (x == nil)
            return nil;
        x = [self act:x];
    }

    MPSGraphTensor *local = [self conv:x named:@"local1" stride:1];
    if (local == nil)
        return nil;
    local = [self conv:[self act:local] named:@"local2" stride:1];
    if (local == nil || nGlobal == 0)
        return nil;

    MPSGraphTensor *global = x;
    for (NSUInteger i = 0; i < nGlobal; i++) {
        global = [self conv:global named:[NSString stringWithFormat:@"gdown.%lu", (unsigned long)i] stride:2];
        if (global == nil)
            return nil;
        global = [self act:global];
    }
    NSNumber *globalChannels = _shapes[[NSString stringWithFormat:@"gdown.%lu.weight",
                                        (unsigned long)(nGlobal - 1)]][0];
    NSNumber *width = _shapes[@"fc2.weight"][0];
    if (globalChannels == nil || width == nil)
        return nil;
    global = [_graph meanOfTensor:global axes:@[@2, @3] name:nil];
    global = [_graph reshapeTensor:global withShape:@[@1, globalChannels] name:nil];
    global = [self linear:global named:@"fc1"];
    if (global == nil)
        return nil;
    global = [self linear:[self act:global] named:@"fc2"];
    if (global == nil)
        return nil;
    global = [_graph reshapeTensor:global withShape:@[@1, width, @1, @1] name:nil];

    MPSGraphTensor *fused = [self act:[_graph additionWithPrimaryTensor:local
                                                        secondaryTensor:global
                                                                   name:nil]];
    MPSGraphTensor *out = [self conv:fused named:@"out" stride:1];
    if (out == nil)
        return nil;
    out = [_graph sigmoidWithTensor:out name:nil];
    /* NCHW [1, depth*3, h, w] -> NHWC [1, h, w, depth*3]: the grid layout the
     * expander reads ([y][x][bin][channel], channel = bin * 3 + c). */
    out = [_graph transposeTensor:out dimension:1 withDimension:2 name:nil];
    return [_graph transposeTensor:out dimension:2 withDimension:3 name:nil];
}

- (BOOL)buildCopyKernel:(NSError **)error
{
    id<MTLLibrary> library = [_device newLibraryWithSource:kThumbnailToBufferSource
                                                   options:nil
                                                     error:error];
    id<MTLFunction> fn = [library newFunctionWithName:@"sdr2hdr_thumbnail_to_nchw"];
    if (fn == nil)
        return NO;
    _toBuffer = [_device newComputePipelineStateWithFunction:fn error:error];
    return _toBuffer != nil;
}

#pragma mark - VLCHDRGridProducer

- (BOOL)supportsQuality:(enum maclc_sdr2hdr_quality)quality
{
    return quality == _quality;
}

- (nullable id<MTLCommandBuffer>)encodeGridForThumbnail:(id<MTLTexture>)thumbnail
                                               intoGrid:(id<MTLBuffer>)grid
                                          commandBuffer:(id<MTLCommandBuffer>)commandBuffer
{
    if (thumbnail.width != _thumbnailSize || thumbnail.height != _thumbnailSize
        || grid.length < _gridWidth * _gridHeight * _gridDepth * 3 * 2)
        return nil;

    id<MTLComputeCommandEncoder> enc = [commandBuffer computeCommandEncoder];
    if (enc == nil)
        return nil;
    [enc setComputePipelineState:_toBuffer];
    [enc setTexture:thumbnail atIndex:0];
    [enc setBuffer:_inputBuffer offset:0 atIndex:0];
    [enc dispatchThreadgroups:MTLSizeMake((_thumbnailSize + 15) / 16, (_thumbnailSize + 15) / 16, 1)
        threadsPerThreadgroup:MTLSizeMake(16, 16, 1)];
    [enc endEncoding];

    MPSGraphTensorData *inData =
        [[MPSGraphTensorData alloc] initWithMTLBuffer:_inputBuffer
                                                shape:_input.shape
                                             dataType:MPSDataTypeFloat16];
    MPSGraphTensorData *outData =
        [[MPSGraphTensorData alloc] initWithMTLBuffer:grid
                                                shape:@[@1, @(_gridHeight), @(_gridWidth), @(_gridDepth * 3)]
                                             dataType:MPSDataTypeFloat16];

    /* MPSGraph may commit the command buffer and continue in a new one on the
     * same queue (commitAndContinue): hand the expander whichever it ends
     * with, so the passes that read the grid follow the prediction. */
    MPSCommandBuffer *mpsBuffer = [MPSCommandBuffer commandBufferWithCommandBuffer:commandBuffer];
    [_executable encodeToCommandBuffer:mpsBuffer
                           inputsArray:@[ inData ]
                          resultsArray:@[ outData ]
                   executionDescriptor:nil];
    /* rootCommandBuffer is the one still alive after a commitAndContinue;
     * commandBuffer stays the (then committed) one we wrapped. */
    return mpsBuffer.rootCommandBuffer;
}

@end

#pragma mark - Set

@implementation VLCHDRNetworkSet

+ (nullable instancetype)networkSetWithDevice:(id<MTLDevice>)device
                                userDirectory:(nullable NSString *)userDirectory
                                          log:(void (^ _Nullable)(NSString *line))logger
{
    NSMutableArray<NSString *> *directories = [NSMutableArray array];
    if (userDirectory.length > 0)
        [directories addObject:userDirectory];
    NSArray<NSURL *> *support = [NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory
                                                                     inDomains:NSUserDomainMask];
    if (support.firstObject != nil)
        [directories addObject:[[support.firstObject URLByAppendingPathComponent:@"MacLC/models"] path]];
    NSString *resources = NSBundle.mainBundle.resourcePath;
    if (resources != nil)
        [directories addObject:[resources stringByAppendingPathComponent:@"models"]];

    VLCHDRNetwork *(^load)(NSString *) = ^VLCHDRNetwork *(NSString *file) {
        for (NSString *directory in directories) {
            NSString *path = [directory stringByAppendingPathComponent:file];
            if (![NSFileManager.defaultManager fileExistsAtPath:path])
                continue;
            NSError *error = nil;
            VLCHDRNetwork *network = [VLCHDRNetwork networkWithContentsOfFile:path device:device error:&error];
            if (logger)
                logger(network ? [NSString stringWithFormat:@"loaded %@ (%@)", path, network.name]
                            : [NSString stringWithFormat:@"could not load %@: %@", path,
                               error.localizedDescription ?: @"unknown error"]);
            if (network)
                return network;
        }
        return nil;
    };

    VLCHDRNetwork *high = load(@"sdr2hdr-high-v1.maclcnn");
    VLCHDRNetwork *maximum = load(@"sdr2hdr-max-v1.maclcnn");
    if (high == nil && maximum == nil) {
        if (logger)
            logger([NSString stringWithFormat:@"no SDR to HDR network in %@",
                 [directories componentsJoinedByString:@", "]]);
        return nil;
    }
    VLCHDRNetworkSet *set = [[VLCHDRNetworkSet alloc] init];
    set->_high = high;
    set->_maximum = maximum;
    set->_currentQuality = MACLC_SDR2HDR_HIGH;
    return set;
}

- (VLCHDRNetwork *)current
{
    if (_currentQuality == MACLC_SDR2HDR_MAXIMUM && _maximum != nil)
        return _maximum;
    return _high ?: _maximum;
}

- (NSUInteger)gridWidth { return self.current.gridWidth; }
- (NSUInteger)gridHeight { return self.current.gridHeight; }
- (NSUInteger)gridDepth { return self.current.gridDepth; }
- (NSUInteger)thumbnailSize { return self.current.thumbnailSize; }

- (BOOL)supportsQuality:(enum maclc_sdr2hdr_quality)quality
{
    if (quality == MACLC_SDR2HDR_MAXIMUM)
        return _maximum != nil;
    if (quality == MACLC_SDR2HDR_HIGH)
        return _high != nil;
    return NO;
}

- (nullable id<MTLCommandBuffer>)encodeGridForThumbnail:(id<MTLTexture>)thumbnail
                                               intoGrid:(id<MTLBuffer>)grid
                                          commandBuffer:(id<MTLCommandBuffer>)commandBuffer
{
    return [self.current encodeGridForThumbnail:thumbnail intoGrid:grid commandBuffer:commandBuffer];
}

@end
