extends Label3D

## A "功德+1" that pops out of the frog, drifts up and fades away.

const DURATION := 1.05
const RISE := 0.058

var _elapsed := 0.0
var _start := Vector3.ZERO
var _drift := Vector3.ZERO


func _ready() -> void:
	set_process(false)


func launch(at: Vector3, drift_x: float) -> void:
	_start = at
	global_position = at
	_drift = Vector3(drift_x, 0.0, drift_x * 0.4)
	_elapsed = 0.0
	scale = Vector3.ONE * 0.7
	modulate.a = 1.0
	set_process(true)


func _process(delta: float) -> void:
	_elapsed += delta
	var t := _elapsed / DURATION
	if t >= 1.0:
		queue_free()
		return

	var rise := 1.0 - pow(1.0 - t, 2.6)
	global_position = _start + _drift * rise + Vector3(0.0, RISE * rise, 0.0)

	# quick overshoot then settle, then fade out
	var pop := 0.7 + 1.9 * t if t < 0.20 else maxf(1.0, 1.08 - 0.4 * (t - 0.20))
	scale = Vector3.ONE * pop
	modulate.a = clampf(1.0 - pow(t, 2.4), 0.0, 1.0)
