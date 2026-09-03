# VideoToolbox / EDR probe results

Produced by `vt_probe.m` in this directory. Build and run it with:

```
clang -framework Foundation -framework AppKit -framework VideoToolbox \
      -framework CoreMedia -framework CoreVideo -framework CoreFoundation \
      -fobjc-arc -o vt_probe vt_probe.m && ./vt_probe
```

The probe is a standalone diagnostic. It is deliberately not wired into the VLC
build.

## Run of 2026-09-03

```
================================================================
  VT Probe — VideoToolbox / EDR Capability Report
  MacLC (VLC 4.0 macOS Apple Silicon fork)
================================================================

========================================
SECTION 2: Machine Identification
========================================

  CPU brand string : Apple M3 Max
  Hardware model   : Mac15,9
  macOS version    : 26.2.0 (Version 26.2 (Build 25C56))

========================================
SECTION 1: VTIsHardwareDecodeSupported()
========================================

  kCMVideoCodecType_H264                        ('avc1')  ->  YES (hardware)
  kCMVideoCodecType_HEVC                        ('hvc1')  ->  YES (hardware)
  kCMVideoCodecType_AV1                         ('av01')  ->  YES (hardware)
  kCMVideoCodecType_VP9                         ('vp09')  ->  NO
  kCMVideoCodecType_AppleProRes422              ('apcn')  ->  YES (hardware)
  kCMVideoCodecType_DolbyVisionHEVC             ('dvh1')  ->  YES (hardware)

========================================
SECTION 3: Pixel Format Availability
========================================

  [info] Using a real HEVC Main10 format description from the hardware encoder.

  Pixel Format                                             Result
  ------------                                             ------
  420YpCbCr8BiPlanarVideoRange  (NV12 / '420v')            OK (session created)
  420YpCbCr10BiPlanarVideoRange (P010 / 'x420')            OK (session created)
  422YpCbCr10BiPlanarVideoRange ('x422')                   OK (session created)
  422YpCbCr16BiPlanarVideoRange ('sv22')                   OK (session created)
  444YpCbCr16BiPlanarVideoRange ('sv44')                   OK (session created)
  32BGRA                        ('BGRA')                   OK (session created)

  [info] SDK check: kCVPixelFormatType_420YpCbCr16BiPlanar* is NOT DEFINED
         in this SDK. CoreVideo/CVPixelBuffer.h declares 16-bit biplanar
         YCbCr for 4:2:2 ('sv22') and 4:4:4 ('sv44') only.

========================================
SECTION 4: Display EDR Capabilities
========================================

  Found 1 display(s):

  --- Display 1 ---
    Name                        : Built-in Retina Display
    maxExtendedDynamicRange      : 2.951
    maxPotentialExtendedDynRange  : 16.000
    maxRefExtendedDynRange       : 0.000
    Color space                  : (unknown)
    HDR-capable color space?      : YES

================================================================
  END OF PROBE
================================================================
```

## What this settles

- **Hardware AV1 decode is available on this machine.** `deviceSupportsAV1()`
  in `modules/codec/videotoolbox/decoder.c` gates on `__aarch64__`, macOS 14+
  and `VTIsHardwareDecodeSupported(kCMVideoCodecType_AV1)`. All three hold on
  an M3 Max running macOS 26.2, so the hardware AV1 path is reachable here and
  no longer needs to be treated as untestable. Decoding a real AV1 HDR stream
  still has to be done separately.
- **Dolby Vision HEVC reports hardware decode support** (`'dvh1'`), which is
  worth knowing for the RPU work: VideoToolbox may be handling some of this
  itself.
- **VP9 has no hardware decode** on this machine, so that path stays on the
  software decoder.
- **16-bit biplanar destinations are accepted.** A decompression session for an
  HEVC Main10 source can be created with `'sv22'` (4:2:2 16-bit) and `'sv44'`
  (4:4:4 16-bit) as the destination pixel format. There is still no 4:2:0
  16-bit format in CoreVideo, so a real >10-bit path would go through 4:2:2 with
  VideoToolbox doing the chroma upsampling, not through a 4:2:0 16-bit buffer.
  This bears directly on the fallback comment in `GetBestChroma()`.
- **EDR is observable on this machine.** The built-in display reports a current
  headroom of 2.951 and a potential headroom of 16.0, so the EDR headroom
  handling, the subtitle attenuation curve and the dynamic range switching can
  all be exercised here rather than only reasoned about.

## What it does not settle

Session creation succeeding is not proof that the decoder will actually emit
`'sv22'` or `'sv44'` buffers for a 12-bit bitstream; that needs a real >10-bit
stream decoded end to end. The probe also says nothing about picture quality,
about the compositor's tone curve, or about whether the AV1 hardware path
produces correct output.
