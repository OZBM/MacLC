/*****************************************************************************
 * MacLCLibraryGridSection.h: a section showing one library list
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

#import "medialib/sections/MacLCLibrarySectionViewController.h"

#import "medialib/components/MacLCMediaCardItem.h"
#import "medialib/components/MacLCTrackListController.h"

NS_ASSUME_NONNULL_BEGIN

/// Sort keys a section can offer (sortOptions).
extern NSString * const MacLCSortKeyTitle;
extern NSString * const MacLCSortKeyDuration;
extern NSString * const MacLCSortKeyLastPlayed;
extern NSString * const MacLCSortKeyYear;
extern NSString * const MacLCSortKeyArtist;

/// The body of Videos, Shows, Artists, Albums, Songs, Genres and Playlists:
/// one MacLCLibraryStore list as a grid (MacLCLibraryGridViewController)
/// and/or a list (MacLCTrackListController), the count as subtitle, a
/// persistent sort menu, an empty state, and details pushed for containers.
@interface MacLCLibraryGridSection : MacLCLibrarySectionViewController

- (instancetype)initWithSegmentType:(NSInteger)segmentType
                              title:(NSString *)title
                         collection:(MacLCLibraryCollection)collection
                              shape:(MacLCArtworkShape)shape
                      subtitleStyle:(MacLCCardSubtitleStyle)subtitleStyle;

/// "video" / "videos" for the "38 videos" subtitle.
- (void)setCountNounSingular:(NSString *)singular plural:(NSString *)plural;
- (void)setEmptyStateSymbolName:(NSString *)symbolName title:(NSString *)title message:(nullable NSString *)message;
- (void)setEmptyStateActionTitle:(nullable NSString *)title handler:(nullable void (^)(void))handler;

/// Builds the detail pushed when a container is opened. nil: items play.
@property (nonatomic, copy, nullable) NSViewController * _Nullable (^detailFactory)(id<VLCMediaLibraryItemProtocol> item);

/// List columns; 0 means no list mode.
@property (nonatomic) MacLCTrackListColumns listColumns;
/// The list is the only presentation (Songs).
@property (nonatomic) BOOL listOnly;

/// Sort keys in menu order (MacLCSortKey...); the first is the default.
@property (nonatomic, copy) NSArray<NSString *> *sortOptions;

@end

NS_ASSUME_NONNULL_END
