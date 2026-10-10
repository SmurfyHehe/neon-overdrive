extends SceneTree

# The map, loop 1 (scripts/world/road_map.gd, 2026-10-10): the road is a closed
# loop of 8 districts, driven in both directions, and the save records which
# road the car is on.
#
# Without a game:
# - the loop's shape repeats every lap in both directions (bends, heading,
#   grade, height), every join is smooth, the lap closing included, and the
#   closing chunks stay inside the road's limits
# - 8 districts, the same ones a lap on and a lap back; a crossing just inside
#   each end of each city area and none on the highway stretches
# In the game (curved, hilly, with traffic):
# - turning round and driving back the other way, past where the road used to
#   begin: road under the car all the way, the chunk pool the same both sides,
#   and traffic turns with the player (cars ahead in its lanes going its way,
#   oncoming ones on the other side, none placed in view)
# - a whole lap on, the same buildings stand in the same places
# - the save names the road, the place on the lap and the heading; a save from
#   laps later resumes in the same spot; a save with no road id, or one this
#   build does not know, starts at the top of the loop and keeps the clock
#
# Exit code 1 on failure. Run (headless):
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --fixed-fps 60 --path . -s res://tests/world/loop_road.gd

const RoadMap := preload("res://scripts/world/road_map.gd")
const Districts := preload("res://scripts/world/districts.gd")
const SaveStore := preload("res://scripts/save/save_store.gd")
const SaveDirector := preload("res://scripts/save/save_director.gd")

const L := 50.0

var game: Node
var phase := 0
var ticks := 0
var fails: Array[String] = []
var sigs := {}
var lap_from := 0
var z_turn := 0.0
var saved := {}

func _fail(msg: String) -> void:
	fails.append(msg)
	print("FAIL ", msg)

func _initialize() -> void:
	_shape()
	_districts()
	OS.set_environment("NEON_CURVES", "0.5")
	OS.set_environment("NEON_HILLS", "0.5")
	OS.set_environment("NEON_TRAFFIC", "14")
	OS.set_environment("NEON_ROAD", "")
	OS.set_environment("NEON_ROAD_SEED", "")
	OS.set_environment("NEON_CITY_LIGHTS", "1")
	OS.set_environment("NEON_LAYOUT", "0")
	SaveStore.root = "user://test_loop_road"
	SaveStore.slot = 0
	SaveStore.chase_active = false
	SaveDirector.enabled = true
	SaveStore.select_slot(1)
	SaveStore.clear_run()
	SaveStore.load_meta()
	_boot()

func _boot() -> void:
	if game != null:
		root.remove_child(game)
		game.free()
	game = (load("res://Game.tscn") as PackedScene).instantiate()
	root.add_child.call_deferred(game)
	ticks = 0

# ---------- without a game ----------

func _shape() -> void:
	RoadMap.use("loop_1")
	var n := RoadMap.period
	if n != 128 or RoadMap.district_count() != 8:
		_fail("loop_1 is %d chunks in %d districts, expected 128 in 8" % [n, RoadMap.district_count()])
	var worst_join := 0.0
	for road_seed in [1, 2, 3, 777, RoadMap.seed_of("loop_1")]:
		var a := RoadAlignment.new(road_seed, 0.8, 0.8, 0.0, n)
		for i in range(-n - 3, 2 * n + 3):
			if a.curvature(i) != a.curvature(i + n) or a.vcurve(i) != a.vcurve(i + n) \
					or a.start_heading(i) != a.start_heading(i + n) or a.start_grade(i) != a.start_grade(i + n) \
					or a.start_height(i) != a.start_height(i + n):
				_fail("seed %d: chunk %d and chunk %d differ" % [road_seed, i, i + n])
				break
			# The join to the next chunk: where this arc ends is where that one starts.
			var k := a.curvature(i)
			var e := RoadAlignment.arc_point(k, L).rotated(Vector3.UP, a.start_heading(i))
			var gap := Vector2(a.start_x(i) + e.x - a.start_x(i + 1), a.start_z(i) + e.z - a.start_z(i + 1)).length()
			var turn := absf(a.start_heading(i) + k * L - a.start_heading(i + 1))
			var step := absf(a.height_at(i, L) - a.start_height(i + 1))
			var kink := absf(a.grade_at(i, L) - a.start_grade(i + 1))
			worst_join = maxf(worst_join, maxf(maxf(gap, turn), maxf(step, kink)))
			if gap > 1e-6 or turn > 1e-9 or step > 1e-6 or kink > 1e-9:
				_fail("seed %d: join after chunk %d is off by %.2e m, %.2e rad, %.2e m high, %.2e grade" % [road_seed, i, gap, turn, step, kink])
				break
			if absf(k) > 1.0 / RoadAlignment.MIN_RADIUS + 1e-12 or absf(a.start_heading(i)) > RoadAlignment.MAX_HEADING + 1e-9:
				_fail("seed %d: chunk %d bends past the limits (radius %.0f m, heading %.1f deg)" % [road_seed, i, 1.0 / absf(k), rad_to_deg(a.start_heading(i))])
				break
			# The lap's tilt may add a little to the steepest grade, never much.
			if absf(a.start_grade(i)) > RoadAlignment.MAX_GRADE + 0.01 or a.vcurve(i) < -1.0 / RoadAlignment.CREST_MIN_RADIUS - 1e-12 \
					or a.vcurve(i) > 1.0 / RoadAlignment.SAG_MIN_RADIUS + 1e-12:
				_fail("seed %d: chunk %d is steeper or sharper than the limits (grade %.3f, vcurve %.5f)" % [road_seed, i, a.start_grade(i), a.vcurve(i)])
				break
		# Each lap sits one lap further down the world: it does not come back on itself.
		if a.start_z(n) > -float(n) * L * 0.8:
			_fail("seed %d: a lap only covers %.0f m of ground" % [road_seed, -a.start_z(n)])
	# An endless road is untouched by all this.
	var plain := RoadAlignment.new(777, 0.8, 0.8)
	if plain.curvature(-1) != 0.0 or plain.start_z(-2) != 100.0:
		_fail("endless road: chunks before 0 are no longer straight")
	print("shape: %d chunks a lap (%.1f km), worst join %.9f" % [n, RoadMap.length() / 1000.0, worst_join])

func _districts() -> void:
	RoadMap.use("loop_1")
	var n := RoadMap.period
	var seen := {}
	for i in n:
		var d := RoadMap.district_of(i)
		seen[d] = true
		if Districts.name_at(i) != Districts.name_at(i + n) or Districts.name_at(i) != Districts.name_at(i - n):
			_fail("district at chunk %d changes from lap to lap" % i)
			break
		if Districts.name_at(i) != String(RoadMap.district_info(d).kind):
			_fail("chunk %d is %s, the map says %s" % [i, Districts.name_at(i), RoadMap.district_info(d).kind])
			break
	if seen.size() != 8:
		_fail("%d districts on the loop, expected 8" % seen.size())
	# Blending into the next district happens at the lap's end too (8 -> 1).
	if Districts.name_for_building(n - 1, 0.0) != Districts.name_at(0):
		_fail("the last chunk of the lap does not blend into district 1")
	# Crossings: one just inside each end of each city area, in city chunks only.
	var js := RoadMap.junctions()
	var city_edges := 0
	for d in 8:
		if RoadMap.district_info(d).area == "city" and RoadMap.district_info(d + 1).area != "city":
			city_edges += 1
		if RoadMap.district_info(d).area != "city" and RoadMap.district_info(d + 1).area == "city":
			city_edges += 1
	if js.size() != city_edges or js.size() == 0:
		_fail("%d crossings for %d city edges" % [js.size(), city_edges])
	for s in js:
		if RoadMap.district_info(RoadMap.district_of(floori(s / L))).area != "city":
			_fail("crossing at %.0f m is not in a city area" % s)
	Junction.enabled = true
	var touched := 0
	for i in n:
		if Junction.touches(i) != Junction.touches(i + n) or Junction.touches(i) != Junction.touches(i - 3 * n):
			_fail("crossing at chunk %d is not there every lap" % i)
		if Junction.touches(i):
			touched += 1
			if RoadMap.district_info(RoadMap.district_of(i)).area != "city":
				_fail("chunk %d on a highway stretch has a crossing" % i)
	if touched < js.size():
		_fail("only %d chunks have a crossing, for %d crossings" % [touched, js.size()])
	Junction.enabled = false
	print("districts: 8, crossings at %s m" % [js])
	RoadMap.use("")

# ---------- in the game ----------

func _pool_span() -> Vector2i:
	var lo := 1 << 30
	var hi := -(1 << 30)
	for c in game.chunk_pool:
		lo = mini(lo, c.index)
		hi = maxi(hi, c.index)
	return Vector2i(lo, hi)

func _chunk_of(p: Node3D) -> int:
	return floori(RoadFrame.s_at(RoadFrame.unroll(p.global_position).z) / L)

## What stands on chunk `idx`: every building's place and size.
func _sig(idx: int) -> String:
	for c in game.chunk_pool:
		if c.index != idx:
			continue
		var out := PackedStringArray()
		for child in c.root.get_children():
			if child is MeshInstance3D and String(child.name).begins_with("BuildingMesh"):
				var t: Transform3D = child.transform
				out.append("%s %s %.2f %.2f %.2f / %.2f %.2f %.2f" % [child.name, child.visible, t.origin.x, t.origin.y, t.origin.z,
					t.basis.x.length(), t.basis.y.length(), t.basis.z.length()])
		return "\n".join(out)
	return "(chunk %d is not built)" % idx

## Puts the car at road-space (x, z) heading `yaw` (0 = down the road), still.
func _put(p: PlayerCar, x: float, z: float, yaw: float) -> void:
	var y := RoadFrame.unroll(p.global_position).y
	var t := RoadFrame.pose(x, y, z, yaw)
	game.saver.restore_car(p, {"xform": SaveDirector.xform_to_array(t), "lin_vel": [0.0, 0.0, 0.0], "ang_vel": [0.0, 0.0, 0.0], "gear": 1})
	game.call("_update_chunk_pool", z)
	game.call("flush_rebuilds")  # rebuilds are spread over frames; a jump needs its road now

## Drives along the road: way -1 = down it in lane 1, +1 = back up it in the
## far side's lane 1.
func _drive(p: PlayerCar, way: float) -> void:
	p.driver = func(c: Vehicle) -> void:
		# About 110 km/h: this bot steers on its lane offset alone.
		c.throttle_input = 1.0 if c.linear_velocity.length() < 30.0 else 0.0
		c.brake_input = 0.0
		var u := RoadFrame.unroll(c.global_position)
		var lane := TrafficManager.lane_centre(1, way > 0.0)
		c.steering_input = clampf((u.x - lane) * 0.08 * -way, -0.3, 0.3)
		if c.current_gear < 3 and c.motor_rpm > 6000.0:
			c.current_gear += 1

func _road_under(p: PlayerCar, what: String) -> void:
	var space := p.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(p.global_position + Vector3.UP * 2.0, p.global_position + Vector3.DOWN * 5.0)
	q.exclude = [p.get_rid()]
	if space.intersect_ray(q).is_empty():
		_fail("%s: no road under the car" % what)
	var u := RoadFrame.unroll(p.global_position)
	if absf(u.y) > 1.5 or absf(u.x) > 16.0 or p.global_basis.y.y < 0.5:
		_fail("%s: car is off the road (x %.1f, y %.1f, up %.2f)" % [what, u.x, u.y, p.global_basis.y.y])

func _physics_process(_delta: float) -> bool:
	if game == null or not game.is_inside_tree():
		return false
	ticks += 1
	var hz := Engine.physics_ticks_per_second
	var p: PlayerCar = game.get("player")
	var tr: TrafficManager = game.get("traffic")
	match phase:
		0:  # turn round and drive back up the road, past where it used to begin
			if ticks == 2:
				if RoadMap.road_id != "loop_1" or not RoadMap.is_loop():
					_fail("a fresh run is on road '%s', not loop_1" % RoadMap.road_id)
				if game.road_seed != RoadMap.seed_of("loop_1"):
					_fail("loop_1 was built from seed %d, not its own" % game.road_seed)
				var span := _pool_span()
				if span != Vector2i(-6, 6):
					_fail("pool at the start spans %s, expected -6..6" % span)
				if game.junction == null:
					_fail("city lights are on but there is no crossing")
				z_turn = RoadFrame.unroll(p.global_position).z
				_put(p, TrafficManager.lane_centre(1, true), z_turn, PI)
				_drive(p, 1.0)
				tr.log_spawns = true
			if ticks > 2 and ticks % (hz * 4) == 0:
				print("back: t=%d chunk %d flow %+.0f %.0f km/h pool %s" % [ticks, _chunk_of(p), tr.flow, p.linear_velocity.length() * 3.6, _pool_span()])
			if ticks > hz * 3 and ticks % hz == 0:
				_road_under(p, "driving back, chunk %d" % _chunk_of(p))
			if ticks < hz * 30:
				return false
			var back := RoadFrame.unroll(p.global_position).z - z_turn
			if back < 500.0:
				_fail("only got %.0f m back up the road in 30 s" % back)
			var c0 := _chunk_of(p)
			var span := _pool_span()
			if c0 >= 0 or span.x > c0 - 5 or span.y < c0 + 5:
				_fail("pool spans %s around chunk %d: not road both ways" % [span, c0])
			if tr.flow != 1.0 or tr.flow_flips != 1:
				_fail("traffic did not turn with the player (flow %+.0f, %d flips)" % [tr.flow, tr.flow_flips])
			# Since the turn: nothing placed in view; cars going the player's way are
			# on its side (-x), oncoming ones on the other.
			var after := 0
			for s in tr.spawn_log:
				if s.player_speed < 10.0:
					continue  # before the flow turned
				after += 1
				if s.in_view:
					_fail("a car was placed in view at %.0f m" % s.dist)
				if not s.behind and s.dist < 60.0:
					_fail("a car was placed %.0f m ahead, inside the spawn band" % s.dist)
				if (s.direction > 0.0) != (s.lane_x < 0.0):
					_fail("a car going %+.0f was placed at x %.1f" % [s.direction, s.lane_x])
			var pz := RoadFrame.unroll(p.global_position).z
			var ahead_with := 0
			var ahead_onc := 0
			for car in tr.cars:
				var cz := RoadFrame.unroll(car.global_position).z
				if cz > pz and cz < pz + 500.0:
					if car.direction > 0.0:
						ahead_with += 1
					else:
						ahead_onc += 1
			if after < 6 or ahead_with < 1 or ahead_onc < 1:
				_fail("traffic after the turn: %d spawns, %d ahead going my way, %d oncoming ahead" % [after, ahead_with, ahead_onc])
			print("back: %.0f m, chunk %d, %d spawns since the turn, ahead %d with / %d oncoming" % [back, c0, after, ahead_with, ahead_onc])
			phase = 1
			ticks = 0
		1:  # a whole lap on: the same place
			if ticks == 1:
				p.driver = Callable()
				p.throttle_input = 0.0
				tr.log_spawns = false
				lap_from = _chunk_of(p)
				_put(p, TrafficManager.lane_centre(1, false), -(float(lap_from) + 0.5 - float(game.origin_index)) * L, 0.0)
			if ticks == 20:
				for i in range(lap_from - 4, lap_from + 5):
					sigs[i] = _sig(i)
				if sigs[lap_from].count("\n") < 2:
					_fail("chunk %d has almost no buildings to compare:\n%s" % [lap_from, sigs[lap_from]])
			# A lap in four jumps, with time for the floating origin in between.
			if ticks in [30, 60, 90, 120]:
				var z := RoadFrame.unroll(p.global_position).z
				_put(p, TrafficManager.lane_centre(1, false), z - RoadMap.length() / 4.0, 0.0)
			if ticks < 150:
				return false
			var now := _chunk_of(p)
			if now != lap_from + RoadMap.period:
				_fail("after a lap the car is on chunk %d, expected %d" % [now, lap_from + RoadMap.period])
			var same := 0
			for i in sigs:
				if _sig(i + RoadMap.period) == sigs[i]:
					same += 1
				else:
					_fail("chunk %d is not the same place a lap later:\n%s\n-- was --\n%s" % [i, _sig(i + RoadMap.period), sigs[i]])
			_road_under(p, "a lap on")
			print("lap: chunk %d -> %d, %d of %d chunks identical, origin %d" % [lap_from, now, same, sigs.size(), game.origin_index])
			# The save: which road, where on the lap, which way.
			saved = game.saver.capture()
			var want_s := fposmod((float(lap_from) + 0.5) * L, RoadMap.length())
			if saved.road.get("id") != "loop_1" or absf(float(saved.road.get("s", -1.0)) - want_s) > 2.0 or saved.road.get("dir") != 1:
				_fail("save says road %s, s %s, dir %s; expected loop_1, %.0f, 1" % [saved.road.get("id"), saved.road.get("s"), saved.road.get("dir"), want_s])
			# The same save from three laps later: must resume in the same spot.
			saved.origin_index = int(saved.origin_index) + 3 * RoadMap.period
			saved.clock = {"minutes": 123.0, "night": 2}
			SaveStore.save_run(saved)
			phase = 2
			_boot()
		2:
			if ticks < 3:
				return false
			if not game.resume_place or RoadMap.road_id != "loop_1":
				_fail("a loop_1 save did not resume on loop_1")
			if game.origin_index < 0 or game.origin_index >= RoadMap.period:
				_fail("resumed origin index %d is not within one lap" % game.origin_index)
			var want := SaveDirector.array_to_xform(saved.car.xform)
			if p.global_position.distance_to(want.origin) > 0.5:
				_fail("resumed %.2f m from where the save was" % p.global_position.distance_to(want.origin))
			if _chunk_of(p) != RoadMap.lap_chunk(lap_from):
				_fail("resumed on chunk %d, saved on lap chunk %d" % [_chunk_of(p), RoadMap.lap_chunk(lap_from)])
			_road_under(p, "resumed")
			if _sig(_chunk_of(p)) != sigs[lap_from]:
				_fail("the resumed chunk is not the place that was saved")
			print("resume: chunk %d, origin %d" % [_chunk_of(p), game.origin_index])
			# A save from before the map (no road id).
			var old: Dictionary = saved.duplicate(true)
			old.road.erase("id")
			old.road.erase("s")
			old.road.erase("dir")
			SaveStore.save_run(old)
			phase = 3
			_boot()
		3, 4:
			if ticks < 3:
				return false
			var what := "a save with no road id" if phase == 3 else "a save from a road this build does not have"
			if game.resume_place or RoadMap.road_id != "loop_1":
				_fail("%s: on road '%s', resume_place %s" % [what, RoadMap.road_id, game.resume_place])
			var from_top := RoadFrame.s_at(RoadFrame.unroll(p.global_position).z)
			if absf(from_top) > 5.0 or game.origin_index != 0 or p.linear_velocity.length() > 1.0:
				_fail("%s: did not start at the top of the loop (%.1f m from it, origin %d)" % [what, from_top, game.origin_index])
			if absf(game.night_clock.minutes - 123.0) > 1.0 or game.night_clock.night != 2:
				_fail("%s: the clock was not kept (%.1f, night %d)" % [what, game.night_clock.minutes, game.night_clock.night])
			_road_under(p, what)
			print("%s: starts at the top of loop_1, clock kept" % what)
			if phase == 4:
				_finish()
				return true
			var other: Dictionary = saved.duplicate(true)
			other.road.id = "loop_9"
			SaveStore.save_run(other)
			phase = 4
			_boot()
	return false

func _finish() -> void:
	SaveStore.clear_run()
	SaveDirector.enabled = false
	print("loop_road: ", "PASS" if fails.is_empty() else "FAIL (%d)" % fails.size())
	quit(0 if fails.is_empty() else 1)
