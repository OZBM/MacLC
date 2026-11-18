# Apple spatial audio / Dolby Atmos output (macOS)

`avsamplebuffer` is an opt-in audio output (`--aout=avsamplebuffer`) that uses
Apple's `AVSampleBufferAudioRenderer` instead of AUHAL. AUHAL remains the
default output.

## What it does

* **Compressed E-AC-3 / E-AC-3 JOC (Dolby Digital Plus + Dolby Atmos)** is
  passed to the system decoder untouched. A `dec3` cookie is built from the
  bitstream, including the JOC/Atmos signalling, so macOS enables its native
  Atmos renderer (head tracking / Personalized Spatial Audio on supported
  AirPods/Beats are controlled by macOS, not by this code).
* **PCM 2.1–7.1** is emitted with standard CoreAudio spatial-layout tags and
  the correct channel reordering.
* The **Pass through Dolby Atmos (E-AC-3 JOC)** preference (on by default;
  `--no-atmos-passthrough` disables it) allows A/B comparison against avcodec
  decoding the same stream to PCM.

There is no custom HRTF/spatializer; the system decides how to render for the
connected device. DRM-protected files (e.g. Apple Music downloads) are not
supported.

## Building

The feature is wired in `modules/audio_output/Makefile.am` (autotools), which
is MacLC's supported build. No Meson changes are required.

## Testing

`test/spatial_audio.sh` generates its own media (ffmpeg plus the small
`test/generate_silent_joc.c` bitstream generator) and asserts JOC/Atmos
passthrough, plain E-AC-3 passthrough, the decode-to-PCM toggle and PCM
spatial layout tags. It requires `ffmpeg`, a C compiler and `gtimeout` or
`timeout`, and skips (`exit 77`) when `APP` is not set, so `make check` can
list it safely:

```
APP=/path/to/MacLC.app/Contents/MacOS/MacLC sh test/spatial_audio.sh
```

This is a log-path smoke test; it verifies signalling and format selection,
not audible spatial rendering on a specific output device.

## Licensing / attribution

The `dec3` bitstream construction follows published E-AC-3 (ETSI TS 102 366)
and Dolby specifications; no third-party source code is copied. The Atmos
priming helper generates its own silent E-AC-3 JOC stream and uses public
AVFoundation APIs; it was observed to work on macOS 27.2 (26B123) with
AirPods 3. No documented API exists for registering the system decoder.

Dolby, Dolby Atmos and Dolby Digital Plus are trademarks of Dolby Laboratories.
