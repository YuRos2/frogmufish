class_name Palette
extends RefCounted

## Macaron palette shared by the 3D scene, the HUD theme and the code-built
## models. Soft, low-saturation pastels with one deeper tone per hue, so the
## scene stays legible for younger eyes without ever going neon.

# --- background -----------------------------------------------------------
const SKY_TOP := Color("bfe3f5")        # powder blue
const SKY_HORIZON := Color("ffeef2")    # strawberry milk
const GROUND := Color("efe3f6")         # soft lilac floor

# --- pastel family --------------------------------------------------------
const CREAM := Color("fff6ea")
const LAVENDER := Color("cdb4db")
const LAVENDER_DEEP := Color("a98bc4")
const MINT := Color("a8e6cf")
const MINT_DEEP := Color("5cc9a7")
const PEACH := Color("ffd3b6")
const PEACH_DEEP := Color("ffab84")
const PINK := Color("ffaaa5")
const ROSE := Color("ff8b94")
const LEMON := Color("ffe9a8")
const LEMON_DEEP := Color("f2cf63")
const SKY := Color("a3d5ff")
const SKY_DEEP := Color("6fb6f0")

# --- ink ------------------------------------------------------------------
const PLUM := Color("5d4a63")
const PLUM_SOFT := Color("8a7a92")
const INK := Color("4a3b50")

# --- surfaces -------------------------------------------------------------
const TABLE := Color("d9c6ee")
const TABLE_EDGE := Color("cbb2e2")
const PANEL := Color("fff6ea")
const PANEL_EDGE := Color("ffc9c2")

# --- pond -----------------------------------------------------------------
## The frog now sits on a lotus leaf that floats on a macaron pond. The water
## is a desaturated deep green so the pastel leaf, frog and pink bud still read
## against it, and the leaf is a mint-leaning green so its hue stays clear of
## the frog's yellow-green body.
const POND := Color("35604a")         # deep macaron green water
const POND_DEEP := Color("27493a")    # shading under the horizon
const POND_LIGHT := Color("7fb99b")   # ripple highlight
const LOTUS := Color("7fd3a6")        # lotus leaf body
const LOTUS_DEEP := Color("40996f")   # lotus leaf veins and rim
const LOTUS_RIM := Color("b6ecd0")    # curled-up leaf edge

# --- lotus bud mallet -----------------------------------------------------
const PETAL := Color("ffacc6")         # outer bud petals
const PETAL_DEEP := Color("ff7fa8")    # petal tips / seams
const PETAL_CORE := Color("ffe6ee")    # inner petals
const STEM := Color("76c596")          # lotus stem (the mallet handle)

# --- phase accents (deep enough to stay readable on the cream panels) --------
const FOCUS := Color("e07a4f")
const SHORT_BREAK := Color("3fae8d")
const LONG_BREAK := Color("4a97d4")
const IDLE := Color("9b7fb8")
