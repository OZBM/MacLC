/*****************************************************************************
 * MacLCResumePosition.m: which playback positions are worth resuming
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

#import "MacLCResumePosition.h"

static const int64_t SecInMillisecs = 1000;
static const int64_t MinInMillisecs = SecInMillisecs * 60;
static const int64_t MinimumDuration = 3 * MinInMillisecs;
static const double MinimumStorePercent = 0.05;
static const double MaximumStorePercent = 0.95;
static const int64_t MinimumStoreTime = MinInMillisecs;
static const int64_t MinimumStoreRemainingTime = MinInMillisecs;

int64_t MacLCMediaDurationInMilliseconds(vlc_tick_t inputItemDuration,
                                         int64_t libraryDurationMs)
{
    if (inputItemDuration > 0) {
        return MS_FROM_VLC_TICK(inputItemDuration);
    }
    return libraryDurationMs;
}

BOOL MacLCCanResumeAtPosition(double position, int64_t durationMs)
{
    /* Written so that a NaN position is refused too. */
    if (!(position > 0. && position < 1.)) {
        return NO;
    }

    if (durationMs < MinimumDuration) {
        return NO;
    }

    const double positionTime = position * durationMs;
    const double remainingTime = durationMs - positionTime;

    if (position < MinimumStorePercent && positionTime < MinimumStoreTime) {
        return NO;
    }

    if (position > MaximumStorePercent && remainingTime < MinimumStoreRemainingTime) {
        return NO;
    }

    return YES;
}

int64_t MacLCResumeTimeInSeconds(double position, int64_t durationMs)
{
    if (!MacLCCanResumeAtPosition(position, durationMs)) {
        return -1;
    }
    return (int64_t)(position * durationMs) / SecInMillisecs;
}
