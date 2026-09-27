class_name Frog
extends StaticBody3D

## The frog mokugyo. Static, with a concave body shape so the mallet can pass
## through the mouth slot and rest on the lip.
##
## Only the visible model reacts to a hit; the collision never moves.
##
## On top of the strike reaction the frog has *moods*, which the pomodoro timer
## drives: attentive during a focus block, drowsy on a break, and a little show
## off when a focus block is finished. The moods only touch `Model` and
## `FrogMesh`, so the physics body is untouched.

enum Mood { IDLE, FOCUS, CHEER, BREAK, WAKE }

const SQUASH := Vector3(1.05, 0.94, 1.05)
const RECOVER := 0.20

## Blink: the pupils are their own nodes, so squashing them flat reads as a
## closed eye while the green eye bumps stay put.
const BLINK_SQUASH := 0.10
const BLINK_CLOSE := 0.06
const BLINK_HOLD := 0.04
const BLINK_OPEN := 0.22

## Eye targets per mood: normal, half closed for a nap, wide for excitement.
const EYE_OPEN := 1.0
const EYE_DROWSY := 0.42
const EYE_WIDE := 1.22

## The imported pupils are two different hand-sculpted caps - the right one is a
## teardrop - which reads as a wonky face. Both are replaced at load with one
## identical ellipsoid in the mirror-image position so the frog always looks
## straight ahead. Positions are averages of the two originals.
const PUPIL_SPACING := 0.0329
const PUPIL_Y := 0.1033
const PUPIL_Z := 0.0620
const PUPIL_RADIUS := 0.0093
const PUPIL_DEPTH := 0.68

## The frog is turned a touch towards the clock instead of facing dead ahead,
## but only a little: any more and perspective makes one eye look bigger.
const BASE_YAW := -0.07

const CONFETTI_COLOURS := [
	Palette.PINK, Palette.MINT, Palette.PEACH, Palette.SKY,
	Palette.LEMON, Palette.LAVENDER,
]

@onready var model: Node3D = $Model
@onready var mesh: Node3D = $Model/FrogMesh
@onready var pupils: Array[Node3D] = [
	$Model/FrogMesh/PupilL,
	$Model/FrogMesh/PupilR,
]

var mood: int = Mood.IDLE

var _tween: Tween
var _blink: Tween
var _mood_tween: Tween
var _hop: Tween
var _base_y := 0.0
var _breath := 0.0
var _breath_speed := 0.0
var _breath_amp := 0.0
var _tilt := 0.0
## A temporary mood (cheer, wake) plays for a moment and then falls back.
var _hold_until := 0
var _held_mood := Mood.IDLE
var _requested := Mood.IDLE


func _ready() -> void:
	_base_y = model.position.y
	_symmetrize_eyes()
	model.rotation.y = BASE_YAW


## Rebuilds both pupils from one shared ellipsoid at mirrored positions.
func _symmetrize_eyes() -> void:
	var mesh := SphereMesh.new()
	mesh.radius = PUPIL_RADIUS
	mesh.height = PUPIL_RADIUS * 2.04
	mesh.radial_segments = 24
	mesh.rings = 12
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("221f27")
	mat.roughness = 0.32
	mat.metallic = 0.0
	mesh.material = mat

	var sides := [-1.0, 1.0]
	for i in pupils.size():
		var pupil := pupils[i] as MeshInstance3D
		if pupil == null:
			continue
		pupil.mesh = mesh
		pupil.position = Vector3(sides[i] * PUPIL_SPACING, PUPIL_Y, PUPIL_Z)
		pupil.rotation = Vector3.ZERO
		pupil.scale = Vector3(1.0, 1.0, PUPIL_DEPTH)


func _process(delta: float) -> void:
	if _hold_until > 0 and Time.get_ticks_msec() >= _hold_until:
		_hold_until = 0
		if _requested == Mood.CHEER or _requested == Mood.WAKE:
			_requested = _held_mood
		_apply_mood(_requested)
	if _breath_amp <= 0.0:
		return
	_breath += delta * _breath_speed
	var swell := sin(_breath * TAU) * _breath_amp
	mesh.scale = Vector3(1.0 - swell * 0.35, 1.0 + swell, 1.0 - swell * 0.35)
	model.rotation.z = _tilt


# --- moods ----------------------------------------------------------------

## Sets the long-lived mood the frog settles into. Ignored while a temporary
## mood (cheer or wake) is still playing, which is remembered instead.
func set_mood(value: int) -> void:
	_requested = value
	if Time.get_ticks_msec() < _hold_until:
		return
	_apply_mood(value)


## Plays a short, showy mood and then falls back to `fallback`.
func play_mood(value: int, seconds: float, fallback: int) -> void:
	_held_mood = fallback
	_hold_until = Time.get_ticks_msec() + int(seconds * 1000.0)
	_requested = value
	_apply_mood(value)


## Focus block finished: hop, go wide-eyed and throw confetti.
func celebrate() -> void:
	play_mood(Mood.CHEER, 2.4, Mood.BREAK)
	_spawn_confetti()
	_do_hop()


## Break: settle down for a nap, pupils half closed and slower breathing.
func rest() -> void:
	set_mood(Mood.BREAK)


## Break over: wake up, stretch and go wide-eyed before focusing again.
func wake() -> void:
	play_mood(Mood.WAKE, 1.6, Mood.FOCUS)
	_do_hop(0.012)


func _apply_mood(value: int) -> void:
	mood = value
	match value:
		Mood.FOCUS:
			_breath_speed = 1.45
			_breath_amp = 0.012
			_tilt = 0.0
		Mood.BREAK:
			_breath_speed = 0.55
			_breath_amp = 0.024
			_tilt = 0.10
		Mood.CHEER, Mood.WAKE:
			_breath_speed = 2.6
			_breath_amp = 0.020
			_tilt = 0.0
		_:
			_breath_amp = 0.0
			_tilt = 0.0
	if value == Mood.IDLE:
		model.rotation.z = 0.0
		mesh.scale = Vector3.ONE
	_sweep_eyes()


func _eye_target() -> float:
	match mood:
		Mood.BREAK:
			return EYE_DROWSY
		Mood.CHEER, Mood.WAKE:
			return EYE_WIDE
		_:
			return EYE_OPEN


## Eases the pupils to whatever the current mood asks for.
func _sweep_eyes() -> void:
	if _blink != null and _blink.is_valid():
		_blink.kill()
	if _mood_tween != null and _mood_tween.is_valid():
		_mood_tween.kill()
	_mood_tween = create_tween().set_parallel(true)
	for pupil in pupils:
		_mood_tween.tween_property(pupil, "scale:y", _eye_target(), 0.35) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


# --- strike reaction ------------------------------------------------------

## Called by the main scene on every landed strike.
func thump(strength: float) -> void:
	var s := clampf(strength, 0.0, 1.0)
	if mood == Mood.BREAK:
		s *= 0.55
	if _tween != null and _tween.is_valid():
		_tween.kill()
	model.scale = Vector3.ONE.lerp(SQUASH, s)
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(model, "scale", Vector3.ONE, RECOVER) \
		.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	blink()


func blink() -> void:
	if _blink != null and _blink.is_valid():
		_blink.kill()
	if _mood_tween != null and _mood_tween.is_valid():
		_mood_tween.kill()
	_blink = create_tween().set_parallel(true)
	for pupil in pupils:
		_blink.tween_property(pupil, "scale:y", BLINK_SQUASH, BLINK_CLOSE) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		_blink.tween_property(pupil, "scale:y", _eye_target(), BLINK_OPEN) \
			.set_delay(BLINK_CLOSE + BLINK_HOLD) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func is_blinking() -> bool:
	return _blink != null and _blink.is_valid() and _blink.is_running()


# --- little show ----------------------------------------------------------

## A couple of happy hops. The collision body never moves, only the model.
func _do_hop(height := 0.026) -> void:
	if _hop != null and _hop.is_valid():
		_hop.kill()
	model.position.y = _base_y
	_hop = create_tween()
	_hop.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	for i in 2:
		_hop.tween_property(model, "position:y", _base_y + height, 0.16)
		_hop.tween_property(model, "position:y", _base_y, 0.22) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


## A one-shot puff of macaron confetti over the frog's head.
func _spawn_confetti() -> void:
	var particles := CPUParticles3D.new()
	particles.name = "Confetti"
	particles.position = Vector3(0.0, 0.135, 0.02)
	particles.one_shot = true
	particles.emitting = false
	particles.amount = 54
	particles.lifetime = 1.5
	particles.explosiveness = 0.92
	particles.direction = Vector3(0.0, 1.0, 0.0)
	particles.spread = 62.0
	particles.gravity = Vector3(0.0, -1.6, 0.0)
	particles.initial_velocity_min = 0.55
	particles.initial_velocity_max = 1.15
	particles.angular_velocity_min = -420.0
	particles.angular_velocity_max = 420.0
	particles.scale_amount_min = 0.6
	particles.scale_amount_max = 1.3

	var palette := Gradient.new()
	palette.colors = PackedColorArray(CONFETTI_COLOURS)
	palette.offsets = PackedFloat32Array([0.0, 0.2, 0.4, 0.6, 0.8, 1.0])
	if "color_initial_ramp" in particles:
		particles.color_initial_ramp = palette
	else:
		particles.color = Palette.PINK

	var quad := QuadMesh.new()
	quad.size = Vector2(0.012, 0.008)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	quad.material = mat
	particles.mesh = quad

	add_child(particles)
	particles.emitting = true
	particles.finished.connect(particles.queue_free)
