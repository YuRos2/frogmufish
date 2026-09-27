# 番茄木鱼 Pomodoro Mokugyo Frog

A **macaron-coloured 3D pomodoro timer** for primary and secondary school pupils,
built for **Godot 4.7**. A frog-shaped electronic mokugyo sits on a lotus leaf
floating on a deep-green pond: the timer counts focus and break blocks, the frog
reacts to each phase, and tapping it with a lotus-bud mallet earns 功德.

The frog model was generated in **Blender 4.2** from the author's own reference
photos, which are not part of this repository. Point the measurement tools at
your own folder with the `MOKUGYO_PICTURES` environment variable (see
[Checking the model against the photos](#checking-the-model-against-the-photos)).
The pond, the lotus leaf and the bud-shaped mallet
are all built procedurally from Godot primitives - see [The pond](#the-pond).

The mallet rests horizontally through the frog's **mouth** - the slot that wraps
the front of the face - exactly like the real toy. Pull it out, tap the frog, and
every solid hit plays a mokugyo "tok", makes the frog blink and squash, and pops
a **功德+1**.

## 番茄时钟 Pomodoro

The timer lives in `scripts/pomodoro.gd` and knows nothing about frogs or
clocks: it counts down and emits signals, and `main.gd` turns those into stage
reactions.

| Phase | Default | Scene | Frog |
| --- | --- | --- | --- |
| 专注 Focus | 25 min | focus accent on the HUD | attentive, gentle breathing |
| 短休息 Short break | 5 min | break accent on the HUD | half-closed eyes, slow breathing, head tilt |
| 长休息 Long break | 15 min | long-break accent | the same nap, lasting longer |
| 番茄完成 | - | confetti | **mallet taps out the difficulty**, then hops and throws macaron confetti |

Every fourth focus block is followed by a long break instead of a short one. The
HUD has **15 / 25 / 45** minute presets, start/pause, skip and reset, plus a
**60x demo speed** so a whole cycle can be shown to a class in about a minute.

When a focus block finishes, the mallet swings on its own and taps the frog
once per difficulty step - **轻松 1, 标准 2, 深入 3** - and the confetti only
falls after the last tap. Each of those taps counts as merit, so a harder block
literally earns more 功德.

The countdown panel in the top-right shows the **local time of day** just under
the remaining time, in the same colour and shape as the countdown itself, so the
time is still always visible now that the analogue face is gone.

## Running

```
godot --path .
```

## Controls

| Input | Action |
| --- | --- |
| **Left mouse drag on the mallet** | Pick it up and move it. The mallet is a rigid body, so it collides with the frog the whole way. |
| **Left mouse release** | Let go. |
| **Space** | Scripted tap: slides the mallet out, lands **1-3 randomized taps** on the frog's head, and slides it back. |
| **R** | Put the mallet back in the mouth. |
| **T** | Start / pause / resume the pomodoro. |
| **N** | Skip to the next pomodoro phase. |
| **D** | Toggle the 60x demo speed. |
| **HUD buttons** | Start/pause, skip, reset, demo and the 15/25/45 presets. |
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
  scallop-edged, gently cupped disc with the classic **radial slit** and
  face-averaged normals. Its colour - a green body, a deeper edge and lighter
  radial veins - is painted into an `ImageTexture` at load time, so there is
  still no imported asset to track. The surface stays flat out to about two
  thirds of the radius, because the frog and the mallet both rest on the physics
  floor at `y = 0`; only the outer rim curls up.
* `scripts/lotus_mallet.gd` re-skins the mallet as a **lotus flower bud**. The
  physics is untouched - the same two capsule collision shapes, the same ball at
  the origin - so every strike, grab and auto-swing behaves exactly as before.
  The bud is a lobe-ridged solid of revolution with a cream-to-pink gradient
  baked into its vertex colours, and the handle becomes a green stem with a
  small calyx where the two meet.

The old analogue alarm clock has been removed: its dial, twelve numerals,
second/minute/hour hands and bells are all gone. `scripts/clock_3d.gd` and
`scenes/clock_3d.tscn` are left in the tree, unused, in case the floating clock
is ever wanted back - they are no longer referenced by `main.tscn`.

## Macaron palette

Every colour in the scene comes from `scripts/palette.gd`: powder-blue sky,
strawberry-milk horizon, deep-green pond, mint lotus leaf and pastel mint / peach /
rose / lemon / lavender / sky accents. The same palette drives
`resources/theme/macaron_theme.tres`, which is set as the project's default GUI
theme, so the HUD panels, buttons and progress bar stay consistent with the 3D
scene. Re-theming the whole project means editing that one file.

**Shadows.** Godot shadows have no colour of their own - what you see in a
shadow is the ambient and fill light that still reaches it. The environment
uses a single pastel ambient colour, and the fill and rim lights use that same
colour, so the frog and the mallet both cast the **same tinted shadow** instead
of picking up the sky colour. The pond is deep enough in colour that those
shadows still read against it.

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

### Taking the mallet out

The head is wider than the mouth slot, so the only way the mallet fits is by
sliding it along its own axis. Drag it **sideways/left** and it comes free; push
it forward into the frog and the lip stops it. That falls out of the collision
shapes rather than any special-cased rule, and the test suite checks both
directions.

## Reading the face

Two things about the reference toy are easy to get wrong, and both are worth
stating because the model depends on them:

* the **black wavy line is the nose**, not a smile. It sits high on the muzzle
  just under the eyes, runs about 0.40 of the frog's width, is only ~1.3 mm
  thick, and both ends curl upwards.
* the **slot is the mouth**. Everything between it and the bottom of the frog is
  the lower jaw, and the mallet lies in the mouth with its head outside.

## How it works

**Geometry.** `assets/models/frog_mokugyo.glb` carries three nodes: `FrogMokugyo`
(body, cheeks and nose) plus `PupilL` and `PupilR`. The pupils are separate nodes
rooted at each pupil's centre so Godot can squash them vertically to blink. The
body is a lathed silhouette with a hollow sound chamber, a horizontal mouth slot
wrapping the front 210°, and a deeper rounded opening on the face.

Every dimension is a fraction of the frog's width, read off the photos by
`tools/analyze_refs.py`:

| feature | reference measurement |
| --- | --- |
| overall height / width | 1.18 (every standing shot agrees) |
| eye bumps | 0.375 of the width across, tops are the highest point |
| pupils | v 0.07-0.19, centres at u 0.24 / 0.77 |
| nose line | v 0.15-0.20, spans u 0.30-0.70, ends curl up |
| cheeks | centres u 0.20 / 0.84 at v 0.38, ~0.20 of the width across |
| mouth | seam at v 0.74, opening reaches v 0.86 |
| widest point | v 0.45-0.60, i.e. around the cheeks |

The body is therefore 114.8 mm wide and 135.5 mm tall, and its widest ring sits
at the cheeks rather than down at the lip - the first version had that backwards
and came out 20% too short, which made the frog read as a bowl on a plate.

Below the lower lip the silhouette is drawn as a single circular arc, so the
belly tucks under into a small contact patch and the frog reads as one plump
ball. An earlier version closed the lathe with a wide flat disc; that read as a
pedestal the frog was standing on, not as its underside. The lip itself is left
alone at r 0.0440 / z 0.0258, because that edge is what the mallet handle rests
on and moving it throws the resting pose off.

`assets/models/mallet.glb` has the ball head centred on the origin with the
handle running along +X, so the same transform is both the head and the pivot.

**Collision.** `resources/collision/frog_body.res` is a concave
`ConcavePolygonShape3D` (11 724 triangles) built from the body surface only, so
the mallet can genuinely pass through the mouth slot and the painted details
(pupils, cheeks, nose) do not create phantom collisions. `gen_collision.gd`
locates the body by finding the surface that owns the `FrogBody` material rather
than trusting a node name or assuming surface 0. The mallet is a compound of two
capsules. Both bodies use friction 0.9, and the mallet has continuous collision
detection on.

**Interaction.** While held, the mallet is driven by a velocity controller
(`linear_velocity = error * gain`, clamped) rather than teleported, and its
orientation is held by an angular spring. The solver therefore still resolves
every contact, which is what stops the mallet from ever being pushed through the
frog. The controller cancels gravity itself: Godot applies gravity *after*
`_integrate_forces`, so a driven body sags ~0.1 m/s and never reaches the pose
the controller asked for. (Owning the whole integrator with `custom_integrator`
fixes the sag too, but it also hides the solver's contacts and lets the head sink
into the frog.)

**Strike detection.** A hit counts when a contact lands within 32 mm of the ball
head *and* the head had been clear of the frog for at least 120 ms. The clearance
rule means holding the mallet pressed against the frog is one tap rather than a
drum roll, and the reach limit means scraping the handle along the mouth slot
while pulling the mallet out is not a hit. The closing speed is tracked the whole
time the head is clear, so it cannot go stale between taps of one swing.

**Auto tap.** Space (and a finished pomodoro block) swings the mallet like a
real one: a **fixed grip point** stands in for the player's hand and the mallet
rotates about it, so the ball travels along an **arc** onto the frog's crown
instead of being lifted and dropped straight down. The down stroke eases in so
it accelerates into the frog; the frog's body stops the ball, and that stop is
the tap. The whole move goes through the same controller as the mouse, so it
obeys collisions the whole way. Every swing is different:

* **1-3 taps** per press, weighted 45 / 33 / 22 so one tap is still the common case
* each tap picks its own **aim point** on the head (+/-17 mm across, jitter
  drawn from a triangular distribution so most taps land near the middle)
* each tap picks its own **roll** (+/-0.22 rad) and its own **impact speed**
  (1.5-3.0 m/s), which is what the squash strength, camera shake and sound pitch
  all key off

The swing writes what it did to `Mallet.last_plan`, so the randomness is
inspectable rather than only felt - `tools/verify.gd` compares the plans of three
unseeded swings and asserts they differ. `auto_strike(taps, seed)` pins both, and
the pinned checks use a fixed seed so they stay stable. The harness also checks
the pendulum itself: every point of the swing is the same distance from the
grip, and the ball really does travel sideways rather than straight up and down.

**Sound.** `assets/audio/mokugyo_0*.wav` are four round-robin variations
synthesised from scratch: an inharmonic modal stack around 500-570 Hz with fast
per-partial decays, a hollow 188 Hz body resonance, and a filtered noise click
for the wooden attack.

**Reaction.** `frog.gd` squashes the model (not the collision) and squashes the
pupil nodes to 10% height so the black collapses to a slit while the green eye
bumps stay put, which reads as a closed eye. Both are tweened, so repeated taps
restart them cleanly. The same script owns the pomodoro moods: a slow breath and
open eyes while focusing, half-closed eyes and a head tilt on a break, and a
hop with wide eyes and confetti when a focus block finishes. A temporary mood
(cheer, wake) plays for a fixed time and then falls back to whatever the timer
asked for in the meantime, so a phase change mid-celebration is never lost.

**Eyes.** The two pupils in the imported GLB are hand-sculpted and different -
the right one is a teardrop, which read as a wonky face. `_symmetrize_eyes()`
replaces both with one shared ellipsoid at mirror-image positions, so the eyes
are always identical.

## Layout

```
assets/models/          frog_mokugyo.glb, mallet.glb
assets/audio/           mokugyo_01..04.wav
resources/collision/    frog_body.res, mallet_head.tres, mallet_handle.tres
resources/theme/        macaron_theme.tres
scenes/                 main.tscn, frog.tscn, mallet.tscn, hud.tscn, merit_popup.tscn,
                        clock_3d.tscn (retired)
scripts/                main.gd, pomodoro.gd, palette.gd, mallet.gd, lotus_mallet.gd,
                        pond.gd, lotus_leaf.gd, frog.gd, hud.gd, merit_popup.gd,
                        headless_watchdog.gd (clock_3d.gd is retired)
tools/                  asset builders, reference measurement, the preview shot
                        helper and the verification harness
```

## Rebuilding the assets

The `tools/` builders are the source of truth for the frog model and the audio;
the `.glb` and `.wav` files are their output. `build_models.py` needs the
original sculpt it was baked from and takes it from `LUCKY_FROG_BLEND`
(default `tools/Lucky+frog.blend`); that file is not redistributed here. The
committed `frog_mokugyo.glb` is the finished result, so the game runs without
it. (`build_models.py` still emits
`mallet.glb`, but the scene no longer references it - the mallet is dressed as a
lotus bud by `scripts/lotus_mallet.gd` and only keeps the two capsule collision
shapes.)

```
BLENDER=blender            # Blender 4.2 or newer on PATH
"$BLENDER" --background --factory-startup --python tools/build_models.py
"$BLENDER" --background --factory-startup --python tools/build_audio.py
"$BLENDER" --background --factory-startup --python tools/render_preview.py   # optional renders

GODOT=godot                # Godot 4.7 on PATH
"$GODOT" --headless --path . --import
"$GODOT" --headless --path . --script res://tools/gen_collision.gd
```

`gen_collision.gd` re-derives the collision shapes from whatever the GLB
importer produced, so the collision can never drift from the art.

## Checking the model against the photos

The reference photos themselves are not distributed with this project. Put your
own copies of the JPEGs in a folder and point `MOKUGYO_PICTURES` at it; the
tools fall back to `reference_photos/` next to this README.

```
export MOKUGYO_PICTURES="$HOME/Pictures"
"$BLENDER" --background --factory-startup --python tools/analyze_refs.py
"$BLENDER" --background --factory-startup --python tools/compare_front.py
"$BLENDER" --background --factory-startup --python tools/ref_sheet.py
```

* `analyze_refs.py` masks the green silhouette in each photo and prints every
  feature as a (u, v) fraction of that silhouette, plus `tools/refs_report.txt`.
  It also writes `tools/crops/a_front_*.png` overlays showing the detected masks.
* `compare_front.py` renders the built model orthographically, normalises the
  render and the photo to the same silhouette width, and writes
  `tools/preview/compare_front.png`: photo, model, then the two silhouettes
  overlaid. It prints the width error every 5% of the height - currently within
  5% everywhere the photo is not hidden inside its base.
* `ref_sheet.py` writes a contact sheet of all 29 reference photos.

## Verification

```
"$GODOT" --headless --path . res://tools/verify.tscn        # logic checks
"$GODOT" --path . res://tools/verify.tscn                   # + screenshots in tools/shots/
```

The harness loads the real `main.tscn` and asserts the behaviour the design
promises: the scene wiring, the resting pose, that a real click grabs the
mallet, that it can only leave the mouth along its axis, that a tap produces
exactly one hit / one sound / one blink / one popup, that an unseeded auto tap
lands every tap it chose and returns the mallet to the mouth, that successive
swings differ in aim, roll and impact speed, and that a mallet driven hard into
the frog is stopped by the lip instead of sinking through it.

It also checks that the frog sits on the lotus leaf over the water, that the
physical clock is gone and the countdown panel carries the local time, that the
mallet is dressed as a lotus bud, and then runs a whole speeded-up pomodoro
cycle: start begins a focus block, the HUD shows the countdown and its progress
bar tracks it, difficulty picks the 1/2/3 completion tap count, the mallet taps
before the confetti, the break puts the frog to sleep
with half-closed eyes, waking is its own mood, merit still counts while a block
runs, and the HUD buttons and demo toggle drive the same public API.

`tools/preview_clock.tscn` is a shorter helper that loads the scene, walks an
idle -> focus -> break -> celebration -> tap cycle and writes one screenshot per
stage into `tools/shots/`. It needs a renderer, so run it headed:

```
"$GODOT" --path . res://tools/preview_clock.tscn
```

The blink is judged by the geometry the pupils produce rather than by sampling
the tween over wall time. That matters here: this machine renders the window at
9 fps, so a single tween step skips straight over the 100 ms squash and a
value-sampling check would be a coin flip.

> Two gotchas worth remembering.
>
> Godot's `Transform3D(...)` text form takes **row-major** basis values, so
> `Transform3D(x.x, y.x, z.x, x.y, y.y, z.y, ...)` is what produces the columns
> you intended. The light/camera checks exist because getting this backwards
> silently points the lights at the sky.
>
> `bpy.ops.object.shade_auto_smooth()` needs the "Smooth by Angle" geometry node
> asset, which `blender --factory-startup` does not load. It reports an error and
> leaves the mesh flat shaded, so the builder tags sharp edges through bmesh
> instead.

## License

[MIT](LICENSE) (c) 2026 YuRos2. The frog and mallet models, the mokugyo audio
samples and every other asset in this repository are the author's own work and
are covered by the same licence.
