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
@class MacLCWatchCollection;

NS_ASSUME_NONNULL_BEGIN

/// Base of the three Watch sections. Root: a MacLCWatchBrowseViewController
/// for the section's media type. Title: "Home" / "Movies" / "TV Shows";
/// no view modes, no sort menu; search placeholder "Search Movies and TV
/// Shows" (Home), "Search Movies", "Search TV Shows".
@interface MacLCWatchSectionViewController : MacLCLibrarySectionViewController
/// For subclasses in other files (Favorites and History,
/// MacLCWatchLibrarySections.h).
- (instancetype)initWithMediaType:(nullable NSString *)mediaType segmentType:(NSInteger)segmentType;
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
/// Sections, top to bottom (Home, Movies, TV Shows; Watch is about finding
/// tonight's film, so the page reads: what's hot → narrow it down → be
/// inspired → browse):
/// 1. The carousel (MacLCWatchHeroView): 6 titles taken in turn from the
///    catalogs whose identifier is "top" among the section's catalogs
///    (Home: popular movies and popular shows alternating);
///    eyebrows "POPULAR MOVIE" / "POPULAR TV SHOW" (catalog name + type,
///    uppercased). With a service selected: the first 6 titles of that
///    service's catalog(s), eyebrow "POPULAR ON NETFLIX". The carousel gets
///    -setScrollOffset: on every clip view bounds change (parallax and
///    stretch).
/// 2. The services bar (MacLCWatchServiceBar, MacLCWatchLayout
///    insetBarSectionWithHeight:), always shown. Selecting a service
///    re-scopes the WHOLE page to it, in place, without pushing: the
///    carousel, then "Top on <Service>" (its catalog for the section's
///    type(s), first 20, ranked as Top 10 for the first 10), then one shelf
///    per genre present in that catalog ("<Service> · Comedy", client-side,
///    MacLCWatchDiscovery items:matchingGenre:, genres with at least 4
///    titles, in the genre order), The Edit and the genre tiles are hidden
///    while scoped. "All" restores the normal page and its scroll position.
///    The selection is remembered per section in NSUserDefaults
///    "MacLCWatchService.<section title>". The page fades (0.2 s) between
///    scopes; no motion under Reduce Motion. "Choose Services…" opens
///    MacLCWatchServicesSheetController on the window.
/// 3. The Edit (Home: 3 collections of any type; Movies: 3 "movie"; TV
///    Shows: 3 "series"; MacLCWatchDiscovery editForDate:now): a shelf
///    "The Edit" with subtitle "New collections every two weeks · Next on
///    Oct 20" (date: nextEditDateAfter:, NSDateFormatter "MMM d" template)
///    and info button (topic Collections), items MacLCWatchCollectionCard,
///    layout collectionShelfSectionWithEnvironment:. Each card resolves its
///    collection when it is about to be shown (resolveCollection:) and
///    updates its posters. Activating a card pushes
///    MacLCWatchCollectionViewController.
/// 4. Top 10 (the "top" catalog, ranked, as before).
/// 5. "Browse by Genre": genre tiles (MacLCWatchGenreTile,
///    genreShelfSectionWithEnvironment:) for the section's genres
///    (genresForMediaType:; Home: movie genres), each with 2 posters taken
///    from shelves already loaded (titles whose genres contain it), else
///    none. Activating a tile pushes MacLCWatchCatalogViewController for the
///    "top" catalog and that genre, titled "<Genre> Movies" / "<Genre>
///    Shows" (Home: movies).
/// 6. One shelf per title catalog of the section's type
///    (MacLCAddonStore.titleCatalogs), in order, except the "top" one
///    already shown: "<name> <type plural>": "New Movies", "Featured TV
///    Shows". Catalogs of other add-ons than the first add title "<name>
///    <type plural>" and subtitle the add-on's name. Catalogs of the
///    services add-on are NOT shown here (they are what the services bar
///    scopes to). Each shelf header has "See All" pushing
///    MacLCWatchCatalogViewController.
/// 7. Movies and TV Shows only: genre shelves, "Popular in <Genre>" for each
///    genre option of the section's "top" catalog (Cinemeta: Action,
///    Adventure... 19), loaded lazily when about to scroll into view (prefetch
///    two shelves ahead), each with See All.
/// Every horizontal shelf uses MacLCWatchShelfHeaderView (paging chevrons,
/// state updated when its embedded scroll view's clip bounds change) and
/// MacLCWatchShelfScrolling: no scrollers, configured in
/// collectionView:willDisplayItem:forRepresentedObjectAtIndexPath:.
/// Loading: every shelf shows 8 placeholder posters (quaternarySystemFill,
/// no text) until its page arrives; a failed shelf disappears, unless all
/// fail: then the empty state (medialib/components/MacLCEmptyStateView)
/// "Can't Load Add-ons" with the error text (same wording rules as
/// MacLCAddonSearchWindowController's getErrorTitle:) and "Try Again". No
/// browsable catalog at all: "No Catalogs" / "Install an add-on with catalogs
/// to see movies and shows here." / "Browse Add-ons…" (opens Settings ▸
/// Add-ons). Reloads on MacLCAddonsDidChangeNotification and
/// MacLCWatchDiscoveryDidChangeNotification.
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

/// A collection of The Edit, pushed on the section: a vertical scroll of the
/// MacLCWatchCollectionHeaderView (eyebrow "THE EDIT · UNTIL <last day of
/// its period, MMM d>") then a poster grid (posterGridSectionWithEnvironment:
/// hasHeader:NO) of the resolved items in the pool's order. Loading: the header shows at once with placeholder
/// posters; the grid fills when resolveCollection: completes; nothing
/// matched: MacLCEmptyStateView "Nothing to Show Yet" / "None of these
/// titles were found in your catalog add-ons.".
@interface MacLCWatchCollectionViewController : NSViewController
- (instancetype)initWithSection:(MacLCWatchSectionViewController *)section
                     collection:(MacLCWatchCollection *)collection;
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
/// Streams: Play (or an episode card) opens "Choose a Version", the sheet
/// MacLCStreamPickerController (addons/watch/MacLCStreamPicker.h) on the
/// window, for the item and the episode. The old popover is gone.
@interface MacLCWatchDetailViewController : NSViewController
- (instancetype)initWithItem:(MacLCAddonItem *)item showStreams:(BOOL)showStreams;
@property (readonly) MacLCAddonItem *item;
@end

NS_ASSUME_NONNULL_END
