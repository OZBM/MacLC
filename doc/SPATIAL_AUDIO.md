# Apple Spatial Audio / Dolby Atmos output (macOS)

This document describes the native spatial-audio path added to the macOS audio
output modules and the companion object-audio decoders.

## Goal

Match Apple TV / QuickTime Player / Apple Music behaviour by using **Apple's
own renderer** instead of a custom HRTF/spatializer:

* multichannel PCM is handed to `AVSampleBufferAudioRenderer` with a standard
  CoreAudio channel-layout tag;
* compressed **E-AC-3 with JOC** (Dolby Digital Plus + Dolby Atmos) is passed
  through untouched, with a `dec3` cookie built from the bitstream, so macOS
  registers the Atmos decoder and enables Spatial Audio (including head
  tracking / Personalized Spatial Audio on supported AirPods);
* Dolby TrueHD Atmos and DTS:X are decoded locally (macOS has no native
  decoder or bitstream passthrough for those formats) and rendered to a 7.1
  bed, which is then spatialized by Apple's renderer.

The `auhal` output remains available as a fallback (`--aout=auhal`).

## Supported input

| Format | Path | Notes |
| --- | --- | --- |
| 5.1 / 7.1 E-AC-3 JOC (Atmos) | compressed passthrough | native Apple Atmos rendering; `dec3`/JOC cookie; one-shot async priming |
| 5.1 / 7.1 E-AC-3 (no JOC) | compressed passthrough | native Apple DD+ decoding |
| Plain AC-3 | software decode to PCM | |
| PCM 2.1 - 7.1 | spatial layout tags | standard CoreAudio layouts, channel reorder |
| TrueHD / TrueHD Atmos | LibTrueHD decode + object render | 7.1 bed (heights folded); 7.1.4 renderer hooks prepared |
| DTS:X (standard presentation) | LibDTSX decode + object render | auto-selected for DTS-HD; falls back to avcodec when refused |

DRM-protected files (e.g. Apple Music downloads) are not supported.

## Key files

* `modules/audio_output/apple/avsamplebuffer.m` — compressed passthrough,
  priming, spatial flags, hotplug and default-device handling.
* `modules/audio_output/apple/eac3_dec3.{c,h}` — E-AC-3/JOC parsing and
  `dec3` cookie construction.
* `modules/audio_output/apple/atmos_prime.{m,h}` — in-process silent JOC
  stream used to register the system Atmos decoder once per process.
* `modules/audio_output/apple/channel_layout.{c,h}` — CoreAudio layout tags
  and VLC WG4 channel reordering.
* `modules/codec/truehd/` — LibTrueHD and LibDTSX vendored libraries, the
  object renderers and the two decoder modules.

## Building

The modules build with the normal Meson (`meson setup ... && ninja`) or
autotools build. On macOS, Meson needs a recent Bison for the JSON demuxer
grammar; Homebrew's Bison works (`PATH="$(brew --prefix bison)/bin:$PATH"`).

`AOUT_CHAN_MAX` is raised to 16 to carry the 7.1.4 bed. Modules with fixed
9-channel tables were updated accordingly. A full compatible build requires
rebuilding libvlccore *and all plugins together*; swapping libvlccore alone
into an existing app bundle is not ABI-compatible.

## Limitations

* TrueHD and DTS:X cannot be bitstreamed on macOS; their object metadata is
  rendered into a channel bed before Apple spatializes it.
* Discrete 7.1.4 height output requires the rebuilt core and is not active in
  a stock-libvlccore app bundle.
* LibDTSX refuses alternate/object presentations; those fall back to avcodec.

## Licensing / attribution

* LibTrueHD / `truehdd` — see `modules/codec/truehd/LICENSE.truehd`,
  `LICENSE-APACHE.truehd` and `NOTICE.truehd`.
* LibDTSX — see `modules/codec/truehd/LICENSE.dtsx`.
