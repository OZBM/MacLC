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

- **Rename to MacLC** — bundle name, display name and executable. The bundle
  identifier stays `org.videolan.vlc` on purpose: changing it moves the
  preferences domain, the application support directory and the sandbox
  container, so settings, library and privacy permissions would silently vanish.
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

## What is NOT verified

**Nothing in the settings UI has been constructed at runtime, and no part of the
redesign has been looked at.** Screen-recording and accessibility access were
both unavailable in the environment where this was built, so there are no
screenshots and no interactive testing. The panes compile and are wired into the
window; whether they lay out correctly, and whether every SF Symbol resolves, is
unknown.

A startup self-check was specified for exactly this — `MACLC_SELFTEST=1`
constructing every pane and logging what built — but the delegation service kept
failing mid-edit, twice leaving damaged files that had to be reverted. It is
worth finishing. The specification is in the session notes; it needs two files
and a three-line hook in `-applicationDidFinishLaunching:`.

## Known debt

- `MacLCHDRSettingsViewController` defines its own `MacLCSettingsRowView` and
  `MacLCStatusRowView` while the settings window has `MacLCSettingsRow`. They
  were written in parallel and should be consolidated onto the shared builder.
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
