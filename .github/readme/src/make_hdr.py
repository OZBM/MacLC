"""Split Before/After still for the README: left as filmed, right through MacLC's
Fast SDR to HDR curve (same maths as vlc_hdr_expand_fast in VLCHDRExpander.m).
Writes base.png (8-bit sRGB, what SDR screens show) and hdr.raw (float32 RGBA,
extended linear sRGB, what HDR screens show)."""
import sys
import numpy as np
from PIL import Image, ImageDraw, ImageFont

src, width, peak = sys.argv[1], int(sys.argv[2]), float(sys.argv[3])
frame = Image.open(src).convert("RGB")
frame = frame.crop((900, 0, frame.width, frame.height))     # the sun, the tower and the sky
half = width // 2 - 6
fh = round(frame.height * half / frame.width)
frame = frame.resize((half, fh), Image.LANCZOS)
h = fh
im = Image.new("RGB", (width, h), (13, 17, 23))
im.paste(frame, (0, 0)); im.paste(frame, (width - half, 0))
mid = width // 2

# labels go into the 8-bit picture first, so both copies carry them at SDR white
d = ImageDraw.Draw(im)
font = ImageFont.truetype("/System/Library/Fonts/SFNS.ttf", 30)
for txt, x in (("Original", 26), ("MacLC SDR to HDR", width - half + 26)):
    d.text((x + 2, 24 + 2), txt, font=font, fill=(0, 0, 0))
    d.text((x, 24), txt, font=font, fill=(255, 255, 255))
im.save("base.png")

srgb = np.asarray(im).astype(np.float32) / 255.0
lin = np.where(srgb <= 0.04045, srgb / 12.92, ((srgb + 0.055) / 1.055) ** 2.4)

def fast_curve(dv, knee, pk):
    span = max(1.0 - knee, 1e-4)
    t = (dv - knee) / span
    return np.where(dv <= knee, dv, np.where(dv <= 1.0, dv + (pk - 1.0) * t * t,
                                             pk + (dv - 1.0) * (1.0 + 2.0 * (pk - 1.0) / span)))

kr, kb = 0.2126, 0.0722
r, g, b = lin[..., 0], lin[..., 1], lin[..., 2]
y = kr * r + (1 - kr - kb) * g + kb * b
drive = np.maximum(y, 0.85 * np.maximum(np.maximum(r, g), b))
gain = np.where(drive > 0, fast_curve(drive, 0.5, peak) / np.maximum(drive, 1e-6), 1.0)
gain[:, : width - half] = 1.0                 # the left copy and the gap stay as filmed
hdr = lin * gain[..., None]
# the white label text on the right keeps SDR white
text_mask = (srgb.min(axis=2) > 0.98) & (np.arange(h)[:, None] < 70)
hdr[text_mask] = lin[text_mask]
rgba = np.concatenate([hdr, np.ones((h, width, 1), np.float32)], axis=2).astype(np.float32)
rgba.tofile("hdr.raw")
print(width, h, "max", float(hdr.max()), "share of right half above SDR white",
      float((hdr[:, mid:].max(axis=2) > 1.0).mean()))
