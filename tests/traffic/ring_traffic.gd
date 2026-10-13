extends SceneTree

# Traffic uses the ramps and the ring (#630; Roy 17:27Z: "the NPCs dont even
# use the roundabout"). Before this, a 150 s probe past the ring sites counted
# 0 traffic cars on a slip lane, a ramp or a ring (driving-ai-measured
# section 12).
#
# Boots the real Game.tscn on the curved, hilly loop with 40 cars, then:
# A. 150 s past the ring sites at 130 km/h in lane 1 (a bot that flashes and
#    brakes behind slower cars, like a player), the game's own shares: how
#    many cars use the slip lanes, ramps and rings.
# B. 90 s at 100 km/h with every outside-lane car taking the exit and the
#    rings seeded to the cap (a busy ring): the give-way lines get used.
# C. The player drives up onto a busy ring, twice and a half round it and
#    down the far side (the line tests/world/ring_drive.gd drives), braking
#    for what is in front of it but giving way to nobody.
# Every tick it sorts every traffic car within SITE_REACH m of a ring's
# centre: main lanes, slip lane, ramp or ring (RoadRamps.place_of).
#
# Asserts (exit code 1 on failure; thresholds are measured, see the numbers
# printed at the end, and never loosened):
# - A: at least MIN_RING_CARS different cars seen on a ring, MIN_RAMP_CARS on
#   a ramp, traffic off the main lanes at MIN_SITE_SHARE of the sites passed,
#   MIN_DONE routes finished (back on the main road);
# - B: cars held at a give-way line (slowed or stopped for the ring) at least
#   MIN_GIVE_WAYS times;
# - all phases: no two cars touching at a site where one of them is a
#   visitor, none touching the player; no visitor wrecked; nobody waits at a
#   give-way line over MAX_WAIT_S; no visitor spawned in view or shown inside
#   250 m in sight; the visitors' own code under MAX_COST_US per physics tick
#   on average in A; no engine or script errors.
#
# Run (headless):
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --fixed-fps 60 --path . -s res://tests/traffic/ring_traffic.gd

const Harness := preload("res://tests/traffic/traffic_harness.gd")
const RoadMap := preload("res://scripts/world/road_map.gd")
const RoadRamps := preload("res://scripts/world/road_ramps.gd")
const RingVisitors := preload("res://scripts/traffic/ring_visitors.gd")
const SaveDirector := preload("res://scripts/save/save_director.gd")

const L := 50.0
const CARS := 40
const A_S := 150.0
const A_SPEED := 130.0 / 3.6
const B_S := 90.0
const B_SPEED := 30.0 / 3.6
const C_TIMEOUT_S := 200.0
const SITE_REACH := 320.0
const LANE_X := 11.6
const SLIP_X := RoadRamps.X_LANE + RoadRamps.HALF
const RAMP_SPEED := 13.0
const RING_SPEED := 10.0
## Thresholds (measured 2026-10-13 in the cloud, see the PR).
const MIN_RING_CARS := 4
const MIN_RAMP_CARS := 6
const MIN_SITE_SHARE := 0.6
const MIN_DONE := 3
const MIN_GIVE_WAYS := 1
const MAX_WAIT_S := 10.0
const MAX_COST_US := 60.0
## Touching: centres closer than this across and along the first car (the
## cars are about 1.8 x 4.4 m).
const TOUCH_X := 1.7
const TOUCH_Z := 4.0

var logger := Harness.ErrorCounter.new()
var game: Node
var tr: TrafficManager
var player: PlayerCar
var ticks := 0
var phase := ""
var phase_t0 := -1
var fails: Array[String] = []
var on_part := {"slip": {}, "ramp": {}, "ring": {}}
var samples := {"main": 0, "slip": 0, "ramp": 0, "ring": 0}
var sites_passed := {}     # site s -> true once the player was within 300 m of it
var sites_busy := {}       # site s -> true once a car was off the main lanes there while the player was near
var touches := {"A": 0, "B": 0, "C": 0}
var player_touches := 0
var touch_log: Array[String] = []
var _touching := {}        # pair key -> true while touching (rising edges are counted)
var wrecked := {}
var popins := 0
var max_wait := 0.0
var give_ways := 0
var _waiting := {}         # car id -> true while stopped at a give-way line
var give_way_holds := 0
var b_max_visitors := 0
var _held := {}            # car id -> true while held at a give-way line
var cost_a := 0.0
var phys_sum := 0.0
var phys_n := 0
var done_a := 0
var stats_a := ""
var path: Array[Vector3] = []   # (x, w past the site's centre, speed)
var path_i := 0
var site_s := 0.0
var c_ring_ticks := 0
var c_near_ticks := 0          # ticks with a visitor within 30 m of the player on the ring
var _cost0 := 0
var _ticks0 := 0

func _initialize() -> void:
	OS.add_logger(logger)
	OS.set_environment("NEON_CURVES", "0.5")
	OS.set_environment("NEON_HILLS", "0.5")
	OS.set_environment("NEON_ROAD", "")
	OS.set_environment("NEON_ACT", "")
	OS.set_environment("NEON_ROAD_SEED", "4242")
	OS.set_environment("NEON_POLICE", "0")
	game = Harness.boot(self, CARS, 300.0, 7)

func _fail(msg: String) -> void:
	fails.append(msg)
	print("FAIL ", msg)

func _on_event(kind: String, car: TrafficCar, pos: Vector3) -> void:
	if not car.visiting or (kind != "spawn" and kind != "show"):
		return
	var d := absf(RoadFrame.unroll(pos).z - tr._z[0])
	if (kind == "spawn" or d < 250.0) and tr.in_view(pos):
		popins += 1
		print("ring_traffic: a visitor %s in view %.0f m away" % [kind, d])

func _start(p: String) -> void:
	phase = p
	phase_t0 = ticks
	_cost0 = RingVisitors.cost_usec
	_ticks0 = ticks

func _physics_process(_delta: float) -> bool:
	if game == null or not game.is_inside_tree():
		return false
	ticks += 1
	if ticks < 3:
		return false
	var hz := Engine.physics_ticks_per_second
	if phase == "":
		tr = game.get("traffic")
		player = game.get("player")
		if tr == null or player == null or not RoadMap.is_loop() or tr.cars.size() < CARS:
			return false
		tr.event_hook = _on_event
		Harness.move_player_to_lane(player, Harness.lane_x(1))
		Harness.launch_player(player, A_SPEED)
		player.driver = Harness.flash_brake_driver(tr, Harness.lane_x(1), A_SPEED)
		_start("A")
		return false
	if phase != "C":
		phys_sum += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
		phys_n += 1
	_look()
	var t := ticks - phase_t0
	match phase:
		"A":
			if t >= int(A_S * hz):
				cost_a = float(RingVisitors.cost_usec - _cost0) / float(maxi(ticks - _ticks0, 1))
				for c in tr.cars:
					done_a += c.visits_done
				stats_a = "different cars on a slip lane %d, ramp %d, ring %d; %d sites passed, %d with traffic off the main lanes; routes started from the outside lane %d, placed on a ring ahead %d, finished %d" % [
					(on_part.slip as Dictionary).size(), (on_part.ramp as Dictionary).size(), (on_part.ring as Dictionary).size(),
					sites_passed.size(), sites_busy.size(), tr.visit_starts, tr.ring_spawn_count, done_a]
				_check_a()
				tr.visit_share = 1.0
				tr.ring_spawn_share = 1.0
				tr.ring_seed_cap = RingVisitors.SITE_CAP
				player.driver = Harness.flash_brake_driver(tr, Harness.lane_x(1), B_SPEED)
				_start("B")
		"B":
			b_max_visitors = maxi(b_max_visitors, tr.visitors.size())
			if t >= int(B_S * hz):
				_begin_c()
				_start("C")
		"C":
			if path_i >= path.size() - 3 or t >= int(C_TIMEOUT_S * hz):
				if path_i < path.size() - 3:
					_fail("the player did not get round the ring in %.0f s (%d of %d path points)" % [C_TIMEOUT_S, path_i, path.size()])
				_finish()
				return true
			var pu := RoadFrame.unroll(player.global_position)
			var place := RoadRamps.place_of(pu, RoadFrame.s_at(pu.z))
			if not place.is_empty() and String(place.part) == "ring":
				c_ring_ticks += 1
				for c in tr.visitors:
					if c.global_position.distance_to(player.global_position) < 30.0:
						c_near_ticks += 1
						break
	return false

func _check_a() -> void:
	var ring_cars := (on_part.ring as Dictionary).size()
	var ramp_cars := (on_part.ramp as Dictionary).size()
	var share := float(sites_busy.size()) / float(maxi(sites_passed.size(), 1))
	if ring_cars < MIN_RING_CARS:
		_fail("A: only %d cars seen on a ring (need %d)" % [ring_cars, MIN_RING_CARS])
	if ramp_cars < MIN_RAMP_CARS:
		_fail("A: only %d cars seen on a ramp (need %d)" % [ramp_cars, MIN_RAMP_CARS])
	if share < MIN_SITE_SHARE:
		_fail("A: traffic off the main lanes at %d of %d sites passed (need %.0f%%)" % [sites_busy.size(), sites_passed.size(), MIN_SITE_SHARE * 100.0])
	if done_a < MIN_DONE:
		_fail("A: only %d visitors finished their route (need %d)" % [done_a, MIN_DONE])
	if cost_a > MAX_COST_US:
		_fail("A: the visitors' code cost %.1f us a tick (max %.0f)" % [cost_a, MAX_COST_US])

# ---------- phase C: the player on the ring ----------

func _z_of(w: float) -> float:
	return float(RoadFrame.origin_index) * L - (site_s + w)

func _begin_c() -> void:
	var ps := RoadFrame.s_at(RoadFrame.unroll(player.global_position).z)
	# a site well ahead, so the ring is seeded before the player gets there
	site_s = float(RoadMap.ring_near(ps + 2400.0).s)
	path = []
	var w := -900.0
	while w < -260.0:
		path.append(Vector3(LANE_X, w, 22.0))
		w += 2.0
	while w < -RoadRamps.V_GORE - 1.0:
		path.append(Vector3(lerpf(LANE_X, SLIP_X, smoothstep(-250.0, -205.0, w)), w, RAMP_SPEED))
		w += 2.0
	w = -RoadRamps.V_GORE
	while w < 0.0:
		path.append(Vector3(RoadRamps.x_at(-w), w, RING_SPEED if w > -40.0 else RAMP_SPEED))
		w += 2.0
	for i in range(0, 240):
		var a := TAU * float(i) / 96.0
		path.append(Vector3(RoadRamps.X_TOP * cos(a), RoadRamps.X_TOP * sin(a), RING_SPEED))
	var v := 0.0
	while v <= RoadRamps.V_GORE:
		path.append(Vector3(-RoadRamps.x_at(v), -v, RING_SPEED if v < 30.0 else RAMP_SPEED))
		v += 2.0
	while v < 330.0:
		path.append(Vector3(-lerpf(SLIP_X, LANE_X, smoothstep(205.0, 250.0, v)), -v, RAMP_SPEED))
		v += 2.0
	path_i = 0
	var t := RoadFrame.pose(path[0].x, 0.45, _z_of(path[0].y), 0.0)
	game.saver.restore_car(player, {"xform": SaveDirector.xform_to_array(t), "lin_vel": [0.0, 0.0, 0.0], "ang_vel": [0.0, 0.0, 0.0], "gear": 1})
	game.call("_update_chunk_pool", RoadFrame.unroll(player.global_position).z)
	game.call("flush_rebuilds")
	Harness.launch_player(player, 20.0)
	player.driver = _path_driver

## ring_drive's path follower, plus braking for anything in front of it.
func _path_driver(c: Vehicle) -> void:
	if path_i >= path.size() - 1:
		c.throttle_input = 0.0
		c.brake_input = 1.0
		return
	var u := RoadFrame.unroll(c.global_position)
	var best := INF
	for i in range(path_i, mini(path_i + 12, path.size())):
		var d := Vector2(path[i].x - u.x, _z_of(path[i].y) - u.z).length()
		if d < best:
			best = d
			path_i = i
	var speed := c.linear_velocity.length()
	var look := clampf(speed * 0.6, 4.0, 9.0)
	var j := path_i
	var run := 0.0
	while j < path.size() - 1 and run < look:
		run += Vector2(path[j + 1].x - path[j].x, path[j + 1].y - path[j].y).length()
		j += 1
	var target := RoadFrame.roll(Vector3(path[j].x, 0.0, _z_of(path[j].y)))
	var fwd := -c.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var right := fwd.cross(Vector3.UP)
	var to := target - c.global_position
	var alpha := atan2(to.dot(right), to.dot(fwd))
	var dist := maxf(Vector2(to.dot(right), to.dot(fwd)).length(), 0.5)
	var want := clampf(atan(2.6 * 2.0 * sin(alpha) / dist) / c.max_steering_angle, -1.0, 1.0)
	c.steering_input = -signf(want) * pow(absf(want), 1.0 / maxf(c.steering_exponent, 0.1))
	var goal: float = path[path_i].z
	# whatever is in front: follow it, never closer than 5 m
	for car in tr.cars:
		var l := c.to_local(car.global_position)
		if l.z < -1.0 and l.z > -(6.0 + speed * 1.5 + 4.4) and absf(l.x) < 1.9 and absf(l.y) < 2.0:
			var gap := -l.z - 4.4
			goal = minf(goal, maxf(car.lane_speed(), 0.0) + 0.5 * (gap - 5.0))
	goal = maxf(goal, 0.0)
	c.throttle_input = clampf((goal - speed) * 0.5, 0.0, 1.0)
	c.brake_input = clampf((speed - goal - 0.5) * 0.4, 0.0, 1.0)
	if c.current_gear < 1:
		c.current_gear = 1

# ---------- every tick ----------

func _look() -> void:
	var pu := RoadFrame.unroll(player.global_position)
	var ps := RoadFrame.s_at(pu.z)
	var pnear := RoadMap.ring_near(ps)
	if phase == "A" and absf(float(pnear.s) - ps) < 300.0:
		sites_passed[float(pnear.s)] = true
	var near_cars: Array[TrafficCar] = []
	for car in tr.cars:
		if car.benched or not car.shown:
			continue
		if car.visiting:
			max_wait = maxf(max_wait, car.visit_wait_max)
			if car.wrecked:
				wrecked[car.get_instance_id()] = true
			var id := car.get_instance_id()
			if car.signal_held and not _held.has(id):
				_held[id] = true
				if phase == "B":
					give_way_holds += 1
			elif not car.signal_held:
				_held.erase(id)
			if car.visit_wait > 0.0 and not _waiting.has(id):
				_waiting[id] = true
				if phase == "B":
					give_ways += 1
			elif car.visit_wait == 0.0:
				_waiting.erase(id)
		var u := RoadFrame.unroll(car.global_position)
		var s := RoadFrame.s_at(u.z)
		var site := RoadMap.ring_near(s)
		var w := s - float(site.s)
		if absf(w) > SITE_REACH:
			continue
		near_cars.append(car)
		if phase != "A":
			continue
		var place := RoadRamps.place_of(u, s)
		var part := "main"
		if not place.is_empty():
			part = "ring" if String(place.part) == "ring" else "ramp"
		elif absf(u.x) > RoadRamps.X_LANE + 0.4 and absf(u.y) < 1.0:
			part = "slip"
		samples[part] += 1
		if part != "main":
			(on_part[part] as Dictionary)[car.get_instance_id()] = true
			if absf(float(site.s) - ps) < 300.0:
				sites_busy[float(site.s)] = true
	# touching: every pair where at least one is a visitor, and the player
	var bodies: Array[Node3D] = []
	for c in near_cars:
		bodies.append(c)
	bodies.append(player)
	for i in bodies.size():
		var a := bodies[i]
		var a_vis: bool = a is TrafficCar and (a as TrafficCar).visiting
		for j in range(i + 1, bodies.size()):
			var b := bodies[j]
			var b_vis: bool = b is TrafficCar and (b as TrafficCar).visiting
			if not (a_vis or b_vis):
				continue
			var k := _key(a, b)
			if a.global_position.distance_squared_to(b.global_position) > 36.0:
				_touching.erase(k)
				continue
			var t := Harness.overlaps(a, b, TOUCH_X, TOUCH_Z) or Harness.overlaps(b, a, TOUCH_X, TOUCH_Z)
			if t and not _touching.has(k):
				touches[phase] += 1
				if b is PlayerCar:
					player_touches += 1
				if touch_log.size() < 10:
					touch_log.append("%s: %s / %s" % [phase, _describe(a), _describe(b)])
			if t:
				_touching[k] = true
			else:
				_touching.erase(k)

func _key(a: Node3D, b: Node3D) -> String:
	return "%d-%d" % [mini(a.get_instance_id(), b.get_instance_id()), maxi(a.get_instance_id(), b.get_instance_id())]

func _describe(n: Node3D) -> String:
	var u := RoadFrame.unroll(n.global_position)
	var s := RoadFrame.s_at(u.z)
	var w := s - float(RoadMap.ring_near(s).s)
	if n is PlayerCar:
		return "player at x %.1f w %.1f y %.1f" % [u.x, w, u.y]
	var c := n as TrafficCar
	var what := "lane car"
	if c.visiting:
		what = "visitor (route %d side %d, d %.0f, %s)" % [int(c.visit.kind), int(c.visit.side), c.visit_d, "sim" if c.detailed else "rails"]
	return "%s at x %.1f w %.1f y %.1f %.1f m/s" % [what, u.x, w, u.y, c.lane_speed()]

func _finish() -> void:
	var done := 0
	for c in tr.cars:
		done += c.visits_done
	print("ring_traffic: A (%.0f s at %.0f km/h, %d cars): %s" % [A_S, A_SPEED * 3.6, CARS, stats_a])
	print("ring_traffic: A samples main %d, slip %d, ramp %d, ring %d" % [samples.main, samples.slip, samples.ramp, samples.ring])
	print("ring_traffic: A visitors' own code %.1f us per physics tick; whole physics step %.2f ms a tick on average over A and B (report only)" % [cost_a, phys_sum / float(maxi(phys_n, 1)) * 1000.0])
	print("ring_traffic: B (busy rings): most visitors at once %d, held at a give-way line %d times, %d of them to a stop; all phases: routes started %d, placed on a ring %d, finished %d" % [b_max_visitors, give_way_holds, give_ways, tr.visit_starts, tr.ring_spawn_count, done])
	print("ring_traffic: C: player on the ring %.0f s, %.0f s of it with a visitor within 30 m" % [float(c_ring_ticks) / 60.0, float(c_near_ticks) / 60.0])
	print("ring_traffic: touching A %d, B %d, C %d (with the player %d), wrecked visitors %d, longest give-way wait %.1f s, visitors in view %d" % [touches.A, touches.B, touches.C, player_touches, wrecked.size(), max_wait, popins])
	for t in touch_log:
		print("  touch: ", t)
	if give_way_holds < MIN_GIVE_WAYS:
		_fail("B: cars held at a give-way line only %d times on a busy ring (need %d)" % [give_way_holds, MIN_GIVE_WAYS])
	var all_touches: int = touches.A + touches.B + touches.C
	if all_touches > 0:
		_fail("%d times two cars touched at a ring site (%d with the player)" % [all_touches, player_touches])
	if not wrecked.is_empty():
		_fail("%d visitors wrecked" % wrecked.size())
	if max_wait > MAX_WAIT_S:
		_fail("a car waited %.1f s at a give-way line (max %.0f)" % [max_wait, MAX_WAIT_S])
	if popins > 0:
		_fail("%d visitors appeared in view" % popins)
	if not logger.errors.is_empty():
		for e in logger.errors.slice(0, 5):
			print("  error: ", e)
		_fail("%d engine or script errors" % logger.errors.size())
	print("ring_traffic: %s" % ("PASS" if fails.is_empty() else "FAIL (%d)" % fails.size()))
	quit(1 if not fails.is_empty() else 0)
