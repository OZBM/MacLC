# Prompt — Build the MacLC product website

> **How to use this file.** Paste the whole thing as the opening message of a new
> project. It is written to be self-contained: the agent receiving it has **no access to
> the MacLC source repository** and must be able to build the entire site from what is
> below. Everything factual in Part 2 is verified; nothing in it should be softened,
> embellished, or invented around.

---

---

# PART 0 — YOUR ROLE AND THE BRIEF

You are a senior product designer and front-end engineer. You have shipped marketing sites
for hardware and pro software. You are being asked to design and build the **complete
product website for MacLC**, a macOS media player.

The bar is explicit and it is not negotiable: **the site must be indistinguishable in
craft from a first-party Apple product page.** Not "inspired by Apple". Not "Apple-ish
gradients on a Bootstrap layout". The real thing: restraint, enormous type, generous
negative space, one idea per viewport, scroll-driven motion that has a reason to exist,
and a level of typographic and spacing discipline that most sites never attempt.

If a section of your output would look at home on a template marketplace, you have failed
and must redo it.

**Deliverable:** a complete, production-ready, deployable website. Every page, every asset,
every state. Not a mockup, not a single-file demo — a real project with a real structure.

---

# PART 1 — WHAT MACLC IS (read this before designing anything)

MacLC is a **macOS-only fork of VLC 4.0 for Apple Silicon**.

It keeps 100% of VLC's playback capability — the same demuxers, decoders, protocol stack
and engine (`libvlccore`), so it plays literally everything VLC plays. What it changes is
everything *around* that: the HDR pipeline on Apple displays, the settings experience, and
the interface itself.

**The one-sentence positioning:**
> Everything VLC can play. Finally built like a Mac app.

**The emotional promise:** you already trust VLC to open the file. MacLC is what happens
when someone spends the effort to make that same engine feel like it was made by Apple,
and makes your XDR display actually do something.

**Who it is for:** Mac users with good displays — MacBook Pro XDR, Pro Display XDR, Studio
Display, or an external HDR panel — who care how video looks, and who are tired of
choosing between "plays everything, looks like 2007" and "looks beautiful, won't open my
file."

**What it is not:** it is not a media library manager, not a streaming service, not a
transcoder front-end. It is a player. Playback is the product.

---

# PART 2 — THE FACTS (this is your entire source of truth)

Everything in this part is verified. Use it. Do not invent features beyond it, do not
inflate a number, and do not turn a measured figure into a rounder, prettier one.

## 2.1 Origin and honesty about it

- MacLC is a fork of VLC 4.0.0-dev, licensed **GPL v2 or later** (the engine `libVLC` is **LGPL v2.1 or later**).
- **It is not affiliated with, endorsed by, or supported by VideoLAN.**
- "VLC", "VideoLAN" and the traffic-cone logo are **VideoLAN trademarks**. MacLC uses none of them. It has its own name, its own bundle identifier (`org.maclc.MacLC`) and its own original icon.
- The site must state this clearly and respectfully, and must credit VideoLAN. This is both a legal requirement and, done well, a *credibility* asset: a project honest about what it inherited reads as more trustworthy, not less.

## 2.2 The flagship feature — SDR → HDR

**This is the hero of the entire site. Give it the most space, the best art direction, and
the most careful copy.**

**The problem.** An XDR display can go five to six times brighter than SDR white. Play an
ordinary video file — which is almost every file you own — and none of that is used,
because an ordinary file carries no HDR signal at all. Your expensive display sits idle on
99% of your library.

**Why the naive fix fails.** You cannot just relabel an SDR file as HDR. Under the PQ
encoding used by HDR, the same numbers mean roughly **five times** the brightness. Do that
and mid-tones blow out — faces go white, the whole picture looks wrong.

**What MacLC does.** A Metal compute shader (`VLCHDRExpander`, 895 lines) re-encodes each
SDR frame as PQ / BT.2020 10-bit:

```
Y'CbCr or BGRA → R'G'B' → linear (BT.1886 / sRGB) → highlight expansion
               → BT.2020 primaries → PQ → 10-bit x420
```

**Why the curve is the interesting part.** The expansion is **the identity at and below a
knee at half SDR white**, and quadratic above it — chosen so that value *and slope* match
the identity exactly at the knee, and SDR white lands exactly on the boost. It is applied
to the largest of the three colour components, and the whole triplet is scaled by the
result, so **hue and saturation never move.**

**The consequence — this is the sentence that sells it:**
> Shadows and mid-tones reach your eye at exactly the brightness they always did.
> Nothing is "brightened". Only the highlights — a glint on metal, a sky, a streetlight,
> an explosion — are lifted into the range your panel had spare all along.

**Measured results** (M3 Max, 6.15× display headroom, against an independently written CPU
reference implementation of the same transform):

| Measurement | Result |
|---|---|
| Luma and chroma vs. reference | Agree to the code over an eight-step ramp |
| Bit accuracy | Bottom six bits of every 16-bit word clear — true 10-bit, no noise in the pad bits |
| Round-trip through PQ | Returns the exact SDR luminance for every input at or below the knee, rising monotonically to exactly the boost at SDR white |
| Cost at 1080p | **0.53 ms** per frame, including the synchronous wait |
| Cost at 4K | **0.91 ms** per frame, including the synchronous wait |
| 60-second 4K run | Same wall-clock time as with the feature off |
| Memory | Flat against a 20-second run |

Effective boost is `min(your setting, the screen's real headroom)` — it can never ask for
more than the panel has. Output carries mastering-display metadata describing the volume
generated, so macOS has no reason to tone-map it back down. Skipped automatically for
sources already in PQ or HLG. Works live: flip the switch mid-film and the picture changes
on the frame you are watching, not on the next file.

Boost is user-adjustable, `1.0`–`16.0`, default `4.0`. `1.0` disables it. The copy should
say: *4.0 is natural, higher is dramatic and less faithful.*

**Honesty constraint on this claim.** Inverse tone mapping is not a new idea — libplacebo,
mpv and some TVs do versions of it. What is genuinely distinct here, and what you may say,
is: **MacLC does it in Metal on the default AVFoundation display path, where libplacebo is
unreachable on macOS, exposed as one switch and one slider, and validated numerically
against an independent reference.** Do not write "the only player in the world that…".
Write the precise thing. It is more impressive and it is true.

## 2.3 HDR defects fixed vs. upstream VLC

An audit of VLC 4.0.0-dev on Apple Silicon found **6 confirmed defects and 9 missing
capabilities** in the macOS HDR path. All six defects are fixed.

| What was broken in VLC | What you saw | What MacLC does |
|---|---|---|
| Display headroom read once, from the *main* screen | Drag the window to a second display, HDR brightness stayed wrong | Re-measured on every screen, window-move and display-profile change |
| The HDR mode selector and brightness slider in Preferences did nothing | The settings were decorative | Both wired live — they take effect during playback |
| No tone-mapping path to SDR | HDR film on a normal display clipped to flat white | A real conversion, with a correct fallback on older macOS |
| Subtitles untagged over HDR video | White subtitles rendered at full HDR luminance — searingly bright over dark scenes | Subtitles pinned to SDR and scaled to the ITU-R BT.2408 203-nit reference white |
| Video above 10-bit downsampled to 8-bit | 12-bit and 16-bit sources lost detail before reaching the screen | Full 10-bit path preserved; 16-bit 4:2:2 wired through |
| Sub-4K HDR mis-tagged, zero-nit mastering volume emitted | Wide-gamut content played through the wrong primaries | Correct tagging per stream |

## 2.4 New capabilities beyond the fixes

- **Hardware AV1 decoding on M3 and M4** — VideoToolbox, gated on real hardware support. Falls back to software elsewhere. Confirmed available on M3 Max.
- **HDR10+ dynamic metadata** carried end-to-end through the filter chain.
- **Dolby Vision metadata extraction** from the VideoToolbox bitstream, with hardened parsers, including a fix for Dolby Vision being lost to a stray bit on the very first frame.
- **Hand-written ARM64 NEON chroma conversions** replacing scalar loops on the software-decode path.
- **OpenGL 4.1 / 3.2 Core profile with 64-bit colour**, which is what unblocks libplacebo's shaders. Upstream failed with *"OpenGL version too old (2 < 3)"*.
- **Mastering-display (ST 2086) and content-light-level (CTA-861.3) metadata** forwarded correctly.
- **Per-window ICC profile** taken from the window's own screen rather than the main one.

## 2.5 The settings window

VLC's macOS preferences: five toolbar icons over five panes, plus an "Advanced" tree that
walks the entire module registry and renders one widget per option — thousands of
unexplained controls.

MacLC:

- **One window. A sidebar of categories. A search field** that filters by label, description *and* keyword.
- **Eight panes**: General · Playback · Video · HDR & Colour · Audio · Subtitles · Interface · Shortcuts.
- Each pane is a stack of **titled cards**. Each row is a label, a control, and **a one-sentence explanation underneath of what it does in terms of what you will see or hear.**
- The house style for those explanations: *"highlights keep detail but the picture is dimmer overall"* — never *"applies a BT.2390 EETF"*. **Quote this contrast on the site.** It is the clearest single expression of the product's philosophy.
- Advanced controls behind a collapsed disclosure. Anything that can break playback carries a warning glyph and a sentence saying what will happen.
- **Nothing decorative**: every control is verified wired to a real option in the build. Where an option is genuinely absent, the row is not drawn at all.
- **The old advanced tree is untouched and still reachable.** Nothing was taken away from power users.
- A startup self-check builds all eight panes and verifies every view, control and SF Symbol resolves: **8 panes, 8 ok, 0 failed.**

**A story worth telling on the site** (it is true, and it is the kind of detail that makes
engineers trust a product): opening the Interface pane used to *abort the entire app* on
one build configuration — a missing option hit an `assert()` deep inside the engine, a hard
process kill no error handler could catch. The fix routed **all 240 configuration reads in
the settings panes** through guarded wrappers. That is the difference between a settings
window that was drawn and one that was engineered.

## 2.6 The HDR pane

- **A live status block** — your connected display, its measured brightness headroom, the active video engine, and during playback the transfer function of the stream and whether tone mapping is currently on. When nothing is playing, it says so plainly.
- **Four named modes**, each with one plain sentence: *Automatic (recommended)* · *Always use HDR* · *Convert HDR to SDR* · *Turn HDR off*.
- **SDR → HDR** with a boost slider that shows the peak your setting reaches *and* the headroom your screen actually allows.
- **Brightness headroom**, automatic or manual.
- **Advanced**: tone-mapping curve (10 algorithms — hard clip, BT.2390 EETF, Reinhard, Mobius, Hable, gamma-power, linear stretch, BT.2446A, single-pivot spline), tone-mapping parameter, gamut mapping (7 modes), inverse tone mapping, dithering, ICC colour management.

Thirteen options, each verified against the module that declares it.

## 2.7 The interface

- **Unified toolbar**, transparent titlebar, search that collapses the way the system's does.
- **A real macOS source-list sidebar** — which is what brings the system's own vibrancy, material and collapse behaviour, rather than a table styled to look like one.
- **Floating HUD playback controls** over video, inset from the edges on the system's HUD material, SF Symbol transport glyphs at one weight and size, and **monospaced-digit time labels so the numbers stop shifting as the seconds tick.** (That last detail is small, specific and very "Apple". Use it.)
- **Empty states** that are a symbol, a headline, a sentence and an action — not a blank pane.
- **Six layout metrics moved onto the 8-point grid.** The small row height went from 25 pt to 32 pt — 25 pt was below a comfortable click target.

## 2.8 The design system underneath

Upstream had eleven literal colour values in one file alone, font sizes typed at the call
site, and corner radii that landed wherever they landed.

MacLC has **`MacLCDesign`**: a single token layer defining every colour, type style,
spacing, radius, material, icon configuration and animation duration, all mapped to the
system's own semantics.

**Which is why MacLC follows your accent colour, light and dark appearance, Reduce
Transparency, Reduce Motion, Increase Contrast, VoiceOver and full keyboard access —
because it never hardcoded around them in the first place.** Accessibility here is a
consequence of the architecture, not a feature bolted on. Say so.

## 2.9 App identity

- **Its own icon**: a graphite superellipse on Apple's 824-of-1024 icon grid, carrying a warm play triangle with a highlight bloom behind it and a specular edge along its lit face. The bloom is the only place any saturated colour appears — which is what lets it read as *bright* rather than merely orange.
- It is a **superellipse, not a rounded rectangle**: circular corners look visibly wrong beside system icons, and at 16 points that difference is most of what makes an icon look native. **This detail belongs on the site.**
- The artwork is **generated by a committed program**, so it can be regenerated, adjusted and diffed — not checked in as an opaque binary.
- **Its own bundle identifier.** While it shared VLC's, macOS resolved the running app to `/Applications/VLC.app` — Stage Manager drew VLC's cone on MacLC's windows, and MacLC was reading and writing the real VLC's settings and media library.
- **Your settings come with you.** First launch copies your preferences, application-support directory and defaults across. It only ever *copies* — your existing VLC install is left exactly as it was and keeps working.
- **Every translation still works.** Names are substituted after translation, so French resolves "Hide VLC" and then renders "Masquer MacLC". No language catalogue was broken.

## 2.10 Stability

Fixed: a use-after-free crash on quit (100% reproducible upstream), a playback stall, a
teardown deadlock, swapped subtitle channels, a dangling display pointer, a layer wait that
never ended, headroom lost mid-filter, and a duplicated toolbar separator.

## 2.11 Requirements

- **Apple Silicon** (M1 or newer)
- **macOS 13 Ventura** or later
- Full HDR feature set benefits from macOS 14+ / 15+
- Hardware AV1 decode needs M3 or M4
- SDR → HDR needs a display with real extended range (XDR or an HDR external panel); on an SDR display it does nothing
- Developed and measured on an M3 Max, macOS 26.2

## 2.12 What is NOT yet verified — and how the site must handle it

Two things have **not** been visually reviewed by a human: the interface redesign, and the
on-screen appearance of the SDR → HDR grade. The mathematics is verified; nobody has sat
in front of it and said "that looks good."

**Do not hide this. Turn it into the reason someone joins.** There should be an honest
"Where the project is" section near the bottom of the home page — quiet, confident,
factual — that says the engineering is measured and the aesthetics need eyes on them, and
invites people to be those eyes. Frame it as *early access to something being built
properly*, not as an apology. Projects that admit exactly what they have not checked are
the ones people believe about what they have.

---

# PART 3 — COMPETITIVE POSITIONING

Build a comparison, but build it **honestly**. A comparison table that overclaims destroys
the credibility the rest of the site works to earn, and this audience will check.

**Rules for the comparison:**

1. Only compare on axes where MacLC genuinely wins or genuinely ties.
2. Never mark a competitor red on something they actually do well. Give VLC, IINA and Infuse their real strengths visibly — it makes MacLC's wins land harder.
3. Where you are unsure of a competitor's current capability, either omit that row or mark it "varies" — never guess a red X.
4. No competitor logos (trademark risk). Use their names as plain text in the system typeface.
5. Add a footnote: *"Compared against publicly documented behaviour as of the date shown. Corrections welcome — open an issue."* And show a date.

**Suggested comparison set:** VLC · IINA · Infuse · Movist Pro · QuickTime Player

**Suggested axes:**

| Axis | MacLC's position |
|---|---|
| Plays essentially any format/container | Yes — full VLC engine |
| Native macOS interface (system materials, sidebar, HUD controls) | Yes |
| HDR10 / HLG / Dolby Vision metadata handling | Yes, with the six upstream defects fixed |
| Hardware AV1 decode on M3/M4 | Yes |
| **SDR → HDR highlight expansion on the native display path** | **Yes — MacLC only, of this set** |
| Settings that explain themselves in plain language | Yes |
| Full advanced option tree still available | Yes |
| Respects Reduce Motion / Transparency / Increase Contrast / VoiceOver by architecture | Yes |
| Open source, auditable | Yes — GPL v2+ |
| Price | Free. Donation optional |
| Subscription required | No |

**The honest framing to use in prose above the table:**
> VLC plays everything and doesn't feel like a Mac app. QuickTime feels perfect and won't
> open your file. Infuse is beautiful and asks for a subscription. IINA is genuinely lovely
> and doesn't go where MacLC goes on HDR. MacLC is the intersection nobody had built.

Also include a short, gracious **"What we didn't build"** note — MacLC is macOS and Apple
Silicon only, is a player rather than a library manager, and if you are on Windows or Linux
you should use VLC, which is excellent. Saying this out loud costs nothing and buys a great
deal of trust.

---

# PART 4 — SITE ARCHITECTURE

```
/                      Home — the full product narrative
/hdr                   Deep dive: HDR and SDR → HDR (the technical showpiece)
/design                Deep dive: interface, settings, design system, accessibility
/compare               Comparison against other macOS players
/donate                The donation gate — the ONLY route to a download
/download/thanks       Post-donation success + the actual download link
/download/direct       Free ($0) path landing — same download, zero friction, zero shame
/changelog             Release notes
/faq                   FAQ (incl. GPL, VideoLAN relationship, why donations)
/privacy               Privacy (should be short and genuinely good — no tracking)
/legal                 License + trademark attribution
404                    Custom, on-brand
```

---

# PART 5 — PAGE-BY-PAGE SPECIFICATION

## 5.1 Home

Design as a **scroll narrative**: one idea per viewport, each earning the next scroll.

**Section 1 — Hero**
- Full-viewport. Near-black background.
- Product name at extreme scale (`clamp(4rem, 12vw, 11rem)`), tight tracking (≈ `-0.04em`), weight 600–700.
- Sub-headline: *Everything VLC can play. Finally built like a Mac app.*
- The app icon rendered large, floating, with a soft warm bloom behind it that subtly tracks cursor position on desktop (and is static on touch / Reduce Motion).
- Two buttons: **Download** (primary — routes to `/donate`, never straight to a file) and **See what changed** (ghost, scrolls down).
- One quiet line beneath: *Free and open source · Apple Silicon · macOS 13+*
- Entrance: elements rise 24 px and fade over ~600 ms, staggered ~80 ms, spring easing. Once. Never on re-scroll.

**Section 2 — The SDR → HDR reveal (the money shot)**
- A scroll-scrubbed before/after. As the user scrolls, a masked frame transitions from SDR to expanded HDR — highlights blooming while mid-tones visibly hold still.
- **Critical honesty rule: label it.** A small persistent caption: *"Simulated on an SDR display. The real effect requires an HDR panel."* This is non-negotiable — you cannot show real HDR in a browser on an SDR screen, and pretending otherwise is a lie the audience will catch.
- Copy alongside, revealed in steps as the scrub advances: the problem → why relabelling fails → the knee → *"shadows and mid-tones don't move."*
- End on the measured cost: **0.53 ms at 1080p. 0.91 ms at 4K.** Set in monospaced digits.

**Section 3 — Six defects, fixed**
- The table from §2.3, rendered as cards or a refined table, not a wall of text.
- Consider a subtle "before" state (dimmed, struck) transitioning to "after" as each row enters the viewport.

**Section 4 — Settings that explain themselves**
- A large, pixel-accurate mockup of the settings window (you will build this in HTML/CSS — see §7.3).
- Beside it, the philosophy quote contrast: *"highlights keep detail but the picture is dimmer overall"* vs. *"applies a BT.2390 EETF"*. Make the typographic treatment do the arguing.

**Section 5 — Built on the system**
- Interface details: unified toolbar, real source list, floating HUD controls, monospaced-digit timecodes, 8-point grid.
- **Live demo idea:** a small interactive control that toggles the page's own appearance and shows the mockups following it — proving the point about respecting the system rather than merely claiming it.

**Section 6 — Accessibility as architecture**
- Short. Confident. The point that Reduce Motion, Increase Contrast, Reduce Transparency and VoiceOver work *because nothing was hardcoded around them.*

**Section 7 — The icon**
- Show it large. Tell the superellipse story and the bloom story. This is the section that signals someone cared about details nobody asked about.

**Section 8 — Comparison teaser**
- Three or four rows of the comparison, then a link to `/compare`.

**Section 9 — Where the project is** (see §2.12)
- Honest, quiet, confident. Invitation to test and report.

**Section 10 — Download / donate CTA**
- Restate the value in one line. Primary button to `/donate`. Beneath it, in smaller but *clearly legible* text: *"You can also download it for free."* → `/download/direct`.

**Section 11 — Footer**
- Nav, VideoLAN attribution and trademark disclaimer, license, source link, privacy, "not affiliated with VideoLAN".

## 5.2 `/hdr` — the technical showpiece

For the audience that wants to know *how*. Go deep and stay beautiful.

- The full pipeline diagram, as **inline SVG you author** (not an image), animated stage by stage on scroll, and legible in both light and dark.
- **The expansion curve, plotted live.** An interactive chart: x = input signal, y = output luminance. Let the visitor drag the boost slider (1.0–16.0) and watch the curve change. Mark the knee. Show the identity line below the knee overlapping exactly. This single interactive element will do more to communicate the feature than a page of prose.
- The verification results as a data table, in monospaced digits.
- The four HDR modes, each with its plain-language sentence.
- The complete advanced option list, presented as reference rather than marketing.
- A "what this does not do" note: it will not invent detail that was never captured, and on an SDR display it does nothing at all.

## 5.3 `/design`

- The settings window mockup at full scale.
- The card/row anatomy, annotated — label, control, explanation.
- The token layer explained visually: a colour ramp, the type scale, the 8-point grid.
- Before/after on the six changed metrics — particularly 25 pt → 32 pt for the click target.
- Accessibility section with live toggles where you can honestly demonstrate the behaviour on the page itself.

## 5.4 `/compare`

Per Part 3. Sticky header row, MacLC's column subtly emphasised (a slightly lighter surface
and a hairline border — not a screaming highlight). Mobile: transpose to per-competitor
cards rather than a horizontally scrolling table.

## 5.5 `/donate` — **the download gate**

This page carries the whole commercial model. Design it with more care than the hero.

**Flow: every Download button anywhere on the site routes here first. There is no direct
binary link in the primary navigation.**

**Structure:**

1. **Headline** — warm, not needy. Suggested: *"MacLC is free. Keeping it working isn't."*

2. **The honest ask — three or four short paragraphs.** This is the most important copy on the site. Write it like a person, not a nonprofit mailer. It should say, in substance:
   - MacLC is free and open source, and it always will be. There is no paid tier and nothing is held back.
   - But it is a fork of a very large codebase that upstream changes constantly. Every VLC release has to be merged, re-tested and re-measured. HDR behaviour changes with every macOS release — Apple changes tone-mapping semantics between versions and the whole path has to be re-verified.
   - Verification is the expensive part. The SDR → HDR shader was validated against a separately written CPU reference across the full signal range. That is the kind of work that keeps a picture correct, and it is invisible, unglamorous and slow.
   - Apple's developer program, notarisation and code signing cost money every year, whether anyone donates or not. An app that isn't signed and notarised is one macOS refuses to open.
   - Real hardware costs money. HDR claims cannot be verified on a spec sheet — verifying behaviour across displays means having the displays.
   - **If you can give something, it goes directly into that. If you can't, take it anyway — genuinely. Someone who tests it on a display we don't own and files a good bug report is worth more than most donations.**

3. **The amount selector.**
   - Preset tiles: **$0** · $3 · $5 · $10 · $25 · Custom.
   - **The $0 tile must be visually equal to the others.** Same size, same weight, same border treatment. Not smaller, not greyed, not a text link hidden below the fold, no guilt copy attached. If a designer would call it a dark pattern, you have built it wrong.
   - Label the $0 tile plainly: **"Nothing right now"**. Beneath it, one warm line: *"Completely fine. Enjoy it."*
   - Optional and genuinely nice: a checkbox on the $0 path — *"I'll test it and report what I find"* — which routes to the download and shows a short "what's most useful to report" note on the thanks page. It converts a non-donation into a contribution, without ever requiring it.

4. **Where it goes** — three or four small icon+label items: hardware for HDR verification · Apple developer program and notarisation · merging upstream VLC releases · re-testing after each macOS update. Keep it concrete. Do not fabricate a budget breakdown or precise percentages.

5. **Payment**: PayPal. See §6 for implementation.

6. **The GPL line, always visible on this page:**
   > MacLC is GPL v2+ software. The complete source code is always available, free, with no gate: [source link]. This page asks for support. It never sells access.

   This is a legal necessity *and* a trust asset — put it in the layout properly, not in 10 px grey.

7. **A quiet transparency block** (if and when real data exists): total raised this month, and what it went to. If there is no data yet, say *"Nothing to report yet — this is the first month."* Never invent figures.

## 5.6 `/download/thanks` and `/download/direct`

**Both must feel equally good.** Someone arriving from $0 should feel welcomed, not
processed.

- `/download/thanks`: genuine thanks (name it if PayPal returned one), the download button, checksum, version, size, macOS and hardware requirements, and a link to the changelog.
- `/download/direct`: same download, same warmth, no guilt. One low-key line at the bottom: *"If it turns out to be useful, you can always come back."* — and nothing more.
- Both pages: **system requirements shown before the button** (Apple Silicon, macOS 13+), first-launch Gatekeeper instructions if the build is not notarised, and the source-code link.

## 5.7 `/faq`

Include at minimum: Is this VLC? · Is it affiliated with VideoLAN? · Is it really free? · Why ask for donations if it's free? · Will it break my VLC install? (no — settings are copied, never moved) · Does it work on Intel? · Do I need an HDR display? · What does SDR → HDR actually do? · Why should I trust a fork with my media? · How do I go back to VLC? · How do I report a bug?

---

# PART 6 — THE PAYPAL DONATION FLOW (implementation)

## 6.1 Required behaviour

1. Every "Download" CTA on the site routes to `/donate`. No direct binary URL in the nav.
2. On `/donate`, the visitor chooses an amount, including **$0**.
3. **$0 →** straight to `/download/direct`. No payment step, no email required, no account, no delay, no interstitial.
4. **Any amount > 0 →** PayPal checkout → on success, `/download/thanks`.
5. **Payment cancelled or failed →** return to `/donate` with a calm, non-punitive message and the download still reachable. **Never trap a user behind a failed payment.**
6. The actual binary must remain reachable regardless — a failed payment must not become a locked door.

## 6.2 Recommended technical approach

**Preferred: PayPal JavaScript SDK (Orders v2) + a serverless capture endpoint.**

- Client renders PayPal Buttons with the chosen amount.
- On approval, the client calls your serverless function (`/api/capture`), which captures the order **server-side** using PayPal's REST API with credentials held in environment variables.
- The function verifies capture status, then issues a short-lived signed token (HMAC, ~30 min TTL) and redirects to `/download/thanks?t=…`.
- The thanks page validates the token and reveals the link.
- **Never put PayPal client secrets in front-end code.** Never trust a client-side "payment succeeded" claim.

**Acceptable simpler fallback** if no backend is available: a PayPal hosted Donate button
with a `return` URL to `/download/thanks`. Note in code comments that this return URL is
guessable and therefore not a real access control — which is fine here, because **the
download is deliberately not access-controlled anyway.** The gate is a *moment of asking*,
not a paywall. Design it as such, and say so in the code.

## 6.3 Rules

- Currency: USD by default; if you implement a currency selector, keep the presets sensible per currency (not a naive conversion producing $4.63).
- Do not collect an email as a condition of downloading. Offer an optional release-notification opt-in on the thanks page only, clearly optional.
- No analytics on the payment path beyond an anonymous count.
- Handle these states explicitly: pending · cancelled · declined · network error · user closed the PayPal window.
- Full keyboard operability through the entire flow. The amount tiles must be a proper radio group with visible focus rings.
- Announce state changes to screen readers via a polite live region.

---

# PART 7 — DESIGN DIRECTION (the part that decides whether this succeeds)

## 7.1 Principles

1. **One idea per viewport.** If two ideas are competing for attention, split them.
2. **Type carries the design.** Not gradients, not glass, not decoration. Enormous, beautifully set type against space.
3. **Space is the luxury signal.** When something feels cheap, the answer is almost always more room, not more ornament.
4. **Motion must have a job.** Reveal, direct attention, or demonstrate. Anything else is noise — remove it.
5. **Dark first.** MacLC is about light on screen; a dark canvas makes highlights read. Light mode must be equally finished, not an afterthought.
6. **Detail at the pixel level.** Optical alignment over mathematical alignment. Correct optical sizes. Real hanging punctuation where it matters.

## 7.2 Specifics

**Typography**
- Stack: `-apple-system, BlinkMacSystemFont, "SF Pro Display", "SF Pro Text", "Inter", system-ui, sans-serif`. Ship Inter as a webfont fallback with `font-display: swap` for non-Apple platforms.
- Display: `clamp(3.5rem, 9vw, 9rem)`, weight 600–700, tracking `-0.035em` to `-0.045em`, line-height 0.95–1.05.
- Section heads: `clamp(2rem, 4.5vw, 3.75rem)`, weight 600, tracking `-0.025em`.
- Body: 17–19 px, line-height 1.55–1.65, **max measure 68ch — never wider**.
- Caption: 13–14 px, reduced opacity, tracking `+0.01em`.
- **Every number, timecode, measurement and duration in `font-variant-numeric: tabular-nums`.** This is a MacLC product value; the site must live it.

**Colour**
- Dark: base `#0A0A0B` → `#111113`, surfaces `#161618` / `#1C1C1F`, hairlines `rgba(255,255,255,0.08)`, primary text `rgba(255,255,255,0.92)`, secondary `0.62`, tertiary `0.40`.
- Light: base `#FBFBFD`, surfaces `#FFFFFF`, hairlines `rgba(0,0,0,0.08)`.
- **One accent only**, taken from the icon's bloom: a warm amber-orange, roughly `#FF9A3C` → `#FF7A1A`. Use it sparingly — primary CTA, the highlight-expansion visualisation, the active state on the boost slider. **Nowhere else.** Restraint is what makes it read as premium.
- All text pairs must pass **WCAG AA** in both themes. Check them; do not assume.

**Layout**
- 8-point spacing scale: 8 · 16 · 24 · 32 · 48 · 64 · 96 · 128 · 192.
- Content max-width 1200 px; text columns 680 px; full-bleed for hero and visualisations.
- Section rhythm: 128–192 px vertical on desktop, 80–96 px on mobile.

**Motion**
- Entrances: 500–700 ms, `cubic-bezier(0.16, 1, 0.3, 1)`, 16–32 px travel, opacity 0 → 1.
- Stagger 60–90 ms between siblings. Never more than five staggered items.
- Scroll-scrub via **IntersectionObserver + `requestAnimationFrame`**, or CSS scroll-driven animations with a JS fallback. Never a scroll event handler doing layout reads.
- Hover: 150–200 ms, translate ≤ 2 px, scale ≤ 1.02. Subtle.
- **`prefers-reduced-motion: reduce` must disable every transform and scrub animation and render the final state immediately.** Not "reduce" — off. Test it.

**Surfaces**
- Cards: 12–16 px radius, hairline border, very subtle elevation. On dark, elevation is a *lighter surface*, not a heavier shadow.
- Backdrop blur only where content actually sits over content, and always with an opaque fallback.
- No glassmorphism as decoration. No neon. No mesh gradients. No floating 3D blobs.

## 7.3 The app mockups — build them in HTML/CSS

You have no screenshots of the real app. **Do not fake photographic screenshots, and do not
use stock images of other software.** Instead, build faithful, labelled HTML/CSS
reconstructions of the interface from the descriptions in Part 2:

- The settings window: sidebar with eight categories, search field at the top, cards in the detail pane, each row = label + control + explanation line.
- The HDR pane with its live status block and four mode options.
- The floating HUD player controls with SF Symbol-equivalent glyphs and a tabular-numerals timecode.

**Every mockup carries a small, permanent caption: *"Interface reconstruction."*** This is
not a limitation — done well, a crisp vector reconstruction looks *better* than a
screenshot and follows the site's own theme automatically. But it must be labelled.

Use inline SVG for all iconography (SF Symbols themselves may not be redistributed as web
assets — draw equivalents). Ship no raster UI images.

---

# PART 8 — TECHNICAL REQUIREMENTS

**Stack** — choose one and use it properly:
- **Astro** (recommended: content-heavy, ships almost no JS, islands for the interactive pieces), or
- **Next.js App Router** with React Server Components, or
- Hand-authored HTML/CSS/JS with a small build step.

Do not reach for a heavyweight SPA framework for what is a marketing site.

**Non-negotiables**
- Fully responsive: 320 px → 2560 px. Test at 320, 375, 768, 1024, 1440, 1920.
- Lighthouse ≥ 95 on Performance, Accessibility, Best Practices, SEO.
- LCP < 1.8 s on simulated 4G. CLS < 0.05. Total JS under 100 KB gzipped for the home page.
- Semantic HTML. One `<h1>` per page. Correct heading hierarchy. Landmark regions.
- Every interactive element keyboard-reachable with a visible focus ring (a real ring, not `outline: none` plus a colour change).
- All images with real `alt` text; decorative ones `alt=""` and `aria-hidden`.
- Respect `prefers-reduced-motion`, `prefers-color-scheme`, `prefers-contrast`.
- Open Graph and Twitter card metadata, plus a generated OG image per page.
- `sitemap.xml`, `robots.txt`, JSON-LD `SoftwareApplication` schema.
- **No third-party analytics, no tracking pixels, no cookie banner.** If measurement is needed, use privacy-preserving server-side counting and say so on `/privacy`. A player whose pitch is trust cannot ship a tracking script — and the *absence* of a cookie banner is itself a statement.

**Content management**
- Version number, file size, checksum, release date and download URL in **one config file**, referenced everywhere. Never hardcode a version in markup.
- Changelog authored in Markdown.

---

# PART 9 — VOICE AND COPY

**Voice:** the engineer who built it, explaining it to a smart friend. Precise, warm,
unhurried, quietly proud. Never breathless. Never a startup landing page.

**Rules**
- Say what it does and what you will see. *"Shadows and mid-tones don't move"* beats *"revolutionary AI-powered HDR enhancement"* by an enormous distance.
- Numbers are your strongest asset. Use them exactly: **0.53 ms**, **0.91 ms**, **6 defects**, **240 config reads**, **8 panes**, **6.15×**. Never round them up for rhythm.
- **Banned:** revolutionary · game-changing · seamless · cutting-edge · unleash · elevate · reimagined · next-generation · AI-powered · blazing fast · buttery smooth. Also: any em-dash-heavy breathless cadence.
- Sentences short. Paragraphs three lines or fewer. If a sentence needs a comma to survive, split it.
- Technical terms are allowed **after** a plain-English sentence has done the work — exactly the rule the app itself follows for its settings.
- Never claim a superlative you cannot defend. Precision is more persuasive than hyperbole to this audience, and this audience is the only one that matters.

**Reference lines you may use verbatim:**
- *Everything VLC can play. Finally built like a Mac app.*
- *Your display can go six times brighter than SDR white. Almost nothing you own asks it to.*
- *Shadows and mid-tones reach your eye at exactly the brightness they always did. Only the highlights move.*
- *Every setting tells you what it does. In a sentence. In English.*
- *0.53 ms at 1080p. You will not notice it. You will notice the picture.*
- *It respects Reduce Motion, Increase Contrast and VoiceOver — because it never hardcoded around them in the first place.*

---

# PART 10 — LEGAL AND ETHICAL CONSTRAINTS

These are hard requirements, not preferences.

1. **Never imply VideoLAN endorsement.** A visible disclaimer in the footer of every page, and a fuller statement on `/legal` and `/faq`.
2. **Never use the VLC cone or any VideoLAN mark**, in any form, including as a "before" image, a struck-through logo, or a silhouette. Refer to VLC by name in plain text only.
3. **Credit VideoLAN generously and sincerely.** MacLC exists because of two decades of their work. The site should say so somewhere it is actually read, not only in the legal page.
4. **GPL compliance is visible, not buried.** Source-code link in the footer of every page, and stated plainly on `/donate`. The download page must make clear that the source is always available at no cost.
5. **The donation must never be framed as a purchase.** No "buy", no "price", no "unlock", no "pro version". It is support for maintenance. The $0 option makes this true; the copy must make it obvious.
6. **No dark patterns anywhere in the donation flow.** No pre-selected amount above $0. No countdown timers. No fake scarcity. No "are you sure?" friction on the $0 path. No guilt copy. No prechecked recurring-donation box.
7. **Never fabricate:** user counts, testimonials, download numbers, review quotes, press mentions, awards, team size, or donation totals. If there is no social proof yet, build a beautiful page that does not need any. There is a real story here; it does not require invented ones.
8. **Label every simulated visual.** The SDR/HDR comparison and every interface reconstruction must carry a visible caption saying what it is.
9. Comparison claims must be defensible, dated, and correctable — with an explicit invitation to report errors.

---

# PART 11 — WHAT TO DELIVER

1. A complete, runnable project — installable and buildable with standard commands.
2. Every page in Part 4, fully built, in light and dark, responsive across the full range.
3. All interface mockups built in HTML/CSS/SVG, labelled as reconstructions.
4. The interactive expansion-curve visualisation on `/hdr`, working with the boost slider.
5. The complete donation flow, including the PayPal integration and the serverless capture endpoint (with clear setup instructions for credentials as environment variables).
6. A `README.md` explaining: how to run it, how to change the version/download config, how to configure PayPal, and how to deploy.
7. A short `DESIGN-NOTES.md` recording the type scale, colour tokens, spacing scale and motion values you settled on — so the next person does not have to reverse-engineer them.

---

# PART 12 — HOW TO START

Do **not** begin by writing markup.

1. First, write back a **one-page creative direction**: the core narrative arc of the home page, the three or four moments you intend to be memorable, your type scale, your colour tokens, and your motion language. Include the exact hero copy you propose.
2. Then build the design system — tokens, base styles, primitives.
3. Then the home page, section by section, complete before moving on.
4. Then the deep-dive pages.
5. Then the donation flow.
6. Then the supporting pages.
7. Then the accessibility, performance and cross-viewport pass.

Ask before you start **only** if something is genuinely blocking. Otherwise choose the
strong option, state the choice, and build.

**The test to hold yourself to, section by section:** would this survive being placed next
to a real Apple product page, on the same screen, at the same time?

If not, it is not finished.
