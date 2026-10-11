extends SceneTree

# Cop alertness and the oncoming warning flash (more-alive MA4: K1 + T8).
# No game: a car and a parked cop with PoliceHeat stepped by hand at 60 Hz
# (as tests/traffic/police_rules.gd), and MomentSpots asked directly.
# - the table: each look's factor, half asleep only from 3 a.m., about one cop
#   in five sharp whatever it looks like, the same draw for the same key;
# - each look changes the time to judge speed by its factor (reading 1.6,
#   on break 1.3, bored 1.0, half asleep 2.0), and the time to notice an
#   offence that needs no judging by the extra of it;
# - no look adds a reason to react: at the traffic flow in front of the cop
#   nothing is seen as an offence, a look never makes a cop quicker, and the
#   same drive gives the same offences as with a plain cop;
# - a mismatched (sharp) cop uses the normal numbers;
# - the speed trap: a sharp cop clocks on the first look, a distracted one
#   after the extra of its factor;
# - the warning flash: about one trap in three, only from a shown oncoming car
#   200-400 m past the trap that the player can see ahead, at most once per
#   trap; a traffic car's flash_twice is two flashes;
# - the look on the car: a few meshes, no lights, replaced when re-dressed.
#   <godot> --headless --path . -s res://tests/traffic/cop_alertness.gd

const LOOKS := [CopAlertness.READING, CopAlertness.ON_BREAK, CopAlertness.BORED, CopAlertness.HALF_ASLEEP]
const WANT := {CopAlertness.READING: 1.6, CopAlertness.ON_BREAK: 1.3, CopAlertness.BORED: 1.0, CopAlertness.HALF_ASLEEP: 2.0}
const TICK := 1.0 / 60.0
const SLACK := 0.15   # s: the cop looks 10 times a second

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
var heat: PoliceHeat
var player: RigidBody3D
var cop: Node3D
var warnings := 0
var offences: Array[int] = []
var t := 0
var done := false

func _check(ok: bool, msg: String) -> void:
	if not ok:
		failures.append(msg)

func _initialize() -> void:
	player = RigidBody3D.new()
	player.gravity_scale = 0.0
	var c := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = Vector3(2, 1.4, 4)
	c.shape = b
	player.add_child(c)
	var lamp := Node3D.new()
	lamp.name = "Headlights"
	player.add_child(lamp)
	root.add_child(player)
	cop = Node3D.new()
	root.add_child(cop)
	heat = PoliceHeat.new()
	heat.player = player
	heat.area_override = "city"
	heat.set_physics_process(false)
	root.add_child(heat)
	heat.register_cop(cop)
	heat.warning_started.connect(func(_c: Node3D, _k: int) -> void: warnings += 1)
	heat.offence_seen.connect(func(k: int, _c: Node3D) -> void: offences.append(k))

func _physics_process(_delta: float) -> bool:
	t += 1
	if t < 3 or done:
		return false
	done = true
	_table()
	_judging()
	_no_new_reasons()
	_trap()
	_flash()
	_look_on_car()
	for f in failures:
		printerr("FAIL: " + f)
	print("cop_alertness: %s" % ("PASS" if failures.is_empty() else "FAIL (%d)" % failures.size()))
	quit(0 if failures.is_empty() else 1)
	return false

# ---------- helpers ----------

## The player at road x going -Z at `kmh`, lit; the parked cop 60 m ahead,
## facing the player.
func _setup(kmh: float) -> void:
	player.global_position = Vector3(2.0, 0, 0)
	player.linear_velocity = Vector3(0, 0, -kmh / 3.6)
	cop.rotation = Vector3(0, PI, 0)
	cop.global_position = Vector3(2.0, 0, -60.0)

## A fresh heat; the cop plain (look < SHARP's -1 is "no tag") or tagged.
func _fresh(tagged: bool, look := 0, sharp := false) -> void:
	heat.reset()
	heat._acc = 0.0   # every run starts on the same look tick
	heat.area_override = "city"
	heat.flow_kmh = Callable()
	heat.racing = false
	for m in [&"radar", &"parked", CopAlertness.META_LOOK, CopAlertness.META_DELAY, CopAlertness.META_HEAR]:
		if cop.has_meta(m):
			cop.remove_meta(m)
	if tagged:
		CopAlertness.tag(cop, look, sharp)
	warnings = 0
	offences.clear()

## Seconds until `until` is true (10 s at most; -1 = never).
func _time_to(until: Callable) -> float:
	for i in 600:
		heat._physics_process(TICK)
		if until.call():
			return float(i + 1) * TICK
	return -1.0

func _warned() -> bool:
	return heat.warning_active

func _wanted() -> bool:
	return heat.level >= PoliceHeat.TWO_CARS

# ---------- the table ----------

func _table() -> void:
	for look in LOOKS:
		_check(is_equal_approx(CopAlertness.delay_factor(look, false), WANT[look]), "%s: delay factor %s" % [CopAlertness.STATES[look].name, CopAlertness.delay_factor(look, false)])
		_check(CopAlertness.delay_factor(look, true) == 1.0 and CopAlertness.hear_factor(look, true) == 1.0, "%s: a sharp cop uses 1.0" % CopAlertness.STATES[look].name)
	_check(CopAlertness.hear_factor(CopAlertness.BORED, false) == 1.3, "bored hears 1.3x as far")
	_check(CopAlertness.hear_factor(CopAlertness.ON_BREAK, false) == 1.0, "on break hears at the normal range")
	_check(CopAlertness.delay_of(null) == 1.0 and CopAlertness.delay_of(cop) == 1.0, "an untagged cop is normal")
	_check(PoliceRules.judge_secs() == PoliceRules.JUDGE_SECS and PoliceRules.judge_secs(1.0, true) == 0.0, "the rulebook's own times are unchanged")
	_check(is_equal_approx(PoliceRules.judge_secs(1.6), 1.6) and is_equal_approx(PoliceRules.judge_secs(1.6, true), 0.6), "judge_secs with a factor")
	_check(PoliceRules.notice_secs() == 0.0 and is_equal_approx(PoliceRules.notice_secs(2.0), 1.0), "notice_secs")
	_check(PoliceRules.judge_secs(0.5) == PoliceRules.JUDGE_SECS and PoliceRules.notice_secs(0.5) == 0.0, "no factor makes a cop quicker than the rulebook")
	# The draw.
	var sharp := 0
	var asleep_early := 0
	var asleep_late := 0
	var seen := {}
	for key in 5000:
		var a := CopAlertness.pick(key, 22)
		var b := CopAlertness.pick(key, 22)
		if a.look != b.look or a.sharp != b.sharp:
			_check(false, "the draw for key %d changed" % key)
			break
		seen[a.look] = true
		if a.sharp:
			sharp += 1
		if a.look == CopAlertness.HALF_ASLEEP:
			asleep_early += 1
		for hour in [3, 4, 5]:
			if CopAlertness.pick(key, hour).look == CopAlertness.HALF_ASLEEP:
				asleep_late += 1
	_check(asleep_early == 0, "half asleep before 3 a.m.: %d" % asleep_early)
	_check(asleep_late > 2000, "half asleep from 3 a.m.: %d of 15000" % asleep_late)
	_check(CopAlertness.pick(7, 0).look != CopAlertness.HALF_ASLEEP and not CopAlertness.asleep_hour(2) and not CopAlertness.asleep_hour(6) and not CopAlertness.asleep_hour(20), "the asleep hours are 3, 4 and 5")
	_check(seen.size() == 3, "all three evening looks are drawn: %s" % [seen.keys()])
	_check(sharp > 800 and sharp < 1200, "about one cop in five is sharp: %d of 5000" % sharp)
	print("  draw: %d of 5000 sharp (%.1f%%)" % [sharp, sharp / 50.0])

# ---------- judging and noticing ----------

func _judging() -> void:
	# Speeding (a judged offence): 100 km/h in the city, the cop 60 m ahead.
	_fresh(false)
	_setup(100.0)
	var base := _time_to(_warned)
	_check(base > 0.0, "a plain cop warns a speeder")
	# Racing (no judging): noticed at once by a plain cop.
	_fresh(false)
	_setup(100.0)
	heat.racing = true
	var base_notice := _time_to(_wanted)
	_check(base_notice > 0.0 and base_notice <= 0.2, "a plain cop notices racing at once: %.2f s" % base_notice)
	for look in LOOKS:
		var n: String = CopAlertness.STATES[look].name
		var f: float = WANT[look]
		_fresh(true, look)
		_setup(100.0)
		var got := _time_to(_warned)
		_check(absf(got - PoliceRules.JUDGE_SECS * f) <= SLACK, "%s: judged in %.2f s, want %.2f s (%.1f s x %.1f)" % [n, got, PoliceRules.JUDGE_SECS * f, PoliceRules.JUDGE_SECS, f])
		_check(got >= base - 0.001, "%s is never quicker than a plain cop" % n)
		_check(offences == [PoliceRules.Offence.SPEEDING], "%s: the same offence as a plain cop: %s" % [n, offences])
		_fresh(true, look)
		_setup(100.0)
		heat.racing = true
		var noticed := _time_to(_wanted)
		_check(absf(noticed - (base_notice + (f - 1.0) * PoliceRules.JUDGE_SECS)) <= SLACK, "%s: noticed racing in %.2f s, want %.2f s" % [n, noticed, base_notice + (f - 1.0)])
		# The mismatched cop: looks the part, uses the normal numbers.
		_fresh(true, look, true)
		_setup(100.0)
		var sharp := _time_to(_warned)
		_check(is_equal_approx(sharp, base), "a sharp cop that looks %s: %.2f s, plain %.2f s" % [n, sharp, base])
		print("  %s: judged in %.2f s (plain %.2f), noticed racing in %.2f s (plain %.2f)" % [n, got, base, noticed, base_notice])
	# A radar car: at once when sharp, the extra only when distracted.
	_fresh(true, CopAlertness.HALF_ASLEEP)
	cop.set_meta(&"radar", true)
	_setup(100.0)
	heat._physics_process(0.1)
	_check(heat._judge_cop() == null, "a half asleep radar cop does not judge at once")
	_fresh(true, CopAlertness.HALF_ASLEEP, true)
	cop.set_meta(&"radar", true)
	_setup(100.0)
	heat._physics_process(0.1)
	_check(heat._judge_cop() == cop, "a sharp radar cop judges at once")

func _no_new_reasons() -> void:
	for look in LOOKS:
		var n: String = CopAlertness.STATES[look].name
		# At the flow of the fast lane, in front of the cop, for two minutes.
		_fresh(true, look)
		heat.flow_kmh = func() -> float: return 115.0
		_setup(115.0)
		for i in 120 * 60:
			heat._physics_process(TICK)
		_check(heat.seen, "%s: the cop saw the car (so the test means something)" % n)
		_check(heat.heat == 0.0 and warnings == 0 and offences.is_empty(), "%s: at the flow: heat %.2f warnings %d offences %s" % [n, heat.heat, warnings, offences])
		# Standing still beside it, lights on: nothing.
		_fresh(true, look)
		_setup(0.0)
		player.global_position = Vector3(2.0, 0, -55.0)
		for i in 30 * 60:
			heat._physics_process(TICK)
		_check(heat.heat == 0.0 and warnings == 0 and offences.is_empty(), "%s: standing by the cop: offences %s" % [n, offences])
		# Speeding behind a parked cop (no mirrors): unseen, so nothing.
		_fresh(true, look)
		_setup(160.0)
		cop.rotation = Vector3.ZERO
		for i in 30 * 60:
			heat._physics_process(TICK)
		_check(not heat.seen and heat.heat == 0.0 and offences.is_empty(), "%s: unseen behind it: seen %s offences %s" % [n, heat.seen, offences])

# ---------- the speed trap ----------

## Looks at a trap 50 m ahead of a lit car at 100 km/h until it clocks;
## returns the looks it took (0 = never in 5 s).
func _trap_looks(m: MomentSpots, look: int, sharp: bool) -> int:
	var spot := {"chunk": 4, "card": "speed_trap", "fired": false, "look": look, "sharp": sharp}
	var s := 4.0 * RoadChunkBuilder.CHUNK_LEN + MomentSpots.TRAP_Z - 50.0
	for i in 50:
		m._watch_trap(spot, s, 5.0)
		if spot.fired:
			return i + 1
	return 0

func _trap() -> void:
	var car := FakeCar.new()
	car.speed = 100.0 / 3.6
	var m := MomentSpots.new()
	m.player = car
	var clocks := [0]
	m.clocked.connect(func(_k: float, _c: Node3D) -> void: clocks[0] += 1)
	_check(_trap_looks(m, CopAlertness.READING, true) == 1, "a sharp trap cop clocks on the first look")
	for look in LOOKS:
		var want := 1 + roundi((WANT[look] - 1.0) / MomentSpots.CHECK_EVERY)
		var got := _trap_looks(m, look, false)
		_check(got == want, "%s trap cop: clocked on look %d, want %d" % [CopAlertness.STATES[look].name, got, want])
	_check(clocks[0] == LOOKS.size() + 1, "every trap clocked once: %d" % clocks[0])
	# Under the line: no look ever clocks, whatever the cop is doing.
	car.speed = 60.0 / 3.6
	clocks[0] = 0
	for look in LOOKS:
		_check(_trap_looks(m, look, false) == 0, "%s trap cop leaves a car under the line alone" % CopAlertness.STATES[look].name)
	_check(clocks[0] == 0, "nothing clocked under the line")
	# Tonight's look is drawn once and kept.
	var spot := {"chunk": 9, "card": "speed_trap", "fired": false}
	m.road_seed = 77
	m._alertness(spot)
	var first: int = spot.look
	m._alertness(spot)
	_check(spot.look == first and spot.has("sharp"), "a trap keeps its look for the night")
	m.free()
	car.free()

# ---------- the oncoming warning flash ----------

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

# ---------- the look on the car ----------

func _count(n: Node, lights: Array) -> int:
	var meshes := 0
	for c in n.get_children():
		if c is MeshInstance3D:
			meshes += 1
		if c is Light3D:
			lights.append(c)
		meshes += _count(c, lights)
	return meshes

func _look_on_car() -> void:
	var car := Node3D.new()
	for look in LOOKS:
		CopAlertness.dress(car, MomentSpots.TRAP_KIND, look)
		var lights := []
		var n := car.get_node_or_null(CopAlertness.LOOK_NODE)
		_check(n != null and car.get_child_count() == 1, "%s: one look node on the car" % CopAlertness.STATES[look].name)
		if n != null:
			var meshes := _count(n, lights)
			_check(meshes >= 1 and meshes <= 4 and lights.is_empty(), "%s: %d meshes, %d lights" % [CopAlertness.STATES[look].name, meshes, lights.size()])
	CopAlertness.dress(car, MomentSpots.TRAP_KIND, CopAlertness.SHARP)
	_check(car.get_child_count() == 0, "no look: nothing on the car")
	car.free()
