/*****************************************************************************
 * MacLCConfigSafe.m: Safe wrappers around the libvlccore configuration accessors
 *****************************************************************************
 * Copyright (C) 2026 VLC authors and VideoLAN
 *
 * Authors: MacLC Settings Team
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston MA 02110-1301, USA.
 *****************************************************************************/

#import "settings/MacLCConfigSafe.h"

#ifdef HAVE_CONFIG_H
# include "config.h"
#endif

#include <vlc_common.h>
#include <vlc_configuration.h>

BOOL MacLCConfigExists(const char *name)
{
    return config_FindConfig(name) != NULL;
}

char *MacLCConfigGetPsz(const char *name)
{
    if (!config_FindConfig(name))
        return NULL;
    return config_GetPsz(name);
}

int64_t MacLCConfigGetInt(const char *name, int64_t fallback)
{
    if (!config_FindConfig(name))
        return fallback;
    return config_GetInt(name);
}

float MacLCConfigGetFloat(const char *name, float fallback)
{
    if (!config_FindConfig(name))
        return fallback;
    return config_GetFloat(name);
}

void MacLCConfigPutPsz(const char *name, const char *value)
{
    if (!config_FindConfig(name))
        return;
    config_PutPsz(name, value);
}

void MacLCConfigPutInt(const char *name, int64_t value)
{
    if (!config_FindConfig(name))
        return;
    config_PutInt(name, value);
}

void MacLCConfigPutFloat(const char *name, float value)
{
    if (!config_FindConfig(name))
        return;
    config_PutFloat(name, value);
}
