"""Light and dark SVG charts for MacLC's README.

Usage: python3 make_charts.py <curve.csv> <out_dir>
Colours: the dataviz reference categorical slots 1-2 (validated against
GitHub's #ffffff and #0d1117 canvases), text in GitHub's own ink.
"""
import csv
import sys
from datetime import date

FONT = "-apple-system, BlinkMacSystemFont, 'SF Pro Text', 'Segoe UI', Helvetica, Arial, sans-serif"

THEMES = {
    "light": dict(ink="#1f2328", ink2="#59636e", ink3="#818b98", grid="#d1d9e0", axis="#9198a1",
                  orange="#eb6834", blue="#2a78d6", band="#eb6834", band_op="0.07", dot_ring="#ffffff",
                  track="#d1d9e0"),
    "dark": dict(ink="#f0f6fc", ink2="#9198a1", ink3="#6e7681", grid="#30363d", axis="#656c76",
                 orange="#d95926", blue="#3987e5", band="#d95926", band_op="0.12", dot_ring="#0d1117",
                 track="#30363d"),
}


def svg(w, h, body, label):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {w} {h}" width="{w}" height="{h}" '
            f'role="img" aria-label="{label}" font-family="{FONT}">\n{body}\n</svg>\n')


def text(x, y, s, size=13, fill="#000", anchor="start", weight=400, extra=""):
    s = s.replace("&", "&amp;").replace("<", "&lt;")
    return (f'<text x="{x:.1f}" y="{y:.1f}" font-size="{size}" fill="{fill}" text-anchor="{anchor}" '
            f'font-weight="{weight}" {extra}>{s}</text>')


def curve_chart(rows, t):
    W, H = 960, 560
    L, R, T, B = 84, 690, 118, 470          # plot box
    ymax = 420.0
    X = lambda s: L + s * (R - L)
    Y = lambda v: B - v / ymax * (B - T)
    out = []
    out.append(text(24, 40, "SDR to HDR, Balanced level: only what should shine gets brighter", 22, t["ink"], weight=600))
    out.append(text(24, 64, "Brightness on screen for every level of an ordinary (SDR) video, at the default setting.",
                    14, t["ink2"]))
    # legend row
    lx = 24
    for name, col, dash in (("Original video", t["ink2"], "5 4"), ("MacLC, small highlights", t["orange"], ""),
                            ("MacLC, large bright areas", t["blue"], "")):
        d = f' stroke-dasharray="{dash}"' if dash else ""
        out.append(f'<line x1="{lx}" y1="88" x2="{lx + 22}" y2="88" stroke="{col}" stroke-width="2.5"{d} stroke-linecap="round"/>')
        out.append(text(lx + 30, 92.5, name, 13, t["ink2"]))
        lx += 30 + len(name) * 7.0 + 26
    # highlight band (where the curves part)
    out.append(f'<rect x="{X(0.905):.1f}" y="{T}" width="{X(1) - X(0.905):.1f}" height="{B - T}" '
               f'fill="{t["band"]}" fill-opacity="{t["band_op"]}"/>')
    # grid + y ticks
    for v in (0, 100, 200, 300, 400):
        out.append(f'<line x1="{L}" y1="{Y(v):.1f}" x2="{R}" y2="{Y(v):.1f}" stroke="{t["grid"]}" stroke-width="1"/>')
        out.append(text(L - 10, Y(v) + 4.5, f"{v}", 12, t["ink2"], "end", extra='font-variant-numeric="tabular-nums"'))
    # x ticks
    for s in (0, 0.25, 0.5, 0.75, 1.0):
        out.append(f'<line x1="{X(s):.1f}" y1="{B}" x2="{X(s):.1f}" y2="{B + 5}" stroke="{t["axis"]}" stroke-width="1"/>')
        out.append(text(X(s), B + 21, f"{int(s * 100)}%", 12, t["ink2"], "middle"))
    out.append(f'<line x1="{L}" y1="{B}" x2="{R}" y2="{B}" stroke="{t["axis"]}" stroke-width="1"/>')
    out.append(text((L + R) / 2, B + 46, "Brightness in the video file (signal level)", 13, t["ink2"], "middle"))
    out.append(text(22, (T + B) / 2, "On screen (cd/m², SDR white = 100)", 13, t["ink2"], "middle",
                    extra=f'transform="rotate(-90 22 {(T + B) / 2})"'))
    # region captions
    out.append(text(X(0.45), Y(352), "Shadows, skin and mid-tones:", 14, t["ink"], "middle", 600))
    out.append(text(X(0.45), Y(352) + 20, "exactly as filmed", 14, t["ink"], "middle", 600))
    out.append(text(X(0.905) - 8, Y(405), "Highlights", 13, t["orange"] if False else t["ink2"], "end"))
    # series
    def path(key):
        pts = " ".join(f"{X(float(r['signal'])):.1f},{Y(float(r[key]) * 100):.1f}" for r in rows)
        return pts
    out.append(f'<polyline points="{path("original")}" fill="none" stroke="{t["ink2"]}" stroke-width="2.5" '
               f'stroke-dasharray="5 4" stroke-linecap="round" stroke-linejoin="round"/>')
    out.append(f'<polyline points="{path("large")}" fill="none" stroke="{t["blue"]}" stroke-width="2.5" '
               f'stroke-linecap="round" stroke-linejoin="round"/>')
    out.append(f'<polyline points="{path("small")}" fill="none" stroke="{t["orange"]}" stroke-width="2.5" '
               f'stroke-linecap="round" stroke-linejoin="round"/>')
    # end markers with surface ring + direct labels
    last = rows[-1]
    for key, col, lab in (("small", t["orange"], "400: lamps, sun, reflections"),
                          ("large", t["blue"], "190: a bright sky stays calm"),
                          ("original", t["ink2"], "100: where the original stops")):
        v = float(last[key]) * 100
        out.append(f'<circle cx="{X(1):.1f}" cy="{Y(v):.1f}" r="5" fill="{col}" stroke="{t["dot_ring"]}" stroke-width="2"/>')
        out.append(text(X(1) + 14, Y(v) + 4.5, lab, 13, t["ink"]))
    out.append(text(24, H - 18, "Computed with MacLC's own curve (maclc_sdr2hdr_curve_point, Balanced level, highlights up to 400 cd/m²). "
                    "High and Maximum refine it scene by scene.", 11.5, t["ink3"]))
    return svg(W, H, "\n".join(out), "Chart: SDR to HDR leaves shadows and mid-tones unchanged and lifts only the top of the signal, small highlights up to 400 cd/m², large bright areas to 190, while the original stops at 100.")


def ladder_chart(t):
    # What donations pay for: the milestones of hazenstudio.com/maclc/donate (data/support.js).
    goals = [(99, "No more “Open Anyway”", "Apple notarisation"),
             (400, "Play on TV out of beta", "real Apple TV + Chromecast"),
             (900, "A second HDR screen", "tested on more panels"),
             (1600, "MacLC for everyone", "full accessibility pass"),
             (2500, "Self-updating app", "signed in-app updates")]
    W, H = 960, 270
    L, R, Yt = 96, 864, 128
    step = (R - L) / (len(goals) - 1)
    out = [text(24, 40, "What your donation unlocks", 22, t["ink"], weight=600),
           text(24, 64, "Totals raised across all donors. Each step ships when its total is reached.", 14, t["ink2"])]
    out.append(f'<line x1="{L}" y1="{Yt}" x2="{R}" y2="{Yt}" stroke="{t["track"]}" stroke-width="4" stroke-linecap="round"/>')
    for i, (e, title, sub) in enumerate(goals):
        x = L + i * step
        first = i == 0
        col = t["orange"] if first else t["ink2"]
        out.append(f'<circle cx="{x:.1f}" cy="{Yt}" r="{9 if first else 7}" fill="{col}" stroke="{t["dot_ring"]}" stroke-width="3"/>')
        out.append(text(x, Yt - 22, f"€{e:,}", 16, t["ink"], "middle", 600, extra='font-variant-numeric="tabular-nums"'))
        out.append(text(x, Yt + 36, title, 13, t["ink"], "middle", 600 if first else 400))
        out.append(text(x, Yt + 54, sub, 12, t["ink2"], "middle"))
    out.append(text(24, H - 18, "Milestones as published on hazenstudio.com/maclc/donate (live total there).", 11.5, t["ink3"]))
    return svg(W, H, "\n".join(out), "Donation milestones: 99 euros for Apple notarisation, 400 for Play on TV out of beta, 900 for a second HDR screen, 1,600 for an accessibility pass, 2,500 for self-updating releases.")


def timeline_chart(t):
    rel = [("1.0", date(2026, 9, 22), "first release"),
           ("1.1", date(2026, 9, 23), "torrent streaming"),
           ("1.1.1", date(2026, 9, 23), "self-contained app"),
           ("1.2", date(2026, 10, 3), "library, Metal engine"),
           ("1.3", date(2026, 10, 7), "Watch, add-ons, sound"),
           ("1.4", date(2026, 10, 10), "history, YouTube"),
           ("1.5", date(2026, 11, 1), "Xcode, macOS 27"),
           ("1.6", date(2026, 11, 2), "upscaling, compare")]
    W, H = 960, 250
    L, R, Yt = 60, 930, 142
    d0, d1 = date(2026, 9, 20), date(2026, 11, 4)
    X = lambda d: L + (d - d0).days / (d1 - d0).days * (R - L)
    out = [text(24, 40, "8 releases in 6 weeks", 22, t["ink"], weight=600),
           text(24, 64, "Every version since the first beta, with what it brought.", 14, t["ink2"])]
    out.append(f'<line x1="{L}" y1="{Yt}" x2="{R}" y2="{Yt}" stroke="{t["track"]}" stroke-width="2"/>')
    for m, lab in ((date(2026, 10, 1), "Oct"), (date(2026, 11, 1), "Nov")):
        out.append(f'<line x1="{X(m):.1f}" y1="{Yt - 6}" x2="{X(m):.1f}" y2="{Yt + 6}" stroke="{t["axis"]}" stroke-width="1"/>')
    out.append(text(X(date(2026, 9, 21)), Yt + 84, "Sep 2026", 12, t["ink3"], "start"))
    out.append(text(X(date(2026, 10, 1)), Yt + 84, "Oct", 12, t["ink3"], "middle"))
    out.append(text(X(date(2026, 11, 1)), Yt + 84, "Nov", 12, t["ink3"], "middle"))
    # label rows chosen by hand so nothing collides: (row, anchor, dx); row <0 above the axis, >0 below
    slots = {"1.0": (-1, "end", 6), "1.1": (1, "start", -6), "1.1.1": (-1, "start", -4), "1.2": (1, "middle", 0),
             "1.3": (-1, "middle", 0), "1.4": (1, "middle", 0), "1.5": (-1, "end", 6), "1.6": (1, "end", 10)}
    for v, d, what in rel:
        x = X(d)
        row, anchor, dx = slots[v]
        lx = x + dx
        col = t["orange"] if v == "1.6" else t["ink2"]
        base = Yt - 28 - (abs(row) - 1) * 44 if row < 0 else Yt + 34
        if row == -2:
            out.append(f'<line x1="{x:.1f}" y1="{Yt - 8}" x2="{lx - 4:.1f}" y2="{base + 10:.1f}" stroke="{t["axis"]}" stroke-width="1"/>')
        out.append(f'<circle cx="{x:.1f}" cy="{Yt}" r="{7 if v == "1.6" else 6}" fill="{col}" stroke="{t["dot_ring"]}" stroke-width="2.5"/>')
        if row < 0:
            out.append(text(lx, base - 17, v, 15, t["ink"], anchor, 600))
            out.append(text(lx, base, what, 12, t["ink2"], anchor))
        else:
            out.append(text(lx, base, v, 15, t["ink"], anchor, 600))
            out.append(text(lx, base + 17, what, 12, t["ink2"], anchor))
    return svg(W, H, "\n".join(out), "Timeline: MacLC 1.0 on 22 September 2026 to 1.6 on 2 November 2026, eight releases.")


def motion_demo(t):
    # The same movement at 24 fps (steps) and at the screen's own rate (linear): an illustration, not a capture.
    W, H = 960, 230
    L, R = 250, 900
    span, dur = R - L, 2.5
    lanes = ((84, "24 fps, as filmed", t["ink2"], f"steps({int(24 * dur)}, end)"),
             (158, "Interpolated to 120 fps", t["orange"], "linear"))
    out = [f"""<style>
@keyframes run {{ from {{ transform: translateX(0px); }} to {{ transform: translateX({span}px); }} }}
.dot {{ animation: run {dur}s infinite alternate; }}
@media (prefers-reduced-motion: reduce) {{ .dot {{ animation: none; }} }}
</style>"""]
    out.append(text(24, 36, "Smooth motion, illustrated", 20, t["ink"], weight=600))
    out.append(text(24, 58, "The same movement at both frame rates. Your browser draws the lower one as smoothly as it can.",
                    13, t["ink2"]))
    for y, label, col, timing in lanes:
        out.append(text(24, y + 5, label, 14, t["ink"], weight=600 if col == t["orange"] else 400))
        out.append(f'<line x1="{L}" y1="{y}" x2="{R}" y2="{y}" stroke="{t["track"]}" stroke-width="2" stroke-linecap="round"/>')
        out.append(f'<circle class="dot" cx="{L}" cy="{y}" r="13" fill="{col}" stroke="{t["dot_ring"]}" stroke-width="2.5" '
                   f'style="animation-timing-function: {timing};"/>')
    out.append(text(24, H - 16, "Illustration, not a capture: real interpolation computes the in-between frames from the video.", 11.5, t["ink3"]))
    return svg(W, H, "\n".join(out), "Animated illustration: a dot crossing the screen in visible steps at 24 frames per second, and smoothly at 120 frames per second.")


if __name__ == "__main__":
    rows = list(csv.DictReader(open(sys.argv[1])))
    out_dir = sys.argv[2]
    for name, t in THEMES.items():
        open(f"{out_dir}/sdr-to-hdr-curve-{name}.svg", "w").write(curve_chart(rows, t))
        open(f"{out_dir}/donation-milestones-{name}.svg", "w").write(ladder_chart(t))
        open(f"{out_dir}/releases-{name}.svg", "w").write(timeline_chart(t))
        open(f"{out_dir}/motion-demo-{name}.svg", "w").write(motion_demo(t))
