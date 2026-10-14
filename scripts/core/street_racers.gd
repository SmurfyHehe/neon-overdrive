extends Node

# Street racers, step S2 of races in the world
# (docs/planning/races-in-the-world-2026-10-14.md): the rolling challenge.
#
# One car in the traffic ahead of you, going your way, is a street racer. It
# carries a halo: an amber glow on the road under it that pulses, seen within
# HALO_RANGE (decided: the halo shows close only). Flash it (H) from behind
# within CHALLENGE_REACH and it answers:
#
#   yes   its hazards blink, the halo flares, three honks, "GO!": a race from
#         where you both are (RaceController.start_rolling), to the line
#         DEFAULT_DISTANCE down the road. Win pays (Stakes, $250). Lose or
#         give up and it drives off: gone for the night, no retry (decided).
#   no    with cops on you (heat 1+) or a race already on: it waves you off.
#
# Roy's rule: real-life based, effects exaggerated. The hazards, the halo flare
# and the big stamps are louder than life on purpose.
#
# Placeholders until later steps: the finish is a fixed distance, not the next
# landmark; any NPC car can be the racer (sport builds first); no crew sticker
# yet, the halo alone marks it.
# No class_name on purpose: preload it, so no class cache refresh is needed.

const RaceControllerScript := preload("res://scripts/core/race_controller.gd")

## How often (s) a new racer is looked for when there is none.
const MARK_EVERY := 3.0
## A new racer is picked this far ahead of you (m, along the road).
const MARK_MIN_AHEAD := 60.0
const MARK_MAX_AHEAD := 450.0
## A racer this far behind or ahead is let go (it left you behind, or you it).
const DROP_BEHIND := 150.0
const DROP_AHEAD := 800.0
## The flash only counts this close (m, centre to centre along the road).
const CHALLENGE_REACH := 35.0
## After a race or a wave-off, no new racer for this long (s).
const COOLDOWN := 20.0
## The halo shows within this far of you (decided: close only, 60 m).
const HALO_RANGE := 60.0

## The yes: hazards for HAZARD_SECS, honks at HONKS, go at GO_AT (s).
const HAZARD_SECS := 1.3
const HONKS := [0.45, 0.85, 1.25]
const GO_AT := 1.65

const SODIUM := Color("#FF8A1F")
const AMBER := Color("#FFC066")
const SILVER := Color("#C9CED6")
const HALO_ENERGY := 1.4
const HALO_PULSE := 0.7      # +- energy
const HALO_HZ := 1.6
const HALO_REACH := 3.6      # m of light under the car
const FLARE_ENERGY := 7.0
const FLARE_REACH := 7.5

enum State { WAITING, MARKED, ACCEPTING, RACING }

signal marked(car: TrafficCar)
signal accepted(car: TrafficCar)
signal declined(car: TrafficCar)

var traffic: TrafficManager
var race: Node
var player: Node3D
var heat: Object
var stakes: Node

var state := State.WAITING
var racer: TrafficCar
var halo: OmniLight3D
var challenges := 0
var declines := 0
## Tests widen this to challenge from anywhere.
var challenge_reach := CHALLENGE_REACH
var _wait := MARK_EVERY
var _flashes_seen := -1
var _t := 0.0
var _honked := 0

func bind(t: TrafficManager, r: Node, p: Node3D, h: Object, s: Node) -> void:
	traffic = t
	race = r
	player = p
	heat = h
	stakes = s
	if race != null:
		race.race_ended.connect(_on_race_ended)

func _ready() -> void:
	name = "StreetRacers"

# ---------- pure rules (tests use these) ----------

## Whether `car` may be picked as a street racer at `ahead` m in front of you.
static func can_mark(car: TrafficCar, flow: float, ahead: float) -> bool:
	if car == null or not is_instance_valid(car):
		return false
	if car.benched or car.race_pinned or car.race_released or car.sim_only or car.wrecked:
		return false
	if car.direction != flow or not car.kind.begins_with("n"):
		return false
	return ahead >= MARK_MIN_AHEAD and ahead <= MARK_MAX_AHEAD

## A racer says no with the cops on you or a race already on.
static func says_no(heat_level: int, racing: bool) -> bool:
	return heat_level > 0 or racing

static func halo_energy(t: float) -> float:
	return HALO_ENERGY + HALO_PULSE * sin(TAU * HALO_HZ * t)

# ---------- the loop ----------

func _ahead(car: Node3D) -> float:
	return RaceControllerScript.road_distance(car.global_position) - RaceControllerScript.road_distance(player.global_position)

func _physics_process(delta: float) -> void:
	if traffic == null or player == null or race == null:
		return
	_t += delta
	match state:
		State.WAITING:
			_wait -= delta
			if _wait <= 0.0:
				_wait = MARK_EVERY
				if not race.is_racing():
					_pick()
		State.MARKED:
			if not _still_good():
				_unmark()
				_wait = MARK_EVERY
			else:
				_watch_flash()
		State.ACCEPTING:
			_accepting(delta)
	_draw_halo(delta)

func _pick() -> void:
	var best: TrafficCar = null
	var best_score := INF
	for car in traffic.cars:
		var a := _ahead(car)
		if not can_mark(car, traffic.flow, a):
			continue
		# a sport build first, then the nearest
		var score := a + (0.0 if car.build == "sport" else 1000.0)
		if score < best_score:
			best = car
			best_score = score
	if best != null:
		mark(best)

## Makes `car` the street racer (tests call it to pick one).
func mark(car: TrafficCar) -> void:
	if racer != null:
		_unmark()
	racer = car
	car.street_racer = true
	halo = OmniLight3D.new()
	halo.name = "RacerHalo"
	halo.light_color = SODIUM
	halo.omni_range = HALO_REACH
	halo.light_energy = HALO_ENERGY
	halo.shadow_enabled = false
	halo.position = Vector3(0.0, 0.35, 0.0)
	halo.visible = false
	car.add_child(halo)
	state = State.MARKED
	_flashes_seen = traffic.flash_count
	marked.emit(car)

func _unmark() -> void:
	if racer != null and is_instance_valid(racer):
		racer.street_racer = false
	if halo != null and is_instance_valid(halo):
		halo.queue_free()
	halo = null
	racer = null
	state = State.WAITING

func _still_good() -> bool:
	if racer == null or not is_instance_valid(racer) or racer.benched or racer.wrecked or racer.race_released:
		return false
	var a := _ahead(racer)
	return a > -DROP_BEHIND and a < DROP_AHEAD

func _watch_flash() -> void:
	var n: int = traffic.flash_count
	if n == _flashes_seen:
		return
	_flashes_seen = n
	if traffic.flashed_car != racer:
		return
	var a := _ahead(racer)
	if a <= 0.0 or a > challenge_reach:
		return
	challenge()

## The racer was flashed from close behind: yes or no.
func challenge() -> bool:
	if racer == null or state != State.MARKED:
		return false
	racer.flashed_at = -1000.0   # it is not being asked to move over
	var lvl: int = int(heat.level) if heat != null else 0
	if says_no(lvl, race.is_racing()):
		declines += 1
		if stakes != null:
			stakes.shout("NOT NOW", "COPS ON YOU" if lvl > 0 else "", SILVER, false)
		declined.emit(racer)
		return false
	challenges += 1
	state = State.ACCEPTING
	_t = 0.0
	_honked = 0
	racer.hazards_until = traffic.now + HAZARD_SECS
	if stakes != null:
		stakes.cut_queue()
		stakes.shout("CHALLENGE", "THEY'RE IN", AMBER, true)
	accepted.emit(racer)
	return true

func _accepting(_delta: float) -> void:
	if not _still_good() and _t < GO_AT:
		_unmark()
		_wait = COOLDOWN
		return
	while _honked < HONKS.size() and _t >= HONKS[_honked]:
		traffic.honk(racer, false)
		_honked += 1
	if _t < GO_AT:
		return
	var car := racer
	_unmark()   # the halo goes: it is the rival now
	if race.start_rolling(car):
		state = State.RACING
		if stakes != null:
			stakes.cut_queue()
			stakes.shout("GO!", "", AMBER, true)
	else:
		_wait = COOLDOWN

func _on_race_ended(_r: int) -> void:
	if state == State.RACING:
		state = State.WAITING
		_wait = COOLDOWN

# ---------- the halo ----------

func _draw_halo(_delta: float) -> void:
	if halo == null or racer == null or not is_instance_valid(racer):
		return
	var near := absf(_ahead(racer)) <= HALO_RANGE and racer.visible
	halo.visible = near
	if not near:
		return
	if state == State.ACCEPTING:
		var k := clampf(_t / GO_AT, 0.0, 1.0)
		halo.light_energy = lerpf(FLARE_ENERGY, HALO_ENERGY, k) * (1.0 if fmod(_t, 0.3) < 0.18 else 0.4)
		halo.omni_range = lerpf(FLARE_REACH, HALO_REACH, k)
	else:
		halo.light_energy = halo_energy(_t)
		halo.omni_range = HALO_REACH
