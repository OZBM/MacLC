"""Grades the made-up frame rendered by hdr_scene.py into the README's SDR/HDR illustration.

Usage: grade_illustration.py <frame.exr> <exposure> <out_dir>
Writes, as float32 RGBA in extended-linear Display P3 (1.0 = SDR white), for gainmap.swift:
  split-base.raw / split-hdr.raw  the split frame: SDR on the left, HDR on the right
  hdr-base.raw / hdr-hdr.raw      the whole frame in HDR (and its SDR fallback)
and sdr.png, the whole frame as SDR video would show it. Prints the size.
"""
import os
import sys

os.environ["OPENCV_IO_ENABLE_OPENEXR"] = "1"
import cv2  # noqa: E402
import numpy as np  # noqa: E402
from PIL import Image, ImageDraw, ImageFont  # noqa: E402

src, exposure, out = sys.argv[1], float(sys.argv[2]), sys.argv[3]
lin = cv2.imread(src, cv2.IMREAD_UNCHANGED)[..., :3][..., ::-1].astype(np.float32) * exposure
h, w, _ = lin.shape
Y709 = np.array([0.2126, 0.7152, 0.0722], np.float32)
P3 = np.array([[0.8225, 0.1774, 0.0], [0.0332, 0.9669, 0.0], [0.0171, 0.0724, 0.9108]], np.float32)

# A little bloom around the light sources, in scene light, the same for every grade.
spill = np.maximum(lin - 1.5, 0)
for sigma, weight in ((2.5, 0.10), (10, 0.05), (36, 0.025)):
    lin += weight * cv2.GaussianBlur(spill, (0, 0), sigma)


def shoulder(x, knee, peak):
    """Identity up to knee, then an exponential approach to peak."""
    span = peak - knee
    return np.where(x <= knee, x, knee + span * (1 - np.exp(-(x - knee) / span)))


def by_max(rgb, knee, peak):
    """Shoulder on the brightest channel, the colour kept."""
    m = rgb.max(axis=2, keepdims=True)
    return rgb * (shoulder(m, knee, peak) / np.maximum(m, 1e-6))


def whiten(rgb, start, end, amount):
    """Very bright light turns towards white, as it does on film."""
    y = (rgb @ Y709)[..., None]
    t = np.clip((rgb.max(axis=2, keepdims=True) - start) / (end - start), 0, 1)
    return rgb + (y - rgb) * (t * t * (3 - 2 * t)) * amount


# SDR video: every channel clips softly at white, so neon and the sun bleach to flat white.
sdr = shoulder(lin, 0.85, 1.0)
# HDR: the same picture with its light kept, up to 8x SDR white.
hdr = whiten(by_max(lin, 0.85, 8.0), 3.0, 8.0, 0.55)
# The HDR picture on an SDR screen: highlights compressed, colours kept.
hdr_on_sdr = whiten(by_max(lin, 0.7, 1.0), 0.9, 1.0, 0.25)


def labelled(left, right, divider):
    img = np.concatenate([left[:, : w // 2], right[:, w // 2:]], axis=1) if divider else right.copy()
    font = ImageFont.truetype("/System/Library/Fonts/SFNS.ttf", 30)
    pill, text = Image.new("L", (w, h)), Image.new("L", (w, h))
    spots = (("SDR", 24, "la"), ("HDR", w - 24, "ra")) if divider else ()
    for label, x, anchor in spots:
        d = ImageDraw.Draw(text)
        x0, y0, x1, y1 = d.textbbox((x, 22), label, font=font, anchor=anchor)
        ImageDraw.Draw(pill).rounded_rectangle((x0 - 14, y0 - 9, x1 + 14, y1 + 9), radius=12, fill=255)
        d.text((x, 22), label, font=font, fill=255, anchor=anchor)
    a_p = np.asarray(pill, np.float32)[..., None] / 255
    a_t = np.asarray(text, np.float32)[..., None] / 255
    img = img * (1 - 0.55 * a_p)
    img = img * (1 - a_t) + a_t
    if divider:
        img[:, w // 2 - 1: w // 2 + 1] = 1.0
    return img


def save(name, rgb):
    p3 = np.maximum(rgb @ P3.T, 0)
    np.concatenate([p3, np.ones((h, w, 1), np.float32)], axis=2).astype(np.float32).tofile(os.path.join(out, name))


save("split-base.raw", np.clip(labelled(sdr, hdr_on_sdr, True), 0, 1))
save("split-hdr.raw", labelled(sdr, hdr, True))
save("hdr-base.raw", np.clip(hdr_on_sdr, 0, 1))
save("hdr-hdr.raw", hdr)
enc = np.where(sdr <= 0.0031308, 12.92 * sdr, 1.055 * np.power(np.clip(sdr, 0, 1), 1 / 2.4) - 0.055)
Image.fromarray((np.clip(enc, 0, 1) * 255 + 0.5).astype(np.uint8)).save(os.path.join(out, "sdr.png"))
right = hdr[:, w // 2:]
print(w, h, "hdr max", round(float(hdr.max()), 2), "right half above white", round(float((right.max(axis=2) > 1).mean()), 3),
      "above 4x", round(float((right.max(axis=2) > 4).mean()), 4))
