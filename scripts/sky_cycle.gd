class_name SkyCycle
extends Node3D

## Turns the pure `SkyState` model into the scene the player sees: the
## procedural sky, the key / fill / rim lights, the ambient fill, the fog, a
## star dome that fades in after sunset and small sun and moon discs that ride
## the same directions as the lights.
##
## The scene's own clocks are only consulted here. Every frame this node works
## out where the sun *should* be for the current local time and latitude, asks
## `SkyState` for the matching look, eases the previous look towards it and
## pushes the result into the environment. Weather arrives as a report from
## `weather.gd` and simply becomes another input to the same model.
##
## `pin()` freezes the clock and the weather. That is what the verification
## harness uses to render a noon sky, a midnight sky and a thunderstorm on
## demand, and what a teacher can use to show a class what dusk looks like.

signal look_changed(look: Dictionary)

## How fast the eased look catches up with the target. Slow enough that a
## weather change rolls in over a few seconds instead of popping.
const TRANSITION_RATE := 1.8
## The star dome and the discs sit just inside the camera's 20 m far plane.
const STAR_RADIUS := 16.5
const STAR_COUNT := 220
const DISC_RADIUS := 15.0
## How often the look is handed to listeners, in seconds.
const EMIT_INTERVAL := 0.25

const WEEKDAYS := ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]

## The values that are eased from one look to the next. Everything else - the
## labels, the totals, the nested dictionaries - is copied straight across,
## because interpolating a date string would be nonsense.
const EASED_KEYS := [
	"sky_top", "sky_horizon", "sky_curve", "ground_bottom", "ground_horizon",
	"ambient_color", "ambient_energy",
	"key_direction", "key_color", "key_energy",
	"fill_color", "fill_energy", "rim_color", "rim_energy",
	"fog_color", "fog_density", "fog_aerial",
	"star_opacity", "glow_intensity", "glow_bloom",
	"water_color", "water_roughness", "water_ripple",
]

@export var latitude := 39.9042
@export var longitude := 116.4074
@export var follow_system_clock := true

var look: Dictionary = {}

var _target: Dictionary = {}
var _current: Dictionary = {}
var _weather_code := 0
var _cloud := -1.0
var _wind := 0.0
var _pinned := false
var _pin_hours := 12.0

var _env: Environment
var _sky_mat: ProceduralSkyMaterial
var _key: DirectionalLight3D
var _fill: DirectionalLight3D
var _rim: DirectionalLight3D
var _stars: MultiMeshInstance3D
var _star_mat: StandardMaterial3D
var _sun_disc: Sprite3D
var _moon_disc: Sprite3D
var _flash_boost := 0.0
var _emit_elapsed := 0.0


func _ready() -> void:
	var host := get_parent()
	var world := host.get_node_or_null("WorldEnvironment") as WorldEnvironment
	_env = world.environment if world != null else null
	_key = host.get_node_or_null("KeyLight") as DirectionalLight3D
	_fill = host.get_node_or_null("FillLight") as DirectionalLight3D
	_rim = host.get_node_or_null("RimLight") as DirectionalLight3D
	if _env != null and _env.sky != null:
		_sky_mat = _env.sky.sky_material as ProceduralSkyMaterial
	if _env != null:
		_env.fog_enabled = false
		_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_build_stars()
	_sun_disc = _build_disc(1.15, Color("fff3cf"), Color("ffb066"), 2)
	_moon_disc = _build_disc(0.85, Color("f2f4ff"), Color("cdd6f5"), 1)
	_recompute()
	_current = _target.duplicate(true)
	_apply()


func _process(delta: float) -> void:
	_flash_boost = maxf(0.0, _flash_boost - delta * 6.5)
	if not _pinned:
		_recompute()
	var t := clampf(delta * TRANSITION_RATE, 0.0, 1.0)
	for key in EASED_KEYS:
		if _current.has(key) and _target.has(key):
			_current[key] = _ease(_current[key], _target[key], t)
	_sync_static()
	_apply()
	_emit_elapsed += delta
	if _emit_elapsed >= EMIT_INTERVAL:
		_emit_elapsed = 0.0
		look_changed.emit(_current)


# --- public API -----------------------------------------------------------

## Feeds a `Weather.report` in. Latitude, cloud cover and wind all matter; the
## rest is only used by the HUD.
func set_weather(report: Dictionary) -> void:
	if report.is_empty():
		return
	_weather_code = int(report.get("code", 0))
	_cloud = float(report.get("cloud", -1.0)) if report.has("cloud") else -1.0
	_wind = float(report.get("wind", 0.0))
	if report.has("latitude"):
		latitude = float(report["latitude"])
	if report.has("longitude"):
		longitude = float(report["longitude"])
	# While pinned, a live update is remembered but not drawn: the verification
	# run and the preview tool have to render the sky they asked for even if the
	# weather answers in the middle of them.
	if not _pinned:
		_recompute()


## Pins the sky to a fixed hour (0..24) and, optionally, a weather report. The
## verification harness and the preview tool use this to make the scene
## deterministic; `unpin()` hands control back to the wall clock.
func pin(hours: float, report: Dictionary = {}) -> void:
	_pinned = true
	_pin_hours = fposmod(hours, 24.0)
	if not report.is_empty():
		_weather_code = int(report.get("code", 0))
		_cloud = float(report.get("cloud", -1.0)) if report.has("cloud") else -1.0
		_wind = float(report.get("wind", 0.0))
	_recompute()
	snap()


func unpin() -> void:
	_pinned = false
	_recompute()


## Copies the target look over the eased one and applies it immediately, so a
## pinned scene is exactly the requested one for the next rendered frame.
func snap() -> void:
	_recompute()
	_current = _target.duplicate(true)
	_apply()


## A lightning flash: briefly lifts the ambient light. `weather_fx.gd` calls it.
func flash(strength: float) -> void:
	_flash_boost = maxf(_flash_boost, clampf(strength, 0.0, 3.0))


func hours() -> float:
	if _pinned:
		return _pin_hours
	var t := Time.get_time_dict_from_system()
	return float(t.get("hour", 0)) + float(t.get("minute", 0)) / 60.0 \
		+ float(t.get("second", 0)) / 3600.0


func is_pinned() -> bool:
	return _pinned


# --- the look -------------------------------------------------------------

func _recompute() -> void:
	var date := Time.get_date_dict_from_system()
	var doy := SkyState.day_of_year(
		int(date.get("year", 2026)), int(date.get("month", 1)), int(date.get("day", 1)))
	var target := SkyState.look(hours(), latitude, doy, _weather_code, _cloud, _wind)
	var rise: Dictionary = target["sunrise"]
	target["date"] = "%04d-%02d-%02d" % [
		int(date.get("year", 2026)), int(date.get("month", 1)), int(date.get("day", 1))]
	target["date_text"] = "%d月%d日 %s" % [
		int(date.get("month", 1)), int(date.get("day", 1)),
		WEEKDAYS[clampi(int(date.get("weekday", 0)), 0, 6)]]
	target["weekday"] = int(date.get("weekday", 0))
	target["sunrise_hour"] = float(rise.get("sunrise", -1.0))
	target["sunset_hour"] = float(rise.get("sunset", -1.0))
	target["polar_day"] = bool(rise.get("polar_day", false))
	target["polar_night"] = bool(rise.get("polar_night", false))
	target["latitude"] = latitude
	target["longitude"] = longitude
	_target = target


func _apply() -> void:
	if _current.is_empty():
		return
	var l := _current

	if _sky_mat != null:
		_sky_mat.sky_top_color = l["sky_top"]
		_sky_mat.sky_horizon_color = l["sky_horizon"]
		_sky_mat.sky_curve = l["sky_curve"]
		_sky_mat.ground_bottom_color = l["ground_bottom"]
		_sky_mat.ground_horizon_color = l["ground_horizon"]
		_sky_mat.ground_curve = 0.05
	if _env != null:
		_env.ambient_light_color = l["ambient_color"]
		_env.ambient_light_energy = float(l["ambient_energy"]) + _flash_boost
		_env.fog_enabled = bool(l["fog"])
		_env.fog_light_color = l["fog_color"]
		_env.fog_density = float(l["fog_density"])
		_env.fog_aerial_perspective = float(l["fog_aerial"])
		_env.glow_intensity = float(l["glow_intensity"])
		_env.glow_bloom = float(l["glow_bloom"])
	if _key != null:
		_key.light_color = l["key_color"]
		_key.light_energy = float(l["key_energy"]) + _flash_boost * 0.6
		_key.global_transform = _aim(l["key_direction"])
	if _fill != null:
		_fill.light_color = l["fill_color"]
		_fill.light_energy = float(l["fill_energy"])
	if _rim != null:
		_rim.light_color = l["rim_color"]
		_rim.light_energy = float(l["rim_energy"])

	# The stars and discs follow the same numbers, so a pinned noon really does
	# have no stars and a pinned thunderstorm really does hide the sun.
	var star_alpha := float(l["star_opacity"])
	if _star_mat != null:
		_star_mat.albedo_color = Color(1.0, 1.0, 1.0, star_alpha)
	if _stars != null:
		_stars.visible = star_alpha > 0.01
		_stars.rotation.y = -deg_to_rad(hours() * 15.0)

	var sun_dir: Vector3 = l["sun"].direction if l.has("sun") else Vector3.UP
	var elevation := float(l["sun_elevation"])
	var clear := clampf(1.0 - float(l["cloud"]) * 0.9, 0.0, 1.0)
	if _sun_disc != null:
		_sun_disc.position = sun_dir * DISC_RADIUS
		var sun_alpha := smoothstep(-0.03, 0.05, elevation) * clear \
			* (1.0 - float(l["fog_amount"]) * 0.6)
		_sun_disc.modulate = Color(
			l["key_color"].lerp(Color("fff6e0"), 0.5), clampf(sun_alpha, 0.0, 1.0))
		_sun_disc.visible = sun_alpha > 0.02
	if _moon_disc != null:
		_moon_disc.position = -sun_dir * DISC_RADIUS
		var moon_alpha := (1.0 - smoothstep(-0.10, 0.02, elevation)) * clear \
			* (1.0 - float(l["fog_amount"]))
		_moon_disc.modulate = Color(Color("eef2ff"), clampf(moon_alpha, 0.0, 1.0))
		_moon_disc.visible = moon_alpha > 0.02
	look = _current


## A basis with -Z along `direction` (the way a DirectionalLight3D shines) and
## a sane up vector even when the sun is directly overhead. The direction is
## lerped between reviews, so a day/night flip can pass through (almost) zero;
## that is caught here rather than handed to `Basis.looking_at`.
static func _aim(direction: Vector3) -> Transform3D:
	var dir := direction
	if dir.length_squared() < 1e-8:
		dir = Vector3.UP
	dir = dir.normalized()
	var up := Vector3.UP
	if absf(dir.y) > 0.999:
		up = Vector3.FORWARD
	return Transform3D(Basis.looking_at(-dir, up), dir * 4.0)


## Everything that is *not* eased - the labels, the nested sun dictionary and
## the particle amounts - is copied straight across, so the discs and the fog
## never freeze on their first value.
func _sync_static() -> void:
	for key in _target:
		if not EASED_KEYS.has(key):
			_current[key] = _target[key]


static func _ease(prev, next, t: float):
	if prev is Color:
		return (prev as Color).lerp(next, t)
	if prev is Vector3:
		return (prev as Vector3).lerp(next, t)
	if prev is bool:
		return next
	if prev is String:
		return next
	return lerpf(float(prev), float(next), t)


# --- built objects --------------------------------------------------------

## A dome of billboarded dots. Kept as one MultiMesh so the whole night sky is
## a single draw call, and faded purely by the material's alpha.
func _build_stars() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20240926
	var quad := QuadMesh.new()
	quad.size = Vector2(0.14, 0.14)

	_star_mat = StandardMaterial3D.new()
	_star_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_star_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_star_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_star_mat.billboard_keep_scale = true
	_star_mat.vertex_color_use_as_albedo = true
	_star_mat.disable_receive_shadows = true
	_star_mat.albedo_texture = _disc_texture(24, Color(1, 1, 1), Color("a9bbe8"), 2)
	_star_mat.albedo_color = Color(1, 1, 1, 0)
	quad.material = _star_mat

	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.use_colors = true
	multi.mesh = quad
	multi.instance_count = STAR_COUNT

	var placed := 0
	while placed < STAR_COUNT:
		# Uniform over the sphere, then reject everything below the horizon and
		# a little above it, so the dome hugs the water rather than the floor.
		var theta := TAU * rng.randf()
		var z := rng.randf_range(-1.0, 1.0)
		var r := sqrt(maxf(0.0, 1.0 - z * z))
		var dir := Vector3(r * cos(theta), z, r * sin(theta))
		if dir.y < 0.035:
			continue
		var scale := rng.randf_range(0.45, 1.5)
		var warmth := rng.randf()
		var tint := Color(1, 1, 1).lerp(Color("cfe0ff"), warmth) \
			.lerp(Color("ffe6c9"), rng.randf() * 0.25)
		multi.set_instance_transform(placed, Transform3D(
			Basis().scaled(Vector3(scale, scale, scale)), dir * STAR_RADIUS))
		multi.set_instance_color(placed, tint)
		placed += 1

	_stars = MultiMeshInstance3D.new()
	_stars.name = "StarDome"
	_stars.multimesh = multi
	_stars.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_stars.visible = false
	add_child(_stars)


## A soft round disc for the sun or the moon, drawn as a billboard.
func _build_disc(size: float, inner: Color, edge: Color, softness: int) -> Sprite3D:
	var tex := _disc_texture(64, inner, edge, softness)
	var sprite := Sprite3D.new()
	sprite.texture = tex
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.pixel_size = size / 64.0
	sprite.shaded = false
	sprite.no_depth_test = false
	sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sprite.modulate = Color(1, 1, 1, 0)
	sprite.visible = false
	add_child(sprite)
	return sprite


static func _disc_texture(
		size: int, inner: Color, edge: Color, softness: int) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var half := float(size) * 0.5
	for py in size:
		for px in size:
			var dx := (float(px) + 0.5 - half) / half
			var dy := (float(py) + 0.5 - half) / half
			var d := sqrt(dx * dx + dy * dy)
			var core := 1.0 - smoothstep(0.55, 1.0, d)
			var halo := pow(maxf(0.0, 1.0 - d), float(softness)) * 0.5
			var c := inner.lerp(edge, clampf((d - 0.35) / 0.65, 0.0, 1.0))
			img.set_pixel(px, py, Color(c.r, c.g, c.b, clampf(core + halo, 0.0, 1.0)))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)
