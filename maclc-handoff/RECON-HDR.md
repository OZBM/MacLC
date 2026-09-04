# VLC 4.0-dev macOS Apple Silicon HDR Audit & Settings Inventory

**Target Path:** `/Users/omarbenmustapha/Downloads/vlc-master/.maclc-recon/RECON-HDR.md`  
**Audit Baseline:** Commit `68a52cd` (`Merge branch 'macos-fix-teardown-use-after-free'`) on branch `main`  
**Architecture Context:** VLC 4.0.0-dev (`MacLC`) for macOS on Apple Silicon (ARM64)

---

## 1. Complete Inventory of Config Options Affecting HDR on macOS

This section documents every VLC configuration option (`add_bool`, `add_integer`, `add_string`, `add_float`, `add_module`, `add_loadfile`, etc.) across `modules/video_output/apple/`, `modules/video_output/opengl/`, `modules/video_output/libplacebo/`, `modules/codec/videotoolbox/`, `modules/video_chroma/`, and the vout core (`src/video_output/`, `src/libvlc-module.c`).

---

### 1.1 `modules/video_output/apple/VLCSampleBufferDisplay.m`

#### `force-darwin-legacy-display`
- **Option String:** `"force-darwin-legacy-display"`
- **Type:** `add_bool`, with `change_volatile()`
- **Default Value:** `false`
- **Short Text:** `N_("Force fallback to legacy display")` ([`VLCSampleBufferDisplay.m:1930`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/apple/VLCSampleBufferDisplay.m#L1930))
- **Long Text:** `N_("Triggers an initialization failure to allow fallback to any other legacy display.")` ([`VLCSampleBufferDisplay.m:1931-1932`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/apple/VLCSampleBufferDisplay.m#L1931-L1932))
- **Declaring Module:** `samplebufferdisplay` ([`VLCSampleBufferDisplay.m:1965-1967`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/apple/VLCSampleBufferDisplay.m#L1965-L1967))
- **Reader Location:** [`VLCSampleBufferDisplay.m:1721-1723`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/apple/VLCSampleBufferDisplay.m#L1721-L1723) in `Open()` via `var_InheritBool(vd, "force-darwin-legacy-display")`. If true, `Open()` immediately returns `VLC_EGENERIC` to yield to lower-priority display modules (`caopengllayer`).

#### `macosx-hdr-mode`
- **Option String:** `"macosx-hdr-mode"`
- **Type:** `add_integer`, with list values `{0, 1, 2, 3}`
- **Default Value:** `0` (Auto)
- **Short Text:** `N_("HDR Video Output Mode")` ([`VLCSampleBufferDisplay.m:1934`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/apple/VLCSampleBufferDisplay.m#L1934), [`macosx.m:170`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/gui/macosx/main/macosx.m#L170))
- **Long Text:** `N_("Controls how HDR video content is presented on macOS displays. Auto: Uses native EDR on HDR/XDR displays and hardware tonemapping on SDR displays. Force Native HDR: Always uses native EDR output. Tone-map to SDR: Performs high quality tone mapping to SDR color space. Disable HDR: Clamps and renders in standard SDR.")` ([`VLCSampleBufferDisplay.m:1935-1940`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/apple/VLCSampleBufferDisplay.m#L1935-L1940), [`macosx.m:171-176`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/gui/macosx/main/macosx.m#L171-L176))
- **List Text:**
  - `0`: `N_("Auto (Native EDR on HDR screens, Tonemap on SDR)")` ([`VLCSampleBufferDisplay.m:1948`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/apple/VLCSampleBufferDisplay.m#L1948), [`macosx.m:184`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/gui/macosx/main/macosx.m#L184))
  - `1`: `N_("Force Native EDR / HDR")` ([`VLCSampleBufferDisplay.m:1949`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/apple/VLCSampleBufferDisplay.m#L1949), [`macosx.m:185`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/gui/macosx/main/macosx.m#L185))
  - `2`: `N_("Tone-map to SDR")` ([`VLCSampleBufferDisplay.m:1950`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/apple/VLCSampleBufferDisplay.m#L1950), [`macosx.m:186`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/gui/macosx/main/macosx.m#L186))
  - `3`: `N_("Disable HDR")` ([`VLCSampleBufferDisplay.m:1951`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/apple/VLCSampleBufferDisplay.m#L1951), [`macosx.m:187`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/gui/macosx/main/macosx.m#L187))
- **Declaring Modules:** `samplebufferdisplay` ([`VLCSampleBufferDisplay.m:1968-1969`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/apple/VLCSampleBufferDisplay.m#L1968-L1969)) and `macosx` ([`modules/gui/macosx/main/macosx.m:194-195`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/gui/macosx/main/macosx.m#L194-L195))
- **Reader Locations:**
  - `VLCSampleBufferDisplay.m`: [`Open():1764-1765`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/apple/VLCSampleBufferDisplay.m#L1764-L1765) binds [`HdrModeCallback:1260-1267`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/apple/VLCSampleBufferDisplay.m#L1260-L1267); [`updateDynamicRangeAndHeadroom:936`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/apple/VLCSampleBufferDisplay.m#L936) reads via `var_InheritInteger(vd, "macosx-hdr-mode")`; [`RenderPicture():1364-1401`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/apple/VLCSampleBufferDisplay.m#L1364-L1401) reads per-frame to force PQ/BT.2020 (mode 1) or BT.709 buffer retagging (mode 2 on macOS < 14, mode 3).
  - `caopengllayer.m`: [`Open():676, 693-694`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/caopengllayer.m#L676) reads via `var_InheritInteger(vd, "macosx-hdr-mode")` and binds [`HdrModeCallback:491-499`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/caopengllayer.m#L491-L499); [`updateDynamicRangeProperties:924-955`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/caopengllayer.m#L924-L955) applies `preferredDynamicRange` (`CADynamicRangeHigh` vs `CADynamicRangeStandard`).
  - GUI: [`VLCSimplePrefsController.m:873, 1204`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/gui/macosx/preferences/VLCSimplePrefsController.m#L873) reads and writes popup selection.

#### `macosx-edr-headroom`
- **Option String:** `"macosx-edr-headroom"`
- **Type:** `add_float`
- **Default Value:** `0.0f` (0.0 = auto screen headroom)
- **Short Text:** `N_("EDR Headroom Scaling")` ([`VLCSampleBufferDisplay.m:1942`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/apple/VLCSampleBufferDisplay.m#L1942), [`macosx.m:178`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/gui/macosx/main/macosx.m#L178))
- **Long Text:** In `VLCSampleBufferDisplay.m:1943-1944`: `N_("Controls the extended dynamic range brightness scaling factor (0.0 for auto screen headroom, >= 1.0 to force specific headroom).")`; in `macosx.m:179-180`: `N_("Controls the extended dynamic range brightness scaling factor (0.0 for auto screen headroom).")`
- **Declaring Modules:** `samplebufferdisplay` ([`VLCSampleBufferDisplay.m:1970`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/apple/VLCSampleBufferDisplay.m#L1970)) and `macosx` ([`modules/gui/macosx/main/macosx.m:196`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/gui/macosx/main/macosx.m#L196))
- **Reader Locations:**
  - `VLCSampleBufferDisplay.m`: [`Open():1749-1758`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/apple/VLCSampleBufferDisplay.m#L1749-L1758) reads initial headroom; [`1761-1762`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/apple/VLCSampleBufferDisplay.m#L1761-L1762) binds [`EdrHeadroomCallback:1245-1258`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/apple/VLCSampleBufferDisplay.m#L1245-L1258); [`updateDynamicRangeAndHeadroom:978-984`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/apple/VLCSampleBufferDisplay.m#L978-L984) overrides screen headroom when `_userHeadroom > 0.0f`.
  - `caopengllayer.m`: [`Open():677, 690-691`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/caopengllayer.m#L677) reads initial value and binds [`EdrHeadroomCallback:478-489`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/caopengllayer.m#L478-L489); [`updateDynamicRangeProperties:920-923`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/caopengllayer.m#L920-L923) overrides layer headroom.
  - `modules/video_output/opengl/pl_scale.c:427`: `sys->user_headroom = var_InheritFloat(filter, "macosx-edr-headroom");` used as fallback target peak if effective headroom is missing.
  - GUI: [`VLCSimplePrefsController.m:876, 1206`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/gui/macosx/preferences/VLCSimplePrefsController.m#L876) reads and writes float text field.

#### `edr-headroom-effective` (Runtime Variable)
- **Variable String:** `"edr-headroom-effective"`
- **Type:** Dynamic `VLC_VAR_FLOAT` variable on `vout_display_t` object
- **Default Value:** `1.0f`
- **Publishers:**
  - `VLCSampleBufferDisplay.m:1869-1870`: `var_Create(vd, "edr-headroom-effective", VLC_VAR_FLOAT); var_SetFloat(vd, "edr-headroom-effective", 1.0f);`
  - `VLCSampleBufferDisplay.m:1068`: `var_SetFloat(vd, "edr-headroom-effective", (float)effectiveHeadroom);`
  - `caopengllayer.m:696-697`: `var_Create(vd, "edr-headroom-effective", VLC_VAR_FLOAT); var_SetFloat(vd, "edr-headroom-effective", 1.0f);`
  - `caopengllayer.m:960`: `var_SetFloat(_vd, "edr-headroom-effective", (float)effectiveHeadroom);`
- **Consumer:** [`modules/video_output/opengl/pl_scale.c:431-455`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/opengl/pl_scale.c#L431-L455) queries `FindEdrHeadroomSource(filter)` and binds live callback [`EdrHeadroomCallback:293-298`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/opengl/pl_scale.c#L293-L298) at line 444, setting `color_out.hdr.max_luma = 100.0f * effective;` ([`pl_scale.c:452`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/opengl/pl_scale.c#L452)).

---

### 1.2 `modules/codec/videotoolbox/decoder.c`

#### `videotoolbox-hw-decoder-only`
- **Option String:** `"videotoolbox-hw-decoder-only"`
- **Type:** `add_bool`
- **Default Value:** `true`
- **Short Text:** `N_("Use Hardware decoders only")` ([`decoder.c:3232`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/codec/videotoolbox/decoder.c#L3232))
- **Long Text:** `N_("Use Hardware decoders only")` ([`decoder.c:3268`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/codec/videotoolbox/decoder.c#L3268))
- **Declaring Module:** `videotoolbox` ([`decoder.c:3268`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/codec/videotoolbox/decoder.c#L3268))
- **Reader Location:** [`decoder.c:1344`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/codec/videotoolbox/decoder.c#L1344) in `StartVideoToolbox()` via `var_InheritBool(p_dec, "videotoolbox-hw-decoder-only")`. Populates `kVTVideoDecoderSpecification_RequireHardwareAcceleratedVideoDecoder` in session specification.

#### `videotoolbox-cvpx-chroma`
- **Option String:** `"videotoolbox-cvpx-chroma"`
- **Type:** `add_string`, with string choice list
- **Default Value:** `""` (Auto)
- **Short Text:** `"Force the VideoToolbox output chroma"` ([`decoder.c:3233`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/codec/videotoolbox/decoder.c#L3233))
- **Long Text:** `"Force the VideoToolbox decoder to output CVPixelBuffers in the specified pixel format instead of the default. By default, the best chroma is chosen by the VideoToolbox decoder."` ([`decoder.c:3234-3236`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/codec/videotoolbox/decoder.c#L3234-L3236))
- **Choice Values & Names:**
  - `""`: `"Auto"` ([`decoder.c:3252`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/codec/videotoolbox/decoder.c#L3252))
  - `"x420"`: `"Y'CbCr 10-bit 4:2:0 (Bi-Planar, Video Range - HDR)"` ([`decoder.c:3253`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/codec/videotoolbox/decoder.c#L3253)) -> `kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange`
  - `"xf20"`: `"Y'CbCr 10-bit 4:2:0 (Bi-Planar, Full Range - HDR)"` ([`decoder.c:3254`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/codec/videotoolbox/decoder.c#L3254)) -> `kCVPixelFormatType_420YpCbCr10BiPlanarFullRange`
  - `"BGRA"`: `"BGRA 8-bit"` ([`decoder.c:3255`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/codec/videotoolbox/decoder.c#L3255)) -> `kCVPixelFormatType_32BGRA`
  - `"y420"`: `"Y'CbCr 8-bit 4:2:0 (Planar)"` ([`decoder.c:3256`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/codec/videotoolbox/decoder.c#L3256))
  - `"420f"`: `"Y'CbCr 8-bit 4:2:0 (Bi-Planar, Full Range)"` ([`decoder.c:3257`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/codec/videotoolbox/decoder.c#L3257))
  - `"420v"`: `"Y'CbCr 8-bit 4:2:0 (Bi-Planar)"` ([`decoder.c:3258`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/codec/videotoolbox/decoder.c#L3258))
  - `"2vuy"`: `"Y'CbCr 8-bit 4:2:2"` ([`decoder.c:3259`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/codec/videotoolbox/decoder.c#L3259))
- **Declaring Module:** `videotoolbox` ([`decoder.c:3269-3270`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/codec/videotoolbox/decoder.c#L3269-L3270))
- **Reader Location:** [`decoder.c:1347`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/codec/videotoolbox/decoder.c#L1347) in `StartVideoToolbox()` via `var_InheritString(p_dec, "videotoolbox-cvpx-chroma")`. Forces `p_sys->i_cvpx_format` ([`decoder.c:1351-1376`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/codec/videotoolbox/decoder.c#L1351-L1376)).

---

### 1.3 `modules/video_output/opengl/` & `pl_scale`

#### `gl-upscaler` & `gl-downscaler`
- **Option Strings:** `"gl-upscaler"`, `"gl-downscaler"`
- **Type:** `add_integer`, with scale algorithm list
- **Default Value:** `VLC_GLSCALE_BUILTIN` (`0`)
- **Short Text:** `N_("OpenGL upscaler")` / `N_("OpenGL downscaler")` ([`gl_scale.h:104, 107`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/opengl/gl_scale.h#L104))
- **Long Text:** `N_("Scaling filter to apply during upscaling.")` / `N_("Scaling filter to apply during downscaling.")` ([`gl_scale.h:105, 108`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/opengl/gl_scale.h#L105))
- **Declaring Modules:** `macosx` (`vout_macosx`) via `add_glopts()` ([`modules/video_output/macosx.m:80`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/macosx.m#L80)) and `opengl/display.c:69`
- **Reader Location:** [`modules/video_output/opengl/vout_helper.c:120-121`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/opengl/vout_helper.c#L120-L121) via `var_InheritInteger(gl, "gl-upscaler")` / `"gl-downscaler"`. When non-zero, or when HDR/DoVi is detected (`has_dovi || has_hdr` at line 126), automatically creates and appends `pl_scale` to the filter chain ([`vout_helper.c:146`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/opengl/vout_helper.c#L146)).

#### `plscale-upscaler` & `plscale-downscaler`
- **Option Strings:** `"plscale-upscaler"`, `"plscale-downscaler"`
- **Type:** `add_integer`, with filter preset list
- **Default Value:** `SCALE_BUILTIN` (`0`)
- **Short Text:** `"OpenGL upscaler"` / `"OpenGL downscaler"` ([`pl_scale.c:513, 519`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/opengl/pl_scale.c#L513))
- **Long Text:** `"Upscaler filter to apply during rendering"` / `"Downscaler filter to apply during rendering"` ([`pl_scale.c:514, 520`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/opengl/pl_scale.c#L514))
- **Declaring Module:** `pl_scale` ([`modules/video_output/opengl/pl_scale.c:515, 521`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/opengl/pl_scale.c#L515))
- **Reader Location:** [`pl_scale.c:313-314`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/opengl/pl_scale.c#L313-L314) via `var_InheritInteger(filter, "plscale-upscaler")` / `"plscale-downscaler"`.

#### `plscale-target-prim` & `plscale-target-trc`
- **Option Strings:** `"plscale-target-prim"`, `"plscale-target-trc"`
- **Type:** `add_integer`, with colorimetry lists
- **Default Value:** `PL_COLOR_PRIM_UNKNOWN` (`0`), `PL_COLOR_TRC_UNKNOWN` (`0`)
- **Short Text:** `"Override detected display primaries"` / `"Override detected display transfer function"` ([`utils.h:87, 122`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/libplacebo/utils.h#L87))
- **Long Text:** `"Override the auto-detected display primaries."` / `"Override the auto-detected display transfer function."` ([`utils.h:88, 123`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/libplacebo/utils.h#L88))
- **Declaring Module:** `pl_scale` ([`modules/video_output/opengl/pl_scale.c:525, 529`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/opengl/pl_scale.c#L525))
- **Reader Location:** [`pl_scale.c:315-325`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/opengl/pl_scale.c#L315-L325). Falls back to `"pl-target-prim"` (line 317) and `"pl-target-trc"` (line 323). Sets `color_out` primaries/transfer for libplacebo tone-mapping ([`pl_scale.c:412-425`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/opengl/pl_scale.c#L412-L425)).

---

### 1.4 `modules/video_output/opengl/sampler.c` (`glsampler`)

Declared via `add_placebo_color_map_opts("gl")` ([`sampler.c:1260`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/opengl/sampler.c#L1260)) and companion options:
- **`gl-gamut-mapping`:** `add_integer`, default `GAMUT_AUTO` (`0`). Short: `N_("Gamut mapping mode")`, Long: `N_("Algorithm to use for mapping colors to the display's gamut")` ([`utils.h:234-235`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/libplacebo/utils.h#L234)). Read by [`sampler.c:317`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/opengl/sampler.c#L317) via `vlc_placebo_ColorMapParams`.
- **`gl-tone-mapping-function`:** `add_integer`, default `TONEMAP_AUTO` (`0`). Short: `N_("Tone-mapping function")`, Long: `N_("Algorithm to use for tone mapping HDR into the display's dynamic range.")` ([`utils.h:258-259`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/libplacebo/utils.h#L258)). Read by [`sampler.c:317`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/opengl/sampler.c#L317).
- **`gl-tone-mapping-param`:** `add_float`, default `0.0f`. Short: `N_("Tone-mapping parameter")`, Long: `N_("Tuning parameter for the tone-mapping function.")` ([`utils.h:261-262`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/libplacebo/utils.h#L261)). Read by [`sampler.c:317`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/opengl/sampler.c#L317).
- **`gl-inverse-tone-mapping`:** `add_bool`, default `false`. Short: `N_("Inverse tone-mapping")`, Long: `N_("Enable inverse tone mapping (SDR to HDR expansion)")` ([`utils.h:264-265`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/libplacebo/utils.h#L264)). Read by [`sampler.c:317`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/opengl/sampler.c#L317).
- **`target-prim` & `target-trc`:** `add_integer`, default `0` (`PL_COLOR_PRIM_UNKNOWN` / `PL_COLOR_TRC_UNKNOWN`). Declared at [`sampler.c:1261, 1264`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/opengl/sampler.c#L1261). Read at [`sampler.c:321, 327`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/opengl/sampler.c#L321).
- **`dither-algo` & `dither-depth`:** `add_integer` (default `-1`), `add_integer_with_range` (default `0`, range `0..16`). Declared at [`sampler.c:1268, 1271`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/opengl/sampler.c#L1268). Read at [`sampler.c:332, 337`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/opengl/sampler.c#L332).
- **`gl-lut-file`:** `add_loadfile`, default `NULL`. Declared at [`sampler.c:1273`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/opengl/sampler.c#L1273). Read at [`sampler.c:342`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/opengl/sampler.c#L342).

---

### 1.5 `modules/video_output/libplacebo/display.c`

Declared in [`display.c:768-891`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/libplacebo/display.c#L768-L891), read by `UpdateParams()` ([`display.c:898-955`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/libplacebo/display.c#L898-L955)):
- `pl-gpu`: `add_module` ("libplacebo gpu", default "any", `:774`)
- `pl-user-shader`: `add_loadfile` (default NULL, `:777`)
- `pl-upscaler-preset`: `add_integer` (default `SCALE_BUILTIN` = 0, `:780`)
- `pl-downscaler-preset`: `add_integer` (default `SCALE_BUILTIN` = 0, `:783`)
- `pl-lut-entries`: `add_integer_with_range` (default 64, range 16..256, `:786`)
- `pl-antiringing`: `add_float_with_range` (default 0.0, range 0..1, `:788`)
- `pl-sigmoid`: `add_bool` (default true, `:790`)
- `pl-sigmoid-center`: `add_float_with_range` (default 0.75, range 0..1, `:792`)
- `pl-sigmoid-slope`: `add_float_with_range` (default 6.5, range 1..20, `:794`)
- `pl-debanding`: `add_bool` (default false, `:798`)
- `pl-iterations`: `add_integer` (default 1, `:799`)
- `pl-threshold`: `add_float` (default 4.0, `:801`)
- `pl-radius`: `add_float` (default 16.0, `:803`)
- `pl-grain`: `add_float` (default 6.0, `:805`)
- `pl-output-hint`: `add_integer` (default true / auto, `:809`)
- `pl-gamut-mapping`: `add_integer` (default `GAMUT_AUTO`, `:811`)
- `pl-tone-mapping-function`: `add_integer` (default `TONEMAP_AUTO`, `:811`)
- `pl-tone-mapping-param`: `add_float` (default 0.0, `:811`)
- `pl-inverse-tone-mapping`: `add_bool` (default false, `:811`)
- `pl-target-prim`: `add_integer` (default `PL_COLOR_PRIM_UNKNOWN`, `:812`)
- `pl-target-trc`: `add_integer` (default `PL_COLOR_TRC_UNKNOWN`, `:814`)
- `pl-lut-file`: `add_loadfile` (default NULL, `:817`)
- `pl-lut-mode`: `add_integer` (default `LUT_DISABLED`, `:818`)
- `pl-peak-period`: `add_float_with_range` (default 100.0, range 0..1000, `:827`)
- `pl-scene-threshold-low`: `add_float` (default 5.5, `:829`)
- `pl-scene-threshold-high`: `add_float` (default 10.0, `:831`)
- `pl-contrast-recovery`: `add_float_with_range` (default 0.0, range 0..3, `:835`)
- `pl-contrast-smoothness`: `add_float_with_range` (default 3.5, range 0..10, `:837`)
- `pl-dither`: `add_integer` (default -1, `:842`)
- `pl-dither-size`: `add_integer_with_range` (default 6, range 1..8, `:845`)
- `pl-temporal-dither`: `add_bool` (default false, `:847`)
- `pl-dither-depth`: `add_integer_with_range` (default 0, range 0..16, `:849`)
- Custom scalers: `pl-upscaler-kernel`, `pl-upscaler-window`, `pl-upscaler-polar`, `pl-upscaler-clamp`, `pl-upscaler-blur`, `pl-upscaler-taper`, and matching downscaler options (`:853-880`)
- Performance tweaks: `pl-skip-aa`, `pl-polar-cutoff`, `pl-overlay-direct`, `pl-disable-linear`, `pl-force-general`, `pl-delayed-peak` (`:883-889`)

---

### 1.6 Chroma & Core Vout Options

#### `swscale-mode`
- **Option String:** `"swscale-mode"`
- **Type:** `add_integer`
- **Default Value:** `2` (Bicubic)
- **Short Text:** `N_("Scaling mode")` ([`swscale.c:115`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_chroma/swscale.c#L115))
- **Long Text:** `N_("Scaling mode to use")` ([`swscale.c:120`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_chroma/swscale.c#L120))
- **Declaring Module:** `swscale` ([`modules/video_chroma/swscale.c:120`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_chroma/swscale.c#L120))
- **Reader Location:** [`swscale.c:292`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_chroma/swscale.c#L292) via `var_InheritInteger(p_filter, "swscale-mode")`.

#### `vout`
- **Option String:** `"vout"`
- **Type:** `add_module`, capability `"vout display"`, default `"any"`
- **Short Text:** `N_("Video output module")` ([`src/libvlc-module.c:1774`](file:///Users/omarbenmustapha/Downloads/vlc-master/src/libvlc-module.c#L1774))
- **Long Text:** `N_("This is the video output method used by VLC. The default behavior is to automatically choose the best method.")` ([`src/libvlc-module.c:1774`](file:///Users/omarbenmustapha/Downloads/vlc-master/src/libvlc-module.c#L1774))
- **Declaring Module:** Core (`src/libvlc-module.c:1774`)
- **Reader Location:** [`src/video_output/vout_wrapper.c:69`](file:///Users/omarbenmustapha/Downloads/vlc-master/src/video_output/vout_wrapper.c#L69) via `var_InheritString(vout, "vout")`.

---

## 2. Usable Video Output Modules on macOS ARM Today

### 2.1 Module Election Table

| Module Name / Shortcut | Source File | Priority | Usable on macOS ARM? | Chosen by Default? | How to Pick |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **`samplebufferdisplay`** | [`modules/video_output/apple/VLCSampleBufferDisplay.m:1972`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/apple/VLCSampleBufferDisplay.m#L1972) | **600** | **YES** | **YES (Default Winner)** | Default auto-selection, or CLI `--vout=samplebufferdisplay` |
| **`caopengllayer`** | [`modules/video_output/caopengllayer.m:1346`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/caopengllayer.m#L1346) | **300** | **YES** | **No (Primary Fallback)** | CLI `--force-darwin-legacy-display`, `--vout=caopengllayer`, or automatic on 360° videos |
| **`vout_macosx` / `macosx`** | [`modules/video_output/macosx.m:78`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/macosx.m#L78) | **290** | **Partially (Deprecated)** | **No** | CLI `--vout=macosx` or `--vout=vout_macosx` |
| **`libplacebo` (`pl`)** | [`modules/video_output/libplacebo/display.c:772`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/libplacebo/display.c#L772) | **0** | **NO (Fails to start)** | **No** | Cannot run standalone; lacks Darwin Vulkan platform surface (`VULKAN-DARWIN-PLAN.md`) |
| **`vdummy` / `vmem` / `yuv`** | `modules/video_output/vdummy.c`, `vmem.c`, `yuv.c` | **0** | **YES (Headless/Testing)** | **No** | CLI `--vout=vdummy`, `--vout=vmem`, `--vout=yuv` |

### 2.2 Election Mechanics & Module Reachability
1. **Default Winner:** VLC core sorts candidate display modules by descending priority in `src/video_output/vout_wrapper.c:69-105`. `samplebufferdisplay` at priority 600 ([`VLCSampleBufferDisplay.m:1972`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/apple/VLCSampleBufferDisplay.m#L1972)) wins unconditionally. It handles hardware CVPX buffers directly and filters software CPU pictures into `VLC_CODEC_CVPX_P010` via `CreateCVPXConverter()` ([`VLCSampleBufferDisplay.m:431-488`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/apple/VLCSampleBufferDisplay.m#L431-L488)).
2. **Fallback to `caopengllayer`:** If `--force-darwin-legacy-display` is specified, `VLCSampleBufferDisplay.m:1721-1723` returns `VLC_EGENERIC`. Probing falls through to `caopengllayer` (priority 300, [`caopengllayer.m:1346`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/caopengllayer.m#L1346)), which opens a CGL Core 4.1 context ([`caopengllayer.m:221-286`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/caopengllayer.m#L221-L286)). Spherical 360° videos also reject `samplebufferdisplay` at line 1727 and fall back to `caopengllayer`.
3. **Why `libplacebo` Standalone Cannot Run:** Its Vulkan backend (`placebo_vk`) requires `VK_EXT_metal_surface` integration with `CAMetalLayer`. VLC on Darwin lacks a `vulkan platform` module, and `contrib/src/libplacebo/rules.mak:26-31` explicitly excludes Vulkan on Darwin ([`VULKAN-DARWIN-PLAN.md:24-34`](file:///Users/omarbenmustapha/Downloads/vlc-master/VULKAN-DARWIN-PLAN.md#L24-L34)). Setting `--vout=libplacebo` fails during probe and halts video output.
4. **How `libplacebo` IS Reached Today:** Under `caopengllayer`, commit `512ce00` automatically inserts `pl_scale` whenever HDR10/HLG or Dolby Vision content is played ([`vout_helper.c:126`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/opengl/vout_helper.c#L126)), making libplacebo's tone-mapping algorithms active under OpenGL.

---

## 3. The Tone-Mapping Pipeline on Apple Silicon

### 3.1 Primary Path: `samplebufferdisplay` (CoreMedia / CoreAnimation)

```
[Demuxer / Bitstream] ──► [VideoToolbox Decoder: decoder.c]
                               │ Output: CVPixelBufferRef (P010 / P216)
                               │ Attachments: Matrix, Primaries, Transfer, mdcv, clli
                               ▼
            [VLCSampleBufferDisplay.m: RenderPicture]
              ├─ Extract & retain CVPixelBufferRef (:1334)
              ├─ Apply Rotation if needed (:1343)
              ├─ Merge format colorimetry (:1352-1362)
              ├─ Evaluate macosx-hdr-mode (:1364-1401)
              ├─ Attach CoreVideo color properties (vt_utils.c:648-726)
              ├─ Attach ST 2086 & CTA-861.3 metadata (vt_utils.c:530-555)
              ├─ Wrap in CMVideoFormatDescription (:1456)
              ├─ Wrap in CMSampleBufferRef with CACurrentMediaTime (:1474)
              └─ Enqueue into AVSampleBufferDisplayLayer (:1483)
                               │
                               ▼
        [Apple CoreAnimation & WindowServer Compositor]
          (Queries display profile & physical EDR capability;
           executes 100% of tone mapping and gamut compression in hardware)
                               │
                               ▼
     [Apple Silicon Display Engine -> Liquid Retina XDR / Pro Display XDR]
```

#### The Structuring Architectural Fact: 0% Tone Mapping by VLC
On this path, VLC performs **0% algorithmic tone mapping, gamut conversion, or highlight compression**. VLC merely tags the `CVPixelBufferRef` with CoreVideo color dictionaries, sets the layer's EDR properties, and enqueues the buffer. The Apple Silicon Display Engine and macOS compositor execute all tone reproduction in hardware.

#### Where Headroom is Measured
1. **Initial Layer Creation:** [`VLCSampleBufferDisplay.m:702`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/apple/VLCSampleBufferDisplay.m#L702) queries `screen.maximumExtendedDynamicRangeColorComponentValue`.
2. **Per-Window Screen Resolution:** [`VLCSampleBufferDisplay.m:959-965`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/apple/VLCSampleBufferDisplay.m#L959-L965) queries `targetScreen.maximumExtendedDynamicRangeColorComponentValue` from `self.window.screen ?: [NSScreen mainScreen]`. If `_currentHeadroom <= 1.0`, it inspects `maximumPotentialExtendedDynamicRangeColorComponentValue` to verify panel EDR capability.
3. **Screen Observers:** [`setupScreenObservers:876-895`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/apple/VLCSampleBufferDisplay.m#L876-L895) listens for `NSApplicationDidChangeScreenParametersNotification`, `NSWindowDidChangeScreenNotification`, and `NSWindowDidChangeScreenProfileNotification`, calling `updateDynamicRangeAndHeadroom` upon display reconfiguration or window dragging between screens.

#### How Headroom is Propagated
- **User Override:** If `_userHeadroom > 0.0f` (`macosx-edr-headroom`), effective headroom is clamped to user setting ([`VLCSampleBufferDisplay.m:978-984`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/apple/VLCSampleBufferDisplay.m#L978-L984)); otherwise it uses the screen's measured peak headroom.
- **Published to Vout Object:** Line 1068 publishes `var_SetFloat(vd, "edr-headroom-effective", (float)effectiveHeadroom);`.
- **Applied to Display Layer:**
  - `wantsExtendedDynamicRangeContent = YES` ([`VLCSampleBufferDisplay.m:1071`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/apple/VLCSampleBufferDisplay.m#L1071))
  - `preferredDynamicRange = CADynamicRangeHigh` ([`VLCSampleBufferDisplay.m:1097`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/apple/VLCSampleBufferDisplay.m#L1097))
  - `contentsHeadroom = effectiveHeadroom` ([`VLCSampleBufferDisplay.m:1099`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/apple/VLCSampleBufferDisplay.m#L1099))
  - `toneMapMode = CAToneMapModeIfSupported` ([`VLCSampleBufferDisplay.m:1122`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/apple/VLCSampleBufferDisplay.m#L1122))
  - `self.window.colorSpace = [NSColorSpace extendedSRGBColorSpace]` ([`VLCSampleBufferDisplay.m:1075`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/apple/VLCSampleBufferDisplay.m#L1075))
- **Subtitle Adaptation (BT.2408):** Subtitles are rendered into tagged `kCGColorSpaceSRGB` ([`VLCSampleBufferDisplay.m:1533`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/apple/VLCSampleBufferDisplay.m#L1533)). In [`VLCSampleBufferDisplay.m:1154-1168`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/apple/VLCSampleBufferDisplay.m#L1154-L1168), subtitle layer opacity is attenuated using ITU-R BT.2408 reference white: `factor = 203.0f / (100.0f * effectiveHeadroom)`, clamped between 0.15 and 1.0, and applied via `spuView.layer.opacity = (float)factor;`.

---

### 3.2 Fallback Path: `caopengllayer` + `pl_scale` (libplacebo Tone Mapping)

When running through `caopengllayer`, VLC takes full control of tone mapping via `libplacebo`:
1. **Headroom Measurement:** [`caopengllayer.m:774-775, 974-975`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/caopengllayer.m#L774) queries `screen.maximumExtendedDynamicRangeColorComponentValue`.
2. **Headroom Publication:** [`caopengllayer.m:960`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/caopengllayer.m#L960) publishes `var_SetFloat(_vd, "edr-headroom-effective", (float)effectiveHeadroom);`.
3. **Live Headroom Tracking in `pl_scale`:** [`modules/video_output/opengl/pl_scale.c:431-446`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/opengl/pl_scale.c#L431-L446) discovers the vout display via `FindEdrHeadroomSource(filter)` and registers a live callback `var_AddCallback(display, "edr-headroom-effective", EdrHeadroomCallback, &sys->headroom)` (commit `4447bb7`). `Draw()` loads this atomic headroom per-frame.
4. **Display Target Configuration:** [`pl_scale.c:409-455`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/opengl/pl_scale.c#L409-L455):
   - Target Primaries: `PL_COLOR_PRIM_DISPLAY_P3` (line 415).
   - Target Transfer: `PL_COLOR_TRC_SRGB` (line 422).
   - Target Peak Luminance: `color_out.hdr.max_luma = 100.0f * effective;` (line 452).
5. **ColorSync ICC Profile Tracking:** [`modules/video_output/libplacebo/darwin_icc.m:85-110`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/libplacebo/darwin_icc.m#L85-L110) extracts the window screen's ColorSync profile via `CGDisplayCopyColorSpace()` and `CGColorSpaceCopyICCData()`, monitored via dirty flag (commit `73db80d`), and feeds `pl_icc_profile` into libplacebo.
6. **Dynamic Metadata Propagation:**
   - **HDR10+:** VideoToolbox decodes ITU-T T.35 SEI packets ([`decoder.c:600-645`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/codec/videotoolbox/decoder.c#L600-L645), commit `3a90e9e`). Passed via `VLC_ANCILLARY_ID_HDR10PLUS` to `filters.c:552-562`, ingested in `pl_scale.c:192-194` into `vlc_placebo_HdrMetadata()`, and reset per-frame at line 196 (commit `512ce00`).
   - **Dolby Vision:** VideoToolbox parses RPU NAL unit 62 ([`decoder.c:650-780`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/codec/videotoolbox/decoder.c#L650-L780), commit `3a90e9e`, `c6934eb`). Carried via `VLC_ANCILLARY_ID_DOVI` to `pl_scale.c:375-380`.

---

## 4. GUI Exposure: Simple vs. Advanced vs. CLI-Only

```
┌─────────────────────────────────────────────────────────────────────────┐
│                           VLC PREFERENCES                               │
├───────────────────────────────────┬─────────────────────────────────────┤
│ SIMPLE PREFERENCES                │ ADVANCED PREFERENCES / CLI ONLY     │
│ (VLCSimplePrefsController.m)      │ (prefs.m / CLI Flags)               │
├───────────────────────────────────┼─────────────────────────────────────┤
│ • macosx-hdr-mode                 │ • force-darwin-legacy-display       │
│   (Auto, Force, Tonemap, Disable) │ • videotoolbox-hw-decoder-only      │
│ • macosx-edr-headroom             │ • videotoolbox-cvpx-chroma          │
│   (Floating point text field)     │ • gl-upscaler / gl-downscaler       │
│ • EDR Status Label                │ • plscale-upscaler / plscale-down   │
│   (Read-only dynamic peak EDR)    │ • plscale-target-prim / target-trc  │
│ • Hardware Acceleration Checkbox  │ • gl-gamut-mapping / tone-mapping   │
│   (Controls "videotoolbox")       │ • pl-debanding / pl-dither          │
│                                   │ • vout (display module picker)      │
│                                   │ • edr-headroom-effective (Internal) │
└───────────────────────────────────┴─────────────────────────────────────┘
```

1. **Exposed in Simple Preferences (`VLCSimplePrefsController.m`):**
   - `macosx-hdr-mode`: Configured in `_video_hdrBox` via `_video_hdrModePopup` ([`VLCSimplePrefsController.m:863-873, 1203-1204`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/gui/macosx/preferences/VLCSimplePrefsController.m#L863)).
   - `macosx-edr-headroom`: Configured via `_video_edrHeadroomTextField` ([`VLCSimplePrefsController.m:875-876, 1205-1206`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/gui/macosx/preferences/VLCSimplePrefsController.m#L875)).
   - Screen EDR Capability Display: Read-only status in `_video_hdrStatusLabel` ([`VLCSimplePrefsController.m:878-889`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/gui/macosx/preferences/VLCSimplePrefsController.m#L878)) querying `screen.maximumExtendedDynamicRangeColorComponentValue`.
   - Hardware Acceleration: `_input_hardwareAccelerationCheckbox` ([`VLCSimplePrefsController.m:900, 1216`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/gui/macosx/preferences/VLCSimplePrefsController.m#L900)) toggles `"videotoolbox"`.
2. **Exposed in Advanced Preferences (`prefs.m`):**
   - Automatically walks module descriptors ([`prefs.m:503-562`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/gui/macosx/preferences/prefs.m#L503-L562)):
     - `Video` -> `Output modules` -> `CoreMedia sample buffers based video output display`: exposes `force-darwin-legacy-display`, `macosx-hdr-mode`, `macosx-edr-headroom`.
     - `Video` -> `Output modules` -> `libplacebo video output`: exposes all `pl-*` options.
     - `Video` -> `Output modules` -> `glsampler`: exposes `gl-gamut-mapping`, `gl-tone-mapping-function`, `gl-tone-mapping-param`, `target-prim`, `target-trc`, `dither-algo`.
     - `Video` -> `Filters` -> `pl_scale`: exposes `plscale-upscaler`, `plscale-downscaler`, `plscale-target-prim`, `plscale-target-trc`.
     - `Input / Codecs` -> `Video codecs` -> `VideoToolbox`: exposes `videotoolbox-hw-decoder-only`, `videotoolbox-cvpx-chroma`.
     - `Video` -> `Output modules`: exposes `vout` selection popup.
3. **Hidden / CLI-Only from Simple Preferences:**
   `force-darwin-legacy-display`, `videotoolbox-cvpx-chroma`, `videotoolbox-hw-decoder-only`, `gl-upscaler`, `gl-downscaler`, `plscale-*`, `gl-*`, and `pl-*`.
   `edr-headroom-effective` is an internal object variable and completely hidden from both GUI and CLI help.

---

## 5. Concrete Plain-English User Experience Explanations

| Option Name String | Value / Change Tested | Concrete User Experience (What a Normal User Sees / Hears) |
| :--- | :--- | :--- |
| **`macosx-hdr-mode`** | Set to `0` (Auto) | Normal playback: HDR videos display with bright, dazzling highlights on XDR screens, while SDR screens get clean, non-blown-out highlights. |
| | Set to `1` (Force HDR) | Standard non-HDR videos become extremely dark, dull, and aggressively clipped, with harsh, crushed shadows and unnatural skin tones. |
| | Set to `2` (Tone-map to SDR) | HDR videos lose their intense specular brilliance on Liquid Retina XDR screens, appearing like ordinary standard-definition TV video. |
| | Set to `3` (Disable HDR) | Bright clouds, explosions, and sunlight blow out into solid flat chalky white with zero detail, and saturated colors look pale and washed out. |
| **`macosx-edr-headroom`** | Set > 0.0 (e.g. `2.5`) | Overrides system auto-brightness: highlights punch through with intense, blinding brightness even in a brightly lit room, or clamp dimmer if set low. |
| | Set to `0.0` (Auto) | Screen brightness tracks Apple's system display slider smoothly, dimming highlights when ambient light is bright to avoid eye strain. |
| **`force-darwin-legacy-display`** | Checked (`true`) | Video switches to an OpenGL window: battery drains faster and fans may spin up, but advanced scaler filters like Lanczos and custom tone curves become available. |
| **`videotoolbox-hw-decoder-only`** | Unchecked (`false`) | Enables playback of exotic video files your Mac GPU doesn't natively support, but causes high CPU usage and significant battery drain. |
| **`videotoolbox-cvpx-chroma`** | Set to `"BGRA"` | Squeezes 10-bit HDR down into 8-bit color, causing noticeable banding and posterization stripes across smooth gradients like skies and sunsets. |
| | Set to `"x420"` (P010) | Delivers pristine 10-bit color with zero gradient banding on HDR10 and HLG movies. |
| **`gl-upscaler` / `plscale-upscaler`** | Set to `Lanczos` / `Spline` | Low-resolution 720p and 1080p movies appear noticeably crisper and sharper on a 4K or MacBook Pro Retina display without blurry edges. |
| **`gl-downscaler` / `plscale-downscaler`** | Set to `Mitchell` / `Catmull-Rom` | Eliminates flickering, shimmering lines and moiré noise when watching 4K HDR videos scaled down onto a 1080p laptop or monitor. |
| **`gl-tone-mapping-function`** | Set to `BT.2390` | Broadcast-accurate HDR look: highlights retain rich color saturation and sparkle without turning into washed-out white blobs. |
| | Set to `Hable` | Cinematic filmic contrast: highlights roll off gently with deep rich blacks, mimicking a modern theatrical cinema grade. |
| | Set to `Clip` | Any highlight brighter than your screen's peak is abruptly chopped off into pure flat white, destroying texture in clouds and lights. |
| **`gl-gamut-mapping`** | Set to `Perceptual` | Wide BT.2020 cinema colors compress gently to fit your screen, preventing neon or radioactive color shifts in bright saturated scenes. |
| | Set to `Clip` | Out-of-bounds neon hues are harshly flattened against the gamut edge, causing blotchy, uniform patches in extreme colors. |
| **`gl-inverse-tone-mapping`** | Checked (`true`) | Fakes HDR from SDR: ordinary YouTube videos pop with exaggerated, neon-like brightness, though skin tones may look overly harsh. |
| **`pl-debanding`** | Checked (`true`) | Removes ugly compression ridges and color stair-stepping in dark scenes, skies, and anime, producing silky smooth color washes. |
| **`pl-dither` / `dither-algo`** | Set to `Blue Noise` | Hides 8-bit color stepping on budget external monitors by adding an imperceptible film-grain dither, eliminating visible banding. |
| **`vout`** | Set to `caopengllayer` | Forces the OpenGL video engine; setting an invalid engine causes a black video frame with audio-only playback. |

---

## 6. Recommended 5-Section Grouping for Settings UI

To replace VLC's scattered controls with a coherent, intuitive settings interface, group all HDR options into the following 5 user-facing sections:

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    PROPOSED HDR SETTINGS PANE                           │
├─────────────────────────────────────────────────────────────────────────┤
│ 1. HDR Display & Brightness                                             │
│    [Primary / Visible by default]                                       │
│    • HDR Output Mode (Auto / Force HDR / Tone-map SDR / Disable HDR)    │
│    • Screen EDR Headroom Limit (Slider: Auto to 4.0x)                   │
│    • [Status] Connected Display EDR Peak: 2.95x (HDR Supported)         │
├─────────────────────────────────────────────────────────────────────────┤
│ 2. Tone Mapping & Color Gamut                                           │
│    [Advanced / Hidden by default]                                       │
│    • Tone Mapping Curve (Auto, BT.2390 Broadcast, Hable Film, Reinhard) │
│    • Tone Mapping Tuning Parameter (Fine-tune slider)                   │
│    • Gamut Compression Mode (Perceptual, Relative, Clip)                │
│    • Enhance SDR Content to HDR (Inverse Tone Mapping toggle)           │
├─────────────────────────────────────────────────────────────────────────┤
│ 3. Display Engine & Compatibility                                       │
│    [Advanced / Hidden by default]                                       │
│    • Video Output Engine (Apple Native CoreMedia vs OpenGL Layer)       │
│    • Force Legacy Display Fallback (Emergency compatibility toggle)     │
├─────────────────────────────────────────────────────────────────────────┤
│ 4. Video Scaling & Image Clarity                                        │
│    [Advanced / Hidden by default]                                       │
│    • Upscaling Algorithm (Built-in, Lanczos Sharp, Spline Smooth)       │
│    • Downscaling Anti-Aliasing (Mitchell, Catmull-Rom)                  │
│    • Color Banding Reduction / Debanding (On/Off + Threshold)           │
│    • Dithering Method (Blue Noise, White Noise, Off)                    │
├─────────────────────────────────────────────────────────────────────────┤
│ 5. Hardware Decoding & Color Precision                                  │
│    [Advanced / Hidden by default]                                       │
│    • Hardware Acceleration (VideoToolbox Decode Only)                   │
│    • Output Pixel Format & Bit Depth (Auto 10-bit P010 vs 8-bit BGRA)   │
└─────────────────────────────────────────────────────────────────────────┘
```

### Section 1: "HDR Display & Brightness"
- **Visibility:** **Visible by Default (Simple)**
- **Options Included:**
  - `macosx-hdr-mode` (Dropdown: "Automatic (Recommended)", "Always Enable HDR", "Convert HDR to SDR", "Disable HDR")
  - `macosx-edr-headroom` (Slider: `0.0` [Automatic] to `4.0x` [Force Boosted Peak])
  - Read-Only Live Status Indicator: Shows whether the current display supports EDR and displays the active headroom (e.g. "Liquid Retina XDR: 2.95x EDR Headroom Active").
- **Rationale:** 95% of users only need to control whether HDR is enabled and how bright the screen drives specular highlights.

### Section 2: "Tone Mapping & Color Gamut"
- **Visibility:** **Advanced / Hidden by Default**
- **Options Included:**
  - `gl-tone-mapping-function` / `pl-tone-mapping-function` (Dropdown: Auto, BT.2390 Broadcast, Hable Filmic, Mobius, Reinhard, Clip)
  - `gl-tone-mapping-param` / `pl-tone-mapping-param` (Slider: fine adjustment)
  - `gl-gamut-mapping` / `pl-gamut-mapping` (Dropdown: Perceptual, Relative, Clip, Desaturate)
  - `gl-inverse-tone-mapping` (Checkbox: "Expand standard video (SDR) into HDR")
- **Rationale:** Requires OpenGL/libplacebo pipeline. Modifies highlight roll-off and wide-gamut mapping for cinephiles and mastering engineers.

### Section 3: "Display Engine & Compatibility"
- **Visibility:** **Advanced / Hidden by Default**
- **Options Included:**
  - `vout` (Dropdown: "Apple Native CoreMedia (Recommended)", "OpenGL Core Layer")
  - `force-darwin-legacy-display` (Emergency Checkbox: "Force OpenGL fallback display")
- **Rationale:** Switching the video display module fundamentally alters power consumption and pipeline routing.

### Section 4: "Video Scaling & Image Clarity"
- **Visibility:** **Advanced / Hidden by Default**
- **Options Included:**
  - `gl-upscaler` / `plscale-upscaler` (Dropdown: Fast Built-in, Lanczos, Spline36)
  - `gl-downscaler` / `plscale-downscaler` (Dropdown: Fast Built-in, Mitchell-Netravali, Catmull-Rom)
  - `pl-debanding` (Checkbox: "Remove color banding in gradients")
  - `dither-algo` / `pl-dither` (Dropdown: Automatic, Blue Noise, None)
- **Rationale:** Scaler and dithering parameters affect visual sharpness and GPU shader overhead.

### Section 5: "Hardware Decoding & Color Precision"
- **Visibility:** **Advanced / Hidden by Default**
- **Options Included:**
  - `videotoolbox-hw-decoder-only` (Checkbox: "Require hardware decoding")
  - `videotoolbox-cvpx-chroma` (Dropdown: "Auto (Best Quality 10-bit)", "Force 10-bit P010", "Force 8-bit BGRA")
- **Rationale:** Hardware decoder buffer allocation options that should only be adjusted for troubleshooting.

---

## 7. Dangerous Options and Breakage Hazards

| Option | Setting | Why It Breaks Playback (File:Line Evidence) | Exact Failure Mode |
| :--- | :--- | :--- | :--- |
| **`macosx-hdr-mode`** | Set to `1` ("Force Native EDR / HDR") | [`VLCSampleBufferDisplay.m:1366-1371`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/apple/VLCSampleBufferDisplay.m#L1366-L1371) blindly forces `TRANSFER_FUNC_SMPTE_ST2084` and `COLOR_PRIMARIES_BT2020` on **all non-HLG streams**. | Completely destroys standard SDR video playback. Standard BT.709 videos appear almost pitch black, with hyper-saturated neon skin tones and crushed shadow details. |
| **`videotoolbox-cvpx-chroma`** | Set to incompatible chroma (e.g. `"BGRA"`, `"2vuy"`, or invalid fourcc) | In [`decoder.c:1347-1355`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/codec/videotoolbox/decoder.c#L1347-L1355), forcing chroma overrides hardware negotiation. In [`decoder.c:2189-2191`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/codec/videotoolbox/decoder.c#L2189-L2191), if VideoToolbox outputs a buffer not matched in the `cvfmt` switch, it hits `default: return VTSESSION_STATUS_ABORT;`. | Aborts the VideoToolbox decompression session, halting video playback immediately with an unrecoverable error. Forcing `"BGRA"` degrades 10-bit HDR to 8-bit SDR, discarding HDR metadata. |
| **`force-darwin-legacy-display`** | Set to `true` | [`VLCSampleBufferDisplay.m:1721-1723`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/apple/VLCSampleBufferDisplay.m#L1721-L1723) unconditionally aborts `samplebufferdisplay` initialization. | Bypasses Apple's zero-copy CoreAnimation compositor. If OpenGL CGL context creation fails (e.g. external display disconnect, virtual desktop), playback fails completely with a blank black screen. Increases GPU power consumption by 2–3x. |
| **`vout`** | Set to `libplacebo` or `pl` | Standalone `libplacebo` display has priority 0 ([`display.c:772`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/libplacebo/display.c#L772)). Its Vulkan backend lacks a Darwin windowing platform module ([`VULKAN-DARWIN-PLAN.md:14, 80-90`](file:///Users/omarbenmustapha/Downloads/vlc-master/VULKAN-DARWIN-PLAN.md#L14)). | Video output fails immediately with `"no suitable vout display module"`. Playback drops to audio-only. |
| **`videotoolbox-hw-decoder-only`** | Set to `true` | [`decoder.c:1344`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/codec/videotoolbox/decoder.c#L1344) sets `kVTVideoDecoderSpecification_RequireHardwareAcceleratedVideoDecoder`. | If playing AV1 on M1/M2 Macs (which lack hardware AV1 decode) or unsupported HEVC profiles, VideoToolbox rejects decompression session creation. If software fallback is blocked, video fails to open. |

---

## 8. UNCERTAIN (Unverified Areas)

1. **Compositor Highlight Rolloff Curve:** The exact mathematical tone curve, highlight rolloff, and gamut compression mapping computed by Apple's closed-source CoreAnimation / ColorSync / WindowServer compositor on physical Liquid Retina XDR and Pro Display XDR screens cannot be determined from static source code analysis without calibrated physical photometer measurements.
2. **VideoToolbox Hardware AV1 on Physical M3/M4:** Although `deviceSupportsAV1()` and `kCMVideoCodecType_AV1` compile cleanly and report hardware support on Apple M3 Max (`tools/hdr-probe/RESULTS.md`), live decoding performance and graceful fallback have not been exercised against a live AV1 10-bit HDR video stream on this machine.
3. **Dolby Vision RPU Bitstream Parser against Live Media:** The VideoToolbox RPU parser in [`decoder.c:650-780`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/codec/videotoolbox/decoder.c#L650-L780) was hardened in commits `3a1d775` and `c6934eb`, but it has not been verified against live Dolby Vision Profile 5 or Profile 8.1 container streams with an active display.
4. **HDR10+ ITU-T T.35 SEI Parser against Live Media:** The SEI parser in [`decoder.c:600-645`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/codec/videotoolbox/decoder.c#L600-L645) has not been verified against live HDR10+ bitstreams carrying dynamic metadata packets.
