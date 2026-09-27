## Temporary: grab screenshots of the resting scene and of a scripted tap.
extends Node

const DIR := "res://tools/shots"

var main
var mallet
var hits := 0
var shot := 0
var t0 := 0.0


func _ready() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	mallet = main.get_node("Mallet")
	mallet.struck.connect(func(a, s):
		hits += 1
		print("HIT %d t=%.3f speed=%.3f at=%s mallet=%s held=%s" % [
			hits, (Time.get_ticks_msec() - t0) / 1000.0, s, a,
			mallet.global_position, mallet.is_held()]))
	await get_tree().create_timer(2.5).timeout
	await _shot("rest")
	print("rest pos ", mallet.global_position, "  basis ", mallet.global_transform.basis)
	print("rest used ", mallet.rest_transform)
	mallet.auto_strike(2, 20240926)
	t0 = Time.get_ticks_msec()
	var waited := 0.0
	while hits == 0 and waited < 12.0:
		await get_tree().physics_frame
		waited += get_physics_process_delta_time()
	await _shot("tap")
	while mallet.is_held() and waited < 30.0:
		await get_tree().physics_frame
		waited += get_physics_process_delta_time()
	await get_tree().create_timer(0.6).timeout
	print("ended at ", mallet.global_position, " drift %.4f" % mallet.global_position.distance_to(mallet.rest_transform.origin))
	print("plan ", mallet.last_plan)
	await _shot("after")
	get_tree().quit()


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := ProjectSettings.globalize_path(DIR).path_join("%s_%d.png" % [name, shot])
	shot += 1
	image.save_png(path)
	print("shot -> ", path)
