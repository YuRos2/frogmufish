"""Measure key proportions from the reference photos (scratch tool).

  blender --background --factory-startup --python tools/_measure.py

Prints normalised geometry (fractions of the frog's overall width/height) so the
Blender builder can be tuned against real numbers instead of eyeballing.
"""

import os
import bpy
import numpy as np

PROJECT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PICTURES = os.environ.get("MOKUGYO_PICTURES",
                         os.path.join(PROJECT, "reference_photos"))


def load_upright(src):
    img = bpy.data.images.load(os.path.join(PICTURES, src))
    w, h = img.size
    px = np.array(img.pixels[:], dtype=np.float32).reshape(h, w, 4)
    px = px[::-1]
    px = np.rot90(px, k=-1)
    bpy.data.images.remove(img)
    return px


def masks(px):
    r, g, b = px[..., 0], px[..., 1], px[..., 2]
    green = (g > r * 1.05) & (g > b * 1.25) & (g > 0.02)
    dark = (r < 0.05) & (g < 0.05) & (b < 0.05)
    pink = (r > g * 1.12) & (r > b * 1.08) & (r > 0.15) & (g > 0.08)
    return green, dark, pink


def bbox(mask):
    ys, xs = np.nonzero(mask)
    if len(xs) == 0:
        return None
    return xs.min(), ys.min(), xs.max(), ys.max()


def centroid(mask):
    ys, xs = np.nonzero(mask)
    if len(xs) == 0:
        return None
    return float(xs.mean()), float(ys.mean())


def label_largest(mask, keep=4, min_area=400):
    """Cheap connected components via iterative scanline flooding."""
    h, w = mask.shape
    seen = np.zeros_like(mask, dtype=bool)
    out = []
    idx = np.argwhere(mask)
    for y0, x0 in idx[::97]:
        if seen[y0, x0]:
            continue
        stack = [(y0, x0)]
        seen[y0, x0] = True
        pts = []
        while stack:
            y, x = stack.pop()
            pts.append((y, x))
            for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                ny, nx = y + dy, x + dx
                if 0 <= ny < h and 0 <= nx < w and mask[ny, nx] and not seen[ny, nx]:
                    seen[ny, nx] = True
                    stack.append((ny, nx))
        if len(pts) >= min_area:
            arr = np.array(pts)
            out.append((len(pts), arr[:, 1].min(), arr[:, 1].max(),
                        arr[:, 0].min(), arr[:, 0].max()))
    out.sort(reverse=True)
    return out[:keep]


def report(name, src):
    px = load_upright(src)
    green, dark, pink = masks(px)
    gb = bbox(green)
    print("\n=== %s (%dx%d) ===" % (name, px.shape[1], px.shape[0]))
    print("green bbox x[%d..%d] y[%d..%d]  w=%d h=%d  aspect h/w=%.3f" % (
        gb[0], gb[2], gb[1], gb[3], gb[2] - gb[0], gb[3] - gb[1],
        (gb[3] - gb[1]) / max(1, gb[2] - gb[0])))
    W = gb[2] - gb[0]
    H = gb[3] - gb[1]
    # figure out orientation: for frog00 the head is at the top
    for sign in (+1, -1):
        pass
    print("downsampled silhouette widths (fraction of W) top->bottom:")
    for i in range(21):
        y = int(gb[1] + (H - 1) * i / 20)
        row = np.nonzero(green[y, :])[0]
        if len(row) == 0:
            print("   %.2f  -" % (i / 20.0))
            continue
        print("   %.2f  x %+.3f..%+.3f  width %.3f" % (
            i / 20.0,
            (row.min() - (gb[0] + W / 2)) / W,
            (row.max() - (gb[0] + W / 2)) / W,
            (row.max() - row.min()) / W))
    print("pupil blobs (area, x0,x1, y0,y1) normalised:")
    for area, x0, x1, y0, y1 in label_largest(dark & green[..., None][..., 0] if False else dark):
        print("   area %7d  x %+.3f..%+.3f  y %.3f..%.3f  w %.3f h %.3f  cx %+.3f cy %.3f" % (
            area, (x0 - (gb[0] + W / 2)) / W, (x1 - (gb[0] + W / 2)) / W,
            (y0 - gb[1]) / H, (y1 - gb[1]) / H,
            (x1 - x0) / W, (y1 - y0) / H,
            ((x0 + x1) / 2 - (gb[0] + W / 2)) / W, ((y0 + y1) / 2 - gb[1]) / H))
    print("pink blobs:")
    for area, x0, x1, y0, y1 in label_largest(pink, min_area=800):
        print("   area %7d  x %+.3f..%+.3f  y %.3f..%.3f  w %.3f h %.3f  cx %+.3f cy %.3f" % (
            area, (x0 - (gb[0] + W / 2)) / W, (x1 - (gb[0] + W / 2)) / W,
            (y0 - gb[1]) / H, (y1 - gb[1]) / H,
            (x1 - x0) / W, (y1 - y0) / H,
            ((x0 + x1) / 2 - (gb[0] + W / 2)) / W, ((y0 + y1) / 2 - gb[1]) / H))


def mallet(src):
    px = load_upright(src)
    r, g, b = px[..., 0], px[..., 1], px[..., 2]
    wooden = (r > g * 1.15) & (r > b * 1.6) & (r > 0.10)
    print("\n=== mallet %s ===" % src)
    print("wood bbox:", bbox(wooden))
    for area, x0, x1, y0, y1 in label_largest(wooden, min_area=2000, keep=3):
        print("   wood area %d x %d..%d y %d..%d  len %d  thickness %d" % (
            area, x0, x1, y0, y1, x1 - x0, y1 - y0))


report("front frog00", "frog00.jpg")
report("side frog12", "frog12.jpg")
report("three-quarter FrogGhanta00", "FrogGhanta00.jpg")
mallet("ghanta00.jpg")
