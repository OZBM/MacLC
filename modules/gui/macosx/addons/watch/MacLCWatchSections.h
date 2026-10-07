/*****************************************************************************
 * MacLCWatchSections.h: Home, Movies and TV Shows, made of what the
 * installed add-ons list, and the title page
 *****************************************************************************
 * Copyright (C) 2026 Hazen Studio
 *
 * This program is free software; you can redistribute it and/or modify it
 * under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation; either version 2.1 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin Street, Fifth Floor, Boston MA 02110-1301, USA.
 *****************************************************************************/

/* Sidebar (medialib/shell/MacLCLibrarySidebarViewController):
 *   Watch ───────────────
 *     Home        play.tv
 *     Movies      film.stack
 *     TV Shows    tv
 *   Library ─────────────  (the media library, unchanged)
 * Each row is a section of the library window (MacLCLibraryRouter keeps one
 * section view controller per class, so each keeps its scroll position and
 * navigation stack). Watch needs no media library. */
#import "medialib/sections/MacLCLibrarySectionViewController.h"

@class MacLCAddonItem;
@class MacLCAddonTitleCatalog;

NS_ASSUME_NONNULL_BEGIN

/// Base of the three Watch sections. Root: a MacLCWatchBrowseViewController
/// for the section's media type. Title: "Home" / "Movies" / "TV Shows";
/// no view modes, no sort menu; search placeholder "Search Movies and TV
/// Shows" (Home), "Search Movies", "Search TV Shows".
@interface MacLCWatchSectionViewController : MacLCLibrarySectionViewController
/// nil (every type), @"movie" or @"series".
@property (readonly, copy, nullable) NSString *mediaType;
/// Pushes the title page. showStreams: open the stream picker as soon as the
/// streams are known (the carousel's Play).
- (void)showDetailForItem:(MacLCAddonItem *)item showStreams:(BOOL)showStreams;
/// A picture fills the top, under the toolbar (carousel, title page): the
/// router hides the window title then, which would sit on the picture
/// (toolbars.md: "If titling a toolbar seems redundant, you can leave the
/// title area empty"); the sidebar still shows where people are.
@property (readonly) BOOL showsPictureUnderToolbar;
/// Developer hook (MACLC_DEBUG_WATCH): once the carousel has its titles,
/// push the first one's page (and its stream picker when showStreams).
- (void)debugOpenFirstFeaturedShowingStreams:(BOOL)showStreams;
@end

/// VLCLibraryWatchHomeSegmentType, every type.
@interface MacLCWatchHomeSectionViewController : MacLCWatchSectionViewController
- (instancetype)init;
@end
/// VLCLibraryWatchMoviesSegmentType, @"movie".
@interface MacLCWatchMoviesSectionViewController : MacLCWatchSectionViewController
- (instancetype)init;
@end
/// VLCLibraryWatchShowsSegmentType, @"series".
@interface MacLCWatchShowsSectionViewController : MacLCWatchSectionViewController
- (instancetype)init;
@end

/// The root of a Watch section: one NSCollectionView (compositional layout,
/// MacLCWatchLayout) in a scroll view filling the view, top content inset 0
/// so the carousel goes under the toolbar.
///
/// Sections, top to bottom:
/// 1. The carousel (MacLCWatchHeroView): 6 titles taken in turn from the
///    catalogs whose identifier is "top" among the section's catalogs
///    (Home: popular movies and popular shows alternating);
///    eyebrows "POPULAR MOVIE" / "POPULAR TV SHOW" (catalog name + type,
///    uppercased).
/// 2. One shelf per title catalog of the section's type
///    (MacLCAddonStore.titleCatalogs), in order. A catalog whose identifier
///    is "top" is shown ranked as "Top 10 Movies" / "Top 10 TV Shows" (its
///    first 10 titles); others are "<name> <type plural>": "New Movies",
///    "Featured TV Shows". Catalogs of other add-ons than the first add title
///    "<name> <type plural>" and subtitle the add-on's name. Each shelf
///    header has "See All" pushing MacLCWatchCatalogViewController.
/// 3. Movies and TV Shows only: genre shelves, "Popular in <Genre>" for each
///    genre option of the section's "top" catalog (Cinemeta: Action,
///    Adventure... 19), loaded lazily when about to scroll into view (prefetch
///    two shelves ahead), each with See All.
/// Loading: every shelf shows 8 placeholder posters (quaternarySystemFill,
/// no text) until its page arrives; a failed shelf disappears, unless all
/// fail: then the empty state (medialib/components/MacLCEmptyStateView)
/// "Can't Load Add-ons" with the error text (same wording rules as
/// MacLCAddonSearchWindowController's getErrorTitle:) and "Try Again". No
/// browsable catalog at all: "No Catalogs" / "Install an add-on with catalogs
/// to see movies and shows here." / "Browse Add-ons…" (opens Settings ▸
/// Add-ons). Reloads on MacLCAddonsDidChangeNotification.
/// Search (the section's search field): two or more characters replace the
/// shelves with a poster grid of MacLCAddonStore searchTitles: results of the
/// section's type, headed per catalog ("Movies", "TV Shows"), 300 ms debounce;
/// "No Results for “x”" empty state; "" restores the shelves and their scroll
/// position.
/// Activating a poster calls section showDetailForItem:showStreams:NO; the
/// carousel's Details too, its Play with showStreams:YES.
@interface MacLCWatchBrowseViewController : NSViewController
- (instancetype)initWithSection:(MacLCWatchSectionViewController *)section;
- (void)applySearchString:(NSString *)searchString;
/// The carousel's titles once loaded (empty before); for the debug hook.
@property (readonly, copy) NSArray<MacLCAddonItem *> *featuredItems;
/// The carousel is at the top (not searching, no empty state); changes call
/// the section's -chromeDidChange.
@property (readonly) BOOL showsPictureAtTop;
/// Called once, on the main queue, when featuredItems is first non-empty.
@property (nonatomic, copy, nullable) void (^featuredItemsLoadedHandler)(void);
@end

/// "See All": a poster grid of one catalog (and genre), pushed on the
/// section. Title header in the content ("Popular in Sci-Fi", title1 bold);
/// pages of the catalog appended as the last row comes into view (skip =
/// items so far) while the add-on keeps answering with new titles (stop on
/// an empty page or a page of titles already shown).
@interface MacLCWatchCatalogViewController : NSViewController
- (instancetype)initWithSection:(MacLCWatchSectionViewController *)section
                        catalog:(MacLCAddonTitleCatalog *)catalog
                          genre:(nullable NSString *)genre
                          title:(NSString *)title;
@end

/// The title page (the Apple TV app's movie and show pages), pushed on the
/// section; Back pops it.
///
/// Header, filling the top 75 % of the view's height (clamped 420-720 pt):
/// the background picture (meta.backgroundURL, else the item's), aspect
/// fill, extended under the sidebar and toolbar (NSBackgroundExtensionView),
/// with the carousel's scrims; bottom-leading, 40 pt insets, white: the logo
/// (else the name as largeTitle bold), the facts line
/// (MacLCWatchFactsLine), the description (body, 4 lines; when truncated a
/// "More" button opens a popover with the whole text), the details line
/// "2026 · 1 h 41 min · ★ 7.8 IMDb" (callout, white 75 %), then the buttons:
/// "Play" (play.fill, glass, prominent) — for a show "Play S1, E1" naming
/// the episode it plays (first episode of the lowest season ≥ 1) —, and
/// "Trailer" (film, glass) when the meta has one (plays
/// https://www.youtube.com/watch?v=<id>). Bottom-trailing, at most 320 wide:
/// "Starring <cast, 3>" and "Director <name>" (subheadline, white 75 % labels,
/// white names).
/// Below, scrolling with the header (one NSScrollView, content layer):
/// - shows: a season pop-up ("Season 1", NSPopUpButton, pull-down style off,
///   "Specials" for season 0, listed last) above an episode shelf
///   (MacLCWatchEpisodeItem, MacLCWatchLayout episodeShelf) of that season;
///   activating an episode opens the stream picker for it;
/// - "About": the description in full (body), with "Genres", "Released",
///   "Runtime", "Rating" in a two-column grid of small labels.
/// Loading: the item's own fields show at once; meta fills the rest; a meta
/// error keeps the page with a "Can't load episodes" inline message and Try
/// Again for shows.
///
/// Stream picker: an NSPopover (transient, preferred edge max-Y) anchored to
/// the Play button or the activated episode card, 420 × up to 480 pt:
/// header "<Title>" / "S1, E2 · <episode>" for an episode; then the streams of
/// every add-on providing streams (MacLCAddonStore fetchStreamsForType:...),
/// grouped by add-on name, each row: quality badges (stream.qualityTokens,
/// capsules as in the search window), headline (1 line), details (secondary,
/// 2 lines); rows arrive as add-ons answer, a spinner row while any is
/// pending. The first row is selected; Return, a double-click or "Play"
/// (prominent, bottom-trailing) plays it, "Add to Queue" queues it; Escape
/// closes. No add-on provides streams: "No Streams Add-on" / "Install an
/// add-on that provides streams to play titles." / "Browse Add-ons…" (opens
/// Settings ▸ Add-ons). None found: "No Streams Found". Playing: an
/// VLCOpenInputMetadata with MRLString = stream.MRL and itemName =
/// MacLCAddonStore itemNameForItem:video:, added to the play queue with
/// startPlayback YES (as -[MacLCAddonSearchWindowController playAction:]).
@interface MacLCWatchDetailViewController : NSViewController
- (instancetype)initWithItem:(MacLCAddonItem *)item showStreams:(BOOL)showStreams;
@property (readonly) MacLCAddonItem *item;
@end

NS_ASSUME_NONNULL_END
