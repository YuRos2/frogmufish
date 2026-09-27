"""Measure the frog from the reference photos so the model can be rebuilt from
numbers instead of eyeballing.

  blender --background --factory-startup --python tools/analyze_refs.py

Everything is reported as a fraction of the green silhouette's bounding box:
  u = (x - box_left) / box_width        (0 = left of the frog, 1 = right)
  v = (y - box_top) / box_height        (0 = top of the frog, 1 = bottom)
so the numbers are independent of how big the toy was in the frame.

The same text is written to tools/refs_report.txt, and the tool also writes
tools/crops/a_*.png overlays: the detected mask painted over the photo with a
10% grid on the silhouette box, so every number can be checked by eye.
"""

import os
import sys

import bpy
import numpy as np

PROJECT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PICTURES = os.environ.get("MOKUGYO_PICTURES",
                         os.path.join(PROJECT, "reference_photos"))
OUT = os.path.join(PROJECT, "tools", "crops")

ROT_K = -1          # stored landscape, displayed 90 degrees clockwise


# ---------------------------------------------------------------------------
# loading / saving
# ---------------------------------------------------------------------------

def load_upright(src, longest=1100):
    img = bpy.data.images.load(os.path.join(PICTURES, src))
    w, h = img.size
    if max(w, h) > longest:
        s = longest / max(w, h)
        img.scale(max(1, int(w * s)), max(1, int(h * s)))
        w, h = img.size
    buf = np.empty(w * h * 4, dtype=np.float32)
    img.pixels.foreach_get(buf)
    px = buf.reshape(h, w, 4)[::-1]
    if ROT_K:
        px = np.rot90(px, k=ROT_K)
    bpy.data.images.remove(img)
    return np.ascontiguousarray(px)


def save(label, px):
    px = np.clip(px, 0.0, 1.0)
    out = bpy.data.images.new(label, width=px.shape[1], height=px.shape[0],
                              alpha=False)
    out.pixels = px[::-1].ravel().tolist()
    out.filepath_raw = os.path.join(OUT, label + ".png")
    out.file_format = "PNG"
    out.save()
    bpy.data.images.remove(out)
    print("  wrote tools/crops/%s.png (%dx%d)" % (label, px.shape[1], px.shape[0]))


# ---------------------------------------------------------------------------
# segmentation
# ---------------------------------------------------------------------------

def masks(px):
    """Green / black / pink masks.

    Blender hands back the JPEG's sRGB-encoded values here (not linear), so the
    thresholds are the ones you would read off the picture directly.
    """
    r, g, b = px[..., 0], px[..., 1], px[..., 2]
    lum = 0.2126 * r + 0.7152 * g + 0.0722 * b
    green = (g > r * 1.05) & (g > b * 1.25) & (g > 0.15)
    black = lum < 0.30
    pink = (r > g * 1.06) & (r > b * 1.05) & (r > 0.45) & (g > 0.35)
    return green, black, pink


def bbox(mask):
    ys, xs = np.nonzero(mask)
    return xs.min(), ys.min(), xs.max(), ys.max()


def overlay(px, green, black, pink, label):
    """Paint the masks over the photo and draw a 10% grid on the green box."""
    out = px.copy()
    x0, y0, x1, y1 = bbox(green)
    box = np.zeros_like(green)
    box[y0:y1 + 1, x0:x1 + 1] = True
    out[green & ~box] *= 0.35
    out[green & ~box, 1] += 0.45
    out[green & ~box, 0] *= 0.4
    out[black] = np.array([0.0, 0.0, 1.0, 1.0])          # blue = detected black
    out[pink & green] = np.array([1.0, 0.0, 1.0, 1.0])   # magenta = detected pink
    w, h = (x1 - x0), (y1 - y0)
    for i in range(11):
        gx = int(x0 + w * i / 10)
        gy = int(y0 + h * i / 10)
        out[y0:y1 + 1, max(0, gx - 1):gx + 2] = np.array([1.0, 0.0, 0.0, 1.0])
        out[max(0, gy - 1):gy + 2, x0:x1 + 1] = np.array([1.0, 0.0, 0.0, 1.0])
    save(label, out)
    return x0, y0, x1, y1


# ---------------------------------------------------------------------------
# reports
# ---------------------------------------------------------------------------

def frac(u, v, x0, y0, w, h):
    return "(u=%.3f v=%.3f)" % ((u - x0) / w, (v - y0) / h)


def report_slot(px, green, black, x0, y0, x1, y1):
    """The mouth slot: the dark seam that crosses the lower part of the frog."""
    w, h = float(x1 - x0), float(y1 - y0)
    band = np.zeros_like(black)
    band[int(y0 + h * 0.60):int(y0 + h * 0.98), x0:x1 + 1] = True
    slot = black & band
    print("  mouth slot rows (dark fraction of the row, inside the green box):")
    for i in range(12):
        v = 0.60 + 0.38 * i / 11
        yy = int(y0 + h * v)
        row = slot[yy, x0:x1 + 1]
        if not row.any():
            print("    v=%.3f  -" % v)
            continue
        cols = np.nonzero(row)[0]
        print("    v=%.3f  u %.3f..%.3f  fill %.2f  centre u %.3f" % (
            v, cols.min() / w, cols.max() / w, row.mean(),
            (cols.min() + cols.max()) / (2 * w)))


def report_glint(px, black, x0, y0, x1, y1):
    """The white highlight inside each pupil."""
    r, g, b = px[..., 0], px[..., 1], px[..., 2]
    lum = 0.2126 * r + 0.7152 * g + 0.0722 * b
    white = (lum > 0.75) & (abs(r - g) < 0.06) & (abs(g - b) < 0.06)
    # only inside the black blobs (the pupils)
    w, h = float(x1 - x0), float(y1 - y0)
    for bx0, by0, bx1, by1 in blobs(black, min_px=150):
        if (by1 - by0) / h < 0.04 or bx1 < x0 or bx0 > x1:
            continue
        sub = np.zeros_like(white)
        sub[by0:by1 + 1, bx0:bx1 + 1] = True
        for gx0, gy0, gx1, gy1 in blobs(white & sub, min_px=2):
            print("    pupil u %.3f..%.3f v %.3f..%.3f -> glint at u %.3f v %.3f, d %.3f" % (
                (bx0 - x0) / w, (bx1 - x0) / w, (by0 - y0) / h, (by1 - y0) / h,
                (gx0 + gx1 - 2 * x0) / (2 * w), (gy0 + gy1 - 2 * y0) / (2 * h),
                (gx1 - gx0) / w))


def report_front(name):
    print("\n=== FRONT VIEW: %s ===" % name)
    px = load_upright(name)
    green, black, pink = masks(px)
    x0, y0, x1, y1 = overlay(px, green, black, pink, "a_front_" + name.split(".")[0])
    w, h = float(x1 - x0), float(y1 - y0)
    # Ignore anything outside the frog's own box: the dark cardboard behind it
    # would otherwise show up as a "feature".
    inside = np.zeros_like(black)
    inside[y0:y1 + 1, x0:x1 + 1] = True
    black = black & inside
    pink = pink & inside
    print("  green box: x %d..%d  y %d..%d   aspect h/w = %.3f" % (x0, x1, y0, y1, h / w))

    # --- silhouette half-width every 5% of the height
    print("  silhouette width (u, half-width as a fraction of box width):")
    for i in range(21):
        yy = int(y0 + h * i / 20)
        row = np.nonzero(green[yy, x0:x1 + 1])[0]
        if row.size == 0:
            print("    v=%.2f  -" % (i / 20.0))
            continue
        lo, hi = row.min() + x0, row.max() + x0
        print("    v=%.2f  u %.3f .. %.3f   width %.3f  centre u %.3f" % (
            i / 20.0, (lo - x0) / w, (hi - x0) / w, (hi - lo) / w,
            (lo + hi - 2 * x0) / (2 * w)))

    # --- eye bumps: the top 20% of the green box, split left / right
    print("  eye bump rows (top of silhouette):")
    for i in range(9):
        yy = int(y0 + h * i / 20)
        row = np.nonzero(green[yy, x0:x1 + 1])[0]
        if row.size == 0:
            continue
        gaps = np.nonzero(np.diff(row) > 3)[0]
        segs = np.split(row, gaps + 1)
        print("    v=%.3f  %d segment(s): %s" % (
            i / 20.0, len(segs),
            " ".join("%.3f-%.3f" % (s.min() / w, s.max() / w) for s in segs)))

    # --- black features
    print("  black features (connected blobs, u/v of the green box):")
    for blob in blobs(black, min_px=60):
        bx0, by0, bx1, by1 = blob
        print("    u %.3f..%.3f  v %.3f..%.3f   w %.3f h %.3f  centre u %.3f v %.3f" % (
            (bx0 - x0) / w, (bx1 - x0) / w, (by0 - y0) / h, (by1 - y0) / h,
            (bx1 - bx0) / w, (by1 - by0) / h,
            (bx0 + bx1 - 2 * x0) / (2 * w), (by0 + by1 - 2 * y0) / (2 * h)))

    # --- the nose line: black blobs that sit in the middle third, above 45%
    print("  nose line trace (centre of the black run in each column):")
    nose = np.zeros_like(black)
    nose[:, x0 + int(w * 0.30):x0 + int(w * 0.70)] = True
    nose[int(y0 + h * 0.50):, :] = False
    nose[:int(y0 + h * 0.14), :] = False
    cols = np.nonzero((black & nose).any(axis=0))[0]
    if cols.size:
        print("    spans u %.3f..%.3f" % ((cols.min() - x0) / w, (cols.max() - x0) / w))
        for k in range(13):
            cx = int(cols.min() + (cols.max() - cols.min()) * k / 12)
            col = np.nonzero((black & nose)[:, cx])[0]
            if col.size:
                print("      u %.3f  v %.3f  (thickness %.3f)" % (
                    (cx - x0) / w, (col.mean() - y0) / h, col.size / h))

    # --- cheeks
    print("  pink cheeks:")
    for blob in blobs(pink, min_px=200):
        bx0, by0, bx1, by1 = blob
        print("    u %.3f..%.3f  v %.3f..%.3f   w %.3f h %.3f  centre u %.3f v %.3f" % (
            (bx0 - x0) / w, (bx1 - x0) / w, (by0 - y0) / h, (by1 - y0) / h,
            (bx1 - bx0) / w, (by1 - by0) / h,
            (bx0 + bx1 - 2 * x0) / (2 * w), (by0 + by1 - 2 * y0) / (2 * h)))

    report_slot(px, green, black, x0, y0, x1, y1)
    print("  pupil glints:")
    report_glint(px, black, x0, y0, x1, y1)
    return x0, y0, x1, y1


def blobs(mask, min_px=50, max_blobs=12):
    """Cheap flood fill over a boolean mask; returns (x0, y0, x1, y1) boxes."""
    m = mask.copy()
    h, w = m.shape
    out = []
    for _ in range(max_blobs):
        ys, xs = np.nonzero(m)
        if ys.size < min_px:
            break
        seed = (ys[0], xs[0])
        stack = [seed]
        m[seed] = False
        bx0 = bx1 = seed[1]
        by0 = by1 = seed[0]
        n = 0
        while stack:
            y, x = stack.pop()
            n += 1
            bx0, bx1 = min(bx0, x), max(bx1, x)
            by0, by1 = min(by0, y), max(by1, y)
            for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                ny, nx = y + dy, x + dx
                if 0 <= ny < h and 0 <= nx < w and m[ny, nx]:
                    m[ny, nx] = False
                    stack.append((ny, nx))
        if n >= min_px:
            out.append((bx0, by0, bx1, by1))
    out.sort(key=lambda b: (b[1], b[0]))
    return out


def report_side(name):
    print("\n=== SIDE VIEW: %s ===" % name)
    px = load_upright(name)
    green, black, pink = masks(px)
    x0, y0, x1, y1 = overlay(px, green, black, pink, "a_side_" + name.split(".")[0])
    w, h = float(x1 - x0), float(y1 - y0)
    print("  green box: x %d..%d  y %d..%d   aspect h/w = %.3f" % (x0, x1, y0, y1, h / w))
    print("  silhouette width per 5%% of height:")
    for i in range(21):
        yy = int(y0 + h * i / 20)
        row = np.nonzero(green[yy, x0:x1 + 1])[0]
        if row.size == 0:
            print("    v=%.2f  -" % (i / 20.0))
            continue
        lo, hi = row.min() + x0, row.max() + x0
        print("    v=%.2f  u %.3f .. %.3f   depth %.3f  centre u %.3f" % (
            i / 20.0, (lo - x0) / w, (hi - x0) / w, (hi - lo) / w,
            (lo + hi - 2 * x0) / (2 * w)))
    print("  black features:")
    for blob in blobs(black, min_px=60):
        bx0, by0, bx1, by1 = blob
        print("    u %.3f..%.3f  v %.3f..%.3f" % (
            (bx0 - x0) / w, (bx1 - x0) / w, (by0 - y0) / h, (by1 - y0) / h))


class _Tee:
    """Prints to stdout and to the report file at once, so simply running the
    tool is what refreshes tools/refs_report.txt."""

    def __init__(self, path, stream):
        self.file = open(path, "w", encoding="utf-8")
        self.stream = stream

    def write(self, text):
        self.stream.write(text)
        self.file.write(text)

    def flush(self):
        self.stream.flush()
        self.file.flush()


if __name__ == "__main__":
    report = os.path.join(PROJECT, "tools", "refs_report.txt")
    real_stdout = sys.stdout
    tee = _Tee(report, real_stdout)
    sys.stdout = tee
    try:
        report_front("frog00.jpg")
        report_front("frog13.jpg")
        report_side("frog12.jpg")
        report_side("frog14.jpg")
        print("\nWROTE", report)
    finally:
        sys.stdout = real_stdout
        tee.file.close()
