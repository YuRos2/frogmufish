"""Put the built model next to the reference photo, lined up on the silhouette.

  blender --background --factory-startup --python tools/compare_front.py

Renders the frog orthographically from the front with a transparent film, then
scales the reference photo's green silhouette and the render's alpha silhouette
to the same width and the same top edge. The output is a single strip:

  left   the reference photo (frog00.jpg), cropped to its green silhouette
  middle the render, cropped to its alpha silhouette
  right  the two overlaid, reference in red and model in green

Because both crops are normalised on the silhouette rather than on pixels, the
strip shows real proportion errors: the reference's bottom edge sits inside the
wooden base, so everything below it on the model is the part the photo hides.
"""

import os

import bpy
import numpy as np
from mathutils import Vector

PROJECT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PICTURES = os.environ.get("MOKUGYO_PICTURES",
                         os.path.join(PROJECT, "reference_photos"))
OUT = os.path.join(PROJECT, "tools", "preview")
CROPS = os.path.join(PROJECT, "tools", "crops")

REF = "frog00.jpg"
ROT_K = -1
STRIP_H = 900


# ---------------------------------------------------------------------------
# render the model
# ---------------------------------------------------------------------------

def look_at(obj, target):
    d = Vector(target) - obj.location
    obj.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()


def render_model():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for coll in (bpy.data.meshes, bpy.data.curves, bpy.data.materials,
                 bpy.data.lights, bpy.data.cameras):
        for item in list(coll):
            if item.users == 0:
                coll.remove(item)

    bpy.ops.import_scene.gltf(
        filepath=os.path.join(PROJECT, "assets", "models", "frog_mokugyo.glb"))

    world = bpy.context.scene.world
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = (
        0.62, 0.68, 0.74, 1.0)
    world.node_tree.nodes["Background"].inputs[1].default_value = 1.1

    key = bpy.data.lights.new("Key", "AREA")
    key.energy = 4.0
    key.size = 2.0
    ko = bpy.data.objects.new("Key", key)
    bpy.context.collection.objects.link(ko)
    ko.location = (0.22, -0.60, 0.55)
    look_at(ko, (0, 0, 0.07))

    fill = bpy.data.lights.new("Fill", "AREA")
    fill.energy = 1.2
    fill.size = 1.5
    fo = bpy.data.objects.new("Fill", fill)
    bpy.context.collection.objects.link(fo)
    fo.location = (-0.55, -0.45, 0.20)
    look_at(fo, (0, 0, 0.07))

    cam_data = bpy.data.cameras.new("Cam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = 0.17
    cam = bpy.data.objects.new("Cam", cam_data)
    bpy.context.collection.objects.link(cam)
    bpy.context.scene.camera = cam
    # glTF import leaves the frog facing +Y in Blender, so the camera looks
    # from +Y back towards it. Frame the body, not the origin: the model's
    # vertical centre sits above its base.
    cam.location = (0.0, -0.45, 0.0678)
    look_at(cam, (0.0, 0.0, 0.0678))

    scn = bpy.context.scene
    scn.render.engine = "BLENDER_EEVEE_NEXT"
    scn.render.resolution_x = 700
    scn.render.resolution_y = 1000
    scn.render.film_transparent = True
    scn.view_settings.view_transform = "Standard"
    os.makedirs(OUT, exist_ok=True)
    scn.render.filepath = os.path.join(OUT, "model_front.png")
    bpy.ops.render.render(write_still=True)
    print("RENDERED", scn.render.filepath)


# ---------------------------------------------------------------------------
# image helpers
# ---------------------------------------------------------------------------

def load(path, longest=None):
    img = bpy.data.images.load(path)
    w, h = img.size
    if longest is not None and max(w, h) > longest:
        s = longest / max(w, h)
        img.scale(max(1, int(w * s)), max(1, int(h * s)))
        w, h = img.size
    buf = np.empty(w * h * 4, dtype=np.float32)
    img.pixels.foreach_get(buf)
    px = buf.reshape(h, w, 4)[::-1]
    bpy.data.images.remove(img)
    return np.ascontiguousarray(px)


def save(label, px):
    px = np.clip(px, 0.0, 1.0)
    out = bpy.data.images.new(label, width=px.shape[1], height=px.shape[0],
                              alpha=False)
    out.pixels = px[::-1].ravel().tolist()
    path = os.path.join(OUT, label + ".png")
    out.filepath_raw = path
    out.file_format = "PNG"
    out.save()
    print("WROTE", path, px.shape[1], "x", px.shape[0])
    bpy.data.images.remove(out)


STRIP_W = 520


def fit_width(px, mask, width):
    """Crop both the image and its mask to the mask, then scale so the
    silhouette is `width` pixels across. Both views are lined up on width, not
    on height, because the reference's bottom edge is hidden inside its base."""
    ys, xs = np.nonzero(mask)
    x0, x1, y0, y1 = xs.min(), xs.max(), ys.min(), ys.max()
    sub = px[y0:y1 + 1, x0:x1 + 1]
    sub_mask = mask[y0:y1 + 1, x0:x1 + 1]
    h, w = sub.shape[:2]
    scale = width / w
    nh = max(1, int(round(h * scale)))
    ys2 = (np.arange(nh) / scale).astype(np.int32).clip(0, h - 1)
    xs2 = (np.arange(width) / scale).astype(np.int32).clip(0, w - 1)
    return sub[ys2][:, xs2], sub_mask[ys2][:, xs2]


def pad(img, height, width):
    tile = np.zeros((height, width, 4), dtype=np.float32)
    tile[..., 3] = 1.0
    tile[..., :3] = 0.09
    tile[:img.shape[0]] = img
    return tile


def main():
    render_model()

    ref = load(os.path.join(PICTURES, REF))
    if ROT_K:
        ref = np.rot90(ref, k=ROT_K)
    r, g, b = ref[..., 0], ref[..., 1], ref[..., 2]
    ref_mask = (g > r * 1.05) & (g > b * 1.25) & (g > 0.15)

    model = load(os.path.join(OUT, "model_front.png"))
    model_mask = model[..., 3] > 0.5

    ref_img, ref_m = fit_width(ref, ref_mask, STRIP_W)
    model_img, model_m = fit_width(model, model_mask, STRIP_W)

    height = max(ref_img.shape[0], model_img.shape[0]) + 20
    gapp = 10
    left = pad(ref_img, height, STRIP_W)
    mid = pad(model_img, height, STRIP_W)

    # overlay: reference silhouette red, model silhouette green, overlap yellow
    over = np.zeros((height, STRIP_W, 4), dtype=np.float32)
    over[..., 3] = 1.0
    rm = np.zeros((height, STRIP_W), dtype=bool)
    mm = np.zeros((height, STRIP_W), dtype=bool)
    rm[:ref_m.shape[0]] = ref_m
    mm[:model_m.shape[0]] = model_m
    over[..., 0] = np.where(rm, 1.0, 0.1)
    over[..., 1] = np.where(mm, 1.0, 0.1)
    over[..., 2] = np.where(rm | mm, 0.15, 0.1)
    over[rm & mm] = (1.0, 1.0, 0.2, 1.0)

    gap = np.zeros((height, gapp, 4), dtype=np.float32)
    gap[..., 3] = 1.0
    strip = np.concatenate([left, gap, mid, gap, over], axis=1)
    save("compare_front", strip)

    print("silhouettes normalised to %d px wide" % STRIP_W)
    print("  reference height %d px (bottom edge is inside the base)" %
          int(rm.any(axis=1).sum()))
    print("  model     height %d px  -> %.2f x the reference's visible height" %
          (int(mm.any(axis=1).sum()),
           mm.any(axis=1).sum() / float(rm.any(axis=1).sum())))
    print("  span (widest - leftmost green) per 5%% of the model's height:")
    mh = int(mm.any(axis=1).sum())

    def span(row):
        idx = np.nonzero(row)[0]
        return 0 if idx.size == 0 else int(idx.max() - idx.min() + 1)

    for i in range(21):
        yy = min(height - 1, int(i * mh / 20))
        rw = span(rm[yy])
        mw = span(mm[yy])
        print("    v=%.2f  ref %4d  model %4d  (%+.0f%%)" % (
            i / 20.0, rw, mw, (mw - rw) * 100.0 / max(1, rw)))


main()
