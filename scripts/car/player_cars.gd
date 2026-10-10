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

const SaveStore := preload("res://scripts/save/save_store.gd")
const TestMode := preload("res://scripts/core/test_mode.gd")

const DEFAULT := "p1_coupe"

## In the order the garage lists them. "name" is the working name from the
## PR #197 car table (the beater's is new); names are placeholders, Roy's to write.
const KINDS := [
	{"id": "p0_beater", "label": "Rear-engine beater", "name": "Tarp", "tier": "T0", "nm": 290, "kg": 1000},
	{"id": "p1_coupe", "label": "Sports coupe", "name": "Coupe", "tier": "T3", "nm": 460, "kg": 1300},
	{"id": "p2_hothatch", "label": "Hot hatch", "name": "Kobo", "tier": "T1", "nm": 270, "kg": 1080},
	{"id": "p3_tuner", "label": "Tuner sedan", "name": "Ronin", "tier": "T2", "nm": 360, "kg": 1300},
	{"id": "p4_kei", "label": "Kei roadster", "name": "Mite", "tier": "T1", "nm": 180, "kg": 760},
	{"id": "p5_muscle", "label": "Muscle sedan", "name": "Marlowe", "tier": "T3", "nm": 820, "kg": 1800},
	{"id": "p6_crossover", "label": "Perf. crossover", "name": "Cairn", "tier": "T2", "nm": 400, "kg": 1450},
	# The 4-door work pickup Walt sells after act 1 (Roy, 2026-10-10).
	{"id": "p17_work_pickup", "label": "Work pickup", "name": "Camel", "tier": "T2", "nm": 640, "kg": 1780},
	# Special vehicles (S0): story-end unlocks, not sprint-race cars. The truck's
	# numbers are its own (S1); the lowrider borrows the coupe's until its body step.
	{"id": "m1_monster", "label": "Monster truck", "name": "Brute", "tier": "S", "nm": 750, "kg": 3500},
	{"id": "l1_lowrider", "label": "Lowrider", "name": "Slab", "tier": "S", "nm": 460, "kg": 1300},
]

## Each special vehicle's own data file; its SPECIAL const is what is_special reads.
const SPECIAL_DATA := {
	"m1_monster": preload("res://scripts/car/m1_monster_data.gd"),
	"l1_lowrider": preload("res://scripts/car/l1_lowrider_data.gd"),
}

static var selected := DEFAULT

## Every car's cabin is its own now (CABIN in its data file, CabinSpec);
## the stage D stand-in offset table that sat the coupe's cabin in each
## car is gone (interior pass, 2026-10-09).

static func ids() -> Array[String]:
	var out: Array[String] = []
	for k in KINDS:
		out.append(k.id)
	return out

static func is_player_kind(kind: String) -> bool:
	return kind in ids()

## True for a story-end special vehicle (its data file's SPECIAL).
static func is_special(kind: String) -> bool:
	var d: Variant = SPECIAL_DATA.get(kind)
	return d != null and d.SPECIAL

## The cars a sprint race may pick from: no specials.
static func sprint_ids() -> Array[String]:
	var out: Array[String] = []
	for k in ids():
		if not is_special(k):
			out.append(k)
	return out

## The cars the garage / free roam list: every normal car, plus the specials
## whose entry in `unlocked` (GameState.special_unlocked) is true.
static func garage_ids(unlocked: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for k in ids():
		if not is_special(k) or unlocked.get(k, false) == true:
			out.append(k)
	return out

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
	# A special saved as the car but not unlocked (a new slot, a wiped save)
	# spawns the default car instead.
	if is_special(selected) and not TestMode.active() 			and not SaveStore.load_special().get("unlocked", {}).get(selected, false):
		select(DEFAULT)

## Keeps the other sections (audio, traffic, fx) as they are.
static func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.load(AudioSettings.path)  # missing is fine: a new file
	cfg.set_value("player", "car", selected)
	cfg.save(AudioSettings.path)
