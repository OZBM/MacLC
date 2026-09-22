// SPDX-License-Identifier: LGPL-2.1-or-later
/*****************************************************************************
 * maclc_frc_vs.m: the SmoothVideo Project engine, hosted by VapourSynth
 *****************************************************************************
 * Copyright © 2026 Hazen Studio
 *****************************************************************************/

#ifdef HAVE_CONFIG_H
# include "config.h"
#endif

#include <vlc_common.h>
#include <vlc_threads.h>
#include <vlc_tick.h>

#import <Foundation/Foundation.h>
#import <CoreVideo/CoreVideo.h>

#include <dlfcn.h>
#include <pthread.h>
#include <stdlib.h>
#include <string.h>

/* The API headers are carried in the tree (see vapoursynth/README): the
 * library itself is opened with dlopen at run time, so building MacLC never
 * needs VapourSynth to be installed. */
#include "vapoursynth/VapourSynth4.h"
#include "vapoursynth/VSScript4.h"
#include "vapoursynth/VSHelper4.h"
#include "vapoursynth/VSConstants4.h"

#include "maclc_frc_backend.h"

/* Capacity of the source frame FIFO holding buffers published by run() */
#define RING_CAPACITY 16

struct ring_slot
{
    int64_t index;
    CVPixelBufferRef buffer;
};

struct maclc_frc_vs_backend;

/* Dynamically allocated per asynchronous output request to avoid stack lifetime
 * hazards when a run() invocation times out before worker callbacks fire. */
struct frame_ticket
{
    struct maclc_frc_vs_backend *backend;
    uint64_t generation;
    unsigned slot;
};

struct maclc_frc_vs_backend
{
    struct maclc_frc_backend ops_backend;

    struct maclc_frc_backend_setup setup;

    /* Dynamic library handle and API dispatch tables */
    void *vss_handle;
    const VSSCRIPTAPI *vssapi;
    const VSAPI *vsapi;

    /* VapourSynth engine instances */
    VSCore *vs_core;
    bool core_is_the_script_s;  /* createScript took it, even if it failed */
    VSScript *vs_script;
    VSNode *in_node;
    VSNode *out_node;
    VSVideoInfo vi;

    /* Thread synchronization */
    pthread_mutex_t lock;
    pthread_cond_t ring_cond;
    pthread_cond_t run_cond;

    /* State transitions */
    bool b_flushing;
    bool b_stopped;
    bool run_cancelled;
    bool run_failed;

    /* Ring buffer holding source frames for the VapourSynth source filter */
    struct ring_slot ring[RING_CAPACITY];
    int ring_count;
    int64_t source_frame_idx;

    /* Output request tracking */
    uint64_t run_generation;
    unsigned run_pending;
    const VSFrame *run_frames[8];

    /* What VapourSynth still has in its hands. A pass that gives up on its
     * deadline leaves requests running, and freeing the core or this very
     * structure while one of them is still in flight is a crash waiting for a
     * slow machine, so nothing is torn down until both of these reach zero. */
    unsigned async_inflight;   /* requests made, callback not yet returned */
    unsigned active_workers;   /* threads inside the source filter */
};

/*****************************************************************************
 * Ring buffer management
 *****************************************************************************/

/* Determines whether frame n is already available in the ring buffer.
 * If n is strictly older than any frame retained in our lookback window,
 * we consider it ready so that the retrieval can clamp rather than stall. */
static bool RingHasFrame(const struct maclc_frc_vs_backend *backend, int64_t n)
{
    if (backend->ring_count == 0)
        return false;

    int64_t min_idx = backend->ring[0].index;
    for (int i = 1; i < backend->ring_count; i++)
    {
        if (backend->ring[i].index < min_idx)
            min_idx = backend->ring[i].index;
    }
    if (n <= min_idx)
        return true;

    for (int i = 0; i < backend->ring_count; i++)
    {
        if (backend->ring[i].index == n)
            return true;
    }
    return false;
}

/* The newest frame published so far, or -1 when nothing has been. */
static int64_t RingNewestIndex(const struct maclc_frc_vs_backend *backend)
{
    int64_t newest = -1;
    for (int i = 0; i < backend->ring_count; i++)
    {
        if (backend->ring[i].index > newest)
            newest = backend->ring[i].index;
    }
    return newest;
}

static CVPixelBufferRef RingGetFrame(const struct maclc_frc_vs_backend *backend, int64_t n)
{
    if (backend->ring_count == 0)
        return NULL;

    for (int i = 0; i < backend->ring_count; i++)
    {
        if (backend->ring[i].index == n)
            return backend->ring[i].buffer;
    }

    /* Clamp to the oldest available frame if historical request fell behind */
    int oldest_slot = 0;
    for (int i = 1; i < backend->ring_count; i++)
    {
        if (backend->ring[i].index < backend->ring[oldest_slot].index)
            oldest_slot = i;
    }
    return backend->ring[oldest_slot].buffer;
}

static void RingPush(struct maclc_frc_vs_backend *backend, int64_t index,
                     CVPixelBufferRef buffer)
{
    if (buffer == NULL)
        return;

    for (int i = 0; i < backend->ring_count; i++)
    {
        if (backend->ring[i].index == index)
        {
            if (backend->ring[i].buffer != buffer)
            {
                CVPixelBufferRelease(backend->ring[i].buffer);
                backend->ring[i].buffer = CVPixelBufferRetain(buffer);
            }
            return;
        }
    }

    if (backend->ring_count < RING_CAPACITY)
    {
        int slot = backend->ring_count++;
        backend->ring[slot].index = index;
        backend->ring[slot].buffer = CVPixelBufferRetain(buffer);
    }
    else
    {
        /* Evict the oldest entry when ring capacity is reached */
        int oldest_slot = 0;
        for (int i = 1; i < backend->ring_count; i++)
        {
            if (backend->ring[i].index < backend->ring[oldest_slot].index)
                oldest_slot = i;
        }
        CVPixelBufferRelease(backend->ring[oldest_slot].buffer);
        backend->ring[oldest_slot].index = index;
        backend->ring[oldest_slot].buffer = CVPixelBufferRetain(buffer);
    }
}

static void RingClear(struct maclc_frc_vs_backend *backend)
{
    for (int i = 0; i < backend->ring_count; i++)
    {
        if (backend->ring[i].buffer != NULL)
        {
            CVPixelBufferRelease(backend->ring[i].buffer);
            backend->ring[i].buffer = NULL;
        }
    }
    backend->ring_count = 0;
}

/*****************************************************************************
 * Format conversion helpers
 *****************************************************************************/

/* Translates a CoreVideo 4:2:0 bi-planar buffer into a 3-plane VSFrame,
 * de-interleaving the chroma plane and adjusting 10-bit bit alignment. */
static VSFrame *CVPixelBufferToVSFrame(struct maclc_frc_vs_backend *backend,
                                      CVPixelBufferRef cv_buf)
{
    if (CVPixelBufferLockBaseAddress(cv_buf, kCVPixelBufferLock_ReadOnly) != kCVReturnSuccess)
        return NULL;

    const VSAPI *vsapi = backend->vsapi;
    VSFrame *frame = vsapi->newVideoFrame(&backend->vi.format, backend->vi.width,
                                          backend->vi.height, NULL, backend->vs_core);
    if (frame == NULL)
    {
        CVPixelBufferUnlockBaseAddress(cv_buf, kCVPixelBufferLock_ReadOnly);
        return NULL;
    }

    const size_t width = backend->setup.width;
    const size_t height = backend->setup.height;
    const size_t chroma_w = width / 2;
    const size_t chroma_h = height / 2;

    const uint8_t *cv_y = (const uint8_t *)CVPixelBufferGetBaseAddressOfPlane(cv_buf, 0);
    const size_t cv_stride_y = CVPixelBufferGetBytesPerRowOfPlane(cv_buf, 0);
    const uint8_t *cv_uv = (const uint8_t *)CVPixelBufferGetBaseAddressOfPlane(cv_buf, 1);
    const size_t cv_stride_uv = CVPixelBufferGetBytesPerRowOfPlane(cv_buf, 1);

    uint8_t *vs_y = vsapi->getWritePtr(frame, 0);
    const ptrdiff_t vs_stride_y = vsapi->getStride(frame, 0);
    uint8_t *vs_u = vsapi->getWritePtr(frame, 1);
    const ptrdiff_t vs_stride_u = vsapi->getStride(frame, 1);
    uint8_t *vs_v = vsapi->getWritePtr(frame, 2);
    const ptrdiff_t vs_stride_v = vsapi->getStride(frame, 2);

    if (!backend->setup.ten_bit)
    {
        for (size_t y = 0; y < height; y++)
            memcpy(vs_y + y * vs_stride_y, cv_y + y * cv_stride_y, width);

        for (size_t y = 0; y < chroma_h; y++)
        {
            const uint8_t *src_uv = cv_uv + y * cv_stride_uv;
            uint8_t *dst_u = vs_u + y * vs_stride_u;
            uint8_t *dst_v = vs_v + y * vs_stride_v;
            for (size_t x = 0; x < chroma_w; x++)
            {
                dst_u[x] = src_uv[2 * x];
                dst_v[x] = src_uv[2 * x + 1];
            }
        }
    }
    else
    {
        /* CoreVideo 10-bit bi-planar (P010) packs each component into the top 10
         * bits of a 16-bit word (bits [15:6]). VapourSynth integer formats expect
         * significant bits justified to the least-significant position (0..1023).
         * We right-shift by 6 to map from CoreVideo to VapourSynth storage. */
        for (size_t y = 0; y < height; y++)
        {
            const uint16_t *src_row = (const uint16_t *)(cv_y + y * cv_stride_y);
            uint16_t *dst_row = (uint16_t *)(vs_y + y * vs_stride_y);
            for (size_t x = 0; x < width; x++)
                dst_row[x] = src_row[x] >> 6;
        }

        for (size_t y = 0; y < chroma_h; y++)
        {
            const uint16_t *src_uv = (const uint16_t *)(cv_uv + y * cv_stride_uv);
            uint16_t *dst_u = (uint16_t *)(vs_u + y * vs_stride_u);
            uint16_t *dst_v = (uint16_t *)(vs_v + y * vs_stride_v);
            for (size_t x = 0; x < chroma_w; x++)
            {
                dst_u[x] = src_uv[2 * x] >> 6;
                dst_v[x] = src_uv[2 * x + 1] >> 6;
            }
        }
    }

    CVPixelBufferUnlockBaseAddress(cv_buf, kCVPixelBufferLock_ReadOnly);

    VSMap *props = vsapi->getFramePropertiesRW(frame);
    vsapi->mapSetInt(props, "_ColorRange", VSC_RANGE_LIMITED, maReplace);
    if (backend->setup.budget > 0)
    {
        vsapi->mapSetInt(props, "_DurationNum", backend->setup.budget, maReplace);
        vsapi->mapSetInt(props, "_DurationDen", CLOCK_FREQ, maReplace);
    }
    return frame;
}

/* Translates a 3-plane VSFrame back into an interleaved 4:2:0 bi-planar CoreVideo buffer,
 * restoring 10-bit components to their high-bit justification. */
static bool VSFrameToCVPixelBuffer(struct maclc_frc_vs_backend *backend,
                                   const VSFrame *vs_frame,
                                   CVPixelBufferRef cv_buf)
{
    if (CVPixelBufferLockBaseAddress(cv_buf, 0) != kCVReturnSuccess)
        return false;

    const VSAPI *vsapi = backend->vsapi;
    const size_t width = backend->setup.width;
    const size_t height = backend->setup.height;
    const size_t chroma_w = width / 2;
    const size_t chroma_h = height / 2;

    uint8_t *cv_y = (uint8_t *)CVPixelBufferGetBaseAddressOfPlane(cv_buf, 0);
    const size_t cv_stride_y = CVPixelBufferGetBytesPerRowOfPlane(cv_buf, 0);
    uint8_t *cv_uv = (uint8_t *)CVPixelBufferGetBaseAddressOfPlane(cv_buf, 1);
    const size_t cv_stride_uv = CVPixelBufferGetBytesPerRowOfPlane(cv_buf, 1);

    const uint8_t *vs_y = vsapi->getReadPtr(vs_frame, 0);
    const ptrdiff_t vs_stride_y = vsapi->getStride(vs_frame, 0);
    const uint8_t *vs_u = vsapi->getReadPtr(vs_frame, 1);
    const ptrdiff_t vs_stride_u = vsapi->getStride(vs_frame, 1);
    const uint8_t *vs_v = vsapi->getReadPtr(vs_frame, 2);
    const ptrdiff_t vs_stride_v = vsapi->getStride(vs_frame, 2);

    if (!backend->setup.ten_bit)
    {
        for (size_t y = 0; y < height; y++)
            memcpy(cv_y + y * cv_stride_y, vs_y + y * vs_stride_y, width);

        for (size_t y = 0; y < chroma_h; y++)
        {
            const uint8_t *src_u = vs_u + y * vs_stride_u;
            const uint8_t *src_v = vs_v + y * vs_stride_v;
            uint8_t *dst_uv = cv_uv + y * cv_stride_uv;
            for (size_t x = 0; x < chroma_w; x++)
            {
                dst_uv[2 * x]     = src_u[x];
                dst_uv[2 * x + 1] = src_v[x];
            }
        }
    }
    else
    {
        /* VapourSynth integer samples occupy bits [9:0]. CoreVideo 10-bit P010
         * requires them shifted to bits [15:6]. We left-shift by 6 to populate
         * the CoreVideo destination buffer. */
        for (size_t y = 0; y < height; y++)
        {
            const uint16_t *src_row = (const uint16_t *)(vs_y + y * vs_stride_y);
            uint16_t *dst_row = (uint16_t *)(cv_y + y * cv_stride_y);
            for (size_t x = 0; x < width; x++)
                dst_row[x] = src_row[x] << 6;
        }

        for (size_t y = 0; y < chroma_h; y++)
        {
            const uint16_t *src_u = (const uint16_t *)(vs_u + y * vs_stride_u);
            const uint16_t *src_v = (const uint16_t *)(vs_v + y * vs_stride_v);
            uint16_t *dst_uv = (uint16_t *)(cv_uv + y * cv_stride_uv);
            for (size_t x = 0; x < chroma_w; x++)
            {
                dst_uv[2 * x]     = src_u[x] << 6;
                dst_uv[2 * x + 1] = src_v[x] << 6;
            }
        }
    }

    CVPixelBufferUnlockBaseAddress(cv_buf, 0);
    return true;
}

static CVPixelBufferRef PoolTake(CVPixelBufferPoolRef pool)
{
    CVPixelBufferRef buffer = NULL;
    if (pool == NULL || CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &buffer) != kCVReturnSuccess)
        return NULL;
    return buffer;
}

/*****************************************************************************
 * Source node callbacks
 *****************************************************************************/

/* Filter registration mode fmUnordered is selected because our source node
 * maintains mutable state (a sliding window ring buffer of decoded frames)
 * and can be called concurrently across VapourSynth worker threads. The
 * condition variable gate inside InFilterGetFrame ensures that frame
 * requests block cleanly until run() publishes the necessary frames,
 * without suffering the single-frame throughput serialization of fmFrameState. */
/* Both counters are watched by stop(); the lock is already held. */
static void WorkerLeave(struct maclc_frc_vs_backend *backend)
{
    if (--backend->active_workers == 0)
        pthread_cond_broadcast(&backend->run_cond);
}

static const VSFrame *VS_CC InFilterGetFrame(int n, int activationReason,
                                             void *instanceData,
                                             void **frameData,
                                             VSFrameContext *frameCtx,
                                             VSCore *core,
                                             const VSAPI *vsapi)
{
    VLC_UNUSED(frameData);
    VLC_UNUSED(core);
    if (activationReason != arInitial)
        return NULL;

    struct maclc_frc_vs_backend *backend = (struct maclc_frc_vs_backend *)instanceData;

    pthread_mutex_lock(&backend->lock);
    backend->active_workers++;

    /* run() publishes both frames of the pair before it asks for anything, so
     * a request for something newer than the pair belongs to a pass that has
     * already been given up on: waiting for it would wait forever. */
    while (!RingHasFrame(backend, n)
        && n <= RingNewestIndex(backend)
        && !backend->b_flushing && !backend->b_stopped && !backend->run_cancelled)
    {
        pthread_cond_wait(&backend->ring_cond, &backend->lock);
    }

    CVPixelBufferRef buf = NULL;
    const char *refusal = NULL;
    if (backend->b_flushing || backend->b_stopped || backend->run_cancelled)
        refusal = "frame request abandoned: the sequence was flushed or stopped";
    else if (!RingHasFrame(backend, n))
        refusal = "frame request abandoned: that frame is not in the player's hands";
    else
    {
        buf = RingGetFrame(backend, n);
        if (buf == NULL)
            refusal = "frame request abandoned: no source frame";
        else
            CVPixelBufferRetain(buf);
    }

    if (refusal != NULL)
    {
        vsapi->setFilterError(refusal, frameCtx);
        WorkerLeave(backend);
        pthread_mutex_unlock(&backend->lock);
        return NULL;
    }
    pthread_mutex_unlock(&backend->lock);

    /* Perform pixel conversion outside the lock to avoid stalling other workers */
    VSFrame *frame = CVPixelBufferToVSFrame(backend, buf);
    CVPixelBufferRelease(buf);

    pthread_mutex_lock(&backend->lock);
    WorkerLeave(backend);
    pthread_mutex_unlock(&backend->lock);

    if (frame == NULL)
    {
        vsapi->setFilterError("Failed to convert CoreVideo buffer to VSFrame", frameCtx);
        return NULL;
    }

    return frame;
}

static void VS_CC InFilterFree(void *instanceData, VSCore *core, const VSAPI *vsapi)
{
    VLC_UNUSED(instanceData);
    VLC_UNUSED(core);
    VLC_UNUSED(vsapi);
}

static void VS_CC FrameDoneCallback(void *userData, const VSFrame *f, int n,
                                    VSNode *node, const char *errorMsg)
{
    VLC_UNUSED(n);
    VLC_UNUSED(node);
    struct frame_ticket *ticket = (struct frame_ticket *)userData;
    if (ticket == NULL)
        return;

    struct maclc_frc_vs_backend *backend = ticket->backend;

    pthread_mutex_lock(&backend->lock);
    if (backend->async_inflight > 0 && --backend->async_inflight == 0)
        pthread_cond_broadcast(&backend->run_cond);
    if (ticket->generation == backend->run_generation && !backend->run_cancelled)
    {
        if (f != NULL && errorMsg == NULL)
        {
            backend->run_frames[ticket->slot] = f;
        }
        else
        {
            backend->run_failed = true;
            if (f != NULL)
                backend->vsapi->freeFrame(f);
        }
        if (--backend->run_pending == 0 || backend->run_failed)
            pthread_cond_broadcast(&backend->run_cond);
    }
    else
    {
        /* Request was cancelled, timed out, or invalidated by flush */
        if (f != NULL)
            backend->vsapi->freeFrame(f);
    }
    pthread_mutex_unlock(&backend->lock);

    free(ticket);
}

/*****************************************************************************
 * Script generator
 *****************************************************************************/

static NSString *ResolveSVPBundle(const struct maclc_frc_backend_setup *setup)
{
    NSFileManager *fm = NSFileManager.defaultManager;
    if (setup->svp_path != NULL && setup->svp_path[0] != '\0')
    {
        NSString *path = [NSString stringWithUTF8String:setup->svp_path];
        if ([fm fileExistsAtPath:path])
            return path;
    }
    NSString *systemApp = @"/Applications/SVP 4 Mac.app";
    if ([fm fileExistsAtPath:systemApp])
        return systemApp;

    NSString *userApp = [NSHomeDirectory() stringByAppendingPathComponent:@"Applications/SVP 4 Mac.app"];
    if ([fm fileExistsAtPath:userApp])
        return userApp;

    return nil;
}

static NSString *GenerateMotionVectorScript(const struct maclc_frc_backend_setup *setup,
                                            NSString *svp_bundle,
                                            double fps)
{
    NSString *p1 = [svp_bundle stringByAppendingPathComponent:@"Contents/Resources/plugins/libsvpflow1_arm.dylib"];
    NSString *p2 = [svp_bundle stringByAppendingPathComponent:@"Contents/Resources/plugins/libsvpflow2_arm.dylib"];

    return [NSString stringWithFormat:
        @"import vapoursynth as vs\n"
        @"core = vs.core\n"
        @"core.std.LoadPlugin(\"%@\")\n"
        @"core.std.LoadPlugin(\"%@\")\n"
        @"src = video_in\n"
        @"smooth_src = src.resize.Bicubic(format=vs.YUV420P8)\n"
        @"sup = core.svp1.Super(smooth_src, \"{gpu:1}\")\n"
        @"vec = core.svp1.Analyse(sup[\"clip\"], sup[\"data\"], smooth_src, \"{}\")\n"
        @"out = core.svp2.SmoothFps(src, sup[\"clip\"], sup[\"data\"], vec[\"clip\"], vec[\"data\"], "
        @"\"{rate:{num:%u,den:1,abs:false},algo:13,mask:{area:100}}\", "
        @"src=src, fps=%.3f)\n"
        @"out.set_output()\n",
        p1, p2, setup->factor, fps];
}

static NSString *GenerateRIFEScript(const struct maclc_frc_backend_setup *setup,
                                   NSString *svp_bundle,
                                   double fps,
                                   bool rife_has_scale)
{
    NSMutableString *s = [NSMutableString string];
    [s appendString:@"import vapoursynth as vs\ncore = vs.core\n"];

    NSString *p2 = svp_bundle != nil
        ? [svp_bundle stringByAppendingPathComponent:@"Contents/Resources/plugins/libsvpflow2_arm.dylib"]
        : nil;
    bool has_svpflow2 = (p2 != nil && [NSFileManager.defaultManager fileExistsAtPath:p2]);

    if (has_svpflow2)
        [s appendFormat:@"core.std.LoadPlugin(\"%@\")\n", p2];

    [s appendString:@"src = video_in\nclip = src\n"];

    if (setup->rife_scene_cut)
        [s appendString:@"clip = clip.misc.SCDetect()\n"];

    [s appendString:@"clip = clip.resize.Bicubic(format=vs.RGBS, matrix_in_s=\"709\")\n"];

    NSString *model_path = nil;
    if (setup->rife_model != NULL && setup->rife_model[0] != '\0')
        model_path = [NSString stringWithUTF8String:setup->rife_model];
    else if (svp_bundle != nil)
        model_path = [svp_bundle stringByAppendingPathComponent:@"Contents/Resources/rife/rife-v4"];
    else
        model_path = @"/Applications/SVP 4 Mac.app/Contents/Resources/rife/rife-v4";

    NSString *scale_arg = @"";
    if (rife_has_scale && setup->rife_scale > 0.0f && setup->rife_scale <= 1.0f)
        scale_arg = [NSString stringWithFormat:@", scale=%.2f", setup->rife_scale];

    unsigned threads = setup->rife_threads > 0 ? setup->rife_threads : 1;

    [s appendFormat:@"smooth = core.rife.RIFE(clip, factor_num=%u, factor_den=1, model_path=\"%@\", gpu_id=0, gpu_thread=%u, tta=False, sc=True%@)\n",
     setup->factor, model_path, threads, scale_arg];

    if (has_svpflow2)
    {
        [s appendString:@"smooth = smooth.resize.Point(format=src.format.id, matrix_s=\"709\")\n"];
        [s appendFormat:@"out = core.svp2.SmoothFps_RIFE(smooth, \"{rate:{num:%u,den:1,abs:false},algo:13}\", src=src, multi=%u, fps=%.3f)\n",
         setup->factor, setup->factor, fps];
    }
    else
    {
        [s appendString:@"smooth = smooth.resize.Bicubic(format=src.format.id, matrix_s=\"709\")\n"];
        [s appendString:@"out = smooth\n"];
    }

    [s appendString:@"out.set_output()\n"];
    return s;
}

/*****************************************************************************
 * Backend operations
 *****************************************************************************/

static bool maclc_frc_vs_run(struct maclc_frc_backend *b,
                             CVPixelBufferRef prev,
                             CVPixelBufferRef cur,
                             CVPixelBufferRef *out)
{
    struct maclc_frc_vs_backend *backend = (struct maclc_frc_vs_backend *)b;
    if (backend == NULL || prev == NULL || cur == NULL || out == NULL)
        return false;

    const unsigned count = backend->setup.factor - 1;
    if (count == 0 || count > 7)
        return false;

    pthread_mutex_lock(&backend->lock);
    if (backend->b_stopped || backend->b_flushing)
    {
        pthread_mutex_unlock(&backend->lock);
        return false;
    }

    backend->run_generation++;
    backend->run_pending = count;
    backend->run_failed = false;
    backend->run_cancelled = false;
    for (unsigned i = 0; i < 8; i++)
        backend->run_frames[i] = NULL;

    const int64_t n = backend->source_frame_idx;
    RingPush(backend, n, prev);
    RingPush(backend, n + 1, cur);
    pthread_cond_broadcast(&backend->ring_cond);
    const uint64_t current_generation = backend->run_generation;
    pthread_mutex_unlock(&backend->lock);

    bool dispatch_ok = true;
    for (unsigned i = 0; i < count; i++)
    {
        struct frame_ticket *ticket = malloc(sizeof(*ticket));
        if (ticket == NULL)
        {
            dispatch_ok = false;
            break;
        }
        ticket->backend = backend;
        ticket->generation = current_generation;
        ticket->slot = i;

        int out_frame_no = (int)(n * backend->setup.factor + (i + 1));
        pthread_mutex_lock(&backend->lock);
        backend->async_inflight++;
        pthread_mutex_unlock(&backend->lock);
        backend->vsapi->getFrameAsync(out_frame_no, backend->out_node,
                                      FrameDoneCallback, ticket);
    }

    if (!dispatch_ok)
    {
        pthread_mutex_lock(&backend->lock);
        backend->run_cancelled = true;
        pthread_cond_broadcast(&backend->ring_cond);
        for (unsigned i = 0; i < 8; i++)
        {
            if (backend->run_frames[i] != NULL)
            {
                backend->vsapi->freeFrame(backend->run_frames[i]);
                backend->run_frames[i] = NULL;
            }
        }
        pthread_mutex_unlock(&backend->lock);
        return false;
    }

    /* Wait with a bound derived from frame duration so playback never freezes */
    pthread_mutex_lock(&backend->lock);
    vlc_tick_t deadline = backend->setup.budget > 0 ? backend->setup.budget * 3 : VLC_TICK_FROM_MS(150);
    struct timespec ts;
    ts.tv_sec = deadline / CLOCK_FREQ;
    ts.tv_nsec = (deadline % CLOCK_FREQ) * 1000;

    while (backend->run_pending > 0 && !backend->run_failed
           && !backend->b_flushing && !backend->b_stopped
           && !backend->run_cancelled)
    {
        int rc = pthread_cond_timedwait_relative_np(&backend->run_cond, &backend->lock, &ts);
        if (rc != 0)
        {
            backend->run_cancelled = true;
            pthread_cond_broadcast(&backend->ring_cond);
            break;
        }
    }

    bool success = (backend->run_pending == 0 && !backend->run_failed
                    && !backend->b_flushing && !backend->b_stopped
                    && !backend->run_cancelled);

    const VSFrame *frames[8] = { NULL };
    if (success)
    {
        for (unsigned i = 0; i < count; i++)
        {
            frames[i] = backend->run_frames[i];
            backend->run_frames[i] = NULL;
        }
    }
    else
    {
        backend->run_cancelled = true;
        pthread_cond_broadcast(&backend->ring_cond);
        for (unsigned i = 0; i < 8; i++)
        {
            if (backend->run_frames[i] != NULL)
            {
                backend->vsapi->freeFrame(backend->run_frames[i]);
                backend->run_frames[i] = NULL;
            }
        }
    }
    pthread_mutex_unlock(&backend->lock);

    if (!success)
        return false;

    bool conv_ok = true;
    for (unsigned i = 0; i < count; i++)
    {
        out[i] = PoolTake(backend->setup.out_pool);
        if (out[i] == NULL)
        {
            conv_ok = false;
            break;
        }
        if (!VSFrameToCVPixelBuffer(backend, frames[i], out[i]))
        {
            conv_ok = false;
            break;
        }
    }

    for (unsigned i = 0; i < count; i++)
    {
        if (frames[i] != NULL)
            backend->vsapi->freeFrame(frames[i]);
    }

    if (!conv_ok)
    {
        for (unsigned i = 0; i < count; i++)
        {
            if (out[i] != NULL)
            {
                CVPixelBufferRelease(out[i]);
                out[i] = NULL;
            }
        }
        return false;
    }

    pthread_mutex_lock(&backend->lock);
    backend->source_frame_idx++;
    pthread_mutex_unlock(&backend->lock);
    return true;
}

static void maclc_frc_vs_flush(struct maclc_frc_backend *b)
{
    struct maclc_frc_vs_backend *backend = (struct maclc_frc_vs_backend *)b;
    if (backend == NULL)
        return;

    pthread_mutex_lock(&backend->lock);
    backend->b_flushing = true;
    backend->run_cancelled = true;
    backend->run_generation++;
    pthread_cond_broadcast(&backend->ring_cond);
    pthread_cond_broadcast(&backend->run_cond);

    for (unsigned i = 0; i < 8; i++)
    {
        if (backend->run_frames[i] != NULL)
        {
            backend->vsapi->freeFrame(backend->run_frames[i]);
            backend->run_frames[i] = NULL;
        }
    }

    RingClear(backend);
    backend->source_frame_idx = 0;
    backend->b_flushing = false;
    pthread_mutex_unlock(&backend->lock);
}

static void maclc_frc_vs_stop(struct maclc_frc_backend *b)
{
    struct maclc_frc_vs_backend *backend = (struct maclc_frc_vs_backend *)b;
    if (backend == NULL)
        return;

    pthread_mutex_lock(&backend->lock);
    backend->b_stopped = true;
    backend->run_cancelled = true;
    backend->run_generation++;
    pthread_cond_broadcast(&backend->ring_cond);
    pthread_cond_broadcast(&backend->run_cond);

    /* Freeing a node or a core while a request is still running is undefined,
     * and the callback would come back to a structure that no longer exists.
     * Every worker and every callback is on its way out by now -- they all
     * check b_stopped -- so this wait is short; it is bounded anyway, because
     * leaking a backend is a far smaller thing than a crash on quit. */
    const vlc_tick_t quiesce_deadline = vlc_tick_now() + VLC_TICK_FROM_SEC(2);
    while (backend->async_inflight > 0 || backend->active_workers > 0)
    {
        const vlc_tick_t left = quiesce_deadline - vlc_tick_now();
        if (left <= 0)
            break;
        struct timespec ts = {
            .tv_sec = left / CLOCK_FREQ,
            .tv_nsec = (left % CLOCK_FREQ) * 1000,
        };
        if (pthread_cond_timedwait_relative_np(&backend->run_cond, &backend->lock, &ts) != 0)
            break;
    }
    const bool quiet = backend->async_inflight == 0 && backend->active_workers == 0;
    RingClear(backend);
    pthread_mutex_unlock(&backend->lock);

    if (!quiet)
    {
        msg_Err(backend->setup.log, "VapourSynth did not let go within two "
                "seconds; leaving its core and this engine behind rather than "
                "freeing them under it");
        return;
    }

    /* Output and input nodes must be freed before freeing the script context,
     * as required by VSScript documentation to prevent dangling core references. */
    if (backend->out_node != NULL)
    {
        backend->vsapi->freeNode(backend->out_node);
        backend->out_node = NULL;
    }
    if (backend->in_node != NULL)
    {
        backend->vsapi->freeNode(backend->in_node);
        backend->in_node = NULL;
    }

    /* freeScript frees the VSScript environment and takes ownership of releasing
     * the underlying VSCore provided to createScript. */
    if (backend->vs_script != NULL)
    {
        backend->vssapi->freeScript(backend->vs_script);
        backend->vs_script = NULL;
        backend->vs_core = NULL;
    }
    else if (backend->vs_core != NULL && !backend->core_is_the_script_s)
    {
        backend->vsapi->freeCore(backend->vs_core);
        backend->vs_core = NULL;
    }
    backend->vs_core = NULL;

    if (backend->vss_handle != NULL)
    {
        dlclose(backend->vss_handle);
        backend->vss_handle = NULL;
    }

    pthread_mutex_destroy(&backend->lock);
    pthread_cond_destroy(&backend->ring_cond);
    pthread_cond_destroy(&backend->run_cond);

    free(backend);
}

static const struct maclc_frc_backend_ops vs_ops = {
    .run   = maclc_frc_vs_run,
    .flush = maclc_frc_vs_flush,
    .stop  = maclc_frc_vs_stop,
};

/*****************************************************************************
 * Entry point
 *****************************************************************************/

struct maclc_frc_backend *
maclc_frc_vs_start(const struct maclc_frc_backend_setup *setup)
{
    if (setup == NULL || setup->log == NULL || setup->out_pool == NULL
     || setup->width == 0 || setup->height == 0
     || setup->factor < 2 || setup->factor > 8)
    {
        return NULL;
    }

    /* A script of the user's own decides for itself what it loads, so it is
     * looked for before anything is demanded of the installation. */
    NSString *app_support = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES).firstObject;
    NSString *user_script_path = [app_support stringByAppendingPathComponent:@"MacLC/frc.vpy"];
    const bool use_user_script = [NSFileManager.defaultManager fileExistsAtPath:user_script_path];

    NSString *svp_bundle = ResolveSVPBundle(setup);
    if (!setup->rife && !use_user_script)
    {
        if (svp_bundle == nil)
        {
            msg_Warn(setup->log, "SmoothVideo Project application bundle not found "
                     "(looked in '%s', '/Applications/SVP 4 Mac.app', '~/Applications/SVP 4 Mac.app')",
                     setup->svp_path ? setup->svp_path : "");
            return NULL;
        }

        NSString *plugins_dir = [svp_bundle stringByAppendingPathComponent:@"Contents/Resources/plugins"];
        NSString *p1 = [plugins_dir stringByAppendingPathComponent:@"libsvpflow1_arm.dylib"];
        NSString *p2 = [plugins_dir stringByAppendingPathComponent:@"libsvpflow2_arm.dylib"];
        NSFileManager *fm = NSFileManager.defaultManager;
        if (![fm fileExistsAtPath:p1])
        {
            msg_Warn(setup->log, "SmoothVideo Project plugin not found: %s", p1.UTF8String);
            return NULL;
        }
        if (![fm fileExistsAtPath:p2])
        {
            msg_Warn(setup->log, "SmoothVideo Project plugin not found: %s", p2.UTF8String);
            return NULL;
        }
    }

    static const char *const vss_candidates[] = {
        "/opt/homebrew/lib/libvapoursynth-script.dylib",
        "/usr/local/lib/libvapoursynth-script.dylib",
        "libvapoursynth-script.dylib",
    };

    void *vss_handle = NULL;
    for (size_t i = 0; i < sizeof(vss_candidates) / sizeof(vss_candidates[0]); i++)
    {
        vss_handle = dlopen(vss_candidates[i], RTLD_NOW | RTLD_LOCAL);
        if (vss_handle != NULL)
            break;
    }

    if (vss_handle == NULL)
    {
        msg_Dbg(setup->log, "VapourSynth scripting library not found (libvapoursynth-script.dylib)");
        return NULL;
    }

    typedef const VSSCRIPTAPI *(*vss_get_api_f)(int version);
    vss_get_api_f get_vss_api = (vss_get_api_f)dlsym(vss_handle, "getVSScriptAPI");
    if (get_vss_api == NULL)
    {
        msg_Warn(setup->log, "failed to locate getVSScriptAPI symbol: %s", dlerror());
        dlclose(vss_handle);
        return NULL;
    }

    const VSSCRIPTAPI *vssapi = get_vss_api(VSSCRIPT_API_VERSION);
    if (vssapi == NULL)
    {
        msg_Warn(setup->log, "getVSScriptAPI(%d) returned NULL", VSSCRIPT_API_VERSION);
        dlclose(vss_handle);
        return NULL;
    }

    const VSAPI *vsapi = vssapi->getVSAPI(VAPOURSYNTH_API_VERSION);
    if (vsapi == NULL)
    {
        msg_Warn(setup->log, "getVSAPI(%d) returned NULL", VAPOURSYNTH_API_VERSION);
        dlclose(vss_handle);
        return NULL;
    }

    VSCore *core = vsapi->createCore(0);
    if (core == NULL)
    {
        msg_Err(setup->log, "failed to create VapourSynth core");
        dlclose(vss_handle);
        return NULL;
    }
    vsapi->setThreadCount(4, core);

    bool rife_has_scale = false;
    if (setup->rife && !use_user_script)
    {
        VSPlugin *rife_plugin = vsapi->getPluginByNamespace("rife", core);
        if (rife_plugin == NULL)
        {
            msg_Warn(setup->log, "RIFE mode requested but no 'rife' plugin is registered in VapourSynth");
            vsapi->freeCore(core);
            dlclose(vss_handle);
            return NULL;
        }
        VSPluginFunction *rife_func = vsapi->getPluginFunctionByName("RIFE", rife_plugin);
        const char *func_args = rife_func ? vsapi->getPluginFunctionArguments(rife_func) : NULL;
        rife_has_scale = (func_args != NULL && strstr(func_args, "scale") != NULL);
    }

    struct maclc_frc_vs_backend *backend = calloc(1, sizeof(*backend));
    if (backend == NULL)
    {
        vsapi->freeCore(core);
        dlclose(vss_handle);
        return NULL;
    }

    backend->ops_backend.ops = &vs_ops;
    backend->setup = *setup;
    backend->vss_handle = vss_handle;
    backend->vssapi = vssapi;
    backend->vsapi = vsapi;
    backend->vs_core = core;

    pthread_mutex_init(&backend->lock, NULL);
    pthread_cond_init(&backend->ring_cond, NULL);
    pthread_cond_init(&backend->run_cond, NULL);

    vsapi->getVideoFormatByID(&backend->vi.format,
                              setup->ten_bit ? pfYUV420P10 : pfYUV420P8, core);
    backend->vi.width = setup->width;
    backend->vi.height = setup->height;
    if (setup->budget > 0)
    {
        backend->vi.fpsNum = CLOCK_FREQ;
        backend->vi.fpsDen = setup->budget;
        vsh_reduceRational(&backend->vi.fpsNum, &backend->vi.fpsDen);
    }
    else
    {
        backend->vi.fpsNum = 24000;
        backend->vi.fpsDen = 1001;
    }
    backend->vi.numFrames = 100000000;

    backend->in_node = vsapi->createVideoFilter2("video_in", &backend->vi,
                                                 InFilterGetFrame,
                                                 InFilterFree,
                                                 fmUnordered,
                                                 NULL, 0,
                                                 backend, core);
    if (backend->in_node == NULL)
    {
        msg_Err(setup->log, "failed to create video_in source node");
        maclc_frc_vs_stop(&backend->ops_backend);
        return NULL;
    }

    /* createScript owns the core from here on, on success and on failure
     * alike (VSScript4.h). The pointer stays, because frames are still
     * allocated from it; what changes is who frees it. */
    backend->core_is_the_script_s = true;
    backend->vs_script = vssapi->createScript(core);
    if (backend->vs_script == NULL)
    {
        msg_Err(setup->log, "failed to create VSScript context");
        maclc_frc_vs_stop(&backend->ops_backend);
        return NULL;
    }

    VSMap *vars = vsapi->createMap();
    vsapi->mapSetNode(vars, "video_in", backend->in_node, maReplace);
    double fps = setup->budget > 0 ? (double)CLOCK_FREQ / (double)setup->budget : 23.976;
    vsapi->mapSetFloat(vars, "container_fps", fps, maReplace);
    vssapi->setVariables(backend->vs_script, vars);
    vsapi->freeMap(vars);

    int rc;
    if (use_user_script)
    {
        msg_Dbg(setup->log, "evaluating user override script: %s", user_script_path.UTF8String);
        vssapi->evalSetWorkingDir(backend->vs_script, 1);
        rc = vssapi->evaluateFile(backend->vs_script, user_script_path.UTF8String);
    }
    else
    {
        msg_Dbg(setup->log, "evaluating generated %s script", setup->rife ? "RIFE" : "motion vector");
        NSString *script_text = setup->rife
            ? GenerateRIFEScript(setup, svp_bundle, fps, rife_has_scale)
            : GenerateMotionVectorScript(setup, svp_bundle, fps);
        rc = vssapi->evaluateBuffer(backend->vs_script, script_text.UTF8String, "maclc_frc.vpy");
    }

    if (rc != 0)
    {
        const char *err = vssapi->getError(backend->vs_script);
        msg_Err(setup->log, "failed to evaluate VapourSynth script: %s", err ? err : "unknown error");
        maclc_frc_vs_stop(&backend->ops_backend);
        return NULL;
    }

    backend->out_node = vssapi->getOutputNode(backend->vs_script, 0);
    if (backend->out_node == NULL)
    {
        msg_Err(setup->log, "VapourSynth script produced no output node (set_output not called)");
        maclc_frc_vs_stop(&backend->ops_backend);
        return NULL;
    }

    const VSVideoInfo *out_vi = vsapi->getVideoInfo(backend->out_node);
    if (out_vi == NULL || out_vi->width != (int)setup->width || out_vi->height != (int)setup->height)
    {
        msg_Err(setup->log, "output node size (%dx%d) does not match input (%ux%u)",
                out_vi ? out_vi->width : 0, out_vi ? out_vi->height : 0,
                setup->width, setup->height);
        maclc_frc_vs_stop(&backend->ops_backend);
        return NULL;
    }

    return &backend->ops_backend;
}
