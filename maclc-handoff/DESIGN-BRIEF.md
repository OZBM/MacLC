# MacLC — Design Brief (north star)

This document is the single source of truth for the MacLC UI/UX overhaul. Every
implementation task must comply with it. It is written for agents that have no
other context.

## 0. Product identity

- The application is renamed from **VLC / VLC media player** to **MacLC**.
- MacLC targets **macOS on Apple Silicon (ARM64) only**. Code paths for Windows,
  Linux, Android, iOS, Qt, skins2 and ncurses are out of scope: never let them
  constrain a macOS design decision. Do not delete them, just ignore them.
- Minimum deployment target for new UI code: **macOS 13 Ventura**. Guard newer
  API with `@available` only when the API is macOS 14+.
- The product is a *media player*, not a media library manager. The library is a
  feature; playback is the product.

## 1. Design principles

1. **Native first.** If AppKit provides a control, material, colour or metric,
   use it. Never re-implement what the system already draws.
2. **Nothing hardcoded.** No literal RGB colours, no literal font sizes, no
   magic pixel numbers scattered through the code. Everything comes from the
   design-token layer (section 3).
3. **Plain language.** Every user-visible string is written for a person who has
   never heard of a codec. Jargon may appear, but only after a plain-English
   sentence that explains it.
4. **Progressive disclosure.** A simple default view; advanced controls behind a
   clearly labelled disclosure. Never a wall of checkboxes.
5. **Explain, do not just expose.** Every setting has (a) a short label, (b) a
   one-sentence explanation of what it does in terms of what the user will see
   or hear, and (c) where relevant, a recommendation.
6. **Respect the system.** Accent colour, appearance (light/dark), reduce
   transparency, reduce motion, increase contrast, VoiceOver, full keyboard
   access. All of them.

## 2. Visual language

- **Windows**: `titlebarAppearsTransparent` where content flows under the title
  bar; unified toolbars via `NSToolbar` with `.unifiedCompact` /
  `.unified` style; `NSWindow.toolbarStyle = .unified`.
- **Sidebar**: a real `NSSplitViewController` sidebar item created with
  `+splitViewItemWithSidebarWithViewController:` so the system supplies
  vibrancy, the correct material, the collapse behaviour and the toolbar
  tracking separator. Sidebar rows use `NSTableView` with
  `NSTableViewStyleSourceList` (or the outline equivalent) and SF Symbols.
- **Materials**: `NSVisualEffectView` with the semantic materials
  (`.sidebar`, `.headerView`, `.underWindowBackground`, `.hudWindow`), never a
  hand-rolled blur or a translucent PNG.
- **Colour**: system semantic colours only —
  `NSColor.controlAccentColor`, `.labelColor`, `.secondaryLabelColor`,
  `.tertiaryLabelColor`, `.separatorColor`, `.controlBackgroundColor`,
  `.windowBackgroundColor`, `.selectedContentBackgroundColor`. Any brand colour
  lives in `Assets.xcassets` as a named colour with light and dark variants,
  and is read through the token layer.
- **Type**: `NSFont.preferredFontForTextStyle:options:` for body text
  (`.body`, `.headline`, `.subheadline`, `.caption1`, `.largeTitle`), and
  `+monospacedDigitSystemFontOfSize:weight:` for anything that counts (time
  codes, bitrates, frame counts) so digits do not jitter.
- **Icons**: **SF Symbols** everywhere, via
  `+[NSImage imageWithSystemSymbolName:accessibilityDescription:]` with an
  `NSImageSymbolConfiguration`. Custom PNG/PDF icons only where no SF Symbol
  exists, and then as a template image in the asset catalogue.
- **Metrics**: an 8-point grid. Standard window content margin 20 pt, group
  spacing 20 pt, related-control spacing 8 pt, label-to-control spacing 8 pt.
  Corner radius 8 pt for cards, 6 pt for small controls, 12 pt for floating
  panels. All of these come from the token layer, never typed inline.
- **Motion**: `NSAnimationContext` with the system default duration; honour
  `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion`.

## 3. The design-token layer

A single pair of files defines every token. New UI code reads tokens; it never
hardcodes a value.

- Colours, fonts, spacings, radii, durations, materials and symbol
  configurations are exposed as class properties/methods.
- Existing hardcoded values found while touching a file are migrated to tokens
  as part of that change.

## 4. Settings: the model to follow

Settings are the part of the app users understand least today. The target is the
mental model of macOS System Settings:

- One window, a **sidebar of categories** (not a row of toolbar icons), a
  **search field** at the top of the sidebar that filters settings by label,
  description and keyword.
- Each pane is a vertical stack of **groups**. Each group is a titled card.
- Each row is: **label** (bold-ish, `.body`), **control** on the trailing edge,
  and a **one-line explanation** underneath in `.secondaryLabelColor`
  `.caption1`. Longer explanations go in a disclosure or a help popover.
- Every pane ends with a **"Reset this section"** action.
- Advanced/expert settings live behind a `NSButton` disclosure triangle labelled
  "Advanced", collapsed by default.
- Categories, in this order:
  1. **General** — startup, appearance, language, updates, privacy.
  2. **Playback** — resume, playback speed, skip amounts, repeat, hardware
     decoding.
  3. **Video & HDR** — output, deinterlace, fullscreen behaviour, and the HDR
     section described in section 5.
  4. **Audio** — output device, volume behaviour, normalisation, spatial audio.
  5. **Subtitles** — font, size, colour, outline, encoding, preferred language.
  6. **Library** — folders watched, metadata, artwork.
  7. **Shortcuts** — the hotkey editor.
  8. **Advanced** — the existing tree of all VLC options, kept intact as an
     escape hatch, reachable but not prominent.

## 5. HDR settings — the flagship

HDR is the reason this fork exists. It gets a first-class, self-explanatory
section inside **Video & HDR**, designed so a non-expert can get a correct
result without reading a manual.

Requirements:

- A **status block at the top** that reports live facts, not settings:
  the connected display's name, whether it reports EDR/HDR capability, the
  measured headroom in nits (or as a multiplier), the current video output
  module, and — during playback — the transfer function of the current video
  (SDR / HDR10 / HLG / Dolby Vision) and whether tone mapping is currently
  active. When nothing is playing, say so plainly.
- A **single primary control**: an HDR mode selector with a small number of
  named presets, each with a one-sentence explanation:
  - **Automatic (recommended)** — follow the display and the content.
  - **Always tone-map to SDR** — for displays that handle HDR badly.
  - **Passthrough** — send HDR untouched; only for displays known to be right.
  - **Custom** — reveals the expert controls.
- Expert controls appear only in **Custom**, each with its plain-English
  explanation, its default clearly marked, and a **Reset to default** control:
  tone-mapping curve/algorithm, target peak brightness, contrast recovery,
  gamut mapping, dithering, and the ICC/colour-management toggle.
- Anything that can break playback outright is marked with a warning glyph and
  a sentence saying what will happen.
- No option is exposed unless it is actually wired to a real config option in
  this build. It is better to show five real controls than fifteen decorative
  ones.
- Every explanation is phrased in terms of the visible result:
  "highlights keep detail but the picture is dimmer overall", not
  "applies a BT.2390 EETF".

## 6. Main window

- Sidebar (native, collapsible) for Home / Video / Music / Playlists / Browse /
  Streams.
- Unified toolbar: back/forward, a search field, and the view-mode control.
- Content area: grid and list views that use the system selection colours and
  `NSCollectionViewCompositionalLayout` where practical.
- **Player controls**: a floating, rounded, `.hudWindow`-material bar over
  video, auto-hiding, with SF Symbol transport controls, a scrubber with a
  monospaced-digit time label, and volume/route/subtitle/fullscreen controls
  grouped on the trailing edge. Modelled on QuickTime Player and the Apple TV
  app.
- Empty states: a large SF Symbol, a headline, a sentence, and one primary
  action button. Never a blank pane.

## 7. Accessibility (non-negotiable)

- Every control has an accessibility label and, where the label is not
  self-evident, a help/hint string.
- Full keyboard access: correct `nextKeyView` chains, `Escape` closes panels,
  `⌘,` opens Settings, all destructive actions confirmable.
- Contrast: text/background pairs must remain legible with
  `accessibilityDisplayShouldIncreaseContrast`.
- Transparency: when `accessibilityDisplayShouldReduceTransparency` is on,
  materials fall back to opaque backgrounds.

## 8. Engineering rules

- Objective-C, matching the surrounding style of `modules/gui/macosx/`.
- New files are added to **both** `modules/gui/macosx/Makefile.am` and
  `modules/gui/macosx/meson.build`.
- User-visible strings go through `_NS("...")`.
- Do not break the build. The macOS plugin must still compile:
  `make -C build/modules libmacosx_plugin.la`.
- Do not change C API, module names, config option names, or library sonames.
- Prefer building UI in code over new XIBs when the view is new; keep existing
  XIBs working when only restyling.
