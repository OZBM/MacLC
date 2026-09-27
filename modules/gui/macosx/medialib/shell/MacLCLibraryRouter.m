/*****************************************************************************
 * MacLCLibraryRouter.m: shows native library sections in the library window
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

#import "medialib/shell/MacLCLibraryRouter.h"

#import "extensions/NSString+Helpers.h"

#import "library/VLCLibraryDataTypes.h"
#import "library/VLCLibrarySegment.h"
#import "library/VLCLibraryWindow.h"

#import "main/VLCMain.h"

#import "medialib/sections/MacLCLibrarySections.h"
#import "medialib/sections/MacLCLibrarySectionViewController.h"

NSNotificationName const MacLCLibraryRouterSectionDidChangeNotification =
    @"MacLCLibraryRouterSectionDidChangeNotification";

// One router per library window, keyed by window pointer (value-wrapped).
static NSMapTable<NSValue *, MacLCLibraryRouter *> *sRouterTable;

@interface MacLCLibraryRouter ()
{
    // Keyed by section class name → section view controller.
    NSMutableDictionary<NSString *, MacLCLibrarySectionViewController *> *_sections;
    NSInteger _currentSegmentType;
}
@end

@implementation MacLCLibraryRouter

#pragma mark - Factory

+ (instancetype)routerForLibraryWindow:(VLCLibraryWindow *)libraryWindow
{
    NSParameterAssert(libraryWindow != nil);
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sRouterTable = [NSMapTable weakToStrongObjectsMapTable];
    });
    NSValue * const key = [NSValue valueWithNonretainedObject:libraryWindow];
    MacLCLibraryRouter *router = [sRouterTable objectForKey:key];
    if (router == nil) {
        router = [[MacLCLibraryRouter alloc] initWithLibraryWindow:libraryWindow];
        [sRouterTable setObject:router forKey:key];
    }
    return router;
}

#pragma mark - Segment type → section class mapping

+ (BOOL)handlesSegmentType:(NSInteger)segmentType
{
    switch (segmentType) {
        case VLCLibraryHomeSegmentType:
        case VLCLibraryFavoritesSegmentType:
        case VLCLibraryVideoSegmentType:
        case VLCLibraryMoviesVideoSubSegmentType:
        case VLCLibraryShowsVideoSubSegmentType:
        case VLCLibraryMusicSegmentType:
        case VLCLibraryArtistsMusicSubSegmentType:
        case VLCLibraryAlbumsMusicSubSegmentType:
        case VLCLibrarySongsMusicSubSegmentType:
        case VLCLibraryGenresMusicSubSegmentType:
        case VLCLibraryPlaylistsSegmentType:
        case VLCLibraryPlaylistsMusicOnlyPlaylistsSubSegmentType:
        case VLCLibraryPlaylistsVideoOnlyPlaylistsSubSegmentType:
        case VLCLibraryGroupsSegmentType:
        case VLCLibraryGroupsGroupSubSegmentType:
            return YES;
        default:
            return NO;
    }
}

/// Returns the section view controller class for a segment type. Segments that
/// share a section (e.g. Video and Movies → Videos) map to the same class.
+ (Class)sectionClassForSegmentType:(NSInteger)segmentType
{
    switch (segmentType) {
        case VLCLibraryHomeSegmentType:
            return MacLCLibraryHomeViewController.class;
        case VLCLibraryVideoSegmentType:
        case VLCLibraryMoviesVideoSubSegmentType:
        case VLCLibraryGroupsSegmentType:
        case VLCLibraryGroupsGroupSubSegmentType:
            return MacLCLibraryVideosViewController.class;
        case VLCLibraryShowsVideoSubSegmentType:
            return MacLCLibraryShowsViewController.class;
        case VLCLibraryMusicSegmentType:
        case VLCLibraryAlbumsMusicSubSegmentType:
            return MacLCLibraryAlbumsViewController.class;
        case VLCLibraryArtistsMusicSubSegmentType:
            return MacLCLibraryArtistsViewController.class;
        case VLCLibrarySongsMusicSubSegmentType:
            return MacLCLibrarySongsViewController.class;
        case VLCLibraryGenresMusicSubSegmentType:
            return MacLCLibraryGenresViewController.class;
        case VLCLibraryPlaylistsSegmentType:
        case VLCLibraryPlaylistsMusicOnlyPlaylistsSubSegmentType:
        case VLCLibraryPlaylistsVideoOnlyPlaylistsSubSegmentType:
            return MacLCLibraryPlaylistsViewController.class;
        case VLCLibraryFavoritesSegmentType:
            return MacLCLibraryFavoritesViewController.class;
        default:
            return nil;
    }
}

#pragma mark - Init

- (instancetype)initWithLibraryWindow:(VLCLibraryWindow *)libraryWindow
{
    self = [super initWithLibraryWindow:libraryWindow];
    if (self) {
        _sections = [NSMutableDictionary dictionary];
        _currentSegmentType = VLCLibraryLowSentinelSegment;

        NSNotificationCenter * const nc = NSNotificationCenter.defaultCenter;
        [nc addObserver:self
               selector:@selector(sectionChromeDidChange:)
                   name:MacLCLibrarySectionChromeDidChangeNotification
                 object:nil];
    }
    return self;
}

- (void)dealloc
{
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

#pragma mark - Segment presentation

- (void)presentSegmentType:(NSInteger)segmentType
{
    Class const sectionClass = [MacLCLibraryRouter sectionClassForSegmentType:segmentType];
    if (sectionClass == Nil) {
        return;
    }

    _currentSegmentType = segmentType;

    /* One instance per section class: Video, Movies and Groups share the
     * Videos section, so its scroll position and stack survive either. Each
     * section configures itself in -init. */
    NSString * const key = NSStringFromClass(sectionClass);
    MacLCLibrarySectionViewController *section = _sections[key];
    if (section == nil) {
        section = [[sectionClass alloc] init];
        _sections[key] = section;
    }
    _currentSection = section;

    // Show the section's view in the library window's content area.
    [self.libraryWindow displayLibraryView:section.view];

    [self updateWindowChromeFromSection:section];

    [NSNotificationCenter.defaultCenter
        postNotificationName:MacLCLibraryRouterSectionDidChangeNotification
                      object:self];
}

- (void)showPlaylist:(VLCMediaLibraryPlaylist *)playlist
{
    // Switch to the Playlists section and push the playlist detail.
    self.libraryWindow.librarySegmentType = VLCLibraryPlaylistsSegmentType;
    [self presentSegmentType:VLCLibraryPlaylistsSegmentType];
    [_currentSection showItem:(id<VLCMediaLibraryItemProtocol>)playlist];
}

#pragma mark - VLCLibraryItemPresentingCapable

- (void)presentLibraryItem:(id<VLCMediaLibraryItemProtocol>)libraryItem
{
    if (_currentSection != nil) {
        [_currentSection showItem:libraryItem];
    }
}

#pragma mark - Chrome

- (void)updateWindowChromeFromSection:(MacLCLibrarySectionViewController *)section
{
    self.libraryWindow.title = section.sectionTitle ?: @"";
    self.libraryWindow.subtitle = section.sectionSubtitle ?: @"";
}

- (void)sectionChromeDidChange:(NSNotification *)notification
{
    MacLCLibrarySectionViewController * const section = notification.object;
    if (section == _currentSection) {
        [self updateWindowChromeFromSection:section];
    }
}

@end
