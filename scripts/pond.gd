class_name Pond
extends MeshInstance3D

## The macaron pond the lotus leaf floats on.
##
## The surface is a single deep-green plane with a low roughness, so the pastel
## sky reflects off it at grazing angles the way water does. Two procedural
## touches sell the "water" without any imported texture:
##
## * a tiling normal map, generated from two crossing sine waves and scrolled
##   slowly, gives the surface a soft moving shimmer;
## * a few thin rings ripple outward around the leaf.
##
## The plane is oversized (24 m) so its far edge sits beyond the camera's frame
## and the water reads as reaching the horizon instead of as a floating slab.

const SIZE := 24.0
const RIPPLES := 3
const RIPPLE_SPEED := 0.16
const RIPPLE_BASE := 0.34
const RIPPLE_MIN := 0.45
const RIPPLE_MAX := 1.7
const NORMAL_SIZE := 128

var _rings: Array[MeshInstance3D] = []
var _mats: Array[StandardMaterial3D] = []
var _t: Array[float] = []

var _flow := Vector2.ZERO


func _ready() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(SIZE, SIZE)
	plane.subdivide_width = 1
	plane.subdivide_depth = 1
	var mat := _water_material()
	plane.material = mat
	mesh = plane
	material_override = mat

	for i in RIPPLES:
		var ring := _make_ripple()
		add_child(ring)
		_rings.append(ring)
		_mats.append(ring.material_override as StandardMaterial3D)
		_t.append(float(i) / float(RIPPLES))


func _process(delta: float) -> void:
	# Drift the normal map so the shimmer crawls across the water.
	_flow += Vector2(0.013, 0.021) * delta
	var mat := material_override as StandardMaterial3D
	if mat != null:
		mat.uv1_offset = Vector3(_flow.x, _flow.y, 0.0)

	for i in _rings.size():
		_t[i] = fmod(_t[i] + delta * RIPPLE_SPEED, 1.0)
		var t := _t[i]
		var scale := lerpf(RIPPLE_MIN, RIPPLE_MAX, t)
		_rings[i].scale = Vector3(scale, 1.0, scale)
		_mats[i].albedo_color = Color(Palette.POND_LIGHT, 0.40 * (1.0 - t))


func _water_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Palette.POND
	mat.roughness = 0.20
	mat.metallic = 0.0
	mat.metallic_specular = 0.7
	mat.normal_enabled = true
	mat.normal_texture = _build_normal_map()
	mat.normal_scale = 0.12
	mat.uv1_scale = Vector3(9.0, 9.0, 1.0)
	return mat


## A thin ring that grows outward and fades as it travels.
func _make_ripple() -> MeshInstance3D:
	var torus := TorusMesh.new()
	torus.inner_radius = RIPPLE_BASE
	torus.outer_radius = RIPPLE_BASE + 0.012
	torus.rings = 64
	torus.ring_segments = 8
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(Palette.POND_LIGHT, 0.4)
	var ring := MeshInstance3D.new()
	ring.mesh = torus
	ring.material_override = mat
	ring.position.y = 0.0015
	ring.scale = Vector3(RIPPLE_MIN, 1.0, RIPPLE_MIN)
	return ring


## A tiling normal map built from two crossing sine waves, so the flat pond
## catches moving highlights instead of looking like painted card.
func _build_normal_map() -> ImageTexture:
	var img := Image.create(NORMAL_SIZE, NORMAL_SIZE, false, Image.FORMAT_RGB8)
	var strength := 0.55
	for py in NORMAL_SIZE:
		for px in NORMAL_SIZE:
			var u := float(px) / float(NORMAL_SIZE)
			var v := float(py) / float(NORMAL_SIZE)
			var phase_a := TAU * (3.0 * u + 1.0 * v)
			var phase_b := TAU * (1.0 * u - 4.0 * v)
			var phase_c := TAU * (2.0 * u + 5.0 * v)
			var dhu := TAU * 3.0 * cos(phase_a) + TAU * 1.0 * cos(phase_b) \
				+ TAU * 2.0 * cos(phase_c)
			var dhv := TAU * 1.0 * cos(phase_a) - TAU * 4.0 * cos(phase_b) \
				+ TAU * 5.0 * cos(phase_c)
			var n := Vector3(-dhu * strength, 1.0, -dhv * strength).normalized()
			# Tangent-space encoding: R = tangent.x, G = bitangent.z, B = normal.y.
			img.set_pixel(px, py, Color(
				n.x * 0.5 + 0.5, n.z * 0.5 + 0.5, n.y * 0.5 + 0.5))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)
