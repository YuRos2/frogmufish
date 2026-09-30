# 番茄木鱼 Pomodoro Mokugyo Frog

A **macaron-coloured 3D pomodoro timer** for primary and secondary school pupils,
built for **Godot 4.7**. The UI is deliberately large, colourful and emoji-rich
so younger children can use it on their own. A frog-shaped electronic mokugyo
sits on a lotus leaf floating on a deep-green pond: the timer counts focus and
break blocks, the frog reacts to each phase, and tapping it with a lotus-bud
mallet earns 功德.

The frog and the striker now come from the companion **`Documents/froggreen`**
project: `assets/models/frog_muyu.glb` was rebuilt in Blender from the author's
own reference photos and ships a real head, a real lower jaw, painted eyes,
nose and blush, and the wooden **striker**. The pond and the lotus leaf are
still built procedurally from Godot primitives - see [The pond](#the-pond).

The striker rests **horizontally in the frog's mouth** - exactly like the real
toy. Tapping the frog drops the jaw open and snaps it shut around the striker,
plays a mokugyo "tok", blinks and squashes the frog, and pops a **功德+1**. A
press of the auto-tap key is not one knock but a **continuous, even run of
10-20 taps**, because a mokugyo is played as a rhythm.

## 番茄时钟 Pomodoro

The timer lives in `scripts/pomodoro.gd` and knows nothing about frogs or
clocks: it counts down and emits signals, and `main.gd` turns those into stage
reactions.

| Phase | Default | Scene | Frog |
| --- | --- | --- | --- |
| 专注 Focus | 15 min | focus accent on the HUD | attentive, gentle breathing |
| 短休息 Short break | 3 min | break accent on the HUD | half-closed eyes, slow breathing, head tilt |
| 长休息 Long break | 9 min | long-break accent | the same nap, lasting longer |

The defaults are tuned for younger pupils; the 25 and 45 minute presets are still
available for older children who can focus longer.
| 番茄完成 | - | lotus petals | a **10-20 tap mokugyo run**, then hops and showers lotus petals |

Every fourth focus block is followed by a long break instead of a short one. The
HUD has **15 / 25 / 45** minute presets, start/pause, skip and reset, plus a
**60x demo speed** so a whole cycle can be shown to a class in about a minute.

When a focus block finishes, the mallet swings on its own and plays a
**continuous 10-20 tap run**, and the lotus petals only fall after the last tap.
Each of those taps counts as merit, so a full session earns a lot of 功德. The
petals are a small hand-built mesh (milky base,
deep-pink tip) rather than flat confetti squares, so they flutter and turn
edge-on as they fall.

The countdown panel in the top-right shows the **local time of day** just under
the remaining time, in the same colour and shape as the countdown itself, so the
time is still always visible now that the analogue face is gone.

## 天气与日夜 Weather and daylight

The pond is no longer lit by a fixed studio key light. It sits under a real sky:
the sun rises and sets according to **the date, the local clock and the pond's
latitude**, and the local forecast decides whether that sun is visible at all.
Nothing about the scene is baked in - a clear July noon, a rainy November dusk
and a snowy February evening are all the same code with different inputs.

The model is split from the hardware so it can be tested on its own:

* `scripts/sky_state.gd` is **pure maths**. Give it a clock reading, a latitude,
a day of the year and a WMO weather code and it returns one flat dictionary: the
sun's direction and elevation, the sky and ground colours, the ambient fill, the
key/fill/rim light colours and energies, the fog, the star opacity, and how the
water should look. The solar position is the real one - the day length grows and
shrinks with the seasons, the sun rises in the east, and the hemisphere flip
means July is summer in Beijing and winter in Sydney.
* `scripts/weather.gd` finds out where we are and what the sky is doing. It
resolves the location from the best source that answers, in this order: the
project settings, an **environment override** (`MOKUGYO_GPS="lat,lon[,city]"`),
the machine's own **GPS / location service** (on Windows, through the Windows
location API), the last fix cached under `user://`, then IP geolocation
(`ip-api.com`, `ipwho.is`, `ipinfo.io`). When none of them can place the pond it
defaults to **宁波市鄞州区** (`weather.DEFAULT_CITY`, 29.8161 N 121.5453 E).
Finally it asks [Open-Meteo](https://open-meteo.com) for the current conditions -
no API key is needed. The report is cached, so a later offline run still knows
the last real forecast, and the HUD's source line says which route was taken
(`本机定位` / `网络定位` / `上次位置` / `默认位置`).
* `scripts/sky_cycle.gd` eases that dictionary into the actual scene: the
`ProceduralSkyMaterial`, the three lights, the ambient fill, the fog, a
billboarded **star dome**, and **sun and moon discs** that ride the same
directions as the lights. Weather changes roll in over a couple of seconds
instead of popping.
* `scripts/weather_fx.gd` makes the weather *fall*: rain streaks, drifting snow,
hailstones, wind that sways the lotus leaf, and lightning that flashes the whole
scene. The strike rate comes from `SkyState`, so a bad cell flickers constantly
with forked chains while an ordinary thunderstorm only rumbles now and then.
* `scripts/pond.gd` answers too - the water darkens and roughens in rain, pales
under snow, quickens in wind, and stipples with short-lived rain rings.

### 强对流 Severe convective weather

Not every storm is a drizzle. `SkyState.severe_state()` reads the *numbers* of a
report - the sustained wind, the hail amount and whether it is thundering - and
classifies it on a 0-3 scale: **0** quiet, **1** thunderstorm, **2** hail or
tropical storm, **3** typhoon (≥ 118 km/h). WMO codes 96 and 99 (`雷雨冰雹`) carry
the hail, and a typhoon lights up any heavy-rain code once the wind is strong
enough. The `look()` dictionary then darkens the sky, thickens the fog, churns
the water, raises the lightning rate and hands `weather_fx.gd` a hail amount and
a gust factor, so the rain slants harder and the leaf is whipped around.

The environment panel raises a `⚠` warning line naming whatever is overhead
whenever a fetched report actually reports it - a **雷暴**, a **冰雹** storm or a
**台风** - and a real storm of level 2 or worse raises a banner on its own. The
demo is never staged ahead of the sky: it follows the report.

The HUD's **环境 / environment panel** in the bottom-left has today's
date and season, the temperature and what the sky is doing, the sunrise and
sunset the model worked out for the latitude, and where the numbers came from.
**This build hides that panel** (`EnvPanel.visible = false`): the frog and the
striker are the whole show. The sky, the lights and the weather simulation still
run exactly as before - only the read-out is out of the frame.
Two controls sit in it:

| Control | What it does |
| --- | --- |
| **同步天气** | Fetch the local forecast again. |
| **跟随时间** (switch) | On, the sun follows the wall clock. Off, the sky freezes at the current hour, so one moment of the day can be studied without it moving. |

**When there is no network** the panel says so instead of pretending. It falls
back to the last cached forecast, and if there has never been one it *simulates*
a plausible day seeded from the date (`weather.simulated_report()`), labelled
`模拟天气`. That keeps the scene changing with the season and the time of day
even on a machine that has never been online, without passing made-up numbers
off as a real forecast.

**Settings.** The pond pins itself to a city by filling these in under
**Project Settings -> mokugyo/weather**:

| Setting | Default | Meaning |
| --- | --- | --- |
| `latitude` / `longitude` | `0.0` | Set both to skip geolocation and use a fixed place. |
| `city` | `""` | The name shown in the HUD when the location is pinned. |
| `use_network` | `true` | Set to `false` to stay offline and use the simulation. |
| `refresh_minutes` | `20.0` | How often the forecast is fetched again. |

Set `MOKUGYO_GPS="29.87,121.55,家"` in the environment to hand the pond a GPS
fix directly - it is how a wrapper script or a CI run pins the location without
touching the project file.

The verification harness pins the clock to a clear noon and takes the network
out of the run, so the lighting checks mean the same thing at 3 am as at noon;
see [Verification](#verification).

## Running

```
godot --path .
```

## Controls

| Input | Action |
| --- | --- |
| **Left click** | Start a continuous mokugyo run on the frog. |
| **Space** | The same run: the striker lifts out of the mouth and lands a **random 10-20 rhythmic taps** on the frog's crown, chomping the jaw on every hit, then returns to the mouth. |
| **R** | Put the striker straight back in the mouth. |
| **T** | Start / pause / resume the pomodoro. |
| **N** | Skip to the next pomodoro phase. |
| **D** | Toggle the 60x demo speed. |
| **HUD buttons** | ▶ Start/pause, ⏭ skip, ↺ reset, 🚀 demo and the 🍅 15 / 📚 25 / 🎯 45 minute presets. |
| **🌤 同步天气** (HUD) | Fetch the local weather again. |
| **⏰ 跟随时间** (HUD switch) | Freeze or resume the sun following the wall clock. |
| **Right mouse drag** | Orbit the camera. |
| **Mouse wheel** | Zoom. |

## The pond

The frog no longer sits on a table with a cream place mat. It rests on a
**lotus leaf** that floats on a **deep-green macaron pond**:

* `scripts/pond.gd` draws the water: one oversized plane in `Palette.POND`,
  with a low roughness so the pastel sky reflects off it, a **procedural tiling
  normal map** (crossing sine waves, scrolled slowly) for a moving shimmer, and
  a few rings that ripple outward around the leaf.
* `scripts/lotus_leaf.gd` builds the leaf as a hand-made `ArrayMesh`: a
  scalloped-edged, gently cupped disc with the classic **radial slit** and
  face-averaged normals. Its colour - a green body, a deeper edge and lighter
  radial veins - is painted into an `ImageTexture` at load time, so there is
  still no imported asset to track. The surface stays flat out to about two
  thirds of the radius, because the frog rests on the physics floor at `y = 0`;
  only the outer rim curls up.

The lotus-bud mallet that used to dress the striker is gone: the striker is now
the wooden mallet that ships inside the froggreen GLB, and the old
`frog_mokugyo.glb`, `frog_mokugyo_photo.glb` and `mallet.glb` assets were
deleted with it.

The old analogue alarm clock has been removed: its dial, twelve numerals,
second/minute/hour hands and bells are all gone, along with the retired
`scripts/clock_3d.gd` and `scenes/clock_3d.tscn`.

## Macaron palette

Every colour in the *models and the HUD* comes from `scripts/palette.gd`:
powder-blue sky, strawberry-milk horizon, deep-green pond, mint lotus leaf and
pastel mint / peach / rose / lemon / lavender / sky accents. The same palette
drives `resources/theme/macaron_theme.tres`, which is set as the project's
default GUI theme, so the HUD panels, buttons and progress bar stay consistent
with the 3D scene. Re-theming the whole project means editing that one file.

The sky and the lights are the exception: they are not a fixed palette any more
but the output of `scripts/sky_state.gd`. Its clear noon is anchored to the
original powder-blue / strawberry-milk colours, so an ordinary afternoon still
looks like the artwork this project was built from, and every other hour is that
same palette tilted by the sun.

**Shadows.** Godot shadows have no colour of their own - what you see in a
shadow is the ambient and fill light that still reaches it. The fill and rim
lights are tinted from the same ambient/sky blend the environment is using, so
the frog and the mallet both cast the **same tinted shadow** instead of picking
up the sky colour, and that tint warms at dusk and cools to moonlight at night.
The pond is deep enough in colour that those shadows still read against it.

## Headless 无头模式

Two independent guards keep a headless run from hanging:

* `scripts/headless_watchdog.gd` is an autoload that, **only when the display
  server is `headless`**, arms a one-shot timer for **300 s (5 minutes)** and
  then quits with code 2. The budget can be changed with the project setting
  `application/run/headless_timeout_seconds`. An interactive session never arms
  it.
* The Godot Agent Loop CLI timeout (`GODOT_COMMAND_TIMEOUT_MS` in
  `@beremaran/godot-agent-loop`) was raised from 30 s to **300 s**, because the
  first headless `--import` of this project can legitimately take longer than
  30 s on a slow machine and was being killed mid-import.

## 青蛙的嘴 The mouth

### The jaw

The froggreen rebuild splits the lower jaw out as its own mesh, so the mouth is
no longer a static slot: `frog.gd` re-parents the jaw under a hinge at the back
of the mouth and `chomp()` drops it open and snaps it shut. Every landed tap
calls it, so the frog visibly bites down on the striker resting in its mouth.
The striker is a plain `Node3D` driven by script, so it can wait in the mouth
without gravity pulling it out and can never be wedged in the frog.

## Reading the face

Two things about the reference toy are easy to get wrong, and both are worth
stating because the model depends on them:

* the **black wavy line is the nose**, not a smile. It sits high on the muzzle
  just under the eyes, runs about 0.40 of the frog's width, is only ~1.3 mm
  thick, and both ends curl upwards.
* the **slot is the mouth**. Everything between it and the bottom of the frog is
  the lower jaw, and the mallet lies in the mouth with its head outside.

## How it works

**Geometry.** `assets/models/frog_muyu.glb` (the froggreen build) carries the
head, the lower jaw, the dark mouth interior, the black eyes with their
catchlights, the nose and the blush, plus the wooden striker. `frog.gd` hides
the striker inside the frog scene and `mallet.gd` hides the frog inside the
mallet scene, so the one GLB dresses both. The jaw is wrapped in a hinge pivot
at load, and the eyes are collapsed to blink, so no extra art nodes are needed.

The froggreen rebuild was modelled from the author's own reference photos in the
companion project; the measurement workflow for it lives there, not here. The
built model is 135.5 mm tall at the scale baked into `frog.tscn`.

`frog_muyu.glb` ships the striker in the same file, with its ball head at the
far end of the handle; the resting transform is read straight from the model
rather than invented.

**Collision.** The striker is animated by script rather than driven by the
physics solver, so the only physical body that needs a shape is the frog itself:
a single `SphereShape3D` (`resources/collision/frog_head.tres`) matching the
upper dome. `tools/gen_collision.gd` re-derives it from the GLB's bounds.

**Interaction.** There is no physics on the striker at all: `mallet.gd` eases
its `global_transform` between the rest, extracted, lifted and tap poses and
emits `struck` at the bottom of each stroke. That keeps a long run deterministic
and means the mallet can never sink into the frog or wedge itself in the mouth.

**Strike.** The striker is driven by script, so a tap is simply the moment the
script reaches the impact pose: `mallet.gd` emits `struck(at, speed)`, and
`main.gd` plays the "tok", counts the merit and pops the 功德+1 from there. There
is no contact query to tune and no way for the mallet to jam, which is what
makes a long run reliable.

**Auto tap.** Space (and a finished pomodoro block) takes the striker out of the
mouth and plays a run of taps. The rest pose threads the mallet horizontally
through the mouth, so the first move slides it along its own axis until the
handle clears the lip; only then is it lifted, because a horizontal striker
swept straight up would drag its handle through the head. Each tap is a short
peck - the mallet is cocked just above the crown and drops onto the aim point -
and the last move of the run threads it back into the mouth. Every tap is
different:

* **a random 10-20 taps** per press, because a mokugyo session is a rhythm; the
  beat between taps is kept about the same so the run settles into a tempo
* each tap picks its own **aim point** on the head (triangular jitter, so most
  taps land near the middle) and its own **impact speed** (1.6-2.8 m/s), which
  is what the squash strength, camera shake and sound pitch key off

The run writes what it did to `Mallet.last_plan`, so the randomness is
inspectable rather than only felt. `auto_strike(taps, seed)` pins both, and the
scripted return always ends exactly on the rest pose.

**Sound.** `assets/audio/mokugyo_0*.wav` are four round-robin variations
synthesised from scratch: an inharmonic modal stack around 500-570 Hz with fast
per-partial decays, a hollow 188 Hz body resonance, and a filtered noise click
for the wooden attack.

**Reaction.** `frog.gd` squashes the model (not the collision) and collapses the
eye meshes right down so the black vanishes and only the green bump is left,
which reads as a closed eye. Squashing a single axis would leave a black slit or
ring behind, so the whole eye - and its catchlight - shrinks together. Every hit
also drops the jaw open and snaps it shut (`chomp()`), so the mouth action is
part of the strike reaction. Both are tweened, so repeated taps restart them
cleanly. The same script owns the pomodoro moods: a slow breath and
open eyes while focusing, half-closed eyes and a head tilt on a break, and a
hop with wide eyes and a shower of lotus petals when a focus block finishes. A
temporary mood
(cheer, wake) plays for a fixed time and then falls back to whatever the timer
asked for in the meantime, so a phase change mid-celebration is never lost.

**Eyes.** The froggreen build already ships the two black eyes, so there is
nothing to create: `frog.gd` collects `Eye_L` / `Eye_R` and drives their scale
directly.

## Layout

```
assets/models/          frog_muyu.glb (froggreen)
assets/audio/           mokugyo_01..04.wav
resources/collision/    frog_head.tres
resources/theme/        macaron_theme.tres
scenes/                 main.tscn, frog.tscn, mallet.tscn, hud.tscn, merit_popup.tscn
scripts/                main.gd, pomodoro.gd, palette.gd, mallet.gd,
                        pond.gd, lotus_leaf.gd, frog.gd, hud.gd, merit_popup.gd,
                        sky_state.gd, sky_cycle.gd, weather.gd, weather_fx.gd,
                        headless_watchdog.gd
tools/                  build_audio.py (Blender), gen_collision.gd,
                        verify_froggreen.gd and the two preview helpers
```

## Rebuilding the assets

The `tools/` builders are the source of truth for the **audio**, and the old
frog/mallet generators were retired along with `frog_mokugyo.glb` and
`mallet.glb`. The **current** frog and striker are built by the companion
project as `Documents/froggreen/blender/make_frog.py` (run it with Blender 4.5);
copy its `models/frog_muyu.glb` into `assets/models/` and let Godot re-import it.

```
BLENDER=blender            # Blender 4.2 or newer on PATH
"$BLENDER" --background --factory-startup --python tools/build_audio.py

GODOT=godot                # Godot 4.7 on PATH
"$GODOT" --headless --path . --import
"$GODOT" --headless --path . --script res://tools/gen_collision.gd
```

`gen_collision.gd` re-derives the collision shapes from whatever the GLB
importer produced, so the collision can never drift from the art.

## Verification

The rebuilt behaviour is checked by `tools/verify_froggreen.gd`, a small
headless SceneTree script:

```
"$GODOT" --headless --path . --script res://tools/verify_froggreen.gd
```

It loads the real `main.tscn` and asserts that the striker starts exactly at its
mouth rest pose, that a default auto-strike lands **10-20 taps**, that the gaps
between those taps read as a steady rhythm, and that the striker is returned
exactly to the mouth afterwards.

`tools/preview_clock.tscn` is a longer, headed helper that loads the scene and
walks an idle -> focus -> break -> celebration -> tap cycle, writing one
screenshot per stage into the git-ignored `tools/shots/`. It needs a renderer,
so run it headed:

```
"$GODOT" --path . res://tools/preview_clock.tscn
```

`tools/preview_weather.tscn` renders the same scene under a strip of pinned
clocks and weathers - clear noon, morning fog, dusk, night, rain, a thunderstorm,
snow, a hailstorm and a typhoon - one PNG per row in `tools/shots/`. It also
needs a renderer:

```
"$GODOT" --path . res://tools/preview_weather.tscn
```

> One gotcha worth remembering: Godot's `Transform3D(...)` text form takes
> **row-major** basis values, so `Transform3D(x.x, y.x, z.x, x.y, y.y, z.y, ...)`
> is what produces the columns you intended. Getting the striker's alignment
> matrix backwards is what once made its handle point out of the frog instead of
> through its mouth.

## License

[MIT](LICENSE) (c) 2026 YuRos2. The frog and mallet models, the mokugyo audio
samples and every other asset in this repository are the author's own work and
are covered by the same licence.
