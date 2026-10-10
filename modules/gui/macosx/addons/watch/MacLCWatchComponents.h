/*****************************************************************************
 * MacLCWatchComponents.h: the building blocks of Watch (Home, Movies, TV
 * Shows): posters, the featured carousel, episode cards, images, layouts
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

/* Watch shows what the installed add-ons list (Cinemeta by default) the way
 * the Apple TV app does: a featured carousel filling the top, then shelves of
 * posters. Everything here is in the content layer: no glass except the
 * carousel's buttons, which float over pictures (liquid-glass.md, clear). */
#import <Cocoa/Cocoa.h>

@class MacLCAddonItem;
@class MacLCAddonVideo;

NS_ASSUME_NONNULL_BEGIN

#pragma mark - Images

/// Cancels one image load; a cancelled load never calls its completion.
@interface MacLCWatchImageRequest : NSObject
- (void)cancel;
@end

/// Remote pictures (posters, backgrounds, logos, stills), downloaded with
/// NSURLSession, decoded and downsampled off the main thread
/// (CGImageSourceCreateThumbnailAtIndex) to the drawn size in pixels, kept in
/// an NSCache keyed by URL + pixel size (cost = bytes, limit 200 MB).
@interface MacLCWatchImageCache : NSObject
@property (class, readonly) MacLCWatchImageCache *sharedCache;
/// The cached image right away (completion not called), or nil and the
/// completion later on the main queue (image nil on failure).
/// pointSize: the size drawn, in points; scale: the backing scale factor.
- (nullable NSImage *)imageForURL:(NSURL *)url
                        pointSize:(NSSize)pointSize
                            scale:(CGFloat)scale
                          request:(MacLCWatchImageRequest * _Nullable * _Nullable)outRequest
                       completion:(void (^)(NSImage * _Nullable image))completion;
@end

#pragma mark - Layouts

/// Supplementary kind of the shelf headers (MacLCSectionHeaderView from
/// medialib/components, registered by the screens with this kind).
extern NSString * const MacLCWatchHeaderElementKind;

/// Metrics shared by every Watch screen (points). Leading/trailing insets 40
/// (wider than the library's 24: Apple TV aligns shelves on its hero text),
/// 20 between items, 36 between sections.
@interface MacLCWatchLayout : NSObject
/// One row of 2:3 posters scrolling horizontally (orthogonal scrolling,
/// NSCollectionLayoutSectionOrthogonalScrollingBehaviorContinuousGroupLeadingBoundary:
/// a flick settles on a poster's leading edge, never between two), poster
/// width 168 (ranked: 168 too, the rank sits inside the poster), header on top
/// (MacLCWatchShelfHeaderView, kind MacLCWatchHeaderElementKind). No room
/// is reserved under the items for a scroller any more: shelves show none
/// (MacLCWatchShelfScrolling).
+ (NSCollectionLayoutSection *)posterShelfSectionWithEnvironment:(id<NSCollectionLayoutEnvironment>)environment;
/// The Top 10 row: the same posters, each item 52 pt wider for its rank,
/// drawn beside the poster as in the Apple TV app.
+ (NSCollectionLayoutSection *)rankedPosterShelfSectionWithEnvironment:(id<NSCollectionLayoutEnvironment>)environment;
/// A vertical grid of 2:3 posters: as many columns as fit at 150-200 wide,
/// 20 between columns, 32 between rows; optional header.
+ (NSCollectionLayoutSection *)posterGridSectionWithEnvironment:(id<NSCollectionLayoutEnvironment>)environment
                                                      hasHeader:(BOOL)hasHeader;
/// One row of 16:9 episode cards, 300 wide, scrolling horizontally, header on top.
+ (NSCollectionLayoutSection *)episodeShelfSectionWithEnvironment:(id<NSCollectionLayoutEnvironment>)environment;
/// One full-width item of the given height, no insets (the carousel).
+ (NSCollectionLayoutSection *)fullWidthSectionWithHeight:(CGFloat)height;
/// One row of collection cards (MacLCWatchCollectionCard, 340 × 216),
/// 20 apart, same leading inset and scrolling as the poster shelf, header
/// with subtitle on top.
+ (NSCollectionLayoutSection *)collectionShelfSectionWithEnvironment:(id<NSCollectionLayoutEnvironment>)environment;
/// One row of genre tiles (MacLCWatchGenreTile, 196 × 110), 16 apart,
/// scrolling as the poster shelf, header on top.
+ (NSCollectionLayoutSection *)genreShelfSectionWithEnvironment:(id<NSCollectionLayoutEnvironment>)environment;
/// One full-width item of the given height with the Watch leading/trailing
/// insets (the services bar), no header.
+ (NSCollectionLayoutSection *)insetBarSectionWithHeight:(CGFloat)height;
/// The item height of a poster cell for a width: width * 1.5 + 8 + text.
+ (CGFloat)posterItemHeightForWidth:(CGFloat)width;
/// Supplementary header item for Watch sections.
+ (NSCollectionLayoutBoundarySupplementaryItem *)headerSupplementaryItem;
+ (NSCollectionLayoutBoundarySupplementaryItem *)headerSupplementaryItemWithSubtitle:(BOOL)hasSubtitle;
@end

#pragma mark - Poster

extern NSUserInterfaceItemIdentifier const MacLCWatchPosterItemIdentifier;

/// A title in a shelf or a grid. Top to bottom: the poster (2:3, corner radius
/// MacLCDesign.cornerRadiusMedium, quaternarySystemFill + "film" placeholder
/// symbol while loading or without poster; a 1 px separatorColor inner border
/// so posters keep their edge on any background), 8 pt, the title
/// (MacLCDesign.body, medium, 1 line, tail truncation), the subtitle
/// (MacLCDesign.subheadline, secondaryLabel, 1 line): "2026 · Drama".
/// Ranked (Top 10), as in the Apple TV app: the rank beside the poster, not on
/// it (it would cover the poster's own title): heavy rounded digits, 80 pt,
/// labelColor, bottom-aligned with the poster, which overlaps it slightly; the
/// poster and its titles start 52 pt in (item 220 wide in the ranked shelf).
/// Hover: the poster lifts — scale 1.05 and a soft shadow (radius 14, 30 %,
/// y −6) — with a spring (CASpringAnimation damping 15, stiffness 260,
/// mass 1, initial velocity from the current value so a quick in/out does
/// not jump), and settles back the same way on exit (no motion under Reduce
/// Motion: the shadow alone appears); the pointing hand shows. Selection
/// (keyboard focus): a 3 pt accent ring 3 pt outside the poster.
/// Double-click, Return or a single click (Apple TV opens on click) call
/// activationHandler. VoiceOver: one element, "<rank>, <title>, <subtitle>",
/// button role.
@interface MacLCWatchPosterItem : NSCollectionViewItem
/// rank 0: unranked; < 0: ranked shelf placeholder (rank column left empty).
- (void)configureWithItem:(MacLCAddonItem *)item rank:(NSInteger)rank;
@property (readonly, nullable) MacLCAddonItem *addonItem;
@property (nonatomic, copy, nullable) void (^activationHandler)(MacLCAddonItem *item);
@end

#pragma mark - Episode card

extern NSUserInterfaceItemIdentifier const MacLCWatchEpisodeItemIdentifier;

/// An episode in a season shelf, as on the Apple TV app's show pages: the
/// still (16:9, cornerRadiusMedium, "tv" placeholder) with, under it, the
/// eyebrow "EPISODE 3" (footnote, semibold, +0.6 tracking, secondaryLabel),
/// the title (body, semibold, 1 line), the overview (subheadline,
/// secondaryLabel, 2 lines) and the air date ("Jul 7, 2023", footnote,
/// tertiaryLabel; "Upcoming" when in the future). Same hover, selection,
/// activation and VoiceOver rules as the poster.
@interface MacLCWatchEpisodeItem : NSCollectionViewItem
- (void)configureWithVideo:(MacLCAddonVideo *)video;
@property (readonly, nullable) MacLCAddonVideo *video;
@property (readonly, copy, nullable) NSString *titleIdentifier;
@property (nonatomic, copy, nullable) void (^activationHandler)(MacLCAddonVideo *video);
/// Item height for a width.
+ (CGFloat)heightForWidth:(CGFloat)width;
@end

#pragma mark - Featured carousel

/// The top of Home, Movies and TV Shows (the Apple TV app's hero): one title
/// at a time filling the view edge to edge.
/// - The background picture (item.backgroundURL, else the poster) fills the
///   view, aspect fill, inside an NSBackgroundExtensionView so it extends
///   under the floating sidebar and toolbar (as medialib's MacLCHeroView).
/// - Scrims: bottom black 0 → 70 % over the lower 60 %, leading black 0 → 45 %
///   over the leading 55 %, so white text reads on any picture.
/// - Text block, bottom-leading, 40 pt from the leading edge and 40 pt from
///   the bottom, at most 460 pt wide, white whatever the appearance:
///   eyebrow (footnote, semibold, +0.6 tracking, white 75 %: the shelf it
///   comes from, e.g. "POPULAR MOVIE"), the title as its logo picture
///   (item.logoURL, at most 360 × 120, aspect fit, leading) or, without logo,
///   as text (MacLCDesign.largeTitle, bold, 2 lines), the facts line
///   ("Movie · Drama · Crime · 2026 · ★ 7.8", callout, white 85 %), the
///   description (body, white 85 %, 3 lines, tail truncation), then the
///   buttons: "Play" (play.fill, NSBezelStyleGlass, prominent, the view's one
///   tinted control) and "Details" (info.circle, NSBezelStyleGlass), 12 apart.
/// - Page dots, bottom-trailing, 40 pt from the edges: one 8 pt dot per
///   title (white 40 %, current white 100 % and 20 pt wide capsule), each a
///   button ("Show <title>", 20 pt hit target).
/// - Previous / next chevrons (chevron.left / chevron.right, 28 pt glass
///   circles) appear on hover at mid-height on each edge.
/// - It advances every 8 s with a 0.5 s cross-fade; it pauses while the
///   pointer is over it, while its window is not visible or not on screen,
///   and never advances under Reduce Motion (the dots and chevrons still
///   work, with a plain cut). Left/right arrow keys move when it has focus.
/// - Text and picture of a title change together: the new picture is loaded
///   before the cross-fade starts.
/// - VoiceOver: a group "Featured, <title>, <facts>, <description>, page 2
///   of 6"; the buttons and dots follow.
@interface MacLCWatchHeroView : NSView
/// At most 8 are shown. Setting it shows the first.
@property (nonatomic, copy) NSArray<MacLCAddonItem *> *items;
/// One eyebrow per item, same order; missing ones show nothing.
@property (nonatomic, copy) NSArray<NSString *> *eyebrows;
@property (nonatomic, copy, nullable) void (^playHandler)(MacLCAddonItem *item);
@property (nonatomic, copy, nullable) void (^detailsHandler)(MacLCAddonItem *item);
/// Height for a content height: 62 % of it, clamped to 360-620 pt.
+ (CGFloat)heightForAvailableHeight:(CGFloat)height;
/// How far the page is scrolled, in points, negative while the scroll view
/// rubber-bands above the top (clip view bounds origin y, flipped). The
/// carousel answers like a photo pinned under glass: scrolled up (offset
/// > 0), the picture moves at half speed (parallax) and the text block fades
/// out over the first 60 % of the carousel's height; rubber-banding
/// (offset < 0), the picture grows from its top edge so it always fills the
/// gap (scale 1 + |offset| / height, anchored at the bottom centre) — the
/// stretch people know from iOS headers. Layer transforms only, no layout,
/// called on every bounds change. Ignored under Reduce Motion (offset 0).
- (void)setScrollOffset:(CGFloat)offset;
@end

/// "Movie · Drama · Crime · 2026 · ★ 7.8": type ("Movie", "TV Show", else the
/// capitalised type), the first two genres, releaseInfo, rating. Shared by
/// the carousel and the detail page.
NSString *MacLCWatchFactsLine(NSString *type,
                              NSArray<NSString *> *genres,
                              NSString * _Nullable releaseInfo,
                              NSString * _Nullable imdbRating);

NS_ASSUME_NONNULL_END
