class_name Pomodoro
extends Node

## A classroom-friendly pomodoro timer.
##
## The timer knows nothing about frogs or clocks: it only counts down through
## focus / short-break / long-break phases and tells anyone listening. `main.gd`
## turns those signals into frog reactions and HUD text.
##
## `time_scale` exists so a whole 25 minute cycle can be demonstrated in 25
## seconds for a class, a parent or the verification harness. It defaults to 1.

enum Phase { IDLE, FOCUS, SHORT_BREAK, LONG_BREAK }
enum State { STOPPED, RUNNING, PAUSED }

signal phase_started(phase: int, duration: float)
signal phase_ended(phase: int, next_phase: int)
signal tick(phase: int, remaining: float, progress: float)
signal state_changed(state: int)
signal cycle_changed(completed_focus: int, rounds: int)

const DEMO_SCALE := 60.0

## Default preset: the classic 25 / 5 with a longer 15 minute break every
## fourth focus block.
@export var focus_seconds := 25 * 60
@export var short_break_seconds := 5 * 60
@export var long_break_seconds := 15 * 60
@export var rounds_before_long_break := 4

var phase: int = Phase.IDLE
var state: int = State.STOPPED
var remaining := 0.0
var duration := 0.0
var completed_focus := 0
var time_scale := 1.0

var _last_phase := Phase.IDLE


func _ready() -> void:
	reset()


func _process(delta: float) -> void:
	if state != State.RUNNING:
		return
	remaining = maxf(0.0, remaining - delta * time_scale)
	tick.emit(phase, remaining, progress())
	if remaining <= 0.0:
		_advance()


# --- controls -------------------------------------------------------------

## Start a fresh focus block, or resume a paused one.
func start() -> void:
	match state:
		State.PAUSED:
			_set_state(State.RUNNING)
		State.STOPPED:
			_enter(Phase.FOCUS)
		_:
			pass


func pause() -> void:
	if state == State.RUNNING:
		_set_state(State.PAUSED)


func resume() -> void:
	if state == State.PAUSED:
		_set_state(State.RUNNING)


## One button for start / pause / resume.
func toggle() -> void:
	if state == State.RUNNING:
		pause()
	else:
		start()


## Jump straight to the next phase. From idle this just starts a focus block.
func skip() -> void:
	if phase == Phase.IDLE:
		_enter(Phase.FOCUS)
	else:
		_advance()


## Back to a clean, idle timer. Merit and the 3D scene are untouched.
func reset() -> void:
	phase = Phase.IDLE
	completed_focus = 0
	duration = focus_seconds
	remaining = duration
	_set_state(State.STOPPED)
	tick.emit(phase, remaining, progress())
	cycle_changed.emit(completed_focus, rounds_before_long_break)


## Speed the clock up so a full cycle can be shown in a minute, or back to 1x.
func set_time_scale(value: float) -> void:
	time_scale = maxf(0.05, value)


func toggle_demo() -> bool:
	if is_equal_approx(time_scale, 1.0):
		set_time_scale(DEMO_SCALE)
		return true
	set_time_scale(1.0)
	return false


## Focus length in minutes; keeps the classic 1 : 0.2 : 0.6 break ratio.
func apply_preset(focus_minutes: int) -> void:
	var unit := float(focus_minutes) * 60.0 / 25.0
	focus_seconds = float(focus_minutes) * 60.0
	short_break_seconds = roundf(5.0 * unit)
	long_break_seconds = roundf(15.0 * unit)
	reset()


# --- read-only helpers ----------------------------------------------------

func progress() -> float:
	return 0.0 if duration <= 0.0 else clampf(1.0 - remaining / duration, 0.0, 1.0)


func is_running() -> bool:
	return state == State.RUNNING


func is_on_break() -> bool:
	return phase == Phase.SHORT_BREAK or phase == Phase.LONG_BREAK


## Difficulty of the current focus length: 0 easy, 1 standard, 2 deep. The
## HUD's 15 / 25 / 45 minute presets map to these three levels.
func difficulty_level() -> int:
	if focus_seconds <= 20 * 60:
		return 0
	if focus_seconds <= 35 * 60:
		return 1
	return 2


## How many celebratory mallet taps a finished focus block earns: one per
## difficulty step, so easy 1, standard 2, deep 3.
func completion_taps() -> int:
	return difficulty_level() + 1


static func difficulty_title(level: int) -> String:
	return ["轻松", "标准", "深入"][clampi(level, 0, 2)]


func total_duration_for(p: int) -> float:
	match p:
		Phase.SHORT_BREAK:
			return short_break_seconds
		Phase.LONG_BREAK:
			return long_break_seconds
		_:
			return focus_seconds


static func phase_title(p: int) -> String:
	match p:
		Phase.FOCUS:
			return "专注时间"
		Phase.SHORT_BREAK:
			return "休息时间"
		Phase.LONG_BREAK:
			return "长休息"
		_:
			return "准备开始"


static func phase_accent(p: int) -> Color:
	match p:
		Phase.FOCUS:
			return Palette.FOCUS
		Phase.SHORT_BREAK:
			return Palette.SHORT_BREAK
		Phase.LONG_BREAK:
			return Palette.LONG_BREAK
		_:
			return Palette.IDLE


static func format_time(seconds: float) -> String:
	var whole := int(ceil(maxf(0.0, seconds)))
	return "%02d:%02d" % [whole / 60, whole % 60]


# --- internals ------------------------------------------------------------

func _set_state(value: int) -> void:
	if state == value:
		return
	state = value
	state_changed.emit(state)


func _enter(p: int) -> void:
	_last_phase = p
	phase = p
	duration = total_duration_for(p)
	remaining = duration
	_set_state(State.RUNNING)
	phase_started.emit(p, duration)
	tick.emit(p, remaining, progress())


func _advance() -> void:
	var ended := phase
	if ended == Phase.FOCUS:
		completed_focus += 1
		cycle_changed.emit(completed_focus, rounds_before_long_break)
	var next := Phase.FOCUS
	if ended == Phase.FOCUS:
		next = Phase.LONG_BREAK \
			if completed_focus % maxi(1, rounds_before_long_break) == 0 \
			else Phase.SHORT_BREAK
	phase_ended.emit(ended, next)
	_enter(next)
