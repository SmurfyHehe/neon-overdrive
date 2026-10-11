extends SceneTree

# Police P3 proof in the real game: city traffic keeps the city pace
# (75 / 65 / 55 / 50 km/h by lane), highway traffic the old one
# (115 / 100 / 85 / 70), and a car changes pace when it drives from one into
# the other. The bot drives lane 0 at that lane's flow from District 1 (city)
# through District 2 (city) into District 3 (highway), 1.6 km on.
#
# Checked every tick, for every traffic car that is not a rule breaker:
#   - its cruise target is its lane's speed for the area it is in (plus or
#     minus the per-car jitter), within a second of crossing the line;
#   - well inside a city (20 s on the city pace) it drives under 90 km/h: so
#     keeping up with city traffic is never over the 85 offence line by more
#     than a car's own jitter.
# And the run must have seen both: cars on the city pace and cars on the
# highway pace, and at least one car that changed pace on the road.
# Needs --fixed-fps 60:
#   <godot> --headless --fixed-fps 60 --path . -s res://tests/traffic/city_pace.gd

const Harness := preload("res://tests/traffic/traffic_harness.gd")
const RoadMap := preload("res://scripts/world/road_map.gd")
const RUN_SECS := 170.0
const SETTLE := 1.0        # s a car may lag the area it is in (the manager paces one car a tick)
const CITY_SLOW_SECS := 20.0
const CITY_MAX_KMH := 90.0

var failures: Array[String] = []
var game: Node
var player: PlayerCar
var traffic: TrafficManager
var t := 0
var game_t := 0.0
var want := 0.0
var city_cars := 0
var highway_cars := 0
var changed := 0
var fastest_city := 0.0
var last_city := {}      # car -> pace_city last tick
var wrong_since := {}    # car -> game time its pace first disagreed with its area
var city_since := {}     # car -> game time it went on the city pace
var player_areas := {}

func _check(ok: bool, msg: String) -> void:
	if not ok and failures.size() < 12 and not failures.has(msg):
		failures.append(msg)

func _initialize() -> void:
	OS.set_environment("NEON_POLICE", "0")
	OS.set_environment("NEON_CURVES", "0")
	OS.set_environment("NEON_HILLS", "0")
	game = Harness.boot(self, 16, 300.0, 7)

func _driver() -> Callable:
	var x := Harness.lane_x(0)
	return func(c: PlayerCar) -> void:
		var u := RoadFrame.unroll(c.global_position)
		var side_v := RoadFrame.dir_to_road(u.z, c.linear_velocity).x
		c.steering_input = TrafficCar.lane_steer(c, x - side_v * Harness.LAT_DAMP_T, -1.0, 2.5, Harness.PLAYER_UNDERSTEER_FF)
		c.handbrake_input = 0.0
		var v := c.current_speed()
		var gap := traffic.scan(u.z, -1.0, x - 1.0, x + 1.0, true, 0, TrafficManager.PLAYER_HALF_L, 300.0, false)
		var a := (want - v) * 2.0
		if gap < INF:
			a = minf(a, TrafficCar.follow_accel(v, want, gap, traffic.q_speed, 1.0))
		c.throttle_input = clampf(a, 0.0, 1.0) if a >= -0.3 else 0.0
		c.brake_input = clampf(-a / 9.0, 0.0, 1.0) if a < -0.3 else 0.0

func _physics_process(delta: float) -> bool:
	t += 1
	game_t += delta
	if t < 5:
		return false
	if player == null:
		player = game.get("player")
		traffic = game.get("traffic")
		_check(RoadMap.period > 0, "the game is not on a mapped road: no areas to pace by")
		if RoadMap.period <= 0:
			return _finish()
		Harness.move_player_to_lane(player, Harness.lane_x(0))
		want = traffic.lane_speed(0, false, true)
		Harness.launch_player(player, want)
		player.driver = _driver()
	var pz := RoadFrame.unroll(player.global_position).z
	want = traffic.lane_speed(0, false, traffic.city_at(pz, -1.0))
	player_areas[RoadMap.area_at(RoadFrame.s_at(pz))] = true
	for car in traffic.cars:
		if car.benched or car.pace_lane < 0 or car.rule_breaker or car.wrecked:
			last_city.erase(car)
			wrong_since.erase(car)
			city_since.erase(car)
			continue
		var z := RoadFrame.unroll(car.global_position).z if car.detailed else car.rail_z_now()
		var city := traffic.city_at(z, car.direction)
		if city != car.pace_city:
			if not wrong_since.has(car):
				wrong_since[car] = game_t
			_check(game_t - float(wrong_since[car]) <= SETTLE, "a car %s for %.1f s is still on the %s pace" % ["in the city" if city else "on the highway", game_t - float(wrong_since[car]), "city" if car.pace_city else "highway"])
		else:
			wrong_since.erase(car)
		var lane_v := traffic.lane_speed(car.pace_lane, car.pace_far, car.pace_city)
		_check(absf(car.target_speed - lane_v) <= TrafficManager.SPEED_JITTER + 0.01, "a car's cruise target is %.0f km/h, its lane's %s speed is %.0f" % [car.target_speed * 3.6, "city" if car.pace_city else "highway", lane_v * 3.6])
		if last_city.has(car) and bool(last_city[car]) != car.pace_city:
			changed += 1
		last_city[car] = car.pace_city
		if car.pace_city:
			city_cars += 1
			if not city_since.has(car):
				city_since[car] = game_t
			elif game_t - float(city_since[car]) >= CITY_SLOW_SECS:
				fastest_city = maxf(fastest_city, car.lane_speed() * 3.6)
		else:
			highway_cars += 1
			city_since.erase(car)
	if game_t >= RUN_SECS:
		return _finish()
	return false

func _finish() -> bool:
	print("city_pace: %.0f s; car-ticks on the city pace %d, highway pace %d; pace changes on the road %d; fastest settled city car %.0f km/h; player drove %s" % [game_t, city_cars, highway_cars, changed, fastest_city, player_areas.keys()])
	_check(city_cars > 0 and highway_cars > 0, "the run saw %d car-ticks on the city pace and %d on the highway pace: it needs both" % [city_cars, highway_cars])
	_check(changed >= 1, "no car changed pace on the road")
	_check(player_areas.has("city") and player_areas.has("highway"), "the bot only drove %s" % [player_areas.keys()])
	_check(fastest_city <= CITY_MAX_KMH, "a car settled in the city drove %.0f km/h (max %.0f)" % [fastest_city, CITY_MAX_KMH])
	for f in failures:
		printerr("FAIL: " + f)
	print("city_pace: %s" % ("PASS" if failures.is_empty() else "FAIL (%d)" % failures.size()))
	quit(0 if failures.is_empty() else 1)
	return true
