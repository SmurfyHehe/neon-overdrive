extends SceneTree

# Tonight's events test (living world step 3, 2026-10-08), headless and silent:
# - the pure table: which event is on when, the rule-breaker share for each
#   (3 / 12 / 20 / 0.5 %), the 20% cap where a meet runs through bar close,
#   weaving only at bar close, the bar-close traffic burst with no jumps
# - the real game from 1:59 a.m. (NEON_CLOCK) on Dave's station: 2 a.m.
#   strikes and Dave warns about bar close; at 2:05 the spawns carry about 12%
#   rule breakers, some weaving, all faster than their lane; a meet night lifts
#   the share to 20%; a crackdown makes everyone on the road behave at once and
#   Dave says so. Wrecks are counted and printed.
#
# Setting sweep: NEON_TRAFFIC=4 / 16 / 40 / 80 (default 40, so enough cars
# spawn for the share to mean something; 0 also means 40).
#
# Exit code 1 on failure. Run (headless):
#   Godot_v4.7.2-stable_win64_console.exe --headless --fixed-fps 60 --path . -s res://tests/world/world_mood.gd

const TIMEOUT_TICKS := 1800
const TALK := 2
const SAMPLE_SPAWNS := 150
const SAMPLE_TICKS := 20000

enum Step { BOOT, BAR_CLOSE, SAMPLE, MEET, CRACKDOWN, DONE }

var step := Step.BOOT
var step_start := 0
var tick := 0
var failures: Array[String] = []
var game: Node
var cars := 40
var spawns_at := 0
var breakers_at := 0
var heard_bar_close := false

func _initialize() -> void:
	var env := OS.get_environment("NEON_TRAFFIC")
	# run_tests.bat sets NEON_TRAFFIC=0 for the older drive tests; with no cars
	# there is no share to measure, so 0 means the default here.
	cars = int(env) if env.is_valid_int() and int(env) > 0 else 40
	OS.set_environment("NEON_TRAFFIC", str(cars))
	_table_tests()
	NightClock.path = "user://test_world_mood.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(NightClock.path))
	OS.set_environment("NEON_CLOCK", "01:59")
	print("world_mood: %d cars" % cars)
	change_scene_to_file("res://Game.tscn")

func _table_tests() -> void:
	var E := WorldMood.Event
	_check(WorldMood.event_at(100.0, false, false) == E.NORMAL, "9:40 p.m. is a normal night")
	_check(WorldMood.event_at(360.0, false, false) == E.BAR_CLOSE, "2:00 a.m. is bar close")
	_check(WorldMood.event_at(389.0, false, false) == E.BAR_CLOSE, "2:29 a.m. is bar close")
	_check(WorldMood.event_at(390.0, false, false) == E.NORMAL, "2:30 a.m. is over")
	_check(WorldMood.event_at(100.0, true, false) == E.NORMAL, "a meet starts at 10 p.m.")
	_check(WorldMood.event_at(150.0, true, false) == E.MEET, "10:30 p.m. on a meet night")
	_check(WorldMood.event_at(370.0, true, true) == E.CRACKDOWN, "a crackdown beats everything")
	_near(WorldMood.rule_breaker_share(100.0, false, false), 0.03, "normal share")
	_near(WorldMood.rule_breaker_share(365.0, false, false), 0.12, "bar close share")
	_near(WorldMood.rule_breaker_share(200.0, true, false), 0.20, "meet share")
	_near(WorldMood.rule_breaker_share(365.0, true, false), 0.20, "meet through bar close: the higher share, capped")
	_near(WorldMood.rule_breaker_share(365.0, true, true), 0.005, "crackdown share")
	var m := 0.0
	var prev := WorldMood.traffic_bonus(0.0)
	while m <= NightClock.NIGHT_MINUTES:
		var s := WorldMood.rule_breaker_share(m, true, false)
		_check(s <= WorldMood.CAP and s <= TrafficManager.RULE_BREAKER_CAP, "share never above 20%% (%.2f at %.0f)" % [s, m])
		var b := WorldMood.traffic_bonus(m)
		_check(absf(b - prev) <= 0.051, "no jump in the bar-close burst at %.0f (%.3f -> %.3f)" % [m, prev, b])
		_check(b == 0.0 or (m >= 360.0 and m < 400.0), "the burst only around bar close (%.0f)" % m)
		prev = b
		m += 1.0
	_near(WorldMood.traffic_bonus(370.0), 0.25, "the taxi burst")
	_check(WorldMood.weave_share(365.0, false) > 0.0 and WorldMood.weave_share(200.0, false) == 0.0, "weaving at bar close only")
	_check(WorldMood.weave_share(365.0, true) == 0.0, "nobody weaves in a crackdown")

func _physics_process(_delta: float) -> bool:
	tick += 1
	if step == Step.DONE:
		return false
	game = current_scene
	if game == null or game.get("world_mood") == null or game.get("traffic") == null:
		return tick > TIMEOUT_TICKS and _end("Game never became ready")
	var traffic: TrafficManager = game.traffic
	var clock: NightClock = game.night_clock
	var mood: WorldMood = game.world_mood
	var waited := tick - step_start
	match step:
		Step.BOOT:
			_check(not mood.meet_night, "no meet without NEON_MEET")
			game.radio.station = TALK
			clock.speed = 30.0   # 1:59 -> 2:00 in about 2 s
			_go(Step.BAR_CLOSE)
		Step.BAR_CLOSE:
			if clock.minutes >= 365.0:
				clock.speed = 0.0   # hold 2:05 a.m.
				_check(heard_bar_close or game.radio.dj_text == WorldMood.BAR_CLOSE_LINE, "Dave warns about bar close at 2 (%s)" % game.radio.dj_text)
				_check(mood.event == WorldMood.Event.BAR_CLOSE, "2:05 a.m. is bar close (%s)" % WorldMood.event_name(mood.event))
				_near(traffic.rule_breaker_share, 0.12, "the traffic got the bar-close share")
				_check(traffic.weave_share > 0.0, "and some of them weave")
				spawns_at = traffic.spawn_count
				breakers_at = traffic.rule_breaker_spawns
				_go(Step.SAMPLE)
			elif game.radio.dj_text == WorldMood.BAR_CLOSE_LINE:
				heard_bar_close = true
			elif waited > 1200:
				return _end("2:05 a.m. never came (%s)" % clock.text())
		Step.SAMPLE:
			var n := traffic.spawn_count - spawns_at
			if n >= SAMPLE_SPAWNS or (waited > SAMPLE_TICKS and n > 0):
				var share := float(traffic.rule_breaker_spawns - breakers_at) / float(n)
				print("world_mood: bar close, %d spawns, %.1f%% rule breakers, %d on the road, %d weaving, %d wrecks so far" % [
					n, share * 100.0, traffic.rule_breakers_on_road(), _weavers(traffic), traffic.wreck_recycle_count])
				if n >= SAMPLE_SPAWNS:
					_check(share > 0.04 and share < 0.22, "about 12%% of spawns break rules (%.1f%%)" % (share * 100.0))
				for car in traffic.cars:
					if car.rule_breaker and not car.benched:
						_check(_spawned_fast(traffic, car), "a rule breaker cruises %.1f m/s over its spawn lane (%.1f)" % [TrafficCar.RB_SPEED, car.target_speed])
				mood.meet_night = true
				_go(Step.MEET)
			elif waited > SAMPLE_TICKS:
				return _end("no spawns in %d ticks" % waited)
		Step.MEET:
			if waited == 2:
				_check(mood.event == WorldMood.Event.MEET, "a meet night runs through bar close (%s)" % WorldMood.event_name(mood.event))
				_near(traffic.rule_breaker_share, 0.20, "meet share, capped")
				_check(game.radio.dj_text == WorldMood.EVENT_LINES[WorldMood.Event.MEET], "Dave mentions the meet (%s)" % game.radio.dj_text)
			if waited == 600:
				print("world_mood: meet night, %d rule breakers on the road of %d" % [traffic.rule_breakers_on_road(), traffic.active_count()])
				mood.start_crackdown(clock.minutes, 10.0)
				_go(Step.CRACKDOWN)
		Step.CRACKDOWN:
			if waited == 2:
				_check(mood.event == WorldMood.Event.CRACKDOWN, "crackdown on (%s)" % WorldMood.event_name(mood.event))
				_check(traffic.rule_breakers_on_road() == 0, "everyone behaves at once (%d still breaking rules)" % traffic.rule_breakers_on_road())
				_near(traffic.rule_breaker_share, 0.005, "crackdown share")
				_check(traffic.weave_share == 0.0, "nobody weaves")
				_check(game.radio.dj_text == WorldMood.EVENT_LINES[WorldMood.Event.CRACKDOWN], "Dave mentions the cops (%s)" % game.radio.dj_text)
				clock.minutes = mood.crackdown_until + 1.0
			if waited == 4:
				_check(mood.event == WorldMood.Event.MEET, "the crackdown ends on time and the meet is back (%s)" % WorldMood.event_name(mood.event))
				print("world_mood: %d wrecks recycled over the run" % traffic.wreck_recycle_count)
				return _end("")
	return false

func _weavers(traffic: TrafficManager) -> int:
	var n := 0
	for car in traffic.cars:
		if car.weave > 0.0 and not car.benched:
			n += 1
	return n

func _go(next: Step) -> void:
	step = next
	step_start = tick

func _near(got: float, want: float, msg: String) -> void:
	_check(absf(got - want) < 1e-4, "%s: expected %.3f, got %.3f" % [msg, want, got])

func _check(ok: bool, msg: String) -> void:
	if not ok:
		failures.append(msg)

var _ended := false
func _end(msg: String) -> bool:
	if _ended:
		return true
	_ended = true
	step = Step.DONE
	if msg != "":
		failures.append(msg)
	for f in failures:
		printerr("FAIL: ", f)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(NightClock.path))
	print("world_mood: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
	return true

## Its cruise speed is some lane's speed plus RB_SPEED, within the jitter
## (a lane change since the spawn does not change the cruise speed).
func _spawned_fast(traffic: TrafficManager, car: TrafficCar) -> bool:
	var oncoming := car.direction > 0.0
	for l in (traffic.onc_lanes if oncoming else traffic.own_lanes):
		if absf(car.target_speed - TrafficCar.RB_SPEED - traffic.lane_speed(l, oncoming)) <= TrafficManager.SPEED_JITTER + 0.01:
			return true
	return false
