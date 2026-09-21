/*****************************************************************************
 * MacLCVolumePath.m: whether a path lives on a local volume
 *****************************************************************************
 * Copyright (C) 2026 Hazen Studio
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

#import "MacLCVolumePath.h"

#include <sys/mount.h>
#include <sys/param.h>
#include <string.h>
#include <strings.h>

BOOL MacLCPathIsOnLocalVolume(NSString *path)
{
    /* -fileSystemRepresentation raises on an empty string, so the length is
     * tested before asking for it. */
    if (path.length == 0) {
        return NO;
    }

    struct statfs *mounts = NULL;
    const int count = getmntinfo(&mounts, MNT_NOWAIT);
    const char * const cPath = path.fileSystemRepresentation;
    if (count <= 0 || cPath == NULL || cPath[0] == '\0') {
        return NO;
    }

    size_t bestLength = 0;
    BOOL isLocal = NO;
    for (int i = 0; i < count; i++) {
        const char * const mountPoint = mounts[i].f_mntonname;
        const size_t length = strlen(mountPoint);
        if (length < bestLength) {
            continue;
        }
        /* Most volumes are case insensitive, so a path whose case differs from
         * the mount point's still lives on that volume. Comparing exactly
         * would leave it matching "/" alone and call a remote file local,
         * which is the one mistake that costs a frozen interface; a case
         * insensitive match can only ever answer "not local" here, since a
         * mount that really is a different, case sensitive one is remote or
         * local on its own merits. */
        if (strncasecmp(cPath, mountPoint, length) != 0) {
            continue;
        }
        /* Match whole path components only ("/Volumes/A" is not "/Volumes/AB"). */
        if (length > 1 && cPath[length] != '\0' && cPath[length] != '/') {
            continue;
        }
        const BOOL mountIsLocal = (mounts[i].f_flags & MNT_LOCAL) != 0;
        if (length == bestLength) {
            /* Two mount points differ only in case: keep the cautious answer. */
            isLocal = isLocal && mountIsLocal;
            continue;
        }
        bestLength = length;
        isLocal = mountIsLocal;
    }
    return isLocal;
}
