extends SceneTree

## Bounded headless check of the froggreen rebuild: the striker rests in the
## mouth, a default auto-strike plays 10..20 rhythmic taps, and it ends back at
## its rest pose.

var _hits := 0
var _hit_times: Array[float] = []
var _main


func _initialize() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)
	_run()


func _run() -> void:
	await create_timer(1.0).timeout
	var mallet = _main.get_node("Mallet")
	var frog = _main.get_node("Frog")
	var rest: Transform3D = mallet.rest_transform
	print("rest origin = ", rest.origin)
	print("start origin = ", mallet.global_transform.origin)
	print("jaw pivot = ", frog._jaw_pivot)
	mallet.struck.connect(func(_a, _s):
		_hits += 1
		_hit_times.append(Time.get_ticks_msec() / 1000.0))
	mallet.auto_strike()
	var waited := 0.0
	while mallet.is_auto_striking() and waited < 60.0:
		await physics_frame
		waited += 1.0 / 90.0
	print("hits = ", _hits, " elapsed = %.2f s" % waited)
	var gaps := PackedFloat32Array()
	for i in range(1, _hit_times.size()):
		gaps.append(_hit_times[i] - _hit_times[i - 1])
	print("gaps = ", gaps)
	print("end origin = ", mallet.global_transform.origin)
	print("drift = %.5f" % mallet.global_transform.origin.distance_to(rest.origin))
	var ok: bool = _hits >= 10 and _hits <= 20 and mallet.global_transform.origin.distance_to(rest.origin) < 0.02
	print("RESULT ", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)
