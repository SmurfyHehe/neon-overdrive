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
