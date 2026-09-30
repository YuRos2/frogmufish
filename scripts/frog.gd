class_name Frog
extends StaticBody3D

## The frog mokugyo, rebuilt from the `froggreen` companion model.
##
## The froggreen frog ships as separate head, jaw, mouth-interior, eye, nose
## and blush meshes, plus the wooden striker that rests through the mouth. This
## scene keeps the frog parts and hides the striker (the mallet is its own
## scene); the visible model reacts to every hit while the collision never
## moves.
##
## Two things make the rebuild different from the old one-shell frog:
##
## * the **jaw** is a real mesh, so `chomp()` can drop it open and snap it shut
##   around the striker. The jaw is re-parented under a hinge pivot at load so
##   the rotation happens at the back of the mouth rather than at the body.
## * the **eyes** are already black spheres, so a blink is a squash of the eye
##   node itself instead of a squashed pupil.
##
## On top of the strike reaction the frog has *moods*, which the pomodoro timer
## drives: attentive during a focus block, drowsy on a break, and a little show
## off when a focus block is finished. The moods only touch `Model` and
## `FrogMesh`, so the physics body is untouched.

enum Mood { IDLE, FOCUS, CHEER, BREAK, WAKE }

const SQUASH := Vector3(1.05, 0.94, 1.05)
const RECOVER := 0.20

## Blink: the eyes are small black ellipsoids sitting on the green bumps, so
## collapsing them right down is what reads as a closed eye. Squashing only one
## axis would leave a black slit or ring behind; the whole eye has to go.
const BLINK_SQUASH := 0.02
const BLINK_CLOSE := 0.06
const BLINK_HOLD := 0.04
const BLINK_OPEN := 0.22

## Eye targets per mood: normal, half closed for a nap, wide for excitement.
const EYE_OPEN := 1.0
const EYE_DROWSY := 0.42
const EYE_WIDE := 1.22

## The jaw hinge, in the frog model's own (unscaled) units. It sits at the back
## of the mouth slit, so the lower jaw swings open around it the way a real one
## would.
const JAW_HINGE := Vector3(0.0, 0.70, -0.50)

## How far the jaw drops for a full-strength tap, in radians. Positive X lifts
## the front of the jaw down.
const MOUTH_OPEN := 0.30

## The frog is turned a touch towards the clock instead of facing dead ahead,
## but only a little: any more and perspective makes one eye look bigger.
const BASE_YAW := -0.07

## A finished focus block rains lotus petals, not square confetti: the pond is
## a lotus pond, so the reward matches the scene. The three pinks are the same
## ones the mallet bud uses.
const PETAL_COLOURS := [
	Palette.PETAL_CORE, Palette.PETAL, Palette.PETAL_DEEP,
]

@onready var model: Node3D = $Model
@onready var mesh: Node3D = $Model/Scaled/FrogMesh

var mood: int = Mood.IDLE
## How many petal bursts have been thrown. Monotonic, so a test can prove the
## celebration really did sow petals.
var petal_bursts := 0

var _eyes: Array[Node3D] = []
var _highlights: Array[Node3D] = []
var _jaw_pivot: Node3D
var _tween: Tween
var _blink: Tween
var _chomp: Tween
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
	_hide_striker()
	_setup_jaw()
	_setup_eyes()
	model.rotation.y = BASE_YAW


## The mallet is imported from the same GLB, so keep only the frog pieces here.
func _hide_striker() -> void:
	for node in mesh.find_children("*", "MeshInstance3D", true, false):
		if node.name.begins_with("Striker"):
			(node as MeshInstance3D).visible = false


## Wraps the lower jaw in a pivot placed at the hinge, so `chomp()` can rotate
## it about the back of the mouth. The jaw keeps its pose; only its parent
## changes.
func _setup_jaw() -> void:
	var jaw := mesh.find_child("Frog_Jaw", true, false) as Node3D
	if jaw == null:
		return
	var parent := jaw.get_parent()
	_jaw_pivot = Node3D.new()
	_jaw_pivot.name = "JawPivot"
	_jaw_pivot.position = JAW_HINGE
	parent.add_child(_jaw_pivot)
	jaw.reparent(_jaw_pivot, true)


## Collects the two eye meshes the blink and the mood tweens both drive, plus
## their white catchlights, which have to vanish with the eye.
func _setup_eyes() -> void:
	for name in ["Eye_L", "Eye_R"]:
		var eye := mesh.find_child(name, true, false) as Node3D
		if eye != null:
			_eyes.append(eye)
	for name in ["EyeHL_L", "EyeHL_R"]:
		var hl := mesh.find_child(name, true, false) as Node3D
		if hl != null:
			_highlights.append(hl)


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


## Focus block finished: hop, go wide-eyed and throw lotus petals.
func celebrate() -> void:
	play_mood(Mood.CHEER, 2.4, Mood.BREAK)
	_spawn_petals()
	_do_hop(0.035)
	_do_wiggle()


## Break: settle down for a nap, pupils half closed and slower breathing.
func rest() -> void:
	set_mood(Mood.BREAK)


## Break over: wake up, stretch and go wide-eyed before focusing again.
func wake() -> void:
	play_mood(Mood.WAKE, 1.6, Mood.FOCUS)
	_do_hop(0.012)


## A quick cheer used for merit milestones - no petals, just a happy hop.
func cheer() -> void:
	_do_hop(0.038)
	_do_wiggle()


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


## Eases the eyes to whatever the current mood asks for.
func _sweep_eyes() -> void:
	if _blink != null and _blink.is_valid():
		_blink.kill()
	if _mood_tween != null and _mood_tween.is_valid():
		_mood_tween.kill()
	_mood_tween = create_tween().set_parallel(true)
	for eye in _eyes:
		# Tween the whole scale, not just `z`: a mood change that interrupts a
		# blink must not leave the eye stuck at its collapsed size.
		_mood_tween.tween_property(eye, "scale", Vector3(1.0, 1.0, _eye_target()), 0.35) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	for hl in _highlights:
		_mood_tween.tween_property(hl, "scale", Vector3.ONE, 0.35) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


# --- strike reaction ------------------------------------------------------

## Called by the main scene on every landed strike. The frog squashes, blinks
## and - the reason this rebuild exists - chomps its open jaw shut around the
## striker that rests in its mouth.
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
	chomp(s)


## Drops the jaw open and snaps it shut: one mokugyo mouth action. Repeated
## taps restart the tween cleanly rather than stacking.
func chomp(strength := 1.0) -> void:
	if _jaw_pivot == null:
		return
	if _chomp != null and _chomp.is_valid():
		_chomp.kill()
	var open := MOUTH_OPEN * clampf(strength, 0.45, 1.0)
	_chomp = create_tween()
	_chomp.tween_property(_jaw_pivot, "rotation:x", open, 0.055) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_chomp.tween_property(_jaw_pivot, "rotation:x", 0.0, 0.10) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func blink() -> void:
	if _blink != null and _blink.is_valid():
		_blink.kill()
	if _mood_tween != null and _mood_tween.is_valid():
		_mood_tween.kill()
	_blink = create_tween().set_parallel(true)
	for eye in _eyes:
		_blink.tween_property(eye, "scale", Vector3.ONE * BLINK_SQUASH, BLINK_CLOSE) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		_blink.tween_property(eye, "scale", Vector3(1.0, 1.0, _eye_target()), BLINK_OPEN) \
			.set_delay(BLINK_CLOSE + BLINK_HOLD) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	for hl in _highlights:
		_blink.tween_property(hl, "scale", Vector3.ONE * BLINK_SQUASH, BLINK_CLOSE) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		_blink.tween_property(hl, "scale", Vector3.ONE, BLINK_OPEN) \
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


## A quick happy wiggle for celebrations - just the visible model, no physics.
func _do_wiggle() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(model, "rotation:y", BASE_YAW + 0.18, 0.12)
	_tween.tween_property(model, "rotation:y", BASE_YAW - 0.18, 0.12).set_delay(0.12)
	_tween.tween_property(model, "rotation:y", BASE_YAW, 0.12).set_delay(0.24)


## A one-shot shower of lotus petals over the frog's head. The petals are a
## small hand-built mesh rather than flat squares, so they flutter and turn
## edge-on as they fall the way real petals do.
func _spawn_petals() -> void:
	petal_bursts += 1
	var particles := CPUParticles3D.new()
	particles.name = "Petals"
	particles.position = Vector3(0.0, 0.135, 0.02)
	particles.one_shot = true
	particles.emitting = false
	particles.amount = 45
	particles.lifetime = 2.4
	particles.explosiveness = 0.9
	particles.direction = Vector3(0.18, 1.0, 0.12).normalized()
	particles.spread = 68.0
	particles.gravity = Vector3(0.0, -0.95, 0.0)
	particles.initial_velocity_min = 0.45
	particles.initial_velocity_max = 1.05
	particles.angular_velocity_min = -260.0
	particles.angular_velocity_max = 260.0
	particles.scale_amount_min = 0.75
	particles.scale_amount_max = 1.35
	# Light drag: a petal is a sail, not a stone, so it drifts down slowly.
	particles.damping_min = 0.20
	particles.damping_max = 0.45

	var palette := Gradient.new()
	palette.colors = PackedColorArray(PETAL_COLOURS)
	palette.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	if "color_initial_ramp" in particles:
		particles.color_initial_ramp = palette
	else:
		particles.color = Palette.PETAL

	particles.mesh = _petal_mesh()
	add_child(particles)
	particles.emitting = true
	particles.finished.connect(particles.queue_free)


## One lotus petal: a thin, footed blade that is milky at the base and deep
## pink at the tip. Built from a small grid so the blade can be curved, and
## coloured per vertex (converted to linear, as the renderer expects).
func _petal_mesh() -> ArrayMesh:
	var rows := 7
	var cols := 5
	var length := 0.020
	var half := 0.0068
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var grid := []
	for i in rows:
		var t := float(i) / float(rows - 1)
		# The blade pinches to a point at both ends and is widest past the
		# middle, which is what makes a lotus petal read as one.
		var width := pow(sin(PI * clampf(t, 0.07, 0.98)), 0.72) * half
		var lift := sin(PI * t) * 0.0016
		var row := PackedVector3Array()
		for j in cols:
			var v := (float(j) / float(cols - 1) - 0.5) * 2.0
			# The edges curl back, so the blade is a shallow spoon rather
			# than a flat chip.
			row.append(Vector3(v * width, lift - absf(v) * absf(v) * 0.0028,
				t * length))
		grid.append(row)
	for i in rows - 1:
		var t := float(i) / float(rows - 1)
		var colour := _petal_colour(t).srgb_to_linear()
		var a: Vector3 = grid[i][0]
		for j in cols - 1:
			var b: Vector3 = grid[i][j + 1]
			var c: Vector3 = grid[i + 1][j + 1]
			var d: Vector3 = grid[i + 1][j]
			surface.set_color(colour)
			surface.add_vertex(a)
			surface.set_color(colour)
			surface.add_vertex(b)
			surface.set_color(colour)
			surface.add_vertex(c)
			surface.set_color(colour)
			surface.add_vertex(a)
			surface.set_color(colour)
			surface.add_vertex(c)
			surface.set_color(colour)
			surface.add_vertex(d)
			a = b
	surface.generate_normals()
	var petal := surface.commit()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	petal.surface_set_material(0, mat)
	return petal


static func _petal_colour(t: float) -> Color:
	var c := Palette.PETAL_CORE.lerp(Palette.PETAL, smoothstep(0.0, 0.5, t))
	return c.lerp(Palette.PETAL_DEEP, smoothstep(0.5, 1.0, t))
