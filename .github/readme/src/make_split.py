"""The README's SDR to HDR demo from two HDR captures of MacLC playing the same still clip,
SDR to HDR off and on (raw float32 RGBA, extended-linear Display P3, 1.0 = SDR white).
Writes base.raw (what SDR screens show: the 'off' capture twice) and hdr.raw (the 'off'
capture, then the 'on' one), float32 RGBA in extended-linear Display P3, and prints the size.

Usage: make_split.py <off.f32> <on.f32> <capture WxH> <crop x0,y0,x1,y1> <right label> <width>
"""
import sys
import numpy as np
from PIL import Image, ImageDraw, ImageFont

off_path, on_path, size, crop, right_label, width = sys.argv[1:7]
cw, ch = (int(v) for v in size.split("x"))
x0, y0, x1, y1 = (int(v) for v in crop.split(","))
width = int(width)

def load(path):
    return np.fromfile(path, np.float32).reshape(ch, cw, 4)[y0:y1, x0:x1, :3]

gap = 12
half = (width - gap) // 2
h = round((y1 - y0) * half / (x1 - x0))

def fit(img):
    # cv2-free resize of linear light: Pillow's float mode, one channel at a time
    return np.stack([np.asarray(Image.fromarray(img[..., c]).resize((half, h), Image.LANCZOS)) for c in range(3)], axis=2)

off, on = fit(load(off_path)), fit(load(on_path))
canvas = lambda: np.full((h, width, 3), 0.0055, np.float32)  # GitHub's dark #0d1117, roughly, in linear light
base, hdr = canvas(), canvas()
base[:, :half], base[:, width - half:] = off, off
hdr[:, :half], hdr[:, width - half:] = off, on

# Labels at SDR white with a soft shadow, the same in both renditions so the gain map leaves them alone.
font = ImageFont.truetype("/System/Library/Fonts/SFNS.ttf", 30)
text, shadow = Image.new("L", (width, h)), Image.new("L", (width, h))
for label, x in (("Original", 26), (right_label, width - half + 26)):
    ImageDraw.Draw(shadow).text((x + 2, 26), label, font=font, fill=200)
    ImageDraw.Draw(text).text((x, 24), label, font=font, fill=255)
a_s = np.asarray(shadow, np.float32)[..., None] / 255
a_t = np.asarray(text, np.float32)[..., None] / 255
for img in (base, hdr):
    img *= 1 - a_s
    img[:] = img * (1 - a_t) + a_t

base = np.clip(base, 0, 1)
for name, img in (("base.raw", base), ("hdr.raw", hdr)):
    np.concatenate([img, np.ones((h, width, 1), np.float32)], axis=2).astype(np.float32).tofile(name)
print(width, h, "hdr max", round(float(hdr.max()), 2), "share above white", round(float((hdr[:, width - half:].max(axis=2) > 1).mean()), 3))
