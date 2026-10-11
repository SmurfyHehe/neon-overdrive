extends SceneTree

# Police P3: the amber mark on the cockpit speedo sits at the speed the police
# act on in the area the car is in (PoliceRules' offence line: 85 km/h in a
# city district, 125 on a highway stretch) and moves when the car drives into
# another area. Headless:
#   <godot> --headless --audio-driver Dummy --path . -s res://tests/view/limit_tick.gd

const RoadMap := preload("res://scripts/world/road_map.gd")
const TIMEOUT_TICKS := 60 * 30

var tick := 0
var step := 0
var step_start := 0
var failures: Array[String] = []
var city_angle := 0.0

func _initialize() -> void:
	OS.set_environment("NEON_TRAFFIC", "0")
	OS.set_environment("NEON_POLICE", "0")
	change_scene_to_file("res://Game.tscn")

func _check(ok: bool, msg: String) -> void:
	if not ok:
		failures.append(msg)

func _area(p: PlayerCar) -> String:
	return PoliceRules.area_at(RoadFrame.s_at(RoadFrame.unroll(p.global_position).z))

## Where on the dial `kmh` is, as the needle's rotation.
func _angle(frame: CockpitFrame, kmh: float) -> float:
	return deg_to_rad(frame.dial_sweep * 0.5 - frame.dial_sweep * kmh / float(frame.cab.speedo_max_kmh))

func _physics_process(_delta: float) -> bool:
	tick += 1
	var game := current_scene
	if game == null or game.get("player") == null or game.get("camera") == null:
		if tick > TIMEOUT_TICKS:
			_check(false, "Game never became ready")
			return _end()
		return false
	var p: PlayerCar = game.player
	var cam: ChaseCamera = game.camera
	var frame: CockpitFrame = cam.frame
	p.driver = func(c: PlayerCar) -> void:
		c.throttle_input = 0.0
		c.brake_input = 1.0
		c.steering_input = 0.0
	match step:
		0:
			_check(RoadMap.period > 0, "the game is not on a mapped road")
			cam.set_view(ChaseCamera.View.COCKPIT)
			step = 1
			step_start = tick
		1:
			if tick - step_start < 60:
				return false
			var tick_node := frame.limit_tick
			_check(tick_node != null and tick_node.get_parent() == frame, "no LimitTick on the cockpit frame")
			if tick_node == null:
				return _end()
			_check(_area(p) == PoliceRules.CITY, "the drive starts in '%s', the test expects a city" % _area(p))
			var line := PoliceRules.offence_line(PoliceRules.CITY, false)
			_check(is_equal_approx(frame.limit_kmh, line), "city: the mark is at %.0f km/h, the offence line is %.0f" % [frame.limit_kmh, line])
			_check(tick_node.visible, "city: the mark is hidden")
			_check(absf(tick_node.rotation.z - _angle(frame, line)) < 0.001, "city: the mark's angle is %.3f, %.0f km/h on this dial is %.3f" % [tick_node.rotation.z, line, _angle(frame, line)])
			_check(tick_node.position.distance_to(frame.speedo_needle.position) < 0.01, "the mark's pivot is not the speedo's (%.3f m apart)" % tick_node.position.distance_to(frame.speedo_needle.position))
			city_angle = tick_node.rotation.z
			# on to the first highway stretch: the map's first district whose area is highway
			var n := 0
			while n < RoadMap.district_count() and String(RoadMap.district_info(n).area) != PoliceRules.HIGHWAY:
				n += 1
			_check(n < RoadMap.district_count(), "the map has no highway stretch")
			var s := RoadMap.district_start(n) + 120.0
			var u := RoadFrame.unroll(p.global_position)
			var z := float(RoadFrame.origin_index) * RoadMap.L - s
			p.global_transform = RoadFrame.pose(u.x, p.global_position.y - RoadFrame.roll(Vector3(u.x, 0.0, u.z)).y, z, 0.0)
			p.linear_velocity = Vector3.ZERO
			p.angular_velocity = Vector3.ZERO
			step = 2
			step_start = tick
		2:
			if tick - step_start < 90:
				return false
			_check(_area(p) == PoliceRules.HIGHWAY, "the car was moved to '%s', not a highway" % _area(p))
			var line := PoliceRules.offence_line(PoliceRules.HIGHWAY, false)
			_check(is_equal_approx(frame.limit_kmh, line), "highway: the mark is at %.0f km/h, the offence line is %.0f" % [frame.limit_kmh, line])
			_check(absf(frame.limit_tick.rotation.z - _angle(frame, line)) < 0.001, "highway: the mark's angle is %.3f, expected %.3f" % [frame.limit_tick.rotation.z, _angle(frame, line)])
			_check(frame.limit_tick.rotation.z < city_angle - 0.05, "the mark did not move up the dial from the city to the highway")
			print("limit_tick: city %.0f km/h, highway %.0f km/h on a %d km/h dial" % [PoliceRules.offence_line(PoliceRules.CITY, false), line, int(frame.cab.speedo_max_kmh)])
			return _end()
	return false

func _end() -> bool:
	for f in failures:
		printerr("FAIL: " + f)
	print("limit_tick: %s" % ("PASS" if failures.is_empty() else "FAIL (%d)" % failures.size()))
	quit(0 if failures.is_empty() else 1)
	return true
