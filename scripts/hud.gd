extends CanvasLayer

## The macaron HUD: merit counter, pomodoro panel, phase banner and controls.
##
## `main.gd` pushes state in through the `set_*` calls; the only thing the HUD
## owns is what the buttons do, and it does that through the `Pomodoro`
## reference handed to `bind()`. The demo button lives in `main.gd` (it touches
## the camera), so the HUD only announces that it was pressed.

signal demo_requested
signal weather_refresh_requested
signal clock_follow_toggled(follow: bool)

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
@onready var env_title: Label = $Root/EnvPanel/EnvBox/EnvTitle
@onready var weather_label: Label = $Root/EnvPanel/EnvBox/WeatherLabel
@onready var severe_label: Label = $Root/EnvPanel/EnvBox/SevereLabel
@onready var detail_label: Label = $Root/EnvPanel/EnvBox/DetailLabel
@onready var sun_label: Label = $Root/EnvPanel/EnvBox/SunLabel
@onready var source_label: Label = $Root/EnvPanel/EnvBox/SourceLabel
@onready var refresh_button: Button = $Root/EnvPanel/EnvBox/EnvButtons/RefreshButton
@onready var clock_button: CheckButton = $Root/EnvPanel/EnvBox/EnvButtons/ClockButton

var pomodoro

var _merit_punch: Tween
var _banner_tween: Tween
var _fill: StyleBoxFlat
var _weather: Dictionary = {}
var _weather_status := "待同步"
var _location_text := ""


func _ready() -> void:
	# The weather / environment panel is hidden for this build: the frog and the
	# striker are the whole show, so the panel stays out of the frame.
	$Root/EnvPanel.visible = false
	banner_panel.visible = false
	hint_label.text = "🐸 单击 / 空格 连续敲木鱼（10-20 下）    " \
		+ "T 开始/暂停 · N 跳过 · D 演示 · 右键 转视角 · 滚轮 缩放"
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
	refresh_button.pressed.connect(func(): weather_refresh_requested.emit())
	clock_button.toggled.connect(func(on: bool): clock_follow_toggled.emit(on))
	$Root/Controls/ControlBox/Presets/PresetEasy.pressed.connect(func(): _preset(15))
	$Root/Controls/ControlBox/Presets/PresetStandard.pressed.connect(func(): _preset(25))
	$Root/Controls/ControlBox/Presets/PresetDeep.pressed.connect(func(): _preset(45))
	# Kid-friendly first run: a welcoming nudge.
	banner("🐸 小青蛙准备好啦，点开始一起专注吧！", Palette.MINT_DEEP)


## Hands the HUD the timer it should command.
func bind(timer) -> void:
	pomodoro = timer


# --- state pushed in by main ---------------------------------------------

func set_merit(value: int, milestone: int = 0) -> void:
	merit_label.text = "%d" % value
	if _merit_punch != null and _merit_punch.is_valid():
		_merit_punch.kill()
	var punch_scale := Vector2(1.30, 1.30) if milestone > 0 else Vector2(1.22, 1.22)
	merit_label.scale = punch_scale
	_merit_punch = create_tween()
	_merit_punch.tween_property(merit_label, "scale", Vector2.ONE, 0.32) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if milestone > 0:
		var msg := ""
		match milestone:
			1: msg = "🌟 太棒了！获得 10 个功德！"
			2: msg = "🎉 好厉害！50 个功德达成！"
			3: msg = "🏆 超级棒！100 个功德啦！"
			_: msg = "✨ 功德里程碑达成！"
		banner(msg, Palette.LEMON_DEEP)


func set_phase(phase: int, state: int) -> void:
	var accent := Pomodoro.phase_accent(phase)
	var title := Pomodoro.phase_title(phase)
	if phase == Pomodoro.Phase.FOCUS and pomodoro != null:
		title += " · " + Pomodoro.difficulty_title(pomodoro.difficulty_level())
	phase_label.text = "🍅 " + title
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
		difficulty = " · %s" % Pomodoro.difficulty_title(pomodoro.difficulty_level())
	round_label.text = "🍅 已完成 %d 个番茄%s · 每 %d 个长休息一次" % [completed, difficulty, rounds]


func set_running(running: bool) -> void:
	start_button.text = "暂停" if running else "继续"
	phase_label.modulate.a = 1.0 if running else 0.65


func set_demo(on: bool) -> void:
	demo_button.text = "🚀 演示 60x" if on else "🚀 演示 1x"


# --- environment panel ----------------------------------------------------

## Shows the normalised weather report from `weather.gd`.
func set_weather(report: Dictionary) -> void:
	if report.is_empty():
		return
	_weather = report
	var label: String = String(report.get("label", "--"))
	var temperature := float(report.get("temperature", NAN))
	weather_label.text = "🌤 %s  %s" % [label, _degrees(temperature)]
	var apparent := float(report.get("apparent", temperature))
	var humidity := float(report.get("humidity", NAN))
	var wind := float(report.get("wind", NAN))
	detail_label.text = "体感 %s · 湿度 %s · 风 %s" % [
		_degrees(apparent),
		"--" if is_nan(humidity) else "%d%%" % roundi(humidity),
		"--" if is_nan(wind) else "%.0f km/h" % wind]
	# Severe convective weather gets its own warning line: a typhoon or a
	# hailstorm should be impossible to miss in the panel.
	var severe := int(report.get("severe_level", 0))
	var severe_title := String(report.get("severe_title", ""))
	severe_label.visible = severe > 0 and not severe_title.is_empty()
	if severe_label.visible:
		severe_label.text = "⚠ %s" % severe_title
	_apply_weather_accent()
	_refresh_source()


## How the location was found, for the source line.
func set_location_text(text: String) -> void:
	_location_text = text
	_refresh_source()


## "实时天气" / "模拟天气" / "刷新中…" from the weather node.
func set_weather_status(text: String) -> void:
	_weather_status = text
	_refresh_source()


## The eased sky look from `sky_cycle.gd`: the date, the season and the
## sunrise / sunset the model worked out for today's latitude.
func set_sky(look: Dictionary) -> void:
	if look.is_empty():
		return
	var season := String(look.get("season_title", ""))
	env_title.text = "🌈 今日 · %s%s" % [
		String(look.get("date_text", "")), "" if season.is_empty() else " · " + season]
	var phase := String(look.get("phase_title", ""))
	if bool(look.get("polar_night", false)):
		sun_label.text = "极夜 · %s" % phase
	elif bool(look.get("polar_day", false)):
		sun_label.text = "极昼 · %s" % phase
	else:
		sun_label.text = "日出 %s · 日落 %s · %s" % [
			_clock(float(look.get("sunrise_hour", -1.0))),
			_clock(float(look.get("sunset_hour", -1.0))), phase]


## Tints the temperature line to match what the sky is doing, so the panel
## itself changes with the weather the way the 3D scene does.
func _apply_weather_accent() -> void:
	var code := int(_weather.get("code", 0))
	var accent := Palette.LEMON_DEEP
	if int(_weather.get("severe_level", 0)) >= 2:
		accent = Palette.ROSE
	elif code >= 71 and code <= 86:
		accent = Palette.SKY_DEEP
	elif code >= 51:
		accent = Palette.SKY_DEEP
	elif code == 0 or code == 1:
		accent = Palette.LEMON_DEEP
	else:
		accent = Palette.PLUM_SOFT
	weather_label.add_theme_color_override("font_color", accent)


func _refresh_source() -> void:
	var city := String(_weather.get("city", ""))
	if city.is_empty():
		city = "未知地点"
	var parts := PackedStringArray([city])
	if not _location_text.is_empty():
		parts.append(_location_text)
	parts.append(_weather_status)
	source_label.text = "🌍 " + " · ".join(parts)


static func _degrees(value: float) -> String:
	if is_nan(value):
		return "--°C"
	return "%d°C" % roundi(value)


## A wall-clock hour (0..24, float) as HH:MM. Polar days have no such hour, so
## anything negative prints as a dash.
static func _clock(hours: float) -> String:
	if hours < 0.0:
		return "--:--"
	var wrapped := fposmod(hours, 24.0)
	var hh := int(floor(wrapped))
	var mm := int(round((wrapped - float(hh)) * 60.0)) % 60
	return "%02d:%02d" % [hh % 24, mm]


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
		banner("🍅 已切换到 %d 分钟专注，你能做到！" % minutes, Palette.LAVENDER_DEEP)


func _sync_start_button(state: int) -> void:
	match state:
		Pomodoro.State.RUNNING:
			start_button.text = "⏸ 暂停"
		Pomodoro.State.PAUSED:
			start_button.text = "▶ 继续"
		_:
			start_button.text = "▶ 开始"


func _make_track() -> StyleBoxFlat:
	var track := StyleBoxFlat.new()
	track.bg_color = Palette.LAVENDER.lightened(0.5)
	track.set_corner_radius_all(10)
	return track
