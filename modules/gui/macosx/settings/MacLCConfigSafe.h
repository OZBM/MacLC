/*****************************************************************************
 * MacLCConfigSafe.h: Safe wrappers around the libvlccore configuration accessors
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

#import <Foundation/Foundation.h>

#include <stdint.h>

/// YES when the named option is registered in this build. Options declared by
/// optional plugins (lua, avcodec, ...) are absent when those plugins are not
/// built, and reading one that is absent aborts inside libvlccore.
BOOL MacLCConfigExists(const char *name);

/// config_Get*/config_Put* wrappers that fall back instead of aborting when the
/// option is not registered in this build.
char *MacLCConfigGetPsz(const char *name);                   // NULL when absent
int64_t MacLCConfigGetInt(const char *name, int64_t fallback);
float MacLCConfigGetFloat(const char *name, float fallback);
void MacLCConfigPutPsz(const char *name, const char *value);  // no-op when absent
void MacLCConfigPutInt(const char *name, int64_t value);      // no-op when absent
void MacLCConfigPutFloat(const char *name, float value);      // no-op when absent
