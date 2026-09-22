// SPDX-License-Identifier: LGPL-2.1-or-later
/*****************************************************************************
 * maclc_frc_backend.h: engines that live outside maclc_frc.m
 *****************************************************************************
 * Copyright © 2026 Hazen Studio
 *
 * The engines built on VideoToolbox and on Metal are written inside
 * maclc_frc.m because they share its pools and its pixel transfer sessions.
 * The two engines that reach outside the player -- the SmoothVideo Project
 * graph, which is hosted by VapourSynth, and the RIFE neural network, which
 * runs on Core ML -- are large enough to deserve their own files. They see the
 * filter only through this contract.
 *
 * The filter hands a backend two consecutive source buffers and expects
 * factor - 1 buffers back, evenly spaced between them. Every buffer handed
 * back belongs to the caller, which releases it; buffers are taken from the
 * pool in the setup, so they already have the size and the format the rest of
 * the chain expects.
 *****************************************************************************/

#ifndef MACLC_FRC_BACKEND_H
#define MACLC_FRC_BACKEND_H

#include <vlc_common.h>
#include <vlc_tick.h>
#include <CoreVideo/CoreVideo.h>

/* What the filter tells a backend when it starts it. */
struct maclc_frc_backend_setup
{
    vlc_object_t *log;          /* for msg_Dbg and friends; never NULL */

    unsigned      width, height;/* visible size of the pictures */
    OSType        cv_fmt;       /* CoreVideo format of the source buffers and
                                 * of the buffers in out_pool */
    bool          ten_bit;      /* cv_fmt carries 10 bits per component */

    unsigned      factor;       /* output frames per source frame, 2 to 8 */
    vlc_tick_t    budget;       /* how long one source frame lasts */

    CVPixelBufferPoolRef out_pool; /* where the result buffers come from */

    /* SmoothVideo Project engine */
    const char   *svp_path;     /* the SVP application bundle, or NULL for the
                                 * usual place */
    /* RIFE, both as the SVP engine's neural mode and as the Core ML engine */
    bool          rife;         /* SVP: interpolate with RIFE rather than with
                                 * the svpflow motion vectors */
    const char   *rife_model;   /* the model directory or package, or NULL to
                                 * look in the usual places */
    float         rife_scale;   /* the resolution the flow is computed at,
                                 * 1.0 for the full picture, 0.5 for half */
    unsigned      rife_threads; /* concurrent inferences, 1 on Apple silicon */
    bool          rife_scene_cut;/* leave a cut alone rather than blend across it */
};

struct maclc_frc_backend;

struct maclc_frc_backend_ops
{
    /* Makes factor - 1 frames between prev and cur, oldest first, into out.
     * Returns false and leaves out untouched when the pair cannot be done;
     * the filter then restarts its sequence. */
    bool (*run)(struct maclc_frc_backend *, CVPixelBufferRef prev,
                CVPixelBufferRef cur, CVPixelBufferRef *out);
    /* The sequence is broken: forget everything held from earlier frames. */
    void (*flush)(struct maclc_frc_backend *);
    /* Releases the backend and everything in it. */
    void (*stop)(struct maclc_frc_backend *);
};

struct maclc_frc_backend
{
    const struct maclc_frc_backend_ops *ops;
};

/* Both return NULL, after saying why in the log, when the pieces they need are
 * not installed. Neither is ever chosen automatically: the user asks for them. */
struct maclc_frc_backend *
maclc_frc_vs_start(const struct maclc_frc_backend_setup *setup);

struct maclc_frc_backend *
maclc_frc_rife_start(const struct maclc_frc_backend_setup *setup);

#endif /* MACLC_FRC_BACKEND_H */
