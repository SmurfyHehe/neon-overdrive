extends SceneTree

# Lowered cars through the tunnel's dip (TN1; Roy 2026-10-11: "what if we max
# lower the car? you need to stress test").
#
# The real Game.tscn on the default hilly road, no traffic. For each car and
# each tune, the car is built from the tuned spec (the way a saved tune
# loads), put at the top of one ramp and sent through to the top of the
# other at a held speed, then back the other way on the oncoming carriageway.
# The tunes are the Tuner's lowest ride height (0.16 m front, 0.18 m rear;
# a saved tune cannot go lower) with its softest and its stiffest springs and
# dampers, and stock for comparison.
#
# The speed is held by a push at the centre of mass (no pitch from it), so a
# kei car really is at 300 km/h in the sag; real cars would be slower there.
#
# Per pass it prints: ticks the body touched the road, the lowest the body
# shape's underside got above the road and where, ticks with no wheel on the
# road and the fewest wheels down, and wall contacts.
#
#   [STRESS_CARS=p1_coupe,p4_kei] [STRESS_TUNES=low_soft] [STRESS_SPEEDS=200,300]
#     <godot> --headless --audio-driver Dummy --fixed-fps 120 --path . -s res://tools/tunnel_stress.gd

const Harness := preload("res://tests/traffic/traffic_harness.gd")
const RoadMap := preload("res://scripts/world/road_map.gd")

const RATE := 120
const S_TOP_IN := 4101.0     # top of the ramp going in (the way the chunks count)
const S_TOP_OUT := 4699.0    # top of the far ramp
const TUNES := {
	"stock": {},
	"low_soft": {"front_spring_length": 0.16, "rear_spring_length": 0.18,
		"front_resting_ratio": 0.3, "rear_resting_ratio": 0.3,
		"front_damping_ratio": 0.25, "rear_damping_ratio": 0.25},
	"low_stiff": {"front_spring_length": 0.16, "rear_spring_length": 0.18,
		"front_resting_ratio": 0.7, "rear_resting_ratio": 0.55,
		"front_damping_ratio": 0.9, "rear_damping_ratio": 0.9},
}

var cars: Array = ["p0_beater", "p1_coupe", "p3_tuner", "p5_muscle", "p4_kei", "p2_hothatch", "p17_work_pickup"]
var tunes: Array = ["low_soft", "low_stiff", "stock"]
var speeds: Array = [100.0, 150.0, 200.0, 250.0, 300.0]
var game: Node
var rows: Array = []

func _list(env_name: String, fallback: Array, numbers := false) -> Array:
	var v := OS.get_environment(env_name)
	if v == "":
		return fallback
	var out := []
	for part in v.split(","):
		out.append(float(part) if numbers else part)
	return out

func _initialize() -> void:
	Engine.physics_ticks_per_second = RATE
	cars = _list("STRESS_CARS", cars)
	tunes = _list("STRESS_TUNES", tunes)
	speeds = _list("STRESS_SPEEDS", speeds, true)
	OS.set_environment("NEON_HILLS", "0.5")
	OS.set_environment("NEON_CURVES", "0.5")
	OS.set_environment("NEON_KICKERS", "0")
	OS.set_environment("NEON_ROAD", "0")
	OS.set_environment("NEON_POLICE", "0")
	OS.set_environment("NEON_START_S", str(S_TOP_IN))
	if OS.get_environment("NEON_TUNNEL") != "0":
		OS.set_environment("NEON_TUNNEL", "")
	game = Harness.boot(self, 0, 300.0, 777)
	_run.call_deferred()

func _s_of(n: Node3D) -> float:
	return RoadMap.wrap_s(RoadFrame.s_at(RoadFrame.unroll(n.global_position).z))

func _run() -> void:
	for i in RATE:
		await physics_frame
	var first: PlayerCar = game.get("player")
	first.freeze = true
	first.process_mode = Node.PROCESS_MODE_DISABLED
	first.visible = false
	# The rescue watches the first car, which stays parked while the road moves on.
	var rescue: Node = game.get("rescue")
	if rescue != null:
		rescue.set("enabled", false)
	var origin_chunk := floori(S_TOP_IN / 50.0)
	var was_selected := PlayerCars.selected
	for kind in cars:
		PlayerCars.selected = kind
		for tune_name in tunes:
			for kmh in speeds:
				for dir in [1, -1]:
					await _pass(kind, tune_name, kmh, dir)
	PlayerCars.selected = was_selected
	game.set("player", first)
	_table()
	quit(0)

func _pass(kind: String, tune_name: String, kmh: float, dir: int) -> void:
	var car := PlayerCar.new()
	car.sim_only = true
	var spec := CarSpec.player_spec(kind)
	for path in TUNES[tune_name]:
		TuneParams.set_value(spec, path, TUNES[tune_name][path])
	car.spec = spec
	var s_start := S_TOP_IN if dir == 1 else S_TOP_OUT
	var s_end := S_TOP_OUT if dir == 1 else S_TOP_IN
	var lane := Harness.lane_x(1) * float(dir)
	# road-space z of the start on the lap the game is on
	var z0 := -(s_start - float(int(game.get("origin_index"))) * 50.0)
	car.transform = RoadFrame.pose(lane, 0.6, z0, 0.0 if dir == 1 else PI)
	game.add_child(car)
	Harness.launch_player(car, 0.0)
	game.set("player", car)
	car.contact_monitor = true
	car.max_contacts_reported = maxi(car.max_contacts_reported, 8)
	# settle on its springs, held in place
	car.driver = func(c: Vehicle) -> void:
		c.steering_input = 0.0
		c.throttle_input = 0.0
		c.brake_input = 1.0
		c.handbrake_input = 1.0
	for i in RATE * 2:
		await physics_frame
	var v := kmh / 3.6
	var rest_clear := _clearance(car)
	Harness.launch_player(car, v)
	car.driver = func(c: Vehicle) -> void:
		var u := RoadFrame.unroll(c.global_position)
		c.steering_input = TrafficCar.lane_steer(c, lane - RoadFrame.dir_to_road(u.z, c.linear_velocity).x * Harness.LAT_DAMP_T, -float(dir), 2.5, Harness.PLAYER_UNDERSTEER_FF)
		c.throttle_input = 0.25
		c.brake_input = 0.0
		c.handbrake_input = 0.0
		# hold the speed: a push along the road at the centre of mass
		var fwd := -c.global_transform.basis.z
		var along := c.linear_velocity.dot(fwd)
		c.apply_central_force(fwd * clampf((v - along) * 4.0, -6.0, 12.0) * c.mass)
	var road_ticks := 0
	var wall_ticks := 0
	var air_ticks := 0
	var fewest := 4
	var low := INF
	var low_at := 0.0
	var first_at := -1.0
	var min_kmh := INF
	var t := 0
	while t < RATE * 40:
		await physics_frame
		t += 1
		var s := _s_of(car)
		if (dir == 1 and s >= s_end) or (dir == -1 and s <= s_end):
			break
		if t < 12:
			continue  # the launch itself
		min_kmh = minf(min_kmh, car.current_speed() * 3.6)
		var touched_road := false
		for b in car.get_colliding_bodies():
			var bn := String(b.name)
			if bn.begins_with("Boundary") or bn.begins_with("Building") or bn == "BarrierCol":
				wall_ticks += 1
			else:
				touched_road = true
		if touched_road:
			road_ticks += 1
			if first_at < 0.0:
				first_at = s
		var grounded := 0
		for w in car.wheel_array:
			if w.is_colliding():
				grounded += 1
		fewest = mini(fewest, grounded)
		if grounded == 0:
			air_ticks += 1
		var c := _clearance(car)
		if c < low:
			low = c
			low_at = s
	rows.append({"kind": kind, "tune": tune_name, "kmh": kmh, "dir": dir, "road": road_ticks, "wall": wall_ticks, "air": air_ticks,
		"fewest": fewest, "low": low, "low_at": low_at, "first_at": first_at, "rest": rest_clear, "min_kmh": min_kmh, "done": t < RATE * 40})
	print("stress: %-16s %-9s %3.0f km/h %s  road contact %4d ticks%s  lowest underside %6.3f m at %4.0f m (at rest %.3f)  air %d, fewest wheels %d, wall %d, slowest %.0f%s" % [
		kind, tune_name, kmh, "in " if dir == 1 else "out", road_ticks, (" from %.0f m" % first_at) if first_at >= 0.0 else "",
		low, low_at, rest_clear, air_ticks, fewest, wall_ticks, min_kmh, "" if t < RATE * 40 else "  DID NOT FINISH"])
	car.driver = Callable()
	car.queue_free()
	await physics_frame

## Lowest point of the body shape above the road under it (m); as
## tests/car/car_scrape.gd measures it.
func _clearance(v: Vehicle) -> float:
	var col: CollisionShape3D
	for ch in v.get_children():
		if ch is CollisionShape3D:
			col = ch
	var pts: PackedVector3Array
	if col.shape is BoxShape3D:
		var h := (col.shape as BoxShape3D).size * 0.5
		for sx in [-1.0, 1.0]:
			for sy in [-1.0, 1.0]:
				for sz in [-1.0, 1.0]:
					pts.append(Vector3(sx * h.x, sy * h.y, sz * h.z))
	else:
		pts = (col.shape as ConvexPolygonShape3D).points
	var space := v.get_world_3d().direct_space_state
	var low := INF
	for pt in pts:
		var w := v.global_transform * (col.position + pt)
		var q := PhysicsRayQueryParameters3D.create(w + Vector3(0, 3, 0), w - Vector3(0, 3, 0), 1)
		var hit := space.intersect_ray(q)
		if not hit.is_empty():
			low = minf(low, w.y - hit.position.y)
	return low

## One line per car and tune: road-contact ticks at each speed, in / out.
func _table() -> void:
	var head := "%-16s %-9s" % ["car", "tune"]
	for kmh in speeds:
		head += " | %3.0f in/out" % kmh
	print("\nRoad-contact ticks (120 a second), in / out, and * where a wheel set left the road:")
	print(head)
	for kind in cars:
		for tune_name in tunes:
			var line := "%-16s %-9s" % [kind, tune_name]
			for kmh in speeds:
				var cell := ""
				for dir in [1, -1]:
					for r in rows:
						if r.kind == kind and r.tune == tune_name and r.kmh == kmh and r.dir == dir:
							cell += "%4d%s" % [r.road, "*" if int(r.air) > 0 else " "]
				line += " | %s" % cell
			print(line)
	var worst := 0
	var airborne := 0
	for r in rows:
		worst = maxi(worst, int(r.road))
		airborne += int(r.air)
	print("worst road contact %d ticks; ticks with no wheel on the road, all passes: %d" % [worst, airborne])
