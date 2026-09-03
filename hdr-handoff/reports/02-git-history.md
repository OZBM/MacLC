# VLC macOS Apple Silicon HDR Engineering Report

### 1. Commits on `main` from `912f9fa` Onward

---

#### Commit [`912f9fa`](file:///Users/omarbenmustapha/Downloads/vlc-master/): `macos: HDR fixes for Apple Silicon`
* **Commit Message**:
  > Fix the four confirmed defects on the macOS HDR path and add the two missing decoder capabilities, per the Apple Silicon HDR audit.
  >
  > VLCSampleBufferDisplay: read macosx-edr-headroom in the render path instead of ignoring it, drop its duplicate declaration, and add the missing branch for macosx-hdr-mode=2 (tone-map to SDR) using preferredDynamicRange/toneMapMode with a BT.709 retag fallback on older macOS. Take the EDR headroom from the window's own screen rather than mainScreen, and re-evaluate it on screen and window-screen changes. Render subpictures into a tagged sRGB colour space and scale them to BT.2408 reference white so subtitle white has a defined level over PQ.
  >
  > caopengllayer: forward ST 2086 and MaxCLL/MaxFALL to the OpenGL sampler, and set contentsHeadroom, preferredDynamicRange and toneMapMode with the same screen-change re-evaluation.
  >
  > videotoolbox: add a hardware AV1 path gated on VTIsHardwareDecodeSupported so M1/M2 still fall back to dav1d, and stop routing >10-bit HEVC through 32BGRA - it now falls back to P010 rather than being crushed to 8 bits per channel.
  >
  > copy: add NEON implementations of the semi-planar/planar conversions, which were vectorised only under SSE2/SSE3 and therefore ran scalar on every Apple Silicon Mac.
* **Function-by-Function Changes and Current Tree Line References**:
  * [modules/codec/videotoolbox/decoder.c](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/codec/videotoolbox/decoder.c):
    * [`kCMVideoCodecType_AV1`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/codec/videotoolbox/decoder.c#L53-L55): Defines the FourCC `'av01'` if not provided by older macOS SDK headers.
    * [`deviceSupportsAV1()`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/codec/videotoolbox/decoder.c#L1567-L1574) (declared at [L83](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/codec/videotoolbox/decoder.c#L83)): Checks `VTIsHardwareDecodeSupported(kCMVideoCodecType_AV1)` under macOS 14.0+ / iOS 17.0+ on `__aarch64__`.
    * [`GetBestChroma()`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/codec/videotoolbox/decoder.c#L154-L196): For `i_depth_luma > 10 && i_depth_chroma > 10`, prevents crushing >10-bit HEVC to 8-bit `kCVPixelFormatType_32BGRA`; instead falls back to `kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange` (P010) when supported.
    * [`CopyDecoderExtradataAV1()`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/codec/videotoolbox/decoder.c#L821-L830): Wraps `fmt_in->p_extra` into an `av1C` atom dictionary for VideoToolbox initialization.
    * [`CodecPrecheck()`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/codec/videotoolbox/decoder.c#L964-L978): Adds `case VLC_CODEC_AV1` requiring extradata and `deviceSupportsAV1()` before returning `kCMVideoCodecType_AV1`.
    * [`StartVideoToolbox()`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/codec/videotoolbox/decoder.c#L1267-L1288): Recognizes 12-bit and 16-bit planar/semi-planar chromas (`I420_12L/B`, `I420_16L/B`, `P012`, `P016`) for 10-bit/16-bit pipeline selection; differentiates forced vs chosen chroma logging.
    * [`OpenDecoder()`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/codec/videotoolbox/decoder.c#L1519-L1524): Binds `CopyDecoderExtradataAV1` for `kCMVideoCodecType_AV1`.
  * [modules/video_chroma/copy.c](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_chroma/copy.c):
    * [`NEON_CopyPlane16()`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_chroma/copy.c#L634-L673): Vectorized 16-bit plane copy with left or right bitshift using `vld1q_u16` / `vst1q_u16` and `vshlq_u16`.
    * [`NEON_SplitPlanes16()`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_chroma/copy.c#L675-L741): De-interleaves 16-bit semi-planar UV (P010) into separate U and V planes with optional bitshift using `vld2q_u16` / `vst1q_u16`.
    * [`NEON_InterleavePlanes16()`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_chroma/copy.c#L743-L808): Interleaves planar 16-bit U and V planes into semi-planar UV (P010) with optional bitshift using `vld1q_u16` / `vst2q_u16`.
    * [`NEON_SplitPlanes8()`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_chroma/copy.c#L810-L840): De-interleaves 8-bit semi-planar UV (NV12) into U and V planes using `vld2q_u8` / `vst1q_u8`.
    * [`NEON_InterleavePlanes8()`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_chroma/copy.c#L842-L873): Interleaves planar 8-bit U and V into semi-planar UV (NV12) using `vld1q_u8` / `vst2q_u8`.
    * Wrapper dispatches: [`NEON_Copy420_SP_to_P()`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_chroma/copy.c#L875-L883), [`NEON_Copy420_16_SP_to_P()`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_chroma/copy.c#L885-L894), [`NEON_Copy420_P_to_SP()`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_chroma/copy.c#L896-L905), and [`NEON_Copy420_16_P_to_SP()`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_chroma/copy.c#L907-L916).
    * Integration in [`CopyPlane()`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_chroma/copy.c#L927-L929), [`Copy420_SP_to_P()`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_chroma/copy.c#L1056-L1061), [`Copy420_16_SP_to_P()`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_chroma/copy.c#L1082-L1087), [`Copy420_P_to_SP()`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_chroma/copy.c#L1142-L1147), [`Copy420_16_P_to_SP()`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_chroma/copy.c#L1178-L1183), and self-test [`main()`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_chroma/copy.c#L1445-L1456).
  * [modules/video_output/apple/VLCSampleBufferDisplay.m](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/apple/VLCSampleBufferDisplay.m):
    * [`setupScreenObservers`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/apple/VLCSampleBufferDisplay.m#L876-L896): Subscribes to `NSApplicationDidChangeScreenParametersNotification`, `NSWindowDidChangeScreenNotification`, and `NSWindowDidChangeScreenProfileNotification`.
    * Notification handlers: [`screenParametersDidChange:`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/apple/VLCSampleBufferDisplay.m#L898-L906), [`windowDidChangeScreen:`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/apple/VLCSampleBufferDisplay.m#L908-L915), and [`windowDidChangeScreenProfile:`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/apple/VLCSampleBufferDisplay.m#L917-L924) invoke `updateDynamicRangeAndHeadroom`.
    * [`updateDynamicRangeAndHeadroom`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/apple/VLCSampleBufferDisplay.m#L926-L1172): Evaluates screen headroom from `self.window.screen ?: [NSScreen mainScreen]`, applies user headroom override (`userHeadroom`), configures `CALayer.preferredDynamicRange`, `contentsHeadroom`, and `toneMapMode` for Modes 0/1 (HDR) vs Modes 2/3 (SDR), and scales subtitle layer (`spuView`) opacity to ITU-R BT.2408 reference white (203 nits over SDR 100 nits * headroom).
    * [`EdrHeadroomCallback()`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/apple/VLCSampleBufferDisplay.m#L1245-L1258) and [`HdrModeCallback()`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/apple/VLCSampleBufferDisplay.m#L1260-L1267): Live configuration variable update callbacks.
    * [`RenderPicture()`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/apple/VLCSampleBufferDisplay.m#L1282-L1440): Handles `macosx-hdr-mode` branching (Mode 1 force HDR, Mode 2 SDR tone-map via layer or BT.709 fallback retag, Mode 3 SDR, Mode 0 auto).
    * [`UpdateSubpictureRegions()`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/apple/VLCSampleBufferDisplay.m#L1503-L1556): Uses `kCGColorSpaceSRGB` rather than `CGColorSpaceCreateDeviceRGB()`.
    * [`Open()`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/apple/VLCSampleBufferDisplay.m#L1718-L1776): Inherits `macosx-edr-headroom` and `macosx-hdr-mode` and attaches callbacks.
  * [modules/video_output/caopengllayer.m](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/caopengllayer.m):
    * [`Open()`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/caopengllayer.m#L533-L628): Extracts SMPTE ST 2086 mastering display metadata and CTA-861.3 lighting metadata from `vd->source` into `fmt`, detects HDR transfer function, and passes `is_hdr` to `[view setHDR:]`.
    * [`setHDR:`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/caopengllayer.m#L751-L755) and [`updateDynamicRangeProperties`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/caopengllayer.m#L757-L787): Queries screen headroom and invokes `[layer updateDynamicRangeWithHeadroom:headroom isHDR:_isHDR]`.
    * [`updateDynamicRangeWithHeadroom:isHDR:`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/caopengllayer.m#L988-L1018): Updates `wantsExtendedDynamicRangeContent`, `preferredDynamicRange`, `contentsHeadroom`, and `toneMapMode`.
    * Screen listeners added in [`init:`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/caopengllayer.m#L687-L720) and removed in [`vlcClose`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/caopengllayer.m#L802-L832) and [`dealloc`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/caopengllayer.m#L834-L843).

---

#### Commit [`1705a0f`](file:///Users/omarbenmustapha/Downloads/vlc-master/): `macos: log the applied HDR mode and dynamic-range state`
* **Commit Message**:
  > The four macosx-hdr-mode values were indistinguishable in a debug log, which made mode 2 in particular impossible to verify from a run. Each mode now reports the dynamic-range properties it actually applied, the effective headroom and its source, the colour properties attached to the buffers, and the subtitle reference-white factor. Headroom re-evaluations log only when the value changes.
* **Function-by-Function Changes and Current Tree Line References**:
  * [modules/video_output/apple/VLCSampleBufferDisplay.m](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/apple/VLCSampleBufferDisplay.m):
    * Class Interface & Init ([L550-L559](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/apple/VLCSampleBufferDisplay.m#L550-L559), [L794-L804](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/apple/VLCSampleBufferDisplay.m#L794-L804)): Adds logging state tracking (`effectivePdrStr`, `effectiveTmmStr`, `effectiveEdrStr`, `effectiveHeadroomVal`, `hasLoggedEffectiveConfig`, `lastSubtitleScale`, `hasComputedSubtitleScale`, and SDK warning flags).
    * [`screenParametersDidChange:`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/apple/VLCSampleBufferDisplay.m#L898-L906) & [`windowDidChangeScreen:`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/apple/VLCSampleBufferDisplay.m#L908-L915): Logs re-evaluation only when `fabs(_currentHeadroom - prevHeadroom) > 0.001f`.
    * [`updateDynamicRangeAndHeadroom`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/apple/VLCSampleBufferDisplay.m#L958-L1170): Emits `msg_Dbg` detailing applied PDR, TMM, contentsHeadroom, and EDR state for Modes 0, 1, 2, and 3; warns when macOS APIs are unsupported on older runtime versions; logs subtitle scaling factor only when changed.
    * [`RenderPicture()`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/apple/VLCSampleBufferDisplay.m#L1407-L1439): Logs initial effective display & buffer configuration (transfer function, color primaries, matrix, and layer state).

---

#### Commit [`f28fae4`](file:///Users/omarbenmustapha/Downloads/vlc-master/): `caopengllayer: request a Core Profile so the GL sampler can start`
* **Commit Message**:
  > The CGL pixel format never asked for kCGLPFAOpenGLProfile, so macOS handed back a legacy 2.1 context and libplacebo refused it: 'OpenGL version too old (2 < 3)'. The module therefore failed to initialise for every stream, HDR and SDR alike, which left VLC with no tone-mapping path at all on macOS.
  >
  > Ask for a 4.1 Core profile, falling back to 3.2 Core and then to the previous legacy behaviour, combined with the existing deep-colour request so the 64-bit EDR path is preserved. The module now reports which combination it got.
* **Function-by-Function Changes and Current Tree Line References**:
  * [modules/video_output/caopengllayer.m](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/caopengllayer.m):
    * Header compatibility macros ([L47-L63](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/caopengllayer.m#L47-L63)): Defines `kCGLOGLPVersion_GL4_1_Core` (0x4100) and `kCGLOGLPVersion_GL3_2_Core` (0x3200) when not present in the SDK.
    * [`vlc_CreateCGLContext()`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/caopengllayer.m#L212-L305): Refactored to accept `vlc_gl_t *gl`. Iterates through profiles (`kCGLOGLPVersion_GL4_1_Core`, `kCGLOGLPVersion_GL3_2_Core`, and legacy fallback) crossed with color depths (64-bit color / 16-bit alpha for EDR, then standard 24-bit / 8-bit alpha). Logs the acquired profile and bit depth via `msg_Dbg(gl, ...)`.
    * [`init:`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/caopengllayer.m#L695): Passes `gl` to `vlc_CreateCGLContext(gl)`.

---

#### Commit [`dd62400`](file:///Users/omarbenmustapha/Downloads/vlc-master/): `opengl: carry HDR10+ dynamic metadata to libplacebo`
* **Commit Message**:
  > Dolby Vision RPU already travelled through the GL filter chain, but HDR10+ did not: avcodec attached VLC_ANCILLARY_ID_HDR10PLUS to the picture and the only consumer was the standalone libplacebo vout, which sits at priority 0 and is never elected. The metadata was decoded and then dropped in every normal configuration.
  >
  > Fetch the ancillary alongside the DoVi one and pass it to vlc_placebo_HdrMetadata, reusing the existing conversion rather than duplicating it. The new vlc_gl_input_meta field is NULL whenever no HDR10+ ancillary is attached, so nothing changes for streams without it.
* **Function-by-Function Changes and Current Tree Line References**:
  * [include/vlc_opengl_filter.h](file:///Users/omarbenmustapha/Downloads/vlc-master/include/vlc_opengl_filter.h):
    * [`struct vlc_gl_input_meta`](file:///Users/omarbenmustapha/Downloads/vlc-master/include/vlc_opengl_filter.h#L44-L52): Adds field `const vlc_video_hdr_dynamic_metadata_t *hdr10plus;` ([L50](file:///Users/omarbenmustapha/Downloads/vlc-master/include/vlc_opengl_filter.h#L50)).
  * [modules/video_output/opengl/filters.c](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/opengl/filters.c):
    * [`struct vlc_gl_filters`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/opengl/filters.c#L147-L149): Adds `vlc_video_hdr_dynamic_metadata_t hdr10plus`, `int has_hdr10plus`, and `bool hdr10plus_logged` to `filters->pic`.
    * [`vlc_gl_filters_New()`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/opengl/filters.c#L184-L185): Initializes `has_hdr10plus = 0` and `hdr10plus_logged = false`.
    * [`vlc_gl_filters_UpdatePicture()`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/opengl/filters.c#L552-L563): Queries `picture_GetAncillary(picture, VLC_ANCILLARY_ID_HDR10PLUS)`, copies data into `filters->pic.hdr10plus`, and logs on first occurrence.
    * [`vlc_gl_filters_Draw()`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/opengl/filters.c#L588): Populates `.hdr10plus` on the `struct vlc_gl_input_meta` instance passed to filters.
  * [modules/video_output/opengl/pl_scale.c](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/opengl/pl_scale.c):
    * [`Draw()`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/opengl/pl_scale.c#L184-L186): When `meta->hdr10plus` is present, forwards metadata via [`vlc_placebo_HdrMetadata(meta->hdr10plus, &frame_in->color.hdr)`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/opengl/pl_scale.c#L185).

---

#### Commit [`1a2b147`](file:///Users/omarbenmustapha/Downloads/vlc-master/): `test: cover the NEON chroma conversions and CoreVideo HDR metadata`
* **Commit Message**:
  > Neither had any coverage: image_cvpx.c stops at 8-bit NV12 and nothing exercised the colour metadata round-trip at all.
  >
  > copy_neon checks the semi-planar/planar conversions against reference implementations derived from the format definitions rather than from the code under test, over widths that do and do not divide by the vector width, padded and asymmetric pitches, and both shift directions. Each plane is followed by a guard pattern, so a write past the end of a row fails the test instead of passing unnoticed. It compiles to a no-op off aarch64.
  >
  > cvpx_hdr_metadata attaches PQ and HLG colour properties with ST 2086 and CTA-861.3 metadata to a P010 buffer, reads them back and compares every field, and checks that a buffer carrying no metadata does not yield values that look real.
* **Function-by-Function Changes and Current Tree Line References**:
  * [test/src/misc/cvpx_hdr_metadata.c](file:///Users/omarbenmustapha/Downloads/vlc-master/test/src/misc/cvpx_hdr_metadata.c):
    * [`test_cvpx_hdr_pq()`](file:///Users/omarbenmustapha/Downloads/vlc-master/test/src/misc/cvpx_hdr_metadata.c#L39-L98): Allocates 10-bit P010 `CVPixelBuffer`, attaches BT.2020 PQ color volume, ST 2086 mastering metadata, and CTA-861.3 lighting metadata via [`cvpx_attach_mapped_color_properties`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/codec/vt_utils.h), reads it back via [`cvpx_extract_color_properties`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/codec/vt_utils.h), and verifies round-trip equality.
    * [`test_cvpx_hdr_hlg()`](file:///Users/omarbenmustapha/Downloads/vlc-master/test/src/misc/cvpx_hdr_metadata.c#L100-L159): Tests identical round-trip attachment and extraction for HLG transfer functions.
    * [`test_cvpx_hdr_negative()`](file:///Users/omarbenmustapha/Downloads/vlc-master/test/src/misc/cvpx_hdr_metadata.c#L161-L224): Tests clean unattached P010 buffers and standard SDR NV12 buffers, verifying that unattached properties extract as undefined / 0.
    * [`main()`](file:///Users/omarbenmustapha/Downloads/vlc-master/test/src/misc/cvpx_hdr_metadata.c#L226-L234): Executes PQ, HLG, and negative test suites.
  * [test/src/video_chroma/copy_neon.c](file:///Users/omarbenmustapha/Downloads/vlc-master/test/src/video_chroma/copy_neon.c):
    * Reference models: [`ref_Copy420_SP_to_P()`](file:///Users/omarbenmustapha/Downloads/vlc-master/test/src/video_chroma/copy_neon.c#L159-L192), [`ref_Copy420_P_to_SP()`](file:///Users/omarbenmustapha/Downloads/vlc-master/test/src/video_chroma/copy_neon.c#L194-L225), [`ref_Copy420_16_SP_to_P()`](file:///Users/omarbenmustapha/Downloads/vlc-master/test/src/video_chroma/copy_neon.c#L227-L275), and [`ref_Copy420_16_P_to_SP()`](file:///Users/omarbenmustapha/Downloads/vlc-master/test/src/video_chroma/copy_neon.c#L277-L322).
    * Test framework: Allocates buffers with guard canaries ([L75-L108](file:///Users/omarbenmustapha/Downloads/vlc-master/test/src/video_chroma/copy_neon.c#L75-L108)), tests varied image dimensions, unaligned pitches, positive/negative bitshifts, and validates memory bounds integrity in [`run_single_test()`](file:///Users/omarbenmustapha/Downloads/vlc-master/test/src/video_chroma/copy_neon.c#L392-L584) and [`main()`](file:///Users/omarbenmustapha/Downloads/vlc-master/test/src/video_chroma/copy_neon.c#L586-L677).
  * [test/Makefile.am](file:///Users/omarbenmustapha/Downloads/vlc-master/test/Makefile.am): Integrates `copy_neon` and `cvpx_hdr_metadata` test suites into the build system.

---

### 2. Branch `dovi-rpu-wip`, Commit [`964d210`](file:///Users/omarbenmustapha/Downloads/vlc-master/)

* **Commit Title & Message**:
  > `WIP: Dolby Vision RPU parsing on the VideoToolbox path`
  >
  > Incomplete - do not merge. The parser reaches the RPU and reads its header correctly, but desynchronises at the partition fields and therefore attaches nothing. See the handoff note for the exact divergence point.
* **Diff Scope**: Modifies a single file: [modules/codec/videotoolbox/decoder.c](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/codec/videotoolbox/decoder.c) (+444 lines, -3 lines relative to `main` / `1a2b147`).
* **What the RPU Parsing Does & Added Functions**:
  1. [`rpu_unescape_rbsp()`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/codec/videotoolbox/decoder.c): Removes H.264/HEVC emulation prevention 3-byte sequences (`0x00 0x00 0x03` $\to$ `0x00 0x00`) from the NAL unit payload before bitstream extraction.
  2. [`rpu_read_se_coef()`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/codec/videotoolbox/decoder.c): Helper to parse signed fixed-point or IEEE 754 32-bit floating-point coefficients depending on `coef_data_type`, scaled by `1 << coef_log2_denom`.
  3. [`ParseHEVCDoviRPU()`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/codec/videotoolbox/decoder.c):
     - Parses HEVC NAL unit type 62 (Dolby Vision RPU) with layer ID 0.
     - Checks NAL length $\ge 4$, unescapes payload to RBSP using a local 2048-byte buffer (or dynamic `malloc` if larger).
     - Validates `rpu_nal_prefix == 25` and `rpu_type == 2`.
     - Parses sequence info if `vdr_seq_info_present_flag` is set (`coef_data_type`, `coef_log2_denom`, bit depths for BL/EL/VDR, spatial flags).
     - Checks `use_prev_vdr_rpu_flag` to reuse cached state from `hevcctx->last_dovi`.
     - Otherwise parses mapping color space, chroma format, and reshape curve pivot points / coefficients (polynomial orders 1–2 or MMR orders 1–3).
     - Parses non-linear quantization (`nlq_method_idc`) if `el_bit_depth > 0`.
     - Parses extended dynamic metadata blocks (`vdr_dm_metadata_present_flag`), specifically Level 1 (`source_min_pq`, `source_max_pq`), Level 254 (`dm_version`), and Level 255 (LMS and matrix conversions).
  4. Integration in [`FillReorderInfoHEVC()`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/codec/videotoolbox/decoder.c): Pre-scans the access unit block for NAL unit type 62, invokes `ParseHEVCDoviRPU()`, and marks `p_vt_info->has_dovi = true`.
  5. Extension of frame info in [`CreateReorderInfo()`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/codec/videotoolbox/decoder.c): Allocates [`struct vt_frame_info_t`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/codec/videotoolbox/decoder.c) wrapping [`frame_info_t`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/codec/videotoolbox/decoder.c) with `has_dovi` and [`vlc_video_dovi_metadata_t`](file:///Users/omarbenmustapha/Downloads/vlc-master/include/vlc_ancillary.h#L239-L276).
  6. Propagation in [`DecoderCallback()`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/codec/videotoolbox/decoder.c): Calls `picture_AttachNewAncillary(p_pic, VLC_ANCILLARY_ID_DOVI, sizeof(*dst))` and copies the parsed `dovi` struct onto the output picture.
* **How Far It Got & What Is Unfinished or Broken**:
  - The NAL detection, frame association, and ancillary attachment plumbing are implemented.
  - The bitstream parser desynchronises immediately after reading `mapping_chroma_format_idc`. In Dolby Vision RPU bitstream syntax, partition and slice/coefficient segmentation metadata must be decoded before iterating channel pivots. Because `ParseHEVCDoviRPU()` immediately attempts to read `num_pivots_minus_2` via `bs_read_ue(&bs)`, the bitstream reader reads garbage values, encounters a bitstream error or pivot limit violation (`num_pivots > 9`), emits `"Dolby Vision RPU bitstream read error / truncated"`, and returns `false`.
  - Consequently, `has_dovi` is never set to true on valid streams, and no ancillary is attached to pictures.
* **TODO / FIXME Lines**:
  - Within commit [`964d210`](file:///Users/omarbenmustapha/Downloads/vlc-master/) itself, there are **no inline `TODO` or `FIXME` comment lines** in the diff.
  - The unfinished status and divergence location are documented in the commit message:
    > `"Incomplete - do not merge. The parser reaches the RPU and reads its header correctly, but desynchronises at the partition fields and therefore attaches nothing. See the handoff note for the exact divergence point."`
  - *(Note: In earlier commit [`912f9fa`](file:///Users/omarbenmustapha/Downloads/vlc-master/) on [modules/codec/videotoolbox/decoder.c:L183](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/codec/videotoolbox/decoder.c#L183), an unrelated TODO exists: `TODO: Add VLC_CODEC_CVPX_P016 across VLC when 16-bit CVPX pipeline support is added.`)*

---

### 3. Branch `macos-fix-teardown-use-after-free`, Commit [`09fc7f5`](file:///Users/omarbenmustapha/Downloads/vlc-master/)

* **Commit Title & Message**:
  > `macos: fix crash on quit at the end of playback`
  >
  > Quitting VLC while the "playback has truly ended" timer was armed crashed the application every time.
  >
  > Reaching the stopped state schedules a 0.5s timer to resume iTunes / Apple Music / Spotify. On interface teardown, onPlaybackHasTruelyEnded: only reset the ivar holding it. The run loop retains a scheduled timer, so clearing the ivar does not cancel it: the timer stayed armed, fired after CloseIntf had returned, and logged through an interface object that libvlc had already destroyed.
  >
  > Invalidate the timer instead of just releasing it, and clear p_interface_thread once the interface is gone so that getIntf() reports it as such rather than handing out a dangling pointer. Callers that can outlive the interface -- deferred main queue blocks of the video output provider, dialog provider deallocs, the launch handler of the play queue controller -- now check for it, as getMediaLibrary() already did.
  >
  > That teardown path also closed the video window, which reached a nil library window before the application finished launching, inserted an already zeroed weak view into an array, and refreshed the artwork button from a player being destroyed. Guard those too, otherwise the shutdown crashes again a few frames later. Note that VLCMain.sharedInstance is nil by then, so its isTerminating cannot serve as the teardown signal.
  >
  > Playing a 12s clip with --play-and-exit crashed 10 out of 10 runs before, split between the timer callback and the media library lookup of removeVoutForDisplay:. It now completes 20 out of 20 runs.
* **Summary of the Fix**:
  1. [modules/gui/macosx/playqueue/VLCPlayerController.m](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/gui/macosx/playqueue/VLCPlayerController.m): Added `cancelPlaybackHasTruelyEndedTimer` to explicitly call `[_playbackHasTruelyEndedTimer invalidate]`, preventing the retained runloop timer from firing after interface destruction. Guarded `getIntf()` calls in `onPlaybackHasTruelyEnded:`, `stopOtherAudioPlaybackApps`, and `resumeOtherAudioPlaybackApps`.
  2. [modules/gui/macosx/main/VLCMain.m](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/gui/macosx/main/VLCMain.m): In `CloseIntf`, sets `p_interface_thread = NULL` so `getIntf()` returns `NULL` rather than a dangling pointer after interface destruction.
  3. [modules/gui/macosx/windows/video/VLCVideoOutputProvider.m](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/gui/macosx/windows/video/VLCVideoOutputProvider.m): Adds `if (getIntf() == NULL) return;` guards in deferred main-queue blocks (`WindowDisable`, `WindowResize`, `WindowSetState`, `WindowSetFullscreen`), validates non-nil `libraryWindow` in `setupMainLibraryVideoWindow` falling back to detached window, and guards `videoWindow == nil` in `setupVideoOutputForVideoWindow:`.
  4. [modules/gui/macosx/library/VLCLibraryWindow.m](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/gui/macosx/library/VLCLibraryWindow.m): Prevents inserting a nil view in `displayLibraryView:`; guards `updateArtworkButtonEnabledState` and `configureArtworkButtonLiveVideoView` against destroyed player state when `getIntf() == NULL`.
  5. [modules/gui/macosx/panels/dialogs/VLCCoreDialogProvider.m](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/gui/macosx/panels/dialogs/VLCCoreDialogProvider.m), [modules/gui/macosx/windows/extensions/VLCExtensionsDialogProvider.m](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/gui/macosx/windows/extensions/VLCExtensionsDialogProvider.m), and [modules/gui/macosx/playqueue/VLCPlayQueueController.m](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/gui/macosx/playqueue/VLCPlayQueueController.m): Guards `dealloc` and launch handler callbacks against a NULL `getIntf()`.
* **Is It HDR-Related?**:
  **No**. It is strictly a Cocoa UI lifecycle and teardown concurrency / use-after-free fix.
* **Should It Be Merged Into `main`?**:
  **Yes**. It resolves a 100% reproducible application crash on termination and playback teardown (e.g. CLI playback with `--play-and-exit`). Its base commit is [`b91aa25`](file:///Users/omarbenmustapha/Downloads/vlc-master/) (the exact tip of `main`), allowing a clean, fast-forward merge with zero conflicts against HDR modifications.

---

### 4. Upstream Baseline Identification

* **Project Version**: **`4.0.0-dev`** (VLC 4.0 developmental development branch / master).
  * [configure.ac:L6-L11](file:///Users/omarbenmustapha/Downloads/vlc-master/configure.ac#L6-L11): `AC_INIT([vlc], [4.0.0-dev])`, `VERSION_MAJOR=4`, `VERSION_MINOR=0`, `VERSION_REVISION=0`, `VERSION_DEV=dev`.
  * [meson.build:L2-L4](file:///Users/omarbenmustapha/Downloads/vlc-master/meson.build#L2-L4): `project('VLC', ['c', 'cpp'], version: '4.0.0-dev')`.
* **Codename**: **`Otto Chriek`** ([configure.ac:L33](file:///Users/omarbenmustapha/Downloads/vlc-master/configure.ac#L33), [meson.build:L7](file:///Users/omarbenmustapha/Downloads/vlc-master/meson.build#L7)).
* **Library ABI Version**: **`12.0.0`** (`LIBVLC_ABI_MAJOR=12`, `LIBVLC_ABI_MINOR=0`, `LIBVLC_ABI_MICRO=0` in [configure.ac:L27-L29](file:///Users/omarbenmustapha/Downloads/vlc-master/configure.ac#L27-L29) and [meson.build:L10](file:///Users/omarbenmustapha/Downloads/vlc-master/meson.build#L10)).
* **Branch Changeset Tag**: `4.0.0-dev-arm64-hdr` (in [src/revision.c:L1](file:///Users/omarbenmustapha/Downloads/vlc-master/src/revision.c#L1)).
* **Available Upstream APIs and Architecture**:
  * Core VLC 4.0 player pipeline (`vlc_player_t` via [include/vlc_player.h](file:///Users/omarbenmustapha/Downloads/vlc-master/include/vlc_player.h)), replacing `input_thread_t`.
  * VLC 4.0 clock master architecture (audio-driven output clock).
  * Ancillary metadata framework ([include/vlc_ancillary.h](file:///Users/omarbenmustapha/Downloads/vlc-master/include/vlc_ancillary.h)) supporting `VLC_ANCILLARY_ID_DOVI` and `VLC_ANCILLARY_ID_HDR10PLUS`.
  * Modern macOS platform baseline: macOS 10.13+ minimum system target ([NEWS:L9](file:///Users/omarbenmustapha/Downloads/vlc-master/NEWS#L9)).

---

### 5. HDR Feature Status: Committed on `main` vs. Stranded on Branches

| Feature / Subsystem | Status | Location / Branch | Description |
| :--- | :--- | :--- | :--- |
| **AVSampleBufferDisplayLayer EDR Pipeline** | **Committed on `main`** | [`912f9fa`](file:///Users/omarbenmustapha/Downloads/vlc-master/), [`1705a0f`](file:///Users/omarbenmustapha/Downloads/vlc-master/) | `preferredDynamicRange`, `contentsHeadroom`, screen change notifications, dynamic headroom re-evaluations. |
| **HDR Display Modes (0, 1, 2, 3)** | **Committed on `main`** | [`912f9fa`](file:///Users/omarbenmustapha/Downloads/vlc-master/), [`1705a0f`](file:///Users/omarbenmustapha/Downloads/vlc-master/) | Auto, Force HDR, Mode 2 SDR tone-mapping via `CADynamicRangeStandard` (with BT.709 retag fallback), Disable HDR. |
| **Subtitle ITU-R BT.2408 Adaptation** | **Committed on `main`** | [`912f9fa`](file:///Users/omarbenmustapha/Downloads/vlc-master/), [`1705a0f`](file:///Users/omarbenmustapha/Downloads/vlc-master/) | Subtitle layers tagged in sRGB and luminance scaled to 203 nits relative to peak headroom. |
| **Hardware AV1 Decoding** | **Committed on `main`** | [`912f9fa`](file:///Users/omarbenmustapha/Downloads/vlc-master/) | VideoToolbox hardware decode for AV1 on Apple Silicon (M3+) gated on `deviceSupportsAV1()`. |
| **>10-Bit HEVC Chroma Path** | **Committed on `main`** | [`912f9fa`](file:///Users/omarbenmustapha/Downloads/vlc-master/) | Routes 12/16-bit HEVC to P010 (`kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange`) rather than 8-bit BGRA. |
| **ARM64 NEON Chroma Conversions** | **Committed on `main`** | [`912f9fa`](file:///Users/omarbenmustapha/Downloads/vlc-master/), [`1a2b147`](file:///Users/omarbenmustapha/Downloads/vlc-master/) | Vectorized NV12/P010 $\leftrightarrow$ I420/I420_10L SIMD routines and comprehensive unit test suite `copy_neon`. |
| **CVPixelBuffer HDR Round-trip Tests** | **Committed on `main`** | [`1a2b147`](file:///Users/omarbenmustapha/Downloads/vlc-master/) | Unit test `cvpx_hdr_metadata` covering PQ, HLG, and negative test cases. |
| **OpenGL Core Profile (4.1 / 3.2)** | **Committed on `main`** | [`f28fae4`](file:///Users/omarbenmustapha/Downloads/vlc-master/) | Enables `caopengllayer` to acquire Core profile contexts required by libplacebo. |
| **OpenGL ST 2086 / CTA-861.3 Forwarding** | **Committed on `main`** | [`912f9fa`](file:///Users/omarbenmustapha/Downloads/vlc-master/) | Forwards mastering and light level metadata from source to `caopengllayer`. |
| **OpenGL HDR10+ Dynamic Tone-Mapping** | **Committed on `main`** | [`dd62400`](file:///Users/omarbenmustapha/Downloads/vlc-master/) | Carries `VLC_ANCILLARY_ID_HDR10PLUS` through GL filter chain to `vlc_placebo_HdrMetadata`. |
| **VideoToolbox Dolby Vision RPU Parser** | **Stranded** (Broken/WIP) | [`dovi-rpu-wip`](file:///Users/omarbenmustapha/Downloads/vlc-master/) ([`964d210`](file:///Users/omarbenmustapha/Downloads/vlc-master/)) | Bitstream parser desynchronises at partition fields; no metadata attached to frames. |
| **Teardown Use-After-Free Crash Fix** | **Stranded** (Ready) | [`macos-fix-teardown-use-after-free`](file:///Users/omarbenmustapha/Downloads/vlc-master/) ([`09fc7f5`](file:///Users/omarbenmustapha/Downloads/vlc-master/)) | Non-HDR UI stability fix resolving quit/teardown crashes; ready for merge onto `main`. |

UNCERTAIN: The external "handoff note" detailing the partition field divergence point referenced in commit 964d210's commit message is not present in the git repository or local filesystem.

