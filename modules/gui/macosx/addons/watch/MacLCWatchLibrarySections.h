/*****************************************************************************
 * MacLCWatchLibrarySections.h: Favorites and History, the two Watch sections
 * that show what the person saved and what they watched
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
 *     Home          play.tv
 *     Movies        film.stack
 *     TV Shows      tv
 *     Favorites     heart          <- here (VLCLibraryWatchFavoritesSegmentType)
 *     History       clock          <- here (VLCLibraryWatchHistorySegmentType)
 * The segment types, the router mapping and the sidebar rows are wired by the
 * lead; the classes below only have to exist.
 *
 * Both are MacLCWatchSectionViewController subclasses: a title opens the title
 * page (-showDetailForItem:showStreams:), Back pops it, the toolbar's search
 * field filters the list in memory (as you type, case and diacritic
 * insensitive on the title). Neither needs any add-on or network: they read
 * MacLCWatchLibrary, and redraw on MacLCWatchLibraryDidChangeNotification
 * (only when the changed titles are shown, or the set is absent).
 *
 * FAVORITES (VLCLibraryWatchFavoritesSegmentType, title "Favorites", search
 * placeholder "Search Favorites").
 * Root: a scroll view with a header and a poster grid.
 *  - Header (top of the content, not a toolbar item): a segmented control
 *    "All · Movies · TV Shows" (NSSegmentedControl, selection remembered in
 *    NSUserDefaults "MacLCWatchFavoritesFilter"), and, trailing, the count
 *    ("12 titles", footnote, secondaryLabel).
 *  - Grid: MacLCWatchPosterItem (posterGridSectionWithEnvironment:hasHeader:NO)
 *    of favoriteEntries filtered; most recently added first. Posters show
 *    their watched/progress state like everywhere (MacLCWatchLibraryViews.h).
 *    Context menu: MacLCWatchActions with inHistory:NO.
 *  - Empty (no favorites): MacLCEmptyStateView, symbol "heart", "No Favorites
 *    Yet", "Add movies and shows you want to watch later: tap the heart on a
 *    poster, or on a title's page." No button.
 *  - Empty after the filter or the search: "No Results" (+ for the filter
 *    "No Favorite Movies" / "No Favorite TV Shows").
 *
 * HISTORY (VLCLibraryWatchHistorySegmentType, title "History", search
 * placeholder "Search History").
 * Root: a scroll view with a header and sections of resume cards.
 *  - Header: title area like Favorites with, trailing, a "Clear History…"
 *    button (borderless, destructive role colour only on the confirmation):
 *    an NSAlert sheet "Clear your watch history?" / "Resume points and watched
 *    marks for all movies and shows are removed. Favorites stay." / buttons
 *    "Clear History" (destructive) and "Cancel". Hidden when empty.
 *  - Sections by relative date of lastPlayed, in this order and only when
 *    non-empty: "Today", "Yesterday", "This Week", "This Month", then one per
 *    calendar year or month before ("September", "2025"): header text uses
 *    MacLCSectionHeaderView (kind MacLCWatchHeaderElementKind), items are
 *    MacLCWatchContinueItem with showsLastPlayed NO for Today/Yesterday and YES
 *    otherwise, layout continueGridSectionWithEnvironment:hasHeader:YES.
 *    Items: historyEntries. Activating a card resumes it when it has a resume
 *    target (like Continue Watching), else opens the title page. The "…" menu
 *    and the right-click menu: MacLCWatchActions inHistory:YES.
 *  - Empty: "No History Yet" / "Movies and shows you watch appear here, so you
 *    can pick them up again." symbol "clock".
 *
 * RESUMING from a card (here and on Home, same code path, written once in this
 * file as a function the Home shelf also calls):
 *   void MacLCWatchResumeEntry(MacLCWatchEntry *entry, MacLCWatchSectionViewController *section);
 *   - target kind Resume with a saved stream: -[MacLCWatchPlayback
 *     resumeProgress:item:]; if it answers NO: open the title page with the
 *     stream picker (section showDetailForItem:showStreams:YES).
 *   - target kind NextUp: fetch the meta (MacLCAddonStore fetchMetaForItem:),
 *     find the video, open MacLCStreamPickerController for it as a sheet on the
 *     library window; if the meta cannot be fetched: the title page.
 *   - no target: the title page.
 * (MacLCWatchBrowse.m's Home uses the same function for its Continue Watching
 * shelf, declared below.) */
#import "addons/watch/MacLCWatchSections.h"

@class MacLCWatchEntry;

NS_ASSUME_NONNULL_BEGIN

/// VLCLibraryWatchFavoritesSegmentType.
@interface MacLCWatchFavoritesSectionViewController : MacLCWatchSectionViewController
- (instancetype)init;
@end

/// VLCLibraryWatchHistorySegmentType.
@interface MacLCWatchHistorySectionViewController : MacLCWatchSectionViewController
- (instancetype)init;
@end

/// See the file comment.
void MacLCWatchResumeEntry(MacLCWatchEntry *entry, MacLCWatchSectionViewController *section);

NS_ASSUME_NONNULL_END
