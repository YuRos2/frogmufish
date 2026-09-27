class_name LotusLeaf
extends MeshInstance3D

## The frog's lily pad.
##
## This replaces the old cream place mat: a slightly cupped, scallop-edged
## lotus leaf that floats on the pond. The shape (scalloped rim, radial slit)
## is built into the mesh, while the colour - a light centre, deeper edge and
## radiating veins - is painted into an image texture at load time, so there is
## still no imported asset to track.
##
## The surface is deliberately kept flat out to about two thirds of the radius:
## the frog and the mallet both rest on the physics floor at y = 0, so only the
## outer rim curls up. That way the leaf reads as a cup without the mallet
## visually sinking into it.

const RADIUS := 0.205
const CENTRE_R := 0.014
const RINGS := 28
const SEGMENTS := 72

## How far the outer rim lifts and where the lift starts (fraction of radius).
const CURL_START := 0.60
const CURL_LIFT := 0.026

## Scalloped edge: how much the radius and height wobble, and how many lobes.
const EDGE_WAVE := 0.035
const WAVE_LOBES := 11
const RIM_RIPPLE := 0.010

## The classic radial slit, cut almost to the centre on the front-left so it
## never overlaps where the mallet rests.
const NOTCH_ANGLE := -0.95
const NOTCH_HALF := 0.105
const NOTCH_INNER := 0.16

const TEX_SIZE := 256
const VEIN_COUNT := 15


func _ready() -> void:
	mesh = _build_mesh()
	# The leaf sits a hair above the water so its rim catches the light.
	position.y = 0.0012
	material_override = _build_material()


func _build_mesh() -> ArrayMesh:
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()

	for i in RINGS + 1:
		var t := float(i) / float(RINGS)
		var base_r := lerpf(CENTRE_R, RADIUS, t)
		var curl := clampf((t - CURL_START) / (1.0 - CURL_START), 0.0, 1.0)
		for j in SEGMENTS:
			var a := TAU * float(j) / float(SEGMENTS)
			# Scallop the rim and ripple it up and down.
			var radius := base_r * (1.0 + EDGE_WAVE * sin(WAVE_LOBES * a) * t)
			var x := sin(a) * radius
			var z := cos(a) * radius
			var y := CURL_LIFT * curl * curl \
				+ RIM_RIPPLE * sin(WAVE_LOBES * a) * curl * curl
			verts.append(Vector3(x, y, z))
			uvs.append(Vector2(
				clampf(0.5 + x / (2.0 * RADIUS), 0.002, 0.998),
				clampf(0.5 + z / (2.0 * RADIUS), 0.002, 0.998)))

	for i in RINGS:
		var t0 := float(i) / float(RINGS)
		var t1 := float(i + 1) / float(RINGS)
		for j in SEGMENTS:
			var j1 := (j + 1) % SEGMENTS
			var mid := (t0 + t1) * 0.5
			var a := TAU * (float(j) + 0.5) / float(SEGMENTS)
			var rel := wrapf(a - NOTCH_ANGLE, -PI, PI)
			if absf(rel) < NOTCH_HALF and mid > NOTCH_INNER:
				continue
			var a0 := i * SEGMENTS + j
			var b0 := i * SEGMENTS + j1
			var a1 := (i + 1) * SEGMENTS + j
			var b1 := (i + 1) * SEGMENTS + j1
			indices.append_array([a0, a1, b1, a0, b1, b0])

	# Face-average the normals so the curled rim catches the light smoothly.
	var norms := PackedVector3Array()
	norms.resize(verts.size())
	for k in range(0, indices.size(), 3):
		var ia := indices[k]
		var ib := indices[k + 1]
		var ic := indices[k + 2]
		var face := (verts[ib] - verts[ia]).cross(verts[ic] - verts[ia])
		norms[ia] += face
		norms[ib] += face
		norms[ic] += face
	for i in norms.size():
		norms[i] = Vector3.UP if norms[i].length_squared() < 1e-18 \
			else norms[i].normalized()

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_INDEX] = indices

	var out := ArrayMesh.new()
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return out


func _build_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = _build_texture()
	mat.albedo_color = Color.WHITE
	mat.roughness = 0.80
	mat.metallic = 0.0
	mat.metallic_specular = 0.12
	# The underside is visible from a low camera angle, so draw both sides.
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat


## Paints the leaf colour: a pale centre, a deeper edge and radiating veins.
func _build_texture() -> ImageTexture:
	var img := Image.create(TEX_SIZE, TEX_SIZE, false, Image.FORMAT_RGBA8)
	for py in TEX_SIZE:
		for px in TEX_SIZE:
			var u := float(px) / float(TEX_SIZE - 1)
			var v := float(py) / float(TEX_SIZE - 1)
			var dx := (u - 0.5) * 2.0
			var dy := (v - 0.5) * 2.0
			var rad := sqrt(dx * dx + dy * dy)
			var ang := atan2(dy, dx)
			var body := Palette.LOTUS.lerp(Palette.LOTUS_DEEP, clampf(rad * 0.8, 0.0, 1.0))
			# Sharp radial veins, brightest near the centre.
			var vein := pow(maxf(0.0, cos(ang * float(VEIN_COUNT))), 26.0)
			vein *= clampf(1.15 - rad, 0.0, 1.0)
			body = body.lerp(Palette.LOTUS_RIM, vein * 0.45)
			# Faint concentric ripples so the surface is not dead flat.
			body = body.darkened(0.03 * (0.5 + 0.5 * sin(rad * 46.0)))
			img.set_pixel(px, py, body)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)
