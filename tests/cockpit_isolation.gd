extends SceneTree

# The cockpit is visual only (Roy, 2026-10-06: "make sure the interior doesn't
# break the exterior or any physics"). The same player car is driven twice in
# a row through the same 20 s of scripted input at 120 Hz, first bare, then
# with the CockpitFrame (and, on the driver branch, the DriverModel) built
# under it:
# - nothing in the cockpit subtree is a CollisionObject3D, CollisionShape3D,
#   Area3D, RayCast3D or ShapeCast3D, and none of its meshes casts a shadow
# - mass, inertia, centre of mass, collision shapes, layers, mask, wheel
#   raycasts and wheel hardpoints are identical on both cars
# - the two trajectories match within 1e-6 m and 1e-6 m/s at every tick
# - a traffic car gets no cockpit
# Exit code 1 on failure. Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --fixed-fps 120 --path . -s res://tests/cockpit_isolation.gd

const SECS := 20.0
const TOL := 1e-6
const BAD_CLASSES := ["CollisionObject3D", "CollisionShape3D", "Area3D", "RayCast3D", "ShapeCast3D", "PhysicsBody3D"]

var tick := 0
var ticks_total := 0
var failures: Array[String] = []
var car: PlayerCar
var frame: CockpitFrame
var pass_i := 0          # 0 bare, 1 with the cockpit
var t := 0.0
var pos_log: PackedVector3Array = []
var vel_log: PackedVector3Array = []
var max_dpos := 0.0
var max_dvel := 0.0
var bare := {}
## Both passes spawn the car from a physics tick, so GEVP reads the body's
## inertia (which it scales by inertia_multiplier) at the same tick after spawn.
var spawn_tick := -10

func _initialize() -> void:
	ExhaustTune.save_path = "user://autotune/test_cockpit_isolation_exhaust.json"
	Engine.physics_ticks_per_second = 120
	ticks_total = int(SECS * 120.0)
	var ground := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(400.0, 2.0, 4000.0)
	shape.shape = box
	shape.position = Vector3(0.0, -1.0, -1500.0)
	ground.add_child(shape)
	ground.add_to_group("Road")
	root.add_child(ground)

func _spawn() -> void:
	car = PlayerCar.new()
	car.position = Vector3(0.0, 0.0, 0.0)
	root.add_child(car)
	if pass_i == 1:
		frame = CockpitFrame.new(car)
		car.add_child(frame)
	car.driver = _drive
	spawn_tick = tick

## The same hands both times: full throttle, a gentle weave, a brake at 12-14 s.
func _drive(c: PlayerCar) -> void:
	var braking := t >= 12.0 and t < 14.0
	c.throttle_input = 0.0 if braking else 1.0
	c.brake_input = 1.0 if braking else 0.0
	c.handbrake_input = 0.0
	c.steering_input = 0.2 * sin(t * 0.7)

## What the car is made of, for comparing the two passes.
func _describe(c: PlayerCar) -> Dictionary:
	var shapes := []
	for s in c.find_children("*", "CollisionShape3D", true, false):
		var cs := s as CollisionShape3D
		var desc := {"pos": cs.position, "rot": cs.rotation, "shape": cs.shape.get_class()}
		if cs.shape is BoxShape3D:
			desc["size"] = (cs.shape as BoxShape3D).size
		shapes.append(desc)
	var wheels := []
	for w in c.wheel_array:
		wheels.append({"pos": w.position, "r": w.tire_radius, "spring": w.spring_length, "target": w.target_position})
	return {
		"mass": c.mass, "com": c.center_of_mass, "com_mode": c.center_of_mass_mode, "inertia": c.inertia,
		"phys_inertia": PhysicsServer3D.body_get_param(c.get_rid(), PhysicsServer3D.BODY_PARAM_INERTIA),
		"layer": c.collision_layer, "mask": c.collision_mask, "shapes": shapes, "wheels": wheels,
		"raycasts": c.find_children("*", "RayCast3D", true, false).size(),
		"bodies": c.find_children("*", "CollisionObject3D", true, false).size(),
		"damp": c.linear_damp, "angular_damp": c.angular_damp, "gravity": c.gravity_scale,
	}

func _check_cockpit() -> void:
	var nodes: Array = frame.find_children("*", "", true, false)
	nodes.append(frame)
	var bad := []
	for n in nodes:
		for cls in BAD_CLASSES:
			if n.is_class(cls):
				bad.append("%s (%s)" % [n.name, n.get_class()])
		if n is GeometryInstance3D and (n as GeometryInstance3D).cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			bad.append("%s casts shadows" % n.name)
	_check(bad.is_empty(), "the cockpit subtree must be visual only: %s" % [bad.slice(0, 6)])
	print("cockpit subtree: %d nodes, none physical, no shadow casters" % nodes.size())
	var tc := TrafficCar.new()
	tc.sim_only = true
	root.add_child(tc)
	_check(tc.find_children("*", "CockpitFrame", true, false).is_empty() and tc.find_children("Cockpit", "", true, false).is_empty(), "a traffic car must not get a cockpit")
	tc.queue_free()

func _physics_process(_delta: float) -> bool:
	tick += 1
	if tick == 1:
		_spawn()
		return false
	var since := tick - spawn_tick
	t = float(since) / 120.0
	if since == 3:
		var d := _describe(car)
		if pass_i == 0:
			bare = d
			print("mass %.0f kg, inertia %s, %d shapes, %d raycasts, layer %d mask %d" % [d.mass, d.phys_inertia, d.shapes.size(), d.raycasts, d.layer, d.mask])
		else:
			_check_cockpit()
			for key in bare:
				_check(bare[key] == d[key], "with the cockpit, %s differs: %s vs %s" % [key, bare[key], d[key]])
	if since < 4:
		return false
	var i := since - 4
	if pass_i == 0:
		pos_log.append(car.global_position)
		vel_log.append(car.linear_velocity)
	else:
		max_dpos = maxf(max_dpos, pos_log[i].distance_to(car.global_position))
		max_dvel = maxf(max_dvel, vel_log[i].distance_to(car.linear_velocity))
	if since == 400:
		_check(car.current_speed() > 10.0, "pass %d: the car should be moving (%.1f m/s)" % [pass_i, car.current_speed()])
	if since >= ticks_total:
		if pass_i == 0:
			print("bare pass: final speed %.1f m/s, travelled %.1f m" % [car.current_speed(), -car.global_position.z])
			car.driver = Callable()
			root.remove_child(car)
			car.free()
			pass_i = 1
			_spawn()
			return false
		print("20 s at 120 Hz, bare vs cockpit: max position difference %s m, max velocity difference %s m/s, final speed %.1f m/s" % [String.num_scientific(max_dpos), String.num_scientific(max_dvel), car.current_speed()])
		_check(max_dpos <= TOL, "trajectories differ by %s m (limit %s)" % [String.num_scientific(max_dpos), String.num_scientific(TOL)])
		_check(max_dvel <= TOL, "velocities differ by %s m/s" % String.num_scientific(max_dvel))
		return _end("")
	return false

func _check(ok: bool, msg: String) -> void:
	if not ok:
		failures.append(msg)

func _end(msg: String) -> bool:
	if msg != "":
		failures.append(msg)
	for f in failures:
		printerr("FAIL: ", f)
	print("cockpit_isolation: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
	return true
