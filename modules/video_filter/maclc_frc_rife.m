// SPDX-License-Identifier: LGPL-2.1-or-later
/*****************************************************************************
 * maclc_frc_rife.m: the RIFE neural network on Core ML
 *****************************************************************************
 * Copyright © 2026 Hazen Studio
 *
 * Synthesizes intermediate video frames by evaluating a RIFE neural network
 * via Core ML on Apple Silicon.
 *
 * Real-time budget considerations:
 * Published benchmarks for RIFE v4 report approximately 18-22 ms per 1080p
 * frame on an Apple M3 Max (40-core GPU). For a 24 fps source, each source
 * interval lasts 41.7 ms; doubling the frame rate requires generating one
 * intermediate frame (costing ~20 ms), which comfortably fits within the
 * frame budget. Conversely, 4K resolution quadruples the pixel workload,
 * taking ~75-95 ms per frame and exceeding real-time thresholds without
 * spatial downscaling. All timings referenced from external sources are
 * treated as second-hand estimates; runtime enforcement and degradation are
 * handled by the filter's real-time budget guard in maclc_frc.m.
 *****************************************************************************/

#ifdef HAVE_CONFIG_H
# include "config.h"
#endif

#include <vlc_common.h>
#include <vlc_plugin.h>
#include <vlc_filter.h>

#import <Foundation/Foundation.h>
#import <CoreVideo/CoreVideo.h>
#import <CoreMedia/CoreMedia.h>
#import <VideoToolbox/VideoToolbox.h>
#import <CoreML/CoreML.h>
#import <Accelerate/Accelerate.h>

#include "maclc_frc_backend.h"

/*****************************************************************************
 * Private Context Interface
 *****************************************************************************/

@interface MacLCFrcRifeContext : NSObject

@property (nonatomic, assign) vlc_object_t *log;

@property (nonatomic, assign) unsigned factor;
@property (nonatomic, assign) unsigned srcWidth;
@property (nonatomic, assign) unsigned srcHeight;
@property (nonatomic, assign) unsigned workingWidth;
@property (nonatomic, assign) unsigned workingHeight;

@property (nonatomic, assign) BOOL inputIsImage;
@property (nonatomic, assign) BOOL outputIsImage;
@property (nonatomic, assign) MLMultiArrayDataType inputMultiArrayDataType;
@property (nonatomic, assign) MLMultiArrayDataType outputMultiArrayDataType;

@property (nonatomic, copy) NSString *input0Name;
@property (nonatomic, copy) NSString *input1Name;
@property (nonatomic, copy) NSString *outputName;
@property (nonatomic, copy) NSString *timestepName;

@property (nonatomic, copy) NSArray<NSNumber *> *multiArrayInputShape;
@property (nonatomic, copy) NSArray<MLFeatureValue *> *timestepValues;

@property (nonatomic, strong) MLModel *model;
@property (nonatomic, strong) NSURL *computeURL;   /* the compiled model, to reload it under another configuration */
@property (nonatomic, strong) MLMultiArray *input0Array;
@property (nonatomic, strong) MLMultiArray *input1Array;

@property (nonatomic, strong) NSMutableDictionary<NSString *, id> *featureDict;

@property (nonatomic, assign) CVPixelBufferPoolRef outPool;
@property (nonatomic, assign) CVPixelBufferPoolRef bgraPool;

@property (nonatomic, assign) VTPixelTransferSessionRef xferIn;
@property (nonatomic, assign) VTPixelTransferSessionRef xferOut;

/* Cached representations of the current frame from the previous pair,
 * avoiding redundant scaling and color-space conversions when frames are consecutive. */
@property (nonatomic, assign) CVPixelBufferRef cachedCurSource;
@property (nonatomic, assign) CVPixelBufferRef cachedWorkCur;
@property (nonatomic, strong) MLMultiArray *cachedWorkCurArray;

/* Pre-allocated scratch buffers for Accelerate conversions in MultiArray mode. */
@property (nonatomic, assign) uint8_t *b8;
@property (nonatomic, assign) uint8_t *g8;
@property (nonatomic, assign) uint8_t *r8;
@property (nonatomic, assign) uint8_t *a8;
@property (nonatomic, assign) float *rScratchF;
@property (nonatomic, assign) float *gScratchF;
@property (nonatomic, assign) float *bScratchF;

- (BOOL)setupWithBackendSetup:(const struct maclc_frc_backend_setup *)setup;
- (BOOL)runWithPrev:(CVPixelBufferRef)prev cur:(CVPixelBufferRef)cur out:(CVPixelBufferRef *)out;
- (void)flush;
- (void)stop;

@end

/*****************************************************************************
 * Backend C Struct Wrapper
 *****************************************************************************/

struct maclc_frc_rife_backend
{
    struct maclc_frc_backend backend;
    MacLCFrcRifeContext *ctx;
};

/*****************************************************************************
 * Model Discovery and Compilation Helpers
 *****************************************************************************/

/* Checks whether a given URL points directly to an acceptable Core ML model
 * package/bundle or contains one. */
static NSURL *ResolveModelAtURL(NSURL *candidateURL, NSFileManager *fm)
{
    if (!candidateURL)
        return nil;

    NSString *ext = candidateURL.pathExtension.lowercaseString;
    if ([ext isEqualToString:@"mlmodelc"] || [ext isEqualToString:@"mlpackage"])
    {
        if ([fm fileExistsAtPath:candidateURL.path])
            return candidateURL;
        return nil;
    }

    BOOL isDir = NO;
    if (![fm fileExistsAtPath:candidateURL.path isDirectory:&isDir] || !isDir)
        return nil;

    /* Prioritize standard naming conventions first. */
    NSURL *standardModelc = [candidateURL URLByAppendingPathComponent:@"rife.mlmodelc"];
    if ([fm fileExistsAtPath:standardModelc.path])
        return standardModelc;

    NSURL *standardPackage = [candidateURL URLByAppendingPathComponent:@"rife.mlpackage"];
    if ([fm fileExistsAtPath:standardPackage.path])
        return standardPackage;

    /* Accept the single model inside the directory if exactly one exists. */
    NSError *dirErr = nil;
    NSArray<NSURL *> *contents = [fm contentsOfDirectoryAtURL:candidateURL
                                   includingPropertiesForKeys:nil
                                                      options:NSDirectoryEnumerationSkipsHiddenFiles
                                                        error:&dirErr];
    if (!contents || dirErr)
        return nil;

    NSMutableArray<NSURL *> *matches = [NSMutableArray arrayWithCapacity:2];
    for (NSURL *entry in contents)
    {
        NSString *entryExt = entry.pathExtension.lowercaseString;
        if ([entryExt isEqualToString:@"mlmodelc"] || [entryExt isEqualToString:@"mlpackage"])
            [matches addObject:entry];
    }

    if (matches.count == 1)
        return matches.firstObject;

    return nil;
}

/* Obtains the compiled model URL, compiling .mlpackage files into ~/Library/Caches/MacLC/models/
 * when necessary so that expensive compilation is only incurred on the first run. */
static NSURL *EnsureCompiledModel(NSURL *sourceURL, vlc_object_t *log, NSFileManager *fm)
{
    NSString *ext = sourceURL.pathExtension.lowercaseString;
    if ([ext isEqualToString:@"mlmodelc"])
        return sourceURL;

    NSArray<NSURL *> *cacheDirs = [fm URLsForDirectory:NSCachesDirectory inDomains:NSUserDomainMask];
    NSURL *userCache = cacheDirs.firstObject;
    if (!userCache)
    {
        msg_Err(log, "failed to locate user Caches directory for model compilation");
        return nil;
    }

    NSURL *modelCacheDir = [[userCache URLByAppendingPathComponent:@"MacLC"] URLByAppendingPathComponent:@"models"];
    NSError *mkdirErr = nil;
    if (![fm createDirectoryAtURL:modelCacheDir withIntermediateDirectories:YES attributes:nil error:&mkdirErr])
    {
        msg_Warn(log, "could not create model cache directory at '%s': %s",
                 modelCacheDir.path.UTF8String,
                 mkdirErr.localizedDescription.UTF8String ?: "unknown error");
    }

    NSDictionary *attrs = [fm attributesOfItemAtPath:sourceURL.path error:nil];
    NSDate *modDate = attrs[NSFileModificationDate] ?: [NSDate date];
    unsigned long long timestamp = (unsigned long long)[modDate timeIntervalSince1970];
    NSString *baseName = sourceURL.lastPathComponent.stringByDeletingPathExtension;
    NSString *cachedName = [NSString stringWithFormat:@"%@-%llu.mlmodelc", baseName, timestamp];
    NSURL *destinationCompiledURL = [modelCacheDir URLByAppendingPathComponent:cachedName];

    if ([fm fileExistsAtPath:destinationCompiledURL.path])
        return destinationCompiledURL;

    msg_Dbg(log, "compiling RIFE model at '%s'...", sourceURL.path.UTF8String);
    NSError *compileErr = nil;
    NSURL *tempCompiledURL = [MLModel compileModelAtURL:sourceURL error:&compileErr];
    if (!tempCompiledURL)
    {
        msg_Err(log, "failed to compile RIFE model: %s",
                compileErr.localizedDescription.UTF8String ?: "unknown error");
        return nil;
    }

    /* Move compiled artifact into permanent cache; fall back to temporary directory on failure. */
    NSError *copyErr = nil;
    if ([fm copyItemAtURL:tempCompiledURL toURL:destinationCompiledURL error:&copyErr])
    {
        [fm removeItemAtURL:tempCompiledURL error:nil];
        return destinationCompiledURL;
    }

    msg_Warn(log, "could not persist compiled model to '%s': %s; continuing with temporary output",
             destinationCompiledURL.path.UTF8String,
             copyErr.localizedDescription.UTF8String ?: "unknown error");
    return tempCompiledURL;
}

/*****************************************************************************
 * Pool Allocation Helper
 *****************************************************************************/

static CVPixelBufferPoolRef CreateWorkingBGRAPool(unsigned width, unsigned height, unsigned minCount)
{
    NSDictionary *poolAttrs = @{
        (__bridge NSString *)kCVPixelBufferPoolMinimumBufferCountKey: @(minCount),
    };
    NSDictionary *pixelAttrs = @{
        (__bridge NSString *)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA),
        (__bridge NSString *)kCVPixelBufferWidthKey: @(width),
        (__bridge NSString *)kCVPixelBufferHeightKey: @(height),
        (__bridge NSString *)kCVPixelBufferIOSurfacePropertiesKey: @{},
    };
    CVPixelBufferPoolRef pool = NULL;
    CVReturn err = CVPixelBufferPoolCreate(kCFAllocatorDefault,
                                          (__bridge CFDictionaryRef)poolAttrs,
                                          (__bridge CFDictionaryRef)pixelAttrs,
                                          &pool);
    if (err != kCVReturnSuccess)
        return NULL;
    return pool;
}

static CVPixelBufferRef PoolTake(CVPixelBufferPoolRef pool)
{
    if (!pool)
        return NULL;
    CVPixelBufferRef buffer = NULL;
    if (CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &buffer) != kCVReturnSuccess)
        return NULL;
    return buffer;
}

/*****************************************************************************
 * Context Implementation
 *****************************************************************************/

static MLComputeUnits ComputeUnitsFor(int choice)
{
    switch (choice)
    {
        case MACLC_FRC_RIFE_COMPUTE_NEURAL: return MLComputeUnitsAll;
        case MACLC_FRC_RIFE_COMPUTE_CPU:    return MLComputeUnitsCPUOnly;
        default:                            return MLComputeUnitsCPUAndGPU;
    }
}

static const char *ComputeUnitsName(int choice)
{
    switch (choice)
    {
        case MACLC_FRC_RIFE_COMPUTE_NEURAL: return "the Neural Engine and the GPU";
        case MACLC_FRC_RIFE_COMPUTE_CPU:    return "the processor";
        default:                            return "the GPU";
    }
}

@implementation MacLCFrcRifeContext

- (BOOL)setupWithBackendSetup:(const struct maclc_frc_backend_setup *)setup
{
    _log = setup->log;
    _factor = setup->factor;
    _srcWidth = setup->width;
    _srcHeight = setup->height;
    _outPool = setup->out_pool;

    NSFileManager *fm = [NSFileManager defaultManager];
    NSMutableArray<NSString *> *searchedDirectories = [NSMutableArray arrayWithCapacity:3];
    NSURL *foundModelURL = nil;

    /* 1. Explicit user configuration via setup->rife_model. */
    if (setup->rife_model != NULL && setup->rife_model[0] != '\0')
    {
        NSString *userPath = [NSString stringWithUTF8String:setup->rife_model];
        [searchedDirectories addObject:userPath];
        foundModelURL = ResolveModelAtURL([NSURL fileURLWithPath:userPath], fm);
    }

    /* 2. Bundle resources directory via bundleForClass. */
    if (!foundModelURL)
    {
        NSBundle *pluginBundle = [NSBundle bundleForClass:[self class]];
        NSURL *bundleRes = [pluginBundle resourceURL];
        if (bundleRes)
        {
            NSURL *modelsDir = [bundleRes URLByAppendingPathComponent:@"models"];
            [searchedDirectories addObject:modelsDir.path];
            foundModelURL = ResolveModelAtURL(modelsDir, fm);
        }

        /* If loaded as a standalone plug-in within Contents/MacOS/plugins/, inspect parent app resources. */
        if (!foundModelURL && pluginBundle.bundleURL)
        {
            NSURL *appResourcesModels = [[[[pluginBundle.bundleURL URLByDeletingLastPathComponent]
                                           URLByDeletingLastPathComponent]
                                          URLByAppendingPathComponent:@"Resources"]
                                         URLByAppendingPathComponent:@"models"];
            if (appResourcesModels && ![searchedDirectories containsObject:appResourcesModels.path])
            {
                [searchedDirectories addObject:appResourcesModels.path];
                foundModelURL = ResolveModelAtURL(appResourcesModels, fm);
            }
        }
    }

    /* 3. User Application Support models directory. */
    if (!foundModelURL)
    {
        NSArray<NSURL *> *appSupport = [fm URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask];
        if (appSupport.firstObject)
        {
            NSURL *userModelsDir = [[appSupport.firstObject URLByAppendingPathComponent:@"MacLC"] URLByAppendingPathComponent:@"models"];
            [searchedDirectories addObject:userModelsDir.path];
            foundModelURL = ResolveModelAtURL(userModelsDir, fm);
        }
    }

    if (!foundModelURL)
    {
        NSString *dirsList = [searchedDirectories componentsJoinedByString:@", "];
        msg_Warn(_log, "the RIFE engine requires a Core ML model (.mlmodelc or .mlpackage). "
                       "None found in: %s. "
                       "Please place a RIFE model in '~/Library/Application Support/MacLC/models/' "
                       "or specify the path with --maclc-frc-rife-model.",
                 dirsList.UTF8String);
        return NO;
    }

    NSURL *compiledModelURL = EnsureCompiledModel(foundModelURL, _log, fm);
    if (!compiledModelURL)
        return NO;

    /* Which silicon runs the network is not obvious and is not the same for
     * every model: measured here on an M3 Max, RIFE v4.25 at 1920x1088 takes
     * about 33 ms with the GPU alone and about 285 ms when the Neural Engine
     * is allowed, because the warps it cannot run split the network into
     * pieces that then travel back and forth. So unless the user names a
     * choice, both are timed on this machine and the faster one is kept. */
    self.computeURL = compiledModelURL;
    MLModelConfiguration *modelConfig = [[MLModelConfiguration alloc] init];
    modelConfig.computeUnits = ComputeUnitsFor(setup->rife_compute);

    NSError *loadErr = nil;
    _model = [MLModel modelWithContentsOfURL:compiledModelURL configuration:modelConfig error:&loadErr];
    if (!_model)
    {
        msg_Err(_log, "failed to load Core ML model from '%s': %s",
                compiledModelURL.path.UTF8String,
                loadErr.localizedDescription.UTF8String ?: "unknown error");
        return NO;
    }

    /* Inspect input and output feature descriptions to adapt to varying model signatures. */
    MLModelDescription *desc = _model.modelDescription;
    NSDictionary<NSString *, MLFeatureDescription *> *inDescs = desc.inputDescriptionsByName;
    NSDictionary<NSString *, MLFeatureDescription *> *outDescs = desc.outputDescriptionsByName;

    MLFeatureDescription *timestepDesc = nil;
    NSMutableArray<MLFeatureDescription *> *pictureDescs = [NSMutableArray arrayWithCapacity:2];

    for (NSString *key in inDescs)
    {
        MLFeatureDescription *fd = inDescs[key];
        NSString *lowerName = key.lowercaseString;

        /* Discriminate scalar or single-element multi-arrays used for timestep injection. */
        const BOOL isTimestepByName = [lowerName isEqualToString:@"t"]
                                   || [lowerName containsString:@"time"]
                                   || [lowerName containsString:@"timestep"];
        const BOOL isScalarType = (fd.type == MLFeatureTypeDouble || fd.type == MLFeatureTypeInt64);
        BOOL isSingleElementArray = NO;
        if (fd.type == MLFeatureTypeMultiArray)
        {
            NSArray<NSNumber *> *sh = fd.multiArrayConstraint.shape;
            NSInteger total = 1;
            for (NSNumber *n in sh)
                total *= n.integerValue;
            if (total == 1)
                isSingleElementArray = YES;
        }

        if (isScalarType || isSingleElementArray || (isTimestepByName && fd.type == MLFeatureTypeMultiArray))
        {
            timestepDesc = fd;
        }
        else if (fd.type == MLFeatureTypeImage || fd.type == MLFeatureTypeMultiArray)
        {
            [pictureDescs addObject:fd];
        }
        else
        {
            msg_Err(_log, "unsupported input feature '%s' of type %ld in RIFE model",
                    key.UTF8String, (long)fd.type);
            return NO;
        }
    }

    if (pictureDescs.count != 2)
    {
        msg_Err(_log, "RIFE model must have exactly 2 image/multiarray inputs, found %lu",
                (unsigned long)pictureDescs.count);
        return NO;
    }

    /* Standard models without a timestep input can only compute the half-interval frame. */
    if (!timestepDesc && _factor != 2)
    {
        msg_Warn(_log, "RIFE model has no timestep input (only supports 2x interpolation), "
                       "but factor %u was requested; refusing to start", _factor);
        return NO;
    }

    /* Determine input ordering (frame 0 before frame 1) using common naming heuristics. */
    MLFeatureDescription *p0 = pictureDescs[0];
    MLFeatureDescription *p1 = pictureDescs[1];
    NSString *n0 = p0.name.lowercaseString;
    NSString *n1 = p1.name.lowercaseString;

    const BOOL n0IsFirst = [n0 containsString:@"0"] || [n0 containsString:@"prev"]
                        || [n0 containsString:@"first"] || [n0 containsString:@"before"];
    const BOOL n1IsFirst = [n1 containsString:@"0"] || [n1 containsString:@"prev"]
                        || [n1 containsString:@"first"] || [n1 containsString:@"before"];

    if (n1IsFirst && !n0IsFirst)
    {
        _input0Name = p1.name;
        _input1Name = p0.name;
        _inputIsImage = (p1.type == MLFeatureTypeImage);
        _inputMultiArrayDataType = p1.multiArrayConstraint.dataType;
    }
    else
    {
        _input0Name = p0.name;
        _input1Name = p1.name;
        _inputIsImage = (p0.type == MLFeatureTypeImage);
        _inputMultiArrayDataType = p0.multiArrayConstraint.dataType;
    }

    if (timestepDesc)
        _timestepName = timestepDesc.name;

    /* Verify output signature. */
    if (outDescs.count == 0)
    {
        msg_Err(_log, "RIFE model provides no output features");
        return NO;
    }

    MLFeatureDescription *outDesc = nil;
    for (NSString *k in outDescs)
    {
        MLFeatureDescription *d = outDescs[k];
        if (d.type == MLFeatureTypeImage || d.type == MLFeatureTypeMultiArray)
        {
            outDesc = d;
            break;
        }
    }

    if (!outDesc)
    {
        msg_Err(_log, "RIFE model output must be an image or a MultiArray");
        return NO;
    }

    _outputName = outDesc.name;
    _outputIsImage = (outDesc.type == MLFeatureTypeImage);
    _outputMultiArrayDataType = outDesc.multiArrayConstraint.dataType;

    /* Determine working dimensions. RIFE's optical flow coarse-to-fine spatial
     * pyramid requires image dimensions to be divisible by 32. */
    float scale = setup->rife_scale;
    if (scale <= 0.0f || scale > 1.0f)
        scale = 1.0f;

    unsigned desiredW = (unsigned)roundf((float)_srcWidth * scale);
    unsigned desiredH = (unsigned)roundf((float)_srcHeight * scale);
    desiredW = (desiredW / 32) * 32;
    desiredH = (desiredH / 32) * 32;
    if (desiredW < 32) desiredW = 32;
    if (desiredH < 32) desiredH = 32;

    MLFeatureDescription *primaryInputDesc = [inDescs objectForKey:_input0Name];
    if (_inputIsImage)
    {
        MLImageConstraint *imgConstraint = primaryInputDesc.imageConstraint;
        MLImageSizeConstraint *sizeConstraint = imgConstraint.sizeConstraint;
        if (sizeConstraint && sizeConstraint.type == MLImageSizeConstraintTypeEnumerated)
        {
            NSArray<MLImageSize *> *sizes = sizeConstraint.enumeratedImageSizes;
            MLImageSize *closest = nil;
            unsigned minDiff = UINT_MAX;
            for (MLImageSize *s in sizes)
            {
                unsigned diff = (unsigned)(abs((int)s.pixelsWide - (int)desiredW) + abs((int)s.pixelsHigh - (int)desiredH));
                if (diff < minDiff)
                {
                    minDiff = diff;
                    closest = s;
                }
            }
            if (closest)
            {
                _workingWidth = ((unsigned)closest.pixelsWide / 32) * 32;
                _workingHeight = ((unsigned)closest.pixelsHigh / 32) * 32;
            }
        }
        else if (sizeConstraint && sizeConstraint.type == MLImageSizeConstraintTypeRange)
        {
            NSRange wRange = sizeConstraint.pixelsWideRange;
            NSRange hRange = sizeConstraint.pixelsHighRange;
            unsigned clampedW = desiredW;
            if (clampedW < wRange.location) clampedW = (unsigned)wRange.location;
            if (clampedW >= NSMaxRange(wRange)) clampedW = (unsigned)NSMaxRange(wRange) - 1;
            clampedW = (clampedW / 32) * 32;
            if (clampedW < wRange.location) clampedW = (unsigned)wRange.location;

            unsigned clampedH = desiredH;
            if (clampedH < hRange.location) clampedH = (unsigned)hRange.location;
            if (clampedH >= NSMaxRange(hRange)) clampedH = (unsigned)NSMaxRange(hRange) - 1;
            clampedH = (clampedH / 32) * 32;
            if (clampedH < hRange.location) clampedH = (unsigned)hRange.location;

            _workingWidth = clampedW;
            _workingHeight = clampedH;
        }
        else
        {
            _workingWidth = (unsigned)imgConstraint.pixelsWide;
            _workingHeight = (unsigned)imgConstraint.pixelsHigh;
        }
    }
    else
    {
        MLMultiArrayConstraint *mac = primaryInputDesc.multiArrayConstraint;
        MLMultiArrayShapeConstraint *sc = mac.shapeConstraint;
        if (sc && sc.type == MLMultiArrayShapeConstraintTypeEnumerated)
        {
            NSArray<NSArray<NSNumber *> *> *shapes = sc.enumeratedShapes;
            NSArray<NSNumber *> *bestShape = nil;
            unsigned minDiff = UINT_MAX;
            for (NSArray<NSNumber *> *sh in shapes)
            {
                if (sh.count >= 2)
                {
                    unsigned w = sh[sh.count - 1].unsignedIntValue;
                    unsigned h = sh[sh.count - 2].unsignedIntValue;
                    unsigned diff = (unsigned)(abs((int)w - (int)desiredW) + abs((int)h - (int)desiredH));
                    if (diff < minDiff)
                    {
                        minDiff = diff;
                        bestShape = sh;
                    }
                }
            }
            if (bestShape && bestShape.count >= 2)
            {
                _workingWidth = (bestShape[bestShape.count - 1].unsignedIntValue / 32) * 32;
                _workingHeight = (bestShape[bestShape.count - 2].unsignedIntValue / 32) * 32;
                _multiArrayInputShape = bestShape;
            }
        }
        else if (sc && sc.type == MLMultiArrayShapeConstraintTypeRange)
        {
            NSArray<NSValue *> *ranges = sc.sizeRangeForDimension;
            if (ranges.count >= 2)
            {
                NSRange wRange = ranges[ranges.count - 1].rangeValue;
                NSRange hRange = ranges[ranges.count - 2].rangeValue;
                unsigned clampedW = (desiredW / 32) * 32;
                if (clampedW < wRange.location) clampedW = (unsigned)wRange.location;
                if (clampedW >= NSMaxRange(wRange)) clampedW = (unsigned)NSMaxRange(wRange) - 1;

                unsigned clampedH = (desiredH / 32) * 32;
                if (clampedH < hRange.location) clampedH = (unsigned)hRange.location;
                if (clampedH >= NSMaxRange(hRange)) clampedH = (unsigned)NSMaxRange(hRange) - 1;

                _workingWidth = clampedW;
                _workingHeight = clampedH;
                _multiArrayInputShape = @[ @1, @3, @(_workingHeight), @(_workingWidth) ];
            }
        }
        else
        {
            NSArray<NSNumber *> *sh = mac.shape;
            if (sh.count >= 2)
            {
                _workingWidth = sh[sh.count - 1].unsignedIntValue;
                _workingHeight = sh[sh.count - 2].unsignedIntValue;
                _multiArrayInputShape = sh;
            }
        }
    }

    if (_workingWidth == 0 || _workingHeight == 0)
    {
        _workingWidth = desiredW;
        _workingHeight = desiredH;
    }

    if (!_inputIsImage && !_multiArrayInputShape)
        _multiArrayInputShape = @[ @1, @3, @(_workingHeight), @(_workingWidth) ];

    msg_Dbg(_log, "RIFE model loaded from '%s', signature: [%s -> %s, timestep: %s], "
                 "working size: %ux%u (scale %.2f), Neural Engine allowed",
            compiledModelURL.path.UTF8String,
            _inputIsImage ? "Image" : "MultiArray",
            _outputIsImage ? "Image" : "MultiArray",
            _timestepName ? _timestepName.UTF8String : "none (fixed 2x)",
            _workingWidth, _workingHeight,
            scale);

    /* Allocate pixel transfer sessions. Scaling mode is explicitly forced to Normal
     * so that working sizes with slightly differing aspect ratios stretch the contents
     * rather than letterboxing with black bars. */
    if (VTPixelTransferSessionCreate(kCFAllocatorDefault, &_xferIn) != noErr
     || VTPixelTransferSessionCreate(kCFAllocatorDefault, &_xferOut) != noErr)
    {
        msg_Err(_log, "failed to create VideoToolbox pixel transfer sessions");
        return NO;
    }

    VTSessionSetProperty(_xferIn, kVTPixelTransferPropertyKey_RealTime, kCFBooleanTrue);
    VTSessionSetProperty(_xferIn, kVTPixelTransferPropertyKey_ScalingMode, kVTScalingMode_Normal);
    VTSessionSetProperty(_xferOut, kVTPixelTransferPropertyKey_RealTime, kCFBooleanTrue);
    VTSessionSetProperty(_xferOut, kVTPixelTransferPropertyKey_ScalingMode, kVTScalingMode_Normal);

    /* Dedicated working pool holding uncompressed BGRA buffers for inference. */
    _bgraPool = CreateWorkingBGRAPool(_workingWidth, _workingHeight, _factor + 2);
    if (!_bgraPool)
    {
        msg_Err(_log, "failed to create working BGRA pixel buffer pool");
        return NO;
    }

    /* Pre-compute timestep feature representations to avoid allocating metadata objects
     * on the critical video output thread. */
    if (_timestepName)
    {
        NSMutableArray<MLFeatureValue *> *tv = [NSMutableArray arrayWithCapacity:_factor - 1];
        for (unsigned i = 1; i < _factor; i++)
        {
            const double phase = (double)i / (double)_factor;
            MLFeatureDescription *tDesc = [inDescs objectForKey:_timestepName];
            if (tDesc.type == MLFeatureTypeMultiArray)
            {
                NSArray<NSNumber *> *tShape = tDesc.multiArrayConstraint.shape ?: @[ @1 ];
                NSError *tErr = nil;
                MLMultiArray *tArr = [[MLMultiArray alloc] initWithShape:tShape
                                                                dataType:tDesc.multiArrayConstraint.dataType
                                                                   error:&tErr];
                if (!tArr)
                {
                    msg_Err(_log, "failed to allocate timestep MultiArray: %s",
                            tErr.localizedDescription.UTF8String ?: "unknown error");
                    return NO;
                }
                if (tDesc.multiArrayConstraint.dataType == MLMultiArrayDataTypeDouble)
                    *(double *)tArr.dataPointer = phase;
                else
                    *(float *)tArr.dataPointer = (float)phase;

                [tv addObject:[MLFeatureValue featureValueWithMultiArray:tArr]];
            }
            else
            {
                [tv addObject:[MLFeatureValue featureValueWithDouble:phase]];
            }
        }
        _timestepValues = [tv copy];
    }

    /* Allocate persistent MultiArray tensors and scratch memory when working with planar arrays. */
    if (!_inputIsImage)
    {
        NSError *aErr = nil;
        _input0Array = [[MLMultiArray alloc] initWithShape:_multiArrayInputShape
                                                  dataType:_inputMultiArrayDataType
                                                     error:&aErr];
        _input1Array = [[MLMultiArray alloc] initWithShape:_multiArrayInputShape
                                                  dataType:_inputMultiArrayDataType
                                                     error:&aErr];
        if (!_input0Array || !_input1Array)
        {
            msg_Err(_log, "failed to allocate persistent input MultiArrays: %s",
                    aErr.localizedDescription.UTF8String ?: "unknown error");
            return NO;
        }

        const size_t planePixels = (size_t)_workingWidth * _workingHeight;
        _b8 = malloc(planePixels);
        _g8 = malloc(planePixels);
        _r8 = malloc(planePixels);
        _a8 = malloc(planePixels);
        _rScratchF = malloc(planePixels * sizeof(float));
        _gScratchF = malloc(planePixels * sizeof(float));
        _bScratchF = malloc(planePixels * sizeof(float));
        if (!_b8 || !_g8 || !_r8 || !_a8 || !_rScratchF || !_gScratchF || !_bScratchF)
        {
            msg_Err(_log, "failed to allocate planar scratch buffers");
            return NO;
        }
    }
    else if (!_outputIsImage)
    {
        const size_t planePixels = (size_t)_workingWidth * _workingHeight;
        _b8 = malloc(planePixels);
        _g8 = malloc(planePixels);
        _r8 = malloc(planePixels);
        _a8 = malloc(planePixels);
        _rScratchF = malloc(planePixels * sizeof(float));
        _gScratchF = malloc(planePixels * sizeof(float));
        _bScratchF = malloc(planePixels * sizeof(float));
        if (!_b8 || !_g8 || !_r8 || !_a8 || !_rScratchF || !_gScratchF || !_bScratchF)
        {
            msg_Err(_log, "failed to allocate planar scratch buffers for output");
            return NO;
        }
    }

    _featureDict = [NSMutableDictionary dictionaryWithCapacity:3];

    /* The first inference of a freshly compiled model pays for its own
     * warm-up -- a second or so -- and the filter's budget guard would see
     * that as an engine far too slow to keep and throw it away. Both the
     * warm-up and the choice of silicon happen here, before anyone is timing. */
    [self chooseComputeUnits:setup->rife_compute];
    return YES;
}

/* Times one inference under a configuration, in microseconds, or 0 on failure. */
- (vlc_tick_t)timeOneInferenceWithUnits:(MLComputeUnits)units reload:(BOOL)reload
{
    if (reload)
    {
        MLModelConfiguration *cfg = [[MLModelConfiguration alloc] init];
        cfg.computeUnits = units;
        NSError *err = nil;
        MLModel *m = [MLModel modelWithContentsOfURL:self.computeURL configuration:cfg error:&err];
        if (!m)
            return 0;
        _model = m;
    }

    CVPixelBufferRef a = PoolTake(_bgraPool);
    CVPixelBufferRef b = PoolTake(_bgraPool);
    vlc_tick_t spent = 0;
    if (a != NULL && b != NULL)
    {
        _featureDict[_input0Name] = [MLFeatureValue featureValueWithPixelBuffer:a];
        _featureDict[_input1Name] = [MLFeatureValue featureValueWithPixelBuffer:b];
        if (_timestepName != nil && _timestepValues.count > 0)
            _featureDict[_timestepName] = _timestepValues[0];

        NSError *err = nil;
        id<MLFeatureProvider> provider =
            [[MLDictionaryFeatureProvider alloc] initWithDictionary:_featureDict error:&err];
        if (provider != nil)
        {
            /* Once to warm up, once to time. */
            if ([_model predictionFromFeatures:provider error:&err] != nil)
            {
                const vlc_tick_t started = vlc_tick_now();
                if ([_model predictionFromFeatures:provider error:&err] != nil)
                    spent = vlc_tick_now() - started;
            }
        }
        [_featureDict removeAllObjects];
    }
    if (a != NULL) CVPixelBufferRelease(a);
    if (b != NULL) CVPixelBufferRelease(b);
    return spent;
}

- (void)chooseComputeUnits:(int)requested
{
    if (!self.inputIsImage)
    {
        /* The probe feeds pixel buffers; a model that wants arrays is simply
         * warmed up under whatever the user asked for. */
        return;
    }

    if (requested != MACLC_FRC_RIFE_COMPUTE_MEASURE)
    {
        const vlc_tick_t t = [self timeOneInferenceWithUnits:ComputeUnitsFor(requested) reload:NO];
        msg_Dbg(_log, "RIFE on %s: %.1f ms a frame",
                ComputeUnitsName(requested), (double)t / 1000.0);
        return;
    }

    const vlc_tick_t gpu = [self timeOneInferenceWithUnits:MLComputeUnitsCPUAndGPU reload:YES];
    const vlc_tick_t all = [self timeOneInferenceWithUnits:MLComputeUnitsAll reload:YES];

    const bool gpu_wins = gpu > 0 && (all == 0 || gpu < all);
    msg_Dbg(_log, "RIFE measured here: %.1f ms on the GPU, %.1f ms with the "
            "Neural Engine allowed; keeping %s",
            (double)gpu / 1000.0, (double)all / 1000.0,
            gpu_wins ? "the GPU" : "the Neural Engine");

    if (gpu_wins)
        [self timeOneInferenceWithUnits:MLComputeUnitsCPUAndGPU reload:YES];
}

/*****************************************************************************
 * Accelerate Format Conversions
 *****************************************************************************/

- (BOOL)convertBGRAToMultiArray:(CVPixelBufferRef)bgraBuf
                 dstMultiArray:(MLMultiArray *)multiArray
{
    if (CVPixelBufferLockBaseAddress(bgraBuf, kCVPixelBufferLock_ReadOnly) != kCVReturnSuccess)
        return NO;

    void *bgraPtr = CVPixelBufferGetBaseAddress(bgraBuf);
    const size_t rowBytes = CVPixelBufferGetBytesPerRow(bgraBuf);

    vImage_Buffer srcBGRA = {
        .data = bgraPtr,
        .height = _workingHeight,
        .width = _workingWidth,
        .rowBytes = rowBytes,
    };
    vImage_Buffer bufB8 = { .data = _b8, .height = _workingHeight, .width = _workingWidth, .rowBytes = _workingWidth };
    vImage_Buffer bufG8 = { .data = _g8, .height = _workingHeight, .width = _workingWidth, .rowBytes = _workingWidth };
    vImage_Buffer bufR8 = { .data = _r8, .height = _workingHeight, .width = _workingWidth, .rowBytes = _workingWidth };
    vImage_Buffer bufA8 = { .data = _a8, .height = _workingHeight, .width = _workingWidth, .rowBytes = _workingWidth };

    /* Deinterleave BGRA into planar 8-bit components. */
    vImage_Error vErr = vImageConvert_BGRA8888toPlanar8(&srcBGRA, &bufB8, &bufG8, &bufR8, &bufA8, kvImageNoFlags);
    CVPixelBufferUnlockBaseAddress(bgraBuf, kCVPixelBufferLock_ReadOnly);
    if (vErr != kvImageNoError)
        return NO;

    const size_t planePixels = (size_t)_workingWidth * _workingHeight;
    float *dstFloatR = _rScratchF;
    float *dstFloatG = _gScratchF;
    float *dstFloatB = _bScratchF;

    if (_inputMultiArrayDataType == MLMultiArrayDataTypeFloat32)
    {
        dstFloatR = (float *)multiArray.dataPointer;
        dstFloatG = dstFloatR + planePixels;
        dstFloatB = dstFloatG + planePixels;
    }

    vImage_Buffer bufRF = { .data = dstFloatR, .height = _workingHeight, .width = _workingWidth, .rowBytes = _workingWidth * sizeof(float) };
    vImage_Buffer bufGF = { .data = dstFloatG, .height = _workingHeight, .width = _workingWidth, .rowBytes = _workingWidth * sizeof(float) };
    vImage_Buffer bufBF = { .data = dstFloatB, .height = _workingHeight, .width = _workingWidth, .rowBytes = _workingWidth * sizeof(float) };

    /* Scale 8-bit integers [0, 255] to normalized floats [0.0, 1.0]. */
    vImageConvert_Planar8toPlanarF(&bufR8, &bufRF, 1.0f, 0.0f, kvImageNoFlags);
    vImageConvert_Planar8toPlanarF(&bufG8, &bufGF, 1.0f, 0.0f, kvImageNoFlags);
    vImageConvert_Planar8toPlanarF(&bufB8, &bufBF, 1.0f, 0.0f, kvImageNoFlags);

    if (_inputMultiArrayDataType == MLMultiArrayDataTypeFloat16)
    {
        uint16_t *dst16R = (uint16_t *)multiArray.dataPointer;
        uint16_t *dst16G = dst16R + planePixels;
        uint16_t *dst16B = dst16G + planePixels;

        vImage_Buffer dstBuf16R = { .data = dst16R, .height = _workingHeight, .width = _workingWidth, .rowBytes = _workingWidth * sizeof(uint16_t) };
        vImage_Buffer dstBuf16G = { .data = dst16G, .height = _workingHeight, .width = _workingWidth, .rowBytes = _workingWidth * sizeof(uint16_t) };
        vImage_Buffer dstBuf16B = { .data = dst16B, .height = _workingHeight, .width = _workingWidth, .rowBytes = _workingWidth * sizeof(uint16_t) };

        vImageConvert_PlanarFtoPlanar16F(&bufRF, &dstBuf16R, kvImageNoFlags);
        vImageConvert_PlanarFtoPlanar16F(&bufGF, &dstBuf16G, kvImageNoFlags);
        vImageConvert_PlanarFtoPlanar16F(&bufBF, &dstBuf16B, kvImageNoFlags);
    }

    return YES;
}

- (BOOL)convertMultiArrayToBGRA:(MLMultiArray *)multiArray
                 dstPixelBuffer:(CVPixelBufferRef)bgraBuf
{
    const float minVal = 0.0f;
    const float maxVal = 1.0f;

    /* Core ML is free to pad rows and planes, and does on some devices, so the
     * layout comes from the array rather than from the picture's size. The
     * last three strides are plane, row and column whether the shape is
     * [1, 3, H, W] or [3, H, W]. */
    NSArray<NSNumber *> *strides = multiArray.strides;
    if (strides.count < 3)
        return false;
    const size_t planeStride = strides[strides.count - 3].unsignedLongValue;
    const size_t rowStride   = strides[strides.count - 2].unsignedLongValue;
    if (strides[strides.count - 1].unsignedLongValue != 1
     || rowStride < (size_t)_workingWidth
     || planeStride < rowStride * (size_t)_workingHeight)
        return NO;

    /* The scratch planes are packed, so everything downstream counts pixels. */
    const size_t planePixels = (size_t)_workingWidth * _workingHeight;

    float *srcFloatR = NULL;
    float *srcFloatG = NULL;
    float *srcFloatB = NULL;

    if (multiArray.dataType == MLMultiArrayDataTypeFloat16)
    {
        uint16_t *src16R = (uint16_t *)multiArray.dataPointer;
        uint16_t *src16G = src16R + planeStride;
        uint16_t *src16B = src16G + planeStride;
        const size_t srcRowBytes16 = rowStride * sizeof(uint16_t);

        vImage_Buffer srcBuf16R = { .data = src16R, .height = _workingHeight, .width = _workingWidth, .rowBytes = srcRowBytes16 };
        vImage_Buffer srcBuf16G = { .data = src16G, .height = _workingHeight, .width = _workingWidth, .rowBytes = srcRowBytes16 };
        vImage_Buffer srcBuf16B = { .data = src16B, .height = _workingHeight, .width = _workingWidth, .rowBytes = srcRowBytes16 };

        vImage_Buffer dstBufFR = { .data = _rScratchF, .height = _workingHeight, .width = _workingWidth, .rowBytes = _workingWidth * sizeof(float) };
        vImage_Buffer dstBufFG = { .data = _gScratchF, .height = _workingHeight, .width = _workingWidth, .rowBytes = _workingWidth * sizeof(float) };
        vImage_Buffer dstBufFB = { .data = _bScratchF, .height = _workingHeight, .width = _workingWidth, .rowBytes = _workingWidth * sizeof(float) };

        vImageConvert_Planar16FtoPlanarF(&srcBuf16R, &dstBufFR, kvImageNoFlags);
        vImageConvert_Planar16FtoPlanarF(&srcBuf16G, &dstBufFG, kvImageNoFlags);
        vImageConvert_Planar16FtoPlanarF(&srcBuf16B, &dstBufFB, kvImageNoFlags);

        srcFloatR = _rScratchF;
        srcFloatG = _gScratchF;
        srcFloatB = _bScratchF;
    }
    else
    {
        float *plane0 = (float *)multiArray.dataPointer;
        const size_t srcRowBytesF = rowStride * sizeof(float);
        vImage_Buffer srcF[3] = {
            { .data = plane0,                   .height = _workingHeight, .width = _workingWidth, .rowBytes = srcRowBytesF },
            { .data = plane0 + planeStride,     .height = _workingHeight, .width = _workingWidth, .rowBytes = srcRowBytesF },
            { .data = plane0 + planeStride * 2, .height = _workingHeight, .width = _workingWidth, .rowBytes = srcRowBytesF },
        };
        float *scratch[3] = { _rScratchF, _gScratchF, _bScratchF };
        for (unsigned i = 0; i < 3; i++)
        {
            vImage_Buffer dst = { .data = scratch[i], .height = _workingHeight,
                                  .width = _workingWidth,
                                  .rowBytes = (size_t)_workingWidth * sizeof(float) };
            if (vImageCopyBuffer(&srcF[i], &dst, sizeof(float), kvImageNoFlags) != kvImageNoError)
                return NO;
        }
        srcFloatR = _rScratchF;
        srcFloatG = _gScratchF;
        srcFloatB = _bScratchF;
    }

    /* Constrain synthesized floating-point color values to the valid [0.0, 1.0] unit range. */
    vDSP_vclip(srcFloatR, 1, &minVal, &maxVal, _rScratchF, 1, planePixels);
    vDSP_vclip(srcFloatG, 1, &minVal, &maxVal, _gScratchF, 1, planePixels);
    vDSP_vclip(srcFloatB, 1, &minVal, &maxVal, _bScratchF, 1, planePixels);

    vImage_Buffer bufRF = { .data = _rScratchF, .height = _workingHeight, .width = _workingWidth, .rowBytes = _workingWidth * sizeof(float) };
    vImage_Buffer bufGF = { .data = _gScratchF, .height = _workingHeight, .width = _workingWidth, .rowBytes = _workingWidth * sizeof(float) };
    vImage_Buffer bufBF = { .data = _bScratchF, .height = _workingHeight, .width = _workingWidth, .rowBytes = _workingWidth * sizeof(float) };

    vImage_Buffer bufR8 = { .data = _r8, .height = _workingHeight, .width = _workingWidth, .rowBytes = _workingWidth };
    vImage_Buffer bufG8 = { .data = _g8, .height = _workingHeight, .width = _workingWidth, .rowBytes = _workingWidth };
    vImage_Buffer bufB8 = { .data = _b8, .height = _workingHeight, .width = _workingWidth, .rowBytes = _workingWidth };
    vImage_Buffer bufA8 = { .data = _a8, .height = _workingHeight, .width = _workingWidth, .rowBytes = _workingWidth };

    vImageConvert_PlanarFtoPlanar8(&bufRF, &bufR8, 1.0f, 0.0f, kvImageNoFlags);
    vImageConvert_PlanarFtoPlanar8(&bufGF, &bufG8, 1.0f, 0.0f, kvImageNoFlags);
    vImageConvert_PlanarFtoPlanar8(&bufBF, &bufB8, 1.0f, 0.0f, kvImageNoFlags);
    memset(_a8, 255, planePixels);

    if (CVPixelBufferLockBaseAddress(bgraBuf, 0) != kCVReturnSuccess)
        return NO;

    void *dstPtr = CVPixelBufferGetBaseAddress(bgraBuf);
    const size_t dstRowBytes = CVPixelBufferGetBytesPerRow(bgraBuf);

    vImage_Buffer dstBGRA = {
        .data = dstPtr,
        .height = _workingHeight,
        .width = _workingWidth,
        .rowBytes = dstRowBytes,
    };

    /* Interleave planar bytes into 32BGRA format. In vImageConvert_Planar8toARGB8888,
     * the arguments map sequentially to byte offsets 0 (B), 1 (G), 2 (R), and 3 (A). */
    vImage_Error vErr = vImageConvert_Planar8toARGB8888(&bufB8, &bufG8, &bufR8, &bufA8, &dstBGRA, kvImageNoFlags);
    CVPixelBufferUnlockBaseAddress(bgraBuf, 0);

    return (vErr == kvImageNoError);
}

/*****************************************************************************
 * Prediction Pipeline
 *****************************************************************************/

- (BOOL)runWithPrev:(CVPixelBufferRef)prev cur:(CVPixelBufferRef)cur out:(CVPixelBufferRef *)out
{
    const unsigned count = _factor - 1;
    for (unsigned i = 0; i < count; i++)
        out[i] = NULL;

    CVPixelBufferRef workPrevBuf = NULL;
    CVPixelBufferRef workCurBuf = NULL;
    MLFeatureValue *feat0 = nil;
    MLFeatureValue *feat1 = nil;
    MLMultiArray *curTargetArray = nil;

    /* Check if previous frame's working buffer matches our cached tensor from the last call. */
    const BOOL reusePrev = (_cachedCurSource != NULL && _cachedCurSource == prev
                            && (_cachedWorkCur != NULL || _cachedWorkCurArray != nil));

    if (_inputIsImage)
    {
        if (reusePrev)
        {
            workPrevBuf = CVPixelBufferRetain(_cachedWorkCur);
        }
        else
        {
            workPrevBuf = PoolTake(_bgraPool);
            if (!workPrevBuf)
                return NO;
            if (VTPixelTransferSessionTransferImage(_xferIn, prev, workPrevBuf) != noErr)
            {
                CVPixelBufferRelease(workPrevBuf);
                return NO;
            }
        }

        workCurBuf = PoolTake(_bgraPool);
        if (!workCurBuf)
        {
            CVPixelBufferRelease(workPrevBuf);
            return NO;
        }
        if (VTPixelTransferSessionTransferImage(_xferIn, cur, workCurBuf) != noErr)
        {
            CVPixelBufferRelease(workPrevBuf);
            CVPixelBufferRelease(workCurBuf);
            return NO;
        }

        feat0 = [MLFeatureValue featureValueWithPixelBuffer:workPrevBuf];
        feat1 = [MLFeatureValue featureValueWithPixelBuffer:workCurBuf];
    }
    else
    {
        if (reusePrev && _cachedWorkCurArray)
        {
            feat0 = [MLFeatureValue featureValueWithMultiArray:_cachedWorkCurArray];
            curTargetArray = (_cachedWorkCurArray == _input1Array) ? _input0Array : _input1Array;
        }
        else
        {
            workPrevBuf = PoolTake(_bgraPool);
            if (!workPrevBuf)
                return NO;
            if (VTPixelTransferSessionTransferImage(_xferIn, prev, workPrevBuf) != noErr
             || ![self convertBGRAToMultiArray:workPrevBuf dstMultiArray:_input0Array])
            {
                CVPixelBufferRelease(workPrevBuf);
                return NO;
            }
            CVPixelBufferRelease(workPrevBuf);
            workPrevBuf = NULL;
            feat0 = [MLFeatureValue featureValueWithMultiArray:_input0Array];
            curTargetArray = _input1Array;
        }

        workCurBuf = PoolTake(_bgraPool);
        if (!workCurBuf)
            return NO;
        if (VTPixelTransferSessionTransferImage(_xferIn, cur, workCurBuf) != noErr
         || ![self convertBGRAToMultiArray:workCurBuf dstMultiArray:curTargetArray])
        {
            CVPixelBufferRelease(workCurBuf);
            return NO;
        }
        CVPixelBufferRelease(workCurBuf);
        workCurBuf = NULL;
        feat1 = [MLFeatureValue featureValueWithMultiArray:curTargetArray];
        _cachedWorkCurArray = curTargetArray;
    }

    /* Reuse single dictionary provider per inference call. */
    _featureDict[_input0Name] = feat0;
    _featureDict[_input1Name] = feat1;

    bool ok = true;
    for (unsigned i = 0; i < count && ok; i++)
    {
        if (_timestepName && _timestepValues.count > i)
            _featureDict[_timestepName] = _timestepValues[i];

        NSError *featErr = nil;
        MLDictionaryFeatureProvider *inProvider =
            [[MLDictionaryFeatureProvider alloc] initWithDictionary:_featureDict error:&featErr];
        if (!inProvider)
        {
            msg_Warn(_log, "failed to create feature provider for phase %u/%u: %s",
                     i + 1, _factor, featErr.localizedDescription.UTF8String ?: "unknown error");
            ok = false;
            break;
        }

        NSError *predErr = nil;
        id<MLFeatureProvider> outProvider = [_model predictionFromFeatures:inProvider error:&predErr];
        if (!outProvider)
        {
            msg_Warn(_log, "RIFE prediction failed for phase %u/%u: %s",
                     i + 1, _factor, predErr.localizedDescription.UTF8String ?: "unknown error");
            ok = false;
            break;
        }

        MLFeatureValue *outVal = [outProvider featureValueForName:_outputName];
        if (!outVal)
        {
            msg_Warn(_log, "missing output feature '%s' from prediction", _outputName.UTF8String);
            ok = false;
            break;
        }

        CVPixelBufferRef dst = NULL;
        if (CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, _outPool, &dst) != kCVReturnSuccess)
        {
            msg_Warn(_log, "failed to allocate destination buffer from out_pool");
            ok = false;
            break;
        }

        if (_outputIsImage)
        {
            CVPixelBufferRef outImage = [outVal imageBufferValue];
            if (!outImage || VTPixelTransferSessionTransferImage(_xferOut, outImage, dst) != noErr)
            {
                CVPixelBufferRelease(dst);
                ok = false;
                break;
            }
        }
        else
        {
            MLMultiArray *outMulti = [outVal multiArrayValue];
            CVPixelBufferRef intermediateBgra = PoolTake(_bgraPool);
            if (!intermediateBgra || !outMulti
             || ![self convertMultiArrayToBGRA:outMulti dstPixelBuffer:intermediateBgra]
             || VTPixelTransferSessionTransferImage(_xferOut, intermediateBgra, dst) != noErr)
            {
                if (intermediateBgra)
                    CVPixelBufferRelease(intermediateBgra);
                CVPixelBufferRelease(dst);
                ok = false;
                break;
            }
            CVPixelBufferRelease(intermediateBgra);
        }

        out[i] = dst;
    }

    if (ok)
    {
        /* Cache cur frame representation for the next pair. */
        MLMultiArray *cachedArray = _inputIsImage ? nil : curTargetArray;
        [self flush];
        _cachedCurSource = CVPixelBufferRetain(cur);
        if (_inputIsImage)
        {
            _cachedWorkCur = CVPixelBufferRetain(workCurBuf);
            CVPixelBufferRelease(workCurBuf);
            CVPixelBufferRelease(workPrevBuf);
        }
        else
        {
            _cachedWorkCurArray = cachedArray;
        }
    }
    else
    {
        /* Release partially generated output buffers and drop state. */
        for (unsigned i = 0; i < count; i++)
        {
            if (out[i] != NULL)
            {
                CVPixelBufferRelease(out[i]);
                out[i] = NULL;
            }
        }
        if (workPrevBuf)
            CVPixelBufferRelease(workPrevBuf);
        if (workCurBuf)
            CVPixelBufferRelease(workCurBuf);
        [self flush];
    }

    return ok;
}

- (void)flush
{
    if (_cachedCurSource)
    {
        CVPixelBufferRelease(_cachedCurSource);
        _cachedCurSource = NULL;
    }
    if (_cachedWorkCur)
    {
        CVPixelBufferRelease(_cachedWorkCur);
        _cachedWorkCur = NULL;
    }
    _cachedWorkCurArray = nil;
    /* The feature dictionary holds the last pair's pictures; a seek means they
     * are no longer worth keeping alive. */
    [_featureDict removeAllObjects];
}

- (void)stop
{
    [self flush];

    if (_xferIn)
    {
        VTPixelTransferSessionInvalidate(_xferIn);
        CFRelease(_xferIn);
        _xferIn = NULL;
    }
    if (_xferOut)
    {
        VTPixelTransferSessionInvalidate(_xferOut);
        CFRelease(_xferOut);
        _xferOut = NULL;
    }
    if (_bgraPool)
    {
        CVPixelBufferPoolRelease(_bgraPool);
        _bgraPool = NULL;
    }

    if (_b8) { free(_b8); _b8 = NULL; }
    if (_g8) { free(_g8); _g8 = NULL; }
    if (_r8) { free(_r8); _r8 = NULL; }
    if (_a8) { free(_a8); _a8 = NULL; }
    if (_rScratchF) { free(_rScratchF); _rScratchF = NULL; }
    if (_gScratchF) { free(_gScratchF); _gScratchF = NULL; }
    if (_bScratchF) { free(_bScratchF); _bScratchF = NULL; }
}

- (void)dealloc
{
    [self stop];
}

@end

/*****************************************************************************
 * C Contract Implementation
 *****************************************************************************/

static bool RifeRun(struct maclc_frc_backend *b, CVPixelBufferRef prev,
                    CVPixelBufferRef cur, CVPixelBufferRef *out)
{
    struct maclc_frc_rife_backend *sys = (struct maclc_frc_rife_backend *)b;
    return [sys->ctx runWithPrev:prev cur:cur out:out];
}

static void RifeFlush(struct maclc_frc_backend *b)
{
    struct maclc_frc_rife_backend *sys = (struct maclc_frc_rife_backend *)b;
    [sys->ctx flush];
}

static void RifeStop(struct maclc_frc_backend *b)
{
    struct maclc_frc_rife_backend *sys = (struct maclc_frc_rife_backend *)b;
    [sys->ctx stop];
    sys->ctx = nil;
    free(sys);
}

static const struct maclc_frc_backend_ops rife_ops = {
    .run   = RifeRun,
    .flush = RifeFlush,
    .stop  = RifeStop,
};

struct maclc_frc_backend *
maclc_frc_rife_start(const struct maclc_frc_backend_setup *setup)
{
    if (!setup || !setup->log || setup->factor < 2 || !setup->out_pool)
        return NULL;

    @autoreleasepool {
        MacLCFrcRifeContext *ctx = [[MacLCFrcRifeContext alloc] init];
        if (![ctx setupWithBackendSetup:setup])
            return NULL;

        struct maclc_frc_rife_backend *backend = calloc(1, sizeof(*backend));
        if (!backend)
        {
            [ctx stop];
            return NULL;
        }

        backend->backend.ops = &rife_ops;
        backend->ctx = ctx;
        return &backend->backend;
    }
}
