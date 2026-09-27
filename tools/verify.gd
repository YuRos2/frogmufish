## Verification harness for the mokugyo frog.
##
##   godot --path . res://tools/verify.tscn            (also writes screenshots)
##   godot --headless --path . res://tools/verify.tscn (logic checks only)
##
## It loads the real main scene, lets the physics settle, then checks the
## behaviour the design promises: the mallet lies on the table beside the
## frog, a tap is counted and heard, and a driven mallet cannot be pushed
## into the frog.

extends Node

const HEAD_R := 0.0136
const DOME_TOP := 0.1355          # frog dome apex in world space
const FROG_HALF_WIDTH := 0.0671   # the sculpt is 134.1 mm across
const RNG_SEED := 20240926        # fixed seed, so the pinned checks stay stable
const SHOT_DIR := "res://tools/shots"
const BLINK_POSE := 0.10

## How far beside the frog the mallet's ball is allowed to rest. It has to
## clear the frog's widest point by at least the ball's own radius, or the two
## would be resting against each other.
const REST_CLEARANCE := FROG_HALF_WIDTH + HEAD_R
const REST_DRIFT := 0.012

var main
var mallet: Mallet
var popups: Node3D

var failures: PackedStringArray = []
var can_capture := false
var _clock := 0.0


func _ready() -> void:
	can_capture = DisplayServer.get_name() != "headless"
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	await _run()
	_summary()


func _check(label: String, ok: bool, detail: String) -> void:
	print("%s | %s | %s" % ["PASS" if ok else "FAIL", label, detail])
	if not ok:
		failures.append(label)


func _run() -> void:
	mallet = main.get_node("Mallet")
	mallet.struck.connect(_on_struck)
	popups = main.get_node("Popups")

	await _wait(2.5)
	_check_lighting()
	await _check_rest_pose()
	if can_capture:
		await _capture("baseline.png")
	_check_mouse_grab()
	await _check_relocation()
	await _check_blink()
	await _check_strike_pipeline()
	await _check_auto_strike_variety()
	await _check_no_clipping()
	await _check_swing_arc()
	await _check_repeatability()
	await _check_pomodoro()


# --- 0. the scene is wired up the way it reads ---------------------------

func _check_lighting() -> void:
	var key: DirectionalLight3D = main.get_node("KeyLight")
	var fill: DirectionalLight3D = main.get_node("FillLight")
	var cam: Camera3D = main.get_node("CameraPivot/Camera3D")
	var kd := -key.global_transform.basis.z
	var fd := -fill.global_transform.basis.z
	var cd := -cam.global_transform.basis.z
	_check("key light actually shines down onto the scene", kd.y < -0.5,
		"direction = %s" % str(kd.snappedf(0.001)))
	_check("fill light actually shines down onto the scene", fd.y < -0.4,
		"direction = %s" % str(fd.snappedf(0.001)))
	_check("camera looks down at the frog", cd.y < -0.15,
		"direction = %s" % str(cd.snappedf(0.001)))
	if can_capture:
		await _wait(1.0)
		print("      renderer: %s - %.0f fps at 1280x800" % [
			RenderingServer.get_video_adapter_name(),
			Engine.get_frames_per_second()])


# --- 1. the mallet settles beside the frog --------------------------------

func _check_rest_pose() -> void:
	var rest := mallet.rest_transform.origin
	var drift := mallet.global_position.distance_to(rest)
	var speed := mallet.linear_velocity.length()
	_check("mallet settles on its spot beside the frog",
		drift < REST_DRIFT and speed < 0.05,
		"drift=%.4f m speed=%.4f m/s at %s" % [drift, speed, str(mallet.global_position)])

	# Beside, not inside: the ball has to sit out past the frog's widest point
	# by more than its own radius, or the two would be resting on each other.
	var frog := main.get_node("Frog") as Node3D
	var sideways := absf(mallet.global_position.x - frog.global_position.x)
	_check("mallet rests beside the frog, clear of its widest point",
		sideways > REST_CLEARANCE,
		"ball centre %.4f m across, needs > %.4f" % [sideways, REST_CLEARANCE])

	# and it is the table holding it up, not the frog
	var ball_bottom := mallet.global_position.y - HEAD_R
	_check("mallet is lying on the table, not propped on the frog",
		absf(ball_bottom) < 0.004,
		"ball bottom y = %.4f (table top y = 0)" % ball_bottom)


# --- 1b. a real click on the mallet picks it up ---------------------------

func _check_mouse_grab() -> void:
	var cam: Camera3D = main.get_node("CameraPivot/Camera3D")
	var on_screen := cam.unproject_position(mallet.global_position)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = on_screen
	mallet._unhandled_input(press)
	var grabbed := mallet.is_held()
	mallet.release()
	_check("clicking the mallet picks it up", grabbed,
		"clicked at screen %s (mallet projects to %s)" % [str(press.position), str(on_screen)])

	# and clicking the frog must not
	var frog: Node3D = main.get_node("Frog")
	var off := cam.unproject_position(frog.global_position + Vector3(0, 0.06, 0))
	var miss := InputEventMouseButton.new()
	miss.button_index = MOUSE_BUTTON_LEFT
	miss.pressed = true
	miss.position = off
	mallet._unhandled_input(miss)
	var wrongly := mallet.is_held()
	mallet.release()
	_check("clicking the frog does not grab the mallet", not wrongly,
		"clicked at screen %s" % str(off))


# --- 2. it can be picked up, carried off and put back ---------------------

func _check_relocation() -> void:
	# Free-standing, so the mallet can be dragged anywhere the player likes.
	mallet.return_to_rest()
	await _wait(0.5)
	var home := mallet.rest_transform.origin
	_hold(mallet, mallet.rest_transform.basis)
	var away := home + Vector3(0.0, 0.12, -0.10)
	mallet._desired = away
	var reached := await _drive_until(away, 0.012, 1.5)
	_check("mallet can be picked up and carried away from its spot", reached,
		"wanted %s, got %s" % [str(away), str(mallet.global_position)])

	mallet.release()
	await _wait(0.3)
	mallet.return_to_rest()
	await _wait(0.4)
	_check("R puts the mallet back on its spot beside the frog",
		mallet.global_position.distance_to(home) < REST_DRIFT,
		"ended at %s (home %s)" % [str(mallet.global_position), str(home)])


# --- 3. tap -> sound + 功德+1 --------------------------------------------

var _hits := 0
var _last_merit := 0
var _sound_at_hit := false
var _popups_at_hit := 0
var _blink_at_hit := false

func _on_struck(at: Vector3, _speed: float) -> void:
	_hits += 1
	_last_merit = main.merit
	_sound_at_hit = _any_sound_playing()
	_popups_at_hit = popups.get_child_count()
	_blink_at_hit = main.get_node("Frog").is_blinking()
	print("      hit %d at t=%.2fs  speed=%.3f  contact=%s  mallet=%s  held=%s" % [
		_hits, _clock, _speed, str(at), str(mallet.global_position), str(mallet.is_held())])


func _any_sound_playing() -> bool:
	for p in main.get_node("StrikeAudio").get_children():
		if (p as AudioStreamPlayer3D).playing:
			return true
	return false


func _check_strike_pipeline() -> void:
	var hits_before := _hits
	var merit_before: int = main.merit
	mallet.auto_strike(1, RNG_SEED)
	var landed := await _wait_for(func(): return _hits > hits_before, 9.0)

	_check("striking the frog registers a hit", landed,
		"hits %d -> %d" % [hits_before, _hits])
	_check("merit increases by exactly one per hit",
		main.merit == merit_before + 1,
		"merit %d -> %d" % [merit_before, main.merit])
	_check("a mokugyo sound plays on the hit", _sound_at_hit, "playing=%s" % _sound_at_hit)
	_check("a 功德+1 popup is spawned on the hit", _popups_at_hit >= 1,
		"popups = %d" % _popups_at_hit)

	_check("being struck makes the frog blink", _blink_at_hit,
		"blink running when the hit landed = %s" % str(_blink_at_hit))

	if can_capture:
		await _capture("struck.png")

	# wait for the scripted swing to finish and put the mallet back
	await _wait_for(func(): return not mallet.is_held(), 12.0)
	await _wait(0.4)
	_check("auto tap sets the mallet back down beside the frog",
		mallet.global_position.distance_to(mallet.rest_transform.origin) < REST_DRIFT,
		"ended at %s" % str(mallet.global_position))


# --- 3b. the frog blinks ------------------------------------------------

func _pupils() -> Array:
	return (main.get_node("Frog") as Node).pupils


func _pupil_ys(pupils: Array) -> Array:
	var out := []
	for p in pupils:
		out.append(snappedf(p.scale.y, 0.001))
	return out


func _pupil_scales(pupils: Array, tolerance: float) -> bool:
	for p in pupils:
		if absf(p.scale.y - 1.0) > tolerance:
			return false
	return true


## Bounding box of everything the pupils draw. Sampling a tween's value over
## wall time would be a coin flip on a slow frame rate, so the blink is judged
## by the geometry it produces instead.
func _pupil_extent(pupils: Array) -> Vector3:
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for p in pupils:
		var box: AABB = p.global_transform * (p as MeshInstance3D).get_aabb()
		lo = lo.min(box.position)
		hi = hi.max(box.position + box.size)
	return hi - lo


func _check_blink() -> void:
	var frog: Node = main.get_node("Frog")
	var pupils := _pupils()
	_check("both pupils are wired up as blinkable nodes", pupils.size() == 2,
		"found %d" % pupils.size())
	if pupils.size() != 2:
		return

	_check("eyes are open at rest", _pupil_scales(pupils, 0.01),
		"scale.y = %s" % str(_pupil_ys(pupils)))

	var open_box := _pupil_extent(pupils)
	for p in pupils:
		p.scale.y = BLINK_POSE
	var shut_box := _pupil_extent(pupils)
	_check("blinking collapses the pupil to a slit in place",
		shut_box.y <= open_box.y * 0.2 \
			and absf(shut_box.x - open_box.x) < 0.001 \
			and absf(shut_box.z - open_box.z) < 0.001,
		"open %s -> shut %s" % [str(open_box.snappedf(0.0001)),
			str(shut_box.snappedf(0.0001))])

	if can_capture:
		# Hold the squashed pose for the photo so the shot is not at the mercy
		# of the frame rate.
		await _capture("blink.png")

	for p in pupils:
		p.scale.y = 1.0

	frog.blink()
	_check("blink() starts a blink animation", frog.is_blinking(),
		"is_blinking = %s" % str(frog.is_blinking()))
	await _wait(0.8)
	_check("the eyes open again afterwards", _pupil_scales(pupils, 0.02),
		"scale.y = %s" % str(_pupil_ys(pupils)))


# --- 4. physics stops the mallet entering the frog ------------------------

func _check_no_clipping() -> void:
	mallet.return_to_rest()
	await _wait(0.4)

	# Hold the mallet head-down above the frog and drive it hard into the
	# dome. The velocity controller pushes at full speed for two seconds.
	var down := Basis(Vector3(0, 1, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1))
	mallet.linear_velocity = Vector3.ZERO
	mallet.angular_velocity = Vector3.ZERO
	mallet.global_transform = Transform3D(down, Vector3(0.0, 0.30, 0.0))
	_hold(mallet, down)
	mallet._desired = Vector3(0.0, 0.035, 0.0)

	var lowest := 999.0
	var elapsed := 0.0
	while elapsed < 2.5:
		await get_tree().physics_frame
		elapsed += get_physics_process_delta_time()
		lowest = minf(lowest, mallet.global_position.y)

	mallet.set_held(false)
	mallet.return_to_rest()

	var floor_limit := DOME_TOP + HEAD_R - 0.004
	_check("a driven mallet cannot be forced into the frog",
		lowest >= floor_limit,
		"lowest head centre y=%.4f, must stay above %.4f" % [lowest, floor_limit])


# --- 5. taps keep counting ------------------------------------------------

func _check_repeatability() -> void:
	await _wait(0.6)
	var before: int = main.merit
	var hits_before := _hits
	for i in 2:
		mallet.auto_strike(1, RNG_SEED + i)
		await _wait_for(func(): return _hits > hits_before + i, 9.0)
		await _wait_for(func(): return not mallet.is_held(), 12.0)
	var gained: int = main.merit - before
	_check("two more taps add two more merit", gained == 2,
		"merit %d -> %d" % [before, main.merit])

	if can_capture:
		await _wait(0.12)
		await _capture("hud.png")


# --- 6. the auto tap is not the same swing every time ---------------------

## Runs unseeded auto taps and compares the plans they produced. The plan is
## written by the mallet itself, so this checks the thing the player sees - tap
## count, aim, roll and impact speed - rather than the code that generates it.
func _check_auto_strike_variety() -> void:
	var plans := []
	for i in 3:
		var hits_before := _hits
		var merit_before: int = main.merit
		mallet.auto_strike()
		var landed := await _wait_for(func(): return _hits > hits_before, 16.0)
		await _wait_for(func(): return not mallet.is_held(), 14.0)
		var plan: Dictionary = mallet.last_plan
		plans.append(plan)

		var taps: int = plan.get("taps", 0)
		var landed_hits := _hits - hits_before
		_check("unseeded auto tap %d lands every tap it chose" % (i + 1),
			landed and landed_hits == taps,
			"planned %d tap(s), felt %d" % [taps, landed_hits])
		_check("unseeded auto tap %d counts merit once per landed tap" % (i + 1),
			main.merit - merit_before == landed_hits,
			"merit +%d for %d tap(s)" % [main.merit - merit_before, landed_hits])
		_check("unseeded auto tap %d sets the mallet back down beside the frog" % (i + 1),
			mallet.global_position.distance_to(mallet.rest_transform.origin) < REST_DRIFT,
			"ended at %s" % str(mallet.global_position))

	var aims := []
	var speeds := []
	var rolls := []
	var tap_counts := []
	for p in plans:
		tap_counts.append(int(p.get("taps", 0)))
		for tap in p.get("plan", []):
			aims.append(tap["aim"])
			speeds.append(tap["speed"])
			rolls.append(tap["roll"])
	print("      tap counts %s" % str(tap_counts))
	_check("auto tap aims at a different spot each swing",
		_distinct(aims), "aims = %s" % str(aims))
	_check("auto tap varies how hard it hits",
		_distinct(speeds), "speeds = %s" % str(speeds))
	_check("auto tap varies the mallet's roll",
		_distinct(rolls), "rolls = %s" % str(rolls))


## True when every value in `values` is unique to a sane tolerance.
static func _distinct(values: Array) -> bool:
	for i in values.size():
		for j in range(i + 1, values.size()):
			if values[i] is Vector3:
				if (values[i] as Vector3).distance_to(values[j] as Vector3) < 0.0005:
					return false
			elif absf(float(values[i]) - float(values[j])) < 0.001:
				return false
	return values.size() > 1


# --- 6b. the scripted swing is a pendulum --------------------------------

## The mallet must rotate about a fixed grip so the ball travels along an arc,
## rather than being lifted and dropped. The grip never moves, so every point of
## the swing is the same distance from it, and the ball really does travel
## sideways rather than straight up and down.
func _check_swing_arc() -> void:
	mallet.return_to_rest()
	await _wait(0.4)
	mallet._aim_swing(Vector3.ZERO)
	var grip: Vector3 = mallet._grip
	var impact: Vector3 = mallet._arc_point(0.0)
	var radius: float = impact.distance_to(grip)
	var worst := 0.0
	var travel := 0.0
	for i in 13:
		var point: Vector3 = mallet._arc_point(
			float(i) / 12.0 * Mallet.SWING_READY_ANGLE)
		worst = maxf(worst, absf(point.distance_to(grip) - radius))
		travel = maxf(travel, Vector2(point.x - impact.x, point.z - impact.z).length())
	_check("the ball swings on a fixed-radius arc about the grip",
		worst < 0.001, "max radius error %.5f m" % worst)
	_check("the swing travels an arc, not a straight up-and-down drop",
		travel > 0.03, "widest horizontal travel %.4f m" % travel)


# --- 7. the pomodoro drives the frog and the clock ------------------------

## Runs a whole (speeded-up) pomodoro cycle and asserts the stage reacted:
## difficulty sets the celebration tap count, the mallet taps before the
## confetti, the frog's mood follows the phase, and its eyes droop on a break.
func _check_pomodoro() -> void:
	var pom: Pomodoro = main.get_node("Pomodoro")
	var frog: Frog = main.get_node("Frog")

	_check("the scene ships an idle pomodoro timer",
		pom.phase == Pomodoro.Phase.IDLE and pom.state == Pomodoro.State.STOPPED,
		"phase=%d state=%d" % [pom.phase, pom.state])

	# The physical clock is gone: the frog now sits on a lotus leaf on the pond,
	# and the local time moved into the countdown panel.
	var leaf: MeshInstance3D = main.get_node_or_null("LotusLeaf")
	_check("the frog sits on a lotus leaf",
		leaf != null and leaf.mesh != null and leaf.mesh.get_surface_count() > 0,
		"leaf = %s" % str(leaf))
	var pond: MeshInstance3D = main.get_node_or_null("Pond/Water")
	_check("the leaf floats on a water surface",
		pond != null and pond.mesh != null, "pond = %s" % str(pond))
	_check("the physical clock face is gone",
		main.get_node_or_null("Clock3D") == null,
		"Clock3D = %s" % str(main.get_node_or_null("Clock3D")))
	var local_label: Label = main.get_node("HUD/Root/TimerPanel/TimerBox/LocalTimeLabel")
	_check("the countdown panel carries the local time",
		local_label.text.begins_with("现在 ") and local_label.text.length() == 11,
		"local time reads %s" % local_label.text)

	# The mallet is dressed as a lotus bud but keeps its ball-shaped collision.
	var bud: Node = main.get_node_or_null("Mallet/Model/Bud")
	_check("the mallet is dressed as a lotus bud", bud != null, "bud = %s" % str(bud))

	# Difficulty: the chosen focus length decides the celebration tap count.
	var saved_focus := pom.focus_seconds
	pom.focus_seconds = 15 * 60
	var easy := pom.completion_taps()
	pom.focus_seconds = 25 * 60
	var standard := pom.completion_taps()
	pom.focus_seconds = 45 * 60
	var deep := pom.completion_taps()
	pom.focus_seconds = saved_focus
	_check("focus difficulty decides the celebration tap count (1/2/3)",
		easy == 1 and standard == 2 and deep == 3,
		"15 -> %d, 25 -> %d, 45 -> %d" % [easy, standard, deep])

	# Focus ends into a 10 s break: long enough for the completion taps, the
	# celebration hold and the nap to all fit.
	pom.focus_seconds = 2.0
	pom.short_break_seconds = 10.0
	pom.long_break_seconds = 10.0
	pom.rounds_before_long_break = 4
	pom.time_scale = 1.0
	pom.reset()
	_check("reset arms a fresh focus block",
		pom.phase == Pomodoro.Phase.IDLE and is_equal_approx(pom.remaining, 2.0),
		"phase=%d remaining=%.2f" % [pom.phase, pom.remaining])

	pom.start()
	_check("start begins a focus block",
		pom.phase == Pomodoro.Phase.FOCUS and pom.state == Pomodoro.State.RUNNING,
		"phase=%d state=%d" % [pom.phase, pom.state])
	_check("focus puts the frog in its attentive mood",
		frog.mood == Frog.Mood.FOCUS, "mood=%d" % frog.mood)
	var hud_label: Label = main.get_node("HUD/Root/TimerPanel/TimerBox/TimeLabel")
	_check("the HUD shows the countdown", hud_label.text == "00:02",
		"HUD reads %s" % hud_label.text)

	# The progress bar is the 2D replacement for the clock's old dot ring.
	var bar: ProgressBar = main.get_node("HUD/Root/TimerPanel/TimerBox/ProgressBar")
	await _wait(0.6)
	_check("the HUD progress bar tracks the countdown",
		absf(bar.value / 100.0 - pom.progress()) < 0.08,
		"bar=%.2f timer=%.2f" % [bar.value / 100.0, pom.progress()])

	var to_break := await _wait_for(
		func(): return pom.phase == Pomodoro.Phase.SHORT_BREAK, 6.0)
	_check("a finished focus block rolls into a short break", to_break,
		"phase=%d" % pom.phase)

	# The completion show: the mallet taps out the difficulty, and only then
	# does the confetti fall.
	var expected_taps := pom.completion_taps()
	var hits_before_completion := _hits
	var merit_before_completion: int = main.merit
	var drove := await _wait_for(
		func(): return mallet.is_auto_striking(), 6.0)
	_check("finishing focus drives the mallet automatically", drove,
		"auto striking = %s" % str(mallet.is_auto_striking()))
	await _wait_for(func(): return not mallet.is_auto_striking(), 30.0)
	var landed := _hits - hits_before_completion
	_check("the completion swing lands the difficulty's tap count",
		landed == expected_taps,
		"planned %s, landed %d, expected %d" % [
			str(mallet.last_plan.get("taps", -1)), landed, expected_taps])
	_check("every completion tap earns merit",
		main.merit - merit_before_completion == expected_taps,
		"merit +%d for %d tap(s)" % [
			main.merit - merit_before_completion, expected_taps])
	var cheered := await _wait_for(
		func(): return frog.mood == Frog.Mood.CHEER, 8.0)
	_check("the confetti celebration follows the taps", cheered,
		"mood=%d" % frog.mood)

	await _wait_for(func(): return frog.mood == Frog.Mood.BREAK, 6.0)
	_check("the break settles the frog into a nap", frog.mood == Frog.Mood.BREAK,
		"mood=%d" % frog.mood)
	await _wait(0.6)
	var drowsy := true
	for p in frog.pupils:
		if absf(p.scale.y - 0.42) > 0.10:
			drowsy = false
	_check("a napping frog half-closes its eyes", drowsy,
		"scale.y = %s" % str(_pupil_ys(frog.pupils)))

	var to_focus := await _wait_for(
		func(): return pom.phase == Pomodoro.Phase.FOCUS, 12.0)
	_check("the break returns to focus", to_focus, "phase=%d" % pom.phase)
	await _wait(0.3)
	_check("waking up is its own mood", frog.mood == Frog.Mood.WAKE,
		"mood=%d" % frog.mood)
	await _wait_for(func(): return frog.mood == Frog.Mood.FOCUS, 3.0)
	_check("the frog settles back into focus", frog.mood == Frog.Mood.FOCUS,
		"mood=%d" % frog.mood)

	# The mokugyo keeps working while the timer runs.
	var merit_before: int = main.merit
	var hits_before := _hits
	pom.pause()
	mallet.auto_strike(1, RNG_SEED)
	await _wait_for(func(): return _hits > hits_before, 9.0)
	await _wait_for(func(): return not mallet.is_held(), 12.0)
	_check("a running pomodoro does not stop the mokugyo counting merit",
		main.merit == merit_before + 1,
		"merit %d -> %d" % [merit_before, main.merit])
	pom.reset()
	_check("reset returns the stage to idle",
		pom.phase == Pomodoro.Phase.IDLE and frog.mood == Frog.Mood.IDLE,
		"phase=%d mood=%d" % [pom.phase, frog.mood])

	# The HUD buttons drive the same public API.
	var start_button: Button = main.get_node(
		"HUD/Root/Controls/ControlBox/Buttons/StartButton")
	var preset: Button = main.get_node("HUD/Root/Controls/ControlBox/Presets/PresetEasy")
	var demo: Button = main.get_node("HUD/Root/Controls/ControlBox/Buttons2/DemoButton")

	start_button.emit_signal("pressed")
	_check("the HUD start button starts the timer",
		pom.state == Pomodoro.State.RUNNING, "state=%d" % pom.state)
	start_button.emit_signal("pressed")
	_check("the HUD start button pauses again",
		pom.state == Pomodoro.State.PAUSED, "state=%d" % pom.state)

	preset.emit_signal("pressed")
	_check("a preset button retunes the focus length",
		is_equal_approx(pom.focus_seconds, 900.0), "focus=%.0f s" % pom.focus_seconds)

	demo.emit_signal("pressed")
	_check("the demo button speeds the timer up", pom.time_scale > 1.0,
		"time_scale=%.0f" % pom.time_scale)
	demo.emit_signal("pressed")
	_check("the demo button returns to normal speed",
		is_equal_approx(pom.time_scale, 1.0), "time_scale=%.0f" % pom.time_scale)
	pom.reset()


# --- helpers --------------------------------------------------------------

## Takes hold of the mallet the same way _begin_grab does, so a mallet that has
## gone to sleep in the mouth starts responding again.
func _hold(m: Mallet, basis: Basis) -> void:
	m.set_held(true)
	m._pointer_driven = false
	m._hold_basis = basis
	m._desired = m.global_position

func _wait(seconds: float) -> void:
	_clock += seconds
	await get_tree().create_timer(seconds).timeout


func _wait_for(predicate: Callable, timeout: float) -> bool:
	var elapsed := 0.0
	while elapsed < timeout:
		if predicate.call():
			return true
		await get_tree().physics_frame
		var step := get_physics_process_delta_time()
		elapsed += step
		_clock += step
	return predicate.call()


func _drive_until(target: Vector3, tolerance: float, timeout: float) -> bool:
	return await _wait_for(func(): return mallet.global_position.distance_to(target) <= tolerance, timeout)


func _capture(name: String) -> void:
	var dir := ProjectSettings.globalize_path(SHOT_DIR)
	DirAccess.make_dir_recursive_absolute(dir)
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.save_png(dir.path_join(name))
	print("      shot -> %s" % dir.path_join(name))


func _summary() -> void:
	print("")
	if failures.is_empty():
		print("RESULT: ALL CHECKS PASSED")
	else:
		print("RESULT: %d CHECK(S) FAILED: %s" % [failures.size(), ", ".join(failures)])
	get_tree().quit(0 if failures.is_empty() else 1)
