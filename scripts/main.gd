extends Node3D

## Scene director. Wires the mallet to the frog, plays the strike sound, spawns
## the "功德+1" popups, drives the orbit camera and translates the pomodoro
## timer's phases into reactions from the frog and the HUD.

const POPUP_SCENE := preload("res://scenes/merit_popup.tscn")

const ZOOM_MIN := 0.34
const ZOOM_MAX := 1.30
const PITCH_MIN := 0.10
const PITCH_MAX := 1.05
const ORBIT_SPEED := 0.007

## Camera framing: the frog (135.5 mm tall) sits on its lotus leaf in the middle
## of the pond, so the frame has to hold the frog, the leaf and enough water
## around it to read as a pond rather than as a prop on a table.
const START_PITCH := 0.30
const START_DISTANCE := 1.05

## How hard the camera shakes for a hit of a given strength, and how fast the
## shake decays. The auto tap lands at different speeds on purpose, so the
## shake doubles as feedback for how hard the tap was.
const SHAKE_DECAY := 3.4
const SHAKE_AMPLITUDE := 0.008

## Where a "功德+1" is allowed to appear; high hits are pulled down so the
## text never leaves the top of the frame.
const POPUP_CEILING := 0.148
const POPUP_MIN_Z := 0.010

@onready var mallet: Mallet = $Mallet
@onready var frog: Frog = $Frog
@onready var pomodoro: Pomodoro = $Pomodoro
@onready var hud = $HUD
@onready var popups: Node3D = $Popups
@onready var pivot: Node3D = $CameraPivot
@onready var camera: Camera3D = $CameraPivot/Camera3D
@onready var players: Array[AudioStreamPlayer3D] = [
	$StrikeAudio/Strike0,
	$StrikeAudio/Strike1,
	$StrikeAudio/Strike2,
	$StrikeAudio/Strike3,
]

var merit := 0

var _yaw := 0.0
var _pitch := START_PITCH
var _distance := START_DISTANCE
var _orbiting := false
var _next_player := 0
var _shake := 0.0
var _demo := false
var _hud_phase := -1


func _ready() -> void:
	mallet.struck.connect(_on_struck)
	pomodoro.phase_started.connect(_on_phase_started)
	pomodoro.phase_ended.connect(_on_phase_ended)
	pomodoro.tick.connect(_on_tick)
	pomodoro.state_changed.connect(_on_state_changed)
	pomodoro.cycle_changed.connect(_on_cycle_changed)

	hud.bind(pomodoro)
	hud.demo_requested.connect(toggle_demo)
	hud.set_merit(merit)
	hud.set_phase(pomodoro.phase, pomodoro.state)
	_hud_phase = pomodoro.phase
	hud.set_time(pomodoro.remaining, pomodoro.progress())
	_on_cycle_changed(pomodoro.completed_focus, pomodoro.rounds_before_long_break)
	_apply_camera()


func _process(delta: float) -> void:
	if _shake > 0.0:
		_shake = maxf(0.0, _shake - delta * SHAKE_DECAY)
		var amp := _shake * _shake * SHAKE_AMPLITUDE
		camera.h_offset = randf_range(-amp, amp)
		camera.v_offset = randf_range(-amp, amp)
	elif camera.h_offset != 0.0 or camera.v_offset != 0.0:
		camera.h_offset = 0.0
		camera.v_offset = 0.0


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("reset_mallet"):
		mallet.return_to_rest()
	elif event.is_action_pressed("auto_strike"):
		mallet.auto_strike()
	elif event.is_action_pressed("toggle_timer"):
		pomodoro.toggle()
	elif event.is_action_pressed("skip_phase"):
		pomodoro.skip()
	elif event.is_action_pressed("demo_speed"):
		toggle_demo()
	elif event.is_action_pressed("orbit"):
		_orbiting = true
	elif event.is_action_released("orbit"):
		_orbiting = false
	elif event is InputEventMouseMotion and _orbiting:
		_yaw -= event.relative.x * ORBIT_SPEED
		_pitch = clampf(_pitch + event.relative.y * ORBIT_SPEED, PITCH_MIN, PITCH_MAX)
		_apply_camera()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_distance = clampf(_distance * 0.88, ZOOM_MIN, ZOOM_MAX)
			_apply_camera()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_distance = clampf(_distance * 1.14, ZOOM_MIN, ZOOM_MAX)
			_apply_camera()


## Called by the HUD's demo button and the D key alike.
func toggle_demo() -> void:
	_demo = pomodoro.toggle_demo()
	hud.set_demo(_demo)
	hud.banner("演示速度 60 倍：一分钟看完一整个番茄" if _demo \
		else "已回到正常速度", Palette.LAVENDER_DEEP)


func _apply_camera() -> void:
	pivot.rotation = Vector3(0.0, _yaw, 0.0)
	camera.position = Vector3(
		0.0, _distance * sin(_pitch), _distance * cos(_pitch))
	camera.rotation = Vector3(-_pitch, 0.0, 0.0)


# --- mokugyo --------------------------------------------------------------

func _on_struck(at: Vector3, speed: float) -> void:
	merit += 1
	hud.set_merit(merit)
	frog.thump(clampf(speed / 1.5, 0.4, 1.0))
	_play_strike()
	_spawn_popup(at)
	_shake = clampf(0.35 + speed * 0.22, 0.35, 1.0)


func _play_strike() -> void:
	var player := players[_next_player]
	_next_player = (_next_player + 1) % players.size()
	player.pitch_scale = randf_range(0.94, 1.07)
	player.play()


func _spawn_popup(at: Vector3) -> void:
	var popup := POPUP_SCENE.instantiate()
	popups.add_child(popup)
	var spot := Vector3(
		at.x, minf(at.y, POPUP_CEILING), maxf(at.z, POPUP_MIN_Z))
	popup.launch(spot + Vector3(0.0, 0.014, 0.0), randf_range(-0.018, 0.018))


# --- pomodoro -> stage ----------------------------------------------------

func _on_phase_started(phase: int, _duration: float) -> void:
	hud.set_phase(phase, pomodoro.state)
	_hud_phase = phase
	hud.set_time(pomodoro.remaining, 0.0)
	match phase:
		Pomodoro.Phase.FOCUS:
			# A celebration may still be playing; the frog queues this mood.
			frog.set_mood(Frog.Mood.FOCUS)
			hud.banner("专注时间到，我们一起加油！", Palette.FOCUS)
		Pomodoro.Phase.LONG_BREAK:
			frog.rest()
			hud.banner("太棒了！好好休息一会儿", Palette.LONG_BREAK)
		Pomodoro.Phase.SHORT_BREAK:
			frog.rest()
			hud.banner("休息一下，站起来动一动", Palette.SHORT_BREAK)


func _on_phase_ended(phase: int, _next: int) -> void:
	if phase == Pomodoro.Phase.FOCUS:
		_completion_show()
	else:
		frog.wake()
		hud.banner("休息结束，继续专注吧！", Palette.FOCUS)


## A finished focus block earns its difficulty in mallet taps. The confirmation
## fireworks only start once the mallet has finished tapping, so the reward
## reads as the frog being drummed into a celebration.
func _completion_show() -> void:
	# Let the break phase's own mood and banner land first.
	await get_tree().process_frame
	var taps := pomodoro.completion_taps()
	if not mallet.is_held():
		frog.set_mood(Frog.Mood.FOCUS)
		hud.banner("完成一个番茄！敲 %d 下庆祝" % taps, Palette.FOCUS)
		mallet.auto_strike(taps)
		if mallet.is_auto_striking():
			await _wait_auto_done(30.0)
	_finish_celebration()


## The confetti moment, shared by the struck and the skipped paths.
func _finish_celebration() -> void:
	frog.celebrate()
	_shake = 1.0
	hud.banner("太棒了！休息一会儿", Palette.MINT)


## Waits for the mallet's scripted swing to finish. A player-driven swing is
## deliberately not waited on, so holding the mallet can never stall the scene.
func _wait_auto_done(timeout: float) -> bool:
	var waited := 0.0
	while mallet.is_auto_striking() and waited < timeout:
		await get_tree().physics_frame
		waited += get_physics_process_delta_time()
	return not mallet.is_auto_striking()


func _on_tick(phase: int, remaining: float, progress: float) -> void:
	hud.set_time(remaining, progress)
	if phase != _hud_phase:
		# Covers a reset back to idle, which changes phase without starting one.
		_hud_phase = phase
		hud.set_phase(phase, pomodoro.state)
		if phase == Pomodoro.Phase.IDLE:
			frog.set_mood(Frog.Mood.IDLE)


func _on_state_changed(state: int) -> void:
	hud.set_running(state == Pomodoro.State.RUNNING)


func _on_cycle_changed(completed: int, rounds: int) -> void:
	hud.set_round(completed, rounds)
