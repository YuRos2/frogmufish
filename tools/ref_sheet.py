"""Contact sheet of every reference photo, so all views can be compared at once.

  blender --background --factory-startup --python tools/ref_sheet.py

Writes tools/crops/ref_sheet.png. The grid is filled left-to-right, top-to-bottom
with the file names printed to stdout, so a cell can be traced back to its photo.
"""

import os

import bpy
import numpy as np

PROJECT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PICTURES = os.environ.get("MOKUGYO_PICTURES",
                         os.path.join(PROJECT, "reference_photos"))
OUT = os.path.join(PROJECT, "tools", "crops")

# The JPEGs store landscape pixels and rely on an EXIF tag Blender ignores.
ROT_K = -1

COLS = 7
CELL_W = 240
CELL_H = 320


def load_upright(src, longest=900):
    img = bpy.data.images.load(os.path.join(PICTURES, src))
    w, h = img.size
    if max(w, h) > longest:
        s = longest / max(w, h)
        img.scale(max(1, int(w * s)), max(1, int(h * s)))
        w, h = img.size
    buf = np.empty(w * h * 4, dtype=np.float32)
    img.pixels.foreach_get(buf)
    px = buf.reshape(h, w, 4)[::-1]     # Blender stores bottom-up
    if ROT_K:
        px = np.rot90(px, k=ROT_K)
    bpy.data.images.remove(img)
    return px


def fit(px, cell_w, cell_h):
    """Nearest-neighbour downscale into a cell_w x cell_h tile."""
    h, w = px.shape[:2]
    scale = min(cell_w / w, cell_h / h)
    nw, nh = max(1, int(w * scale)), max(1, int(h * scale))
    ys = (np.arange(nh) / scale).astype(np.int32).clip(0, h - 1)
    xs = (np.arange(nw) / scale).astype(np.int32).clip(0, w - 1)
    small = px[ys][:, xs]
    tile = np.ones((cell_h, cell_w, 4), dtype=np.float32)
    y0 = (cell_h - nh) // 2
    x0 = (cell_w - nw) // 2
    tile[y0:y0 + nh, x0:x0 + nw] = small
    return tile


names = sorted(f for f in os.listdir(PICTURES)
               if f.lower().endswith((".jpg", ".png")))
rows = (len(names) + COLS - 1) // COLS
sheet = np.ones((rows * CELL_H, COLS * CELL_W, 4), dtype=np.float32)

for i, name in enumerate(names):
    px = load_upright(name)
    tile = fit(px, CELL_W, CELL_H)
    # a dark bar at the top of the cell so the cells read as a grid
    tile[:3, :, :3] = 0.0
    r, c = divmod(i, COLS)
    sheet[r * CELL_H:(r + 1) * CELL_H, c * CELL_W:(c + 1) * CELL_W] = tile
    print("cell %2d row %d col %d : %s" % (i, r, c, name))

out = bpy.data.images.new("ref_sheet", width=sheet.shape[1],
                          height=sheet.shape[0], alpha=False)
out.pixels = sheet[::-1].ravel().tolist()
out.filepath_raw = os.path.join(OUT, "ref_sheet.png")
out.file_format = "PNG"
out.save()
print("WROTE", out.filepath_raw, sheet.shape[1], "x", sheet.shape[0])
