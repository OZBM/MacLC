<!--
  MacLC's GitHub page. Pictures live in .github/readme/.
  banner.jpg and sdr-to-hdr-split.jpg carry HDR gain maps (ISO 21496-1): keep them as they are,
  re-encoding them drops the glow. On each release, update the version numbers in "Install".
  The translations (README.<lang>.md) follow this file: update them when it changes.
-->

<h1 align="center">
  <a href="https://github.com/OZBM/MacLC/releases/latest">
    <img src=".github/readme/banner.jpg" width="100%" alt="MacLC. Plays everything. Makes it shine. Free, open source, real HDR, Apple Silicon.">
  </a>
</h1>

<p align="center">
  <b>The free video player for Mac that plays everything, and makes it shine.</b><br>
  Real HDR, SDR&nbsp;to&nbsp;HDR, nine upscalers, smooth motion, Voice&nbsp;Boost and a library in the style of the Apple&nbsp;TV app, in one native app for Apple&nbsp;Silicon.
</p>

<p align="center">
  <a href="https://github.com/OZBM/MacLC/releases/latest"><img alt="Download MacLC for Mac" src="https://img.shields.io/github/v/release/OZBM/MacLC?display_name=tag&label=Download%20for%20Mac&style=for-the-badge&logo=apple&logoColor=white&color=e8640c"></a>
  <a href="https://www.hazenstudio.com/maclc/donate/"><img alt="Donate to MacLC" src="https://img.shields.io/badge/Donate-PayPal%20or%20card-2f343c?style=for-the-badge&logo=githubsponsors&logoColor=ff8a3d"></a>
</p>

<p align="center">
  <img alt="macOS 26 Tahoe or later" src="https://img.shields.io/badge/macOS-26%20Tahoe%20or%20later-24292f?logo=apple&logoColor=white">
  <img alt="Apple Silicon, M1 or newer" src="https://img.shields.io/badge/Apple%20Silicon-M1%20or%20newer-24292f">
  <img alt="Free, no ads, no tracking" src="https://img.shields.io/badge/free-no%20ads%20%C2%B7%20no%20tracking-24292f">
  <a href="COPYING"><img alt="Licence: GPL 2.0 or later" src="https://img.shields.io/badge/licence-GPL--2.0--or--later-24292f"></a>
</p>

<p align="center">
  <b>English</b> · <a href="README.fr.md">Français</a> · <a href="README.zh-CN.md">简体中文</a> · <a href="README.ja.md">日本語</a> · <a href="README.es.md">Español</a> · <a href="README.de.md">Deutsch</a>
</p>

<picture>
  <source media="(prefers-color-scheme: dark)" srcset=".github/readme/library-dark.webp">
  <img src=".github/readme/library-light.webp" alt="MacLC's library window on macOS 26: Continue Watching, Recently Added and a Now Playing capsule, with 4K, HDR10, HLG and Dolby Vision badges on the videos.">
</picture>

## Why MacLC

<table>
<tr>
<td width="50%" valign="top">

**Plays everything.** MKV, MP4, AVI, WebM, TS, AV1, HEVC, FLAC, DTS, subtitles in SRT, ASS and more, and the odd file other players refuse. No codecs to install.

</td>
<td width="50%" valign="top">

**Real HDR.** Dolby Vision, HDR10+, HDR10 and HLG with their real highlights on a MacBook Pro or any HDR screen, and subtitles kept at a comfortable white.

</td>
</tr>
<tr>
<td valign="top">

**SDR to HDR.** Ordinary videos use the extra brightness of your screen: lamps, skies and reflections start to glow, while faces and shadows stay close to how they were filmed.

</td>
<td valign="top">

**Sharper, smoother.** Nine GPU upscalers (MetalFX, FSR, NIS, Anime4K…) for small videos on big screens, and frame interpolation up to your screen's refresh rate, 120&nbsp;Hz on ProMotion.

</td>
</tr>
<tr>
<td valign="top">

**A real Mac app.** Liquid Glass, Mac menus and shortcuts, a library in the style of the Apple TV app, and settings that say what each switch does.

</td>
<td valign="top">

**And more.** Voice Boost for clearer dialogue, Watch for add-on catalogs, torrents that play while they download, YouTube (with the free yt-dlp), and Play on TV (beta).

</td>
</tr>
</table>

<p align="center"><b>Free. No ads, no account, no tracking.</b> Open source under the GPL.</p>

## HDR that uses your whole screen

A MacBook Pro screen can show highlights several times brighter than white. MacLC is built around that.

- **Dolby Vision, HDR10+, HDR10 and HLG**, each shown the way your screen can best display it, including the HDR videos your iPhone records.
- **The right brightness on every screen.** MacLC measures the screen each window is on, and measures again when you move the window to another display.
- **HDR on ordinary screens too**, fitted to what the screen can show instead of clipped to flat white.
- **Subtitles you can look at.** They stay at a calm white instead of shining like the brightest highlight of the film.
- **Hardware AV1** on M3 and newer, and software AV1 everywhere else.

MacLC's own Metal video engine renders Dolby Vision and HDR10+, and the six HDR defects found in the code it builds on are fixed ([details](#under-the-hood)).

### SDR to HDR: light where your screen has some to spare

**Reading this on a MacBook Pro? Look at the picture below in Safari.** It carries a real HDR version: the right copy went through MacLC's SDR to HDR curve, and its sun and sky glow brighter than the white of this page. On other screens both copies look the same, and that is the point: MacLC keeps the picture you know and spends your screen's extra light on its highlights.

<p align="center">
  <img src=".github/readme/sdr-to-hdr-split.jpg" width="100%" alt="The same frame of the open movie Sintel twice: on the left as filmed, on the right through MacLC's SDR to HDR. On an HDR screen, in a browser that shows HDR images, the sun and sky on the right glow.">
</p>

<picture>
  <source media="(prefers-color-scheme: dark)" srcset=".github/readme/sdr-to-hdr-curve-dark.svg">
  <img src=".github/readme/sdr-to-hdr-curve-light.svg" width="100%" alt="Chart: with SDR to HDR at the Balanced level, the bottom 90 percent of the signal is shown exactly as in the original video; above it, small highlights rise to 400 cd/m² and large bright areas to 190, where the original stops at 100.">
</picture>

Choose a level from Fast to Maximum, or let Auto pick one your Mac can keep up with. High and Maximum use small networks trained for MacLC, about half a millisecond a frame on an M3 Max. You set how bright highlights may go, and **Hold to Compare** shows the original while you press.

<p align="center">
  <img src=".github/readme/sdr-to-hdr.webp" width="100%" alt="MacLC playing Sintel with the SDR to HDR panel open: quality levels, a curve of the effect, and a slider for how bright highlights may go.">
</p>

## Sharper and smoother

**Upscaling.** A 720p episode on a 5K display deserves better than a blur. MacLC enlarges small videos on the GPU, with nine methods to choose from, each explained in plain words in its panel:

| Method | Best for |
|---|---|
| Auto | Picks for you: Apple's super resolution on small videos, then MetalFX |
| Apple Neural 4x | Apple's 4× neural model (a one-time download from Apple); steps back to 2× when the Mac cannot keep up |
| Anime and Anime4K | Drawn animation: clean lines, flat colours |
| FSRCNNX | Fine detail (downloaded only after you accept its licence) |
| Sharp (AMD FSR 1) and NIS (NVIDIA Image Scaling) | Crisp edges at almost no cost |
| Efficient (MetalFX) | Battery life |
| Classic (EWA Lanczos) | Staying as true to the source as possible |

Apple's neural passes, Anime, Anime4K and FSRCNNX work on 8-bit SDR video. On HDR and 10-bit video, and with SDR to HDR on, MacLC uses the other methods.

**Compare Before and After.** Split the picture down the middle, on the video you are watching: on the left without SDR to HDR, upscaling and interpolation, on the right with them.

**Smooth motion.** Frame interpolation raises 24 fps to your screen's refresh rate: 60 Hz, 120 Hz on a ProMotion MacBook Pro, or more on a fast external display. Automatic picks a method that keeps up in real time; optical flow and RIFE, a neural network, can be chosen by hand. It is off by default, because cinema purists are right too.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset=".github/readme/motion-demo-dark.svg">
  <img src=".github/readme/motion-demo-light.svg" width="100%" alt="Animated illustration: a dot crossing in visible steps at 24 frames per second, and smoothly when interpolated to 120 frames per second.">
</picture>

<p align="center">
  <img src=".github/readme/motion.webp" width="100%" alt="MacLC's Motion Interpolation panel over a scene from Sintel: Interpolate Frames on, method Automatic, frame rate Match the Display, playing 24 fps as 120 fps.">
</p>

## A library worth opening

Point MacLC at your folders and it builds a library in the style of the Apple TV app: **Home** with what you were watching, then **Videos, Shows, Artists, Albums, Songs, Genres, Favorites and Playlists**. Episodes named like `Show S01E02` group into seasons, cards carry **Dolby Vision, HDR10, HLG and 4K** badges, and a floating Now Playing capsule keeps the picture alive while you browse. Your files never move.

**Watch** browses film and series catalogs in the style of the Apple TV app, with featured titles, shelves, a Top 10, genres and title pages with cast and episodes. Cinemeta, built in, provides posters, details and search; what you can play depends on the add-ons you install, which speak the [Stremio add-on protocol](https://github.com/Stremio/stremio-addon-sdk/blob/master/docs/protocol.md). Favorites, history and Continue Watching stay on your Mac.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset=".github/readme/watch-dark.webp">
  <img src=".github/readme/watch-light.webp" alt="MacLC's Watch section: a featured carousel and a Top 10 shelf of Blender open movies.">
</picture>

- **Torrents that play while they download.** Open a `.torrent` file or paste a magnet link: playback starts once a few seconds are verified, and a marker on the playback bar shows what is buffered, the speed and the peers.
- **YouTube** with Home, Subscriptions, Watch Later, playlists and search. It needs the free [`yt-dlp`](https://github.com/yt-dlp/yt-dlp), and MacLC shows you the one command that installs it. Signing in is optional: on Google's own page, or with the session of a browser where you are already signed in. MacLC keeps only the session cookies yt-dlp needs, in a private file on your Mac, and Sign Out deletes it.
- **Play on TV (beta).** Send what is playing to an Apple TV or another AirPlay receiver, or to a Chromecast.

MacLC ships no films, shows or streams. Add-ons are third-party services: use them only for content you have the right to watch.

## Dialogue you can follow

<img src=".github/readme/sound-dark.webp" align="right" width="260" alt="MacLC's Sound panel: Voice Boost selected, an Intensity slider and the list of sound modes.">

**Voice Boost** makes dialogue clearer without raising the music. On 5.1 films it lifts the centre channel (+7.4&nbsp;dB of dialogue advantage, measured). On stereo it isolates the voice in the centre of the mix, in real time on Apple's vDSP (+4.8&nbsp;dB in the 1 to 4&nbsp;kHz speech band, measured on a real mix, about 16&nbsp;ms of latency).

Also: **Night, Cinema, Music, Bass Boost, Spoken Word, Headphones and Small Speakers** modes, each with an Intensity slider, a **10-band equalizer** (⌥⌘E) and a limiter that keeps loud scenes from clipping.

<br clear="right">

## Settings that explain themselves

One window, a sidebar and a search field. Every row says what the switch does in terms of what you will see or hear. Expert settings are still there, behind a disclosure.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset=".github/readme/settings-hdr-dark.webp">
  <img src=".github/readme/settings-hdr-light.webp" alt="MacLC's HDR and Colour settings: a live status of the display's brightness headroom, four named playback modes with a sentence each, and SDR to HDR options.">
</picture>

## How it compares

|  | **MacLC** | IINA | Infuse | QuickTime Player |
|---|:---:|:---:|:---:|:---:|
| Plays almost any video file | ✅ | ✅ | ✅ some audio needs Pro | ❌ mostly MP4 and MOV |
| HDR video on HDR screens | ✅ | ✅ | ✅ | ✅ |
| Makes ordinary video glow on HDR screens (SDR to HDR) | ✅ | ❌ | ❌ | ❌ |
| Upscaling methods built in | ✅ nine | ➖ shaders you install | ✅ one AI mode | ❌ |
| Smooth motion (frame interpolation) | ✅ built in | ➖ through mpv options | ❌ | ❌ |
| One-click dialogue boost | ✅ Voice Boost | ❌ filters by hand | ❌ volume boost only | ❌ |
| Library for your own videos | ✅ and music | ❌ playlists and history | ✅ its speciality | ❌ |
| Add-on catalogs and torrents | ✅ | ❌ | ❌ | ❌ |
| YouTube and web video | ✅ with yt-dlp | ✅ with yt-dlp | ❌ | ❌ |
| Free | ✅ | ✅ | ➖ Pro is paid | ✅ with macOS |
| Open source | ✅ GPL | ✅ GPL | ❌ | ❌ |

<sub>Checked on 3 November 2026 against each player's own documentation and release notes. IINA is excellent, free and open source too.</sub>

## Install

<p>
  <a href="https://github.com/OZBM/MacLC/releases/latest"><img alt="Download MacLC" src="https://img.shields.io/github/v/release/OZBM/MacLC?display_name=tag&label=Download&style=for-the-badge&logo=apple&logoColor=white&color=e8640c"></a>
</p>

1. Download `maclc-1.6.dmg` (57.8 MB) from [the latest release](https://github.com/OZBM/MacLC/releases/latest).
2. Open it and drag **MacLC** into **Applications**.
3. Open MacLC. The first time, macOS stops it: click **Done**, then open **System Settings › Privacy & Security**, scroll to **Security** and click **Open Anyway** next to "MacLC was blocked". Confirm with Touch ID or your password. You only do this once per version.

> [!NOTE]
> **Why the extra click?** macOS opens apps with a double-click only when their developer pays Apple €99 a year for a Developer ID and has each version notarised. MacLC is free and has not raised that money yet. **The first €99 of donations removes this step for everyone.** [Donate](https://www.hazenstudio.com/maclc/donate/)

<details>
<summary>Terminal alternative, checksum and requirements</summary>

Instead of **Open Anyway**, you can remove the "downloaded from the internet" flag:

```bash
xattr -dr com.apple.quarantine /Applications/MacLC.app
```

Check that your copy is exactly the published one (the expected value is on the release page; for 1.6 it is `194de0b42a836985dba92a75d283264e21b4285f5a24934769b0e2aad5aae805`):

```bash
shasum -a 256 ~/Downloads/maclc-1.6.dmg
```

If macOS ever says MacLC "is damaged and can't be opened", the download is incomplete: delete it and download it again. Do not bypass that message.

**Requirements**

- A Mac with Apple Silicon (M1 or newer). Intel Macs are not supported.
- macOS 26 Tahoe or later.
- SDR to HDR needs a screen that can go brighter than white (a MacBook Pro with an XDR display, a Pro Display XDR, an HDR monitor). Everything else works on any screen.
- Optional: [`yt-dlp`](https://github.com/yt-dlp/yt-dlp) for YouTube and web video (`brew install yt-dlp`).

The app is self-contained: FFmpeg, libass, libplacebo, libtorrent and about 140 other libraries are inside it, with their licences in `MacLC.app/Contents/Resources/Licenses/`.

</details>

## Support MacLC

MacLC is a personal project: no ads, no subscription, no data to sell. Donations pay for what a free app cannot get on its own, in this order:

<picture>
  <source media="(prefers-color-scheme: dark)" srcset=".github/readme/donation-milestones-dark.svg">
  <img src=".github/readme/donation-milestones-light.svg" width="100%" alt="What donations unlock: 99 euros, no more Open Anyway (Apple notarisation); 400 euros, Play on TV out of beta; 900 euros, a second HDR screen for testing; 1,600 euros, a full accessibility pass; 2,500 euros, an app that updates itself.">
</picture>

**Every gift comes with a wish.** Tell me what MacLC should do next, or back a wish already on the list: the wishes with the most supporters go first. Pay with PayPal or a card on [the donation page](https://www.hazenstudio.com/maclc/donate/), where the total raised is live.

<p align="center">
  <a href="https://www.hazenstudio.com/maclc/donate/"><img alt="Donate and make a wish" src="https://img.shields.io/badge/Donate%20and%20make%20a%20wish-%E2%82%AC5%20%C2%B7%20%E2%82%AC15%20%C2%B7%20%E2%82%AC30%20%C2%B7%20%E2%82%AC99-e8640c?style=for-the-badge&logo=githubsponsors&logoColor=white"></a>
</p>

**No money? These help just as much:**

- ⭐ **Star this repository.** Stars are how people find MacLC on GitHub.
- **Tell someone.** Share on [X](https://x.com/intent/post?text=MacLC%3A%20the%20free%20video%20player%20for%20Mac%20that%20plays%20everything%2C%20with%20real%20HDR%2C%20SDR%20to%20HDR%2C%20upscaling%20and%20smooth%20motion.&url=https%3A%2F%2Fgithub.com%2FOZBM%2FMacLC), [Bluesky](https://bsky.app/intent/compose?text=MacLC%3A%20the%20free%20video%20player%20for%20Mac%20that%20plays%20everything%2C%20with%20real%20HDR%2C%20SDR%20to%20HDR%2C%20upscaling%20and%20smooth%20motion.%20https%3A//github.com/OZBM/MacLC), [Reddit](https://www.reddit.com/submit?url=https%3A%2F%2Fgithub.com%2FOZBM%2FMacLC&title=MacLC%3A%20a%20free%2C%20open-source%20video%20player%20for%20Mac%20with%20real%20HDR%20and%20SDR%20to%20HDR) or [LinkedIn](https://www.linkedin.com/sharing/share-offsite/?url=https%3A%2F%2Fgithub.com%2FOZBM%2FMacLC).
- **Report what you see.** A file that will not play, a crash, a wrong colour: [open an issue](https://github.com/OZBM/MacLC/issues/new) with what you did and what you expected.
- **Test on your screen.** Only one MacBook Pro has checked MacLC's HDR so far. If you own another HDR display, tell me how it looks.

## Questions

<details>
<summary><b>Is MacLC really free?</b></summary>

Yes. No paid version, no subscription, no ads, no account, and nothing held back. It is open source under the GPL 2.0 or later.
</details>

<details>
<summary><b>Is it safe? Why does macOS block it the first time?</b></summary>

The whole source code is public in this repository, and MacLC has no analytics or tracking: it does not report what you watch to its developer or to anyone else. Watch, YouTube and torrents connect to the services they use, as any app would. macOS blocks MacLC the first time only because it is not notarised by Apple, which costs €99 a year (see [Install](#install)). Each release publishes the SHA-256 checksum of the disk image, so you can check your copy.
</details>

<details>
<summary><b>Do I need an HDR screen?</b></summary>

No. MacLC plays every video on any Mac screen, and fits HDR films to ordinary screens. Only SDR to HDR needs a screen that can go brighter than white.
</details>

<details>
<summary><b>Does it work on Intel Macs, or on macOS 15 and earlier?</b></summary>

No. MacLC targets Apple Silicon and macOS 26 Tahoe or later, and its bundled libraries require macOS 26.
</details>

<details>
<summary><b>How do I update?</b></summary>

Download the new disk image from [Releases](https://github.com/OZBM/MacLC/releases) and replace the app. Updates that install themselves are on the donation roadmap. To hear about new versions, click GitHub's **Watch** button at the top of this page, then **Custom › Releases**.
</details>

<details>
<summary><b>Won't smooth motion make films look like a soap opera?</b></summary>

It can, which is why it is off by default. Many people like it for sport, nature and animation, and keep the classic 24-frame look for cinema. Try both on the same scene.
</details>

<details>
<summary><b>Does MacLC come with films or shows?</b></summary>

No. MacLC plays your own files and what you open. Watch shows the catalogs of the add-ons you choose to install, which are third-party services: use them only for content you have the right to watch.
</details>

## Under the hood

MacLC is built on part of VLC 4's open-source code, chiefly its playback engine (`libVLC`). The interface, the library and Watch, the Metal video output, the HDR pipeline, SDR to HDR, upscaling, motion interpolation, Voice Boost and AirPlay were written or rebuilt for MacLC, for macOS on Apple Silicon only.

<details>
<summary><b>HDR pipeline: six defects fixed in the inherited code</b></summary>

From an audit of the macOS HDR path of VLC 4.0.0-dev on Apple Silicon (2026-09-02, baseline `99034f9`):

| Defect | What you saw | Fix |
|---|---|---|
| EDR headroom read once, from `[NSScreen mainScreen]` | Moving the window to another display left HDR at the wrong brightness | Headroom re-evaluated on screen, profile and parameter changes |
| HDR mode and EDR headroom preferences did nothing | Settings were decorative | Wired to live variable callbacks, applied during playback |
| No SDR tone-mapping branch | HDR films on SDR screens clipped to flat white | `CADynamicRangeStandard` with `CAToneMapModeAutomatic`, BT.709 retag fallback |
| Subtitles untagged over PQ video | White subtitles at full PQ luminance over dark scenes | Subtitle layer tagged sRGB, scaled to BT.2408 reference white |
| HEVC above 10 bits downsampled to 8-bit BGRA | 12-bit and 16-bit sources lost bits before the screen | Routed to P010; 16-bit 4:2:2 wired through the CVPX helpers |
| Sub-4K HDR tagged BT.709, zero-nit mastering volume emitted | Wide-gamut content shown through the wrong primaries | Correct tagging per stream, mastering volume never zero |

Also: HDR10+ dynamic metadata through the filter chain, Dolby Vision metadata from the VideoToolbox bitstream (profiles 5 and 8.1 in MacLC's Metal engine, 8.4 from iPhone), ST 2086 and CTA-861.3 metadata forwarded to the display layer, a per-window ICC profile, hardware AV1 on M3 and newer, and ARM64 NEON chroma conversions.
</details>

<details>
<summary><b>How SDR to HDR works</b></summary>

The picture is linearised and each pixel's drive is taken as the larger of its luminance and 85 % of its brightest channel. Fast lifts the drive above half of SDR white along a fixed quadratic; Balanced lifts only what lies above diffuse white, by an amount that shrinks when large areas are bright. In both, the whole triplet is scaled by the same factor, so hue and saturation do not move. High and Maximum use two small networks trained for MacLC, which predict a grid of brightness gains for each scene, with per-channel gains kept within 0.2 (log) of the luminance gain. The result is limited to the screen's actual headroom, with a rolloff below it, and tagged so the compositor does not tone-map it back down. Sources that are already HDR are left alone. The maths are in [`maclc_sdr2hdr.h`](modules/video_output/apple/maclc_sdr2hdr.h) and the Metal kernels in [`VLCHDRExpander.m`](modules/video_output/apple/VLCHDRExpander.m).
</details>

<details>
<summary><b>Upscaling engine, cost and licences</b></summary>

Upscaling runs in MacLC's Metal video output when the window is at least 1.2 times larger than the video. Measured on an M3 Max: MetalFX spatial 0.4 to 0.84 ms per frame, AMD FSR 1 from 720p to 1440p about 0.5 ms, NIS from 720p to 4K 1.19 ms, ArtCNN from 540p to 1080p about 2.1 ms. Neural passes stand down on battery, in Low Power Mode, when the Mac is hot, or when a frame would take more than 60 % of its time. A translator runs mpv-style hook shaders, which is how Anime4K and FSRCNNX run in Metal.

Licences: NIS and FSR 1 (MIT, with NVIDIA's and AMD's notices kept verbatim), Anime4K and ArtCNN (MIT), FSRCNNX (LGPL-3.0, downloaded only after you accept its licence), MetalFX and VideoToolbox super resolution (Apple system frameworks).
</details>

<details>
<summary><b>Command-line options added</b></summary>

| Option | Values | What it does |
|---|---|---|
| `--macosx-hdr-mode` | 0 to 3 | 0 Auto, 1 force native HDR, 2 tone-map to SDR, 3 HDR off |
| `--macosx-edr-headroom` | float | 0 follows the screen; 1 or more forces a headroom |
| `--macosx-sdr-to-hdr` | bool | Expand SDR video into the screen's extended range |
| `--macosx-sdr-to-hdr-boost` | 1 to 16 | How far above SDR white highlights may go (default 4) |
| `--macosx-sdr-to-hdr-quality` | auto, fast, balanced, high, maximum | SDR to HDR level |
| `--maclc-upscale`, `--maclc-upscale-method` | bool, string | Upscaling on or off, and the method |

</details>

<details>
<summary><b>Building from source</b></summary>

MacLC builds on an Apple Silicon Mac with autotools against Homebrew's libraries. Meson does not build the macOS interface: use autotools, or the Xcode project for interface work.

```bash
# once: the media library engine, TagLib and libdvbpsi, built from contrib/src's pinned versions
extras/package/macosx/build-medialibrary.sh
extras/package/macosx/build-taglib.sh
extras/package/macosx/build-dvbpsi.sh

# configure a development build in build/, then:
make -C build -j12
make -C build package-macosx          # signed MacLC.app and maclc-<version>.dmg

# interface work in Xcode (deploys the plugin into build/MacLC.app)
xcodebuild -project extras/package/macosx/MacLC.xcodeproj -scheme MacLC build

# a release: clean build in build-release/, checks, smoke test on sample files, SHA-256
extras/package/macosx/make-release.sh --samples ~/Movies/maclc-samples
```

Configure with `build-deps/prefix/lib/pkgconfig` and `build-deps/pkgconfig` first in `PKG_CONFIG_PATH`; `automake` 1.18 is required to regenerate `Makefile.in`; any file using `_NS("…")` must be listed in `po/POTFILES.in`. The unit tests (308, XCTest) run with `make check-macosx` from `build/modules`, and `MACLC_SELFTEST=1` builds the main settings panes at startup and reports what appeared. The app icon is drawn by a committed Swift program, [`maclc_app_icon.swift`](extras/package/macosx/asset_sources/maclc_app_icon.swift).
</details>

## Releases

<picture>
  <source media="(prefers-color-scheme: dark)" srcset=".github/readme/releases-dark.svg">
  <img src=".github/readme/releases-light.svg" width="100%" alt="Timeline: eight releases from 1.0 on 22 September 2026 to 1.6 on 2 November 2026.">
</picture>

What changed in each version is in [Releases](https://github.com/OZBM/MacLC/releases). To hear about the next one, click GitHub's **Watch** button at the top of this page, then **Custom › Releases**.

## Status

MacLC is in beta and moves fast. It is developed and measured on an M3 Max MacBook Pro, and every release plays a set of sample files before it ships. Not verified yet: Play on TV with real AirPlay and Chromecast receivers (hence the beta label), VoiceOver and Reduce Motion across the library and Watch, a very large real library, and HDR on displays other than that MacBook Pro's. Most of those are donation milestones above.

## Licence, trademarks and credits

MacLC is released under the **GNU General Public License 2.0 or later**. It contains code from VLC, whose engine `libVLC` remains under the LGPL 2.1 or later: see [`COPYING`](COPYING) and [`COPYING.LIB`](COPYING.LIB). As with VLC on some platforms, the distributed app is de facto under the GPL 3.0 because of the licences of some bundled libraries. The complete corresponding source is this repository. The app also contains VideoLAN's `libmedialibrary` and `libdvbpsi` (LGPL 2.1 or later) and TagLib (LGPL 2.1 or MPL 1.1), built from their pinned sources by the scripts above. The SDR to HDR networks were designed and trained for MacLC on Poly Haven's CC0 HDR photographs and are distributed under the LGPL 2.1 or later; the RIFE v4.25 interpolation network comes from [Practical-RIFE](https://github.com/hzwer/Practical-RIFE) (MIT, © 2021 hzwer).

**MacLC is not affiliated with, endorsed by or supported by VideoLAN.** VLC, VideoLAN and the traffic-cone logo are trademarks of VideoLAN; MacLC does not use them. Please report MacLC bugs here, not to VideoLAN. Dolby Vision is a trademark of Dolby Laboratories; other names belong to their owners.

MacLC builds on more than twenty years of work on VLC by the VideoLAN project and many volunteers: thank you. See [`AUTHORS`](AUTHORS) and [`THANKS`](THANKS); the upstream README is kept as [`README.upstream.md`](README.upstream.md).

Pictures on this page show open movies: *Sintel*, *Big Buck Bunny*, *Tears of Steel* and *Elephants Dream* (© Blender Foundation, CC BY), *Cosmos Laundromat* (Andy Goralczyk and the Blender Foundation, CC BY 4.0), *Spring* (Francesco Siddi, Blender Foundation, CC BY 4.0), *Sprite Fright* (Blender Studio, CC BY 4.0) and *Caminandes: Llama Drama* (Pablo Vazquez, Beorn Leonard, Francesco Siddi, CC BY 3.0), and Poly Haven panoramas (CC0).

<p align="center">
  <a href="https://github.com/OZBM/MacLC/releases/latest"><b>Download MacLC</b></a> ·
  <a href="https://www.hazenstudio.com/maclc/"><b>Website</b></a> ·
  <a href="https://www.hazenstudio.com/maclc/donate/"><b>Donate</b></a>
</p>
