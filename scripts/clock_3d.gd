class_name Clock3D
extends Node3D

## A macaron-pastel 3D alarm clock that doubles as the pomodoro display.
##
## The analog hands show the real time of day, so a pupil always knows what
## o'clock it is. The digital panel under the hands and the ring of dots inside
## the bezel show the pomodoro phase and how much of it is left.
##
## The model is built procedurally from Godot primitives: no downloaded asset,
## no licence to track, and the whole palette can be re-themed from
## `palette.gd`. To swap in a downloaded GLB instead, drop it as a child of
## `Model` - the builder notices the container is not empty and leaves it alone.

# --- geometry (metres, local to this node) --------------------------------
const BASE_Y := 0.098           # top of the pedestal
const FACE_Y := BASE_Y + 0.075
const FACE_Z := 0.021
const BELL_Y := FACE_Y + 0.084
const NUMERAL_RADIUS := 0.0315
const NUMERAL_FONT := 28
const NUMERAL_PIXEL := 0.00042
const RING_RADIUS := 0.045
const DOT_COUNT := 24

const RING_BELL_HZ := 14.0
const RING_MAX_TILT := 0.42

## The clock is not placed square-on: it leans and slowly sways so it reads as
## a lively hovering object rather than a diagram. The sway is added on top of
## whatever transform the scene places it with.
const BASE_TILT_Z := -0.12
const BASE_YAW := 0.30
const SWAY_YAW := 0.07
const SWAY_TILT := 0.028

@onready var model: Node3D = $Model

var _face: MeshInstance3D
var _bezel: MeshInstance3D
var _body: Node3D
var _bells: Array[Node3D] = []
var _hour_pivot: Node3D
var _minute_pivot: Node3D
var _second_pivot: Node3D
var _dots: MultiMeshInstance3D
var _phase_label: Label3D
var _face_mat: StandardMaterial3D

var _progress := 0.0
var _ring_left := 0.0
var _ring_power := 0.0
var _flash := 0.0
var _bob := 0.0
var _accent: Color = Palette.IDLE
var _cj_font: SystemFont


func _ready() -> void:
	_cj_font = _make_cjk_font()
	if model.get_child_count() == 0:
		_build()
	set_phase(Pomodoro.Phase.IDLE, 25 * 60)


func _process(delta: float) -> void:
	# A slow hover and sway, so the clock reads as a friendly magical object
	# rather than a prop stuck in mid-air.
	_bob += delta * 1.1
	model.position.y = sin(_bob) * 0.008
	model.position.x = cos(_bob * 0.6) * 0.004
	model.rotation.y = BASE_YAW + sin(_bob * 0.5 + 1.0) * SWAY_YAW
	model.rotation.z = BASE_TILT_Z + sin(_bob * 0.78) * SWAY_TILT
	_update_clock_hands()
	_update_ring(delta)
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta * 2.2)
		if _face_mat != null:
			_face_mat.emission_energy_multiplier = 0.10 + _flash * 0.85


# --- public API -----------------------------------------------------------

## Switches the face, dot ring and phase banner over to a new pomodoro phase.
func set_phase(phase: int, _duration: float) -> void:
	_accent = Pomodoro.phase_accent(phase)
	_progress = 0.0
	if _phase_label != null:
		_phase_label.text = Pomodoro.phase_title(phase)
		_phase_label.modulate = _accent
	if _face_mat != null:
		_face_mat.emission = _accent
	if _bezel != null:
		var bezel_mat := _bezel.material_override as StandardMaterial3D
		if bezel_mat != null:
			bezel_mat.albedo_color = _accent
	_update_dots()
	ring(0.7, 0.45)


func set_remaining(remaining: float, progress: float) -> void:
	_progress = clampf(progress, 0.0, 1.0)
	_update_dots()


func set_paused(value: bool) -> void:
	if _phase_label != null:
		_phase_label.modulate.a = 0.45 if value else 1.0
	if _face_mat != null:
		_face_mat.emission_energy_multiplier = 0.02 if value else 0.10


## How far through the current phase the dot ring is (0..1).
func progress() -> float:
	return _progress


## The phase name shown on the floating banner, for tests and screenshots.
func phase_text() -> String:
	return "" if _phase_label == null else _phase_label.text


## Shakes the bells and rattles the dial. `power` scales the movement, so a
## short break can chime softly while the end of a focus block goes wild.
func ring(seconds := 1.2, power := 1.0) -> void:
	_ring_left = maxf(_ring_left, seconds)
	_ring_power = maxf(_ring_power, power)


func celebrate() -> void:
	ring(1.8, 1.0)
	_flash = 1.0


# --- building -------------------------------------------------------------

func _build() -> void:
	# Body drum (axis along +Z) with the dial recessed a little in front of it.
	_body = Node3D.new()
	_body.name = "Dial"
	model.add_child(_body)
	_add_mesh(_body, _cyl(0.056, 0.030, Palette.PEACH), Vector3(0, FACE_Y, 0), _face_rotation())
	_add_mesh(_body, _cyl(0.050, 0.034, Palette.CREAM), Vector3(0, FACE_Y, 0.002), _face_rotation())
	_face = _add_mesh(_body, _cyl(0.048, 0.005, Palette.CREAM),
		Vector3(0, FACE_Y, FACE_Z + 0.002), _face_rotation())
	_face_mat = _face.material_override as StandardMaterial3D
	_face_mat.emission_enabled = true
	_face_mat.emission = Palette.IDLE
	_face_mat.emission_energy_multiplier = 0.10

	# Bezel and the ring of progress dots just inside it.
	_bezel = _add_mesh(_body, _torus(0.049, 0.063, Palette.MINT),
		Vector3(0, FACE_Y, FACE_Z), _face_rotation())
	_dots = _build_dot_ring(_body)

	# Hour numerals, flat on the dial, so the clock can actually be read as the
	# local time. They sit inside the dot ring and the hands sweep over them.
	for i in range(1, 13):
		var a := TAU * float(i) / 12.0
		_make_numeral(_body, str(i), Vector3(
			sin(a) * NUMERAL_RADIUS, FACE_Y + cos(a) * NUMERAL_RADIUS,
			FACE_Z + 0.0065))

	# Hands: dark hour and minute, plus a brighter second hand with a tail so
	# its sweep is obvious.
	_hour_pivot = _make_hand(_body, "HourHand", 0.013, 0.030, Palette.PLUM)
	_minute_pivot = _make_hand(_body, "MinuteHand", 0.009, 0.042, Palette.PLUM)
	_second_pivot = _make_hand(_body, "SecondHand", 0.0032, 0.050, Palette.ROSE, 0.013)
	_add_mesh(_body, _sphere(0.0065, Palette.LAVENDER_DEEP),
		Vector3(0, FACE_Y, FACE_Z + 0.008))
	_add_mesh(_body, _sphere(0.0035, Palette.CREAM),
		Vector3(0, FACE_Y, FACE_Z + 0.012))

	# Two bells and a hammer, the classic alarm-clock silhouette.
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		var bell := Node3D.new()
		bell.name = "Bell%d" % i
		bell.position = Vector3(side * 0.042, BELL_Y, 0.0)
		_body.add_child(bell)
		var shell := _add_mesh(bell, _sphere(0.022, Palette.PINK if i == 0 else Palette.SKY),
			Vector3.ZERO)
		shell.scale = Vector3(1.0, 1.0, 0.78)
		_add_mesh(bell, _cyl(0.006, 0.006, Palette.CREAM), Vector3(0, -0.020, 0.0))
		_bells.append(bell)
	_add_mesh(_body, _cyl(0.004, 0.028, Palette.LAVENDER_DEEP),
		Vector3(0, BELL_Y - 0.020, 0.0))
	_add_mesh(_body, _sphere(0.007, Palette.LEMON_DEEP), Vector3(0, BELL_Y, 0.0))

	# Phase banner above the bells. The countdown itself is not repeated here -
	# it lives in the HUD's timer panel and in the dot ring.
	_phase_label = _make_label(model, Vector3(0, BELL_Y + 0.054, 0.006),
		40, 0.00078, Palette.IDLE)


func _make_hand(parent: Node3D, hand_name: String, width: float, length: float,
		color: Color, tail := 0.0) -> Node3D:
	var pivot := Node3D.new()
	pivot.name = hand_name
	pivot.position = Vector3(0, FACE_Y, FACE_Z + 0.007)
	parent.add_child(pivot)
	var mesh := BoxMesh.new()
	mesh.size = Vector3(width, length, 0.005)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _mat(color)
	mi.position = Vector3(0, length * 0.5 - 0.006, 0)
	pivot.add_child(mi)
	if tail > 0.0:
		var tail_mesh := BoxMesh.new()
		tail_mesh.size = Vector3(width, tail, 0.005)
		var tail_mi := MeshInstance3D.new()
		tail_mi.mesh = tail_mesh
		tail_mi.material_override = _mat(color)
		tail_mi.position = Vector3(0, -tail * 0.5 + 0.004, 0)
		pivot.add_child(tail_mi)
	return pivot


## A flat hour numeral, parented to the dial so it turns with it.
func _make_numeral(parent: Node3D, text: String, pos: Vector3) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.position = pos
	label.font = _cj_font
	label.font_size = NUMERAL_FONT
	label.pixel_size = NUMERAL_PIXEL
	label.modulate = Palette.PLUM
	label.outline_modulate = Palette.CREAM
	label.outline_size = 8
	label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	label.double_sided = false
	parent.add_child(label)
	return label


func _build_dot_ring(parent: Node3D) -> MultiMeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = 0.0038
	mesh.height = 0.0076
	mesh.radial_segments = 12
	mesh.rings = 6
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = DOT_COUNT
	for i in DOT_COUNT:
		var a := TAU * float(i) / float(DOT_COUNT)
		var pos := Vector3(
			sin(a) * RING_RADIUS, FACE_Y + cos(a) * RING_RADIUS, FACE_Z + 0.004)
		mm.set_instance_transform(i, Transform3D(Basis(), pos))
		mm.set_instance_color(i, Palette.LAVENDER)
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "ProgressDots"
	mmi.multimesh = mm
	var mat := _mat(Palette.CREAM)
	mat.vertex_color_use_as_albedo = true
	mat.emission_enabled = true
	mat.emission = Palette.CREAM
	mat.emission_energy_multiplier = 0.35
	mmi.material_override = mat
	parent.add_child(mmi)
	return mmi


func _update_dots() -> void:
	if _dots == null:
		return
	var mm := _dots.multimesh
	var filled := int(round(_progress * DOT_COUNT))
	for i in DOT_COUNT:
		mm.set_instance_color(i, _accent if i < filled else Palette.LAVENDER)


func _make_label(parent: Node3D, pos: Vector3, size: int, pixel: float,
		color: Color) -> Label3D:
	var label := Label3D.new()
	label.position = pos
	label.font = _cj_font
	label.font_size = size
	label.pixel_size = pixel
	label.modulate = color
	label.outline_modulate = Palette.PLUM
	label.outline_size = 12
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.double_sided = false
	parent.add_child(label)
	return label


# --- per-frame ------------------------------------------------------------

func _update_clock_hands() -> void:
	if _hour_pivot == null:
		return
	# Local wall-clock time; the fractional second makes the second hand sweep
	# smoothly instead of stepping once per second.
	var t := Time.get_time_dict_from_system()
	var frac := fmod(Time.get_unix_time_from_system(), 1.0)
	var sec := float(t.get("second", 0)) + frac
	var minute := float(t.get("minute", 0)) + sec / 60.0
	var hour := float(int(t.get("hour", 0)) % 12) + minute / 60.0
	_second_pivot.rotation.z = -TAU * sec / 60.0
	_minute_pivot.rotation.z = -TAU * minute / 60.0
	_hour_pivot.rotation.z = -TAU * hour / 12.0


func _update_ring(delta: float) -> void:
	if _bells.is_empty():
		return
	if _ring_left <= 0.0:
		for bell in _bells:
			bell.rotation.z = 0.0
		if _body != null:
			_body.rotation.z = 0.0
		_ring_power = 0.0
		return
	_ring_left = maxf(0.0, _ring_left - delta)
	var envelope := clampf(_ring_left * 1.6, 0.0, 1.0) * _ring_power
	var phase := Time.get_ticks_msec() * 0.001 * TAU * RING_BELL_HZ
	var wave := sin(phase) * RING_MAX_TILT * envelope
	for i in _bells.size():
		_bells[i].rotation.z = wave * (1.0 if i == 0 else -1.0)
	if _body != null:
		_body.rotation.z = sin(phase + 0.9) * 0.05 * envelope


# --- small builders -------------------------------------------------------

static func _face_rotation() -> Vector3:
	# Primitive cylinders and tori are built around +Y; the clock faces +Z.
	return Vector3(PI * 0.5, 0.0, 0.0)


static func _mat(color: Color, emission := Color(0, 0, 0, 0), energy := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.5
	m.metallic = 0.0
	if emission.a > 0.0:
		m.emission_enabled = true
		m.emission = emission
		m.emission_energy_multiplier = energy
	return m


func _add_mesh(parent: Node3D, mesh: Mesh, pos: Vector3,
		rotation := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mesh.surface_get_material(0)
	mi.position = pos
	mi.rotation = rotation
	parent.add_child(mi)
	return mi


static func _cyl(radius: float, height: float, color: Color) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = radius
	m.bottom_radius = radius
	m.height = height
	m.radial_segments = 32
	m.material = _mat(color)
	return m


static func _torus(inner: float, outer: float, color: Color) -> TorusMesh:
	var m := TorusMesh.new()
	m.inner_radius = inner
	m.outer_radius = outer
	m.rings = 40
	m.ring_segments = 16
	m.material = _mat(color)
	return m


static func _sphere(radius: float, color: Color) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = radius
	m.height = radius * 2.0
	m.radial_segments = 24
	m.rings = 12
	m.material = _mat(color)
	return m


static func _make_cjk_font() -> SystemFont:
	var f := SystemFont.new()
	f.font_names = PackedStringArray([
		"Microsoft YaHei UI", "Microsoft YaHei", "PingFang SC",
		"Noto Sans CJK SC", "Source Han Sans SC", "SimHei",
		"Arial Unicode MS", "Sans-Serif",
	])
	f.allow_system_fallback = true
	return f
