# Cuts the gradient sphere out of Resources/Billy-sphere-artwork.png (a disc on white)
# into Resources/Billy-sphere.png: a square with a clean, anti-aliased circular edge.
# Needs Pillow and NumPy: python3 scripts/cut-sphere.py
import numpy as np
from PIL import Image

INSET = 2.5  # pulls the edge in so none of the white surround survives
SCALE = 4    # works at this multiple of the artwork for a smooth edge

img = Image.open("Resources/Billy-sphere-artwork.png").convert("RGB")
a = np.asarray(img).astype(np.float32)
ink = (255 - a.min(axis=2)) > 40  # anything clearly not white
ys, xs = np.nonzero(ink)
cx, cy = (xs.min() + xs.max() + 1) / 2, (ys.min() + ys.max() + 1) / 2
r = min(xs.max() + 1 - xs.min(), ys.max() + 1 - ys.min()) / 2 - INSET
print(f"centre ({cx:.1f}, {cy:.1f}), radius {r:.1f}")

side = int(np.ceil(r)) * 2
box = (int(round(cx)) - side // 2, int(round(cy)) - side // 2)
big = side * SCALE
crop = img.crop((box[0], box[1], box[0] + side, box[1] + side)).resize((big, big), Image.LANCZOS)
yy, xx = np.mgrid[0:big, 0:big]
ox, oy = (cx - box[0]) * SCALE, (cy - box[1]) * SCALE
d = np.hypot(xx + 0.5 - ox, yy + 0.5 - oy) - r * SCALE
alpha = np.clip(0.5 - d / SCALE, 0, 1)  # one artwork pixel of anti-aliasing
out = np.dstack([np.asarray(crop).astype(np.float32), alpha * 255])
Image.fromarray(out.round().astype(np.uint8)).save("Resources/Billy-sphere.png")
print("Wrote Resources/Billy-sphere.png")
