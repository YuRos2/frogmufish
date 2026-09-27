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

for src, label in [("FrogGhanta00.jpg","zg00"), ("FrogGhanta02.jpg","zg02"), ("ghanta04.jpg","zg04"), ("ghanta00.jpg","zh00")]:
    px = load_upright(src)
    h, w = px.shape[:2]
    step = max(1, int(np.ceil(w/1000.0)))
    save(label, px[::step, ::step])
