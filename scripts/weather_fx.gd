class_name WeatherFX
extends Node3D

## The visible weather: rain, snow, hail, wind and lightning.
##
## `sky_cycle.gd` decides how the *light* changes; this node decides what falls
## out of the sky. It reads the same eased look dictionary - rain, snow, hail,
## wind, thunder and the severe-weather level - and drives three CPU particle
## systems, a lightning lamp, and a sway on the lotus leaf.
##
## Severe convective weather steps all of it up: the rain thickens, the hail
## falls like gravel, the wind gusts so a typhoon visibly whips the leaf, and
## the strike rate from `SkyState` decides how often the sky flickers.
##
## Everything is built in code from Godot primitives, matching the rest of the
## project: no textures, no imported particle materials.
##
## The particle amounts ease rather than snap, so walking out of a rain shower
## takes a few seconds and never pops. Changing `amount` reallocates the
## particle buffer, so the integer is only written when it actually changes.

## Fires when lightning strikes, so `sky_cycle.gd` can lift the ambient light
## for a frame or two as well. A flash reads as a flash because the whole scene
## brightens, not just the shadows.
signal flash(strength: float)

const RAIN_AMOUNT := 460
const SNOW_AMOUNT := 520
const HAIL_AMOUNT := 300
const TRANSITION_RATE := 1.4

const RAIN_COLOR := Color(0.72, 0.82, 0.95, 0.42)
const SNOW_COLOR := Color(1.0, 1.0, 1.0, 0.92)
const HAIL_COLOR := Color(0.88, 0.95, 1.0, 0.95)

var _rain: CPUParticles3D
var _snow: CPUParticles3D
var _hail: CPUParticles3D
var _lightning: DirectionalLight3D
var _leaf: Node3D
var _rain_quad: QuadMesh
var _snow_quad: QuadMesh

var _rain_level := 0.0
var _snow_level := 0.0
var _hail_level := 0.0
var _wind := 0.0
var _wind_deg := 225.0
var _thunder := false
var _severe := 0
var _typhoon := false
var _lightning_rate := 0.0
var _rain_count := -1
var _snow_count := -1
var _hail_count := -1
var _flash := 0.0
var _echo := 0.0
var _chain := 0
var _cooldown := 0.0
var _sway := 0.0
var _gust := 0.0
var _frost := 0.0


func _ready() -> void:
	_leaf = get_parent().get_node_or_null("LotusLeaf")
	_build_rain()
	_build_snow()
	_build_hail()
	_lightning = DirectionalLight3D.new()
	_lightning.name = "LightningLight"
	_lightning.light_color = Color("dfe8ff")
	_lightning.light_energy = 0.0
	_lightning.shadow_enabled = false
	_lightning.rotation_degrees = Vector3(-72.0, 28.0, 0.0)
	add_child(_lightning)


## Takes the eased sky look. Only the weather part is used here.
func apply_look(look: Dictionary) -> void:
	_rain_level = float(look.get("rain", 0.0))
	_snow_level = float(look.get("snow", 0.0))
	_hail_level = float(look.get("hail", 0.0))
	_wind = float(look.get("wind", 0.0))
	_thunder = bool(look.get("thunder", false))
	_severe = int(look.get("severe_level", 0))
	_typhoon = bool(look.get("typhoon", false))
	_lightning_rate = float(look.get("lightning_rate", 0.0))
	_frost = float(look.get("snow", 0.0))
	if look.has("wind_deg"):
		_wind_deg = float(look["wind_deg"])


## Wind bearing in meteorological degrees (the direction it blows *from*).
func set_wind_deg(deg: float) -> void:
	_wind_deg = deg


## True while it is actually raining hard enough to see. The tests use it.
func is_raining() -> bool:
	return _rain != null and _rain.emitting


func is_snowing() -> bool:
	return _snow != null and _snow.emitting


func is_hailing() -> bool:
	return _hail != null and _hail.emitting


func rain_level() -> float:
	return _rain_level


func hail_level() -> float:
	return _hail_level


func severe_level() -> int:
	return _severe


func is_typhoon() -> bool:
	return _typhoon


func _process(delta: float) -> void:
	if _rain == null or _snow == null or _hail == null:
		return
	var t := clampf(delta * TRANSITION_RATE, 0.0, 1.0)
	var breeze := deg_to_rad(_wind_deg + 180.0)
	# A typhoon does not blow steadily: it gusts. The swell rides on top of the
	# reported wind so a 150 km/h storm visibly surges against the leaf.
	_gust += delta * lerpf(0.9, 2.4, clampf(float(_severe) / 3.0, 0.0, 1.0))
	var gust_mix := 1.0 + sin(_gust) * 0.35 * clampf(float(_severe) / 3.0, 0.0, 1.0)
	var wind_vector := Vector3(sin(breeze), 0.0, -cos(breeze)) \
		* _wind * 0.06 * gust_mix

	# --- rain -------------------------------------------------------------
	var rain_target := clampf(_rain_level, 0.0, 1.0)
	_rain.emitting = rain_target > 0.015
	if _rain.emitting:
		var count := maxi(8, int(round(rain_target * RAIN_AMOUNT
			* (1.0 + float(_severe) * 0.22))))
		if count != _rain_count:
			_rain_count = count
			_rain.amount = count
		_rain.gravity = Vector3(wind_vector.x, -9.0, wind_vector.z)
		# Slant the streaks into the wind without moving the emitter.
		_rain.rotation.z = lerpf(_rain.rotation.z, -wind_vector.x * 0.02, t)
		_rain.rotation.x = lerpf(_rain.rotation.x, wind_vector.z * 0.02, t)
		var rain_alpha := lerpf(0.18, 0.5, rain_target)
		var rain_mesh := _rain.mesh as QuadMesh
		if rain_mesh != null:
			(rain_mesh.material as StandardMaterial3D).albedo_color = \
				Color(RAIN_COLOR, rain_alpha)

	# --- snow -------------------------------------------------------------
	var snow_target := clampf(_snow_level, 0.0, 1.0)
	_snow.emitting = snow_target > 0.02
	if _snow.emitting:
		var count := maxi(10, int(round(snow_target * SNOW_AMOUNT)))
		if count != _snow_count:
			_snow_count = count
			_snow.amount = count
		_snow.gravity = Vector3(wind_vector.x * 0.35, -0.10, wind_vector.z * 0.35)

	# --- hail -------------------------------------------------------------
	# Ice does not drift: it is thrown down hard and rattles through the frame,
	# so it gets a short life, a steep gravity and only a light wind push.
	var hail_target := clampf(_hail_level, 0.0, 1.0)
	_hail.emitting = hail_target > 0.02
	if _hail.emitting:
		var hcount := maxi(6, int(round(hail_target * HAIL_AMOUNT)))
		if hcount != _hail_count:
			_hail_count = hcount
			_hail.amount = hcount
		_hail.gravity = Vector3(wind_vector.x * 0.6, -15.0, wind_vector.z * 0.6)

	_apply_frost(delta)
	apply_wind_sway(delta)
	_apply_lightning(delta, breeze)

## Snow settles on the lotus leaf as a pale coat, so the weather is visible in
## the still parts of the scene too, not only in the particles.
func _apply_frost(delta: float) -> void:
	var leaf := _leaf as MeshInstance3D
	if leaf == null:
		return
	var mat := leaf.material_override as StandardMaterial3D
	if mat == null:
		return
	var wanted := Color.WHITE.lerp(Color("e6f0ff"), clampf(_frost, 0.0, 1.0) * 0.6)
	mat.albedo_color = mat.albedo_color.lerp(wanted, clampf(delta * 1.2, 0.0, 1.0))


func _apply_lightning(delta: float, breeze: float) -> void:
	_flash = maxf(0.0, _flash - delta * 7.5)
	if _echo > 0.0:
		_echo -= delta
		if _echo <= 0.0:
			_flash = maxf(_flash, randf_range(1.1, 2.0))
			flash.emit(_flash * 0.6)
			if _chain > 0:
				_chain -= 1
				_echo = randf_range(0.06, 0.16)
	if _thunder or _lightning_rate > 0.0:
		_cooldown -= delta
		if _cooldown <= 0.0:
			_fire_bolt()
	else:
		_cooldown = randf_range(1.5, 4.0)
	_lightning.light_energy = _flash
	# The bolt comes from wherever the wind is coming from.
	_lightning.global_rotation = Vector3(
		-1.15, breeze + PI, 0.0)


## One strike: a bright main flash, often an echo, and - in a bad cell - a
## chain of two or three flicks that reads as forked lightning.
func _fire_bolt() -> void:
	var power := 1.0 + float(_severe) * 0.45
	_flash = randf_range(1.9, 3.2) * power
	flash.emit(_flash * 0.55)
	var rate := maxf(2.0, _lightning_rate)
	_cooldown = clampf(60.0 / rate * randf_range(0.35, 1.6), 0.25, 20.0)
	if randf() < 0.45:
		_echo = randf_range(0.08, 0.20)
	if _severe >= 2 and randf() < 0.4:
		_chain = 2 if _severe >= 3 else 1
		_echo = maxf(_echo, 0.07)


# --- wind on the leaf -----------------------------------------------------

## Called from `_process` indirectly through the same delta, kept separate so
## the sway can be reasoned about (and pinned) on its own.
func apply_wind_sway(delta: float) -> void:
	if _leaf == null:
		return
	_sway += delta
	var amplitude := clampf(0.003 + _wind * 0.00035, 0.003, 0.022)
	# The sway grows with the rain so a storm looks agitated rather than calm,
	# and a typhoon whips the leaf around rather than rocking it.
	amplitude *= lerpf(1.0, 1.6, clampf(_rain_level, 0.0, 1.0))
	amplitude *= 1.0 + float(_severe) * 0.25
	var speed := 1.1 + float(_severe) * 0.6 + _gust * 2.0 * float(_severe)
	_leaf.rotation.z = sin(_sway * speed) * amplitude
	_leaf.rotation.x = sin(_sway * (speed * 0.64) + 1.3) * amplitude * 0.6


# --- built systems --------------------------------------------------------

func _build_rain() -> void:
	_rain = CPUParticles3D.new()
	_rain.name = "Rain"
	_rain.amount = 8
	_rain.lifetime = 0.85
	_rain.preprocess = 0.85
	_rain.randomness = 0.4
	_rain.local_coords = false
	_rain.emitting = false
	_rain.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_rain.emission_box_extents = Vector3(2.4, 0.05, 2.4)
	_rain.position = Vector3(0.0, 1.4, 0.0)
	_rain.direction = Vector3(0.0, -1.0, 0.0)
	_rain.spread = 2.0
	_rain.gravity = Vector3(0.0, -9.0, 0.0)
	_rain.initial_velocity_min = 0.0
	_rain.initial_velocity_max = 0.7
	_rain.scale_amount_min = 0.9
	_rain.scale_amount_max = 1.5
	_rain.mesh = _streak_mesh()
	_rain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_rain)


func _build_snow() -> void:
	_snow = CPUParticles3D.new()
	_snow.name = "Snow"
	_snow.amount = 10
	_snow.lifetime = 5.0
	_snow.preprocess = 3.0
	_snow.randomness = 0.6
	_snow.local_coords = false
	_snow.emitting = false
	_snow.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	# The camera frames the frog closely, so the whole visible air column is
	# roughly a metre tall. Snow has to be emitted inside that column or it
	# falls for metres out of frame and is never seen.
	_snow.emission_box_extents = Vector3(1.8, 0.50, 1.8)
	_snow.position = Vector3(0.0, 0.78, 0.0)
	_snow.direction = Vector3(0.0, -1.0, 0.0)
	_snow.spread = 25.0
	# Flakes need drag, not free fall: without it they are underground within a
	# second of leaving the emitter and the air looks empty.
	_snow.gravity = Vector3(0.0, -0.10, 0.0)
	_snow.damping_min = 0.30
	_snow.damping_max = 0.65
	_snow.initial_velocity_min = 0.12
	_snow.initial_velocity_max = 0.38
	_snow.angular_velocity_min = -80.0
	_snow.angular_velocity_max = 80.0
	_snow.scale_amount_min = 0.5
	_snow.scale_amount_max = 1.3
	_snow.mesh = _flake_mesh()
	_snow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_snow)


func _build_hail() -> void:
	_hail = CPUParticles3D.new()
	_hail.name = "Hail"
	_hail.amount = 8
	_hail.lifetime = 0.9
	_hail.preprocess = 0.9
	_hail.randomness = 0.5
	_hail.local_coords = false
	_hail.emitting = false
	_hail.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_hail.emission_box_extents = Vector3(1.6, 0.05, 1.6)
	_hail.position = Vector3(0.0, 1.1, 0.0)
	_hail.direction = Vector3(0.0, -1.0, 0.0)
	_hail.spread = 6.0
	_hail.gravity = Vector3(0.0, -15.0, 0.0)
	_hail.initial_velocity_min = 1.6
	_hail.initial_velocity_max = 3.4
	_hail.scale_amount_min = 0.5
	_hail.scale_amount_max = 1.4
	_hail.mesh = _hail_mesh()
	_hail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_hail)


func _streak_mesh() -> QuadMesh:
	_rain_quad = QuadMesh.new()
	_rain_quad.size = Vector2(0.0045, 0.055)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	mat.billboard_keep_scale = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = RAIN_COLOR
	_rain_quad.material = mat
	return _rain_quad


func _flake_mesh() -> QuadMesh:
	_snow_quad = QuadMesh.new()
	_snow_quad.size = Vector2(0.024, 0.024)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.billboard_keep_scale = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_texture = _flake_texture(24)
	mat.albedo_color = SNOW_COLOR
	_snow_quad.material = mat
	return _snow_quad


## A faceted little ice pellet: a low-poly sphere with a bright unshaded
## surface, so it reads as hail and not as slower snow.
func _hail_mesh() -> SphereMesh:
	var sphere := SphereMesh.new()
	sphere.radius = 0.008
	sphere.height = 0.016
	sphere.radial_segments = 6
	sphere.rings = 3
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = HAIL_COLOR
	sphere.material = mat
	return sphere


## A soft round flake, so the snow reads as snow rather than as falling
## squares. Bright enough to stand out against the darker snow sky.
static func _flake_texture(size: int) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var half := float(size) * 0.5
	for py in size:
		for px in size:
			var dx := (float(px) + 0.5 - half) / half
			var dy := (float(py) + 0.5 - half) / half
			var d := sqrt(dx * dx + dy * dy)
			var alpha := 1.0 - smoothstep(0.25, 0.95, d)
			img.set_pixel(px, py, Color(1.0, 1.0, 1.0, alpha))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)
