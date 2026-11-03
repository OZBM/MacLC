<!-- Übersetzung von README.md: Die englische Seite ist die Referenz. -->

<h1 align="center">
  <a href="https://github.com/OZBM/MacLC/releases/latest">
    <img src=".github/readme/banner.jpg" width="100%" alt="MacLC. Spielt alles ab. Bringt jedes Bild zum Strahlen. Kostenlos, Open Source, echtes HDR, Apple Silicon.">
  </a>
</h1>

<p align="center">
  <b>Der kostenlose Videoplayer für den Mac, der alles abspielt und jedes Bild zum Strahlen bringt.</b><br>
  Echtes HDR, SDR&nbsp;zu&nbsp;HDR, neun Upscaler, flüssige Bewegung, Voice&nbsp;Boost und eine Mediathek im Stil der Apple&nbsp;TV&nbsp;App – vereint in einer nativen App für Apple&nbsp;Silicon.
</p>

<p align="center">
  <a href="https://github.com/OZBM/MacLC/releases/latest"><img alt="MacLC für den Mac laden" src="https://img.shields.io/github/v/release/OZBM/MacLC?display_name=tag&label=Download%20for%20Mac&style=for-the-badge&logo=apple&logoColor=white&color=e8640c"></a>
  <a href="https://www.hazenstudio.com/maclc/donate/"><img alt="Für MacLC spenden" src="https://img.shields.io/badge/Donate-PayPal%20or%20card-2f343c?style=for-the-badge&logo=githubsponsors&logoColor=ff8a3d"></a>
</p>

<p align="center">
  <img alt="macOS 26 Tahoe oder neuer" src="https://img.shields.io/badge/macOS-26%20Tahoe%20or%20later-24292f?logo=apple&logoColor=white">
  <img alt="Apple Silicon, M1 oder neuer" src="https://img.shields.io/badge/Apple%20Silicon-M1%20or%20newer-24292f">
  <img alt="Kostenlos, keine Werbung, kein Tracking" src="https://img.shields.io/badge/free-no%20ads%20%C2%B7%20no%20tracking-24292f">
  <a href="COPYING"><img alt="Lizenz: GPL 2.0 oder neuer" src="https://img.shields.io/badge/licence-GPL--2.0--or--later-24292f"></a>
</p>

<p align="center">
  <a href="README.md">English</a> · <a href="README.fr.md">Français</a> · <a href="README.zh-CN.md">简体中文</a> · <a href="README.ja.md">日本語</a> · <a href="README.es.md">Español</a> · <b>Deutsch</b>
</p>

<picture>
  <source media="(prefers-color-scheme: dark)" srcset=".github/readme/library-dark.webp">
  <img src=".github/readme/library-light.webp" alt="Das Mediathekfenster von MacLC unter macOS 26: Weiter ansehen, Zuletzt hinzugefügt und eine „Jetzt läuft“-Kapsel, mit Kennzeichnungen für 4K, HDR10, HLG und Dolby Vision auf den Videos.">
</picture>

## Warum MacLC

<table>
<tr>
<td width="50%" valign="top">

**Spielt alles ab.** MKV, MP4, AVI, WebM, TS, AV1, HEVC, FLAC, DTS, Untertitel in SRT, ASS und mehr – selbst ausgefallene Dateien, bei denen andere Player streiken. Keine Codecs zu installieren.

</td>
<td width="50%" valign="top">

**Echtes HDR.** Dolby Vision, HDR10+, HDR10 und HLG mit ihren echten Spitzlichtern auf einem MacBook Pro oder jedem anderen HDR-Display – und Untertitel in angenehmem Weiß.

</td>
</tr>
<tr>
<td valign="top">

**SDR zu HDR.** Gewöhnliche Videos nutzen die zusätzliche Helligkeit deines Displays: Lampen, Himmel und Spiegelungen beginnen zu leuchten, während Gesichter und Schatten nah daran bleiben, wie sie gefilmt wurden.

</td>
<td valign="top">

**Schärfer, flüssiger.** Neun GPU-Upscaler (MetalFX, FSR, NIS, Anime4K …) für kleine Videos auf großen Displays und Zwischenbildberechnung bis zur Bildwiederholrate deines Displays, 120&nbsp;Hz mit ProMotion.

</td>
</tr>
<tr>
<td valign="top">

**Eine echte Mac-App.** Liquid Glass, Mac-Menüs und -Kurzbefehle, eine Mediathek im Stil der Apple TV App und Einstellungen, die sagen, was jeder Schalter bewirkt.

</td>
<td valign="top">

**Und mehr.** Voice Boost für klarere Dialoge, Watch für Add-on-Kataloge, Torrents, die schon beim Laden abspielen, YouTube (mit dem kostenlosen yt-dlp) und Play on TV (Beta).

</td>
</tr>
</table>

<p align="center"><b>Kostenlos. Keine Werbung, kein Konto, kein Tracking.</b> Open Source unter der GPL.</p>

## HDR, das dein ganzes Display nutzt

Ein MacBook Pro Display kann Spitzlichter um ein Vielfaches heller darstellen als Weiß. Genau darauf ist MacLC ausgelegt.

- **Dolby Vision, HDR10+, HDR10 und HLG**, jeweils so wiedergegeben, wie dein Display es am besten darstellen kann – einschließlich der HDR-Videos deines iPhones.
- **Die richtige Helligkeit auf jedem Display.** MacLC misst für jedes Fenster das jeweilige Display aus – und misst erneut, sobald du das Fenster auf einen anderen Bildschirm schiebst.
- **HDR auch auf gewöhnlichen Displays**, abgestimmt auf das, was der Bildschirm darstellen kann, statt zu flachem Weiß übersteuert zu werden.
- **Untertitel, die man gerne ansieht.** Sie bleiben in ruhigem Weiß, statt so hell zu strahlen wie das hellste Spitzlicht des Films.
- **Hardware-AV1** auf dem M3 und neuer, Software-AV1 überall sonst.

Die eigene Metal-Video-Engine von MacLC rendert Dolby Vision und HDR10+, und die sechs HDR-Fehler im übernommenen Code sind behoben ([Details](#unter-der-haube)).

### SDR zu HDR: Licht, wo dein Display Reserven hat

**Du liest das auf einem MacBook Pro? Schau dir das Bild unten in Safari an.** Es enthält eine echte HDR-Fassung: Das rechte Bild zeigt, was MacLC auf einem MacBook Pro mit SDR zu HDR auf der Stufe Maximum dargestellt hat, direkt aus der App aufgenommen, und seine Sonne samt dem Himmel um sie herum leuchtet heller als das Weiß dieser Seite. Auf anderen Bildschirmen sehen beide Bilder gleich aus – und genau darum geht es: MacLC bewahrt das vertraute Bild und setzt das zusätzliche Licht deines Displays gezielt für Spitzlichter ein.

<p align="center">
  <img src=".github/readme/sdr-to-hdr-split.jpg" width="100%" alt="Dasselbe Einzelbild aus dem Open-Movie Sintel zweimal: links wie gefilmt, rechts so, wie SDR zu HDR von MacLC es zeigt, direkt aus der App aufgenommen. Auf einem HDR-Display und in einem Browser, der HDR-Bilder unterstützt, leuchtet rechts die Sonne.">
</p>

<picture>
  <source media="(prefers-color-scheme: dark)" srcset=".github/readme/sdr-to-hdr-curve-dark.svg">
  <img src=".github/readme/sdr-to-hdr-curve-light.svg" width="100%" alt="Diagramm: Mit SDR zu HDR auf der Stufe Balanced werden die unteren 90 Prozent des Signals exakt wie im Originalvideo dargestellt; darüber steigen kleine Spitzlichter auf bis zu 400 cd/m² und große helle Flächen auf 190, während das Original bei 100 endet.">
</picture>

Wähle eine Stufe von Fast bis Maximum oder überlass Auto die Wahl einer Stufe, mit der dein Mac Schritt hält. High und Maximum nutzen kleine, eigens für MacLC trainierte neuronale Netze – rund eine halbe Millisekunde pro Bild auf einem M3 Max. Du legst fest, wie hell Spitzlichter werden dürfen, und **Hold to Compare** zeigt das Original, solange du gedrückt hältst.

<p align="center">
  <img src=".github/readme/sdr-to-hdr.webp" width="100%" alt="MacLC spielt Sintel bei geöffnetem SDR-zu-HDR-Panel ab: Qualitätsstufen, eine Effektkurve und ein Regler für die maximale Helligkeit der Spitzlichter.">
</p>

## Schärfer und flüssiger

**Upscaling.** Eine 720p-Folge auf einem 5K-Display hat Besseres verdient als Unschärfe. MacLC skaliert kleine Videos auf der GPU hoch – mit neun Methoden zur Auswahl, jede im eigenen Panel in klaren Worten erklärt:

| Methode | Ideal für |
|---|---|
| Auto | Wählt automatisch: Apples Super Resolution bei kleinen Videos, sonst MetalFX |
| Apple Neural 4x | Apples neuronales 4×-Modell (einmaliger Download von Apple); wechselt auf 2× zurück, wenn der Mac nicht hinterherkommt |
| Anime und Anime4K | Gezeichnete Animation: klare Linien, einfarbige Flächen |
| FSRCNNX | Feine Details (wird erst geladen, nachdem du der Lizenz zugestimmt hast) |
| Sharp (AMD FSR 1) und NIS (NVIDIA Image Scaling) | Knackige Kanten bei nahezu null Aufwand |
| Efficient (MetalFX) | Akkulaufzeit |
| Classic (EWA Lanczos) | So nah am Original wie möglich |

Apples neuronale Verfahren, Anime, Anime4K und FSRCNNX arbeiten mit 8-Bit-SDR-Videos. Bei HDR- und 10-Bit-Videos sowie bei aktiviertem SDR zu HDR nutzt MacLC die übrigen Methoden.

**Compare Before and After.** Teile das Bild mitten im laufenden Video: links ohne SDR zu HDR, Upscaling und Zwischenbildberechnung, rechts mit.

**Flüssige Bewegung.** Die Zwischenbildberechnung hebt 24 fps auf die Bildwiederholrate deines Displays an: 60 Hz, 120 Hz auf einem MacBook Pro mit ProMotion oder mehr auf einem schnellen externen Monitor. Automatisch wählt ein Verfahren, das in Echtzeit mithält; optischer Fluss und RIFE, ein neuronales Netz, lassen sich auch manuell auswählen. Standardmäßig ist die Funktion ausgeschaltet – denn auch Kinopuristen haben recht.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset=".github/readme/motion-demo-dark.svg">
  <img src=".github/readme/motion-demo-light.svg" width="100%" alt="Animierte Grafik: Ein Punkt wandert bei 24 Bildern pro Sekunde in sichtbaren Sprüngen über das Bild und gleitet bei Zwischenbildberechnung auf 120 Bilder pro Sekunde flüssig dahin.">
</picture>

<p align="center">
  <img src=".github/readme/motion.webp" width="100%" alt="Das Panel zur Zwischenbildberechnung von MacLC über einer Szene aus Sintel: Bilder interpolieren aktiviert, Methode Automatisch, Bildrate An Display anpassen, Wiedergabe von 24 fps mit 120 fps.">
</p>

## Eine Mediathek, die man gerne öffnet

Verweise MacLC auf deine Ordner, und es baut daraus eine Mediathek im Stil der Apple TV App auf: **Startseite** mit dem, was du zuletzt geschaut hast, dazu **Videos, Serien, Künstler, Alben, Titel, Genres, Favoriten und Playlists**. Folgen mit Namen wie `Show S01E02` werden nach Staffeln gruppiert, Kacheln tragen Abzeichen für **Dolby Vision, HDR10, HLG und 4K**, und eine schwebende „Jetzt läuft“-Kapsel lässt das Video beim Stöbern weiterlaufen. Deine Dateien bleiben dabei genau dort, wo sie liegen.

**Watch** durchstöbert Film- und Serienkataloge im Stil der Apple TV App – mit Empfehlungen, Themenreihen, einer Top 10, Genres sowie Detailseiten mit Besetzung und Folgen. Das integrierte Cinemeta liefert Poster, Infos und Suche; was sich abspielen lässt, hängt von den installierten Add-ons ab, die das [Stremio-Add-on-Protokoll](https://github.com/Stremio/stremio-addon-sdk/blob/master/docs/protocol.md) sprechen. Favoriten, Verlauf und Weiter ansehen bleiben auf deinem Mac.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset=".github/readme/watch-dark.webp">
  <img src=".github/readme/watch-light.webp" alt="Der Bereich Watch in MacLC: ein Empfehlungskarussell und eine Top-10-Reihe mit Open-Movies von Blender.">
</picture>

- **Torrents, die schon beim Laden abspielen.** Öffne eine `.torrent`-Datei oder füge einen Magnet-Link ein: Die Wiedergabe startet, sobald ein paar Sekunden geprüft sind, und eine Markierung in der Zeitleiste zeigt Pufferstand, Geschwindigkeit und Peers.
- **YouTube** mit Startseite, Abos, Später ansehen, Playlists und Suche. Dafür wird das kostenlose [`yt-dlp`](https://github.com/yt-dlp/yt-dlp) benötigt, und MacLC zeigt dir den einen Befehl, der es installiert. Eine Anmeldung ist optional: direkt auf der Google-Seite oder über die Sitzung eines Browsers, in dem du bereits angemeldet bist. MacLC speichert nur die Sitzungs-Cookies, die yt-dlp benötigt, in einer privaten Datei auf deinem Mac; beim Abmelden wird sie gelöscht.
- **Play on TV (Beta).** Sende die laufende Wiedergabe an ein Apple TV, einen anderen AirPlay-Empfänger oder einen Chromecast.

MacLC liefert keine Filme, Serien oder Streams mit. Add-ons sind Dienste von Drittanbietern: Nutze sie nur für Inhalte, zu deren Wiedergabe du berechtigt bist.

## Dialoge, die man versteht

<img src=".github/readme/sound-dark.webp" align="right" width="260" alt="Das Ton-Panel von MacLC: Voice Boost ausgewählt, ein Intensitätsregler und die Liste der Klangmodi.">

**Voice Boost** macht Dialoge klarer, ohne die Musik lauter zu drehen. Bei 5.1-Filmen hebt die Funktion den Center-Kanal an (+7,4&nbsp;dB Dialogvorteil, gemessen). Bei Stereo isoliert sie Stimmen in der Mitte des Mixes, in Echtzeit über Apples vDSP (+4,8&nbsp;dB im Sprachband von 1 bis 4&nbsp;kHz, gemessen an einem echten Mix, rund 16&nbsp;ms Latenz).

Außerdem: Modi für **Nacht, Kino, Musik, Bass-Boost, Gesprochenes Wort, Kopfhörer und Kleine Lautsprecher**, jeweils mit eigenem Intensitätsregler, einem **10-Band-Equalizer** (⌥⌘E) und einem Limiter, der Übersteuerungen in lauten Szenen verhindert.

<br clear="right">

## Einstellungen, die sich selbst erklären

Ein Fenster, eine Seitenleiste und ein Suchfeld. Jede Zeile beschreibt, was der Schalter bewirkt – anhand dessen, was du tatsächlich siehst oder hörst. Die Experteneinstellungen sind weiterhin da, hinter einem Ausklappbereich.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset=".github/readme/settings-hdr-dark.webp">
  <img src=".github/readme/settings-hdr-light.webp" width="100%" alt="Die Einstellungen für HDR und Farbe in MacLC: Live-Status der Helligkeitsreserve des Displays, vier benannte Wiedergabemodi mit je einem erklärenden Satz sowie Optionen für SDR zu HDR.">
</picture>

## Der Vergleich

|  | **MacLC** | IINA | Infuse | QuickTime Player |
|---|:---:|:---:|:---:|:---:|
| Spielt fast jede Videodatei ab | ✅ | ✅ | ✅ manche Tonformate nur mit Pro | ❌ vor allem MP4 und MOV |
| HDR-Videos auf HDR-Displays | ✅ | ✅ | ✅ | ✅ |
| Bringt gewöhnliche Videos auf HDR-Displays zum Leuchten (SDR zu HDR) | ✅ | ❌ | ❌ | ❌ |
| Integrierte Upscaling-Methoden | ✅ neun | ➖ selbst installierte Shader | ✅ ein KI-Modus | ❌ |
| Flüssige Bewegung (Zwischenbildberechnung) | ✅ eingebaut | ➖ über mpv-Optionen | ❌ | ❌ |
| Dialogverstärkung per Klick | ✅ Voice Boost | ❌ Filter von Hand | ❌ nur Lautstärkeanhebung | ❌ |
| Mediathek für eigene Videos | ✅ und Musik | ❌ Playlists und Verlauf | ✅ seine Spezialität | ❌ |
| Add-on-Kataloge und Torrents | ✅ | ❌ | ❌ | ❌ |
| YouTube und Webvideos | ✅ mit yt-dlp | ✅ mit yt-dlp | ❌ | ❌ |
| Kostenlos | ✅ | ✅ | ➖ Pro ist kostenpflichtig | ✅ bei macOS dabei |
| Open Source | ✅ GPL | ✅ GPL | ❌ | ❌ |

<sub>Geprüft am 3. November 2026 anhand der Dokumentation und Versionshinweise des jeweiligen Players. IINA ist ebenfalls hervorragend, kostenlos und Open Source.</sub>

## Installation

<p>
  <a href="https://github.com/OZBM/MacLC/releases/latest"><img alt="MacLC laden" src="https://img.shields.io/github/v/release/OZBM/MacLC?display_name=tag&label=Download&style=for-the-badge&logo=apple&logoColor=white&color=e8640c"></a>
</p>

1. Lade `maclc-1.6.dmg` (57,8 MB) von [der neuesten Version](https://github.com/OZBM/MacLC/releases/latest) herunter.
2. Öffne die Datei und ziehe **MacLC** in den Ordner **Programme**.
3. Öffne MacLC. Beim ersten Start blockiert macOS die App: Klicke auf **Fertig**, öffne dann **Systemeinstellungen › Datenschutz & Sicherheit**, scrolle zu **Sicherheit** und klicke neben „MacLC wurde blockiert“ auf **Dennoch öffnen**. Bestätige mit Touch ID oder deinem Passwort. Das ist pro Version nur einmal nötig.

> [!NOTE]
> **Warum der zusätzliche Klick?** macOS öffnet Apps nur dann direkt per Doppelklick, wenn ihr Entwickler Apple 99 € im Jahr für eine Developer ID zahlt und jede Version notarisieren lässt. MacLC ist kostenlos und hat diesen Betrag noch nicht zusammen. **Die ersten 99 € an Spenden schaffen diesen Schritt für alle ab.** [Spenden](https://www.hazenstudio.com/maclc/donate/)

<details>
<summary>Terminal-Alternative, Prüfsumme und Voraussetzungen</summary>

Statt auf **Dennoch öffnen** zu klicken, kannst du die Markierung „aus dem Internet geladen“ im Terminal entfernen:

```bash
xattr -dr com.apple.quarantine /Applications/MacLC.app
```

Prüfe, ob deine Datei exakt der veröffentlichten entspricht (der erwartete Wert steht auf der Release-Seite; für 1.6 lautet er `194de0b42a836985dba92a75d283264e21b4285f5a24934769b0e2aad5aae805`):

```bash
shasum -a 256 ~/Downloads/maclc-1.6.dmg
```

Falls macOS jemals meldet, MacLC „ist beschädigt und kann nicht geöffnet werden“, war der Download unvollständig: Lösche die Datei und lade sie erneut herunter. Umgehe diese Meldung nicht.

**Voraussetzungen**

- Ein Mac mit Apple Silicon (M1 oder neuer). Intel-Macs werden nicht unterstützt.
- macOS 26 Tahoe oder neuer.
- SDR zu HDR erfordert ein Display, das heller als Weiß leuchten kann (ein MacBook Pro mit XDR-Display, ein Pro Display XDR oder einen HDR-Monitor). Alles andere funktioniert auf jedem Bildschirm.
- Optional: [`yt-dlp`](https://github.com/yt-dlp/yt-dlp) für YouTube und Webvideos (`brew install yt-dlp`).

Die App bringt alles Nötige selbst mit: FFmpeg, libass, libplacebo, libtorrent und rund 140 weitere Bibliotheken sind direkt enthalten; ihre Lizenzen liegen unter `MacLC.app/Contents/Resources/Licenses/`.

</details>

## MacLC unterstützen

MacLC ist ein persönliches Projekt: keine Werbung, kein Abo, keine Daten zum Verkaufen. Spenden finanzieren das, was eine kostenlose App nicht von allein bekommt – in dieser Reihenfolge:

<picture>
  <source media="(prefers-color-scheme: dark)" srcset=".github/readme/donation-milestones-dark.svg">
  <img src=".github/readme/donation-milestones-light.svg" width="100%" alt="Was Spenden freischalten: 99 Euro, kein „Dennoch öffnen“ mehr (Apple-Notarisierung); 400 Euro, Play on TV verlässt die Beta; 900 Euro, ein zweites HDR-Display zum Testen; 1.600 Euro, vollständige Überarbeitung der Bedienungshilfen; 2.500 Euro, automatische App-Updates.">
</picture>

**Zu jeder Spende gehört ein Wunsch.** Sag mir, was MacLC als Nächstes können soll, oder unterstütze einen bestehenden Wunsch auf der Liste: Die Wünsche mit den meisten Unterstützern kommen zuerst dran. Bezahlen kannst du per PayPal oder Karte auf [der Spendenseite](https://www.hazenstudio.com/maclc/donate/) – dort ist auch der aktuelle Stand live zu sehen.

<p align="center">
  <a href="https://www.hazenstudio.com/maclc/donate/"><img alt="Spenden und einen Wunsch äußern" src="https://img.shields.io/badge/Donate%20and%20make%20a%20wish-%E2%82%AC5%20%C2%B7%20%E2%82%AC15%20%C2%B7%20%E2%82%AC30%20%C2%B7%20%E2%82%AC99-e8640c?style=for-the-badge&logo=githubsponsors&logoColor=white"></a>
</p>

**Kein Geld übrig? Das hilft genauso viel:**

- ⭐ **Gib diesem Repository einen Stern.** Über Sterne entdecken andere MacLC auf GitHub.
- **Erzähl es weiter.** Teile MacLC auf [X](https://x.com/intent/post?text=MacLC%3A%20the%20free%20video%20player%20for%20Mac%20that%20plays%20everything%2C%20with%20real%20HDR%2C%20SDR%20to%20HDR%2C%20upscaling%20and%20smooth%20motion.&url=https%3A%2F%2Fgithub.com%2FOZBM%2FMacLC), [Bluesky](https://bsky.app/intent/compose?text=MacLC%3A%20the%20free%20video%20player%20for%20Mac%20that%20plays%20everything%2C%20with%20real%20HDR%2C%20SDR%20to%20HDR%2C%20upscaling%20and%20smooth%20motion.%20https%3A//github.com/OZBM/MacLC), [Reddit](https://www.reddit.com/submit?url=https%3A%2F%2Fgithub.com%2FOZBM%2FMacLC&title=MacLC%3A%20a%20free%2C%20open-source%20video%20player%20for%20Mac%20with%20real%20HDR%20and%20SDR%20to%20HDR) oder [LinkedIn](https://www.linkedin.com/sharing/share-offsite/?url=https%3A%2F%2Fgithub.com%2FOZBM%2FMacLC).
- **Melde, was dir auffällt.** Eine Datei, die nicht abspielt, ein Absturz, eine falsche Farbe: [Erstelle ein Issue](https://github.com/OZBM/MacLC/issues/new) und beschreibe, was du getan und was du erwartet hast.
- **Teste auf deinem Display.** Bisher wurde das HDR von MacLC nur auf einem einzigen MacBook Pro geprüft. Wenn du ein anderes HDR-Display besitzt, schreib mir, wie es aussieht.

## Fragen

<details>
<summary><b>Ist MacLC wirklich kostenlos?</b></summary>

Ja. Keine Kaufversion, kein Abo, keine Werbung, kein Konto und nichts wird zurückgehalten. MacLC ist Open Source unter der GPL 2.0 oder neuer.
</details>

<details>
<summary><b>Ist es sicher? Warum blockiert macOS es beim ersten Start?</b></summary>

Der gesamte Quellcode ist in diesem Repository öffentlich einsehbar, und MacLC enthält weder Analysefunktionen noch Tracking: Was du ansiehst, wird weder an den Entwickler noch an Dritte übertragen. Watch, YouTube und Torrents verbinden sich wie jede andere App mit den jeweiligen Diensten. macOS blockiert MacLC beim ersten Start nur deshalb, weil die App nicht von Apple notarisiert ist – das kostet 99 € im Jahr (siehe [Installation](#installation)). Zu jeder Version wird die SHA-256-Prüfsumme des Disk-Images veröffentlicht, sodass du deine Datei überprüfen kannst.
</details>

<details>
<summary><b>Brauche ich ein HDR-Display?</b></summary>

Nein. MacLC spielt jedes Video auf jedem Mac-Bildschirm ab und passt HDR-Filme an gewöhnliche Displays an. Nur SDR zu HDR erfordert ein Display, das heller als Weiß leuchten kann.
</details>

<details>
<summary><b>Läuft es auf Intel-Macs oder unter macOS 15 und älter?</b></summary>

Nein. MacLC ist für Apple Silicon und macOS 26 Tahoe oder neuer entwickelt, und auch die mitgelieferten Bibliotheken setzen macOS 26 voraus.
</details>

<details>
<summary><b>Wie aktualisiere ich MacLC?</b></summary>

Lade das neue Disk-Image unter [Releases](https://github.com/OZBM/MacLC/releases) herunter und ersetze die App. Automatische Updates stehen auf dem Spendenfahrplan. Um über neue Versionen informiert zu werden, klicke oben auf dieser Seite auf GitHubs Schaltfläche **Watch** und wähle **Custom › Releases**.
</details>

<details>
<summary><b>Lässt die Zwischenbildberechnung Filme nicht wie eine Seifenoper wirken?</b></summary>

Das kann passieren – genau deshalb ist sie standardmäßig ausgeschaltet. Viele mögen sie bei Sport, Natur und Animation und bleiben bei Spielfilmen beim klassischen 24-Bilder-Look. Probier einfach beides an derselben Szene aus.
</details>

<details>
<summary><b>Bringt MacLC Filme oder Serien mit?</b></summary>

Nein. MacLC spielt deine eigenen Dateien und das ab, was du selbst öffnest. Watch zeigt lediglich die Kataloge der Add-ons an, die du selbst installierst – das sind Dienste von Drittanbietern: Nutze sie nur für Inhalte, zu deren Wiedergabe du berechtigt bist.
</details>

## Unter der Haube

MacLC baut auf Teilen des Open-Source-Codes von VLC 4 auf, vor allem auf dessen Wiedergabe-Engine (`libVLC`). Oberfläche, Mediathek und Watch, Metal-Videoausgabe, HDR-Pipeline, SDR zu HDR, Upscaling, Zwischenbildberechnung, Voice Boost und AirPlay wurden für MacLC neu geschrieben oder von Grund auf überarbeitet – ausschließlich für macOS auf Apple Silicon.

<details>
<summary><b>HDR-Pipeline: sechs behobene Fehler im übernommenen Code</b></summary>

Aus einem Audit des macOS-HDR-Pfads von VLC 4.0.0-dev auf Apple Silicon (02.09.2026, Basis `99034f9`):

| Fehler | Was zu sehen war | Behebung |
|---|---|---|
| EDR-Headroom nur einmalig über `[NSScreen mainScreen]` gelesen | Beim Verschieben des Fensters auf ein anderes Display stimmte die HDR-Helligkeit nicht mehr | Headroom wird bei Bildschirm-, Profil- und Parameterwechseln neu ermittelt |
| Einstellungen für HDR-Modus und EDR-Headroom ohne Wirkung | Schalter waren reine Dekoration | Mit Live-Variablen-Callbacks verbunden, greifen während der Wiedergabe |
| Kein Zweig für SDR-Tone-Mapping | HDR-Filme wurden auf SDR-Displays zu flachem Weiß übersteuert | `CADynamicRangeStandard` mit `CAToneMapModeAutomatic`, Fallback per BT.709-Umkennzeichnung |
| Untertitel über PQ-Video ohne Farbraum-Tag | Weiße Untertitel leuchteten über dunklen Szenen mit voller PQ-Leuchtdichte | Untertitelebene als sRGB gekennzeichnet und auf BT.2408-Referenzweiß skaliert |
| HEVC über 10 Bit auf 8-Bit-BGRA heruntergerechnet | 12-Bit- und 16-Bit-Quellen verloren schon vor dem Display Farbtiefe | Weiterleitung als P010; 16-Bit-4:2:2 über die CVPX-Helfer angebunden |
| HDR unterhalb von 4K als BT.709 gekennzeichnet, Mastering-Volumen mit 0 Nit ausgegeben | Wide-Gamut-Inhalte wurden mit falschen Primärvalenzen dargestellt | Korrekte Kennzeichnung pro Stream, Mastering-Volumen nie null |

Außerdem: dynamische HDR10+-Metadaten durch die gesamte Filterkette, Metadaten für Dolby Vision aus dem VideoToolbox-Bitstream (Profile 5 und 8.1 in der Metal-Engine von MacLC, 8.4 vom iPhone), Weitergabe von Metadaten nach ST 2086 und CTA-861.3 an den Display-Layer, ein eigenes ICC-Profil pro Fenster, Hardware-AV1 ab dem M3 sowie ARM64-NEON-Chromakonvertierungen.
</details>

<details>
<summary><b>Wie SDR zu HDR funktioniert</b></summary>

Das Bild wird linearisiert; als Aussteuerung jedes Pixels gilt das Maximum aus seiner Luminanz und 85 % seines hellsten Kanals. Fast hebt die Aussteuerung oberhalb der Hälfte von SDR-Weiß entlang einer festen quadratischen Kurve an; Balanced hebt nur Werte oberhalb von diffusem Weiß an – und zwar umso weniger, je größer die hellen Bildflächen sind. In beiden Stufen wird das gesamte Farb-Tripel mit demselben Faktor skaliert, sodass Farbton und Sättigung unverändert bleiben. High und Maximum nutzen zwei kleine, für MacLC trainierte Netze, die pro Szene ein Raster von Helligkeitsverstärkungen vorhersagen, wobei die Verstärkung je Kanal innerhalb von 0,2 (log) der Luminanzverstärkung bleibt. Das Ergebnis wird mit sanftem Rolloff auf den tatsächlichen Headroom des Displays begrenzt und so gekennzeichnet, dass der Compositor es nicht wieder per Tone-Mapping herunterregelt. Quellen, die bereits in HDR vorliegen, bleiben unangetastet. Die Mathematik steht in [`maclc_sdr2hdr.h`](modules/video_output/apple/maclc_sdr2hdr.h), die Metal-Kernel in [`VLCHDRExpander.m`](modules/video_output/apple/VLCHDRExpander.m).
</details>

<details>
<summary><b>Upscaling-Engine, Rechenaufwand und Lizenzen</b></summary>

Das Upscaling läuft in der Metal-Videoausgabe von MacLC, sobald das Fenster mindestens 1,2-mal größer ist als das Video. Gemessen auf einem M3 Max: räumliches MetalFX 0,4 bis 0,84 ms pro Bild, AMD FSR 1 von 720p auf 1440p rund 0,5 ms, NIS von 720p auf 4K 1,19 ms, ArtCNN von 540p auf 1080p rund 2,1 ms. Neuronale Verfahren schalten im Akkubetrieb, im Stromsparmodus, bei heißem Mac oder wenn ein Bild mehr als 60 % seiner Framezeit benötigen würde, automatisch zurück. Ein Übersetzer führt Hook-Shader im mpv-Stil aus – so laufen Anime4K und FSRCNNX direkt in Metal.

Lizenzen: NIS und FSR 1 (MIT, mit wortgetreu übernommenen Hinweisen von NVIDIA und AMD), Anime4K und ArtCNN (MIT), FSRCNNX (LGPL-3.0, wird erst nach Zustimmung zur Lizenz heruntergeladen), MetalFX und VideoToolbox Super Resolution (Apple-Systemframeworks).
</details>

<details>
<summary><b>Neue Befehlszeilenoptionen</b></summary>

| Option | Werte | Funktion |
|---|---|---|
| `--macosx-hdr-mode` | 0 bis 3 | 0 Auto, 1 natives HDR erzwingen, 2 Tone-Mapping auf SDR, 3 HDR aus |
| `--macosx-edr-headroom` | float | 0 folgt dem Display; 1 oder höher erzwingt einen festen Headroom |
| `--macosx-sdr-to-hdr` | bool | SDR-Video in den erweiterten Dynamikumfang des Displays erweitern |
| `--macosx-sdr-to-hdr-boost` | 1 bis 16 | Maximale Anhebung von Spitzlichtern über SDR-Weiß (Standard: 4) |
| `--macosx-sdr-to-hdr-quality` | auto, fast, balanced, high, maximum | Stufe für SDR zu HDR |
| `--maclc-upscale`, `--maclc-upscale-method` | bool, string | Upscaling ein- oder ausschalten sowie Auswahl der Methode |

</details>

<details>
<summary><b>Aus dem Quellcode bauen</b></summary>

MacLC wird auf einem Mac mit Apple Silicon per autotools gegen die Bibliotheken von Homebrew gebaut. Meson baut die macOS-Oberfläche nicht: Nutze autotools – oder das Xcode-Projekt für Arbeiten an der Oberfläche.

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

Konfiguriere den Build mit `build-deps/prefix/lib/pkgconfig` und `build-deps/pkgconfig` an erster Stelle in `PKG_CONFIG_PATH`; zum Neugenerieren von `Makefile.in` ist `automake` 1.18 erforderlich; jede Datei, die `_NS("…")` verwendet, muss in `po/POTFILES.in` aufgeführt sein. Die Unit-Tests (308, XCTest) laufen mit `make check-macosx` aus `build/modules`, und `MACLC_SELFTEST=1` baut beim Start die wichtigsten Einstellungsbereiche auf und meldet, was angezeigt wurde. Das App-Icon wird von einem eingecheckten Swift-Programm gezeichnet: [`maclc_app_icon.swift`](extras/package/macosx/asset_sources/maclc_app_icon.swift).
</details>

## Versionen

<picture>
  <source media="(prefers-color-scheme: dark)" srcset=".github/readme/releases-dark.svg">
  <img src=".github/readme/releases-light.svg" width="100%" alt="Zeitstrahl: acht Versionen von 1.0 am 22. September 2026 bis 1.6 am 2. November 2026.">
</picture>

Was sich in jeder Version geändert hat, steht unter [Releases](https://github.com/OZBM/MacLC/releases). Um über die nächste informiert zu werden, klicke oben auf dieser Seite auf GitHubs Schaltfläche **Watch** und dann auf **Custom › Releases**.

## Status

MacLC ist in der Beta-Phase und entwickelt sich schnell weiter. Entwickelt und vermessen wird auf einem MacBook Pro mit M3 Max, und vor jeder Veröffentlichung spielt die App einen Satz Testdateien durch. Noch nicht verifiziert: Play on TV mit echten AirPlay- und Chromecast-Empfängern (daher der Beta-Zusatz), VoiceOver und Bewegung reduzieren in der gesamten Mediathek und in Watch, eine sehr große reale Mediathek sowie HDR auf anderen Displays als dem dieses MacBook Pro. Die meisten dieser Punkte sind oben als Spendenmeilensteine aufgeführt.

## Lizenz, Marken und Danksagung

MacLC erscheint unter der **GNU General Public License 2.0 oder neuer**. Die App enthält Code aus VLC, dessen Engine `libVLC` weiterhin unter der LGPL 2.1 oder neuer steht: siehe [`COPYING`](COPYING) und [`COPYING.LIB`](COPYING.LIB). Wie bei VLC auf einigen Plattformen unterliegt die ausgelieferte App aufgrund der Lizenzen einiger mitgelieferter Bibliotheken faktisch der GPL 3.0. Der vollständige zugehörige Quellcode ist dieses Repository. Die App enthält außerdem `libmedialibrary` und `libdvbpsi` von VideoLAN (LGPL 2.1 oder neuer) sowie TagLib (LGPL 2.1 oder MPL 1.1), gebaut aus den fixierten Quellversionen über die oben genannten Skripte. Die Netze für SDR zu HDR wurden für MacLC entworfen, auf CC0-HDR-Fotografien von Poly Haven trainiert und werden unter der LGPL 2.1 oder neuer verbreitet; das Interpolationsnetz RIFE v4.25 stammt aus [Practical-RIFE](https://github.com/hzwer/Practical-RIFE) (MIT, © 2021 hzwer).

**MacLC steht in keiner Verbindung zu VideoLAN und wird von VideoLAN weder empfohlen noch unterstützt.** VLC, VideoLAN und das Leitkegel-Logo sind Marken von VideoLAN; MacLC verwendet sie nicht. Bitte melde Fehler in MacLC hier und nicht bei VideoLAN. Dolby Vision ist eine Marke der Dolby Laboratories; alle weiteren Namen gehören ihren jeweiligen Inhabern.

MacLC baut auf über zwanzig Jahren Arbeit des VideoLAN-Projekts und vieler Freiwilliger an VLC auf: danke. Siehe [`AUTHORS`](AUTHORS) und [`THANKS`](THANKS); die ursprüngliche README-Datei bleibt als [`README.upstream.md`](README.upstream.md) erhalten.

Die Bilder auf dieser Seite zeigen Open-Movies: *Sintel*, *Big Buck Bunny*, *Tears of Steel* und *Elephants Dream* (© Blender Foundation, CC BY), *Cosmos Laundromat* (Andy Goralczyk und Blender Foundation, CC BY 4.0), *Spring* (Francesco Siddi, Blender Foundation, CC BY 4.0), *Sprite Fright* (Blender Studio, CC BY 4.0) und *Caminandes: Llama Drama* (Pablo Vazquez, Beorn Leonard, Francesco Siddi, CC BY 3.0) sowie Panoramen von Poly Haven (CC0).

<p align="center">
  <a href="https://github.com/OZBM/MacLC/releases/latest"><b>MacLC laden</b></a> ·
  <a href="https://www.hazenstudio.com/maclc/"><b>Website</b></a> ·
  <a href="https://www.hazenstudio.com/maclc/donate/"><b>Spenden</b></a>
</p>
