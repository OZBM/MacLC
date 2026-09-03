# Handoff — HDR on macOS / Apple Silicon in VLC 4.0.0-dev

## 1. Context in 10 lines
1. VLC 4.0.0-dev on macOS delegates 100% of HDR tone mapping to the operating system compositor (CoreAnimation, ColorSync, WindowServer) on its primary display path (samplebufferdisplay), leaving internal engines like libplacebo completely unreachable.
2. A technical audit conducted on September 2, 2026 against pre-work baseline commit 99034f9 revealed 6 confirmed defects and 9 missing architectural features on Apple Silicon (M1–M4).
3. Critical audit findings included non-functional GUI EDR sliders, a missing SDR tone-mapping branch, static EDR headroom evaluated only from [NSScreen mainScreen], untagged subtitles causing blinding luminance over PQ video, downsampling >10-bit HEVC to 8-bit BGRA, and lack of ARM64 NEON vectorization in chroma conversions.
4. Missing capabilities spanned hardware AV1 decoding on M3/M4, Dolby Vision RPU extraction in VideoToolbox, end-to-end dynamic HDR10+ delivery, Darwin Vulkan platform support for libplacebo, and zero automated test coverage.
5. In response, commit 912f9fa resolved the four confirmed display defects, added an M3/M4 hardware AV1 decoder path, routed >10-bit HEVC to P010, and implemented ARM64 NEON semi-planar/planar chroma conversions.
6. Commit 1705a0f introduced comprehensive runtime debugging for applied EDR headroom, CoreAnimation dynamic range states, buffer color properties, and BT.2408 subtitle scaling.
7. Commit f28fae4 enabled caopengllayer to negotiate OpenGL 4.1/3.2 Core profiles with 64-bit color depth, unblocking libplacebo OpenGL shaders from initialization failures.
8. Commit dd62400 plumbed HDR10+ dynamic metadata (VLC_ANCILLARY_ID_HDR10PLUS) through the OpenGL filter chain (filters.c) into vlc_placebo_HdrMetadata in pl_scale.c.
9. Commit 1a2b147 established the first automated test suites: copy_neon for NEON chroma SIMD routines and cvpx_hdr_metadata for CoreVideo PQ/HLG/mastering metadata round-tripping.
10. Significant work remains stranded or unfinished, including a broken Dolby Vision RPU bitstream parser on branch dovi-rpu-wip, missing HDR10+ auto-insertion, unconfigured display targets in pl_scale, and unmerged teardown stability fixes.

## 2. Repository state
- **Absolute Repository Path:** `/Users/omarbenmustapha/Downloads/vlc-master`
- **VLC Version & Upstream Baseline:** `4.0.0-dev` (Codename "Otto Chriek", Library ABI version `12.0.0`, Changeset tag `4.0.0-dev-arm64-hdr`, Target OS baseline macOS 10.13+).
  - Defined in `configure.ac:6-11, 27-29, 33`, `meson.build:2-4, 7, 10`, `NEWS:9`, and `src/revision.c:1`.
  - Core platform capabilities: VLC 4.0 player pipeline (`vlc_player_t` via `include/vlc_player.h`), audio-driven master clock architecture, and per-picture ancillary metadata framework (`include/vlc_ancillary.h`).
- **Active Git Branches:**
  - `main`: Active development branch carrying the committed HDR fixes, logging, OpenGL Core profile support, HDR10+ GL filter plumbing, and unit test suites (tip at `b91aa25`).
  - `dovi-rpu-wip`: Experimental branch containing in-progress VideoToolbox Dolby Vision RPU parsing (commit `964d210`, branched from `1a2b147`).
  - `macos-fix-teardown-use-after-free`: Stability branch fixing reproducible teardown crashes on playback stop and application quit (commit `09fc7f5`, branched from `b91aa25`).

### Commit List (One Line Each)
- `99034f9` baseline before HDR work
- `912f9fa` macos: HDR fixes for Apple Silicon
- `1705a0f` macos: log the applied HDR mode and dynamic-range state
- `f28fae4` caopengllayer: request a Core Profile so the GL sampler can start
- `dd62400` opengl: carry HDR10+ dynamic metadata to libplacebo
- `1a2b147` test: cover the NEON chroma conversions and CoreVideo HDR metadata
- `b91aa25` Add the remaining upstream sources to complete the baseline
- `964d210` WIP: Dolby Vision RPU parsing on the VideoToolbox path
- `09fc7f5` macos: fix crash on quit at the end of playback

### Committed on `main` vs. Stranded on Branches

| Feature / Subsystem | Commit(s) | Branch | Status & Impact |
| :--- | :--- | :--- | :--- |
| **AVSampleBufferDisplayLayer EDR Pipeline** | `912f9fa`, `1705a0f` | `main` | **Committed:** Dynamic headroom evaluation, `CADynamicRangeHigh`, `contentsHeadroom`, `toneMapMode`. |
| **HDR Display Modes (0, 1, 2, 3)** | `912f9fa`, `1705a0f` | `main` | **Committed:** Auto, Force HDR, Mode 2 SDR tone-mapping via `CADynamicRangeStandard` (BT.709 fallback), Disable HDR. |
| **Subtitle ITU-R BT.2408 Adaptation** | `912f9fa`, `1705a0f` | `main` | **Committed:** Subtitles tagged in sRGB, opacity scaled to 203 nits reference white relative to display headroom. |
| **Hardware AV1 Decoding (M3/M4)** | `912f9fa` | `main` | **Committed:** VideoToolbox hardware decode for AV1 gated on `deviceSupportsAV1()` (`VTIsHardwareDecodeSupported`). |
| **>10-Bit HEVC Chroma Path** | `912f9fa` | `main` | **Committed:** Routes 12/16-bit HEVC to P010 (`kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange`) rather than 8-bit BGRA. |
| **ARM64 NEON Chroma SIMD** | `912f9fa`, `1a2b147` | `main` | **Committed:** Vectorized NV12/P010 <-> I420/I420_10L SIMD routines with unit test `copy_neon`. |
| **CVPixelBuffer HDR Round-trip Tests** | `1a2b147` | `main` | **Committed:** Standalone unit test `cvpx_hdr_metadata` covering PQ, HLG, and negative unattached cases. |
| **OpenGL Core Profile (4.1 / 3.2)** | `f28fae4` | `main` | **Committed:** Enables `caopengllayer` to negotiate Core profiles required by `libplacebo` GL shaders. |
| **OpenGL ST 2086 / CTA-861.3 Forwarding** | `912f9fa` | `main` | **Committed:** Copies mastering display and light level metadata from `vd->source` into `caopengllayer`. |
| **OpenGL HDR10+ Dynamic Metadata** | `dd62400` | `main` | **Committed:** Carries `VLC_ANCILLARY_ID_HDR10PLUS` through GL filter chain to `vlc_placebo_HdrMetadata`. |
| **VideoToolbox Dolby Vision RPU Parser** | `964d210` | `dovi-rpu-wip` | **Stranded (Broken):** Bitstream parser desynchronises at partition fields; no metadata attached to frames. |
| **Teardown Use-After-Free Crash Fix** | `09fc7f5` | `macos-fix-teardown-use-after-free` | **Stranded (Ready):** Resolves 100% reproducible crash on application quit/teardown; ready for merge onto `main`. |

## 3. Architecture of the macOS HDR pipeline

### End-to-End Pipeline: Demux to Screen
```
[Container / Demuxer: MKV / MP4 / TS]
         │ (Container descriptors: ST 2086 mdcv, CTA-861.3 clli, VUI SPS/PPS)
         ▼
[Decoder Selection: modules/codec/]
   ├─ Hardware: videotoolbox/decoder.c (Priority 800)
   │     ├─ Codecs: H.264, HEVC, AV1 (M3+ via deviceSupportsAV1()), ProRes, DV
   │     ├─ Output: CVPixelBufferRef (VLC_CODEC_CVPX_P010 for 10-bit)
   │     └─ Attachments: Matrix, Primaries, Transfer, mdcv (24B), clli (4B)
   └─ Software Fallbacks:
         ├─ dav1d.c (Priority 10000): Software AV1 10-bit (M1/M2 or software path)
         └─ avcodec/video.c: VP9 Profile 2 / HEVC fallback (planar I420_10L)
         │
         ▼
[Vout Display Election & Core: vout_display_Prepare]
   │
   ├─► Priority 600: modules/video_output/apple/VLCSampleBufferDisplay.m (DEFAULT WINNER)
   │     ├─ Software input? -> CreateCVPXConverter() filters planar I420_10L -> CVPX_P010
   │     ├─ Merge fmt colorimetry into CVPixelBuffer attachments (vt_utils.c)
   │     ├─ Apply macosx-hdr-mode & window-screen contentsHeadroom
   │     ├─ Wrap CVPixelBuffer -> CMVideoFormatDescription -> CMSampleBufferRef
   │     ├─ Enqueue into AVSampleBufferDisplayLayer
   │     └─ Subtitles: Rendered into ARGB sRGB spuView, opacity scaled to 203 nits
   │           │
   │           ▼
   │     [Apple CoreAnimation & WindowServer Compositor]
   │           │ (OS handles 100% of tone mapping, gamut mapping, and EDR expansion)
   │           ▼
   │     [Apple Silicon Display Engine -> Liquid Retina XDR / Pro Display XDR / HDMI 2.1]
   │
   ├─► Priority 300: modules/video_output/caopengllayer.m (FALLBACK)
   │     ├─ Triggered by --force-darwin-legacy-display or 360° projection
   │     ├─ Acquires CGL Core Profile 4.1/3.2 context with 64-bit RGBA16F depth
   │     ├─ Sets layer wantsExtendedDynamicRangeContent, ExtendedLinearDisplayP3
   │     └─ Uses OpenGL shaders / libplacebo pl_scale (if up/downscalers active)
   │
   ├─► Priority 290: modules/gui/macosx/ (Legacy NSOpenGLView display)
   │
   └─► Priority 0: modules/video_output/libplacebo/display.c (NEVER ELECTED)
         └─ Vulkan backend (placebo_vk) lacks Darwin platform module (no CAMetalLayer)
```

### Module Priorities and Election
- `10000`: `dav1d` (software AV1 decoder).
- `800`: `videotoolbox` (hardware video decoder).
- `600`: `samplebufferdisplay` (`VLCSampleBufferDisplay.m`): Unconditional winner for video display on macOS.
- `300`: `caopengllayer` (`caopengllayer.m`): Fallback display module.
- `290`: `macosx` (deprecated `NSOpenGLView` display).
- `0`: `vout libplacebo` (`libplacebo/display.c`): Disabled from auto-selection.

### The Structuring Architectural Fact: 0% Tone Mapping by VLC
On macOS / Apple Silicon, the video output pipeline behaves fundamentally differently from Linux or Windows:
1. **Delegation to OS Compositor:** When running through the primary `samplebufferdisplay` path, VLC performs **0% of tone mapping, color space conversion, or gamut compression**. VLC merely tags the `CVPixelBufferRef` with CoreVideo color attachments (`kCVImageBufferTransferFunctionKey`, `kCVImageBufferColorPrimariesKey`, `kCVImageBufferYCbCrMatrixKey`, `kCVImageBufferMasteringDisplayColorVolumeKey`, `kCVImageBufferContentLightLevelInfoKey`), wraps the buffer in a `CMSampleBuffer`, and enqueues it directly into `AVSampleBufferDisplayLayer`.
2. **Apple Compositor Execution:** The operating system compositor (`CoreAnimation`, `ColorSync`, and `WindowServer`) reads the buffer attachments, evaluates the active display profile, queries the display's physical EDR capability, and executes the dynamic range compression in hardware using the Apple Silicon Display Engine.
3. **Inaccessibility of `libplacebo`:** VLC's advanced reference tone-mapping engine (`libplacebo`), which implements 9 configurable tone-mapping algorithms, is completely bypassed:
   - Its standalone vout module (`modules/video_output/libplacebo/display.c`) sits at priority 0 and is never chosen during module probing.
   - Its Vulkan backend (`placebo_vk`) cannot initialize because Darwin lacks a Vulkan windowing platform module (`VK_EXT_metal_surface` / `CAMetalLayer` bridge).
   - Even when forcing the OpenGL fallback (`caopengllayer`), `libplacebo` is only engaged as an OpenGL filter (`pl_scale`) if scaling is active or Dolby Vision is signaled on `fmt_in`. Dynamic metadata arriving per-frame is ignored by the default sampler.

## 4. What is already implemented

### 4.1 `VLCSampleBufferDisplay.m` (`modules/video_output/apple/VLCSampleBufferDisplay.m`)
- **Module Lifecycle & Fallback:**
  - `Open()` (`VLCSampleBufferDisplay.m:1718-1787`): Checks `--force-darwin-legacy-display` (`:1721-1723`) and non-rectangular projection (`:1727`), returning `VLC_EGENERIC` to yield to `caopengllayer`. If software decoding is detected (`!vlc_video_context_HoldType(..., VLC_VIDEO_CONTEXT_CVPX)` at `:1731-1736`), instantiates `CreateCVPXConverter()` (`:431-488`) to filter CPU frames into `VLC_CODEC_CVPX_P010` (`:449-461`).
  - Reads `macosx-edr-headroom` (`:1749-1758`) and binds live variable callbacks `EdrHeadroomCallback()` (`:1245-1258`) and `HdrModeCallback()` (`:1260-1267`).
  - Declares subpicture chroma support for `VLC_CODEC_ARGB` (`:1779-1784`).
- **Layer Configuration & EDR Setup:**
  - `makeBackingLayer` (`:672-709`): Creates `AVSampleBufferDisplayLayer`. Enables `wantsExtendedDynamicRangeContent = YES` (macOS 10.15+), `preferredDynamicRange = CADynamicRangeHigh` (macOS 14+), queries screen headroom via `maximumExtendedDynamicRangeColorComponentValue`, sets `contentsHeadroom = headroom`, and sets `toneMapMode = CAToneMapModeIfSupported` (macOS 15+).
  - `VLCSampleBufferSubpictureView` (`:584-654`): Subtitle overlay layer created with `wantsExtendedDynamicRangeContent = NO` and `contentsHeadroom = 1.0` (`:589-611`) to prevent highlight expansion on text.
  - `setupScreenObservers` (`:876-895`): Subscribes to `NSApplicationDidChangeScreenParametersNotification`, `NSWindowDidChangeScreenNotification`, and `NSWindowDidChangeScreenProfileNotification`. Handlers (`screenParametersDidChange:`, `windowDidChangeScreen:`, `windowDidChangeScreenProfile:` at `:898-924`) invoke `updateDynamicRangeAndHeadroom`.
- **Dynamic Headroom & Mode Adaptation:**
  - `updateDynamicRangeAndHeadroom` (`:926-1173`): Evaluates headroom from `self.window.screen ?: [NSScreen mainScreen]` (`:947-952`). Applies user override `_userHeadroom` (`:966-972`).
  - For SDR Modes 2 and 3 (`:982-1046`): Applies `CADynamicRangeStandard`, `CAToneMapModeAutomatic`, and `wantsExtendedDynamicRangeContent = NO`.
  - For HDR Modes 0 and 1 (`:1055-1134`): Applies `CADynamicRangeHigh`, `CAToneMapModeIfSupported`, `extendedSRGBColorSpace`, and `wantsExtendedDynamicRangeContent = YES`.
  - Subtitle Adaptation (`:1142-1170`): Calculates scaling factor `factor = 203.0f / (100.0f * effectiveHeadroom)` (derived from ITU-R BT.2408 reference white 203 nits over SDR 100 nits * headroom), clamps between 0.15 and 1.0, and sets `spuView.layer.opacity = (float)factor`.
- **Frame Render & Presentation:**
  - `RenderPicture()` (`:1282-1487`): Routes software frames through chroma filter (`:1330-1332`), extracts `CVPixelBufferRef` (`:1334`), and applies rotation (`:1343-1349`). Merges format metadata (`:1352-1362`).
  - Evaluates `macosx-hdr-mode` (`:1364-1401`): Mode 1 forces ST 2084 / BT.2020; Mode 2 applies layer tone-mapping or falls back to BT.709 buffer retagging on macOS < 14 (`:1388-1390`); Mode 3 forces BT.709 (`:1393-1395`).
  - Calls `cvpx_attach_mapped_color_properties()` (`:1404`) and `cvpx_attach_hdr_metadata()` (`:1405`). Attaches pixel aspect ratio (`:1440-1452`).
  - Wraps buffer in `CMVideoFormatDescriptionRef` (`:1456`), timestamps via `CACurrentMediaTime()` (`:1463-1472`), encapsulates in `CMSampleBufferRef` (`:1474`), and enqueues via `[sys.displayLayer enqueueSampleBuffer:sampleBuffer]` (`:1483`).
  - `UpdateSubpictureRegions()` (`:1503-1556`): Renders subtitle subpictures into tagged `kCGColorSpaceSRGB` rather than device-dependent RGB (`:1531`).
- **Verification:** Verified via extensive debug logging in `1705a0f` (`msg_Dbg` at `:902, 911, 920, 1048, 1051, 1128, 1131, 1163, 1434`), static audit inspections, and screen change notifications.

### 4.2 `caopengllayer.m` (`modules/video_output/caopengllayer.m`)
- **CGL Context Negotiation:**
  - `vlc_CreateCGLContext()` (`caopengllayer.m:212-305`): Implements fallback loop requesting OpenGL 4.1 Core (`kCGLOGLPVersion_GL4_1_Core = 0x4100`), falling back to 3.2 Core (`kCGLOGLPVersion_GL3_2_Core = 0x3200`), and finally legacy 2.1. Combines profile with deep-color requests: 64-bit color (16 bits/channel RGBA, 16-bit alpha for EDR) falling back to standard 24-bit color (`:221-286`). Logs resulting context properties (`:300-302`).
- **HDR Setup & Screen Observers:**
  - `Open()` (`:533-680`): Inspects `vd->source` for ST 2086 mastering display metadata and CTA-861.3 lighting metadata, injecting into `fmt` (`:588-591`). Checks `is_hdr` (`:606-609`) and invokes `[view setHDR:is_hdr]` (`:615`).
  - `init:` (`:687-720`): Subscribes to `NSApplicationDidChangeScreenParametersNotification`, `NSWindowDidChangeScreenNotification`, and `NSWindowDidChangeScreenProfileNotification`. Unsubscribes in `vlcClose` (`:802-832`) and `dealloc` (`:834-843`).
  - Backing layer `VLCCAOpenGLLayer` (`:938-986`): Configured with `wantsExtendedDynamicRangeContent = YES` and `colorspace = kCGColorSpaceExtendedLinearDisplayP3` (`:960-965`).
  - `updateDynamicRangeWithHeadroom:isHDR:` (`:988-1017`): Updates `wantsExtendedDynamicRangeContent = YES`, `preferredDynamicRange = isHDR ? CADynamicRangeHigh : CADynamicRangeStandard`, `contentsHeadroom = headroom`, and `toneMapMode = isHDR ? CAToneMapModeIfSupported : CAToneMapModeAutomatic`.
- **Rendering Pipeline:**
  - `PictureRender()` (`:430-455`): Binds CGL context (`:437`), invokes `vout_display_opengl_Prepare()` (`:448`) to upload textures and run shaders, and marks layer ready via `[layer markReady]` (`:453`).
  - `drawInCGLContext:pixelFormat:forLayerTime:displayTime:` (`:1076-1105`): CoreAnimation render loop calls `vout_display_opengl_Display()` (`:623-639`) and executes `CGLFlushDrawable()` (`:831-836`).
- **Verification:** Verified by context profile debug logging (`:300-302`) and metadata logging (`:594-604`), confirming elimination of the "OpenGL version too old (2 < 3)" failure that prevented `libplacebo` GL shaders from loading.

### 4.3 VideoToolbox Hardware Decoder (`modules/codec/videotoolbox/decoder.c`, `vt_utils.c`)
- **AV1 Hardware Decoding (Apple Silicon M3/M4):**
  - Definition of `kCMVideoCodecType_AV1` (`'av01'`) (`decoder.c:53-55`).
  - `deviceSupportsAV1()` (`decoder.c:1567-1574`): Gated on `__aarch64__` and macOS 14.0+ / iOS 17.0+; executes `VTIsHardwareDecodeSupported(kCMVideoCodecType_AV1)`.
  - `CodecPrecheck()` (`decoder.c:964-978`): Allows `VLC_CODEC_AV1` if extradata is present and `deviceSupportsAV1()` returns true.
  - `CopyDecoderExtradataAV1()` (`decoder.c:821-830`): Packages `fmt_in->p_extra` into an `av1C` atom dictionary for session initialization. Bound in `OpenDecoder()` (`:1519-1524`).
- **Chroma Preservation (>10-Bit HEVC):**
  - `GetBestChroma()` (`decoder.c:154-196`): For `i_depth_luma > 10 && i_depth_chroma > 10`, replaces obsolete downsampling to 8-bit `kCVPixelFormatType_32BGRA` by falling back to `kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange` (P010) (`:184-191`).
  - `StartVideoToolbox()` (`decoder.c:1258-1288`): Recognizes 12-bit and 16-bit planar/semi-planar chromas (`I420_12L/B`, `I420_16L/B`, `P012`, `P016`) for pipeline configuration.
- **Colorimetric Tagging & Extraction (The Solid Part):**
  - Session Setup (`decoder.c:1130-1199`): `SetDecoderColorProperties()` maps `p_dec->fmt_out.video` into CoreVideo dictionaries:
    - Matrix: `cvpx_map_YCbCrMatrix_from_vcs()` (`vt_utils.c:309`) -> `kCVImageBufferYCbCrMatrixKey`.
    - Primaries: `cvpx_map_ColorPrimaries_from_vcp()` (`vt_utils.c:343`) -> `kCVImageBufferColorPrimariesKey`.
    - Transfer: `cvpx_map_TransferFunction_from_vtf()` (`vt_utils.c:366`) -> `kCVImageBufferTransferFunctionKey`.
    - ST 2086: `cvpx_create_mastering_display_color_volume_data()` (`vt_utils.c:484`) -> 24-byte big-endian binary payload (`kCVImageBufferMasteringDisplayColorVolumeKey`).
    - CTA-861.3: `cvpx_create_content_light_level_data()` (`vt_utils.c:519`) -> 4-byte packed big-endian payload (`kCVImageBufferContentLightLevelInfoKey`).
  - Extraction (`UpdateVideoFormat()` at `decoder.c:2124-2201` and `cvpx_extract_color_properties()` at `vt_utils.c:558-644`): Deserializes attachments from decoded `CVPixelBufferRef` and populates `fmt_out.video` colorimetry, ST 2086 mastering (`ntohs`/`ntohl`), and CTA-861.3 light levels (`ntohs`).
  - Propagation (`DecoderCallback()` at `decoder.c:2289-2305`): Symmetrically copies all color, mastering, and lighting structs directly to each newly allocated `picture_t`.
- **Verification:** Verified via standalone unit test `test/src/misc/cvpx_hdr_metadata.c` (validating PQ, HLG, and negative unattached buffers) and static code inspection.

### 4.4 ARM64 NEON Chroma Conversions (`modules/video_chroma/copy.c`)
- **Vectorized Implementations (`copy.c:634-873` under `#if defined(__aarch64__)`):**
  - `NEON_CopyPlane16()` (`:634-671`): Vectorized 16-bit plane copy with left or right bitshifting via `vld1q_u16`, `vshlq_u16` with `vdupq_n_s16(-bitshift)`, and `vst1q_u16`.
  - `NEON_SplitPlanes16()` (`:673-741`): De-interleaves 16-bit semi-planar UV (P010) into separate U and V planar buffers (I420_10L) with bitshift using `vld2q_u16`, `vshlq_u16`, and `vst1q_u16`.
  - `NEON_InterleavePlanes16()` (`:743-815`): Interleaves planar 16-bit U and V into semi-planar UV (P010) with bitshift using `vld1q_u16`, `vshlq_u16`, and `vst2q_u16`.
  - `NEON_SplitPlanes8()` (`:817-844`): De-interleaves 8-bit semi-planar UV (NV12) into U and V (I420) using `vld2q_u8` and `vst1q_u8`.
  - `NEON_InterleavePlanes8()` (`:846-873`): Interleaves planar 8-bit U and V into semi-planar UV (NV12) using `vld1q_u8` and `vst2q_u8`.
  - Wrappers: `NEON_Copy420_SP_to_P()`, `NEON_Copy420_16_SP_to_P()`, `NEON_Copy420_P_to_SP()`, and `NEON_Copy420_16_P_to_SP()` (`:875-917`).
- **Pipeline Dispatch Points:**
  - Integrated in `CopyPlane()` (`:928`), `Copy420_SP_to_P()` (`:1059`), `Copy420_16_SP_to_P()` (`:1085`), `Copy420_P_to_SP()` (`:1145`), and `Copy420_16_P_to_SP()` (`:1181`).
  - Invoked externally by `modules/video_chroma/cvpx.c:144, 153, 162, 167` (for CVPX <-> CPU planar transfers with shifts `+6` / `-6`) and `modules/video_chroma/i420_nv12.c:67, 91, 112, 126`.
- **Verification:** Fully verified by `test/src/video_chroma/copy_neon.c` comparing against independent mathematical reference models over diverse pitches, unaligned widths, bitshifts, and guard-canary boundaries.

### 4.5 OpenGL / libplacebo HDR10+ Plumbing
- **Header & Filter State:**
  - `include/vlc_opengl_filter.h:50`: Added `const vlc_video_hdr_dynamic_metadata_t *hdr10plus;` to `struct vlc_gl_input_meta`.
  - `modules/video_output/opengl/filters.c:147-149`: Added `vlc_video_hdr_dynamic_metadata_t hdr10plus`, `int has_hdr10plus`, and `bool hdr10plus_logged` to `filters->pic`. Initialized in `vlc_gl_filters_New()` (`:184-185`).
- **Ancillary Extraction & Propagation:**
  - `vlc_gl_filters_UpdatePicture()` (`filters.c:552-562`): Queries `picture_GetAncillary(picture, VLC_ANCILLARY_ID_HDR10PLUS)`. If present, logs receipt on first frame and copies payload into `filters->pic.hdr10plus`.
  - `vlc_gl_filters_Draw()` (`filters.c:588`): Attaches `.hdr10plus` pointer to `struct vlc_gl_input_meta meta` and passes it to filter draw calls.
  - `modules/video_output/opengl/pl_scale.c:Draw()` (`:184-186`): When `meta->hdr10plus` is non-NULL, invokes `vlc_placebo_HdrMetadata(meta->hdr10plus, &frame_in->color.hdr)`.
  - `modules/video_output/libplacebo/utils.c:453-473`: `vlc_placebo_HdrMetadata()` converts HDR10+ dynamic metadata into `pl_hdr_metadata` (scene max, scene avg, Bezier tone curve parameters).
- **Verification:** Verified via build and OpenGL filter compilation.

### 4.6 Automated Unit Tests (`test/Makefile.am`)
- **`test/src/misc/cvpx_hdr_metadata.c`:**
  - `test_cvpx_hdr_pq()` (`:39-98`): Allocates P010 `CVPixelBuffer`, attaches BT.2020 PQ, ST 2086, and CTA-861.3 metadata via `cvpx_attach_mapped_color_properties` / `cvpx_attach_hdr_metadata`, extracts via `cvpx_extract_color_properties`, and asserts equality across every struct member.
  - `test_cvpx_hdr_hlg()` (`:100-159`): Exercises identical attachment and extraction for HLG transfer functions.
  - `test_cvpx_hdr_negative()` (`:161-224`): Tests bare unattached P010 buffers and 8-bit NV12 SDR buffers, validating that unattached properties extract cleanly as 0 / undefined.
- **`test/src/video_chroma/copy_neon.c`:**
  - Independent reference models (`:159-322`) for SP-to-P and P-to-SP conversions in 8-bit and 16-bit.
  - Test framework (`:392-677`): Wraps buffers in canary guard patterns (`:75-108`) to detect out-of-bounds writes; iterates through aligned/unaligned pitches, odd image dimensions, and +-6 bitshifts. Off-architecture (`#if !defined(__aarch64__)` at `:38-44`) compiles to a clean skip (exit 0).
- **Build Registration:** Registered in `test/Makefile.am:74, 120, 157, 314-316, 335-336` and validated under `make check`.

## 5. What is NOT done

### 1. Dolby Vision RPU Bitstream Parsing on VideoToolbox Path
- **Priority:** High
- **Effort:** L (Large)
- **Problem:** Stranded on branch `dovi-rpu-wip` (commit `964d210`). The parser in `modules/codec/videotoolbox/decoder.c` detects NAL unit type 62 in `FillReorderInfoHEVC()`, allocates `vt_frame_info_t`, unescapes RBSP (`rpu_unescape_rbsp()`), and attaches `VLC_ANCILLARY_ID_DOVI` in `DecoderCallback()`. However, `ParseHEVCDoviRPU()` desynchronises immediately after reading `mapping_chroma_format_idc`. In Dolby Vision RPU bitstream syntax, partition metadata and slice/coefficient segmentation headers precede channel pivot points. Attempting to immediately read `num_pivots_minus_2` via `bs_read_ue(&bs)` reads garbage, violates pivot limits (`num_pivots > 9`), emits `"Dolby Vision RPU bitstream read error / truncated"`, and fails. No metadata is ever attached to pictures.
- **Exact Files & Lines:**
  - `modules/codec/videotoolbox/decoder.c:650-780` (on branch `dovi-rpu-wip`): Divergence in `ParseHEVCDoviRPU()`.
  - `modules/video_output/apple/VLCSampleBufferDisplay.m:1400-1410`: Display layer completely lacks code to forward Dolby Vision attachments to CoreMedia/CoreAnimation.
- **Concrete Approach:**
  1. Rewrite `ParseHEVCDoviRPU()` bitstream parsing following the SMPTE RPU / Dolby Vision bitstream specification: parse sequence header, partition fields, and slice coefficient metadata before iterating channel pivots.
  2. Align the parser data structures with `vlc_video_dovi_metadata_t` in `include/vlc_ancillary.h:239-276`.
  3. Wire extracted DoVi metadata into `VLCSampleBufferDisplay.m` by attaching CoreVideo Dolby Vision keys (or forward to `caopengllayer.m` / `libplacebo`).

### 2. HDR10+ End-to-End Delivery & Auto-Insertion
- **Priority:** High
- **Effort:** M (Medium)
- **Problem:** Although commit `dd62400` wired HDR10+ metadata through `filters.c` to `pl_scale.c`, three critical breaks exist:
  1. In `modules/video_output/opengl/vout_helper.c:122-124`, `pl_scale` is **only** loaded into the OpenGL filter chain if up/downscalers are specified or `fmt_in->dovi.rpu_present` is true. Because HDR10+ dynamic metadata arrives per-frame via ancillary data, `pl_scale` is never instantiated for pure HDR10+ streams.
  2. In `modules/video_output/opengl/pl_scale.c:184-186`, `vlc_placebo_HdrMetadata` mutates `frame_in->color.hdr` in place. When subsequent frames lack HDR10+ metadata (`meta->hdr10plus == NULL`), `frame_in->color.hdr` is never cleared, causing stale HDR10+ tone-mapping parameters to persist indefinitely.
  3. VideoToolbox hardware decoding ignores ITU-T T.35 SEI NALUs carrying HDR10+; it is only extracted by software `avcodec`.
- **Exact Files & Lines:**
  - `modules/video_output/opengl/vout_helper.c:122-146`: Filter auto-insertion condition.
  - `modules/video_output/opengl/pl_scale.c:184-186, 330-344`: Per-frame state reset and output target color configuration.
  - `modules/codec/videotoolbox/decoder.c:611-625`: Missing ITU-T T.35 SEI parsing in VideoToolbox.
- **Concrete Approach:**
  1. In `vout_helper.c`, instantiate `pl_scale` automatically whenever input transfer is ST 2084 or HLG.
  2. In `pl_scale.c:184`, add an `else` branch resetting `frame_in->color.hdr` back to static mastering metadata when `meta->hdr10plus == NULL`.
  3. Add ITU-T T.35 SEI NAL parsing in VideoToolbox to extract HDR10+ dynamic metadata into `VLC_ANCILLARY_ID_HDR10PLUS`.

### 3. Darwin Vulkan / MoltenVK Platform Module & `libplacebo` Vout Priority
- **Priority:** Medium
- **Effort:** L (Large)
- **Problem:** `vout libplacebo` (`modules/video_output/libplacebo/display.c`) sits locked at priority 0. Its Vulkan backend (`placebo_vk`) cannot start on macOS because there is no Darwin "vulkan platform" module providing `VK_EXT_metal_surface` integration over `CAMetalLayer`. VLC users on macOS are completely unable to access `libplacebo`'s 9 tone-mapping algorithms.
- **Exact Files & Lines:**
  - `modules/video_output/libplacebo/display.c:64-70`: Module priority definition (`set_callback_display(Open, 0)`).
  - `modules/video_output/vulkan/` (or new Darwin provider): Total absence of Darwin platform surface creation.
- **Concrete Approach:**
  1. Implement a Darwin Vulkan windowing platform module using MoltenVK (`VK_EXT_metal_surface`), attaching a `CAMetalLayer` to the macOS video view.
  2. Implement context creation and surface binding.
  3. Expose a GUI preference or dynamic fallback allowing users to select `vout libplacebo` with custom tone-mapping algorithms.

### 4. ColorSync ICC Profile Support in `libplacebo`
- **Priority:** Low
- **Effort:** S (Small)
- **Problem:** `modules/video_output/libplacebo/display.c:702` contains an explicit `// TODO: support for ICC profiles`. On macOS, display color characteristics are defined by ColorSync profiles, but `display.c` passes no ICC data to `libplacebo`.
- **Exact Files & Lines:**
  - `modules/video_output/libplacebo/display.c:702`: Unimplemented ICC profile stub.
- **Concrete Approach:**
  1. On Darwin, query the active window screen's ColorSync profile using `CGDisplayCopyColorSpace()` or `[NSScreen colorSpace]`.
  2. Extract raw ICC profile data via `CGColorSpaceCopyICCData()`.
  3. Feed the ICC byte array into `struct pl_icc_profile` in `libplacebo/display.c`.

### 5. True 12-Bit and 16-Bit Pipeline Handling
- **Priority:** Medium
- **Effort:** M (Medium)
- **Problem:** VideoToolbox clamps >10-bit HEVC to 10-bit P010 (`decoder.c:184-191`). An explicit TODO exists at `decoder.c:182`: `/* TODO: Add VLC_CODEC_CVPX_P016 across VLC when 16-bit CVPX pipeline support is added. */`. VLC lacks `VLC_CODEC_CVPX_P016` in `include/vlc_fourcc.h:498-502` and `modules/video_chroma/cvpx.c:140`. Furthermore, `decoder.c:2189-2191` aborts playback (`VTSESSION_STATUS_ABORT`) if hardware outputs any unexpected format (such as 16-bit biplanar or 4:2:2/4:4:4).
- **Exact Files & Lines:**
  - `include/vlc_fourcc.h:498-502`: Missing `VLC_CODEC_CVPX_P016`.
  - `modules/codec/videotoolbox/decoder.c:182-191, 2189-2191`: Clamping and abort paths.
  - `modules/video_chroma/cvpx.c:140-170`: Missing 16-bit CVPX chroma mapping.
  - `modules/video_chroma/copy.c`: Lack of P012/P016 semi-planar routines.
- **Concrete Approach:**
  1. Define `VLC_CODEC_CVPX_P016` in `include/vlc_fourcc.h`.
  2. Map `kCVPixelFormatType_420YpCbCr16BiPlanarVideoRange` in `cvpx.c` and `decoder.c`.
  3. Extend NEON routines in `copy.c` to support P016 without bitshift truncation.

### 6. Hardware AV1 Live Verification on Apple Silicon M3/M4
- **Priority:** Medium
- **Effort:** S (Small)
- **Problem:** Support for `kCMVideoCodecType_AV1` and `deviceSupportsAV1()` was committed in `912f9fa`, but it was verified only via SDK compilation and static analysis. Real-world runtime behavior on physical M3/M4 hardware under macOS 14+ has not been verified with live 10-bit AV1 bitstreams.
- **Exact Files & Lines:**
  - `modules/codec/videotoolbox/decoder.c:53-55, 83, 964-978, 1567-1574`.
- **Concrete Approach:**
  1. Execute playback of AV1 10-bit HDR streams on Apple M3 and M4 hardware running macOS 14+.
  2. Verify VideoToolbox hardware decompression session creation (`msg_Dbg` confirmation).
  3. Verify graceful fallback to `dav1d` on M1/M2 hardware.

### 7. Subtitle Reference-White Scaling Refinement
- **Priority:** Medium
- **Effort:** S (Small)
- **Problem:** In `modules/video_output/apple/VLCSampleBufferDisplay.m:1156`, the subtitle scale calculation is `factor = 203.0f / (100.0f * effectiveHeadroom)`. For any display where headroom is <= 2.03 (e.g. standard SDR displays at 1.0, or displays below ~400 nits), `factor >= 1.0` and gets clamped to `1.0`. Thus, subtitle attenuation only begins when headroom exceeds 2.03x and does nothing on intermediate displays. Additionally, line 1531 uses `kCGBitmapByteOrderDefault | kCGImageAlphaFirst`, which relies on host endianness matching CoreGraphics ARGB memory layout.
- **Exact Files & Lines:**
  - `modules/video_output/apple/VLCSampleBufferDisplay.m:1142-1170, 1531-1534`.
- **Concrete Approach:**
  1. Refine the luminance transfer curve so subtitle brightness transitions smoothly across headrooms between 1.0 and 2.0.
  2. Explicitly specify `kCGBitmapByteOrder32Host` in bitmap context creation (`:1531`).

### 8. Dynamic EDR Re-evaluation & Race Condition Hardening
- **Priority:** Medium
- **Effort:** M (Medium)
- **Problem:**
  1. Asynchronous initialization of `sys.displayLayer` on the main queue (`VLCSampleBufferDisplay.m:846-868`) creates a race condition where initial video frames reaching `RenderPicture` on the vout thread find `sys.displayLayer == nil` and are dropped silently (`:1321-1322`).
  2. In `VLCSampleBufferDisplay.m:1225`, calling `[[NSNotificationCenter defaultCenter] removeObserver:self]` during module teardown without synchronizing with the asynchronous UI blocks can lead to leaked notifications or selectors called during deallocation.
  3. `RenderPicture()` calls `var_InheritInteger(vd, "macosx-hdr-mode")` on every single frame (`:1364`), incurring unnecessary lock and tree-traversal overhead on the render thread.
  4. `caopengllayer.m:1001-1012` completely ignores `macosx-hdr-mode`.
- **Exact Files & Lines:**
  - `modules/video_output/apple/VLCSampleBufferDisplay.m:846-868, 1225, 1321-1322, 1364`.
  - `modules/video_output/caopengllayer.m:1001-1012`.
- **Concrete Approach:**
  1. Synchronize layer initialization or buffer pre-roll frames until the layer reports ready.
  2. Synchronize deallocation with `dispatch_sync` on the main thread before deallocating `sys`.
  3. Cache `macosx-hdr-mode` via `HdrModeCallback()` instead of reading via `var_InheritInteger` on every frame.
  4. Wire `macosx-hdr-mode` into `caopengllayer.m` to respect user HDR preferences.

### 9. Test Suite Registration in Meson Build System
- **Priority:** Medium
- **Effort:** S (Small)
- **Problem:** Commit `1a2b147` registered `cvpx_hdr_metadata` and `copy_neon` in `test/Makefile.am` (Autotools). However, both test suites are **completely absent** from all `meson.build` files (`test/src/meson.build` and `modules/video_chroma/meson.build`). In a Meson build, running `ninja test` compiles and executes neither test.
- **Exact Files & Lines:**
  - `test/src/meson.build:390-396`: Under `if host_system == 'darwin'`, only `image_cvpx` is registered.
  - `modules/video_chroma/meson.build:130-149`: Only SSE tests are registered.
- **Concrete Approach:**
  1. Add `test_src_misc_cvpx_hdr_metadata` to `test/src/meson.build` under `if host_system == 'darwin'`, linking `CoreVideo` and `libvlc_vtutils`.
  2. Add `test_src_video_chroma_copy_neon` to `test/src/meson.build` (or `modules/video_chroma/meson.build`), linking `chroma_copy_lib`.

### 10. Correction of Synthetic Metadata Attachment on HLG Streams
- **Priority:** High
- **Effort:** S (Small)
- **Problem:** In `modules/codec/vt_utils.c:476, 526` (and `:441-446, 506-512`), `is_hdr` includes `fmt->transfer == TRANSFER_FUNC_HLG`. HLG broadcast streams are relative, scene-referred transfers that do not have ST 2086 mastering volume or CTA-861.3 light level info. VLC's code generates and attaches synthetic 1000-nit HDR10 mastering and CLL metadata to HLG `CVPixelBuffer`s, violating HLG specifications and corrupting OS tone curve calculation.
- **Exact Files & Lines:**
  - `modules/codec/vt_utils.c:441-446, 476, 506-512, 526`.
- **Concrete Approach:**
  - Disallow synthetic ST 2086 and CTA-861.3 attachment when `fmt->transfer == TRANSFER_FUNC_HLG`. Attach mastering metadata only when transfer is SMPTE ST 2084 (PQ).

### 11. Mastering Display Luminance Heuristic & Core Color Adjustment Bugs
- **Priority:** Medium
- **Effort:** S (Small)
- **Problem:**
  1. In `modules/codec/vt_utils.c:477-478`, `if (max_l > 0 && max_l < 10000) max_l *= 10000;`. VLC defines `max_luminance` in 0.0001 nit units. Arbitrarily multiplying values below 10000 corrupts valid low mastering targets (<1 nit).
  2. In `modules/codec/vt_utils.c:464-471`, checking only `st2086.display_primaries[0][0] == 0` (Green.x) to trigger default BT.2020 primaries leaves red and blue primaries zeroed if green is non-zero.
  3. In `include/vlc_es.h:419-456`, `video_format_AdjustColorSpace()` forces undefined streams with height > 576 to BT.709, lacking heuristics for UHD/4K HDR streams.
- **Exact Files & Lines:**
  - `modules/codec/vt_utils.c:464-478`.
  - `include/vlc_es.h:419-456`.
- **Concrete Approach:**
  1. Correct the unit scaling logic in `vt_utils.c` to avoid corrupting fractional luminance values.
  2. Validate each primary coordinate individually.
  3. Update `video_format_AdjustColorSpace()` to check for UHD resolutions before defaulting to BT.709.

### 12. Teardown Concurrency Fix Integration
- **Priority:** High (Stability)
- **Effort:** S (Small)
- **Problem:** Branch `macos-fix-teardown-use-after-free` (commit `09fc7f5`) contains critical fixes for 100% reproducible crashes on quit when quitting while the 0.5s playback-ended timer is armed. It invalidates the timer, clears `p_interface_thread = NULL`, and guards deferred main queue blocks in `VLCVideoOutputProvider.m` and `VLCLibraryWindow.m`.
- **Exact Files & Lines:**
  - `modules/gui/macosx/playqueue/VLCPlayerController.m`
  - `modules/gui/macosx/main/VLCMain.m`
  - `modules/gui/macosx/windows/video/VLCVideoOutputProvider.m`
  - `modules/gui/macosx/library/VLCLibraryWindow.m`
- **Concrete Approach:**
  - Fast-forward merge `macos-fix-teardown-use-after-free` directly into `main`. The branch is cleanly rebased on `b91aa25` with zero merge conflicts.

## 6. Known risks, fragile code and open questions

### Report Discrepancies & Audit Pre-Work Baseline Warning
- **Line Number Divergence:** The technical audit (`report-pdf.md`) evaluated baseline commit `99034f9` prior to the HDR engineering work. All line references cited in the PDF differ from current tree line numbers (e.g. `Open()` in `VLCSampleBufferDisplay.m` moved from line 1291 to 1718; `CodecPrecheck()` in `decoder.c` moved from line 917 to 964). Current line numbers from `report-git.md`, `report-vout.md`, and `report-core.md` must be used.
- **Subtitle State:** `report-pdf.md` cataloged subtitles as completely unscaled in device-dependent RGB (`CGColorSpaceCreateDeviceRGB()`). Current tree implements tagged `kCGColorSpaceSRGB` (`VLCSampleBufferDisplay.m:1531`) and BT.2408 scaling (`:1156`), but with the threshold defect noted in Section 5.7.
- **HDR Mode 2 State:** `report-pdf.md` flagged Mode 2 ("Tone-map to SDR") as missing a branch in code. Current tree adds Mode 2 (`VLCSampleBufferDisplay.m:982-1046, 1381-1391`), but on macOS < 14 it falls back to a brute-force retag to BT.709 without color space tone mapping.

### Fragile and Questionable Code Catalog
1. **Attachment Mutation on Pooled CVPixelBuffers (`VLCSampleBufferDisplay.m:1404-1405`):**
   `cvpx_attach_mapped_color_properties` and `cvpx_attach_hdr_metadata` directly mutate attachments on `pixelBuffer`. Because VideoToolbox recycles `CVPixelBuffer`s through its decompression pool, mutating attachments directly can contaminate subsequent frames or external consumers if buffers are reused without being reset.
2. **Per-Frame Variable Lookup on Time-Critical Thread (`VLCSampleBufferDisplay.m:1364`):**
   Calling `var_InheritInteger(vd, "macosx-hdr-mode")` on every single frame inside `RenderPicture()` incurs unnecessary lock acquisition and config tree traversal.
3. **Brute-Force BT.709 Retagging (`VLCSampleBufferDisplay.m:1388-1390`):**
   Mode 2 on macOS < 14 and Mode 3 (Disable HDR) simply re-label the transfer and primaries as BT.709 without applying any algorithmic gamut mapping or tone curve compression, leading to severe highlight blowout and crushed colors.
4. **Mode 1 Blind Forcing of PQ/BT.2020 (`VLCSampleBufferDisplay.m:1366-1371`):**
   Mode 1 ("Force Native EDR / HDR") unconditionally forces `TRANSFER_FUNC_SMPTE_ST2084` and `COLOR_PRIMARIES_BT2020` on any non-HLG stream, severely corrupting SDR playback.
5. **Synthetic Metadata on HLG Content (`vt_utils.c:476, 526`):**
   HLG content is erroneously treated as `is_hdr`, synthesizing 1000-nit ST 2086 and CTA-861.3 metadata contrary to ITU-R BT.2100.
6. **Unconditional ExtendedLinearDisplayP3 in OpenGL Layer (`caopengllayer.m:961-965`):**
   Unconditionally setting the layer colorspace to `kCGColorSpaceExtendedLinearDisplayP3` forces the OS compositor to run linear Extended P3 conversions even for standard SDR BT.709 content.
7. **Presentation Timestamps with CACurrentMediaTime (`VLCSampleBufferDisplay.m:1463-1472`):**
   Timing `CMSampleBuffer`s against `CACurrentMediaTime()` in microsecond precision rather than the CoreMedia host clock (`CMClockGetHostTimeClock()`) risks audio/video desynchronization against CoreAudio.
8. **Asynchronous Display Layer Race Condition (`VLCSampleBufferDisplay.m:846-868`):**
   Main-thread dispatch of layer creation creates a race condition where initial frames reaching `RenderPicture` drop silently because `sys.displayLayer == nil`.
9. **Unsynchronized Notification Observer Removal (`VLCSampleBufferDisplay.m:1225`):**
   Removing observers without synchronizing asynchronous UI blocks can cause selectors to fire during object deallocation.

### Open Questions & Uncertainties Carried Forward
- **Closed-Source Compositor Behavior:** The exact visual tone curve, highlight rolloff, and luminance mapping computed by Apple's closed-source CoreAnimation / ColorSync / WindowServer compositor on physical XDR displays cannot be determined from static source analysis.
- **Hardware Dolby Vision Handling in VideoToolbox:** Whether VideoToolbox hardware decoding on Apple Silicon internally processes or discards Dolby Vision RPU metadata packets under the hood without exposing them to VLC remains unverified without low-level runtime tracing.
- **Missing External Handoff Note:** The external "handoff note" referenced in commit `964d210`'s commit message detailing the RPU partition field divergence point is not present in the repository or local filesystem.
- **MoltenVK / Vulkan Feasibility:** Whether a MoltenVK `VK_EXT_metal_surface` backend for `libplacebo` can be integrated without a major overhaul of VLC's macOS windowing architecture remains an open architectural question.
- **Hardware AV1 Execution:** Real-world decoding performance and fallback dynamics of `deviceSupportsAV1()` on actual M3/M4 Apple Silicon hardware have not been verified with a running binary.

## 7. How to build, run and test

### Build Commands

#### Autotools Build (Recommended for Existing Tests)
```bash
cd /Users/omarbenmustapha/Downloads/vlc-master

# Bootstrap autotools if needed
./bootstrap

# Configure with Darwin, VideoToolbox, and debug support
./configure     --enable-debug     --enable-videotoolbox     --enable-av1     --enable-dav1d     --disable-vulkan     --prefix=$(pwd)/install_dir

# Build core and modules
make -j$(sysctl -n hw.ncpu)
```

#### Meson Build (Fast Compilation)
```bash
cd /Users/omarbenmustapha/Downloads/vlc-master

# Setup build directory
meson setup build --buildtype=debugoptimized

# Compile
ninja -C build
```

### Running Automated Test Targets
```bash
# Run Autotools test suites (includes copy_neon and cvpx_hdr_metadata)
make -C test check TESTS="test_src_video_chroma_copy_neon test_src_misc_cvpx_hdr_metadata"

# Run individual standalone test binaries directly:
./test/test_src_video_chroma_copy_neon
./test/test_src_misc_cvpx_hdr_metadata

# Under Meson (Note: tests must be registered in meson.build first):
ninja -C build test
```

### Running VLC Manually
```bash
# Run CLI playback with verbose debug logging for HDR inspection
./bin/vlc-static --play-and-exit -vvv /path/to/hdr_video.mkv

# Run GUI application
./bin/vlc-static /path/to/hdr_video.mp4
```

### Required Hardware and Media for Verification
- **Hardware Required:**
  - Apple Silicon Mac powered by M1, M2, M3, or M4.
  - M3 or M4 Mac specifically required to verify VideoToolbox hardware AV1 decoding (`deviceSupportsAV1()`).
  - M1 or M2 Mac required to verify graceful hardware AV1 fallback to `dav1d`.
  - Built-in or external display supporting Apple EDR: Liquid Retina XDR (MacBook Pro 14"/16"), Apple Pro Display XDR, or external HDMI 2.1 display capable of HDR10/HLG.
- **Test Media Required:**
  - **HEVC Main 10 PQ (ST 2084):** 4K 10-bit stream with SMPTE ST 2086 and CTA-861.3 metadata.
  - **HEVC Main 10 HLG:** Broadcast stream with HLG transfer function (verify no synthetic ST 2086 metadata is attached).
  - **AV1 10-bit HDR:** Stream with AV1 bitstream metadata to test `deviceSupportsAV1()` vs `dav1d`.
  - **Dolby Vision Profile 5 & Profile 8.1:** HEVC base layer + RPU bitstreams to test `dovi-rpu-wip` parser.
  - **HDR10+ Dynamic Stream:** Stream with ITU-T T.35 SEI packets to test `pl_scale` dynamic ingestion.
  - **HEVC 12-bit / 16-bit:** Stream to verify P010 fallback vs future P016 pipeline.
  - **Subtitles over HDR:** ASS/SRT subtitles over 1000+ nit PQ content to verify BT.2408 luminance scaling.

### What CANNOT Be Verified Without a Physical HDR Display
- **EDR Headroom Scaling:** On SDR screens, `maximumExtendedDynamicRangeColorComponentValue` returns `1.0`. Extended Dynamic Range highlight expansion cannot be observed or measured without an XDR or HDR panel.
- **CoreAnimation Tone Mapping Curve:** Apple's OS compositor tone curve cannot be inspected in memory; its perceptual accuracy requires a physical HDR display and a calibrated photometer.
- **Subtitle Reference-White Attenuation:** Visual comfortable readability of subtitles over high-nit backgrounds cannot be evaluated on an SDR monitor.
- **Multi-Monitor Window Dragging:** Headroom recalculation across heterogeneous displays (dragging between internal XDR and external SDR monitor) requires physical multiple displays.

## 8. Source reports
This handoff document synthesises and supersedes findings from the following project documents:

1. **`hdr-handoff/reports/01-audit-pdf-summary.md`:**
   Summary of the original technical audit PDF (`rapporthdrvlcmacosapplesilicon.pdf`).
   > **CRITICAL WARNING:** The line numbers cited in `01-audit-pdf-summary.md` correspond to the **pre-work baseline commit `99034f9`**, NOT the current codebase. Do not use line numbers from `01-audit-pdf-summary.md` to navigate the current tree.
2. **`hdr-handoff/reports/02-git-history.md`:**
   Commit-by-commit history of the HDR engineering implementation across branch `main` (`912f9fa` through `b91aa25`), `dovi-rpu-wip` (`964d210`), and `macos-fix-teardown-use-after-free` (`09fc7f5`).
3. **`hdr-handoff/reports/03-vout-apple-layer.md`:**
   Deep architectural mapping of the macOS video output display modules (`VLCSampleBufferDisplay.m`, `caopengllayer.m`), EDR properties, subtitle handling, and CoreVideo attachments.
4. **`hdr-handoff/reports/04-decoder-chroma-opengl.md`:**
   Deep architectural mapping of VideoToolbox decoding, ARM64 NEON chroma conversions (`copy.c`), OpenGL / `libplacebo` dynamic metadata plumbing (`filters.c`, `pl_scale.c`), and build-system test wiring.
5. **`rapporthdrvlcmacosapplesilicon.pdf`:**
   The original 10-page French technical audit document located at `/Users/omarbenmustapha/Downloads/vlc-master/rapporthdrvlcmacosapplesilicon.pdf`.


---

## 9. Provenance and verification status

**How this document was produced.** Sections 1–8 were synthesised from four independent static-analysis passes (Gemini 3.8 Flash High, via the Antigravity CLI) over the source tree, the git history, and the audit PDF. Each pass was read-only; `git status` was clean before and after. The raw passes are preserved verbatim under `hdr-handoff/reports/`.

**Independently re-checked against the working tree** (claims below were confirmed by direct grep/read of the current `main`, not taken from the analysis passes):

| Claim | Evidence |
| :--- | :--- |
| `macosx-edr-headroom` is now actually read | `modules/video_output/apple/VLCSampleBufferDisplay.m:1749` (`var_InheritFloat`), declared once at `:1833` |
| `macosx-hdr-mode` is read in the render path and has callbacks | `VLCSampleBufferDisplay.m:939`, `:1364`, callbacks registered `:1761`, `:1764`, removed `:1274-1275` |
| Headroom now comes from the window's own screen | `VLCSampleBufferDisplay.m:690`, `:942` — `self.window.screen ?: [NSScreen mainScreen]` |
| NEON chroma routines exist and are dispatched without a runtime CPU check | `modules/video_chroma/copy.c:634, 675, 743, 810, 842, 875, 885, 896, 907`; dispatch note at `:1058` |
| Hardware AV1 path exists and is gated | `modules/codec/videotoolbox/decoder.c:53-55` (fourcc fallback), `:965-977`, `:1567-1574` (`VTIsHardwareDecodeSupported`) |
| HDR10+ is carried through the GL filter chain | `include/vlc_opengl_filter.h:49-50`; consumed at `modules/video_output/opengl/pl_scale.c:184-185` |
| Both new tests are registered in Autotools | `test/Makefile.am:74, 120, 314-316, 335-336` |
| Both new tests are **absent** from Meson | no `copy_neon` / `cvpx_hdr_metadata` match in `test/src/meson.build`; only `test_src_misc_image_cvpx` at `:392-393` |
| `pl_scale` auto-insertion condition excludes plain HDR10+ | `modules/video_output/opengl/vout_helper.c:120-124` — gate is `upscaler \|\| downscaler \|\| has_dovi` |
| ICC TODO still present | `modules/video_output/libplacebo/display.c:702` |
| Synthetic ST 2086 / CLL is attached to HLG streams | `modules/codec/vt_utils.c:442`, `:507` include `TRANSFER_FUNC_HLG` in the `is_hdr` test |
| Suspicious luminance rescale | `modules/codec/vt_utils.c:476-479` — `if (max_l > 0 && max_l < 10000) max_l *= 10000;` |
| Only the green primary is checked before defaulting | `modules/codec/vt_utils.c:464-465` |
| Subtitle scale factor and its clamps | `VLCSampleBufferDisplay.m:1154-1160` — `ITU_BT2408_REFERENCE_WHITE_NITS / (SDR_NOMINAL_WHITE_NITS * effectiveHeadroom)`, clamped to `[0.15, 1.0]`, and skipped for `hdr_mode` 2 and 3 |
| Branch parentage | `git merge-base main dovi-rpu-wip` = `1a2b147`; `git merge-base main macos-fix-teardown-use-after-free` = `b91aa25` |
| Version identity | `configure.ac:5` `AC_INIT([vlc], [4.0.0-dev])`, `:35` `CODENAME="Otto Chriek"`; `src/revision.c:1` `psz_vlc_changeset[] = "4.0.0-dev-arm64-hdr"` |
| `dovi-rpu-wip` is knowingly incomplete | commit `964d210` message: parser "desynchronises at the partition fields and therefore attaches nothing" |

**Correction to the source reports:** the CoreVideo colour-property helper lives at `modules/codec/vt_utils.c`, not `modules/codec/videotoolbox/vt_utils.c`. Paths in this document use the correct location.

**Not verified by execution.** Nothing in this handoff was compiled or run. No playback, no HDR display, no photometry, no Instruments trace. Every behavioural claim is static-analysis grade. The subtitle-attenuation curve, the AV1 hardware path on M3/M4, and the OS tone curve all need a physical Apple Silicon Mac with an EDR-capable display before they can be called correct.

**One note on the `964d210` commit message:** it refers to "the handoff note" describing the exact RPU divergence point. No such note exists anywhere in the repository or in the surrounding filesystem. Whoever continues the Dolby Vision work must re-derive the divergence point from the bitstream, not go looking for that document.
