"""Overlay a measurement grid on tight crops of the references (scratch tool).

  blender --background --factory-startup --python tools/_grid.py

Writes tools/crops/g_*.png with horizontal lines every 5% and vertical lines
every 10% of the green silhouette bounding box.
"""

import os
import bpy
import numpy as np

PROJECT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PICTURES = os.environ.get("MOKUGYO_PICTURES",
                         os.path.join(PROJECT, "reference_photos"))
OUT = os.path.join(PROJECT, "tools", "crops")


def load_upright(src):
    img = bpy.data.images.load(os.path.join(PICTURES, src))
    w, h = img.size
    px = np.array(img.pixels[:], dtype=np.float32).reshape(h, w, 4)
    px = px[::-1]
    px = np.rot90(px, k=-1)
    bpy.data.images.remove(img)
    return px


def save(label, px):
    out = bpy.data.images.new(label, width=px.shape[1], height=px.shape[0], alpha=False)
    out.pixels = px[::-1].ravel().tolist()
    out.filepath_raw = os.path.join(OUT, label + ".png")
    out.file_format = "PNG"
    out.save()
    bpy.data.images.remove(out)
    print("GRID", label, px.shape[1], px.shape[0])


def green_bbox(px, pad=0.02):
    r, g, b = px[..., 0], px[..., 1], px[..., 2]
    green = (g > r * 1.05) & (g > b * 1.25) & (g > 0.02)
    ys, xs = np.nonzero(green)
    x0, x1, y0, y1 = xs.min(), xs.max(), ys.min(), ys.max()
    w = x1 - x0
    h = y1 - y0
    return (max(0, int(x0 - w * pad)), max(0, int(y0 - h * pad)),
            min(px.shape[1], int(x1 + w * pad)), min(px.shape[0], int(y1 + h * pad)))


def annotate(src, label, zoom=1):
    px = load_upright(src)
    x0, y0, x1, y1 = green_bbox(px)
    sub = px[y0:y1, x0:x1].copy()
    H, W = sub.shape[:2]
    # green silhouette inside the crop, for the exact reference box
    r, g, b = sub[..., 0], sub[..., 1], sub[..., 2]
    green = (g > r * 1.05) & (g > b * 1.25) & (g > 0.02)
    ys, xs = np.nonzero(green)
    gx0, gx1, gy0, gy1 = xs.min(), xs.max(), ys.min(), ys.max()
    gw, gh = gx1 - gx0, gy1 - gy0
    ink = np.array([1.0, 0.0, 0.0])
    for i in range(0, 21):
        y = int(gy0 + gh * i / 20)
        sub[max(0, y - 1):y + 2, gx0:gx1, :3] = ink
    for j in range(0, 11):
        x = int(gx0 + gw * j / 10)
        sub[gy0:gy1, max(0, x - 1):x + 2, :3] = ink
    if zoom > 1:
        sub = np.repeat(np.repeat(sub, zoom, axis=0), zoom, axis=1)
    if sub.shape[1] > 2000:
        step = int(np.ceil(sub.shape[1] / 2000))
        sub = sub[::step, ::step]
    save(label, sub)
    print("   green box w=%d h=%d  aspect h/w=%.3f  (grid: 5%% x 10%%)" % (
        gw, gh, gh / gw))


for src, label in [("frog00.jpg", "g_front"), ("frog12.jpg", "g_side"),
                   ("FrogGhanta00.jpg", "g_tq"), ("frog08.jpg", "g_back"),
                   ("frog02.jpg", "g_under"), ("frog16.jpg", "g_under2")]:
    annotate(src, label)
