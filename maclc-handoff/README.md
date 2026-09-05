# MacLC — UI/UX overhaul handoff

These are the working documents from the MacLC redesign. They are kept for the
same reason `hdr-handoff/` is: the next person to touch this code should not
have to rediscover any of it.

| File | What it is | Trust |
|---|---|---|
| `DESIGN-BRIEF.md` | The north star. Product identity, design principles, the visual language, how settings are meant to work, and the HDR specification. Every implementation task was written against it. | Written deliberately; still current |
| `VERIFIED-FACTS.md` | The real layout and APIs of `modules/gui/macosx/`, checked directly against the tree. | Verified |
| `PANE-CONTRACT.md` | The `MacLCSettingsPane` protocol and the row idiom, so panes written independently fit together. | Verified — two agents wrote the header from it independently and produced byte-identical files |
| `RECON-HDR.md` | Inventory of every config option affecting HDR on macOS, with `file:line` evidence and plain-English descriptions of what each one does to the picture. | Spot-checked, held up |
| `RECON-BRANDING.md` | The rename audit: every place the name appears, and — more importantly — everything that must NOT be renamed. | Spot-checked, held up |
| `RECON-GUI.md` | Survey of the macOS GUI architecture. | **Partly wrong.** It invented `main-controls/`, `common/VLCUIUnits.h`, and a `vlcTintColor` / `#FF8800` constant that does not exist. Structural claims (autotools only, meson does not build the macOS GUI) are correct. Where it disagrees with `VERIFIED-FACTS.md`, that file wins. |
| `syntax-check.sh` | Parses an Objective-C source from a worktree that has no build directory of its own, by borrowing `config.h` and the generated headers from the reference build tree. Run it from a worktree root. | Working |

## What was built

- **Rename to MacLC** — bundle name, display name, executable, icon and bundle
  identifier. The identifier was initially left as `org.videolan.vlc` to keep
  user settings in place, but that turned out to be untenable: macOS identifies
  running apps by it, so with upstream VLC also installed, Stage Manager and the
  Dock resolved MacLC to `/Applications/VLC.app` and drew its cone — and MacLC
  was reading and writing the real VLC's configuration and media library. It is
  now `org.maclc.MacLC`, and `-migrateFromLegacyBundleIdentifier` copies the old
  preferences directory, application-support directory and user-defaults domain
  across on first launch. It only ever copies, so an older build still finds
  everything where it left it. Core `vlcrc` options are read by libvlc before
  the interface module runs, so those take effect from the second launch;
  the media library and user defaults are correct immediately.
  Visible strings are substituted *after* `vlc_gettext` returns, which keeps
  every translation in `po/` valid. Sparkle's update feed is blanked so the app
  cannot replace itself with upstream VLC.
- **`MacLCDesign` / `MacLCCardView`** (`modules/gui/macosx/theme/`) — the token
  layer. Colours, type scale, 8-point spacing, radii, materials, SF Symbols and
  motion, all honouring the system accessibility settings.
- **Settings** (`modules/gui/macosx/settings/`) — a searchable, sidebar-driven
  window; seven panes; every row carries a sentence explaining what it does.
  The old advanced tree is untouched and still reachable.
- **HDR pane** (`settings/panes/MacLCHDRSettingsViewController.m`) — a live
  status block, four named playback modes with explanations, a headroom control,
  and an Advanced disclosure. Thirteen options, each verified against the module
  that declares it.
- **Window and playback chrome** — unified toolbar, real source-list sidebar,
  floating HUD controls over video, empty states.
- **SDR to HDR** (`macosx-sdr-to-hdr`, `macosx-sdr-to-hdr-boost`) — one switch
  that plays ordinary files through the display's extended range.
  `modules/video_output/apple/VLCHDRExpander.{h,m}` re-encodes each SDR picture
  as PQ / BT.2020 10-bit in a Metal compute pass: de-quantise, linearise with
  the source transfer function, expand highlights, convert the primaries, PQ,
  then write `x420`. The expansion curve is the identity at and below a knee at
  half SDR white and quadratic above it, matching value and slope at the knee
  and landing SDR white on the boost, applied to the largest component so hue
  and saturation do not move. Effective boost is `min(user boost, screen
  headroom)`, and the result carries mastering-display metadata describing the
  volume that was generated, so the compositor does not tone-map it back down.
  Wired into `RenderPicture` in `VLCSampleBufferDisplay.m`, which skips it for
  HDR sources and for HDR modes 2 and 3. The same two variables are registered
  on the video output thread as well, so the settings pane can switch it while
  a file is playing rather than only for the next one.

## What was verified, and how

Verified by building and running:

- `make -C build/modules libmacosx_plugin.la` succeeds.
- The app launches, loads the macOS interface, and stays up.
- HDR10 playback (HEVC 10-bit, PQ/BT.2020, mastering metadata) drives
  `samplebufferdisplay` with `EDR on` and correct PQ/BT.2020 buffer tagging.
- An SDR clip under the same Auto mode is tagged BT.709 — no false HDR.
- `--macosx-hdr-mode=2` produces `preferredDynamicRange=Standard`, `EDR off`.
- `--macosx-edr-headroom=2.0` is picked up as a user override and propagated.
- The brand substitution passes 22 cases, including `VLC.app`, `VLCKit`,
  `libvlccore`, `vlc://quit`, `VLC_PLUGIN_PATH` and a French UI string.
- SDR to HDR, on an M3 Max with 6.15x display headroom. The shader was checked
  against a CPU reference of the same transform written separately: luma and
  chroma agree to the code on an eight-step ramp, the bottom six bits of every
  16-bit word are clear, and decoding the result back through PQ gives the
  luminance SDR would have shown for every input at or below the knee, rising
  monotonically to exactly the boost at SDR white. Playback was exercised for
  all four input formats the expander accepts — `420v`, `420f`, `x420` and
  `BGRA` — and an HDR10 clip under the same switch is left untouched. The pass
  costs 0.53 ms at 1080p and 0.91 ms at 4K including the synchronous wait; a
  60-second 4K run finishes in the same wall-clock time as with the switch off
  and its memory is flat against a 20-second one. The harness that measures all
  of this is not in the tree; it lives in the session scratch directory as
  `shadertest.m` and needs only clang and Metal.

## What the self-check found

`MACLC_SELFTEST=1` builds every pane at startup and logs what appeared:

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

Its first run did not get that far. The Interface pane aborted the whole
process on `config_GetPsz("http-password")` — an option only the lua interface
declares, and this build is `--disable-lua`. Since that is an `assert()` inside
libvlccore rather than an Objective-C exception, no `@try` could have caught it:
opening settings would have killed the app. Fixed by routing all 240 config
accesses in the panes through wrappers that check `config_FindConfig` first, and
by not building the web remote card at all when its option is absent.

## Known debt

- `MacLCHDRSettingsViewController` defines its own `MacLCSettingsRowView` and
  `MacLCStatusRowView` while the settings window has `MacLCSettingsRow`. They
  were written in parallel and should be consolidated onto the shared builder.
- Step 3 of the config hardening was applied only where it was needed: the web
  remote card. Other panes are safe from aborting, but a row whose option is
  missing will still be shown and do nothing. Making every row declare its
  option name would let `MacLCSettingsRow` skip it generically.
- Adding a `_Nullable` declaration to `NSString+Helpers.h` outside any
  `NS_ASSUME_NONNULL` region produces 38 nullability warnings across the module.
  Wrapping the new declarations would silence them.
- `extras/package/macosx/package.mak` copies `$(prefix)/bin/vlc`, but this
  configuration installs neither `bin/vlc` nor `vlc-preparser` into the
  destdir, so `make MacLC.app` cannot assemble a bundle on its own. This
  predates the rename. The bundle used for testing was assembled by hand from
  the build outputs. `pseudo-bundle` also fails here because `CONTRIB_DIR` is
  empty and `build/Frameworks` already exists.
- The app icon is still the VLC cone. Renaming the artwork needs a designer, not
  a rename pass.

## Build notes

`automake` 1.18 is required — the tree's `aclocal.m4` declares
`am__api_version='1.18'` — and was installed via Homebrew during this work.
Without it, `Makefile.in` cannot be regenerated when source files are added.
