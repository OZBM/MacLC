/*****************************************************************************
 * MacLCYouTubeSections.h: the YouTube section of the library window: Home,
 * Subscriptions, History, Watch Later, Liked Videos, Playlists, and the
 * pages they open (channel, playlist, video)
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

/* Sidebar (medialib/shell/MacLCLibrarySidebarViewController), a group after
 * Watch, as YouTube's own left rail:
 *   YouTube ─────────────
 *     Home            house
 *     Subscriptions   play.square.stack
 *     History         clock.arrow.circlepath
 *     Watch Later     clock
 *     Liked Videos    hand.thumbsup
 *     Playlists       list.and.film
 * The segment types (VLCLibraryYouTube...SegmentType), the router mapping and
 * the rows are wired by the lead; the classes below only have to exist. Each
 * section keeps its own navigation stack (MacLCLibrarySectionViewController).
 *
 * Every root (MacLCYouTubeFeedViewController) has, at the top of its content
 * (scrolling with it):
 *  - a header row: the section's title (MacLCDesign.largeTitle, bold) and,
 *    trailing, MacLCYouTubeAccountButton;
 *  - Home only: MacLCYouTubeChipsBar with MacLCYouTubeCategory homeCategories
 *    ("All" selected; the choice is kept for the launch, not saved);
 *  - then the content: a video grid (videos) or a playlist grid (Playlists).
 *    Lists load 36 entries, then 36 more each time the last row comes into
 *    view while page.mayHaveMore (ask limit 72, 108... and append what is new).
 *  - loading: 12 placeholder cards (thumbnail fill, two grey text bars), no
 *    spinner; errors and states use MacLCEmptyStateView:
 *      extractor missing: symbol "exclamationmark.triangle", "yt-dlp Is Needed",
 *        "MacLC uses the free yt-dlp tool to read YouTube. Install it with
 *        Homebrew (brew install yt-dlp), then try again.", buttons "Try Again",
 *        "Copy Install Command";
 *      sign-in required (the account feeds while signed out, or cookies
 *        refused): symbol "person.crop.circle", "Sign In to See Your
 *        <Subscriptions | History | Watch Later | Liked Videos | Playlists |
 *        Recommendations>", "MacLC shows your own YouTube when you sign in
 *        with Google.", buttons "Sign In with Google…" (prominent) and "Use
 *        Browser Session…" (the account button's browser menu);
 *      network: "Can't Reach YouTube" + the error text + "Try Again";
 *      empty: "Nothing Here Yet".
 *  - The section's search field (toolbar, placeholder "Search YouTube") searches
 *    YouTube from any YouTube section: 2+ characters, 600 ms after the last
 *    keystroke (Return: at once), the content becomes the results: chips
 *    "All · Videos · Channels · Playlists" (MacLCYouTubeSearchFilter) above
 *    rows (MacLCYouTubeResultRowItem); "" restores the section's content and
 *    its scroll position. Requests in flight are cancelled when replaced.
 * Activation: a video plays (MacLCYouTubeActions playVideo:...); a channel
 * pushes MacLCYouTubeChannelViewController; a playlist pushes
 * MacLCYouTubePlaylistViewController; "Show Details" pushes
 * MacLCYouTubeVideoViewController. Everything reloads on
 * MacLCYouTubeAccountDidChangeNotification.
 * Developer hook: MACLC_DEBUG_YOUTUBE=home|subscriptions|history|watchlater|
 * liked|playlists[:search=<query>|:channel=<url>|:playlist=<url>|:video=<id>]
 * selects the section at launch and opens that page (wired in VLCMain.m by the
 * lead; the sections provide -debugOpen: below). */
#import "medialib/sections/MacLCLibrarySectionViewController.h"

#import "youtube/MacLCYouTubeService.h"

NS_ASSUME_NONNULL_BEGIN

/// Base of the six sections. sectionTitle: the root's title, or the pushed
/// page's title; search placeholder "Search YouTube"; no view modes, no sort.
@interface MacLCYouTubeSectionViewController : MacLCLibrarySectionViewController
/// YES for Home (its content is not an account feed when signed out).
@property (readonly, getter=isHome) BOOL home;
/// The account feed shown at the root (meaningless for Home).
@property (readonly) MacLCYouTubeFeed feed;
- (void)showChannelWithURL:(NSURL *)channelURL name:(nullable NSString *)name;
- (void)showPlaylist:(MacLCYouTubePlaylist *)playlist;
- (void)showDetailsForVideo:(MacLCYouTubeVideo *)video;
/// The developer hook's page: "search=<q>", "channel=<url>", "playlist=<url>",
/// "video=<id>"; ignored when not understood.
- (void)debugOpen:(NSString *)page;
@end

@interface MacLCYouTubeHomeSectionViewController : MacLCYouTubeSectionViewController
- (instancetype)init;
@end
@interface MacLCYouTubeSubscriptionsSectionViewController : MacLCYouTubeSectionViewController
- (instancetype)init;
@end
@interface MacLCYouTubeHistorySectionViewController : MacLCYouTubeSectionViewController
- (instancetype)init;
@end
@interface MacLCYouTubeWatchLaterSectionViewController : MacLCYouTubeSectionViewController
- (instancetype)init;
@end
@interface MacLCYouTubeLikedSectionViewController : MacLCYouTubeSectionViewController
- (instancetype)init;
@end
@interface MacLCYouTubePlaylistsSectionViewController : MacLCYouTubeSectionViewController
- (instancetype)init;
@end

/// The root of a section (see the file comment).
@interface MacLCYouTubeFeedViewController : NSViewController
- (instancetype)initWithSection:(MacLCYouTubeSectionViewController *)section;
- (void)applySearchString:(NSString *)searchString;
@end

/// A channel: the banner (when there is one: full width minus insets, 16:3,
/// corner radius 16), then the avatar (88 pt circle), name (title1 bold) +
/// seal, "@handle · 577K subscribers" (secondaryLabel), description (2 lines,
/// "more" opens a popover with all of it), then a segmented control "Videos ·
/// Live · Playlists" (MacLCYouTubeChannelTab) and the tab's grid (cards with
/// showsChannel NO, or playlist tiles). Title: the channel's name. Paging as
/// the roots.
@interface MacLCYouTubeChannelViewController : NSViewController
- (instancetype)initWithSection:(MacLCYouTubeSectionViewController *)section
                     channelURL:(NSURL *)channelURL
                           name:(nullable NSString *)name;
@end

/// A playlist: header with its thumbnail (360 wide, 16:9), title (title1
/// bold), channel name, "24 videos", buttons "Play All" (play.fill,
/// prominent) and "Shuffle" (shuffle), then the videos as numbered rows
/// (index, 160 × 90 thumbnail, title, channel, duration) in one column.
/// Activating a row plays from it (MacLCYouTubeService playVideos:
/// startingAtIndex:). Title: the playlist's title.
@interface MacLCYouTubePlaylistViewController : NSViewController
- (instancetype)initWithSection:(MacLCYouTubeSectionViewController *)section
                       playlist:(MacLCYouTubePlaylist *)playlist;
@end

/// A video's page, what YouTube shows under its player: a large thumbnail (16:9,
/// at most 960 wide, corner radius 16) with a centred glass Play button
/// (play.fill, 64 pt) and the duration badge; the title (title1 bold, wraps);
/// a row with the channel (name + seal, subscribers; click opens the channel)
/// and, trailing, "Add to Queue", "Copy Link", "Open in Browser" (glass
/// buttons, symbol + label); a rounded description box (quaternarySystemFill):
/// "1.2M views · 3 days ago · 45K likes" in semibold, then the description,
/// 4 lines with "Show More" / "Show Less", links clickable (NSDataDetector);
/// chapters when there are some, as a horizontal shelf of chips "0:00
/// Intro"... (clicking one plays from there: MacLCYouTubeService playVideo
/// with the chapter's start as "start-time"); then "More from <channel>": a
/// grid of the channel's latest 12 videos. Loads details with
/// detailsForVideo: (what the list gave shows at once). Title: the video's.
@interface MacLCYouTubeVideoViewController : NSViewController
- (instancetype)initWithSection:(MacLCYouTubeSectionViewController *)section
                          video:(MacLCYouTubeVideo *)video;
@end

NS_ASSUME_NONNULL_END
