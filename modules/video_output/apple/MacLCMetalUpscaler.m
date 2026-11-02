/*****************************************************************************
 * MacLCMetalUpscaler.m: neural and MetalFX upscaling for the Metal output
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

#import "MacLCMetalUpscaler.h"
#import "MacLCMetalArtCNN.h"
#import "MacLCMetalHookShader.h"
#include "maclc_anime4k_cnn_x2_m.h"
#include "maclc_upscale_vars.h"

#import <MetalFX/MetalFX.h>
#import <VideoToolbox/VideoToolbox.h>
#import <IOKit/ps/IOPowerSources.h>
#import <IOKit/ps/IOPSKeys.h>
#include <mach/mach_time.h>

/* Frames the cost of a pass is averaged over, and the share of the frame
 * interval it may take: past ~70% playback stalls (measured with the
 * interpolation filter), so stay clear of it. */
#define COST_FRAMES        8
#define COST_FRAMES_4X     4   /* each of its frames stalls playback, judge fast */
#define COST_BUDGET        0.6
/* Power is polled, not observed: IOPS is too costly for every frame. */
#define POWER_POLL_FRAMES  60
/* How long a missing ×4 model is waited for before it is checked again. */
#define MODEL_RETRY_FRAMES 150

static CVPixelBufferPoolRef PoolFor(NSDictionary *attributes, size_t width, size_t height)
{
    NSMutableDictionary *attrs = [attributes mutableCopy] ?: [NSMutableDictionary dictionary];
    attrs[(__bridge NSString *)kCVPixelBufferWidthKey] = @(width);
    attrs[(__bridge NSString *)kCVPixelBufferHeightKey] = @(height);
    attrs[(__bridge NSString *)kCVPixelBufferIOSurfacePropertiesKey] = @{};
    NSDictionary *poolAttrs = @{ (__bridge NSString *)kCVPixelBufferPoolMinimumBufferCountKey: @3 };
    CVPixelBufferPoolRef pool = NULL;
    CVPixelBufferPoolCreate(kCFAllocatorDefault, (__bridge CFDictionaryRef)poolAttrs,
                            (__bridge CFDictionaryRef)attrs, &pool);
    return pool;
}

static CVPixelBufferPoolRef MetalPool(OSType format, size_t width, size_t height)
{
    return PoolFor(@{ (__bridge NSString *)kCVPixelBufferPixelFormatTypeKey: @(format),
                      (__bridge NSString *)kCVPixelBufferMetalCompatibilityKey: @YES },
                   width, height);
}

static BOOL OnBattery(void)
{
    CFTypeRef info = IOPSCopyPowerSourcesInfo();
    if (info == NULL)
        return NO;
    CFStringRef type = IOPSGetProvidingPowerSourceType(info);
    BOOL battery = type != NULL && CFEqual(type, CFSTR(kIOPMBatteryPowerKey));
    CFRelease(info);
    return battery;
}

static double Seconds(uint64_t ticks)
{
    static mach_timebase_info_data_t tb;
    if (tb.denom == 0)
        mach_timebase_info(&tb);
    return (double)ticks * tb.numer / tb.denom / 1e9;
}

/* Averages the cost of a pass over `frames` frames; true once it is over
 * budget. The first frame is left out: it warms caches and models. */
struct cost { double sum; int frames; BOOL warm; };

static BOOL OverBudget(struct cost *c, uint64_t start, int frames, double interval)
{
    if (!c->warm) {
        c->warm = YES;
        return NO;
    }
    c->sum += Seconds(mach_absolute_time() - start);
    if (++c->frames < frames)
        return NO;
    const double average = c->sum / frames;
    c->sum = 0.0;
    c->frames = 0;
    return average > COST_BUDGET * interval;
}

/** One running VideoToolbox super resolution session. Ending it may take a
 *  while, so the last reference is dropped on the upscaler's queue. */
@interface MacLCSRSession : NSObject {
@public
    id processor;                  /* VTFrameProcessor */
    size_t w, h;
    float factor;
    BOOL full;                     /* ×4 VTSuperResolutionScaler */
    CVPixelBufferPoolRef srcPool, dstPool, outPool;
    CVPixelBufferRef prevSrc, prevDst;  /* ×4: the previous frame and its output */
    int64_t frame;
    struct cost cost;
}
@end

@implementation MacLCSRSession

- (void)dealloc
{
    if (@available(macOS 26.0, *))
        [(VTFrameProcessor *)processor endSession];
    CVPixelBufferPoolRelease(srcPool);
    CVPixelBufferPoolRelease(dstPool);
    CVPixelBufferPoolRelease(outPool);
    CVPixelBufferRelease(prevSrc);
    CVPixelBufferRelease(prevDst);
}

- (BOOL)matchesWidth:(size_t)width height:(size_t)height factor:(float)f full:(BOOL)isFull
{
    return w == width && h == height && factor == f && full == isFull;
}

@end

/* Starts a session, on the upscaler's queue. */
static MacLCSRSession *StartSession(size_t w, size_t h, float factor, BOOL full,
                                    const char **failure) API_AVAILABLE(macos(26.0))
{
    id<VTFrameProcessorConfiguration> config;
    if (full) {
        VTSuperResolutionScalerConfiguration *c = [[VTSuperResolutionScalerConfiguration alloc]
            initWithFrameWidth:(NSInteger)w frameHeight:(NSInteger)h scaleFactor:(NSInteger)factor
                     inputType:VTSuperResolutionScalerConfigurationInputTypeVideo
            usePrecomputedFlow:NO
         qualityPrioritization:VTSuperResolutionScalerConfigurationQualityPrioritizationNormal
                      revision:VTSuperResolutionScalerConfiguration.defaultRevision];
        /* the model is downloaded from the upscaling panel, never from here */
        if (c != nil && c.configurationModelStatus != VTSuperResolutionScalerConfigurationModelStatusReady) {
            *failure = "model";
            return nil;
        }
        config = c;
    } else {
        config = [[VTLowLatencySuperResolutionScalerConfiguration alloc]
            initWithFrameWidth:(NSInteger)w frameHeight:(NSInteger)h scaleFactor:factor];
    }
    VTFrameProcessor *processor = [[VTFrameProcessor alloc] init];
    NSError *error = nil;
    if (config == nil || ![processor startSessionWithConfiguration:config error:&error]) {
        *failure = "unsupported";
        return nil;
    }
    MacLCSRSession *s = [MacLCSRSession new];
    s->processor = processor;
    s->w = w; s->h = h; s->factor = factor; s->full = full;
    const size_t ow = (size_t)(w * factor), oh = (size_t)(h * factor);
    s->srcPool = PoolFor(config.sourcePixelBufferAttributes, w, h);
    s->dstPool = PoolFor(config.destinationPixelBufferAttributes, ow, oh);
    /* ×4 works in RGhA, which the decode kernel does not take: back to BGRA */
    if (full)
        s->outPool = MetalPool(kCVPixelFormatType_32BGRA, ow, oh);
    if (s->srcPool == NULL || s->dstPool == NULL || (full && s->outPool == NULL)) {
        *failure = "unsupported";
        return nil;
    }
    return s;
}

@implementation MacLCMetalUpscaler {
    id<MTLDevice> _device;
    VTPixelTransferSessionRef _transfer;
    int64_t _frames;
    BOOL _lowPower;                /* battery, Low Power Mode */

    /* neural */
    dispatch_queue_t _queue;
    MacLCSRSession *_session;      /* the one in use, vout thread only */
    BOOL _starting;                /* a start is on the queue */
    MacLCSRSession *_ready;        /* handed over by the queue, under @synchronized */
    const char *_readyFailure;
    size_t _startW, _startH;
    float _startFactor;
    BOOL _startFull;
    const char *_disabled;         /* low latency: "slow" or "unsupported", for good */
    const char *_fullDisabled;     /* ×4: also "model", until _fullRetry */
    int64_t _fullRetry;

    /* anime */
    id _cnn;                       /* MacLCMetalArtCNN or MacLCMetalHookShader */
    NSInteger _network;            /* the method _cnn was made for */
    id<MTLCommandQueue> _cnnQueue;
    CVMetalTextureCacheRef _textureCache;
    CVPixelBufferPoolRef _animePool;
    size_t _aW, _aH;
    OSType _aFormat;
    const char *_animeDisabled;
    struct cost _animeCost;

    /* spatial */
    id _spatial;                   /* MTLFXSpatialScaler, macOS 13 */
    NSUInteger _sInW, _sInH, _sOutW, _sOutH;
    MTLPixelFormat _sFormat;
    id<MTLTexture> _outputs[2];
    unsigned _next;
}

- (instancetype)initWithDevice:(id<MTLDevice>)device
{
    self = [super init];
    if (self) {
        _device = device;
        _queue = dispatch_queue_create("org.maclc.upscale", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (void)dealloc
{
    [self dropSession];
    CVPixelBufferPoolRelease(_animePool);
    if (_textureCache != NULL)
        CFRelease(_textureCache);
    if (_transfer != NULL) {
        VTPixelTransferSessionInvalidate(_transfer);
        CFRelease(_transfer);
    }
}

- (BOOL)makeTransfer
{
    if (_transfer == NULL
     && VTPixelTransferSessionCreate(kCFAllocatorDefault, &_transfer) == noErr)
        VTSessionSetProperty(_transfer, kVTPixelTransferPropertyKey_RealTime, kCFBooleanTrue);
    return _transfer != NULL;
}

- (const char *)blocker
{
    if (_frames++ % POWER_POLL_FRAMES == 0) {
        BOOL lowPower = OnBattery();
        if (@available(macOS 12.0, *))
            lowPower = lowPower || [NSProcessInfo processInfo].isLowPowerModeEnabled;
        _lowPower = lowPower;
    }
    if (_lowPower)
        return "power";
    if ([NSProcessInfo processInfo].thermalState >= NSProcessInfoThermalStateSerious)
        return "thermal";
    return NULL;
}

#pragma mark - Neural

+ (float)neuralFactorForWidth:(size_t)width height:(size_t)height maxRatio:(float)maxRatio
{
    float best = 0.0f;
    if (@available(macOS 26.0, *)) {
        if (!VTLowLatencySuperResolutionScalerConfiguration.isSupported)
            return 0.0f;
        NSArray<NSNumber *> *factors = [VTLowLatencySuperResolutionScalerConfiguration
            supportedScaleFactorsForFrameWidth:(NSInteger)width frameHeight:(NSInteger)height];
        for (NSNumber *f in factors)
            /* a little overshoot is fine, MetalFX then scales down a touch */
            if (f.floatValue <= maxRatio + 0.05f && f.floatValue > best)
                best = f.floatValue;
    }
    return best;
}

- (void)dropSession
{
    MacLCSRSession *old = _session;
    _session = nil;
    if (old != nil)
        dispatch_async(_queue, ^{ (void)old; });
}

/* The session for this key, or nil while it starts ("loading") or when it
 * cannot ("unsupported", "model": then recorded as disabled). */
- (MacLCSRSession *)sessionForWidth:(size_t)w height:(size_t)h factor:(float)factor
                               full:(BOOL)full why:(const char **)why API_AVAILABLE(macos(26.0))
{
    if (_session != nil && [_session matchesWidth:w height:h factor:factor full:full])
        return _session;

    @synchronized (self) {
        if (!_starting && (_ready != nil || _readyFailure != NULL)) {
            if (_startW == w && _startH == h && _startFactor == factor && _startFull == full) {
                if (_ready != nil) {
                    [self dropSession];
                    _session = _ready;
                } else if (full) {
                    _fullDisabled = _readyFailure;
                    _fullRetry = _frames + MODEL_RETRY_FRAMES;
                } else {
                    _disabled = _readyFailure;
                }
            }
            _ready = nil;
            _readyFailure = NULL;
        }
        if (_session != nil && [_session matchesWidth:w height:h factor:factor full:full])
            return _session;
        if (full ? _fullDisabled != NULL : _disabled != NULL) {
            *why = full ? _fullDisabled : _disabled;
            return nil;
        }
        if (!_starting) {
            _starting = YES;
            _startW = w; _startH = h; _startFactor = factor; _startFull = full;
            __weak MacLCMetalUpscaler *weakSelf = self;
            dispatch_async(_queue, ^{
                const char *failure = NULL;
                MacLCSRSession *s = StartSession(w, h, factor, full, &failure);
                MacLCMetalUpscaler *upscaler = weakSelf;
                if (upscaler == nil)
                    return;
                @synchronized (upscaler) {
                    upscaler->_ready = s;
                    upscaler->_readyFailure = s != nil ? NULL : failure;
                    upscaler->_starting = NO;
                }
            });
        }
    }
    *why = "loading";
    return nil;
}

- (CVPixelBufferRef)processFull:(CVPixelBufferRef)source session:(MacLCSRSession *)s API_AVAILABLE(macos(26.0))
{
    CVPixelBufferRef src = NULL, dst = NULL, out = NULL;
    CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, s->srcPool, &src);
    CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, s->dstPool, &dst);
    CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, s->outPool, &out);
    BOOL ok = src != NULL && dst != NULL && out != NULL
           && VTPixelTransferSessionTransferImage(_transfer, source, src) == noErr;
    if (ok) {
        const CMTime pts = CMTimeMake(s->frame, 30), prevPts = CMTimeMake(s->frame - 1, 30);
        VTFrameProcessorFrame *sf = [[VTFrameProcessorFrame alloc] initWithBuffer:src presentationTimeStamp:pts];
        VTFrameProcessorFrame *df = [[VTFrameProcessorFrame alloc] initWithBuffer:dst presentationTimeStamp:pts];
        VTFrameProcessorFrame *pf = nil, *po = nil;
        if (s->prevSrc != NULL) {
            pf = [[VTFrameProcessorFrame alloc] initWithBuffer:s->prevSrc presentationTimeStamp:prevPts];
            po = [[VTFrameProcessorFrame alloc] initWithBuffer:s->prevDst presentationTimeStamp:prevPts];
        }
        /* shortcut: a seek still says Sequential, a frame of ghosting at
         * most; pass the picture date in if that ever shows. */
        VTSuperResolutionScalerParameters *params = [[VTSuperResolutionScalerParameters alloc]
            initWithSourceFrame:sf previousFrame:pf previousOutputFrame:po opticalFlow:nil
                 submissionMode:pf != nil ? VTSuperResolutionScalerParametersSubmissionModeSequential
                                          : VTSuperResolutionScalerParametersSubmissionModeRandom
               destinationFrame:df];
        NSError *error = nil;
        ok = sf != nil && df != nil && params != nil
          && [(VTFrameProcessor *)s->processor processWithParameters:params error:&error]
          && VTPixelTransferSessionTransferImage(_transfer, dst, out) == noErr;
    }
    if (ok) {
        CVPixelBufferRelease(s->prevSrc);
        CVPixelBufferRelease(s->prevDst);
        s->prevSrc = src;
        s->prevDst = dst;
        s->frame++;
        return out;
    }
    CVPixelBufferRelease(src);
    CVPixelBufferRelease(dst);
    CVPixelBufferRelease(out);
    return NULL;
}

- (CVPixelBufferRef)processLowLatency:(CVPixelBufferRef)source session:(MacLCSRSession *)s API_AVAILABLE(macos(26.0))
{
    CVPixelBufferRef src = NULL, dst = NULL;
    CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, s->srcPool, &src);
    CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, s->dstPool, &dst);
    BOOL ok = src != NULL && dst != NULL
           && VTPixelTransferSessionTransferImage(_transfer, source, src) == noErr;
    if (ok) {
        const CMTime pts = CMTimeMake(s->frame++, 30); /* only needs to be increasing */
        VTFrameProcessorFrame *sf = [[VTFrameProcessorFrame alloc] initWithBuffer:src presentationTimeStamp:pts];
        VTFrameProcessorFrame *df = [[VTFrameProcessorFrame alloc] initWithBuffer:dst presentationTimeStamp:pts];
        VTLowLatencySuperResolutionScalerParameters *params =
            [[VTLowLatencySuperResolutionScalerParameters alloc] initWithSourceFrame:sf destinationFrame:df];
        NSError *error = nil;
        ok = sf != nil && df != nil && params != nil
          && [(VTFrameProcessor *)s->processor processWithParameters:params error:&error];
    }
    CVPixelBufferRelease(src);
    if (!ok) {
        CVPixelBufferRelease(dst);
        return NULL;
    }
    return dst;
}

- (CVPixelBufferRef)neuralUpscale:(CVPixelBufferRef)source
                         maxRatio:(float)maxRatio
                          apple4x:(BOOL *)apple4x
                    frameInterval:(double)frameInterval
                              why:(const char **)why
{
    const BOOL want4x = *apple4x;
    *apple4x = NO;
    *why = NULL;
    if (@available(macOS 26.0, *)) {
        const char *blocked = [self blocker];
        if (blocked != NULL || ![self makeTransfer]) {
            *why = blocked != NULL ? blocked : "unsupported";
            [self dropSession];
            return NULL;
        }
        const size_t w = CVPixelBufferGetWidth(source), h = CVPixelBufferGetHeight(source);

        /* ×4 first; its reason, if any, is kept for the status */
        if (want4x) {
            if (_fullDisabled != NULL && strcmp(_fullDisabled, "model") == 0 && _frames >= _fullRetry)
                _fullDisabled = NULL;
            const char *why4x = NULL;
            if (!VTSuperResolutionScalerConfiguration.isSupported)
                why4x = "unsupported";
            else if (maxRatio < 2.5f || w > 1920 || h > 1080)
                why4x = "size";
            else {
                MacLCSRSession *s = [self sessionForWidth:w height:h factor:4.0f full:YES why:&why4x];
                if (s != nil) {
                    const uint64_t start = mach_absolute_time();
                    CVPixelBufferRef out = [self processFull:source session:s];
                    if (out == NULL) {
                        _fullDisabled = why4x = "unsupported";
                        [self dropSession];
                    } else {
                        if (OverBudget(&s->cost, start, COST_FRAMES_4X, frameInterval)) {
                            _fullDisabled = "slow";
                            [self dropSession];
                        }
                        CVBufferPropagateAttachments(source, out);
                        *apple4x = YES;
                        return out;
                    }
                }
            }
            /* while ×4 loads, show the plain video rather than start a
             * low-latency session only to drop it seconds later */
            if (strcmp(why4x, "loading") == 0) {
                *why = why4x;
                return NULL;
            }
            *why = why4x;
        }

        const float factor = [MacLCMetalUpscaler neuralFactorForWidth:w height:h maxRatio:maxRatio];
        const char *whyLL = NULL;
        if (factor == 0.0f)
            whyLL = VTLowLatencySuperResolutionScalerConfiguration.isSupported ? "size" : "unsupported";
        MacLCSRSession *s = factor == 0.0f ? nil
            : [self sessionForWidth:w height:h factor:factor full:NO why:&whyLL];
        if (s == nil) {
            if (*why == NULL || strcmp(whyLL, "loading") == 0)
                *why = whyLL;
            return NULL;
        }
        const uint64_t start = mach_absolute_time();
        CVPixelBufferRef dst = [self processLowLatency:source session:s];
        if (dst == NULL) {
            _disabled = "unsupported";
            [self dropSession];
            if (*why == NULL)
                *why = _disabled;
            return NULL;
        }
        if (OverBudget(&s->cost, start, COST_FRAMES, frameInterval)) {
            _disabled = "slow";
            [self dropSession];
        }
        /* the matrix and primaries the decode kernel reads */
        CVBufferPropagateAttachments(source, dst);
        return dst;
    }
    *why = "unsupported";
    return NULL;
}

#pragma mark - Anime

/* The luma network of a method; nil with `why` set when there is none. */
- (id)makeNetwork:(NSInteger)method why:(const char **)why
{
    if (method == MACLC_UPSCALE_ANIME)
        return [[MacLCMetalArtCNN alloc] initWithDevice:_device];
    NSString *source;
    if (method == MACLC_UPSCALE_ANIME4K)
        source = @(maclc_anime4k_cnn_x2_m);
    else {
        NSURL *support = [NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory
                                                              inDomains:NSUserDomainMask].firstObject;
        NSURL *file = [[support URLByAppendingPathComponent:@MACLC_UPSCALE_MODELS_DIR isDirectory:YES]
                       URLByAppendingPathComponent:@MACLC_UPSCALE_FSRCNNX_FILE];
        source = [NSString stringWithContentsOfURL:file encoding:NSUTF8StringEncoding error:NULL];
        if (source == nil) {
            *why = "model"; /* not accepted and downloaded yet: looked for again next frame */
            return nil;
        }
    }
    id network = [[MacLCMetalHookShader alloc] initWithDevice:_device source:source];
    if (network == nil)
        *why = "unsupported";
    return network;
}

- (CVPixelBufferRef)animeUpscale:(CVPixelBufferRef)source
                         network:(NSInteger)method
                        maxRatio:(float)maxRatio
                   frameInterval:(double)frameInterval
                             why:(const char **)why
{
    if (method != _network) {
        _network = method;
        _cnn = nil;
        _animeDisabled = NULL;
        _animeCost = (struct cost){ 0 };
    }
    *why = _animeDisabled;
    if (*why == NULL)
        *why = [self blocker];
    if (*why != NULL)
        return NULL;
    const OSType format = CVPixelBufferGetPixelFormatType(source);
    if (format != kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
     && format != kCVPixelFormatType_420YpCbCr8BiPlanarFullRange) {
        *why = "format";
        return NULL;
    }
    if (maxRatio < 1.4f) { /* x2 then the draw downscales a little; below 1.4 it is wasted work */
        *why = "size";
        return NULL;
    }

    if (_cnnQueue == nil) {
        _cnnQueue = [_device newCommandQueue];
        if (_cnnQueue == nil || ![self makeTransfer]
         || CVMetalTextureCacheCreate(kCFAllocatorDefault, NULL, _device, NULL, &_textureCache) != kCVReturnSuccess) {
            _cnnQueue = nil;
            _animeDisabled = *why = "unsupported";
            return NULL;
        }
    }
    if (_cnn == nil) {
        _cnn = [self makeNetwork:method why:why];
        if (_cnn == nil) {
            if (strcmp(*why, "model") != 0)
                _animeDisabled = *why;
            return NULL;
        }
    }
    const size_t w = CVPixelBufferGetWidth(source), h = CVPixelBufferGetHeight(source);
    if (_animePool == NULL || w != _aW || h != _aH || format != _aFormat) {
        CVPixelBufferPoolRelease(_animePool);
        _animePool = MetalPool(format, 2 * w, 2 * h);
        _aW = w; _aH = h; _aFormat = format;
        _animeCost = (struct cost){ 0 };
        if (_animePool == NULL) {
            _animeDisabled = *why = "unsupported";
            return NULL;
        }
    }

    const uint64_t start = mach_absolute_time();
    CVPixelBufferRef dst = NULL;
    CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, _animePool, &dst);
    /* chroma (and a luma the network then overwrites) at twice the size */
    if (dst == NULL || VTPixelTransferSessionTransferImage(_transfer, source, dst) != noErr) {
        CVPixelBufferRelease(dst);
        *why = "format";
        return NULL;
    }
    NSDictionary *usage = @{ (__bridge NSString *)kCVMetalTextureUsage:
                                @(MTLTextureUsageShaderRead | MTLTextureUsageShaderWrite) };
    CVMetalTextureRef yRef = NULL, y2Ref = NULL;
    CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, _textureCache, source, NULL,
        MTLPixelFormatR8Unorm, CVPixelBufferGetWidthOfPlane(source, 0),
        CVPixelBufferGetHeightOfPlane(source, 0), 0, &yRef);
    CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, _textureCache, dst,
        (__bridge CFDictionaryRef)usage, MTLPixelFormatR8Unorm,
        CVPixelBufferGetWidthOfPlane(dst, 0), CVPixelBufferGetHeightOfPlane(dst, 0), 0, &y2Ref);
    BOOL ok = NO;
    if (yRef != NULL && y2Ref != NULL) {
        id<MTLCommandBuffer> cb = [_cnnQueue commandBuffer];
        if (cb != nil && [_cnn encodeLuma:CVMetalTextureGetTexture(yRef)
                                       to:CVMetalTextureGetTexture(y2Ref)
                               videoRange:format == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
                            commandBuffer:cb]) {
            [cb commit];
            [cb waitUntilCompleted];
            ok = cb.status == MTLCommandBufferStatusCompleted;
        }
    }
    if (yRef != NULL)
        CFRelease(yRef);
    if (y2Ref != NULL)
        CFRelease(y2Ref);
    CVMetalTextureCacheFlush(_textureCache, 0);
    if (!ok) {
        CVPixelBufferRelease(dst);
        *why = "format"; /* not IOSurface-backed, most likely */
        return NULL;
    }
    if (OverBudget(&_animeCost, start, COST_FRAMES, frameInterval))
        _animeDisabled = "slow";
    CVBufferPropagateAttachments(source, dst);
    return dst;
}

#pragma mark - Spatial

- (id<MTLTexture>)encodeSpatialFrom:(id<MTLTexture>)texture
                              width:(NSUInteger)width
                             height:(NSUInteger)height
                      commandBuffer:(id<MTLCommandBuffer>)commandBuffer
{
    if (@available(macOS 13.0, *)) {
        if (_spatial == nil || texture.width != _sInW || texture.height != _sInH
         || width != _sOutW || height != _sOutH || texture.pixelFormat != _sFormat) {
            _spatial = nil;
            _outputs[0] = _outputs[1] = nil;
            if (![MTLFXSpatialScalerDescriptor supportsDevice:_device])
                return nil;
            MTLFXSpatialScalerDescriptor *desc = [MTLFXSpatialScalerDescriptor new];
            desc.colorTextureFormat = texture.pixelFormat;
            desc.outputTextureFormat = texture.pixelFormat;
            desc.inputWidth = texture.width;
            desc.inputHeight = texture.height;
            desc.outputWidth = width;
            desc.outputHeight = height;
            /* stage A is linear light that may exceed 1.0 */
            desc.colorProcessingMode = MTLFXSpatialScalerColorProcessingModeHDR;
            id<MTLFXSpatialScaler> scaler = [desc newSpatialScalerWithDevice:_device];
            if (scaler == nil)
                return nil;
            MTLTextureDescriptor *td = [MTLTextureDescriptor
                texture2DDescriptorWithPixelFormat:texture.pixelFormat
                                             width:width height:height mipmapped:NO];
            td.usage = scaler.outputTextureUsage | MTLTextureUsageShaderRead;
            td.storageMode = MTLStorageModePrivate;
            /* two, so the next frame never writes the one being drawn */
            for (int i = 0; i < 2; i++)
                if ((_outputs[i] = [_device newTextureWithDescriptor:td]) == nil)
                    return nil;
            _spatial = scaler;
            _sInW = texture.width; _sInH = texture.height;
            _sOutW = width; _sOutH = height;
            _sFormat = texture.pixelFormat;
        }
        id<MTLFXSpatialScaler> spatial = _spatial;
        if ((texture.usage & spatial.colorTextureUsage) != spatial.colorTextureUsage)
            return nil;
        id<MTLTexture> output = _outputs[_next];
        _next ^= 1;
        spatial.colorTexture = texture;
        spatial.outputTexture = output;
        spatial.inputContentWidth = texture.width;
        spatial.inputContentHeight = texture.height;
        [spatial encodeToCommandBuffer:commandBuffer];
        return output;
    }
    return nil;
}

@end
