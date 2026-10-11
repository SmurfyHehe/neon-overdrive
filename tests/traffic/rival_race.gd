extends SceneTree

# Rival driver, wired in (rival driver build spec, step 2): the race as the
# game runs it. The real Game.tscn with its bends and hills and 16 traffic
# cars; the player is the shared test driver (clean, 170 km/h) and starts a
# 1500 m race the way the pause menu's "Race a test rival" does. Checks:
#   - the rival has a racing driver and stays in the full sim while it is
#     inside the built road (RaceController.RACE_SIM_DISTANCE_HILLS),
#   - it never wrecks, never falls through the road, never leaves the road,
#   - the race ends by somebody crossing the line, and the car is handed back
#     to traffic with no driver.
# Reports who won, how far the rival got, and how much of the race it spent
# with its racing line put away for traffic.
#
# Exit code 1 on failure. Run (about 1.5 min):
#   Godot_v4.7.2-stable_win64_console.exe --headless --fixed-fps 120 --path . -s res://tests/traffic/rival_race.gd

const Harness := preload("res://tests/traffic/traffic_harness.gd")
const TestDriver := preload("res://scripts/core/test_driver.gd")

const DISTANCE := 1500.0
const TIMEOUT_TICKS := 120 * 150

var failures: Array[String] = []
var game: Node
var race: RaceController
var rival: TrafficCar
var wait := 0
var racing := false
var ticks := 0
var sim_ticks := 0
var traffic_ticks := 0
var top := 0.0
var braked := 0
var lowest := INF
var off_road := 0
var rival_m := 0.0

func _initialize() -> void:
	Engine.physics_ticks_per_second = 120
	OS.set_environment("NEON_POLICE", "0")
	OS.set_environment("NEON_CURVES", "0.5")
	OS.set_environment("NEON_HILLS", "0.5")
	OS.set_environment("NEON_ROAD", "endless")
	OS.set_environment("NEON_ROAD_SEED", "11")
	OS.set_environment("NEON_LAYOUT", "0")
	OS.set_environment("NEON_WEATHER", "dry")
	OS.set_environment("NEON_MUTE", "1")
	OS.set_environment("NEON_RACE", "")
	OS.set_environment("NEON_RACE_SEED", "3")
	game = Harness.boot(self, 16, 300.0, 21)

func _physics_process(_delta: float) -> bool:
	wait += 1
	if not racing:
		if game.get("race") != null and game.get("player") != null and wait > 120:
			race = game.race
			# A rolling start at 110 km/h: the build boots parked with the engine off.
			Harness.launch_player(game.player, 30.0)
			TestDriver.start(game, "clean", {"speed": 170.0, "lane": 2})
			_check(race.start_race(DISTANCE), "start_race returns true")
			rival = race.rival
			_check(rival != null and rival.racer != null, "the rival has a racing driver")
			_check(rival != null and rival.kind == RaceController.RIVAL_KIND, "the rival drives the rival car")
			_check(game.traffic.pinned_distance == RaceController.RACE_SIM_DISTANCE_HILLS, "the rival's full sim reaches as far as the built road")
			racing = true
			wait = 0
		return false
	if race.phase == RaceController.Phase.RACING and is_instance_valid(rival):
		ticks += 1
		rival_m = race.rival_progress()
		if rival.detailed:
			sim_ticks += 1
			var u := RoadFrame.unroll(rival.global_position)
			lowest = minf(lowest, u.y)
			if u.x - rival.half_w < 0.0 or u.x + rival.half_w > RoadChunkBuilder.MEDIAN_GAP + 4.0 * RoadChunkBuilder.LANE_W + RoadChunkBuilder.SHOULDER_W:
				off_road += 1
			top = maxf(top, rival.current_speed())
			if rival.brake_input > 0.05:
				braked += 1
			if rival.racer.in_traffic:
				traffic_ticks += 1
		if rival.wrecked:
			_check(false, "the rival wrecked %.0f m into the race" % rival_m)
			return _finish()
	elif race.phase != RaceController.Phase.RACING:
		return _finish()
	if wait > TIMEOUT_TICKS:
		_check(false, "the race did not end in %d s (rival at %.0f m, player at %.0f m)" % [TIMEOUT_TICKS / 120, rival_m, race.player_progress()])
		return _finish()
	return false

func _finish() -> bool:
	var r := race.result
	_check(r == RaceController.Result.WIN or r == RaceController.Result.LOSE, "the race ended at the line (got %s)" % RaceController.Result.keys()[r])
	_check(lowest > -1.0, "the rival stayed on the road surface (lowest %.2f m)" % lowest)
	_check(off_road == 0, "the rival stayed on its side of the road (%d ticks off it)" % off_road)
	_check(is_instance_valid(rival) and rival.racer == null and rival.race_released, "the car went back to traffic with no driver")
	_check(game.traffic.pinned_distance == TrafficManager.PINNED_DISTANCE_DEFAULT, "the sim distance is back to normal")
	print("race: %s in %.1f s; player %.0f m, rival %.0f m of %.0f; rival top %.0f km/h, braking on %d ticks, in the full sim %d%% of the race, line put away for traffic %d%% of that, off road %d ticks" % [
		RaceController.Result.keys()[r], race.race_time, race.player_progress(), rival_m, DISTANCE, top * 3.6, braked,
		roundi(100.0 * float(sim_ticks) / maxf(float(ticks), 1.0)), roundi(100.0 * float(traffic_ticks) / maxf(float(sim_ticks), 1.0)), off_road])
	print("rival_race: ", "PASS" if failures.is_empty() else "FAIL (%d)" % failures.size())
	quit(0 if failures.is_empty() else 1)
	return true

func _check(ok: bool, what: String) -> void:
	if not ok:
		failures.append(what)
		printerr("FAIL: ", what)
