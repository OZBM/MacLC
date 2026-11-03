"""HDR rendition of the banner: the art's highlights through MacLC's Fast SDR to HDR curve,
text and icon left at SDR white. Writes banner-base.png and banner-hdr.raw (float32 RGBA)."""
import numpy as np
from PIL import Image
full = np.asarray(Image.open("bA.png").convert("RGB")).astype(np.float32) / 255
art = np.asarray(Image.open("bA-art.png").convert("RGB")).astype(np.float32) / 255
lin = lambda c: np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)
F, A = lin(full), lin(art)
def fast_curve(d, knee=0.5, pk=4.0):
    t = (d - knee) / (1 - knee)
    return np.where(d <= knee, d, np.where(d <= 1, d + (pk - 1) * t * t, pk + (d - 1) * (1 + 2 * (pk - 1) / (1 - knee))))
y = 0.2126 * A[..., 0] + 0.7152 * A[..., 1] + 0.0722 * A[..., 2]
d = np.maximum(y, 0.85 * A.max(axis=2))
gain = np.where(d > 0, fast_curve(d) / np.maximum(d, 1e-6), 1.0)
gain[np.abs(full - art).max(axis=2) > 2 / 255] = 1.0     # text, chips and icon stay at SDR white
hdr = F * gain[..., None]
h, w = gain.shape
np.concatenate([hdr, np.ones((h, w, 1))], axis=2).astype(np.float32).tofile("banner-hdr.raw")
Image.fromarray((full * 255).round().astype(np.uint8)).save("banner-base.png")
print(w, h, "max", hdr.max(), "share above white", (hdr.max(axis=2) > 1).mean())
