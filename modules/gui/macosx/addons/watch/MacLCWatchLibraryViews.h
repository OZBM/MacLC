/*****************************************************************************
 * MacLCWatchLibraryViews.h: how history, resume points and favorites show in
 * Watch: watched badges, progress bars, the favorite heart, Continue
 * Watching cards, the shared actions menu
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

/* Everything here reads MacLCWatchLibrary (MacLCWatchLibrary.h) and redraws
 * itself on MacLCWatchLibraryDidChangeNotification, only when its own title
 * is in the notification's changed set (or the set is absent).
 *
 * The look follows the Apple TV app, which people know:
 *  - a title in progress: a thin progress bar at the bottom of its picture;
 *  - a title watched: a checkmark badge at the picture's bottom-trailing corner
 *    and the picture slightly dimmed (never the text), so that it reads at a
 *    glance in a grid, without relying on the badge alone;
 *  - a favorite: a filled heart at the top-trailing corner; on hover, an
 *    outlined heart appears there to add the title (a click toggles).
 * Every state has an accessibility value ("Watched", "In progress, 40 %",
 * "Favorite"); colour is never the only signal. Reduce Motion: states change
 * without animation. Colours come from MacLCDesign; badges over pictures use a
 * dark translucent circle (NSVisualEffectView, material hudWindow, or drawn
 * black 45 %) so they read on any picture, light or dark appearance. */
#import <Cocoa/Cocoa.h>

#import "addons/watch/MacLCWatchComponents.h"

@class MacLCAddonItem;
@class MacLCAddonVideo;
@class MacLCWatchEntry;

NS_ASSUME_NONNULL_BEGIN

#pragma mark - Small parts

/// A 4 pt progress bar with round ends: track white 30 %, fill white. Meant for
/// pictures (always the same colours); hidden at fraction 0 or 1.
@interface MacLCWatchProgressBar : NSView
@property (nonatomic) double fraction;
@end

/// The checkmark circle for watched titles, 24 × 24 (intrinsicContentSize).
@interface MacLCWatchedBadge : NSView
@end

/// The favorite heart. Toggles MacLCWatchLibrary on click and follows it.
/// onPicture YES: a dark translucent circle behind the heart, white/pink glyph
/// (for posters and cards); NO: a plain borderless symbol button with
/// the system tint (lists, menus). 28 × 28 hit target either way.
@interface MacLCWatchFavoriteButton : NSButton
@property (nonatomic) BOOL onPicture;
- (void)configureWithItem:(nullable MacLCAddonItem *)item;
@end

#pragma mark - Continue Watching cards

extern NSUserInterfaceItemIdentifier const MacLCWatchContinueItemIdentifier;

/// A 16:9 resume card (the Apple TV app's Up Next): the title's background
/// picture (else the poster, cropped), a bottom scrim, the progress bar over
/// the picture's bottom edge, a play glyph in a glass circle centred on hover;
/// under it the title (body, medium, 1 line) and the resume text
/// (subheadline, secondaryLabel): entry.resumeTarget.detailText. Hover: scale
/// 1.04 with the same spring as the posters. Activation (click, Return) calls
/// activationHandler; the "…" button (top-trailing, on hover) opens the
/// context menu (MacLCWatchActions). Right-click shows the same menu.
@interface MacLCWatchContinueItem : NSCollectionViewItem
- (void)configureWithEntry:(MacLCWatchEntry *)entry;
@property (readonly, nullable) MacLCWatchEntry *entry;
/// Resume (or play next up).
@property (nonatomic, copy, nullable) void (^activationHandler)(MacLCWatchEntry *entry);
/// "Show Details": opens the title page.
@property (nonatomic, copy, nullable) void (^detailsHandler)(MacLCWatchEntry *entry);
/// The relative last-played text ("Today", "Yesterday", "Oct 4") under the
/// resume text; for the History grid.
@property (nonatomic) BOOL showsLastPlayed;
/// YES in the History section: the menu offers Remove from History.
@property (nonatomic) BOOL inHistory;
/// Item height for a width: width * 9/16 + 8 + text.
+ (CGFloat)heightForWidth:(CGFloat)width;
@end

@interface MacLCWatchLayout (Library)
/// One row of resume cards (300 wide, 20 apart), horizontal scrolling like the
/// poster shelf, header on top.
+ (NSCollectionLayoutSection *)continueShelfSectionWithEnvironment:(id<NSCollectionLayoutEnvironment>)environment;
/// A vertical grid of resume cards: as many columns as fit at 280-360 wide,
/// 20 between columns, 28 between rows; optional header.
+ (NSCollectionLayoutSection *)continueGridSectionWithEnvironment:(id<NSCollectionLayoutEnvironment>)environment
                                                        hasHeader:(BOOL)hasHeader;
@end

#pragma mark - Episodes

@interface MacLCWatchEpisodeItem (Library)
/// Like -configureWithVideo:, and shows the episode's state: a progress bar
/// over the still when in progress, the watched badge (and a dimmed still)
/// when watched. titleIdentifier is the show's id (progress is keyed by it).
/// The plain -configureWithVideo: derives it from the video id (text before
/// the first ":") so old call sites keep working.
- (void)configureWithVideo:(MacLCAddonVideo *)video titleIdentifier:(NSString *)titleIdentifier;
@end

#pragma mark - Actions

/// The menu shared by posters, cards, episodes and the title page's "…" button.
/// Items (those that apply, in this order):
///   "Add to Favorites" / "Remove from Favorites"   (heart / heart.slash)
///   "Mark as Watched" / "Mark as Unwatched"        (checkmark.circle / arrow.counterclockwise.circle)
///   "Remove from Continue Watching"                (xmark.circle; only for an entry that has a resume target;
///                                                   it forgets the title's progress: removeFromHistory:)
///   "Remove from History"                          (only in the History section: pass inHistory:YES)
/// video: the episode the menu is for (nil: the movie, or the whole show for
/// the poster of a show, where "Mark as Watched" is not offered: marking a
/// whole show happens on its page, per season). Actions run on
/// MacLCWatchLibrary and need no other object. Items carry SF Symbols.
@interface MacLCWatchActions : NSObject
+ (NSMenu *)menuForItem:(MacLCAddonItem *)item
                  video:(nullable MacLCAddonVideo *)video
              inHistory:(BOOL)inHistory;
@end

NS_ASSUME_NONNULL_END
