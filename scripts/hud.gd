extends CanvasLayer

## The macaron HUD: merit counter, pomodoro panel, phase banner and controls.
##
## `main.gd` pushes state in through the `set_*` calls; the only thing the HUD
## owns is what the buttons do, and it does that through the `Pomodoro`
## reference handed to `bind()`. The demo button lives in `main.gd` (it touches
## the camera), so the HUD only announces that it was pressed.

signal demo_requested

@onready var merit_label: Label = $Root/MeritPanel/MeritBox/MeritLabel
@onready var phase_label: Label = $Root/TimerPanel/TimerBox/PhaseLabel
@onready var time_label: Label = $Root/TimerPanel/TimerBox/TimeLabel
@onready var local_time_label: Label = $Root/TimerPanel/TimerBox/LocalTimeLabel
@onready var progress_bar: ProgressBar = $Root/TimerPanel/TimerBox/ProgressBar
@onready var round_label: Label = $Root/TimerPanel/TimerBox/RoundLabel
@onready var banner_panel: PanelContainer = $Root/Banner
@onready var banner_label: Label = $Root/Banner/BannerLabel
@onready var start_button: Button = $Root/Controls/ControlBox/Buttons/StartButton
@onready var demo_button: Button = $Root/Controls/ControlBox/Buttons2/DemoButton
@onready var hint_label: Label = $Root/Hint

var pomodoro

var _merit_punch: Tween
var _banner_tween: Tween
var _fill: StyleBoxFlat


func _ready() -> void:
	banner_panel.visible = false
	hint_label.text = "拖动木槌敲击青蛙 · 空格 自动敲击 · R 放回木槌 · 右键拖动 转视角 · 滚轮 缩放       " \
		+ "T 开始/暂停 · N 跳过阶段 · D 演示速度"
	_update_local_time()
	_fill = StyleBoxFlat.new()
	_fill.bg_color = Palette.PEACH_DEEP
	_fill.set_corner_radius_all(10)
	progress_bar.add_theme_stylebox_override("fill", _fill)
	progress_bar.add_theme_stylebox_override("background", _make_track())

	start_button.pressed.connect(_on_start_pressed)
	$Root/Controls/ControlBox/Buttons/SkipButton.pressed.connect(_on_skip_pressed)
	$Root/Controls/ControlBox/Buttons2/ResetButton.pressed.connect(_on_reset_pressed)
	demo_button.pressed.connect(func(): demo_requested.emit())
	$Root/Controls/ControlBox/Presets/PresetEasy.pressed.connect(func(): _preset(15))
	$Root/Controls/ControlBox/Presets/PresetStandard.pressed.connect(func(): _preset(25))
	$Root/Controls/ControlBox/Presets/PresetDeep.pressed.connect(func(): _preset(45))


## Hands the HUD the timer it should command.
func bind(timer) -> void:
	pomodoro = timer


# --- state pushed in by main ---------------------------------------------

func set_merit(value: int) -> void:
	merit_label.text = "%d" % value
	if _merit_punch != null and _merit_punch.is_valid():
		_merit_punch.kill()
	merit_label.scale = Vector2(1.22, 1.22)
	_merit_punch = create_tween()
	_merit_punch.tween_property(merit_label, "scale", Vector2.ONE, 0.28) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func set_phase(phase: int, state: int) -> void:
	var accent := Pomodoro.phase_accent(phase)
	var title := Pomodoro.phase_title(phase)
	if phase == Pomodoro.Phase.FOCUS and pomodoro != null:
		title += " · " + Pomodoro.difficulty_title(pomodoro.difficulty_level())
	phase_label.text = title
	phase_label.add_theme_color_override("font_color", accent)
	time_label.add_theme_color_override("font_color", accent)
	# The local clock reads like the countdown, just quieter and smaller.
	local_time_label.add_theme_color_override("font_color", accent.darkened(0.12))
	if _fill != null:
		_fill.bg_color = accent
	_sync_start_button(state)


func set_time(remaining: float, progress: float) -> void:
	time_label.text = Pomodoro.format_time(remaining)
	progress_bar.value = progress * 100.0


func set_round(completed: int, rounds: int) -> void:
	var difficulty := ""
	if pomodoro != null:
		difficulty = " · 难度 %s" % Pomodoro.difficulty_title(pomodoro.difficulty_level())
	round_label.text = "已完成 %d 个番茄%s · 每 %d 个一次长休息" % [completed, difficulty, rounds]


func set_running(running: bool) -> void:
	start_button.text = "暂停" if running else "继续"
	phase_label.modulate.a = 1.0 if running else 0.65


func set_demo(on: bool) -> void:
	demo_button.text = "演示 60x" if on else "演示 1x"


## A short-lived message over the controls: "休息一下", "完成一个番茄", ...
func banner(text: String, color: Color) -> void:
	banner_label.text = text
	banner_label.add_theme_color_override("font_color", color)
	if _banner_tween != null and _banner_tween.is_valid():
		_banner_tween.kill()
	banner_panel.visible = true
	banner_panel.modulate.a = 0.0
	_banner_tween = create_tween()
	_banner_tween.tween_property(banner_panel, "modulate:a", 1.0, 0.22)
	_banner_tween.tween_interval(2.3)
	_banner_tween.tween_property(banner_panel, "modulate:a", 0.0, 0.55)
	_banner_tween.tween_callback(func(): banner_panel.visible = false)


# --- per-frame ------------------------------------------------------------

## Keeps the local wall-clock reading under the countdown. Shown in the same
## HH:MM:SS shape as the countdown's MM:SS, so the pair reads as one panel.
func _process(_delta: float) -> void:
	_update_local_time()


func _update_local_time() -> void:
	var t := Time.get_time_dict_from_system()
	var text := "现在 %02d:%02d:%02d" % [
		t.get("hour", 0), t.get("minute", 0), t.get("second", 0)]
	if local_time_label.text != text:
		local_time_label.text = text


# --- buttons --------------------------------------------------------------

func _on_start_pressed() -> void:
	if pomodoro != null:
		pomodoro.toggle()
		_sync_start_button(pomodoro.state)


func _on_skip_pressed() -> void:
	if pomodoro != null:
		pomodoro.skip()


func _on_reset_pressed() -> void:
	if pomodoro != null:
		pomodoro.reset()
		_sync_start_button(pomodoro.state)


func _preset(minutes: int) -> void:
	if pomodoro != null:
		pomodoro.apply_preset(minutes)
		banner("已切换到 %d 分钟专注" % minutes, Palette.LAVENDER_DEEP)


func _sync_start_button(state: int) -> void:
	match state:
		Pomodoro.State.RUNNING:
			start_button.text = "暂停"
		Pomodoro.State.PAUSED:
			start_button.text = "继续"
		_:
			start_button.text = "开始"


func _make_track() -> StyleBoxFlat:
	var track := StyleBoxFlat.new()
	track.bg_color = Palette.LAVENDER.lightened(0.5)
	track.set_corner_radius_all(10)
	return track
