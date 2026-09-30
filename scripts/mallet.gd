class_name Mallet
extends Node3D

## The striker, dressed as the wooden mallet that ships in the froggreen GLB.
##
## In the real toy the mallet lies **horizontally through the frog's mouth**:
## the ball head sits just outside the left cheek, the handle crosses the mouth
## slit and sticks out to the right. The rest pose is exactly that, and this
## scene animates the striker as a short scripted peck:
##
## 1. the mallet is pulled out of the mouth along its own axis,
## 2. lifted clear of the head,
## 3. cocked just above the crown,
## 4. taps the crown 10-20 times in a steady rhythm,
## 5. and is threaded back into the mouth.
##
## Because the motion is scripted rather than solver-driven, the striker can
## never get wedged in the frog, the stroke always stays inside the camera
## frame, and the final pose is always exact.

signal struck(at: Vector3, speed: float)

## How many taps one press of the auto-strike key plays.
const TAP_MIN := 10
const TAP_MAX := 20

## The tap is a short peck: the mallet is cocked just above and in front of the
## crown and drops onto it, so the whole stroke stays inside the camera frame.
const SWING_AIM := Vector3(0.017, 0.146, 0.006)
const READY_OFFSET := Vector3(0.028, 0.038, 0.034)
const READY_HANDLE := Vector3(0.34, 0.70, 0.62)
const IMPACT_HANDLE := Vector3(0.40, 1.0, 0.22)

## Where the striker waits while it is out of the frog. `EXTRACT_DIST` is how
## far it slides along its own axis to clear the lip; a horizontal striker
## swept straight up would drag its handle through the head.
const EXTRACT_DIST := 0.17
const LIFT_POS := Vector3(0.100, 0.175, 0.02)

const EXTRACT_TIME := 0.16
const LIFT_TIME := 0.15
const READY_TIME := 0.10
const DOWN_TIME := 0.11
const UP_TIME := 0.10
const GAP := 0.02

## The pose the mallet rests in, captured from the scene at load.
var rest_transform := Transform3D()

## What the last run did, so the randomness can be inspected by a harness.
var last_plan := {}

var _auto := false
var _ready_pos := Vector3.ZERO
var _ready_basis := Basis()
var _impact_pos := Vector3.ZERO
var _impact_basis := Basis()
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	rest_transform = transform
	_aim_swing(SWING_AIM)
	_rng.randomize()
	# This scene borrows the froggreen frog GLB for its striker, so keep only
	# the three Striker_* meshes and hide the frog.
	for node in find_children("*", "MeshInstance3D", true, false):
		if not node.name.begins_with("Striker"):
			(node as MeshInstance3D).visible = false


func is_held() -> bool:
	return _auto


## True only while a scripted run owns the striker.
func is_auto_striking() -> bool:
	return _auto


## Puts the striker straight back into its resting pose in the mouth.
func return_to_rest() -> void:
	_auto = false
	global_transform = rest_transform


## Pulls the striker out, plays `taps` rhythmic taps on the crown (a random
## 10-20 by default) and threads it back into the mouth. Pass `taps` and `seed`
## to pin the run down the way the test harness does.
func auto_strike(taps := 0, seed := -1) -> void:
	if _auto:
		return
	if seed >= 0:
		_rng.seed = seed
	if taps <= 0:
		taps = _rng.randi_range(TAP_MIN, TAP_MAX)

	_auto = true
	var plan: Array[Dictionary] = []
	last_plan = {"taps": taps, "plan": plan}

	var rest_basis := rest_transform.basis
	var rest_pos := rest_transform.origin
	var extract := rest_pos + rest_basis.x.normalized() * EXTRACT_DIST

	# Out of the mouth first: slide along the striker's own axis, then lift.
	await _move(extract, rest_basis, EXTRACT_TIME, Ease.OUT)
	if not _auto:
		return
	await _move(LIFT_POS, rest_basis, LIFT_TIME, Ease.OUT)
	if not _auto:
		return

	for _i in taps:
		if not _auto:
			return
		var aim := Vector3(
			SWING_AIM.x + _jitter(0.012), SWING_AIM.y,
			SWING_AIM.z + _jitter(0.010))
		var speed := _rng.randf_range(1.6, 2.8)
		plan.append({"aim": aim, "speed": speed})
		_aim_swing(aim)

		await _move(_ready_pos, _ready_basis, READY_TIME, Ease.OUT)
		if not _auto:
			return
		await _settle(GAP)

		# Down stroke: accelerate into the crown, and that stop is the tap.
		await _move(_impact_pos, _impact_basis, DOWN_TIME, Ease.IN)
		if not _auto:
			return
		struck.emit(global_position, speed)
		await _settle(0.015)
		await _move(_ready_pos, _ready_basis, UP_TIME, Ease.IN)
		if not _auto:
			return
		await _settle(GAP)

	# Back beside the frog, then re-thread the handle through the mouth.
	await _move(LIFT_POS, rest_basis, LIFT_TIME, Ease.OUT)
	if not _auto:
		return
	await _move(extract, rest_basis, 0.12, Ease.OUT)
	if not _auto:
		return
	await _move(rest_pos, rest_basis, EXTRACT_TIME, Ease.OUT)
	_auto = false
	global_transform = rest_transform


# --- scripted motion ------------------------------------------------------

enum Ease { SMOOTH, IN, OUT }

## Eases `global_transform` to a pose over `duration` seconds.
func _move(to_pos: Vector3, to_basis: Basis, duration: float, ease: int) -> void:
	var from := global_transform
	var q0 := from.basis.get_rotation_quaternion()
	var q1 := to_basis.get_rotation_quaternion()
	var elapsed := 0.0
	while elapsed < duration:
		var u := clampf(elapsed / duration, 0.0, 1.0)
		var e := _ease(u, ease)
		global_transform = Transform3D(
			Basis(q0.slerp(q1, e)), from.origin.lerp(to_pos, e))
		await get_tree().physics_frame
		elapsed += get_physics_process_delta_time()
	global_transform = Transform3D(to_basis, to_pos)


static func _ease(u: float, ease: int) -> float:
	match ease:
		Ease.IN:
			return u * u
		Ease.OUT:
			return 1.0 - (1.0 - u) * (1.0 - u)
		_:
			return u * u * (3.0 - 2.0 * u)


func _settle(seconds: float) -> void:
	var waited := 0.0
	while waited < seconds:
		await get_tree().physics_frame
		waited += get_physics_process_delta_time()


## Triangular jitter in [-spread, +spread]: most taps land near the middle of
## the crown and only a few reach its edges.
func _jitter(spread: float) -> float:
	return (_rng.randf() + _rng.randf() - 1.0) * spread


# --- pendulum geometry ----------------------------------------------------

## Recomputes this tap's cocked and impact poses. The tap always lands on the
## aim point with a nearly vertical handle; the cocked pose keeps the same ball
## offset but tilts the handle further forward, so the stroke reads as a wrist
## turn rather than a lift-and-drop.
func _aim_swing(aim: Vector3) -> void:
	_impact_pos = aim
	_ready_pos = aim + READY_OFFSET
	_impact_basis = _basis_from_x(IMPACT_HANDLE)
	_ready_basis = _basis_from_x(READY_HANDLE)


## A right-handed basis whose local +X (the handle) points along `x_axis`.
static func _basis_from_x(x_axis: Vector3) -> Basis:
	var x := x_axis.normalized()
	var z := x.cross(Vector3.UP)
	if z.length_squared() < 0.01:
		z = x.cross(Vector3.FORWARD)
	z = z.normalized()
	return Basis(x, z.cross(x), z)
