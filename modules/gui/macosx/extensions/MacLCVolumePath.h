/*****************************************************************************
 * MacLCVolumePath.h: whether a path lives on a local volume
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

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * Whether a file system path sits on a locally attached volume.
 *
 * Reading a file's attributes on a network volume that has become unreachable
 * blocks until the mount times out, which freezes the interface when it
 * happens while drawing a row. This answer comes from the mount table alone
 * (getmntinfo with MNT_NOWAIT) and never touches the volume, so it is safe to
 * ask on the main thread.
 *
 * A path that matches no mount point, or an empty one, counts as not local.
 */
BOOL MacLCPathIsOnLocalVolume(NSString *_Nullable path);

NS_ASSUME_NONNULL_END
