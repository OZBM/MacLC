/*****************************************************************************
 * MacLCYouTubeViews.h: the building blocks of the YouTube section: video
 * cards, result rows, channel and playlist tiles, topic chips, the account
 * button, layouts
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

/* YouTube's web layout, which people know, made native and calmer: the same
 * grid of 16:9 cards with the duration on the picture and "views · age" under
 * the title, topic chips on top, rows for search results; no ads, no Shorts
 * shelf, no autoplaying previews, larger type, content-layer colours from
 * MacLCDesign (YouTube red only for the LIVE badge), glass only for controls
 * floating over pictures (liquid-glass.md). Every picture goes through
 * MacLCWatchImageCache (addons/watch/MacLCWatchComponents.h): downsampled,
 * cached, cancellable. Every control has an accessibility label and tooltip;
 * hover motion follows Reduce Motion. */
#import <Cocoa/Cocoa.h>

#import "youtube/MacLCYouTubeModel.h"

NS_ASSUME_NONNULL_BEGIN

#pragma mark - Video card

extern NSUserInterfaceItemIdentifier const MacLCYouTubeVideoItemIdentifier;

/// A video in a grid. Top to bottom: the thumbnail (16:9, aspect fill,
/// corner radius 12, quaternarySystemFill + "play.rectangle" placeholder while
/// loading), the duration badge on it (bottom-trailing, 6 pt in: black 78 %
/// capsule, white 12 pt semibold monospaced digits "12:05"; "LIVE" on
/// systemRed with a dot for lives; "UPCOMING" for premieres), 10 pt, the
/// title (15 pt semibold, labelColor, 2 lines, word wrap, truncates the last
/// line), 4 pt, the channel name (13 pt, secondaryLabel, 1 line) followed by
/// checkmark.seal.fill (11 pt) when verified, then the metadata line
/// (MacLCYouTubeFormat metadataLineForVideo:now:, 13 pt, secondaryLabel).
/// Hover: the thumbnail scales 1.03 (spring, as Watch's posters), a glass
/// "Add to Queue" button (text.badge.plus, 28 pt circle) shows at its
/// top-trailing corner; pointing hand. While the video is being opened
/// (-setOpening:YES) a small spinner sits on the thumbnail and clicks are
/// ignored. Activation (click, Return, double-click) calls activationHandler.
/// Right-click: Play, Add to Queue, separator, Show Details, Go to Channel
/// (when there is one), separator, Copy Link, Open in Browser. VoiceOver: one
/// element "<title>, <channel>, <duration>, <metadata>", button role, custom
/// actions for the menu items.
@interface MacLCYouTubeVideoItem : NSCollectionViewItem
- (void)configureWithVideo:(MacLCYouTubeVideo *)video;
@property (readonly, nullable) MacLCYouTubeVideo *video;
/// NO on a channel's own page (the name would repeat).
@property (nonatomic) BOOL showsChannel;
- (void)setOpening:(BOOL)opening;
@property (nonatomic, copy, nullable) void (^activationHandler)(MacLCYouTubeVideo *video);
@property (nonatomic, copy, nullable) void (^enqueueHandler)(MacLCYouTubeVideo *video);
@property (nonatomic, copy, nullable) void (^detailsHandler)(MacLCYouTubeVideo *video);
@property (nonatomic, copy, nullable) void (^channelHandler)(MacLCYouTubeVideo *video);
/// Height for a width: width * 9 / 16 + 10 + two title lines + 4 + two lines.
+ (CGFloat)heightForWidth:(CGFloat)width;
@end

#pragma mark - Search result row

extern NSUserInterfaceItemIdentifier const MacLCYouTubeResultRowItemIdentifier;

/// One search result as a row (YouTube's search list), 16 pt between rows:
/// video: the thumbnail 320 × 180 on the leading side (same badges), then
/// title (17 pt semibold, 2 lines), metadata line, channel name (+ seal),
/// and nothing else (flat results carry no description);
/// channel: a 136 pt avatar circle centred in a 320 wide area, then name
/// (17 pt semibold), handle · subscribers, description (2 lines);
/// playlist: the thumbnail with a translucent bar on its trailing third
/// showing "24 videos" and list.and.film, then title, channel name.
/// Same hover, menu and VoiceOver rules as the card.
@interface MacLCYouTubeResultRowItem : NSCollectionViewItem
- (void)configureWithResult:(MacLCYouTubeResult *)result;
@property (readonly, nullable) MacLCYouTubeResult *result;
- (void)setOpening:(BOOL)opening;
@property (nonatomic, copy, nullable) void (^activationHandler)(MacLCYouTubeResult *result);
@property (nonatomic, copy, nullable) void (^enqueueHandler)(MacLCYouTubeVideo *video);
@property (nonatomic, copy, nullable) void (^detailsHandler)(MacLCYouTubeVideo *video);
@property (nonatomic, copy, nullable) void (^channelHandler)(MacLCYouTubeVideo *video);
+ (CGFloat)rowHeight;
@end

#pragma mark - Channel and playlist tiles

extern NSUserInterfaceItemIdentifier const MacLCYouTubeChannelItemIdentifier;

/// A channel in a shelf: avatar circle (96), name (13 pt semibold, 2 lines,
/// centred), subscribers (12 pt, secondaryLabel). Click: activationHandler.
@interface MacLCYouTubeChannelItem : NSCollectionViewItem
- (void)configureWithChannel:(MacLCYouTubeChannel *)channel;
@property (readonly, nullable) MacLCYouTubeChannel *channel;
@property (nonatomic, copy, nullable) void (^activationHandler)(MacLCYouTubeChannel *channel);
@end

extern NSUserInterfaceItemIdentifier const MacLCYouTubePlaylistItemIdentifier;

/// A playlist in a grid: the thumbnail with two thin "stacked" edges above it
/// (the YouTube look of a collection), the count badge "24 videos"
/// (list.and.film) bottom-trailing, then title (15 pt semibold, 2 lines) and
/// channel name. Click: activationHandler.
@interface MacLCYouTubePlaylistItem : NSCollectionViewItem
- (void)configureWithPlaylist:(MacLCYouTubePlaylist *)playlist;
@property (readonly, nullable) MacLCYouTubePlaylist *playlist;
@property (nonatomic, copy, nullable) void (^activationHandler)(MacLCYouTubePlaylist *playlist);
@end

#pragma mark - Chips

/// YouTube's topic chips: a single row of capsules (32 high, 12 pt
/// horizontal padding, 14 pt medium text, 8 apart) that scrolls sideways
/// without a scroller when it does not fit, with soft fades at the clipped
/// edges. Selected chip: labelColor fill and windowBackgroundColor text; the
/// others quaternarySystemFill and labelColor. Arrow keys move the selection
/// when it has focus. VoiceOver: a radio group.
@interface MacLCYouTubeChipsBar : NSView
@property (nonatomic, copy) NSArray<NSString *> *titles;
@property (nonatomic) NSInteger selectedIndex;
@property (nonatomic, copy, nullable) void (^selectionHandler)(NSInteger index);
@end

#pragma mark - Account

/// The account control at the top-trailing corner of every YouTube page.
/// Signed out: a "Sign In" capsule (person.crop.circle, bordered). Signed
/// in: the avatar (28 pt circle; person.crop.circle.fill when unknown).
/// Click shows a menu:
///   signed out: "Sign In with Google…", "Use <Browser>'s Session" (one item
///   per MacLCYouTubeAccount availableBrowsers, with a short explanation as
///   the item's tooltip), separator, "About Signing In" (an NSAlert that says
///   what is stored: a session cookie file in MacLC's folder, no password).
///   signed in: a disabled title "Signed in with Google" or "Using
///   <Browser>'s session", "Open YouTube in Browser", separator, "Sign Out".
/// Follows MacLCYouTubeAccountDidChangeNotification.
@interface MacLCYouTubeAccountButton : NSButton
@end

#pragma mark - Browser-session error

@class MacLCEmptyStateView;
/// The empty state for MacLCYouTubeErrorBrowserCookies: "Can't Use <Browser>'s
/// Session", a message that depends on the browser (Safari: Full Disk Access;
/// Chromium family: the Keychain prompt), "Sign In with Google…" (prominent;
/// afterSignIn runs once signed in) and, for Safari, "Open Privacy Settings".
/// window: the window to present the sign-in sheet from (may return nil).
FOUNDATION_EXPORT MacLCEmptyStateView *MacLCYouTubeBrowserCookiesStateView(NSWindow * _Nullable (^window)(void),
                                                                          void (^afterSignIn)(void));

#pragma mark - Layouts

@interface MacLCYouTubeLayout : NSObject
/// Leading/trailing insets 24, cards 260-380 wide (as many columns as fit),
/// 16 between columns, 36 between rows; optional header.
+ (NSCollectionLayoutSection *)videoGridSectionWithEnvironment:(id<NSCollectionLayoutEnvironment>)environment
                                                     hasHeader:(BOOL)hasHeader;
/// One full-width row per item (MacLCYouTubeResultRowItem rowHeight), max
/// content width 1100, insets 24.
+ (NSCollectionLayoutSection *)resultListSectionWithEnvironment:(id<NSCollectionLayoutEnvironment>)environment
                                                      hasHeader:(BOOL)hasHeader;
/// A horizontal shelf of channel tiles (120 wide).
+ (NSCollectionLayoutSection *)channelShelfSectionWithEnvironment:(id<NSCollectionLayoutEnvironment>)environment;
/// Playlist tiles: same grid metrics as the video grid.
+ (NSCollectionLayoutSection *)playlistGridSectionWithEnvironment:(id<NSCollectionLayoutEnvironment>)environment
                                                        hasHeader:(BOOL)hasHeader;
@end

#pragma mark - Shared actions

/// What cards, rows and pages do, in one place (play goes through
/// MacLCYouTubeService; errors become a sheet with the resolver's message).
@interface MacLCYouTubeActions : NSObject
/// Plays now; calls setOpening on `cell` (a card or a row, may be nil) around
/// the resolution.
+ (void)playVideo:(MacLCYouTubeVideo *)video fromItem:(nullable NSCollectionViewItem *)cell window:(nullable NSWindow *)window;
+ (void)enqueueVideo:(MacLCYouTubeVideo *)video;
+ (void)copyLinkOfVideo:(MacLCYouTubeVideo *)video;
+ (void)openInBrowser:(NSURL *)URL;
@end

NS_ASSUME_NONNULL_END
