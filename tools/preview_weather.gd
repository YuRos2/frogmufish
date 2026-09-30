## Iteration helper: loads the real main scene and renders it under a handful of
## pinned clocks and weathers, so the day/night and weather work can be judged
## by eye. Run it headed (it needs a renderer):
##
##   godot --path . res://tools/preview_weather.tscn
##
## It pins the sky itself, so the shots do not depend on what the wall clock or
## the network are doing.
extends Node

const DIR := "res://tools/shots"

## name, hour, weather code, cloud, wind, temperature
const SCENES := [
	["w0_noon_clear", 12.0, 0, 0.05, 5.0, 24.0],
	["w1_morning_fog", 8.0, 45, 0.85, 3.0, 14.0],
	["w2_dusk_clear", 18.2, 1, 0.25, 8.0, 20.0],
	["w3_night_clear", 23.0, 0, 0.02, 4.0, 16.0],
	["w4_rain", 13.0, 63, 0.95, 18.0, 17.0],
	["w5_storm", 16.0, 95, 1.0, 32.0, 21.0],
	["w6_snow", 10.0, 73, 0.95, 12.0, -2.0],
	["w7_hail", 14.0, 99, 1.0, 58.0, 19.0],
	["w8_typhoon", 15.0, 82, 1.0, 158.0, 26.0],
]

var main


func _ready() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(1.5).timeout

	var weather: Weather = main.get_node("Weather")
	weather.stop()
	var sky: SkyCycle = main.get_node("SkyCycle")

	# A wide framing so the sky, the fog and the water all fit the frame.
	var cam: Camera3D = main.get_node("CameraPivot/Camera3D")
	main._pitch = 0.22
	main._distance = 1.18
	main._apply_camera()

	for row in SCENES:
		var name: String = row[0]
		var hour: float = row[1]
		var code: int = row[2]
		var report := {
			"code": code,
			"label": SkyState.weather_profile(code)["label"],
			"cloud": row[3],
			"wind": row[4],
			"temperature": row[5],
			"apparent": row[5],
			"humidity": 60.0,
			"city": "预览",
			"latitude": 39.9042,
			"longitude": 116.4074,
			"wind_deg": 250.0,
		}
		weather.force_report(report)
		sky.pin(hour, report)
		await get_tree().create_timer(1.6).timeout
		await _shot(name)

	main.pomodoro.reset()
	print("weather preview done")
	get_tree().quit()


func _shot(name: String) -> void:
	var dir := ProjectSettings.globalize_path(DIR)
	DirAccess.make_dir_recursive_absolute(dir)
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.save_png(dir.path_join(name + ".png"))
	print("      shot -> %s" % dir.path_join(name + ".png"))
