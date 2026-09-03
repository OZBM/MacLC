# Comprehensive Analysis of VLC HDR Plumbing Outside the Apple Vout Display Layer

## 1. VideoToolbox Decoder HDR Metadata Handling

### Core VLC Structs Involved
- [`decoder_t`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/codec/videotoolbox/decoder.c#L68): Root decoder structure holding `p_dec->fmt_in`, `p_dec->fmt_out`, and private state `p_dec->p_sys` ([`decoder_sys_t`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/codec/videotoolbox/decoder.c#L107)).
- [`es_format_t`](file:///Users/omarbenmustapha/Downloads/vlc-master/include/vlc_es.h#L529): Encapsulates stream format info for input and output.
- [`video_format_t`](file:///Users/omarbenmustapha/Downloads/vlc-master/include/vlc_es.h#L320): Carries colorimetry, transfer functions, and HDR mastering/lighting data:
  - `video_color_primaries_t primaries`
  - `video_transfer_func_t transfer`
  - `video_color_space_t space`
  - `video_color_range_t color_range`
  - `video_chroma_location_t chroma_location`
  - `struct { uint16_t primaries[6]; uint16_t white_point[2]; uint32_t max_luminance; uint32_t min_luminance; } mastering`
  - `struct { uint16_t MaxCLL; uint16_t MaxFALL; } lighting`
  - `struct { ... } dovi`
- [`picture_t`](file:///Users/omarbenmustapha/Downloads/vlc-master/include/vlc_picture.h#L182): Per-frame decoded picture structure receiving color properties and holding the attached `CVPixelBufferRef`.
- `CFMutableDictionaryRef` / `CFDictionaryRef`: CoreFoundation dictionaries configuring Decompression Session format extensions (`decoderConfiguration`) and pixel buffer pool attributes (`destinationPixelBufferAttributes`).

---

### Step-by-Step Metadata Extraction and Propagation

#### A. Initial ES Configuration and SPS/VUI Parsing
1. **Initial Format Copy:**
   In [`OpenDecoder()`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/codec/videotoolbox/decoder.c#L1460-L1466):
   - [`modules/codec/videotoolbox/decoder.c:1460`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/codec/videotoolbox/decoder.c#L1460):
     `p_dec->fmt_out.video = p_dec->fmt_in->video;` initializes `fmt_out.video` with all demuxer/container-provided colorimetry, mastering display, content light level, and Dolby Vision container descriptors.
2. **Codec Parameter Set Colorimetry Parsing:**
   In [`ConfigureVoutH264()`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/codec/videotoolbox/decoder.c#L466-L489) (aliased as `ConfigureVoutHEVC` at [`decoder.c:807`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/codec/videotoolbox/decoder.c#L807)):
   - [`modules/codec/videotoolbox/decoder.c:476-487`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/codec/videotoolbox/decoder.c#L476-L487):
     If `p_dec->fmt_in->video.primaries == COLOR_PRIMARIES_UNDEF`, extracts VUI colorimetry from SPS NALUs via [`hxxx_helper_get_colorimetry()`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/codec/hxxx_helper.h#L112) into `primaries`, `transfer`, `colorspace`, and `full_range`, populating `p_dec->fmt_out.video`.

#### B. VideoToolbox Decompression Session Setup
1. **10-bit P010 Chroma Selection:**
   In [`StartVideoToolbox()`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/codec/videotoolbox/decoder.c#L1258-L1275):
   - [`modules/codec/videotoolbox/decoder.c:1258-1275`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/codec/videotoolbox/decoder.c#L1258-L1275):
     If input video is HDR (`transfer == TRANSFER_FUNC_SMPTE_ST2084`, `TRANSFER_FUNC_HLG`, `primaries == COLOR_PRIMARIES_BT2020`, 10/12/16-bit chroma formats, or HEVC Main 10 profile 2) and `p_sys->i_cvpx_format == 0`, selects `p_sys->i_cvpx_format = kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange`.
2. **Attaching Color Properties to the Session Format Description:**
   In [`CreateSessionDescriptionFormat()`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/codec/videotoolbox/decoder.c#L1130-L1199):
   - [`modules/codec/videotoolbox/decoder.c:1174`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/codec/videotoolbox/decoder.c#L1174): Calls [`video_format_AdjustColorSpace(&p_dec->fmt_out.video)`](file:///Users/omarbenmustapha/Downloads/vlc-master/include/vlc_es.h#L419).
   - [`modules/codec/videotoolbox/decoder.c:1176`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/codec/videotoolbox/decoder.c#L1176): Calls [`SetDecoderColorProperties(decoderConfiguration, &p_dec->fmt_out.video)`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/codec/videotoolbox/decoder.c#L1047).
3. **CoreVideo Attachment Mapping:**
   In [`SetDecoderColorProperties()`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/codec/videotoolbox/decoder.c#L1047-L1128):
   - **Matrix:** [`decoder.c:1056-1064`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/codec/videotoolbox/decoder.c#L1056-L1064) calls [`cvpx_map_YCbCrMatrix_from_vcs(video_fmt->space)`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/codec/vt_utils.c#L309) -> `kCVImageBufferYCbCrMatrixKey`.
   - **Primaries:** [`decoder.c:1066-1074`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/codec/videotoolbox/decoder.c#L1066-L1074) calls [`cvpx_map_ColorPrimaries_from_vcp(video_fmt->primaries)`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/codec/vt_utils.c#L343) -> `kCVImageBufferColorPrimariesKey`.
   - **Transfer Function:** [`decoder.c:1076-1084`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/codec/videotoolbox/decoder.c#L1076-L1084) calls [`cvpx_map_TransferFunction_from_vtf(video_fmt->transfer)`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/codec/vt_utils.c#L366) -> `kCVImageBufferTransferFunctionKey`.
   - **Mastering Display Color Volume (SMPTE ST 2086):** [`decoder.c:1102-1110`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/codec/videotoolbox/decoder.c#L1102-L1110) calls [`cvpx_create_mastering_display_color_volume_data(video_fmt)`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/codec/vt_utils.c#L484) -> `kCVImageBufferMasteringDisplayColorVolumeKey`. Serializes a 24-byte big-endian payload containing display primaries (G, B, R in $0.00002$ units), white point (D65 in $0.00002$ units), max luminance, and min luminance in $0.0001\text{ nit}$ units.
   - **Content Light Level (CTA-861.3):** [`decoder.c:1113-1121`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/codec/videotoolbox/decoder.c#L1113-L1121) calls [`cvpx_create_content_light_level_data(video_fmt)`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/codec/vt_utils.c#L519) -> `kCVImageBufferContentLightLevelInfoKey`. Serializes a 4-byte packed big-endian payload containing `max_cll` and `max_fall`.

#### C. Extraction from Decoded `CVPixelBufferRef`
1. **Frame Arrival in Decompression Callback:**
   In [`DecoderCallback()`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/codec/videotoolbox/decoder.c#L2214-L2319):
   - [`modules/codec/videotoolbox/decoder.c:2256-2260`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/codec/videotoolbox/decoder.c#L2256-L2260): On the first decoded buffer (or format update), calls [`UpdateVideoFormat(p_dec, imageBuffer)`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/codec/videotoolbox/decoder.c#L2124).
2. **Extraction Routine:**
   In [`UpdateVideoFormat()`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/codec/videotoolbox/decoder.c#L2124-L2201):
   - [`modules/codec/videotoolbox/decoder.c:2128-2161`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/codec/videotoolbox/decoder.c#L2128-L2161): Extracts `kCVImageBufferChromaLocationTopFieldKey` and `BottomFieldKey` into `p_dec->fmt_out.video.chroma_location`.
   - [`modules/codec/videotoolbox/decoder.c:2163-2193`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/codec/videotoolbox/decoder.c#L2163-L2193): Maps pixel format `kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange` to `p_dec->fmt_out.i_codec = VLC_CODEC_CVPX_P010`.
   - [`modules/codec/videotoolbox/decoder.c:2195`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/codec/videotoolbox/decoder.c#L2195): Calls [`cvpx_extract_color_properties(imageBuffer, &p_dec->fmt_out.video)`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/codec/vt_utils.c#L558).
3. **CoreVideo Attachment Deserialization:**
   In [`cvpx_extract_color_properties()`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/codec/vt_utils.c#L558-L644):
   - Calls `CVBufferGetAttachments(cvpx, kCVAttachmentMode_ShouldPropagate)`.
   - `kCVImageBufferYCbCrMatrixKey` -> `fmt->space` (`COLOR_SPACE_BT709`, `COLOR_SPACE_BT601`, `COLOR_SPACE_BT2020`) ([`vt_utils.c:567-577`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/codec/vt_utils.c#L567-L577)).
   - `kCVImageBufferColorPrimariesKey` -> `fmt->primaries` (`COLOR_PRIMARIES_BT709`, `COLOR_PRIMARIES_BT2020`, `COLOR_PRIMARIES_DCI_P3`, etc.) ([`vt_utils.c:579-593`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/codec/vt_utils.c#L579-L593)).
   - `kCVImageBufferTransferFunctionKey` -> `fmt->transfer` (`TRANSFER_FUNC_BT709`, `TRANSFER_FUNC_SMPTE_ST2084`, `TRANSFER_FUNC_HLG`, `TRANSFER_FUNC_LINEAR`, `TRANSFER_FUNC_SRGB`) ([`vt_utils.c:595-613`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/codec/vt_utils.c#L595-L613)).
   - `kCVImageBufferMasteringDisplayColorVolumeKey` -> parses 24 bytes using `ntohs()` and `ntohl()` into `fmt->mastering.primaries[0..5]`, `fmt->mastering.white_point[0..1]`, `fmt->mastering.max_luminance`, `fmt->mastering.min_luminance` ([`vt_utils.c:619-634`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/codec/vt_utils.c#L619-L634)).
   - `kCVImageBufferContentLightLevelInfoKey` -> parses 4 bytes using `ntohs()` into `fmt->lighting.MaxCLL` and `fmt->lighting.MaxFALL` ([`vt_utils.c:636-642`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/codec/vt_utils.c#L636-L642)).

#### D. Per-Picture Metadata Propagation
In [`DecoderCallback()`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/codec/videotoolbox/decoder.c#L2289-L2305):
- [`modules/codec/videotoolbox/decoder.c:2289-2295`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/codec/videotoolbox/decoder.c#L2289-L2295): Copies all color and HDR properties from `p_dec->fmt_out.video` directly into each newly allocated picture:
  ```c
  p_pic->format.mastering = p_dec->fmt_out.video.mastering;
  p_pic->format.lighting = p_dec->fmt_out.video.lighting;
  p_pic->format.primaries = p_dec->fmt_out.video.primaries;
  p_pic->format.transfer = p_dec->fmt_out.video.transfer;
  p_pic->format.space = p_dec->fmt_out.video.space;
  p_pic->format.color_range = p_dec->fmt_out.video.color_range;
  ```
- [`modules/codec/videotoolbox/decoder.c:2297`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/codec/videotoolbox/decoder.c#L2297): Attaches the underlying CVPixelBuffer to the picture via [`cvpxpic_attach(p_pic, imageBuffer, p_sys->vctx, video_context_OnPicReleased)`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/codec/vt_utils.c#L223).

#### E. Dolby Vision and HDR10+ Dynamic Metadata in VideoToolbox
- **Dolby Vision RPU:** Not extracted. VideoToolbox decoder does not parse NAL units for Dolby Vision RPU metadata, does not read Dolby Vision attachments from CVPixelBuffers, and never attaches `VLC_ANCILLARY_ID_DOVI` to the decoded `picture_t`.
- **HDR10+ Dynamic Metadata:** Not extracted. VideoToolbox decoder ignores ITU-T T.35 SEI NAL units carrying HDR10+ metadata and never attaches `VLC_ANCILLARY_ID_HDR10PLUS` to `picture_t`.

---

## 2. Chroma Conversion Routines in `modules/video_chroma/copy.c`

### New Conversion Routines Added
All new routines are static ARM64 NEON vector implementations added under `#if defined(__aarch64__)`:
1. [`NEON_CopyPlane16`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_chroma/copy.c#L634-L671) ([`modules/video_chroma/copy.c:634`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_chroma/copy.c#L634)):
   16-bit single-plane copy supporting arbitrary bitshifts using `vld1q_u16`, `vshlq_u16` with `vdupq_n_s16(-bitshift)`, and `vst1q_u16` (8 pixels per vector).
2. [`NEON_SplitPlanes16`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_chroma/copy.c#L673-L741) ([`modules/video_chroma/copy.c:673`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_chroma/copy.c#L673)):
   De-interleaves 16-bit semi-planar UV (e.g. P010) into planar U and V planes (e.g. I420_10L) with bitshifting using `vld2q_u16`, `vshlq_u16`, and `vst1q_u16`.
3. [`NEON_InterleavePlanes16`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_chroma/copy.c#L743-L815) ([`modules/video_chroma/copy.c:743`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_chroma/copy.c#L743)):
   Interleaves separate planar 16-bit U and V planes into semi-planar interleaved UV pairs with bitshifting using `vld1q_u16`, `vshlq_u16`, and `vst2q_u16`.
4. [`NEON_SplitPlanes8`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_chroma/copy.c#L817-L844) ([`modules/video_chroma/copy.c:817`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_chroma/copy.c#L817)):
   De-interleaves 8-bit semi-planar UV (NV12) into planar U and V (I420) using `vld2q_u8` and `vst1q_u8` (16 pixels per chunk).
5. [`NEON_InterleavePlanes8`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_chroma/copy.c#L846-L873) ([`modules/video_chroma/copy.c:846`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_chroma/copy.c#L846)):
   Interleaves separate 8-bit U and V planes into semi-planar UV using `vld1q_u8` and `vst2q_u8`.
6. [`NEON_Copy420_SP_to_P`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_chroma/copy.c#L875-L883) ([`modules/video_chroma/copy.c:875`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_chroma/copy.c#L875)):
   Wrapper for 8-bit NV12 -> I420; copies plane Y via `CopyPlane` and de-interleaves UV via `NEON_SplitPlanes8`.
7. [`NEON_Copy420_16_SP_to_P`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_chroma/copy.c#L885-L894) ([`modules/video_chroma/copy.c:885`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_chroma/copy.c#L885)):
   Wrapper for 16-bit P010 -> I420_10L; copies plane Y via `CopyPlane` (calling `NEON_CopyPlane16`) and de-interleaves UV via `NEON_SplitPlanes16`.
8. [`NEON_Copy420_P_to_SP`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_chroma/copy.c#L896-L905) ([`modules/video_chroma/copy.c:896`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_chroma/copy.c#L896)):
   Wrapper for 8-bit I420 -> NV12; copies plane Y and interleaves U/V via `NEON_InterleavePlanes8`.
9. [`NEON_Copy420_16_P_to_SP`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_chroma/copy.c#L907-L917) ([`modules/video_chroma/copy.c:907`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_chroma/copy.c#L907)):
   Wrapper for 16-bit I420_10L -> P010; copies plane Y and interleaves U/V via `NEON_InterleavePlanes16`.

---

### Pixel Formats Handled
- **NV12 $\leftrightarrow$ I420:** 8-bit 4:2:0 biplanar $\leftrightarrow$ planar.
- **P010 $\leftrightarrow$ I420_10L:** 10-bit 4:2:0 biplanar (MSB-aligned in 16-bit words) $\leftrightarrow$ 10-bit 4:2:0 planar (LSB-aligned in 16-bit words). Bitshifts used:
  - `P010` $\rightarrow$ `I420_10L`: `bitshift = 6` (shifts right by 6 bits).
  - `I420_10L` $\rightarrow$ `P010`: `bitshift = -6` (shifts left by 6 bits).
- **Formats NOT handled in `copy.c`:** `v210` (packed 10-bit 4:2:2) is not present or handled anywhere in `copy.c`. Similarly, 4:2:2 semi-planar (P210), 4:4:4 semi-planar (P410), and >10-bit formats (P012, P016) are not supported by these routines.

---

### NEON / SIMD Status and CPU Detection
- **Architecture:** 128-bit ARM Advanced SIMD (NEON) vector instructions via `<arm_neon.h>` ([`copy.c:38`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_chroma/copy.c#L38)).
- **CPU Detection:** Unconditional on `__aarch64__`. Because ARMv8-A architecture mandates NEON support, no runtime `vlc_CPU()` check is performed ([`copy.c:630`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_chroma/copy.c#L630), [`copy.c:1058`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_chroma/copy.c#L1058)).

---

### Dispatch Points
1. **Internal Dispatch inside `copy.c`:**
   - [`modules/video_chroma/copy.c:928`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_chroma/copy.c#L928) in [`CopyPlane()`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_chroma/copy.c#L920): Dispatches to `NEON_CopyPlane16` when `bitshift != 0`.
   - [`modules/video_chroma/copy.c:1059`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_chroma/copy.c#L1059) in [`Copy420_SP_to_P()`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_chroma/copy.c#L1051): Calls `NEON_Copy420_SP_to_P`.
   - [`modules/video_chroma/copy.c:1085`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_chroma/copy.c#L1085) in [`Copy420_16_SP_to_P()`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_chroma/copy.c#L1075): Calls `NEON_Copy420_16_SP_to_P`.
   - [`modules/video_chroma/copy.c:1145`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_chroma/copy.c#L1145) in [`Copy420_P_to_SP()`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_chroma/copy.c#L1137): Calls `NEON_Copy420_P_to_SP`.
   - [`modules/video_chroma/copy.c:1181`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_chroma/copy.c#L1181) in [`Copy420_16_P_to_SP()`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_chroma/copy.c#L1172): Calls `NEON_Copy420_16_P_to_SP`.
2. **External Callers in VLC Pipeline:**
   - **`modules/video_chroma/cvpx.c`:**
     - [`modules/video_chroma/cvpx.c:144`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_chroma/cvpx.c#L144): NV12 $\rightarrow$ I420 dispatches to `Copy420_SP_to_P`.
     - [`modules/video_chroma/cvpx.c:153`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_chroma/cvpx.c#L153): P010 $\rightarrow$ I420_10L dispatches to `Copy420_16_SP_to_P` with `shift = 6`.
     - [`modules/video_chroma/cvpx.c:162`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_chroma/cvpx.c#L162): I420 $\rightarrow$ NV12 dispatches to `Copy420_P_to_SP`.
     - [`modules/video_chroma/cvpx.c:167`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_chroma/cvpx.c#L167): I420_10L $\rightarrow$ P010 dispatches to `Copy420_16_P_to_SP` with `shift = -6`.
   - **`modules/video_chroma/i420_nv12.c`:**
     - [`modules/video_chroma/i420_nv12.c:67`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_chroma/i420_nv12.c#L67): `I420_NV12()` filter calls `Copy420_P_to_SP`.
     - [`modules/video_chroma/i420_nv12.c:91`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_chroma/i420_nv12.c#L91): `NV12_I420()` filter calls `Copy420_SP_to_P`.
     - [`modules/video_chroma/i420_nv12.c:112`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_chroma/i420_nv12.c#L112): `I42010B_P010()` filter calls `Copy420_16_P_to_SP` with `shift = -6`.
     - [`modules/video_chroma/i420_nv12.c:126`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_chroma/i420_nv12.c#L126): `P010_I42010B()` filter calls `Copy420_16_SP_to_P` with `shift = 6`.
   - **Self-Test Suite:**
     - [`modules/video_chroma/copy.c:1302-1313`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_chroma/copy.c#L1302-L1313): Registered in benchmark/validation table for `main()`.
     - [`test/src/video_chroma/copy_neon.c:655-667`](file:///Users/omarbenmustapha/Downloads/vlc-master/test/src/video_chroma/copy_neon.c#L655-L667): Invoked directly by the standalone unit test suite.

---

## 3. OpenGL / libplacebo Path and HDR10+ Dynamic Metadata Plumbing

### Struct Fields Added
1. In [`include/vlc_opengl_filter.h`](file:///Users/omarbenmustapha/Downloads/vlc-master/include/vlc_opengl_filter.h#L40):
   - [`include/vlc_opengl_filter.h:50`](file:///Users/omarbenmustapha/Downloads/vlc-master/include/vlc_opengl_filter.h#L50): Added to `struct vlc_gl_input_meta`:
     ```c
     /** HDR10+ dynamic metadata for the input picture, if any */
     const vlc_video_hdr_dynamic_metadata_t *hdr10plus;
     ```
2. In [`modules/video_output/opengl/filters.c`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/opengl/filters.c#L130):
   - [`modules/video_output/opengl/filters.c:147-149`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/opengl/filters.c#L147-L149): Added to `filters->pic` inside `struct vlc_gl_filters`:
     ```c
     /** HDR10+ dynamic metadata for the last picture, if any */
     vlc_video_hdr_dynamic_metadata_t hdr10plus;
     int has_hdr10plus;
     bool hdr10plus_logged;
     ```

---

### How HDR10+ Dynamic Metadata is Carried
1. **Filter State Initialization:**
   In [`vlc_gl_filters_New()`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/opengl/filters.c#L164):
   - [`modules/video_output/opengl/filters.c:184-185`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/opengl/filters.c#L184-L185): Initializes `filters->pic.has_hdr10plus = 0; filters->pic.hdr10plus_logged = false;`.
2. **Per-Picture Ancillary Retrieval:**
   In [`vlc_gl_filters_UpdatePicture()`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/opengl/filters.c#L535):
   - [`modules/video_output/opengl/filters.c:552-562`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/opengl/filters.c#L552-L562):
     Queries picture ancillary data using `picture_GetAncillary(picture, VLC_ANCILLARY_ID_HDR10PLUS)`.
     If found:
     - Sets `filters->pic.has_hdr10plus = 1`.
     - Logs on first receipt: `msg_Dbg(filters->gl, "Using HDR10+ dynamic metadata");`
     - Copies data: `memcpy(&filters->pic.hdr10plus, vlc_ancillary_GetData(hdr10plus), sizeof(filters->pic.hdr10plus));`
     If not found, `filters->pic.has_hdr10plus = 0`.
3. **Passing Down the GL Filter Chain:**
   In [`vlc_gl_filters_Draw()`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/opengl/filters.c#L578):
   - [`modules/video_output/opengl/filters.c:588`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/opengl/filters.c#L588): Assigns `.hdr10plus = filters->pic.has_hdr10plus ? &filters->pic.hdr10plus : NULL` to `struct vlc_gl_input_meta meta` and passes `&meta` to the filters' draw operations.
4. **libplacebo Ingestion:**
   In [`modules/video_output/opengl/pl_scale.c:Draw()`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/opengl/pl_scale.c#L136):
   - [`modules/video_output/opengl/pl_scale.c:184-186`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/opengl/pl_scale.c#L184-L186):
     ```c
     if (meta->hdr10plus) {
         vlc_placebo_HdrMetadata(meta->hdr10plus, &frame_in->color.hdr);
     }
     ```
     Invokes [`vlc_placebo_HdrMetadata()`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/libplacebo/utils.c#L453) (defined in [`modules/video_output/libplacebo/utils.c:453-473`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/libplacebo/utils.c#L453-L473)), which populates `frame_in->color.hdr` (`scene_max`, `scene_avg`, and OOTF Bezier anchors/knee point).

---

### What is Still NOT Wired
1. **Filter Chain Auto-Insertion in `vout_helper.c`:**
   In [`modules/video_output/opengl/vout_helper.c:122-124`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/opengl/vout_helper.c#L122-L124):
   ```c
   int has_dovi = fmt_in->dovi.rpu_present && !fmt_in->dovi.el_present; /* can't handle EL yet */
   if (upscaler || downscaler || has_dovi)
   ```
   `pl_scale` is **only** loaded into the OpenGL filter chain if `--gl-upscaler` or `--gl-downscaler` is set or if Dolby Vision (`has_dovi`) is present in `fmt_in`. There is no check for HDR10+ (since HDR10+ dynamic metadata arrives per-frame via ancillary data, not statically on `fmt_in`). For an HDR10+ stream without scaling and without Dolby Vision, **`pl_scale` is never instantiated**, causing the metadata fetched in `filters.c` to be completely unconsumed and ignored.
2. **Missing Frame-to-Frame State Reset in `pl_scale.c`:**
   In [`modules/video_output/opengl/pl_scale.c:184-186`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/opengl/pl_scale.c#L184-L186), `vlc_placebo_HdrMetadata` mutates `frame_in->color.hdr` in place. If an HDR10+ sequence is followed by frames without HDR10+ metadata (`meta->hdr10plus == NULL`), `frame_in->color.hdr` is never cleared or reset back to static mastering metadata. Stale HDR10+ tone-mapping parameters persist on all subsequent frames.
3. **Unconfigured Output Colorspace and Display Headroom:**
   In [`modules/video_output/opengl/pl_scale.c:330-344`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/opengl/pl_scale.c#L330-L344), `sys->frame_out` is created with 1 plane, but `sys->frame_out.color` is never populated. Libplacebo tone-maps against an uninitialized/default target color space with no knowledge of the display's actual peak luminance or EDR headroom.
4. **libplacebo Version Guard:**
   In [`modules/video_output/libplacebo/utils.c:455-472`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/libplacebo/utils.c#L455-L472), `vlc_placebo_HdrMetadata` is conditionally compiled on `#if PL_API_VER >= 242`. Under older libplacebo headers, the function is a silent no-op (`(void) src; (void) dst;`).
5. **Standard OpenGL Sampler Path Ignorant:**
   The standard OpenGL shaders and sampler ([`modules/video_output/opengl/sampler.c`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/opengl/sampler.c)) do not implement dynamic metadata tone mapping; dynamic metadata is completely unreachable unless `pl_scale` is running.

---

## 4. Incomplete Code, Defects, TODOs, Hardcoded Constants, and Disabled Blocks

### A. `modules/codec/videotoolbox/decoder.c`
- **Line 182 (TODO - Missing 16-bit CVPX pipeline):**
  [`modules/codec/videotoolbox/decoder.c:182`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/codec/videotoolbox/decoder.c#L182):
  ```c
  /* TODO: Add VLC_CODEC_CVPX_P016 across VLC when 16-bit CVPX pipeline support is added. */
  ```
  Content with $>10\text{-bit}$ precision (e.g. 12-bit or 16-bit HEVC) cannot be output as `kCVPixelFormatType_420YpCbCr16BiPlanarVideoRange` because VLC lacks `VLC_CODEC_CVPX_P016` in [`include/vlc_fourcc.h`](file:///Users/omarbenmustapha/Downloads/vlc-master/include/vlc_fourcc.h#L498) and [`modules/video_chroma/cvpx.c`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_chroma/cvpx.c#L140). It falls back to 10-bit P010 (`kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange`) or crushes to 8-bit `kCVPixelFormatType_32BGRA` ([`decoder.c:184-191`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/codec/videotoolbox/decoder.c#L184-L191)).
- **Lines 1028–1033 (Disabled Code / `#if 0`):**
  [`modules/codec/videotoolbox/decoder.c:1028-1033`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/codec/videotoolbox/decoder.c#L1028-L1033):
  ```c
  /* mpgv / mp2v needs fixing, so disable it for now */
  #if 0
          case VLC_CODEC_MPGV:
              return kCMVideoCodecType_MPEG1Video;
          case VLC_CODEC_MP2V:
              return kCMVideoCodecType_MPEG2Video;
  #endif
  ```
- **Line 1088 (Hardcoded Gamma Constant):**
  [`modules/codec/videotoolbox/decoder.c:1088`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/codec/videotoolbox/decoder.c#L1088):
  ```c
  if (video_fmt->transfer == TRANSFER_FUNC_SRGB)
      gamma = 2.2;
  ```
  Hardcoded gamma constant of $2.2$ applied to `kCVImageBufferGammaLevelKey`.
- **Lines 2189–2191 (Unhandled Formats / Abort):**
  [`modules/codec/videotoolbox/decoder.c:2189-2191`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/codec/videotoolbox/decoder.c#L2189-L2191):
  In `UpdateVideoFormat()`, the switch over `cvfmt` only handles UYVY, NV12, P010, I420, and 32BGRA. Any other format produced by hardware decoding hits:
  ```c
  default:
      p_sys->vtsession_status = VTSESSION_STATUS_ABORT;
      return -1;
  ```
  Aborts playback for any other format (e.g. 10-bit 4:2:2, 10-bit 4:4:4, or 16-bit biplanar).
- **Missing Dolby Vision RPU & HDR10+ SEI Handling:**
  VideoToolbox decoder does not parse bitstream NAL units for Dolby Vision RPU or HDR10+ dynamic metadata, completely dropping per-frame dynamic metadata.

---

### B. `modules/codec/vt_utils.c`
- **Lines 492–515 (Hardcoded HDR10 Mastering Display Fallbacks):**
  [`modules/codec/vt_utils.c:492-515`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/codec/vt_utils.c#L492-L515):
  In `cvpx_create_mastering_display_color_volume_data()`:
  - If `max_luminance == 0`, hardcodes $1000\text{ nits}$ (`10000000` in $0.0001\text{ nit}$ units) ([`vt_utils.c:495`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/codec/vt_utils.c#L495)).
  - If `min_luminance == 0`, hardcodes $0.0001\text{ nits}$ (`1` in $0.0001\text{ nit}$ units) ([`vt_utils.c:496`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/codec/vt_utils.c#L496)).
  - If `!has_mastering && is_hdr`, fills hardcoded BT.2020 primaries ($G(0.265, 0.690)$, $B(0.150, 0.060)$, $R(0.680, 0.320)$) and D65 white point ($0.3127, 0.3290$) ([`vt_utils.c:500-509`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/codec/vt_utils.c#L500-L509)).
- **Lines 533–538 (Hardcoded Content Light Level Fallbacks):**
  [`modules/codec/vt_utils.c:533-538`](file:///Users/omarbenmustapha/Downloads/vt_utils.c#L533-L538):
  In `cvpx_create_content_light_level_data()`:
  - If `!has_lighting && is_hdr`: hardcodes `MaxCLL = 1000` nits and `MaxFALL = 400` nits ([`vt_utils.c:536-537`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/codec/vt_utils.c#L536-L537)).
  - If `MaxFALL == 0`: hardcodes `MaxCLL / 2` or `400` ([`vt_utils.c:534`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/codec/vt_utils.c#L534)).
- **Lines 476 & 526 (Improper HLG Handling):**
  [`modules/codec/vt_utils.c:476`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/codec/vt_utils.c#L476) and [`modules/codec/vt_utils.c:526`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/codec/vt_utils.c#L526):
  `is_hdr` includes `fmt->transfer == TRANSFER_FUNC_HLG`. HLG broadcast streams are scene-referred and do not have ST 2086 or CTA-861.3 metadata, but these functions generate and attach synthetic 1000-nit HDR10 mastering and CLL metadata to HLG buffers.
- **Lines 657–664 (Hardcoded ST 2084 Default for HDR):**
  [`modules/codec/vt_utils.c:662-664`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/codec/vt_utils.c#L662-L664):
  ```c
  if (transfer == TRANSFER_FUNC_UNDEF)
      transfer = TRANSFER_FUNC_SMPTE_ST2084;
  ```
  Forces ST 2084 PQ when transfer is undefined on any HDR stream.

---

### C. `modules/video_chroma/copy.c`
- **Line 141 (XXX - SSE efficiency limitation):**
  [`modules/video_chroma/copy.c:141`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_chroma/copy.c#L141):
  ```c
  * XXX It is really efficient only when SSE4.1 is available.
  ```
- **Lines 1332–1334 (Disabled Code / `#if 0`):**
  [`modules/video_chroma/copy.c:1332-1334`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_chroma/copy.c#L1332-L1334):
  ```c
  #if 0 /* too long */
      { 8192, 8192, 8192, 8192 },
  #endif
  ```
  Disables 8K conversion validation in test suite due to execution time.
- **Lines 1080 & 1177 (Bitshift Restrictions):**
  [`modules/video_chroma/copy.c:1080`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_chroma/copy.c#L1080) and [`copy.c:1177`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_chroma/copy.c#L1177):
  ```c
  assert(bitshift >= -6 && bitshift <= 6 && (bitshift % 2 == 0));
  ```
  Hardcoded bounds check limiting bitshift to even offsets between -6 and +6.
- **Unhandled Formats:**
  No support for 10-bit 4:2:2 (e.g. v210 or P210), 10-bit 4:4:4, or >10-bit biplanar formats (P012/P016).

---

### D. `modules/video_output/opengl/vout_helper.c`
- **Line 122 (Incomplete Dolby Vision EL Handling):**
  [`modules/video_output/opengl/vout_helper.c:122`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/opengl/vout_helper.c#L122):
  ```c
  int has_dovi = fmt_in->dovi.rpu_present && !fmt_in->dovi.el_present; /* can't handle EL yet */
  ```
  Explicitly rejects Dolby Vision Enhancement Layer (Profile 7).
- **Lines 124–146 (Missing HDR10+ Instantiation):**
  [`modules/video_output/opengl/vout_helper.c:124`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/opengl/vout_helper.c#L124):
  `pl_scale` is not inserted for HDR10+ dynamic metadata streams unless `--gl-upscaler` or `--gl-downscaler` is manually set or Dolby Vision is present.

---

### E. `modules/video_output/opengl/pl_scale.c`
- **Line 177 (Hardcoded DoVi PQ Normalization Constant):**
  [`modules/video_output/opengl/pl_scale.c:177`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/opengl/pl_scale.c#L177):
  ```c
  const float scale = 1.0f / ((1 << 12) - 1);
  ```
  Hardcoded 12-bit PQ normalization scale factor $1 / 4095.0\text{f}$.
- **Lines 184–186 (Missing Per-Frame Reset):**
  [`modules/video_output/opengl/pl_scale.c:184-186`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/opengl/pl_scale.c#L184-L186):
  Does not reset `frame_in->color.hdr` when an input picture has no `meta->hdr10plus`.
- **Lines 330–344 (Unconfigured Target Display / Output Color):**
  [`modules/video_output/opengl/pl_scale.c:330-344`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/opengl/pl_scale.c#L330-L344):
  `sys->frame_out.color` remains all zeros.

---

### F. Core Formats & Headers
- **`include/vlc_es.h` Lines 419–456 (Defective HDR Heuristic in `video_format_AdjustColorSpace`):**
  [`include/vlc_es.h:419-456`](file:///Users/omarbenmustapha/Downloads/vlc-master/include/vlc_es.h#L419-L456):
  ```c
  static inline void video_format_AdjustColorSpace( video_format_t *p_fmt )
  {
      if ( p_fmt->primaries == COLOR_PRIMARIES_UNDEF )
      {
          if ( p_fmt->i_visible_height > 576 ) // HD
              p_fmt->primaries = COLOR_PRIMARIES_BT709;
          ...
      }
      if ( p_fmt->transfer == TRANSFER_FUNC_UNDEF )
      {
          if ( p_fmt->i_visible_height > 576 ) // HD
              p_fmt->transfer = TRANSFER_FUNC_BT709;
          ...
      }
      if ( p_fmt->space == COLOR_SPACE_UNDEF )
      {
          if ( p_fmt->i_visible_height > 576 ) // HD
              p_fmt->space = COLOR_SPACE_BT709;
          ...
      }
  ```
  Has no heuristic for HDR / UHD. Any stream with undefined primaries, transfer, or matrix is forced to SDR BT.709 even if visible height is 2160 (4K) or 4320 (8K).
- **`include/vlc_fourcc.h` Lines 498–502 (Missing CVPX FourCCs):**
  [`include/vlc_fourcc.h:498-502`](file:///Users/omarbenmustapha/Downloads/vlc-master/include/vlc_fourcc.h#L498-L502):
  Defines `VLC_CODEC_CVPX_NV12`, `VLC_CODEC_CVPX_UYVY`, `VLC_CODEC_CVPX_I420`, `VLC_CODEC_CVPX_BGRA`, and `VLC_CODEC_CVPX_P010`. Lacks definitions for 16-bit CVPX formats (`VLC_CODEC_CVPX_P016`) or 10-bit packed CVPX formats (`VLC_CODEC_CVPX_v210`).

---

## 5. Build-System Wiring and Test Registration

### `Makefile.am` Entries
- [`test/Makefile.am:74`](file:///Users/omarbenmustapha/Downloads/vlc-master/test/Makefile.am#L74):
  Adds `test_src_video_chroma_copy_neon` to `check_PROGRAMS` unconditionally.
- [`test/Makefile.am:120`](file:///Users/omarbenmustapha/Downloads/vlc-master/test/Makefile.am#L120):
  Adds `test_src_misc_cvpx_hdr_metadata` to `check_PROGRAMS` under `if HAVE_DARWIN`.
- [`test/Makefile.am:157`](file:///Users/omarbenmustapha/Downloads/vlc-master/test/Makefile.am#L157):
  ```makefile
  TESTS = $(check_PROGRAMS) check_POTFILES.sh
  ```
  Registers all `check_PROGRAMS` directly into `TESTS` for execution during `make check`.
- [`test/Makefile.am:314-316`](file:///Users/omarbenmustapha/Downloads/vlc-master/test/Makefile.am#L314-L316):
  ```makefile
  test_src_misc_cvpx_hdr_metadata_SOURCES = src/misc/cvpx_hdr_metadata.c
  test_src_misc_cvpx_hdr_metadata_LDADD = $(LIBVLCCORE) $(LIBVLC) ../modules/libvlc_vtutils.la
  test_src_misc_cvpx_hdr_metadata_LDFLAGS = $(AM_LDFLAGS) -Wl,-framework,CoreVideo
  ```
- [`test/Makefile.am:335-336`](file:///Users/omarbenmustapha/Downloads/vlc-master/test/Makefile.am#L335-L336):
  ```makefile
  test_src_video_chroma_copy_neon_SOURCES = src/video_chroma/copy_neon.c
  test_src_video_chroma_copy_neon_LDADD = $(LIBVLCCORE) $(LIBVLC) ../modules/libchroma_copy.la
  ```
- [`modules/video_chroma/Makefile.am:15-17`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_chroma/Makefile.am#L15-L17):
  Included by [`modules/Makefile.am:100`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/Makefile.am#L100):
  ```makefile
  libchroma_copy_la_SOURCES = video_chroma/copy.c video_chroma/copy.h
  libchroma_copy_la_LDFLAGS = -static
  noinst_LTLIBRARIES += libchroma_copy.la
  ```
- [`modules/video_chroma/Makefile.am:89-103`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_chroma/Makefile.am#L89-L103):
  Builds `chroma_copy_sse_test` and `chroma_copy_test`. Does not build or reference `copy_neon.c`.

---

### `meson.build` Entries
- [`modules/video_chroma/meson.build:2-8`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_chroma/meson.build#L2-L8):
  Builds `chroma_copy_lib` from `copy.c`.
- [`modules/video_chroma/meson.build:130-149`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_chroma/meson.build#L130-L149):
  Registers `chroma_copy_sse_test` and `chroma_copy_test` into `vlc_tests`. Does not register `copy_neon.c`.
- [`test/src/meson.build:390-396`](file:///Users/omarbenmustapha/Downloads/vlc-master/test/src/meson.build#L390-L396):
  Under `if host_system == 'darwin'`, only registers `test_src_misc_image_cvpx`.
- **Missing Meson Registrations:**
  - `test/src/misc/cvpx_hdr_metadata.c` is **completely absent** from all `meson.build` files.
  - `test/src/video_chroma/copy_neon.c` is **completely absent** from all `meson.build` files.

---

### Registration Status Evaluation
- **Autotools (`make check`): Correctly Registered.**
  Both `test_src_misc_cvpx_hdr_metadata` and `test_src_video_chroma_copy_neon` are registered in `check_PROGRAMS` and included in `TESTS`.
  - `cvpx_hdr_metadata.c` is guarded by `if HAVE_DARWIN` and links the required `CoreVideo` framework and `libvlc_vtutils.la`.
  - `copy_neon.c` is unconditional in `test/Makefile.am`, but safely handles non-ARM64 platforms via an architecture guard in [`test/src/video_chroma/copy_neon.c:38-44`](file:///Users/omarbenmustapha/Downloads/vlc-master/test/src/video_chroma/copy_neon.c#L38-L44) (`#if !defined(__aarch64__)`), where it logs a skip message and exits 0.
- **Meson (`ninja test`): NOT Registered.**
  Neither test is registered in any `meson.build` file. In a Meson build, neither `copy_neon` nor `cvpx_hdr_metadata` will be compiled or executed.

---

UNCERTAIN:
- Whether any out-of-tree or third-party OpenGL filter plugins consume `vlc_gl_input_meta.hdr10plus` when `pl_scale` is not loaded in `vout_helper.c`.
- Runtime behavior of `deviceSupportsAV1()` on actual Apple Silicon M3/M4 hardware running macOS 14.0+ (verified statically via SDK API check).

