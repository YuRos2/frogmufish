"""Scratch: high magnification crops of the frog's nose / mouth from the refs.

  blender --background --factory-startup --python tools/_zoom.py

Fractions are of the upright image (see crop_refs.py); 0,0 is top-left.
"""

import os
import bpy
import numpy as np

PROJECT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PICTURES = os.environ.get("MOKUGYO_PICTURES",
                         os.path.join(PROJECT, "reference_photos"))
OUT = os.path.join(PROJECT, "tools", "crops")
ROT_K = -1


def load_upright(src):
    img = bpy.data.images.load(os.path.join(PICTURES, src))
    w, h = img.size
    px = np.array(img.pixels[:], dtype=np.float32).reshape(h, w, 4)
    px = px[::-1]
    if ROT_K:
        px = np.rot90(px, k=ROT_K)
    bpy.data.images.remove(img)
    return px


def save(label, px):
    out = bpy.data.images.new(label, width=px.shape[1], height=px.shape[0], alpha=False)
    out.pixels = px[::-1].ravel().tolist()
    out.filepath_raw = os.path.join(OUT, label + ".png")
    out.file_format = "PNG"
    out.save()
    bpy.data.images.remove(out)
    print("ZOOM", label, px.shape[1], px.shape[0])


JOBS = [
    ("frog00.jpg", "z_nose", 0.34, 0.28, 0.68, 0.38, 8),
    ("frog00.jpg", "z_seam", 0.10, 0.46, 0.95, 0.68, 3),
    ("frog04.jpg", "z_nose2", 0.34, 0.28, 0.68, 0.38, 8),
    ("frog04.jpg", "z_seam2", 0.10, 0.46, 0.95, 0.68, 3),
    ("frog10.jpg", "z_side", 0.05, 0.10, 1.00, 1.00, 1),
]

for src, label, l, t, r, b, zoom in JOBS:
    px = load_upright(src)
    h, w = px.shape[:2]
    sub = px[int(t * h):int(b * h), int(l * w):int(r * w)].copy()
    if zoom != 1:
        sub = np.repeat(np.repeat(sub, zoom, axis=0), zoom, axis=1)
    if sub.shape[1] > 2200:
        step = int(np.ceil(sub.shape[1] / 2200))
        sub = sub[::step, ::step]
    save(label, sub)
