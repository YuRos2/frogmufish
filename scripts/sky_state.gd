class_name SkyState
extends RefCounted

## "What should the world look like right now?" - the entire day/night and
## weather model as pure maths.
##
## Nothing here touches a node, a resource or the network. Hand it a clock
## reading, a latitude, a day of the year and a weather code, and it returns one
## flat dictionary of colours, light directions, fog and particle amounts.
## `sky_cycle.gd` eases that dictionary into the real sky and lights, and
## `weather_fx.gd` reads the rain / snow / wind back out of it.
##
## Keeping the model pure matters for two reasons: it is the part worth testing
## (see `tools/verify_froggreen.gd`), and a headless run can render a noon sky, a
## midnight sky or a thunderstorm without waiting for the real clock or the
## real weather.
##
## World axes are the ones the scene already uses: `+X` east, `+Y` up and
## `-Z` north, so a positive `key_direction.x` really does put the sun in the
## east and the sky above the pond follows it.

## How far the sun's declination swings over the year.
const AXIAL_TILT := 23.44
## The sun's apparent elevation at the moment it touches the horizon: the solar
## disc's radius plus the atmosphere's refraction, in radians.
const HORIZON_ELEVATION := -0.01454

## Palette keys for the four seasonal tints that nudge the horizon and the
## ambient fill. Subtle on purpose: they should be felt, not noticed.
const SEASON_TINTS := [
	Color("ffd9e2"),  # spring: cherry blossom
	Color("d8f5e2"),  # summer: fresh leaf
	Color("ffe0bd"),  # autumn: amber
	Color("dbe8ff"),  # winter: cold light
]
const SEASON_TITLES := ["春", "夏", "秋", "冬"]

# --- base looks -----------------------------------------------------------
# Two anchored palettes - deep night and open noon - that everything else is
# blended from. They match the original macaron scene at midday, so a clear
# afternoon still looks exactly like the artwork it was built from.

const NIGHT_SKY_TOP := Color("0d1226")
const NIGHT_SKY_HORIZON := Color("232c52")
const NIGHT_SKY_CURVE := 0.16
const NIGHT_GROUND_BOTTOM := Color("070b10")
const NIGHT_GROUND_HORIZON := Color("18202e")
const NIGHT_AMBIENT := Color("5b6fb4")
const NIGHT_AMBIENT_ENERGY := 0.44
const NIGHT_KEY := Color("c7d6ff")
const NIGHT_KEY_ENERGY := 0.40

const DAY_SKY_TOP := Color("bfe3f5")
const DAY_SKY_HORIZON := Color("ffeef2")
const DAY_SKY_CURVE := 0.15
const DAY_GROUND_BOTTOM := Color("3f6f57")
const DAY_GROUND_HORIZON := Color("d3ecd0")
const DAY_AMBIENT := Color("dbd0f0")
const DAY_AMBIENT_ENERGY := 0.72
const DAY_KEY := Color("fff2e1")
const DAY_KEY_ENERGY := 1.0

## A peach wash that only shows while the sun sits near the horizon.
const HORIZON_WARM := Color("ff9f6b")

## Overcast and storm skies. Deep cloud is almost neutral grey so it reads as
## weather rather than as a colour choice.
const OVERCAST_TOP := Color("9aa3b2")
const OVERCAST_HORIZON := Color("c6cad2")
const STORM_TOP := Color("5d6472")
const STORM_HORIZON := Color("8a909c")
const SNOW_TOP := Color("8f9db5")
const SNOW_HORIZON := Color("ccd6e4")

const FOG_COLOR_DAY := Color("dfe3e8")
const FOG_COLOR_NIGHT := Color("1c2230")


## Maps a WMO weather code (the ones Open-Meteo returns) onto the handful of
## things the scene actually reacts to. `cloud` is the fraction of the sky the
## clouds cover, so it works even when the API reports a different cloud_cover.
static func weather_profile(code: int) -> Dictionary:
	var cloud := 0.12
	var rain := 0.0
	var snow := 0.0
	var thunder := false
	var fog := 0.0
	var hail := 0.0
	var label := "晴"
	match code:
		0:
			label = "晴"
			cloud = 0.06
		1:
			label = "晴间多云"
			cloud = 0.30
		2:
			label = "多云"
			cloud = 0.62
		3:
			label = "阴"
			cloud = 0.94
		45:
			label = "有雾"
			cloud = 0.80
			fog = 0.75
		48:
			label = "雾凇"
			cloud = 0.85
			fog = 1.0
		51, 53:
			label = "毛毛雨"
			cloud = 0.86
			rain = 0.22
		55:
			label = "细雨"
			cloud = 0.92
			rain = 0.34
		56, 57:
			label = "冻毛毛雨"
			cloud = 0.92
			rain = 0.30
		61:
			label = "小雨"
			cloud = 0.90
			rain = 0.46
		63:
			label = "中雨"
			cloud = 0.96
			rain = 0.70
		65:
			label = "大雨"
			cloud = 1.0
			rain = 1.0
		66, 67:
			label = "冻雨"
			cloud = 1.0
			rain = 0.82
		71:
			label = "小雪"
			cloud = 0.90
			snow = 0.42
		73:
			label = "中雪"
			cloud = 0.96
			snow = 0.72
		75:
			label = "大雪"
			cloud = 1.0
			snow = 1.0
		77:
			label = "米雪"
			cloud = 0.90
			snow = 0.50
		80:
			label = "阵雨"
			cloud = 0.74
			rain = 0.50
		81:
			label = "强阵雨"
			cloud = 0.86
			rain = 0.76
		82:
			label = "暴雨"
			cloud = 1.0
			rain = 1.0
		85:
			label = "阵雪"
			cloud = 0.86
			snow = 0.60
		86:
			label = "强阵雪"
			cloud = 1.0
			snow = 0.95
		95:
			label = "雷阵雨"
			cloud = 1.0
			rain = 0.80
			thunder = true
		96, 99:
			label = "雷雨冰雹"
			cloud = 1.0
			rain = 0.92
			snow = 0.10
			hail = 0.9 if code == 99 else 0.65
			thunder = true
		_:
			label = "未知"
			cloud = 0.30
	return {
		"code": code,
		"label": label,
		"cloud": cloud,
		"rain": rain,
		"snow": snow,
		"hail": hail,
		"thunder": thunder,
		"fog": fog,
	}


## Severe convective weather is not one WMO code: it is what the *numbers*
## say. A report can be a plain thunderstorm, a hailstorm, a tropical storm or
## a full typhoon, and the scene has to know which of those it is looking at.
##
## `wind_kmh` is the sustained wind speed in km/h (Open-Meteo's default unit),
## `hail` the 0..1 amount from `weather_profile`, and `thunder` the same. The
## returned `level` runs 0 quiet, 1 thunderstorm, 2 hail / tropical storm and
## 3 typhoon, which is what the rain, the lightning rate and the sky darkening
## are all scaled from.
static func severe_state(wind_kmh: float, hail: float, thunder: bool) -> Dictionary:
	var level := 0
	var titles := PackedStringArray()
	if thunder:
		level = maxi(level, 1)
		titles.append("雷暴")
	if hail >= 0.4:
		level = maxi(level, 2)
		titles.append("冰雹")
	if wind_kmh >= 62.0:
		level = maxi(level, 1)
		titles.append("热带风暴" if wind_kmh < 89.0 else "强热带风暴")
	if wind_kmh >= 118.0:
		level = 3
		titles = PackedStringArray(["台风"])
	return {
		"level": level,
		"title": " · ".join(titles),
		"typhoon": wind_kmh >= 118.0,
		"tropical": wind_kmh >= 62.0,
	}


## Where the sun is for a given local clock time. `hours` is a float 0..24, so
## 12.5 is half past noon, and `day_of_year` is 1..366. The returned
## `direction` points from the pond towards the sun and is already normalised.
static func solar(hours: float, latitude_deg: float, day_of_year: int) -> Dictionary:
	var lat := deg_to_rad(clampf(latitude_deg, -89.0, 89.0))
	var decl := deg_to_rad(AXIAL_TILT) \
		* sin(TAU * (float(day_of_year) - 81.0) / 365.0)
	var hour_angle := deg_to_rad((hours - 12.0) * 15.0)
	var sin_elev := sin(lat) * sin(decl) + cos(lat) * cos(decl) * cos(hour_angle)
	var elevation := asin(clampf(sin_elev, -1.0, 1.0))
	# The textbook azimuth is measured from south and grows towards the west;
	# the +PI makes it a compass bearing, and the axis flip below turns that
	# into the scene's (+X east, -Z north) world.
	var az_south := atan2(
		sin(hour_angle), cos(hour_angle) * sin(lat) - tan(decl) * cos(lat))
	var compass := az_south + PI
	var cos_elev := cos(elevation)
	var direction := Vector3(
		sin(compass) * cos_elev, sin(elevation), -cos(compass) * cos_elev)
	return {
		"direction": direction.normalized(),
		"elevation": elevation,
		"azimuth": compass,
		"declination": decl,
	}


## Local clock hours for sunrise and sunset, plus the polar edge cases. The
## approximation gets within a couple of minutes of a nautical almanac, which
## is far more than the pond needs.
static func sunrise_sunset(latitude_deg: float, day_of_year: int) -> Dictionary:
	var lat := deg_to_rad(clampf(latitude_deg, -89.0, 89.0))
	var decl := deg_to_rad(AXIAL_TILT) \
		* sin(TAU * (float(day_of_year) - 81.0) / 365.0)
	var elev0 := deg_to_rad(-0.833)
	var denominator := cos(lat) * cos(decl)
	if absf(denominator) < 1e-6:
		return {"sunrise": -1.0, "sunset": -1.0,
			"polar_day": false, "polar_night": true}
	var cos_h := (sin(elev0) - sin(lat) * sin(decl)) / denominator
	if cos_h <= -1.0:
		return {"sunrise": 0.0, "sunset": 24.0,
			"polar_day": true, "polar_night": false}
	if cos_h >= 1.0:
		return {"sunrise": -1.0, "sunset": -1.0,
			"polar_day": false, "polar_night": true}
	var half := rad_to_deg(acos(cos_h)) / 15.0
	return {"sunrise": 12.0 - half, "sunset": 12.0 + half,
		"polar_day": false, "polar_night": false}


## 0 spring, 1 summer, 2 autumn, 3 winter, hemisphere aware.
static func season_index(day_of_year: int, latitude_deg: float) -> int:
	var doy := ((day_of_year - 1) % 366 + 366) % 366 + 1
	var index := 3  # winter by default
	if doy >= 60 and doy <= 151:
		index = 0
	elif doy >= 152 and doy <= 243:
		index = 1
	elif doy >= 244 and doy <= 334:
		index = 2
	if latitude_deg < 0.0:
		index = [2, 3, 0, 1][index]
	return index


## The one call the rest of the project uses. `weather_code` comes from the WMO
## set; pass -1 for "just time of day, no weather". `cloud_cover` (0..1) is
## optional and sharpens the cloud amount when the API reported it directly.
static func look(
		hours: float,
		latitude_deg: float,
		day_of_year: int,
		weather_code: int = 0,
		cloud_cover: float = -1.0,
		wind_speed: float = 0.0) -> Dictionary:
	var weather := weather_profile(weather_code)
	var cloud: float = weather["cloud"]
	if cloud_cover >= 0.0:
		cloud = clampf(cloud_cover, 0.0, 1.0)
	var rain: float = weather["rain"]
	var snow: float = weather["snow"]
	var hail: float = weather["hail"]
	var thunder: bool = weather["thunder"]
	var fog_amount: float = weather["fog"]
	var severe := severe_state(wind_speed, hail, thunder)
	var severe_level: int = severe["level"]
	var storm_mix := clampf(float(severe_level) / 3.0, 0.0, 1.0)

	var sol := solar(hours, latitude_deg, day_of_year)
	var elevation: float = sol["elevation"]
	var direction: Vector3 = sol["direction"]

	# `day` is the master blend: 0 deep night, 1 open day. The wide band from
	# astronomical night to a few degrees of altitude is what gives the scene a
	# real twilight instead of a hard switch.
	var day := smoothstep(-0.185, 0.05, elevation)
	# Only while the sun is close to the horizon: the warm wash.
	var horizon := clampf(1.0 - absf(elevation) / 0.30, 0.0, 1.0)
	# The moon rides opposite the sun, so there is always a directional light.
	var moon := -direction

	var season := season_index(day_of_year, latitude_deg)
	var tint: Color = SEASON_TINTS[season]

	var sky_top: Color = NIGHT_SKY_TOP.lerp(DAY_SKY_TOP, day)
	var sky_horizon: Color = NIGHT_SKY_HORIZON.lerp(DAY_SKY_HORIZON, day)
	var ground_bottom: Color = NIGHT_GROUND_BOTTOM.lerp(DAY_GROUND_BOTTOM, day)
	var ground_horizon: Color = NIGHT_GROUND_HORIZON.lerp(DAY_GROUND_HORIZON, day)
	var ambient: Color = NIGHT_AMBIENT.lerp(DAY_AMBIENT, day)
	var ambient_energy := lerpf(NIGHT_AMBIENT_ENERGY, DAY_AMBIENT_ENERGY, day)
	var key: Color = NIGHT_KEY.lerp(DAY_KEY, day)
	var key_energy := lerpf(NIGHT_KEY_ENERGY, DAY_KEY_ENERGY, day)
	var key_direction := direction
	if elevation < HORIZON_ELEVATION:
		key_direction = moon
		key_energy = lerpf(NIGHT_KEY_ENERGY, 0.0, day)

	# Season: a whisper of tint on the horizon wash and the fill light.
	sky_horizon = sky_horizon.lerp(tint, 0.10)
	ground_horizon = ground_horizon.lerp(tint, 0.08)
	sky_horizon = sky_horizon.lerp(HORIZON_WARM, horizon * (1.0 - cloud) * 0.85)

	# --- weather ----------------------------------------------------------
	if cloud > 0.0:
		var over_top := OVERCAST_TOP
		var over_horizon := OVERCAST_HORIZON
		if snow > 0.0:
			over_top = over_top.lerp(SNOW_TOP, snow)
			over_horizon = over_horizon.lerp(SNOW_HORIZON, snow)
		if rain > 0.0:
			over_top = over_top.lerp(STORM_TOP, rain)
			over_horizon = over_horizon.lerp(STORM_HORIZON, rain)
		# Overcast skies at night are not grey, they are the same darkness with
		# the stars switched off.
		over_top = over_top.lerp(NIGHT_SKY_TOP.lerp(over_top, 0.35), 1.0 - day)
		over_horizon = over_horizon.lerp(
			NIGHT_SKY_HORIZON.lerp(over_horizon, 0.35), 1.0 - day)
		sky_top = sky_top.lerp(over_top, cloud)
		sky_horizon = sky_horizon.lerp(over_horizon, cloud)
		ground_horizon = ground_horizon.lerp(over_horizon.darkened(0.18), cloud * 0.7)

	# The sun is what makes a day bright. Thick cloud puts it out and leaves the
	# scene lit mostly by the sky, so the ambient goes *up* while the key drops.
	key_energy *= lerpf(1.0, 0.14, cloud)
	key = key.lerp(OVERCAST_HORIZON, cloud * 0.5)
	ambient_energy *= lerpf(1.0, 0.92, cloud)
	if thunder:
		key_energy *= 0.7
		ambient_energy *= 0.9
	if severe_level > 0:
		# A severe cell drains the colour out of the sky and puts the sun out
		# altogether; the pond is lit by the storm itself.
		sky_top = sky_top.lerp(Color("3f4552"), storm_mix * 0.5)
		sky_horizon = sky_horizon.lerp(Color("6d736f"), storm_mix * 0.45)
		ground_horizon = ground_horizon.lerp(Color("4a5350"), storm_mix * 0.35)
		key_energy *= lerpf(1.0, 0.32, storm_mix)
		ambient_energy *= lerpf(1.0, 0.82, storm_mix)
		ambient = ambient.lerp(Color("8a93a6"), storm_mix * 0.25)
	if hail > 0.0:
		ambient = ambient.lerp(SNOW_HORIZON, hail * 0.16)
	if snow > 0.0:
		# Snow bounces a lot of light back up; the scene never goes as dark.
		ambient_energy *= 1.06
		ambient = ambient.lerp(SNOW_HORIZON, snow * 0.22)
	# Fog flattens everything into the sky, so the fill light gains a little.
	var fill_energy := 0.40 * lerpf(0.42, 1.0, day)
	var rim_energy := 0.26 * lerpf(0.30, 1.0, day) * lerpf(1.0, 0.35, cloud)

	# --- fog --------------------------------------------------------------
	var fog_density := 0.0
	if fog_amount > 0.0:
		fog_density = lerpf(0.05, 0.16, fog_amount)
	fog_density += rain * 0.045 + snow * 0.03 + hail * 0.035
	if thunder:
		fog_density += 0.02
	if severe_level >= 2:
		fog_density += 0.03 * storm_mix
	var fog_color: Color = FOG_COLOR_NIGHT.lerp(FOG_COLOR_DAY, day)
	fog_color = fog_color.lerp(sky_horizon, 0.35)
	fog_color = fog_color.lerp(FOG_COLOR_DAY, fog_amount * 0.5)
	var fog_on := fog_density > 0.004

	# --- stars ------------------------------------------------------------
	var star_opacity := (1.0 - smoothstep(-0.16, 0.01, elevation)) \
		* (1.0 - cloud * 0.96) * (1.0 - fog_amount) \
		* smoothstep(0.02, 0.35, 1.0 - fog_amount)
	star_opacity = clampf(star_opacity, 0.0, 1.0)

	# --- the pond ---------------------------------------------------------
	var water := Color("35604a")
	var water_rough := 0.20
	var water_ripple := 1.0
	water = water.lerp(Color("16281f"), 1.0 - day)
	water = water.lerp(Color("20362c"), cloud * 0.5)
	water = water.lerp(Color("16262a"), rain)
	water = water.lerp(Color("6f8f92"), snow)
	water = water.lerp(Color("1b2c33"), storm_mix * 0.7)
	water_rough = lerpf(water_rough, 0.42, rain)
	water_rough = lerpf(water_rough, 0.55, snow)
	water_rough = lerpf(water_rough, 0.34, cloud * 0.4)
	water_rough = lerpf(water_rough, 0.62, storm_mix)
	water_ripple = 1.0 + wind_speed * 0.05 + rain * 3.0 + storm_mix * 2.0
	water_ripple = minf(water_ripple, 12.0)

	# --- lightning --------------------------------------------------------
	# How many strikes a minute the storm should throw. `weather_fx.gd` turns
	# this into the gap between bolts, so a bad cell flickers constantly while a
	# single thunderstorm rumbles now and then.
	var lightning_rate := 0.0
	if thunder:
		lightning_rate = 8.0 + rain * 18.0 + float(severe_level) * 10.0
	if bool(severe["typhoon"]):
		lightning_rate += 10.0

	return {
		"hour": hours,
		"day_of_year": day_of_year,
		"latitude": latitude_deg,
		"season": season,
		"season_title": SEASON_TITLES[season],
		"sun": sol,
		"sun_elevation": elevation,
		"sun_azimuth": sol["azimuth"],
		"sunrise": sunrise_sunset(latitude_deg, day_of_year),
		"daylight": day,
		"phase_title": phase_title(hours, elevation),
		"sky_top": sky_top,
		"sky_horizon": sky_horizon,
		"sky_curve": lerpf(NIGHT_SKY_CURVE, DAY_SKY_CURVE, day),
		"ground_bottom": ground_bottom,
		"ground_horizon": ground_horizon,
		"ambient_color": ambient,
		"ambient_energy": ambient_energy,
		"key_direction": key_direction,
		"key_color": key,
		"key_energy": key_energy,
		"fill_color": ambient.lerp(sky_horizon, 0.35),
		"fill_energy": fill_energy,
		"rim_color": ambient.lerp(sky_horizon, 0.5),
		"rim_energy": rim_energy,
		"fog": fog_on,
		"fog_color": fog_color,
		"fog_density": fog_density,
		"fog_aerial": clampf(fog_density * 3.0, 0.0, 0.7),
		"star_opacity": star_opacity,
		"glow_intensity": lerpf(0.06, 0.12, day),
		"glow_bloom": 0.03,
		"weather": weather,
		"weather_label": weather["label"],
		"cloud": cloud,
		"rain": rain,
		"snow": snow,
		"hail": hail,
		"thunder": thunder,
		"fog_amount": fog_amount,
		"severe_level": severe_level,
		"severe_title": severe["title"],
		"typhoon": severe["typhoon"],
		"storm_mix": storm_mix,
		"lightning_rate": lightning_rate,
		"wind": wind_speed,
		"water_color": water,
		"water_roughness": water_rough,
		"water_ripple": water_ripple,
	}


## "夜晚" / "黄昏" / "白天" ... a short word for the HUD and for tests.
static func phase_title(hours: float, elevation: float) -> String:
	if elevation > 0.25:
		return "白天"
	if elevation > 0.0:
		return "上午" if hours < 12.0 else "下午"
	if elevation > -0.12:
		return "清晨" if hours < 12.0 else "黄昏"
	return "夜晚"


## True when the sun is up, refraction included. Used by the HUD to decide
## whether to talk about sunrise or sunset.
static func is_daylight(elevation: float) -> bool:
	return elevation > HORIZON_ELEVATION


static func is_leap_year(year: int) -> bool:
	return (year % 4 == 0 and year % 100 != 0) or year % 400 == 0


## Day of the year for a calendar date, 1..366. Kept here so the weather and
## the sky agree on what "today" means without touching the Time singleton.
static func day_of_year(year: int, month: int, day: int) -> int:
	var lengths := [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
	if is_leap_year(year):
		lengths[1] = 29
	var doy := clampi(day, 1, 31)
	for i in clampi(month - 1, 0, 11):
		doy += lengths[i]
	return doy
