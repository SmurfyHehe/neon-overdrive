class_name BobbleFigures
extends RefCounted

# The dash bobble head catalogue (interiors B1, 2026-10-11; brief: Roy's
# dashboard-figures design, 29 figures). Data only: who a figure is, how you
# get it, its colours and its spring. The shapes are in BobbleSculpt. Original
# figures: no licensed characters, no real people, no brands, no team logos.
#
# group "crew": won by beating the crew or driver named in "how" (the rule is
# not built yet). group "shop": bought in the shop for about $50 (not built
# yet): the shop family, the local jokes, and our own versions of the dash
# classics. For the test build every figure is pickable from Settings.
#
# spring: each figure's own bob, one small record, no extra cost (the same
# damped spring, different constants): hz the spring's rate, zeta its damping,
# gain how far it goes for the same jolt (1 = BobbleHead's default), side how
# much of that is side-to-side lean (1 = both axes alike; above 1 leans more
# than it nods, below 1 nods more than it leans).

const NONE := "none"

# ---- the shared palette (ROADMAP: Amber vs. Dusk; no magenta, no cyan) ----
const SKIN := Color("#D9A878")
const SKIN_PALE := Color("#E8C9A6")
const SKIN_DARK := Color("#8A5A3A")
const BONE := Color("#E9E6DF")
const SILVER := Color("#C9CED6")
const GREY := Color("#9AA0A8")
const NAVY := Color("#26314D")
const NAVY_DEEP := Color("#1B2A4A")
const SODIUM := Color("#FF8A1F")
const AMBER := Color("#FFC066")
const INK := Color("#15171C")
const OIL := Color("#1A1A1A")
const RUST := Color("#B8641A")
const COPPER := Color("#B87333")
const BRASS := Color("#B08D3C")
const GOLD := Color("#D4A52A")
const CHARCOAL := Color("#3A3D42")
const SLATE := Color("#5A6470")
const TAN := Color("#C9A574")
const MOSS := Color("#4F6B45")
const PINE := Color("#2B4A3A")
const WOOD := Color("#6B4A2B")
const FUR := Color("#8A6A45")
const FUR_DARK := Color("#5E4228")
const RED := Color("#B8312F")
## The one off-palette colour, police only (the cartoon cop figure).
const POLICE_BLUE := Color("#2E4FD8")

## Pick order in the pause menu: index 0 is "none", then the crews, then the
## shop family and jokes, then the dash classics.
const IDS: Array[String] = [
	NONE,
	"ledger", "kasumi_leader", "gruppe9_leader", "diesel_leader", "kess", "pike",
	"rally_king", "topspeed_king", "muscle_king",
	"walt", "moose", "juno", "pilar", "teo", "dave", "dunmore_mascot", "traffic_cone",
	"nodding_dog", "hula_dancer", "sports_nodder", "lucky_cat", "dancing_flower", "drinking_bird",
	"tiki", "little_alien", "skeleton", "cowboy", "surfer", "traffic_cop",
]

## name: pause-menu text; group; how: how you get it (placeholder names);
## body / accent: the figure's two colours (the base mark uses accent);
## spring: see the file comment.
const FIGURES := {
	# ---- the crews: the people you beat ----
	"ledger": {"name": "Ledger", "group": "crew", "how": "beat Ironbridge",
		"body": CHARCOAL, "accent": BRASS, "spring": {"hz": 2.2, "zeta": 0.05, "gain": 1.6, "side": 1.0}},
	"kasumi_leader": {"name": "Kasumi Run leader", "group": "crew", "how": "beat Kasumi Run",
		"body": BONE, "accent": MOSS, "spring": {"hz": 4.0, "zeta": 0.08, "gain": 1.0, "side": 1.8}},
	"gruppe9_leader": {"name": "Gruppe 9 leader", "group": "crew", "how": "beat Gruppe 9",
		"body": SLATE, "accent": SILVER, "spring": {"hz": 5.0, "zeta": 0.30, "gain": 0.4, "side": 1.0}},
	"diesel_leader": {"name": "Diesel Row leader", "group": "crew", "how": "beat Diesel Row",
		"body": COPPER, "accent": OIL, "spring": {"hz": 1.6, "zeta": 0.25, "gain": 0.8, "side": 1.0}},
	"kess": {"name": "Kess", "group": "crew", "how": "beat Kess",
		"body": TAN, "accent": NAVY, "spring": {"hz": 2.5, "zeta": 0.50, "gain": 0.25, "side": 1.0}},
	"pike": {"name": "Pike", "group": "crew", "how": "the finale",
		"body": NAVY_DEEP, "accent": GOLD, "spring": {"hz": 3.0, "zeta": 0.80, "gain": 0.10, "side": 1.0}},
	"rally_king": {"name": "Rally king", "group": "crew", "how": "beat the rally king",
		"body": SODIUM, "accent": NAVY, "spring": {"hz": 3.2, "zeta": 0.08, "gain": 1.3, "side": 1.0}},
	"topspeed_king": {"name": "Top-speed king", "group": "crew", "how": "beat the top-speed king",
		"body": NAVY, "accent": AMBER, "spring": {"hz": 6.0, "zeta": 0.06, "gain": 0.6, "side": 1.0}},
	"muscle_king": {"name": "Muscle king", "group": "crew", "how": "beat the muscle king",
		"body": BONE, "accent": SODIUM, "spring": {"hz": 2.0, "zeta": 0.12, "gain": 1.2, "side": 0.4}},
	# ---- the shop family and the local jokes ----
	"walt": {"name": "Walt", "group": "shop", "how": "shop",
		"body": NAVY, "accent": AMBER, "spring": {"hz": 1.8, "zeta": 0.30, "gain": 0.6, "side": 1.0}},
	"moose": {"name": "Moose", "group": "shop", "how": "shop",
		"body": NAVY, "accent": SILVER, "spring": {"hz": 2.2, "zeta": 0.30, "gain": 0.5, "side": 1.0}},
	"juno": {"name": "Juno", "group": "shop", "how": "shop",
		"body": SODIUM, "accent": BONE, "spring": {"hz": 4.5, "zeta": 0.15, "gain": 0.9, "side": 1.0}},
	"pilar": {"name": "Pilar", "group": "shop", "how": "shop",
		"body": MOSS, "accent": BONE, "spring": {"hz": 1.4, "zeta": 0.12, "gain": 1.0, "side": 1.6}},
	"teo": {"name": "Teo", "group": "shop", "how": "shop",
		"body": NAVY, "accent": AMBER, "spring": {"hz": 7.0, "zeta": 0.08, "gain": 0.5, "side": 1.0}},
	"dave": {"name": "Dave", "group": "shop", "how": "shop",
		"body": NAVY, "accent": AMBER, "spring": {"hz": 1.2, "zeta": 0.10, "gain": 1.0, "side": 1.8}},
	"dunmore_mascot": {"name": "Dunmore Auto mascot", "group": "shop", "how": "shop",
		"body": SILVER, "accent": SODIUM, "spring": {"hz": 3.5, "zeta": 0.07, "gain": 1.2, "side": 1.0}},
	"traffic_cone": {"name": "Traffic cone", "group": "shop", "how": "shop",
		"body": SODIUM, "accent": BONE, "spring": {"hz": 1.8, "zeta": 0.05, "gain": 1.4, "side": 1.0}},
	# ---- the dash classics, our own versions ----
	"nodding_dog": {"name": "Nodding dog", "group": "shop", "how": "shop",
		"body": FUR, "accent": AMBER, "spring": {"hz": 1.0, "zeta": 0.08, "gain": 1.2, "side": 0.3}},
	"hula_dancer": {"name": "Hula dancer", "group": "shop", "how": "shop",
		"body": MOSS, "accent": SODIUM, "spring": {"hz": 1.6, "zeta": 0.10, "gain": 1.3, "side": 2.0}},
	"sports_nodder": {"name": "Sports nodder", "group": "shop", "how": "shop",
		"body": BONE, "accent": NAVY, "spring": {"hz": 4.0, "zeta": 0.10, "gain": 1.0, "side": 0.5}},
	"lucky_cat": {"name": "Lucky cat", "group": "shop", "how": "shop",
		"body": BONE, "accent": AMBER, "spring": {"hz": 2.0, "zeta": 0.20, "gain": 0.8, "side": 1.6}},
	"dancing_flower": {"name": "Dancing flower", "group": "shop", "how": "shop",
		"body": MOSS, "accent": AMBER, "spring": {"hz": 1.5, "zeta": 0.08, "gain": 1.4, "side": 1.0}},
	"drinking_bird": {"name": "Drinking bird", "group": "shop", "how": "shop",
		"body": SODIUM, "accent": SILVER, "spring": {"hz": 0.9, "zeta": 0.05, "gain": 1.3, "side": 0.1}},
	"tiki": {"name": "Tiki", "group": "shop", "how": "shop",
		"body": WOOD, "accent": AMBER, "spring": {"hz": 5.0, "zeta": 0.50, "gain": 0.2, "side": 1.0}},
	"little_alien": {"name": "Little alien", "group": "shop", "how": "shop",
		"body": NAVY_DEEP, "accent": SILVER, "spring": {"hz": 3.0, "zeta": 0.10, "gain": 1.1, "side": 1.0}},
	"skeleton": {"name": "Skeleton", "group": "shop", "how": "shop",
		"body": BONE, "accent": INK, "spring": {"hz": 3.2, "zeta": 0.08, "gain": 1.0, "side": 1.0}},
	"cowboy": {"name": "Cowboy", "group": "shop", "how": "shop",
		"body": RUST, "accent": BONE, "spring": {"hz": 2.4, "zeta": 0.10, "gain": 1.2, "side": 1.0}},
	"surfer": {"name": "Surfer", "group": "shop", "how": "shop",
		"body": SODIUM, "accent": NAVY, "spring": {"hz": 1.3, "zeta": 0.08, "gain": 1.0, "side": 1.0}},
	"traffic_cop": {"name": "Traffic cop", "group": "shop", "how": "shop",
		"body": POLICE_BLUE, "accent": SILVER, "spring": {"hz": 3.5, "zeta": 0.10, "gain": 0.8, "side": 1.0}},
}

static func name_of(id: String) -> String:
	if id == NONE:
		return "None"
	return str(FIGURES.get(id, {}).get("name", id))

## Pause-menu labels in IDS order.
static func names() -> Array[String]:
	var out: Array[String] = []
	for id in IDS:
		out.append(name_of(id))
	return out

## Index in IDS of the id (0, "none", if unknown).
static func index_of(id: String) -> int:
	return maxi(IDS.find(id), 0)

## The figure's spring record (BobbleHead's defaults for none / unknown).
static func spring_of(id: String) -> Dictionary:
	return FIGURES.get(id, {}).get("spring", {})
