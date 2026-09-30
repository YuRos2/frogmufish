class_name Weather
extends Node

## The pond's link to the real world: where we are and what the sky is doing.
##
## Everything here is deliberately forgiving. The scene has to look right in a
## classroom with no network, on a laptop that has never been online, and in a
## headless test run - so the report is assembled from the best source that
## answers, in this order:
##
## 1. an explicit latitude/longitude in the project settings (a teacher pinning
##    the school's location, or a test),
## 2. the machine's own GPS / location service (see `_request_device_location`),
## 3. the last location cached under `user://`,
## 4. IP geolocation, then the live Open-Meteo forecast (neither needs a key),
## 5. a deterministic *simulated* forecast derived from the date.
##
## When nothing can say where the pond is, it defaults to **宁波市鄞州区** rather
## than to some unrelated capital. The simulated fallback is labelled
## `源: 模拟` in the HUD rather than passed off as real weather: the point is
## that the scene still changes with the season and the time of day, not that
## it lies about the sky.
##
## `sky_cycle.gd` consumes the normalised report; `hud.gd` shows it.

signal report_changed(report: Dictionary)
signal status_changed(text: String)

enum Status { IDLE, LOCATING, FETCHING, READY, CACHED, OFFLINE, DISABLED }
enum Step { NONE, GEO, WEATHER }

const CACHE_PATH := "user://weather_report.json"
const LOCATION_PATH := "user://weather_location.json"
## The pond's home: 宁波市鄞州区, the author's own neighbourhood. Used only when
## neither the machine, the cache nor the network can place us.
const DEFAULT_LATITUDE := 29.8161
const DEFAULT_LONGITUDE := 121.5453
const DEFAULT_CITY := "宁波市鄞州区"

## A fix handed in by the environment, `"lat,lon[,city]"`. It is how a wrapper
## script, a test or a build without a location service injects a GPS reading.
const GPS_ENV := "MOKUGYO_GPS"
## Where the Windows location probe writes its script and its answer.
const GPS_SCRIPT_PATH := "user://mokugyo_gps.ps1"
const GPS_FIX_PATH := "user://mokugyo_gps_fix.json"
## How long we wait for the location service before falling back.
const GPS_TIMEOUT := 9.0

## Older than this and a cached report is only used if nothing else answers.
const STALE_SECONDS := 3 * 3600
const FORECAST_URL := "https://api.open-meteo.com/v1/forecast"
const CURRENT_FIELDS := "temperature_2m,relative_humidity_2m,apparent_temperature" \
	+ ",precipitation,rain,snowfall,weather_code,cloud_cover" \
	+ ",wind_speed_10m,wind_direction_10m"

## Tried in order. `ip-api.com` is plain HTTP on purpose: it is the one that
## still answers when a captive portal or a strict TLS filter is in the way.
const GEO_ENDPOINTS := [
	"http://ip-api.com/json/?fields=status,country,regionName,city,lat,lon,timezone",
	"https://ipwho.is/",
	"https://ipinfo.io/json",
]

const REQUEST_TIMEOUT := 12.0

## Ready-made severe-weather reports, used by the verification harness and the
## preview tool to place the pond under a thunderstorm, a hailstorm or a
## typhoon without waiting for the sky to cooperate. The running game never
## uses them for the UI - on screen the storm only ever follows a real report.
const SEVERE_PRESETS := [
	{"name": "关闭", "active": false},
	{"name": "强雷暴", "active": true,
		"code": 95, "cloud": 1.0, "wind": 46.0, "wind_deg": 205.0,
		"temperature": 24.0, "humidity": 88.0, "precipitation": 9.0},
	{"name": "冰雹", "active": true,
		"code": 99, "cloud": 1.0, "wind": 58.0, "wind_deg": 240.0,
		"temperature": 19.0, "humidity": 93.0, "precipitation": 14.0},
	{"name": "台风", "active": true,
		"code": 82, "cloud": 1.0, "wind": 158.0, "wind_deg": 120.0,
		"temperature": 26.0, "humidity": 96.0, "precipitation": 48.0},
]

## A PowerShell probe for the Windows location service. WinRT hands back an
## `IAsyncOperation`, which Windows PowerShell cannot await directly, so it is
## projected through `System.WindowsRuntimeSystemExtensions.AsTask` first. When
## the service is off, or the user has never granted the location privacy
## permission, the task faults with `UnauthorizedAccessException`; the catch
## swallows it and no file is written, so the caller simply times out. The
## fix path is substituted for `%s`.
const WINDOWS_GPS_SCRIPT := """$ErrorActionPreference = 'Stop'
$out = '%s'
try {
    Add-Type -AssemblyName System.Runtime.WindowsRuntime | Out-Null
    $null = [Windows.Devices.Geolocation.Geolocator, Windows.Devices.Geolocation, ContentType = WindowsRuntime]
    $asTask = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
        $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and `
            $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1'
    })[0].MakeGenericMethod([Windows.Devices.Geolocation.Geoposition])
    $locator = New-Object Windows.Devices.Geolocation.Geolocator
    $locator.DesiredAccuracyInMeters = 300
    $task = $asTask.Invoke($null, @($locator.GetGeopositionAsync()))
    if (-not $task.Wait(7000)) { exit }
    $position = $task.Result.Coordinate.Point.Position
    ([ordered]@{ latitude = $position.Latitude; longitude = $position.Longitude } | ConvertTo-Json -Compress) |
        Set-Content -Encoding ASCII -Path $out
} catch { }
"""

@export var use_network := true
@export var auto_start := true
@export var refresh_minutes := 20.0

var status: int = Status.IDLE
var report: Dictionary = {}
var location: Dictionary = {}
## Where the fix came from: "settings", "gps", "cache", "ip" or "default".
var location_source := ""
var last_error := ""

var _http: HTTPRequest
var _step: int = Step.NONE
var _geo_index := 0
var _elapsed := 0.0
var _started := false
var _stopped := false
var _gps_active := false
var _gps_elapsed := 0.0


func _ready() -> void:
	_http = HTTPRequest.new()
	_http.timeout = REQUEST_TIMEOUT
	_http.request_completed.connect(_on_request_completed)
	add_child(_http)
	refresh_minutes = float(ProjectSettings.get_setting(
		"mokugyo/weather/refresh_minutes", refresh_minutes))
	use_network = bool(ProjectSettings.get_setting(
		"mokugyo/weather/use_network", use_network))
	if auto_start:
		start()


# --- public API -----------------------------------------------------------

## Begins resolving the location and fetching a report. Safe to call twice.
func start() -> void:
	if _started:
		return
	_started = true
	# A pinned location is honoured whatever the network is doing; otherwise the
	# offline path never has to reach for a satellite.
	var configured := _configured_location()
	if not configured.is_empty():
		location = configured
		location_source = "settings"
	if not use_network:
		_use_offline("")
		return
	if not configured.is_empty():
		_fetch_weather()
		return
	_request_device_location()


## Cancels anything in flight and stops refreshing. The current report stays
## readable, so a paused/locked clock or a test run keeps its last sky.
func stop() -> void:
	_stopped = true
	_step = Step.NONE
	_gps_active = false
	if _http != null:
		_http.cancel_request()


## Fetches again from scratch; honours the network switch.
func refresh() -> void:
	_stopped = false
	_elapsed = 0.0
	if not use_network:
		_use_offline("已关闭联网")
		return
	if location.is_empty() or location_source == "default":
		_geo_index = 0
		_request_device_location()
	else:
		_fetch_weather()


## Turns one of the `SEVERE_PRESETS` into a forced report, so a test or the
## preview tool can place the pond under a hailstorm or a typhoon without
## waiting for the sky to cooperate. The UI never calls this: on screen the
## severe weather only ever follows a real report. Returns the preset's name.
func apply_severe(index: int) -> String:
	var preset: Dictionary = SEVERE_PRESETS[
		clampi(index, 0, SEVERE_PRESETS.size() - 1)]
	var name := String(preset["name"])
	if not bool(preset.get("active", false)):
		refresh()
		return name
	var overrides := preset.duplicate(true)
	overrides.erase("name")
	overrides.erase("active")
	force_report(overrides)
	return name


## Injects a report (tests, the preview tool, a teacher overriding the sky).
## Fields that `_decorate` derives - the label, the hail amount, the severe
## classification - are dropped first unless the override sets them, so a
## forced report never inherits the last storm's label.
func force_report(overrides: Dictionary) -> void:
	var merged := report.duplicate(true)
	for key in ["label", "hail", "thunder", "severe_level", "severe_title",
			"typhoon"]:
		if not overrides.has(key):
			merged.erase(key)
	merged.merge(overrides, true)
	merged["source"] = overrides.get("source", "forced")
	merged["updated_unix"] = Time.get_unix_time_from_system()
	report = _decorate(merged)
	_set_status(Status.READY)
	report_changed.emit(report)


## A one-line description of where the numbers came from, for the HUD.
func status_text() -> String:
	match status:
		Status.LOCATING:
			return "🔍 定位中…"
		Status.FETCHING:
			return "🌐 刷新中…"
		Status.DISABLED:
			return "⛔ 已关闭"
		Status.OFFLINE:
			return "🎨 模拟天气"
		Status.CACHED:
			return "📦 离线缓存"
		Status.READY:
			return "🌤 实时天气"
		_:
			return "⏳ 待同步"


## How the location was found, for the HUD's source line.
func location_text() -> String:
	match location_source:
		"settings":
			return "🎚 手动位置"
		"gps":
			return "📍 本机定位"
		"cache":
			return "📦 上次位置"
		"ip":
			return "🌐 网络定位"
		"default":
			return "🏠 默认位置"
		_:
			return ""


func city() -> String:
	var name: String = String(location.get("city", ""))
	if name.is_empty():
		name = String(report.get("city", ""))
	return name if not name.is_empty() else "未知地点"


func is_live() -> bool:
	return status == Status.READY and report.get("source", "") == "open-meteo"


func cache_age_seconds() -> float:
	return _report_age(report)


static func _report_age(source: Dictionary) -> float:
	var stamp := float(source.get("updated_unix", 0))
	if stamp <= 0.0:
		return INF
	return Time.get_unix_time_from_system() - stamp


# --- per-frame ------------------------------------------------------------

func _process(delta: float) -> void:
	if _gps_active:
		_poll_device_location(delta)
	if not _started or _stopped or not use_network:
		return
	_elapsed += delta
	if _elapsed >= maxf(5.0, refresh_minutes) * 60.0:
		refresh()


# --- location -------------------------------------------------------------

## The location chain: an environment override, the machine's own GPS / location
## service, the last fix we cached, and finally IP geolocation. The GPS comes
## first on purpose - only a cached GPS fix is trusted to answer instantly -
## and if none of them can place the pond, `_use_offline` installs the
## 宁波市鄞州区 default.
func _request_device_location() -> void:
	var injected := _env_location()
	if not injected.is_empty():
		_accept_location(injected, "gps")
		return
	# A previous GPS fix is good enough to answer right away; anything else in
	# the cache waits until the location service has had its chance.
	var cached := _cached_location()
	if not cached.is_empty() and String(cached.get("source", "")) == "gps":
		location = cached
		location_source = "gps"
		_fetch_weather()
		return
	if _start_platform_gps():
		_set_status(Status.LOCATING)
		return
	_finish_without_device_fix()


## The location service could not help. Fall back to whatever we cached last
## time - an IP fix is still a fix - and only then to IP geolocation.
func _finish_without_device_fix() -> void:
	var cached := _cached_location()
	if not cached.is_empty():
		location = cached
		location_source = String(cached.get("source", "cache"))
		_fetch_weather()
		return
	_request_geo()


## A fix handed in through `MOKUGYO_GPS` as `"lat,lon[,city]"`.
func _env_location() -> Dictionary:
	var raw := OS.get_environment(GPS_ENV).strip_edges()
	if raw.is_empty():
		return {}
	var parts := raw.split(",")
	if parts.size() < 2:
		return {}
	var lat := float(parts[0].strip_edges())
	var lon := float(parts[1].strip_edges())
	if is_zero_approx(lat) and is_zero_approx(lon):
		return {}
	var city := "本机定位"
	if parts.size() > 2 and not parts[2].strip_edges().is_empty():
		city = parts[2].strip_edges()
	return {
		"latitude": lat,
		"longitude": lon,
		"city": city,
		"timezone": "",
		"source": "gps",
	}


## The last place we resolved, if any. Carries its own `source` so a cached IP
## fix is never passed off as a GPS one.
func _cached_location() -> Dictionary:
	var file := FileAccess.open(LOCATION_PATH, FileAccess.READ)
	if file == null:
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary and parsed.has("latitude"):
		return parsed
	return {}


## Asks the operating system for a location fix. Only Windows exposes one that
## the engine can reach without a plugin, and even there the user has to have
## allowed it - so a failure is completely ordinary and simply falls through.
func _start_platform_gps() -> bool:
	if OS.get_name() != "Windows" or DisplayServer.get_name() == "headless":
		return false
	var fix_path := ProjectSettings.globalize_path(GPS_FIX_PATH)
	DirAccess.remove_absolute(fix_path)
	var file := FileAccess.open(GPS_SCRIPT_PATH, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(WINDOWS_GPS_SCRIPT % fix_path.replace("'", "''"))
	file.close()
	var pid := OS.create_process("powershell.exe", [
		"-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass",
		"-File", ProjectSettings.globalize_path(GPS_SCRIPT_PATH)])
	if pid <= 0:
		return false
	_gps_active = true
	_gps_elapsed = 0.0
	return true


func _poll_device_location(delta: float) -> void:
	_gps_elapsed += delta
	var fix := _read_gps_fix()
	if not fix.is_empty():
		_gps_active = false
		if not _stopped:
			_accept_location(fix, "gps")
		return
	if _gps_elapsed >= GPS_TIMEOUT:
		_gps_active = false
		last_error = "本机定位不可用"
		if not _stopped:
			_finish_without_device_fix()


func _read_gps_fix() -> Dictionary:
	var file := FileAccess.open(GPS_FIX_PATH, FileAccess.READ)
	if file == null:
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if not (parsed is Dictionary):
		return {}
	if not (parsed.has("latitude") and parsed.has("longitude")):
		return {}
	var lat := float(parsed["latitude"])
	var lon := float(parsed["longitude"])
	if is_zero_approx(lat) and is_zero_approx(lon):
		return {}
	return {
		"latitude": lat,
		"longitude": lon,
		"city": "本机定位",
		"timezone": "",
		"source": "gps",
	}


func _accept_location(fix: Dictionary, source: String) -> void:
	location = fix
	location_source = source
	location["source"] = source
	_save_location()
	_fetch_weather()


## A latitude in the project settings wins over everything: it is how a school
## pins the pond to its own city, and how the verification run stays stable.
func _configured_location() -> Dictionary:
	var lat := float(ProjectSettings.get_setting("mokugyo/weather/latitude", 0.0))
	var lon := float(ProjectSettings.get_setting("mokugyo/weather/longitude", 0.0))
	if is_zero_approx(lat) and is_zero_approx(lon):
		return {}
	return {
		"latitude": lat,
		"longitude": lon,
		"city": String(ProjectSettings.get_setting("mokugyo/weather/city", "自定义")),
		"timezone": String(ProjectSettings.get_setting(
			"mokugyo/weather/timezone", "")),
	}


func _request_geo() -> void:
	if _geo_index >= GEO_ENDPOINTS.size():
		_use_offline("无法定位")
		return
	_step = Step.GEO
	_set_status(Status.LOCATING)
	var err := _http.request(GEO_ENDPOINTS[_geo_index])
	if err != OK:
		_geo_index += 1
		_request_geo()


func _geo_result(index: int, data: Dictionary) -> Dictionary:
	match index:
		0:
			if String(data.get("status", "")) != "success":
				return {}
			return {
				"latitude": float(data.get("lat", 0.0)),
				"longitude": float(data.get("lon", 0.0)),
				"city": String(data.get("city", "")),
				"timezone": String(data.get("timezone", "")),
				"source": "ip",
			}
		1:
			if not bool(data.get("success", false)):
				return {}
			return {
				"latitude": float(data.get("latitude", 0.0)),
				"longitude": float(data.get("longitude", 0.0)),
				"city": String(data.get("city", "")),
				"timezone": String(data.get("timezone", "")),
				"source": "ip",
			}
		_:
			var loc: String = String(data.get("loc", ""))
			var parts := loc.split(",")
			if parts.size() < 2:
				return {}
			return {
				"latitude": float(parts[0]),
				"longitude": float(parts[1]),
				"city": String(data.get("city", "")),
				"timezone": String(data.get("timezone", "")),
				"source": "ip",
			}


# --- forecast -------------------------------------------------------------

func _fetch_weather() -> void:
	if location.is_empty():
		_request_geo()
		return
	_step = Step.WEATHER
	_set_status(Status.FETCHING)
	var url := "%s?latitude=%.4f&longitude=%.4f&current=%s&timezone=auto&forecast_days=1" \
		% [FORECAST_URL, location["latitude"], location["longitude"], CURRENT_FIELDS]
	var err := _http.request(url)
	if err != OK:
		_use_offline("网络不可用")


func _on_request_completed(
		result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if _stopped:
		return
	var step := _step
	_step = Step.NONE
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		if step == Step.GEO:
			_geo_index += 1
			_request_geo()
		else:
			_use_offline("请求失败 (%d)" % code)
		return

	var data = JSON.parse_string(body.get_string_from_utf8())
	if not (data is Dictionary):
		if step == Step.GEO:
			_geo_index += 1
			_request_geo()
		else:
			_use_offline("数据无法解析")
		return

	if step == Step.GEO:
		var found := _geo_result(_geo_index, data)
		if found.is_empty():
			_geo_index += 1
			_request_geo()
			return
		location = found
		location_source = String(found.get("source", "ip"))
		_save_location()
		_fetch_weather()
	elif step == Step.WEATHER:
		_accept_open_meteo(data)


func _accept_open_meteo(data: Dictionary) -> void:
	var current: Dictionary = data.get("current", {})
	if current.is_empty():
		_use_offline("缺少 current 数据")
		return
	var code := int(current.get("weather_code", 0))
	report = _decorate({
		"source": "open-meteo",
		"simulated": false,
		"code": code,
		"temperature": float(current.get("temperature_2m", 0.0)),
		"apparent": float(current.get("apparent_temperature", 0.0)),
		"humidity": float(current.get("relative_humidity_2m", 0.0)),
		"precipitation": float(current.get("precipitation", 0.0)),
		"rain": float(current.get("rain", 0.0)),
		"snowfall": float(current.get("snowfall", 0.0)),
		"cloud": float(current.get("cloud_cover", 0.0)) / 100.0,
		"wind": float(current.get("wind_speed_10m", 0.0)),
		"wind_deg": float(current.get("wind_direction_10m", 0.0)),
		"is_day": bool(current.get("is_day", 1)),
		"city": city(),
		"latitude": float(data.get("latitude", location.get("latitude", 0.0))),
		"longitude": float(data.get("longitude", location.get("longitude", 0.0))),
		"timezone": String(data.get("timezone", location.get("timezone", ""))),
		"observed": String(current.get("time", "")),
		"updated_unix": Time.get_unix_time_from_system(),
	})
	_save_report()
	_set_status(Status.READY)
	report_changed.emit(report)


## Fills in the fields the scene derives rather than reads: the WMO label, how
## much hail the code implies, and the severe-weather classification. Every
## source - live, simulated or forced - goes through here, so a report always
## describes the same storm no matter where it came from.
func _decorate(source: Dictionary) -> Dictionary:
	var decorated := source
	var code := int(decorated.get("code", 0))
	var profile := SkyState.weather_profile(code)
	if not decorated.has("label") or String(decorated["label"]).is_empty():
		decorated["label"] = profile["label"]
	if not decorated.has("hail"):
		decorated["hail"] = float(profile["hail"])
	var thunder := bool(decorated.get("thunder", profile["thunder"]))
	decorated["thunder"] = thunder
	var severe := SkyState.severe_state(
		float(decorated.get("wind", 0.0)), float(decorated["hail"]), thunder)
	decorated["severe_level"] = int(severe["level"])
	decorated["severe_title"] = String(severe["title"])
	decorated["typhoon"] = bool(severe["typhoon"])
	if bool(severe["typhoon"]):
		decorated["label"] = "台风"
	return decorated


# --- offline / simulated --------------------------------------------------

## Falls back to the cache, then to a simulated forecast, then to the built-in
## default location. Never leaves `report` empty.
func _use_offline(reason: String) -> void:
	last_error = reason
	var cached := _load_cached_report()
	if not cached.is_empty() and _report_age(cached) < STALE_SECONDS:
		report = cached
		report["source"] = "cache"
		report["simulated"] = false
		report["note"] = reason
		_set_status(Status.CACHED)
		report_changed.emit(report)
		return
	if location.is_empty():
		location = {
			"latitude": DEFAULT_LATITUDE,
			"longitude": DEFAULT_LONGITUDE,
			"city": DEFAULT_CITY,
			"timezone": "",
			"source": "default",
		}
		location_source = "default"
	report = simulated_report()
	report["note"] = reason
	_set_status(Status.OFFLINE)
	report_changed.emit(report)


## A plausible forecast for today that needs no network. It is seeded from the
## date, so the pond is stable within a day and changes overnight - the scene
## still has seasons and weather even on a machine that is offline for months.
func simulated_report() -> Dictionary:
	var date := Time.get_date_dict_from_system()
	var doy := SkyState.day_of_year(
		int(date.get("year", 2026)), int(date.get("month", 1)), int(date.get("day", 1)))
	var lat := float(location.get("latitude", DEFAULT_LATITUDE))
	var season := SkyState.season_index(doy, lat)

	var rng := RandomNumberGenerator.new()
	rng.seed = hash("mokugyo-%d-%d-%d" % [
		int(date.get("year", 2026)), int(date.get("month", 1)), int(date.get("day", 1))])

	var pools := [
		[0, 0, 1, 1, 2, 2, 51, 61, 80],        # spring
		[0, 0, 0, 1, 2, 2, 3, 80, 95],         # summer
		[0, 1, 1, 2, 2, 3, 45, 51, 61, 63],    # autumn
		[0, 0, 1, 2, 3, 45, 71, 73, 75],       # winter
	]
	var code: int = pools[season][rng.randi_range(0, pools[season].size() - 1)]
	# Show the severe end of the weather too: a summer or autumn evening can
	# roll in a hailstorm or a typhoon instead of another grey drizzle.
	var typhoon := (season == 1 or season == 2) and rng.randf() < 0.10
	var hail := (season == 1 or season == 3) and rng.randf() < 0.12
	var wind := rng.randf_range(2.0, 26.0)
	if typhoon:
		code = 82
		wind = rng.randf_range(120.0, 185.0)
	elif hail:
		code = 99
		wind = rng.randf_range(45.0, 70.0)
	var profile := SkyState.weather_profile(code)

	var base_temp: float = [16.0, 29.0, 17.0, 3.0][season]
	base_temp += -absf(lat) * 0.16 + 7.2
	var temperature: float = base_temp + rng.randf_range(-4.0, 4.0)
	var cloud := clampf(profile["cloud"] + rng.randf_range(-0.1, 0.1), 0.0, 1.0)
	return _decorate({
		"source": "simulated",
		"simulated": true,
		"code": code,
		"label": profile["label"],
		"temperature": snappedf(temperature, 0.1),
		"apparent": snappedf(temperature - rng.randf_range(0.0, 3.0), 0.1),
		"humidity": snappedf(rng.randf_range(35.0, 92.0), 1.0),
		"precipitation": snappedf(profile["rain"] * rng.randf_range(0.0, 6.0), 0.1),
		"rain": snappedf(profile["rain"], 0.01),
		"snowfall": snappedf(profile["snow"] * rng.randf_range(0.0, 2.0), 0.1),
		"cloud": snappedf(cloud, 0.01),
		"wind": snappedf(wind, 1.0),
		"wind_deg": snappedf(rng.randf_range(0.0, 360.0), 1.0),
		"is_day": true,
		"city": city(),
		"latitude": lat,
		"longitude": float(location.get("longitude", DEFAULT_LONGITUDE)),
		"timezone": String(location.get("timezone", "")),
		"observed": "",
		"updated_unix": Time.get_unix_time_from_system(),
	})


# --- persistence ----------------------------------------------------------

func _save_location() -> void:
	var file := FileAccess.open(LOCATION_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(location))


func _save_report() -> void:
	var file := FileAccess.open(CACHE_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report))


func _load_cached_report() -> Dictionary:
	var file := FileAccess.open(CACHE_PATH, FileAccess.READ)
	if file == null:
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Dictionary else {}


func _set_status(value: int) -> void:
	if status == value:
		return
	status = value
	status_changed.emit(status_text())
