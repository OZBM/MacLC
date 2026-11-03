<!-- README.md の翻訳：英語ページが基準です。 -->

<h1 align="center">
  <a href="https://github.com/OZBM/MacLC/releases/latest">
    <img src=".github/readme/banner.jpg" width="100%" alt="MacLC。なんでも再生。映像を輝かせる。無料、オープンソース、本物のHDR、Apple Silicon。">
  </a>
</h1>

<p align="center">
  <b>なんでも再生し、映像を輝かせる、Mac用の無料ビデオプレーヤー。</b><br>
  本物のHDR、SDR&nbsp;to&nbsp;HDR、9種類のアップスケーラー、なめらかな動き、Voice&nbsp;Boost、そしてApple&nbsp;TVアプリ風のライブラリを、Apple&nbsp;Siliconネイティブの1つのアプリに。
</p>

<p align="center">
  <a href="https://github.com/OZBM/MacLC/releases/latest"><img alt="Mac用 MacLC をダウンロード" src="https://img.shields.io/github/v/release/OZBM/MacLC?display_name=tag&label=Download%20for%20Mac&style=for-the-badge&logo=apple&logoColor=white&color=e8640c"></a>
  <a href="https://www.hazenstudio.com/maclc/donate/"><img alt="MacLC に寄付する" src="https://img.shields.io/badge/Donate-PayPal%20or%20card-2f343c?style=for-the-badge&logo=githubsponsors&logoColor=ff8a3d"></a>
</p>

<p align="center">
  <img alt="macOS 26 Tahoe 以降" src="https://img.shields.io/badge/macOS-26%20Tahoe%20or%20later-24292f?logo=apple&logoColor=white">
  <img alt="Apple Silicon、M1 以降" src="https://img.shields.io/badge/Apple%20Silicon-M1%20or%20newer-24292f">
  <img alt="無料、広告なし、トラッキングなし" src="https://img.shields.io/badge/free-no%20ads%20%C2%B7%20no%20tracking-24292f">
  <a href="COPYING"><img alt="ライセンス：GPL 2.0 以降" src="https://img.shields.io/badge/licence-GPL--2.0--or--later-24292f"></a>
</p>

<p align="center">
  <a href="README.md">English</a> · <a href="README.fr.md">Français</a> · <a href="README.zh-CN.md">简体中文</a> · <b>日本語</b> · <a href="README.es.md">Español</a> · <a href="README.de.md">Deutsch</a>
</p>

<picture>
  <source media="(prefers-color-scheme: dark)" srcset=".github/readme/library-dark.webp">
  <img src=".github/readme/library-light.webp" alt="macOS 26 上の MacLC のライブラリウインドウ：「視聴を続ける」「最近追加した項目」と再生中カプセルが並び、各動画に 4K、HDR10、HLG、Dolby Vision のバッジが表示されている。">
</picture>

## MacLC を選ぶ理由

<table>
<tr>
<td width="50%" valign="top">

**なんでも再生。** MKV、MP4、AVI、WebM、TS、AV1、HEVC、FLAC、DTS、SRTやASSなどの字幕、さらには他のプレーヤーが受け付けない珍しいファイルまで対応。コーデックの追加インストールは不要です。

</td>
<td width="50%" valign="top">

**本物のHDR。** Dolby Vision、HDR10+、HDR10、HLG本来のハイライトをMacBook ProやあらゆるHDR画面で再現。字幕は目に優しい落ち着いた白に保ちます。

</td>
</tr>
<tr>
<td valign="top">

**SDR to HDR。** 通常の映像でも画面の余剰輝度を活用。照明や空、反射光が輝きを帯びる一方、肌や暗部は撮影されたままのトーンに近い状態で保たれます。

</td>
<td valign="top">

**よりシャープに、よりなめらかに。** 小さな映像を大画面向けに拡大する9種類のGPUアップスケーラー（MetalFX、FSR、NIS、Anime4K…）と、ProMotionの120&nbsp;Hzをはじめ画面のリフレッシュレートまで引き上げるフレーム補間を搭載。

</td>
</tr>
<tr>
<td valign="top">

**正統派のMacアプリ。** Liquid Glass、Mac標準のメニューとショートカット、Apple TVアプリ風のライブラリ、そして各スイッチの働きがそのまま書かれた設定画面を備えています。

</td>
<td valign="top">

**さらに多彩な機能。** セリフをクリアにするVoice Boost、アドオンカタログを楽しめるWatch、ダウンロードしながら再生できるトレント、YouTube（無料のyt-dlpを使用）、Play on TV（ベータ）。

</td>
</tr>
</table>

<p align="center"><b>無料。広告なし、アカウント不要、トラッキングなし。</b> GPLに基づくオープンソースです。</p>

## 画面の力をすべて引き出すHDR

MacBook Proの画面は、通常の白の数倍もの明るさでハイライトを表示できます。MacLCは、その性能を前提に設計されています。

- **Dolby Vision、HDR10+、HDR10、HLG** — iPhoneで撮影したHDRビデオを含め、お使いの画面に最も適した形で表示します。
- **どの画面でも適切な明るさに。** MacLCはウインドウが表示されている画面を測定し、ウインドウを別のディスプレイへ移動すると再測定します。
- **通常の画面でもHDR再生に対応。** 平坦な白に白飛びさせるのではなく、その画面が表示できる範囲に合わせて収めます。
- **まぶしくない字幕。** 映画の最も明るいハイライトのように光るのではなく、落ち着いた白に保たれます。
- M3以降では**ハードウェアAV1**、それ以外ではソフトウェアAV1に対応。

MacLC独自のMetalビデオエンジンがDolby VisionとHDR10+を描画し、ベースとなったコードで見つかった6つのHDR不具合も修正されています（[詳細](#内部の仕組み)）。

### SDR to HDR：画面の余力を光に変える

**MacBook Proでこのページをご覧なら、下の画像をSafariで見てみてください。** 実際のHDRデータが埋め込まれており、右側の画像はMacBook ProでSDR to HDRをMaximumレベルにしたときにMacLCが実際に表示した映像をアプリから取り込んだもので、太陽とその周りの空がこのページの白よりも明るく輝いて見えます。それ以外の画面では左右どちらも同じに見えますが、まさにそこがポイントです。MacLCは元の映像の印象をそのまま保ち、画面が持つ余剰の光だけをハイライトに注ぎます。

<p align="center">
  <img src=".github/readme/sdr-to-hdr-split.jpg" width="100%" alt="オープンムービー Sintel の同じフレームを2つ並べた比較：左は撮影されたままの映像、右は MacLC の SDR to HDR が実際に表示した映像をアプリから取り込んだもの。HDR画像を表示できるブラウザとHDR画面で見ると、右側の太陽が輝いて見える。">
</p>

<picture>
  <source media="(prefers-color-scheme: dark)" srcset=".github/readme/sdr-to-hdr-curve-dark.svg">
  <img src=".github/readme/sdr-to-hdr-curve-light.svg" width="100%" alt="グラフ：SDR to HDR を Balanced レベルにした場合、信号の下位90%は元の映像とまったく同じに表示され、それを超える領域では元の映像が 100 cd/m² で止まるところ、小さなハイライトは 400 cd/m²、広い明部は 190 cd/m² まで伸びる。">
</picture>

レベルは Fast から Maximum まで選べるほか、Auto に任せればお使いのMacで処理が追いつくレベルが自動で選ばれます。High と Maximum ではMacLC専用に学習された軽量ニューラルネットワークを使用し、M3 Maxでの処理時間は1フレームあたり約0.5ミリ秒です。ハイライトの明るさの上限も自分で設定でき、**Hold to Compare** を押している間は元の映像を表示して比較できます。

<p align="center">
  <img src=".github/readme/sdr-to-hdr.webp" width="100%" alt="SDR to HDR パネルを開いて Sintel を再生中の MacLC：品質レベル、効果のカーブ、ハイライトの明るさの上限を調整するスライダーが表示されている。">
</p>

## よりシャープに、よりなめらかに

**アップスケーリング。** 5Kディスプレイで観る720pのエピソードが、ぼやけたままではもったいないはずです。MacLCは小さな映像をGPUで拡大します。9種類の方式から選べ、パネル内ではそれぞれの特徴が平易な言葉で説明されています。

| 方式 | 適した用途 |
|---|---|
| Auto | 自動選択：小さな映像にはAppleの超解像、それ以外はMetalFXを使用 |
| Apple Neural 4x | Appleの4×ニューラルモデル（初回のみAppleからダウンロード）。Macの処理が追いつかないときは2×に切り替え |
| Anime と Anime4K | 手描きアニメーション：すっきりした線、フラットな色面 |
| FSRCNNX | 精細なディテール（ライセンスに同意した場合のみダウンロード） |
| Sharp (AMD FSR 1) と NIS (NVIDIA Image Scaling) | ほぼ負荷なしで輪郭をくっきり表示 |
| Efficient (MetalFX) | バッテリー駆動時間の重視 |
| Classic (EWA Lanczos) | ソース映像への忠実さをできる限り維持 |

Appleのニューラル処理、Anime、Anime4K、FSRCNNXは8ビットのSDR映像で動作します。HDR映像や10ビット映像、およびSDR to HDRがオンのときは、それ以外の方式が使用されます。

**Compare Before and After。** 視聴中の映像を中央で左右に分割します。左側はSDR to HDR・アップスケーリング・フレーム補間なし、右側は適用後の映像です。

**なめらかな動き。** フレーム補間により、24 fpsの映像をお使いの画面のリフレッシュレート（60 Hz、ProMotion搭載MacBook Proなら120 Hz、高速な外部ディスプレイならそれ以上）まで引き上げます。自動設定ではリアルタイムで追いつく方式が選ばれ、オプティカルフローやニューラルネットワークのRIFEを手動で選ぶこともできます。映画本来の見え方を重んじる方の意見ももっともなので、デフォルトではオフになっています。

<picture>
  <source media="(prefers-color-scheme: dark)" srcset=".github/readme/motion-demo-dark.svg">
  <img src=".github/readme/motion-demo-light.svg" width="100%" alt="アニメーション図解：毎秒24フレームでは段階的に動いて見える点が、毎秒120フレームに補間するとなめらかに横切る様子。">
</picture>

<p align="center">
  <img src=".github/readme/motion.webp" width="100%" alt="Sintel のシーン上に表示された MacLC のモーション補間パネル：フレーム補間がオン、方式は自動、フレームレートはディスプレイに合わせる設定で、24 fps を 120 fps として再生中。">
</p>

## 開きたくなるライブラリ

フォルダを指定するだけで、Apple TVアプリ風のライブラリが構築されます。視聴途中の作品が並ぶ**ホーム**をはじめ、**ビデオ、番組、アーティスト、アルバム、曲、ジャンル、お気に入り、プレイリスト**に整理されます。`Show S01E02` のような名前のエピソードはシーズンごとにまとめられ、カードには**Dolby Vision、HDR10、HLG、4K**のバッジが表示されるほか、ブラウズ中もフローティングの再生中カプセルで映像をそのまま見続けられます。元のファイルが移動されることはありません。

**Watch** では、注目の作品、シェルフ、トップ10、ジャンル、キャストやエピソード一覧を備えた作品ページなど、Apple TVアプリ風の画面で映画やシリーズのカタログをブラウズできます。内蔵のCinemetaがポスターや詳細情報、検索を提供し、再生できるコンテンツはインストールしたアドオン（[Stremio アドオンプロトコル](https://github.com/Stremio/stremio-addon-sdk/blob/master/docs/protocol.md)対応）によって決まります。お気に入り、履歴、「視聴を続ける」のデータはお使いのMac内に保存されます。

<picture>
  <source media="(prefers-color-scheme: dark)" srcset=".github/readme/watch-dark.webp">
  <img src=".github/readme/watch-light.webp" alt="MacLC の Watch セクション：注目作品のカルーセルと、Blender オープンムービーのトップ10シェルフ。">
</picture>

- **ダウンロードしながら再生できるトレント。** `.torrent` ファイルを開くかマグネットリンクを貼り付けると、数秒分のデータが検証された時点で再生が始まり、再生バー上のマーカーにバッファ状況、速度、ピア数が表示されます。
- **YouTube** — ホーム、登録チャンネル、後で見る、プレイリスト、検索に対応。無料の [`yt-dlp`](https://github.com/yt-dlp/yt-dlp) が必要で、インストールするための1行のコマンドがMacLC内に表示されます。ログインは任意で、Google公式ページで行うか、すでにログイン済みのブラウザのセッションを利用できます。MacLCはyt-dlpに必要なセッションCookieのみをMac上のプライベートファイルに保持し、ログアウトすると削除します。
- **Play on TV（ベータ）。** 再生中のコンテンツをApple TVやその他のAirPlayレシーバー、またはChromecastへ送信できます。

MacLCに映画、番組、ストリームは一切同梱されていません。アドオンはサードパーティのサービスです。視聴する権利を持つコンテンツにのみご利用ください。

## 聞き取りやすいセリフ

<img src=".github/readme/sound-dark.webp" align="right" width="260" alt="MacLC のサウンドパネル：Voice Boost が選択され、強度スライダーとサウンドモードの一覧が表示されている。">

**Voice Boost** は、音楽を大きくせずにセリフをクリアにします。5.1chの映画ではセンターチャンネルを持ち上げ（実測でセリフが+7.4&nbsp;dB優位）、ステレオではミックス中央の声をAppleのvDSPでリアルタイムに分離します（実際のミックスでの実測値：1〜4&nbsp;kHzの音声帯域で+4.8&nbsp;dB、レイテンシ約16&nbsp;ms）。

このほか、**ナイト、シネマ、ミュージック、バスブースト、スポークンワード、ヘッドフォン、小型スピーカー**の各モード（それぞれ強度スライダー付き）、**10バンドイコライザー**（⌥⌘E）、大音量シーンの音割れを防ぐリミッターも備えています。

<br clear="right">

## 役割がすぐにわかる設定画面

1つのウインドウに、サイドバーと検索フィールド。すべての項目で、スイッチを切り替えると見た目や音がどう変わるかが具体的に書かれています。上級者向けの設定も省略せず、折りたたみの中に用意されています。

<picture>
  <source media="(prefers-color-scheme: dark)" srcset=".github/readme/settings-hdr-dark.webp">
  <img src=".github/readme/settings-hdr-light.webp" alt="MacLC の HDR とカラー設定：ディスプレイの輝度ヘッドルームのライブステータス、それぞれ1文の説明が付いた4つの再生モード、および SDR to HDR のオプション。">
</picture>

## 他プレーヤーとの比較

|  | **MacLC** | IINA | Infuse | QuickTime Player |
|---|:---:|:---:|:---:|:---:|
| ほぼすべての動画ファイルを再生 | ✅ | ✅ | ✅ 一部の音声はProが必要 | ❌ 主にMP4とMOV |
| HDR画面でのHDR映像再生 | ✅ | ✅ | ✅ | ✅ |
| 通常の映像をHDR画面で輝かせる（SDR to HDR） | ✅ | ❌ | ❌ | ❌ |
| 内蔵のアップスケーリング方式 | ✅ 9種類 | ➖ シェーダーを手動導入 | ✅ AIモード1種類 | ❌ |
| なめらかな動き（フレーム補間） | ✅ 内蔵 | ➖ mpvオプション経由 | ❌ | ❌ |
| ワンクリックのセリフ強調 | ✅ Voice Boost | ❌ 手動でフィルタ設定 | ❌ 音量ブーストのみ | ❌ |
| 手持ちの動画用ライブラリ | ✅ 音楽も対応 | ❌ プレイリストと履歴 | ✅ 得意分野 | ❌ |
| アドオンカタログとトレント | ✅ | ❌ | ❌ | ❌ |
| YouTubeとWeb動画 | ✅ yt-dlpを使用 | ✅ yt-dlpを使用 | ❌ | ❌ |
| 無料 | ✅ | ✅ | ➖ Proは有料 | ✅ macOSに付属 |
| オープンソース | ✅ GPL | ✅ GPL | ❌ | ❌ |

<sub>2026年11月3日時点で各プレーヤーの公式ドキュメントおよびリリースノートと照合。IINAもまた、無料でオープンソースの優れたプレーヤーです。</sub>

## インストール

<p>
  <a href="https://github.com/OZBM/MacLC/releases/latest"><img alt="MacLC をダウンロード" src="https://img.shields.io/github/v/release/OZBM/MacLC?display_name=tag&label=Download&style=for-the-badge&logo=apple&logoColor=white&color=e8640c"></a>
</p>

1. [最新リリース](https://github.com/OZBM/MacLC/releases/latest)から `maclc-1.6.dmg`（57.8 MB）をダウンロードします。
2. ファイルを開き、**MacLC** を **アプリケーション** にドラッグします。
3. MacLCを開きます。初回はmacOSによって停止されるため、**完了** をクリックしてから **システム設定 › プライバシーとセキュリティ** を開き、**セキュリティ** までスクロールして「MacLC はブロックされました」の横にある **このまま開く** をクリックします。Touch IDまたはパスワードで確認してください。この操作はバージョンごとに1回だけです。

> [!NOTE]
> **なぜこの追加クリックが必要なのですか？** macOSでダブルクリックだけでアプリを開けるようにするには、開発者がAppleに年間99ユーロを支払ってDeveloper IDを取得し、各バージョンで公証を受ける必要があります。MacLCは無料であり、まだその資金が集まっていません。**最初の99ユーロの寄付が集まれば、全員がこの手順なしで利用できるようになります。** [寄付する](https://www.hazenstudio.com/maclc/donate/)

<details>
<summary>ターミナルでの代替手順、チェックサム、動作環境</summary>

**このまま開く** の代わりに、「インターネットからダウンロードされた」フラグを削除することもできます：

```bash
xattr -dr com.apple.quarantine /Applications/MacLC.app
```

お手元のファイルが公開されているものと完全に一致するか確認します（期待値はリリースページに記載されています。1.6 では `194de0b42a836985dba92a75d283264e21b4285f5a24934769b0e2aad5aae805` です）：

```bash
shasum -a 256 ~/Downloads/maclc-1.6.dmg
```

もしmacOSにMacLCは「壊れているため開けません」と表示された場合は、ダウンロードが不完全です。削除してもう一度ダウンロードしてください。そのメッセージは回避しないでください。

**動作環境**

- Apple Silicon（M1以降）を搭載したMac。Intel Macには対応していません。
- macOS 26 Tahoe以降。
- SDR to HDRには、通常の白より明るく表示できる画面（XDRディスプレイ搭載のMacBook Pro、Pro Display XDR、HDRモニター）が必要です。それ以外の機能はどの画面でも動作します。
- 任意：YouTubeやWeb動画の再生には [`yt-dlp`](https://github.com/yt-dlp/yt-dlp)（`brew install yt-dlp`）。

アプリは自己完結型です。FFmpeg、libass、libplacebo、libtorrentをはじめ約140個のライブラリが内部に同梱されており、それぞれのライセンスは `MacLC.app/Contents/Resources/Licenses/` に収録されています。

</details>

## MacLC を支援する

MacLCは個人プロジェクトです。広告もサブスクリプションも、販売するデータもありません。寄付は、無料アプリが自力では得られないものに、次の順番で充てられます：

<picture>
  <source media="(prefers-color-scheme: dark)" srcset=".github/readme/donation-milestones-dark.svg">
  <img src=".github/readme/donation-milestones-light.svg" width="100%" alt="寄付で実現すること：99ユーロで「このまま開く」が不要に（Apple の公証）、400ユーロで Play on TV の正式版化、900ユーロでテスト用の2台目のHDR画面、1,600ユーロでアクセシビリティの全面対応、2,500ユーロで自動アップデート機能。">
</picture>

**すべての寄付に「リクエスト権」が付いてきます。** MacLCに次に実現してほしいことを伝えるか、すでにリストにあるリクエストを後押ししてください。賛同者の多いものから優先して取り組みます。[寄付ページ](https://www.hazenstudio.com/maclc/donate/)ではPayPalまたはカードで支払うことができ、集まった総額もリアルタイムで表示されています。

<p align="center">
  <a href="https://www.hazenstudio.com/maclc/donate/"><img alt="寄付してリクエストを送る" src="https://img.shields.io/badge/Donate%20and%20make%20a%20wish-%E2%82%AC5%20%C2%B7%20%E2%82%AC15%20%C2%B7%20%E2%82%AC30%20%C2%B7%20%E2%82%AC99-e8640c?style=for-the-badge&logo=githubsponsors&logoColor=white"></a>
</p>

**お金をかけなくても、同じくらい助けになります：**

- ⭐ **このリポジトリにStarを付ける。** GitHubで人がMacLCを見つけるきっかけになります。
- **誰かに教える。** [X](https://x.com/intent/post?text=MacLC%3A%20the%20free%20video%20player%20for%20Mac%20that%20plays%20everything%2C%20with%20real%20HDR%2C%20SDR%20to%20HDR%2C%20upscaling%20and%20smooth%20motion.&url=https%3A%2F%2Fgithub.com%2FOZBM%2FMacLC)、[Bluesky](https://bsky.app/intent/compose?text=MacLC%3A%20the%20free%20video%20player%20for%20Mac%20that%20plays%20everything%2C%20with%20real%20HDR%2C%20SDR%20to%20HDR%2C%20upscaling%20and%20smooth%20motion.%20https%3A//github.com/OZBM/MacLC)、[Reddit](https://www.reddit.com/submit?url=https%3A%2F%2Fgithub.com%2FOZBM%2FMacLC&title=MacLC%3A%20a%20free%2C%20open-source%20video%20player%20for%20Mac%20with%20real%20HDR%20and%20SDR%20to%20HDR)、[LinkedIn](https://www.linkedin.com/sharing/share-offsite/?url=https%3A%2F%2Fgithub.com%2FOZBM%2FMacLC)でシェアしてください。
- **気づいたことを報告する。** 再生できないファイル、クラッシュ、おかしな色味などがあれば、行った操作と期待していた動作を添えて[Issueを作成](https://github.com/OZBM/MacLC/issues/new)してください。
- **お手持ちの画面でテストする。** これまでのところ、MacLCのHDRを確認できたのは1台のMacBook Proだけです。別のHDRディスプレイをお持ちの方は、どのように見えるか教えてください。

## よくある質問

<details>
<summary><b>MacLCは本当に無料ですか？</b></summary>

はい。有料版もサブスクリプションも広告もアカウントもなく、出し惜しみされている機能も一切ありません。GPL 2.0以降のオープンソースです。
</details>

<details>
<summary><b>安全ですか？ 初回起動時にmacOSがブロックするのはなぜですか？</b></summary>

ソースコードはすべてこのリポジトリで公開されており、MacLCにはアナリティクスやトラッキングもありません。何を視聴したかを開発者や第三者に送信することはありません。Watch、YouTube、トレントは、一般的なアプリと同様にそれぞれの利用先サービスへ接続します。初回起動時にmacOSがMacLCをブロックするのは、年間99ユーロかかるAppleの公証を受けていないためです（[インストール](#インストール)を参照）。各リリースではディスクイメージのSHA-256チェックサムを公開しているため、お手元のファイルを検証できます。
</details>

<details>
<summary><b>HDR画面が必要ですか？</b></summary>

いいえ。MacLCはどのMacの画面でもあらゆる動画を再生でき、HDR映画も通常の画面に合わせて表示します。通常の白より明るく光る画面が必要なのは、SDR to HDRだけです。
</details>

<details>
<summary><b>Intel Macや、macOS 15以前でも動作しますか？</b></summary>

いいえ。MacLCはApple SiliconおよびmacOS 26 Tahoe以降を対象としており、同梱ライブラリもmacOS 26を必要とします。
</details>

<details>
<summary><b>アップデートはどうすればいいですか？</b></summary>

[Releases](https://github.com/OZBM/MacLC/releases)から新しいディスクイメージをダウンロードし、アプリを置き換えてください。自動アップデート機能は寄付のロードマップに含まれています。新バージョンの通知を受け取るには、このページ上部のGitHubの **Watch** ボタンをクリックし、**Custom › Releases** を選択してください。
</details>

<details>
<summary><b>なめらかな動きを使うと、映画がテレビドラマのように見えませんか？</b></summary>

そう見えることがあるため、デフォルトではオフになっています。スポーツや自然映像、アニメーションでは好まれることが多い一方、映画では伝統的な24フレームの質感を残す方も多くいます。同じシーンで両方試してみてください。
</details>

<details>
<summary><b>MacLCに映画や番組は付属していますか？</b></summary>

いいえ。MacLCはご自身のファイルや開いたコンテンツを再生します。Watchにはご自身で選んでインストールしたアドオン（サードパーティのサービス）のカタログが表示されます。視聴する権利を持つコンテンツにのみご利用ください。
</details>

## 内部の仕組み

MacLCはVLC 4のオープンソースコードの一部、主に再生エンジンの `libVLC` をベースに構築されています。インターフェース、ライブラリとWatch、Metalビデオ出力、HDRパイプライン、SDR to HDR、アップスケーリング、モーション補間、Voice Boost、AirPlayは、Apple Silicon上のmacOS専用としてMacLCのために新規作成または再構築されました。

<details>
<summary><b>HDRパイプライン：継承コードで修正された6つの不具合</b></summary>

Apple Silicon上のVLC 4.0.0-devにおけるmacOS HDRパスの監査（2026年9月2日、ベースライン `99034f9`）より：

| 不具合 | 起きていた現象 | 修正内容 |
|---|---|---|
| EDRヘッドルームを `[NSScreen mainScreen]` から1回しか読み取らない | ウインドウを別のディスプレイに移すとHDRが不適切な明るさのままになる | 画面、プロファイル、パラメータの変更時にヘッドルームを再評価 |
| HDRモードとEDRヘッドルームの環境設定が機能していなかった | 設定が見かけだけだった | ライブ変数コールバックに接続し、再生中にも適用 |
| SDRトーンマッピングの分岐がない | HDR映画をSDR画面で表示すると平坦な白にクリップされる | `CADynamicRangeStandard` と `CAToneMapModeAutomatic` を使用し、フォールバックとしてBT.709再タグ付けを実装 |
| PQ映像上の字幕にタグがない | 暗いシーンで白い字幕がPQの最大輝度で表示される | 字幕レイヤーにsRGBタグを付与し、BT.2408リファレンスホワイトにスケーリング |
| 10ビット超のHEVCが8ビットBGRAにダウンサンプリングされる | 12ビットおよび16ビットソースが画面出力前にビット深度を失う | P010へルーティングし、16ビット4:2:2はCVPXヘルパー経由で接続 |
| 4K未満のHDRにBT.709タグが付与され、0 nitのマスタリングボリュームが出力される | 広色域コンテンツが誤った原色（プライマリ）で表示される | ストリームごとに正しくタグ付けし、マスタリングボリュームがゼロにならないよう修正 |

このほか、フィルタチェーンを通じたHDR10+動的メタデータ処理、VideoToolboxビットストリームからのDolby Visionメタデータ処理（プロファイル5および8.1はMacLCのMetalエンジン、プロファイル8.4はiPhone映像に対応）、ST 2086およびCTA-861.3メタデータのディスプレイレイヤーへの転送、ウインドウごとのICCプロファイル、M3以降でのハードウェアAV1、ARM64 NEONによるクロマ変換を備えています。
</details>

<details>
<summary><b>SDR to HDRの仕組み</b></summary>

映像をリニア化し、各ピクセルのドライブ値を「輝度」と「最も明るいチャンネルの85%」のうち大きい方として算出します。Fast ではSDR白の半分を超えるドライブ値を固定の二次曲線に沿って持ち上げ、Balanced では拡散白を超える部分のみを持ち上げつつ、広い領域が明るい場合にはその量を抑えます。いずれの場合もRGBの3要素すべてを同じ係数でスケーリングするため、色相と彩度は変化しません。High と Maximum ではMacLC専用に学習された2つの小規模ネットワークを使用し、シーンごとに輝度ゲインのグリッドを予測します（チャンネルごとのゲインは輝度ゲインから対数で0.2以内に制限）。結果は画面の実際のヘッドルーム以下にロールオフ付きで制限され、コンポジタに再度トーンマッピングで下げられないようタグ付けされます。すでにHDRであるソースには手を加えません。数式は [`maclc_sdr2hdr.h`](modules/video_output/apple/maclc_sdr2hdr.h)、Metalカーネルは [`VLCHDRExpander.m`](modules/video_output/apple/VLCHDRExpander.m) にあります。
</details>

<details>
<summary><b>アップスケーリングのエンジン、コスト、ライセンス</b></summary>

アップスケーリングは、ウインドウが映像の1.2倍以上大きいときにMacLCのMetalビデオ出力内で実行されます。M3 Maxでの実測値：MetalFX空間アップスケーリングが1フレームあたり0.4〜0.84 ms、AMD FSR 1（720pから1440p）が約0.5 ms、NIS（720pから4K）が1.19 ms、ArtCNN（540pから1080p）が約2.1 ms。バッテリー駆動時、低電力モード時、Macが高温のとき、または1フレームの処理にフレーム時間の60%超を要する場合には、ニューラル処理は控えられます。トランスレータがmpv形式のフックシェーダーを実行する仕組みになっており、Anime4KとFSRCNNXはこれによりMetal上で動作します。

ライセンス：NISおよびFSR 1（MIT、NVIDIAおよびAMDの表示を原文のまま保持）、Anime4KおよびArtCNN（MIT）、FSRCNNX（LGPL-3.0、ライセンスに同意した後にのみダウンロード）、MetalFXおよびVideoToolbox超解像（Appleシステムフレームワーク）。
</details>

<details>
<summary><b>追加されたコマンドラインオプション</b></summary>

| オプション | 値 | 機能 |
|---|---|---|
| `--macosx-hdr-mode` | 0〜3 | 0：Auto、1：ネイティブHDRを強制、2：SDRへトーンマッピング、3：HDRオフ |
| `--macosx-edr-headroom` | float | 0は画面に追従、1以上はヘッドルームを強制指定 |
| `--macosx-sdr-to-hdr` | bool | SDR映像を画面の拡張レンジへ拡張 |
| `--macosx-sdr-to-hdr-boost` | 1〜16 | ハイライトをSDR白よりどこまで明るくするか（デフォルト：4） |
| `--macosx-sdr-to-hdr-quality` | auto, fast, balanced, high, maximum | SDR to HDRのレベル |
| `--maclc-upscale`, `--maclc-upscale-method` | bool, string | アップスケーリングのオン／オフと方式 |

</details>

<details>
<summary><b>ソースからのビルド</b></summary>

MacLCはApple Silicon搭載Mac上で、Homebrewのライブラリに対してautotoolsを使ってビルドします。MesonではmacOSインターフェースはビルドできないため、autotoolsを使用するか、インターフェース作業にはXcodeプロジェクトを使用してください。

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

configure時は `PKG_CONFIG_PATH` の先頭に `build-deps/prefix/lib/pkgconfig` と `build-deps/pkgconfig` を指定してください。`Makefile.in` の再生成には `automake` 1.18 が必要です。`_NS("…")` を使用するファイルはすべて `po/POTFILES.in` に記載する必要があります。ユニットテスト（308件、XCTest）は `build/modules` から `make check-macosx` で実行でき、`MACLC_SELFTEST=1` を指定すると起動時に主要な設定ペインを構築して表示内容を報告します。アプリアイコンはリポジトリにコミットされたSwiftプログラム [`maclc_app_icon.swift`](extras/package/macosx/asset_sources/maclc_app_icon.swift) によって描画されます。
</details>

## リリース

<picture>
  <source media="(prefers-color-scheme: dark)" srcset=".github/readme/releases-dark.svg">
  <img src=".github/readme/releases-light.svg" width="100%" alt="タイムライン：2026年9月22日の 1.0 から 2026年11月2日の 1.6 まで、8回のリリース。">
</picture>

各バージョンでの変更点は [Releases](https://github.com/OZBM/MacLC/releases) にあります。次のリリースの通知を受け取るには、このページ上部のGitHubの **Watch** ボタンをクリックし、**Custom › Releases** を選択してください。

## 開発状況

MacLCはベータ版であり、速いペースで開発が進んでいます。M3 Max搭載のMacBook Proで開発・計測されており、各リリースは公開前に一連のサンプルファイルを再生して確認されています。未検証の項目：実際のAirPlayおよびChromecastレシーバーを使った Play on TV（ベータ表記の理由です）、ライブラリとWatch全体でのVoiceOverおよび「視差効果を減らす」、非常に大規模な実ライブラリ、そしてそのMacBook Pro以外のディスプレイでのHDR表示。これらの多くは前述の寄付マイルストーンに含まれています。

## ライセンス、商標、クレジット

MacLCは **GNU General Public License 2.0 以降** のもとで公開されています。VLCのコードを含んでおり、そのエンジン `libVLC` は引き続きLGPL 2.1以降が適用されます（[`COPYING`](COPYING) および [`COPYING.LIB`](COPYING.LIB) を参照）。一部プラットフォームでのVLCと同様に、同梱されている一部ライブラリのライセンスにより、配布されるアプリは実質的にGPL 3.0のもとでの提供となります。対応する完全なソースコードはこのリポジトリです。また、本アプリにはVideoLANの `libmedialibrary` と `libdvbpsi`（LGPL 2.1以降）、およびTagLib（LGPL 2.1またはMPL 1.1）が含まれており、固定されたソースから上記スクリプトでビルドされています。SDR to HDRのネットワークはPoly HavenのCC0 HDR写真を用いてMacLC専用に設計・学習されたもので、LGPL 2.1以降のもとで配布されています。RIFE v4.25補間ネットワークは [Practical-RIFE](https://github.com/hzwer/Practical-RIFE)（MIT、© 2021 hzwer）に由来します。

**MacLCはVideoLANと提携しておらず、VideoLANによる承認やサポートも受けていません。** VLC、VideoLAN、およびカラーコーンのロゴはVideoLANの商標であり、MacLCはこれらを使用していません。MacLCのバグはVideoLANではなく、こちらに報告してください。Dolby VisionはDolby Laboratoriesの商標であり、その他の名称はそれぞれの所有者に帰属します。

MacLCの基盤となっているVLCに20年にわたり取り組んできたVideoLANプロジェクトと多くのボランティアの皆様に感謝いたします（[`AUTHORS`](AUTHORS) および [`THANKS`](THANKS) を参照。アップストリームのREADMEは [`README.upstream.md`](README.upstream.md) として保持されています）。

このページの画像にはオープンムービーが表示されています：*Sintel*、*Big Buck Bunny*、*Tears of Steel*、*Elephants Dream*（© Blender Foundation, CC BY）、*Cosmos Laundromat*（Andy Goralczyk and the Blender Foundation, CC BY 4.0）、*Spring*（Francesco Siddi, Blender Foundation, CC BY 4.0）、*Sprite Fright*（Blender Studio, CC BY 4.0）、*Caminandes: Llama Drama*（Pablo Vazquez, Beorn Leonard, Francesco Siddi, CC BY 3.0）、およびPoly Havenのパノラマ（CC0）。

<p align="center">
  <a href="https://github.com/OZBM/MacLC/releases/latest"><b>MacLC をダウンロード</b></a> ·
  <a href="https://www.hazenstudio.com/maclc/"><b>Webサイト</b></a> ·
  <a href="https://www.hazenstudio.com/maclc/donate/"><b>寄付する</b></a>
</p>
