# Project structure

MacLC is a macOS-only media player targeting macOS 26.0 and later on Apple Silicon, compiled with Xcode 27.2 against the macOS 27 SDK. It builds on the VLC 4 core; code for other operating systems has been removed.

## Top level

- `autotools/`: GNU Autoconf and Automake helper scripts.
- `bin/`: Process entry point and executable wrapper sources.
- `buildsystem/`: Build harness scripts and cargo test runner.
- `compat/`: Portability shim library for POSIX and standard C library routines.
- `contrib/`: Build infrastructure for pinned third-party library dependencies.
- `doc/`: Documentation and ChangeLogs; `doc/upstream/` holds upstream `README`, `NEWS`, and `INSTALL`.
- `extras/`: Packaging targets, platform build scripts, code analysis tools, and icon generators.
- `include/`: Public LibVLC API headers in `include/vlc/` and core internal headers.
- `lib/`: LibVLC public interface library implementation (`libvlc.la`).
- `m4/`: Autotools macro definitions.
- `modules/`: Media player plugins and native interface modules.
- `po/`: Gettext localization string catalogs and `po/POTFILES.in`.
- `share/`: Common shared assets, HRTF profiles, and platform resource templates.
- `src/`: LibVLCcore core engine and Darwin system abstraction layer (`src/darwin/`).
- `test/`: Core test suite and integration test harness.
- `MacLC.xcodeproj`: Root Xcode project for native AppKit interface plugin development.
- `MacLC.xcconfig`: Root Xcode project build configuration and deployment settings.
- `Makefile.am`: Top-level Automake build rules and subdirectories.
- `configure.ac`: Autoconf configuration script and platform feature checks.
- `bootstrap`: Build generation bootstrap script using GNU autoreconf.
- `README.md`: MacLC project overview, installation instructions, and architecture guide.
- `COPYING`: GNU General Public License version 2.0 text.
- `COPYING.LIB`: GNU Lesser General Public License version 2.1 text.
- `AUTHORS`: Upstream VLC and MacLC author credits.
- `THANKS`: Upstream contributors and third-party dependency acknowledgments.

## The macOS app

All GUI sources reside in `modules/gui/macosx/` (Objective-C with ARC and AppKit).

| Folder | What lives there | Entry files |
|---|---|---|
| `coreinteraction` | Hotkeys handling, OSD notifications, and video filter helper | `VLCHotkeysController.m`, `VLCVideoFilterHelper.m`, `MacLCOSDController.m` |
| `extensions` | AppKit and Foundation category extensions and formatting helpers | `NSMenu+VLCAdditions.m`, `NSColor+VLCAdditions.m`, `MacLCVolumePath.m` |
| `imported` | Third-party input device integration wrappers | `imported/AppleRemote/AppleRemote.m`, `imported/SPMediaKeyTap/SPMediaKeyTap.m` |
| `library` | Core media library window controllers, outlines, and split views | `VLCLibraryController.m`, `VLCLibraryWindow.m`, `VLCLibraryModel.m` |
| `library/groups-library` | Media grouping controller and collection data source | `library/groups-library/VLCLibraryGroupsViewController.m`, `library/groups-library/VLCLibraryGroupsDataSource.m` |
| `library/home-library` | Home view carousels, action buttons, and stack views | `library/home-library/VLCLibraryHomeViewController.m`, `library/home-library/VLCLibraryHomeViewActionsView.m` |
| `library/video-library` | Movies and TV show data sources and collection views | `library/video-library/VLCLibraryVideoViewController.m`, `library/video-library/VLCLibraryMoviesDataSource.m` |
| `library/audio-library` | Audio tracks, albums, and artist views | `library/audio-library/VLCLibraryAudioViewController.m`, `library/audio-library/VLCLibraryAlbumTableCellView.m` |
| `library/favorites-library` | Favorite media listings and table data source | `library/favorites-library/VLCLibraryFavoritesViewController.m`, `library/favorites-library/VLCLibraryFavoritesDataSource.m` |
| `library/media-source` | Local and network media browsing and source navigation | `library/media-source/VLCLibraryMediaSourceViewController.m`, `library/media-source/VLCMediaSourceProvider.m` |
| `library/playlist-library` | User playlist view controllers and data sources | `library/playlist-library/VLCLibraryPlaylistViewController.m`, `library/playlist-library/VLCLibraryPlaylistDataSource.m` |
| `library/search-library` | In-library search provider and results controller | `library/search-library/VLCLibrarySearchViewController.m`, `library/search-library/VLCLibrarySearchProvider.m` |
| `medialib/components` | Reusable library cards, artwork loaders, and section headers | `medialib/components/MacLCArtworkView.m`, `medialib/components/MacLCHeroView.m` |
| `medialib/data` | Media library central data store, action handlers, and types | `medialib/data/MacLCLibraryStore.m`, `medialib/data/MacLCLibraryActions.m` |
| `medialib/sections` | Library sections (Home, Movies, Shows, Albums, artist and genre pages) | `medialib/sections/MacLCLibraryHomeViewController.m`, `medialib/sections/MacLCLibraryAlbumsViewController.m` |
| `medialib/shell` | Library window sidebar, toolbar, Now Playing bar, Up Next inspector | `medialib/shell/MacLCLibrarySidebarViewController.m`, `medialib/shell/MacLCNowPlayingBar.m`, `medialib/shell/MacLCUpNextViewController.m` |
| `main` | Application lifecycle, NSApplication subclass, and plugin entry | `main/macosx.m`, `main/VLCMain.m`, `main/VLCApplication.m` |
| `menus` | Menu bar definitions, dynamic library menus, and status bar item | `menus/VLCMainMenu.m`, `menus/MacLCLibraryMenus.m`, `menus/MacLCMenuSymbols.m` |
| `menus/renderers` | Casting discovery and renderer menu selection | `menus/renderers/VLCRendererDiscovery.m`, `menus/renderers/VLCRendererMenuController.m` |
| `os-integration` | System services, AppleScript support, and volume integration | `os-integration/applescript.m`, `os-integration/VLCDocumentController.m`, `os-integration/VLCClickerManager.m` |
| `panels` | Audio/video adjustments, track synchronization, and bookmarks | `panels/VLCAudioEffectsWindowController.m`, `panels/VLCVideoEffectsWindowController.m` |
| `panels/bookmarks` | Playback bookmarks list and table controller | `panels/bookmarks/VLCBookmark.m`, `panels/bookmarks/VLCBookmarksTableViewDataSource.m` |
| `panels/dialogs` | Core modal dialogs, error alerts, and playback resume prompt | `panels/dialogs/VLCCoreDialogProvider.m`, `panels/dialogs/VLCResumeDialogController.m` |
| `playqueue` | Playback queue state, player controller, and saved positions | `playqueue/VLCPlayQueueController.m`, `playqueue/VLCPlayQueueModel.m`, `playqueue/MacLCResumePosition.m` |
| `preferences` | Legacy preferences windows and configuration widgets | `preferences/prefs.m`, `preferences/VLCSimplePrefsController.m` |
| `settings` | System Settings-style preference window and custom rows | `settings/MacLCSettingsWindowController.m`, `settings/MacLCSettingsRow.m`, `settings/MacLCConfigSafe.m` |
| `settings/panes` | Categorized preference panes (General, HDR, Video, Audio, Upscaling) | `settings/panes/MacLCHDRSettingsViewController.m`, `settings/panes/MacLCGeneralSettingsViewController.m` |
| `shaders` | Snow overlay Metal shaders and shader vertex structures | `shaders/VLCSnowShader.metal`, `shaders/VLCShaderTypes.h` |
| `hdr` | Display headroom monitoring, HDR advisor, and tone curve views | `hdr/MacLCHDRController.m`, `hdr/MacLCDisplayInfo.m`, `hdr/MacLCSDRToHDRPanelViewController.m` |
| `frameinterp` | Real-time motion interpolation UI and settings panel | `frameinterp/MacLCFrameInterpolation.m`, `frameinterp/MacLCFrameInterpolationPanelViewController.m` |
| `upscale` | GPU upscaler configuration panel (MetalFX, FSR, NIS, Anime4K) | `upscale/MacLCUpscaling.m`, `upscale/MacLCUpscalingPanelViewController.m` |
| `addons` | Addon discovery, installation window, and stream inspector | `addons/MacLCAddons.m`, `addons/MacLCAddonSearchWindowController.m`, `addons/MacLCStreamFacts.m` |
| `addons/watch` | Watch feature, Stremio catalog discovery, and stream picker | `addons/watch/MacLCWatchDiscovery.m`, `addons/watch/MacLCWatchBrowse.m`, `addons/watch/MacLCStreamPicker.m` |
| `torrent` | Streaming BitTorrent monitor, download view, and buffer status | `torrent/MacLCTorrentMonitor.m`, `torrent/MacLCTorrentStats.m`, `torrent/MacLCTorrentLoadingView.m` |
| `youtube` | YouTube playback via yt-dlp, sign-in window, and subscriptions | `youtube/MacLCYouTubeModel.m`, `youtube/MacLCYouTubeService.m`, `youtube/MacLCYouTubeSignInWindowController.m` |
| `cast` | AirPlay and Chromecast output controller and network discovery | `cast/MacLCCastController.m`, `cast/MacLCNetworkAddress.m`, `cast/MacLCCastStatusView.m` |
| `sound` | Voice Boost DSP controls, sound presets, and 10-band equalizer | `sound/MacLCSoundPanelViewController.m`, `sound/MacLCSoundPresets.m`, `sound/MacLCEqualizerBandsView.m` |
| `theme` | Liquid Glass materials, design tokens, format badges, and buttons | `theme/MacLCDesign.m`, `theme/MacLCGlassView.m`, `theme/MacLCCardView.m` |
| `webvideo` | Web video URL resolver and playback history via yt-dlp | `webvideo/MacLCWebVideoResolver.m`, `webvideo/MacLCWebVideoPanelController.m`, `webvideo/MacLCWebVideoHistory.m` |
| `views` | Reusable AppKit controls, sliders, and progress indicators | `views/VLCPlaybackProgressSlider.m`, `views/VLCVolumeSlider.m`, `views/VLCLoadingOverlayView.m` |
| `views/iCarousel` | Cover flow carousel view component | `views/iCarousel/iCarousel.h`, `views/iCarousel/iCarousel.m` |
| `windows` | Utility windows (About, Open Media, Error, Help) | `windows/VLCAboutWindowController.m`, `windows/VLCOpenWindowController.m`, `windows/VLCErrorWindowController.m` |
| `windows/addons` | Addon manager window controller and list cell items | `windows/addons/VLCAddonsWindowController.m`, `windows/addons/VLCAddonListItem.m` |
| `windows/convertandsave` | Media transcoding and file export window controller | `windows/convertandsave/VLCConvertAndSaveWindowController.m`, `windows/convertandsave/VLCOutput.m` |
| `windows/extensions` | Scripted dialog manager and extension widgets | `windows/extensions/VLCExtensionsManager.m`, `windows/extensions/VLCExtensionsDialogProvider.m` |
| `windows/logging` | Debug log viewer window controller and log messages | `windows/logging/VLCLogWindowController.m`, `windows/logging/VLCLogMessage.m` |
| `windows/controlsbar` | Playback control bars for main and detached video windows | `windows/controlsbar/VLCMainWindowControlsBar.m`, `windows/controlsbar/VLCMainVideoViewControlsBar.m` |
| `windows/video` | Video output windows, full screen, and aspect ratio fitting | `windows/video/VLCMainVideoViewController.m`, `windows/video/MacLCVideoFitGeometry.m`, `windows/video/VLCVideoOutputProvider.m` |
| `UI` | Interface Builder XIB layout definitions | `UI/MainMenu.xib`, `UI/VLCLibraryWindow.xib`, `UI/VLCMainVideoView.xib` |
| `Resources` | Asset catalog, Icon Composer app icon, and neural models | `Resources/Assets.xcassets/Contents.json`, `Resources/App-Icons/MacLC.icon/icon.json` |
| `tests` | XCTest unit test suites for UI logic, geometry, and models | `tests/MacLCVideoFitGeometryTest.m`, `tests/MacLCSDRToHDRTest.m`, `tests/MacLCUpscalingTest.m` |

## Core and plugins

- `src/`: LibVLCcore core engine managing the input pipeline, clock, video/audio output, playlist, dynamic module bank, and Darwin platform abstractions (`src/darwin/`).
- `lib/`: LibVLC public API library (`libvlc.la`) exposing player, media, audio, and video controls.
- `include/`: Header tree split between LibVLC public API (`include/vlc/`) and core internal headers.
- `compat/`: Portability shim library (`libcompat.la`) implementing missing POSIX and standard C library routines.

Module categories in `modules/`:
- `modules/access`: Input access plugins; Apple capture: `libavcapture_plugin.la`, `libavaudiocapture_plugin.la`, and macOS screen grab `libscreen_plugin.la`.
- `modules/access_output`: Stream output access modules (file, UDP, HTTP, livehttp, SRT).
- `modules/audio_filter`: Audio DSP and channel processing plugins (equalizer, spatializer, resamplers).
- `modules/audio_mixer`: Audio downmixing and software floating-point channel mixers.
- `modules/audio_output`: Audio output plugins; Apple backends: `libauhal_plugin.la` (CoreAudio AUHAL) and `libavsamplebuffer_plugin.la` (AVFoundation sample buffer renderer).
- `modules/codec`: Audio/video decoders and encoders; Apple hardware codecs: `libvideotoolbox_plugin.la` (VideoToolbox hardware decoding) and `libvideotoolbox_enc_plugin.la`.
- `modules/control`: Automation and remote control interfaces (gestures, hotkeys, netsync).
- `modules/demux`: Container demuxers for all major media formats (MKV, MP4, AVI, TS, FLAC, OGG, HLS).
- `modules/gui`: Graphical interface plugins; Apple interface: `libmacosx_plugin.la` in `modules/gui/macosx`.
- `modules/isa`: Architecture-specific SIMD routines (`isa/aarch64` ARM64 NEON optimizations, `isa/x86`).
- `modules/keystore`: Secure credential storage; Apple backend: `libkeychain_plugin.la` (macOS Keychain via Security.framework).
- `modules/logger`: Logging drivers for console, file, and system log.
- `modules/lua`: Lua runtime for metadata extraction and external script support.
- `modules/meta_engine`: Metadata parsing plugins (ID3 tags, TagLib).
- `modules/misc`: Core utility plugins; Apple utilities: `libiokit_inhibit_plugin.la` (IOKit sleep inhibitor) and `libsecuretransport_plugin.la` (Security.framework TLS).
- `modules/mux`: Container multiplexers for stream generation (TS, MP4, OGG, AVI, WAV).
- `modules/notify`: `osx_notifications.m`, a notification plugin on the deprecated NSUserNotification API; the build does not enable it.
- `modules/packetizer`: Elementary stream packetizers for H.264, HEVC, AV1, and audio formats.
- `modules/services_discovery`: Network service discovery providers including Bonjour/mDNS.
- `modules/spu`: Subpicture visual filters and overlay compositors.
- `modules/stream_extractor`: Archive content stream extraction (zip, tar).
- `modules/stream_filter`: Stream preprocessing pipelines (cache_read, prefetch, record).
- `modules/stream_out`: Transcoding, broadcast, and streaming output pipeline.
- `modules/text_renderer`: Font rendering; Apple plugins: `libnsspeechsynthesizer_plugin.la` (macOS speech synthesis) and CoreText Darwin backend in `libfreetype_plugin.la`.
- `modules/video_chroma`: Chroma conversion; Apple plugin: `libcvpx_plugin.la` (CVPixelBuffer wrapping and NEON-accelerated conversions).
- `modules/video_filter`: Video filters; Apple/MacLC plugins: `libmaclc_frc_plugin.la` (real-time frame interpolation via Metal/CoreML/RIFE) and `libci_filters_plugin.la` (Core Image).
- `modules/video_output`: Video output display modules; Apple backends in `video_output/apple`: `libsamplebufferdisplay_plugin.la` (AVSampleBufferDisplayLayer output with EDR) and MacLC's Metal renderer, SDR-to-HDR expander, upscalers and Dolby Vision passes (`MacLCMetal*.m`, `MacLCSDR2HDRSession.m`).
- `modules/video_splitter`: Video wall and multi-window splitting modules.
- `modules/visualization`: Audio visualizers (projectM, visual, goom).

## Building and testing

- Configure a build in `build/` (the first lines of `build/config.log` show the exact command of an existing build):
  ```bash
  mkdir -p build && cd build
  ../configure --disable-lua --disable-xcb --disable-alsa --disable-pulse --disable-vnc \
      --disable-dbus --disable-sparkle --disable-macosx-ui-shaders \
      --enable-macosx --enable-macosx-avfoundation --with-macosx-version-min=26.0 \
      PKG_CONFIG_PATH="$PWD/../build-deps/prefix/lib/pkgconfig:$PWD/../build-deps/pkgconfig:/opt/homebrew/lib/pkgconfig"
  ```
- Build core and plugins: `make -j12` (or `make -C build -j12`).
- Package application and DMG: `make -j12 package-macosx` produces `MacLC.app` and `maclc-<version>.dmg`.
- Run unit tests: `make check-macosx` executed from `build/modules` runs the XCTest suite in `modules/gui/macosx/tests`.
- Xcode project workflow (`MacLC.xcodeproj`, `MacLC.xcconfig`):
  - Scheme `MacLC-Package`: runs `make -j12 package-macosx` in `build/` to package dependencies and framework plugins.
  - Scheme `MacLC`: compiles `libmacosx_plugin.dylib` natively, copies it into `build/MacLC.app/Contents/Frameworks/plugins/`, and launches `build/MacLC.app`.
- Packaging scripts in `extras/package/macosx/`:
  - `build-medialibrary.sh`, `build-taglib.sh`, `build-dvbpsi.sh`: compiles pinned dependency libraries from `contrib/src`.
  - `bundle-dylibs.py`: bundles dynamically linked libraries and rewrites Mach-O install names.
  - `codesign.sh`: signs application binaries and plugins using entitlements in `VLC.entitlements`.
  - `make-release.sh`: runs clean builds, sample media playback smoke tests, and final release DMG generation.

## Where to start

1. Add a Settings pane: Create a view controller in `modules/gui/macosx/settings/panes/`, implement `MacLCSettingsPane`, and register it in `modules/gui/macosx/settings/MacLCSettingsWindowController.m`.
2. Add a library section: Define the section enum in `modules/gui/macosx/medialib/sections/MacLCLibrarySections.h`, implement its view controller in `modules/gui/macosx/medialib/sections/`, and register the sidebar entry in `modules/gui/macosx/medialib/shell/MacLCLibrarySidebarViewController.m`.
3. Change the HDR pipeline: Open the Metal video display renderer `modules/video_output/apple/MacLCMetalDisplay.m`, SDR-to-HDR session `modules/video_output/apple/MacLCSDR2HDRSession.m`, color curves in `modules/video_output/apple/maclc_sdr2hdr.h`, or UI state in `modules/gui/macosx/hdr/MacLCHDRController.m`.
4. The video window: Open video playback controller `modules/gui/macosx/windows/video/VLCMainVideoViewController.m` and window geometry fitting in `modules/gui/macosx/windows/video/MacLCVideoFitGeometry.m`.
5. The play queue: Open queue controller `modules/gui/macosx/playqueue/VLCPlayQueueController.m`, queue model `modules/gui/macosx/playqueue/VLCPlayQueueModel.m`, and resume position tracker `modules/gui/macosx/playqueue/MacLCResumePosition.m`.
6. A menu: Open menu bar controller `modules/gui/macosx/menus/VLCMainMenu.m`, library menu actions in `modules/gui/macosx/menus/MacLCLibraryMenus.m`, or layout template `modules/gui/macosx/UI/MainMenu.xib`.
7. Localized strings: Register translatable files in `po/POTFILES.in`, edit translation files in `po/*.po`, or edit bundle strings in `modules/gui/macosx/Resources/Base.lproj/InfoPlist.strings`.
8. App icon and assets: Edit vector icon generator script `extras/package/macosx/asset_sources/maclc_app_icon.swift`, Icon Composer layer descriptor `modules/gui/macosx/Resources/App-Icons/MacLC.icon/icon.json`, or asset catalog in `modules/gui/macosx/Resources/Assets.xcassets/`.
