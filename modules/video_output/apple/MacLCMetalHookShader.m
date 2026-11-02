/*****************************************************************************
 * MacLCMetalHookShader.m: runs a 2x luma user shader on Metal
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

#import "MacLCMetalHookShader.h"

/* GLSL spellings the hook shaders use, in Metal. */
static NSString * const kPrelude = @R"(
#include <metal_stdlib>
using namespace metal;
#define vec2 float2
#define vec3 float3
#define vec4 float4
#define ivec2 int2
#define mat4 float4x4
#define mat4x4 float4x4
struct Range { float scale; float offset; };
constexpr sampler _s(filter::linear, address::clamp_to_edge, coord::normalized);
static inline float _f1(float4 v) { return v.x; }
static inline float _f1(float v) { return v; }

kernel void maclc_hook_prep(texture2d<float, access::read> y [[texture(0)]],
                            texture2d<float, access::write> out [[texture(1)]],
                            constant Range &range [[buffer(0)]],
                            uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= out.get_width() || gid.y >= out.get_height())
        return;
    const float v = y.read(gid).r * range.scale + range.offset;
    out.write(float4(v, v, v, 1.0f), gid);
}
)";

struct Range { float scale, offset; };

static BOOL IsHooked(NSString *name)
{
    return [name isEqualToString:@"MAIN"] || [name isEqualToString:@"LUMA"]
        || [name isEqualToString:@"HOOKED"];
}

@interface MacLCHookPass : NSObject
@property (nonatomic) NSMutableArray<NSString *> *binds;
@property (nonatomic, nullable) NSString *save, *width, *height;
@property (nonatomic) NSMutableString *body;
@property (nonatomic) id<MTLComputePipelineState> pipeline;
@end

@implementation MacLCHookPass
@end

/* Splits the source into passes; nil on a directive this runner lacks. */
static NSArray<MacLCHookPass *> *Parse(NSString *source)
{
    NSMutableArray<MacLCHookPass *> *passes = [NSMutableArray array];
    MacLCHookPass *pass = nil;
    BOOL inBody = NO;
    for (NSString *line in [source componentsSeparatedByString:@"\n"]) {
        if (![line hasPrefix:@"//!"]) {
            [pass.body appendFormat:@"%@\n", line];
            if (pass != nil && [line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length > 0)
                inBody = YES;
            continue;
        }
        if (pass == nil || inBody) {
            pass = [MacLCHookPass new];
            pass.binds = [NSMutableArray array];
            pass.body = [NSMutableString string];
            [passes addObject:pass];
            inBody = NO;
        }
        NSString *directive = [line substringFromIndex:3];
        NSRange space = [directive rangeOfString:@" "];
        NSString *key = space.location == NSNotFound ? directive : [directive substringToIndex:space.location];
        NSString *value = space.location == NSNotFound ? @""
            : [[directive substringFromIndex:space.location + 1]
                  stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if ([key isEqualToString:@"HOOK"]) {
            if (![value isEqualToString:@"MAIN"] && ![value isEqualToString:@"LUMA"])
                return nil;
        } else if ([key isEqualToString:@"BIND"])
            [pass.binds addObject:value];
        else if ([key isEqualToString:@"SAVE"])
            pass.save = value;
        else if ([key isEqualToString:@"WIDTH"])
            pass.width = value;
        else if ([key isEqualToString:@"HEIGHT"])
            pass.height = value;
        else if (![key isEqualToString:@"DESC"] && ![key isEqualToString:@"WHEN"]
              && ![key isEqualToString:@"COMPONENTS"])
            return nil; /* COMPUTE, TEXTURE, OFFSET... */
    }
    if (passes.count == 0)
        return nil;
    /* only the last pass may write the hooked texture, and it must */
    for (NSUInteger i = 0; i < passes.count; i++) {
        const BOOL hooked = passes[i].save == nil || IsHooked(passes[i].save);
        if (hooked != (i == passes.count - 1))
            return nil;
    }
    return passes;
}

static NSString *Replace(NSString *string, NSString *pattern, NSString *template)
{
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:pattern
                                                                        options:NSRegularExpressionAnchorsMatchLines
                                                                          error:NULL];
    return [re stringByReplacingMatchesInString:string options:0
                                          range:NSMakeRange(0, string.length) withTemplate:template];
}

/* One Metal function and kernel per pass; the last one writes the plane. */
static NSString *Translate(MacLCHookPass *pass, NSUInteger index, BOOL last)
{
    NSMutableString *src = [NSMutableString string];
    NSMutableArray<NSString *> *macros = [NSMutableArray array];
    NSMutableArray<NSString *> *params = [NSMutableArray array], *args = [NSMutableArray array],
                               *kparams = [NSMutableArray array];
    for (NSUInteger k = 0; k < pass.binds.count; k++) {
        NSString *n = pass.binds[k];
        [src appendFormat:@"#define %@_tex(p) _t%lu.sample(_s, (p))\n", n, k];
        [src appendFormat:@"#define %@_pos _pos\n", n];
        [src appendFormat:@"#define %@_size float2(_t%lu.get_width(), _t%lu.get_height())\n", n, k, k];
        [src appendFormat:@"#define %@_pt (1.0f / %@_size)\n", n, n];
        [src appendFormat:@"#define %@_texOff(o) %@_tex(%@_pos + %@_pt * float2(o))\n", n, n, n, n];
        for (NSString *suffix in @[ @"tex", @"pos", @"size", @"pt", @"texOff" ])
            [macros addObject:[NSString stringWithFormat:@"%@_%@", n, suffix]];
        [params addObject:[NSString stringWithFormat:@"texture2d<float> _t%lu", k]];
        [args addObject:[NSString stringWithFormat:@"_t%lu", k]];
        [kparams addObject:[NSString stringWithFormat:@"texture2d<float> _t%lu [[texture(%lu)]]", k, k]];
    }
    [params addObject:@"float2 _pos"];

    NSString *body = Replace(pass.body, @"\\bfloat\\s*\\(", @"_f1(");
    body = Replace(body, @"\\bhook\\s*\\(\\s*\\)",
                   [NSString stringWithFormat:@"hook_%lu(%@)", index,
                       [params componentsJoinedByString:@", "]]);
    [src appendString:body];
    NSRegularExpression *define = [NSRegularExpression
        regularExpressionWithPattern:@"^\\s*#define\\s+(\\w+)" options:NSRegularExpressionAnchorsMatchLines error:NULL];
    for (NSTextCheckingResult *m in [define matchesInString:pass.body options:0 range:NSMakeRange(0, pass.body.length)])
        [macros addObject:[pass.body substringWithRange:[m rangeAtIndex:1]]];
    for (NSString *m in macros)
        [src appendFormat:@"#undef %@\n", m];

    [src appendFormat:
        @"kernel void maclc_hook_%lu(%@%@texture2d<float, access::write> _out [[texture(%lu)]],\n"
        "    constant Range &_range [[buffer(0)]], constant uint2 &_size [[buffer(1)]],\n"
        "    uint2 _gid [[thread_position_in_grid]])\n"
        "{\n"
        "    if (_gid.x >= _size.x || _gid.y >= _size.y)\n"
        "        return;\n"
        "    const float4 _r = hook_%lu(%@%@(float2(_gid) + 0.5f) / float2(_size));\n"
        "    _out.write(%@, _gid);\n"
        "}\n",
        index, [kparams componentsJoinedByString:@", "], kparams.count ? @", " : @"", pass.binds.count,
        index, [args componentsJoinedByString:@", "], args.count ? @", " : @"",
        last ? @"float4(clamp(_r.x, 0.0f, 1.0f) * _range.scale + _range.offset)" : @"_r"];
    return src;
}

/* WIDTH/HEIGHT: reverse Polish over NAME.w, NAME.h and numbers. */
static BOOL Evaluate(NSString *expr, NSDictionary<NSString *, NSValue *> *sizes, NSUInteger *out)
{
    NSMutableArray<NSNumber *> *stack = [NSMutableArray array];
    for (NSString *token in [expr componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceCharacterSet]) {
        if (token.length == 0)
            continue;
        if (token.length == 1 && [@"+-*/" containsString:token]) {
            if (stack.count < 2)
                return NO;
            const double b = stack.lastObject.doubleValue;
            [stack removeLastObject];
            const double a = stack.lastObject.doubleValue;
            [stack removeLastObject];
            const unichar op = [token characterAtIndex:0];
            [stack addObject:@(op == '+' ? a + b : op == '-' ? a - b : op == '*' ? a * b : a / b)];
        } else if ([token hasSuffix:@".w"] || [token hasSuffix:@".h"]) {
            NSValue *size = sizes[[token substringToIndex:token.length - 2]];
            if (size == nil)
                return NO;
            const CGSize s = size.sizeValue;
            [stack addObject:@([token hasSuffix:@".w"] ? s.width : s.height)];
        } else {
            NSScanner *scanner = [NSScanner scannerWithString:token];
            double v;
            if (![scanner scanDouble:&v] || !scanner.atEnd)
                return NO;
            [stack addObject:@(v)];
        }
    }
    if (stack.count != 1 || stack[0].doubleValue < 1)
        return NO;
    *out = (NSUInteger)stack[0].doubleValue;
    return YES;
}

static void Dispatch(id<MTLComputeCommandEncoder> enc, id<MTLComputePipelineState> pipe,
                     NSUInteger w, NSUInteger h)
{
    [enc setComputePipelineState:pipe];
    [enc dispatchThreadgroups:MTLSizeMake((w + 7) / 8, (h + 7) / 8, 1)
        threadsPerThreadgroup:MTLSizeMake(8, 8, 1)];
}

@implementation MacLCMetalHookShader {
    id<MTLDevice> _device;
    NSArray<MacLCHookPass *> *_passes;
    id<MTLComputePipelineState> _prep;
    NSUInteger _w, _h;
    id<MTLTexture> _input;
    /* per pass, set up for _w x _h: bound textures, output, output size */
    NSArray<NSArray<id<MTLTexture>> *> *_binds;
    NSArray<id<MTLTexture>> *_outs;
    NSArray<NSValue *> *_sizes;
}

- (instancetype)initWithDevice:(id<MTLDevice>)device source:(NSString *)source
{
    self = [super init];
    if (self == nil)
        return nil;
    _device = device;
    _passes = Parse(source);
    if (_passes == nil) {
        NSLog(@"hook shader: unsupported");
        return nil;
    }
    NSMutableString *msl = [kPrelude mutableCopy];
    for (NSUInteger i = 0; i < _passes.count; i++)
        [msl appendString:Translate(_passes[i], i, i == _passes.count - 1)];
    NSError *error = nil;
    id<MTLLibrary> library = [device newLibraryWithSource:msl options:nil error:&error];
    if (library == nil) {
        NSLog(@"hook shader: %@", error);
        return nil;
    }
    _prep = [device newComputePipelineStateWithFunction:[library newFunctionWithName:@"maclc_hook_prep"]
                                                  error:&error];
    if (_prep == nil)
        return nil;
    for (NSUInteger i = 0; i < _passes.count; i++) {
        id<MTLFunction> f = [library newFunctionWithName:[NSString stringWithFormat:@"maclc_hook_%lu", i]];
        _passes[i].pipeline = f ? [device newComputePipelineStateWithFunction:f error:&error] : nil;
        if (_passes[i].pipeline == nil)
            return nil;
    }
    return self;
}

- (id<MTLTexture>)textureWidth:(NSUInteger)w height:(NSUInteger)h
{
    MTLTextureDescriptor *td = [MTLTextureDescriptor
        texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA16Float width:w height:h mipmapped:NO];
    td.usage = MTLTextureUsageShaderRead | MTLTextureUsageShaderWrite;
    td.storageMode = MTLStorageModePrivate;
    return [_device newTextureWithDescriptor:td];
}

/* Sizes every pass for a w x h input and gives each saved texture a slot,
 * reusing a slot once every pass reading its previous owner has run. */
- (BOOL)setUpWidth:(NSUInteger)w height:(NSUInteger)h
{
    const NSUInteger n = _passes.count;
    NSMutableDictionary<NSString *, NSValue *> *sizes = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString *, NSNumber *> *producer = [NSMutableDictionary dictionary];
    for (NSString *name in @[ @"MAIN", @"LUMA", @"HOOKED" ])
        sizes[name] = [NSValue valueWithSize:CGSizeMake(w, h)];
    NSMutableArray<NSValue *> *outSizes = [NSMutableArray array];
    NSMutableArray<NSArray<NSNumber *> *> *reads = [NSMutableArray array];
    NSInteger lastRead[n];
    for (NSUInteger p = 0; p < n; p++) {
        MacLCHookPass *pass = _passes[p];
        lastRead[p] = (NSInteger)p;
        NSMutableArray<NSNumber *> *r = [NSMutableArray array];
        for (NSString *name in pass.binds) {
            if (IsHooked(name)) {
                [r addObject:@(-1)];
                continue;
            }
            NSNumber *from = producer[name];
            if (from == nil)
                return NO;
            lastRead[from.unsignedIntegerValue] = (NSInteger)p;
            [r addObject:from];
        }
        [reads addObject:r];
        NSUInteger ow = w, oh = h;
        if ((pass.width != nil && !Evaluate(pass.width, sizes, &ow))
         || (pass.height != nil && !Evaluate(pass.height, sizes, &oh)))
            return NO;
        if (p == n - 1 && (ow != 2 * w || oh != 2 * h))
            return NO;
        [outSizes addObject:[NSValue valueWithSize:CGSizeMake(ow, oh)]];
        if (p < n - 1) {
            sizes[pass.save] = outSizes[p];
            producer[pass.save] = @(p);
        }
    }

    id<MTLTexture> input = [self textureWidth:w height:h];
    if (input == nil)
        return NO;
    NSMutableArray<id<MTLTexture>> *slots = [NSMutableArray array];
    NSMutableArray<NSNumber *> *busyUntil = [NSMutableArray array];
    NSMutableArray<id> *outs = [NSMutableArray array];
    for (NSUInteger p = 0; p + 1 < n; p++) {
        const CGSize s = outSizes[p].sizeValue;
        NSUInteger slot = NSNotFound;
        for (NSUInteger k = 0; k < slots.count && slot == NSNotFound; k++)
            if (busyUntil[k].integerValue < (NSInteger)p
             && slots[k].width == s.width && slots[k].height == s.height)
                slot = k;
        if (slot == NSNotFound) {
            id<MTLTexture> t = [self textureWidth:s.width height:s.height];
            if (t == nil)
                return NO;
            [slots addObject:t];
            [busyUntil addObject:@0];
            slot = slots.count - 1;
        }
        busyUntil[slot] = @(lastRead[p]);
        [outs addObject:slots[slot]];
    }
    [outs addObject:NSNull.null]; /* the last pass writes the caller's plane */

    NSMutableArray<NSArray<id<MTLTexture>> *> *binds = [NSMutableArray array];
    for (NSUInteger p = 0; p < n; p++) {
        NSMutableArray<id<MTLTexture>> *b = [NSMutableArray array];
        for (NSNumber *from in reads[p])
            [b addObject:from.integerValue < 0 ? input : outs[from.unsignedIntegerValue]];
        [binds addObject:b];
    }
    _input = input;
    _binds = binds;
    _outs = outs;
    _sizes = outSizes;
    _w = w;
    _h = h;
    return YES;
}

- (BOOL)encodeLuma:(id<MTLTexture>)y
                to:(id<MTLTexture>)y2
        videoRange:(BOOL)videoRange
     commandBuffer:(id<MTLCommandBuffer>)commandBuffer
{
    const NSUInteger w = y.width, h = y.height;
    if (y2.width < 2 * w || y2.height < 2 * h)
        return NO;
    if ((w != _w || h != _h) && ![self setUpWidth:w height:h]) {
        _w = _h = 0;
        return NO;
    }
    const struct Range toUnit = videoRange ? (struct Range){ 255.0f / 219.0f, -16.0f / 219.0f }
                                           : (struct Range){ 1.0f, 0.0f };
    const struct Range toPlane = videoRange ? (struct Range){ 219.0f / 255.0f, 16.0f / 255.0f }
                                            : (struct Range){ 1.0f, 0.0f };

    id<MTLComputeCommandEncoder> enc = [commandBuffer computeCommandEncoder];
    if (enc == nil)
        return NO;
    [enc setTexture:y atIndex:0];
    [enc setTexture:_input atIndex:1];
    [enc setBytes:&toUnit length:sizeof(toUnit) atIndex:0];
    Dispatch(enc, _prep, w, h);

    for (NSUInteger p = 0; p < _passes.count; p++) {
        NSArray<id<MTLTexture>> *b = _binds[p];
        for (NSUInteger k = 0; k < b.count; k++)
            [enc setTexture:b[k] atIndex:k];
        const BOOL last = p == _passes.count - 1;
        [enc setTexture:last ? y2 : _outs[p] atIndex:b.count];
        const CGSize s = _sizes[p].sizeValue;
        const uint32_t size[2] = { (uint32_t)s.width, (uint32_t)s.height };
        [enc setBytes:&toPlane length:sizeof(toPlane) atIndex:0];
        [enc setBytes:size length:sizeof(size) atIndex:1];
        Dispatch(enc, _passes[p].pipeline, size[0], size[1]);
    }
    [enc endEncoding];
    return YES;
}

@end
