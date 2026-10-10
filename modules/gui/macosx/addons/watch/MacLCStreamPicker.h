/*****************************************************************************
 * MacLCStreamPicker.h: "Choose a Version", the streams of a title or an
 * episode, read and ranked so that anyone can pick a good one
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

/* Replaces the stream popover of the title page. A sheet, not a popover:
 * filtering, comparing and choosing among 30 versions is a short modal task
 * (sheets.md; popovers.md › "Avoid making a popover too big").
 *
 * Sheet on the library window, 780 × 640 pt, resizable (min 640 × 460),
 * content layer only (no glass inside a sheet: liquid-glass.md).
 *
 * ┌──────────────────────────────────────────────────────────────────┐
 * │ [poster 40×60] Night of the Living Dead                          │
 * │                1968 · Movie        (episode: "S1, E2 · Pilot")   │
 * ├──────────────────────────────────────────────────────────────────┤
 * │ BEST MATCH ⓘ                                                     │
 * │ ┌──────────────────────────────────────────────────────────────┐ │
 * │ │ [4K]  Dolby Vision · Dolby Atmos 7.1 · English    ▮▮▮▮ 120 ⓘ│ │
 * │ │       ✓ Sharp 4K picture with Dolby Vision                   │ │
 * │ │       ✓ Many people sharing: starts quickly        4.4 GB    │ │
 * │ └──────────────────────────────────────────────────────────────┘ │
 * │ [Language: English ▾] [Quality: Any ▾] [Picture: Any ▾]          │
 * │ [☐ Best sound only]           Sort: [Recommended ▾]  3 hidden ⓘ │
 * ├──────────────────────────────────────────────────────────────────┤
 * │ rows …                                                           │
 * ├──────────────────────────────────────────────────────────────────┤
 * │ ⓘ What do these mean?             [Add to Queue] [Cancel] [Play] │
 * └──────────────────────────────────────────────────────────────────┘
 *
 * Header (64 pt): the poster (40 × 60, cornerRadiusSmall, image cache), the
 * title (title3, semibold), under it "1968 · Movie" or "S1, E2 · <episode
 * name>" (subheadline, secondaryLabel).
 *
 * Best Match card (shown when MacLCStreamFilter bestMatchIn: is non-nil
 * among the FILTERED choices; hidden otherwise): eyebrow "BEST MATCH"
 * (footnote, semibold, +0.6 tracking, accent) + info button (topic
 * BestMatch); a card (MacLCDesign.cardBackground, cornerRadiusLarge, 1 px
 * separator border, 2 pt accent border when it is the selection) with the
 * resolution tile, the facts line, up to 3 reasons (checkmark.circle.fill
 * in systemGreen + callout text) and, trailing, the health meter + seeders
 * and the size. Clicking it selects it (the table deselects); double-click
 * plays.
 *
 * Filter bar: NSPopUpButtons (pull-down off, bezel push, small) built from
 * what the choices contain, so nothing offered is empty:
 *   Language: "Any Language", separator, then "English (12)", "French (4)"…
 *             (MacLCStreamFilter languagesIn:counts:); preselected
 *             preferredLanguageIn:.
 *   Quality:  "Any Quality", "4K and Better"... only resolutions present
 *             ("1080p and Better", "720p and Better").
 *   Picture:  "Any Picture", "HDR", "Dolby Vision", "SDR" (present ones).
 *   Checkbox "Best sound only" (only when some choice has lossless or
 *             immersive audio).
 *   Trailing: "Sort:" pop-up (Recommended, Most Shared, Highest Quality,
 *             Smallest Size), then "<n> hidden" (footnote, secondaryLabel,
 *             explained label topic Verdict; click: shows the hidden ones
 *             by turning hidePoor off; "Hide poor versions" then appears in
 *             its place). Filters change the list with a 0.2 s fade, no
 *             motion under Reduce Motion. Choices persist per launch in
 *             NSUserDefaults "MacLCStreamPickerFilter" (language, picture,
 *             sort, bestSoundOnly), never the quality.
 *
 * Rows (NSTableView, style inset, single column, row height 76, no
 * alternating colors, rows arrive as add-ons answer, sorted in place):
 *   leading  the resolution tile, 52 × 40, cornerRadiusMedium,
 *            quaternarySystemFill, "4K" / "1080" / "720" / "SD" / "?"
 *            (title2, heavy, rounded design, labelColor), "p" small for
 *            1080/720; explained (resolution topics).
 *   line 1   the verdict pill: symbol + word, capsule, 11 pt semibold:
 *            Great  checkmark.seal.fill   systemGreen   text on 15 % fill
 *            Good   hand.thumbsup.fill    systemTeal
 *            Okay   minus.circle.fill     secondaryLabel
 *            Poor   exclamationmark.triangle.fill  systemOrange
 *            (symbol + word: never color alone, accessibility.md); then
 *            fact chips (capsules, quaternarySystemFill, 11 pt medium,
 *            labelColor, 6 pt apart, each explained): dynamic range
 *            ("Dolby Vision" in a subtle gradient text is NOT used: plain
 *            labelColor), first audio ("Dolby Atmos 7.1"), languages ("English,
 *            French" or "Multi-language" with globe symbol), source
 *            ("Blu-ray Remux"), "Season pack" when pack.
 *   line 2   the release name (footnote, tertiaryLabel, 1 line, middle
 *            truncation, full name in the tooltip) + " · " + add-on name
 *            and provider ("Torrentio · YTS").
 *   line 3   (only with cautions) exclamationmark.triangle.fill + the first
 *            caution (footnote, systemOrange).
 *   trailing the health meter: 4 vertical bars 3 × (6, 9, 12, 15) pt,
 *            filled count = Weak 1 … Excellent 4, None 0 (filled labelColor,
 *            empty quaternaryLabel; Excellent/Good systemGreen, Fair
 *            systemYellow, Weak/None systemOrange — plus the word in the
 *            tooltip and VoiceOver); under it "120 peers" (footnote,
 *            monospaced digits, explained topic Peers; "Cached" for debrid,
 *            explained Debrid; nothing when unknown); then the size
 *            ("4.4 GB", footnote, secondaryLabel, explained Size).
 *   VoiceOver: one row element: "<verdict>, 4K, Dolby Vision, Dolby Atmos
 *   7.1, English, 120 people sharing, good connection, 4.4 gigabytes,
 *   <release name>"; custom actions Play, Add to Queue.
 *
 * Footer: leading "What do these mean?" (link-style borderless button,
 * question-mark-circle symbol): a popover listing the topics of every chip
 * shown, each row opening its tip. Trailing: "Add to Queue", "Cancel"
 * (Escape), "Play" (default, Return), Play disabled without selection.
 *
 * States: loading — the table shows 4 placeholder rows (no text,
 * quaternarySystemFill bars) and the bar reads "Looking for versions…"
 * with a small spinner until every add-on answered; errors of one add-on
 * appear as a footnote row "<Add-on> didn't answer" with Try Again; none at
 * all: the empty states of the old popover ("No Streams Add-on" + "Browse
 * Add-ons…", "No Versions Found" + "Try Again"); all hidden by filters:
 * "No Versions Match" + "Clear Filters".
 *
 * Playing: VLCOpenInputMetadata with MRLString = stream.MRL, itemName =
 * +[MacLCAddonStore itemNameForItem:video:], play queue startPlayback YES
 * (as the old popover did), then the sheet closes. */
#import <Cocoa/Cocoa.h>

@class MacLCAddonItem;
@class MacLCAddonVideo;

NS_ASSUME_NONNULL_BEGIN

@interface MacLCStreamPickerController : NSWindowController
- (instancetype)initWithItem:(MacLCAddonItem *)item video:(nullable MacLCAddonVideo *)video;
/// Fetches the streams (MacLCAddonStore fetchStreamsForType:...) and shows
/// the sheet on window. Cancels the requests when the sheet ends.
- (void)beginSheetModalForWindow:(NSWindow *)window;
/// Called once the sheet ended (played, queued or cancelled).
@property (nonatomic, copy, nullable) void (^completionHandler)(BOOL played);
/// Developer hook: once all add-ons answered, play the best match (or the
/// first row) as if Play was clicked.
@property (nonatomic) BOOL debugPlayWhenLoaded;
@end

NS_ASSUME_NONNULL_END
