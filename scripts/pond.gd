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

## Rain does not move the three slow rings above: it stipples the whole surface
## with short-lived splashes. They are pooled, so a storm never allocates.
const SPLASHES := 26
const SPLASH_SPREAD := 1.7
const SPLASH_LIFE := 0.75
const SPLASH_RATE := 26.0

var _rings: Array[MeshInstance3D] = []
var _mats: Array[StandardMaterial3D] = []
var _t: Array[float] = []
var _splashes: Array[MeshInstance3D] = []
var _splash_mat: Array[StandardMaterial3D] = []
var _splash_life: Array[float] = []
var _splash_rng := RandomNumberGenerator.new()

var _flow := Vector2.ZERO
var _flow_speed := Vector2(0.013, 0.021)
var _ripple_speed := RIPPLE_SPEED
var _rain := 0.0
var _snow := 0.0
var _hail := 0.0
var _wind := 0.0
var _target_color := Palette.POND
var _target_rough := 0.20


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

	_splash_rng.seed = 20240926
	for i in SPLASHES:
		var splash := _make_splash()
		splash.visible = false
		add_child(splash)
		_splashes.append(splash)
		_splash_mat.append(splash.material_override as StandardMaterial3D)
		_splash_life.append(1.0)


## Feeds the eased `SkyState` look in. The water answers the weather the same
## way the sky does: darker and rougher in rain, pale and flat under snow, and
## more agitated in wind.
func set_look(look: Dictionary) -> void:
	if look.is_empty():
		return
	_rain = float(look.get("rain", 0.0))
	_snow = float(look.get("snow", 0.0))
	_hail = float(look.get("hail", 0.0))
	_wind = float(look.get("wind", 0.0))
	_target_color = look.get("water_color", Palette.POND)
	_target_rough = float(look.get("water_roughness", 0.20))
	_ripple_speed = RIPPLE_SPEED * float(look.get("water_ripple", 1.0))
	_flow_speed = Vector2(0.013, 0.021) * (0.6 + _wind * 0.07 + _rain * 3.2)


func _process(delta: float) -> void:
	# Drift the normal map so the shimmer crawls across the water.
	_flow += _flow_speed * delta
	var mat := material_override as StandardMaterial3D
	if mat != null:
		mat.uv1_offset = Vector3(_flow.x, _flow.y, 0.0)
		mat.albedo_color = mat.albedo_color.lerp(_target_color, clampf(delta * 1.2, 0.0, 1.0))
		mat.roughness = lerpf(mat.roughness, _target_rough, clampf(delta * 1.2, 0.0, 1.0))

	for i in _rings.size():
		_t[i] = fmod(_t[i] + delta * _ripple_speed, 1.0)
		var t := _t[i]
		var scale := lerpf(RIPPLE_MIN, RIPPLE_MAX, t)
		_rings[i].scale = Vector3(scale, 1.0, scale)
		_mats[i].albedo_color = Color(Palette.POND_LIGHT, 0.40 * (1.0 - t))

	_update_splashes(delta)


## Short-lived rings where the rain lands. Active splashes grow and fade; new
## ones appear at a rate set by the rain amount, and snow gets a much slower
## version so a settled snowfield still shimmers a little.
func _update_splashes(delta: float) -> void:
	# Hail hits the water hardest of all, so it stipples it even more than rain.
	var wet := maxf(_rain, maxf(_snow * 0.25, _hail * 1.4))
	var spawn := wet * SPLASH_RATE * delta
	var whole := int(spawn)
	if _splash_rng.randf() < spawn - float(whole):
		whole += 1
	for _i in whole:
		var pick := _splash_rng.randi_range(0, _splashes.size() - 1)
		_splash_life[pick] = 0.0
		var angle := _splash_rng.randf_range(0.0, TAU)
		var radius := sqrt(_splash_rng.randf()) * SPLASH_SPREAD
		_splashes[pick].position = Vector3(
			cos(angle) * radius, 0.0016, sin(angle) * radius)

	for i in _splashes.size():
		if _splash_life[i] >= 1.0:
			_splashes[i].visible = false
			continue
		_splash_life[i] = minf(1.0, _splash_life[i] + delta / SPLASH_LIFE)
		var t := _splash_life[i]
		var scale := lerpf(0.35, 1.25, t)
		_splashes[i].visible = true
		_splashes[i].scale = Vector3(scale, 1.0, scale)
		_splash_mat[i].albedo_color = Color(
			Palette.POND_LIGHT, 0.26 * (1.0 - t) * clampf(wet * 1.5, 0.0, 1.0))


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
	return _make_ring(RIPPLE_BASE, 0.012, 64, Color(Palette.POND_LIGHT, 0.4))


## A tiny version of the same ring for a raindrop landing.
func _make_splash() -> MeshInstance3D:
	return _make_ring(0.020, 0.0035, 20, Color(Palette.POND_LIGHT, 0.55))


func _make_ring(base: float, thickness: float, segments: int, tint: Color) -> MeshInstance3D:
	var torus := TorusMesh.new()
	torus.inner_radius = base
	torus.outer_radius = base + thickness
	torus.rings = segments
	torus.ring_segments = 8
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = tint
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
