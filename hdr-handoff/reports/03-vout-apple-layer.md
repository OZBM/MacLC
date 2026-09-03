# Technical Architecture Map: macOS / Apple Silicon HDR Video-Output & Display Layer in VLC

---

## 1. HDR Code Paths and Frame Flow (Decoder Output to Screen)

Two distinct video output display modules exist in this fork for macOS:
1. **Primary Path**: [`samplebufferdisplay`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/apple/VLCSampleBufferDisplay.m#L1825-L1836) in [`modules/video_output/apple/VLCSampleBufferDisplay.m`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/apple/VLCSampleBufferDisplay.m) (module priority 600 via `set_callback_display(Open, 600)` at line 1835). This is the default display on macOS.
2. **Fallback Path**: [`caopengllayer`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/caopengllayer.m#L1124-L1131) in [`modules/video_output/caopengllayer.m`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/caopengllayer.m) (module priority 300 via `set_callback_display(Open, 300)` at line 1127). Used if `samplebufferdisplay` fails or if forced via `--force-darwin-legacy-display`.

```
[Decoder: VideoToolbox (Hardware CVPX) / dav1d / avcodec (Software YUV)]
                             │
                             ▼
              [vout core: vout_display_Prepare]
                             │
       ┌─────────────────────┴──────────────────────┐
       │                                            │
       ▼ (Priority 600)                             ▼ (Priority 300 Fallback)
[VLCSampleBufferDisplay]                     [caopengllayer]
  ├─ If software YUV:                          ├─ Request CGL 4.1/3.2 Core Context
  │   CreateCVPXConverter -> CVPX_P010         │   (64-bit RGBA16 or 24-bit RGBA8)
  ├─ Merge format properties                   ├─ Inspect mastering/lighting
  ├─ Apply macosx-hdr-mode                     ├─ VLCCAOpenGLLayer:
  ├─ cvpx_attach_mapped_color_properties       │   ├─ wantsExtendedDynamicRangeContent = YES
  ├─ cvpx_attach_hdr_metadata (ST 2086/CTA861) │   ├─ colorspace = ExtendedLinearDisplayP3
  ├─ Wrap in CMVideoFormatDescription          │   ├─ preferredDynamicRange (High/Standard)
  ├─ Wrap in CMSampleBuffer (CACurrentMediaTime)│   └─ contentsHeadroom = screen headroom
  ├─ AVSampleBufferDisplayLayer                ├─ vout_display_opengl_Prepare (upload & shaders)
  │   ├─ wantsExtendedDynamicRangeContent=YES  ├─ [layer markReady] & [layer displayFromVout]
  │   ├─ preferredDynamicRange=CADynamicRangeHigh └─ drawInCGLContext:
  │   ├─ contentsHeadroom=effectiveHeadroom         └─ vout_display_opengl_Display -> CGLFlushDrawable
  │   └─ toneMapMode=CAToneMapModeIfSupported
  ▼                                            ▼
[Apple CoreAnimation & WindowServer Compositor -> Apple Silicon Display Engine (XDR / EDR)]
```

---

### Path A: Primary CoreMedia / AVSampleBufferDisplayLayer Path
- **Module Registration & Initiation**:
  - Registered with priority 600: [`VLCSampleBufferDisplay.m:1835`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/apple/VLCSampleBufferDisplay.m#L1835).
  - Module open callback [`Open()`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/apple/VLCSampleBufferDisplay.m#L1718-L1787):
    - Checks `force-darwin-legacy-display`: [`VLCSampleBufferDisplay.m:1721-1723`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/apple/VLCSampleBufferDisplay.m#L1721-L1723). If true, aborts with `VLC_EGENERIC` to fall back to `caopengllayer`.
    - Checks video context for `VLC_VIDEO_CONTEXT_CVPX`: [`VLCSampleBufferDisplay.m:1731-1736`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/apple/VLCSampleBufferDisplay.m#L1731-L1736). If absent (software decoders like `dav1d` or `avcodec`), calls [`CreateCVPXConverter()`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/apple/VLCSampleBufferDisplay.m#L431-L488) to instantiate a chroma filter converting CPU pictures to `VLC_CODEC_CVPX_P010` for 10-bit HDR content ([`VLCSampleBufferDisplay.m:449-461`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/apple/VLCSampleBufferDisplay.m#L449-L461)).
    - Instantiates [`VLCSampleBufferDisplay`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/apple/VLCSampleBufferDisplay.m#L772-L807) object: [`VLCSampleBufferDisplay.m:1739-1746`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/apple/VLCSampleBufferDisplay.m#L1739-L1746).
    - Reads initial `macosx-edr-headroom`: [`VLCSampleBufferDisplay.m:1749-1758`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/apple/VLCSampleBufferDisplay.m#L1749-L1758).
    - Sets up dynamic callbacks for `macosx-edr-headroom` ([`EdrHeadroomCallback`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/apple/VLCSampleBufferDisplay.m#L1245-L1258)) and `macosx-hdr-mode` ([`HdrModeCallback`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/apple/VLCSampleBufferDisplay.m#L1260-L1267)) at lines 1760-1765.
    - Sets display callbacks: `.prepare = Prepare`, `.display = Display`, `.update_format = UpdateFormat`, `.video_place_changed = PlacementChanged`, `.close = Close` ([`VLCSampleBufferDisplay.m:1768-1775`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/apple/VLCSampleBufferDisplay.m#L1768-L1775)).
    - Declares subpicture chroma support for `VLC_CODEC_ARGB`: [`VLCSampleBufferDisplay.m:1779-1784`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/apple/VLCSampleBufferDisplay.m#L1779-L1784).

- **Layer & Screen EDR Setup**:
  - Triggered in [`Prepare()`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/apple/VLCSampleBufferDisplay.m#L1636-L1645) -> [`PrepareDisplay()`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/apple/VLCSampleBufferDisplay.m#L1629-L1634) -> [`prepareDisplay`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/apple/VLCSampleBufferDisplay.m#L838-L874).
  - Main thread dispatches UI creation: builds [`VLCSampleBufferDisplayView`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/apple/VLCSampleBufferDisplay.m#L656-L754) and [`VLCSampleBufferSubpictureView`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/apple/VLCSampleBufferDisplay.m#L584-L654).
  - Backing layer [`makeBackingLayer`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/apple/VLCSampleBufferDisplay.m#L672-L709) creates an `AVSampleBufferDisplayLayer`, enables `wantsExtendedDynamicRangeContent = YES` (macOS 10.15+), `preferredDynamicRange = CADynamicRangeHigh` (macOS 14+), queries window screen headroom via `maximumExtendedDynamicRangeColorComponentValue`, sets `contentsHeadroom = headroom`, and sets `toneMapMode = CAToneMapModeIfSupported` (macOS 15+).
  - Subtitle view `spuView` setup ([`VLCSampleBufferDisplay.m#L589-L611`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/apple/VLCSampleBufferDisplay.m#L589-L611)) forces `wantsExtendedDynamicRangeContent = NO` and `contentsHeadroom = 1.0` to isolate subtitle drawing from HDR highlight expansion.
  - Registers screen notifications: [`setupScreenObservers`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/apple/VLCSampleBufferDisplay.m#L876-L895) listens for `NSApplicationDidChangeScreenParametersNotification`, `NSWindowDidChangeScreenNotification`, and `NSWindowDidChangeScreenProfileNotification`.
  - Dynamic headroom & mode adaptation: [`updateDynamicRangeAndHeadroom`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/apple/VLCSampleBufferDisplay.m#L926-L1173):
    - Re-reads screen headroom from `nswindow.screen.maximumExtendedDynamicRangeColorComponentValue` (or potential headroom if peak is 1.0) ([`VLCSampleBufferDisplay.m:947-952`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/apple/VLCSampleBufferDisplay.m#L947-L952)).
    - Reconciles user headroom override `_userHeadroom` with screen headroom ([`VLCSampleBufferDisplay.m:966-972`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/apple/VLCSampleBufferDisplay.m#L966-L972)).
    - Applies `CADynamicRangeStandard` / `CAToneMapModeAutomatic` / `wantsExtendedDynamicRangeContent = NO` for SDR Modes 2 & 3 ([`VLCSampleBufferDisplay.m:982-1046`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/apple/VLCSampleBufferDisplay.m#L982-L1046)).
    - Applies `CADynamicRangeHigh` / `CAToneMapModeIfSupported` / `extendedSRGBColorSpace` / `wantsExtendedDynamicRangeContent = YES` for HDR Modes 0 & 1 ([`VLCSampleBufferDisplay.m:1055-1134`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/apple/VLCSampleBufferDisplay.m#L1055-L1134)).
    - Adapts subtitle luminance/opacity: [`VLCSampleBufferDisplay.m:1142-1170`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/apple/VLCSampleBufferDisplay.m#L1142-L1170) calculates `factor = 203.0f / (100.0f * effectiveHeadroom)` (BT.2408 reference white scale factor) and sets `spuView.layer.opacity = (float)factor`.

- **Frame Render & Presentation Flow**:
  - Core calls [`Prepare()`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/apple/VLCSampleBufferDisplay.m#L1636-L1645) -> [`RenderPicture()`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/apple/VLCSampleBufferDisplay.m#L1282-L1487):
    - Video orientation mapped to rotation session properties: [`VLCSampleBufferDisplay.m:1286-1318`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/apple/VLCSampleBufferDisplay.m#L1286-L1318).
    - If software picture, passes through `sys->converter->ops->filter_video()`: [`VLCSampleBufferDisplay.m:1330-1332`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/apple/VLCSampleBufferDisplay.m#L1330-L1332).
    - Extracts `CVPixelBufferRef pixelBuffer = cvpxpic_get_ref(dst)` and retains: [`VLCSampleBufferDisplay.m:1334-1335`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/apple/VLCSampleBufferDisplay.m#L1334-L1335).
    - Rotates `pixelBuffer` if orientation is non-normal: [`VLCSampleBufferDisplay.m:1343-1349`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/apple/VLCSampleBufferDisplay.m#L1343-L1349) using `VTPixelRotationSessionRotateImage` ([`VLCSampleBufferDisplay.m:283`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/apple/VLCSampleBufferDisplay.m#L283)).
    - Merges format metadata (`transfer`, `primaries`, `space`, `mastering`, `lighting`) from `vd->fmt` into `render_fmt` if `pic->format` is undefined: [`VLCSampleBufferDisplay.m:1352-1362`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/apple/VLCSampleBufferDisplay.m#L1352-L1362).
    - Evaluates `macosx-hdr-mode`: [`VLCSampleBufferDisplay.m:1364-1401`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/apple/VLCSampleBufferDisplay.m#L1364-L1401).
    - Calls [`cvpx_attach_mapped_color_properties(pixelBuffer, &render_fmt)`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/codec/vt_utils.c#L648-L726): [`VLCSampleBufferDisplay.m:1404`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/apple/VLCSampleBufferDisplay.m#L1404).
    - Calls [`cvpx_attach_hdr_metadata(pixelBuffer, &render_fmt)`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/codec/vt_utils.c#L530-L555): [`VLCSampleBufferDisplay.m:1405`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/apple/VLCSampleBufferDisplay.m#L1405).
    - Attaches pixel aspect ratio: [`VLCSampleBufferDisplay.m:1440-1452`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/apple/VLCSampleBufferDisplay.m#L1440-L1452).
    - Creates `CMVideoFormatDescriptionRef` for `pixelBuffer`: [`VLCSampleBufferDisplay.m:1456`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/apple/VLCSampleBufferDisplay.m#L1456).
    - Calculates presentation timing against `CACurrentMediaTime()`: [`VLCSampleBufferDisplay.m:1463-1472`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/apple/VLCSampleBufferDisplay.m#L1463-L1472).
    - Encapsulates into `CMSampleBufferRef`: [`VLCSampleBufferDisplay.m:1474`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/apple/VLCSampleBufferDisplay.m#L1474).
    - Submits to hardware compositor: `[sys.displayLayer enqueueSampleBuffer:sampleBuffer]`: [`VLCSampleBufferDisplay.m:1483`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/apple/VLCSampleBufferDisplay.m#L1483).
    - Pacing stub [`Display()`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/apple/VLCSampleBufferDisplay.m#L1647-L1650) returns immediately.

---

### Path B: Fallback OpenGL / CAOpenGLLayer Path
- **Module Registration & Initiation**:
  - Registered with priority 300: [`caopengllayer.m:1127`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/caopengllayer.m#L1127).
  - Module open callback [`Open()`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/caopengllayer.m#L533-L680):
    - Creates CGL context via [`vlc_CreateCGLContext()`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/caopengllayer.m#L212-L305) inside [`OpenOpenGL()`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/caopengllayer.m#L377-L409).
    - Requests OpenGL 4.1 Core profile (`kCGLOGLPVersion_GL4_1_Core`), falling back to 3.2 Core (`kCGLOGLPVersion_GL3_2_Core`), with 64-bit color depth (16 bits/channel RGBA) ([`caopengllayer.m:221-286`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/caopengllayer.m#L221-L286)).
    - Copies mastering display and lighting info from `vd->source` into `fmt` if missing: [`caopengllayer.m:588-591`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/caopengllayer.m#L588-L591).
    - Checks `is_hdr` boolean (`TRANSFER_FUNC_SMPTE_ST2084` or `TRANSFER_FUNC_HLG`): [`caopengllayer.m:606-609`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/caopengllayer.m#L606-L609).
    - Notifies view on main thread: `[view setHDR:is_hdr]`: [`caopengllayer.m:615`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/caopengllayer.m#L615).
    - Initializes backing [`VLCCAOpenGLLayer`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/caopengllayer.m#L938-L986): sets `wantsExtendedDynamicRangeContent = YES`, `colorspace = kCGColorSpaceExtendedLinearDisplayP3` ([`caopengllayer.m:960-965`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/caopengllayer.m#L960-L965)).
    - Screen headroom query and layer update: [`updateDynamicRangeWithHeadroom:isHDR:`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/caopengllayer.m#L988-L1017) sets `wantsExtendedDynamicRangeContent = YES`, `preferredDynamicRange = isHDR ? CADynamicRangeHigh : CADynamicRangeStandard` (macOS 14+), `contentsHeadroom = headroom` (macOS 14+), `toneMapMode = isHDR ? CAToneMapModeIfSupported : CAToneMapModeAutomatic` (macOS 15+).
    - Creates VLC OpenGL rendering pipeline: `vout_display_opengl_New()` ([`caopengllayer.m:654-656`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/caopengllayer.m#L654-L656)).

- **Frame Render & Presentation Flow**:
  - Core calls [`PictureRender()`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/caopengllayer.m#L430-L455):
    - Locks and binds context: `vlc_gl_MakeCurrent(sys->gl)` ([`caopengllayer.m:437`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/caopengllayer.m#L437)).
    - Updates projection/viewport if changed: [`caopengllayer.m:439-447`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/caopengllayer.m#L439-L447).
    - Uploads picture textures and runs GL shaders / tone mapping: `vout_display_opengl_Prepare(sys->vgl, pic, subpicture)` ([`caopengllayer.m:448`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/caopengllayer.m#L448)).
    - Releases context: `vlc_gl_ReleaseCurrent(sys->gl)` ([`caopengllayer.m:449`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/caopengllayer.m#L449)).
    - Marks layer ready: `[layer markReady]` ([`caopengllayer.m:453`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/caopengllayer.m#L453)).
  - Core calls [`PictureDisplay()`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/caopengllayer.m#L457-L465) -> `[layer displayFromVout]` ([`caopengllayer.m:464`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/caopengllayer.m#L464)) -> triggers `[self display]`.
  - CoreAnimation render loop invokes [`drawInCGLContext:pixelFormat:forLayerTime:displayTime:`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/caopengllayer.m#L1076-L1105):
    - Makes CGL context current: [`caopengllayer.m:1085`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/caopengllayer.m#L1085).
    - Executes rendering block `self.render(newSize)` ([`caopengllayer.m:623-639`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/caopengllayer.m#L623-L639)) calling `vout_display_opengl_Display(sys->vgl)`.
    - Swaps buffers: `vlc_gl_Swap(_gl)` -> `CGLFlushDrawable(_context)` ([`caopengllayer.m:831-836`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/caopengllayer.m#L831-L836)).

---

## 2. HDR Metadata Mapping (VLC Structs -> CoreVideo / CoreAnimation)

All metadata translation is implemented in [`modules/codec/vt_utils.c`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/codec/vt_utils.c) and attached to CVPixelBuffers via [`cvpx_attach_mapped_color_properties()`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/codec/vt_utils.c#L648-L726) and [`cvpx_attach_hdr_metadata()`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/codec/vt_utils.c#L530-L555).

| VLC [`video_format_t`](file:///Users/omarbenmustapha/Downloads/vlc-master/include/vlc_es.h#L343-L377) Field | VLC Enum / Value | Target CoreVideo / CoreAnimation Key | CoreVideo / CoreAnimation Value / Binary Format | Code Location |
| :--- | :--- | :--- | :--- | :--- |
| **`transfer`** | `TRANSFER_FUNC_SMPTE_ST2084` | `kCVImageBufferTransferFunctionKey` | `kCVImageBufferTransferFunction_SMPTE_ST_2084_PQ` | [`vt_utils.c:371-374`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/codec/vt_utils.c#L371-L374) |
| | `TRANSFER_FUNC_HLG` | `kCVImageBufferTransferFunctionKey` | `kCVImageBufferTransferFunction_ITU_R_2100_HLG` | [`vt_utils.c:383-386`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/codec/vt_utils.c#L383-L386) |
| | `TRANSFER_FUNC_BT709` | `kCVImageBufferTransferFunctionKey` | `kCVImageBufferTransferFunction_ITU_R_709_2` | [`vt_utils.c:375-380`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/codec/vt_utils.c#L375-L380) |
| | `TRANSFER_FUNC_SMPTE_240` | `kCVImageBufferTransferFunctionKey` | `kCVImageBufferTransferFunction_SMPTE_240M_1995` | [`vt_utils.c:381-382`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/codec/vt_utils.c#L381-L382) |
| | `TRANSFER_FUNC_LINEAR` | `kCVImageBufferTransferFunctionKey` | `kCVImageBufferTransferFunction_Linear` | [`vt_utils.c:387-395`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/codec/vt_utils.c#L387-L395) |
| | `TRANSFER_FUNC_SRGB` | `kCVImageBufferTransferFunctionKey` & `kCVImageBufferGammaLevelKey` | `kCVImageBufferTransferFunction_UseGamma` & `Float32 = 2.2` | [`vt_utils.c:396-397, 706-718`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/codec/vt_utils.c#L396-L397) |
| | Unhandled / ISO TC | `kCVImageBufferTransferFunctionKey` | `CVTransferFunctionGetStringForIntegerCodePoint(tc_cicp)` | [`vt_utils.c:401-405`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/codec/vt_utils.c#L401-L405) |
| **`primaries`** | `COLOR_PRIMARIES_BT2020` | `kCVImageBufferColorPrimariesKey` | `kCVImageBufferColorPrimaries_ITU_R_2020` | [`vt_utils.c:347-348`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/codec/vt_utils.c#L347-L348) |
| | `COLOR_PRIMARIES_BT709` | `kCVImageBufferColorPrimariesKey` | `kCVImageBufferColorPrimaries_ITU_R_709_2` | [`vt_utils.c:349-350`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/codec/vt_utils.c#L349-L350) |
| | `COLOR_PRIMARIES_SMTPE_170` | `kCVImageBufferColorPrimariesKey` | `kCVImageBufferColorPrimaries_SMPTE_C` | [`vt_utils.c:351-352`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/codec/vt_utils.c#L351-L352) |
| | `COLOR_PRIMARIES_EBU_3213` | `kCVImageBufferColorPrimariesKey` | `kCVImageBufferColorPrimaries_EBU_3213` | [`vt_utils.c:353-354`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/codec/vt_utils.c#L353-L354) |
| | Unhandled / ISO CP | `kCVImageBufferColorPrimariesKey` | `CVColorPrimariesGetStringForIntegerCodePoint(cp_cicp)` | [`vt_utils.c:358-362`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/codec/vt_utils.c#L358-L362) |
| **`space`** | `COLOR_SPACE_BT2020` | `kCVImageBufferYCbCrMatrixKey` | `kCVImageBufferYCbCrMatrix_ITU_R_2020` | [`vt_utils.c:325-328`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/codec/vt_utils.c#L325-L328) |
| | `COLOR_SPACE_BT709` | `kCVImageBufferYCbCrMatrixKey` | `kCVImageBufferYCbCrMatrix_ITU_R_709_2` | [`vt_utils.c:329-330`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/codec/vt_utils.c#L329-L330) |
| | `COLOR_SPACE_BT601` | `kCVImageBufferYCbCrMatrixKey` | `kCVImageBufferYCbCrMatrix_ITU_R_601_4` | [`vt_utils.c:323-324`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/codec/vt_utils.c#L323-L324) |
| | Unhandled / ISO MC | `kCVImageBufferYCbCrMatrixKey` | `CVYCbCrMatrixGetStringForIntegerCodePoint(mc_cicp)` | [`vt_utils.c:334-338`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/codec/vt_utils.c#L334-L338) |
| **`mastering`** | `primaries[6]` | `kCVImageBufferMasteringDisplayColorVolumeKey` | 24-byte big-endian packed `st2086`: `display_primaries[3][2]` (G, B, R in 0.00002 units: `htons(primaries[0..5])`) | [`vt_utils.c:456-471`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/codec/vt_utils.c#L456-L471) |
| | `white_point[2]` | `kCVImageBufferMasteringDisplayColorVolumeKey` | `st2086.white_point[2]` (x, y in 0.00002 units: `htons(white_point[0..1])`) | [`vt_utils.c:462-463, 473-475`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/codec/vt_utils.c#L462-L463) |
| | `max_luminance` | `kCVImageBufferMasteringDisplayColorVolumeKey` | `st2086.max_luminance` (`htonl(max_l)` in 0.0001 nit units; scaled by 10000 if <10000) | [`vt_utils.c:477-479, 492`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/codec/vt_utils.c#L477-L479) |
| | `min_luminance` | `kCVImageBufferMasteringDisplayColorVolumeKey` | `st2086.min_luminance` (`htonl(min_l)` in 0.0001 nit units) | [`vt_utils.c:480, 493`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/codec/vt_utils.c#L480) |
| **`lighting`** | `MaxCLL` | `kCVImageBufferContentLightLevelInfoKey` | 4-byte big-endian packed `cta861_3`: `max_cll = htons(MaxCLL)` (1 nit units) | [`vt_utils.c:519, 522`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/codec/vt_utils.c#L519) |
| | `MaxFALL` | `kCVImageBufferContentLightLevelInfoKey` | `cta861_3.max_fall = htons(MaxFALL)` (1 nit units) | [`vt_utils.c:520, 523`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/codec/vt_utils.c#L520) |
| **`i_sar_num, i_sar_den`** | Aspect ratio | `kCVImageBufferPixelAspectRatioKey` | `CFDictionaryRef` containing horizontal/vertical spacing | [`VLCSampleBufferDisplay.m:1440-1452`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/apple/VLCSampleBufferDisplay.m#L1440-L1452) |
| **Dynamic Range** | EDR Capability | `CALayer.wantsExtendedDynamicRangeContent` | `BOOL = YES` (HDR Modes 0, 1) / `NO` (SDR Modes 2, 3) | [`VLCSampleBufferDisplay.m:986-989, 1059-1065`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/apple/VLCSampleBufferDisplay.m#L986-L989) |
| | Dynamic Range Request | `CALayer.preferredDynamicRange` (macOS 14+) | `CADynamicRangeHigh` (HDR) / `CADynamicRangeStandard` (SDR) | [`VLCSampleBufferDisplay.m:1009, 1085`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/apple/VLCSampleBufferDisplay.m#L1009) |
| | Headroom Scaling | `CALayer.contentsHeadroom` (macOS 14+) | `CGFloat = effectiveHeadroom` (>= 1.0) / `1.0` (SDR) | [`VLCSampleBufferDisplay.m:1010, 1087-1090`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/apple/VLCSampleBufferDisplay.m#L1010) |
| | Compositor Tone Mapping | `CALayer.toneMapMode` (macOS 15+) | `CAToneMapModeIfSupported` (HDR) / `CAToneMapModeAutomatic` (SDR) | [`VLCSampleBufferDisplay.m:1030, 1110`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/apple/VLCSampleBufferDisplay.m#L1030) |
| | Window Color Profile | `NSWindow.colorSpace` | `[NSColorSpace extendedSRGBColorSpace]` | [`VLCSampleBufferDisplay.m:1063`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/apple/VLCSampleBufferDisplay.m#L1063) |

---

## 3. Incomplete Code, Hardcoded Values, Unhandled Cases, and Stubbed Branches

1. **`CAEDRMetadata` is completely unreferenced and unused**:
   - `CAEDRMetadata` has **0 hits** across the entire codebase. Neither `HDR10MetadataWithDisplayInfo:contentInfo:opticalOutputScale:` nor `HLGMetadata` is ever called.
   - `CAMetalLayer` is also unused in rendering (only referenced once in a documentation comment in [`modules/video_output/apple/VLCVideoUIView.m:24`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/apple/VLCVideoUIView.m#L24)).

2. **Hardcoded Fallbacks in SMPTE ST 2086 Mastering Metadata Creation**:
   - [`modules/codec/vt_utils.c:465-470`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/codec/vt_utils.c#L465-L470): Hardcoded BT.2020 primaries if Green X primary is 0:
     ```c
     st2086.display_primaries[0][0] = htons(13250); // G.x
     st2086.display_primaries[0][1] = htons(34500); // G.y
     st2086.display_primaries[1][0] = htons(7500);  // B.x
     st2086.display_primaries[1][1] = htons(3000);  // B.y
     st2086.display_primaries[2][0] = htons(34000); // R.x
     st2086.display_primaries[2][1] = htons(16000); // R.y
     ```
   - [`modules/codec/vt_utils.c:473-474`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/codec/vt_utils.c#L473-L474): Hardcoded D65 white point:
     ```c
     st2086.white_point[0] = htons(15635); // D65.x
     st2086.white_point[1] = htons(16450); // D65.y
     ```
   - [`modules/codec/vt_utils.c:477-480`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/codec/vt_utils.c#L477-L480): Hardcoded 1000 nits max and 0.0001 nits min fallback:
     ```c
     uint32_t max_l = fmt->mastering.max_luminance;
     if (max_l > 0 && max_l < 10000)
         max_l *= 10000;
     st2086.max_luminance = htonl(max_l ? max_l : 10000000);
     st2086.min_luminance = htonl(fmt->mastering.min_luminance ? fmt->mastering.min_luminance : 1);
     ```
   - [`modules/codec/vt_utils.c:484-493`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/codec/vt_utils.c#L484-L493): Entire synthetic ST 2086 payload hardcoded if stream has no mastering display metadata:
     ```c
     st2086.display_primaries[0][0] = htons(13250); // G.x: 0.265
     st2086.display_primaries[0][1] = htons(34500); // G.y: 0.690
     st2086.display_primaries[1][0] = htons(7500);  // B.x: 0.150
     st2086.display_primaries[1][1] = htons(3000);  // B.y: 0.060
     st2086.display_primaries[2][0] = htons(34000); // R.x: 0.680
     st2086.display_primaries[2][1] = htons(16000); // R.y: 0.320
     st2086.white_point[0] = htons(15635);          // D65.x: 0.3127
     st2086.white_point[1] = htons(16450);          // D65.y: 0.3290
     st2086.max_luminance = htonl(10000000);        // 1000 nits in 0.0001 nit units
     st2086.min_luminance = htonl(1);               // 0.0001 nits in 0.0001 nit units
     ```

3. **Hardcoded Fallbacks in CTA-861.3 Content Light Level Metadata**:
   - [`modules/codec/vt_utils.c:519-520`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/codec/vt_utils.c#L519-L520): Hardcoded MaxCLL fallback (1000 nits) and MaxFALL fallback (`MaxCLL / 2` or 400 nits):
     ```c
     cta861_3.max_cll = htons(fmt->lighting.MaxCLL ? fmt->lighting.MaxCLL : 1000);
     cta861_3.max_fall = htons(fmt->lighting.MaxFALL ? fmt->lighting.MaxFALL : (fmt->lighting.MaxCLL ? fmt->lighting.MaxCLL / 2 : 400));
     ```
   - [`modules/codec/vt_utils.c:522-523`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/codec/vt_utils.c#L522-L523): Synthetic lighting payload when `!has_lighting && is_hdr`:
     ```c
     cta861_3.max_cll = htons(1000); // 1000 nits MaxCLL
     cta861_3.max_fall = htons(400);  // 400 nits MaxFALL
     ```

4. **Hardcoded Subtitle Opacity Clamping and Gamma**:
   - [`modules/video_output/apple/VLCSampleBufferDisplay.m:1159-1160`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/apple/VLCSampleBufferDisplay.m#L1159-L1160): Subtitle reference-white scaling factor is arbitrarily clamped:
     ```objc
     if (factor > 1.0)
         factor = 1.0;
     else if (factor < 0.15)
         factor = 0.15;
     ```
   - [`modules/codec/vt_utils.c:708`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/codec/vt_utils.c#L708): Hardcoded 2.2 gamma for sRGB:
     ```c
     Float32 gamma = 2.2;
     ```

5. **Missing Tone Mapping and Brute-Force SDR Fallbacks**:
   - In [`VLCSampleBufferDisplay.m`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/apple/VLCSampleBufferDisplay.m), VLC contains **no algorithmic tone-mapping** of its own. It relies entirely on Apple's OS compositor (`CADynamicRangeStandard` and `CAToneMapModeAutomatic`).
   - On macOS < 14 under Mode 2, or under Mode 3 (Disable HDR), it performs a brute-force retagging to BT.709 without applying any tonal compression or gamut conversion curve:
     - [`modules/video_output/apple/VLCSampleBufferDisplay.m:1388-1390`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/apple/VLCSampleBufferDisplay.m#L1388-L1390):
       ```objc
       render_fmt.transfer = TRANSFER_FUNC_BT709;
       render_fmt.primaries = COLOR_PRIMARIES_BT709;
       render_fmt.space = COLOR_SPACE_BT709;
       ```
     - [`modules/video_output/apple/VLCSampleBufferDisplay.m:1393-1395`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/apple/VLCSampleBufferDisplay.m#L1393-L1395):
       ```objc
       render_fmt.transfer = TRANSFER_FUNC_BT709;
       render_fmt.primaries = COLOR_PRIMARIES_BT709;
       render_fmt.space = COLOR_SPACE_BT709;
       ```
       This causes severe highlight clipping and desaturation on SDR screens on macOS 10.15–13.

6. **Missing Dolby Vision and HDR10+ Dynamic Metadata in Display Layer**:
   - Neither `VLCSampleBufferDisplay.m` nor `caopengllayer.m` inspects or forwards Dolby Vision RPU metadata or HDR10+ dynamic metadata (`VLC_ANCILLARY_ID_HDR10PLUS`). Any decoded dynamic metadata is dropped before reaching CoreMedia/CoreAnimation.

7. **Incorrect Synthetic Metadata for HLG**:
   - In [`modules/codec/vt_utils.c:441-446`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/codec/vt_utils.c#L441-L446) and [`vt_utils.c:506-512`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/codec/vt_utils.c#L506-L512), HLG content (`TRANSFER_FUNC_HLG`) is identified as `is_hdr`, triggering the attachment of synthetic HDR10 ST 2086 mastering volume and CTA-861.3 light level info. HLG is relative/scene-referred and standard specifications state it should not carry ST 2086 or CTA-861.3 metadata.

8. **Missing Ambient Viewing Environment**:
   - `kCVImageBufferAmbientViewingEnvironment` is never handled anywhere (0 hits).

9. **Stubbed / No-op Branches**:
   - [`modules/video_output/apple/VLCSampleBufferDisplay.m:1647-1650`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/apple/VLCSampleBufferDisplay.m#L1647-L1650):
     ```objc
     static void Display(vout_display_t *vd, picture_t *pic)
     {
         // kept as the core is not properly pacing the calls to Prepare without this callback
     }
     ```
   - [`modules/video_output/caopengllayer.m:547-550`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/caopengllayer.m#L547-L550):
     ```objc
     if (@available(macOS 10.14, *)) {
         // This is intentionally left empty, as the check
         // can not be negated or combined with other conditions!
     } else if (!vd->obj.force) {
         return VLC_EGENERIC;
     }
     ```
   - [`modules/video_output/caopengllayer.m:491-496, 522-527`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/caopengllayer.m#L491-L496): Viewport and aspect ratio callbacks are stubbed out because viewport is applied during rendering.

---

## 4. Debug & Logging Instrumentation Added for HDR

The following logging statements were specifically added in `VLCSampleBufferDisplay.m` and `caopengllayer.m`:

### `modules/video_output/apple/VLCSampleBufferDisplay.m`
- [`VLCSampleBufferDisplay.m:902-904`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/apple/VLCSampleBufferDisplay.m#L902-L904):
  `msg_Dbg(_vd, "Screen parameters changed notification: EDR headroom re-evaluated from %.2f to %.2f", (float)prevHeadroom, (float)_currentHeadroom);`
- [`VLCSampleBufferDisplay.m:911-913`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/apple/VLCSampleBufferDisplay.m#L911-L913):
  `msg_Dbg(_vd, "Window did change screen notification: EDR headroom re-evaluated from %.2f to %.2f", (float)prevHeadroom, (float)_currentHeadroom);`
- [`VLCSampleBufferDisplay.m:920-922`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/apple/VLCSampleBufferDisplay.m#L920-L922):
  `msg_Dbg(_vd, "Window did change screen profile notification: EDR headroom re-evaluated from %.2f to %.2f", (float)prevHeadroom, (float)_currentHeadroom);`
- [`VLCSampleBufferDisplay.m:955`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/apple/VLCSampleBufferDisplay.m#L955):
  `msg_Warn(vd, "NSScreen.maximumExtendedDynamicRangeColorComponentValue unavailable (< macOS 10.15); defaulting screen headroom to 1.0");`
- [`VLCSampleBufferDisplay.m:961`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/apple/VLCSampleBufferDisplay.m#L961):
  `msg_Warn(vd, "SDK max allowed < macOS 10.15; defaulting screen headroom to 1.0");`
- [`VLCSampleBufferDisplay.m:994`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/apple/VLCSampleBufferDisplay.m#L994):
  `msg_Warn(vd, "CALayer.wantsExtendedDynamicRangeContent unavailable (< macOS 10.15); standard layer SDR rendering used");`
- [`VLCSampleBufferDisplay.m:1001`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/apple/VLCSampleBufferDisplay.m#L1001):
  `msg_Warn(vd, "SDK max allowed < macOS 10.15; standard layer SDR rendering used");`
- [`VLCSampleBufferDisplay.m:1015`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/apple/VLCSampleBufferDisplay.m#L1015):
  `msg_Warn(vd, "CALayer.preferredDynamicRange/contentsHeadroom unavailable (< macOS 14); falling back to buffer retagging in render path");`
- [`VLCSampleBufferDisplay.m:1022`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/apple/VLCSampleBufferDisplay.m#L1022):
  `msg_Warn(vd, "SDK max allowed < macOS 14; falling back to buffer retagging in render path");`
- [`VLCSampleBufferDisplay.m:1034`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/apple/VLCSampleBufferDisplay.m#L1034):
  `msg_Warn(vd, "CALayer.toneMapMode unavailable (< macOS 15); relying on CADynamicRangeStandard for compositor tone-mapping");`
- [`VLCSampleBufferDisplay.m:1041`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/apple/VLCSampleBufferDisplay.m#L1041):
  `msg_Warn(vd, "SDK max allowed < macOS 15; relying on CADynamicRangeStandard for compositor tone-mapping");`
- [`VLCSampleBufferDisplay.m:1048-1049`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/apple/VLCSampleBufferDisplay.m#L1048-L1049):
  `msg_Dbg(vd, "HDR mode 2 (tone-map to SDR): preferredDynamicRange=%s, toneMapMode=%s, contentsHeadroom=%.2f, EDR %s", applied_pdr, applied_tmm, applied_headroom, applied_edr);`
- [`VLCSampleBufferDisplay.m:1051-1052`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/apple/VLCSampleBufferDisplay.m#L1051-L1052):
  `msg_Dbg(vd, "HDR mode 3 (disable HDR): preferredDynamicRange=%s, toneMapMode=%s, contentsHeadroom=%.2f, EDR %s", applied_pdr, applied_tmm, applied_headroom, applied_edr);`
- [`VLCSampleBufferDisplay.m:1070`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/apple/VLCSampleBufferDisplay.m#L1070):
  `msg_Warn(vd, "CALayer.wantsExtendedDynamicRangeContent/extendedSRGBColorSpace unavailable (< macOS 10.15); display remains standard dynamic range");`
- [`VLCSampleBufferDisplay.m:1077`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/apple/VLCSampleBufferDisplay.m#L1077):
  `msg_Warn(vd, "SDK max allowed < macOS 10.15; display remains standard dynamic range");`
- [`VLCSampleBufferDisplay.m:1095`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/apple/VLCSampleBufferDisplay.m#L1095):
  `msg_Warn(vd, "CALayer.preferredDynamicRange/contentsHeadroom unavailable (< macOS 14); relying on wantsExtendedDynamicRangeContent");`
- [`VLCSampleBufferDisplay.m:1102`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/apple/VLCSampleBufferDisplay.m#L1102):
  `msg_Warn(vd, "SDK max allowed < macOS 14; relying on wantsExtendedDynamicRangeContent");`
- [`VLCSampleBufferDisplay.m:1114`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/apple/VLCSampleBufferDisplay.m#L1114):
  `msg_Warn(vd, "CALayer.toneMapMode unavailable (< macOS 15); relying on CADynamicRangeHigh");`
- [`VLCSampleBufferDisplay.m:1121`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/apple/VLCSampleBufferDisplay.m#L1121):
  `msg_Warn(vd, "SDK max allowed < macOS 15; relying on CADynamicRangeHigh");`
- [`VLCSampleBufferDisplay.m:1128-1129`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/apple/VLCSampleBufferDisplay.m#L1128-L1129):
  `msg_Dbg(vd, "HDR mode 1 (force EDR/HDR): preferredDynamicRange=%s, toneMapMode=%s, contentsHeadroom=%.2f, EDR %s", applied_pdr, applied_tmm, applied_headroom, applied_edr);`
- [`VLCSampleBufferDisplay.m:1131-1132`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/apple/VLCSampleBufferDisplay.m#L1131-L1132):
  `msg_Dbg(vd, "HDR mode 0 (auto): preferredDynamicRange=%s, toneMapMode=%s, contentsHeadroom=%.2f, EDR %s", applied_pdr, applied_tmm, applied_headroom, applied_edr);`
- [`VLCSampleBufferDisplay.m:1163-1165`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/apple/VLCSampleBufferDisplay.m#L1163-L1165):
  `msg_Dbg(vd, "Subtitle reference-white scale factor computed: %.3f (derived from headroom %.2f, reference white %.0f nits)", (float)factor, (float)effectiveHeadroom, ITU_BT2408_REFERENCE_WHITE_NITS);`
- [`VLCSampleBufferDisplay.m:1254-1255`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/apple/VLCSampleBufferDisplay.m#L1254-L1255):
  `msg_Dbg(sys.vd, "EDR headroom updated via variable callback: %.2f%s", val, (val > 0.0f) ? " (user override)" : " (auto screen peak)");`
- [`VLCSampleBufferDisplay.m:1385-1386`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/apple/VLCSampleBufferDisplay.m#L1385-L1386):
  `msg_Warn(vd, "Hardware tone mapping (CADynamicRangeStandard) unavailable on this OS version (< macOS 14); falling back to BT.709 buffer retagging");`
- [`VLCSampleBufferDisplay.m:1434-1436`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/apple/VLCSampleBufferDisplay.m#L1434-L1436):
  `msg_Dbg(vd, "Applied effective display & buffer configuration: preferredDynamicRange=%s, contentsHeadroom=%.2f, toneMapMode=%s, wantsEDR=%s, buffer[transfer=%s, primaries=%s, matrix=%s]", sys.effectivePdrStr ?: "None", sys.effectiveHeadroomVal, sys.effectiveTmmStr ?: "None", sys.effectiveEdrStr ?: "None", transfer_name, primaries_name, space_name);`
- [`VLCSampleBufferDisplay.m:1755`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/apple/VLCSampleBufferDisplay.m#L1755):
  `msg_Dbg(vd, "EDR headroom initialized to user override: %.2f", user_headroom);`
- [`VLCSampleBufferDisplay.m:1757`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/apple/VLCSampleBufferDisplay.m#L1757):
  `msg_Dbg(vd, "EDR headroom initialized to auto (display peak)");`

### `modules/video_output/caopengllayer.m`
- [`caopengllayer.m:300-302`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/caopengllayer.m#L300-L302):
  `msg_Dbg(gl, "Created CGL context with %s profile, %d-bit color (%d-bit alpha)", success_profile, success_color, success_alpha);`
- [`caopengllayer.m:594-600`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/caopengllayer.m#L594-L600):
  `msg_Dbg(vd, "HDR mastering display: primaries [R: %.4f, %.4f, G: %.4f, %.4f, B: %.4f, %.4f], white point [%.4f, %.4f], min/max luminance [%u, %u]", fmt->mastering.primaries[4] / 50000.0, fmt->mastering.primaries[5] / 50000.0, ...);`
- [`caopengllayer.m:602-604`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/caopengllayer.m#L602-L604):
  `msg_Dbg(vd, "HDR content light level: MaxCLL %u cd/m², MaxFALL %u cd/m²", fmt->lighting.MaxCLL, fmt->lighting.MaxFALL);`

---

## 5. Fragile or Problematic Code

1. [`modules/video_output/apple/VLCSampleBufferDisplay.m:1404-1405`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/apple/VLCSampleBufferDisplay.m#L1404-L1405): Mutating attachments on `pixelBuffer` directly modifies pool buffers allocated by VideoToolbox, potentially polluting subsequent reused frames or other consumers.
2. [`modules/video_output/apple/VLCSampleBufferDisplay.m:1364`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/apple/VLCSampleBufferDisplay.m#L1364): Calling `var_InheritInteger(vd, "macosx-hdr-mode")` on every single frame in `RenderPicture()` adds unnecessary variable tree traversal on the time-critical display thread instead of reading a cached property.
3. [`modules/video_output/apple/VLCSampleBufferDisplay.m:1366-1371`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/apple/VLCSampleBufferDisplay.m#L1366-L1371): Mode 1 (Force Native EDR / HDR) blindly forces `TRANSFER_FUNC_SMPTE_ST2084` and `COLOR_PRIMARIES_BT2020` on any non-HLG stream, corrupting standard SDR content into extreme high-contrast, clipped, and dark playback.
4. [`modules/video_output/apple/VLCSampleBufferDisplay.m:1388-1390`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/apple/VLCSampleBufferDisplay.m#L1388-L1390): Mode 2 on macOS < 14 retags HDR buffers as BT.709 without applying any gamut or tone curve compression, falsely reporting tone mapping while delivering washed-out colors.
5. [`modules/codec/vt_utils.c:477-478`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/codec/vt_utils.c#L477-L478): Heuristically scaling `max_luminance *= 10000` when `max_luminance < 10000` is fragile because VLC defines `max_luminance` in 0.0001 nit units, so valid low mastering targets (<1 nit) get corrupted.
6. [`modules/codec/vt_utils.c:464-471`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/codec/vt_utils.c#L464-L471): Checking only `st2086.display_primaries[0][0] == 0` (Green.x) to default all primaries causes silent partial zeroing if green is present but red or blue primaries are missing.
7. [`modules/codec/vt_utils.c:482-494, 522-524`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/codec/vt_utils.c#L482-L494): Attaching synthetic 1000-nit HDR10 mastering and CTA-861.3 content light levels to HLG streams violates the HLG specification, as HLG is scene-referred and has no static mastering volume.
8. [`modules/video_output/caopengllayer.m:606-609`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/caopengllayer.m#L606-L609): `caopengllayer` checks only transfer function equality for ST 2084 or HLG, failing to treat BT.2020 wide-gamut streams with custom mastering metadata as HDR.
9. [`modules/video_output/caopengllayer.m:961-965`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/caopengllayer.m#L961-L965): Unconditionally tagging the layer colorspace as `kCGColorSpaceExtendedLinearDisplayP3` forces the OS compositor to run linear Extended P3 conversions even for standard SDR BT.709 video.
10. [`modules/video_output/caopengllayer.m:1001-1012`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/caopengllayer.m#L1001-L1012): `caopengllayer` completely ignores the `macosx-hdr-mode` configuration variable, so user preferences (Disable HDR, Force Tone-Map to SDR) have no effect in this module.
11. [`modules/video_output/apple/VLCSampleBufferDisplay.m:1156`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/apple/VLCSampleBufferDisplay.m#L1156): Dividing 203 nits by `(100.0f * effectiveHeadroom)` results in factors > 1.0 for any screen with headroom <= 2.03, meaning subtitle dimming only begins to take effect above 2.03x headroom (~400 nits) and does nothing on lower-headroom displays.
12. [`modules/video_output/apple/VLCSampleBufferDisplay.m:1463-1472`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/apple/VLCSampleBufferDisplay.m#L1463-L1472): Computing presentation timestamps with `CACurrentMediaTime()` using microsecond scale instead of CoreMedia's native host clock (`CMClockGetHostTimeClock()`) risks clock drift against CoreAudio output.
13. [`modules/video_output/apple/VLCSampleBufferDisplay.m:846-868`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/apple/VLCSampleBufferDisplay.m#L846-L868): Asynchronously initializing `sys.displayLayer` on the main dispatch queue creates a race condition where initial frames reaching `RenderPicture` on the vout thread find `sys.displayLayer == nil` and are dropped silently ([`VLCSampleBufferDisplay.m:1321-1322`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/apple/VLCSampleBufferDisplay.m#L1321-L1322)).
14. [`modules/video_output/apple/VLCSampleBufferDisplay.m:1531-1534`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/apple/VLCSampleBufferDisplay.m#L1531-L1534): Creating `CGImageRef` with `kCGBitmapByteOrderDefault | kCGImageAlphaFirst` assumes host byte order matches CoreGraphics ARGB memory layout, risking inverted color channels across architectures.
15. [`modules/video_output/apple/VLCSampleBufferDisplay.m:1225`](file:///Users/omarbenmustapha/Downloads/vlc-master/modules/video_output/apple/VLCSampleBufferDisplay.m#L1225): Calling `[[NSNotificationCenter defaultCenter] removeObserver:self]` during module close without synchronizing the asynchronous UI teardown can leak notifications or trigger selectors during deallocation.

---

## 6. Complete Grep Inventory

### `CAEDRMetadata`
*0 hits across the entire tree.*

---

### `wantsExtendedDynamicRangeContent` (17 hits)
- `modules/gui/macosx/windows/video/VLCVoutView.m:108`
- `modules/gui/macosx/windows/video/VLCVoutView.m:124`
- `modules/video_output/apple/VLCSampleBufferDisplay.m:598`
- `modules/video_output/apple/VLCSampleBufferDisplay.m:684`
- `modules/video_output/apple/VLCSampleBufferDisplay.m:986`
- `modules/video_output/apple/VLCSampleBufferDisplay.m:987`
- `modules/video_output/apple/VLCSampleBufferDisplay.m:989`
- `modules/video_output/apple/VLCSampleBufferDisplay.m:994`
- `modules/video_output/apple/VLCSampleBufferDisplay.m:1059`
- `modules/video_output/apple/VLCSampleBufferDisplay.m:1061`
- `modules/video_output/apple/VLCSampleBufferDisplay.m:1065`
- `modules/video_output/apple/VLCSampleBufferDisplay.m:1070`
- `modules/video_output/apple/VLCSampleBufferDisplay.m:1095`
- `modules/video_output/apple/VLCSampleBufferDisplay.m:1102`
- `modules/video_output/apple/VLCSampleBufferDisplay.m:1146`
- `modules/video_output/caopengllayer.m:960`
- `modules/video_output/caopengllayer.m:994`

---

### `maximumExtendedDynamicRangeContentHeadroom`
*0 hits across the entire tree.* (Note: the macOS API used in the codebase is `maximumExtendedDynamicRangeColorComponentValue`, which appears at `VLCSampleBufferDisplay.m:692, 693, 948, 955`, `caopengllayer.m:774, 775, 974, 975`, and `VLCSimplePrefsController.m:881`).

---

### `EDR` (75 hits)
- `doc/libvlc/d3d11_player.cpp:724`
- `doc/libvlc/d3d9_player.c:392`
- `modules/codec/avcodec/video.c:109`
- `modules/codec/avcodec/video.c:110`
- `modules/codec/avcodec/video.c:111`
- `modules/codec/avcodec/video.c:695`
- `modules/codec/avcodec/video.c:1008`
- `modules/codec/avcodec/video.c:1031`
- `modules/codec/avcodec/video.c:1037`
- `modules/codec/avcodec/video.c:1039`
- `modules/codec/avcodec/video.c:1045`
- `modules/codec/avcodec/video.c:1049`
- `modules/codec/avcodec/video.c:1421`
- `modules/codec/avcodec/video.c:1757`
- `modules/demux/adaptive/SharedResources.hpp:20`
- `modules/demux/adaptive/SharedResources.hpp:21`
- `modules/gui/macosx/main/macosx.m:173`
- `modules/gui/macosx/main/macosx.m:174`
- `modules/gui/macosx/main/macosx.m:178`
- `modules/gui/macosx/main/macosx.m:179`
- `modules/gui/macosx/main/macosx.m:184`
- `modules/gui/macosx/main/macosx.m:185`
- `modules/gui/macosx/main/macosx.m:196`
- `modules/gui/macosx/preferences/VLCSimplePrefsController.h:208`
- `modules/gui/macosx/preferences/VLCSimplePrefsController.m:543`
- `modules/gui/macosx/preferences/VLCSimplePrefsController.m:544`
- `modules/gui/macosx/preferences/VLCSimplePrefsController.m:546`
- `modules/gui/macosx/preferences/VLCSimplePrefsController.m:862`
- `modules/gui/macosx/preferences/VLCSimplePrefsController.m:865`
- `modules/gui/macosx/preferences/VLCSimplePrefsController.m:867`
- `modules/gui/macosx/preferences/VLCSimplePrefsController.m:881`
- `modules/gui/macosx/preferences/VLCSimplePrefsController.m:882`
- `modules/gui/macosx/preferences/VLCSimplePrefsController.m:883`
- `modules/gui/macosx/preferences/VLCSimplePrefsController.m:885`
- `modules/gui/qt/maininterface/mainctx_win32.cpp:253`
- `modules/gui/skins2/os2/os2_factory.cpp:184`
- `modules/video_output/apple/VLCSampleBufferDisplay.m:51`
- `modules/video_output/apple/VLCSampleBufferDisplay.m:558`
- `modules/video_output/apple/VLCSampleBufferDisplay.m:801`
- `modules/video_output/apple/VLCSampleBufferDisplay.m:902`
- `modules/video_output/apple/VLCSampleBufferDisplay.m:911`
- `modules/video_output/apple/VLCSampleBufferDisplay.m:920`
- `modules/video_output/apple/VLCSampleBufferDisplay.m:993`
- `modules/video_output/apple/VLCSampleBufferDisplay.m:995`
- `modules/video_output/apple/VLCSampleBufferDisplay.m:1000`
- `modules/video_output/apple/VLCSampleBufferDisplay.m:1002`
- `modules/video_output/apple/VLCSampleBufferDisplay.m:1048`
- `modules/video_output/apple/VLCSampleBufferDisplay.m:1051`
- `modules/video_output/apple/VLCSampleBufferDisplay.m:1055`
- `modules/video_output/apple/VLCSampleBufferDisplay.m:1069`
- `modules/video_output/apple/VLCSampleBufferDisplay.m:1071`
- `modules/video_output/apple/VLCSampleBufferDisplay.m:1076`
- `modules/video_output/apple/VLCSampleBufferDisplay.m:1078`
- `modules/video_output/apple/VLCSampleBufferDisplay.m:1128`
- `modules/video_output/apple/VLCSampleBufferDisplay.m:1131`
- `modules/video_output/apple/VLCSampleBufferDisplay.m:1254`
- `modules/video_output/apple/VLCSampleBufferDisplay.m:1366`
- `modules/video_output/apple/VLCSampleBufferDisplay.m:1399`
- `modules/video_output/apple/VLCSampleBufferDisplay.m:1403`
- `modules/video_output/apple/VLCSampleBufferDisplay.m:1434`
- `modules/video_output/apple/VLCSampleBufferDisplay.m:1755`
- `modules/video_output/apple/VLCSampleBufferDisplay.m:1757`
- `modules/video_output/apple/VLCSampleBufferDisplay.m:1800`
- `modules/video_output/apple/VLCSampleBufferDisplay.m:1801`
- `modules/video_output/apple/VLCSampleBufferDisplay.m:1805`
- `modules/video_output/apple/VLCSampleBufferDisplay.m:1806`
- `modules/video_output/apple/VLCSampleBufferDisplay.m:1811`
- `modules/video_output/apple/VLCSampleBufferDisplay.m:1812`
- `modules/video_output/apple/VLCSampleBufferDisplay.m:1833`
- `modules/video_output/kva.c:222`
- `modules/video_output/window_os2.c:511`
- `src/libvlc-module.c:692`
- `src/libvlc-module.c:693`
- `src/libvlc-module.c:1875`
- `src/libvlc-module.c:1876`

---

### `kCVImageBufferTransferFunction` (19 hits)
- `modules/codec/videotoolbox/decoder.c:1083`
- `modules/codec/vt_utils.c:373`
- `modules/codec/vt_utils.c:377`
- `modules/codec/vt_utils.c:378`
- `modules/codec/vt_utils.c:380`
- `modules/codec/vt_utils.c:382`
- `modules/codec/vt_utils.c:385`
- `modules/codec/vt_utils.c:393`
- `modules/codec/vt_utils.c:397`
- `modules/codec/vt_utils.c:596`
- `modules/codec/vt_utils.c:599`
- `modules/codec/vt_utils.c:601`
- `modules/codec/vt_utils.c:603`
- `modules/codec/vt_utils.c:606`
- `modules/codec/vt_utils.c:609`
- `modules/codec/vt_utils.c:612`
- `modules/codec/vt_utils.c:700`
- `modules/codec/vt_utils.h:101`
- `modules/codec/vt_utils.h:123`

---

### `kCVImageBufferColorPrimaries` (14 hits)
- `modules/codec/videotoolbox/decoder.c:1073`
- `modules/codec/vt_utils.c:348`
- `modules/codec/vt_utils.c:350`
- `modules/codec/vt_utils.c:352`
- `modules/codec/vt_utils.c:354`
- `modules/codec/vt_utils.c:580`
- `modules/codec/vt_utils.c:583`
- `modules/codec/vt_utils.c:585`
- `modules/codec/vt_utils.c:587`
- `modules/codec/vt_utils.c:589`
- `modules/codec/vt_utils.c:592`
- `modules/codec/vt_utils.c:689`
- `modules/codec/vt_utils.h:91`
- `modules/codec/vt_utils.h:123`

---

### `kCVImageBufferYCbCrMatrix` (11 hits)
- `modules/codec/videotoolbox/decoder.c:1064`
- `modules/codec/vt_utils.c:324`
- `modules/codec/vt_utils.c:327`
- `modules/codec/vt_utils.c:330`
- `modules/codec/vt_utils.c:568`
- `modules/codec/vt_utils.c:571`
- `modules/codec/vt_utils.c:573`
- `modules/codec/vt_utils.c:576`
- `modules/codec/vt_utils.c:678`
- `modules/codec/vt_utils.h:81`
- `modules/codec/vt_utils.h:122`

---

### `kCVImageBufferMasteringDisplayColorVolume` (4 hits)
- `modules/codec/videotoolbox/decoder.c:1107`
- `modules/codec/vt_utils.c:541`
- `modules/codec/vt_utils.c:619`
- `modules/codec/vt_utils.h:124`

---

### `kCVImageBufferContentLightLevel` (4 hits)
- `modules/codec/videotoolbox/decoder.c:1116`
- `modules/codec/vt_utils.c:549`
- `modules/codec/vt_utils.c:637`
- `modules/codec/vt_utils.h:124`

---

### `kCVImageBufferAmbientViewingEnvironment`
*0 hits across the entire tree.*

---

### `HDR10` (19 hits)
- `NEWS:1989`
- `include/vlc_ancillary.h:279`
- `include/vlc_ancillary.h:287`
- `include/vlc_opengl_filter.h:49`
- `modules/codec/avcodec/video.c:1348`
- `modules/codec/omxil/utils.c:1175`
- `modules/codec/vt_utils.c:482`
- `modules/video_output/libplacebo/display.c:263`
- `modules/video_output/libplacebo/display.c:500`
- `modules/video_output/libplacebo/utils.h:42`
- `modules/video_output/libplacebo/utils.h:202`
- `modules/video_output/libplacebo/utils.h:209`
- `modules/video_output/libplacebo/utils.h:216`
- `modules/video_output/opengl/filters.c:146`
- `modules/video_output/opengl/filters.c:553`
- `modules/video_output/opengl/filters.c:557`
- `modules/video_output/win32/dxgi_swapchain.cpp:87`
- `modules/video_output/win32/dxgi_swapchain.cpp:375`
- `modules/video_output/win32/dxgi_swapchain.cpp:391`

---

### `PQ` (102 hits)
- `include/vlc/libvlc_media_player.h:846`
- `include/vlc_ancillary.h:251`
- `lib/media_player.c:2619`
- `m4/lib-link.m4:23`
- `m4/lib-link.m4:63`
- `m4/lib-link.m4:164`
- `m4/lib-link.m4:169`
- `m4/lib-link.m4:185`
- `m4/lib-link.m4:188`
- `m4/lib-link.m4:254`
- `m4/lib-link.m4:260`
- `m4/lib-link.m4:281`
- `m4/lib-link.m4:297`
- `m4/lib-link.m4:300`
- `m4/lib-link.m4:309`
- `m4/lib-link.m4:320`
- `m4/lib-link.m4:343`
- `m4/lib-link.m4:349`
- `m4/lib-link.m4:354`
- `m4/lib-link.m4:373`
- `m4/lib-link.m4:389`
- `m4/lib-link.m4:392`
- `m4/lib-link.m4:401`
- `m4/lib-link.m4:412`
- `m4/lib-link.m4:629`
- `m4/lib-link.m4:631`
- `m4/lib-link.m4:648`
- `m4/lib-link.m4:650`
- `m4/lib-link.m4:667`
- `m4/lib-link.m4:669`
- `m4/lib-link.m4:686`
- `m4/lib-link.m4:688`
- `modules/demux/mkv/matroska_segment_parse.cpp:843`
- `modules/gui/macosx/UI/MainMenu.xib:1073`
- `modules/gui/macosx/UI/Open.xib:41`
- `modules/gui/macosx/UI/VLCLibraryWindowPlayQueueView.xib:187`
- `modules/gui/macosx/UI/VLCStatusBarIconMainMenu.xib:51`
- `modules/video_output/apple/VLCSampleBufferDisplay.m:49`
- `modules/video_output/apple/VLCSampleBufferDisplay.m:1377`
- `modules/video_output/apple/VLCSampleBufferDisplay.m:1411`
- `modules/video_output/libplacebo/utils.c:529`
- `modules/video_output/libplacebo/utils.h:156`
- `modules/video_output/libplacebo/utils.h:216`
- `modules/video_output/win32/d3d_shaders.c:46`
- `po/ca.po:14145`
- `po/ca.po:14166`
- `po/ca.po:14174`
- `po/ca.po:14182`
- `po/ca.po:14186`
- `po/ca.po:14260`
- `po/ca.po:14264`
- `po/ca.po:14268`
- `po/ca.po:14272`
- `po/ca.po:14276`
- `po/ca.po:14280`
- `po/ca.po:14300`
- `po/ca.po:14304`
- `po/ca.po:14308`
- `po/ca.po:14315`
- `po/ca.po:14323`
- `po/ca.po:36025`
- `po/ca.po:41352`
- `po/ca@valencia.po:13908`
- `po/ca@valencia.po:13929`
- `po/ca@valencia.po:13937`
- `po/ca@valencia.po:13945`
- `po/ca@valencia.po:13949`
- `po/ca@valencia.po:14023`
- `po/ca@valencia.po:14027`
- `po/ca@valencia.po:14031`
- `po/ca@valencia.po:14035`
- `po/ca@valencia.po:14039`
- `po/ca@valencia.po:14043`
- `po/ca@valencia.po:14063`
- `po/ca@valencia.po:14067`
- `po/ca@valencia.po:14071`
- `po/ca@valencia.po:14078`
- `po/ca@valencia.po:14086`
- `src/input/es_out.c:4719`
- `test/src/misc/cvpx_hdr_metadata.c:41`
- `test/src/misc/cvpx_hdr_metadata.c:97`

---

### `HLG` (68 hits)
- `NEWS:1376`
- `NEWS:1708`
- `include/vlc/libvlc_media_player.h:848`
- `include/vlc_es.h:283`
- `include/vlc_es.h:289`
- `include/vlc_es.h:290`
- `lib/media_player.c:2621`
- `modules/codec/dvbsub.c:327`
- `modules/codec/dvbsub.c:1118`
- `modules/codec/dvbsub.c:1805`
- `modules/codec/dvbsub.c:1817`
- `modules/codec/dvbsub.c:1820`
- `modules/codec/dvbsub.c:1823`
- `modules/codec/dvbsub.c:1826`
- `modules/codec/dvbsub.c:1829`
- `modules/codec/dvbsub.c:1832`
- `modules/codec/dvbsub.c:1835`
- `modules/codec/dvbsub.c:1838`
- `modules/codec/dvbsub.c:1841`
- `modules/codec/dvbsub.c:1844`
- `modules/codec/dvbsub.c:1847`
- `modules/codec/dvbsub.c:1850`
- `modules/codec/dvbsub.c:1853`
- `modules/codec/dvbsub.c:1856`
- `modules/codec/dvbsub.c:1859`
- `modules/codec/dvbsub.c:1862`
- `modules/codec/dvbsub.c:1865`
- `modules/codec/dvbsub.c:1868`
- `modules/codec/dvbsub.c:1871`
- `modules/codec/dvbsub.c:1874`
- `modules/codec/dvbsub.c:1877`
- `modules/codec/dvbsub.c:1880`
- `modules/codec/dvbsub.c:1883`
- `modules/codec/dvbsub.c:1886`
- `modules/codec/dvbsub.c:1889`
- `modules/codec/dvbsub.c:1892`
- `modules/codec/dvbsub.c:1895`
- `modules/codec/dvbsub.c:1898`
- `modules/codec/dvbsub.c:1901`
- `modules/codec/dvbsub.c:1904`
- `modules/codec/dvbsub.c:1907`
- `modules/codec/dvbsub.c:1910`
- `modules/codec/dvbsub.c:1913`
- `modules/codec/dvbsub.c:1916`
- `modules/codec/dvbsub.c:1919`
- `modules/codec/dvbsub.c:1922`
- `modules/codec/dvbsub.c:1925`
- `modules/codec/dvbsub.c:1928`
- `modules/codec/dvbsub.c:1931`
- `modules/demux/mkv/matroska_segment_parse.cpp:845`
- `modules/packetizer/iso_color_tables.h:104`
- `modules/video_output/apple/VLCSampleBufferDisplay.m:49`
- `modules/video_output/apple/VLCSampleBufferDisplay.m:1377`
- `modules/video_output/apple/VLCSampleBufferDisplay.m:1412`
- `modules/video_output/libplacebo/utils.h:157`
- `modules/video_output/libplacebo/utils.h:217`
- `modules/video_output/opengl/sampler.c:957`
- `modules/video_output/win32/dxgi_swapchain.cpp:124`
- `modules/video_output/win32/dxgi_swapchain.cpp:125`
- `modules/video_output/win32/dxgi_swapchain.cpp:172`
- `test/src/misc/cvpx_hdr_metadata.c:102`
- `test/src/misc/cvpx_hdr_metadata.c:158`

---

### `transfer_func` (91 hits)
- `doc/libvlc/QtGL/qtvlcwidget.cpp:145`
- `doc/libvlc/d3d11_player.cpp:439`
- `doc/libvlc/d3d9_player.c:143`
- `doc/libvlc/sdl_opengl_player.cpp:157`
- `include/vlc/libvlc_media_player.h:840`
- `include/vlc/libvlc_media_player.h:841`
- `include/vlc/libvlc_media_player.h:842`
- `include/vlc/libvlc_media_player.h:843`
- `include/vlc/libvlc_media_player.h:844`
- `include/vlc/libvlc_media_player.h:845`
- `include/vlc/libvlc_media_player.h:846`
- `include/vlc/libvlc_media_player.h:847`
- `include/vlc/libvlc_media_player.h:848`
- `include/vlc/libvlc_media_player.h:849`
- `include/vlc/libvlc_media_player.h:1095`
- `include/vlc/libvlc_media_player.h:1129`
- `include/vlc_es.h:273`
- `include/vlc_es.h:291`
- `include/vlc_es.h:355`
- `lib/media_player.c:2613`
- `lib/media_player.c:2614`
- `lib/media_player.c:2615`
- `lib/media_player.c:2616`
- `lib/media_player.c:2617`
- `lib/media_player.c:2618`
- `lib/media_player.c:2619`
- `lib/media_player.c:2620`
- `lib/media_player.c:2621`
- `modules/codec/hxxx_helper.c:916`
- `modules/codec/hxxx_helper.h:130`
- `modules/codec/hxxx_helper_testdec.c:57`
- `modules/codec/jpeg2000.h:98`
- `modules/codec/jpeg2000.h:129`
- `modules/codec/jpeg2000.h:142`
- `modules/codec/omxil/mediacodec.c:556`
- `modules/codec/omxil/mediacodec.c:575`
- `modules/codec/videotoolbox/decoder.c:474`
- `modules/codec/videotoolbox/decoder.c:1078`
- `modules/codec/videotoolbox/decoder.c:1080`
- `modules/codec/videotoolbox/decoder.c:1084`
- `modules/codec/vpx.c:152`
- `modules/codec/vt_utils.c:368`
- `modules/codec/vt_utils.c:370`
- `modules/codec/vt_utils.c:403`
- `modules/codec/vt_utils.c:662`
- `modules/codec/vt_utils.c:695`
- `modules/codec/vt_utils.c:697`
- `modules/codec/vt_utils.c:701`
- `modules/codec/vt_utils.h:102`
- `modules/codec/vt_utils.h:104`
- `modules/codec/vt_utils.h:108`
- `modules/demux/mkv/vlc_colors.c:17`
- `modules/demux/mkv/vlc_colors.h:18`
- `modules/demux/mp4/essetup.c:506`
- `modules/demux/mp4/heif.c:441`
- `modules/demux/mp4/libmp4.c:4125`
- `modules/demux/mp4/libmp4.h:722`
- `modules/hw/nvdec/nvdec.c:906`
- `modules/packetizer/av1.c:143`
- `modules/packetizer/av1_obu.c:561`
- `modules/packetizer/av1_obu.h:167`
- `modules/packetizer/h264_nal.c:990`
- `modules/packetizer/h264_nal.h:238`
- `modules/packetizer/h266_nal.c:1177`
- `modules/packetizer/h266_nal.h:155`
- `modules/packetizer/h26x_nal_common.h:171`
- `modules/packetizer/hevc_nal.c:1149`
- `modules/packetizer/hevc_nal.h:303`
- `modules/packetizer/iso_color_tables.h:107`
- `modules/packetizer/iso_color_tables.h:130`
- `modules/packetizer/iso_color_tables.h:137`
- `modules/video_output/apple/VLCSampleBufferDisplay.m:1408`
- `modules/video_output/apple/VLCSampleBufferDisplay.m:1409`
- `modules/video_output/apple/VLCSampleBufferDisplay.m:1410`
- `modules/video_output/apple/VLCSampleBufferDisplay.m:1411`
- `modules/video_output/apple/VLCSampleBufferDisplay.m:1412`
- `modules/video_output/apple/VLCSampleBufferDisplay.m:1413`
- `modules/video_output/apple/VLCSampleBufferDisplay.m:1414`
- `modules/video_output/apple/VLCSampleBufferDisplay.m:1415`
- `modules/video_output/apple/VLCSampleBufferDisplay.m:1436`
- `modules/video_output/vgl.c:93`
- `modules/video_output/vgl.c:100`
- `modules/video_output/vgl.c:113`
- `modules/video_output/win32/d3d11_shaders.cpp:39`
- `modules/video_output/win32/d3d11_shaders.h:75`
- `modules/video_output/win32/d3d_dynamic_shader.c:419`
- `modules/video_output/win32/d3d_dynamic_shader.c:556`
- `modules/video_output/win32/d3d_dynamic_shader.h:35`
- `modules/video_output/win32/d3d_shaders.h:41`
- `modules/video_output/win32/direct3d11.cpp:218`
- `modules/video_output/win32/direct3d11.cpp:227`
- `modules/video_output/win32/direct3d11.cpp:266`
- `modules/video_output/win32/direct3d11.cpp:314`
- `modules/video_output/win32/direct3d9.c:519`
- `modules/video_output/win32/direct3d9.c:1724`
- `modules/video_output/win32/dxgi_swapchain.cpp:63`
- `modules/video_output/win32/dxgi_swapchain.cpp:171`
- `modules/video_output/win32/dxgi_swapchain.cpp:173`
- `modules/video_output/win32/dxgi_swapchain.cpp:231`
- `modules/video_output/win32/dxgi_swapchain.cpp:435`

---

### `primaries` (562 hits total; 451 code hits, 111 po hits)
*Code hits:*
- `doc/libvlc/QtGL/qtvlcwidget.cpp:144`
- `doc/libvlc/d3d11_player.cpp:438`
- `doc/libvlc/d3d9_player.c:142`
- `doc/libvlc/sdl_opengl_player.cpp:156`
- `include/vlc/libvlc_media_player.h:817, 819, 820, 821, 822, 823, 824, 825, 826, 827, 828, 829, 830, 831, 832, 1094, 1128, 1205`
- `include/vlc_es.h:239, 264, 353, 368`
- `lib/media_player.c:2598, 2599, 2600, 2601, 2602, 2603, 2604, 2605, 2606, 2607, 2608, 2609, 2610, 2611`
- `modules/codec/avcodec/video.c:420, 1199, 1208, 1209, 1210, 1211, 1212`
- `modules/codec/dav1d.c:176, 178, 542`
- `modules/codec/hxxx_helper.c:915`
- `modules/codec/hxxx_helper.h:129`
- `modules/codec/hxxx_helper_testdec.c:56`
- `modules/codec/jpeg2000.h:97, 128, 141`
- `modules/codec/omxil/mediacodec.c:509, 532`
- `modules/codec/videotoolbox/decoder.c:473, 1069, 1071, 1075, 1109, 2297`
- `modules/codec/vpx.c:151`
- `modules/codec/vt_utils.c:344, 346, 360, 443, 449, 456, 457, 458, 459, 460, 461, 464, 465, 466, 467, 468, 469, 470, 482, 484, 485, 486, 487, 488, 489, 508, 580, 581, 582, 584, 586, 588, 590, 592, 593, 625, 626, 627, 628, 629, 630, 657, 661, 667, 668, 685, 687, 691, 723`
- `modules/codec/vt_utils.h:92, 94, 98, 123`
- `modules/demux/mkv/matroska_segment_parse.cpp:943, 944, 945, 946, 947, 948, 949`
- `modules/demux/mkv/vlc_colors.c:5`
- `modules/demux/mkv/vlc_colors.h:6`
- `modules/demux/mp4/essetup.c:505, 775, 776, 777`
- `modules/demux/mp4/heif.c:440, 447`
- `modules/demux/mp4/libmp4.c:4124`
- `modules/demux/mp4/libmp4.h:721`
- `modules/hw/nvdec/nvdec.c:905`
- `modules/misc/preparser_serializer/json/fromjson.c:647, 648, 649, 650, 651, 652`
- `modules/misc/preparser_serializer/json/tojson.c:560, 561, 562, 563, 564, 565`
- `modules/mux/mp4/libmp4mux.c:1062, 1063, 1064`
- `modules/packetizer/av1.c:142`
- `modules/packetizer/av1_obu.c:560`
- `modules/packetizer/av1_obu.h:167`
- `modules/packetizer/h264_nal.c:989`
- `modules/packetizer/h264_nal.h:237`
- `modules/packetizer/h266.c:1357, 1358, 1359, 1360, 1361, 1362`
- `modules/packetizer/h266_nal.c:1176`
- `modules/packetizer/h266_nal.h:154`
- `modules/packetizer/h26x_nal_common.h:170`
- `modules/packetizer/hevc.c:1117, 1118, 1119, 1120, 1121, 1122`
- `modules/packetizer/hevc_nal.c:1148`
- `modules/packetizer/hevc_nal.h:302`
- `modules/packetizer/iso_color_tables.h:7, 57, 79`
- `modules/text_renderer/freetype/freetype.c:1196`
- `modules/video_output/apple/VLCSampleBufferDisplay.m:455, 1355, 1356, 1369, 1389, 1394, 1418, 1419, 1420, 1421, 1422, 1423, 1436`
- `modules/video_output/caopengllayer.m:594, 595, 596, 597`
- `modules/video_output/libplacebo/display.c:343, 344, 481, 484, 485, 486, 487, 488, 489, 501, 505, 868`
- `modules/video_output/libplacebo/utils.c:364, 392, 396, 397, 398, 399, 400, 401, 531`
- `modules/video_output/libplacebo/utils.h:87, 88, 119, 125`
- `modules/video_output/opengl/interop_aimage.c:441`
- `modules/video_output/opengl/interop_asurface.c:252`
- `modules/video_output/opengl/pl_scale.c:316`
- `modules/video_output/opengl/sampler.c:865, 955, 1262`
- `modules/video_output/vgl.c:92, 99, 112`
- `modules/video_output/win32/d3d_shaders.c:65, 69, 176, 185, 187, 189, 191, 193, 195, 209, 211, 230, 233, 237, 238, 240, 241, 583, 586`
- `modules/video_output/win32/d3d_shaders.h:40`
- `modules/video_output/win32/direct3d11.cpp:216, 225, 264, 315, 339, 1084, 1085, 1086, 1087, 1088, 1089, 1492`
- `modules/video_output/win32/direct3d9.c:517, 1723`
- `modules/video_output/win32/dxgi_swapchain.cpp:62, 135, 167, 232, 434`
- `src/input/decoder.c:961, 962`
- `src/input/es_out.c:4701, 4829, 4830, 4832, 4833, 4836, 4837, 4839, 4840, 4843, 4844, 4846, 4847`
- `test/src/misc/cvpx_hdr_metadata.c:34, 46, 70, 77, 86, 87, 88, 89, 90, 91, 107, 131, 138, 147, 148, 149, 150, 151, 152, 168, 199, 206, 215, 216, 217, 218, 219, 220`
*PO translation hits (111 hits):* `po/ca.po:14115, 14125`, `po/ca@valencia.po:13878, 13888`, and corresponding entries in `.po` files for all language catalogs.

---

### `mastering` (231 hits)
- `include/vlc/libvlc_media_player.h:1204`
- `include/vlc_ancillary.h:281`
- `include/vlc_es.h:366, 371`
- `modules/codec/avcodec/video.c:43, 421, 422, 1200, 1202, 1214, 1215, 1216, 1217, 1218, 1219, 1220, 1221, 1222, 1223, 1224, 1226, 1227`
- `modules/codec/dav1d.c:177, 180, 543`
- `modules/codec/videotoolbox/decoder.c:1100, 1102, 1104, 1106, 1107, 2298`
- `modules/codec/vt_utils.c:436, 437, 438, 439, 455, 456, 457, 458, 459, 460, 461, 462, 463, 477, 480, 482, 541, 619, 625, 626, 627, 628, 629, 630, 631, 632, 633, 634, 657`
- `modules/codec/vt_utils.h:124, 135, 137, 151`
- `modules/demux/mkv/matroska_segment_parse.cpp:943, 944, 945, 946, 947, 948, 951, 952, 959, 960`
- `modules/demux/mp4/essetup.c:775, 776, 777, 778, 779, 780`
- `modules/demux/mp4/heif.c:447`
- `modules/misc/preparser_serializer/json/fromjson.c:646, 647, 648, 649, 650, 651, 652, 653`
- `modules/misc/preparser_serializer/json/tojson.c:558, 559, 560, 561, 562, 563, 564, 565`
- `modules/mux/mp4/libmp4mux.c:1060, 1061, 1062, 1063, 1064, 1065, 1066`
- `modules/packetizer/h266.c:1357, 1358, 1359, 1360, 1361, 1362, 1365, 1366`
- `modules/packetizer/hevc.c:1117, 1118, 1119, 1120, 1121, 1122, 1123, 1124`
- `modules/text_renderer/freetype/freetype.c:1197`
- `modules/video_output/apple/VLCSampleBufferDisplay.m:1359, 1360`
- `modules/video_output/caopengllayer.m:588, 589, 593, 594, 595, 596, 597, 598, 599`
- `modules/video_output/libplacebo/display.c:484, 485, 486, 487, 488, 489, 490, 491, 492, 493`
- `modules/video_output/libplacebo/utils.c:396, 397, 398, 399, 400, 401, 402, 403, 405, 406, 407, 408`
- `modules/video_output/win32/direct3d11.cpp:1024, 1081, 1084, 1085, 1086, 1087, 1088, 1089, 1090, 1091, 1092, 1093`
- `modules/video_output/win32/direct3d9.c:1755`
- `src/input/decoder.c:966, 967, 968, 970`
- `src/input/es_out.c:4819, 4821, 4822, 4824, 4826, 4827, 4829, 4830, 4832, 4833, 4836, 4837, 4839, 4840, 4843, 4844, 4846, 4847, 4850, 4851, 4853, 4854`
- `test/src/misc/cvpx_hdr_metadata.c:48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 92, 93, 94, 95, 109, 110, 111, 112, 113, 114, 115, 116, 117, 118, 141, 142, 143, 144, 145, 146, 147, 148, 149, 150, 151, 152, 153, 154, 155, 156, 209, 210, 211, 212, 213, 214, 215, 216, 217, 218, 219, 220, 221, 222, 223, 224`

---

### `lighting` (202 hits total; 91 code hits, 111 po hits)
*Code hits:*
- `doc/Doxyfile.in:1719, 1793, 1865, 1892`
- `include/vlc_es.h:376`
- `modules/access/v4l2/v4l2.c:143`
- `modules/codec/avcodec/video.c:425, 1248, 1249, 1250, 1251, 1252, 1254`
- `modules/codec/dav1d.c:183, 185, 186, 544`
- `modules/codec/videotoolbox/decoder.c:2299`
- `modules/codec/vt_utils.c:505, 510, 518, 519, 520, 641, 642, 658`
- `modules/codec/vt_utils.h:145, 151`
- `modules/demux/mkv/matroska_segment_parse.cpp:967, 973`
- `modules/demux/mp4/essetup.c:781, 782`
- `modules/demux/mp4/heif.c:448, 449`
- `modules/gui/macosx/Resources/App-Icons/VLC-Dev.icon/icon.json:132, 301, 423`
- `modules/gui/macosx/Resources/App-Icons/VLC.icon/icon.json:104, 267, 360`
- `modules/misc/preparser_serializer/json/fromjson.c:654, 657, 658`
- `modules/misc/preparser_serializer/json/tojson.c:567, 568, 572, 573`
- `modules/mux/mp4/libmp4mux.c:1067, 1072, 1073`
- `modules/packetizer/h266.c:1363, 1364`
- `modules/packetizer/hevc.c:1129, 1130`
- `modules/video_output/apple/VLCSampleBufferDisplay.m:1361, 1362`
- `modules/video_output/caopengllayer.m:590, 591, 601, 603`
- `modules/video_output/libplacebo/display.c:494, 495`
- `modules/video_output/libplacebo/utils.c:409, 410`
- `modules/video_output/win32/direct3d11.cpp:1094, 1095`
- `modules/video_output/win32/direct3d9.c:1016`
- `src/config/ansi_term.h:67, 77`
- `src/input/decoder.c:973, 974, 975, 976, 978`
- `src/input/es_out.c:4857, 4860, 4862, 4865`
- `test/src/misc/cvpx_hdr_metadata.c:59, 60, 79, 82, 84, 120, 121, 140, 143, 145, 208, 211, 213`
*PO translation hits (111 hits):* `po/*.po` lines corresponding to the string in `modules/access/v4l2/v4l2.c:143`.

---

UNCERTAIN:
- Real-world perceptual tone mapping and luminance accuracy produced by Apple's closed-source CoreAnimation compositor (`CADynamicRangeHigh`, `CADynamicRangeStandard`, and `CAToneMapModeAutomatic`) across varying Apple Silicon display panels (Liquid Retina XDR, Studio Display, Pro Display XDR, external HDMI 2.1 HDR TVs) could not be verified via static code analysis without hardware luminance measurement.
- Whether VideoToolbox hardware decoding on Apple Silicon preserves or discards Dolby Vision RPU metadata packets in private sample buffer extensions could not be verified without runtime tracing.

