extends SceneTree

# Golden run for the car physics (C++ step 1, 2026-10-11): a bug check of the
# native wheel path against the GDScript reference, not a "feels the same" gate.
#
# Four cars, one after the other, each alone on the same small test ground,
# driven by the same scripted pedals for 20 s at 120 Hz: a flat launch, a hill,
# a kerb taken at an angle, a bend, a hard stop, a handbrake turn. Every tick is
# logged to a CSV: position, rotation, velocity, engine rpm, gear, and per wheel
# its spin, slip and whether it touches the ground.
#
#   record:   <godot> --headless --audio-driver Dummy --fixed-fps 120 --path . -s res://tools/sim_golden.gd -- out=<file.csv>
#             (the GDScript path; set NEON_SIM_NATIVE=1 for the C++ path)
#   compare:  <godot> --headless --path . -s res://tools/sim_golden.gd -- compare=<reference.csv>,<other.csv>
#
# tools/sim-golden.ps1 does the three runs in a row. Compare exits 0 on PASS:
# the same gear and the same wheel contacts on every tick; position within 1 mm
# and speed within 0.01 m/s over the first 5 s; within 5 cm and 0.1 m/s at 20 s.
#
# The cars are sim-only PlayerCars (no body mesh, no audio) on CarSpec data:
# the Bug (p0_beater), the coupe (p1_coupe), a traffic car's spec (n1_commuter)
# and a cop's (c1_patrol). Every car in the game runs this same Vehicle sim.

const RATE := 120
const RUN_S := 20.0
const SETTLE_S := 1.0
const CARS := [
	{"name": "bug", "kind": "p0_beater", "npc": false},
	{"name": "coupe", "kind": "p1_coupe", "npc": false},
	{"name": "traffic", "kind": "n1_commuter", "npc": true},
	{"name": "cop", "kind": "c1_patrol", "npc": true},
]
const HEADER := "car,tick,px,py,pz,qx,qy,qz,qw,vx,vy,vz,speed,rpm,gear,spin0,spin1,spin2,spin3,slipx0,slipx1,slipx2,slipx3,slipy0,slipy1,slipy2,slipy3,hit0,hit1,hit2,hit3"
const COL_TICK := 1
const COL_POS := 2
const COL_SPEED := 12
const COL_GEAR := 14
const COL_HIT := 27

const FIRST_S := 5.0
const FIRST_POS := 0.001
const FIRST_SPEED := 0.01
const END_POS := 0.05
const END_SPEED := 0.1

var _throttle := 0.0
var _brake := 0.0
var _steer := 0.0
var _handbrake := 0.0

func _initialize() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		if kv.size() == 2:
			args[kv[0]] = kv[1]
	if args.has("compare"):
		var files: PackedStringArray = String(args["compare"]).split(",")
		quit(0 if files.size() == 2 and _compare(files[0], files[1]) else 1)
		return
	if not args.has("out"):
		print("sim_golden: give out=<file.csv> or compare=<a.csv>,<b.csv>")
		quit(2)
		return
	Engine.physics_ticks_per_second = RATE
	_record.call_deferred(String(args["out"]))

# ---------- the ground ----------

func _body(group: String, layer: int) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.add_to_group(group)
	body.collision_layer = 1 << (layer - 1)
	root.add_child(body)
	return body

func _box(body: StaticBody3D, size: Vector3, at: Vector3, tilt_x := 0.0) -> void:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position = at
	shape.rotation.x = tilt_x
	body.add_child(shape)

## Flat road 1200 m wide; across the whole width a 1.2 m hill between z = -40 and
## -100 and a 12 cm pavement with ramped edges between z = -130 and -136. The
## cars start at the origin and head down -Z, so every car crosses both.
func _build_ground() -> void:
	var road := _body("Road", CarSpec.WORLD_LAYER)
	_box(road, Vector3(1200.0, 2.0, 1600.0), Vector3(0.0, -1.0, -400.0))
	# the hill: a strip of triangles along a cosine bump
	var hill := _body("Road", CarSpec.WORLD_LAYER)
	var faces := PackedVector3Array()
	var steps := 30
	for i in steps:
		var z0 := -40.0 - 60.0 * float(i) / steps
		var z1 := -40.0 - 60.0 * float(i + 1) / steps
		var y0 := 0.6 * (1.0 - cos(TAU * float(i) / steps))
		var y1 := 0.6 * (1.0 - cos(TAU * float(i + 1) / steps))
		var a := Vector3(-600.0, y0, z0)
		var b := Vector3(600.0, y0, z0)
		var c := Vector3(600.0, y1, z1)
		var d := Vector3(-600.0, y1, z1)
		faces.append_array([a, b, c, a, c, d])
	var tri := ConcavePolygonShape3D.new()
	tri.backface_collision = true
	tri.set_faces(faces)
	var hill_shape := CollisionShape3D.new()
	hill_shape.shape = tri
	hill.add_child(hill_shape)
	# the pavement: wheels only (the kerb layer), its own grip group
	var kerb := _body("Kerb", CarSpec.KERB_LAYER)
	var kerb_faces := PackedVector3Array()
	var profile := [Vector2(-130.0, 0.0), Vector2(-130.12, 0.12), Vector2(-135.88, 0.12), Vector2(-136.0, 0.0)]
	for i in profile.size() - 1:
		var p0: Vector2 = profile[i]
		var p1: Vector2 = profile[i + 1]
		var a := Vector3(-600.0, p0.y, p0.x)
		var b := Vector3(600.0, p0.y, p0.x)
		var c := Vector3(600.0, p1.y, p1.x)
		var d := Vector3(-600.0, p1.y, p1.x)
		kerb_faces.append_array([a, b, c, a, c, d])
	var kerb_tri := ConcavePolygonShape3D.new()
	kerb_tri.backface_collision = true
	kerb_tri.set_faces(kerb_faces)
	var kerb_shape := CollisionShape3D.new()
	kerb_shape.shape = kerb_tri
	kerb.add_child(kerb_shape)
	CarSimSwitch.note_ground(road)
	CarSimSwitch.note_ground(kerb)  # the hill is left for the look-it-up-once path

# ---------- the pedals ----------

## What the driver does at time t (seconds after the settle). steer: + = right.
func _script_at(t: float) -> void:
	_throttle = 0.0
	_brake = 0.0
	_steer = 0.0
	_handbrake = 0.0
	if t < 6.0:
		_throttle = 1.0                      # flat launch, then the hill
	elif t < 9.0:
		_throttle = 0.7
		_steer = -0.12 if t < 7.5 else 0.10  # drift across the lane: the kerb is met at an angle
	elif t < 11.0:
		_throttle = 1.0
	elif t < 14.5:
		_throttle = 0.6                      # the bend
		_steer = 0.45
	elif t < 15.5:
		_throttle = 0.3
		_steer = -0.25
	elif t < 17.5:
		_brake = 1.0                         # hard stop from speed (ABS)
	elif t < 18.5:
		_throttle = 1.0
		_steer = 0.8
	else:
		_handbrake = 1.0                     # handbrake turn to the end
		_steer = 0.8

func _drive(c: PlayerCar) -> void:
	c.throttle_input = _throttle
	c.brake_input = _brake
	c.handbrake_input = _handbrake
	c.steering_input = -signf(_steer) * pow(absf(_steer), 1.0 / maxf(c.steering_exponent, 0.1))

# ---------- record ----------

func _record(path: String) -> void:
	_build_ground()
	for i in 4:
		await physics_frame
	var lines := PackedStringArray([HEADER])
	var native := 0
	for car in CARS:
		var c := PlayerCar.new()
		c.sim_only = true
		c.spec = CarSpec.clone_spec(CarSpec.npc_spec(car.kind)) if car.npc else CarSpec.player_spec(car.kind)
		c.driver = _drive
		c.position = Vector3(0.0, 0.5, 0.0)
		root.add_child(c)
		if not car.npc:
			c.set_transmission_mode(PlayerCar.Transmission.AUTO)
		_script_at(-1.0)
		_brake = 1.0
		for i in int(SETTLE_S * RATE):
			await physics_frame
		for tick in int(RUN_S * RATE):
			_script_at(float(tick) / RATE)
			await physics_frame
			lines.append(_row(String(car.name), tick, c))
		# on the C++ path only if CarSim stepped every tick of it (settle included)
		if c.sim_bridge != null and int(c.sim_bridge.get("native_ticks")) >= int((SETTLE_S + RUN_S) * RATE):
			native += 1
		print("sim_golden: %-8s end pos (%.3f, %.3f, %.3f)  %.1f km/h  gear %d" % [
			car.name, c.global_position.x, c.global_position.y, c.global_position.z, c.linear_velocity.length() * 3.6, c.current_gear])
		c.queue_free()
		for i in 4:
			await physics_frame
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path).get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		print("sim_golden: cannot write %s" % path)
		quit(1)
		return
	f.store_string("\n".join(lines) + "\n")
	f.close()
	print("sim_golden: %d rows -> %s  (cars on the C++ path: %d of %d)" % [lines.size() - 1, path, native, CARS.size()])
	# asked for the C++ path but a car fell back: the file is not what it says
	quit(1 if CarSimSwitch.enabled and native != CARS.size() else 0)

func _num(x: float) -> String:
	return String.num(x, 14)

func _row(name: String, tick: int, c: PlayerCar) -> String:
	var p := c.global_position
	var q := c.global_basis.get_rotation_quaternion()
	var v := c.linear_velocity
	var cols := PackedStringArray([name, str(tick),
		_num(p.x), _num(p.y), _num(p.z), _num(q.x), _num(q.y), _num(q.z), _num(q.w),
		_num(v.x), _num(v.y), _num(v.z), _num(v.length()), _num(c.motor_rpm), str(c.current_gear)])
	var wheels: Array[Wheel] = [c.front_left_wheel, c.front_right_wheel, c.rear_left_wheel, c.rear_right_wheel]
	for w in wheels:
		cols.append(_num(w.spin))
	for w in wheels:
		cols.append(_num(w.slip_vector.x))
	for w in wheels:
		cols.append(_num(w.slip_vector.y))
	for w in wheels:
		cols.append("1" if w.is_colliding() else "0")
	return ",".join(cols)

# ---------- compare ----------

func _load(path: String) -> Dictionary:
	var by_car := {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		print("sim_golden: cannot read %s" % path)
		return by_car
	f.get_line()
	while not f.eof_reached():
		var line := f.get_line()
		if line == "":
			continue
		var cols := line.split(",")
		if not by_car.has(cols[0]):
			by_car[cols[0]] = []
		by_car[cols[0]].append(cols)
	return by_car

func _compare(ref_path: String, other_path: String) -> bool:
	var ref := _load(ref_path)
	var other := _load(other_path)
	if ref.is_empty() or other.is_empty():
		return false
	print("sim_golden: %s (reference) against %s" % [ref_path, other_path])
	print("%-8s %6s | %12s %12s | %12s %12s | %12s %12s | %6s %8s | %s" % [
		"car", "ticks", "pos 0-5s m", "speed 0-5s", "pos @20s m", "speed @20s", "pos max m", "speed max", "gear", "contact", "first tick that differs at all"])
	var all_ok := true
	for car in CARS:
		var name := String(car.name)
		var a: Array = ref.get(name, [])
		var b: Array = other.get(name, [])
		if a.is_empty() or a.size() != b.size():
			print("%-8s rows differ: %d against %d" % [name, a.size(), b.size()])
			all_ok = false
			continue
		var first_pos := 0.0
		var first_speed := 0.0
		var max_pos := 0.0
		var max_speed := 0.0
		var end_pos := 0.0
		var end_speed := 0.0
		var gear_diffs := 0
		var hit_diffs := 0
		var first_diff := -1
		for i in a.size():
			var ra: PackedStringArray = a[i]
			var rb: PackedStringArray = b[i]
			if first_diff < 0 and ra != rb:
				first_diff = int(ra[COL_TICK])
			var dp := Vector3(float(ra[COL_POS]) - float(rb[COL_POS]), float(ra[COL_POS + 1]) - float(rb[COL_POS + 1]), float(ra[COL_POS + 2]) - float(rb[COL_POS + 2])).length()
			var ds := absf(float(ra[COL_SPEED]) - float(rb[COL_SPEED]))
			max_pos = maxf(max_pos, dp)
			max_speed = maxf(max_speed, ds)
			if float(i) / RATE < FIRST_S:
				first_pos = maxf(first_pos, dp)
				first_speed = maxf(first_speed, ds)
			if i == a.size() - 1:
				end_pos = dp
				end_speed = ds
			if ra[COL_GEAR] != rb[COL_GEAR]:
				gear_diffs += 1
			for k in 4:
				if ra[COL_HIT + k] != rb[COL_HIT + k]:
					hit_diffs += 1
					break
		var ok := gear_diffs == 0 and hit_diffs == 0 and first_pos <= FIRST_POS and first_speed <= FIRST_SPEED and end_pos <= END_POS and end_speed <= END_SPEED
		all_ok = all_ok and ok
		print("%-8s %6d | %12.9f %12.9f | %12.9f %12.9f | %12.9f %12.9f | %6s %8s | %s   %s" % [
			name, a.size(), first_pos, first_speed, end_pos, end_speed, max_pos, max_speed,
			"same" if gear_diffs == 0 else str(gear_diffs), "same" if hit_diffs == 0 else str(hit_diffs),
			"none: identical" if first_diff < 0 else "tick %d (%.2f s)" % [first_diff, float(first_diff) / RATE],
			"ok" if ok else "OUT OF TOLERANCE"])
	print("limits: gear and contacts the same on every tick; 0-5 s within %.3f m and %.2f m/s; at 20 s within %.2f m and %.1f m/s" % [FIRST_POS, FIRST_SPEED, END_POS, END_SPEED])
	print("sim_golden: %s" % ("PASS" if all_ok else "FAIL"))
	return all_ok
