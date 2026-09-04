/*****************************************************************************
 * MacLCDesign.h: MacLC macOS design token layer
 *****************************************************************************
 * Copyright (C) 2026 VLC authors and VideoLAN
 *
 * Authors: MacLC Design System Team
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

#import <Cocoa/Cocoa.h>

@class MacLCCardView;

NS_ASSUME_NONNULL_BEGIN

/**
 * MacLCDesign is the single, authoritative design-token layer for MacLC on macOS.
 *
 * Every visual element in the macOS UI must read values from this class.
 * Never hardcode literal RGB/calibrated colours, point sizes, corner radii,
 * animation durations, or pixel metrics in view or layout code.
 */
@interface MacLCDesign : NSObject

#pragma mark - Colours

/**
 * Primary label text colour.
 * Mapped to AppKit `[NSColor labelColor]`.
 * Use for primary text, prominent headlines, values, and titles.
 */
@property (class, readonly) NSColor *primaryLabel;

/**
 * Secondary label text colour.
 * Mapped to AppKit `[NSColor secondaryLabelColor]`.
 * Use for secondary captions, subtitles, explanatory copy, and metadata.
 */
@property (class, readonly) NSColor *secondaryLabel;

/**
 * Tertiary label text colour.
 * Mapped to AppKit `[NSColor tertiaryLabelColor]`.
 * Use for disabled text, watermark hints, and very subtle glyphs.
 */
@property (class, readonly) NSColor *tertiaryLabel;

/**
 * Quaternary label text colour.
 * Mapped to AppKit `[NSColor quaternaryLabelColor]`.
 * Use for lowest-priority background labels, dividers, or decorative glyphs.
 */
@property (class, readonly) NSColor *quaternaryLabel;

/**
 * System accent colour.
 * Mapped to AppKit `[NSColor controlAccentColor]`.
 * Use for active states, highlighted selection, tinting interactive controls, and play buttons.
 */
@property (class, readonly) NSColor *accent;

/**
 * Hairline separator colour.
 * Mapped to AppKit `[NSColor separatorColor]`.
 * Use for table dividers, subtle container borders, and grouping rules.
 */
@property (class, readonly) NSColor *separator;

/**
 * Window canvas background colour.
 * Mapped to AppKit `[NSColor windowBackgroundColor]`.
 * Use for root window surfaces, settings panes background, and opaque fallbacks.
 */
@property (class, readonly) NSColor *windowBackground;

/**
 * Primary content background colour.
 * Mapped to named colour `MacLCContentBackground` in Assets.xcassets,
 * falling back to AppKit `[NSColor controlBackgroundColor]`.
 * Use for collection views, table views, scroll view documents, and content areas.
 */
@property (class, readonly) NSColor *contentBackground;

/**
 * Grouped card surface background colour.
 * Mapped to named colour `MacLCCardBackground` in Assets.xcassets,
 * falling back to an elevated dynamic surface colour.
 * Use for settings section cards, inspector groups, and elevated rounded containers.
 */
@property (class, readonly) NSColor *cardBackground;

/**
 * Interactive control interior background colour.
 * Mapped to AppKit `[NSColor controlBackgroundColor]`.
 * Use for text fields, search fields, popup buttons, and control interiors.
 */
@property (class, readonly) NSColor *controlBackground;

/**
 * Selected content item or row background colour.
 * Mapped to AppKit `[NSColor selectedContentBackgroundColor]`.
 * Use for selected table view rows, list items, and active collection view cells.
 */
@property (class, readonly) NSColor *selectionBackground;

/**
 * Label text colour when rendered over a selection background.
 * Mapped to AppKit `[NSColor alternateSelectedControlTextColor]`.
 * Use for text and icons rendered directly inside selected rows or buttons.
 */
@property (class, readonly) NSColor *selectionLabel;

/**
 * Semantic destructive action colour.
 * Mapped to AppKit `[NSColor systemRedColor]`.
 * Use for delete, remove, error indicators, and critical alert highlights.
 */
@property (class, readonly) NSColor *destructive;

/**
 * Semantic warning colour.
 * Mapped to AppKit `[NSColor systemOrangeColor]`.
 * Use for cautionary notices, non-fatal alerts, and playback warnings.
 */
@property (class, readonly) NSColor *warning;

/**
 * Semantic success colour.
 * Mapped to AppKit `[NSColor systemGreenColor]`.
 * Use for verified states, positive status badges, and completed actions.
 */
@property (class, readonly) NSColor *success;

/**
 * Placeholder prompt text colour.
 * Mapped to AppKit `[NSColor placeholderTextColor]`.
 * Use for empty field prompts and unpopulated text hints.
 */
@property (class, readonly) NSColor *placeholder;

/**
 * Scrubber unplayed track background colour.
 * Mapped to named colour `MacLCScrubberTrack` in Assets.xcassets.
 * Use for the unplayed track of playback scrubbers and progress bars.
 */
@property (class, readonly) NSColor *scrubberTrack;

/**
 * Scrubber played progress fill colour.
 * Mapped to named colour `MacLCScrubberFill` in Assets.xcassets, falling back to accent.
 * Use for the played elapsed progress fill of playback scrubbers and volume bars.
 */
@property (class, readonly) NSColor *scrubberFill;


#pragma mark - Typography

/**
 * Large title font (preferred for `NSFontTextStyleLargeTitle`).
 * Use for hero banners, large empty-state headlines, and prominent window title headers.
 */
@property (class, readonly) NSFont *largeTitle;

/**
 * Title 1 font (preferred for `NSFontTextStyleTitle1`).
 * Use for top-level section headings and primary category headers.
 */
@property (class, readonly) NSFont *title1;

/**
 * Title 2 font (preferred for `NSFontTextStyleTitle2`).
 * Use for settings pane headers and prominent group titles.
 */
@property (class, readonly) NSFont *title2;

/**
 * Title 3 font (preferred for `NSFontTextStyleTitle3`).
 * Use for card titles, sheet titles, and modal dialog headers.
 */
@property (class, readonly) NSFont *title3;

/**
 * Headline font (preferred for `NSFontTextStyleHeadline`).
 * Use for card group titles, table section headers, and emphasized list labels.
 */
@property (class, readonly) NSFont *headline;

/**
 * Body font (preferred for `NSFontTextStyleBody`).
 * Use for standard interface text, control labels, and readable body copy.
 */
@property (class, readonly) NSFont *body;

/**
 * Emphasized body font (preferred for `NSFontTextStyleBody` with bold/semibold trait).
 * Use for settings row labels, prominent key-value titles, and emphasised body text.
 */
@property (class, readonly) NSFont *bodyEmphasized;

/**
 * Callout font (preferred for `NSFontTextStyleCallout`).
 * Use for alert banners, informational callouts, and inline tips.
 */
@property (class, readonly) NSFont *callout;

/**
 * Subheadline font (preferred for `NSFontTextStyleSubheadline`).
 * Use for secondary item descriptions and subtitle metadata.
 */
@property (class, readonly) NSFont *subheadline;

/**
 * Footnote font (preferred for `NSFontTextStyleFootnote`).
 * Use for fine print, timestamps, and compact metadata badges.
 */
@property (class, readonly) NSFont *footnote;

/**
 * Caption font (preferred for `NSFontTextStyleCaption1`).
 * Use for explanatory one-liners beneath settings rows and control hints.
 */
@property (class, readonly) NSFont *caption;

/**
 * Convenience property returning the default body font with monospaced digits.
 * Use for standard-sized numeric readouts and counts.
 */
@property (class, readonly) NSFont *monospacedDigitBody;

/**
 * Returns an NSFont for the specified system text style configured with monospaced digits
 * (`kNumberSpacingType` / `kMonospacedNumbersSelector`).
 *
 * Use for time codes (e.g. `00:01:23 / 02:45:10`), bitrates, frame rates, audio sample rates,
 * and numeric readouts so that numbers do not jitter horizontally as digits change.
 *
 * @param style The system font text style (e.g. `NSFontTextStyleBody`, `NSFontTextStyleCaption1`).
 * @return An NSFont matching the text style with proportional letters and monospaced digits.
 */
+ (NSFont *)monospacedDigitFontForTextStyle:(NSFontTextStyle)style;

/**
 * Returns an NSFont for the specified system text style and font weight configured with monospaced digits.
 *
 * @param style The system font text style.
 * @param weight The font weight (e.g. `NSFontWeightRegular`, `NSFontWeightSemibold`, `NSFontWeightBold`).
 * @return An NSFont matching the text style and weight with proportional letters and monospaced digits.
 */
+ (NSFont *)monospacedDigitFontForTextStyle:(NSFontTextStyle)style weight:(NSFontWeight)weight;


#pragma mark - Spacing (8-pt grid)

/**
 * Extra-extra-small spacing: 2 pt.
 * Use for hairline offsets, badge insets, and micro adjustments.
 */
@property (class, readonly) CGFloat spacingXXS;

/**
 * Extra-small spacing: 4 pt.
 * Use for tight spacing between closely related elements (e.g. icon and text inside a badge).
 */
@property (class, readonly) CGFloat spacingXS;

/**
 * Small spacing: 8 pt (1x grid unit).
 * Use for standard spacing between related controls, inner button padding, and label-to-control spacing.
 */
@property (class, readonly) CGFloat spacingS;

/**
 * Medium spacing: 12 pt (1.5x grid unit).
 * Use for medium insets, card vertical padding, and grouped element margins.
 */
@property (class, readonly) CGFloat spacingM;

/**
 * Large spacing: 16 pt (2x grid unit).
 * Use for card internal padding, section header separation, and standard view margins.
 */
@property (class, readonly) CGFloat spacingL;

/**
 * Extra-large spacing: 20 pt (2.5x grid unit).
 * Standard window content margin and group spacing across settings cards.
 */
@property (class, readonly) CGFloat spacingXL;

/**
 * Extra-extra-large spacing: 28 pt (3.5x grid unit).
 * Extended spacing between major distinct view modules.
 */
@property (class, readonly) CGFloat spacingXXL;

/**
 * Extra-extra-extra-large spacing: 40 pt (5x grid unit).
 * Large spacing for spacious modal presentations and hero layouts.
 */
@property (class, readonly) CGFloat spacingXXXL;

/**
 * Standard window content margin: 20 pt (`spacingXL`).
 * Use for padding between window frame edges and layout content.
 */
@property (class, readonly) CGFloat windowContentMargin;

/**
 * Standard group spacing: 20 pt (`spacingXL`).
 * Use for vertical margins between adjacent card groups or settings categories.
 */
@property (class, readonly) CGFloat groupSpacing;

/**
 * Standard spacing between a label and its associated control: 8 pt (`spacingS`).
 */
@property (class, readonly) CGFloat labelControlSpacing;

/**
 * Standard minimum row height: 32 pt.
 * Use for interactive list, table, and settings rows to ensure comfortable hit targets.
 */
@property (class, readonly) CGFloat rowMinimumHeight;

/**
 * Standard vertical margin before a section header: 16 pt (`spacingL`).
 */
@property (class, readonly) CGFloat sectionHeaderSpacing;


#pragma mark - Radii

/**
 * Small corner radius: 6 pt.
 * Use for small controls, segmented control buttons, and compact tags.
 */
@property (class, readonly) CGFloat cornerRadiusSmall;

/**
 * Medium corner radius: 8 pt.
 * Use for settings group cards, media grid items, and standard popovers.
 */
@property (class, readonly) CGFloat cornerRadiusMedium;

/**
 * Large corner radius: 12 pt.
 * Use for floating HUD panels, modal sheets, and large overlays.
 */
@property (class, readonly) CGFloat cornerRadiusLarge;

/**
 * Capsule corner radius sentinel (`CGFLOAT_MAX`).
 * Indicates a capsule or pill shape (half the height of the view).
 * Automatically clamped to pill shape by Core Animation `CALayer.cornerRadius`.
 */
@property (class, readonly) CGFloat cornerRadiusCapsule;


#pragma mark - Materials

/**
 * Builds an NSVisualEffectView configured for the navigation sidebar.
 * Material: `NSVisualEffectMaterialSidebar`, Blending: Behind Window.
 * Automatically falls back to opaque `windowBackground` when
 * `accessibilityDisplayShouldReduceTransparency` is enabled.
 */
+ (NSVisualEffectView *)sidebarMaterialView;

/**
 * Builds an NSVisualEffectView configured for header and title bar areas.
 * Material: `NSVisualEffectMaterialHeaderView`, Blending: Within Window.
 * Automatically falls back to opaque `windowBackground` when
 * `accessibilityDisplayShouldReduceTransparency` is enabled.
 */
+ (NSVisualEffectView *)headerMaterialView;

/**
 * Builds an NSVisualEffectView configured for the main content background.
 * Material: `NSVisualEffectMaterialUnderWindowBackground`, Blending: Behind Window.
 * Automatically falls back to opaque `contentBackground` when
 * `accessibilityDisplayShouldReduceTransparency` is enabled.
 */
+ (NSVisualEffectView *)contentBackgroundMaterialView;

/**
 * Builds an NSVisualEffectView configured for floating player HUD panels.
 * Material: `NSVisualEffectMaterialHUDWindow`, Blending: Within Window, State: Active.
 * Automatically falls back to opaque `windowBackground` when
 * `accessibilityDisplayShouldReduceTransparency` is enabled.
 */
+ (NSVisualEffectView *)floatingHUDMaterialView;

// Aliases matching alternative consumer naming styles:
+ (NSVisualEffectView *)sidebarVisualEffectView;
+ (NSVisualEffectView *)headerVisualEffectView;
+ (NSVisualEffectView *)contentBackgroundVisualEffectView;
+ (NSVisualEffectView *)floatingHUDVisualEffectView;
+ (NSVisualEffectView *)floatingHUDPanelMaterialView;


#pragma mark - Symbols

/**
 * Returns an SF Symbol image configured with an accessibility description.
 *
 * If the symbol name is not available on this macOS version, returns nil safely
 * and logs a single diagnostic message to the console once per unique missing name.
 *
 * @param name The SF Symbol system name (e.g. @"play.fill", @"gearshape").
 * @param accessibilityLabel A localized description for accessibility/VoiceOver, or nil.
 * @return An NSImage representing the symbol, or nil if unavailable.
 */
+ (nullable NSImage *)symbolNamed:(NSString *)name accessibilityLabel:(nullable NSString *)accessibilityLabel;

/**
 * Returns an SF Symbol image configured with a specified point size, font weight,
 * and accessibility description.
 *
 * If the symbol name is not available on this macOS version, returns nil safely
 * and logs a single diagnostic message to the console once per unique missing name.
 *
 * @param name The SF Symbol system name.
 * @param pointSize The target point size for the symbol glyph.
 * @param weight The font weight (e.g. `NSFontWeightRegular`, `NSFontWeightSemibold`).
 * @param accessibilityLabel A localized description for accessibility/VoiceOver, or nil.
 * @return An NSImage configured with NSImageSymbolConfiguration, or nil if unavailable.
 */
+ (nullable NSImage *)symbolNamed:(NSString *)name
                        pointSize:(CGFloat)pointSize
                           weight:(NSFontWeight)weight
               accessibilityLabel:(nullable NSString *)accessibilityLabel;


#pragma mark - Motion

/**
 * Standard animation duration for macOS interface transitions (0.25 seconds).
 */
@property (class, readonly) NSTimeInterval animationDuration;

/**
 * Indicates whether the user has enabled Reduced Motion in System Settings.
 * Reads `NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion`.
 */
@property (class, readonly) BOOL reducedMotion;

/**
 * Executes a block with standard interface animation.
 *
 * When `reducedMotion` is enabled, the block is executed with duration 0.0 and
 * implicit animations disabled so that UI updates apply instantaneously without motion.
 *
 * @param actions The block containing view or layout animations.
 */
+ (void)performAnimated:(void(^)(void))actions;


#pragma mark - Card Helper

/**
 * Creates and returns a titled settings container card view (`MacLCCardView`).
 *
 * Styled with `MacLCDesign.cardBackground`, `MacLCDesign.cornerRadiusMedium` (8 pt),
 * and a subtle border using `MacLCDesign.separator`. Provides a `contentStackView`
 * property where consumers add settings rows or controls.
 *
 * @param title The title displayed above the card container, or nil for an untitled card.
 * @return A configured MacLCCardView ready to host settings rows.
 */
+ (MacLCCardView *)cardViewWithTitle:(nullable NSString *)title;

@end

NS_ASSUME_NONNULL_END
