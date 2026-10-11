extends SceneTree

# Police P1 proof in the real game: a bot driving at the traffic flow in every
# own-direction lane (115 / 100 / 85 / 70 km/h, the TrafficManager lane
# speeds) for 150 s each = 10 minutes, with the patrol car on the road
# (alternating oncoming and same direction), gets 0 heat, no warning and no
# loudspeaker line; cops do see it (so the test means something). Then the
# same bot in the slowest lane at 100 km/h (30 over the flow of 70, over the
# city line of 85) gets a warning, then heat 1 when it ignores it.
# Needs --fixed-fps 60 (game time runs as fast as the laptop steps it):
#   <godot> --headless --fixed-fps 60 --path . -s res://tests/traffic/police_flow.gd
# No traffic cars (the bot never brakes for them, a rear-end crash is its own
# fault and would be a legitimate offence); the patrol car is the only one.

const Harness := preload("res://tests/traffic/traffic_harness.gd")
const LANE_SECS := 150.0
const SPEEDING_SECS := 240.0

var failures: Array[String] = []
var game: Node
var player: PlayerCar
var heat: PoliceHeat
var step := 0
var t := 0
var game_t := 0.0
var lane := 0
var lane_start := 0.0
var max_level := 0
var warnings := 0
var spotted := 0
var lines: Array[String] = []
var wall_start := 0

func _check(ok: bool, msg: String) -> void:
	if not ok:
		failures.append(msg)

func _initialize() -> void:
	OS.set_environment("NEON_POLICE", "1")
	game = Harness.boot(self, 0, 300.0, 11)
	wall_start = Time.get_ticks_msec()

func _flow_kmh(i: int) -> float:
	var traffic: TrafficManager = game.get("traffic")
	return traffic.lane_speeds_own[i] * 3.6

func _go_lane(i: int, kmh: float) -> void:
	Harness.move_player_to_lane(player, Harness.lane_x(i))
	Harness.launch_player(player, kmh / 3.6)
	player.driver = Harness.lane_driver(Harness.lane_x(i), 1.0, kmh / 3.6)
	lane_start = game_t

func _physics_process(delta: float) -> bool:
	t += 1
	game_t += delta
	match step:
		0:
			if t < 5:
				return false
			player = game.get("player")
			heat = game.get("police_heat")
			_check(heat != null and game.get("police") != null, "no police in the game with NEON_POLICE=1")
			if heat == null:
				return _finish()
			(game.get("night_clock") as NightClock).night = 1
			heat.reset()
			heat.warning_started.connect(func(_c: Node3D, _k: int) -> void: warnings += 1)
			heat.spotted.connect(func(_c: Node3D) -> void: spotted += 1)
			heat.line_said.connect(func(s: String) -> void: lines.append(s))
			_go_lane(0, _flow_kmh(0))
			step = 1
		1:
			max_level = maxi(max_level, heat.level)
			if game_t - lane_start >= LANE_SECS:
				_check(max_level == 0 and warnings == 0, "flow in lane %d (%.0f km/h): max level %d, warnings %d" % [lane, _flow_kmh(lane), max_level, warnings])
				lane += 1
				if lane < 4:
					_go_lane(lane, _flow_kmh(lane))
				else:
					print("police_flow: 600 s at the flow: spotted %d times, max level %d, warnings %d, wall %.0f s" % [spotted, max_level, warnings, (Time.get_ticks_msec() - wall_start) / 1000.0])
					_check(spotted >= 1, "no cop ever saw the bot in 10 minutes: the proof proves nothing")
					_check(not lines.has(PoliceHeat.MOCK_LINE) and not PoliceRules.WARN_LINES.values().any(func(l: String) -> bool: return lines.has(l)),
						"police spoke at the flow: %s" % [lines])
					_go_lane(3, 100.0)
					step = 2
		2:
			if heat.level >= PoliceHeat.ONE_CAR:
				_check(warnings >= 1, "heat 1 without a warning first")
				return _finish()
			if game_t - lane_start >= SPEEDING_SECS:
				_check(false, "100 km/h in the 70 lane for %.0f s: level %d, warnings %d, spotted %d" % [SPEEDING_SECS, heat.level, warnings, spotted])
				return _finish()
	return false

func _finish() -> bool:
	for f in failures:
		printerr("FAIL: " + f)
	print("police_flow: %s" % ("PASS" if failures.is_empty() else "FAIL (%d)" % failures.size()))
	quit(0 if failures.is_empty() else 1)
	return true
