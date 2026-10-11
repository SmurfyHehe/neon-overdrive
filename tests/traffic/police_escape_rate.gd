extends SceneTree

# Police P5 measurement (spec section 11: "escape rate at heat 2 with the
# weave bot"): the real game, 40 traffic cars, the weave bot fleeing with the
# patrol car 40 m behind it and heat set to 2. Each trial ends when the bot is
# busted, when heat has cooled to nothing (escaped), or after ESCAPE_SECS of
# game time (unresolved: still being chased).
#
# It measures; it only fails when something is broken outright: a trial with
# no chase at all, a cop off its wheels, or a cop stuck in view for over 5 s.
# The 75-85% target needs the chase roles of the later steps (a lone tailing
# cop cannot stop a bot that never stops), so the rate is printed, not judged.
#
# Env: ESCAPE_TRIALS (3), ESCAPE_SECS (150), ESCAPE_SPEED (km/h, 180),
# ESCAPE_SEED (1), ESCAPE_CARS (40). About 2 min of wall clock a trial:
#   <godot> --headless --fixed-fps 60 --path . -s res://tests/traffic/police_escape_rate.gd

const Harness := preload("res://tests/traffic/traffic_harness.gd")
const TestDriver := preload("res://scripts/core/test_driver.gd")
const S := CopBrain.State

var failures: Array[String] = []
var game: Node
var p: PlayerCar
var police: PolicePatrol
var heat: PoliceHeat
var traffic: TrafficManager
var bot: RefCounted
var trials := 3
var secs := 150.0
var speed_kmh := 180.0
var seed_value := 1
var cars := 40
var trial := 0
var phase := 0          # 0 waiting for a cop, 1 chasing, 2 settling
var t := 0.0
var results: Array[String] = []
var state_secs := {}
var called_off := 0
var turns := 0
var recycles := 0
var flip_ticks := 0
var stuck_run := 0.0
var stuck_max := 0.0
var chase_seen := false
var busted_now := false
var kmh_sum := 0.0
var kmh_n := 0
var dist_sum := 0.0
var danger_max := 0.0
var brain_seen: CopBrain

func _env(name: String, fallback: String) -> String:
	var v := OS.get_environment(name)
	return v if v != "" else fallback

func _check(ok: bool, msg: String) -> void:
	if not ok:
		failures.append(msg)
		printerr("FAIL: " + msg)

func _initialize() -> void:
	trials = int(_env("ESCAPE_TRIALS", "3"))
	secs = float(_env("ESCAPE_SECS", "150"))
	speed_kmh = float(_env("ESCAPE_SPEED", "180"))
	seed_value = int(_env("ESCAPE_SEED", "1"))
	cars = int(_env("ESCAPE_CARS", "40"))
	OS.set_environment("NEON_POLICE", "1")
	OS.set_environment("NEON_NEAR_MISS_LOG", "")
	game = Harness.boot(self, cars, 300.0, seed_value, 300.0)

func _physics_process(delta: float) -> bool:
	if p == null:
		p = game.get("player")
		if p == null or not p.is_ready or Engine.get_physics_frames() < 60:
			p = null
			return false
		police = game.get("police")
		heat = game.get("police_heat")
		traffic = game.get("traffic")
		_check(police != null, "no police in the game with NEON_POLICE=1")
		if police == null:
			return _finish()
		if traffic.cars.size() < cars:
			traffic.set_car_count(cars)
		(game.get("night_clock") as NightClock).night = 2
		police.oncoming_next = false
		police.busted.connect(func(_c: Node3D) -> void: busted_now = true)
		p.set_headlights(true)
		bot = TestDriver.start(game, "weave", {"speed": speed_kmh, "seed": seed_value})
		Harness.launch_player(p, 25.0)
		return false
	t += delta
	match phase:
		0:
			police.oncoming_next = false
			if police.car == null or t < 4.0:
				if t > 90.0:
					_check(false, "trial %d: no patrol car for 90 s" % (trial + 1))
					return _finish()
				return false
			# the cop 40 m behind the bot, in its lane, at its speed; heat 2
			var u := RoadFrame.unroll(p.global_position)
			var lane := clampi(RoadChunkBuilder.lane_at(u.x), 0, traffic.own_lanes - 1)
			var x := TrafficManager.lane_centre(lane, false)
			var c := police.car
			if traffic._slot_check(c, x, u.z + 40.0, -1.0, maxf(p.current_speed(), 10.0)).is_empty():
				return false   # a car is there: try again next tick
			c.place(x, -1.0, u.z + 40.0, c.rest_y, maxf(p.current_speed(), 10.0))
			traffic._put(c)
			heat.reset()
			heat._raise_to(2.0)
			if police.brain != brain_seen:
				brain_seen = police.brain
			busted_now = false
			chase_seen = false
			phase = 1
			t = 0.0
		1:
			var brain := police.brain
			if police.car == null or brain == null:
				results.append("lost the cop")
				_next()
				return false
			if brain.in_chase():
				chase_seen = true
			state_secs[brain.state] = float(state_secs.get(brain.state, 0.0)) + delta
			kmh_sum += p.current_speed() * 3.6
			kmh_n += 1
			dist_sum += police.car.global_position.distance_to(p.global_position)
			danger_max = maxf(danger_max, brain.danger)
			var c := police.car
			if c.detailed and c.global_transform.basis.y.y < FreeDriver.FLIP_UP:
				flip_ticks += 1
			if brain.in_chase() and c.lane_speed() < FreeDriver.STUCK_V and p.current_speed() > 5.0 and traffic.in_view(c.global_position):
				stuck_run += delta
				stuck_max = maxf(stuck_max, stuck_run)
			else:
				stuck_run = 0.0
			var out := ""
			if busted_now:
				out = "busted"
			elif heat.level == PoliceHeat.NONE:
				out = "escaped"
			elif t >= secs:
				out = "unresolved"
			if out != "":
				_check(chase_seen, "trial %d: heat 2 with a cop 40 m behind and no chase (state %s)" % [trial + 1, brain.state_name()])
				called_off += brain.called_off
				turns += brain.turns
				if brain.driver != null:
					recycles += brain.driver.recycles
				results.append("%s after %.0f s (cop: %s)" % [out, t, brain.state_name()])
				_next()
		2:
			if t > 5.0:
				phase = 0
				t = 0.0
	return false

func _next() -> void:
	trial += 1
	heat.reset()
	# every trial starts with fresh cops: none left in place from the last one
	while not police.units.is_empty():
		police.drop()
	police.set("_wait", 2.0)
	phase = 2
	t = 0.0
	if trial >= trials:
		_finish()

func _finish() -> bool:
	var esc := 0
	var bust := 0
	var open := 0
	for r in results:
		if r.begins_with("escaped"):
			esc += 1
		elif r.begins_with("busted"):
			bust += 1
		elif r.begins_with("unresolved"):
			open += 1
	for i in results.size():
		print("police_escape_rate: trial %d: %s" % [i + 1, results[i]])
	var parts: Array[String] = []
	for k in state_secs:
		parts.append("%s %.0f s" % [CopBrain.NAMES[k], state_secs[k]])
	print("police_escape_rate: %d trials at heat 2, bot asked for %.0f km/h (drove %.0f on average), %d cars: escaped %d, busted %d, unresolved %d" % [results.size(), speed_kmh, kmh_sum / maxi(kmh_n, 1), cars, esc, bust, open])
	print("police_escape_rate: cop time by state: %s; called off %d, turned round %d, recycled %d, mean distance %.0f m, highest danger %.2f (line %.1f), flips %d ticks, longest stuck in view %.1f s" % [", ".join(parts), called_off, turns, recycles, dist_sum / maxi(kmh_n, 1), danger_max, PoliceRules.DANGER_LINE, flip_ticks, stuck_max])
	if bot != null:
		print("police_escape_rate: bot " + String(bot.call("summary")))
	_check(flip_ticks == 0, "a cop was off its wheels for %d ticks" % flip_ticks)
	_check(stuck_max <= FreeDriver.STUCK_SECS + 0.5, "a cop was stuck in view for %.1f s" % stuck_max)
	print("police_escape_rate: %s" % ("PASS" if failures.is_empty() else "FAIL (%d)" % failures.size()))
	quit(0 if failures.is_empty() else 1)
	return true
