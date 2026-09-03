# Technical Audit Report: HDR in VLC 4.0-dev on macOS / Apple Silicon

## Document Metadata & Extraction Tools
- **Document Title:** AUDIT TECHNIQUE — PÉRIMÈTRE MACOS / APPLE SILICON : HDR dans VLC 4.0-dev sur Mac à puce M1, M2, M3, M4
- **Analyzed Source Tree:** `vlc-master` (version `4.0.0-dev`)
- **Target Architecture & OS:** macOS · arm64 · Apple Silicon (M1, M2, M3, M4)
- **Report Date:** September 2, 2026
- **Extraction Tools Tried:**
  1. `view_file` (Direct viewer tool): Succeeded; retrieved high-resolution page renderings and OCR text for all 10 pages.
  2. `pdftotext`: Attempted via shell; failed (`zsh:1: command not found: pdftotext`, exit code 127).
  3. `python3` with `pypdf`: Succeeded; extracted complete textual content across all 10 pages without error.

---

## 1. Structure of the Report (Section Titles)

The document spans 10 pages and is organized into the following sections and sidebars:

- **Header / Cover Page (Page 1):** Audit scope, target architecture, methodology, date, and analyzed branch.
- **01 Synthèse (Page 2):** Executive summary, key numerical metrics, platform maturity by stage, and structural architectural takeaways.
  - *Callout:* **Le point structurant, propre au Mac** (The structuring point specific to Mac).
- **02 La chaîne macOS, de bout en bout (Page 3):** End-to-end pipeline diagram (decoding, buffering, VLC output selection, and system display composition).
  - *Callout:* **Quand samplebufferdisplay laisse la main** (When `samplebufferdisplay` yields control).
- **03 Décodage HDR sur Apple Silicon (Pages 4–5):**
  - **3.1 — Ce que la puce décode, et ce qu'elle ne décode pas** (Hardware vs. software decoding capabilities on Apple Silicon).
  - **3.2 — Étiquetage colorimétrique : la partie solide** (CoreVideo colorimetric tagging and metadata round-tripping).
  - **3.3 — Métadonnées dynamiques : un seul chemin, logiciel** (Dynamic metadata paths: HDR10+ and Dolby Vision).
  - *Callout:* **L'impasse pratique** (The practical impasse).
- **04 Affichage et EDR (Pages 6–7):**
  - **4.1 — Ce que le calque déclare, selon la version de macOS** (CoreAnimation EDR layer properties across macOS versions).
  - **4.2 — Qui fait le tone mapping** (Who performs tone mapping).
  - **4.3 — Les deux autres sorties** (`caopengllayer`, `macosx` legacy, and `libplacebo` vout modules).
  - **4.4 — Sous-titres sur image HDR** (Subtitle rendering architecture on HDR video).
- **05 Ce qu'il reste à faire (Pages 8–9):**
  - **5.1 — Défauts confirmés** (Confirmed bugs and design flaws #1 to #6).
  - **5.2 — Fonctionnalités absentes** (Missing features across decoding, rendering, and testing).
  - **5.3 — Réglages exposés à l'utilisateur** (Comparison of GUI settings vs. actual runtime effects).
- **06 Méthode et fiabilité (Pages 9–10):** Audit methodology, AI agents used, manual source cross-checks.
  - *Callout:* **Ce que cet audit ne prouve pas** (What this audit does not prove / limits of static analysis).

---

## 2. Technical Problem Statement: What Does Not Work with HDR in VLC on macOS / Apple Silicon

On macOS / Apple Silicon, VLC 4.0 adopts an architecture fundamentally different from other platforms: **it performs 0% of tone mapping itself**. Instead, it delegates all dynamic range compression to Apple's operating system compositor (`CoreAnimation`, `ColorSync`, and `WindowServer`). While tagging static HDR10 metadata is solid, the implementation suffers from major structural issues:

1. **Loss of Tone Mapping Control & Inaccessible `libplacebo`:**
   - Because `samplebufferdisplay` (priority 600) systematically wins the vout election, VLC passes raw frames as-is to `AVSampleBufferDisplayLayer`.
   - VLC has no control over the applied tone curve.
   - VLC's reference tone mapping engine (`libplacebo`) is compiled into macOS contribs but is practically unreachable: its vout module has priority 0, and its Vulkan backend (`placebo_vk`) cannot start due to the total absence of a Darwin "vulkan platform" module.
2. **Missing Hardware AV1 Decoding on M3 / M4:**
   - Apple M3 and M4 chips feature a hardware AV1 decoder in VideoToolbox. VLC lacks support for `kCMVideoCodecType_AV1`, forcing all 10-bit AV1 streams to decode in software via `dav1d` (CPU load, battery drain, and thermal throttling).
3. **Arbitrary 12-bit Video Degradation:**
   - Any video exceeding 10 bits (such as HEVC 12-bit) is forced into 8-bit per channel (`kCVPixelFormatType_32BGRA`), completely crushing HDR. This was an old workaround for Apple OpenGL texture limitations, which is obsolete on the modern `samplebufferdisplay` path.
4. **Dynamic Metadata (Dolby Vision RPU & HDR10+) is a Dead End:**
   - VideoToolbox hardware decoding only parses timing SEI (`ParseHEVCSEI`) and completely ignores Dolby Vision NAL RPUs, falling back to basic HEVC HDR10.
   - Dynamic metadata (`AV_FRAME_DATA_DYNAMIC_HDR_PLUS`, `AV_FRAME_DATA_DOVI_METADATA`) is only parsed by software `avcodec`, and only consumed by `libplacebo`, which is never elected as the output module. Under default settings, dynamic HDR cannot function.
5. **Unmanaged Subtitles (Eye-Straining Luminance):**
   - Subtitles are rendered via `spuView` into an untagged, device-dependent 8-bit color space (`CGColorSpaceCreateDeviceRGB()`).
   - No target reference white is defined, and no luminance attenuation is applied based on current display EDR headroom. Subtitles can render with blinding brightness on high-nit PQ content.
6. **Incorrect and Static EDR Headroom Handling:**
   - EDR headroom is queried only once upon layer creation from `[NSScreen mainScreen]` (the screen containing the menu bar, rather than the screen hosting the playback window).
   - Headroom is never dynamically re-evaluated when moving the window across HDR/SDR monitors or changing display brightness (`NSApplicationDidChangeScreenParametersNotification` is ignored).
7. **Cosmetic / Non-Functional User Settings:**
   - Two out of three HDR controls in Simple Preferences have no real effect.
   - `macosx-hdr-mode = 2` ("Tone-map to SDR") has no branch in code and silently acts as "Auto".
   - `macosx-edr-headroom` slider is saved in GUI settings but never queried (`var_Inherit*` is absent) by rendering code.
8. **Lack of ARM64 NEON Vectorization:**
   - Color conversion routines (`CVPX_P010` ↔ planar) fall back to scalar C code because vectorized implementations exist only for x86 SSE2/SSE3.
9. **Zero Automated Testing:**
   - Automated test coverage for the Apple HDR pipeline is completely absent (0%).

---

## 3. Implemented and Proposed Solutions: APIs, Code Paths, Files, and Functions

### Decoding & Demuxing Pipeline
- **VideoToolbox Hardware Decoder Filter:**
  - File: `modules/codec/videotoolbox/decoder.c:917–994`
  - Function: `CodecPrecheck()` restricts VideoToolbox hardware decoding strictly to: H.264, HEVC, MPEG-4 Part 2, H.263, ProRes, and DV. All other codecs return `-1` and fall back to software.
  - File: `modules/codec/videotoolbox/decoder.c:165–170`
  - Function: `GetBestChroma()` forces `kCVPixelFormatType_32BGRA` (8 bits per channel) for any format beyond 10-bit.
  - File: `modules/codec/videotoolbox/decoder.c:611–621`
  - Function: `ParseHEVCSEI()` only processes timing SEI; ignores Dolby Vision NAL RPUs.
- **Static Colorimetric Tagging (The Solid Part):**
  - File: `modules/codec/videotoolbox/decoder.c:998–1074`
  - Before decoding, the decompression session attaches full colorimetry: YCbCr matrix, color primaries, transfer functions, and binary attachments:
    - `mdcv` (SMPTE ST 2086 mastering display volume, 24 bytes big-endian).
    - `clli` (CTA-861.3 content light level: MaxCLL / MaxFALL, 4 bytes).
  - File: `modules/codec/videotoolbox/vt_utils.c:558–646`
  - Function: `cvpx_extract_color_properties()` reads attachments from the decoded `CVPixelBuffer` and injects them symmetrically into VLC's `video_format_t`.
  - Nominal output format: `420YpCbCr10BiPlanarVideoRange` → `VLC_CODEC_CVPX_P010`.
- **Software Decoders:**
  - `dav1d` (priority 10000): Software AV1 10-bit with NEON. File: `modules/codec/dav1d.c:229–259`, function `ExtractCaptions()` filters ITU-T T.35 solely on signature `GA94` (no HDR10+).
  - `avcodec`: VP9 Profile 2 fallback. File: `modules/codec/avcodec/video.c:1332–1353` converts `AV_FRAME_DATA_DYNAMIC_HDR_PLUS` and `AV_FRAME_DATA_DOVI_METADATA` into ancillary metadata.

### Video Output (vout) & Presentation Pipeline
- **Primary Vout: `samplebufferdisplay` (Priority 600):**
  - File: `modules/video_output/apple/VLCSampleBufferDisplay.m`
  - Fallback check: `Open()` (`:1291–1298`) checks `--force-darwin-legacy-display` and non-rectangular projection (360° video). If detected, it yields to `caopengllayer`.
  - Render function: `RenderPicture()` (`:1012–1061`) attaches color properties, wraps the pixel buffer into a `CMVideoFormatDescription`, and invokes `[AVSampleBufferDisplayLayer enqueueSampleBuffer:]`. No shaders, no LUTs, no custom tone curves.
  - CoreAnimation & Window Properties configured:
    - `wantsExtendedDynamicRangeContent = YES` on layer, view, and window (`:621, 656, 809`).
    - `window.colorSpace = [NSColorSpace extendedSRGBColorSpace]` (`:657, 825`).
    - `preferredDynamicRange = CADynamicRangeHigh` (macOS 14+, `:628, 815`).
    - `contentsHeadroom = [[NSScreen mainScreen] maximumExtendedDynamicRangeColorComponentValue]` (macOS 14+, `:629–632, 816–819`).
    - `toneMapMode = CAToneMapModeIfSupported` (macOS 15+, `:637, 822`).
- **Subtitles (`spuView`):**
  - File: `modules/video_output/apple/VLCSampleBufferDisplay.m:1331–1336` declares `subpicture_chromas = { VLC_CODEC_ARGB }`.
  - Subtitles render in a separate overlay view `spuView` created with `CGColorSpaceCreateDeviceRGB()` (`:1088`).
- **Secondary Vouts:**
  - `caopengllayer` (priority 300): File `caopengllayer.m:199–232, 786–794`. Requests 64-bit CGL context (16-bit float per channel, alpha 16, 24-bit fallback), layer in `kCGColorSpaceExtendedLinearDisplayP3` and `wantsExtendedDynamicRangeContent`. Tone maps via OpenGL sampler (`libplacebo` GL if `HAVE_LIBPLACEBO_GL`). Lacks ST 2086, MaxCLL, `contentsHeadroom`, and `toneMapMode`.
  - `macosx` (priority 290): Deprecated `NSOpenGLView`. Calls `setWantsExtendedDynamicRangeOpenGLSurface:`.
  - `vout libplacebo` (priority 0): Vulkan backend `placebo_vk` lacks Darwin platform support (`VK_EXT_metal_surface` / `CAMetalLayer` missing). File `modules/video_output/libplacebo/display.c:702` contains `// TODO: support for ICC profiles`.
- **Chroma & ISA Conversions:**
  - File: `modules/video_chroma/cvpx.c:153, 167` calls `Copy420_16_SP_to_P` and `Copy420_16_P_to_SP` in `modules/video_chroma/copy.c`.
  - File: `configure.ac:1968–1969` restricts `modules/isa/arm/` to 32-bit ARM. `modules/isa/aarch64/` only contains deinterlacing routines.

---

## 4. Remaining Work, Limitations, Known Bugs, and Next Steps

The audit catalogs 6 confirmed defects and 9 missing features:

### Confirmed Defects (Section 5.1)
1. **Unread Headroom Option (`macosx-edr-headroom`):** Declared twice and exposed in GUI (`VLCSampleBufferDisplay.m:1386`, `VLCSimplePrefsController.m:876, 1206`), but never read via `var_Inherit*`. User slider is non-functional.
2. **Missing SDR Mode (`macosx-hdr-mode = 2`):** Menu offers "Tone-map to SDR", but `VLCSampleBufferDisplay.m:999–1010` contains no branch for value 2. It traverses without effect and behaves as "Auto".
3. **Static Headroom on Wrong Screen:** Headroom is evaluated once using `[NSScreen mainScreen]` instead of the active window screen (`VLCSampleBufferDisplay.m:629–632, 816–819`). Moving between SDR/HDR screens or altering display brightness leaves `contentsHeadroom` stale.
4. **Untagged Subtitle Colorimetry:** Subtitles use untagged 8-bit `CGColorSpaceCreateDeviceRGB()` (`:1088`) with zero luminance scaling against PQ backgrounds.
5. **Obsolete 12-bit Downsampling:** Video over 10-bit is clamped to 8-bit `32BGRA` (`videotoolbox/decoder.c:165–170`) based on outdated OpenGL constraints.
6. **Absence of ARM64 NEON SIMD:** 10-bit planar ↔ bi-planar conversions run in scalar C on Apple Silicon (`video_chroma/copy.c`).

### Missing Features (Section 5.2)
1. **Hardware AV1 Decoding:** No support for `kCMVideoCodecType_AV1` in VideoToolbox to leverage M3/M4 hardware engines.
2. **Hardware Dolby Vision RPU Extraction:** No parsing of Dolby Vision NAL RPUs in VideoToolbox.
3. **End-to-End Dynamic HDR Pipeline:** No default mechanism to bridge `avcodec` dynamic metadata to a displayable output layer.
4. **Darwin Vulkan Platform Module:** Missing `VK_EXT_metal_surface` / `CAMetalLayer` platform module for Darwin in `libplacebo`.
5. **Usable Priority / Access for `vout libplacebo`:** Priority is locked at 0; no GUI or auto-selection mechanism to access its 9 tone mapping algorithms.
6. **HDR Metadata in `caopengllayer`:** Missing ST 2086, MaxCLL/MaxFALL, `contentsHeadroom`, and `toneMapMode`.
7. **Dynamic EDR Re-evaluation:** Missing observer on `NSApplicationDidChangeScreenParametersNotification` and window frame changes.
8. **ICC Profiles:** Unimplemented `// TODO: support for ICC profiles` in `libplacebo/display.c:702`.
9. **Automated Test Coverage:** Complete lack of test suites for the Apple HDR pipeline (`VLCSampleBufferDisplay.m` has 0 tests; `image_cvpx.c` is limited to NV12 8-bit; `dpb_test.c` only tests frame ordering).

### Settings Reality in GUI (Section 5.3)
- `macosx-hdr-mode = 0` (Auto): **Active** (passes stream colorimetry through).
- `macosx-hdr-mode = 1` (Forcer EDR): **Active** (forces PQ/HLG and BT.2020).
- `macosx-hdr-mode = 2` (Tone-map SDR): **Inactive / No effect** (missing code branch).
- `macosx-hdr-mode = 3` (Désactiver HDR): **Active** (forces BT.709).
- `macosx-edr-headroom`: **Inactive / No effect** (never read by rendering backend).
- `Label d'état HDR`: **Informational** (queries main screen peak EDR or checks if macOS < 10.15).

---

## 5. Test Procedures, Sample Media, and Hardware Setup

- **Hardware Scope Described:**
  - Mac computers powered by Apple Silicon: **M1, M2, M3, and M4** processors.
  - Display hardware referenced: Built-in and external Apple XDR panels (Liquid Retina XDR, Pro Display XDR) supporting EDR (Extended Dynamic Range).
- **Target Operating System Versions:**
  - macOS 13 (Ventura): Basic EDR flag supported.
  - macOS 14 (Sonoma): Introduction of `preferredDynamicRange` and `contentsHeadroom`.
  - macOS 15+ (Sequoia): Introduction of `toneMapMode`.
  - macOS < 10.15 (Catalina legacy check in GUI).
- **Sample Media Types Evaluated in Code Paths:**
  - HEVC Main 10 PQ
  - HEVC Main 10 HLG
  - AV1 10-bit
  - VP9 Profile 2
  - Dolby Vision (HEVC base layer + RPU)
  - HEVC 12-bit
  - 360° non-rectangular projection video
- **Audit Methodology & Verification:**
  - Methodology: Static code analysis conducted on September 2, 2026.
  - 3 parallel static audit passes performed by Gemini 3.7 Flash (High) agents across:
    1. VideoToolbox decoding & software fallbacks.
    2. Apple output modules, EDR, and libplacebo integration.
    3. Build system, ARM64 contribs, GUI controllers, and tests.
  - 14 manual cross-verifications executed directly against the source tree (module priorities, AV1 codec constants, Vulkan platform providers, GUI variables, subtitle color spaces, Darwin contrib flags, 64-bit OpenGL context settings, and fallback branches).
- **Explicit Limits (What Was NOT Tested):**
  - The audit explicitly notes that **no dynamic runtime execution**, **no live playback on XDR displays**, and **no physical luminance / photometer measurements** were performed.
  - Windows (Direct3D 11), Android, Linux, and HDR video encoding were explicitly excluded from scope.

---

## 6. Key Numbers and Technical Specifications

### Luminance, Color Primaries & Transfer Functions
- **Transfer Functions:**
  - `PQ` (SMPTE ST 2084 / Perceptual Quantizer).
  - `HLG` (`ITU_R_2100_HLG`).
- **Color Primaries & Matrices:**
  - `BT.2020`
  - `BT.709`
  - `extendedSRGBColorSpace`
  - `kCGColorSpaceExtendedLinearDisplayP3`
- **Metadata Payloads:**
  - `24 bytes` (big-endian): `mdcv` binary structure for SMPTE ST 2086 mastering display color volume.
  - `4 bytes`: `clli` binary structure for CTA-861.3 content light levels (MaxCLL and MaxFALL).

### Bit Depths and Color Formats
- **10-bit:** Nominal pipeline (`420YpCbCr10BiPlanarVideoRange` / `VLC_CODEC_CVPX_P010`, `Copy420_16_SP_to_P`, `dav1d 10 bits`).
- **12-bit:** Clamped down to 8-bit `32BGRA` (`kCVPixelFormatType_32BGRA`).
- **8-bit:** Subtitle overlay (`CGColorSpaceCreateDeviceRGB()`), fallback chroma, and NV12 test coverage.
- **64-bit:** Color context in `caopengllayer` (16 bits per channel floating point, 16-bit alpha), with a 24-bit color fallback.

### Module Priorities
- `10000`: `dav1d` software decoder.
- `800`: `videotoolbox` hardware decoder.
- `600`: `samplebufferdisplay` output module (default winner).
- `300`: `caopengllayer` output module (360° / legacy fallback).
- `290`: `macosx` legacy `NSOpenGLView` output module.
- `0`: `vout libplacebo` (never elected automatically).

### Platform & Architecture Metrics
- **0%:** Proportion of tone mapping computed by VLC on Apple Silicon.
- **2 / 3:** Proportion of user-facing HDR settings in Simple Preferences that are non-functional in code.
- **0:** Automated test cases covering the macOS Apple Silicon HDR pipeline.
- **9:** Number of tone mapping curves provided by `libplacebo` that remain inaccessible in default configurations.
- **4 Chip Generations:** Apple M1, M2, M3, and M4 (with hardware AV1 decoding available on M3 and M4 but unused by VLC).
- **3 macOS Versions Analyzed:** macOS 13, macOS 14, macOS 15+.

---

UNCERTAIN: The exact visual tone curve, clipping behavior, and perceived luminance output generated by macOS CoreAnimation/ColorSync/WindowServer on physical XDR displays (cannot be determined from static source code); whether VideoToolbox internally decodes or applies Dolby Vision RPU metadata under the hood without exposing it to VLC; and whether MoltenVK or future libplacebo Darwin backends could be integrated without rewriting VLC's macOS windowing layer.

