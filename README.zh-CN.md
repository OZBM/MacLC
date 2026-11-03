<!-- 译自 README.md：以英文页面为准。 -->

<h1 align="center">
  <a href="https://github.com/OZBM/MacLC/releases/latest">
    <img src=".github/readme/banner.jpg" width="100%" alt="MacLC。什么都能播，让画面熠熠生辉。免费、开源、真 HDR、Apple Silicon。">
  </a>
</h1>

<p align="center">
  <b>免费的 Mac 视频播放器，什么都能播，让画面熠熠生辉。</b><br>
  真 HDR、SDR&nbsp;转&nbsp;HDR、九种画面放大算法、流畅动态、Voice&nbsp;Boost，以及 Apple&nbsp;TV App 风格的媒体库，尽在一款专为 Apple&nbsp;Silicon 原生打造的应用中。
</p>

<p align="center">
  <a href="https://github.com/OZBM/MacLC/releases/latest"><img alt="下载 Mac 版 MacLC" src="https://img.shields.io/github/v/release/OZBM/MacLC?display_name=tag&label=Download%20for%20Mac&style=for-the-badge&logo=apple&logoColor=white&color=e8640c"></a>
  <a href="https://www.hazenstudio.com/maclc/donate/"><img alt="向 MacLC 捐款" src="https://img.shields.io/badge/Donate-PayPal%20or%20card-2f343c?style=for-the-badge&logo=githubsponsors&logoColor=ff8a3d"></a>
</p>

<p align="center">
  <img alt="macOS 26 Tahoe 或更高版本" src="https://img.shields.io/badge/macOS-26%20Tahoe%20or%20later-24292f?logo=apple&logoColor=white">
  <img alt="Apple Silicon，M1 或更新机型" src="https://img.shields.io/badge/Apple%20Silicon-M1%20or%20newer-24292f">
  <img alt="免费、无广告、无追踪" src="https://img.shields.io/badge/free-no%20ads%20%C2%B7%20no%20tracking-24292f">
  <a href="COPYING"><img alt="许可证：GPL 2.0 或更高版本" src="https://img.shields.io/badge/licence-GPL--2.0--or--later-24292f"></a>
</p>

<p align="center">
  <a href="README.md">English</a> · <a href="README.fr.md">Français</a> · <b>简体中文</b> · <a href="README.ja.md">日本語</a> · <a href="README.es.md">Español</a> · <a href="README.de.md">Deutsch</a>
</p>

<picture>
  <source media="(prefers-color-scheme: dark)" srcset=".github/readme/library-dark.webp">
  <img src=".github/readme/library-light.webp" alt="macOS 26 上的 MacLC 媒体库窗口：包含继续观看、最近添加和正在播放胶囊悬浮窗，视频卡片带有 4K、HDR10、HLG 和 Dolby Vision 标识。">
</picture>

## 为什么选择 MacLC

<table>
<tr>
<td width="50%" valign="top">

**什么都能播。** 支持 MKV、MP4、AVI、WebM、TS、AV1、HEVC、FLAC、DTS，以及 SRT、ASS 等多种字幕，连其他播放器拒播的冷门文件也能从容应对。无需安装任何解码器。

</td>
<td width="50%" valign="top">

**真 HDR。** 在 MacBook Pro 或任何 HDR 屏幕上真实还原 Dolby Vision、HDR10+、HDR10 和 HLG 的高光表现，同时将字幕保持在舒适柔和的白色。

</td>
</tr>
<tr>
<td valign="top">

**SDR 转 HDR。** 让普通视频也能用上屏幕的额外亮度：灯光、天空与反光自然发亮，而肤色与暗部依然贴近拍摄原貌。

</td>
<td valign="top">

**更清晰，更流畅。** 内置九种 GPU 画面放大算法（MetalFX、FSR、NIS、Anime4K 等），让小尺寸视频在大屏上依然清晰；支持帧插值至屏幕刷新率，在 ProMotion 屏幕上可达 120&nbsp;Hz。

</td>
</tr>
<tr>
<td valign="top">

**纯正的 Mac 应用。** 采用 Liquid Glass 设计，具备原生的 Mac 菜单与快捷键、Apple TV App 风格的媒体库，以及把每个开关的作用讲得明明白白的设置界面。

</td>
<td valign="top">

**不止于此。** 让对白更清晰的 Voice Boost、浏览扩展片单的 Watch、边下边播的种子播放、YouTube 支持（配合免费的 yt-dlp），以及 Play on TV（测试版）。

</td>
</tr>
</table>

<p align="center"><b>免费。无广告、无需账号、无追踪。</b>基于 GPL 开源。</p>

## 充分释放屏幕潜力的 HDR

MacBook Pro 的屏幕能呈现出比普通白色亮数倍的高光，MacLC 正是围绕这一特性打造的。

- **Dolby Vision、HDR10+、HDR10 和 HLG**，均以当前屏幕最理想的方式呈现，包括 iPhone 拍摄的 HDR 视频。
- **在每块屏幕上都有恰当的亮度。** MacLC 会测量每个窗口所在屏幕的显示能力，当你把窗口移到另一台显示器时也会重新测量。
- **普通屏幕也能看 HDR**，画面会根据屏幕所能呈现的范围自然适配，而不会过曝成死白。
- **不刺眼的字幕。** 字幕保持柔和的白色，不会像影片中最亮的高光那样晃眼。
- **AV1 硬件解码**支持 M3 及更新机型，其他机型则使用 AV1 软件解码。

MacLC 自研的 Metal 视频引擎负责渲染 Dolby Vision 和 HDR10+，并修复了底层原有代码中的六处 HDR 缺陷（[详见下文](#底层原理)）。

### SDR 转 HDR：善用屏幕富余的亮度

**正在用 MacBook Pro 阅读本页？不妨用 Safari 看看下面这张图。** 图中内嵌了真正的 HDR 版本：右侧画面经过 MacLC 的 SDR 转 HDR 曲线处理，太阳与天空比本页的白色还要明亮。在其他屏幕上，左右两幅画面看起来一致——这正是设计初衷：MacLC 保留你熟悉的画面观感，只把屏幕多出来的亮度留给高光。

<p align="center">
  <img src=".github/readme/sdr-to-hdr-split.jpg" width="100%" alt="开源电影 Sintel 同一帧画面的左右对比：左侧为原始画面，右侧经 MacLC 的 SDR 转 HDR 处理。在支持 HDR 图片的浏览器与 HDR 屏幕上，右侧的太阳和天空会呈现明亮光感。">
</p>

<picture>
  <source media="(prefers-color-scheme: dark)" srcset=".github/readme/sdr-to-hdr-curve-dark.svg">
  <img src=".github/readme/sdr-to-hdr-curve-light.svg" width="100%" alt="图表：当 SDR 转 HDR 设为 Balanced 档位时，信号下方的 90% 与原片完全一致；高于该部分时，小面积高光可升至 400 cd/m²，大面积明亮区域升至 190，而原片上限为 100。">
</picture>

你可以从 Fast 到 Maximum 之间选择档位，或交给 Auto 挑选你的 Mac 能跟得上的档位。High 和 Maximum 使用专为 MacLC 训练的轻量神经网络，在 M3 Max 上每帧仅需约半毫秒。你可以自行设定高光亮度上限，按住 **Hold to Compare** 即可随时对比原片。

<p align="center">
  <img src=".github/readme/sdr-to-hdr.webp" width="100%" alt="MacLC 播放 Sintel 并打开 SDR 转 HDR 面板：显示画质档位、效果曲线，以及调节高光亮度上限的滑块。">
</p>

## 更清晰，更流畅

**画面放大。** 在 5K 显示器上看 720p 剧集，不该只是一片模糊。MacLC 通过 GPU 放大低分辨率视频，提供九种方式可选，面板中对每种方式都有直白易懂的说明：

| 方式 | 适用场景 |
|---|---|
| Auto | 自动为你选择：低分辨率视频优先使用 Apple 超分辨率，其次使用 MetalFX |
| Apple Neural 4x | Apple 的 4× 神经网络模型（需从 Apple 一次性下载）；当 Mac 性能吃紧时自动回退至 2× |
| Anime 与 Anime4K | 手绘动画：线条干净、平涂色彩纯粹 |
| FSRCNNX | 丰富细节（仅在你同意其许可证后下载） |
| Sharp (AMD FSR 1) 与 NIS (NVIDIA Image Scaling) | 边缘锐利，几乎没有性能开销 |
| Efficient (MetalFX) | 兼顾电池续航 |
| Classic (EWA Lanczos) | 尽可能忠于片源原貌 |

Apple 的神经网络模型、Anime、Anime4K 和 FSRCNNX 适用于 8 位 SDR 视频；对于 HDR、10 位视频以及开启 SDR 转 HDR 的情况，MacLC 会使用其余方式。

**Compare Before and After。** 将正在观看的视频画面从中一分为二：左侧不开启 SDR 转 HDR、画面放大与帧插值，右侧开启。

**流畅动态。** 帧插值可将 24 fps 提升至屏幕刷新率：60 Hz、ProMotion MacBook Pro 上的 120 Hz，或高刷新率外接显示器的更高帧率。自动模式会挑选能实时跟上的算法；你也可以手动选择光流法或神经网络 RIFE。该功能默认关闭，因为追求原汁原味电影感的人说得也没错。

<picture>
  <source media="(prefers-color-scheme: dark)" srcset=".github/readme/motion-demo-dark.svg">
  <img src=".github/readme/motion-demo-light.svg" width="100%" alt="动态示意图：圆点在每秒 24 帧下呈明显跳跃移动，插值到每秒 120 帧后则平滑移动。">
</picture>

<p align="center">
  <img src=".github/readme/motion.webp" width="100%" alt="Sintel 画面上方打开的 MacLC 动态插值面板：帧插值已开启，方式为自动，帧率匹配显示器，正将 24 fps 以 120 fps 播放。">
</p>

## 值得常打开的媒体库

指定文件夹后，MacLC 就会构建一个 Apple TV App 风格的媒体库：**主页**展示你正在观看的内容，下方依次是**视频、剧集、艺人、专辑、歌曲、类型、个人收藏和播放列表**。形如 `Show S01E02` 命名的剧集会自动按季归类，卡片上带有 **Dolby Vision、HDR10、HLG 和 4K** 标识，浏览时还有悬浮的“正在播放”胶囊窗保持画面播放。你的本地文件绝不会被移动。

**Watch** 以 Apple TV App 的风格浏览电影与剧集片单，包含精选推荐、分类展架、Top 10 榜单、类型筛选，以及带有演职员表和分集列表的详情页。内置的 Cinemeta 提供海报、简介与搜索功能；具体可播放的内容取决于你安装的扩展插件，支持 [Stremio 扩展协议](https://github.com/Stremio/stremio-addon-sdk/blob/master/docs/protocol.md)。个人收藏、观看历史与“继续观看”均保存在你的 Mac 本地。

<picture>
  <source media="(prefers-color-scheme: dark)" srcset=".github/readme/watch-dark.webp">
  <img src=".github/readme/watch-light.webp" alt="MacLC 的 Watch 页面：上方为精选轮播图，下方为 Blender 开源电影 Top 10 展架。">
</picture>

- **种子边下边播。** 打开 `.torrent` 文件或粘贴磁力链接，校验完几秒钟内容后即可开始播放，进度条上的标记会显示已缓冲范围、速度与连接节点数。
- **YouTube**，支持首页、订阅内容、稍后观看、播放列表和搜索。该功能需要免费的 [`yt-dlp`](https://github.com/yt-dlp/yt-dlp)，MacLC 会直接展示安装它所需的那一条命令。登录为可选项：可在 Google 官方页面登录，也可直接使用已登录浏览器的会话。MacLC 仅在你的 Mac 本地私有文件中保存 yt-dlp 所需的会话 Cookie，退出登录即会将其删除。
- **Play on TV（测试版）。** 将正在播放的内容投送到 Apple TV、其他 AirPlay 接收端或 Chromecast。

MacLC 不附带任何电影、剧集或流媒体源。扩展插件均为第三方服务，请仅将其用于你有权观看的内容。

## 听得清的对白

<img src=".github/readme/sound-dark.webp" align="right" width="260" alt="MacLC 的声音面板：已选中 Voice Boost，下方为强度滑块与声音模式列表。">

**Voice Boost** 能在不拉高背景音乐的前提下让对白更清晰。播放 5.1 声道影片时，它会提升中置声道（实测对白增益优势 +7.4&nbsp;dB）；播放立体声时，它会通过 Apple 的 vDSP 实时分离混音中央的人声（真实混音实测在 1 至 4&nbsp;kHz 人声频段提升 +4.8&nbsp;dB，延迟约 16&nbsp;ms）。

此外还有**夜间、影院、音乐、低音增强、口语、耳机和小型扬声器**模式，每种模式均配有强度滑块，并内置 **10 段均衡器**（⌥⌘E）以及防止大音量场景削波的限制器。

<br clear="right">

## 一看就懂的设置

一个窗口、一个侧边栏加一个搜索框。每一行都从你实际会看到或听到的效果出发，说明开关的作用。专业设置依然保留，收纳在展开项之后。

<picture>
  <source media="(prefers-color-scheme: dark)" srcset=".github/readme/settings-hdr-dark.webp">
  <img src=".github/readme/settings-hdr-light.webp" alt="MacLC 的 HDR 与色彩设置：实时显示当前显示器的亮度余量状态、四个各附一句话说明的播放模式，以及 SDR 转 HDR 选项。">
</picture>

## 横向对比

|  | **MacLC** | IINA | Infuse | QuickTime Player |
|---|:---:|:---:|:---:|:---:|
| 几乎支持所有视频文件 | ✅ | ✅ | ✅ 部分音频需 Pro 版 | ❌ 主要支持 MP4 和 MOV |
| 在 HDR 屏幕上播放 HDR 视频 | ✅ | ✅ | ✅ | ✅ |
| 让普通视频在 HDR 屏幕上焕发光彩（SDR 转 HDR） | ✅ | ❌ | ❌ | ❌ |
| 内置画面放大算法 | ✅ 九种 | ➖ 需自行安装着色器 | ✅ 一种 AI 模式 | ❌ |
| 流畅动态（帧插值） | ✅ 内置 | ➖ 需通过 mpv 参数配置 | ❌ | ❌ |
| 一键增强对白 | ✅ Voice Boost | ❌ 需手动配置滤镜 | ❌ 仅整体提高音量 | ❌ |
| 本地视频媒体库 | ✅ 含音乐管理 | ❌ 播放列表与历史记录 | ✅ 主打强项 | ❌ |
| 扩展片单与种子播放 | ✅ | ❌ | ❌ | ❌ |
| YouTube 与网页视频 | ✅ 配合 yt-dlp | ✅ 配合 yt-dlp | ❌ | ❌ |
| 免费 | ✅ | ✅ | ➖ Pro 版付费 | ✅ 随 macOS 附带 |
| 开源 | ✅ GPL | ✅ GPL | ❌ | ❌ |

<sub>于 2026 年 11 月 3 日对照各播放器官方文档与发行说明核实。IINA 同样非常出色，并且免费开源。</sub>

## 安装

<p>
  <a href="https://github.com/OZBM/MacLC/releases/latest"><img alt="下载 MacLC" src="https://img.shields.io/github/v/release/OZBM/MacLC?display_name=tag&label=Download&style=for-the-badge&logo=apple&logoColor=white&color=e8640c"></a>
</p>

1. 从[最新发布页面](https://github.com/OZBM/MacLC/releases/latest)下载 `maclc-1.6.dmg`（57.8 MB）。
2. 打开它，将 **MacLC** 拖入**应用程序**。
3. 打开 MacLC。首次打开时 macOS 会拦截：点击**完成**，然后打开**系统设置 › 隐私与安全性**，滚动到**安全性**，点击“已阻止使用 MacLC”旁边的**仍要打开**，再用 Touch ID 或密码确认。每个版本只需操作这一次。

> [!NOTE]
> **为什么需要多点这一步？** 只有当开发者每年向 Apple 支付 99 欧元购买 Developer ID 并为每个版本完成公证后，macOS 才允许直接双击打开应用。MacLC 是免费应用，目前尚未筹齐这笔费用。**收到的前 99 欧元捐款将为所有人省去这一步。** [捐款支持](https://www.hazenstudio.com/maclc/donate/)

<details>
<summary>终端替代方法、校验和与系统要求</summary>

除了点击**仍要打开**，你也可以移除“从互联网下载”标记：

```bash
xattr -dr com.apple.quarantine /Applications/MacLC.app
```

核对你下载的文件与发布版本完全一致（预期值见发布页面；1.6 版本为 `194de0b42a836985dba92a75d283264e21b4285f5a24934769b0e2aad5aae805`）：

```bash
shasum -a 256 ~/Downloads/maclc-1.6.dmg
```

如果 macOS 提示 MacLC“已损坏，无法打开”，说明下载不完整：请将其删除并重新下载，切勿绕过该提示。

**系统要求**

- 搭载 Apple Silicon（M1 或更新机型）的 Mac。不支持 Intel Mac。
- macOS 26 Tahoe 或更高版本。
- SDR 转 HDR 需要亮度能超过普通白色的屏幕（配备 XDR 显示屏的 MacBook Pro、Pro Display XDR 或 HDR 显示器）。其余所有功能在任何屏幕上均可使用。
- 可选：用于播放 YouTube 和网页视频的 [`yt-dlp`](https://github.com/yt-dlp/yt-dlp)（`brew install yt-dlp`）。

应用完全自包含：内置 FFmpeg、libass、libplacebo、libtorrent 及约 140 个其他依赖库，其许可证位于 `MacLC.app/Contents/Resources/Licenses/`。

</details>

## 支持 MacLC

MacLC 是一个个人项目：无广告、无订阅、没有数据可卖。捐款将按以下顺序，用于支付免费应用无法靠自身获得的条件：

<picture>
  <source media="(prefers-color-scheme: dark)" srcset=".github/readme/donation-milestones-dark.svg">
  <img src=".github/readme/donation-milestones-light.svg" width="100%" alt="捐款解锁目标：99 欧元，告别“仍要打开”（完成 Apple 公证）；400 欧元，Play on TV 结束测试转正；900 欧元，购入第二块 HDR 屏幕用于测试；1,600 欧元，全面适配辅助功能；2,500 欧元，支持应用自动更新。">
</picture>

**每份心意都附带一个心愿。** 告诉我你希望 MacLC 接下来做什么，或者支持列表中已有的心愿：支持人数最多的心愿优先开发。可在[捐款页面](https://www.hazenstudio.com/maclc/donate/)使用 PayPal 或银行卡支付，页面实时显示已筹总额。

<p align="center">
  <a href="https://www.hazenstudio.com/maclc/donate/"><img alt="捐款并许下心愿" src="https://img.shields.io/badge/Donate%20and%20make%20a%20wish-%E2%82%AC5%20%C2%B7%20%E2%82%AC15%20%C2%B7%20%E2%82%AC30%20%C2%B7%20%E2%82%AC99-e8640c?style=for-the-badge&logo=githubsponsors&logoColor=white"></a>
</p>

**手头不便？以下方式同样很有帮助：**

- ⭐ **为本仓库点 Star。** Star 是大家在 GitHub 上发现 MacLC 的途径。
- **推荐给他人。** 分享到 [X](https://x.com/intent/post?text=MacLC%3A%20the%20free%20video%20player%20for%20Mac%20that%20plays%20everything%2C%20with%20real%20HDR%2C%20SDR%20to%20HDR%2C%20upscaling%20and%20smooth%20motion.&url=https%3A%2F%2Fgithub.com%2FOZBM%2FMacLC)、[Bluesky](https://bsky.app/intent/compose?text=MacLC%3A%20the%20free%20video%20player%20for%20Mac%20that%20plays%20everything%2C%20with%20real%20HDR%2C%20SDR%20to%20HDR%2C%20upscaling%20and%20smooth%20motion.%20https%3A//github.com/OZBM/MacLC)、[Reddit](https://www.reddit.com/submit?url=https%3A%2F%2Fgithub.com%2FOZBM%2FMacLC&title=MacLC%3A%20a%20free%2C%20open-source%20video%20player%20for%20Mac%20with%20real%20HDR%20and%20SDR%20to%20HDR) 或 [LinkedIn](https://www.linkedin.com/sharing/share-offsite/?url=https%3A%2F%2Fgithub.com%2FOZBM%2FMacLC)。
- **反馈你遇到的问题。** 无法播放的文件、崩溃或色彩错误：请[提交 Issue](https://github.com/OZBM/MacLC/issues/new)，附上你的操作步骤与预期表现。
- **在你的屏幕上测试。** 目前 MacLC 的 HDR 仅在一台 MacBook Pro 上验证过。如果你有其他 HDR 显示器，欢迎告诉我显示效果如何。

## 常见问题

<details>
<summary><b>MacLC 真的免费吗？</b></summary>

是的。没有付费版、没有订阅、没有广告、无需账号，也没有任何功能保留。它基于 GPL 2.0 或更高版本开源。
</details>

<details>
<summary><b>它安全吗？为什么首次打开时会被 macOS 拦截？</b></summary>

全部源代码都在本仓库公开，且 MacLC 不含任何统计分析或追踪功能，不会向开发者或任何其他人上报你观看的内容。Watch、YouTube 和种子功能会像常规应用一样连接各自使用的服务。macOS 首次拦截 MacLC，只是因为它尚未经过 Apple 公证，而公证每年需花费 99 欧元（见[安装](#安装)）。每次发布都会公布磁盘映像的 SHA-256 校验和，方便你核对下载文件。
</details>

<details>
<summary><b>我需要 HDR 屏幕吗？</b></summary>

不需要。MacLC 可在任何 Mac 屏幕上播放所有视频，并会将 HDR 影片适配到普通屏幕上显示。只有 SDR 转 HDR 需要亮度能超过普通白色的屏幕。
</details>

<details>
<summary><b>支持 Intel Mac，或 macOS 15 及更早版本吗？</b></summary>

不支持。MacLC 面向 Apple Silicon 与 macOS 26 Tahoe 或更高版本，其随附的依赖库同样要求 macOS 26。
</details>

<details>
<summary><b>如何更新？</b></summary>

前往 [Releases](https://github.com/OZBM/MacLC/releases) 下载新版磁盘映像并替换原应用即可。自动更新已列入捐款路线图。若想接收新版本通知，请点击本页顶部的 GitHub **Watch** 按钮，然后选择 **Custom › Releases**。
</details>

<details>
<summary><b>流畅动态会不会让电影看起来像肥皂剧？</b></summary>

有可能，所以它默认关闭。很多人喜欢在看体育赛事、自然纪录片和动画时开启它，而在看电影时保留经典的 24 帧观感。不妨在同一段画面上对比试试。
</details>

<details>
<summary><b>MacLC 自带电影或剧集吗？</b></summary>

不自带。MacLC 仅播放你自己的文件以及你主动打开的内容。Watch 展示的是你选择安装的扩展插件所提供的片单，这些扩展属于第三方服务，请仅将其用于你有权观看的内容。
</details>

## 底层原理

MacLC 基于 VLC 4 的部分开源代码构建，核心是其播放引擎（`libVLC`）。界面、媒体库与 Watch、Metal 视频输出、HDR 管线、SDR 转 HDR、画面放大、动态插值、Voice Boost 以及 AirPlay 均为 MacLC 全新编写或重构，仅面向运行在 Apple Silicon 上的 macOS。

<details>
<summary><b>HDR 管线：修复继承代码中的六处缺陷</b></summary>

基于对 Apple Silicon 上 VLC 4.0.0-dev 的 macOS HDR 路径审计（2026 年 9 月 2 日，基线 `99034f9`）：

| 缺陷 | 原有表现 | 修复方式 |
|---|---|---|
| 仅从 `[NSScreen mainScreen]` 读取一次 EDR 亮度余量 | 将窗口移至另一台显示器后，HDR 亮度不正确 | 在屏幕切换、色彩配置文件及显示参数变化时重新评估余量 |
| HDR 模式与 EDR 余量偏好设置无效 | 设置项形同摆设 | 接入实时变量回调，播放过程中即时生效 |
| 缺少 SDR 色调映射分支 | HDR 影片在 SDR 屏幕上过曝成死白 | 使用 `CADynamicRangeStandard` 配合 `CAToneMapModeAutomatic`，并提供 BT.709 重标记回退 |
| PQ 视频上的字幕未标记色彩空间 | 暗场画面上白色字幕以 PQ 满亮度刺眼发光 | 将字幕图层标记为 sRGB，并缩放至 BT.2408 参考白 |
| 高于 10 位的 HEVC 被下采样为 8 位 BGRA | 12 位与 16 位片源在送显前丢失位深 | 路由至 P010；16 位 4:2:2 通过 CVPX 辅助函数直通 |
| 低于 4K 的 HDR 被误标为 BT.709，且输出 0 尼特的母版色彩容积 | 广色域内容以错误的原色显示 | 按视频流正确标记色域，确保母版色彩容积绝不为零 |

此外还实现了：HDR10+ 动态元数据贯穿滤镜链传递、从 VideoToolbox 码流提取 Dolby Vision 元数据（MacLC 的 Metal 引擎支持 Profile 5 与 8.1，以及来自 iPhone 的 8.4）、向显示层转发 ST 2086 与 CTA-861.3 元数据、按窗口独立应用 ICC 色彩配置文件、M3 及更新机型的 AV1 硬件解码，以及 ARM64 NEON 色度转换。
</details>

<details>
<summary><b>SDR 转 HDR 的工作原理</b></summary>

画面先经线性化处理，每个像素的驱动值取其亮度与最亮通道 85% 二者中的较大值。Fast 沿固定二次曲线提升高于 SDR 白点一半的驱动值；Balanced 仅提升高于漫射白的部分，且当画面存在大面积高亮时自动收窄提升幅度。在这两种模式下，三通道按同一系数缩放，因此色相与饱和度保持不变。High 和 Maximum 使用两个专为 MacLC 训练的轻量网络，为每个场景预测亮度增益网格，并将单通道增益限制在亮度增益的 0.2（对数域）以内。输出结果会限制在屏幕的实际亮度余量之内，并在接近上限处平滑滚降，同时打上标记以免系统合成器将其再次色调映射压暗。本身已是 HDR 的片源保持原样不作处理。数学公式见 [`maclc_sdr2hdr.h`](modules/video_output/apple/maclc_sdr2hdr.h)，Metal 核函数见 [`VLCHDRExpander.m`](modules/video_output/apple/VLCHDRExpander.m)。
</details>

<details>
<summary><b>画面放大引擎、性能开销与许可证</b></summary>

当窗口尺寸至少为视频尺寸的 1.2 倍时，MacLC 的 Metal 视频输出会启用画面放大。M3 Max 实测耗时：MetalFX 空间放大每帧 0.4 至 0.84 ms，AMD FSR 1 从 720p 放大至 1440p 约 0.5 ms，NIS 从 720p 放大至 4K 为 1.19 ms，ArtCNN 从 540p 放大至 1080p 约 2.1 ms。在使用电池供电、处于低电量模式、Mac 发热，或单帧耗时将超过其时间预算的 60% 时，神经网络模型会自动停用让位。内置的转换器可运行 mpv 风格的 hook 着色器，Anime4K 和 FSRCNNX 正是借此在 Metal 中运行的。

许可证：NIS 与 FSR 1（MIT，原样保留 NVIDIA 与 AMD 的声明）、Anime4K 与 ArtCNN（MIT）、FSRCNNX（LGPL-3.0，仅在你同意其许可证后下载）、MetalFX 与 VideoToolbox 超分辨率（Apple 系统框架）。
</details>

<details>
<summary><b>新增命令行选项</b></summary>

| 选项 | 取值 | 作用 |
|---|---|---|
| `--macosx-hdr-mode` | 0 至 3 | 0 为 Auto，1 为强制原生 HDR，2 为色调映射至 SDR，3 为关闭 HDR |
| `--macosx-edr-headroom` | float | 0 为跟随屏幕；1 及以上为强制指定亮度余量 |
| `--macosx-sdr-to-hdr` | bool | 将 SDR 视频扩展至屏幕的扩展动态范围 |
| `--macosx-sdr-to-hdr-boost` | 1 至 16 | 高光可超出 SDR 白点的倍数上限（默认 4） |
| `--macosx-sdr-to-hdr-quality` | auto, fast, balanced, high, maximum | SDR 转 HDR 档位 |
| `--maclc-upscale`, `--maclc-upscale-method` | bool, string | 开启或关闭画面放大，以及所用的放大方式 |

</details>

<details>
<summary><b>从源代码构建</b></summary>

MacLC 在搭载 Apple Silicon 的 Mac 上使用 autotools 配合 Homebrew 依赖库进行构建。Meson 不会构建 macOS 界面：请使用 autotools，或使用 Xcode 项目进行界面开发。

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

配置时需将 `build-deps/prefix/lib/pkgconfig` 和 `build-deps/pkgconfig` 置于 `PKG_CONFIG_PATH` 最前；重新生成 `Makefile.in` 需要 `automake` 1.18；任何使用了 `_NS("…")` 的文件都必须列入 `po/POTFILES.in`。单元测试（308 项，XCTest）可在 `build/modules` 中通过 `make check-macosx` 运行，`MACLC_SELFTEST=1` 则会在启动时构建各主要设置面板并报告显示结果。应用图标由仓库中的 Swift 程序 [`maclc_app_icon.swift`](extras/package/macosx/asset_sources/maclc_app_icon.swift) 绘制生成。
</details>

## 版本发布

<picture>
  <source media="(prefers-color-scheme: dark)" srcset=".github/readme/releases-dark.svg">
  <img src=".github/readme/releases-light.svg" width="100%" alt="时间线：从 2026 年 9 月 22 日的 1.0 到 2026 年 11 月 2 日的 1.6，共八个版本。">
</picture>

每个版本的更新内容见 [Releases](https://github.com/OZBM/MacLC/releases)。若想获知下一版本的消息，请点击本页顶部的 GitHub **Watch** 按钮，然后选择 **Custom › Releases**。

## 当前状态

MacLC 目前处于测试阶段，迭代迅速。它在 M3 Max MacBook Pro 上开发与实测，每个版本在发布前都会实际播放一组样片进行验证。目前尚未验证的项目：配合真实 AirPlay 与 Chromecast 接收端使用 Play on TV（因此标为测试版）、在媒体库和 Watch 中使用“旁白”与“减弱动态效果”、超大规模的真实媒体库，以及除这台 MacBook Pro 以外其他显示器上的 HDR 表现。以上大部分项目都对应上文的捐款里程碑。

## 许可证、商标与致谢

MacLC 基于 **GNU 通用公共许可证 2.0 或更高版本**发布。其中包含来自 VLC 的代码，其引擎 `libVLC` 仍遵循 LGPL 2.1 或更高版本：详见 [`COPYING`](COPYING) 与 [`COPYING.LIB`](COPYING.LIB)。与部分平台上的 VLC 一样，由于随附的部分依赖库所采用的许可证，分发的应用实际上遵循 GPL 3.0。完整的对应源代码即本仓库。应用还包含由上文脚本基于固定版本源码构建的 VideoLAN `libmedialibrary` 与 `libdvbpsi`（LGPL 2.1 或更高版本），以及 TagLib（LGPL 2.1 或 MPL 1.1）。SDR 转 HDR 神经网络专为 MacLC 设计，基于 Poly Haven 的 CC0 HDR 摄影图像训练，并按 LGPL 2.1 或更高版本分发；RIFE v4.25 插值网络来自 [Practical-RIFE](https://github.com/hzwer/Practical-RIFE)（MIT，© 2021 hzwer）。

**MacLC 与 VideoLAN 没有任何隶属关系，亦未获得其背书或支持。** VLC、VideoLAN 及交通锥标志均为 VideoLAN 的商标；MacLC 不使用这些商标。请在此处报告 MacLC 的问题，切勿提交给 VideoLAN。Dolby Vision 是 Dolby Laboratories 的商标；其他名称均归其各自所有者所有。

感谢 VideoLAN 项目以及众多志愿者二十年来在 VLC 上的付出，MacLC 正是建立在这些成果之上：详见 [`AUTHORS`](AUTHORS) 与 [`THANKS`](THANKS)；上游 README 保留为 [`README.upstream.md`](README.upstream.md)。

本页图片展示了以下开源电影：*Sintel*、*Big Buck Bunny*、*Tears of Steel* 和 *Elephants Dream*（© Blender Foundation，CC BY），*Cosmos Laundromat*（Andy Goralczyk 与 Blender Foundation，CC BY 4.0），*Spring*（Francesco Siddi、Blender Foundation，CC BY 4.0），*Sprite Fright*（Blender Studio，CC BY 4.0）以及 *Caminandes: Llama Drama*（Pablo Vazquez、Beorn Leonard、Francesco Siddi，CC BY 3.0），另有 Poly Haven 全景图（CC0）。

<p align="center">
  <a href="https://github.com/OZBM/MacLC/releases/latest"><b>下载 MacLC</b></a> ·
  <a href="https://www.hazenstudio.com/maclc/"><b>官方网站</b></a> ·
  <a href="https://www.hazenstudio.com/maclc/donate/"><b>捐款支持</b></a>
</p>
