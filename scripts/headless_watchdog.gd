extends Node

## Guarantees a headless run cannot hang forever.
##
## Headless runs are used by the asset builders, the verification harness and
## CI. A dropped frame, a stuck physics body or a missing scene can leave one
## spinning with no window and no output. This autoload starts a one-shot
## watchdog only when the display server is headless, so an interactive session
## is never interrupted.
##
## The budget is 5 minutes (300 s) by default and can be overridden with the
## project setting `application/run/headless_timeout_seconds`.

const DEFAULT_TIMEOUT := 300.0
const QUIT_CODE := 2


func _ready() -> void:
	if DisplayServer.get_name() != "headless":
		return
	var timeout := float(ProjectSettings.get_setting(
		"application/run/headless_timeout_seconds", DEFAULT_TIMEOUT))
	if timeout <= 0.0:
		return
	print("[headless] watchdog armed: this run will quit after %.0f s" % timeout)
	var timer := get_tree().create_timer(timeout, true, false, true)
	timer.timeout.connect(_on_timeout)


func _on_timeout() -> void:
	push_warning("[headless] run exceeded the watchdog budget; quitting so the process cannot hang")
	get_tree().quit(QUIT_CODE)
