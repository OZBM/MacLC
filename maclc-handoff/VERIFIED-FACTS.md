# MacLC — verified facts about `modules/gui/macosx/`

These were checked directly against the tree. Where they contradict
`.maclc-design/RECON-GUI.md`, **this file wins** — the recon report invented
several plausible-looking paths and APIs that do not exist.

## Directory layout (real)

```
modules/gui/macosx/
├── coreinteraction/   VLCHotkeysController, VLCVideoFilterHelper
├── extensions/        NS*+VLCAdditions categories, NSString+Helpers
├── imported/          AppleRemote, SPMediaKeyTap
├── library/           VLCLibraryWindow*, sidebar, toolbar delegate, segments,
│                      split-view controller, per-media-type sub-directories
├── main/              VLCMain, VLCApplication, VLCMain+OldPrefs,
│                      VLCMain+Sparkle, macosx.m (module descriptor + options)
├── menus/             VLCMainMenu, VLCStatusBarIcon
├── os-integration/    applescript, remote control, document controller
├── panels/            effects / info / bookmarks window controllers
├── playqueue/         VLCPlayerController, play queue model + views
├── preferences/       VLCSimplePrefsController, VLCSimplePrefsWindow,
│                      prefs.m (advanced tree), prefs_widgets.m
├── shaders/           Metal shader + types
├── tests/             XCTest targets, has its own Makefile.am
├── views/             reusable views AND VLCUIUnits (the metrics token class)
├── windows/           about, open, help, error, connect-to-server
│   ├── controlsbar/   the playback controls bar lives HERE
│   └── video/         video window + VLCMainVideoViewController
└── UI/                49 XIBs
```

**There is no `main-controls/` directory and no `common/` directory.**

## Design helpers that already exist

| What | Where | Note |
|---|---|---|
| Layout metrics | `views/VLCUIUnits.h` (127 lines) | Real token class. `largeSpacing`, `mediumSpacing`, `smallSpacing`, `cornerRadius`, `borderThickness`, row heights, collection-view sizing, `libraryWindowControlsBarHeight`, `controlsFadeAnimationDuration`, and more, all as `@property (class, readonly)`. Extend this rather than duplicating it. |
| Colours | `extensions/NSColor+VLCAdditions.h` | A **small** category, lines 27–44. There is no `vlcTintColor` and no `#FF8800` constant anywhere in it. Read it before assuming an API. |
| Fonts | `extensions/NSFont+VLCAdditions.h` | Small category, starts line 27. |
| Images / SF Symbols | `extensions/NSImage+VLCAdditions.h` | Already has symbol-name loading and async image helpers. |
| Appearance | `extensions/NSAppearance+VLCAdditions.h` | Light/dark helpers. |
| Animation | `extensions/NSAnimationContext+VLCAdditions.h` | |

**Always open the header before calling anything from these categories.**

## Build wiring — autotools only

- `modules/gui/macosx/Makefile.am` is the only build file that matters.
  Sources go in `libmacosx_plugin_la_SOURCES`; XIBs and resources go in the
  `nobase_libmacosx_plugin_la_DATA` list.
- `modules/gui/meson.build` does **not** build `modules/gui/macosx` at all — it
  only knows about `minimal_macosx`. Do not add macOS GUI files to meson;
  it is dead weight for this app. (This part of the recon report is correct.)
- Any file containing `_NS("...")` must also be listed in `po/POTFILES.in`.
- Tests live in `modules/gui/macosx/tests/` and have their own `Makefile.am`.
  `NSStringHelpersTest.m` is the model to copy for a new unit test.

## Preferences — how they work today

- **Simple Preferences**: `preferences/VLCSimplePrefsController.{h,m}` driven by
  `UI/SimplePreferences.xib`. An `NSToolbar` of icons switches between five
  views (Audio, Video, Subtitles/OSD, Input/Codecs, Hotkeys). Each `setup*View`
  method reads current values with `config_GetInt/GetPsz/GetFloat`, and
  `applyChanges:` writes them back with `config_PutInt/PutPsz/PutFloat` followed
  by `config_SaveConfigFile()`.
- **Advanced Preferences**: `preferences/prefs.m` + `prefs_widgets.m`, fully
  programmatic. It walks the module registry (`module_list_get`,
  `module_config_get`) and builds a widget per `module_config_t`. This is the
  escape hatch and must keep working untouched.
- The existing HDR controls are already in the Video pane of Simple
  Preferences: `_video_hdrModePopup` (`macosx-hdr-mode`),
  `_video_edrHeadroomTextField` (`macosx-edr-headroom`) and a read-only
  `_video_hdrStatusLabel`.

## Localisation

- No `Localizable.strings` for UI text. Everything goes through
  `_NS("literal")` -> `toNSStr(vlc_gettext(s))`
  (`extensions/NSString+Helpers.h`), i.e. GNU gettext with the `vlc` domain.
- The only Apple `.strings` files are
  `Resources/*.lproj/InfoPlist.strings` (privacy usage descriptions).
- New user-visible English strings: wrap in `_NS()`, and add the file to
  `po/POTFILES.in`. Never invent a new `.strings` file.

## Build / verification commands

- Syntax-check a file from a worktree: `./.maclc-design/syntax-check.sh <file.m>`
- Full incremental plugin build (reference tree only):
  `make -C build/modules libmacosx_plugin.la`
