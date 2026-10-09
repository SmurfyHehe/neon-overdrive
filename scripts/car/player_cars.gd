class_name PlayerCars
extends RefCounted
# The player's cars (stage D, Roy 2026-10-09: "make all five P2-P6 drivable
# now", plus the beater starter car). Every one of them runs the same raycast
# Vehicle sim; what differs is CarSpec.player_spec(kind) and the body
# (P1CoupeBuilder for the coupe, NpcCarBuilder.KINDS for the others, the same
# sheet meshes the AI cars use).
#
# `selected` is the car the player spawns in. The pause menu's Car page sets
# it, saves it and restarts the run (GameState.restart reloads the scene, so
# the car is rebuilt from scratch, the same way a tune change is). Kept in
# the [player] section of the shared settings.cfg (AudioSettings.path, so
# tests that redirect the settings file redirect this too).
#
# Tiers are the car ladder's arrival bands (docs: rival-and-car-ladder
# proposal, PR #177; garage/mod trees, PR #197): T0 beater, T1 street,
# T2 club, T3 district. Torque and mass are starting values for the D data
# pass, not measured.

const DEFAULT := "p1_coupe"

## In the order the garage lists them. "name" is the working name from the
## PR #197 car table (the beater's is new); names are placeholders, Roy's to write.
const KINDS := [
	{"id": "p0_beater", "label": "Rear-engine beater", "name": "Tarp", "tier": "T0", "nm": 290, "kg": 1000},
	{"id": "p1_coupe", "label": "Sports coupe", "name": "Coupe", "tier": "T3", "nm": 460, "kg": 1300},
	{"id": "p2_hothatch", "label": "Hot hatch", "name": "Kobo", "tier": "T1", "nm": 340, "kg": 1080},
	{"id": "p3_tuner", "label": "Tuner sedan", "name": "Ronin", "tier": "T2", "nm": 520, "kg": 1300},
	{"id": "p4_kei", "label": "Kei roadster", "name": "Mite", "tier": "T1", "nm": 180, "kg": 760},
	{"id": "p5_muscle", "label": "Muscle sedan", "name": "Marlowe", "tier": "T3", "nm": 820, "kg": 1800},
	{"id": "p6_crossover", "label": "Perf. crossover", "name": "Cairn", "tier": "T2", "nm": 580, "kg": 1450},
]

static var selected := DEFAULT

## TEMPORARY default look per car (Roy, 2026-10-09: "all the body modifications
## equipped on the user cars to look as bad ass as possible until we set up the
## mod tree"). Looks only: the sheet build the body wears and the CarParts rim
## set. Nothing here touches CarSpec.player_spec (mass, drag, downforce, grip,
## springs stay the stock numbers; the kit is a mesh swap). The mod tree /
## body shop (Stage E, PR #197 / #267) replaces this table with the garage
## save; delete it then.
##
## "build" is a key of the car's data BUILDS (tools/fleet_design/options.py
## BUILDS bakes them: "full" = race bumper, diffuser, vented hood, widebody,
## wing, slammed stance for the hatch/tuner/kei; chin, drag wing, skirts, quad
## tips for the muscle; rally pod, big roof wing, mud flaps for the crossover).
## A build the data does not have falls back to "stock" (look_for). The beater
## and the coupe have no baked kit yet (the coupe is P1CoupeBuilder's own
## mesh), so they get the rim set only.
## "rim" is a CarParts.RIM_STYLES name, "rim_color" the rim tint: the library
## wheel of each full build mapped onto the four built rims (the hatch's dark
## split 5-spoke -> mesh in rim_dark, the tuner's own mesh gold, the kei's deep
## dish, the muscle's black monoblock -> five in rim_dark, the crossover's
## rally gold -> mesh in rim_gold). The beater sits on steelies, like a beater
## should.
const LOOK := {
	"p0_beater": {"build": "stock", "rim": "steel", "rim_color": Color("#8D939C")},
	"p1_coupe": {"build": "stock", "rim": "five", "rim_color": Color("#C9CED6")},
	"p2_hothatch": {"build": "full", "rim": "mesh", "rim_color": Color("#22252C")},
	"p3_tuner": {"build": "full", "rim": "mesh", "rim_color": Color("#C8A04A")},
	"p4_kei": {"build": "full", "rim": "dish", "rim_color": Color("#C9CED6")},
	"p5_muscle": {"build": "full", "rim": "five", "rim_color": Color("#22252C")},
	"p6_crossover": {"build": "full", "rim": "mesh", "rim_color": Color("#C8A04A")},
}

## The default look for a kind: LOOK's entry with its build checked against
## the car's data (a sheet without that build, e.g. after a car is re-exported
## with other build names, wears "stock" instead of failing to build).
static func look_for(kind: String) -> Dictionary:
	var l: Dictionary = LOOK.get(kind, {"build": "stock", "rim": "five"}).duplicate()
	if NpcCarBuilder.is_npc(kind) and not NpcCarBuilder.builds(kind).has(l.build):
		l.build = "stock"
	return l

## Where the P1's cabin (CockpitFrame, the cockpit eye, the mirrors) sits in
## each other car, as an offset in car space: no scaling (scaled parents break
## the mirror cameras), just moved to the car's own windshield base (fleet.json
## cabin.A against the P1's, in z) and part of the way up to its roof (the
## seat rises less than the roof does). The stage D interior passes (D-n.2,
## PR #197) give every car its own cabin; until then this is the P1's cabin
## sat in the right place, so the view, the wheel and the mirrors fit the
## car's glass rather than the coupe's.
const CABIN_OFFSET := {
	"p0_beater": Vector3(0.0, 0.156, -0.01),
	"p2_hothatch": Vector3(0.0, 0.096, -0.21),
	"p3_tuner": Vector3(0.0, 0.072, -0.12),
	"p4_kei": Vector3(0.0, -0.066, -0.075),
	"p5_muscle": Vector3(0.0, 0.036, -0.025),
	"p6_crossover": Vector3(0.0, 0.22, -0.29),
}

static func cabin_offset(kind: String) -> Vector3:
	return CABIN_OFFSET.get(kind, Vector3.ZERO)

static func ids() -> Array[String]:
	var out: Array[String] = []
	for k in KINDS:
		out.append(k.id)
	return out

static func is_player_kind(kind: String) -> bool:
	return kind in ids()

## The car's peak torque as the player reads it: on full boost for a turbo car.
static func peak_torque(spec: Dictionary) -> float:
	var nm := float(spec.get("max_torque", 0.0))
	return nm * CarSpec.TURBO_PEAK if float(spec.get("turbo_boost_max", 0.0)) > 0.0 else nm

static func info(kind: String) -> Dictionary:
	for k in KINDS:
		if k.id == kind:
			return k
	return KINDS[1]  # the coupe

## "T1 Hot hatch (Kobo)"
static func title(kind: String) -> String:
	var k := info(kind)
	return "%s %s (%s)" % [k.tier, k.label, k.name]

static func select(kind: String) -> void:
	selected = kind if is_player_kind(kind) else DEFAULT

static func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(AudioSettings.path) != OK:
		select(DEFAULT)
		return
	select(str(cfg.get_value("player", "car", DEFAULT)))

## Keeps the other sections (audio, traffic, fx) as they are.
static func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.load(AudioSettings.path)  # missing is fine: a new file
	cfg.set_value("player", "car", selected)
	cfg.save(AudioSettings.path)
