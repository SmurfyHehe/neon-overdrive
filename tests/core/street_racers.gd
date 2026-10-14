extends SceneTree

# Street racers test (S2, docs/planning/races-in-the-world-2026-10-14.md): a
# racer in the traffic you flash to race.
#
# Part 1, the rules: who can be a racer, when a racer says no, the halo pulse.
# Part 2, the real game with traffic:
# - a street racer is picked from the traffic ahead and carries the halo;
# - flashed with heat on you, it says no and stays a racer;
# - flashed (through the traffic's own flash counter), it says yes: hazards,
#   then a rolling race with THAT car as the rival, counted from where each
#   car was (no head start), and the halo is gone;
# - given up: no retry offered, the car drives off for good, a new racer
#   only after the cool-down.
#   <godot> --headless --path . -s res://tests/core/street_racers.gd

const StreetRacers := preload("res://scripts/core/street_racers.gd")
const Harness := preload("res://tests/traffic/traffic_harness.gd")

const MARK_LIMIT := 60 * 40   # ticks to wait for a racer to be picked

var failures: Array[String] = []
var game: Node
var ticks := 0
var step := 0
var step_at := 0
var car: TrafficCar

func _initialize() -> void:
	_rules()
	game = Harness.boot(self, 30, 300.0, 7)

func _check(ok: bool, msg: String) -> void:
	if not ok:
		failures.append(msg)

func _rules() -> void:
	_check(StreetRacers.says_no(1, false) and StreetRacers.says_no(0, true) and not StreetRacers.says_no(0, false), "says_no is wrong")
	var lo := INF
	var hi := -INF
	for i in 100:
		var e := StreetRacers.halo_energy(i * 0.01)
		lo = minf(lo, e)
		hi = maxf(hi, e)
	_check(lo > 0.0 and hi - lo > 1.0, "the halo does not pulse (%.2f..%.2f)" % [lo, hi])
	_check(not StreetRacers.can_mark(null, -1.0, 100.0), "a null car can be marked")
	print("street racers: rules checked")

func _physics_process(_delta: float) -> bool:
	ticks += 1
	var sr: Node = game.get("street_racers")
	var race: Node = game.get("race")
	var traffic: TrafficManager = game.get("traffic")
	if ticks == 5 and sr == null:
		_check(false, "the game has no StreetRacers")
		return _end()
	if sr == null:
		return false
	match step:
		0:
			if sr.state == StreetRacers.State.MARKED:
				car = sr.racer
				_check(car != null and car.street_racer, "the marked car is not flagged")
				_check(sr.halo != null and sr.halo.get_parent() == car, "the racer has no halo")
				_check(car.direction == traffic.flow and car.kind.begins_with("n"), "the racer is not traffic going your way")
				# heat on: no
				var heat: PoliceHeat = game.get("police_heat")
				var was: int = heat.level
				heat.level = 1
				_check(not sr.challenge() and sr.declines == 1 and sr.state == StreetRacers.State.MARKED, "a racer said yes with cops on you")
				heat.level = was
				# the real flash path: the traffic counts a flash at the racer
				sr.challenge_reach = 1.0e6
				traffic.flashed_car = car
				traffic.flash_count += 1
				step = 1
				step_at = ticks
			elif ticks > MARK_LIMIT:
				_check(false, "no street racer was picked in %d ticks" % MARK_LIMIT)
				return _end()
		1:
			if ticks == step_at + 2:
				_check(sr.state == StreetRacers.State.ACCEPTING and sr.challenges == 1, "the flash did not challenge the racer (state %d)" % sr.state)
				_check(car.hazards_until > traffic.now, "the racer's hazards are not on")
			if ticks == step_at + int(StreetRacers.GO_AT * Engine.physics_ticks_per_second) + 10:
				_check(race.is_racing() and race.race_kind == "rolling", "no rolling race after the yes")
				_check(race.rival == car and car.race_pinned and car.racer != null, "the rival is not the racer you flashed")
				_check(absf(race.rival_progress()) < 15.0 and absf(race.player_progress()) < 15.0, "progress does not start from each car's own place (rival %.1f, you %.1f)" % [race.rival_progress(), race.player_progress()])
				_check(sr.halo == null and not car.street_racer and sr.state == StreetRacers.State.RACING, "the racer still has its halo in the race")
				step = 2
				step_at = ticks
		2:
			# the racer drives off flat out under its racing driver
			if ticks == step_at + 4 * Engine.physics_ticks_per_second:
				_check(race.rival_progress() > 30.0, "the rival did not race away (%.1f m in 4 s)" % race.rival_progress())
				race.give_up()
				_check(not race.can_retry(), "a rolling challenge offers a retry")
				_check(car.race_released and not car.race_pinned, "the racer did not drive off for good")
				_check(sr.state == StreetRacers.State.WAITING and sr._wait >= StreetRacers.COOLDOWN - 0.1, "no cool-down after the race")
				return _end()
	return false

func _end() -> bool:
	for m in failures:
		printerr("FAIL: ", m)
	print("street racers: ", "PASS" if failures.is_empty() else "FAIL (%d)" % failures.size())
	quit(0 if failures.is_empty() else 1)
	return true
