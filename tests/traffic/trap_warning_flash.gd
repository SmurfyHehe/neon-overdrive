extends SceneTree

# The oncoming warning flash before a speed trap (more-alive MA4, T8).
# No game: MomentSpots asked directly, with stand-in oncoming cars.
# - about one trap in three is given away, the same traps for a seed and night;
# - only a shown oncoming car 200-400 m past the trap that the player can see
#   ahead flashes; never a car going the player's way, a benched or hidden one;
# - at most once per trap, and never once the trap is closer than the band;
# - a trap that is not given away gets no flash;
# - the trap itself is unchanged: it clocks a lit speeder on the first look
#   and leaves a car under the line alone;
# - a traffic car's flash_twice is two flashes.
#   <godot> --headless --path . -s res://tests/traffic/trap_warning_flash.gd

const TICK := 1.0 / 60.0

class FakeCar extends Node3D:
	var speed := 0.0
	var headlights_on := true
	func current_speed() -> float:
		return speed

class Oncoming extends RefCounted:
	var direction := 1.0
	var benched := false
	var shown := true
	var z := 0.0
	var flashed := 0
	func road_z() -> float:
		return z
	func flash_twice() -> void:
		flashed += 1

var failures: Array[String] = []
var t := 0
var done := false

func _check(ok: bool, msg: String) -> void:
	if not ok:
		failures.append(msg)

func _physics_process(_delta: float) -> bool:
	t += 1
	if t < 3 or done:
		return false
	done = true
	_flash()
	_trap()
	for f in failures:
		printerr("FAIL: " + f)
	print("trap_warning_flash: %s" % ("PASS" if failures.is_empty() else "FAIL (%d)" % failures.size()))
	quit(0 if failures.is_empty() else 1)
	return false

## The trap clocks as it always did: at once, and only over the line.
func _trap() -> void:
	var car := FakeCar.new()
	car.speed = 100.0 / 3.6
	var m := MomentSpots.new()
	m.player = car
	var clocks := [0]
	m.clocked.connect(func(_k: float, _c: Node3D) -> void: clocks[0] += 1)
	var s := 4.0 * RoadChunkBuilder.CHUNK_LEN + MomentSpots.TRAP_Z - 50.0
	var spot := {"chunk": 4, "card": "speed_trap", "fired": false}
	m._watch_trap(spot, s, 5.0)
	_check(spot.fired and clocks[0] == 1, "the trap clocks a lit speeder on the first look")
	car.speed = 60.0 / 3.6
	var slow := {"chunk": 4, "card": "speed_trap", "fired": false}
	for i in 50:
		m._watch_trap(slow, s, 5.0)
	_check(not slow.fired and clocks[0] == 1, "the trap leaves a car under the line alone")
	m.free()
	car.free()

func _flash() -> void:
	_check(is_equal_approx(RoadFrame.s_at(-100.0), 100.0), "this test's road: 100 m along is z = -100")
	var chunk := 20
	var trap_s := float(chunk) * RoadChunkBuilder.CHUNK_LEN + MomentSpots.TRAP_Z
	var yes := -1
	var no := -1
	var warned := 0
	for sd in 3000:
		if MomentSpots.trap_warned(sd, 1, chunk):
			warned += 1
			if yes < 0:
				yes = sd
		elif no < 0:
			no = sd
	_check(warned > 850 and warned < 1150, "about one trap in three is given away: %d of 3000" % warned)
	print("  flash: %d of 3000 traps given away (%.1f%%)" % [warned, warned / 30.0])
	var m := MomentSpots.new()
	m.road_seed = yes
	var spot := {"chunk": chunk, "card": "speed_trap", "fired": false}
	var same_way := Oncoming.new()
	same_way.direction = -1.0
	same_way.z = -(trap_s - 300.0)
	var benched := Oncoming.new()
	benched.benched = true
	benched.z = -(trap_s - 300.0)
	var hidden := Oncoming.new()
	hidden.shown = false
	hidden.z = -(trap_s - 300.0)
	var too_near := Oncoming.new()
	too_near.z = -(trap_s - 150.0)
	var too_far := Oncoming.new()
	too_far.z = -(trap_s - 450.0)
	var good := Oncoming.new()
	good.z = -(trap_s - 300.0)
	var also_good := Oncoming.new()
	also_good.z = -(trap_s - 280.0)
	var cars := [same_way, benched, hidden, too_near, too_far, good, also_good]
	# The player too far back to see the car in the band: nobody flashes.
	_check(m.oncoming_flash(spot, trap_s - 600.0, trap_s, cars, -1.0) == null, "no flash from a car the player cannot see yet")
	_check(m.oncoming_flash(spot, trap_s - 420.0, trap_s, [same_way, benched, hidden, too_near, too_far], -1.0) == null, "only a shown oncoming car 200-400 m past the trap flashes")
	_check(m.oncoming_flash(spot, trap_s - 420.0, trap_s, cars, -1.0) == good, "the oncoming car in the band flashes")
	_check(good.flashed == 1 and also_good.flashed == 0, "one car flashes: %d + %d" % [good.flashed, also_good.flashed])
	for i in 200:
		m.oncoming_flash(spot, trap_s - 420.0 + float(i), trap_s, cars, -1.0)
	var total := 0
	for c in cars:
		total += c.flashed
	_check(total == 1 and m.flashes == 1, "at most one flash per trap: %d" % total)
	# Too late: the player inside 200 m of the trap gets no flash.
	var late := {"chunk": chunk, "card": "speed_trap", "fired": false}
	_check(m.oncoming_flash(late, trap_s - 150.0, trap_s, cars, -1.0) == null and not late.get("flashed", false), "no flash once the trap is closer than the band")
	# A trap that is not given away tonight.
	m.road_seed = no
	var quiet := {"chunk": chunk, "card": "speed_trap", "fired": false}
	for i in 400:
		m.oncoming_flash(quiet, trap_s - 600.0 + float(i), trap_s, cars, -1.0)
	_check(good.flashed == 1 and m.flashes == 1, "a trap that is not given away gets no flash")
	m.free()
	# The real traffic car: two flashes, no more.
	var tc := TrafficCar.new()
	tc.flash_twice()
	tc.flash_twice()
	for i in 120:
		if tc._flash_t >= 0.0:
			tc._flash_step(TICK)
	_check(tc.head_flashes == 2 and not tc._flash_on and tc._flash_t < 0.0, "flash_twice is two flashes: %d" % tc.head_flashes)
	tc.free()
