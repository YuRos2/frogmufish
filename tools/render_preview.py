"""Render preview images of the built frog + mallet for visual verification."""

import math
import os
import sys

import bpy
from mathutils import Vector

PROJECT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(PROJECT, "tools", "preview")


def look_at(obj, target):
    d = Vector(target) - obj.location
    obj.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()


def main():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)

    bpy.ops.import_scene.gltf(
        filepath=os.path.join(PROJECT, "assets", "models", "frog_mokugyo.glb")
    )
    bpy.ops.import_scene.gltf(
        filepath=os.path.join(PROJECT, "assets", "models", "mallet.glb")
    )

    # glTF import is Y-up -> Blender Z-up, so objects land rotated; the frog's
    # face ends up pointing +Y here. Put the mallet back through the mouth slot.
    frog = [o for o in bpy.data.objects if o.name.startswith("FrogMokugyo")][0]
    mallet = [o for o in bpy.data.objects if o.name.startswith("Mallet")][0]

    # The frog is now 135.5 mm tall; the mouth slot's floor sits at 31.6 mm.
    slot_z = (0.0268 + 0.0054) * 1.18
    mallet.rotation_euler = (0.0, 0.0, 0.0)
    mallet.location = (-0.082, 0.0, slot_z)

    print("FROG_BOUNDS", [tuple(round(c, 4) for c in v) for v in frog.bound_box][:2])
    print("FROG_DIM", tuple(round(d, 4) for d in frog.dimensions))
    print("MALLET_DIM", tuple(round(d, 4) for d in mallet.dimensions))

    # ground
    bpy.ops.mesh.primitive_plane_add(size=2.0, location=(0, 0, 0))
    ground = bpy.context.active_object
    m = bpy.data.materials.new("Ground")
    m.use_nodes = True
    m.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (
        0.86, 0.80, 0.68, 1.0)
    m.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.85
    ground.data.materials.append(m)

    world = bpy.context.scene.world
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = (0.55, 0.66, 0.78, 1)
    world.node_tree.nodes["Background"].inputs[1].default_value = 0.9

    scn0 = bpy.context.scene
    scn0.view_settings.view_transform = "Standard"
    scn0.view_settings.look = "None"

    key = bpy.data.lights.new("Key", "AREA")
    key.energy = 5.0
    key.size = 0.5
    ko = bpy.data.objects.new("Key", key)
    bpy.context.collection.objects.link(ko)
    ko.location = (0.20, -0.24, 0.34)
    look_at(ko, (0, 0, 0.066))

    fill = bpy.data.lights.new("Fill", "AREA")
    fill.energy = 2.0
    fill.size = 0.8
    fo = bpy.data.objects.new("Fill", fill)
    bpy.context.collection.objects.link(fo)
    fo.location = (-0.30, -0.18, 0.20)
    look_at(fo, (0, 0, 0.066))

    cam_data = bpy.data.cameras.new("Cam")
    cam_data.lens = 60
    cam = bpy.data.objects.new("Cam", cam_data)
    bpy.context.collection.objects.link(cam)
    bpy.context.scene.camera = cam

    scn = bpy.context.scene
    scn.render.engine = "BLENDER_EEVEE_NEXT"
    scn.render.resolution_x = 640
    scn.render.resolution_y = 800
    scn.render.film_transparent = False

    os.makedirs(OUT, exist_ok=True)

    views = {
        "front": (0.0, -0.40, 0.15),
        "side": (0.34, -0.16, 0.14),
        "top": (0.07, -0.20, 0.34),
    }
    for name, pos in views.items():
        cam.location = pos
        look_at(cam, (0, 0, 0.066))
        scn.render.filepath = os.path.join(OUT, name + ".png")
        bpy.ops.render.render(write_still=True)
        print("RENDERED", scn.render.filepath)


main()
