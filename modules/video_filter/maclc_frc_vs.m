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

#include "maclc_frc_backend.h"

struct maclc_frc_backend *
maclc_frc_vs_start(const struct maclc_frc_backend_setup *setup)
{
    msg_Warn(setup->log, "the SmoothVideo Project engine is not built yet");
    return NULL;
}
