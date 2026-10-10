/*****************************************************************************
 * VLCPlaybackProgressSliderCell.h
 *****************************************************************************
 * Copyright (C) 2017 VLC authors and VideoLAN
 *
 * Authors: Marvin Scholz <epirat07 at gmail dot com>
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

#import <Cocoa/Cocoa.h>

@interface VLCPlaybackProgressSliderCell : NSSliderCell

@property (readwrite, nonatomic) BOOL indefinite;
@property (readwrite, nonatomic) BOOL knobHidden;
/// Pointer over the scrubber: the track thickens and the knob appears.
@property (readwrite, nonatomic) BOOL hovered;

/// A torrent being played: the parts of the file already on disk, as
/// flattened fractions [s0, e0, s1, e1, ...] of the whole (0...1), drawn
/// between the empty track and the played fill.
@property (readwrite, nonatomic, copy, nullable) NSArray<NSNumber *> *downloadedRanges;
/// Where the download has reached in front of the playhead, 0...1; < 0 for none.
@property (readwrite, nonatomic) double downloadHead;
/// YES while data is still coming in: the head glows and pulses (a still
/// head under Reduce Motion). Done (head >= 0.999) or NO: the ranges only.
@property (readwrite, nonatomic) BOOL downloading;

- (void)setSliderStyleLight;
- (void)setSliderStyleDark;

@end
