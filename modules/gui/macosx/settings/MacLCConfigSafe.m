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
#include <vlc_plugin.h>

/* config_Get*() and config_Put*() assert that the option exists and has
 * their type: a settings pane asking for an option a build lacks, or with
 * the wrong type, must not abort the player. */
static module_config_t *FindConfig(const char *name, int kind)
{
    module_config_t * const item = config_FindConfig(name);
    if (item == NULL)
        return NULL;
    switch (kind) {
        case CONFIG_ITEM_STRING:  return IsConfigStringType(item->i_type) ? item : NULL;
        case CONFIG_ITEM_INTEGER: return IsConfigIntegerType(item->i_type) ? item : NULL;
        case CONFIG_ITEM_FLOAT:   return IsConfigFloatType(item->i_type) ? item : NULL;
    }
    return NULL;
}

BOOL MacLCConfigExists(const char *name)
{
    return config_FindConfig(name) != NULL;
}

char *MacLCConfigGetPsz(const char *name)
{
    if (!FindConfig(name, CONFIG_ITEM_STRING))
        return NULL;
    return config_GetPsz(name);
}

int64_t MacLCConfigGetInt(const char *name, int64_t fallback)
{
    if (!FindConfig(name, CONFIG_ITEM_INTEGER))
        return fallback;
    return config_GetInt(name);
}

float MacLCConfigGetFloat(const char *name, float fallback)
{
    if (!FindConfig(name, CONFIG_ITEM_FLOAT))
        return fallback;
    return config_GetFloat(name);
}

void MacLCConfigPutPsz(const char *name, const char *value)
{
    if (!FindConfig(name, CONFIG_ITEM_STRING))
        return;
    config_PutPsz(name, value);
}

void MacLCConfigPutInt(const char *name, int64_t value)
{
    if (!FindConfig(name, CONFIG_ITEM_INTEGER))
        return;
    config_PutInt(name, value);
}

void MacLCConfigPutFloat(const char *name, float value)
{
    if (!FindConfig(name, CONFIG_ITEM_FLOAT))
        return;
    config_PutFloat(name, value);
}
