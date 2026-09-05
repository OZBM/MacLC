<div align="center">

# MacLC

**A media player built for one platform, and finished for it.**

MacLC is a macOS-only fork of [VLC](https://www.videolan.org/vlc/) 4.0 for Apple Silicon.
It keeps everything VLC can play, and rebuilds the parts VLC never had the resources to
make native: HDR on Apple displays, a settings window a person can actually read, and an
interface that uses the system's own materials instead of drawing its own.

[Features](#what-maclc-adds) · [HDR](#1-hdr-that-actually-uses-your-display) · [Building](#building) · [Status](#project-status--honesty-section) · [License](#license-and-trademarks)

</div>

---

## Why this fork exists

VLC plays everything. That is not in question, and nothing here changes it — MacLC ships
the same demuxers, the same decoders, the same protocol stack, the same `libvlccore`.

What VLC does *not* do well is be a Mac app. It runs on Windows, Linux, BSD, Android, iOS,
Haiku and OS/2, and every macOS decision has to survive contact with all of them. The
result on macOS is an interface that draws its own furniture, a preferences window that is
a wall of unexplained checkboxes, and — most consequentially — an HDR path that hands
100% of tone mapping to the operating system and then gets several of the hand-off details
wrong.

MacLC drops every other platform from consideration. Windows, Linux, Qt, skins2 and
ncurses code paths are still in the tree, untouched and unbuilt; they simply stop
constraining macOS design decisions. What is left is a player that can assume Metal,
AVFoundation, CoreVideo, SF Symbols, `NSVisualEffectView` and an Apple Silicon GPU are
always there.

---

## What MacLC adds

### 1. HDR that actually uses your display

This is the reason the fork exists. An audit of VLC 4.0.0-dev on Apple Silicon
(2026‑09‑02, against baseline `99034f9`) found **6 confirmed defects and 9 missing
capabilities** in the macOS HDR path. All six defects are fixed here, and most of the
missing capabilities are now present.

**Fixed defects**

| Defect in upstream VLC | What you saw | Fixed |
|---|---|---|
| EDR headroom read once, from `[NSScreen mainScreen]` | Drag the window to a second display and HDR brightness stayed wrong | Headroom is re-evaluated on `NSApplicationDidChangeScreenParameters`, `NSWindowDidChangeScreen` and `NSWindowDidChangeScreenProfile` |
| The HDR mode selector and EDR slider in Preferences did nothing | Settings were decorative | Both are wired to live `var_` callbacks and take effect during playback |
| No SDR tone-mapping branch | HDR film on an SDR display clipped to flat white | Mode 2 applies `CADynamicRangeStandard` + `CAToneMapModeAutomatic`, with a BT.709 buffer-retag fallback on macOS < 14 |
| Subtitles untagged over PQ video | White subtitle text rendered at full PQ luminance — painfully bright over dark HDR scenes | Subtitle layer is tagged sRGB, `wantsExtendedDynamicRangeContent = NO`, `contentsHeadroom = 1.0`, and opacity is scaled to the ITU‑R BT.2408 203‑nit reference white relative to measured headroom |
| >10-bit HEVC downsampled to 8-bit BGRA | 12-bit and 16-bit sources lost four to eight bits before they reached the screen | Routed to P010 (`kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange`); 16-bit 4:2:2 (`sv22`) wired through the CVPX helpers |
| Sub-4K HDR mis-tagged BT.709; zero-nit mastering volume emitted | Wide-gamut content played through the wrong primaries | Correct tagging per stream, mastering volume never emitted as zero |

**New capabilities**

- **Hardware AV1 decoding on M3 and M4.** Gated on `VTIsHardwareDecodeSupported(kCMVideoCodecType_AV1)`, `__aarch64__`, macOS 14+. Falls back to dav1d elsewhere. (Confirmed available on M3 Max / macOS 26.2 by the bundled probe.)
- **HDR10+ dynamic metadata**, carried as `VLC_ANCILLARY_ID_HDR10PLUS` through the OpenGL filter chain into `vlc_placebo_HdrMetadata`.
- **Dolby Vision metadata extraction** from the VideoToolbox bitstream, with hardened HDR10+ and Dolby Vision parsers, and a fix for Dolby Vision being lost to a stray bit on the first frame.
- **ARM64 NEON chroma conversions** — hand-vectorised NV12/P010 ↔ I420/I420_10L split and interleave paths (`vld2q_u16` / `vshlq_u16` / `vst2q_u16` and friends), replacing scalar loops on the software-decode path.
- **OpenGL 4.1 / 3.2 Core profile negotiation** with 64-bit RGBA16F colour in `caopengllayer`, which is what unblocks libplacebo's GL shaders. Upstream failed with *"OpenGL version too old (2 < 3)"*.
- **ST 2086 mastering-display and CTA‑861.3 content-light-level metadata** forwarded from the source format into the display layer.
- **Per-window ICC profile** taken from the window's own screen, not the main one, with a dedicated Darwin ICC dirty flag.

### 2. SDR → HDR: the feature no other player has

An XDR display can go five to six times brighter than SDR white. Play an ordinary file and
none of that is used, because an ordinary file carries no HDR signal at all.

Retagging an SDR buffer as PQ is not a solution — the same code words mean roughly five
times the luminance under PQ, so the mid-tones blow out and faces go white.

**`VLCHDRExpander`** (`modules/video_output/apple/VLCHDRExpander.{h,m}`, 895 lines) does it
properly, as a Metal compute pass:

```
Y'CbCr or BGRA  →  R'G'B'  →  linear (BT.1886 / sRGB)  →  highlight expansion
                →  BT.2020 primaries  →  PQ  →  10-bit x420
```

The expansion curve is **the identity at and below a knee at half SDR white**, and
quadratic above it — chosen so value *and* slope match the identity at the knee, and SDR
white lands exactly on the boost. It is applied to the largest of the three components and
the triplet is scaled by the result, so **hue and saturation do not move**.

The consequence is the point: shadows and mid-tones reach your eye at exactly the
luminance SDR playback would have produced. Nothing is "brightened". Only highlights —
specular glints, skies, practical lights, explosions — are lifted into the range the panel
has spare. The effective boost is `min(your setting, the screen's actual headroom)`, and
the output carries mastering-display metadata describing the volume that was generated, so
the compositor has no reason to tone-map it back down.

**Measured**, on an M3 Max with 6.15× display headroom, against a separately written CPU
reference implementation of the same transform:

- Luma and chroma agree with the reference to the code over an eight-step ramp.
- The bottom six bits of every 16-bit word are clear (true 10-bit output, no noise in the pad bits).
- Decoding the result back through PQ returns the exact SDR luminance for every input at or below the knee, rising monotonically to exactly the boost at SDR white.
- **0.53 ms at 1080p, 0.91 ms at 4K**, including the synchronous wait.
- A 60-second 4K run finishes in the same wall-clock time as with the switch off, and its memory is flat against a 20-second one.
- All four accepted input formats play (`420v`, `420f`, `x420`, `BGRA`); an HDR10 clip under the same switch is left untouched.

It is skipped automatically for sources that are already PQ or HLG, and for the two HDR
modes that ask for an SDR presentation. Both options (`macosx-sdr-to-hdr`,
`macosx-sdr-to-hdr-boost`) are registered on the video output thread as well as the
display, so the switch takes effect on *what is playing* rather than only on the next file.

### 3. A settings window built on the System Settings model

VLC's macOS preferences are a five-icon toolbar over five XIB-driven panes, plus an
"Advanced" tree that walks the entire module registry and builds one widget per option —
thousands of them, unexplained.

MacLC's settings window (`modules/gui/macosx/settings/`) is:

- **One window, a sidebar of categories, and a search field** that filters by label, description *and* per-pane keywords.
- **Eight panes** — General, Playback, Video, HDR & Colour, Audio, Subtitles, Interface, Shortcuts.
- Each pane is a stack of **titled cards**. Each row is a label, a control on the trailing edge, and **a one-sentence explanation underneath** of what it does *in terms of what you will see or hear*: "highlights keep detail but the picture is dimmer overall", never "applies a BT.2390 EETF".
- Advanced controls live behind a collapsed disclosure. Anything that can break playback carries a warning glyph and a sentence saying what will happen.
- **The old advanced tree is untouched and still reachable.** Nothing was taken away.

**Nothing decorative.** Every control is verified to be wired to a config option that
exists in this build — and where an option is genuinely absent, the row is not built at
all. This is not cosmetic: opening the Interface pane in a `--disable-lua` build used to
call `config_GetPsz("http-password")`, which is an `assert()` inside `libvlccore` — a hard
process abort that no `@try` could catch. All 240 config accesses in the panes now go
through `MacLCConfigSafe` wrappers that check `config_FindConfig` first.

### 4. The HDR pane, in detail

The flagship pane (`MacLCHDRSettingsViewController.m`, 1,499 lines) is built so a
non-expert reaches a correct result without reading a manual:

- **A live status block** — connected display, measured EDR headroom, active video engine, and during playback the transfer function of the stream and whether tone mapping is on. When nothing is playing, it says so.
- **Four named playback modes**, each with a plain sentence: *Automatic (recommended)* · *Always use HDR* · *Convert HDR to SDR* · *Turn HDR off*.
- **SDR → HDR** with a highlight-boost slider that shows the peak your setting reaches and the headroom the screen actually allows — and tells you when the OpenGL engine is selected instead, because that path has its own inverse tone mapping under Advanced.
- **Brightness headroom**, automatic or manual.
- **Advanced**: tone-mapping curve (10 algorithms, from hard clip to BT.2390 EETF, Reinhard, Mobius, Hable, BT.2446A, single-pivot spline), tone-mapping parameter, gamut mapping (7 modes), inverse tone mapping, dithering, ICC colour management.

Thirteen options, each one verified against the module that declares it.

### 5. Interface, rebuilt on system materials

- **Unified toolbar**, transparent titlebar, `NSSearchToolbarItem` that collapses the way the system's does.
- **A real source-list sidebar** (`+splitViewItemWithSidebarWithViewController:`), which is what brings vibrancy, the correct material, collapse behaviour and the toolbar tracking separator — rather than a table styled to look like one.
- **Floating HUD playback controls** over video, inset from the edges on the `.hudWindow` material, with SF Symbol transport glyphs at one weight and size, and **monospaced-digit time labels** so the numbers stop shifting as the seconds tick.
- **Empty states** that are a symbol, a headline, a sentence and an action — not a bare label.
- **Six layout metrics moved onto the 8-point grid.** The small row height went from 25 pt to 32 pt; 25 pt was below a comfortable click target.

### 6. `MacLCDesign` — a real token layer

Upstream had eleven literal colours in the colour category alone, font sizes typed at the
call site, and radii that landed wherever they landed. `modules/gui/macosx/theme/MacLCDesign.{h,m}`
now defines every colour, type style, spacing, radius, material, SF Symbol configuration
and animation duration as a class property, mapped to AppKit semantics
(`labelColor`, `controlAccentColor`, `separatorColor`, `selectedContentBackgroundColor`, …)
with named asset-catalogue colours where a brand value is genuinely needed.

Which means MacLC follows your **accent colour, light/dark appearance, Reduce
Transparency, Reduce Motion, Increase Contrast, VoiceOver and full keyboard access** —
because it never hardcoded around them in the first place.

### 7. A real app identity

- Renamed throughout — bundle name, display name, executable, packaging rules, `Info.plist`.
- **Its own icon.** An original mark: a graphite superellipse on Apple's 824-of-1024 grid with a warm play triangle, a highlight bloom behind it and a specular edge along the lit face. A superellipse, not a rounded rectangle — circular corners look visibly wrong beside system icons, and at 16 points that difference is most of what makes an icon look native. The artwork is **generated by a committed Swift program** (`extras/package/macosx/asset_sources/maclc_app_icon.swift`), so it can be regenerated, adjusted and diffed rather than being an opaque binary.
- **Its own bundle identifier**, `org.maclc.MacLC`. This matters more than it sounds: while it claimed `org.videolan.vlc`, macOS resolved the running app to `/Applications/VLC.app` — Stage Manager and the Dock drew VLC's cone on MacLC's windows, and MacLC was reading and writing the real VLC's `vlcrc` and media library.
- **`-migrateFromLegacyBundleIdentifier`** copies the preferences directory, application-support directory and user-defaults domain across on first launch. It only ever *copies*, so an older VLC install still finds everything where it left it.
- **Translations survive.** Visible strings are substituted *after* `vlc_gettext` returns, so French still resolves "Hide VLC" and then renders "Masquer MacLC". Every catalogue in `po/` stays valid. The substitution deliberately does not run inside `toNSStr`, which also converts option names, option values, font names and media titles.
- **Sparkle's update feed is blanked**, so the app cannot replace itself with upstream VLC on its first update check.

### 8. Stability and correctness fixes

- Use-after-free on teardown — a 100%-reproducible crash on quit at the end of playback.
- A playback stall, a teardown deadlock and swapped subtitle channels.
- `caopengllayer` clearing the view's display pointer before the variable dies.
- The layer wait ending as soon as no attempt is in flight.
- Display headroom tracked for the life of the OpenGL filter, not sampled once.
- `pl_scale` given a real render target instead of default assumptions.
- Plane-splitting bounds comparing like with like in `video_chroma`.
- A duplicated toolbar tracking separator.

### 9. Tests and a startup self-check

- `test/src/misc/cvpx_hdr_metadata.c` — CoreVideo PQ/HLG/mastering metadata round-trips, including negative unattached cases.
- `copy_neon` — the NEON chroma SIMD routines, plus a copy self-test able to run the 4:2:2 conversions.
- Bare HLG and sub-nit mastering luminance coverage.
- `tools/hdr-probe/vt_probe.m` — a standalone VideoToolbox/EDR capability probe. Deliberately not wired into the build.
- **`MACLC_SELFTEST=1`** builds every settings pane at startup and reports what appeared:

```
pane=General    title="General"      symbol=YES views=136 controls=45 status=OK
pane=Playback   title="Playback"     symbol=YES views=223 controls=76 status=OK
pane=Video      title="Video"        symbol=YES views=281 controls=96 status=OK
pane=HDR        title="HDR & Colour" symbol=YES views=204 controls=77 status=OK
pane=Audio      title="Audio"        symbol=YES views=237 controls=80 status=OK
pane=Subtitles  title="Subtitles"    symbol=YES views=200 controls=68 status=OK
pane=Interface  title="Interface"    symbol=YES views=145 controls=49 status=OK
pane=Shortcuts  title="Shortcuts"    symbol=YES views= 78 controls=13 status=OK
window status=OK
summary: 8 panes, 8 ok, 0 failed
```

---

## Options added

| Option | Type | Default | What it does |
|---|---|---|---|
| `--macosx-hdr-mode` | integer 0–3 | `0` | 0 Auto · 1 Force native EDR/HDR · 2 Tone-map to SDR · 3 Disable HDR |
| `--macosx-edr-headroom` | float | `0.0` | `0.0` follows the screen; `≥ 1.0` forces a specific headroom |
| `--macosx-sdr-to-hdr` | bool | `false` | Expand SDR video into the display's extended range |
| `--macosx-sdr-to-hdr-boost` | float 1.0–16.0 | `4.0` | How far above SDR white highlights may go. `1.0` disables; `4.0` is natural; higher is dramatic and less faithful |

---

## Requirements

- **Apple Silicon** (M1 or newer). Intel Macs are out of scope — not blocked, just never targeted or tested.
- **macOS 13 Ventura** minimum for the new interface code.
- Full HDR feature set wants **macOS 14+** (`preferredDynamicRange`) and **macOS 15+** (`toneMapMode`); older systems fall back to a BT.709 retag.
- Hardware AV1 decoding needs an **M3 or M4** and macOS 14+.
- SDR → HDR needs a display with real extended range (XDR, or an HDR external panel). On an SDR display it does nothing.

Developed and measured on an **M3 Max (Mac15,9), macOS 26.2**.

---

## Building

MacLC builds through VLC's own autotools system. The macOS GUI is **autotools only** —
`modules/gui/meson.build` does not build `modules/gui/macosx` at all, so new GUI sources go
in `modules/gui/macosx/Makefile.am` and nowhere else.

```bash
./bootstrap
./extras/package/macosx/build.sh
```

To rebuild just the interface plugin during development:

```bash
make -C build/modules libmacosx_plugin.la
```

**Build notes**

- `automake` 1.18 is required — the tree's `aclocal.m4` declares `am__api_version='1.18'`. Without it, `Makefile.in` cannot be regenerated when source files are added.
- Any file containing `_NS("…")` must also be listed in `po/POTFILES.in`.
- `make MacLC.app` does not currently assemble a bundle on its own: `extras/package/macosx/package.mak` copies `$(prefix)/bin/vlc`, but this configuration installs neither `bin/vlc` nor `vlc-preparser` into the destdir. This predates the rename. The bundle used for testing was assembled by hand from the build outputs. `pseudo-bundle` also fails here, because `CONTRIB_DIR` is empty and `build/Frameworks` already exists.

To regenerate the app icon, see the header comment of
`extras/package/macosx/asset_sources/maclc_app_icon.swift` — it gives the two commands.

---

## Project status — honesty section

This is a working fork under active development, not a shipped 1.0. What follows is what
has and has not actually been checked, because a README that overstates its own testing is
worse than no README.

**Verified by building and running:**

- `make -C build/modules libmacosx_plugin.la` succeeds; the app launches, loads the macOS interface and stays up.
- HDR10 playback (HEVC 10-bit, PQ/BT.2020, mastering metadata) drives `samplebufferdisplay` with EDR on and correct PQ/BT.2020 buffer tagging.
- An SDR clip under the same Auto mode is tagged BT.709 — no false HDR.
- `--macosx-hdr-mode=2` produces `preferredDynamicRange=Standard`, EDR off.
- `--macosx-edr-headroom=2.0` is picked up as a user override and propagated.
- Brand substitution passes 22 cases, including `VLC.app`, `VLCKit`, `libvlccore`, `vlc://quit`, `VLC_PLUGIN_PATH` and a French UI string.
- SDR → HDR, as described above.
- All eight settings panes construct, with every SF Symbol resolving.

**Known debt**

- `MacLCHDRSettingsViewController` defines its own `MacLCSettingsRowView` and `MacLCStatusRowView` while the settings window has `MacLCSettingsRow`. Written in parallel; should be consolidated onto the shared builder.
- Config hardening was applied where it was needed (the web-remote card). Other panes cannot abort, but a row whose option is missing is still shown and does nothing. Making every row declare its option name would let `MacLCSettingsRow` skip it generically.
- Adding a `_Nullable` declaration to `NSString+Helpers.h` outside any `NS_ASSUME_NONNULL` region produces 38 nullability warnings across the module.
- The seasonal Xmas icon is still upstream art — it belongs to an easter egg, and replacing it is a separate piece of drawing.
- The Dolby Vision RPU bitstream parser on `dovi-rpu-wip` desynchronises at partition fields.
- libplacebo's Vulkan backend still cannot be elected on Darwin: there is no Vulkan windowing platform module (`VK_EXT_metal_surface` / `CAMetalLayer` bridge).

---

## License and trademarks

MacLC is a fork of VLC and is released under the **GNU General Public License v2 or
later**, the same terms as VLC. `libVLC`, the engine, remains **LGPLv2.1 or later**. See
[`COPYING`](COPYING) and [`COPYING.LIB`](COPYING.LIB). Complete corresponding source is
this repository.

**MacLC is not affiliated with, endorsed by, or supported by VideoLAN.**
"VLC", "VideoLAN" and the traffic-cone logo are trademarks of the VideoLAN organisation.
MacLC uses none of them: it has its own name, its own bundle identifier and its own,
originally drawn icon. Please do not report MacLC bugs to VideoLAN — they are not
responsible for this fork, and cannot fix it.

Please do report VLC bugs to VideoLAN. Almost everything that works here works because
they built it.

## Credits

VLC is the work of the VideoLAN project and a very large community of volunteers, over
more than two decades. See [`AUTHORS`](AUTHORS) and [`THANKS`](THANKS). The upstream
README is preserved at [`README.upstream.md`](README.upstream.md).

MacLC is the macOS-specific work layered on top of that, and nothing more.
