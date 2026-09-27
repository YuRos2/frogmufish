class_name LotusMallet
extends Node3D

## Re-skins the mallet as a lotus flower bud.
##
## The physics is untouched: `mallet.tscn` still carries the same two capsule
## collision shapes and the ball still sits at the origin, so every strike,
## grab and auto-swing behaves exactly as before. Only the look changes.
##
## The bud is a lobe-ridged solid of revolution built by hand - a rounded base
## tapering to a point, with five petal ridges around it - and a colour
## gradient baked into the vertex colours (cream at the base, pink at the tip,
## deeper pink in the petal seams). The handle becomes the stem, with a small
## green calyx where the two meet.

## The bud's axis is the mallet's local +X (the handle direction). It stays
## inside the head capsule (radius 0.0136) so the collision the strike detector
## uses still matches the visible flower.
const BASE_X := 0.0135
const TIP_X := -0.0165
const RADIUS := 0.0122
const LOBES := 5
const LOBE_AMPL := 0.14
const TWIST := 0.55
const RINGS := 22
const SEGMENTS := 40

const STEM_RADIUS := 0.0042
const STEM_X0 := 0.004
const STEM_X1 := 0.190


func _ready() -> void:
	add_child(_build_bud())
	add_child(_build_stem())
	add_child(_build_calyx())


func _build_bud() -> MeshInstance3D:
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()

	for i in RINGS + 1:
		var u := float(i) / float(RINGS)
		for j in SEGMENTS:
			var a := TAU * float(j) / float(SEGMENTS)
			verts.append(_bud_point(u, a))
			cols.append(_bud_color(u, a))
			uvs.append(Vector2(u, float(j) / float(SEGMENTS)))

	for i in RINGS:
		for j in SEGMENTS:
			var j1 := (j + 1) % SEGMENTS
			var a0 := i * SEGMENTS + j
			var b0 := i * SEGMENTS + j1
			var a1 := (i + 1) * SEGMENTS + j
			var b1 := (i + 1) * SEGMENTS + j1
			idx.append_array([a0, a1, b1, a0, b1, b0])

	# Average the face normals so the bud shades smoothly, including at the
	# pointed tip where several faces meet at one vertex.
	var norms := PackedVector3Array()
	norms.resize(verts.size())
	for t in range(0, idx.size(), 3):
		var ia := idx[t]
		var ib := idx[t + 1]
		var ic := idx[t + 2]
		var face := (verts[ib] - verts[ia]).cross(verts[ic] - verts[ia])
		norms[ia] += face
		norms[ib] += face
		norms[ic] += face
	for i in norms.size():
		norms[i] = Vector3.LEFT if norms[i].length_squared() < 1e-18 \
			else norms[i].normalized()

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color.WHITE
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.44
	mat.metallic = 0.0
	mat.metallic_specular = 0.35
	mat.rim_enabled = true
	mat.rim = 0.45
	mat.rim_tint = 0.6

	var mi := MeshInstance3D.new()
	mi.name = "Bud"
	mi.mesh = mesh
	mi.material_override = mat
	return mi


## The stem is the mallet handle: a slender green rod along +X.
func _build_stem() -> MeshInstance3D:
	var cyl := CylinderMesh.new()
	cyl.top_radius = STEM_RADIUS
	cyl.bottom_radius = STEM_RADIUS * 0.82
	cyl.height = STEM_X1 - STEM_X0
	cyl.radial_segments = 16
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Palette.STEM
	mat.roughness = 0.52
	mat.metallic = 0.0
	mat.metallic_specular = 0.25
	var mi := MeshInstance3D.new()
	mi.name = "Stem"
	mi.mesh = cyl
	mi.material_override = mat
	mi.rotation = Vector3(0.0, 0.0, -PI * 0.5)
	mi.position = Vector3((STEM_X0 + STEM_X1) * 0.5, 0.0, 0.0)
	return mi


## Small green bracts where the stem meets the bud, so the joint reads as a
## lotus stalk rather than a ball glued to a stick.
func _build_calyx() -> Node3D:
	var root := Node3D.new()
	root.name = "Calyx"
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Palette.STEM
	mat.roughness = 0.55
	mat.metallic = 0.0
	for i in 4:
		var a := TAU * float(i) / 4.0 + 0.4
		var leaf := SphereMesh.new()
		leaf.radius = 0.0032
		leaf.height = 0.0064
		leaf.radial_segments = 12
		leaf.rings = 6
		var mi := MeshInstance3D.new()
		mi.mesh = leaf
		mi.material_override = mat
		mi.scale = Vector3(2.6, 0.7, 1.0)
		mi.position = Vector3(0.019, cos(a) * 0.0062, sin(a) * 0.0062)
		mi.rotation = Vector3(a - PI * 0.5, 0.0, 0.5)
		root.add_child(mi)
	return root


# --- bud surface ----------------------------------------------------------

func _bud_point(u: float, a: float) -> Vector3:
	var x := lerpf(BASE_X, TIP_X, u)
	var profile := pow(maxf(0.0, sin(PI * u)), 0.55)
	var r := RADIUS * profile * _lobe(u, a)
	return Vector3(x, r * cos(a), r * sin(a))


func _lobe(u: float, a: float) -> float:
	return 1.0 + LOBE_AMPL * cos(float(LOBES) * a + TWIST * u)


## Cream at the base, pink along the body, deeper pink in the seams and at the
## tip - painted per vertex so the closed bud still reads as layered petals.
func _bud_color(u: float, a: float) -> Color:
	var c := Palette.PETAL_CORE.lerp(Palette.PETAL, smoothstep(0.0, 0.30, u))
	c = c.lerp(Palette.PETAL_DEEP, smoothstep(0.40, 1.0, u))
	var seam := maxf(0.0, -cos(float(LOBES) * a + TWIST * u))
	c = c.lerp(Palette.PETAL_DEEP, seam * 0.5 * smoothstep(0.12, 0.8, u))
	# Vertex colours are linear, while the palette is authored in sRGB; convert
	# so the bud renders as the pink the swatch promises rather than near white.
	return c.srgb_to_linear()
