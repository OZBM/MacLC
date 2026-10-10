/*****************************************************************************
 * MacLCWatchDiscoveryViews.h: The Edit's collection cards, genre tiles, the
 * services bar and sheet, shelf headers that page, and how shelves scroll
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

/* Content layer: no glass anywhere here (liquid-glass.md: glass is for the
 * floating functional layer). Colors: system colors by name
 * (MacLCWatchColorNamed), so they adapt to light, dark and increased
 * contrast. Every animation below is skipped under Reduce Motion
 * (MacLCDesign.reducedMotion) — states still change, without motion. */
#import <Cocoa/Cocoa.h>

@class MacLCAddonItem;
@class MacLCWatchCollection;
@class MacLCWatchService;

NS_ASSUME_NONNULL_BEGIN

/// "red" … "brown" → NSColor.systemRedColor …; unknown → systemBlueColor.
NSColor *MacLCWatchColorNamed(NSString *name);

#pragma mark - Shelf scrolling

/// Horizontal shelves are NSCollectionLayoutSection orthogonal sections, which
/// AppKit backs with one embedded NSScrollView per section. With "Show scroll
/// bars: Always" (the user's setting) each showed a permanent scroller under
/// its posters. Shelves now show no scroller (scroll-views.md: with a page
/// control "don't show the scrolling indicator on the same axis"; partial
/// posters at the trailing edge show there is more, scroll-views.md › "Make
/// it apparent when content is scrollable"); they page with the header's
/// chevrons, the trackpad, Shift + mouse wheel, and the arrow keys.
@interface MacLCWatchShelfScrolling : NSObject
/// The embedded scroll view holding view (an item view of a shelf), or nil
/// when view is not inside an orthogonal section (the outer scroll view is
/// never returned: outerScrollView is skipped).
+ (nullable NSScrollView *)shelfScrollViewForView:(NSView *)view
                                   outerScrollView:(nullable NSScrollView *)outerScrollView;
/// No scrollers (hasHorizontalScroller and hasVerticalScroller NO, also
/// re-applied when NSPreferredScrollerStyleDidChangeNotification fires),
/// horizontal elasticity allowed, vertical none, drawsBackground NO.
/// Idempotent and cheap: call it from willDisplayItem.
+ (void)configureShelfScrollView:(NSScrollView *)scrollView;
/// Scrolls one page (visible width minus one item width + spacing, so the
/// last poster of the page stays partly visible: scroll-views.md › "define
/// a unit of overlap") in direction (-1 back, +1 forward), with a spring-like
/// ease (0.45 s, CAMediaTimingFunction control points 0.2, 1.0, 0.3, 1.0,
/// i.e. fast start and a soft settle), clamped to the content; snaps the
/// end to an item's leading edge (itemPitch = item width + spacing; 0: no
/// snap).
+ (void)scrollShelf:(NSScrollView *)scrollView
          direction:(NSInteger)direction
          itemPitch:(CGFloat)itemPitch;
/// YES when the shelf can scroll that way (more than 1 pt left).
+ (BOOL)shelf:(NSScrollView *)scrollView canScrollInDirection:(NSInteger)direction;
@end

#pragma mark - Shelf header

extern NSUserInterfaceItemIdentifier const MacLCWatchShelfHeaderIdentifier;

/// Watch's shelf header (replaces MacLCSectionHeaderView in Watch): title
/// (title2, bold) with optional subtitle (subheadline, secondaryLabel), an
/// optional info button after the title (MacLCExplainer, topic), and,
/// trailing: "See All" (borderless, secondaryLabel, accent on hover) then two
/// paging buttons (chevron.left / chevron.right, 13 pt semibold symbols in
/// 26 pt circles of quaternarySystemFill, labelColor; disabled = 35 %
/// alpha; hover = tertiarySystemFill; accessibility "Previous" / "Next"
/// "<title>"), 6 apart. Paging buttons are hidden when showsPaging is NO
/// (grids, single page). Height 44 (58 with subtitle).
@interface MacLCWatchShelfHeaderView : NSView <NSCollectionViewElement>
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy, nullable) NSString *subtitle;
@property (nonatomic, copy, nullable) NSString *explainerTopic;
@property (nonatomic, copy, nullable) NSString *actionTitle;
@property (nonatomic, copy, nullable) void (^action)(void);
@property (nonatomic) BOOL showsPaging;
@property (nonatomic) BOOL canPageBack;
@property (nonatomic) BOOL canPageForward;
/// direction -1 / +1.
@property (nonatomic, copy, nullable) void (^pageHandler)(NSInteger direction);
+ (CGFloat)heightWithSubtitle:(BOOL)hasSubtitle;
@end

#pragma mark - The Edit: collection card

extern NSUserInterfaceItemIdentifier const MacLCWatchCollectionCardIdentifier;

/// The signature of Watch: a collection as a card 340 × 216 pt
/// (cornerRadiusLarge), background a diagonal gradient of the collection's
/// tint (32 % → 12 % alpha over windowBackground), a 1 px separator border.
/// Leading half: the symbol (22 pt, tint), the title (title2, bold, 2
/// lines), the subtitle (subheadline, secondaryLabel, 3 lines), the count
/// "16 Films" / "12 Shows" / "14 Titles" (footnote, semibold, tint).
/// Trailing half: up to 3 posters (82 × 123, cornerRadiusSmall, shadow
/// radius 8 at 25 %) fanned like a hand of cards: rotations -8°, 0°, +8°,
/// overlapping by about 55 %, right of the 144 pt text column, the middle one in front, bottoms 18 pt from the
/// card bottom. Before the collection resolves: placeholder posters
/// (quaternarySystemFill). Hover: the fan opens (rotations -14°, 0°, +14°,
/// spread 8 pt more) and the middle poster rises 6 pt, with a spring
/// (CASpringAnimation damping 14, stiffness 220, mass 1, ~0.5 s); exit
/// reverses it. Click, Return: activationHandler. Focus ring: 3 pt accent,
/// 3 pt outside. VoiceOver: button "<title>, <subtitle>, <count>".
@interface MacLCWatchCollectionCard : NSCollectionViewItem
- (void)configureWithCollection:(MacLCWatchCollection *)collection
                          items:(nullable NSArray<MacLCAddonItem *> *)items;
@property (readonly, nullable) MacLCWatchCollection *collection;
@property (nonatomic, copy, nullable) void (^activationHandler)(MacLCWatchCollection *collection);
@end

#pragma mark - Genre tile

extern NSUserInterfaceItemIdentifier const MacLCWatchGenreTileIdentifier;

/// A genre, 196 × 110 pt (cornerRadiusLarge): a gradient of the genre's tint
/// (MacLCWatchDiscovery tintNameForGenre:, top-leading 100 % → bottom-trailing
/// 70 % mixed with black 25 %), the genre's symbol as a large watermark
/// (88 pt, white 18 %, bottom-trailing, clipped, rotated -12°), the name
/// (title3, bold, white, bottom-leading, 14 pt insets; white on these
/// fills measures ≥ 3:1 for this bold 20 pt text, typography.md). When up to
/// 2 posters of that genre are known, they peek from the trailing edge
/// (60 × 90, rotated 10°, white 1 px border) above the watermark. Hover:
/// scale 1.03 + the posters slide 8 pt in, spring as the collection card.
/// Click: activationHandler(genre).
@interface MacLCWatchGenreTile : NSCollectionViewItem
- (void)configureWithGenre:(NSString *)genre posters:(NSArray<MacLCAddonItem *> *)posters;
@property (readonly, copy, nullable) NSString *genre;
@property (nonatomic, copy, nullable) void (^activationHandler)(NSString *genre);
@end

#pragma mark - Services bar

/// The row under the carousel on Home, Movies and TV Shows: a scope bar
/// (search-fields.md › Scope bars and tokens) of capsule buttons, one
/// selected at a time: "All" then one per active service (name only, no
/// logos: the services' marks are theirs), then, trailing, "Choose
/// Services…" (slider.horizontal.3) and an info button (topic Services).
/// Capsules: 28 pt high, 14 pt horizontal padding, callout medium;
/// selected = accent fill, white text; others = quaternarySystemFill,
/// labelColor; hover = tertiarySystemFill. Selection moves with a 0.25 s
/// cross-fade of the fills (none under Reduce Motion). Overflowing: the row
/// scrolls horizontally without scroller (MacLCWatchShelfScrolling). With no
/// active service the bar shows one capsule "Add Your Streaming Services…"
/// (plus.circle) and the info button: it invites, it does not filter.
/// Keyboard: left/right arrows move the selection when focused.
/// VoiceOver: a radio group "Streaming service".
@interface MacLCWatchServiceBar : NSView
@property (nonatomic, copy) NSArray<MacLCWatchService *> *services;
/// nil = All.
@property (nonatomic, copy, nullable) NSString *selectedCode;
@property (nonatomic, copy, nullable) void (^selectionHandler)(NSString * _Nullable code);
@property (nonatomic, copy, nullable) void (^chooseServicesHandler)(void);
+ (CGFloat)height; /* 44 */
@end

#pragma mark - Services sheet

/// "Choose Your Streaming Services" (sheet on the library window, 560 ×
/// 520): a short text — "Pick the services you subscribe to. Watch then lets
/// you browse what's popular on each one. Lists come from the community
/// add-on Streaming Catalogs, which you can remove in Settings ▸ Add-ons." —
/// a grid of toggle tiles (3 columns, 160 × 56, the service name in
/// headline, checkmark.circle.fill accent when on, circle when off;
/// cornerRadiusMedium; selected tiles get a 2 pt accent border), a
/// "Country" pop-up (all ISO regions by localized name, preselected
/// NSLocale.currentLocale.countryCode, else "US": what each service offers
/// differs by country), then "Cancel" and "Save" (default). Save calls
/// MacLCWatchDiscovery setServiceCodes:country:completion: with a spinner in
/// place of the buttons; an error shows inline in systemRed under the grid
/// (no alert, feedback.md). Preselects the active codes.
@interface MacLCWatchServicesSheetController : NSWindowController
- (instancetype)init;
- (void)beginSheetModalForWindow:(NSWindow *)window completion:(nullable void (^)(BOOL saved))completion;
@end

#pragma mark - Collection page header

/// The top of a collection's page: full width, 300 pt high, the tint
/// gradient of the card, the symbol (34 pt), eyebrow "THE EDIT · UNTIL OCT
/// 19" (footnote, semibold, +0.6 tracking, tint), the title (largeTitle,
/// bold), the subtitle (title3, secondaryLabel, 2 lines, max 620 wide), the
/// count, and trailing the fan of 5 posters (as the card's, larger: 110 ×
/// 165, -14° … +14°). The source link "Source: Wikipedia" (footnote,
/// link color) when the collection has one.
@interface MacLCWatchCollectionHeaderView : NSView
- (void)configureWithCollection:(MacLCWatchCollection *)collection
                          items:(NSArray<MacLCAddonItem *> *)items
                       eyebrow:(NSString *)eyebrow;
@end

NS_ASSUME_NONNULL_END
