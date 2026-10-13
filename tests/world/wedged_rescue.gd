extends SceneTree

# Wedged-car rescue (OffMapRescue.REASON_WEDGED, 2026-10-13). The fuzz runs
# (tests/core/fuzz_play.gd) left about one car in 80 jammed between the wall
# and a building front, where no gear or steering got it out and the release
# build has no put-back key. Now a car near a wall with the gas held that goes
# nowhere for OffMapRescue.WEDGE_S is put back at the kerb.
#
# Three cases, one boot:
# - nosed into the right-hand wall, gas held: rescued once, as "wedged",
#   within WEDGE_S plus the fade, and it ends up inside the walls
# - nosed into the wall, no gas: never rescued (a parked car stays put)
# - standing in a lane with gas and brake both held: never rescued (only near
#   a wall counts)
#   godot --headless --audio-driver Dummy --fixed-fps 120 --path . -s res://tests/world/wedged_rescue.gd

const Harness := preload("res://tests/traffic/traffic_harness.gd")
const TestDriver := preload("res://scripts/core/test_driver.gd")
const RATE := 120
const WAIT := OffMapRescue.WEDGE_S + 3.0

var logger := Harness.ErrorCounter.new()
var game: Node
var p: PlayerCar
var rescue: OffMapRescue
var fails: Array[String] = []
var cases := [
	{"name": "nosed into the wall, gas held", "wall": true, "gas": true, "brake": false, "rescued": true},
	{"name": "nosed into the wall, no gas", "wall": true, "gas": false, "brake": false, "rescued": false},
	{"name": "in a lane, gas and brake held", "wall": false, "gas": true, "brake": true, "rescued": false},
]
var at := -1
var tick := 0
var count_before := 0
var settling := false

func _initialize() -> void:
	OS.add_logger(logger)
	Engine.physics_ticks_per_second = RATE
	game = Harness.boot(self, 0, 300.0, 5)

func _physics_process(_delta: float) -> bool:
	if p == null:
		p = game.get("player")
		if p == null or not p.is_ready or Engine.get_physics_frames() < RATE:
			p = null
			return false
		rescue = game.rescue
		return _next()
	if settling:
		if rescue.phase == OffMapRescue.Phase.WATCH:
			settling = false
			return _next()
		return false
	tick += 1
	if rescue.count > count_before or tick >= int(WAIT * RATE):
		_judge()
		settling = true   # let a fade finish before the next case
	return false

func _next() -> bool:
	at += 1
	if at >= cases.size():
		return _end()
	var c: Dictionary = cases[at]
	tick = 0
	count_before = rescue.count
	p.engine_running = true
	if c.wall:
		if not _place_at_wall():
			fails.append("%s: found no clear spot by the wall" % c.name)
			return _next()
	else:
		TestDriver.place(p, Harness.lane_x(1), 0.0, 0.0, 0.0)
	p.driver = func(car: PlayerCar) -> void:
		car.throttle_input = 1.0 if c.gas else 0.0
		car.brake_input = 1.0 if c.brake else 0.0
		car.handbrake_input = 1.0 if c.brake else 0.0
		car.steering_input = 0.0
	return false

## Nose to the right-hand wall, a hand's width off it, on a stretch where
## nothing else stands in the car's footprint.
func _place_at_wall() -> bool:
	for step in 40:
		var u := RoadFrame.unroll(p.global_position)
		var z := u.z - 20.0 - 8.0 * step
		var b: Vector2 = rescue._bounds_at(z)
		if b == Vector2.ZERO:
			continue
		var x := b.x - 2.6
		var xf := RoadFrame.pose(x, 0.9, z, -PI / 2.0)
		var q := PhysicsShapeQueryParameters3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(2.2, 1.0, 4.9)
		q.shape = box
		q.transform = xf
		q.exclude = [p.get_rid()]
		if not p.get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty():
			continue
		TestDriver.place(p, x, -(z - u.z), PI / 2.0, 0.0)
		return true
	return false

func _judge() -> void:
	var c: Dictionary = cases[at]
	var got := rescue.count - count_before
	if c.rescued:
		if got != 1 or rescue.last_reason != OffMapRescue.REASON_WEDGED:
			fails.append("%s: expected one rescue as '%s', got %d (%s) in %.1f s" % [c.name, OffMapRescue.REASON_WEDGED, got, rescue.last_reason, tick / float(RATE)])
		elif tick > int((OffMapRescue.WEDGE_S + 1.5) * RATE):
			fails.append("%s: rescued only after %.1f s" % [c.name, tick / float(RATE)])
		else:
			print("%s: rescued after %.1f s" % [c.name, tick / float(RATE)])
	elif got != 0:
		fails.append("%s: rescued (%s) but should not be" % [c.name, rescue.last_reason])
	else:
		print("%s: left alone for %.0f s" % [c.name, WAIT])
	p.driver = Callable()

func _end() -> bool:
	if not logger.errors.is_empty():
		fails.append("%d engine errors, first: %s" % [logger.errors.size(), logger.errors[0]])
	for f in fails:
		printerr("FAIL: " + f)
	print("wedged_rescue: %s" % ("PASS" if fails.is_empty() else "FAIL (%d)" % fails.size()))
	quit(1 if not fails.is_empty() else 0)
	return true
