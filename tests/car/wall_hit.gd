extends SceneTree

# Wall-hit test (2026-10-07, Roy: hitting the out-of-bounds walls bugs the car
# out and he has to reset). Drives the player across the shoulder, curb and
# sidewalk into the right-hand out-of-bounds wall (#28/#114) at several speeds
# and angles, one scenario after another in one boot.
#
# What was wrong:
# - wheel rays could land on the wall face once the car leaned into it, and
#   the springs pushed the car up the wall (CarSpec.WALL_LAYER);
# - the chassis box, ~4 cm off the road, hit the 15 cm kerb ramp like a ski
#   jump, so at speed the car reached the wall airborne (CarSpec.KERB_LAYER);
# - the wall meets the chassis box ~0.9 m above the very low centre of mass,
#   so a hit rolled or pitched the car onto its side or roof
#   (PlayerCar.WALL_TILT_RATE).
#
# Each scenario: the car starts on the shoulder side of the road, yawed
# `angle` degrees toward the wall, launched at `speed` m/s, full throttle and
# the wheel straight, for RUN_SECS. Asserts (exit code 1 on failure), each
# scenario:
# - the car reached the wall (it is a real test of a hit)
# - it never goes through the wall
# - it stays near upright (tilt under MAX_TILT; main reached 120 deg)
# - it gains no speed from the wall: after contact |v| never jumps by more
#   than MAX_KICK in one tick (full throttle is ~0.05 m/s per tick)
# - it ends the run back on its wheels: over the last END_SECS it stays under
#   END_TILT and has at least three wheels on the ground at some tick (parked
#   against the wall, one wheel can hang over the 0.5 m gap between the
#   sidewalk and the wall; still at full throttle it can be hopping the curb on
#   any single tick), so the player drives off without a reset
# - every number stays finite
# NEON_WALL_ONLY="55,30" runs one scenario; NEON_WALL_LOG=1 prints each tick.
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --fixed-fps 120 --path . -s res://tests/car/wall_hit.gd

const Harness := preload("res://tests/traffic/traffic_harness.gd")

const SPEEDS := [8.0, 20.0, 35.0, 55.0]  # m/s (29 to 198 km/h)
const ANGLES := [10.0, 30.0, 60.0, 89.0]  # degrees toward the wall
const RUN_SECS := 4.0
const START_GAP := 4.6  # m from the wall: on the shoulder, clear of the curb and sidewalk
const MAX_TILT := 30.0  # degrees from upright (all scenarios peak under 13 now)
const MAX_KICK := 1.5  # m/s in one tick
const END_TILT := 15.0  # degrees: back on its wheels at the end
const END_SECS := 0.5  # the end check covers this last stretch of the run

var rate := 120
var logger := Harness.ErrorCounter.new()
var game: Node
var tick := 0
var fails: Array[String] = []
var log_ticks := false

var scenarios: Array = []
var index := -1
var run_tick := 0
var rest_y := 0.0
var wall_x := 0.0
var prev_speed := 0.0
var s := {}

func _initialize() -> void:
	OS.add_logger(logger)
	ExhaustTune.save_path = "user://autotune/test_wall_hit_exhaust.json"
	Engine.physics_ticks_per_second = rate
	log_ticks = OS.get_environment("NEON_WALL_LOG") == "1"
	var only := OS.get_environment("NEON_WALL_ONLY")
	for v in SPEEDS:
		for a in ANGLES:
			if only == "" or only == "%d,%d" % [v, a]:
				scenarios.append([v, a])
	game = Harness.boot(self, 0, 300.0, 4242)

func _find(n: Node, name: String, out: Array) -> void:
	if n.name == name:
		out.append(n)
	for c in n.get_children():
		_find(c, name, out)

## The inner face of the right-hand wall nearest the car's z.
func _wall_face(p: PlayerCar) -> float:
	var found := []
	_find(game, "BoundaryOwn", found)
	var best := INF
	var best_dz := INF
	# The wall is one box per centreline station (#37), each placed by its own
	# CollisionShape3D transform; the body itself sits at the chunk origin.
	for b in found:
		for c in (b as Node).get_children():
			var col := c as CollisionShape3D
			if col == null:
				continue
			var box := col.shape as BoxShape3D
			var dz := absf(col.global_position.z - p.global_position.z)
			if dz < box.size.z / 2.0 + 1.0 and dz < best_dz:
				best_dz = dz
				best = col.global_position.x - box.size.x / 2.0
	return best

func _start(p: PlayerCar) -> void:
	var v: float = scenarios[index][0]
	var a: float = scenarios[index][1]
	# Arrive about 0.8 s after the launch: up to speed in a straight line, and a
	# shallow angle does not need a 100 m run-up. Always start on the road, so
	# the car crosses the curb and sidewalk on the way, as it does in the game.
	wall_x = _wall_face(p)
	var gap := clampf(v * sin(deg_to_rad(a)) * 0.8, START_GAP, wall_x - Harness.lane_x(0))
	var pos := Vector3(wall_x - gap, rest_y, p.global_position.z)
	p.global_transform = Transform3D(Basis(Vector3.UP, -deg_to_rad(a)), pos)
	p.angular_velocity = Vector3.ZERO
	TrafficCar.set_moving(p, v)
	p.reset_physics_interpolation()
	run_tick = 0
	prev_speed = v
	s = {"speed": v, "angle": a, "hit": false, "through": false, "tilt": 0.0, "kick": 0.0,
		"end_tilt": 0.0, "end_wheels": 0, "finite": true}
	# end_tilt is the worst and end_wheels the most over the last END_SECS

func _physics_process(_delta: float) -> bool:
	var p: PlayerCar = game.get("player")
	tick += 1
	if tick < rate:  # settle on the springs first
		return false
	if tick == rate:
		rest_y = p.global_position.y
		p.driver = func(c: Vehicle) -> void:
			c.steering_input = 0.0
			c.throttle_input = 1.0
			c.brake_input = 0.0
			c.handbrake_input = 0.0
		index = 0
		_start(p)
		return false
	run_tick += 1
	if not Harness.finite(p):
		s.finite = false
	else:
		wall_x = _wall_face(p)
		var b := p.global_transform.basis
		var tilt := rad_to_deg(b.y.angle_to(Vector3.UP))
		s.tilt = maxf(s.tilt, tilt)
		# Any corner of the 1.6 x 3.4 m footprint within 5 cm of the wall face.
		var reach := 0.8 * absf(b.x.x) + 1.7 * absf(b.z.x)
		var speed := p.linear_velocity.length()
		if s.hit:
			s.kick = maxf(s.kick, speed - prev_speed)
		elif p.global_position.x + reach >= wall_x - 0.05:
			s.hit = true
		prev_speed = speed
		if p.global_position.x > wall_x + 0.5:
			s.through = true
		if log_ticks:
			print("  %s t=%.2f x=%.2f wall=%.2f y=%.2f tilt=%.0f v=%.1f vx=%.1f vy=%.1f w=(%.1f %.1f %.1f)" % ["H" if s.hit else "-", run_tick / float(rate), p.global_position.x, wall_x, p.global_position.y, tilt, speed, p.linear_velocity.x, p.linear_velocity.y, p.angular_velocity.x, p.angular_velocity.y, p.angular_velocity.z])
	if s.finite and run_tick > int((RUN_SECS - END_SECS) * rate):
		s.end_tilt = maxf(s.end_tilt, rad_to_deg(p.global_transform.basis.y.angle_to(Vector3.UP)))
		var down := 0
		for w in p.wheel_array:
			if (w as Wheel).is_colliding():
				down += 1
		s.end_wheels = maxi(s.end_wheels, down)
	if run_tick >= int(RUN_SECS * rate) or not s.finite:
		_report()
		index += 1
		if index >= scenarios.size():
			return _end()
		_start(p)
	return false

func _report() -> void:
	var name := "%2.0f m/s at %2.0f deg" % [s.speed, s.angle]
	var bad: Array[String] = []
	if not s.finite:
		bad.append("non-finite state")
	if not s.hit:
		bad.append("never reached the wall")
	if s.through:
		bad.append("went through the wall")
	if s.tilt > MAX_TILT:
		bad.append("rolled to %.0f deg" % s.tilt)
	if s.kick > MAX_KICK:
		bad.append("gained %.1f m/s in one tick" % s.kick)
	if s.end_tilt > END_TILT or s.end_wheels < 3:
		bad.append("not back on its wheels (tilt %.0f deg, %d wheels down)" % [s.end_tilt, s.end_wheels])
	print("%s: peak tilt %5.1f deg, biggest one-tick speed gain %4.2f m/s, end tilt %4.1f deg, %d wheels down  %s" % [name, s.tilt, s.kick, s.end_tilt, s.end_wheels, "ok" if bad.is_empty() else "FAIL " + ", ".join(bad)])
	for b in bad:
		fails.append("%s: %s" % [name, b])

func _end() -> bool:
	if logger.errors.size() > 0:
		fails.append("%d engine error(s): %s" % [logger.errors.size(), logger.errors[0]])
	print("wall_hit: %s" % ("PASS" if fails.is_empty() else "%d failure(s)" % fails.size()))
	quit(0 if fails.is_empty() else 1)
	return true
