/*****************************************************************************
 * MacLCResumePosition.h: which playback positions are worth resuming
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

#import <vlc_common.h>
#import <vlc_tick.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * A media's duration in milliseconds, the unit the functions below expect:
 * the input item's, counted in ticks, when the input knows it, else the media
 * library's, kept in milliseconds and unknown (-1) for a file the library has
 * only seen played. 0 or less when neither knows it.
 */
int64_t MacLCMediaDurationInMilliseconds(vlc_tick_t inputItemDuration,
                                         int64_t libraryDurationMs);

/**
 * Whether playback can resume at a position, which is also the test for
 * remembering one: the media lasts at least three minutes, and the position
 * lies inside it, past its first minute or first 5 % (whichever is shorter)
 * and before its last minute or last 5 % (whichever is shorter).
 *
 * A position at or past the end never qualifies. That is what the media
 * library keeps for a file played to its last frame when it does not know the
 * file's duration, and what a time counted across repeated passes of a media
 * would amount to. Nothing qualifies while the duration is unknown, since the
 * position cannot be checked then.
 *
 * @param position the position in the media, from 0 (start) to 1 (end)
 * @param durationMs the media's duration in milliseconds, 0 or less when unknown
 */
BOOL MacLCCanResumeAtPosition(double position, int64_t durationMs);

/**
 * The time in whole seconds at which playback resumes for a position, or -1
 * when MacLCCanResumeAtPosition() refuses the position.
 *
 * @param position the position in the media, from 0 (start) to 1 (end)
 * @param durationMs the media's duration in milliseconds, 0 or less when unknown
 */
int64_t MacLCResumeTimeInSeconds(double position, int64_t durationMs);

NS_ASSUME_NONNULL_END
