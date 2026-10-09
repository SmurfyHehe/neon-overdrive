extends SceneTree

# Cars must not scrape themselves (Roy 2026-10-09: "adjust the car so it
# doesn't scrape itself on its own").
#
# CrashAudio plays its metal scrape whenever the body reports ANY contact
# (RigidBody3D.get_contact_count() > 0), and the chassis box is a car's only
# body shape, so a box corner that touches the road is a scrape: sound, and
# whatever else reads contacts. The box's underside used to ride 3-8 cm above
# the road, and throttle squat (about 3 deg) or brake dive (about 1.6 deg) over
# the half-length of the box was enough to put a rear or front bottom corner
# in the road at 2 m/s. CarSpec.build_collision now lifts the underside at
# the ends and sides (a hull with the same bounding box, so mass, centre of
# mass and inertia are unchanged); this test keeps it that way.
#
# Flat road, nothing else about (no traffic, walls 13+ m away). Any contact is
# a fail. Per car it prints the contact ticks and the lowest the body shape's
# underside got above the road (negative = in the road).
#   - the player (P1 coupe): sit 3 s, full throttle to 180 km/h, full brake to
#     a stop, lane changes at 120 km/h, full-lock swerves, brake in a turn;
#   - every traffic car kind: settle 3 s, accelerate to 120 km/h on its own
#     controller, brake from 100 km/h to a stop;
#   - tests/car_scrape_tunes.gd: the player's manoeuvres (shorter) on tuned coupes (SWEEP: the Tuner's lowest,
#     stiffest, softest and tallest suspension with the most power, brakes and
#     grip, and Roy's own saved tune), built from the tune and, for some, tuned
#     live after the build the way the Tuner does it.
# Walls and buildings do not count (a tuned car can slide into one in the
# swerves); only touching the road does.
# CAR_SCRAPE_HILLS=1 runs the same on the hilly bending road, to compare
# (prints only; the hill road adds real bumps and crests).
#
# Run: <godot> --headless --audio-driver Dummy --fixed-fps 120 --path . -s res://tests/car/car_scrape.gd

const Harness := preload("res://tests/traffic/traffic_harness.gd")

const RATE := 120
const CRUISE := 120.0 / 3.6
const PHASES := ["rest", "accel", "hard_brake", "lane_changes", "swerve", "brake_in_turn"]

var logger := Harness.ErrorCounter.new()
var fails: Array[String] = []
var game: Node
var hills := false
var strict := true
## Set by tests/car_scrape_tunes.gd: run the tuned coupes (SWEEP) instead.
var sweep := false
## Seconds per timed manoeuvre; the sweep runs them shorter to fit the runner.
var lane_s := 15
var swerve_s := 8

# Player scenario state.
var steer := 0.0
var throttle := 0.0
var brake := 0.0
var lane_target := 1

# Per-car measurements, keyed by a label.
var contact_ticks := {}
var contact_names := {}
var min_clear := {}
var current_label := ""

func _check(ok: bool, msg: String) -> void:
	if not ok:
		fails.append(msg)

func _initialize() -> void:
	OS.add_logger(logger)
	Engine.physics_ticks_per_second = RATE
	hills = OS.get_environment("CAR_SCRAPE_HILLS") == "1"
	OS.set_environment("NEON_HILLS", "1.0" if hills else "0")
	OS.set_environment("NEON_CURVES", "1.0" if hills else "0")
	OS.set_environment("NEON_ROAD_SEED", "37")
	game = Harness.boot(self, 0, 300.0, 777, 1.0e6)
	_run.call_deferred()

func _run() -> void:
	for i in RATE:
		await physics_frame
	var p: PlayerCar = game.get("player")
	if not sweep:
		await _inertia_unchanged()
		_watch(p, "player")
		await _drive_player(p)
		_unwatch(p)
		for kind in NpcCarBuilder.KINDS:
			await _drive_traffic(kind, p)
	else:
		await _sweep(p)
	_finish()

# --- handling is unchanged ---------------------------------------------------

## The hull must give the physics engine the same mass distribution as the old
## box: same inverse inertia, same shape bounds.
func _inertia_unchanged() -> void:
	for size in [Vector3(1.6, 1.0, 3.4), Vector3(1.75, 1.14, 4.66), Vector3(1.9, 1.3, 5.2)]:
		var old := RigidBody3D.new()
		var oc := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = size
		oc.shape = box
		old.add_child(oc)
		var nu := RigidBody3D.new()
		var nc := CollisionShape3D.new()
		nc.shape = CarSpec.chassis_hull(size)
		nu.add_child(nc)
		for b in [old, nu]:
			b.mass = 1300.0
			b.gravity_scale = 0.0
			game.add_child(b)
			b.global_position = Vector3(0.0, 500.0, 0.0)
		for i in 3:
			await physics_frame
		var i_old: Vector3 = PhysicsServer3D.body_get_direct_state(old.get_rid()).inverse_inertia
		var i_new: Vector3 = PhysicsServer3D.body_get_direct_state(nu.get_rid()).inverse_inertia
		print("car_scrape: inverse inertia for %s: box %s, hull %s" % [size, i_old, i_new])
		_check(i_old.is_finite() and i_old.length() > 0.0, "box inertia was not computed for %s" % size)
		_check(i_old.distance_to(i_new) < 1.0e-6 * maxf(i_old.length(), 1.0), "hull inertia %s differs from the box's %s for %s" % [i_new, i_old, size])
		_check(nu.center_of_mass.is_equal_approx(old.center_of_mass), "hull centre of mass differs for %s" % size)
		old.queue_free()
		nu.queue_free()

# --- measuring -------------------------------------------------------------

func _watch(v: Vehicle, label: String) -> void:
	current_label = label
	v.contact_monitor = true
	v.max_contacts_reported = maxi(v.max_contacts_reported, 8)
	var cb := func(b: Node) -> void:
		var n := "%s/%s" % [b.get_parent().name if b.get_parent() != null else "?", b.name]
		if not contact_names.has(current_label):
			contact_names[current_label] = {}
		contact_names[current_label][n] = int(contact_names[current_label].get(n, 0)) + 1
	v.body_entered.connect(cb)
	v.set_meta("scrape_cb", cb)

func _unwatch(v: Vehicle) -> void:
	v.body_entered.disconnect(v.get_meta("scrape_cb"))

func _sample(v: Vehicle, label: String) -> void:
	if _touches_road(v):
		contact_ticks[label] = int(contact_ticks.get(label, 0)) + 1
	min_clear[label] = minf(min_clear.get(label, INF), _clearance(v))

## Body contact with anything but the chunks' walls and buildings (a full-lock
## swerve on a tuned car can slide into those; that is a crash, not a scrape).
func _touches_road(v: Vehicle) -> bool:
	for b in v.get_colliding_bodies():
		var n := String(b.name)
		if not (n.begins_with("Boundary") or n.begins_with("Building")):
			return true
	return false

## Lowest point of the body shape above the road under it (m).
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

func _report(label: String, extra: String) -> void:
	var n: int = contact_ticks.get(label, 0)
	print("car_scrape: %-26s contact ticks %5d  lowest underside %6.3f m  %s %s" % [
		label, n, min_clear.get(label, INF), extra, contact_names.get(label, {}) if n > 0 else ""])
	if strict and not hills:
		_check(n == 0, "%s touched something %d ticks on a flat road with nothing around: %s" % [label, n, contact_names.get(label, {})])

# --- the player ------------------------------------------------------------

func _drive_player(p: PlayerCar, prefix := "player") -> void:
	lane_target = 1
	p.driver = func(c: Vehicle) -> void:
		c.steering_input = steer
		c.throttle_input = throttle
		c.brake_input = brake
		c.handbrake_input = 0.0
	for ph in PHASES:
		var label: String = prefix + "/" + ph
		current_label = label
		var t := 0
		var done := false
		while not done:
			await physics_frame
			t += 1
			var spd := p.current_speed()
			var lx := Harness.lane_x(lane_target)
			var u := RoadFrame.unroll(p.global_position)
			var track := TrafficCar.lane_steer(p, lx - RoadFrame.dir_to_road(u.z, p.linear_velocity).x * Harness.LAT_DAMP_T, -1.0, 2.5, Harness.PLAYER_UNDERSTEER_FF)
			match ph:
				"rest":
					steer = 0.0; throttle = 0.0; brake = 0.0
					done = t > RATE * 3
				"accel":
					steer = track; throttle = 1.0; brake = 0.0
					done = spd > 50.0 or t > RATE * 40
				"hard_brake":
					steer = track; throttle = 0.0; brake = 1.0
					done = spd < 1.0 or t > RATE * 20
					if done:
						# The launch itself is not a driver action: settle it unmeasured.
						brake = 0.0
						Harness.move_player_to_lane(p, Harness.lane_x(1))
						Harness.launch_player(p, CRUISE)
						throttle = 0.5
						for i in RATE * 2:
							await physics_frame
							var uu := RoadFrame.unroll(p.global_position)
							steer = TrafficCar.lane_steer(p, Harness.lane_x(1) - RoadFrame.dir_to_road(uu.z, p.linear_velocity).x * Harness.LAT_DAMP_T, -1.0, 2.5, Harness.PLAYER_UNDERSTEER_FF)
				"lane_changes":
					lane_target = 1 + int(t / (RATE * 3)) % 2
					steer = track; throttle = 0.5 if spd < CRUISE else 0.0; brake = 0.0
					done = t > RATE * lane_s
				"swerve":
					steer = 1.0 if int(t / 30) % 2 == 0 else -1.0
					throttle = 0.5 if spd < 30.0 else 0.0; brake = 0.0
					done = t > RATE * swerve_s
				"brake_in_turn":
					steer = 0.5; throttle = 0.0; brake = 1.0
					done = t > RATE * 4
			if t > 5:
				_sample(p, label)
		_report(label, "")
	p.driver = Callable()

# --- tuner settings sweep ----------------------------------------------------

## Tunes that move the body down or pitch it harder than stock. Every value is
## inside the Tuner's safe range (TuneParams min..max), which is also all a
## saved tune can load as (PlayerTune.apply_saved clamps to it).
const SWEEP := {
	# Roy's saved tune on 2026-10-09: ride height at the Tuner's minimum.
	"roy_oct9": {"front_spring_length": 0.16, "rear_spring_length": 0.18,
		"front_resting_ratio": 0.5, "rear_resting_ratio": 0.5,
		"front_damping_ratio": 0.55, "rear_damping_ratio": 0.55,
		"max_torque": 460.0, "turbo_boost_max": 1.5, "brake_force_multiplier": 2.5,
		"aero_downforce_coefficient_front": 0.35, "aero_downforce_coefficient_rear": 0.55,
		"coefficient_of_friction/Road": 1.2, "longitudinal_grip_ratio/Road": 1.1},
	# Lowest, softest, most power, hardest brakes, most grip and downforce.
	"low_soft": {"front_spring_length": 0.16, "rear_spring_length": 0.18,
		"front_resting_ratio": 0.3, "rear_resting_ratio": 0.3,
		"front_damping_ratio": 0.25, "rear_damping_ratio": 0.25,
		"max_torque": 900.0, "turbo_boost_max": 1.5, "brake_force_multiplier": 3.0,
		"aero_downforce_coefficient_front": 1.0, "aero_downforce_coefficient_rear": 1.2,
		"coefficient_of_friction/Road": 2.5, "longitudinal_grip_ratio/Road": 1.2},
	# Lowest and stiffest.
	"low_stiff": {"front_spring_length": 0.16, "rear_spring_length": 0.18,
		"front_resting_ratio": 0.7, "rear_resting_ratio": 0.55,
		"front_damping_ratio": 0.9, "rear_damping_ratio": 0.9,
		"max_torque": 900.0, "turbo_boost_max": 1.5, "brake_force_multiplier": 3.0},
	# Tallest and softest: prints only (see PRINT_ONLY).
	"high_soft": {"front_spring_length": 0.28, "rear_spring_length": 0.27,
		"front_resting_ratio": 0.3, "rear_resting_ratio": 0.3,
		"front_damping_ratio": 0.25, "rear_damping_ratio": 0.25,
		"brake_force_multiplier": 3.0,
		"coefficient_of_friction/Road": 2.5, "longitudinal_grip_ratio/Road": 1.2},
}

## Tunes measured but not failed. high_soft: softest springs and dampers on the
## tallest springs. At 120 km/h and in full-lock swerves all four springs run
## out of travel and the body lands on the road (contacts with 0-7 cm of
## spring left, 2026-10-09). That is the suspension bottoming out, which a
## bump stop would fix (GEVP has none), not the body shape.
const PRINT_ONLY := ["high_soft"]
## Tunes also run "live". Live and built match since CarSpec.remount_wheels.
const LIVE := ["roy_oct9"]

## Each tune two ways: "built" = the car is built from the tuned spec (a saved
## tune at launch, or after a restart), "live" = a stock car changed through
## CarSpec.set_param() after it is built (dragging the Tuner sliders mid-run).
func _sweep(p: PlayerCar) -> void:
	lane_s = 6
	swerve_s = 4
	p.freeze = true
	p.process_mode = Node.PROCESS_MODE_DISABLED
	for tune_name in SWEEP:
		for mode in (["built", "live"] if tune_name in LIVE else ["built"]):
			var car := PlayerCar.new()
			car.sim_only = true
			var spec := CarSpec.coupe_default()
			if mode == "built":
				for path in SWEEP[tune_name]:
					TuneParams.set_value(spec, path, SWEEP[tune_name][path])
			car.spec = spec
			car.position = Vector3(Harness.lane_x(1), p.global_position.y, p.global_position.z - 40.0)
			game.add_child(car)
			# Wheels start with their last position at the origin; make the sim
			# history match where the car is, or the first tick launches it.
			Harness.launch_player(car, 0.0)
			# The road streams around game.player: hand it the tuned car.
			game.set("player", car)
			if mode == "live":
				for path in SWEEP[tune_name]:
					CarSpec.set_param(car, car.spec, path, SWEEP[tune_name][path])
			var prefix := "%s/%s" % [tune_name, mode]
			strict = not tune_name in PRINT_ONLY
			# Settle unmeasured: the drop from the spawn height, or from the
			# old ride height when the tune lands on a built car.
			for i in RATE * 3:
				await physics_frame
			_watch(car, prefix)
			await _drive_player(car, prefix)
			_unwatch(car)
			game.set("player", p)
			car.queue_free()
			await physics_frame

# --- traffic cars ----------------------------------------------------------

func _drive_traffic(kind: String, p: PlayerCar) -> void:
	var car := TrafficCar.new()
	car.kind = kind
	car.build = "stock"
	car.color = NpcCarBuilder.PAINTS[0][0]
	car.target_speed = 0.0
	game.add_child(car)
	var lane := Harness.lane_x(1)
	Harness.move_player_to_lane(p, Harness.lane_x(3))
	car.place(lane, -1.0, p.global_position.z - 15.0, car.rest_y, 0.0)
	p.driver = func(c: Vehicle) -> void:
		var ahead := c.global_position.z - car.global_position.z
		c.steering_input = TrafficCar.lane_steer(c, Harness.lane_x(3) - c.linear_velocity.x * Harness.LAT_DAMP_T, -1.0, 2.5)
		c.throttle_input = 1.0 if ahead > 20.0 else 0.0
		c.brake_input = 0.0 if ahead > 5.0 else 0.5
		c.handbrake_input = 0.0
	var label: String = kind + "/accel"
	_watch(car, label)
	for i in RATE * 3:
		await physics_frame
		if i > 5:
			_sample(car, label)
	car.target_speed = CRUISE
	for i in RATE * 20:
		await physics_frame
		_sample(car, label)
	_unwatch(car)
	_report(label, "(settle + accelerate to %.0f km/h)" % Harness.kmh(car.current_speed()))
	label = kind + "/brake"
	current_label = label
	_watch(car, label)
	car.target_speed = 100.0 / 3.6
	TrafficCar.set_moving(car, 100.0 / 3.6)
	for i in RATE:
		await physics_frame
	car.target_speed = 0.0
	var t := 0
	while car.current_speed() > 0.3 and t < RATE * 20:
		await physics_frame
		t += 1
		_sample(car, label)
	_unwatch(car)
	_report(label, "(brake from 100 km/h)")
	p.driver = Callable()
	car.queue_free()
	await physics_frame

func _finish() -> void:
	for e in logger.errors:
		fails.append("logged error: " + e)
	for f in fails:
		printerr("FAIL: ", f)
	print("car_scrape: %s" % ("PASS" if fails.is_empty() else "FAIL (%d)" % fails.size()))
	quit(0 if fails.is_empty() else 1)
