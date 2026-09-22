// SPDX-License-Identifier: LGPL-2.1-or-later
/*****************************************************************************
 * maclc_frc.m: real-time motion interpolation for Apple Silicon
 *****************************************************************************
 * Copyright © 2026 Hazen Studio
 *
 * Raises the frame rate of the video to the refresh rate of the display by
 * synthesising intermediate frames. Six engines are available. Four are built
 * into the player, from the slowest and best looking to the cheapest:
 *
 *   quality / balanced  VTFrameRateConversion, Apple's optical-flow frame
 *                       interpolator. Works on 64-bit half-float RGBA, so the
 *                       pictures are converted in and out with a
 *                       VTPixelTransferSession.
 *   lowlatency          VTLowLatencyFrameInterpolation. Native 4:2:0 8-bit,
 *                       a tenth of the cost, but the processor refuses
 *                       anything above 1280x720.
 *   motion              Block motion estimation on the video encoder hardware
 *                       (VTMotionEstimationSession) followed by a bidirectional
 *                       motion-compensated warp in a Metal kernel. The only
 *                       engine fast enough for 4K or for 60 fps sources.
 *   blend               The same Metal kernel with the motion field forced to
 *                       zero: a plain cross-fade. Last resort.
 *
 * Two more reach outside the player and live in their own files, behind
 * maclc_frc_backend.h. Neither is ever picked automatically: the user asks for
 * them, and starting one fails plainly when what it needs is not installed.
 *
 *   svp                 The SmoothVideo Project graph, hosted by VapourSynth
 *                       (maclc_frc_vs.m). Uses the libraries SVP 4 Mac
 *                       installed, with its motion vectors or, when the RIFE
 *                       option is on, with the neural network SVP ships.
 *   rife                The RIFE neural network on Core ML (maclc_frc_rife.m),
 *                       with no other software to install.
 *
 * Every engine is timed; when a pass no longer fits in the time one source
 * frame lasts, the filter falls back to a cheaper engine and finally stops
 * interpolating altogether (see the "overrun" option).
 *****************************************************************************/

#ifdef HAVE_CONFIG_H
# include "config.h"
#endif

#include <vlc_common.h>
#include <vlc_plugin.h>
#include <vlc_filter.h>
#include <vlc_picture.h>
#include <vlc_configuration.h>

#include <math.h>

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <CoreVideo/CoreVideo.h>
#import <Metal/Metal.h>
#import <simd/simd.h>
#import <VideoToolbox/VideoToolbox.h>

#include "vt_utils.h"
#include "maclc_frc_geometry.h"
#include "maclc_frc_backend.h"

#define CFG_PREFIX "maclc-frc-"

enum maclc_frc_engine
{
    ENGINE_AUTO = 0,
    ENGINE_QUALITY,
    ENGINE_BALANCED,
    ENGINE_LOWLATENCY,
    ENGINE_MOTION,
    ENGINE_BLEND,
    ENGINE_SVP,
    ENGINE_RIFE,
};

enum maclc_frc_target
{
    TARGET_AUTO = 0,
    TARGET_60,
    TARGET_120,
    TARGET_DOUBLE,
};

enum maclc_frc_overrun
{
    OVERRUN_DEGRADE = 0,
    OVERRUN_STOP,
    OVERRUN_IGNORE,
};

static int  Open(filter_t *);
static void Close(filter_t *);

static const int engine_values[] = {
    ENGINE_AUTO, ENGINE_QUALITY, ENGINE_BALANCED,
    ENGINE_LOWLATENCY, ENGINE_MOTION, ENGINE_BLEND,
    ENGINE_SVP, ENGINE_RIFE,
};
static const char *const engine_names[] = {
    N_("Automatic"), N_("Quality (optical flow)"), N_("Balanced (optical flow)"),
    N_("Low latency (up to 720p)"), N_("Motion compensation"), N_("Blend"),
    N_("SmoothVideo Project"), N_("RIFE neural network"),
};

static const int target_values[] = {
    TARGET_AUTO, TARGET_60, TARGET_120, TARGET_DOUBLE,
};
static const char *const target_names[] = {
    N_("Match the display"), N_("60 fps"), N_("120 fps"), N_("Twice the source"),
};

static const int overrun_values[] = {
    OVERRUN_DEGRADE, OVERRUN_STOP, OVERRUN_IGNORE,
};
static const char *const overrun_names[] = {
    N_("Fall back to a cheaper engine"), N_("Stop interpolating"), N_("Keep going"),
};

#define ENGINE_TEXT N_("Interpolation engine")
#define ENGINE_LONGTEXT N_("Which method synthesises the intermediate frames. " \
    "Automatic picks the best one that fits in the time one source frame " \
    "lasts. Quality costs about twice what Balanced does and was not measured " \
    "to look any better.")
#define TARGET_TEXT N_("Target frame rate")
#define TARGET_LONGTEXT N_("Frame rate to aim for. Matching the display picks " \
    "the largest whole multiple of the source that the screen can show.")
#define OVERRUN_TEXT N_("When too slow")
#define OVERRUN_LONGTEXT N_("What to do when a pass no longer fits in the time " \
    "one source frame lasts.")
#define SVPPATH_TEXT N_("SmoothVideo Project folder")
#define SVPPATH_LONGTEXT N_("Where SVP 4 Mac is installed. Left empty, the " \
    "Applications folder is used. MacLC loads the libraries SVP installed on " \
    "this Mac; it does not carry them.")
#define RIFE_TEXT N_("Use the RIFE neural network")
#define RIFE_LONGTEXT N_("Make the in-between frames with the RIFE network " \
    "rather than with motion vectors. The SmoothVideo Project engine then " \
    "uses the copy of RIFE that SVP installed. The RIFE engine always uses " \
    "the network, whatever this says.")
#define RIFEMODEL_TEXT N_("RIFE model")
#define RIFEMODEL_LONGTEXT N_("The folder or the Core ML package that holds " \
    "the network. Left empty, MacLC looks in its own Resources folder and " \
    "then in Application Support.")
static const int rife_compute_values[] = {
    MACLC_FRC_RIFE_COMPUTE_MEASURE, MACLC_FRC_RIFE_COMPUTE_NEURAL,
    MACLC_FRC_RIFE_COMPUTE_GPU, MACLC_FRC_RIFE_COMPUTE_CPU,
};
static const char *const rife_compute_names[] = {
    N_("Whichever is faster here"), N_("Neural Engine"), N_("Graphics processor"),
    N_("Processor"),
};

#define RIFECOMPUTE_TEXT N_("Run RIFE on")
#define RIFECOMPUTE_LONGTEXT N_("Which part of the chip runs the network. " \
    "The Neural Engine is not always the fastest: a network it cannot run " \
    "whole is cut into pieces that travel back and forth to the graphics " \
    "processor. Left to itself, MacLC times both on this Mac and keeps the " \
    "faster one.")
#define RIFESCALE_TEXT N_("RIFE detail level")
#define RIFESCALE_LONGTEXT N_("The size the motion is worked out at, as a " \
    "fraction of the picture. Half costs about a third as much, which is what " \
    "lets 4K keep up.")
#define MAXFACTOR_TEXT N_("Maximum multiplier")
#define MAXFACTOR_LONGTEXT N_("Never produce more than this many output frames " \
    "per source frame.")

vlc_module_begin()
    set_shortname(N_("Frame interpolation"))
    set_description(N_("Motion interpolation for Apple Silicon"))
    set_subcategory(SUBCAT_VIDEO_VFILTER)
    add_shortcut("maclc_frc")
    set_callback_video_filter(Open)

    add_integer(CFG_PREFIX "engine", ENGINE_AUTO, ENGINE_TEXT, ENGINE_LONGTEXT)
        change_integer_list(engine_values, engine_names)
    add_integer(CFG_PREFIX "target", TARGET_AUTO, TARGET_TEXT, TARGET_LONGTEXT)
        change_integer_list(target_values, target_names)
    add_integer(CFG_PREFIX "overrun", OVERRUN_DEGRADE, OVERRUN_TEXT, OVERRUN_LONGTEXT)
        change_integer_list(overrun_values, overrun_names)
    add_integer_with_range(CFG_PREFIX "max-factor", 5, 2, 8,
                           MAXFACTOR_TEXT, MAXFACTOR_LONGTEXT)
    add_bool(CFG_PREFIX "rife", false, RIFE_TEXT, RIFE_LONGTEXT)
    add_string(CFG_PREFIX "rife-model", NULL, RIFEMODEL_TEXT, RIFEMODEL_LONGTEXT)
    add_float_with_range(CFG_PREFIX "rife-scale", 1.f, 0.25f, 1.f,
                         RIFESCALE_TEXT, RIFESCALE_LONGTEXT)
    add_integer(CFG_PREFIX "rife-compute", MACLC_FRC_RIFE_COMPUTE_MEASURE,
                RIFECOMPUTE_TEXT, RIFECOMPUTE_LONGTEXT)
        change_integer_list(rife_compute_values, rife_compute_names)
    add_string(CFG_PREFIX "svp-path", NULL, SVPPATH_TEXT, SVPPATH_LONGTEXT)
vlc_module_end()

/* The interpolated planes are written by this kernel. The motion field holds
 * the displacement from the current frame to the previous one, in luma pixels;
 * normalised coordinates make it valid for the chroma plane as well. */
static NSString *const kernel_source = @"\n\
#include <metal_stdlib>\n\
using namespace metal;\n\
struct Params {\n\
    float2 mv_norm;\n\
    float  phase;\n\
    float  motion;\n\
    float  occ_lo;\n\
    float  occ_hi;\n\
};\n\
kernel void maclc_frc_interp(texture2d<float, access::sample> prev_plane [[texture(0)]],\n\
                             texture2d<float, access::sample> cur_plane  [[texture(1)]],\n\
                             texture2d<float, access::sample> prev_luma  [[texture(2)]],\n\
                             texture2d<float, access::sample> cur_luma   [[texture(3)]],\n\
                             texture2d<float, access::sample> motion     [[texture(4)]],\n\
                             texture2d<float, access::write>  out_plane  [[texture(5)]],\n\
                             constant Params &p [[buffer(0)]],\n\
                             uint2 gid [[thread_position_in_grid]])\n\
{\n\
    const uint w = out_plane.get_width(), h = out_plane.get_height();\n\
    if (gid.x >= w || gid.y >= h)\n\
        return;\n\
    constexpr sampler smp(coord::normalized, address::clamp_to_edge, filter::linear);\n\
    const float2 uv = (float2(gid) + 0.5) / float2(w, h);\n\
    const float t = p.phase;\n\
    /* The field is indexed by blocks of the current frame and points at the\n\
       previous one. Estimating the other direction as well was measured to\n\
       change nothing and cost 1.5 ms a frame, so one field it is. */\n\
    const float2 mv = p.motion > 0.5 ? motion.sample(smp, uv).xy * p.mv_norm : float2(0.0);\n\
    const float2 uv_cur  = uv - (1.0 - t) * mv;\n\
    const float2 uv_prev = uv + t * mv;\n\
    const float4 c = cur_plane.sample(smp, uv_cur);\n\
    const float4 v = prev_plane.sample(smp, uv_prev);\n\
    const float yc = cur_luma.sample(smp, uv_cur).r;\n\
    const float yv = prev_luma.sample(smp, uv_prev).r;\n\
    /* Where the two motion-compensated samples disagree the block vector is\n\
       wrong or the area is occluded: show the nearer frame instead of a ghost.\n\
       Without motion the two samples are simply the two frames, and every\n\
       moving pixel would look occluded, so a cross-fade must stay a cross-fade. */\n\
    const float occluded = p.motion * smoothstep(p.occ_lo, p.occ_hi, abs(yc - yv));\n\
    const float weight = mix(t, t < 0.5 ? 0.0 : 1.0, occluded);\n\
    out_plane.write(mix(v, c, weight), gid);\n\
}\n";

struct maclc_frc_params
{
    simd_float2 mv_norm;
    float phase;
    float motion;
    float occ_lo;
    float occ_hi;
};

@interface MacLCFrcContext : NSObject
@end

@implementation MacLCFrcContext
{
@public
    filter_t *_filter;

    int _engine;            /* engine in use right now */
    int _engine_starting;   /* the one being set up, for the probe */
    int _requested;         /* what the user asked for */
    int _overrun;
    unsigned _factor;       /* output frames per source frame, >= 2 */
    bool _passthrough;

    picture_t *_prev;
    CVPixelBufferRef _prev_buffer;
    bool _restart;          /* first pair of a new sequence */

    unsigned _width, _height;
    OSType _cv_fmt;         /* CoreVideo format the engines work on */
    bool _ten_bit;
    bool _software;         /* pictures arrive as planes, not CoreVideo buffers */
    bool _planar;           /* ... and in three planes rather than two */

    CVPixelBufferPoolRef _out_pool;

    /* VTFrameProcessor engines */
    VTFrameProcessor *_processor;
    id<VTFrameProcessorConfiguration> _processor_cfg;
    OSType _processor_fmt;
    CVPixelBufferPoolRef _source_pool, _destination_pool;
    CVPixelBufferRef _work_prev;
    NSArray<NSNumber *> *_phases;
    VTPixelTransferSessionRef _xfer_in, _xfer_out;

    /* Metal engines */
    id<MTLDevice> _device;
    id<MTLCommandQueue> _queue;
    id<MTLComputePipelineState> _pipeline;
    CVMetalTextureCacheRef _tex_cache;
    id<MTLTexture> _mv_texture;
    VTMotionEstimationSessionRef _estimator;
    CVPixelBufferPoolRef _luma_pool;   /* 8-bit copies when the source is 10-bit */
    CVPixelBufferRef _estimate_prev;
    VTPixelTransferSessionRef _xfer_luma;
    unsigned _mv_cols, _mv_rows;
    float *_mv_field;                  /* smoothed, 2 floats per block */
    float *_mv_scratch;

    /* engines that live in their own files */
    struct maclc_frc_backend *_backend;
    char *_svp_path;
    char *_rife_model;
    bool _rife;
    float _rife_scale;
    int _rife_compute;

    /* real-time budget */
    vlc_tick_t _budget;
    vlc_tick_t _spent;                 /* exponential moving average */
    unsigned _late_passes;

    /* what the last couple of seconds looked like, for -vv */
    vlc_tick_t _report_at;
    unsigned _report_passes;
    unsigned _report_frames;
}
@end

/*****************************************************************************
 * Small helpers
 *****************************************************************************/

/* The frame processors state the attributes their buffers must have —
 * padding included. A buffer allocated to VLC's own taste can differ, and
 * handing one over corrupts the heap at sizes whose rows do not line up, so
 * every buffer a processor touches comes from here. */
static CVPixelBufferPoolRef PoolFromAttributes(NSDictionary *attributes,
                                               unsigned count)
{
    NSMutableDictionary *buffer_attrs = [attributes mutableCopy];
    if (buffer_attrs == nil)
        return NULL;
    buffer_attrs[(__bridge NSString *)kCVPixelBufferIOSurfacePropertiesKey] = @{};

    NSDictionary *pool_attrs = @{
        (__bridge NSString *)kCVPixelBufferPoolMinimumBufferCountKey: @(count),
    };
    CVPixelBufferPoolRef pool = NULL;
    if (CVPixelBufferPoolCreate(kCFAllocatorDefault,
                                (__bridge CFDictionaryRef)pool_attrs,
                                (__bridge CFDictionaryRef)buffer_attrs,
                                &pool) != kCVReturnSuccess)
        return NULL;
    return pool;
}

static CVPixelBufferRef PoolTake(CVPixelBufferPoolRef pool)
{
    CVPixelBufferRef buffer = NULL;
    if (pool == NULL
     || CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool,
                                           &buffer) != kCVReturnSuccess)
        return NULL;
    return buffer;
}

static bool ChromaIsSupported(vlc_fourcc_t chroma, OSType *cv_fmt, bool *ten_bit,
                              bool *software)
{
    *ten_bit = false;
    *software = false;
    switch (chroma)
    {
        case VLC_CODEC_CVPX_NV12:
            *cv_fmt = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange;
            return true;
        case VLC_CODEC_CVPX_P010:
            *cv_fmt = kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange;
            *ten_bit = true;
            return true;
        case VLC_CODEC_I420:
        case VLC_CODEC_NV12:
            *cv_fmt = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange;
            *software = true;
            return true;
        default:
            return false;
    }
}

/*****************************************************************************
 * Engine setup
 *****************************************************************************/

static void EngineRelease(MacLCFrcContext *ctx)
{
    if (ctx->_backend != NULL)
    {
        ctx->_backend->ops->stop(ctx->_backend);
        ctx->_backend = NULL;
    }
    if (ctx->_processor != nil)
    {
        [ctx->_processor endSession];
        ctx->_processor = nil;
    }
    ctx->_processor_cfg = nil;
    if (ctx->_work_prev != NULL)
    {
        CVPixelBufferRelease(ctx->_work_prev);
        ctx->_work_prev = NULL;
    }
    if (ctx->_source_pool != NULL)
    {
        CVPixelBufferPoolRelease(ctx->_source_pool);
        ctx->_source_pool = NULL;
    }
    if (ctx->_destination_pool != NULL)
    {
        CVPixelBufferPoolRelease(ctx->_destination_pool);
        ctx->_destination_pool = NULL;
    }
    if (ctx->_xfer_in != NULL)
    {
        VTPixelTransferSessionInvalidate(ctx->_xfer_in);
        CFRelease(ctx->_xfer_in);
        ctx->_xfer_in = NULL;
    }
    if (ctx->_xfer_out != NULL)
    {
        VTPixelTransferSessionInvalidate(ctx->_xfer_out);
        CFRelease(ctx->_xfer_out);
        ctx->_xfer_out = NULL;
    }
    if (ctx->_estimator != NULL)
    {
        VTMotionEstimationSessionInvalidate(ctx->_estimator);
        CFRelease(ctx->_estimator);
        ctx->_estimator = NULL;
    }
    if (ctx->_estimate_prev != NULL)
    {
        CVPixelBufferRelease(ctx->_estimate_prev);
        ctx->_estimate_prev = NULL;
    }
    if (ctx->_luma_pool != NULL)
    {
        CVPixelBufferPoolRelease(ctx->_luma_pool);
        ctx->_luma_pool = NULL;
    }
    if (ctx->_xfer_luma != NULL)
    {
        VTPixelTransferSessionInvalidate(ctx->_xfer_luma);
        CFRelease(ctx->_xfer_luma);
        ctx->_xfer_luma = NULL;
    }
    free(ctx->_mv_field);
    ctx->_mv_field = NULL;
    free(ctx->_mv_scratch);
    ctx->_mv_scratch = NULL;
    ctx->_mv_texture = nil;
    ctx->_pipeline = nil;
    ctx->_queue = nil;
    ctx->_device = nil;
    if (ctx->_tex_cache != NULL)
    {
        CVMetalTextureCacheFlush(ctx->_tex_cache, 0);
        CFRelease(ctx->_tex_cache);
        ctx->_tex_cache = NULL;
    }
}

static const char *EngineName(int engine)
{
    switch (engine)
    {
        case ENGINE_QUALITY:    return "quality";
        case ENGINE_BALANCED:   return "balanced";
        case ENGINE_LOWLATENCY: return "low latency";
        case ENGINE_MOTION:     return "motion compensation";
        case ENGINE_BLEND:      return "blend";
        case ENGINE_SVP:        return "SmoothVideo Project";
        case ENGINE_RIFE:       return "RIFE";
        default:                return "none";
    }
}

/* startSession accepts sizes the processor then refuses to work on — the
 * low-latency one says nothing until the first frame comes back with
 * "Processor is not initialized". Push one pair of blank frames through
 * before claiming the engine works. */
static bool ProcessorEngineProbe(MacLCFrcContext *ctx)
{
    if (@available(macOS 15.4, *))
    {
        CVPixelBufferRef a = PoolTake(ctx->_source_pool);
        CVPixelBufferRef b = PoolTake(ctx->_source_pool);
        NSMutableArray<VTFrameProcessorFrame *> *destinations =
            [NSMutableArray arrayWithCapacity:ctx->_factor - 1];
        bool ok = a != NULL && b != NULL;

        for (unsigned i = 0; i < ctx->_factor - 1 && ok; i++)
        {
            CVPixelBufferRef d = PoolTake(ctx->_destination_pool);
            VTFrameProcessorFrame *frame = d == NULL ? nil
                : [[VTFrameProcessorFrame alloc] initWithBuffer:d
                    presentationTimeStamp:CMTimeMake(i + 1, 60)];
            if (d != NULL)
                CVPixelBufferRelease(d);
            if (frame == nil)
                ok = false;
            else
                [destinations addObject:frame];
        }

        VTFrameProcessorFrame *first = ok
            ? [[VTFrameProcessorFrame alloc] initWithBuffer:a
                presentationTimeStamp:CMTimeMake(0, 60)] : nil;
        VTFrameProcessorFrame *second = ok
            ? [[VTFrameProcessorFrame alloc] initWithBuffer:b
                presentationTimeStamp:CMTimeMake(ctx->_factor, 60)] : nil;
        id<VTFrameProcessorParameters> parameters = nil;

        if (first != nil && second != nil)
        {
            if (ctx->_engine_starting == ENGINE_LOWLATENCY)
            {
                if (@available(macOS 26.0, *))
                    parameters = [[VTLowLatencyFrameInterpolationParameters alloc]
                        initWithSourceFrame:second previousFrame:first
                        interpolationPhase:ctx->_phases destinationFrames:destinations];
            }
            else
                parameters = [[VTFrameRateConversionParameters alloc]
                    initWithSourceFrame:first nextFrame:second opticalFlow:nil
                    interpolationPhase:ctx->_phases
                    submissionMode:VTFrameRateConversionParametersSubmissionModeRandom
                    destinationFrames:destinations];
        }

        NSError *error = nil;
        ok = parameters != nil
          && [ctx->_processor processWithParameters:parameters error:&error];
        if (!ok)
            msg_Dbg(ctx->_filter, "%s engine refuses %ux%u x%u: %s",
                    EngineName(ctx->_engine_starting), ctx->_width, ctx->_height,
                    ctx->_factor, error.localizedDescription.UTF8String ?: "no reason given");

        if (a != NULL)
            CVPixelBufferRelease(a);
        if (b != NULL)
            CVPixelBufferRelease(b);
        return ok;
    }
    return false;
}

static bool ProcessorEngineStart(MacLCFrcContext *ctx, int engine)
{
    filter_t *filter = ctx->_filter;
    ctx->_engine_starting = engine;

    if (engine == ENGINE_LOWLATENCY)
    {
        if (@available(macOS 26.0, *))
        {
            if (!VTLowLatencyFrameInterpolationConfiguration.isSupported)
                return false;
            ctx->_processor_cfg = [[VTLowLatencyFrameInterpolationConfiguration alloc]
                initWithFrameWidth:ctx->_width frameHeight:ctx->_height
                numberOfInterpolatedFrames:ctx->_factor - 1];
        }
        else
            return false;
    }
    else
    {
        if (@available(macOS 15.4, *))
        {
            if (!VTFrameRateConversionConfiguration.isSupported)
                return false;
            VTFrameRateConversionConfigurationQualityPrioritization quality =
                engine == ENGINE_QUALITY
                    ? VTFrameRateConversionConfigurationQualityPrioritizationQuality
                    : VTFrameRateConversionConfigurationQualityPrioritizationNormal;
            ctx->_processor_cfg = [[VTFrameRateConversionConfiguration alloc]
                initWithFrameWidth:ctx->_width frameHeight:ctx->_height
                usePrecomputedFlow:NO qualityPrioritization:quality
                revision:VTFrameRateConversionConfigurationRevision1];
        }
        else
            return false;
    }

    if (ctx->_processor_cfg == nil)
        return false;

    NSNumber *wanted = ctx->_processor_cfg.frameSupportedPixelFormats.firstObject;
    if (wanted == nil)
        return false;
    ctx->_processor_fmt = (OSType)wanted.unsignedIntValue;

    if (@available(macOS 15.4, *))
    {
        ctx->_processor = [[VTFrameProcessor alloc] init];
        NSError *error = nil;
        if (![ctx->_processor startSessionWithConfiguration:ctx->_processor_cfg
                                                      error:&error])
        {
            msg_Dbg(filter, "frame processor refused %ux%u: %s",
                    ctx->_width, ctx->_height,
                    error.localizedDescription.UTF8String ?: "unknown error");
            ctx->_processor = nil;
            return false;
        }
    }
    else
        return false;

    ctx->_source_pool =
        PoolFromAttributes(ctx->_processor_cfg.sourcePixelBufferAttributes, 3);
    ctx->_destination_pool =
        PoolFromAttributes(ctx->_processor_cfg.destinationPixelBufferAttributes,
                           ctx->_factor + 2);
    if (ctx->_source_pool == NULL || ctx->_destination_pool == NULL)
        return false;
    if (VTPixelTransferSessionCreate(kCFAllocatorDefault, &ctx->_xfer_in)
     || VTPixelTransferSessionCreate(kCFAllocatorDefault, &ctx->_xfer_out))
        return false;
    VTSessionSetProperty(ctx->_xfer_in,
                         kVTPixelTransferPropertyKey_RealTime, kCFBooleanTrue);
    VTSessionSetProperty(ctx->_xfer_out,
                         kVTPixelTransferPropertyKey_RealTime, kCFBooleanTrue);

    NSMutableArray *phases = [NSMutableArray arrayWithCapacity:ctx->_factor - 1];
    for (unsigned i = 1; i < ctx->_factor; i++)
        [phases addObject:@((float)i / (float)ctx->_factor)];
    ctx->_phases = phases;

    return ProcessorEngineProbe(ctx);
}

static bool MetalEngineStart(MacLCFrcContext *ctx, int engine)
{
    filter_t *filter = ctx->_filter;

    ctx->_device = MTLCreateSystemDefaultDevice();
    if (ctx->_device == nil)
        return false;
    ctx->_queue = [ctx->_device newCommandQueue];
    if (ctx->_queue == nil)
        return false;

    NSError *error = nil;
    id<MTLLibrary> library = [ctx->_device newLibraryWithSource:kernel_source
                                                        options:nil error:&error];
    if (library == nil)
    {
        msg_Err(filter, "cannot build the interpolation kernel: %s",
                error.localizedDescription.UTF8String ?: "unknown error");
        return false;
    }
    id<MTLFunction> function = [library newFunctionWithName:@"maclc_frc_interp"];
    if (function == nil)
        return false;
    ctx->_pipeline = [ctx->_device newComputePipelineStateWithFunction:function
                                                                 error:&error];
    if (ctx->_pipeline == nil)
    {
        msg_Err(filter, "cannot compile the interpolation kernel: %s",
                error.localizedDescription.UTF8String ?: "unknown error");
        return false;
    }

    if (CVMetalTextureCacheCreate(kCFAllocatorDefault, NULL, ctx->_device, NULL,
                                  &ctx->_tex_cache) != kCVReturnSuccess)
        return false;

    if (engine == ENGINE_BLEND)
        return true;

    if (@available(macOS 26.0, *))
    {
        /* 16x16 blocks: the 4x4 search exists but costs twelve times as much
         * and is not offered above 1080p. */
        NSDictionary *options = @{
            (__bridge NSString *)kVTMotionEstimationSessionCreationOption_MotionVectorSize: @16,
            (__bridge NSString *)kVTMotionEstimationSessionCreationOption_UseMultiPassSearch: @NO,
        };
        if (VTMotionEstimationSessionCreate(kCFAllocatorDefault,
                                            (__bridge CFDictionaryRef)options,
                                            ctx->_width, ctx->_height,
                                            &ctx->_estimator) != noErr)
        {
            msg_Dbg(filter, "no motion estimator for %ux%u",
                    ctx->_width, ctx->_height);
            return false;
        }
    }
    else
        return false;

    ctx->_mv_cols = (ctx->_width + 15) / 16;
    ctx->_mv_rows = (ctx->_height + 15) / 16;
    const size_t field_size = (size_t)ctx->_mv_cols * ctx->_mv_rows * 2;
    ctx->_mv_field = calloc(field_size, sizeof(*ctx->_mv_field));
    ctx->_mv_scratch = calloc(field_size, sizeof(*ctx->_mv_scratch));
    if (ctx->_mv_field == NULL || ctx->_mv_scratch == NULL)
        return false;

    MTLTextureDescriptor *descriptor = [MTLTextureDescriptor
        texture2DDescriptorWithPixelFormat:MTLPixelFormatRG32Float
                                     width:ctx->_mv_cols height:ctx->_mv_rows
                                 mipmapped:NO];
    descriptor.usage = MTLTextureUsageShaderRead;
    descriptor.storageMode = MTLStorageModeShared;
    ctx->_mv_texture = [ctx->_device newTextureWithDescriptor:descriptor];
    if (ctx->_mv_texture == nil)
        return false;

    /* The estimator takes 8-bit 4:2:0 and states the padding it wants; feed it
     * buffers of its own rather than the decoder's, whatever the bit depth. */
    CFDictionaryRef estimator_attrs = NULL;
    if (VTMotionEstimationSessionCopySourcePixelBufferAttributes(
            ctx->_estimator, &estimator_attrs) != noErr || estimator_attrs == NULL)
        return false;
    ctx->_luma_pool =
        PoolFromAttributes((__bridge NSDictionary *)estimator_attrs, 3);
    CFRelease(estimator_attrs);
    if (ctx->_luma_pool == NULL
     || VTPixelTransferSessionCreate(kCFAllocatorDefault, &ctx->_xfer_luma))
        return false;
    VTSessionSetProperty(ctx->_xfer_luma,
                         kVTPixelTransferPropertyKey_RealTime, kCFBooleanTrue);
    return true;
}

/* The SmoothVideo Project and RIFE engines are built elsewhere; all this does
 * is fill in what they are told about the stream. */
static bool BackendEngineStart(MacLCFrcContext *ctx, int engine)
{
    const struct maclc_frc_backend_setup setup = {
        .log            = VLC_OBJECT(ctx->_filter),
        .width          = ctx->_width,
        .height         = ctx->_height,
        .cv_fmt         = ctx->_cv_fmt,
        .ten_bit        = ctx->_ten_bit,
        .factor         = ctx->_factor,
        .budget         = ctx->_budget,
        .out_pool       = ctx->_out_pool,
        .svp_path       = ctx->_svp_path,
        /* The RIFE engine is the network by definition; for the SVP graph it
         * is the choice between the neural mode and the motion vectors. */
        .rife           = engine == ENGINE_RIFE ? true : ctx->_rife,
        .rife_model     = ctx->_rife_model,
        .rife_scale     = ctx->_rife_scale,
        /* More than one inference at a time only makes the Metal queues fight
         * over the same memory on Apple silicon. */
        .rife_threads   = 1,
        .rife_compute   = ctx->_rife_compute,
        .rife_scene_cut = true,
    };

    ctx->_backend = engine == ENGINE_RIFE ? maclc_frc_rife_start(&setup)
                                          : maclc_frc_vs_start(&setup);
    return ctx->_backend != NULL;
}

static bool EngineStart(MacLCFrcContext *ctx, int engine)
{
    EngineRelease(ctx);
    ctx->_engine = ENGINE_AUTO;
    ctx->_restart = true;

    bool ok;
    switch (engine)
    {
        case ENGINE_QUALITY:
        case ENGINE_BALANCED:
        case ENGINE_LOWLATENCY:
            ok = ProcessorEngineStart(ctx, engine);
            break;
        case ENGINE_MOTION:
        case ENGINE_BLEND:
            ok = MetalEngineStart(ctx, engine);
            break;
        case ENGINE_SVP:
        case ENGINE_RIFE:
            ok = BackendEngineStart(ctx, engine);
            break;
        default:
            ok = false;
            break;
    }

    if (!ok)
    {
        EngineRelease(ctx);
        return false;
    }
    ctx->_engine = engine;
    msg_Dbg(ctx->_filter, "frame interpolation: %s engine, x%u, budget %" PRId64 " ms",
            EngineName(engine), ctx->_factor, MS_FROM_VLC_TICK(ctx->_budget));
    return true;
}

/* Engines from the best looking to the cheapest; degrading walks down it. */
static const int engine_ladder[] = {
    ENGINE_RIFE, ENGINE_SVP,
    ENGINE_QUALITY, ENGINE_BALANCED, ENGINE_LOWLATENCY, ENGINE_MOTION, ENGINE_BLEND,
};

static bool EngineDegrade(MacLCFrcContext *ctx)
{
    unsigned rank = 0;
    while (rank < ARRAY_SIZE(engine_ladder) && engine_ladder[rank] != ctx->_engine)
        rank++;

    for (unsigned i = rank + 1; i < ARRAY_SIZE(engine_ladder); i++)
    {
        /* Low latency is not a step down from the optical-flow engines: it is
         * limited to 720p, so it would have been chosen already. Neither of
         * the engines that reach outside the player is ever stepped into:
         * they are above everything else in the ladder anyway, and they need
         * software this Mac may not have. */
        if (engine_ladder[i] == ENGINE_LOWLATENCY
         || engine_ladder[i] == ENGINE_SVP
         || engine_ladder[i] == ENGINE_RIFE)
            continue;
        if (EngineStart(ctx, engine_ladder[i]))
        {
            msg_Warn(ctx->_filter, "frame interpolation too slow, falling back to "
                     "the %s engine", EngineName(ctx->_engine));
            ctx->_spent = 0;
            ctx->_late_passes = 0;
            return true;
        }
    }
    return false;
}

/*****************************************************************************
 * VTFrameProcessor engines
 *****************************************************************************/

static CVPixelBufferRef ProcessorConvertIn(MacLCFrcContext *ctx,
                                           CVPixelBufferRef source)
{
    CVPixelBufferRef converted = PoolTake(ctx->_source_pool);
    if (converted == NULL)
        return NULL;
    if (VTPixelTransferSessionTransferImage(ctx->_xfer_in, source, converted) != noErr)
    {
        CVPixelBufferRelease(converted);
        return NULL;
    }
    return converted;
}

/* Fills out[] with factor - 1 CoreVideo buffers in the source format. */
static bool ProcessorRun(MacLCFrcContext *ctx, CVPixelBufferRef current,
                         vlc_tick_t prev_date, vlc_tick_t current_date,
                         CVPixelBufferRef *out)
{
    const unsigned count = ctx->_factor - 1;
    if (ctx->_work_prev == NULL)
        return false;
    CVPixelBufferRef work_cur = ProcessorConvertIn(ctx, current);
    if (work_cur == NULL)
        return false;

    NSMutableArray<VTFrameProcessorFrame *> *destinations =
        [NSMutableArray arrayWithCapacity:count];
    CVPixelBufferRef staging[8] = { NULL };
    bool ok = true;

    for (unsigned i = 0; i < count && ok; i++)
    {
        staging[i] = PoolTake(ctx->_destination_pool);
        if (staging[i] == NULL)
        {
            ok = false;
            break;
        }
        const vlc_tick_t date = prev_date
            + (current_date - prev_date) * (int64_t)(i + 1) / (int64_t)ctx->_factor;
        VTFrameProcessorFrame *frame = [[VTFrameProcessorFrame alloc]
            initWithBuffer:staging[i]
            presentationTimeStamp:CMTimeMake(date, CLOCK_FREQ)];
        if (frame == nil)
            ok = false;
        else
            [destinations addObject:frame];
    }

    if (ok)
    {
        VTFrameProcessorFrame *previous = [[VTFrameProcessorFrame alloc]
            initWithBuffer:ctx->_work_prev
            presentationTimeStamp:CMTimeMake(prev_date, CLOCK_FREQ)];
        VTFrameProcessorFrame *now = [[VTFrameProcessorFrame alloc]
            initWithBuffer:work_cur
            presentationTimeStamp:CMTimeMake(current_date, CLOCK_FREQ)];
        id<VTFrameProcessorParameters> parameters = nil;

        if (previous == nil || now == nil)
            ok = false;
        else if (ctx->_engine == ENGINE_LOWLATENCY)
        {
            if (@available(macOS 26.0, *))
                parameters = [[VTLowLatencyFrameInterpolationParameters alloc]
                    initWithSourceFrame:now previousFrame:previous
                    interpolationPhase:ctx->_phases destinationFrames:destinations];
        }
        else if (@available(macOS 15.4, *))
        {
            /* Sequential tells the processor that this pair continues the
             * previous one, which lets it reuse the flow it already computed. */
            VTFrameRateConversionParametersSubmissionMode mode = ctx->_restart
                ? VTFrameRateConversionParametersSubmissionModeRandom
                : VTFrameRateConversionParametersSubmissionModeSequential;
            parameters = [[VTFrameRateConversionParameters alloc]
                initWithSourceFrame:previous nextFrame:now opticalFlow:nil
                interpolationPhase:ctx->_phases submissionMode:mode
                destinationFrames:destinations];
        }

        if (parameters == nil)
            ok = false;
        else if (@available(macOS 15.4, *))
        {
            NSError *error = nil;
            if (![ctx->_processor processWithParameters:parameters error:&error])
            {
                msg_Warn(ctx->_filter, "interpolation failed: %s",
                         error.localizedDescription.UTF8String ?: "unknown error");
                ok = false;
            }
        }
        else
            ok = false;
    }

    if (ok)
    {
        for (unsigned i = 0; i < count; i++)
        {
            out[i] = PoolTake(ctx->_out_pool);
            if (out[i] == NULL
             || VTPixelTransferSessionTransferImage(ctx->_xfer_out, staging[i],
                                                    out[i]) != noErr)
            {
                ok = false;
                break;
            }
        }
    }

    for (unsigned i = 0; i < count; i++)
        if (staging[i] != NULL)
            CVPixelBufferRelease(staging[i]);

    if (ok)
    {
        if (ctx->_work_prev != NULL)
            CVPixelBufferRelease(ctx->_work_prev);
        ctx->_work_prev = work_cur;
    }
    else
    {
        CVPixelBufferRelease(work_cur);
        for (unsigned i = 0; i < count; i++)
        {
            if (out[i] != NULL)
            {
                CVPixelBufferRelease(out[i]);
                out[i] = NULL;
            }
        }
    }
    return ok;
}

/*****************************************************************************
 * Metal engines
 *****************************************************************************/

/* CVMetalTextureGetTexture hands back a texture the CVMetalTexture owns, so the
 * wrapper has to outlive the work that reads it; callers collect the wrappers
 * and drop them once the command buffer is done. */
static id<MTLTexture> TextureForPlane(MacLCFrcContext *ctx, CVPixelBufferRef buffer,
                                      size_t plane, bool writable,
                                      NSMutableArray *holders)
{
    const size_t width = CVPixelBufferGetWidthOfPlane(buffer, plane);
    const size_t height = CVPixelBufferGetHeightOfPlane(buffer, plane);
    MTLPixelFormat format;
    if (ctx->_ten_bit)
        format = plane == 0 ? MTLPixelFormatR16Unorm : MTLPixelFormatRG16Unorm;
    else
        format = plane == 0 ? MTLPixelFormatR8Unorm : MTLPixelFormatRG8Unorm;

    NSDictionary *attrs = @{
        (__bridge NSString *)kCVMetalTextureUsage:
            @(writable ? MTLTextureUsageShaderWrite : MTLTextureUsageShaderRead),
    };
    CVMetalTextureRef holder = NULL;
    if (CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault,
            ctx->_tex_cache, buffer, (__bridge CFDictionaryRef)attrs, format,
            width, height, plane, &holder) != kCVReturnSuccess)
        return nil;
    id owned = CFBridgingRelease(holder);
    [holders addObject:owned];
    return CVMetalTextureGetTexture((__bridge CVMetalTextureRef)owned);
}

/* Reads the block vectors, drops the wild ones and smooths what is left. A
 * 16x16 block field is a few thousand entries, so this stays free. */
static void MotionFieldUpdate(MacLCFrcContext *ctx, CVPixelBufferRef vectors)
{
    const unsigned cols = ctx->_mv_cols, rows = ctx->_mv_rows;
    const unsigned have_cols = (unsigned)CVPixelBufferGetWidth(vectors);
    const unsigned have_rows = (unsigned)CVPixelBufferGetHeight(vectors);

    CVPixelBufferLockBaseAddress(vectors, kCVPixelBufferLock_ReadOnly);
    const uint8_t *base = CVPixelBufferGetBaseAddress(vectors);
    const size_t stride = CVPixelBufferGetBytesPerRow(vectors);
    const float limit = (float)ctx->_width / 4.f;

    for (unsigned y = 0; y < rows; y++)
    {
        const unsigned sy = y < have_rows ? y : have_rows - 1;
        const __fp16 *line = (const __fp16 *)(base + sy * stride);
        for (unsigned x = 0; x < cols; x++)
        {
            const unsigned sx = x < have_cols ? x : have_cols - 1;
            float dx = (float)line[sx * 2];
            float dy = (float)line[sx * 2 + 1];
            /* A vector longer than a quarter of the picture is a mismatch,
             * not motion: a cross-fade looks better than a smear. */
            if (!isfinite(dx) || !isfinite(dy)
             || fabsf(dx) > limit || fabsf(dy) > limit)
                dx = dy = 0.f;
            ctx->_mv_field[(y * cols + x) * 2] = dx;
            ctx->_mv_field[(y * cols + x) * 2 + 1] = dy;
        }
    }
    CVPixelBufferUnlockBaseAddress(vectors, kCVPixelBufferLock_ReadOnly);

    /* Block matching is noisy and a jagged field tears edges once it is
     * warped. A 3x3 median throws away the odd wrong block without dragging
     * the vectors of a moving object towards the still background around it,
     * which is what averaging would do. */
    float *smoothed = ctx->_mv_scratch;
    for (unsigned y = 0; y < rows; y++)
        for (unsigned x = 0; x < cols; x++)
            for (unsigned c = 0; c < 2; c++)
            {
                float window[9];
                unsigned n = 0;
                for (int j = -1; j <= 1; j++)
                    for (int i = -1; i <= 1; i++)
                    {
                        const int px = (int)x + i, py = (int)y + j;
                        if (px < 0 || py < 0 || px >= (int)cols || py >= (int)rows)
                            continue;
                        window[n++] = ctx->_mv_field[(py * cols + px) * 2 + c];
                    }
                for (unsigned a = 1; a < n; a++)
                {
                    const float key = window[a];
                    unsigned b = a;
                    while (b > 0 && window[b - 1] > key)
                    {
                        window[b] = window[b - 1];
                        b--;
                    }
                    window[b] = key;
                }
                smoothed[(y * cols + x) * 2 + c] = window[n / 2];
            }
    memcpy(ctx->_mv_field, smoothed, (size_t)cols * rows * 2 * sizeof(*smoothed));

    [ctx->_mv_texture replaceRegion:MTLRegionMake2D(0, 0, cols, rows)
                        mipmapLevel:0 withBytes:ctx->_mv_field
                        bytesPerRow:cols * 2 * sizeof(float)];
}

static bool MotionEstimate(MacLCFrcContext *ctx, CVPixelBufferRef current)
{
    if (ctx->_engine != ENGINE_MOTION)
        return true;

    CVPixelBufferRef sample = PoolTake(ctx->_luma_pool);
    if (sample == NULL
     || VTPixelTransferSessionTransferImage(ctx->_xfer_luma, current,
                                            sample) != noErr)
    {
        if (sample != NULL)
            CVPixelBufferRelease(sample);
        return false;
    }

    bool ok = false;
    if (ctx->_estimate_prev != NULL)
    {
        if (@available(macOS 26.0, *))
        {
            __block bool done = false;
            dispatch_semaphore_t wait = dispatch_semaphore_create(0);
            OSStatus status = VTMotionEstimationSessionEstimateMotionVectors(
                ctx->_estimator, ctx->_estimate_prev, sample, 0, NULL,
                ^(OSStatus result, VTMotionEstimationInfoFlags flags,
                  CFDictionaryRef info, CVPixelBufferRef vectors) {
                    VLC_UNUSED(flags); VLC_UNUSED(info);
                    if (result == noErr && vectors != NULL)
                    {
                        MotionFieldUpdate(ctx, vectors);
                        done = true;
                    }
                    dispatch_semaphore_signal(wait);
                });
            if (status == noErr)
                dispatch_semaphore_wait(wait, DISPATCH_TIME_FOREVER);
            ok = done;
        }
    }

    if (ctx->_estimate_prev != NULL)
        CVPixelBufferRelease(ctx->_estimate_prev);
    ctx->_estimate_prev = sample;
    return ok;
}

static bool MetalRun(MacLCFrcContext *ctx, CVPixelBufferRef previous,
                     CVPixelBufferRef current, bool motion, CVPixelBufferRef *out)
{
    const unsigned count = ctx->_factor - 1;
    id<MTLCommandBuffer> commands = [ctx->_queue commandBuffer];
    if (commands == nil)
        return false;

    NSMutableArray *holders = [NSMutableArray arrayWithCapacity:(count + 1) * 2];
    id<MTLTexture> prev_planes[2], cur_planes[2];
    for (size_t plane = 0; plane < 2; plane++)
    {
        prev_planes[plane] = TextureForPlane(ctx, previous, plane, false, holders);
        cur_planes[plane] = TextureForPlane(ctx, current, plane, false, holders);
        if (prev_planes[plane] == nil || cur_planes[plane] == nil)
            return false;
    }

    bool ok = true;
    for (unsigned i = 0; i < count && ok; i++)
    {
        out[i] = PoolTake(ctx->_out_pool);
        if (out[i] == NULL)
        {
            ok = false;
            break;
        }
        struct maclc_frc_params params = {
            .mv_norm = { 1.f / (float)ctx->_width, 1.f / (float)ctx->_height },
            .phase = (float)(i + 1) / (float)ctx->_factor,
            .motion = motion ? 1.f : 0.f,
            .occ_lo = 0.08f,
            .occ_hi = 0.28f,
        };
        for (size_t plane = 0; plane < 2 && ok; plane++)
        {
            id<MTLTexture> destination =
                TextureForPlane(ctx, out[i], plane, true, holders);
            id<MTLComputeCommandEncoder> encoder = [commands computeCommandEncoder];
            if (destination == nil || encoder == nil)
            {
                /* An encoder left open trips Metal when the next one is
                 * created or when the buffer goes away. */
                [encoder endEncoding];
                ok = false;
                break;
            }
            [encoder setComputePipelineState:ctx->_pipeline];
            [encoder setTexture:prev_planes[plane] atIndex:0];
            [encoder setTexture:cur_planes[plane] atIndex:1];
            [encoder setTexture:prev_planes[0] atIndex:2];
            [encoder setTexture:cur_planes[0] atIndex:3];
            [encoder setTexture:ctx->_mv_texture atIndex:4];
            [encoder setTexture:destination atIndex:5];
            [encoder setBytes:&params length:sizeof(params) atIndex:0];
            const MTLSize group = MTLSizeMake(16, 16, 1);
            const MTLSize grid = MTLSizeMake(destination.width, destination.height, 1);
            [encoder dispatchThreads:grid threadsPerThreadgroup:group];
            [encoder endEncoding];
        }
    }

    if (!ok)
    {
        for (unsigned i = 0; i < count; i++)
            if (out[i] != NULL)
            {
                CVPixelBufferRelease(out[i]);
                out[i] = NULL;
            }
        return false;
    }

    [commands commit];
    [commands waitUntilCompleted];
    CVMetalTextureCacheFlush(ctx->_tex_cache, 0);
    return commands.error == nil;
}

/*****************************************************************************
 * Filter
 *****************************************************************************/

/* Copies a software picture into a 4:2:0 8-bit CoreVideo buffer, interleaving
 * the two chroma planes on the way when the source keeps them apart. */
static void PlanesToBuffer(MacLCFrcContext *ctx, const picture_t *picture,
                           CVPixelBufferRef buffer)
{
    CVPixelBufferLockBaseAddress(buffer, 0);
    uint8_t *luma = CVPixelBufferGetBaseAddressOfPlane(buffer, 0);
    const size_t luma_pitch = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0);
    const size_t height = CVPixelBufferGetHeightOfPlane(buffer, 0);
    const size_t width = CVPixelBufferGetWidthOfPlane(buffer, 0);

    for (size_t y = 0; y < height; y++)
        memcpy(luma + y * luma_pitch,
               picture->p[0].p_pixels + y * picture->p[0].i_pitch, width);

    uint8_t *chroma = CVPixelBufferGetBaseAddressOfPlane(buffer, 1);
    const size_t chroma_pitch = CVPixelBufferGetBytesPerRowOfPlane(buffer, 1);
    const size_t chroma_height = CVPixelBufferGetHeightOfPlane(buffer, 1);
    const size_t chroma_width = CVPixelBufferGetWidthOfPlane(buffer, 1);

    for (size_t y = 0; y < chroma_height; y++)
    {
        uint8_t *out = chroma + y * chroma_pitch;
        if (ctx->_planar)
            maclc_frc_interleave_chroma(
                out, 0,
                picture->p[1].p_pixels + y * picture->p[1].i_pitch, 0,
                picture->p[2].p_pixels + y * picture->p[2].i_pitch, 0,
                chroma_width, 1);
        else
            memcpy(out, picture->p[1].p_pixels + y * picture->p[1].i_pitch,
                   chroma_width * 2);
    }
    CVPixelBufferUnlockBaseAddress(buffer, 0);
}

static void BufferToPlanes(MacLCFrcContext *ctx, CVPixelBufferRef buffer,
                           picture_t *picture)
{
    CVPixelBufferLockBaseAddress(buffer, kCVPixelBufferLock_ReadOnly);
    const uint8_t *luma = CVPixelBufferGetBaseAddressOfPlane(buffer, 0);
    const size_t luma_pitch = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0);
    const size_t height = CVPixelBufferGetHeightOfPlane(buffer, 0);
    const size_t width = CVPixelBufferGetWidthOfPlane(buffer, 0);

    for (size_t y = 0; y < height; y++)
        memcpy(picture->p[0].p_pixels + y * picture->p[0].i_pitch,
               luma + y * luma_pitch, width);

    const uint8_t *chroma = CVPixelBufferGetBaseAddressOfPlane(buffer, 1);
    const size_t chroma_pitch = CVPixelBufferGetBytesPerRowOfPlane(buffer, 1);
    const size_t chroma_height = CVPixelBufferGetHeightOfPlane(buffer, 1);
    const size_t chroma_width = CVPixelBufferGetWidthOfPlane(buffer, 1);

    for (size_t y = 0; y < chroma_height; y++)
    {
        const uint8_t *in = chroma + y * chroma_pitch;
        if (ctx->_planar)
            maclc_frc_deinterleave_chroma(
                in, 0,
                picture->p[1].p_pixels + y * picture->p[1].i_pitch, 0,
                picture->p[2].p_pixels + y * picture->p[2].i_pitch, 0,
                chroma_width, 1);
        else
            memcpy(picture->p[1].p_pixels + y * picture->p[1].i_pitch,
                   in, chroma_width * 2);
    }
    CVPixelBufferUnlockBaseAddress(buffer, kCVPixelBufferLock_ReadOnly);
}

/* The picture's pixels as a CoreVideo buffer, owned by the caller. */
static CVPixelBufferRef BufferForPicture(MacLCFrcContext *ctx, picture_t *picture)
{
    if (!ctx->_software)
        return CVPixelBufferRetain(cvpxpic_get_ref(picture));

    CVPixelBufferRef buffer = PoolTake(ctx->_out_pool);
    if (buffer == NULL)
        return NULL;
    PlanesToBuffer(ctx, picture, buffer);
    return buffer;
}

/* Wraps a finished buffer in a picture, consuming the caller's reference to it
 * in every case, success or not. */
static picture_t *PictureFromBuffer(filter_t *filter, CVPixelBufferRef buffer,
                                    picture_t *model, vlc_tick_t date)
{
    MacLCFrcContext *ctx = (__bridge MacLCFrcContext *)filter->p_sys;
    picture_t *picture;

    if (ctx->_software)
    {
        picture = filter_NewPicture(filter);
        if (picture == NULL)
        {
            CVPixelBufferRelease(buffer);
            return NULL;
        }
        BufferToPlanes(ctx, buffer, picture);
        CVPixelBufferRelease(buffer);
    }
    else
    {
        picture = picture_NewFromFormat(&filter->fmt_out.video);
        if (picture == NULL)
        {
            CVPixelBufferRelease(buffer);
            return NULL;
        }
        /* cvpxpic_attach takes its own reference; ours has to go either way. */
        const int attached = cvpxpic_attach(picture, buffer, filter->vctx_out, NULL);
        CVPixelBufferRelease(buffer);
        if (attached != VLC_SUCCESS)
        {
            /* cvpxpic_attach released the picture itself on failure. */
            return NULL;
        }
    }
    picture_CopyProperties(picture, model);
    picture->date = date;
    picture->b_force = false;
    return picture;
}

static void DropHistory(MacLCFrcContext *ctx)
{
    if (ctx->_prev != NULL)
    {
        picture_Release(ctx->_prev);
        ctx->_prev = NULL;
    }
    if (ctx->_prev_buffer != NULL)
    {
        CVPixelBufferRelease(ctx->_prev_buffer);
        ctx->_prev_buffer = NULL;
    }
    if (ctx->_work_prev != NULL)
    {
        CVPixelBufferRelease(ctx->_work_prev);
        ctx->_work_prev = NULL;
    }
    if (ctx->_estimate_prev != NULL)
    {
        CVPixelBufferRelease(ctx->_estimate_prev);
        ctx->_estimate_prev = NULL;
    }
    if (ctx->_backend != NULL)
        ctx->_backend->ops->flush(ctx->_backend);
    ctx->_restart = true;
}

static void Flush(filter_t *filter)
{
    @autoreleasepool {
        MacLCFrcContext *ctx = (__bridge MacLCFrcContext *)filter->p_sys;
        DropHistory(ctx);
    }
}

static void BudgetReport(MacLCFrcContext *ctx, vlc_tick_t now)
{
    if (ctx->_report_at == 0)
    {
        ctx->_report_at = now;
        return;
    }
    if (now - ctx->_report_at < VLC_TICK_FROM_SEC(2))
        return;

    msg_Dbg(ctx->_filter, "frame interpolation: %s, x%u, %u passes, %u frames "
            "added, %.1f ms per pass for a %.1f ms budget",
            EngineName(ctx->_engine), ctx->_factor, ctx->_report_passes,
            ctx->_report_frames, ctx->_spent / 1000.f, ctx->_budget / 1000.f);
    ctx->_report_at = now;
    ctx->_report_passes = 0;
    ctx->_report_frames = 0;
}

static void BudgetAccount(MacLCFrcContext *ctx, vlc_tick_t spent)
{
    ctx->_spent = ctx->_spent == 0 ? spent : (ctx->_spent * 3 + spent) / 4;

    if (ctx->_overrun == OVERRUN_IGNORE || ctx->_budget <= 0)
        return;
    if (ctx->_spent * 10 <= ctx->_budget * 7)
    {
        ctx->_late_passes = 0;
        return;
    }
    /* Half a second of sustained overshoot, not one hiccup. */
    if (++ctx->_late_passes < 12)
        return;

    if (ctx->_overrun == OVERRUN_STOP || !EngineDegrade(ctx))
    {
        msg_Warn(ctx->_filter, "frame interpolation cannot keep up, stopping it");
        EngineRelease(ctx);
        DropHistory(ctx);
        ctx->_passthrough = true;
    }
}

static picture_t *Filter(filter_t *filter, picture_t *source)
{
    MacLCFrcContext *ctx = (__bridge MacLCFrcContext *)filter->p_sys;

    if (source == NULL)
        return NULL;
    if (ctx->_passthrough)
        return source;

    @autoreleasepool {
        if (source->date == VLC_TICK_INVALID || !source->b_progressive)
        {
            DropHistory(ctx);
            return source;
        }

        CVPixelBufferRef current = BufferForPicture(ctx, source);
        if (current == NULL)
        {
            DropHistory(ctx);
            return source;
        }

        const bool processor_engine = ctx->_engine == ENGINE_LOWLATENCY
            || ctx->_engine == ENGINE_QUALITY || ctx->_engine == ENGINE_BALANCED;

        if (ctx->_prev == NULL
         || source->date <= ctx->_prev->date
         || source->date - ctx->_prev->date > ctx->_budget * 4)
        {
            /* The first frame of a sequence has nothing to pair with, and a
             * jump, a still frame or a rewind gives nothing worth pairing:
             * keep it as a reference and let it through unchanged. */
            DropHistory(ctx);
            if (processor_engine)
                ctx->_work_prev = ProcessorConvertIn(ctx, current);
            else
                MotionEstimate(ctx, current);
            ctx->_prev = picture_Hold(source);
            ctx->_prev_buffer = current;
            return source;
        }

        const vlc_tick_t prev_date = ctx->_prev->date;
        const vlc_tick_t date = source->date;

        const unsigned count = ctx->_factor - 1;
        CVPixelBufferRef produced[8] = { NULL };
        const vlc_tick_t started = vlc_tick_now();
        bool ok;

        switch (ctx->_engine)
        {
            case ENGINE_QUALITY:
            case ENGINE_BALANCED:
            case ENGINE_LOWLATENCY:
                ok = ProcessorRun(ctx, current, prev_date, date, produced);
                break;
            case ENGINE_MOTION:
            {
                const bool estimated = MotionEstimate(ctx, current);
                ok = MetalRun(ctx, ctx->_prev_buffer, current,
                              estimated, produced);
                break;
            }
            case ENGINE_BLEND:
                ok = MetalRun(ctx, ctx->_prev_buffer, current,
                              false, produced);
                break;
            case ENGINE_SVP:
            case ENGINE_RIFE:
                ok = ctx->_backend->ops->run(ctx->_backend, ctx->_prev_buffer,
                                             current, produced);
                break;
            default:
                ok = false;
                break;
        }

        const vlc_tick_t finished = vlc_tick_now();
        ctx->_report_passes++;
        if (ok)
            ctx->_report_frames += count;
        BudgetAccount(ctx, finished - started);
        BudgetReport(ctx, finished);

        if (ctx->_passthrough)
        {
            /* The budget guard gave up during this pass; it already dropped
             * the history, so there is nothing left to keep. */
            CVPixelBufferRelease(current);
            if (!ok)
                return source;
        }
        else if (!ok)
        {
            /* Start the sequence again rather than pair this frame with a
             * reference the engine never took in. */
            DropHistory(ctx);
            if (processor_engine)
                ctx->_work_prev = ProcessorConvertIn(ctx, current);
            else
                MotionEstimate(ctx, current);
            ctx->_prev = picture_Hold(source);
            ctx->_prev_buffer = current;
            return source;
        }
        ctx->_restart = false;

        /* The previous frame has already been shown; hand back the frames that
         * come between it and this one, then this one. */
        picture_t *first = NULL, **tail = &first;
        for (unsigned i = 0; i < count; i++)
        {
            const vlc_tick_t when = prev_date
                + (date - prev_date) * (int64_t)(i + 1) / (int64_t)ctx->_factor;
            /* Takes the buffer's reference whether it succeeds or not. */
            picture_t *picture = PictureFromBuffer(filter, produced[i], source, when);
            if (picture == NULL)
                continue;
            *tail = picture;
            tail = &picture->p_next;
        }
        *tail = source;

        if (!ctx->_passthrough)
        {
            picture_Release(ctx->_prev);
            ctx->_prev = picture_Hold(source);
            CVPixelBufferRelease(ctx->_prev_buffer);
            ctx->_prev_buffer = current;
        }
        return first != NULL ? first : source;
    }
}

static const struct vlc_filter_operations filter_ops = {
    .filter_video = Filter,
    .flush = Flush,
    .close = Close,
};

static unsigned FactorFor(filter_t *filter, unsigned source_fps, int target)
{
    const unsigned limit = var_InheritInteger(filter, CFG_PREFIX "max-factor");
    unsigned wanted;
    switch (target)
    {
        case TARGET_60:     wanted = 60; break;
        case TARGET_120:    wanted = 120; break;
        case TARGET_DOUBLE: return source_fps == 0 || limit < 2 ? 1 : 2;
        default:            wanted = maclc_frc_display_refresh_rate(); break;
    }
    return maclc_frc_factor(source_fps, wanted, limit);
}

static void FreeOptions(MacLCFrcContext *ctx)
{
    free(ctx->_rife_model);
    ctx->_rife_model = NULL;
    free(ctx->_svp_path);
    ctx->_svp_path = NULL;
}

static int Open(filter_t *filter)
{
    if (!video_format_IsSimilar(&filter->fmt_in.video, &filter->fmt_out.video)
     || filter->fmt_in.video.i_chroma != filter->fmt_out.video.i_chroma)
    {
        msg_Dbg(filter, "not interpolating: the filter may not change the format");
        video_format_LogDifferences(vlc_object_logger(filter), "in", &filter->fmt_in.video,
                                    "out", &filter->fmt_out.video);
        return VLC_EGENERIC;
    }

    OSType cv_fmt;
    bool ten_bit, software;
    if (!ChromaIsSupported(filter->fmt_in.video.i_chroma, &cv_fmt, &ten_bit,
                           &software))
    {
        msg_Dbg(filter, "not interpolating: %4.4s is not a 4:2:0 chroma this "
                "filter knows", (const char *)&filter->fmt_in.video.i_chroma);
        return VLC_EGENERIC;
    }

    if (!software
     && (filter->vctx_in == NULL
      || vlc_video_context_GetType(filter->vctx_in) != VLC_VIDEO_CONTEXT_CVPX))
    {
        msg_Dbg(filter, "not interpolating: the pictures are not CoreVideo buffers");
        return VLC_EGENERIC;
    }

    const video_format_t *fmt = &filter->fmt_in.video;
    if (fmt->i_frame_rate == 0 || fmt->i_frame_rate_base == 0)
    {
        msg_Dbg(filter, "no frame rate, not interpolating");
        return VLC_EGENERIC;
    }
    const unsigned source_fps =
        (fmt->i_frame_rate + fmt->i_frame_rate_base / 2) / fmt->i_frame_rate_base;

    const int target = var_InheritInteger(filter, CFG_PREFIX "target");
    const unsigned factor = FactorFor(filter, source_fps, target);
    if (factor < 2)
    {
        msg_Dbg(filter, "%u fps already matches the display, not interpolating",
                source_fps);
        return VLC_EGENERIC;
    }

    @autoreleasepool {
        MacLCFrcContext *ctx = [MacLCFrcContext new];
        if (ctx == nil)
            return VLC_ENOMEM;

        ctx->_filter = filter;
        ctx->_requested = var_InheritInteger(filter, CFG_PREFIX "engine");
        ctx->_overrun = var_InheritInteger(filter, CFG_PREFIX "overrun");
        ctx->_rife = var_InheritBool(filter, CFG_PREFIX "rife");
        ctx->_rife_model = var_InheritString(filter, CFG_PREFIX "rife-model");
        ctx->_rife_scale = var_InheritFloat(filter, CFG_PREFIX "rife-scale");
        ctx->_rife_compute = var_InheritInteger(filter, CFG_PREFIX "rife-compute");
        ctx->_svp_path = var_InheritString(filter, CFG_PREFIX "svp-path");
        ctx->_factor = factor;
        ctx->_width = fmt->i_visible_width;
        ctx->_height = fmt->i_visible_height;
        ctx->_cv_fmt = cv_fmt;
        ctx->_ten_bit = ten_bit;
        ctx->_software = software;
        ctx->_planar = filter->fmt_in.video.i_chroma == VLC_CODEC_I420;
        ctx->_budget = vlc_tick_from_samples(fmt->i_frame_rate_base,
                                             fmt->i_frame_rate);

        /* In software mode this pool stages the planes on their way in and out;
         * with hardware decoding it holds the pictures we hand back. */
        ctx->_out_pool = software
            ? PoolFromAttributes(@{
                  (__bridge NSString *)kCVPixelBufferPixelFormatTypeKey: @(cv_fmt),
                  (__bridge NSString *)kCVPixelBufferWidthKey: @(ctx->_width),
                  (__bridge NSString *)kCVPixelBufferHeightKey: @(ctx->_height),
                  (__bridge NSString *)kCVPixelBufferMetalCompatibilityKey: @YES,
              }, (factor + 1) * 3)
            : cvpxpool_create(&filter->fmt_out.video, (factor + 1) * 3);
        if (ctx->_out_pool == NULL)
        {
            FreeOptions(ctx);
            return VLC_ENOMEM;
        }

        int order[ARRAY_SIZE(engine_ladder) + 1];
        unsigned candidates = 0;
        if (ctx->_requested != ENGINE_AUTO)
            order[candidates++] = ctx->_requested;
        else
        {
            const unsigned pixels = ctx->_width * ctx->_height;
            /* Measured on an M3 Max, 1080p: optical flow costs 29 ms for one
             * intermediate frame and 58 ms for four, so it only fits when the
             * source is slow and a single frame is asked for. The low-latency
             * processor does five frames in 18 ms but refuses anything above
             * 720p; motion compensation does five in 11 ms at 1080p and in
             * 12 ms at 4K, which is the only thing that leaves any headroom. */
            if (pixels <= 1280 * 720 && !ten_bit)
                order[candidates++] = ENGINE_LOWLATENCY;
            if (factor == 2 && pixels <= 1920 * 1088
             && ctx->_budget >= VLC_TICK_FROM_MS(40))
                order[candidates++] = ENGINE_BALANCED;
            order[candidates++] = ENGINE_MOTION;
            order[candidates++] = ENGINE_BLEND;
        }

        bool started = false;
        for (unsigned i = 0; i < candidates && !started; i++)
            started = EngineStart(ctx, order[i]);

        if (!started && ctx->_requested != ENGINE_AUTO)
        {
            msg_Warn(filter, "the %s engine is not available here, falling back",
                     EngineName(ctx->_requested));
            started = EngineStart(ctx, ENGINE_MOTION)
                   || EngineStart(ctx, ENGINE_BLEND);
        }

        if (!started)
        {
            msg_Warn(filter, "no interpolation engine available");
            EngineRelease(ctx);
            CVPixelBufferPoolRelease(ctx->_out_pool);
            ctx->_out_pool = NULL;
            FreeOptions(ctx);
            return VLC_EGENERIC;
        }

        filter->fmt_out.video.i_frame_rate = fmt->i_frame_rate * factor;
        filter->vctx_out = software ? NULL
                                    : vlc_video_context_Hold(filter->vctx_in);
        filter->ops = &filter_ops;
        filter->p_sys = (void *)CFBridgingRetain(ctx);

        msg_Info(filter, "interpolating %u fps to %u fps with the %s engine",
                 source_fps, source_fps * factor, EngineName(ctx->_engine));
    }
    return VLC_SUCCESS;
}

static void Close(filter_t *filter)
{
    @autoreleasepool {
        MacLCFrcContext *ctx = CFBridgingRelease(filter->p_sys);
        filter->p_sys = NULL;
        DropHistory(ctx);
        EngineRelease(ctx);
        if (ctx->_out_pool != NULL)
        {
            CVPixelBufferPoolRelease(ctx->_out_pool);
            ctx->_out_pool = NULL;
        }
        if (filter->vctx_out != NULL)
            vlc_video_context_Release(filter->vctx_out);
        FreeOptions(ctx);
    }
}
