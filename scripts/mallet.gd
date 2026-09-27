class_name Mallet
extends RigidBody3D

## The striker.
##
## It lies on the table next to the frog, ball towards the frog and handle
## angled away. Nothing holds it there, so a scripted swing is free to pick it
## up, tap the frog's crown and set it back down without any special-casing:
## the solver resolves every contact on the way, which is what stops the mallet
## from being pushed through the frog while it is being driven.
##
## While held the body is driven by a velocity controller instead of being
## teleported, so those contacts always get a say.

signal struck(at: Vector3, speed: float)

## Approach speed (m/s) needed for a hit to count, and the gap between hits.
const STRIKE_SPEED := 0.22
const STRIKE_COOLDOWN := 0.16

## Only contacts this close to the ball count as a strike. The ball's furthest
## point is 0.021 m from the origin, so the reach is deliberately a little
## wider than the ball itself: catching the handle right where it meets the
## ball still reads as a strike, and the rest of the handle never touches the
## frog anyway.
const HEAD_REACH := 0.032

## The ball must have been clear of the frog this long before a contact counts,
## so holding the mallet pressed against the frog is one tap, not a drum roll.
const CLEAR_TIME := 0.12

const POS_GAIN := 16.0
const ROT_GAIN := 14.0
const MAX_SPEED := 3.2
const MAX_SPIN := 22.0

## The scripted swing is a pendulum, not a lift-and-drop. A fixed grip point
## above the frog stands in for the player's hand, and the mallet rotates about
## it so the ball travels along an arc onto the crown the way a wrist-driven
## strike really does. Only the shape of the move lives here - every number that
## actually reaches the frog gets jittered.
const SWING_GRIP := 0.165        # distance from the ball to the grip point
const SWING_READY_ANGLE := 0.90  # how far back the mallet is cocked (radians)
const SWING_STRIKE_LEAN := 0.62  # handle tilt from vertical at impact
const GRIP_DIR := Vector3(0.35, 0.0, 0.94)  # which way the hand sits, in XZ
const SWING_BACK_Y := 0.290      # height the cocked mallet is carried at
const SWING_LIFT_Y := 0.235      # height it rises to before crossing to the frog

const SWING_SIDE := 0.004      # how far past its own spot it lifts, so it
							   # clears the frog on the way up
const SWING_AIM_X := 0.017     # the frog's crown, which the taps land on
const SWING_AIM_Z := 0.006
const SWING_TAP_Y := 0.132     # inside the frog's crown (0.1355), so the
							   # solver stops the ball as the tap lands

## Give up on a move once it has stopped getting closer for this long. That is
## how a tap ends: the frog stops the ball, and there is nothing left to drive.
const STALL_GIVE_UP := 0.18

## An auto swing is allowed to take this long before it is cut short, so a
## jammed mallet cannot leave the game stuck in a scripted move forever.
const SWING_TIMEOUT := 20.0

## The last stretch of the set-down is crawling, so the mallet does not bounce
## off the table and roll away from the spot it is supposed to rest in.
const SET_DOWN_SPEED := 0.28

## How well aligned the mallet must be before a move that depends on its
## orientation is allowed to continue.
const SWING_GRIP_TOLERANCE := 0.006

## Pose the mallet rests in, captured from the scene at load.
var rest_transform := Transform3D()

## The pendulum for the tap currently being played: where the "hand" holds the
## mallet, the axis it swings about and the handle direction at impact.
var _grip := Vector3.ZERO
var _axis := Vector3(0.0, 0.0, 1.0)
var _handle0 := Vector3(0.0, 1.0, 0.0)

## What the last scripted swing did: the tap count and each tap's aim, roll and
## impact speed. Written so the randomness can be inspected and tested rather
## than only felt.
var last_plan := {}

var _held := false
var _auto := false
## True only while the mallet is being dragged by the mouse; scripted moves
## (auto tap, tests) leave it false so they own `_desired` outright.
var _pointer_driven := false
var _cooldown := 0.0
var _plane := Plane()
var _grab_offset := Vector3.ZERO
var _hold_basis := Basis()
var _desired := Vector3.ZERO
var _approach := 0.0
var _clear := 1.0
## Ceiling on the controller's speed request. The scripted swing lowers it so
## some taps really do land softer than others.
var _speed_cap := MAX_SPEED
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	contact_monitor = true
	max_contacts_reported = 8
	continuous_cd = true
	rest_transform = transform
	_desired = global_position


## Takes the mallet in and out of scripted control.
##
## While the controller is driving, gravity has to be cancelled by hand: Godot
## applies it *after* `_integrate_forces` runs, so a driven body sags about
## 0.1 m/s, never quite reaching the pose the controller asks for, and drifts
## off the table on the way back down. Owning the whole integrator would fix
## that too, but it also hides the solver's contacts, which lets the ball sink
## into the frog. Cancelling gravity leaves collision response alone.
func set_held(value: bool) -> void:
	if _held == value:
		return
	_held = value
	can_sleep = not value
	if value:
		sleeping = false


func is_held() -> bool:
	return _held or _auto


## True only while a scripted swing (auto_strike) owns the mallet, as opposed
## to the player dragging it.
func is_auto_striking() -> bool:
	return _auto


func _unhandled_input(event: InputEvent) -> void:
	if _auto:
		return
	if event is InputEventMouseButton and event.is_action_pressed("grab_mallet"):
		# Take the pointer from the event rather than polling the live cursor, so
		# the ray that decides the grab is the one the player actually clicked.
		_try_grab((event as InputEventMouseButton).position)
	elif event.is_action_released("grab_mallet") and _held:
		release()


func _physics_process(delta: float) -> void:
	# A mallet asleep on the table cannot touch anything or be dragged, so its
	# cooldown does not need to keep ticking.
	if not _held and sleeping:
		return
	_cooldown = maxf(0.0, _cooldown - delta)
	if _pointer_driven and _held:
		_update_mouse_target()


# --- grabbing -------------------------------------------------------------

func _try_grab(pointer: Vector2) -> bool:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return false
	var from := cam.project_ray_origin(pointer)
	var query := PhysicsRayQueryParameters3D.create(
		from, from + cam.project_ray_normal(pointer) * 20.0)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty() or hit.get("collider") != self:
		return false
	return _begin_grab(cam, pointer)


func _begin_grab(cam: Camera3D, pointer: Vector2) -> bool:
	# Work in a plane through the mallet that faces the camera, so dragging
	# moves it sideways across the view instead of toward or away from it.
	_plane = Plane(-cam.global_transform.basis.z, global_position)
	var on_plane = _plane.intersects_ray(
		cam.project_ray_origin(pointer), cam.project_ray_normal(pointer))
	if on_plane == null:
		return false

	_grab_offset = global_position - (on_plane as Vector3)
	_hold_basis = global_transform.basis
	_desired = global_position
	set_held(true)
	_pointer_driven = true
	return true


func release() -> void:
	set_held(false)
	_auto = false
	_pointer_driven = false
	_speed_cap = MAX_SPEED


func _update_mouse_target() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var mouse := get_viewport().get_mouse_position()
	var on_plane = _plane.intersects_ray(
		cam.project_ray_origin(mouse), cam.project_ray_normal(mouse))
	if on_plane != null:
		_desired = (on_plane as Vector3) + _grab_offset


# --- motion ---------------------------------------------------------------

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	# Velocity carried in from the previous solve: the real closing speed, not
	# the speed the controller is asking for right now.
	var incoming := state.linear_velocity.length()
	if _held:
		state.sleeping = false
		state.linear_velocity = _limited(
			(_desired - state.transform.origin) * POS_GAIN, _speed_cap) \
			- state.total_gravity * state.step
		state.angular_velocity = _limited(
			_basis_error(state.transform.basis) * ROT_GAIN, MAX_SPIN)
	if state.get_contact_count() > 0:
		_scan_contacts(state, incoming)
	else:
		# Track the closing speed the whole time the ball is clear. It is the
		# speed carried into the next contact, and that is what decides whether
		# the contact counts as a hit - so it must not go stale between taps.
		_clear += state.step
		_approach = incoming


static func _limited(v: Vector3, limit: float) -> Vector3:
	var n := v.length()
	return v * (limit / n) if n > limit else v


## Shortest-arc axis-angle rotation from the current basis back to the
## orientation the mallet was grabbed in.
func _basis_error(b: Basis) -> Vector3:
	var q := _hold_basis.get_rotation_quaternion() * b.get_rotation_quaternion().inverse()
	if q.w < 0.0:
		q = Quaternion(-q.x, -q.y, -q.z, -q.w)
	var angle := q.get_angle()
	return Vector3.ZERO if angle < 0.0005 else q.get_axis() * angle


## Emits once when the ball arrives at the frog, then stays quiet until it has
## been pulled clear again.
func _scan_contacts(state: PhysicsDirectBodyState3D, incoming: float) -> void:
	var touching := false
	var hit_at := Vector3.ZERO
	for i in state.get_contact_count():
		var other := state.get_contact_collider_object(i)
		if other == null or not (other as Node).is_in_group("mokugyo"):
			continue
		var at := state.get_contact_local_position(i)
		if at.distance_to(state.transform.origin) > HEAD_REACH:
			continue
		touching = true
		hit_at = at

	if not touching:
		# Touching something that is not the frog still leaves the ball clear.
		_clear += state.step
		_approach = incoming
		return

	if _clear >= CLEAR_TIME and _approach >= STRIKE_SPEED and _cooldown <= 0.0:
		_cooldown = STRIKE_COOLDOWN
		struck.emit(hit_at, _approach)
	_clear = 0.0


# --- scripted moves -------------------------------------------------------

## Puts the mallet back on its spot beside the frog.
func return_to_rest() -> void:
	release()
	sleeping = false
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	global_transform = rest_transform
	_desired = global_position


## Swings the mallet in the air until the frog's crown stops the ball, one to
## three times, then sets it back down. Driven by the same controller as the
## mouse, so it obeys collisions the whole way.
##
## Every swing is different: `taps` defaults to a random 1..3, and each tap
## picks its own aim point on the crown, its own roll and its own impact speed.
## Pass an explicit `taps` and `seed` to pin it down (the test harness does).
func auto_strike(taps := 0, seed := -1) -> void:
	if _held or _auto:
		return
	if seed >= 0:
		_rng.seed = seed
	if taps <= 0:
		taps = _roll_taps()

	_auto = true
	set_held(true)
	_pointer_driven = false

	global_transform = rest_transform
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	sleeping = false
	_hold_basis = rest_transform.basis

	var base := rest_transform.origin
	var level := rest_transform.basis
	var plan: Array[Dictionary] = []
	last_plan = {"taps": taps, "plan": plan}
	await get_tree().physics_frame

	var deadline := Time.get_ticks_msec() + int(SWING_TIMEOUT * 1000.0)

	# Lift straight up beside the frog first. It has to clear the face before it
	# can travel across, or the ball clips the cheek on the way.
	await _drive_to(Vector3(base.x + SWING_SIDE, SWING_LIFT_Y, base.z), 0.010, 1.0)

	# Then swing it up into the cocked pose over the frog. The handle turns away
	# from the frog on the way, so it never sweeps through the face.
	_aim_swing(Vector3.ZERO)
	_hold_basis = _arc_basis(SWING_READY_ANGLE, 0.0)
	await _drive_to(_arc_point(SWING_READY_ANGLE), 0.010, 1.2)
	await _await_grip(1.2)

	for _tap in taps:
		if Time.get_ticks_msec() > deadline:
			break
		var aim := Vector3(
			_jitter(SWING_AIM_X), 0.0, SWING_AIM_Z + _jitter(0.008))
		var roll := _rng.randf_range(-0.22, 0.22)
		var speed := _rng.randf_range(1.5, 3.0)
		plan.append({"aim": aim, "roll": roll, "speed": speed})

		# Re-aim the pendulum at this tap's spot and settle at the top of it.
		_aim_swing(aim)
		_hold_basis = _arc_basis(SWING_READY_ANGLE, roll)
		await _drive_to(_arc_point(SWING_READY_ANGLE), 0.008, 0.9)
		await _await_grip(0.5)
		await _settle(_rng.randf_range(0.08, 0.16))

		# Swing down. A lower speed cap means a gentler hit; the frog stops the
		# ball at the crown, and that is the tap.
		_speed_cap = speed
		await _arc_sweep(SWING_READY_ANGLE, 0.0,
			clampf(0.26 / speed, 0.07, 0.20), roll, true)
		await _settle(_rng.randf_range(0.04, 0.09))
		_speed_cap = MAX_SPEED

		# Rebound back up to the cocked pose for the next tap.
		await _arc_sweep(0.0, SWING_READY_ANGLE, 0.24, roll, false)
		await _settle(_rng.randf_range(0.04, 0.09))

	# Carry it back beside the frog, level it out, and set it down gently so it
	# stays where the next swing expects to find it.
	_hold_basis = _arc_basis(SWING_READY_ANGLE, 0.0)
	await _drive_to(Vector3(base.x + SWING_SIDE, SWING_BACK_Y, base.z), 0.010, 1.0)
	_hold_basis = level
	await _await_grip(2.0)
	_speed_cap = SET_DOWN_SPEED
	await _drive_to(Vector3(base.x, base.y + 0.0015, base.z), 0.0020, 2.0)
	await _settle(0.20)
	_speed_cap = MAX_SPEED

	last_plan["ended_at"] = global_position
	set_held(false)
	_auto = false
	if global_position.distance_to(base) > 0.012:
		# The set-down still got away from it. Put the mallet back rather than
		# leave it lying somewhere new, and say so.
		push_warning("auto swing left the mallet at %s instead of at rest"
			% global_position)
		return_to_rest()


# --- pendulum geometry ----------------------------------------------------

## Recomputes the pendulum for one tap: the grip the "hand" holds, the axis the
## mallet swings about, and the handle direction at the moment of impact.
func _aim_swing(aim: Vector3) -> void:
	var flat := Vector3(GRIP_DIR.x, 0.0, GRIP_DIR.z).normalized()
	var ball := Vector3(aim.x, SWING_TAP_Y, aim.z)
	_handle0 = (flat * sin(SWING_STRIKE_LEAN)
		+ Vector3(0.0, 1.0, 0.0) * cos(SWING_STRIKE_LEAN)).normalized()
	_grip = ball + _handle0 * SWING_GRIP
	_axis = Vector3(0.0, 1.0, 0.0).cross(flat).normalized()


## Where the ball sits when the mallet has swung `angle` radians back from
## impact, with the grip held still.
func _arc_point(angle: float) -> Vector3:
	return _grip - _handle0.rotated(_axis, angle) * SWING_GRIP


## The mallet's orientation at that point, with an optional roll about the
## handle.
func _arc_basis(angle: float, roll: float) -> Basis:
	var handle := _handle0.rotated(_axis, angle)
	var b := _basis_from_x(handle)
	return b.rotated(handle, roll)


## A right-handed basis whose local +X (the handle) points along `x_axis`.
static func _basis_from_x(x_axis: Vector3) -> Basis:
	var x := x_axis.normalized()
	var z := x.cross(Vector3(0.0, 1.0, 0.0))
	if z.length_squared() < 0.01:
		z = x.cross(Vector3(0.0, 0.0, 1.0))
	z = z.normalized()
	return Basis(x, z.cross(x), z)


## Sweeps the mallet along its arc from one angle to another, easing the angle
## so the ball accelerates into the frog on the way down and eases off on the
## way back up.
func _arc_sweep(from_angle: float, to_angle: float, duration: float,
		roll: float, accelerate: bool) -> void:
	var elapsed := 0.0
	while elapsed < duration:
		var t := clampf(elapsed / duration, 0.0, 1.0)
		var eased := t * t if accelerate else 1.0 - (1.0 - t) * (1.0 - t)
		var angle := lerpf(from_angle, to_angle, eased)
		_hold_basis = _arc_basis(angle, roll)
		_desired = _arc_point(angle)
		await get_tree().physics_frame
		elapsed += get_physics_process_delta_time()
	_hold_basis = _arc_basis(to_angle, roll)
	_desired = _arc_point(to_angle)


## Triangular jitter in [-spread, +spread]: the mean of two uniforms, so most
## swings land near the middle of the crown and only a few reach its edges.
func _jitter(spread: float) -> float:
	return (_rng.randf() + _rng.randf() - 1.0) * spread


## 1..3 taps, weighted so a single tap is still the common case.
func _roll_taps() -> int:
	var r := _rng.randf()
	return 1 if r < 0.45 else (2 if r < 0.78 else 3)


func _settle(seconds: float) -> void:
	var waited := 0.0
	while waited < seconds:
		await get_tree().physics_frame
		waited += get_physics_process_delta_time()


## Waits until the mallet has actually turned to the grip it was just given,
## rather than for a fixed amount of wall time. A mallet still mid-turn has its
## handle sticking out at an angle, which is exactly what lands a tap wide.
func _await_grip(seconds: float) -> void:
	var waited := 0.0
	while waited < seconds:
		await get_tree().physics_frame
		waited += get_physics_process_delta_time()
		if _basis_error(global_transform.basis).length() < SWING_GRIP_TOLERANCE:
			return


## Drives the mallet towards `target`. Returns true if it arrived; false if the
## frog or the table stopped it (the normal end of a tap) or the move ran out
## of time.
func _drive_to(target: Vector3, tolerance: float, timeout: float) -> bool:
	_desired = target
	var best := global_position.distance_to(target)
	var waited := 0.0
	var stalled := 0.0
	while waited < timeout:
		if best <= tolerance:
			return true
		await get_tree().physics_frame
		var step := get_physics_process_delta_time()
		waited += step
		var dist := global_position.distance_to(target)
		if dist < best - 0.0005:
			best = dist
			stalled = 0.0
		else:
			stalled += step
		if stalled > STALL_GIVE_UP:
			return false
	# Only a genuine timeout is a bug: a stall means something blocked the move,
	# which is what a tap is supposed to do.
	push_warning("mallet swing could not reach %s in %.2fs; stuck at %s (grip error %.3f)" % [
		target, timeout, global_position,
		_basis_error(global_transform.basis).length()])
	return false
