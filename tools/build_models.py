"""Build the frog mokugyo and its mallet as GLB files for Godot 4.

Run with:
  blender --background --factory-startup --python tools/build_models.py

Conventions
-----------
Blender is Z-up; the frog's face looks down -Y. The glTF exporter converts
Blender (x, y, z) -> Godot (x, z, -y), so in Godot the frog faces +Z and one
Blender metre is one Godot unit.

Where the models come from
--------------------------
The frog is no longer sculpted here. It is the "Lucky frog" mesh in
`SOURCE_BLEND` (override with the `LUCKY_FROG_BLEND` environment variable).
`build_frog` bakes that file into the pose the game wants:

  * the source object transform is applied into the mesh, so the sculpt's own
    rotation/scale stop mattering,
  * the frog is spun 180 degrees about Z, because the sculpt looks down +Y and
    the exporter turns -Y into Godot's +Z,
  * it is centred in x/y, stood on z = 0 and scaled to FROG_HEIGHT,
  * two pupil nodes are added, because the sculpt has bare eye bumps and the
    game's blink works by squashing the pupil nodes flat,
  * the body, pupil and glint materials are assigned.

Everything below the "mallet" heading is still generated from scratch. The
mallet deliberately uses the *same* material as the frog, so the two read as a
matched set rather than a green frog and a cream mallet.

All the numbers are fractions of the frog's own width/height, measured off the
sculpt by ray-casting its front surface - the same convention the reference
photo tools use, so nothing here depends on how big the source file happened to
be.
"""

import math
import os

import bmesh
import bpy
from mathutils import Matrix, Vector

PROJECT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(PROJECT, "assets", "models")

SOURCE_BLEND = os.environ.get(
    "LUCKY_FROG_BLEND", os.path.join(PROJECT, "tools", "Lucky+frog.blend"))

# ---------------------------------------------------------------------------
# frog pose
# ---------------------------------------------------------------------------

# The finished frog stands this tall in metres. Everything the game was tuned
# against - the camera framing, the popup ceiling, the mallet's reach - assumes
# roughly this size, so the sculpt is scaled to it rather than the other way
# round.
FROG_HEIGHT = 0.1355

# The sculpt's face is +Y in its own file. Spinning it half a turn puts the
# face down -Y, which the glTF conversion turns into Godot's +Z.
FACE_TURN = math.pi

# The eye bumps. `u` is the offset from the centreline as a fraction of the
# frog's width and `v` the height above the feet as a fraction of its height,
# read off the sculpt by scanning the front surface for the bulge. The sculpt
# is hand-retopologised, so the two eyes are not quite mirror images and each
# one is measured separately.
EYE_U = (0.2278, -0.2580)
EYE_V = 0.7617

# Pupil: a shallow lens sunk into the eye bump, a little under half the bump's
# width across, so the green bump still rings it the way the real toy's does.
PUPIL_R = 0.072            # radius, as a fraction of the frog's width
PUPIL_FLAT = 0.50          # thickness, relative to the radius
PUPIL_SINK = 0.55          # how far the lens centre sits below the eye apex
GLINT_R = 0.009            # the highlight, as a fraction of the frog's width
GLINT_OFF = (0.30, 0.34)   # up and to the left, in pupil radii

# ---------------------------------------------------------------------------
# mallet
# ---------------------------------------------------------------------------

HANDLE_R = 0.0054
HANDLE_LEN = 0.1900
HEAD_R = 0.0136
HEAD_STRETCH = 1.15

# ---------------------------------------------------------------------------
# material
# ---------------------------------------------------------------------------

# The frog is the ceramic green of the reference toy, and the mallet is the
# exact same material - same base colour, same roughness, same sheen.
S_BODY = (0.561, 0.831, 0.271)
S_PUPIL = (0.137, 0.149, 0.122)
S_GLINT = (0.969, 0.969, 0.961)

BODY_ROUGHNESS = 0.42
BODY_SPECULAR = 0.55


def srgb_to_linear(color):
    def channel(u):
        return u / 12.92 if u <= 0.04045 else ((u + 0.055) / 1.055) ** 2.4

    return tuple(channel(c) for c in color)


C_BODY = srgb_to_linear(S_BODY)
C_PUPIL = srgb_to_linear(S_PUPIL)
C_GLINT = srgb_to_linear(S_GLINT)


# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------

def clear_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for coll in (bpy.data.meshes, bpy.data.curves, bpy.data.materials):
        for item in list(coll):
            if item.users == 0:
                coll.remove(item)


def bounds(ob):
    """World-space (min, max) corners of an object's bounding box.

    Read straight off the vertices rather than `ob.bound_box`: that cache is
    only refreshed by a depsgraph evaluation, so it still reports the pose the
    mesh had before `normalize` baked the transform into it.
    """
    corners = ([ob.matrix_world @ v.co for v in ob.data.vertices]
               if ob.type == "MESH"
               else [ob.matrix_world @ Vector(c) for c in ob.bound_box])
    lo = Vector((min(c.x for c in corners),
                 min(c.y for c in corners),
                 min(c.z for c in corners)))
    hi = Vector((max(c.x for c in corners),
                 max(c.y for c in corners),
                 max(c.z for c in corners)))
    return lo, hi


def make_object(name, verts, faces):
    me = bpy.data.meshes.new(name)
    me.from_pydata([tuple(v) for v in verts], [], [tuple(f) for f in faces])
    me.validate(verbose=False)
    me.update()

    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-6)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me)
    bm.free()
    me.update()

    ob = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(ob)
    return ob


def ellipsoid(radii, center=(0, 0, 0), segments=48, rings=24):
    rx, ry, rz = radii
    verts, faces, rows = [], [], []
    for i in range(rings + 1):
        phi = math.pi * i / rings
        cz, sz = math.cos(phi), math.sin(phi)
        if i == 0 or i == rings:
            rows.append([len(verts)])
            verts.append((center[0], center[1], center[2] + rz * cz))
        else:
            row = []
            for j in range(segments):
                th = 2.0 * math.pi * j / segments
                row.append(len(verts))
                verts.append((
                    center[0] + rx * sz * math.cos(th),
                    center[1] + ry * sz * math.sin(th),
                    center[2] + rz * cz,
                ))
            rows.append(row)

    for i in range(rings):
        a, b = rows[i], rows[i + 1]
        if len(a) == 1:
            for j in range(segments):
                faces.append((a[0], b[(j + 1) % segments], b[j]))
        elif len(b) == 1:
            for j in range(segments):
                faces.append((a[j], a[(j + 1) % segments], b[0]))
        else:
            for j in range(segments):
                k = (j + 1) % segments
                faces.append((a[j], a[k], b[k], b[j]))
    return verts, faces


def cylinder(radius, z0, z1, segments=48, axis="Z"):
    verts, faces = [], []
    for z in (z0, z1):
        for j in range(segments):
            a = 2.0 * math.pi * j / segments
            verts.append((radius * math.cos(a), radius * math.sin(a), z))
    cb0 = len(verts)
    verts.append((0.0, 0.0, z0))
    cb1 = len(verts)
    verts.append((0.0, 0.0, z1))

    for j in range(segments):
        k = (j + 1) % segments
        faces.append((j, k, segments + k, segments + j))
        faces.append((cb0, k, j))
        faces.append((cb1, segments + j, segments + k))

    m = Matrix.Identity(4)
    if axis == "X":
        m = Matrix.Rotation(math.radians(90.0), 4, "Y")
    return [m @ Vector(v) for v in verts], faces


def material(name, color, roughness=0.55, metallic=0.0, specular=0.4):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    if "Specular IOR Level" in bsdf.inputs:
        bsdf.inputs["Specular IOR Level"].default_value = specular
    mat.diffuse_color = (*color, 1.0)
    return mat


def assign(ob, mat):
    ob.data.materials.clear()
    ob.data.materials.append(mat)


def smooth(ob, angle_deg=34.0):
    """Smooth shading with hard edges above `angle_deg`.

    `bpy.ops.object.shade_auto_smooth` needs the "Smooth by Angle" geometry
    node asset, which `--factory-startup` does not load - it reports an error
    and leaves the mesh flat shaded. Tagging the sharp edges directly needs no
    asset and survives both the exporter and the re-import.
    """
    limit = math.radians(angle_deg)
    me = ob.data
    me.polygons.foreach_set("use_smooth", [True] * len(me.polygons))
    bm = bmesh.new()
    bm.from_mesh(me)
    for edge in bm.edges:
        edge.smooth = len(edge.link_faces) == 2 and edge.calc_face_angle() <= limit
    bm.to_mesh(me)
    bm.free()
    me.update()


def export_glb(objects, filename):
    os.makedirs(OUT_DIR, exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    for ob in objects:
        ob.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    path = os.path.join(OUT_DIR, filename)
    bpy.ops.export_scene.gltf(
        filepath=path,
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_yup=True,
        export_materials="EXPORT",
        export_normals=True,
        export_texcoords=False,
        export_animations=False,
    )
    print("EXPORTED", path)


# ---------------------------------------------------------------------------
# frog
# ---------------------------------------------------------------------------

def open_source():
    """Load the sculpt and hand back its one mesh object."""
    if not os.path.exists(SOURCE_BLEND):
        raise SystemExit("missing source sculpt: %s" % SOURCE_BLEND)
    bpy.ops.wm.open_mainfile(filepath=SOURCE_BLEND)
    meshes = [ob for ob in bpy.data.objects if ob.type == "MESH"]
    if len(meshes) != 1:
        raise SystemExit("%s should hold exactly one mesh, found %d"
                         % (SOURCE_BLEND, len(meshes)))
    return meshes[0]


def normalize(ob):
    """Bake the source transform, turn the frog to face -Y, stand it on z = 0.

    Everything after this runs in the frog's final local space, so the eye
    rays below can be cast at plain (x, z) fractions of the bounding box.
    """
    ob.data.transform(ob.matrix_world)
    ob.matrix_world = Matrix.Identity(4)
    ob.data.transform(Matrix.Rotation(FACE_TURN, 4, "Z"))

    lo, hi = bounds(ob)
    scale = FROG_HEIGHT / (hi.z - lo.z)
    mid = (lo + hi) * 0.5
    ob.data.transform(Matrix.Translation(Vector((-mid.x, -mid.y, -lo.z))))
    ob.data.transform(Matrix.Diagonal((scale, scale, scale, 1.0)))
    ob.data.update()
    return scale


def face_point(ob, u, v):
    """Where the front of the frog sits at (u, v) fractions, and its normal.

    The frog faces -Y here, so the ray starts behind the camera side of the
    frog and travels +Y. The normal it reports points back out of the face.
    """
    lo, hi = bounds(ob)
    x = (lo.x + hi.x) * 0.5 + u * (hi.x - lo.x)
    z = lo.z + v * (hi.z - lo.z)
    origin = Vector((x, lo.y - 1.0, z))
    ok, loc, normal, _ = ob.ray_cast(origin, Vector((0.0, 1.0, 0.0)))
    if not ok:
        raise SystemExit("no face surface at u=%.4f v=%.4f" % (u, v))
    return loc, normal.normalized()


def build_pupil(name, apex, normal, radius, flat, sink, mat_pupil):
    """A shallow lens sunk into an eye bump.

    The sculpt has bare eye bumps, but the blink works by squashing the pupil
    nodes flat, so the pupils have to be real geometry. A lens - rather than a
    disc - matters because the bump is a small sphere: a flat disc would float
    off the surface at its rim.
    """
    verts, faces = ellipsoid((radius, radius, radius * flat), (0, 0, 0), 40, 20)
    # The lens is flattened along its own Z, so aim that axis down the eye's
    # normal and leave the node free to spin about it as it blinks.
    aim = Vector((0.0, 0.0, 1.0)).rotation_difference(normal).to_matrix().to_4x4()
    verts = [aim @ Vector(v) for v in verts]
    ob = make_object(name, verts, faces)
    assign(ob, mat_pupil)
    smooth(ob, 50.0)
    ob.location = apex - normal * (radius * flat * sink)
    return ob


def build_glint(name, pupil, normal, pupil_radius, radius, mat_glint):
    """The single highlight the toy wears on each pupil.

    Both glints sit up and to the left, because the photos show one light
    source - so this offset is deliberately not mirrored between the eyes.
    The frog faces -Y here, which makes the viewer's left -X and up +Z.
    """
    verts, faces = ellipsoid((radius, radius, radius * 0.55), (0, 0, 0), 20, 10)
    aim = Vector((0.0, 0.0, 1.0)).rotation_difference(normal).to_matrix().to_4x4()
    verts = [aim @ Vector(v) for v in verts]
    ob = make_object(name, verts, faces)
    assign(ob, mat_glint)
    smooth(ob, 60.0)
    ob.location = pupil.location \
        + Vector((-GLINT_OFF[0] * pupil_radius, 0.0, GLINT_OFF[1] * pupil_radius)) \
        + normal * (PUPIL_FLAT * pupil_radius * 0.6)
    return ob


def join(objs, name):
    bpy.ops.object.select_all(action="DESELECT")
    for ob in objs:
        ob.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    joined = bpy.context.view_layer.objects.active
    joined.name = name
    joined.data.name = name
    return joined


def build_frog():
    src = open_source()
    # The materials have to be made after the sculpt is loaded: opening a .blend
    # replaces everything, including any material made before the open.
    mat_body, mat_pupil, mat_glint = frog_materials()
    normalize(src)

    body = src
    body.name = "FrogMokugyo"
    body.data.name = "FrogMokugyo"
    assign(body, mat_body)
    smooth(body, 40.0)

    lo, hi = bounds(body)
    width = hi.x - lo.x
    pupils = []
    for u in EYE_U:
        side = "R" if u > 0.0 else "L"
        apex, normal = face_point(body, u, EYE_V)
        radius = PUPIL_R * width
        pupil = build_pupil("Pupil" + side, apex, normal, radius,
                            PUPIL_FLAT, PUPIL_SINK, mat_pupil)
        glint = build_glint("Glint", pupil, normal, radius,
                            GLINT_R * width, mat_glint)
        # `join` re-expresses the glint around the pupil's own origin, so the
        # node that comes out is already the pivot the blink squashes about.
        # The pupils stay siblings of the body rather than children of it: the
        # game looks them up as `FrogMesh/PupilL`, and hanging them off the
        # body would bury them a level deeper in the imported scene.
        pupils.append(join([pupil, glint], "Pupil" + side))

    bpy.context.scene.cursor.location = (0.0, 0.0, 0.0)
    bpy.ops.object.select_all(action="DESELECT")
    body.select_set(True)
    bpy.context.view_layer.objects.active = body
    bpy.ops.object.origin_set(type="ORIGIN_CURSOR")

    export_glb([body] + pupils, "frog_mokugyo.glb")
    dims = body.dimensions
    print("FROG_DIM %s  width %.4f height %.4f depth %.4f" % (
        tuple(round(d, 4) for d in dims), dims.x, dims.z, dims.y))
    return body


# ---------------------------------------------------------------------------
# mallet
# ---------------------------------------------------------------------------

def frog_materials():
    """Body, pupil and glint, in one place, so the mallet can share the body."""
    return (
        material("FrogBody", C_BODY,
                 roughness=BODY_ROUGHNESS, specular=BODY_SPECULAR),
        material("FrogPupil", C_PUPIL, roughness=0.22, specular=0.8),
        material("FrogGlint", C_GLINT, roughness=0.08, specular=1.0),
    )


def build_mallet(mat_body):
    """Ball head on a straight handle, sharing the frog's material.

    The head is centred on the object's origin and the handle runs along +X, so
    the same transform is both the head and the pivot - which is what lets the
    scene put the ball down next to the frog and have it read as resting there.
    """
    head_v, head_f = ellipsoid(
        [HEAD_R * HEAD_STRETCH, HEAD_R, HEAD_R], (0.0, 0.0, 0.0), 48, 24)
    head = make_object("MalletHead", head_v, head_f)
    assign(head, mat_body)
    smooth(head, 40.0)

    hv, hf = cylinder(HANDLE_R, 0.0, HANDLE_LEN - HANDLE_R * 0.4,
                      segments=48, axis="X")
    handle = make_object("MalletHandle", hv, hf)
    assign(handle, mat_body)
    smooth(handle, 40.0)

    cap_v, cap_f = ellipsoid(
        [HANDLE_R * 0.4, HANDLE_R, HANDLE_R],
        (HANDLE_LEN - HANDLE_R * 0.4, 0.0, 0.0), 24, 12)
    cap = make_object("MalletCap", cap_v, cap_f)
    assign(cap, mat_body)
    smooth(cap, 40.0)

    mallet = join([head, handle, cap], "Mallet")
    bpy.context.scene.cursor.location = (0.0, 0.0, 0.0)
    bpy.ops.object.origin_set(type="ORIGIN_CURSOR")
    export_glb([mallet], "mallet.glb")
    return mallet


def main():
    build_frog()

    clear_scene()
    # One material, both models: the mallet is cut from the same cloth as the
    # frog, so the pair reads as a set.
    build_mallet(frog_materials()[0])
    print("DONE")


if __name__ == "__main__":
    main()
