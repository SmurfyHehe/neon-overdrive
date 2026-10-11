extends SceneTree

# TrafficManager.flow turns the traffic round only once the player has done
# FLOW_FLIP m/s the other way for FLOW_FLIP_SECS (was: the instant it passed
# 6 m/s, so a quick reverse or a spin turned every spawn round). A bare
# manager with no cars and a body for the player, stepped by hand.
# - backing up at 25 km/h for 0.5 s: flow_flips unchanged;
# - two such bursts with a moment forward between them: still unchanged;
# - 20 km/h (under 6 m/s) for 5 s: nothing;
# - 25 km/h the other way held 1.5 s: one flip, and no second one after.
#   <godot> --headless --path . -s res://tests/traffic/flow_flip.gd

const HZ := 60.0

var failures: Array[String] = []
var traffic: TrafficManager
var player: RigidBody3D
var t := 0
var done := false

func _check(ok: bool, msg: String) -> void:
	if not ok:
		failures.append(msg)

func _initialize() -> void:
	player = RigidBody3D.new()
	player.gravity_scale = 0.0
	root.add_child(player)
	traffic = TrafficManager.new()
	traffic.sim_only = true
	traffic.car_count = 0
	traffic.player = player
	traffic.set_physics_process(false)   # stepped by hand below
	root.add_child(traffic)

## `seconds` at `kmh_z` along road z (+ = back up the road, against flow -1).
func _run(kmh_z: float, seconds: float) -> void:
	player.linear_velocity = Vector3(0, 0, kmh_z / 3.6)
	for i in int(seconds * HZ):
		traffic._physics_process(1.0 / HZ)

func _physics_process(_delta: float) -> bool:
	t += 1
	if t < 3 or done:
		return false
	done = true
	_check(traffic.flow == -1.0 and traffic.flow_flips == 0, "starts at flow %+.0f, %d flips" % [traffic.flow, traffic.flow_flips])
	_run(-60.0, 1.0)
	_run(25.0, 0.5)
	_check(traffic.flow_flips == 0 and traffic.flow == -1.0, "backing up at 25 km/h for 0.5 s: %d flips, flow %+.0f" % [traffic.flow_flips, traffic.flow])
	print("  25 km/h back for 0.5 s: flips %d, flow %+.0f" % [traffic.flow_flips, traffic.flow])
	_run(-30.0, 0.2)
	_run(25.0, 0.7)
	_check(traffic.flow_flips == 0, "two short bursts added up to a flip (%d)" % traffic.flow_flips)
	_run(-30.0, 0.2)
	_run(20.0, 5.0)
	_check(traffic.flow_flips == 0, "20 km/h back for 5 s flipped the flow (%d)" % traffic.flow_flips)
	print("  20 km/h back for 5 s: flips %d" % traffic.flow_flips)
	_run(-30.0, 0.2)
	_run(25.0, 1.5)
	_check(traffic.flow_flips == 1 and traffic.flow == 1.0, "25 km/h back held 1.5 s: %d flips, flow %+.0f" % [traffic.flow_flips, traffic.flow])
	print("  25 km/h back held 1.5 s: flips %d, flow %+.0f" % [traffic.flow_flips, traffic.flow])
	_run(25.0, 3.0)
	_check(traffic.flow_flips == 1, "kept flipping while going the new way (%d)" % traffic.flow_flips)
	for f in failures:
		printerr("FAIL: " + f)
	print("flow_flip: %s" % ("PASS" if failures.is_empty() else "FAIL (%d)" % failures.size()))
	quit(0 if failures.is_empty() else 1)
	return false
