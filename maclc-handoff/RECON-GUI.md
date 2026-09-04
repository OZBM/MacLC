# macOS Native GUI Architecture Reconnaissance (VLC 4.0-dev)

**Target Codebase:** `modules/gui/macosx/`  
**Report File:** `/Users/omarbenmustapha/Downloads/vlc-master/.maclc-recon/RECON-GUI.md`  
**Purpose:** Comprehensive architecture map for restyling VLC into a modern, native macOS application.

---

## 1. Entry Points and Window Architecture

### 1.1 Interface Plugin Entry Points & Lifecycle
- **VLC Module Definition:** `modules/gui/macosx/macosx.m:131-202`
  - Defines the interface capability: `set_capability("interface", 100)` (`macosx.m:137`).
  - Sets module callbacks: `set_callbacks(Open, Close)` (`macosx.m:138`).
  - Defines interface options: `macosx-interfacestyle` (`macosx.m:140`, default 1 for modern unified library vs 0 for classic detached window), `macosx-embedded-video` (`macosx.m:143`), and `macosx-video-autoresize` (`macosx.m:147`).
- **Initialization Routine (`Open`):** `modules/gui/macosx/macosx.m:169-202`
  - Initializes `NSApplication`: `[NSApplication sharedApplication]` (`macosx.m:173`).
  - Loads main menu nib: `[[NSBundle mainBundle] loadNibNamed:@"MainMenu" owner:NSApp topLevelObjects:&topLevelObjects]` (`macosx.m:176-177`).
  - Instantiates `VLCMain`: `[VLCMain sharedInstance]` (`macosx.m:178`).
  - Sets application delegate: `[NSApp setDelegate:[VLCMain sharedInstance]]` (`macosx.m:181`).
  - Starts event loop: runs `[NSApp run]` on the main Cocoa thread or enters run loop (`macosx.m:190-194`).
- **Application Delegate (`VLCMain`):** `modules/gui/macosx/VLCMain.m:164-262`
  - `applicationWillFinishLaunching:` (`VLCMain.m:164-203`) sets up app appearance, registers notification observers, and initializes core intf bindings.
  - `applicationDidFinishLaunching:` (`VLCMain.m:205-262`) creates and shows the library window (`VLCMain.m:215`), initializes media source provider (`VLCMain.m:228`), registers sleep/wake power management hooks, and initializes global hotkeys.
  - Singleton & Accessors (`VLCMain.m:300-393`): Provides `sharedInstance` (`VLCMain.m:300`), access to `libraryWindow` (`VLCMain.m:356`), and `videoOutputProvider` (`VLCMain.m:380`).

### 1.2 Window Class Hierarchy & Inheritance
All main windows inherit from a single Cocoa hierarchy:
```
NSWindow
  ↳ VLCWindow (modules/gui/macosx/windows/VLCWindow.h:26)
      ↳ VLCVideoWindowCommon (modules/gui/macosx/windows/video/VLCVideoWindowCommon.h:35)
          ↳ VLCFullVideoViewWindow (modules/gui/macosx/windows/video/VLCFullVideoViewWindow.h:25)
              ↳ VLCLibraryWindow (modules/gui/macosx/library/VLCLibraryWindow.h:33)
          ↳ VLCDetachedVideoWindow (modules/gui/macosx/windows/video/VLCDetachedVideoWindow.h:26)
```
- `VLCWindow` (`windows/VLCWindow.m:25-90`): Custom window handling fullscreen behavior, custom styling masks, and key-window overrides.
- `VLCVideoWindowCommon` (`windows/video/VLCVideoWindowCommon.m:34-180`): Base class managing video aspect ratio, mouse hiding timers, fullscreen animations, and video layout logic.
- `VLCFullVideoViewWindow` (`windows/video/VLCFullVideoViewWindow.m:28-115`): Extends video window to support full-content view embedding and titlebar hiding.
- `VLCLibraryWindow` (`library/VLCLibraryWindow.m:35-980`): The modern primary window combining media library browsing, unified toolbar, embedded video playback, and controls bar.
- `VLCDetachedVideoWindow` (`windows/video/VLCDetachedVideoWindow.m:33-145`): Legacy/detached video output window used when embedded video is disabled.

### 1.3 Video Output Routing (`VLCVideoOutputProvider`)
- **File & Class:** `modules/gui/macosx/windows/video/VLCVideoOutputProvider.m:43-395`, `VLCVideoOutputProvider`.
- **Mechanism:** Implements `vlc_player_vout_listener` callbacks (`VLCVideoOutputProvider.m:188`) to monitor video track lifecycle.
- **Routing Decision:** `getVideoViewForPlayer:andVideoOutput:withWindowType:atWindow:` (`VLCVideoOutputProvider.m:372-395`):
  - Evaluates `macosx-embedded-video` (`config_GetInt("macosx-embedded-video")`).
  - When embedded: routes video output to `VLCLibraryWindow.videoViewContainer` (`VLCVideoOutputProvider.m:385`).
  - When detached or non-embedded: allocates and presents a `VLCDetachedVideoWindow` (`VLCVideoOutputProvider.m:390`).

### 1.4 Library Window Mode vs. Video Window Mode
- **Controller & Implementation:** `modules/gui/macosx/library/VLCLibraryWindow.m:633-726`.
- **Mode Switching:**
  - `showVideoView` (`VLCLibraryWindow.m:633-670`):
    - Hides library navigation sidebar and central collection/table views.
    - Activates `VLCMainVideoViewController` view within the primary window container.
    - Switches toolbar configuration: swaps library search/view toggles for video controls (aspect ratio, audio/subtitle selector).
    - Reconfigures `VLCMainWindowControlsBar` for active video playback.
  - `hideVideoView` (`VLCLibraryWindow.m:672-702`):
    - Re-displays library sidebar and library contents.
    - Tears down active video rendering surface.
    - Restores library toolbar items.
  - `setupWindowLayout` (`VLCLibraryWindow.m:704-726`): Configures split-view constraints between the sidebar and content views.

### 1.5 Classic / Legacy Window Mode
- Controlled via `macosx-interfacestyle` (`macosx.m:140`):
  - Value `1`: Modern single-window interface (`VLCLibraryWindow` hosting both library and video).
  - Value `0`: Classic interface. The playlist/controls and video output reside in separate windows (`VLCDetachedVideoWindow` at `windows/video/VLCDetachedVideoWindow.m:33-145` with `VLCClassicMainVideoView.xib`).
- Video Presentation: `modules/gui/macosx/windows/video/VLCMainVideoViewController.m:56, 125-127, 318` adapts rendering between modern embedded views and detached classic windows.

### 1.6 Controls Bars Architecture
- **Base Class:** `modules/gui/macosx/main-controls/VLCControlsBarCommon.h:35-104`, `VLCControlsBarCommon.m:35-265`
  - Encapsulates common playback controls: Play/Pause button (`playButton`), Previous/Next (`prevButton`, `nextButton`), Time slider (`timeSlider`), Volume slider (`volumeSlider`), and Time display labels (`currentTimeField`, `remainingTimeField`).
  - Connects to core player callbacks (`vlc_player_listener_id`) for time and state updates.
- **Library Controls Bar:** `modules/gui/macosx/main-controls/VLCMainWindowControlsBar.h:27`, `VLCMainWindowControlsBar.m:34-118`
  - Subclass docked permanently at the bottom of `VLCLibraryWindow`.
  - Integrates shuffle, repeat, playlist toggle, audio effects, and fullscreen toggle buttons.
- **Video Controls Bar (HUD):** `modules/gui/macosx/main-controls/VLCMainVideoViewControlsBar.h:27`, `VLCMainVideoViewControlsBar.m:34-192`
  - Floating / HUD overlay controls bar shown during video playback and fullscreen.
  - Auto-hides on mouse inactivity (`setupTimer` at `m:82`).
- **Container View:** `modules/gui/macosx/main-controls/VLCBottomBarView.h:26`, `VLCBottomBarView.m:35-110`
  - Custom `NSView` hosting the controls bar with custom background drawing, border lines, and material vibrancy.

### 1.7 Complete XIB Inventory (49 XIB Files)
All 49 XIB files reside in `modules/gui/macosx/UI/`. Below is the complete mapping of XIB files to their owning controllers and responsibilities:

| XIB File | Owning Controller / Class | Responsibility |
|---|---|---|
| `About.xib` | `VLAboutWindowController` | About box, version info, credits, license |
| `AddonManager.xib` | `VLCAddonManagerWindowController` | Extension and add-on installation window |
| `AudioEffects.xib` | `VLCAudioEffectsWindowController` | Graphic equalizer, spatializer, compressor |
| `Bookmarks.xib` | `VLCBookmarksWindowController` | Media bookmark list and editor |
| `ConvertAndSave.xib` | `VLCConvertAndSaveWindowController` | Transcoding and stream save wizard |
| `CoreDialogs.xib` | `VLCCoreDialogProvider` | Core authentication, warnings, and dialogs |
| `ErrorPanel.xib` | `VLCErrorWindowController` | Error message presentation panel |
| `Help.xib` | `VLCHelpWindowController` | Offline help documentation viewer |
| `LogMessageWindow.xib` | `VLCLogWindowController` | Debug message log console |
| `MainMenu.xib` | `NSApplication` / `VLCMain` | Application menu bar, menu items, shortcuts |
| `Open.xib` | `VLCOpenWindowController` | Open File, Disc, Network, and Capture panels |
| `PlaylistAccessoryView.xib` | `VLCPlaylistAccessoryView` | Open dialog playlist accessory view |
| `PopupPanel.xib` | `VLCPopupPanelController` | Generic modal alert / prompt popup |
| `Preferences.xib` | `VLCPrefs` | Top-level container for Preferences window |
| `ResumeDialog.xib` | `VLCResumeDialogController` | Resume playback position prompt |
| `SimplePreferences.xib` | `VLCSimplePrefsController` | Simple preferences tabs (Audio, Video, etc.) |
| `StreamOutput.xib` | `VLCStreamOutputWindowController` | Network stream output configuration |
| `SyncTracks.xib` | `VLCTrackSynchronizationWindowController` | Audio/video and subtitle sync delay adjustments |
| `TextfieldPanel.xib` | `VLCTextfieldPanelController` | Single-input text prompt panel |
| `TimeSelectionPanel.xib` | `VLCTimeSelectionPanelController` | Jump-to-time timecode input panel |
| `VLCClassicMainVideoView.xib` | `VLCClassicMainVideoViewController` | Video container for detached/classic mode |
| `VLCCustomCropARPanel.xib` | `VLCCustomCropArPanelController` | Custom crop and aspect ratio editor panel |
| `VLCDetachedAudioWindow.xib` | `VLCDetachedAudioWindowController` | Detached audio-only visualizer window |
| `VLCFullScreenPanel.xib` | `VLCMainVideoViewControlsBar` | HUD overlay controls in fullscreen |
| `VLCInformationWindow.xib` | `VLCInformationWindowController` | Media info, codec details, metadata inspector |
| `VLCLibraryAlbumTableCellView.xib` | `VLCLibraryAlbumTableCellView` | Table cell for music album rows |
| `VLCLibraryCarouselViewItemView.xib` | `VLCLibraryCarouselViewItemView` | Carousel item in media library home view |
| `VLCLibraryCollectionViewAudioGroupSupplementaryDetailView.xib` | `VLCLibraryCollectionViewSupplementaryElementView` | Detail header view for audio groups |
| `VLCLibraryCollectionViewMediaItemListSupplementaryDetailView.xib` | `VLCLibraryCollectionViewSupplementaryElementView` | Detail header view for media item lists |
| `VLCLibraryCollectionViewMediaItemSupplementaryDetailView.xib` | `VLCLibraryCollectionViewSupplementaryElementView` | Supplementary detail banner for media items |
| `VLCLibraryHeroView.xib` | `VLCLibraryHeroView` | Hero media banner in library home view |
| `VLCLibraryHomeViewActionsView.xib` | `VLCLibraryHomeViewActionsView` | Quick action buttons in library home view |
| `VLCLibrarySongTableCellView.xib` | `VLCLibrarySongTableCellView` | Table cell for individual audio tracks |
| `VLCLibraryTableCellView.xib` | `VLCLibraryTableCellView` | Generic media item table cell |
| `VLCLibraryVideoTableCellView.xib` | `VLCLibraryVideoTableCellView` | Table cell for video library rows |
| `VLCLibraryWindow.xib` | `VLCLibraryWindow` | Main library window root frame and split views |
| `VLCLibraryWindowChaptersView.xib` | `VLCLibraryWindowChaptersViewController` | Chapter selection sidebar/popup view |
| `VLCLibraryWindowNavigationSidebarView.xib` | `VLCLibraryWindowNavigationSidebarViewController` | Sidebar outline view and scroll view |
| `VLCLibraryWindowPlayQueueView.xib` | `VLCLibraryWindowPlayQueueViewController` | Play queue (now playing) drawer/panel |
| `VLCLibraryWindowSidebarRootView.xib` | `VLCLibraryWindowSidebarRootViewController` | Root container for library navigation sidebar |
| `VLCLibraryWindowTitlesView.xib` | `VLCLibraryWindowTitlesViewController` | Title selection sidebar/popup view |
| `VLCMainVideoView.xib` | `VLCMainVideoViewController` | Embedded main video presentation view |
| `VLCMainVideoViewAudioMediaDecorativeView.xib` | `VLCMainVideoViewController` | Artwork & audio metadata background decorative view |
| `VLCMediaItemCollectionViewItem.xib` | `VLCMediaItemCollectionViewItem` | Grid collection view item for media items |
| `VLCMediaSourceDeviceCollectionViewItem.xib` | `VLCMediaSourceDeviceCollectionViewItem` | Collection item for network/device sources |
| `VLCPlayQueueTableCellView.xib` | `VLCPlayQueueTableCellView` | Row cell for active play queue table |
| `VLCPlaybackEndView.xib` | `VLCPlaybackEndViewController` | Post-playback recommended media screen |
| `VLCStatusBarIconMainMenu.xib` | `VLCStatusBarIcon` | macOS menu bar status item menu |
| `VideoEffects.xib` | `VLCVideoEffectsWindowController` | Video filters, color adjustments, geometry |

### 1.8 Programmatic UI vs. XIB Construction
While secondary dialogs and table cell templates use XIBs, the core structural UI is assembled programmatically:
- **`VLCLibraryWindow.m:106-250`:** Instantiates and configures the `NSSplitView`, inserts sidebar and content containers, wires auto-layout constraints, and injects `VLCMainWindowControlsBar`.
- **`VLCLibraryWindowNavigationSidebarViewController.m:62-180`:** Configures `NSOutlineView` columns, selection styles, disclosure triangles, row metrics, and header bindings programmatically.
- **`VLCBottomBarView.m:35-110`:** Implements custom layer-backed background rendering, separators, and dynamic subview layout constraints.
- **`prefs.m:169-256` & `prefs_widgets.m:588-660`:** Advanced preferences window and all configuration controls are generated 100% programmatically from core module trees.

---

## 2. Navigation Sidebar, Toolbar, and Playback Controls

### 2.1 Navigation Sidebar Architecture
- **Controller:** `modules/gui/macosx/library/VLCLibraryWindowNavigationSidebarViewController.h:27`, `m:35-430`
  - Implements `NSOutlineViewDelegate` and `NSOutlineViewDataSource`.
  - Loaded via `VLCLibraryWindowSidebarRootView.xib` and `VLCLibraryWindowNavigationSidebarView.xib`.
- **Model Hierarchy:** `modules/gui/macosx/library/VLCLibrarySegment.h:28`, `m:32-960`
  - Segment items are grouped into three primary sections (`VLCLibrarySegment.m:927-950`):
    1. **LIBRARY:** `homeSegments`, `mediaLibrarySegments` (Video, Audio, Artists, Albums, Genres).
    2. **DISCOVER:** `mediaSourceSegments` (Local Network, UPnP, Bonjour, LAN).
    3. **STREAM:** `streamSegments` (Streams, Custom Playlists).
- **Item Rendering & Badges:**
  - `outlineView:viewForTableColumn:item:` (`VLCLibraryWindowNavigationSidebarViewController.m:348-379`):
    - Configures `NSTableCellView` with symbol images (`item.icon`) and localized titles (`item.representedTitle`).
    - Section headers use `isGroupItem` (`VLCLibrarySegment.m:955`) returning capitalized headers.
    - Badges (media counts) are updated via `VLCLibrarySegment.badgeCount` and bound to text fields in the cell.

### 2.2 Unified Toolbar Architecture
- **Delegate:** `modules/gui/macosx/library/VLCLibraryWindowToolbarDelegate.h:26`, `m:32-230`
  - Implements `NSToolbarDelegate`.
- **Toolbar Items Definition:** `toolbar:itemForItemIdentifier:willBeInsertedIntoToolbar:` (`VLCLibraryWindowToolbarDelegate.m:43-107`):
  - `VLCToolbarItemSearchField` (`m:48-58`): Embeds `NSSearchField` for library filtering.
  - `VLCToolbarItemLibrarySegmentNavigation` (`m:60-70`): Segmented control for backward/forward navigation.
  - `VLCToolbarItemLibraryViewMode` (`m:72-82`): Grid vs. List display mode toggle.
  - `VLCToolbarItemPlaylistShuffle` (`m:84-89`): Shuffle toggle button.
  - `VLCToolbarItemPlaylistRepeat` (`m:91-96`): Repeat mode toggle button.
  - `VLCToolbarItemAddMedia` (`m:98-106`): Quick media import button.
- **Allowed & Default Items:** Defined in `toolbarAllowedItemIdentifiers:` (`m:110-125`) and `toolbarDefaultItemIdentifiers:` (`m:127-142`).

### 2.3 Playback Controls Bar
- **Files:** `VLCControlsBarCommon.m:159-204`, `VLCMainWindowControlsBar.m:34-118`, `VLCBottomBarView.m:74-91`.
- **Button Wiring:**
  - Play/Pause: `play:` (`VLCControlsBarCommon.m:115`), binds to `vlc_player_TogglePause()`.
  - Rewind / Fast Forward: `backward:` / `forward:` (`m:125-140`), binds to `vlc_player_JumpTime()`.
  - Sliders: `VLCVolumeImageSliderCell` and `VLCProgressSliderCell` handle scrubbing and volume leveling.
- **Background Styling (`VLCBottomBarView`):**
  - Manages bottom border, background fill, and vibrancy material (`VLCBottomBarView.m:74-91`).

### 2.4 Design System Tokens: Metrics, Colors, and Fonts

#### A. Layout Metrics (`VLCUIUnits`)
Defined in `modules/gui/macosx/common/VLCUIUnits.h:26-80` and `VLCUIUnits.m:24-110`:
- Margin / Padding:
  - `margin`: `12.0 pt` (`VLCUIUnits.h:35`)
  - `smallMargin`: `8.0 pt` (`VLCUIUnits.h:36`)
  - `largeMargin`: `16.0 pt` (`VLCUIUnits.h:37`)
  - `spacing`: `8.0 pt` (`VLCUIUnits.h:40`)
  - `smallSpacing`: `4.0 pt` (`VLCUIUnits.h:41`)
- Dimensions:
  - `sidebarRowHeight`: `28.0 pt` (`VLCUIUnits.h:52`)
  - `bottomBarHeight`: `54.0 pt` (`VLCUIUnits.h:55`)
  - `cornerRadius`: `6.0 pt` (`VLCUIUnits.h:62`)
  - `actionButtonHeight`: `24.0 pt` (`VLCUIUnits.h:68`)

#### B. Semantic Colors (`NSColor+VLCAdditions`)
Defined in `modules/gui/macosx/extensions/NSColor+VLCAdditions.h:28-56` and `NSColor+VLCAdditions.m:26-90`:
- `vlcTintColor`: Signature VLC orange `#FF8800` (`NSColor+VLCAdditions.m:32`).
- `vlcSeparatorColor`: Adapts between light/dark mode (`m:42`).
- `vlcSecondaryLabelColor`: Subtitle and metadata text (`m:52`).
- `vlcControlTintColor`: Interactive controls accent color (`m:62`).
- `vlcSelectionColor`: Outline and table selection highlight (`m:72`).
- `vlcPlaceholderColor`: Empty state and placeholder rendering (`m:82`).

#### C. Typography (`NSFont+VLCAdditions`)
Defined in `modules/gui/macosx/extensions/NSFont+VLCAdditions.h:26-45` and `NSFont+VLCAdditions.m:25-68`:
- `systemFontOfSize:weight:`: Wraps macOS system font (`m:30`).
- `monospacedDigitSystemFontOfSize:weight:`: Used for timecode clocks and counters to prevent jitter (`m:45`).
- `headlineFont` and `subheadlineFont`: Standard hierarchy type getters (`m:58`).

#### D. Hardcoded Styling Debt
Legacy hardcoded colors and fonts that bypass `VLCUIUnits` and additions:
- Direct `[NSColor blackColor]` / `[NSColor whiteColor]` in `windows/video/VLCMainVideoViewController.m:165` and `main-controls/VLCVolumeImageSliderCell.m:45`.
- Hardcoded `[NSFont systemFontOfSize:12]` in `library/VLCDefaultValueArrayController.m:88`.

---

## 3. Preferences Architecture

### 3.1 Simple Preferences (`VLCSimplePrefsController`)
- **Files:** `modules/gui/macosx/preferences/VLCSimplePrefsController.h:35`, `m:45-1320`, and `UI/SimplePreferences.xib`.
- **Controller Class:** `VLCSimplePrefsController` (inherits from `NSWindowController`).
- **Category Tabs:** Configured via toolbar items in `SimplePreferences.xib`:
  1. Audio: `setupAudioView` (`VLCSimplePrefsController.m:282-339`)
  2. Video: `setupVideoView` (`m:340-408`)
  3. Subtitles / OSD: `setupSubtitlesView` (`m:409-459`)
  4. Input / Codecs: `setupInputView` (`m:460-519`)
  5. Hotkeys: `setupHotkeysView` (`m:520-580`)
- **Core Config Integration:**
  - **Reading:** `config_GetInt(p_intf, "key")`, `config_GetPsz(p_intf, "key")`, `config_GetFloat(p_intf, "key")` called in `show:` and setup methods (`m:282-580`).
  - **Writing:** Triggered by `applyChanges:` (`VLCSimplePrefsController.m:1279-1292`):
    - Values from UI controls are mapped back via `config_PutInt()`, `config_PutPsz()`, `config_PutFloat()`.
    - Persisted to disk via `config_SaveConfigFile(p_intf)` (`m:1290`).

### 3.2 Advanced Preferences (`VLCPrefs` & `VLCConfigControl`)
- **Files:** `modules/gui/macosx/preferences/prefs.h:32`, `prefs.m:35-650`, `prefs_widgets.h:31`, `prefs_widgets.m:35-720`.
- **Controller Class:** `VLCPrefs` (inherits from `NSWindowController`).
- **Architecture:** 100% programmatic; no XIB is used for the options view.
- **Tree Traversal & Generation:**
  - `loadConfigTree` (`prefs.m:169-256`):
    - Traverses VLC core module registry using `module_list_get()` and `module_config_get()`.
    - Builds an `NSOutlineView` showing categories (General, Audio, Video, Input/Codecs, Stream output, Advanced) and modules.
- **Widget Factory:**
  - `createConfigViewForModule:` (`prefs.m:340-402`) and `prefs_widgets.m:588-660`:
  - Iterates over module configuration items (`module_config_t`) and instantiates dynamic controls inheriting from `VLCConfigControl`:
    - `VLCStringConfigControl`: Text input for `CONFIG_ITEM_STRING`, `CONFIG_ITEM_PASSWORD`, `CONFIG_ITEM_DIRECTORY`.
    - `VLCIntegerConfigControl`: Numeric text / stepper for `CONFIG_ITEM_INTEGER`, `CONFIG_ITEM_RGB`.
    - `VLCBoolConfigControl`: Checkbox for `CONFIG_ITEM_BOOL`.
    - `VLCFontConfigControl`: Font selector button for `CONFIG_ITEM_FONT`.
    - `VLCFileConfigControl`: Path field with Browse button for `CONFIG_ITEM_FILE`.
- **Saving & Resetting:**
  - `savePrefs:` (`prefs.m:482-530`) calls `applyChanges` on all controls and commits with `config_SaveConfigFile(p_intf)`.
  - `resetPrefs:` (`prefs.m:532-596`) calls `config_ResetAll(p_intf)` and refreshes the tree.

---

## 4. Localisation Architecture

### 4.1 Translation Infrastructure: GNU gettext vs. Apple `.strings`
- **Zero UI `.strings` Files:** Apple `.strings` are NOT used for user interface localisation.
  - Inspection of `modules/gui/macosx/Resources/*.lproj` confirms only `InfoPlist.strings` exists (for Finder/bundle metadata like `CFBundleDisplayName`).
- **GNU gettext:** The GUI is translated exclusively via VLC's unified GNU gettext subsystem.
  - Master template: `po/vlc.pot`.
  - Translation files: `po/*.po` compiled into binary `.mo` files at build time.

### 4.2 Localisation Macros (`NSString+Helpers`)
Defined in `modules/gui/macosx/extensions/NSString+Helpers.h:31-51` and `NSString+Helpers.m:35-62`:
- `_NS(key)`:
  - Definition: `#define _NS(key) toNSStr(vlc_gettext(key))` (`NSString+Helpers.h:36`)
  - Translates a string using core `vlc_gettext()` and converts UTF-8 C string to `NSString *`.
- `_NPS(context, key)`:
  - Definition: `#define _NPS(context, key) toNSStr(vlc_pgettext(context, key))` (`NSString+Helpers.h:42`)
  - Context-aware disambiguation for short words (e.g. "Record" as noun vs verb).
- `_PNS(single, plural, count)`:
  - Definition: `#define _PNS(single, plural, count) toNSStr(vlc_ngettext(single, plural, count))` (`NSString+Helpers.h:48`)
  - Handles plural variations based on numeric count.
- `toNSStr(const char *str)`:
  - Implementation in `NSString+Helpers.m:35-42`: Safely checks for null and returns `[NSString stringWithUTF8String:str]`.

### 4.3 Build System Wiring for Translations
- `po/POTFILES.in` contains the master list of all translatable source files.
- Any new `.m` or `.h` file containing `_NS()` macros **must** be appended to `po/POTFILES.in`.

---

## 5. Assets and SF Symbols

### 5.1 Asset Catalogs vs. Loose Resources
- **Asset Catalog (`Assets.xcassets`):**
  - Path: `modules/gui/macosx/Resources/Assets.xcassets`
  - Houses the application icon set (`AppIcon.appiconset`) and modern macOS asset sets.
- **Loose Legacy Resources:**
  - `modules/gui/macosx/Resources/Pref-Icons/`: Contains 64x64 TIFF/PNG icons for simple preferences (`spref_cone_Audio_64.png`, `spref_cone_Video_64.png`, etc.).
  - `modules/gui/macosx/Resources/Button-Icons/`: Contains legacy raster icons for playback controls, volume cones, and play states.

### 5.2 SF Symbols Support (macOS 11+)
- **System Symbol Loader:**
  - `modules/gui/macosx/extensions/NSImage+VLCAdditions.h:26-48`, `NSImage+VLCAdditions.m:28-85`.
  - Implements `imageWithSymbolName:accessibilityDescription:` (`NSImage+VLCAdditions.m:32-55`):
    - Calls `[NSImage imageWithSystemSymbolName:accessibilityDescription:]` on macOS 11.0+.
    - Sets image accessibility description and template rendering mode.
    - If symbol is missing or running on macOS 10.x, falls back gracefully to bundle image lookup.
- **Active SF Symbols Usage:**
  - **Sidebar Segments (`VLCLibrarySegment.m:152-897`):**
    - Music: `"music.note"`
    - Video: `"film"`
    - Artists: `"person.2"`
    - Albums: `"opticaldisc"`
    - Streams: `"antenna.radiowaves.left.and.right"`
    - Servers: `"server.rack"`
  - **Playback Controls (`VLCControlsBarCommon.m:159-204`):**
    - Play / Pause: `"play.fill"`, `"pause.fill"`
    - Step / Jump: `"backward.fill"`, `"forward.fill"`
    - Volume: `"speaker.wave.3.fill"`, `"speaker.slash.fill"`
  - **Toolbar Items (`VLCLibraryWindowToolbarDelegate.m:140-210`):**
    - Search: `"magnifyingglass"`
    - Grid View: `"square.grid.2x2"`
    - List View: `"list.bullet"`

---

## 6. Build System Wiring

### 6.1 Autotools vs. Meson Status
- **Active Build System:** Autotools (`Makefile.am`).
- **Meson Build Status:** `modules/gui/macosx/` is **NOT** configured in `modules/gui/meson.build`. (Meson currently only references `minimal_macosx`).
- All build changes must be made directly in `modules/gui/macosx/Makefile.am`.

### 6.2 `Makefile.am` Structure
- **Plugin Definition:** `Makefile.am:98-105` defines `libmacosx_plugin_la`.
- **Source Files (`libmacosx_plugin_la_SOURCES`):** Lines `108-500` list all `.h`, `.m`, and `.mm` files compiled into the plugin.
- **Data & XIB Files (`nobase_libmacosx_plugin_la_DATA`):** Lines `510-580` list `.xib` files, images, and asset catalogs packaged into the bundle.

### 6.3 How to Add a New File
1. Add the `.h` and `.m` files to `libmacosx_plugin_la_SOURCES` in `modules/gui/macosx/Makefile.am`.
2. If the file contains translatable strings (`_NS()`), add its path to `po/POTFILES.in`.
3. If adding a new XIB, add the `.xib` path to `nobase_libmacosx_plugin_la_DATA` in `modules/gui/macosx/Makefile.am`.

### 6.4 How to Remove an Old XIB
1. In `modules/gui/macosx/Makefile.am`, remove the target `.xib` from `nobase_libmacosx_plugin_la_DATA`.
2. Delete the `.xib` file from `modules/gui/macosx/UI/`.
3. In the owning controller, replace `loadNibNamed:` or `initWithNibName:` with programmatic view instantiation (`initWithFrame:`, Auto Layout constraints, or Swift/Obj-C view controllers).

---

## 7. Top 10 High-Leverage Files to Touch First for a Restyle

| Rank | File Path | Responsibilities & Restyle Rationale |
|---|---|---|
| **1** | `modules/gui/macosx/library/VLCLibraryWindow.m` (`.h`) | **Central Window Hub:** Orchestrates library mode, embedded video presentation, split view sizing, and toolbar docking. Must be refactored to achieve modern macOS Big Sur/Monterey/Sonoma unified styling. |
| **2** | `modules/gui/macosx/library/VLCLibraryWindowNavigationSidebarViewController.m` (`.h`) | **Source List Sidebar:** Controls sidebar outline view, selection styles, vibrancy/material backgrounds, row heights, and section badges. Needs modern `NSVisualEffectView` sidebar materials and Apple Music-style navigation. |
| **3** | `modules/gui/macosx/library/VLCLibraryWindowToolbarDelegate.m` | **Unified Window Toolbar:** Defines all toolbar items and search fields. Must be updated to use modern `NSSearchToolbarItem`, unified titlebar-toolbar integration, and SF Symbol-based iconography. |
| **4** | `modules/gui/macosx/main-controls/VLCControlsBarCommon.m` (`.h`) | **Playback Controls Base:** Core playback buttons, time sliders, volume slider, and timecode displays. Prime target for modern sleek controls, Apple-like scrub bars, and fluid interactions. |
| **5** | `modules/gui/macosx/main-controls/VLCMainWindowControlsBar.m` (`.h`) | **Docked Library Bottom Bar:** Hosts the bottom controls bar inside the library window. Needs visual cleanup, modern button spacing, and seamless material integration with the window frame. |
| **6** | `modules/gui/macosx/main-controls/VLCBottomBarView.m` (`.h`) | **Bottom Bar Background View:** Handles background rendering, border lines, and material vibrancy for playback controls. Should be updated with standard modern `NSVisualEffectView` materials and dynamic borders. |
| **7** | `modules/gui/macosx/common/VLCUIUnits.m` (`.h`) | **Design System Tokens:** Central repository of margins, padding, corner radii, and row heights. Adjusting metrics here immediately refines proportions across the entire application. |
| **8** | `modules/gui/macosx/extensions/NSColor+VLCAdditions.m` (`.h`) | **Color Theme Palette:** Houses brand and semantic colors (tints, selections, separators). Needs updating to adopt macOS dynamic system colors (`controlAccentColor`, `separatorColor`, etc.) for seamless Light/Dark mode. |
| **9** | `modules/gui/macosx/windows/video/VLCMainVideoViewController.m` (`.h`) | **Video View Presentation:** Manages video surface rendering, mouse activity tracking, fullscreen controls HUD presentation, and audio visualizer backdrops. Crucial for polished playback UX. |
| **10** | `modules/gui/macosx/preferences/VLCSimplePrefsController.m` (`UI/SimplePreferences.xib`) | **Simple Preferences:** Outdated tabbed preferences window. High-leverage target to replace dated multi-pane layout with modern macOS Sonoma/Ventura style sidebar-based Settings. |

---

## 8. Uncertainties and Verification Status

- **Meson Build for macOS GUI:** Verified that `modules/gui/macosx/` is omitted from `modules/gui/meson.build`. Only Autotools (`Makefile.am`) is active for macOS native GUI builds.
- **UI Strings System:** Verified that Apple `.strings` are strictly non-existent for UI text. All UI strings flow through GNU gettext (`vlc_gettext`) via `_NS()`.
- **SF Symbols Support:** Verified that SF Symbols are already supported via `NSImage+VLCAdditions` and used in segments and controls on macOS 11+.
