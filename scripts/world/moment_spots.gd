class_name MomentSpots
extends Node

## Moment spots (M0, 2026-10-10): fixed roadside spots in every district run,
## filled each night from a deck of moment cards.
##
## - Spots are fixed for a road: SPOTS_PER_RUN per district run (Districts.RUN
##   chunks), at a chunk picked from the road seed. They do not move from
##   night to night.
## - Each night the deck (DECK: card -> copies) is shuffled from the road seed
##   and the night number and dealt along the spots in order, so a cycle of
##   spots holds every card exactly once. Most cards are "quiet".
## - A card names the spot tags it needs (NEEDS); a spot without them stays
##   quiet that night.
##
## CPU first: nothing here is a per-object script. One node looks at the few
## spots near the car ten times a second, and a chunk is dressed once, when
## the chunk pool builds or recycles it (dress_chunk).
##
## The first two cards:
## - "power_cut": as the car comes up to the block its lamps, light pools,
##   windows and signs flicker and go out, and stay out for the night.
## - "speed_trap": a patrol car parked dark on the sidewalk. It clocks the car
##   passing over the limit, if it can see it: headlights on from SEE_LIT m
##   (PoliceHeat's figure, police F1), headlights off only from SEE_DARK m,
##   which reaches the two lanes next to it and not the two by the centre
##   line. It emits `clocked` or `slipped`; heat is the police system's to
##   raise from `clocked`.

const Districts := preload("res://scripts/world/districts.gd")
const TestMode := preload("res://scripts/core/test_mode.gd")

signal power_cut_started(chunk: int)
## The trap got a speed reading over the limit.
signal clocked(kmh: float, cop: Node3D)
## The car went by a trap unclocked: under the limit, or dark and unseen.
signal slipped(dark: bool)

const SPOTS_PER_RUN := 2
## Chunks of a run a spot may stand on: after the first chunk and clear of the
## district blend at the end, split into one band per spot. The last chunk of
## a band is left free, so two spots are never neighbours and a block fits.
const FIRST_CHUNK := 1
const BAND := 6
## Card -> copies in the deck. 8 spots are 4 runs (3.2 km): one of each
## moment in that stretch, in an order that changes every night.
const DECK := {"power_cut": 1, "speed_trap": 1, "quiet": 6}
## Spot tags a card needs. "block": buildings and lamps on both sides (every
## spot). "shoulder": a clear roadside to park on (no crossing mouth).
const NEEDS := {"power_cut": ["block"], "speed_trap": ["shoulder"]}

const CHECK_EVERY := 0.1

# power cut
const BLOCK_CHUNKS := 2      # 100 m goes dark
const CUT_AT := 120.0        # m before the block: the lights go as you arrive
## Seconds into the flicker at which the block flips: dark, lit, dark, lit,
## dark. An odd count, so it ends dark.
const FLICKER := [0.0, 0.09, 0.17, 0.34, 0.45]
const CUT_LINE := "Dave: And there goes the east side grid again. If your street just went black, no, it is not just you."

# speed trap
const TRAP_KIND := "c1_patrol"
const TRAP_Z := 19.0         # m into the chunk, between two lamps
const SIDEWALK_Y := 0.15
const SPEED_LIMIT_KMH := 70.0
const SEE_LIT := 140.0
const SEE_DARK := 9.0
const PAST := 6.0            # m beyond the cop where the pass is over
const CLOCKED_LINE := "Dave: Word is there is a patrol car sitting dark on the sidewalk tonight, and it just woke up. Somebody is having a worse shift than me."

var road_seed := 0
var night_clock: NightClock
var player: Node3D
## game.chunk_pool: [{root, index}], the live chunks.
var pool: Array = []
## Dave's line, as RadioManager.announce.
var announce: Callable = Callable()

## Tonight's spots by run: run -> [{chunk, card, fired}]. Emptied at 6 a.m.
var _runs: Dictionary = {}
var tonight := 1
var _check_t := 0.0
var _flicker_spot: Dictionary = {}
var _flicker_t := 0.0
var _flicker_i := 0
var _cops: Array[Node3D] = []

## On in the game; off in tests and benchmarks unless NEON_MOMENTS=1 (a parked
## car and dark blocks would move every other test's numbers).
static func enabled() -> bool:
	var env := OS.get_environment("NEON_MOMENTS")
	if env == "0" or env == "1":
		return env == "1"
	return not TestMode.active() and not Benchmark.requested()

# ---------- the deck (pure, seeded) ----------

## The chunk spot i of a run stands on: fixed for a road seed.
static func spot_chunk(seed: int, run: int, i: int) -> int:
	return run * Districts.RUN + FIRST_CHUNK + i * BAND + posmod(hash([seed, run, i, "spot"]), BAND - 1)

static func spot_tags(chunk: int) -> Array:
	var tags := ["block"]
	if not Junction.touches(chunk):
		tags.append("shoulder")
	return tags

static func deck_cards() -> Array:
	var cards := []
	for card in DECK:
		for _n in range(int(DECK[card])):
			cards.append(card)
	return cards

## The card dealt to spot i of a run on a night, before the spot's tags are
## looked at. Spots are numbered along the road; each deck-sized cycle of them
## gets its own shuffle of the whole deck.
static func card_at(seed: int, night: int, run: int, i: int) -> String:
	var cards := deck_cards()
	var g := run * SPOTS_PER_RUN + i
	var cycle := floori(float(g) / float(cards.size()))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed, night, cycle, "deck"])
	for k in range(cards.size() - 1, 0, -1):
		var j := rng.randi_range(0, k)
		var t = cards[k]
		cards[k] = cards[j]
		cards[j] = t
	return cards[posmod(g, cards.size())]

## What happens at spot i of a run on a night: its card, or "quiet" when the
## spot lacks a tag the card needs.
static func moment_at(seed: int, night: int, run: int, i: int) -> String:
	var card := card_at(seed, night, run, i)
	var tags := spot_tags(spot_chunk(seed, run, i))
	for need in NEEDS.get(card, []):
		if not tags.has(need):
			return "quiet"
	return card

# ---------- tonight ----------

func _ready() -> void:
	if night_clock != null:
		tonight = night_clock.night
		night_clock.night_ended.connect(func(_n: int) -> void: new_night.call_deferred())

func _exit_tree() -> void:
	for c in _cops:
		if c.get_parent() == null:
			c.free()
	_cops.clear()

func spots_of_run(run: int) -> Array:
	if not _runs.has(run):
		var spots := []
		for i in range(SPOTS_PER_RUN):
			spots.append({"chunk": spot_chunk(road_seed, run, i),
				"card": moment_at(road_seed, tonight, run, i), "fired": false})
		_runs[run] = spots
	return _runs[run]

## The spot whose moment covers this chunk, or {}.
func spot_at(chunk: int) -> Dictionary:
	for s in spots_of_run(Districts.run_of(chunk)):
		var reach: int = BLOCK_CHUNKS if s.card == "power_cut" else 1
		if chunk >= s.chunk and chunk < s.chunk + reach:
			return s
	return {}

## 6 a.m. rolled the night: a new deal, and the live chunks are put right.
func new_night() -> void:
	if night_clock != null:
		tonight = night_clock.night
	_runs.clear()
	_flicker_spot = {}
	for c in pool:
		dress_chunk(c.root, c.index, false)

# ---------- dressing a chunk ----------

## Called by the chunk pool after it builds or recycles a chunk (`rebuilt`:
## the builder has just rewritten the chunk, windows included).
func dress_chunk(root: Node3D, chunk: int, rebuilt := true) -> void:
	var s := spot_at(chunk)
	var card: String = s.get("card", "quiet")
	_set_dark(root, card == "power_cut" and s.fired, rebuilt)
	var cop := root.get_node_or_null(^"TrapCop") as Node3D
	if card == "speed_trap":
		if cop == null:
			cop = _take_cop()
			root.add_child(cop)
		var x := trap_x()
		var z := -float(chunk - RoadFrame.origin_index) * RoadChunkBuilder.CHUNK_LEN - TRAP_Z
		cop.transform = root.transform.affine_inverse() * RoadFrame.pose(x, SIDEWALK_Y, z, 0.0)
		cop.reset_physics_interpolation()
		_cop_lamps(cop, s.fired)
	elif cop != null:
		root.remove_child(cop)

## Lamps, pools, signs and windows of one chunk off or back on. A chunk that
## was never dark is left alone.
func _set_dark(root: Node3D, dark: bool, rebuilt := false) -> void:
	var was: bool = root.get_meta("moment_dark", false)
	if dark == was and not (dark and rebuilt):
		return
	root.set_meta("moment_dark", dark)
	(root.get_node(^"Lamps") as MultiMeshInstance3D).multimesh.mesh = RoadChunkBuilder.lamp_mesh(dark)
	(root.get_node(^"LampPools") as Node3D).visible = not dark
	var signs := root.get_node_or_null(^"Signs") as Node3D
	if signs != null:
		signs.visible = not dark
	for child in root.get_children():
		if not (child is MeshInstance3D and child.name.begins_with("BuildingMesh")):
			continue
		var mi := child as MeshInstance3D
		if dark:
			if rebuilt or not mi.has_meta("moment_lit"):
				mi.set_meta("moment_lit", mi.get_instance_shader_parameter("lit_density"))
			mi.set_instance_shader_parameter("lit_density", 0.0)
		elif not rebuilt and mi.has_meta("moment_lit"):
			mi.set_instance_shader_parameter("lit_density", mi.get_meta("moment_lit"))

## Across the road: the middle of the own-side sidewalk.
static func trap_x() -> float:
	return RoadChunkBuilder.MEDIAN_GAP + float(RoadChunkBuilder.MAX_OWN_LANES) * RoadChunkBuilder.LANE_W \
		+ RoadChunkBuilder.SHOULDER_W + RoadChunkBuilder.CURB_W + RoadChunkBuilder.SIDEWALK_W * 0.5

func _take_cop() -> Node3D:
	for c in _cops:
		if c.get_parent() == null:
			return c
	var cop := build_cop()
	_cops.append(cop)
	return cop

## A parked patrol car: the sheet body and wheels on a box the cars hit. No
## script, no physics of its own.
static func build_cop() -> Node3D:
	var k: Dictionary = NpcCarBuilder.KINDS[TRAP_KIND]
	var cfg := NpcCarBuilder.config(TRAP_KIND)
	var body := StaticBody3D.new()
	body.name = "TrapCop"
	body.collision_layer = 1 << (CarSpec.CAR_LAYER - 1)
	body.collision_mask = 0
	var vis := NpcCarBuilder.chassis_visual(TRAP_KIND, "stock", NpcCarBuilder.sheet_paint(TRAP_KIND))
	vis.position.y = float(k.rest_y)
	body.add_child(vis)
	for sx in [1.0, -1.0]:
		for sz in [-1.0, 1.0]:
			var hub := Vector3(float(k.wheel_x) * sx, float(k.wheel_r), float(k.axle_z) * sz)
			var wheel := NpcCarBuilder.wheel_visual(TRAP_KIND, "stock", hub)
			wheel.position = hub
			body.add_child(wheel)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = cfg.col_size
	shape.shape = box
	shape.position.y = float(cfg.col_y) + float(k.rest_y)
	body.add_child(shape)
	return body

## Dark while it waits; brake lamps and hazards once it has clocked the car.
func _cop_lamps(cop: Node3D, woke: bool) -> void:
	NpcCarBuilder.set_lamps(cop.get_node(^"NpcBody") as Node3D, 1.0 if woke else 0.0, woke)

# ---------- the watch ----------

func _physics_process(delta: float) -> void:
	if not _flicker_spot.is_empty():
		_flicker(delta)
	_check_t -= delta
	if _check_t > 0.0 or player == null:
		return
	_check_t = CHECK_EVERY
	look(player.global_position)

## One look at the spots around the car at world position `pos`.
func look(pos: Vector3) -> void:
	var at := RoadFrame.unroll(pos)
	var s := RoadFrame.s_at(at.z)
	var here := floori(s / RoadChunkBuilder.CHUNK_LEN)
	var runs := [Districts.run_of(here - 1)]
	if Districts.run_of(here + 3) != runs[0]:
		runs.append(Districts.run_of(here + 3))
	for run in runs:
		for spot in spots_of_run(run):
			if spot.fired:
				continue
			if spot.card == "power_cut":
				_watch_power_cut(spot, s)
			elif spot.card == "speed_trap":
				_watch_trap(spot, s, at.x)

func _watch_power_cut(spot: Dictionary, s: float) -> void:
	var ahead := float(spot.chunk) * RoadChunkBuilder.CHUNK_LEN - s
	if ahead > CUT_AT or ahead < -float(BLOCK_CHUNKS) * RoadChunkBuilder.CHUNK_LEN:
		return
	spot.fired = true
	_flicker_spot = spot
	_flicker_t = 0.0
	_flicker_i = 0
	power_cut_started.emit(spot.chunk)
	if announce.is_valid():
		announce.call(CUT_LINE)

## Runs the FLICKER steps on the block's live chunks: even steps dark.
func _flicker(delta: float) -> void:
	while _flicker_i < FLICKER.size() and _flicker_t >= float(FLICKER[_flicker_i]):
		var dark := _flicker_i % 2 == 0
		for c in pool:
			if c.index >= _flicker_spot.chunk and c.index < _flicker_spot.chunk + BLOCK_CHUNKS:
				_set_dark(c.root, dark)
		_flicker_i += 1
	_flicker_t += delta
	if _flicker_i >= FLICKER.size():
		_flicker_spot = {}

## Headlights: the car's `headlights_on` (police F1's H key) when it has one;
## a car without the switch is lit.
func lights_on() -> bool:
	var v = player.get("headlights_on")
	return v == null or v == true

func _watch_trap(spot: Dictionary, s: float, x: float) -> void:
	var ahead := float(spot.chunk) * RoadChunkBuilder.CHUNK_LEN + TRAP_Z - s
	if ahead > SEE_LIT:
		return
	var lit := lights_on()
	var seen := Vector2(ahead, trap_x() - x).length() <= (SEE_LIT if lit else SEE_DARK)
	var kmh := 0.0
	if player.has_method("current_speed"):
		kmh = absf(player.current_speed()) * 3.6
	if seen and ahead >= -PAST and kmh > SPEED_LIMIT_KMH:
		spot.fired = true
		var cop := _cop_of(spot.chunk)
		if cop != null:
			_cop_lamps(cop, true)
		clocked.emit(kmh, cop)
		if announce.is_valid():
			announce.call(CLOCKED_LINE)
	elif ahead < -PAST:
		spot.fired = true
		slipped.emit(not lit)

func _cop_of(chunk: int) -> Node3D:
	for c in pool:
		if c.index == chunk:
			return c.root.get_node_or_null(^"TrapCop") as Node3D
	return null
