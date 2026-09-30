## Iteration helper: loads the real main scene, walks a demo pomodoro cycle and
## saves screenshots of each stage. Run it headed (it needs a renderer):
##
##   godot --path . res://tools/preview_clock.tscn
extends Node

const DIR := "res://tools/shots"

var main


func _ready() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	# Deterministic light and weather, so the pomodoro shots do not change with
	# the hour the tool happens to be run at.
	main.get_node("Weather").stop()
	main.get_node("Weather").force_report({
		"code": 0, "label": "晴", "cloud": 0.05, "wind": 6.0,
		"temperature": 24.0, "apparent": 23.0, "humidity": 40.0,
		"city": "预览", "latitude": 39.9042, "longitude": 116.4074,
	})
	main.get_node("SkyCycle").pin(11.0, {"code": 0, "cloud": 0.05, "wind": 6.0})
	await get_tree().create_timer(2.0).timeout
	await _shot("p0_idle")

	# A close-up of the pond: the frog on the lotus leaf and the bud mallet.
	var cam: Camera3D = main.get_node("CameraPivot/Camera3D")
	cam.position = Vector3(0.0, 0.14, 0.34)
	cam.rotation = Vector3(-0.30, 0.0, 0.0)
	await get_tree().create_timer(0.4).timeout
	await _shot("p5_pond")
	main._apply_camera()

	# A close-up of the striker resting horizontally in the frog's mouth.
	cam.position = main.mallet.global_position + Vector3(0.03, 0.075, 0.14)
	cam.look_at(main.mallet.global_position, Vector3.UP)
	await get_tree().create_timer(0.4).timeout
	await _shot("p6_mallet")
	main._apply_camera()

	main.pomodoro.start()
	await get_tree().create_timer(0.9).timeout
	await _shot("p1_focus")

	# A frame strip of one scripted swing, so the arc can be judged as motion.
	main.pomodoro.pause()
	main.mallet.auto_strike(1, 20240926)
	for i in 10:
		await get_tree().create_timer(0.13).timeout
		await _shot("swing_%02d" % i)
	await _wait_for(func(): return not main.mallet.is_auto_striking(), 25.0)
	main.pomodoro.resume()

	# Skip the rest of the focus block: this is the real completion show, where
	# the mallet taps out the difficulty and the lotus petals follow afterwards.
	main.pomodoro.skip()
	await get_tree().create_timer(1.0).timeout
	await _shot("p2_tap")
	await _wait_for(func(): return main.frog.mood == Frog.Mood.CHEER, 10.0)
	await get_tree().create_timer(0.25).timeout
	await _shot("p3_celebrate")

	await _wait_for(func(): return main.frog.mood == Frog.Mood.BREAK, 8.0)
	await get_tree().create_timer(0.6).timeout
	await _shot("p4_break")

	print("preview done")
	get_tree().quit()


func _wait_for(predicate: Callable, timeout: float) -> bool:
	var waited := 0.0
	while waited < timeout:
		if predicate.call():
			return true
		await get_tree().process_frame
		waited += get_process_delta_time()
	return predicate.call()


func _shot(name: String) -> void:
	var dir := ProjectSettings.globalize_path(DIR)
	DirAccess.make_dir_recursive_absolute(dir)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(dir.path_join(name + ".png"))
	print("shot -> ", dir.path_join(name + ".png"))
