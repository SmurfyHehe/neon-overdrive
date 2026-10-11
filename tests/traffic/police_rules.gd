extends SceneTree

# The police rulebook, P1 (scripts/traffic/police_rules.gd) and the warning
# step, P2 (scripts/traffic/police_heat.gd). No game: its own little world
# (a car and a cop), PoliceHeat stepped by hand at 60 Hz.
# - the table: limits, offence lines, crackdown, highway, flow exemption,
#   flagrant, reach, cone, mirrors, drop times, fault test, offence heats;
# - P1 proof: driving at the traffic flow in every lane (115/100/85/70 km/h)
#   for 10 minutes in front of a cop gets 0 heat and no warning; the same
#   lanes 30 km/h over the flow get a warning, then heat 1;
# - P2 proof: back under the line inside 5 s clears with no heat; ignoring
#   gives heat 1; no second warning inside 2 minutes; the loudspeaker speaks
#   once a night (city / highway wording);
# - unseen is never an offence; a radar car judges at once, dark, at 120 m;
#   a parked cop has no mirrors; contacts (touch / ram); wrong side; racing;
#   crackdown line; flagrant +1 held.
#   <godot> --headless --path . -s res://tests/traffic/police_rules.gd

var failures: Array[String] = []
var heat: PoliceHeat
var player: RigidBody3D
var cop: Node3D
var warnings := 0
var ended: Array[bool] = []
var lines: Array[String] = []
var t := 0
var done := false

func _check(ok: bool, msg: String) -> void:
	if not ok:
		failures.append(msg)

func _initialize() -> void:
	_table()
	player = RigidBody3D.new()
	player.gravity_scale = 0.0
	var c := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = Vector3(2, 1.4, 4)
	c.shape = b
	player.add_child(c)
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
	heat.warning_ended.connect(func(ok: bool) -> void: ended.append(ok))
	heat.line_said.connect(func(s: String) -> void: lines.append(s))

func _table() -> void:
	_check(PoliceRules.posted_limit("city") == 60.0 and PoliceRules.posted_limit("highway") == 100.0, "posted limits")
	_check(PoliceRules.offence_line("city", false) == 85.0 and PoliceRules.offence_line("highway", false) == 125.0, "offence lines")
	_check(PoliceRules.offence_line("city", true) == 70.0 and PoliceRules.offence_line("highway", true) == 110.0, "crackdown lines")
	_check(PoliceRules.is_speeding(86.0, "city", false) and not PoliceRules.is_speeding(85.0, "city", false), "city line edge")
	_check(PoliceRules.is_speeding(75.0, "city", true) and not PoliceRules.is_speeding(75.0, "city", false), "crackdown line")
	_check(not PoliceRules.is_speeding(115.0, "city", false, 115.0), "flow in the fast lane is never speeding")
	_check(PoliceRules.is_speeding(130.0, "city", false, 115.0), "30 over the flow is speeding")
	_check(PoliceRules.is_flagrant(120.0, "city") and not PoliceRules.is_flagrant(119.0, "city") and PoliceRules.is_flagrant(160.0, "highway"), "flagrant 60 over posted")
	_check(PoliceRules.area_at(0.0) == "city", "no map = city")
	var lit := PoliceRules.reach(1, false)
	_check(lit == 140.0 and PoliceRules.reach(2, false) == 200.0 and PoliceRules.reach(0, false) == 18.0 and PoliceRules.reach(0, true) == 40.0, "reach: low %.0f" % lit)
	var xf := Transform3D.IDENTITY   # faces -Z
	_check(PoliceRules.in_cone(xf, Vector3(0, 0, -100), 140.0), "cone: 100 m dead ahead")
	_check(not PoliceRules.in_cone(xf, Vector3(0, 0, -150), 140.0), "cone: past the reach")
	_check(PoliceRules.in_cone(xf, Vector3(86, 0, -50), 140.0), "cone: 59 deg off, inside")
	_check(not PoliceRules.in_cone(xf, Vector3(100, 0, -50), 140.0), "cone: 63 deg off, outside")
	_check(not PoliceRules.in_cone(xf, Vector3(0, 0, 30), 140.0) and PoliceRules.in_cone(xf, Vector3(0, 0, 30), 140.0, true), "mirrors only when asked, 30 m behind")
	_check(not PoliceRules.in_cone(xf, Vector3(0, 0, 60), 140.0, true), "mirrors reach 45 m, not 60")
	_check(PoliceRules.drop_after(1, false) == 30.0 and PoliceRules.drop_after(2, false) == 60.0 and PoliceRules.drop_after(3, false) == 90.0
		and PoliceRules.drop_after(4, false) == 120.0 and PoliceRules.drop_after(5, false) == 180.0 and PoliceRules.drop_after(5, true) == 90.0, "drop times")
	var o := PoliceRules.OFFENCES
	_check(o[PoliceRules.Offence.RACING].heat == 2 and not o[PoliceRules.Offence.RACING].warn, "racing is heat 2, no warning")
	_check(o[PoliceRules.Offence.RAM_COP].heat == 4 and not o[PoliceRules.Offence.RAM_COP].warn, "ramming is heat 4, no warning")
	_check(o[PoliceRules.Offence.TOUCH_COP].warn and o[PoliceRules.Offence.SPEEDING].warn and o[PoliceRules.Offence.WRONG_SIDE].warn and o[PoliceRules.Offence.RED_LIGHT].warn, "soft offences warn")
	_check(not o[PoliceRules.Offence.CRASH].warn and o[PoliceRules.Offence.HIT_AND_RUN].get("add", false) and o[PoliceRules.Offence.MEDIAN_GAP].get("add", false), "crash no warning; hit and run, gap are +1")
	# Fault: behind and faster = yours; your centre moved into their lane = yours;
	# in front, or slower, or already in the lane a second ago = not.
	_check(PoliceRules.player_at_fault(8.0, 30.0, 20.0, 5.0, 5.0, 5.0, 1.6), "fault: behind and faster")
	_check(not PoliceRules.player_at_fault(8.0, 20.0, 30.0, 5.0, 5.0, 5.0, 1.6), "no fault: behind but slower (they braked into you? no, they pulled away)")
	_check(not PoliceRules.player_at_fault(-8.0, 30.0, 20.0, 5.0, 5.0, 5.0, 1.6), "no fault: they are behind you")
	_check(PoliceRules.player_at_fault(-3.0, 20.0, 25.0, 5.0, 8.5, 5.0, 1.6), "fault: moved into their lane in the last second")
	_check(not PoliceRules.player_at_fault(-3.0, 20.0, 25.0, 5.0, 5.0, 5.0, 1.6), "no fault: already in the lane")

## The player at road x, going -Z at `kmh`; lights lit; the cop `dist` m ahead
## facing the player (rotated half a turn), at rest.
func _setup(kmh: float, x := 2.0, lit := true, dist := 60.0) -> void:
	player.global_position = Vector3(x, 0, 0)
	player.linear_velocity = Vector3(0, 0, -kmh / 3.6)
	var lamp := player.get_node_or_null("Headlights") as Node3D
	if lamp == null:
		lamp = Node3D.new()
		lamp.name = "Headlights"
		player.add_child(lamp)
	lamp.visible = lit
	cop.rotation = Vector3(0, PI, 0)
	cop.global_position = Vector3(x, 0, -dist)

func _speed(kmh: float) -> void:
	player.linear_velocity = Vector3(0, 0, -kmh / 3.6)

func _run(seconds: float) -> void:
	for i in int(seconds * 60.0):
		heat._physics_process(1.0 / 60.0)

func _fresh() -> void:
	heat.reset()
	heat.area_override = "city"
	heat.flow_kmh = Callable()
	heat.world_mood = null
	heat.racing = false
	for m in [&"radar", &"parked"]:
		if cop.has_meta(m):
			cop.remove_meta(m)
	warnings = 0
	ended.clear()
	lines.clear()

func _physics_process(_delta: float) -> bool:
	t += 1
	if t < 3 or done:
		return false
	done = true
	_scenarios()
	for f in failures:
		printerr("FAIL: " + f)
	print("police_rules: %s" % ("PASS" if failures.is_empty() else "FAIL (%d)" % failures.size()))
	quit(0 if failures.is_empty() else 1)
	return false

func _scenarios() -> void:
	# P1 proof: at the flow in every lane for 10 minutes, 0 heat, no warning.
	_fresh()
	var flows := [115.0, 100.0, 85.0, 70.0]
	var cur := [115.0]
	heat.flow_kmh = func() -> float: return cur[0]
	_setup(115.0)
	for lane in 4:
		cur[0] = flows[lane]
		_speed(flows[lane])
		_run(150.0)
		_check(heat.level == PoliceHeat.NONE and warnings == 0, "flow in lane %d (%.0f km/h): level %d, warnings %d" % [lane, flows[lane], heat.level, warnings])
	_check(heat.heat == 0.0 and not lines.has(PoliceHeat.MOCK_LINE) and not lines.has(PoliceRules.WARN_LINES["city"]), "10 min at the flow: heat %.2f lines %s" % [heat.heat, lines])
	_check(heat.seen, "the cop saw the car the whole time (so the test means something)")
	# +30 over the flow, in each lane: a warning, then heat 1.
	for lane in 4:
		_fresh()
		cur[0] = flows[lane]
		heat.flow_kmh = func() -> float: return cur[0]
		_setup(flows[lane] + 30.0)
		_run(1.6)
		_check(heat.warning_active and heat.level == PoliceHeat.NONE, "lane %d at +30: warning %s level %d at 1.6 s" % [lane, heat.warning_active, heat.level])
		_run(PoliceRules.WARN_SECS + 0.2)
		# Lanes 0 and 1 at +30 are 60+ over the posted limit: flagrant, and
		# held 5 s that is the extra +1.
		var want := PoliceHeat.TWO_CARS if flows[lane] + 30.0 >= 120.0 else PoliceHeat.ONE_CAR
		_check(heat.level == want and ended == [false], "lane %d at +30: level %d after the warning (want %d), ended %s" % [lane, heat.level, want, ended])
	# P2: complying inside 5 s, the loudspeaker once, no second warning in 2 min.
	_fresh()
	_setup(100.0)
	_run(1.6)
	_check(heat.warning_active and warnings == 1, "100 km/h in the city: warning %s" % heat.warning_active)
	_check(lines.has(PoliceRules.WARN_LINES["city"]), "loudspeaker names the limit: %s" % [lines])
	_speed(70.0)
	_run(1.0)
	_check(not heat.warning_active and ended == [true] and heat.level == PoliceHeat.NONE and heat.heat == 0.0, "complied: warning %s ended %s level %d" % [heat.warning_active, ended, heat.level])
	_speed(100.0)
	_run(2.5)
	_check(warnings == 1 and heat.level == PoliceHeat.ONE_CAR, "second offence inside 2 min: warnings %d level %d (no second warning, straight to heat)" % [warnings, heat.level])
	# After the 2 minutes a warning again, with no repeat of the loudspeaker line.
	_fresh()
	_setup(100.0)
	_run(1.6)
	var n := lines.size()
	_speed(70.0)
	_run(1.0)
	_run(PoliceRules.WARN_COOLDOWN + 1.0)
	_speed(100.0)
	_run(1.6)
	_check(warnings == 2 and heat.warning_active, "after the cooldown a second warning: %d" % warnings)
	_check(lines.size() == n, "loudspeaker line repeated: %s" % [lines])
	# Highway wording and line.
	_fresh()
	heat.area_override = "highway"
	_setup(120.0)
	_run(3.0)
	_check(warnings == 0 and heat.level == PoliceHeat.NONE, "120 km/h on the highway is under the 125 line: warnings %d" % warnings)
	_speed(135.0)
	_run(2.0)
	_check(heat.warning_active and lines.has(PoliceRules.WARN_LINES["highway"]), "135 km/h on the highway: %s" % [lines])
	# Crackdown night: 75 km/h in the city is over the line of 70.
	_fresh()
	var mood := WorldMood.new()
	mood.crackdown_until = 500.0
	heat.world_mood = mood
	_setup(75.0)
	_run(2.0)
	_check(heat.warning_active, "75 km/h on a crackdown night should warn")
	mood.crackdown_until = -1.0
	_fresh()
	_setup(75.0)
	_run(3.0)
	_check(warnings == 0, "75 km/h on a normal night warned")
	mood.free()
	# Unseen is never an offence: the cop faces away and the car is out of the mirrors.
	_fresh()
	_setup(150.0)
	cop.rotation = Vector3.ZERO
	_run(10.0)
	_check(not heat.seen and warnings == 0 and heat.level == PoliceHeat.NONE, "unseen at 150 km/h: seen %s warnings %d level %d" % [heat.seen, warnings, heat.level])
	# Mirrors: a driving cop, 30 m behind it, 110 km/h faster than it. Parked: no mirrors.
	_fresh()
	_setup(110.0, 2.0, true, 30.0)
	cop.rotation = Vector3.ZERO
	_run(2.0)
	_check(heat.seen and heat.warning_active, "driving cop sees a faster car in its mirrors")
	_fresh()
	_setup(110.0, 2.0, true, 30.0)
	cop.rotation = Vector3.ZERO
	cop.set_meta(&"parked", true)
	_run(2.0)
	_check(not heat.seen and not heat.warning_active, "a parked cop has no mirrors")
	# Radar car: judges a dark car at 120 m in its cone, a patrol cannot.
	_fresh()
	_setup(110.0, 2.0, false, 120.0)
	_run(2.0)
	_check(not heat.seen and warnings == 0, "patrol sees a dark car at 120 m")
	cop.set_meta(&"radar", true)
	_run(2.0)
	_check(heat.seen and heat.warning_active, "radar car should judge a dark car at 120 m")
	# Wrong side: 2 s in the oncoming lanes warns; back in the lane clears.
	_fresh()
	_setup(60.0, -2.0, true, 60.0)
	_run(1.0)
	_check(not heat.warning_active, "1 s in the oncoming lanes warned")
	_run(1.5)
	_check(heat.warning_active and heat.warning_kind == PoliceRules.Offence.WRONG_SIDE, "2.5 s in the oncoming lanes: warning %s" % heat.warning_active)
	player.global_position = Vector3(2.0, 0, 0)
	_run(0.5)
	_check(not heat.warning_active and ended == [true] and heat.level == PoliceHeat.NONE, "back in the lane cleared it")
	# Racing: heat 2 at once, no warning.
	_fresh()
	_setup(60.0)
	heat.racing = true
	_run(0.5)
	_check(heat.level == PoliceHeat.TWO_CARS and warnings == 0, "racing seen: level %d warnings %d" % [heat.level, warnings])
	# Contacts: a touch under 15 km/h is a warning, a ram is heat 4.
	_fresh()
	_setup(10.0, 2.0, true, 8.0)
	_run(0.3)
	heat.on_contact(cop, 10.0)
	_check(heat.warning_active and heat.level == PoliceHeat.NONE and heat.warning_kind == PoliceRules.Offence.TOUCH_COP, "touching a cop at 10 km/h: warning %s level %d" % [heat.warning_active, heat.level])
	_fresh()
	_setup(10.0, 2.0, true, 8.0)
	_run(0.3)
	heat.on_contact(cop, 20.0)
	_check(heat.level == PoliceHeat.SPIKES and warnings == 0, "ramming a cop at 20 km/h: level %d" % heat.level)
	# Bump with a non-cop, non-traffic thing: nothing.
	_fresh()
	_setup(10.0, 2.0, true, 8.0)
	_run(0.3)
	heat.on_contact(Node3D.new(), 60.0)
	_check(heat.level == PoliceHeat.NONE and not heat.warning_active, "a wall hit counted as an offence")
	# Flagrant: 130 km/h in the city (60+ over posted): warning, heat 1, and
	# +1 once held 5 s.
	_fresh()
	_setup(130.0)
	_run(1.6)
	_check(heat.warning_active, "flagrant warns")
	_run(PoliceRules.WARN_SECS + 0.2)
	_check(heat.level == PoliceHeat.TWO_CARS, "flagrant ignored and held 5 s: level %d, expected 2" % heat.level)
	_fresh()
	_setup(130.0)
	_run(1.6)
	_speed(70.0)
	_run(1.0)
	_check(heat.level == PoliceHeat.NONE and ended == [true], "flagrant, slowed inside 5 s: level %d ended %s" % [heat.level, ended])
	# Dark and slow, seen up close: not an offence (lights off never is).
	_fresh()
	_setup(40.0, 2.0, false, 10.0)
	_run(10.0)
	_check(heat.level == PoliceHeat.NONE and warnings == 0, "lights off, 40 km/h: level %d warnings %d" % [heat.level, warnings])
