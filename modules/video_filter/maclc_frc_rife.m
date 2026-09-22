// SPDX-License-Identifier: LGPL-2.1-or-later
/*****************************************************************************
 * maclc_frc_rife.m: the RIFE neural network on Core ML
 *****************************************************************************
 * Copyright © 2026 Hazen Studio
 *****************************************************************************/

#ifdef HAVE_CONFIG_H
# include "config.h"
#endif

#include <vlc_common.h>

#include "maclc_frc_backend.h"

struct maclc_frc_backend *
maclc_frc_rife_start(const struct maclc_frc_backend_setup *setup)
{
    msg_Warn(setup->log, "the RIFE engine is not built yet");
    return NULL;
}
