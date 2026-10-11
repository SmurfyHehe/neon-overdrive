extends SceneTree

# Police P4 proof (spec section 11): the free driver chases the test bot for
# 5 minutes through 40 traffic cars in the real game. The bot (TestDriver
# "weave": holds a speed, changes lane into checked gaps) is the target; a
# patrol-kind car with a FreeDriver follows it 12 m behind.
#
# Must hold:
#   - the chaser is never on its roof or side (no flips);
#   - it is never stuck (stopped while its target drives on) for more than 5 s;
#     a stuck car is recycled behind the target out of view;
#   - it does not plough through traffic: body overlaps with traffic cars are
#     counted (rising edges) and capped;
#   - it does chase: it gets to its spot and spends most of the run near it.
# Prints the chase numbers and the driver's cost per AI tick.
#
# Env: CHASE_SECS (300), CHASE_CARS (40), CHASE_SPEED (km/h of the bot, 105),
# CHASE_SEED (1). Run (about 3 min):
#   <godot> --headless --fixed-fps 60 --path . -s res://tests/traffic/free_driver_chase.gd

const Harness := preload("res://tests/traffic/traffic_harness.gd")
const TestDriver := preload("res://scripts/core/test_driver.gd")
const KIND := "c1_patrol"
const BACK := 12.0
const START_BEHIND := 60.0
const MAX_TOUCHES := 2
const NEAR_M := 40.0

var failures: Array[String] = []
var game: Node
var p: PlayerCar
var traffic: TrafficManager
var cop: TrafficCar
var drv: FreeDriver
var bot: RefCounted
var secs := 300.0
var cars := 40
var speed_kmh := 105.0
var seed_value := 1
var game_t := 0.0
var ticks := 0
var flip_ticks := 0
var stuck_run := 0.0
var stuck_max := 0.0
var touching := {}
var touches := 0
var touch_log: Array[String] = []
var player_touching := false
var player_touches := 0
var wreck_touches := 0
var bot_contacts_seen := 0
var bot_spins_seen := 0
var bot_trouble_t := -100.0
var near_ticks := 0
var sim_ticks := 0
var dist_sum := 0.0
var dist_min := INF
var dist_max := 0.0
var v_sum := 0.0
var blocked_ticks := 0
var wrong_way_ticks := 0

func _env(name: String, fallback: String) -> String:
	var v := OS.get_environment(name)
	return v if v != "" else fallback

func _check(ok: bool, msg: String) -> void:
	if not ok:
		failures.append(msg)

func _initialize() -> void:
	secs = float(_env("CHASE_SECS", "300"))
	cars = int(_env("CHASE_CARS", "40"))
	speed_kmh = float(_env("CHASE_SPEED", "105"))
	seed_value = int(_env("CHASE_SEED", "1"))
	OS.set_environment("NEON_POLICE", "0")
	OS.set_environment("NEON_NEAR_MISS_LOG", "")
	game = Harness.boot(self, cars, 300.0, seed_value, 300.0)

func _physics_process(delta: float) -> bool:
	if p == null:
		p = game.get("player")
		if p == null or not p.is_ready or Engine.get_physics_frames() < 60:
			p = null
			return false
		traffic = game.get("traffic")
		if traffic.cars.size() != cars:
			traffic.set_car_count(cars)
		bot = TestDriver.start(game, "weave", {"speed": speed_kmh, "seed": seed_value})
		Harness.launch_player(p, speed_kmh / 3.6 * 0.6)
		return false
	if cop == null:
		if Engine.get_physics_frames() < 180:
			return false
		var u := RoadFrame.unroll(p.global_position)
		var lane := clampi(RoadChunkBuilder.lane_at(u.x), 0, traffic.own_lanes - 1)
		cop = traffic.add_rival(KIND, TrafficManager.lane_centre(lane, false), u.z + START_BEHIND, p.current_speed(), NpcCarBuilder.sheet_paint(KIND))
		drv = FreeDriver.new()
		drv.target = p
		drv.offset_back = BACK
		drv.setup(cop)
		cop.free_driver = drv
		print("free_driver_chase: chaser top speed %.0f km/h, bot %.0f km/h, %d cars, %.0f s" % [drv.v_top * 3.6, speed_kmh, cars, secs])
		return false
	ticks += 1
	game_t += delta
	if drv.recycle_due:
		drv.recycle(cop)
	var d := cop.global_position.distance_to(p.global_position)
	dist_sum += d
	dist_min = minf(dist_min, d)
	dist_max = maxf(dist_max, d)
	if d < NEAR_M:
		near_ticks += 1
	if cop.detailed:
		sim_ticks += 1
		v_sum += cop.current_speed()
		if cop.global_transform.basis.y.y < FreeDriver.FLIP_UP:
			flip_ticks += 1
		if drv.blocked:
			blocked_ticks += 1
		if drv.wrong_way:
			wrong_way_ticks += 1
	if int(bot.get("car_contacts")) > bot_contacts_seen or int(bot.get("spins")) > bot_spins_seen:
		if not player_touching:
			bot_trouble_t = game_t
			bot_contacts_seen = int(bot.get("car_contacts"))
			bot_spins_seen = int(bot.get("spins"))
	# stuck: stopped while the target drives on
	if cop.lane_speed() < FreeDriver.STUCK_V and p.current_speed() > 5.0:
		stuck_run += delta
		stuck_max = maxf(stuck_max, stuck_run)
	else:
		stuck_run = 0.0
	# body overlaps with traffic (both in the sim), counted once per meeting
	for c in traffic.cars:
		if c == cop or c.benched or not c.detailed or not cop.detailed:
			touching.erase(c)
			continue
		var hit := Harness.overlaps(cop, c, cop.half_w + c.half_w, cop.half_l + c.half_l)
		if hit and not touching.has(c):
			touches += 1
			if touch_log.size() < 12:
				var l := cop.to_local(c.global_position)
				touch_log.append("t=%.0f s at %.0f km/h, other at (%.1f across, %.1f ahead) doing %.0f km/h, line change %s" % [game_t, cop.current_speed() * 3.6, l.x, -l.z, c.lane_speed() * 3.6, absf(drv.aim_x - drv.line_x) > 0.2])
		if hit:
			touching[c] = true
		else:
			touching.erase(c)
	var hit_p := cop.detailed and Harness.overlaps(cop, p, cop.half_w + 0.95, cop.half_l + 2.2)
	if hit_p and not player_touching:
		# running into a target that has just crashed or spun is not the driver's doing
		var crashed: bool = int(bot.get("car_contacts")) > bot_contacts_seen or int(bot.get("spins")) > bot_spins_seen or game_t - bot_trouble_t < 4.0
		var l := cop.to_local(p.global_position)
		touch_log.append("TARGET t=%.0f s, chaser %.0f km/h, target %.0f km/h at (%.1f across, %.1f ahead), target in trouble %s" % [game_t, cop.current_speed() * 3.6, p.current_speed() * 3.6, l.x, -l.z, crashed])
		if crashed:
			wreck_touches += 1
		else:
			player_touches += 1
	player_touching = hit_p
	if game_t >= secs:
		return _finish()
	return false

func _finish() -> bool:
	var n := maxi(ticks, 1)
	print("free_driver_chase: %.0f s; distance to the target mean %.0f m, min %.0f, max %.0f; within %.0f m %.0f%% of the time; in the full sim %.0f%%" % [game_t, dist_sum / n, dist_min, dist_max, NEAR_M, 100.0 * near_ticks / n, 100.0 * sim_ticks / n])
	print("free_driver_chase: flips %d ticks, longest stuck %.1f s, recycles %d, traffic touches %d, target touches %d (+%d into a target that had just crashed), line changes %d, refused %d, blocked %.0f%%, wrong way %.0f%%, mean speed %.0f km/h" % [flip_ticks, stuck_max, drv.recycles, touches, player_touches, wreck_touches, drv.line_changes, drv.refused, 100.0 * blocked_ticks / maxi(sim_ticks, 1), 100.0 * wrong_way_ticks / maxi(sim_ticks, 1), v_sum / maxi(sim_ticks, 1) * 3.6])
	print("free_driver_chase: cost %.1f us a drive tick (%d), %.1f us a plan (%d)" % [float(drv.drive_us) / maxi(drv.drive_runs, 1), drv.drive_runs, float(drv.plan_us) / maxi(drv.plan_runs, 1), drv.plan_runs])
	for l in touch_log:
		print("  touch: " + l)
	if bot != null:
		print("free_driver_chase: bot " + String(bot.call("summary")))
	_check(flip_ticks == 0, "the chaser was off its wheels for %d ticks" % flip_ticks)
	_check(stuck_max <= FreeDriver.STUCK_SECS + 0.5, "the chaser was stuck for %.1f s (max %.0f)" % [stuck_max, FreeDriver.STUCK_SECS])
	_check(touches <= MAX_TOUCHES, "the chaser touched traffic %d times (max %d)" % [touches, MAX_TOUCHES])
	_check(player_touches == 0, "the chaser ran into its target %d times (it is told to sit %.0f m back)" % [player_touches, BACK])
	_check(dist_min < 25.0, "the chaser never got within 25 m of its target (closest %.0f m)" % dist_min)
	_check(float(near_ticks) / n >= 0.5, "the chaser was within %.0f m only %.0f%% of the time" % [NEAR_M, 100.0 * near_ticks / n])
	for f in failures:
		printerr("FAIL: " + f)
	print("free_driver_chase: %s" % ("PASS" if failures.is_empty() else "FAIL (%d)" % failures.size()))
	quit(0 if failures.is_empty() else 1)
	return true
