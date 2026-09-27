"""Crop and magnify regions of the reference photos so the face detail is legible.

The JPEGs are stored landscape and rely on an EXIF orientation tag that Blender
ignores, so the pixels are rotated upright first.

Run with:
  blender --background --factory-startup --python tools/crop_refs.py
"""

import os

import bpy
import numpy as np

PROJECT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PICTURES = os.environ.get("MOKUGYO_PICTURES",
                         os.path.join(PROJECT, "reference_photos"))
OUT = os.path.join(PROJECT, "tools", "crops")

# Stored pixels are 4032x3024 and display as 3024x4032, i.e. 90 degrees CW.
ROT_K = -1

# (source file, label, left, top, right, bottom, zoom) as fractions of the
# upright image, with (0, 0) at the top-left corner.
CROPS = [
    ("frog00.jpg", "f00_full", 0.00, 0.00, 1.00, 1.00, 1),
    ("frog00.jpg", "f00_face", 0.20, 0.13, 0.85, 0.40, 2),
    ("frog00.jpg", "f00_nose", 0.40, 0.26, 0.68, 0.37, 4),
    ("frog00.jpg", "f00_nose2", 0.44, 0.285, 0.63, 0.345, 6),
    ("FrogGhanta00.jpg", "fg00_face", 0.20, 0.22, 0.85, 0.46, 2),
    ("FrogGhanta00.jpg", "fg00_nose", 0.25, 0.26, 0.72, 0.40, 3),
    ("frog08.jpg", "f08_full", 0.00, 0.00, 1.00, 1.00, 1),
    ("frog12.jpg", "f12_full", 0.00, 0.00, 1.00, 1.00, 1),
    ("frog16.jpg", "f16_full", 0.00, 0.00, 1.00, 1.00, 1),
    ("frog04.jpg", "f04_full", 0.00, 0.00, 1.00, 1.00, 1),
    ("frog02.jpg", "f02_full", 0.00, 0.00, 1.00, 1.00, 1),
    ("frog10.jpg", "f10_full", 0.00, 0.00, 1.00, 1.00, 1),
]


def load_upright(src):
    img = bpy.data.images.load(os.path.join(PICTURES, src))
    w, h = img.size
    px = np.array(img.pixels[:], dtype=np.float32).reshape(h, w, 4)
    px = px[::-1]                      # Blender stores bottom-up
    if ROT_K:
        px = np.rot90(px, k=ROT_K)
    bpy.data.images.remove(img)
    return px


def save(label, px):
    out = bpy.data.images.new(label, width=px.shape[1], height=px.shape[0],
                              alpha=True)
    out.pixels = px[::-1].ravel().tolist()
    out.filepath_raw = os.path.join(OUT, label + ".png")
    out.file_format = "PNG"
    out.save()
    bpy.data.images.remove(out)
    print("CROPPED %-12s %dx%d" % (label, px.shape[1], px.shape[0]))


os.makedirs(OUT, exist_ok=True)
for src, label, l, t, r, b, zoom in CROPS:
    try:
        px = load_upright(src)
        h, w = px.shape[:2]
        sub = px[int(t * h):int(b * h), int(l * w):int(r * w)]
        if zoom != 1:
            sub = np.repeat(np.repeat(sub, zoom, axis=0), zoom, axis=1)
        # keep the previews a sane size
        if sub.shape[1] > 2400:
            step = int(np.ceil(sub.shape[1] / 2400))
            sub = sub[::step, ::step]
        save(label, sub)
    except Exception as exc:  # noqa: BLE001
        print("FAILED", label, exc)
